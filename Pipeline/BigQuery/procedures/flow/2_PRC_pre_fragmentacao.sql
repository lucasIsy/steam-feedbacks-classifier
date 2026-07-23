CREATE OR REPLACE PROCEDURE `__DATASET__.2_PRC_pre_fragmentacao`(OUT status_continuidade STRING, OUT motivo STRING)
BEGIN
    -- ========================================================================
    -- VARIÁVEIS DE CONTROLE
    -- ========================================================================
    DECLARE v_count_relevantes INT64 DEFAULT 0;
    DECLARE v_system_instruction STRING;
    DECLARE data_inicio DATE; 
    DECLARE data_fim DATE;    

    -- ========================================================================
    -- DESCOMPACTAÇÃO DO RETORNO DA IA
    -- ========================================================================
    -- Só existe durante a execução dessa procedure
    CREATE OR REPLACE TEMP TABLE direcionamento_dados AS
        WITH dados_preparados AS (
            SELECT
                batch_id,
                ingested_at,
                hash_id,
                recommendation_id,
                date_created,
                date_updated,
                playtime_forever,
                playtime_last_two_weeks,
                playtime_at_review,
                date_last_played,
                language,
                review_after_regex,
                SAFE.PARSE_JSON(response) AS json_response
            FROM `__DATASET__.temporaria_1`
        )

        SELECT
            hash_id,
            batch_id,
            recommendationid,
            date_created,
            date_updated,
            playtime_forever,
            playtime_last_two_weeks,
            playtime_at_review,
            date_last_played,
            language,
            review_after_regex,
            LAX_INT64(SAFE.PARSE_JSON(LAX_STRING(json_response.candidates[0].content.parts[0].text)).Relevant) AS relevant,
            LAX_STRING(SAFE.PARSE_JSON(LAX_STRING(json_response.candidates[0].content.parts[0].text)).CoT) AS cot,
            LAX_STRING(json_response.candidates[0].finishReason) AS finishReason,
            LAX_INT64(json_response.usageMetadata.promptTokenCount) AS prompt_token_count,
            LAX_INT64(json_response.usageMetadata.totalTokenCount) AS total_token_count,
            LAX_STRING(json_response.modelVersion) AS model_version
        FROM dados_preparados;
    
    SET (data_inicio, data_fim) = (
        SELECT AS STRUCT MIN(date_updated), MAX(date_updated) 
        FROM direcionamento_dados
    );

    -- ========================================================================
    -- FLUXO 0: DADOS IRRELEVANTES (Vão direto para a Silver)
    -- ========================================================================
    MERGE INTO `__DATASET__.Silver_Reviews` AS Silver
        USING(
            SELECT * FROM direcionamento_dados
            WHERE relevant = 0
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
                ARRAY<JSON>[] -- ATENÇÃO MÁXIMA NESTE PONTO
            );

    -- ========================================================================
    -- FLUXO NULL / -1: DEAD LETTER QUEUE (DLQ)
    -- ========================================================================
    MERGE INTO `__DATASET__.DLQ_reviews` AS DLQ
    USING(
        SELECT
            batch_id, 
            ingested_at,
            hash_id, 
            review_after_regex AS payload,
            CURRENT_TIMESTAMP() AS updated_at,
            "Classificação Relevância" AS error_checkpoint,
            finishReason AS AI_finishReason,
            0 AS retry_count
        FROM direcionamento_dados
        WHERE relevant IS NULL
    ) AS source
    ON DLQ.data_referencia BETWEEN data_inicio AND data_fim
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

    -- ========================================================================
    -- FLUXO 1: INFERÊNCIA BATCH (Preparação para o Python)
    -- ========================================================================
    SET v_count_relevantes = (
        SELECT COUNT(1) 
        FROM direcionamento_dados 
        WHERE relevant = 1
    );

    IF v_count_relevantes = 0 THEN
        CALL `__DATASET__.PRC_logs_control_table`(4);
        SET status_continuidade = 'ENCERRAR';
        SET motivo = 'Direcionamento - sem dados relevantes para fragmentação';
        RETURN;   
    ELSE
        SET v_system_instruction = (
            SELECT system_instruction
            FROM `__DATASET__.prompts_table`
            WHERE step_prompt_id = 'split_reviews' 
              AND prompt_status = 'PRODUCTION'
        );

        CREATE OR REPLACE TABLE temporaria_2 AS
            SELECT 
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
                STRUCT(
                    [STRUCT(
                        'user' AS role,
                        [STRUCT(
                            CONCAT(v_system_instruction, '\n', review_after_regex) AS text
                        )] AS parts
                    )] AS contents,
                    STRUCT(
                        0.5 AS temperature, 
                        100 AS maxOutputTokens, 
                        'application/json' AS responseMimeType
                    ) AS generationConfig
                ) AS request
            FROM direcionamento_dados
            WHERE relevant = 1;
    END IF;
    CALL `__DATASET__.PRC_logs_control_table`(5);
END;