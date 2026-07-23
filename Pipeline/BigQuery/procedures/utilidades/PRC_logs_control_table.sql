CREATE OR REPLACE PROCEDURE `__DATASET__.PRC_logs_control_table`(IN etapa INT64)
BEGIN

  CASE etapa
    
    -- 1_PRC_regex_pre_inference - (1) verifica se existem reviews
    WHEN 1 THEN
      INSERT INTO `__DATASET__.logs_tabela_controle_geral` (
          pipeline_step,
          max_processed_timestamp,
          inserted_at,
          status,
          message
      ) 
      VALUES (
          'raw_to_temp1',
          CURRENT_DATE(),
          CURRENT_TIMESTAMP(),
          'NO_DATA',
          'Etapa 1 - Sem reviews para processar'
      );

    -- 1_PRC_regex_pre_inference - (2) verifica se existem reviews que sobreviveram ao regex
    WHEN 2 THEN
      INSERT INTO `__DATASET__.logs_tabela_controle_geral` (
          pipeline_step,
          max_processed_timestamp,
          inserted_at,
          status,
          message
      ) 
      VALUES (
          'raw_to_temp1',
          CURRENT_DATE(),
          CURRENT_TIMESTAMP(),
          'NO_DATA',
          'Nenhum dado relevante sobreviveu à etapa de regex'
      );

    -- 1_PRC_regex_pre_inference - (3) Etapa da filtragem até pré-inferencia completa
    WHEN 3 THEN
      INSERT INTO `__DATASET__.logs_tabela_controle_geral` (
          pipeline_step,
          max_processed_timestamp,
          inserted_at,
          status,
          message
      )
      VALUES (
          'raw_to_temp1',
          CURRENT_DATE(),
          CURRENT_TIMESTAMP(),
          'SUCCESS',
          'Temp1 processed successfully'
      );

    -- 2_PRC_pre_fragmentacao - (1) nenhuma review foi classificada como relevante para fragmentação.
    WHEN 4 THEN
      INSERT INTO `__DATASET__.logs_tabela_controle_geral` (
          pipeline_step,
          max_processed_timestamp,
          inserted_at,
          status,
          message
      )
      VALUES (
          'logic_split',
          CURRENT_DATE(),
          CURRENT_TIMESTAMP(),
          'NO_RELEVANT_DATA',
          'Nenhum dado foi marcado como relevante'
      );

    -- 2_PRC_pre_fragmentacao - (2) Tudo OK, dados direcionados e continua para fragmentacao
    WHEN 5 THEN
      INSERT INTO `__DATASET__.logs_tabela_controle_geral` (
          pipeline_step,
          max_processed_timestamp,
          inserted_at,
          status,
          message
      )
      VALUES (
          'sql_logic_split',
          CURRENT_DATE(),
          CURRENT_TIMESTAMP(),
          'SUCCESS',
          'Logic circuit completed'
      );

    -- 3_PRC_pos_fragmentacao - Tudo OK, os dados da fragmentação(struct) inseridos na silver e erros na DLQ
    WHEN 6 THEN
      INSERT INTO `__DATASET__.logs_tabela_controle_geral` (
          pipeline_step,
          max_processed_timestamp,
          inserted_at,
          status,
          message
      )
      VALUES (
          'ai_review_split_temp2',
          CURRENT_DATE(),
          CURRENT_TIMESTAMP(),
          'SUCCESS',
          'AI logic split completed'
      );

    -- 4_PRC_criacao_embeddings - OK, tudo certo
    WHEN 7 THEN
      INSERT INTO `__DATASET__.logs_tabela_controle_geral` (
          pipeline_step,
          max_processed_timestamp, -- Ajustado para manter o padrão da tabela
          inserted_at,
          status,
          message
      )
      VALUES(
          'unnest_to_embedding',
          CURRENT_DATE(),
          CURRENT_TIMESTAMP(),
          'SUCCESS',
          'Data processed successfully'
      );

    -- 5_PRC_classificacao
    WHEN 8 THEN
      INSERT INTO `__DATASET__.logs_tabela_controle_geral` (
          pipeline_step,
          max_processed_timestamp,
          inserted_at,
          status,
          message
      )
      VALUES (
          'router_classifier',
          CURRENT_DATE(),
          CURRENT_TIMESTAMP(),
          'SUCCESS',
          'Router classifier completed'
      );

    -- PRC_remover_tabelas_temporarias
    -- temporaria_1 - sucesso
    WHEN 9 THEN
      INSERT INTO `__DATASET__.logs_tabela_controle_geral` (
          pipeline_step,
          max_processed_timestamp,
          inserted_at,
          status,
          message
      )
      VALUES (
          'Remover tabelas temporárias',
          CURRENT_DATE(),
          CURRENT_TIMESTAMP(),
          'SUCCESS',
          'temporaria_1 deletada com sucesso.'
      );

    -- PRC_remover_tabelas_temporarias
    -- temporaria_1 - falha
    WHEN 10 THEN
      INSERT INTO `__DATASET__.logs_tabela_controle_geral` (
          pipeline_step,
          max_processed_timestamp,
          inserted_at,
          status,
          message
      )
      VALUES (
          'Remover tabelas temporárias',
          CURRENT_DATE(),
          CURRENT_TIMESTAMP(),
          'FAILED',
          'temporaria_1 nao encontrada ou já deletada.'
      );

      -- PRC_remover_tabelas_temporarias
    -- temporaria_2 - sucesso
    WHEN 11 THEN
      INSERT INTO `__DATASET__.logs_tabela_controle_geral` (
          pipeline_step,
          max_processed_timestamp,
          inserted_at,
          status,
          message
      )
      VALUES (
          'Remover tabelas temporárias',
          CURRENT_DATE(),
          CURRENT_TIMESTAMP(),
          'SUCCESS',
          'temporaria_2 deletada com sucesso.'
      );

    -- PRC_remover_tabelas_temporarias
    -- temporaria_2 - falha
    WHEN 12 THEN
      INSERT INTO `__DATASET__.logs_tabela_controle_geral` (
          pipeline_step,
          max_processed_timestamp,
          inserted_at,
          status,
          message
      )
      VALUES (
          'Remover tabelas temporárias',
          CURRENT_DATE(),
          CURRENT_TIMESTAMP(),
          'FAILED',
          'temporaria_2 nao encontrada ou já deletada.'
      );

      -- PRC_remover_tabelas_temporarias
    -- temporaria_3 - sucesso
    WHEN 13 THEN
      INSERT INTO `__DATASET__.logs_tabela_controle_geral` (
          pipeline_step,
          max_processed_timestamp,
          inserted_at,
          status,
          message
      )
      VALUES (
          'Remover tabelas temporárias',
          CURRENT_DATE(),
          CURRENT_TIMESTAMP(),
          'SUCCESS',
          'temporaria_3 deletada com sucesso.'
      );

    -- PRC_remover_tabelas_temporarias
    -- temporaria_3 - falha
    WHEN 14 THEN
      INSERT INTO `__DATASET__.logs_tabela_controle_geral` (
          pipeline_step,
          max_processed_timestamp,
          inserted_at,
          status,
          message
      )
      VALUES (
          'Remover tabelas temporárias',
          CURRENT_DATE(),
          CURRENT_TIMESTAMP(),
          'FAILED',
          'temporaria_3 nao encontrada ou já deletada.'
      );
    
    -- Tratamento caso o número enviado seja inválido
    ELSE
      RAISE USING MESSAGE = FORMAT('Erro: Etapa %d é inválida para a PRC_logs_logs_tabela_controle_geral.', etapa);

  END CASE;

END;