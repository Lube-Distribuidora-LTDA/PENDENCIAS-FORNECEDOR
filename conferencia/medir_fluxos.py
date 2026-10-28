"""
SO LEITURA. Roda no WinThor cada fluxo de fluxos/pendencias.toml (o catalogo do agente) e mostra
linhas, tempo e os totais que o painel vai mostrar. Nao grava nada em lugar nenhum.

Uso: python -X utf8 medir_fluxos.py
"""
import os
import sys
import time
import tomllib
from decimal import Decimal

import oracledb
from dotenv import load_dotenv

ENV = os.environ.get("AGENTE_ENV") or r"C:\Users\gti.julio.alves\Desktop\BI\16. INVENTARIO\etl\ENV"
load_dotenv(ENV)
TOML = r"C:\Users\gti.julio.alves\Desktop\BI\22. AGENTE LUBE\2 - AGENTE\fluxos\pendencias.toml"


def conectar():
    dsn = oracledb.makedsn(os.environ["ORACLE_HOST"].strip(), int(os.environ.get("ORACLE_PORT", "1521")),
                           service_name=os.environ["ORACLE_SERVICE_NAME"].strip())
    conn = oracledb.connect(user=os.environ["ORACLE_USER"].strip(), password=os.environ["ORACLE_PASSWORD"], dsn=dsn)
    conn.module = "CONFERENCIA PENDENCIAS"
    conn.call_timeout = 120_000
    return conn


def main():
    fluxos = tomllib.load(open(TOML, "rb"))["fluxo"]
    conn = conectar()
    cur = conn.cursor()
    cur.execute("SET TRANSACTION READ ONLY")
    cur.execute("SELECT TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS') FROM dual")
    print("Foto do WinThor:", cur.fetchone()[0])
    dados = {}
    for f in fluxos:
        t0 = time.perf_counter()
        cur.execute(f["sql"])
        cols = [d[0].lower() for d in cur.description]
        linhas = [dict(zip(cols, r)) for r in cur.fetchall()]
        ms = (time.perf_counter() - t0) * 1000
        falta = [c for c in f["colunas"] if c not in cols]
        print(f"{f['nome']:<26} {len(linhas):>7,} linhas  {ms:8.0f} ms  {'colunas OK' if not falta else 'FALTA ' + str(falta)}")
        dados[f["nome"].split(".")[1]] = linhas
    conn.rollback()
    conn.close()

    d = lambda v: Decimal(str(v or 0))  # noqa: E731
    vb = dados["verba"]
    saldo_ap = [d(x["valor"]) - d(x["aplicado"]) for x in vb]
    print("\n1809 verbas ativas:", len(vb), "| valor", sum(d(x["valor"]) for x in vb), "| aplicado", sum(d(x["aplicado"]) for x in vb))
    print("     saldo a aplicar > 0,005:", sum(1 for s in saldo_ap if s > Decimal("0.005")),
          "verbas, R$", sum(s for s in saldo_ap if s > Decimal("0.005")))
    print("     saldo a aplicar < -0,005 (aplicado maior que a verba):", sum(1 for s in saldo_ap if s < Decimal("-0.005")),
          "verbas, R$", sum(s for s in saldo_ap if s < Decimal("-0.005")))
    lc = dados["lancamento"]
    deb = sum(d(x["valor"]) for x in lc if x["tipo"] == "D")
    cre = sum(d(x["valor"]) for x in lc if x["tipo"] == "C")
    print("\n1825 lancamentos:", len(lc), "| debitos", deb, "| creditos", cre, "| saldo", deb - cre)
    print("     saldo guardado (PCESTCRFOR):", sum(d(x["valor"]) for x in dados["saldo"]))
    av = dados["avaria"]
    print("\n8073 avaria:", len(av), "linhas | valor (qt x valor ult. entrada)",
          sum((d(x["qtindeniz"]) * d(x["valorultent"])).quantize(Decimal("0.01")) for x in av))
    print("\nfornecedores:", len(dados["fornecedor"]))


if __name__ == "__main__":
    sys.exit(main())
