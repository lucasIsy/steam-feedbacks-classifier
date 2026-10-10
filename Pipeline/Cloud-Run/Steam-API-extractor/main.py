import os, time, io
from datetime import datetime, timezone
from typing import Dict, Any, List
import polars as pl
import polars_hash as plh
import httpx
from google.cloud import bigquery
from google.cloud import storage
from google.api_core.exceptions import GoogleAPIError

# ==============================================================================
# 1. CONFIGURAÇÕES DE AMBIENTE
# ==============================================================================
PROJECT_ID = os.getenv("GCP_PROJECT_ID")
BQ_DATASET = os.getenv("BQ_DATASET")
BQ_EXTRACTION_LOG_TABLE = os.getenv("BQ_EXTRACTION_LOG_TABLE")
GCS_BUCKET_NAME = os.getenv("GCS_BUCKET_NAME")
EXTRACTION_LOG_TABLE = f"{PROJECT_ID}.{BQ_DATASET}.{BQ_EXTRACTION_LOG_TABLE}"

APP_ID = int(os.getenv("STEAM_APP_ID"))
BATCH_ID = os.getenv("BATCH_ID")
INGESTED_AT = datetime.now(timezone.utc)

# ==============================================================================
# 2. Verifica a ultima execução (BIGQUERY)
# ==============================================================================
def get_last_extraction_date() -> int:
    """Retorna a data(UNIX) da última extração dentro da tabela de LOG."""
    print(f"[BIGQUERY] Buscando ultimo ponto de parada em: {EXTRACTION_LOG_TABLE}")
    bq_client = bigquery.Client(project=PROJECT_ID)
    
    query = f"""
        SELECT 
        COALESCE(MAX(max_review_unix_date), 0) as last_extraction
        FROM `{EXTRACTION_LOG_TABLE}`
    """
    try:
        query_job = bq_client.query(query)
        result = query_job.result()
        for row in result:
            return int(row.last_extraction)
    except GoogleAPIError as e:
        if "Not found:" in str(e):
            print("[BIGQUERY] Tabela de log nao encontrada. Assumindo primeira execucao (Timestamp: 0).")
            return 0
        print(f"[ERRO CRITICO BQ] Falha ao ler metadados: {e}")
        raise e

def insert_new_date_extraction_log(max_reviews_date: int | None = None, total_reviews_extracted: int = 0):
    """Atualiza a data da última extração inserindo uma nova linha na tabela de controle do BQ"""
    # print(f"[BIGQUERY] Atualizando log de execucao com o timestamp: {max_reviews_date}")
    
    bq_client = bigquery.Client(project=PROJECT_ID)
    
    # Captura o momento atual uma única vez para evitar micro-diferenças de milissegundos
    current_date = datetime.now(timezone.utc)
    
    # Define o valor do unix_date: usa o max_reviews_date se ele existir, caso contrário calcula o timestamp atual
    unix_date = max_reviews_date if max_reviews_date is not None else int(current_date.timestamp())

    linhas_para_inserir = [{
        "extraction_date": current_date.isoformat(timespec='seconds'),
        "max_review_unix_date": unix_date,
        "total_reviews_extracted": total_reviews_extracted
    }]
    
    errors = bq_client.insert_rows_json(EXTRACTION_LOG_TABLE, linhas_para_inserir)
    if errors:
        raise RuntimeError(f"[ERRO BQ] Falha ao inserir linha de log: {errors}")
    print("[BIGQUERY] Log de controle gravado com sucesso.")

# ==============================================================================
# 3. EXTRACT (HTTPX + STEAM API)
# ==============================================================================
def get_steam_reviews(client: httpx.Client, languages: str, last_extraction: int) -> List[Dict[str, Any]]:
    """Extrai as reviews de um APPID/JOGO a partir de uma data e languages especificados"""
    base_url = f"https://store.steampowered.com/appreviews/{APP_ID}"
    params = {
        "json": 1,
        "filter": "updated",
        "language": languages,
        "review_type": "all",
        "purchase_type": "all",
        "num_per_page": 100,
    }
    
    cursor = "*"
    steam_reviews: List[Dict[str, Any]] = []
    pag = 1
    
    print(f"[STEAM] Iniciando a extração das reviews: {languages.upper()}")
    
    while True:
        current_params = params.copy()
        current_params["cursor"] = cursor
        
        for tentativa in range(5):
            response = client.get(base_url, params=current_params, timeout=15.0)
            if response.status_code not in (429, 500, 502, 503, 504):
                break
            time.sleep(2 ** tentativa)
        response.raise_for_status()
        data = response.json()
        
        # Verificação 1 - API retornou os dados com sucesso?
        if data.get("success") != 1:
            print(f"[STEAM] Falha interna da API na pagina {pag} para {languages}. Pulando bloco.")
            break
        
        # Verificação 2 - API retornou os dados?
        reviews = data.get("reviews", [])
        if not reviews:
            break
            
        # Verificação 2 - Chegou nos dados da última extração? ENCERRA
        finalizado = False

        for r in reviews:
            ts_updated = int(r.get("timestamp_updated", 0))
            
            if ts_updated <= last_extraction:
                finalizado = True
                break
                
            author = r.get("author", {})
            
            # Formata os dados em dicionário para o Polars
            steam_reviews.append({
                "recommendationid": int(r.get("recommendationid", 0)),
                "timestamp_created": int(r.get("timestamp_created", 0)),
                "timestamp_updated": ts_updated,
                "app_release_date": int(r.get("app_release_date", 0)), 
                "language": languages,
                "review": r.get("review", "").strip(),
                "author": {
                    "playtime_forever": int(author.get("playtime_forever", 0)),
                    "playtime_last_two_weeks": int(author.get("playtime_last_two_weeks", 0)),
                    "playtime_at_review": int(author.get("playtime_at_review", 0)),
                    "last_played": int(author.get("last_played", 0))
                }
            })
            
        print(f"  Pagina {pag:02d} | +{len(reviews)} avaliacoes analisadas | Acumulado {languages}: {len(steam_reviews)}")
        
        if finalizado:
            print(f"  [FIM DA EXTRACAO] Dados antigos encontrados no languages {languages}. Parando.")
            break
            
        next_cursor = data.get("cursor")
        if not next_cursor or next_cursor == cursor:
            break
        cursor = next_cursor
        pag += 1
        time.sleep(1.2)
        
    return steam_reviews

# ==============================================================================
# 4. Pre-Transformation -> Parquet
# ==============================================================================
def steam_reviews_to_polars(reviews_list: list) -> tuple[pl.DataFrame, int, int]:
    schema = {
        "recommendationid": pl.Int64,
        "timestamp_created": pl.Int64,
        "timestamp_updated": pl.Int64,
        "app_release_date": pl.Int64,
        "language": pl.Utf8,
        "review": pl.Utf8,
        "author": pl.Struct([
            pl.Field("playtime_forever", pl.Int64),
            pl.Field("playtime_last_two_weeks", pl.Int64),
            pl.Field("playtime_at_review", pl.Int64),
            pl.Field("last_played", pl.Int64)
        ])
    }

    # 1. Cria o DataFrame base para pegar a maior data e total de reviews extraidas primeiro.
    df_base = pl.DataFrame(reviews_list, schema_overrides=schema)

    # 2. Armazena o total de reviews extraidas
    total_reviews_extracted = df_base.height

    # 3. Extrai a maior data no lote das reviews
    max_date = df_base["timestamp_updated"].max()

    # 4. Transforma em LazyFrame e aplica a lógica de processamento e filtragem
    df_steam = (
        df_base
        .lazy()

        # Criando a coluna de espaços antes da Pré-Filtragem para evitar o NameError
        .with_columns([
            (pl.col("review").str.len_chars() - pl.col("review").str.replace_all(" ", "").str.len_chars()).alias("spaces")
        ])

        # Pré-Filtragem
        .filter(pl.col("spaces") > 0)

        # Cria hash da review usando o plugin polars_hash
        .with_columns([
            plh.concat_str("recommendationid", "timestamp_updated")
            .chash.sha2_256()
            .alias("hash_id")
        ])
        
        # Demais transformações de colunas
        .with_columns([
            pl.col("review").str.len_chars().cast(pl.Int64).alias("characters"),
            pl.col("spaces").cast(pl.Int64).alias("spaces"),
            pl.lit(BATCH_ID, dtype=pl.Utf8).alias("batch_id"),
            pl.lit(INGESTED_AT).alias("ingested_at"),
            pl.col("author").struct.field("playtime_forever").alias("playtime_forever"),
            pl.col("author").struct.field("playtime_last_two_weeks").alias("playtime_last_two_weeks"),
            pl.col("author").struct.field("playtime_at_review").alias("playtime_at_review"),
            pl.col("author").struct.field("last_played").alias("last_played")
        ])

        .select([
            "batch_id",
            "ingested_at",
            "hash_id",
            "recommendationid",
            "timestamp_created",
            "timestamp_updated",
            "playtime_forever",
            "playtime_last_two_weeks",
            "playtime_at_review",
            "last_played",
            "app_release_date",
            "language",
            "characters",
            "spaces",
            "review"
        ])
        .collect()
    )
    
    return df_steam, max_date, total_reviews_extracted

# ==============================================================================
# 5. LOAD (GCS)
# ==============================================================================
def send_parquet_to_gcs(df_clean: pl.DataFrame, maior_timestamp: int):
    """Salva o DataFrame transformado em formato Parquet direto no Cloud Storage."""
    agora = datetime.now(timezone.utc)
    gcs_path = f"reviews/ano={agora.year}/mes={agora.month:02d}/reviews_{APP_ID}_{maior_timestamp}_{BATCH_ID}.parquet"
    
    print(f"[GCS] Fazendo upload do Parquet para: gs://{GCS_BUCKET_NAME}/{gcs_path}")
    gcs_client = storage.Client(project=PROJECT_ID)
    bucket = gcs_client.bucket(GCS_BUCKET_NAME)
    blob = bucket.blob(gcs_path)
    
    # Gravação em memória via IO stream
    buffer = io.BytesIO()
    df_clean.write_parquet(buffer)
    buffer.seek(0)
    
    blob.upload_from_file(buffer, content_type="application/octet-stream")
    print("[GCS] Arquivo Parquet enviado com sucesso.")

# ==============================================================================
# 6. MAIN EXECUTION
# ==============================================================================
def executing_pipeline():
    languages_permitidos = ["brazilian", "english", "spanish"]
    
    last_extraction_date = get_last_extraction_date()
    all_reviews: List[Dict[str, Any]] = []
    
    with httpx.Client(headers={"User-Agent": "SteamDataPipeline/2.0"}) as client:
        for languages in languages_permitidos:
            steam_reviews = get_steam_reviews(client, languages, last_extraction_date)
            all_reviews.extend(steam_reviews)
            
    if not all_reviews:
        print("\n[PIPELINE] Sem novas avaliacoes postadas na Steam desde a ultima checagem. Encerrando.")
        # Insere a data de "hoje" e 0 reviews extraidas
        insert_new_date_extraction_log()
        return

    print("[POLARS] Iniciando transformações.")
    df_processed, max_date, total_reviews_extracted = steam_reviews_to_polars(all_reviews)

    # Verificação - Se não existir dados sobreviventes,
    # a função encerra e nem envia o arquivo pro GCS
    if df_processed.is_empty():
        print("[PIPELINE] Nenhuma review sobreviveu à filtragem.")
        insert_new_date_extraction_log(max_date, total_reviews_extracted)
        return

    send_parquet_to_gcs(df_processed, max_date)

    # Envia a data da maior review encontrada e 
    # a quantidade antes da próxima verificação
    insert_new_date_extraction_log(max_date, total_reviews_extracted)
    
    print(f"\n[SUCESSO] Pipeline finalizado. {total_reviews_extracted} novas reviews processadas.")

if __name__ == "__main__":
    executing_pipeline()