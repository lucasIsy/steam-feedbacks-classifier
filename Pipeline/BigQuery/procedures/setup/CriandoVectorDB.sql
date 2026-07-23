CREATE OR REPLACE TABLE `__DATASET__.VectorDB_reviews` (
    ai_split_id INT64 NOT NULL,      
    ingested_at DATE NOT NULL, 
    category STRING NOT NULL,   
    topic STRING NOT NULL,      
    score INT64 NOT NULL,       
    resume_id STRING NOT NULL,     
    embedding ARRAY<FLOAT64> NOT NULL
)
CLUSTER BY category, topic, score;

CREATE VECTOR INDEX IF NOT EXISTS reviews_vector_index
ON `__DATASET__.VectorDB_reviews` (embedding)
STORING (category, topic, score)
OPTIONS (
    index_type = 'IVF',
    distance_type = 'COSINE'
);