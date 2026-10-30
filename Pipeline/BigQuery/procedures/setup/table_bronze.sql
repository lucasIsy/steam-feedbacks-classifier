CREATE TABLE IF NOT EXISTS `__DATASET__.bronze_reviews` (
    batch_id STRING,
    ingested_at TIMESTAMP,
    hash_id STRING,
    recommendationid INT64,
    timestamp_created INT64,
    timestamp_updated INT64,
    playtime_forever INT64,
    playtime_last_two_weeks INT64,
    playtime_at_review INT64,
    last_played INT64,
    app_release_date INT64,
    language STRING,
    characters INT64,
    spaces INT64,
    review STRING
)
PARTITION BY DATE(ingested_at)
CLUSTER BY batch_id;
