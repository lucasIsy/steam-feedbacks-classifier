CREATE TABLE IF NOT EXISTS `__DATASET__.RAG_queue` (
    batch_id STRING NOT NULL,
    ingested_at TIMESTAMP NOT NULL,
    hash_id STRING NOT NULL,
    ai_split_id INT64 NOT NULL,
    category STRING,
    topic STRING,
    sentiment INT64,
    content STRING,
    distance FLOAT64,
    vizinho_ai_split_id INT64,
    data_enfileiramento DATE NOT NULL
)
PARTITION BY DATE(ingested_at)
CLUSTER BY batch_id, category, topic, sentiment;
