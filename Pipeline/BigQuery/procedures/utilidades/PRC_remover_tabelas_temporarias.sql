CREATE OR REPLACE PROCEDURE `__DATASET__.PRC_remover_tabelas_temporarias`()
BEGIN
  -- 1. Tenta deletar a primeira tabela
  BEGIN
    EXECUTE IMMEDIATE "DROP TABLE `__DATASET__.temporaria_1`";
    CALL `__DATASET__.PRC_logs_control_table`(9);
  EXCEPTION WHEN ERROR THEN
    CALL `__DATASET__.PRC_logs_control_table`(10);
  END;

  -- 2. Tenta deletar a segunda tabela
  BEGIN
    EXECUTE IMMEDIATE "DROP TABLE `__DATASET__.temporaria_2`";
    CALL `__DATASET__.PRC_logs_control_table`(11);
  EXCEPTION WHEN ERROR THEN
    CALL `__DATASET__.PRC_logs_control_table`(12);
  END;
  
  -- 3. Tenta deletar a terceira tabela
  BEGIN
    EXECUTE IMMEDIATE "DROP TABLE `__DATASET__.temporaria_3`";
    CALL `__DATASET__.PRC_logs_control_table`(13);
  EXCEPTION WHEN ERROR THEN
    CALL `__DATASET__.PRC_logs_control_table`(14);
  END;
END;