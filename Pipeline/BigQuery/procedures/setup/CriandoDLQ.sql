CREATE OR REPLACE TABLE `__DATASET__.DLQ_reviews` (
  batch_id STRING,
  ingested_at TIMESTAMP,
  hash_id STRING NOT NULL,
  payload STRING,
  error_checkpoint STRING,
  retry_count INT64 NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  AI_finishReason STRING
);