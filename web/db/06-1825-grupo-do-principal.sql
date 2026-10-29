-- =============================================================================
-- PENDÊNCIAS FORNECEDOR — migração pendencias_09_1825_grupo_do_principal (2026-10-29). Roda depois do
-- 05-avaria-sem-filial-11.sql e troca a view lancamento_grupo, a montar_lista() e a detalhe() de lá.
--
-- A 1825 de um código mostra a conta corrente do GRUPO do principal dele no cadastro: tudo o que lançaram os
-- fornecedores que têm o mesmo principal (PCFORNEC.CODFORNECPRINC), o próprio principal incluído. Todo código do
-- grupo mostra o mesmo saldo. Conferido com a tela da rotina num código membro de um grupo grande (o valor dela é a
-- soma do grupo inteiro, ao centavo, com a foto do WinThor da hora do print), e continua batendo nos dois conferidos
-- antes (um principal com um membro; um membro sozinho no grupo, em que o valor do código e o do grupo são o mesmo).
-- Antes a regra era "o código + quem tem ele como principal": certa no principal, errada no membro de grupo grande.
--
-- "Todas as filiais" na rotina = as filiais do cadastro (PCFILIAL). A conta corrente tem lançamentos numa filial que
-- não existe no cadastro e a rotina não os soma: entram as filiais que o agente lê da PCFILIAL (fluxo
-- pendencias.filial, novo) e a tela mostra à parte o que ficou fora. Já são as do cadastro de hoje: a tabela nasce
-- com elas e o agente mantém.
--
-- A 8073 continua como estava (o código + quem tem ele como principal, sem a filial 11): nenhum relatório mostrou
-- ainda um membro de grupo com avaria nos outros fornecedores do grupo.
-- =============================================================================

create table if not exists pendencias.filial (
  codfilial   text primary key,
  razaosocial text
);
alter table pendencias.filial enable row level security;
comment on table pendencias.filial is
  'Filiais do cadastro do WinThor (PCFILIAL). A 1825 com todas as filiais soma só estas. Gravado pelo AGENTE LUBE.';

insert into pendencias.filial (codfilial) values
  ('1'), ('2'), ('3'), ('4'), ('5'), ('6'), ('7'), ('8'), ('9'), ('10'), ('11'), ('12'), ('50'), ('99')
on conflict (codfilial) do nothing;

insert into agente.fluxo (nome, sistema, descricao, destino, modo, colunas, chave, apagar, intervalo_s, sql, atualizado_por)
values ('pendencias.filial', 'pendencias',
        'Filiais do cadastro (PCFILIAL): a rotina 1825 com todas as filiais soma só estas',
        'pendencias.filial', 'chave', array['codfilial', 'razaosocial'], array['codfilial'], 'tudo', 600,
        E'SELECT codigo AS codfilial, razaosocial\n  FROM pcfilial\n',
        'migração pendencias_09 (Claude)')
on conflict (nome) do nothing;

create or replace view pendencias.lancamento_grupo as
select l.numtranscrfor, l.codfilial, l.data, l.hora, l.minuto, l.codfornec, l.tipo, l.valor, l.historico, l.numverba,
       l.numpedido, l.numtransent, l.rotinalanc, l.codfunc, l.funcionario, l.dtestorno,
       coalesce(nullif(f.codfornecprinc, 0), l.codfornec) as principal
  from pendencias.lancamento l
  left join pendencias.fornecedor f on f.codfornec = l.codfornec
 where l.data between date '2011-01-01' and (now() at time zone 'America/Sao_Paulo')::date
   and exists (select 1 from pendencias.filial fi where fi.codfilial = l.codfilial);

create or replace function pendencias.montar_lista()
returns json
language sql
stable
set search_path = pendencias, pg_temp
as $$
with h as (select (now() at time zone 'America/Sao_Paulo')::date as hoje),
v as (
  select codfornec, sum(pendencias.saldo_aplicar(valor, aplicado)) as sa, count(*) as nv,
         count(*) filter (where pendencias.saldo_aplicar(valor, aplicado) <> 0) as nva, max(dtemissao) as ult
    from pendencias.verba, h where dtemissao between date '2011-01-01' and h.hoje group by codfornec
),
-- 1825: lo = só o que o código lançou (o que os totais somam); lg = a conta do grupo do principal (o valor da rotina)
lo as (
  select codfornec, sum(case tipo when 'D' then valor when 'C' then -valor else 0 end) as sfo
    from pendencias.lancamento_grupo group by codfornec
),
lg as (
  select principal, sum(case tipo when 'D' then valor when 'C' then -valor else 0 end) as sfg, count(*) as nlg,
         count(distinct codfornec) as ngl, max(data) as ult
    from pendencias.lancamento_grupo group by principal
),
s as (select codfornec, sum(valor) as sg from pendencias.saldo group by codfornec),
ao as (
  select codfornec, sum(qtindeniz * valorultent) as avo, count(*) as npo, sum(qtindeniz) as qto
    from pendencias.avaria_grupo group by codfornec
),
am as (
  select principal as codfornec, sum(qtindeniz * valorultent) as avm, count(*) as npm, sum(qtindeniz) as qtm,
         count(distinct codfornec) as ngam
    from pendencias.avaria_grupo where principal <> codfornec group by principal
),
ids as (
  select codfornec from pendencias.fornecedor
  union select codfornec from v union select codfornec from lo union select principal from lg
  union select codfornec from s union select codfornec from ao union select codfornec from am
),
b as (
  select i.codfornec, f.codfornec as cad, f.fornecedor, f.fantasia, f.cnpj, f.uf, f.cidade, f.codcomprador, f.comprador,
         f.codfornecprinc, f.revenda, f.dtexclusao, f.bloqueio, coalesce(nullif(f.codfornecprinc, 0), i.codfornec) as pg
    from ids i left join pendencias.fornecedor f on f.codfornec = i.codfornec
),
x as (
  select b.codfornec, b.fornecedor, b.fantasia, b.cnpj, b.uf, b.cidade, b.codcomprador, b.comprador, b.codfornecprinc, b.pg,
         case when b.revenda = 'S' then 1 else 0 end as rv,
         case when b.cad is not null and b.dtexclusao is null then 1 else 0 end as at,
         case when b.bloqueio = 'S' then 1 else 0 end as bl,
         v.sa, coalesce(v.nva, 0) as nva, coalesce(v.nv, 0) as nv,
         lg.sfg as sf, lo.sfo, coalesce(lg.nlg, 0) as nl, coalesce(lg.ngl, 0) as ng,
         s.sg,
         case when ao.codfornec is null and am.codfornec is null then null else coalesce(ao.avo, 0) + coalesce(am.avm, 0) end as av,
         ao.avo, coalesce(ao.npo, 0) + coalesce(am.npm, 0) as npa,
         case when ao.codfornec is null and am.codfornec is null then null else coalesce(ao.qto, 0) + coalesce(am.qtm, 0) end as qta,
         (case when ao.codfornec is null then 0 else 1 end) + coalesce(am.ngam, 0) as nga,
         greatest(v.ult, lg.ult) as um,
         row_number() over (order by b.codfornec) as rn
    from b
    left join v on v.codfornec = b.codfornec
    left join lo on lo.codfornec = b.codfornec
    left join lg on lg.principal = b.pg
    left join s on s.codfornec = b.codfornec
    left join ao on ao.codfornec = b.codfornec
    left join am on am.codfornec = b.codfornec
)
select json_build_object(
  'meta', json_build_object(
     'hoje', to_char((select hoje from h), 'YYYY-MM-DD'),
     'desde', '2011-01-01',
     'desde_1825', '2011-01-01',
     'fornecedores', (select count(*) from x),
     'verbas', (select count(*) from pendencias.verba),
     'lancamentos', (select count(*) from pendencias.lancamento),
     'avarias', (select count(*) from pendencias.avaria)),
  'r', json_build_object(
     'n',   (select count(*) from x),
     'c',   (select coalesce(json_agg(codfornec order by rn), '[]') from x),
     'n_',  (select coalesce(json_agg(fornecedor order by rn), '[]') from x),
     'fa',  (select coalesce(json_agg(fantasia order by rn), '[]') from x),
     'cj',  (select coalesce(json_agg(cnpj order by rn), '[]') from x),
     'uf',  (select coalesce(json_agg(uf order by rn), '[]') from x),
     'ci',  (select coalesce(json_agg(cidade order by rn), '[]') from x),
     'cc',  (select coalesce(json_agg(codcomprador order by rn), '[]') from x),
     'cp',  (select coalesce(json_agg(comprador order by rn), '[]') from x),
     'pr',  (select coalesce(json_agg(codfornecprinc order by rn), '[]') from x),
     'pg',  (select coalesce(json_agg(pg order by rn), '[]') from x),
     'rv',  (select coalesce(json_agg(rv order by rn), '[]') from x),
     'at',  (select coalesce(json_agg(at order by rn), '[]') from x),
     'bl',  (select coalesce(json_agg(bl order by rn), '[]') from x),
     'sa',  (select coalesce(json_agg(trim_scale(round(sa, 6)) order by rn), '[]') from x),
     'nva', (select coalesce(json_agg(nva order by rn), '[]') from x),
     'nv',  (select coalesce(json_agg(nv order by rn), '[]') from x),
     'sf',  (select coalesce(json_agg(trim_scale(round(sf, 6)) order by rn), '[]') from x),
     'sfo', (select coalesce(json_agg(trim_scale(round(sfo, 6)) order by rn), '[]') from x),
     'ng',  (select coalesce(json_agg(ng order by rn), '[]') from x),
     'sg',  (select coalesce(json_agg(trim_scale(round(sg, 6)) order by rn), '[]') from x),
     'nl',  (select coalesce(json_agg(nl order by rn), '[]') from x),
     'av',  (select coalesce(json_agg(trim_scale(round(av, 6)) order by rn), '[]') from x),
     'avo', (select coalesce(json_agg(trim_scale(round(avo, 6)) order by rn), '[]') from x),
     'nga', (select coalesce(json_agg(nga order by rn), '[]') from x),
     'npa', (select coalesce(json_agg(npa order by rn), '[]') from x),
     'qta', (select coalesce(json_agg(trim_scale(qta) order by rn), '[]') from x),
     'um',  (select coalesce(json_agg(um order by rn), '[]') from x)
  )
);
$$;

-- O detalhe de um código X: lancamentos e grupo = a conta do grupo do principal P de X (todo fornecedor com P como
-- principal, P incluído); lancamento_fora = o que o grupo lançou em filial fora do cadastro (a rotina não soma).
-- A 8073 (avaria, avaria_grupo, avaria_fora) e o 'principal' seguem como na migração 08.
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
