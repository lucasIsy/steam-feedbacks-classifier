CREATE OR REPLACE PROCEDURE `__DATASET__.1_PRC_regex_pre_inference`(OUT status_continuidade STRING, OUT motivo STRING)
BEGIN
    DECLARE max_date_processed TIMESTAMP;
    DECLARE v_novos_registros INT64;
    DECLARE v_linhas_temporaria_1 INT64;
    DECLARE system_instruction TEXT;

    SET max_date_processed = (
        SELECT MAX(max_processed_timestamp)
        FROM `__DATASET__.logs_tabela_controle_geral`
        WHERE pipeline_step = 'raw_to_temporaria_1'
    );

    SET v_novos_registros = (
        SELECT COUNT(1)
        FROM `__DATASET__.raw_external_table`
        WHERE ingestedAt > COALESCE(max_date_processed, '2025-01-01')
    );

    IF v_novos_registros = 0 THEN
        CALL `__DATASET__.PRC_logs_control_table`(1);
        SET status_continuidade = 'ENCERRAR'
        SET motivo = 'Etapa 1 - Sem reviews para processar'
        RETURN;
    ELSE
        CREATE OR REPLACE TABLE temporaria_1 AS
            WITH regex_stage AS (
                SELECT
                    batch_id,
                    ingested_at,
                    hash_id,
                    recommendation_id,
                    CAST(TO_TIMESTAMP(timestamp_created) AS DATE) AS date_created,
                    CAST(TO_TIMESTAMP(timestamp_updated) AS DATE) AS date_updated,
                    CAST(TO_TIMESTAMP(last_played) AS DATE) AS date_last_played,
                    playtime_forever,
                    playtime_last_two_weeks,
                    playtime_at_review,
                    language,
                    characters,
                    spaces,
                    TRIM(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(review, r'\[[^\]]*\]|[^a-zA-Z0-9\s.,!?;:()''"áéíóúâêîôûàèìòùãõçñ¿¡%]', ''),
                        r'\s+', ' '
                    )
                    ) AS review_after_regex
                FROM `__DATASET__.raw_external_table`
                WHERE (characters - spaces) > 50
                    AND ingestedAt > COALESCE(max_date_processed, '2025-01-01')
            )

        SELECT 
        *
        FROM regex_stage
        WHERE 
        ((characters - LENGTH(review_after_regex)) / NULLIF(CAST(characters AS NUMERIC), 0) < 0.2)
        OR
        ((LENGTH(review_after_regex) - LENGTH(REPLACE(review_after_regex, ' ', ''))) < 0.1);

        -- Armazena a quantidade de linhas da temporaria_1 pos regex
        SET v_linhas_temporaria_1 = (SELECT COUNT(1) FROM temporaria_1);

        -- Verifica se existem dados sobreviventes, do contrário encerra o pipeline.
        IF v_linhas_temporaria_1 = 0 THEN
            CALL `__DATASET__.PRC_logs_control_table`(2);
            SET status_continuidade = 'ENCERRAR'
            SET motivo = 'Etapa 1 - Nenhuma review sobreviveu ao regex'
            RETURN;
        ELSE
            SET system_instruction = (
                SELECT system_instruction 
                FROM `__DATASET__.prompts_table` 
                WHERE step_prompt_id = 'analise_relevancia' 
                AND prompt_status = 'PRODUCTION'
            );
            
            -- Operação exclusiva do BigQuery
            -- Seleciona os dados pós regex, adiciona o prompt e reescreve a tabela
            CREATE OR REPLACE TABLE temporaria_1 AS
                SELECT
                *,
                STRUCT(
                    [STRUCT(
                    'user' AS role,
                    [STRUCT(
                        CONCAT(system_instruction, '\n', review_after_regex) AS text
                    )] AS parts
                    )] AS contents,
                    STRUCT(
                    0.5 AS temperature, 
                    100 AS maxOutputTokens, 
                    'application/json' AS responseMimeType
                    ) AS generationConfig
                ) AS request
                FROM temporaria_1;
            CALL `__DATASET__.PRC_logs_control_table`(3);
            SET status_continuidade = 'CONTINUAR'
            SET motivo = 'Etapa 1 - Existem dados que passaram pelo CORTE e REGEX'
        END IF;
    END IF;
END;