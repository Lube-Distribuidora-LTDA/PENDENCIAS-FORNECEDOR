"""
SO LEITURA. Confere a tela contra o WinThor, fornecedor por fornecedor, no mesmo instante:

  WinThor   soma as tres rotinas direto nas tabelas, com SQL proprio (agrupado no Oracle, diferente
            do SQL dos fluxos do agente, que le linha a linha):
              1809  saldo a aplicar = PCVERBA.VALOR - soma(PCAPLICVERBA.VLAPLIC), verbas nao canceladas
                    (residuo abaixo de meio centavo = zero, como no painel)
              1825  saldo final     = soma(D) - soma(C) da PCMOVCRFOR, todas as filiais, 01/01/2011 ate hoje, no
                    fornecedor principal do cadastro (como a tela da rotina); e o saldo guardado (PCESTCRFOR)
              8073  valor avaria    = soma(PCEST.QTINDENIZ x VALORULTENT) pelo fornecedor do produto
  Tela      o pacote que o painel baixa (pendencias.pacote 'lista'), o mesmo da tela.

Diferenca pequena e explicavel: o agente le de 60 em 60 s; o que mudou no WinThor nesse meio tempo
aparece aqui e some na leitura seguinte (rodar de novo). Nao grava nada.

Uso: python -X utf8 conferir_winthor.py
"""
import json
import os
import sys
from decimal import Decimal

import oracledb
import psycopg2
from dotenv import load_dotenv

ENV = os.environ.get("AGENTE_ENV") or r"C:\Users\gti.julio.alves\Desktop\BI\16. INVENTARIO\etl\ENV"
load_dotenv(ENV)

SQL_WINTHOR = {
    "sa": """SELECT v.codfornec,
                    SUM(CASE WHEN ABS(v.valor - NVL(a.ap, 0)) < 0.005 THEN 0 ELSE v.valor - NVL(a.ap, 0) END)
               FROM pcverba v
               LEFT JOIN (SELECT numverba, SUM(vlaplic) ap FROM pcaplicverba GROUP BY numverba) a ON a.numverba = v.numverba
              WHERE v.dtcancel IS NULL
              GROUP BY v.codfornec""",
    # 1825 como a tela da rotina (conferido com o Julio em 2026-10-28, referencias.json): todas as filiais,
    # 01/01/2011 ate hoje, somando no codigo os lancamentos de todo fornecedor que tem ele como principal no cadastro
    "sf": """SELECT NVL(NULLIF(f.codfornecprinc, 0), m.codfornec), SUM(DECODE(m.tipo, 'D', m.valor, 'C', -m.valor, 0))
               FROM pcmovcrfor m LEFT JOIN pcfornec f ON f.codfornec = m.codfornec
              WHERE m.data BETWEEN DATE '2011-01-01' AND TRUNC(SYSDATE)
              GROUP BY NVL(NULLIF(f.codfornecprinc, 0), m.codfornec)""",
    "sg": "SELECT codfornec, SUM(valor) FROM pcestcrfor GROUP BY codfornec",
    "av": """SELECT p.codfornec, SUM(e.qtindeniz * e.valorultent)
               FROM pcest e JOIN pcprodut p ON p.codprod = e.codprod
              WHERE e.qtindeniz > 0 GROUP BY p.codfornec""",
}
NOMES = {"sa": "1809 saldo a aplicar", "sf": "1825 saldo final", "sg": "1825 saldo guardado (PCESTCRFOR)", "av": "8073 valor avaria"}


def main():
    dsn = oracledb.makedsn(os.environ["ORACLE_HOST"].strip(), int(os.environ.get("ORACLE_PORT", "1521")),
                           service_name=os.environ["ORACLE_SERVICE_NAME"].strip())
    ora = oracledb.connect(user=os.environ["ORACLE_USER"].strip(), password=os.environ["ORACLE_PASSWORD"], dsn=dsn)
    ora.module = "CONFERENCIA PENDENCIAS"
    ora.call_timeout = 120_000
    oc = ora.cursor()
    oc.execute("SET TRANSACTION READ ONLY")
    oc.execute("SELECT TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS') FROM dual")
    print("Foto do WinThor:", oc.fetchone()[0])
    wt = {}
    for k, sql in SQL_WINTHOR.items():
        oc.execute(sql)
        wt[k] = {int(c): Decimal(str(v or 0)) for c, v in oc.fetchall()}
    ora.rollback()
    ora.close()

    pg = psycopg2.connect(host=os.environ["SUPABASE_DB_HOST"].strip(), port=int(os.environ.get("SUPABASE_DB_PORT", "5432")),
                          dbname=os.environ.get("SUPABASE_DB_NAME", "postgres").strip(), user=os.environ["SUPABASE_DB_USER"].strip(),
                          password=os.environ["SUPABASE_DB_PASSWORD"].strip(), sslmode="require", application_name="conferencia-pendencias")
    pg.set_session(readonly=True)
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
    tela = {k: {} for k in SQL_WINTHOR}
    for i, c in enumerate(r["c"]):
        for k in SQL_WINTHOR:
            v = r[k][i]
            if v is not None:
                tela[k][int(c)] = Decimal(str(v))

    falhou = False
    for k in SQL_WINTHOR:
        a, b = wt[k], tela[k]
        cods = set(a) | set(b)
        dif = sorted(((c, a.get(c, Decimal(0)), b.get(c, Decimal(0))) for c in cods
                      if abs(a.get(c, Decimal(0)) - b.get(c, Decimal(0))) >= Decimal("0.005")), key=lambda x: -abs(x[1] - x[2]))
        ta, tb = sum(a.values()), sum(b.values())
        print(f"\n{NOMES[k]}: WinThor R$ {ta:,.2f} | tela R$ {tb:,.2f} | {len(cods) - len(dif)} de {len(cods)} fornecedores iguais ao centavo")
        for c, x, y in dif[:15]:
            print(f"   fornecedor {c}: WinThor {x:,.2f} | tela {y:,.2f} | diferenca {x - y:,.2f}")
        falhou = falhou or bool(dif)
    # o valor que a tela da rotina mostrou fica fora do Git (o repositorio e publico)
    ref_arq = os.path.join(os.path.dirname(os.path.abspath(__file__)), "referencias.json")
    if os.path.exists(ref_arq):
        for r in json.load(open(ref_arq, encoding="utf-8")).get("1825", []):
            c = int(r["codfornec"])
            print(f"\nReferencia da tela da rotina 1825 ({r.get('quando', '')}): fornecedor {c} = R$ {Decimal(r['saldo_final']):,.2f} | "
                  f"WinThor agora R$ {wt['sf'].get(c, 0):,.2f} | tela R$ {tela['sf'].get(c, 0):,.2f}")
    print("\nRESULTADO:", "DIFERENCAS acima (rodar de novo: se sumirem, era o WinThor andando entre as leituras)" if falhou else "tudo igual ao centavo")
    return 1 if falhou else 0


if __name__ == "__main__":
    sys.exit(main())
