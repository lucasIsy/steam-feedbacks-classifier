CREATE OR REPLACE TABLE `__DATASET__.logs_tabela_controle_extracao` (
    extraction_date STRING NOT NULL,
    max_review_unix_date INT64 NOT NULL,
    total_reviews_extracted INT64
)