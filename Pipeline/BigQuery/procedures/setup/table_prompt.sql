CREATE TABLE IF NOT EXISTS `__DATASET__.prompts_table` (
  step_prompt_id STRING NOT NULL,
  prompt_version STRING NOT NULL,
  prompt_status STRING NOT NULL,
  system_instruction STRING NOT NULL,
  prompt_tokens INT64 NOT NULL,
  efficiency FLOAT64,
  created_at TIMESTAMP NOT NULL
);

-- === step_prompt_id ===
-- ai_boolean_filter
-- ai_fragmentation

-- === prompt_status ===
-- PRODUCTION
-- TESTING
-- ARCHIVED
