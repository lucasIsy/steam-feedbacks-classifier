CREATE TABLE IF NOT EXISTS `__DATASET__.Gold_reviews` (
    batch_id STRING NOT NULL,
    ingested_at TIMESTAMP NOT NULL,
    hash_id STRING NOT NULL,
    recommendationid INT64,
    ai_split_id INT64 NOT NULL,
    date_created DATE,
    date_updated DATE,
    playtime_forever INT64,
    playtime_at_review INT64,
    language STRING,
    category STRING,
    topic STRING,
    sentiment INT64,
    content STRING,
    resume_id STRING,
    distance FLOAT64,
    vizinho_ai_split_id INT64
)
PARTITION BY DATE(ingested_at)
CLUSTER BY batch_id, category, topic, sentiment;
