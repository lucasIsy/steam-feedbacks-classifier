CREATE OR REPLACE PROCEDURE `__DATASET__.1_PRC_regex_pre_inference`(
    IN p_batch_id STRING, -- Novo Watermark
    IN p_gcs_uri STRING,
    OUT status_continuidade STRING,
    OUT motivo STRING
)

BEGIN
    DECLARE v_novos_registros INT64;
    DECLARE v_linhas_temporaria_1 INT64;
    DECLARE v_descartes_copypasta INT64;
    DECLARE v_descartes_sinais INT64;
    DECLARE v_system_instruction STRING;
    DECLARE v_prompt_version STRING;

    DELETE FROM `__DATASET__.bronze_reviews` WHERE batch_id = p_batch_id;

    -- Carrega o arquivo batch da nova extração que chegou ao GCS.
    BEGIN
        EXECUTE IMMEDIATE FORMAT("""
            LOAD DATA INTO `__DATASET__.bronze_reviews`
            FROM FILES (format = 'PARQUET', uris = ['%s'])
        """, p_gcs_uri);

        SET v_novos_registros = (
            SELECT COUNT(1)
            FROM `__DATASET__.bronze_reviews`
            WHERE batch_id = p_batch_id
        );

    -- Se a tabela não foi encontrada, define como 0.
    -- Caso seja outro erro, lança a exceção.
    EXCEPTION WHEN ERROR THEN
        IF REGEXP_CONTAINS(@@error.message, r'(?i)not found.*uri') THEN
            SET v_novos_registros = 0;
        ELSE
            RAISE;
        END IF;
    END;

    -- Se não houverem novos registros, encerra o pipeline.
    IF v_novos_registros = 0 THEN
        CALL `__DATASET__.PRC_logs_control_table`(p_batch_id, 1, 0);
        SET status_continuidade = 'ENCERRAR';
        SET motivo = 'Etapa 1 - Sem reviews para processar';
        RETURN;
    ELSE
        CREATE OR REPLACE TABLE `__DATASET__.temporaria_1` AS
            WITH regex_stage AS (
                SELECT
                    b.batch_id,
                    b.ingested_at,
                    b.hash_id,
                    b.recommendationid,
                    DATE(TIMESTAMP_SECONDS(b.timestamp_created)) AS date_created,
                    DATE(TIMESTAMP_SECONDS(b.timestamp_updated)) AS date_updated,
                    DATE(TIMESTAMP_SECONDS(b.last_played)) AS date_last_played,
                    b.playtime_forever,
                    b.playtime_last_two_weeks,
                    b.playtime_at_review,
                    b.language,
                    b.characters,
                    b.spaces,
                    TRIM(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(b.review, r"\[[^\]]*\]|[^\p{Latin}0-9\s.,!?;:()'\x22%¿¡-]", ''),
                        r'\s+', ' '
                    )
                    ) AS review_after_regex
                FROM `__DATASET__.bronze_reviews` AS b
                WHERE b.batch_id = p_batch_id
                    AND b.spaces > 3
                    AND (b.characters - b.spaces) > 50
                    AND NOT EXISTS (SELECT 1 FROM `__DATASET__.Silver_Reviews` AS s WHERE s.hash_id = b.hash_id)
                    AND NOT EXISTS (SELECT 1 FROM `__DATASET__.DLQ_reviews` AS d WHERE d.hash_id = b.hash_id)
            ),
            medidas AS (
                SELECT
                    *,
                    LENGTH(REGEXP_REPLACE(review_after_regex, r'[^\p{Latin}]', '')) AS letras,
                    ARRAY_LENGTH(SPLIT(review_after_regex, ' ')) AS palavras
                FROM regex_stage
            )

        SELECT
        * EXCEPT (letras, palavras)
        FROM medidas
        WHERE
        letras >= 30
        AND SAFE_DIVIDE(letras, LENGTH(review_after_regex)) >= 0.6
        AND palavras >= 5;

        -- Armazena a quantidade de linhas da temporaria_1 pos regex
        SET v_linhas_temporaria_1 = (SELECT COUNT(1) FROM `__DATASET__.temporaria_1`);

        -- Verifica se existem dados sobreviventes, do contrário encerra o pipeline.
        IF v_linhas_temporaria_1 = 0 THEN
            CALL `__DATASET__.PRC_logs_control_table`(p_batch_id, 2, 0);
            SET status_continuidade = 'ENCERRAR';
            SET motivo = 'Etapa 1 - Nenhuma review sobreviveu ao regex';
            RETURN;
        ELSE
            CALL `__DATASET__.PRC_barreira_copypasta`(p_batch_id, v_descartes_copypasta);

            DELETE FROM `__DATASET__.temporaria_1`
            WHERE `__DATASET__.motivo_sinais`(review_after_regex) IS NOT NULL;
            SET v_descartes_sinais = @@row_count;

            CALL `__DATASET__.PRC_logs_control_table`(p_batch_id, 15, v_descartes_copypasta + v_descartes_sinais);

            SET v_linhas_temporaria_1 = (SELECT COUNT(1) FROM `__DATASET__.temporaria_1`);

            IF v_linhas_temporaria_1 = 0 THEN
                CALL `__DATASET__.PRC_logs_control_table`(p_batch_id, 16, 0);
                SET status_continuidade = 'ENCERRAR';
                SET motivo = 'Etapa 1 - Nenhuma review sobreviveu às barreiras';
                RETURN;
            END IF;

            SET (v_system_instruction, v_prompt_version) = (
                SELECT AS STRUCT system_instruction, prompt_version
                FROM `__DATASET__.prompts_table`
                WHERE step_prompt_id = 'ai_boolean_filter'
                AND prompt_status = 'PRODUCTION'
                QUALIFY ROW_NUMBER() OVER (ORDER BY created_at DESC) = 1
            );

            IF v_system_instruction IS NULL THEN
                RAISE USING MESSAGE = 'Prompt ai_boolean_filter PRODUCTION não encontrado';
            END IF;

            -- Operação exclusiva do BigQuery
            -- Seleciona os dados pós regex, adiciona o prompt e reescreve a tabela
            CREATE OR REPLACE TABLE `__DATASET__.temporaria_1` AS
                SELECT
                *,
                v_prompt_version AS prompt_version,
                STRUCT(
                    STRUCT(
                    [STRUCT(v_system_instruction AS text)] AS parts
                    ) AS systemInstruction,
                    [STRUCT(
                    'user' AS role,
                    [STRUCT(
                        LEFT(review_after_regex, 2000) AS text
                    )] AS parts
                    )] AS contents,
                    STRUCT(
                    0 AS temperature,
                    100 AS maxOutputTokens,
                    'application/json' AS responseMimeType,
                    JSON '{"type": "OBJECT", "properties": {"CoT": {"type": "STRING"}, "Relevant": {"type": "STRING", "enum": ["0", "1"]}}, "required": ["CoT", "Relevant"]}' AS responseSchema
                    ) AS generationConfig
                ) AS request
                FROM `__DATASET__.temporaria_1`;
            CALL `__DATASET__.PRC_logs_control_table`(p_batch_id, 3, v_linhas_temporaria_1);
            SET status_continuidade = 'CONTINUAR';
            SET motivo = 'Etapa 1 - Existem dados que passaram pelo CORTE e REGEX';
        END IF;
    END IF;
END;