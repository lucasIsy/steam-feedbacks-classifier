CREATE TABLE IF NOT EXISTS `__DATASET__.logs_tabela_controle_geral` (
    batch_id STRING,
    pipeline_step STRING NOT NULL,
    max_date_processed DATE NOT NULL,
    inserted_at TIMESTAMP NOT NULL,
    status STRING NOT NULL,
    message STRING,
    rows_affected INT64
)
PARTITION BY max_date_processed
CLUSTER BY batch_id, pipeline_step;