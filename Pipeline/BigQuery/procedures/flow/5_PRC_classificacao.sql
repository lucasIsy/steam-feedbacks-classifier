CREATE OR REPLACE PROCEDURE `__DATASET__.5_PRC_classificacao`()
BEGIN
    DECLARE limite_distancia FLOAT64 DEFAULT 0.15;

    -- Em casos de retry o insert into começa do zero.
    CREATE OR REPLACE TEMP TABLE router_table (
        ai_split_id STRING,
        status STRING,
        resume_id STRING
    );

    -- category(2), topic(8), sentiment(3)(UX: -1 e 1; DEV: 0)
    FOR combination IN (
    SELECT DISTINCT category, topic, sentiment 
    FROM `__DATASET__.temporaria_3`
    )
    DO
        INSERT INTO router_table
        SELECT
            new_review.ai_split_id,
            CASE 
                WHEN distance <= limite_distancia THEN 'OK' 
                ELSE 'Revisão' 
            END AS status,
            CASE 
                WHEN distance <= limite_distancia THEN vectorDB.resume_id 
                ELSE NULL 
            END AS resume_id

        FROM VECTOR_SEARCH(
        -- Busca já restrita ao Cluster com 3 níveis (Inclui o sentiment 0 de DEV automaticamente)
        (
        SELECT ai_split_id, category, topic, sentiment, embedding FROM `__DATASET__.VectorDB_reviews` 
        WHERE category = combination.category 
            AND topic = combination.topic
            AND sentiment = combination.sentiment
        ) as vectorDB,
        'embedding',
        (
        SELECT ai_split_id, category, topic, sentiment, embedding 
        FROM `__DATASET__.temporaria_3` 
        WHERE category = combination.category 
            AND topic = combination.topic
            AND sentiment = combination.sentiment
        ) as new_review,
        'embedding',
        top_k => 1
    );
    END FOR;

    -- Todas tabelas particionadas por data, menos a fila_RAG(volume temporário)
    DELETE FROM `__DATASET__.Gold_reviews` WHERE data_processamento = CURRENT_DATE();
    DELETE FROM `__DATASET__.backup_silver_embeddings` WHERE data_ingestao = CURRENT_DATE();
    DELETE FROM `__DATASET__.RAG_QUEUE` WHERE data_enfileiramento = CURRENT_DATE();

    INSERT INTO `__DATASET__.Silver_classified_reviews` (
        batch_id,
        ingested_at,
        hash_id,
        recommendation_id,
        ai_split_id,
        category,
        topic,
        sentiment,
        content,
        status,
        resume_id
    )
    SELECT 
        temporaria_3.hash_id,
        temporaria_3.recommendation_id,
        temporaria_3.ai_split_id,
        temporaria_3.category,
        temporaria_3.topic,
        temporaria_3.sentiment,
        temporaria_3.content,
        router_table.resume_id
    FROM `__DATASET__.router_table` AS router_table
    WHERE router_table.status = 'OK'
    INNER JOIN `__DATASET__.temporaria_3` AS temporaria_3
    ON router_table.ai_split_id = temporaria_3.ai_split_id;

    INSERT INTO `__DATASET__.backup_silver_embeddings` (
        batch_id,
        ingested_at,
        hash_id,
        recommendation_id,
        ai_split_id,
        category,
        topic,
        sentiment,
        status,
        resume_id,
        embedding
    )
    SELECT 
        temporaria_3.batch_id,
        temporaria_3.ingested_at,
        temporaria_3.hash_id,
        temporaria_3.recommendation_id,
        temporaria_3.ai_split_id,
        temporaria_3.category,
        temporaria_3.topic,
        temporaria_3.sentiment,
        router_table.status,
        router_table.resume_id,
        temporaria_3.embedding
    FROM `__DATASET__.router_table` AS router_table
    -- Não precisa de where pois sua função é guardar todos os embeddings e metadados para usos futuros.
    INNER JOIN `__DATASET__.temporaria_3` AS temporaria_3
    ON router_table.ai_split_id = temporaria_3.ai_split_id;

    INSERT INTO `__DATASET__.Fila_RAG_silver` (
        hash_id,
        category,
        topic,
        sentiment,
        content,
        resume_id,
        data_enfileiramento
    )
    SELECT 
        temporaria_3.hash_id,
        temporaria_3.category,
        temporaria_3.topic,
        temporaria_3.sentiment,
        temporaria_3.content,
        router_table.resume_id,
        CURRENT_DATE()
    FROM `__DATASET__.router_table` AS router_table
    WHERE router_table.status = 'Revisão'
    INNER JOIN `__DATASET__.temporaria_3` AS temporaria_3
    ON router_table.ai_split_id = temporaria_3.ai_split_id;

    -- ========================================================================
    -- TABELA DE CONTROLE - Fim da execução do script
    -- ========================================================================
    CALL `__DATASET__.PRC_logs_control_table`(8);
END;