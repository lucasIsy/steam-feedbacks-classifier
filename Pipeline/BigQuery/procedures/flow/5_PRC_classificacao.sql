CREATE OR REPLACE PROCEDURE `__DATASET__.5_PRC_classificacao`(IN p_batch_id STRING)
BEGIN
    DECLARE limite_distancia FLOAT64 DEFAULT 0.15;
    DECLARE v_conhecidos INT64;

    -- Em casos de retry o insert into começa do zero.
    CREATE OR REPLACE TEMP TABLE router_table (
        ai_split_id INT64,
        status STRING,
        resume_id STRING,
        distance FLOAT64,
        vizinho_ai_split_id INT64
    );

    -- category(2), topic(8), sentiment(3)(UX: -1 e 1; DEV: 0)
    FOR combination IN (
    SELECT DISTINCT category, topic, sentiment
    FROM `__DATASET__.temporaria_3`
    WHERE batch_id = p_batch_id
    )
    DO
        INSERT INTO router_table (ai_split_id, status, resume_id, distance, vizinho_ai_split_id)
        SELECT
            query.ai_split_id,
            IF(distance <= limite_distancia, 'OK', 'Revisão') AS status,
            IF(distance <= limite_distancia, base.resume_id, NULL) AS resume_id,
            distance,
            base.ai_split_id AS vizinho_ai_split_id

        FROM VECTOR_SEARCH(
        -- Busca já restrita ao Cluster com 3 níveis (Inclui o sentiment 0 de DEV automaticamente)
        (
        SELECT ai_split_id, resume_id, embedding FROM `__DATASET__.VectorDB_reviews`
        WHERE category = combination.category
            AND topic = combination.topic
            AND sentiment = combination.sentiment
        ),
        'embedding',
        (
        SELECT ai_split_id, embedding
        FROM `__DATASET__.temporaria_3`
        WHERE batch_id = p_batch_id
            AND category = combination.category
            AND topic = combination.topic
            AND sentiment = combination.sentiment
        ),
        'embedding',
        top_k => 1,
        distance_type => 'COSINE'
    );
    END FOR;

    INSERT INTO router_table (ai_split_id, status, resume_id, distance, vizinho_ai_split_id)
    SELECT t.ai_split_id, 'Revisão', NULL, NULL, NULL
    FROM `__DATASET__.temporaria_3` AS t
    WHERE t.batch_id = p_batch_id
        AND NOT EXISTS (SELECT 1 FROM router_table AS r WHERE r.ai_split_id = t.ai_split_id);

    -- Retry do mesmo lote: apaga o que este batch_id já gravou antes de regravar
    DELETE FROM `__DATASET__.Gold_reviews` WHERE batch_id = p_batch_id;
    DELETE FROM `__DATASET__.Cofre_embeddings` WHERE batch_id = p_batch_id;
    DELETE FROM `__DATASET__.RAG_queue` WHERE batch_id = p_batch_id;

    INSERT INTO `__DATASET__.Gold_reviews` (
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
        category,
        topic,
        sentiment,
        content,
        resume_id,
        distance,
        vizinho_ai_split_id
    )
    SELECT
        temporaria_3.batch_id,
        temporaria_3.ingested_at,
        temporaria_3.hash_id,
        temporaria_3.recommendationid,
        temporaria_3.ai_split_id,
        temporaria_3.date_created,
        temporaria_3.date_updated,
        temporaria_3.playtime_forever,
        temporaria_3.playtime_at_review,
        temporaria_3.language,
        temporaria_3.category,
        temporaria_3.topic,
        temporaria_3.sentiment,
        temporaria_3.content,
        router_table.resume_id,
        router_table.distance,
        router_table.vizinho_ai_split_id
    FROM router_table
    INNER JOIN `__DATASET__.temporaria_3` AS temporaria_3
    USING (ai_split_id)
    WHERE router_table.status = 'OK';

    INSERT INTO `__DATASET__.Cofre_embeddings` (
        batch_id,
        ingested_at,
        hash_id,
        recommendationid,
        ai_split_id,
        category,
        topic,
        sentiment,
        status,
        resume_id,
        distance,
        vizinho_ai_split_id,
        embedding
    )
    SELECT
        temporaria_3.batch_id,
        temporaria_3.ingested_at,
        temporaria_3.hash_id,
        temporaria_3.recommendationid,
        temporaria_3.ai_split_id,
        temporaria_3.category,
        temporaria_3.topic,
        temporaria_3.sentiment,
        router_table.status,
        router_table.resume_id,
        router_table.distance,
        router_table.vizinho_ai_split_id,
        temporaria_3.embedding
    FROM router_table
    -- Não precisa de where pois sua função é guardar todos os embeddings e metadados para usos futuros.
    INNER JOIN `__DATASET__.temporaria_3` AS temporaria_3
    USING (ai_split_id);

    INSERT INTO `__DATASET__.RAG_queue` (
        batch_id,
        ingested_at,
        hash_id,
        ai_split_id,
        category,
        topic,
        sentiment,
        content,
        distance,
        vizinho_ai_split_id,
        data_enfileiramento
    )
    SELECT
        temporaria_3.batch_id,
        temporaria_3.ingested_at,
        temporaria_3.hash_id,
        temporaria_3.ai_split_id,
        temporaria_3.category,
        temporaria_3.topic,
        temporaria_3.sentiment,
        temporaria_3.content,
        router_table.distance,
        router_table.vizinho_ai_split_id,
        CURRENT_DATE()
    FROM router_table
    INNER JOIN `__DATASET__.temporaria_3` AS temporaria_3
    USING (ai_split_id)
    WHERE router_table.status = 'Revisão';

    -- ========================================================================
    -- TABELA DE CONTROLE - Fim da execução do script
    -- ========================================================================
    SET v_conhecidos = (SELECT COUNTIF(status = 'OK') FROM router_table);
    CALL `__DATASET__.PRC_logs_control_table`(p_batch_id, 8, v_conhecidos);
END;
