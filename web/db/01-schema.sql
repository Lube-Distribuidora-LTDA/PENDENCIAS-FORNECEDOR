-- =============================================================================
-- PENDÊNCIAS FORNECEDOR — schema `pendencias` no DATA WAREHOUSE (migração pendencias_01_schema)
-- 2026-10-28. O que cada fornecedor tem pendente com a Lube, nas três rotinas do WinThor que o
-- Júlio pediu, com o AGENTE LUBE mantendo os dados ao vivo:
--   SALDO A APLICAR  rotina 1809 "Relação de verbas por fornecedor": a verba (PCVERBA) menos o
--                    que já foi aplicado (PCAPLICVERBA; o estorno vem como linha negativa).
--   SALDO FINAL      rotina 1825 "Débito e crédito de fornecedor": a conta corrente (PCMOVCRFOR),
--                    débitos (D) − créditos (C) de todo o histórico, estornos inclusos. O saldo que
--                    o WinThor guarda (PCESTCRFOR) vem ao lado, para a conferência.
--   VALOR AVARIA     rotina 8073 "AVARIA 2": estoque avariado (PCEST.QTINDENIZ) × valor da
--                    última entrada, por filial e produto.
--
-- Onde o dado nasce: o AGENTE LUBE (Desktop\BI\22. AGENTE LUBE, fluxos/pendencias.toml) lê as
-- tabelas inteiras no WinThor (são pequenas: 11,6 mil verbas, 43 mil lançamentos, 3,7 mil linhas
-- de avaria, 10,5 mil fornecedores) e grava só o que mudou. Depois de gravar ele roda
-- pendencias.atualizar_pacote() (agente.sistema.apos_gravar), que refaz o pacote da lista.
--
-- O painel não lê as tabelas ao abrir: lê o pacote pronto (um resumo por fornecedor). O detalhe
-- de um fornecedor (pendencias.detalhe) é lido na hora, só daquele fornecedor; antes, o painel
-- pede ao agente uma leitura do WinThor (agente.pedir_atualizacao('pendencias')).
--
-- Migrações no banco: pendencias_01_schema e pendencias_02_saldo_sem_residuo (2026-10-28: o saldo a
-- aplicar abaixo de meio centavo, resíduo das 6 casas do PCAPLICVERBA.VLAPLIC, conta como zero) — este
-- arquivo é o estado das duas — e pendencias_03_saldo_final_grupo (02-saldo-final-grupo.sql, roda depois:
-- o saldo final da 1825 no grupo do fornecedor principal, todas as filiais, 01/01/2011 até hoje).
-- =============================================================================

create schema if not exists pendencias;
comment on schema pendencias is
  'PENDÊNCIAS FORNECEDOR (saldo a aplicar 1809, saldo final 1825, avaria 8073). Gravado pelo AGENTE LUBE; painel em Desktop\BI\24. PENDENCIAS FORNECEDOR.';

-- ----------------------------------------------------------------------------- 1809: verbas
create table if not exists pendencias.verba (
  numverba     bigint primary key,
  codfilial    text,
  codfornec    bigint not null,
  dtemissao    date,
  dtvenc       date,
  dtcadastro   timestamp,
  tipo         text,                 -- PCVERBA.TIPO
  formapgto    text,                 -- PCVERBA.FORMAPGTO (D dinheiro, M mercadoria)
  referencia   text,                 -- REFERENCIA + REFERENCIA1
  numnota      bigint,
  numped       bigint,
  codcomprador integer,
  valor        numeric,              -- valor da verba
  aplicado     numeric,              -- Σ PCAPLICVERBA.VLAPLIC (estorno é linha negativa): aplicado líquido
  qtaplic      integer,              -- linhas de aplicação (com estornos)
  ult_aplic    date,
  cc_debito    numeric,              -- Σ PCMOVCRFOR tipo D desta verba
  cc_credito   numeric,              -- Σ PCMOVCRFOR tipo C desta verba
  dtquitacao   date,
  rotinalanc   integer
);
create index if not exists ix_verba_fornec on pendencias.verba (codfornec);
alter table pendencias.verba enable row level security;
comment on table pendencias.verba is
  'Rotina 1809: verbas não canceladas, com o aplicado (PCAPLICVERBA) e o movimento na conta corrente. Saldo a aplicar = valor − aplicado. Gravado pelo AGENTE LUBE.';

-- ----------------------------------------------------------------------------- 1825: conta corrente
create table if not exists pendencias.lancamento (
  numtranscrfor bigint primary key,
  codfilial     text,
  data          date,
  hora          smallint,
  minuto        smallint,
  codfornec     bigint not null,
  tipo          text,                -- D débito (o fornecedor passa a dever) | C crédito (abatido)
  valor         numeric,
  historico     text,
  numverba      bigint,
  numpedido     bigint,
  numtransent   bigint,
  rotinalanc    integer,
  codfunc       integer,
  funcionario   text,                -- quem lançou
  dtestorno     date
);
create index if not exists ix_lancamento_fornec on pendencias.lancamento (codfornec, numtranscrfor);
alter table pendencias.lancamento enable row level security;
comment on table pendencias.lancamento is
  'Rotina 1825: conta corrente do fornecedor (PCMOVCRFOR), todos os lançamentos. Saldo final = Σ D − Σ C, estornos inclusos. Gravado pelo AGENTE LUBE.';

create table if not exists pendencias.saldo (
  codfornec       bigint not null,
  codfilial       text not null,
  valor           numeric,           -- PCESTCRFOR.VALOR: o saldo que o WinThor guarda
  valorconciliado numeric,
  dtultconcilia   timestamp,
  primary key (codfornec, codfilial)
);
alter table pendencias.saldo enable row level security;
comment on table pendencias.saldo is
  'Saldo da conta corrente guardado pelo WinThor (PCESTCRFOR), por fornecedor e filial. Em 2026-10-28 batia com a soma dos lançamentos em só metade dos fornecedores: fica para a conferência da 1825.';

-- ----------------------------------------------------------------------------- 8073: avaria
create table if not exists pendencias.avaria (
  codfilial   text not null,
  codprod     bigint not null,
  descricao   text,
  embalagem   text,
  unidade     text,
  codfornec   bigint,
  qtindeniz   numeric,               -- quantidade avariada
  qtestger    numeric,
  qtbloqueada numeric,
  valorultent numeric,               -- valor da última entrada (o que valoriza a avaria)
  custoultent numeric,
  custofin    numeric,
  dtultent    date,
  primary key (codfilial, codprod)
);
create index if not exists ix_avaria_fornec on pendencias.avaria (codfornec);
alter table pendencias.avaria enable row level security;
comment on table pendencias.avaria is
  'Rotina 8073 (AVARIA 2): estoque avariado (PCEST.QTINDENIZ > 0) por filial e produto. Valor avaria = QTINDENIZ × VALORULTENT. Gravado pelo AGENTE LUBE.';

-- ----------------------------------------------------------------------------- cadastro
create table if not exists pendencias.fornecedor (
  codfornec            bigint primary key,
  fornecedor           text,
  fantasia             text,
  cnpj                 text,         -- só pessoa jurídica (CPF de pessoa física não vem)
  cidade               text,
  uf                   text,
  codfornecprinc       bigint,
  fornecedor_principal text,
  codcomprador         integer,
  comprador            text,
  revenda              text,
  bloqueio             text,
  dtexclusao           date,
  dtcadastro           date
);
alter table pendencias.fornecedor enable row level security;
comment on table pendencias.fornecedor is
  'Cadastro de fornecedores (PCFORNEC), todos, com o principal e o comprador. Gravado pelo AGENTE LUBE.';

-- ----------------------------------------------------------------------------- o pacote da lista
create table if not exists pendencias.pacote (
  nome       text primary key check (nome in ('lista')),
  versao     text not null,
  hash       text not null,
  gerado_em  timestamptz not null default now(),
  linhas     integer,
  bytes_json integer,
  ms         integer,
  payload    text not null
);
alter table pendencias.pacote enable row level security;
comment on table pendencias.pacote is
  'Pacote pronto do painel: um resumo por fornecedor, em colunas (JSON em texto; a API comprime ao entregar).';

-- Saldo a aplicar de uma verba: resíduo abaixo de meio centavo conta como zero (sem isto o cartão somava
-- -R$ 0,01 de frações que a tabela "com saldo" não mostra).
create or replace function pendencias.saldo_aplicar(p_valor numeric, p_aplicado numeric)
returns numeric language sql immutable
as $$ select case when abs(coalesce(p_valor, 0) - coalesce(p_aplicado, 0)) < 0.005 then 0 else coalesce(p_valor, 0) - coalesce(p_aplicado, 0) end $$;

-- Um fornecedor por posição, em colunas. Valores cheios: arredondar só na tela.
--   c código · n nome · fa fantasia · cj CNPJ · uf · ci cidade · cc/cp comprador · pr fornecedor principal
--   rv revenda (1/0) · at ativo (sem exclusão, 1/0) · bl bloqueado (1/0)
--   sa saldo a aplicar (1809) · nva verbas com saldo a aplicar · nv verbas
--   sf saldo final (1825, Σ D − Σ C) · sg saldo guardado (PCESTCRFOR) · nl lançamentos
--   av valor avaria (8073) · npa produtos avariados · qta quantidade avariada · um último movimento
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
  select codfornec, sum(case tipo when 'D' then valor when 'C' then -valor else 0 end) as sf, count(*) as nl, max(data) as ult
    from pendencias.lancamento group by codfornec
),
s as (select codfornec, sum(valor) as sg from pendencias.saldo group by codfornec),
a as (
  select codfornec, sum(qtindeniz * valorultent) as av, count(*) as npa, sum(qtindeniz) as qta
    from pendencias.avaria where codfornec is not null group by codfornec
),
ids as (
  select codfornec from pendencias.fornecedor
  union select codfornec from v union select codfornec from l union select codfornec from s union select codfornec from a
),
x as (
  select i.codfornec, f.fornecedor, f.fantasia, f.cnpj, f.uf, f.cidade, f.codcomprador, f.comprador, f.codfornecprinc,
         case when f.revenda = 'S' then 1 else 0 end as rv,
         case when f.codfornec is not null and f.dtexclusao is null then 1 else 0 end as at,
         case when f.bloqueio = 'S' then 1 else 0 end as bl,
         v.sa, coalesce(v.nva, 0) as nva, coalesce(v.nv, 0) as nv,
         l.sf, s.sg, coalesce(l.nl, 0) as nl,
         a.av, coalesce(a.npa, 0) as npa, a.qta,
         greatest(v.ult, l.ult) as um,
         row_number() over (order by i.codfornec) as rn
    from ids i
    left join pendencias.fornecedor f on f.codfornec = i.codfornec
    left join v on v.codfornec = i.codfornec
    left join l on l.codfornec = i.codfornec
    left join s on s.codfornec = i.codfornec
    left join a on a.codfornec = i.codfornec
)
select json_build_object(
  'meta', json_build_object(
     'hoje', to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD'),
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
     'rv',  (select coalesce(json_agg(rv order by rn), '[]') from x),
     'at',  (select coalesce(json_agg(at order by rn), '[]') from x),
     'bl',  (select coalesce(json_agg(bl order by rn), '[]') from x),
     'sa',  (select coalesce(json_agg(trim_scale(round(sa, 6)) order by rn), '[]') from x),
     'nva', (select coalesce(json_agg(nva order by rn), '[]') from x),
     'nv',  (select coalesce(json_agg(nv order by rn), '[]') from x),
     'sf',  (select coalesce(json_agg(trim_scale(round(sf, 6)) order by rn), '[]') from x),
     'sg',  (select coalesce(json_agg(trim_scale(round(sg, 6)) order by rn), '[]') from x),
     'nl',  (select coalesce(json_agg(nl order by rn), '[]') from x),
     'av',  (select coalesce(json_agg(trim_scale(round(av, 6)) order by rn), '[]') from x),
     'npa', (select coalesce(json_agg(npa order by rn), '[]') from x),
     'qta', (select coalesce(json_agg(trim_scale(qta) order by rn), '[]') from x),
     'um',  (select coalesce(json_agg(um order by rn), '[]') from x)
  )
);
$$;
comment on function pendencias.montar_lista() is
  'Pacote da lista do painel Pendências Fornecedor: um resumo por fornecedor (saldo a aplicar, saldo final, avaria), em colunas.';

-- Quem chama: o AGENTE LUBE depois de gravar (agente.sistema.apos_gravar) e o botão Atualizar.
-- Só troca a versão se o conteúdo mudou (o navegador só baixa de novo quando a versão muda).
create or replace function pendencias.atualizar_pacote()
returns text
language plpgsql
set search_path = pendencias, pg_temp
as $$
declare
  v_ini  timestamptz := clock_timestamp();
  v_json text;
  v_hash text;
begin
  v_json := pendencias.montar_lista()::text;
  v_hash := md5(v_json);
  if exists (select 1 from pendencias.pacote where nome = 'lista' and hash = v_hash) then
    return 'nada mudou';
  end if;
  insert into pendencias.pacote (nome, versao, hash, gerado_em, linhas, bytes_json, ms, payload)
  values ('lista', to_char(clock_timestamp() at time zone 'America/Sao_Paulo', 'YYYYMMDD-HH24MISS-MS'), v_hash, now(),
          (v_json::json -> 'r' ->> 'n')::int, octet_length(v_json),
          (extract(epoch from (clock_timestamp() - v_ini)) * 1000)::int, v_json)
  on conflict (nome) do update set versao = excluded.versao, hash = excluded.hash, gerado_em = excluded.gerado_em,
         linhas = excluded.linhas, bytes_json = excluded.bytes_json, ms = excluded.ms, payload = excluded.payload;
  return 'lista refeita';
end;
$$;
comment on function pendencias.atualizar_pacote() is
  'Remonta o pacote da lista do painel Pendências Fornecedor, se mudou. Quem chama: o AGENTE LUBE depois de gravar no schema pendencias.';

-- ----------------------------------------------------------------------------- o detalhe de um fornecedor
-- As três rotinas, cada uma com as suas linhas, e quando o agente leu cada fluxo no WinThor.
-- Na conta corrente, o saldo corrido vai na ordem da transação (NUMTRANSCRFOR), como a 1825 lista.
create or replace function pendencias.detalhe(p_codfornec bigint)
returns json
language sql
stable
set search_path = pendencias, pg_temp
as $$
select json_build_object(
  'fornecedor', (select row_to_json(f) from pendencias.fornecedor f where f.codfornec = p_codfornec),
  'verbas', (select coalesce(json_agg(json_build_object(
                 'nv', numverba, 'fi', codfilial, 'em', dtemissao, 've', dtvenc, 'ti', tipo, 'fp', formapgto,
                 'rf', referencia, 'nn', numnota, 'np', numped, 'vl', valor, 'ap', coalesce(aplicado, 0),
                 'sa', pendencias.saldo_aplicar(valor, aplicado), 'qa', coalesce(qtaplic, 0), 'ua', ult_aplic,
                 'cd', coalesce(cc_debito, 0), 'cr', coalesce(cc_credito, 0), 'dq', dtquitacao, 'rl', rotinalanc)
               order by dtemissao desc nulls last, numverba desc), '[]')
               from pendencias.verba where codfornec = p_codfornec),
  'lancamentos', (select coalesce(json_agg(json_build_object(
                 'nt', numtranscrfor, 'fi', codfilial, 'dt', data, 'hr', hora, 'mi', minuto, 'ti', tipo, 'vl', valor,
                 'hi', historico, 'nv', numverba, 'np', numpedido, 'ne', numtransent, 'rl', rotinalanc,
                 'fu', funcionario, 'es', dtestorno, 'sd', saldo)
               order by numtranscrfor desc), '[]')
               from (select l.*, sum(case tipo when 'D' then valor when 'C' then -valor else 0 end)
                                   over (order by numtranscrfor) as saldo
                       from pendencias.lancamento l where codfornec = p_codfornec) z),
  'saldos', (select coalesce(json_agg(json_build_object('fi', codfilial, 'vl', valor, 'vc', valorconciliado, 'dc', dtultconcilia)
               order by codfilial), '[]')
               from pendencias.saldo where codfornec = p_codfornec),
  'avaria', (select coalesce(json_agg(json_build_object(
                 'fi', codfilial, 'cp', codprod, 'ds', descricao, 'em', embalagem, 'un', unidade, 'qt', qtindeniz,
                 'qe', qtestger, 'qb', qtbloqueada, 'vu', valorultent, 'cu', custoultent, 'cf', custofin, 'de', dtultent,
                 'va', qtindeniz * valorultent)
               order by qtindeniz * valorultent desc nulls last), '[]')
               from pendencias.avaria where codfornec = p_codfornec),
  'lido', (select coalesce(json_object_agg(fluxo, json_build_object('lido_em', lido_em, 'mudou_em', mudou_em, 'status', status)), '{}')
             from agente.estado where fluxo like 'pendencias.%')
);
$$;
comment on function pendencias.detalhe(bigint) is
  'Detalhe de um fornecedor no painel Pendências Fornecedor: verbas (1809), conta corrente com saldo corrido (1825), saldo guardado por filial e avaria (8073).';

-- ----------------------------------------------------------------------------- acesso: só o servidor
revoke all on all tables in schema pendencias from public;
revoke all on function pendencias.montar_lista() from public;
revoke all on function pendencias.atualizar_pacote() from public;
revoke all on function pendencias.detalhe(bigint) from public;
revoke all on function pendencias.saldo_aplicar(numeric, numeric) from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on function pendencias.saldo_aplicar(numeric, numeric) from anon, authenticated;
    revoke all on schema pendencias from anon, authenticated;
    revoke all on all tables in schema pendencias from anon, authenticated;
    revoke all on function pendencias.montar_lista() from anon, authenticated;
    revoke all on function pendencias.atualizar_pacote() from anon, authenticated;
    revoke all on function pendencias.detalhe(bigint) from anon, authenticated;
  end if;
end $$;

-- ----------------------------------------------------------------------------- o agente monta depois de gravar
insert into agente.sistema (sistema, versao, apos_gravar, apos_gravar_s)
values ('pendencias', '', 'select pendencias.atualizar_pacote()', 15)
on conflict (sistema) do update set apos_gravar = excluded.apos_gravar, apos_gravar_s = excluded.apos_gravar_s;
