CREATE TABLE IF NOT EXISTS `__DATASET__.Silver_Reviews`(
    batch_id STRING NOT NULL,
    ingested_at TIMESTAMP NOT NULL,
    hash_id STRING NOT NULL,
    recommendationid INT64,
    date_created DATE,
    date_updated DATE,
    date_last_played DATE, 
    playtime_forever INT64,
    playtime_last_two_weeks INT64,
    playtime_at_review INT64,
    language STRING,
    review_after_regex STRING,
    relevance_label INT64,
    relevance_cot STRING,
    prompt_version STRING,
    model_version STRING,
    filter_total_tokens INT64,
    split_total_tokens INT64,
    AI_struct_array ARRAY<JSON>
)
PARTITION BY DATE(ingested_at)
CLUSTER BY batch_id, hash_id;
