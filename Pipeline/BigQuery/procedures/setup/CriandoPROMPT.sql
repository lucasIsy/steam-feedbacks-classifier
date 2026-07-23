CREATE OR REPLACE TABLE `__DATASET__.prompts_table` (
  step_prompt_id STRING NOT NULL,
  prompt_status STRING NOT NULL,
  system_instruction STRING NOT NULL,
  prompt_tokens INT64 NOT NULL,
  efficiency FLOAT64 
);

-- === step_prompt_id ===
-- ai_boolean_filter
-- ai_fragmentation

-- === prompt_status ===
-- PRODUCTION
-- TESTING
-- ARCHIVED