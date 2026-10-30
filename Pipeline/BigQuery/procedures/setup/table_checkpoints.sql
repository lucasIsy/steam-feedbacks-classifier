CREATE TABLE IF NOT EXISTS `__DATASET__.pipeline_checkpoints` (
    batch_id STRING NOT NULL,
    step STRING NOT NULL,
    status STRING NOT NULL,
    updated_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(updated_at)
CLUSTER BY batch_id, step;
