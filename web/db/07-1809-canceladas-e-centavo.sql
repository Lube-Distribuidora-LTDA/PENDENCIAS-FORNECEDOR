-- =============================================================================
-- PENDÊNCIAS FORNECEDOR — migração pendencias_10_1809_canceladas_e_centavo (2026-10-29). Roda depois do
-- 06-1825-grupo-do-principal.sql: troca o fluxo pendencias.verba, a saldo_aplicar() e a detalhe() de lá.
--
-- O total da rotina 1809 de um fornecedor (print do Júlio) deu R$ 9.999,99 a mais que o painel:
--   * a rotina soma também as verbas CANCELADAS. Quase todas têm saldo zero, mas duas (em toda a base) foram
--     canceladas com o valor zerado e uma aplicação negativa (rotina 1807) que ficou: saldo = 0 − (−aplicação). O
--     agente lia só as não canceladas (WHERE DTCANCEL IS NULL); agora lê todas, com a data do cancelamento;
--   * o centavo: a rotina deixa fora a fração de verba abaixo de R$ 0,01 (o corte do painel era meio centavo). Com o
--     corte em um centavo o total bate; com o de meio centavo sobrava R$ 0,01.
-- =============================================================================

alter table pendencias.verba add column if not exists dtcancel date;
comment on column pendencias.verba.dtcancel is
  'PCVERBA.DTCANCEL. A rotina 1809 soma a verba cancelada também (a que ficou com aplicação negativa tem saldo).';

update agente.fluxo
   set descricao = 'Rotina 1809: verbas do fornecedor (PCVERBA, canceladas inclusive, como a rotina) com o aplicado (PCAPLICVERBA) e a conta corrente da verba',
       colunas = array['numverba', 'codfilial', 'codfornec', 'dtemissao', 'dtvenc', 'dtcadastro', 'tipo', 'formapgto',
                       'referencia', 'numnota', 'numped', 'codcomprador', 'valor', 'aplicado', 'qtaplic', 'ult_aplic',
                       'cc_debito', 'cc_credito', 'dtquitacao', 'rotinalanc', 'dtcancel'],
       sql = $q$SELECT v.numverba, v.codfilial, v.codfornec, v.dtemissao, v.dtvenc, v.dtcadastro, v.tipo, v.formapgto,
       TRIM(TRIM(v.referencia) || ' ' || TRIM(v.referencia1)) AS referencia,
       v.numnota, v.numped, v.codcomprador, v.valor,
       a.aplicado, a.qtaplic, a.ult_aplic,
       m.cc_debito, m.cc_credito, v.dtquitacao, v.rotinalanc, v.dtcancel
  FROM pcverba v
  LEFT JOIN (SELECT numverba, SUM(vlaplic) AS aplicado, COUNT(*) AS qtaplic, MAX(dtaplic) AS ult_aplic
               FROM pcaplicverba GROUP BY numverba) a ON a.numverba = v.numverba
  LEFT JOIN (SELECT numverba, SUM(DECODE(tipo, 'D', valor, 0)) AS cc_debito,
                    SUM(DECODE(tipo, 'C', valor, 0)) AS cc_credito
               FROM pcmovcrfor GROUP BY numverba) m ON m.numverba = v.numverba
$q$,
       atualizado_em = now(),
       atualizado_por = 'migração pendencias_10 (Claude)'
 where nome = 'pendencias.verba';

-- Saldo a aplicar de uma verba: a fração abaixo de um centavo conta como zero, como na rotina 1809.
create or replace function pendencias.saldo_aplicar(p_valor numeric, p_aplicado numeric)
returns numeric language sql immutable
as $$ select case when abs(coalesce(p_valor, 0) - coalesce(p_aplicado, 0)) < 0.01 then 0 else coalesce(p_valor, 0) - coalesce(p_aplicado, 0) end $$;

-- O detalhe ganha 'dc' (cancelada em) em cada verba; o resto é o da migração 09.
create or replace function pendencias.detalhe(p_codfornec bigint)
returns json
language sql
stable
set search_path = pendencias, pg_temp
as $$
with eu as (
  select coalesce(nullif(f.codfornecprinc, 0), p_codfornec) as principal, (now() at time zone 'America/Sao_Paulo')::date as hoje
    from (select 1) x left join pendencias.fornecedor f on f.codfornec = p_codfornec
)
select json_build_object(
  'fornecedor', (select row_to_json(f) from pendencias.fornecedor f where f.codfornec = p_codfornec),
  'periodo', (select json_build_object('desde', '2011-01-01', 'ate', to_char(hoje, 'YYYY-MM-DD')) from eu),
  'periodo_1825', (select json_build_object('desde', '2011-01-01', 'ate', to_char(hoje, 'YYYY-MM-DD')) from eu),
  'verbas', (select coalesce(json_agg(json_build_object(
                 'nv', numverba, 'fi', codfilial, 'em', dtemissao, 've', dtvenc, 'ti', tipo, 'fp', formapgto,
                 'rf', referencia, 'nn', numnota, 'np', numped, 'vl', valor, 'ap', coalesce(aplicado, 0),
                 'sa', pendencias.saldo_aplicar(valor, aplicado), 'qa', coalesce(qtaplic, 0), 'ua', ult_aplic,
                 'cd', coalesce(cc_debito, 0), 'cr', coalesce(cc_credito, 0), 'dq', dtquitacao, 'rl', rotinalanc, 'dc', dtcancel)
               order by dtemissao desc nulls last, numverba desc), '[]')
               from pendencias.verba, eu where codfornec = p_codfornec and dtemissao between date '2011-01-01' and eu.hoje),
  'grupo_1825', (select principal from eu),
  'lancamentos', (select coalesce(json_agg(json_build_object(
                 'nt', numtranscrfor, 'fo', codfornec, 'fi', codfilial, 'dt', data, 'hr', hora, 'mi', minuto, 'ti', tipo, 'vl', valor,
                 'hi', historico, 'nv', numverba, 'np', numpedido, 'ne', numtransent, 'rl', rotinalanc,
                 'fu', funcionario, 'es', dtestorno, 'sd', saldo)
               order by numtranscrfor desc), '[]')
               from (select g.*, sum(case tipo when 'D' then valor when 'C' then -valor else 0 end)
                                   over (order by numtranscrfor) as saldo
                       from pendencias.lancamento_grupo g, eu where g.principal = eu.principal) z),
  'grupo', (select coalesce(json_agg(json_build_object('fo', codfornec, 'fn', fornecedor, 'sd', saldo, 'nl', n) order by codfornec), '[]')
              from (select g.codfornec, f.fornecedor, count(*) as n,
                           sum(case g.tipo when 'D' then g.valor when 'C' then -g.valor else 0 end) as saldo
                      from pendencias.lancamento_grupo g left join pendencias.fornecedor f on f.codfornec = g.codfornec, eu
                     where g.principal = eu.principal group by g.codfornec, f.fornecedor) z),
  'lancamento_fora', (select coalesce(json_agg(json_build_object('fi', codfilial, 'va', valor, 'nl', n) order by codfilial), '[]')
              from (select l.codfilial, count(*) as n, sum(case l.tipo when 'D' then l.valor when 'C' then -l.valor else 0 end) as valor
                      from pendencias.lancamento l left join pendencias.fornecedor f on f.codfornec = l.codfornec, eu
                     where coalesce(nullif(f.codfornecprinc, 0), l.codfornec) = eu.principal
                       and l.data between date '2011-01-01' and eu.hoje
                       and not exists (select 1 from pendencias.filial fi where fi.codfilial = l.codfilial)
                     group by l.codfilial) z),
  'principal', (select case when e.principal <> p_codfornec then json_build_object(
                  'c', e.principal, 'n', (select fornecedor from pendencias.fornecedor where codfornec = e.principal),
                  'sf', (select sum(case tipo when 'D' then valor when 'C' then -valor else 0 end) from pendencias.lancamento_grupo
                          where principal = e.principal),
                  'av', (select sum(qtindeniz * valorultent) from pendencias.avaria_grupo
                          where codfornec = e.principal or principal = e.principal))
                end from eu e),
  'saldos', (select coalesce(json_agg(json_build_object('fi', codfilial, 'vl', valor, 'vc', valorconciliado, 'dc', dtultconcilia)
               order by codfilial), '[]')
               from pendencias.saldo where codfornec = p_codfornec),
  'avaria', (select coalesce(json_agg(json_build_object(
                 'fo', codfornec, 'fi', codfilial, 'cp', codprod, 'ds', descricao, 'em', embalagem, 'un', unidade, 'qt', qtindeniz,
                 'qe', qtestger, 'qb', qtbloqueada, 'vu', valorultent, 'cu', custoultent, 'cf', custofin, 'de', dtultent,
                 'va', qtindeniz * valorultent)
               order by qtindeniz * valorultent desc nulls last), '[]')
               from pendencias.avaria_grupo where codfornec = p_codfornec or principal = p_codfornec),
  'avaria_grupo', (select coalesce(json_agg(json_build_object('fo', codfornec, 'fn', fornecedor, 'va', valor, 'np', n) order by codfornec), '[]')
              from (select g.codfornec, f.fornecedor, count(*) as n, sum(g.qtindeniz * g.valorultent) as valor
                      from pendencias.avaria_grupo g left join pendencias.fornecedor f on f.codfornec = g.codfornec
                     where g.codfornec = p_codfornec or g.principal = p_codfornec group by g.codfornec, f.fornecedor) z),
  'avaria_fora', (select coalesce(json_agg(json_build_object('fi', codfilial, 'va', valor, 'np', n) order by codfilial), '[]')
              from (select a.codfilial, count(*) as n, sum(a.qtindeniz * a.valorultent) as valor
                      from pendencias.avaria a
                      join pendencias.filial_fora_8073 x on x.codfilial = a.codfilial
                      left join pendencias.fornecedor f on f.codfornec = a.codfornec
                     where a.codfornec = p_codfornec or coalesce(nullif(f.codfornecprinc, 0), a.codfornec) = p_codfornec
                     group by a.codfilial) z),
  'lido', (select coalesce(json_object_agg(fluxo, json_build_object('lido_em', lido_em, 'mudou_em', mudou_em, 'status', status)), '{}')
             from agente.estado where fluxo like 'pendencias.%')
);
$$;

select pendencias.atualizar_pacote();
