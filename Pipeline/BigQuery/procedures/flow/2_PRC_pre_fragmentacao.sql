CREATE OR REPLACE PROCEDURE `__DATASET__.2_PRC_pre_fragmentacao`(IN p_batch_id STRING, OUT status_continuidade STRING, OUT motivo STRING)
BEGIN
    -- ========================================================================
    -- VARIÁVEIS DE CONTROLE
    -- ========================================================================
    DECLARE v_count_relevantes INT64 DEFAULT 0;
    DECLARE v_system_instruction STRING;
    DECLARE v_data_ingestao DATE;

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
                recommendationid,
                date_created,
                date_updated,
                playtime_forever,
                playtime_last_two_weeks,
                playtime_at_review,
                date_last_played,
                language,
                review_after_regex,
                prompt_version,
                SAFE.PARSE_JSON(response) AS json_response
            FROM `__DATASET__.temporaria_1`
            WHERE batch_id = p_batch_id
        )

        SELECT
            hash_id,
            batch_id,
            ingested_at,
            recommendationid,
            date_created,
            date_updated,
            playtime_forever,
            playtime_last_two_weeks,
            playtime_at_review,
            date_last_played,
            language,
            review_after_regex,
            prompt_version,
            LAX_INT64(SAFE.PARSE_JSON(LAX_STRING(json_response.candidates[0].content.parts[0].text)).Relevant) AS relevant,
            LAX_STRING(SAFE.PARSE_JSON(LAX_STRING(json_response.candidates[0].content.parts[0].text)).CoT) AS cot,
            LAX_STRING(json_response.candidates[0].finishReason) AS finishReason,
            LAX_INT64(json_response.usageMetadata.promptTokenCount) AS prompt_token_count,
            LAX_INT64(json_response.usageMetadata.totalTokenCount) AS total_token_count,
            LAX_STRING(json_response.modelVersion) AS model_version
        FROM dados_preparados;

    SET v_data_ingestao = (SELECT DATE(MIN(ingested_at)) FROM direcionamento_dados);

    -- ========================================================================
    -- FLUXO 0: DADOS IRRELEVANTES (Vão direto para a Silver)
    -- ========================================================================
    MERGE INTO `__DATASET__.Silver_Reviews` AS Silver
        USING(
            SELECT * FROM direcionamento_dados
            WHERE relevant IS NOT NULL AND relevant != 1
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
                source.relevant,
                source.cot,
                source.prompt_version,
                source.model_version,
                source.total_token_count,
                ARRAY<JSON>[] -- ATENÇÃO MÁXIMA NESTE PONTO
            );

    -- ========================================================================
    -- FLUXO NULL: DEAD LETTER QUEUE (DLQ)
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

    -- ========================================================================
    -- FLUXO 1: INFERÊNCIA BATCH (Preparação para a fragmentação)
    -- ========================================================================
    SET v_count_relevantes = (
        SELECT COUNT(1)
        FROM direcionamento_dados
        WHERE relevant = 1
    );

    IF v_count_relevantes = 0 THEN
        CALL `__DATASET__.PRC_logs_control_table`(p_batch_id, 4, 0);
        SET status_continuidade = 'ENCERRAR';
        SET motivo = 'Direcionamento - sem dados relevantes para fragmentação';
        RETURN;
    ELSE
        SET v_system_instruction = (
            SELECT system_instruction
            FROM `__DATASET__.prompts_table`
            WHERE step_prompt_id = 'ai_fragmentation'
              AND prompt_status = 'PRODUCTION'
            QUALIFY ROW_NUMBER() OVER (ORDER BY created_at DESC) = 1
        );

        IF v_system_instruction IS NULL THEN
            RAISE USING MESSAGE = 'Prompt ai_fragmentation PRODUCTION não encontrado';
        END IF;

        CREATE OR REPLACE TABLE `__DATASET__.temporaria_2` AS
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
                cot AS relevance_cot,
                prompt_version,
                model_version,
                total_token_count AS filter_total_tokens,
                STRUCT(
                    STRUCT(
                        [STRUCT(v_system_instruction AS text)] AS parts
                    ) AS systemInstruction,
                    [STRUCT(
                        'user' AS role,
                        [STRUCT(
                            review_after_regex AS text
                        )] AS parts
                    )] AS contents,
                    STRUCT(
                        0 AS temperature,
                        1024 AS maxOutputTokens,
                        'application/json' AS responseMimeType,
                        JSON '{"type": "ARRAY", "items": {"type": "OBJECT", "properties": {"f": {"type": "STRING"}, "c": {"type": "STRING", "enum": ["UX", "DEV"]}, "t": {"type": "STRING"}, "s": {"type": "STRING", "enum": ["-1", "0", "1"]}}, "required": ["f", "c", "t", "s"]}}' AS responseSchema
                    ) AS generationConfig
                ) AS request
            FROM direcionamento_dados
            WHERE relevant = 1;

        CALL `__DATASET__.PRC_logs_control_table`(p_batch_id, 5, v_count_relevantes);
        SET status_continuidade = 'CONTINUAR';
        SET motivo = 'Direcionamento - existem dados relevantes para fragmentação';
    END IF;
END;
