# PENDÊNCIAS FORNECEDOR — Lube Distribuidora

Todos os fornecedores com o que cada um tem pendente com a Lube, em três números do WinThor:

| Número | Rotina do WinThor | De onde vem |
|---|---|---|
| **Saldo a aplicar** | **1809** — Relação de verbas por fornecedor | `PCVERBA.VALOR` − soma de `PCAPLICVERBA.VLAPLIC` (o estorno vem como linha negativa: a soma é o aplicado líquido), verbas não canceladas emitidas **de 01/01/2011 até hoje**, só do código |
| **Saldo final** | **1825** — Débito e crédito de fornecedor | conta corrente `PCMOVCRFOR`: débitos (D) − créditos (C), estornos inclusos, **todas as filiais do cadastro (`PCFILIAL`), de 01/01/2011 até hoje**, na **conta do grupo do principal**: todo fornecedor com o mesmo principal no cadastro (`PCFORNEC.CODFORNECPRINC`) lança na mesma conta, e todo código do grupo mostra o mesmo saldo |
| **Valor avaria** | **8073** — AVARIA 2 (personalizada, `PCSIS800`) | `PCEST.QTINDENIZ` × `VALORULTENT`, **todas as filiais menos a 11** (como o relatório da rotina): a avaria dos produtos do código + a de todo fornecedor que tem ele como **principal no cadastro** |

**Regra do Júlio para todos os relatórios: sempre todas as filiais.** O período começa sempre em
**01/01/2011** e termina no dia de hoje (o dia de Brasília, que anda sozinho); a tela mostra o período na faixa
de filtros e no cabeçalho do fornecedor.

**O número de cada código é o da rotina:** na 1825, todo código mostra a conta do grupo do principal dele (o
principal e os membros, o mesmo saldo); na 8073, o código mostra a própria avaria + a dos fornecedores que têm ele
como principal. Por isso a soma das linhas repetiria o grupo: o total da 1825 soma cada grupo uma vez e o da 8073
soma cada produto uma vez (`avo`). A tela do fornecedor diz quanto é só do código.

A lista mostra os 10,5 mil fornecedores do cadastro com os três números; o clique num fornecedor
abre a tela dele com os três cartões e, **só quando a pessoa clica**, as linhas de cada rotina
(verbas, lançamentos da conta corrente com saldo corrido, produtos avariados), com Excel.

## Ligado ao WinThor pelo AGENTE LUBE

O painel nunca fala com o WinThor. Quem lê é o **AGENTE LUBE** (`Desktop\BI\22. AGENTE LUBE`), na
`SRV-IA`, com 6 fluxos em `fluxos/pendencias.toml`:

| Fluxo | A cada | No WinThor (2026-10-28) |
|---|---|---|
| `pendencias.verba` (1809) | 60 s | 11.614 verbas, ~0,1 s |
| `pendencias.lancamento` (1825) | 60 s | 43.172 lançamentos, ~1 s |
| `pendencias.saldo` (`PCESTCRFOR`) | 60 s | 940 linhas |
| `pendencias.avaria` (8073) | 60 s | 3.670 produto × filial, ~0,1 s |
| `pendencias.fornecedor` (`PCFORNEC`) | 10 min | 10.562 fornecedores |
| `pendencias.filial` (`PCFILIAL`) | 10 min | 14 filiais (desde 2026-10-29: a 1825 soma só as filiais do cadastro) |

- **A tela muda sozinha:** depois de gravar, o agente roda `pendencias.atualizar_pacote()`, que refaz o
  pacote da lista (só troca a versão se o conteúdo mudou). O navegador pergunta de 15 em 15 s.
- **A busca puxa do WinThor:** o clique num fornecedor (e o botão **Buscar no WinThor** da tela dele, e o
  Atualizar do topo) pede ao agente uma leitura na hora (`agente.pedir_atualizacao('pendencias')`, a ponte
  pelo banco, sem porta aberta na rede). O agente lê as cinco tabelas, grava o que mudou e responde; a
  tela diz "Conferido no WinThor às hh:mm:ss" e o que mudou. Medido: 3 a 5 s do clique à resposta.

## Banco

Schema `pendencias` no DATA WAREHOUSE (`db/01-schema.sql` a `db/06-1825-grupo-do-principal.sql`; migrações
`pendencias_01` a `pendencias_09`). Tabelas com RLS ligado e sem políticas; só o agente e as funções
do servidor leem. `pendencias.detalhe(cod)` devolve um fornecedor; `pendencias.montar_lista()` o pacote.

## Conferência

`conferencia\conferir_winthor.py` (só leitura) soma as três rotinas direto no WinThor, com SQL próprio,
e compara com a tela fornecedor por fornecedor. **2026-10-28 17:12: tudo igual ao centavo** (843, 878 e
311 fornecedores). `conferencia\medir_fluxos.py` mede os fluxos no WinThor.

**1825 conferida com a tela da rotina (Júlio, 2026-10-28):** para o fornecedor de exemplo, o saldo final
da rotina = os lançamentos dele + os de um segundo código que tem ele como fornecedor principal. O painel
dá o mesmo número (o valor de referência fica em `conferencia\referencias.json`, fora do Git). Em
2026-10-29 o Júlio conferiu um código que tem outro como principal: a rotina mostra os lançamentos dele (o painel
escrevia "no principal X"; migração `pendencias_07_codigo_e_grupo`). O saldo que o WinThor guarda
(`PCESTCRFOR`) não é o da 1825 (difere em metade dos fornecedores) e fica só no banco.

**1825, a regra certa (Júlio, 2026-10-29):** um membro de um grupo grande (75 fornecedores com lançamento) dava
negativo no painel e positivo na rotina. A rotina mostra a **conta do grupo inteiro do principal**, para o
principal e para cada membro: a soma do grupo bateu ao centavo com o print, sem um lançamento feito minutos depois
dele. Os dois conferidos antes continuam batendo (no principal o grupo é o mesmo; o outro era membro sozinho no
grupo). E "todas as filiais" na rotina são as do cadastro: um lançamento numa filial que não existe na `PCFILIAL`
fica fora (fluxo `pendencias.filial`, migração `pendencias_09_1825_grupo_do_principal`); a tela mostra à parte.

**8073 conferida com o relatório da rotina (Júlio, 2026-10-28 e 2026-10-29):** dois relatórios puxados com
todas as filiais batem ao centavo com a avaria do grupo **sem a filial 11** (BA, a única que usa estoque de
depósito fechado). A lista das filiais que a rotina não soma mora no banco (`pendencias.filial_fora_8073`,
migração `pendencias_08_avaria_filiais_da_rotina`); a tela do fornecedor mostra à parte o que ficou fora. O SQL
da 8073 não fica no banco: a regra foi achada pelo número.

**2026-10-29 08:26:** a conferência deu tudo igual ao centavo, inclusive os quatro valores de referência das rotinas.
**2026-10-29 09:48 (regra do grupo na 1825):** tudo igual ao centavo (828 códigos na 1825) e os cinco valores de
referência IGUAIS (`referencias.json` aceita `lancado_depois`: transações que entraram depois do print).

**A confirmar:** se a 1809 também soma o grupo do principal.

## Na máquina

`INICIAR.bat` → http://localhost:3107 (lê o DATA WAREHOUSE com o `ENV` do agente ou do Inventário; só
esta máquina acessa, sem o login do Painel Lube).

## Publicação

Publicado em 2026-10-28 (autorização do Júlio): repositório público
`Lube-Distribuidora-LTDA/PENDENCIAS-FORNECEDOR`, **sem valores nem códigos de fornecedor** (nasceu de um commit
só); projeto Vercel `pendencias-fornecedor` (Root `web`, `gru1`, Node 22; deploy a cada push na `main`);
guarda da Sentinela fechado (`middleware.ts`), registrado no banco do portal **antes** do 1º deploy (migração
`registrar_pendencias_fornecedor`: só entra quem tem acesso pelo Painel Lube; rede em observar); cartão no portal
em COMPRAS; site no Guardião. Variáveis: `SUPABASE_DB_HOST`, `SUPABASE_DB_PORT` (5432), `SUPABASE_DB_NAME` e
`SUPABASE_DB_USER` cadastradas; **`SUPABASE_DB_PASSWORD` (Sensitive) quem cadastra é o Júlio** — sem ela a API
responde `configuracao_incompleta`.

Registro no cérebro: `Projetos/PENDÊNCIAS FORNECEDOR.md`.
