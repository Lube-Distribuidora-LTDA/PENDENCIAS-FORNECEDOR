-- =============================================================================
-- PENDÊNCIAS FORNECEDOR — migração pendencias_04_avaria_grupo (2026-10-28). Roda depois do 02-saldo-final-grupo.sql
-- e troca a montar_lista() e a detalhe() de lá.
--
-- Rotina 8073 conferida com o Júlio: o relatório de um fornecedor de exemplo (3 folhas) bateu ao centavo com a avaria
-- do GRUPO do fornecedor principal do cadastro (ele + um segundo código que tem ele como principal), QTINDENIZ ×
-- VALORULTENT somados sem arredondar linha a linha — o relatório saiu só com a filial 1. Regra do Júlio: "TODOS OS
-- RELATÓRIOS VOCÊ PRECISA PUXAR SEMPRE DE TODAS AS FILIAIS". Então a avaria fica como a 1825: no principal do
-- fornecedor do produto, todas as filiais, cada linha uma vez só.
-- =============================================================================

create or replace view pendencias.avaria_grupo as
select a.*, coalesce(nullif(f.codfornecprinc, 0), a.codfornec) as principal
  from pendencias.avaria a
  left join pendencias.fornecedor f on f.codfornec = a.codfornec
 where a.codfornec is not null;
comment on view pendencias.avaria_grupo is
  'Avaria (8073) com o fornecedor principal do cadastro: o valor avaria de um código soma os produtos de todo fornecedor que tem ele como principal, todas as filiais.';
revoke all on pendencias.avaria_grupo from public;
do $$ begin if exists (select 1 from pg_roles where rolname = 'anon') then revoke all on pendencias.avaria_grupo from anon, authenticated; end if; end $$;

-- A lista: av = avaria do grupo (no principal); avp = a avaria de um fornecedor de OUTRO principal (vai para o principal);
-- nga = quantos fornecedores somam avaria no código. O resto como no 02.
create or replace function pendencias.montar_lista()
returns json
language sql
stable
set search_path = pendencias, pg_temp
as $$
with v as (
  select codfornec, sum(pendencias.saldo_aplicar(valor, aplicado)) as sa, count(*) as nv,
         count(*) filter (where pendencias.saldo_aplicar(valor, aplicado) <> 0) as nva, max(dtemissao) as ult
    from pendencias.verba group by codfornec
),
l as (
  select principal as codfornec, sum(case tipo when 'D' then valor when 'C' then -valor else 0 end) as sf, count(*) as nl,
         count(distinct codfornec) as ng, max(data) as ult
    from pendencias.lancamento_grupo group by principal
),
lp as (
  select codfornec, sum(case tipo when 'D' then valor when 'C' then -valor else 0 end) as sfp
    from pendencias.lancamento_grupo where principal <> codfornec group by codfornec
),
s as (select codfornec, sum(valor) as sg from pendencias.saldo group by codfornec),
a as (
  select principal as codfornec, sum(qtindeniz * valorultent) as av, count(*) as npa, sum(qtindeniz) as qta,
         count(distinct codfornec) as nga
    from pendencias.avaria_grupo group by principal
),
ap as (
  select codfornec, sum(qtindeniz * valorultent) as avp
    from pendencias.avaria_grupo where principal <> codfornec group by codfornec
),
ids as (
  select codfornec from pendencias.fornecedor
  union select codfornec from v union select codfornec from l union select codfornec from lp
  union select codfornec from s union select codfornec from a union select codfornec from ap
),
x as (
  select i.codfornec, f.fornecedor, f.fantasia, f.cnpj, f.uf, f.cidade, f.codcomprador, f.comprador, f.codfornecprinc,
         coalesce(nullif(f.codfornecprinc, 0), i.codfornec) as pg,
         case when f.revenda = 'S' then 1 else 0 end as rv,
         case when f.codfornec is not null and f.dtexclusao is null then 1 else 0 end as at,
         case when f.bloqueio = 'S' then 1 else 0 end as bl,
         v.sa, coalesce(v.nva, 0) as nva, coalesce(v.nv, 0) as nv,
         l.sf, lp.sfp, coalesce(l.ng, 0) as ng, s.sg, coalesce(l.nl, 0) as nl,
         a.av, ap.avp, coalesce(a.nga, 0) as nga, coalesce(a.npa, 0) as npa, a.qta,
         greatest(v.ult, l.ult) as um,
         row_number() over (order by i.codfornec) as rn
    from ids i
    left join pendencias.fornecedor f on f.codfornec = i.codfornec
    left join v on v.codfornec = i.codfornec
    left join l on l.codfornec = i.codfornec
    left join lp on lp.codfornec = i.codfornec
    left join s on s.codfornec = i.codfornec
    left join a on a.codfornec = i.codfornec
    left join ap on ap.codfornec = i.codfornec
)
select json_build_object(
  'meta', json_build_object(
     'hoje', to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD'),
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
     'sfp', (select coalesce(json_agg(trim_scale(round(sfp, 6)) order by rn), '[]') from x),
     'ng',  (select coalesce(json_agg(ng order by rn), '[]') from x),
     'sg',  (select coalesce(json_agg(trim_scale(round(sg, 6)) order by rn), '[]') from x),
     'nl',  (select coalesce(json_agg(nl order by rn), '[]') from x),
     'av',  (select coalesce(json_agg(trim_scale(round(av, 6)) order by rn), '[]') from x),
     'avp', (select coalesce(json_agg(trim_scale(round(avp, 6)) order by rn), '[]') from x),
     'nga', (select coalesce(json_agg(nga order by rn), '[]') from x),
     'npa', (select coalesce(json_agg(npa order by rn), '[]') from x),
     'qta', (select coalesce(json_agg(trim_scale(qta) order by rn), '[]') from x),
     'um',  (select coalesce(json_agg(um order by rn), '[]') from x)
  )
);
$$;

-- O detalhe: avaria = os produtos do grupo do código (com o fornecedor de cada produto); avaria_grupo = quanto cada
-- fornecedor do grupo soma; avaria_proprios = quando o principal do código é OUTRO. O resto como no 02.
create or replace function pendencias.detalhe(p_codfornec bigint)
returns json
language sql
stable
set search_path = pendencias, pg_temp
as $$
with eu as (
  select coalesce(nullif(f.codfornecprinc, 0), p_codfornec) as principal
    from (select 1) x left join pendencias.fornecedor f on f.codfornec = p_codfornec
)
select json_build_object(
  'fornecedor', (select row_to_json(f) from pendencias.fornecedor f where f.codfornec = p_codfornec),
  'periodo_1825', json_build_object('desde', '2011-01-01', 'ate', to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD')),
  'verbas', (select coalesce(json_agg(json_build_object(
                 'nv', numverba, 'fi', codfilial, 'em', dtemissao, 've', dtvenc, 'ti', tipo, 'fp', formapgto,
                 'rf', referencia, 'nn', numnota, 'np', numped, 'vl', valor, 'ap', coalesce(aplicado, 0),
                 'sa', pendencias.saldo_aplicar(valor, aplicado), 'qa', coalesce(qtaplic, 0), 'ua', ult_aplic,
                 'cd', coalesce(cc_debito, 0), 'cr', coalesce(cc_credito, 0), 'dq', dtquitacao, 'rl', rotinalanc)
               order by dtemissao desc nulls last, numverba desc), '[]')
               from pendencias.verba where codfornec = p_codfornec),
  'lancamentos', (select coalesce(json_agg(json_build_object(
                 'nt', numtranscrfor, 'fo', codfornec, 'fi', codfilial, 'dt', data, 'hr', hora, 'mi', minuto, 'ti', tipo, 'vl', valor,
                 'hi', historico, 'nv', numverba, 'np', numpedido, 'ne', numtransent, 'rl', rotinalanc,
                 'fu', funcionario, 'es', dtestorno, 'sd', saldo)
               order by numtranscrfor desc), '[]')
               from (select g.*, sum(case tipo when 'D' then valor when 'C' then -valor else 0 end)
                                   over (order by numtranscrfor) as saldo
                       from pendencias.lancamento_grupo g where principal = p_codfornec) z),
  'grupo', (select coalesce(json_agg(json_build_object('fo', codfornec, 'fn', fornecedor, 'sd', saldo, 'nl', n) order by codfornec), '[]')
              from (select g.codfornec, f.fornecedor, count(*) as n,
                           sum(case g.tipo when 'D' then g.valor when 'C' then -g.valor else 0 end) as saldo
                      from pendencias.lancamento_grupo g left join pendencias.fornecedor f on f.codfornec = g.codfornec
                     where g.principal = p_codfornec group by g.codfornec, f.fornecedor) z),
  'principal', (select case when e.principal <> p_codfornec then json_build_object(
                  'c', e.principal, 'n', (select fornecedor from pendencias.fornecedor where codfornec = e.principal),
                  'sf', (select sum(case tipo when 'D' then valor when 'C' then -valor else 0 end) from pendencias.lancamento_grupo where principal = e.principal),
                  'av', (select sum(qtindeniz * valorultent) from pendencias.avaria_grupo where principal = e.principal))
                end from eu e),
  'proprios', (select coalesce(json_agg(json_build_object(
                 'nt', numtranscrfor, 'fo', codfornec, 'fi', codfilial, 'dt', data, 'hr', hora, 'mi', minuto, 'ti', tipo, 'vl', valor,
                 'hi', historico, 'nv', numverba, 'np', numpedido, 'ne', numtransent, 'rl', rotinalanc,
                 'fu', funcionario, 'es', dtestorno, 'sd', saldo)
               order by numtranscrfor desc), '[]')
               from (select g.*, sum(case tipo when 'D' then valor when 'C' then -valor else 0 end)
                                   over (order by numtranscrfor) as saldo
                       from pendencias.lancamento_grupo g where codfornec = p_codfornec and principal <> p_codfornec) z),
  'saldos', (select coalesce(json_agg(json_build_object('fi', codfilial, 'vl', valor, 'vc', valorconciliado, 'dc', dtultconcilia)
               order by codfilial), '[]')
               from pendencias.saldo where codfornec = p_codfornec),
  'avaria', (select coalesce(json_agg(json_build_object(
                 'fo', codfornec, 'fi', codfilial, 'cp', codprod, 'ds', descricao, 'em', embalagem, 'un', unidade, 'qt', qtindeniz,
                 'qe', qtestger, 'qb', qtbloqueada, 'vu', valorultent, 'cu', custoultent, 'cf', custofin, 'de', dtultent,
                 'va', qtindeniz * valorultent)
               order by qtindeniz * valorultent desc nulls last), '[]')
               from pendencias.avaria_grupo where principal = p_codfornec),
  'avaria_grupo', (select coalesce(json_agg(json_build_object('fo', codfornec, 'fn', fornecedor, 'va', valor, 'np', n) order by codfornec), '[]')
              from (select g.codfornec, f.fornecedor, count(*) as n, sum(g.qtindeniz * g.valorultent) as valor
                      from pendencias.avaria_grupo g left join pendencias.fornecedor f on f.codfornec = g.codfornec
                     where g.principal = p_codfornec group by g.codfornec, f.fornecedor) z),
  'avaria_proprios', (select coalesce(json_agg(json_build_object(
                 'fo', codfornec, 'fi', codfilial, 'cp', codprod, 'ds', descricao, 'em', embalagem, 'un', unidade, 'qt', qtindeniz,
                 'qe', qtestger, 'qb', qtbloqueada, 'vu', valorultent, 'cu', custoultent, 'cf', custofin, 'de', dtultent,
                 'va', qtindeniz * valorultent)
               order by qtindeniz * valorultent desc nulls last), '[]')
               from pendencias.avaria_grupo where codfornec = p_codfornec and principal <> p_codfornec),
  'lido', (select coalesce(json_object_agg(fluxo, json_build_object('lido_em', lido_em, 'mudou_em', mudou_em, 'status', status)), '{}')
             from agente.estado where fluxo like 'pendencias.%')
);
$$;

select pendencias.atualizar_pacote();
