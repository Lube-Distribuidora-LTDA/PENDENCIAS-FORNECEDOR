-- =============================================================================
-- PENDÊNCIAS FORNECEDOR — migração pendencias_12_avaria_sem_filial_12 (2026-10-30). Roda depois do
-- 08-avaria-sem-filial-7.sql.
--
-- A 8073 de um fornecedor com avaria nas filiais 1 e 12 (relatório do Júlio, todas as filiais) traz só as linhas da
-- filial 1, produto por produto; o painel tinha a mais os da 12. Com a 7 e a 11, a 12 sai: entre as filiais que têm
-- avaria hoje (1, 7, 11 e 12), a rotina com todas as filiais só soma a filial 1. Filial nova com avaria: conferir com um
-- relatório antes de deixar entrar.
-- =============================================================================

insert into pendencias.filial_fora_8073 (codfilial, motivo) values
  ('12', 'Relatório da 8073 com todas as filiais não traz a filial 12: um fornecedor com avaria nas filiais 1 e 12 veio só com as linhas da 1 (2026-10-30)')
on conflict (codfilial) do nothing;

select pendencias.atualizar_pacote();
