CREATE TABLE IF NOT EXISTS `__DATASET__.Cofre_embeddings` (
    batch_id STRING NOT NULL,
    ingested_at TIMESTAMP NOT NULL,
    hash_id STRING NOT NULL,
    recommendationid INT64,
    ai_split_id INT64 NOT NULL,
    category STRING,
    topic STRING,
    sentiment INT64,
    status STRING,
    resume_id STRING,
    distance FLOAT64,
    vizinho_ai_split_id INT64,
    embedding ARRAY<FLOAT64>
)
PARTITION BY DATE(ingested_at)
CLUSTER BY batch_id, category, topic, sentiment;
