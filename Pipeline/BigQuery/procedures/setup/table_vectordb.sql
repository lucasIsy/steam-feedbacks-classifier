CREATE TABLE IF NOT EXISTS `__DATASET__.VectorDB_reviews` (
    ai_split_id INT64 NOT NULL,      
    ingested_at TIMESTAMP NOT NULL, 
    category STRING NOT NULL,   
    topic STRING NOT NULL,      
    sentiment INT64 NOT NULL,       
    resume_id STRING NOT NULL,     
    embedding_model STRING NOT NULL,
    embedding ARRAY<FLOAT64>
)
CLUSTER BY category, topic, sentiment;
