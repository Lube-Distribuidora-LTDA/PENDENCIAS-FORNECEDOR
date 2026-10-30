"""
SO LEITURA. Confere a tela contra o WinThor, fornecedor por fornecedor, no mesmo instante:

  WinThor   soma as tres rotinas direto nas tabelas, com SQL proprio (agrupado no Oracle, diferente
            do SQL dos fluxos do agente, que le linha a linha):
              1809  saldo a aplicar = PCVERBA.VALOR - soma(PCAPLICVERBA.VLAPLIC), verbas emitidas de 01/01/2011 ate
                    hoje, CANCELADAS INCLUSIVE (a rotina soma), fracao abaixo de R$ 0,01 = zero (como a rotina)
              1825  saldo final     = soma(D) - soma(C) da PCMOVCRFOR, as filiais do cadastro (PCFILIAL), 01/01/2011
                    ate hoje, na conta do GRUPO do principal: o valor de X = tudo o que lancaram os fornecedores com o
                    mesmo principal de X no cadastro (PCFORNEC.CODFORNECPRINC); e o saldo guardado (PCESTCRFOR)
              8073  valor avaria    = soma(PCEST.QTINDENIZ x VALORULTENT) pelo fornecedor do produto, todas as filiais
                    menos as que a rotina nao soma (pendencias.filial_fora_8073: a 11); o valor de X = a avaria de X
                    + a dos fornecedores que tem X como principal no cadastro
            Como as rotinas (conferido com o Julio em 2026-10-28 e 2026-10-29). Confere tambem o valor so do codigo
            (sfo, avo), a base dos totais do painel.
  Tela      o pacote que o painel baixa (pendencias.pacote 'lista'), o mesmo da tela.

Diferenca pequena e explicavel: o agente le de 60 em 60 s; o que mudou no WinThor nesse meio tempo
aparece aqui e some na leitura seguinte (rodar de novo). Nao grava nada.

Uso: python -X utf8 conferir_winthor.py
"""
import json
import os
import sys
from collections import defaultdict
from decimal import Decimal

import oracledb
import psycopg2
from dotenv import load_dotenv

ENV = os.environ.get("AGENTE_ENV") or r"C:\Users\gti.julio.alves\Desktop\BI\16. INVENTARIO\etl\ENV"
load_dotenv(ENV)

# valor so do codigo (o fornecedor do lancamento ou do produto); o grupo do principal e montado aqui embaixo
SQL_PROPRIO = {
    "sa": """SELECT v.codfornec,
                    SUM(CASE WHEN ABS(v.valor - NVL(a.ap, 0)) < 0.01 THEN 0 ELSE v.valor - NVL(a.ap, 0) END)
               FROM pcverba v
               LEFT JOIN (SELECT numverba, SUM(vlaplic) ap FROM pcaplicverba GROUP BY numverba) a ON a.numverba = v.numverba
              WHERE v.dtemissao BETWEEN DATE '2011-01-01' AND TRUNC(SYSDATE)
              GROUP BY v.codfornec""",
    "sfo": """SELECT m.codfornec, SUM(DECODE(m.tipo, 'D', m.valor, 'C', -m.valor, 0))
                FROM pcmovcrfor m
               WHERE m.data BETWEEN DATE '2011-01-01' AND TRUNC(SYSDATE)
                 AND EXISTS (SELECT 1 FROM pcfilial f WHERE f.codigo = m.codfilial)
               GROUP BY m.codfornec""",
    "sg": "SELECT codfornec, SUM(valor) FROM pcestcrfor GROUP BY codfornec",
    "avo": """SELECT p.codfornec, SUM(e.qtindeniz * e.valorultent)
                FROM pcest e JOIN pcprodut p ON p.codprod = e.codprod
               WHERE e.qtindeniz > 0 AND p.codfornec IS NOT NULL {fora}
               GROUP BY p.codfornec""",
}
NOMES = {"sa": "1809 saldo a aplicar", "sf": "1825 saldo final (conta do grupo do principal)",
         "sfo": "1825 so o codigo (o que os totais somam)", "sg": "1825 saldo guardado (PCESTCRFOR)",
         "av": "8073 valor avaria (codigo + quem tem ele como principal)", "avo": "8073 so o codigo (o que os totais somam)"}


def com_grupo(proprio, principal):
    """valor de X = o de X + o de todo m com principal(m) = X (m <> X)"""
    out = defaultdict(Decimal)
    for c, v in proprio.items():
        out[c] += v
        p = principal.get(c)
        if p and p != c:
            out[p] += v
    return dict(out)


def conta_grupo(proprio, principal):
    """1825: valor de X = a conta do grupo do principal de X (tudo o que lancaram os fornecedores com o mesmo principal)"""
    tot = defaultdict(Decimal)
    for c, v in proprio.items():
        tot[principal.get(c, c)] += v
    out = {c: tot[principal.get(c, c)] for c in set(principal) | set(proprio) if principal.get(c, c) in tot}
    for p, v in tot.items():
        out.setdefault(p, v)  # principal que nao esta no cadastro
    return out


def main():
    pg = psycopg2.connect(host=os.environ["SUPABASE_DB_HOST"].strip(), port=int(os.environ.get("SUPABASE_DB_PORT", "5432")),
                          dbname=os.environ.get("SUPABASE_DB_NAME", "postgres").strip(), user=os.environ["SUPABASE_DB_USER"].strip(),
                          password=os.environ["SUPABASE_DB_PASSWORD"].strip(), sslmode="require", application_name="conferencia-pendencias")
    pg.set_session(readonly=True)
    with pg.cursor() as cur:
        cur.execute("SELECT codfilial FROM pendencias.filial_fora_8073 ORDER BY 1")
        fora = [r[0] for r in cur.fetchall()]

    dsn = oracledb.makedsn(os.environ["ORACLE_HOST"].strip(), int(os.environ.get("ORACLE_PORT", "1521")),
                           service_name=os.environ["ORACLE_SERVICE_NAME"].strip())
    ora = oracledb.connect(user=os.environ["ORACLE_USER"].strip(), password=os.environ["ORACLE_PASSWORD"], dsn=dsn)
    ora.module = "CONFERENCIA PENDENCIAS"
    ora.call_timeout = 120_000
    oc = ora.cursor()
    oc.execute("SET TRANSACTION READ ONLY")
    oc.execute("SELECT TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS') FROM dual")
    print("Foto do WinThor:", oc.fetchone()[0], "| filiais fora da 8073:", ", ".join(fora) or "nenhuma")
    wt = {}
    for k, sql in SQL_PROPRIO.items():
        if k == "avo":
            sql = sql.format(fora="AND e.codfilial NOT IN (" + ", ".join(f"'{int(f)}'" for f in fora) + ")" if fora else "")
        oc.execute(sql)
        wt[k] = {int(c): Decimal(str(v or 0)) for c, v in oc.fetchall()}
    oc.execute("SELECT codfornec, NVL(NULLIF(codfornecprinc, 0), codfornec) FROM pcfornec")
    principal = {int(c): int(p) for c, p in oc.fetchall()}
    # o valor que a tela da rotina mostrou fica fora do Git (o repositorio e publico); "lancado_depois" = transacoes
    # que entraram no WinThor depois do print (a referencia e comparada sem elas)
    ref_arq = os.path.join(os.path.dirname(os.path.abspath(__file__)), "referencias.json")
    refs = json.load(open(ref_arq, encoding="utf-8")) if os.path.exists(ref_arq) else {}
    depois = {}
    for x in refs.get("1825", []):
        nts = [int(n) for n in x.get("lancado_depois", [])]
        if nts:
            oc.execute("SELECT NVL(SUM(DECODE(tipo, 'D', valor, 'C', -valor, 0)), 0) FROM pcmovcrfor WHERE numtranscrfor IN ("
                       + ", ".join(str(n) for n in nts) + ")")
            depois[int(x["codfornec"])] = Decimal(str(oc.fetchone()[0]))
    ora.rollback()
    ora.close()
    wt["sf"] = conta_grupo(wt["sfo"], principal)
    wt["av"] = com_grupo(wt["avo"], principal)

    with pg.cursor() as cur:
        cur.execute("SELECT versao, gerado_em, payload FROM pendencias.pacote WHERE nome = 'lista'")
        versao, gerado, payload = cur.fetchone()
        cur.execute("SELECT fluxo, lido_em FROM agente.estado WHERE fluxo LIKE 'pendencias.%' ORDER BY 1")
        lidos = cur.fetchall()
    pg.close()
    print("Tela (pacote):", versao, "montado em", gerado)
    for f, l in lidos:
        print(f"   {f:<24} lido no WinThor em {l}")
    r = json.loads(payload)["r"]
    tela = {k: {} for k in NOMES}
    for i, c in enumerate(r["c"]):
        for k in NOMES:
            v = r[k][i]
            if v is not None:
                tela[k][int(c)] = Decimal(str(v))

    falhou = False
    for k in NOMES:
        a, b = wt[k], tela[k]
        cods = {c for c in set(a) | set(b) if a.get(c) or b.get(c)}
        dif = sorted(((c, a.get(c, Decimal(0)), b.get(c, Decimal(0))) for c in cods
                      if abs(a.get(c, Decimal(0)) - b.get(c, Decimal(0))) >= Decimal("0.005")), key=lambda x: -abs(x[1] - x[2]))
        ta, tb = sum(a.values()), sum(b.values())
        print(f"\n{NOMES[k]}: WinThor R$ {ta:,.2f} | tela R$ {tb:,.2f} | {len(cods) - len(dif)} de {len(cods)} fornecedores iguais ao centavo")
        for c, x, y in dif[:15]:
            print(f"   fornecedor {c}: WinThor {x:,.2f} | tela {y:,.2f} | diferenca {x - y:,.2f}")
        falhou = falhou or bool(dif)

    print()
    for rotina, campo, chave in (("1809", "sa", "saldo_aplicar"), ("1825", "sf", "saldo_final"), ("8073", "av", "valor")):
        for x in refs.get(rotina, []):
            c, esperado = int(x["codfornec"]), Decimal(x[chave])
            dep = depois.get(c, Decimal(0)) if rotina == "1825" else Decimal(0)
            ok = abs(tela[campo].get(c, Decimal(0)) - dep - esperado) < Decimal("0.005")
            # tela = WinThor de agora e diferente do print: o WinThor andou depois do print (referencia velha), nao erro
            andou = not ok and abs(tela[campo].get(c, Decimal(0)) - wt[campo].get(c, Decimal(0))) < Decimal("0.005")
            print(f"Rotina {rotina} ({x.get('quando', '')}): fornecedor {c} = R$ {esperado:,.2f} | WinThor agora "
                  f"R$ {wt[campo].get(c, 0):,.2f} | tela R$ {tela[campo].get(c, 0):,.2f}"
                  + (f" (sem o lancado depois do print: R$ {tela[campo].get(c, 0) - dep:,.2f})" if dep else "")
                  + f" | {'IGUAL' if ok else 'O WINTHOR MUDOU DESDE O PRINT (tela = WinThor de agora)' if andou else 'DIFERENTE'}")
    print("\nRESULTADO:", "DIFERENCAS acima (rodar de novo: se sumirem, era o WinThor andando entre as leituras)" if falhou else "tudo igual ao centavo")
    return 1 if falhou else 0


if __name__ == "__main__":
    sys.exit(main())
