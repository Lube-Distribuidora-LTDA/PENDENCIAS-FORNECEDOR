# PENDÊNCIAS FORNECEDOR — Lube Distribuidora

Todos os fornecedores com o que cada um tem pendente com a Lube, em três números do WinThor:

| Número | Rotina do WinThor | De onde vem |
|---|---|---|
| **Saldo a aplicar** | **1809** — Relação de verbas por fornecedor | `PCVERBA.VALOR` − soma de `PCAPLICVERBA.VLAPLIC` (o estorno vem como linha negativa: a soma é o aplicado líquido), verbas não canceladas |
| **Saldo final** | **1825** — Débito e crédito de fornecedor | conta corrente `PCMOVCRFOR`: débitos (D) − créditos (C), estornos inclusos, **todas as filiais, de 01/01/2011 até hoje**, somando no código os lançamentos de todo fornecedor que tem ele como **principal no cadastro** (`PCFORNEC.CODFORNECPRINC`) |
| **Valor avaria** | **8073** — AVARIA 2 (personalizada, `PCSIS800`) | `PCEST.QTINDENIZ` × `VALORULTENT`, por filial e produto, pelo fornecedor do produto |

A lista mostra os 10,5 mil fornecedores do cadastro com os três números; o clique num fornecedor
abre a tela dele com os três cartões e, **só quando a pessoa clica**, as linhas de cada rotina
(verbas, lançamentos da conta corrente com saldo corrido, produtos avariados), com Excel.

## Ligado ao WinThor pelo AGENTE LUBE

O painel nunca fala com o WinThor. Quem lê é o **AGENTE LUBE** (`Desktop\BI\22. AGENTE LUBE`), na
`SRV-IA`, com 5 fluxos em `fluxos/pendencias.toml`:

| Fluxo | A cada | No WinThor (2026-10-28) |
|---|---|---|
| `pendencias.verba` (1809) | 60 s | 11.614 verbas, ~0,1 s |
| `pendencias.lancamento` (1825) | 60 s | 43.172 lançamentos, ~1 s |
| `pendencias.saldo` (`PCESTCRFOR`) | 60 s | 940 linhas |
| `pendencias.avaria` (8073) | 60 s | 3.670 produto × filial, ~0,1 s |
| `pendencias.fornecedor` (`PCFORNEC`) | 10 min | 10.562 fornecedores |

- **A tela muda sozinha:** depois de gravar, o agente roda `pendencias.atualizar_pacote()`, que refaz o
  pacote da lista (só troca a versão se o conteúdo mudou). O navegador pergunta de 15 em 15 s.
- **A busca puxa do WinThor:** o clique num fornecedor (e o botão **Buscar no WinThor** da tela dele, e o
  Atualizar do topo) pede ao agente uma leitura na hora (`agente.pedir_atualizacao('pendencias')`, a ponte
  pelo banco, sem porta aberta na rede). O agente lê as cinco tabelas, grava o que mudou e responde; a
  tela diz "Conferido no WinThor às hh:mm:ss" e o que mudou. Medido: 3 a 5 s do clique à resposta.

## Banco

Schema `pendencias` no DATA WAREHOUSE (`db/01-schema.sql`; migrações `pendencias_01_schema` e
`pendencias_02_saldo_sem_residuo`). Tabelas com RLS ligado e sem políticas; só o agente e as funções
do servidor leem. `pendencias.detalhe(cod)` devolve um fornecedor; `pendencias.montar_lista()` o pacote.

## Conferência

`conferencia\conferir_winthor.py` (só leitura) soma as três rotinas direto no WinThor, com SQL próprio,
e compara com a tela fornecedor por fornecedor. **2026-10-28 17:12: tudo igual ao centavo** (843, 878 e
311 fornecedores). `conferencia\medir_fluxos.py` mede os fluxos no WinThor.

**1825 conferida com a tela da rotina (Júlio, 2026-10-28):** para o fornecedor de exemplo, o saldo final
da rotina = os lançamentos dele + os de um segundo código que tem ele como fornecedor principal. O painel
dá o mesmo número (o valor de referência fica em `conferencia\referencias.json`, fora do Git). Cada lançamento entra uma vez só, no principal do fornecedor dele; o fornecedor de outro
principal mostra "no principal X" e, na tela dele, os próprios lançamentos com o saldo do principal. O saldo
que o WinThor guarda (`PCESTCRFOR`) não é o da 1825 (difere em metade dos fornecedores) e fica só no banco.

**A confirmar:** o SQL da 8073 não fica no banco (o usuário de leitura não enxerga): a regra usada é a de
avaria da casa; e se a 1809 e a 8073 também somam o grupo do principal, como a 1825.

## Na máquina

`INICIAR.bat` → http://localhost:3107 (lê o DATA WAREHOUSE com o `ENV` do agente ou do Inventário; só
esta máquina acessa, sem o login do Painel Lube).

## Publicação

Ainda não publicado (falta o OK do Júlio). O desenho é o dos outros painéis: repositório público
`Lube-Distribuidora-LTDA/PENDENCIAS-FORNECEDOR` sem valores, projeto Vercel `pendencias-fornecedor`
(Root `web`), guarda da Sentinela fechado (`middleware.ts`) registrado antes do 1º deploy, variáveis
`SUPABASE_DB_*` (a senha quem cadastra é o Júlio) e cartão no portal.

Registro no cérebro: `Projetos/PENDÊNCIAS FORNECEDOR.md`.
