CREATE OR REPLACE PROCEDURE `__DATASET__.4_PRC_criacao_embeddings`()
BEGIN
    DECLARE max_date_processed DATE;

    SET max_date_processed = (
        SELECT MAX(max_processed_timestamp)
        FROM `__DATASET__.logs_tabela_controle_geral`
        WHERE pipeline_step = 'unnest_to_embedding'
    );

    CREATE OR REPLACE TABLE `__DATASET__.temporaria_3`
        WITH reviews_splited AS (
            SELECT
                hash_id,
                recommendationid,
                FARM_FINGERPRINT(CONCAT(CAST(hash_id AS STRING), '|', CAST(array_position AS STRING))) AS ai_split_id,
                date_created,
                JSON_VALUE(item_json.f) AS content,
                JSON_VALUE(item_json.c) AS category,
                JSON_VALUE(item_json.t) AS topic,
                SAFE_CAST(JSON_VALUE(item_json.s) AS INT64) AS sentiment,
                ml_generate_embedding_result AS embedding
            FROM `__DATASET__.Silver_Reviews`,
            UNNEST(AIstruct) AS item_json WITH OFFSET AS array_position
            WHERE ingested_at > max_date_processed
        )

        SELECT 
            *, 
            ml_generate_embedding_result AS embedding 
            FROM ML.GENERATE_EMBEDDING(
                MODEL `__DATASET__.model_name`,
                (
                    SELECT
                        hash_id,
                        recommendation_id,
                        ai_split_id,
                        date_created,
                        content, 
                        category,
                        topic,
                        sentiment
                    FROM reviews_splited
                ),
                STRUCT('SEMANTIC_SIMILARITY' AS task_type, 256 AS OUTPUT_DIMENSIONALITY)
        );

    -- ========================================================================
    -- TABELA DE CONTROLE - Fim da execução do script
    -- ========================================================================
    CALL `__DATASET__.PRC_logs_control_table`(7);

END;

