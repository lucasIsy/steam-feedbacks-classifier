CREATE OR REPLACE TABLE `__DATASET__.logs_tabela_controle_geral` (
    pipeline_step STRING NOT NULL,
    max_date_processed DATE NOT NULL,
    inserted_at TIMESTAMP NOT NULL,
    status STRING NOT NULL,
    message STRING
)
PARTITION BY max_date_processed
CLUSTER BY pipeline_step;