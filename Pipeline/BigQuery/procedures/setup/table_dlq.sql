CREATE TABLE IF NOT EXISTS `__DATASET__.DLQ_reviews` (
  batch_id STRING NOT NULL,
  ingested_at TIMESTAMP NOT NULL,
  hash_id STRING NOT NULL,
  payload STRING,
  error_checkpoint STRING,
  retry_count INT64 NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  AI_finishReason STRING
)
PARTITION BY DATE(ingested_at)
CLUSTER BY error_checkpoint, hash_id;
