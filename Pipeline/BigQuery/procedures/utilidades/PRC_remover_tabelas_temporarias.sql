CREATE OR REPLACE PROCEDURE `__DATASET__.PRC_remover_tabelas_temporarias`(IN p_batch_id STRING)
BEGIN
  -- 1. Tenta deletar a primeira tabela
  BEGIN
    EXECUTE IMMEDIATE "DROP TABLE `__DATASET__.temporaria_1`";
    CALL `__DATASET__.PRC_logs_control_table`(p_batch_id, 9, NULL);
  EXCEPTION WHEN ERROR THEN
    CALL `__DATASET__.PRC_logs_control_table`(p_batch_id, 10, NULL);
  END;

  -- 2. Tenta deletar a segunda tabela
  BEGIN
    EXECUTE IMMEDIATE "DROP TABLE `__DATASET__.temporaria_2`";
    CALL `__DATASET__.PRC_logs_control_table`(p_batch_id, 11, NULL);
  EXCEPTION WHEN ERROR THEN
    CALL `__DATASET__.PRC_logs_control_table`(p_batch_id, 12, NULL);
  END;
  
  -- 3. Tenta deletar a terceira tabela
  BEGIN
    EXECUTE IMMEDIATE "DROP TABLE `__DATASET__.temporaria_3`";
    CALL `__DATASET__.PRC_logs_control_table`(p_batch_id, 13, NULL);
  EXCEPTION WHEN ERROR THEN
    CALL `__DATASET__.PRC_logs_control_table`(p_batch_id, 14, NULL);
  END;
END;
