-- =============================================================================
-- PENDÊNCIAS FORNECEDOR — migração pendencias_11_avaria_sem_filial_7 (2026-10-30). Roda depois do
-- 07-1809-canceladas-e-centavo.sql e troca a montar_lista() da 06.
--
-- O "Total Valor" da última folha da 8073 de um principal com grupo grande (relatório do Júlio, todas as filiais) é a
-- avaria do grupo SÓ na filial 1: o painel tinha a mais um produto da filial 7. Como a 11, a 7 sai da conta (a lista
-- mora em pendencias.filial_fora_8073). Nos três relatórios conferidos até aqui o total é sempre o da filial 1; a 12 fica
-- dentro até um relatório de um fornecedor com avaria só na 12 dizer o contrário.
-- O pacote da lista passa a levar a lista das filiais fora da 8073 (meta.fora_8073), para a tela não escrever na mão.
-- =============================================================================

insert into pendencias.filial_fora_8073 (codfilial, motivo) values
  ('7', 'Relatório da 8073 com todas as filiais não traz a filial 7: o total de um principal com grupo grande é o da filial 1 ao centavo (2026-10-30)')
on conflict (codfilial) do nothing;

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
     'fora_8073', (select coalesce(json_agg(codfilial order by length(codfilial), codfilial), '[]') from pendencias.filial_fora_8073),
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

select pendencias.atualizar_pacote();
