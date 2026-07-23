CREATE OR REPLACE TABLE `__DATASET__.Cofre_embeddings` (
    ai_split_id STRING NOT NULL,
    ingested_at DATE NOT NULL,
    category STRING,
    topic STRING,
    score INT64,
    resume_id STRING,
    embedding ARRAY<FLOAT64> NOT NULL
)
PARTITION BY ingested_at
CLUSTER BY category, topic, score; 