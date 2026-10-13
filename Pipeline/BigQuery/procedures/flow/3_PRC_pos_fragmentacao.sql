CREATE OR REPLACE PROCEDURE `__DATASET__.3_PRC_pos_fragmentacao`(IN p_batch_id STRING)
BEGIN
    DECLARE v_fragmentados INT64;
    DECLARE v_data_ingestao DATE;

    CREATE OR REPLACE TEMP TABLE fragmentos AS
        WITH parsed_data AS (
            SELECT
                batch_id,
                ingested_at,
                hash_id,
                recommendationid,
                date_created,
                date_updated,
                playtime_forever,
                playtime_last_two_weeks,
                playtime_at_review,
                date_last_played,
                language,
                review_after_regex,
                relevance_cot,
                prompt_version,
                model_version,
                filter_total_tokens,
                SAFE.PARSE_JSON(response) AS json_response
            FROM `__DATASET__.temporaria_2`
            WHERE batch_id = p_batch_id
        )
        SELECT
            batch_id,
            ingested_at,
            hash_id,
            recommendationid,
            date_created,
            date_updated,
            playtime_forever,
            playtime_last_two_weeks,
            playtime_at_review,
            date_last_played,
            language,
            review_after_regex,
            relevance_cot,
            prompt_version,
            model_version,
            filter_total_tokens,
            ARRAY(
                SELECT frag
                FROM UNNEST(
                    JSON_QUERY_ARRAY(
                        SAFE.PARSE_JSON(LAX_STRING(json_response.candidates[0].content.parts[0].text))
                    )
                ) AS frag
                WHERE frag IS NOT NULL
            ) AS AI_struct_array,
            LAX_STRING(json_response.candidates[0].finishReason) AS finishReason,
            LAX_INT64(json_response.usageMetadata.promptTokenCount) AS prompt_token_count,
            LAX_INT64(json_response.usageMetadata.totalTokenCount) AS total_token_count
        FROM parsed_data;

    CREATE OR REPLACE TEMP TABLE fragmentos_validados AS
        SELECT
            *,
            finishReason IS DISTINCT FROM 'STOP'
            OR ARRAY_LENGTH(AI_struct_array) = 0
            OR EXISTS (
                SELECT 1
                FROM UNNEST(AI_struct_array) AS frag
                WHERE JSON_VALUE(frag.f) IS NULL
                    OR JSON_VALUE(frag.t) IS NULL
                    OR IFNULL(JSON_VALUE(frag.c), '') NOT IN ('UX', 'DEV')
                    OR IFNULL(SAFE_CAST(JSON_VALUE(frag.s) AS INT64), 99) NOT IN (-1, 0, 1)
                    OR (JSON_VALUE(frag.c) = 'DEV' AND SAFE_CAST(JSON_VALUE(frag.s) AS INT64) != 0)
                    OR (JSON_VALUE(frag.c) = 'UX' AND SAFE_CAST(JSON_VALUE(frag.s) AS INT64) = 0)
            ) AS falhou
        FROM fragmentos;

    SET v_data_ingestao = (SELECT DATE(MIN(ingested_at)) FROM fragmentos_validados);

    MERGE INTO `__DATASET__.DLQ_reviews` as DLQ
    USING(
        select
            batch_id,
            ingested_at,
            hash_id,
            review_after_regex as payload,
            CURRENT_TIMESTAMP() as updated_at,
            "Split_Review" as error_checkpoint,
            finishReason as AI_finishReason,
            0 as retry_count
        from fragmentos_validados
        where falhou
    ) AS source
    ON DATE(DLQ.ingested_at) = v_data_ingestao
    AND DLQ.batch_id = source.batch_id
    AND DLQ.hash_id = source.hash_id
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

    MERGE INTO `__DATASET__.Silver_Reviews` as Silver
    USING(
        select * from fragmentos_validados
        where not falhou
    ) AS source

    ON DATE(Silver.ingested_at) = v_data_ingestao
    AND Silver.batch_id = source.batch_id
    AND Silver.hash_id = source.hash_id

    WHEN NOT MATCHED THEN
        INSERT (
            batch_id,
            ingested_at,
            hash_id,
            recommendationid,
            date_created,
            date_updated,
            playtime_forever,
            playtime_last_two_weeks,
            playtime_at_review,
            date_last_played,
            language,
            review_after_regex,
            relevance_label,
            relevance_cot,
            prompt_version,
            model_version,
            filter_total_tokens,
            split_total_tokens,
            AI_struct_array
        )
        VALUES (
            source.batch_id,
            source.ingested_at,
            source.hash_id,
            source.recommendationid,
            source.date_created,
            source.date_updated,
            source.playtime_forever,
            source.playtime_last_two_weeks,
            source.playtime_at_review,
            source.date_last_played,
            source.language,
            source.review_after_regex,
            1,
            source.relevance_cot,
            source.prompt_version,
            source.model_version,
            source.filter_total_tokens,
            source.total_token_count,
            source.AI_struct_array
        );

    -- ========================================================================
    -- TABELA DE CONTROLE - Fim da execução do script
    -- ========================================================================
    SET v_fragmentados = (SELECT COUNTIF(NOT falhou) FROM fragmentos_validados);
    CALL `__DATASET__.PRC_logs_control_table`(p_batch_id, 6, v_fragmentados);
END;
