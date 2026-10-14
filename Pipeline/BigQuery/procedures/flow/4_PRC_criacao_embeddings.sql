CREATE OR REPLACE PROCEDURE `__DATASET__.4_PRC_criacao_embeddings`(IN p_batch_id STRING)
BEGIN
    DECLARE v_embeddings INT64;
    DECLARE v_data_ingestao DATE;

    CREATE OR REPLACE TEMP TABLE embeddings_brutos AS
        WITH reviews_splited AS (
            SELECT
                batch_id,
                ingested_at,
                hash_id,
                recommendationid,
                FARM_FINGERPRINT(CONCAT(hash_id, '|', CAST(array_position AS STRING))) AS ai_split_id,
                date_created,
                date_updated,
                playtime_forever,
                playtime_at_review,
                language,
                JSON_VALUE(item_json.f) AS content,
                JSON_VALUE(item_json.c) AS category,
                JSON_VALUE(item_json.t) AS topic,
                SAFE_CAST(JSON_VALUE(item_json.s) AS INT64) AS sentiment
            FROM `__DATASET__.Silver_Reviews`,
            UNNEST(AI_struct_array) AS item_json WITH OFFSET AS array_position
            WHERE batch_id = p_batch_id
        )

        SELECT
            *
            FROM ML.GENERATE_EMBEDDING(
                MODEL `__DATASET__.gemini_embedding_model`,
                (
                    SELECT
                        batch_id,
                        ingested_at,
                        hash_id,
                        recommendationid,
                        ai_split_id,
                        date_created,
                        date_updated,
                        playtime_forever,
                        playtime_at_review,
                        language,
                        content,
                        category,
                        topic,
                        sentiment
                    FROM reviews_splited
                    WHERE content IS NOT NULL AND TRIM(content) != ''
                ),
                STRUCT('SEMANTIC_SIMILARITY' AS task_type, 256 AS output_dimensionality)
        );

    CREATE OR REPLACE TABLE `__DATASET__.temporaria_3` AS
        SELECT
            * EXCEPT (ml_generate_embedding_result, ml_generate_embedding_status, ml_generate_embedding_statistics),
            ml_generate_embedding_result AS embedding
        FROM embeddings_brutos
        WHERE ml_generate_embedding_status = '';

    SET v_data_ingestao = (SELECT DATE(MIN(ingested_at)) FROM embeddings_brutos);

    MERGE INTO `__DATASET__.DLQ_reviews` AS DLQ
    USING(
        SELECT
            batch_id,
            ingested_at,
            hash_id,
            content AS payload,
            CURRENT_TIMESTAMP() AS updated_at,
            "Embedding" AS error_checkpoint,
            ml_generate_embedding_status AS AI_finishReason,
            0 AS retry_count
        FROM embeddings_brutos
        WHERE ml_generate_embedding_status != ''
    ) AS source
    ON DATE(DLQ.ingested_at) = v_data_ingestao
    AND DLQ.batch_id = source.batch_id
    AND DLQ.hash_id = source.hash_id
    AND DLQ.error_checkpoint = source.error_checkpoint
    AND DLQ.payload = source.payload
    WHEN NOT MATCHED THEN
        INSERT (
            batch_id,
            ingested_at,
            hash_id,
            payload,
            updated_at,
            error_checkpoint,
            AI_finishReason,
            retry_count
        )
        VALUES (
            source.batch_id,
            source.ingested_at,
            source.hash_id,
            source.payload,
            source.updated_at,
            source.error_checkpoint,
            source.AI_finishReason,
            source.retry_count
        );

    -- ========================================================================
    -- TABELA DE CONTROLE - Fim da execução do script
    -- ========================================================================
    SET v_embeddings = (SELECT COUNT(1) FROM `__DATASET__.temporaria_3`);
    CALL `__DATASET__.PRC_logs_control_table`(p_batch_id, 7, v_embeddings);

END;
