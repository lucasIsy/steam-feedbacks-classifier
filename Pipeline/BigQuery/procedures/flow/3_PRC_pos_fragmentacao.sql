CREATE OR REPLACE PROCEDURE `__DATASET__.3_PRC_pos_fragmentacao`()
BEGIN
    CREATE OR REPLACE TEMP TABLE Struct AS 
        WITH parsed_data AS (
            SELECT
                batch_id,
                ingested_at,
                hash_id,
                recommendationid,
                date_created,
                date_updated,
                timestamp_updated,
                playtime_forever,
                playtime_last_two_weeks,
                playtime_at_review,
                date_last_played,
                language,
                review_after_regex,
                PARSE_JSON(response) AS json_response
            FROM `__DATASET__.temporaria_2`
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
            ARRAY(
                SELECT PARSE_JSON(LAX_STRING(part.text))
                FROM UNNEST(JSON_QUERY_ARRAY(json_response.candidates[0].content.parts)) AS part
            ) AS AI_struct_array,
            LAX_STRING(json_response.candidates[0].finishReason) AS finishReason,
            LAX_INT64(json_response.usageMetadata.promptTokenCount) AS prompt_token_count,
            LAX_INT64(json_response.usageMetadata.totalTokenCount) AS total_token_count,
            LAX_STRING(json_response.modelVersion) AS model_version
        FROM parsed_data;

    -- ========================================================================
    -- VARIÁVEIS DE CONTROLE
    -- ========================================================================
    SET (data_inicio, data_fim) = (
        SELECT AS STRUCT MIN(date_created), MAX(date_created) 
        FROM `__DATASET__.Struct`
    );

    MERGE INTO `__DATASET__.DLQ` as DLQ
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
        from Struct
        where AI_struct_array IS NULL
    ) AS source
    ON DLQ.ingested_at BETWEEN data_inicio AND data_fim
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
            source.review_after_regex,
            source.updated_at,
            source.error_checkpoint,
            source.AI_finishReason,
            source.retry_count
        );
        
    MERGE INTO `__DATASET__.Silver_Reviews` as Silver
    USING(
        select * from Struct
        where AI_struct_array IS NOT NULL
    ) AS source

    ON Silver.data_referencia BETWEEN data_inicio AND data_fim
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
            AIstruct_array
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
            source.AIstruct_array   
        );
        
    -- ========================================================================
    -- TABELA DE CONTROLE - Fim da execução do script
    -- ========================================================================
    CALL `__DATASET__.PRC_logs_control_table`(6);
END;