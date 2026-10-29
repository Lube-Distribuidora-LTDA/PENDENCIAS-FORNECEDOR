-- =============================================================================
-- PENDÊNCIAS FORNECEDOR — migração pendencias_08_avaria_filiais_da_rotina (2026-10-29). Roda depois do
-- 04-codigo-e-grupo.sql e troca a view avaria_grupo e a detalhe() de lá.
--
-- A 8073 puxada com TODAS as filiais não traz a filial 11 (BA): os dois relatórios que o Júlio mandou deram exatamente
-- o estoque avariado sem as linhas da 11 (valores em conferencia/referencias.json, fora do Git).
-- No cadastro (PCFILIAL) a 11 é a única das filiais com avaria que usa estoque de depósito fechado
-- (USAESTOQUEDEPFECHADO = 'S') e não emite nota própria. As filiais 1, 7 e 12 entram.
-- A lista das filiais que a rotina deixa de fora mora no banco: mudar é um insert/delete, sem mexer em código.
-- A tela mostra à parte quanto ficou fora, para nada sumir sem aviso.
-- =============================================================================

create table if not exists pendencias.filial_fora_8073 (
  codfilial text primary key,
  motivo    text not null,
  desde     date not null default (now() at time zone 'America/Sao_Paulo')::date
);
alter table pendencias.filial_fora_8073 enable row level security;
comment on table pendencias.filial_fora_8073 is
  'Filiais que a rotina 8073 do WinThor não soma, mesmo com todas as filiais (conferido contra os relatórios do Júlio).';

insert into pendencias.filial_fora_8073 (codfilial, motivo) values
  ('11', 'Relatório da 8073 com todas as filiais não traz a filial 11 (BA, estoque de depósito fechado): conferido em dois relatórios do Júlio em 2026-10-29')
on conflict (codfilial) do nothing;

create or replace view pendencias.avaria_grupo as
select a.codfilial, a.codprod, a.descricao, a.embalagem, a.unidade, a.codfornec, a.qtindeniz, a.qtestger, a.qtbloqueada,
       a.valorultent, a.custoultent, a.custofin, a.dtultent,
       coalesce(nullif(f.codfornecprinc, 0), a.codfornec) as principal
  from pendencias.avaria a
  left join pendencias.fornecedor f on f.codfornec = a.codfornec
 where a.codfornec is not null
   and not exists (select 1 from pendencias.filial_fora_8073 x where x.codfilial = a.codfilial);

-- O detalhe ganha 'avaria_fora': a avaria das filiais que a 8073 não soma (mesmo grupo do código), só para informar.
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
                 'cd', coalesce(cc_debito, 0), 'cr', coalesce(cc_credito, 0), 'dq', dtquitacao, 'rl', rotinalanc)
               order by dtemissao desc nulls last, numverba desc), '[]')
               from pendencias.verba, eu where codfornec = p_codfornec and dtemissao between date '2011-01-01' and eu.hoje),
  'lancamentos', (select coalesce(json_agg(json_build_object(
                 'nt', numtranscrfor, 'fo', codfornec, 'fi', codfilial, 'dt', data, 'hr', hora, 'mi', minuto, 'ti', tipo, 'vl', valor,
                 'hi', historico, 'nv', numverba, 'np', numpedido, 'ne', numtransent, 'rl', rotinalanc,
                 'fu', funcionario, 'es', dtestorno, 'sd', saldo)
               order by numtranscrfor desc), '[]')
               from (select g.*, sum(case tipo when 'D' then valor when 'C' then -valor else 0 end)
                                   over (order by numtranscrfor) as saldo
                       from pendencias.lancamento_grupo g where g.codfornec = p_codfornec or g.principal = p_codfornec) z),
  'grupo', (select coalesce(json_agg(json_build_object('fo', codfornec, 'fn', fornecedor, 'sd', saldo, 'nl', n) order by codfornec), '[]')
              from (select g.codfornec, f.fornecedor, count(*) as n,
                           sum(case g.tipo when 'D' then g.valor when 'C' then -g.valor else 0 end) as saldo
                      from pendencias.lancamento_grupo g left join pendencias.fornecedor f on f.codfornec = g.codfornec
                     where g.codfornec = p_codfornec or g.principal = p_codfornec group by g.codfornec, f.fornecedor) z),
  'principal', (select case when e.principal <> p_codfornec then json_build_object(
                  'c', e.principal, 'n', (select fornecedor from pendencias.fornecedor where codfornec = e.principal),
                  'sf', (select sum(case tipo when 'D' then valor when 'C' then -valor else 0 end) from pendencias.lancamento_grupo
                          where codfornec = e.principal or principal = e.principal),
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
