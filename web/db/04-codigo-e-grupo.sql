-- =============================================================================
-- PENDÊNCIAS FORNECEDOR — migração pendencias_07_codigo_e_grupo (2026-10-29). Roda depois do 03-avaria-grupo.sql
-- e troca a montar_lista() e a detalhe() de lá.
--
-- A 1825 de um código que tem outro fornecedor como principal mostra os lançamentos DELE (o Júlio conferiu: "o valor
-- do 1825 tá batendo"), e a do principal soma os dele e os do grupo. Regra das rotinas 1825 e 8073 para
-- um código X: o que X lançou + o que lançaram os fornecedores que têm X como principal no cadastro. Um código que é
-- membro de um grupo mostra o seu valor (antes o painel escrevia "No principal X"). Como o membro aparece no código dele e
-- de novo no principal, a soma das linhas repete o grupo: os totais do painel usam o valor só do código (sfo, avo), em
-- que cada lançamento e cada produto entram uma vez.
-- Período fixo da 1809 e da 1825 (Júlio): de 01/01/2011 até hoje (o dia de Brasília, que anda sozinho); sempre todas as
-- filiais. A 8073 é a foto do estoque de agora (sem período).
-- =============================================================================

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
lo as (
  select codfornec, sum(case tipo when 'D' then valor when 'C' then -valor else 0 end) as sfo, count(*) as nlo, max(data) as ult
    from pendencias.lancamento_grupo group by codfornec
),
lm as (
  select principal as codfornec, sum(case tipo when 'D' then valor when 'C' then -valor else 0 end) as sfm, count(*) as nlm,
         count(distinct codfornec) as ngm, max(data) as ult
    from pendencias.lancamento_grupo where principal <> codfornec group by principal
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
  union select codfornec from v union select codfornec from lo union select codfornec from lm
  union select codfornec from s union select codfornec from ao union select codfornec from am
),
x as (
  select i.codfornec, f.fornecedor, f.fantasia, f.cnpj, f.uf, f.cidade, f.codcomprador, f.comprador, f.codfornecprinc,
         coalesce(nullif(f.codfornecprinc, 0), i.codfornec) as pg,
         case when f.revenda = 'S' then 1 else 0 end as rv,
         case when f.codfornec is not null and f.dtexclusao is null then 1 else 0 end as at,
         case when f.bloqueio = 'S' then 1 else 0 end as bl,
         v.sa, coalesce(v.nva, 0) as nva, coalesce(v.nv, 0) as nv,
         case when lo.codfornec is null and lm.codfornec is null then null else coalesce(lo.sfo, 0) + coalesce(lm.sfm, 0) end as sf,
         lo.sfo, coalesce(lo.nlo, 0) + coalesce(lm.nlm, 0) as nl,
         (case when lo.codfornec is null then 0 else 1 end) + coalesce(lm.ngm, 0) as ng,
         s.sg,
         case when ao.codfornec is null and am.codfornec is null then null else coalesce(ao.avo, 0) + coalesce(am.avm, 0) end as av,
         ao.avo, coalesce(ao.npo, 0) + coalesce(am.npm, 0) as npa,
         case when ao.codfornec is null and am.codfornec is null then null else coalesce(ao.qto, 0) + coalesce(am.qtm, 0) end as qta,
         (case when ao.codfornec is null then 0 else 1 end) + coalesce(am.ngam, 0) as nga,
         greatest(v.ult, lo.ult, lm.ult) as um,
         row_number() over (order by i.codfornec) as rn
    from ids i
    left join pendencias.fornecedor f on f.codfornec = i.codfornec
    left join v on v.codfornec = i.codfornec
    left join lo on lo.codfornec = i.codfornec
    left join lm on lm.codfornec = i.codfornec
    left join s on s.codfornec = i.codfornec
    left join ao on ao.codfornec = i.codfornec
    left join am on am.codfornec = i.codfornec
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

-- O detalhe de um código X: lancamentos e avaria = os de X + os dos fornecedores que têm X como principal (com o
-- fornecedor de cada linha); grupo / avaria_grupo = quanto cada um soma; principal = se X tem OUTRO principal P, o valor
-- de P (P + o grupo de P), só para informar.
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
  'lido', (select coalesce(json_object_agg(fluxo, json_build_object('lido_em', lido_em, 'mudou_em', mudou_em, 'status', status)), '{}')
             from agente.estado where fluxo like 'pendencias.%')
);
$$;

select pendencias.atualizar_pacote();
