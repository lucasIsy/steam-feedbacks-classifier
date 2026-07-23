CREATE OR REPLACE TABLE `__DATASET__.Silver_Reviews`(
    batch_id STRING,
    ingested_at TIMESTAMP,
    hash_id STRING,
    recommendationid STRING,
    date_created DATE,
    date_updated DATE,
    date_last_played DATE, 
    timestamp_updated TIMESTAMP,
    playtime_forever FLOAT64,
    playtime_last_two_weeks FLOAT64,
    playtime_at_review FLOAT64,
    language STRING,
    review_after_regex STRING,
    AI_struct_array ARRAY<JSON>
)
partition by ingestedAT