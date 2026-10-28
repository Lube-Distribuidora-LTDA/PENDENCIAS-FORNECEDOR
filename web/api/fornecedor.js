/**
 * /api/fornecedor?cod=<código> — o detalhe de um fornecedor: as verbas (rotina 1809), a conta
 * corrente com o saldo corrido (1825), o saldo que o WinThor guarda por filial e a avaria (8073),
 * mais a hora em que o agente leu cada rotina no WinThor.
 *
 * Lido na hora, só daquele fornecedor (pendencias.detalhe), sem cache: quem chama é o clique no
 * fornecedor e, logo depois, a resposta do agente ao pedido de leitura do WinThor.
 */
"use strict";
const zlib = require("zlib");
const { consultar, json, semConfiguracao, erroBanco } = require("./_db");

module.exports = async function handler(req, res) {
  if (semConfiguracao(res)) return;
  const cod = new URL(req.url, "http://x").searchParams.get("cod");
  if (!/^\d{1,12}$/.test(cod || "")) return json(res, 400, { erro: "codigo", mensagem: "Código de fornecedor inválido." });
  try {
    const l = (await consultar("SELECT pendencias.detalhe($1::bigint)::text AS j", [cod])).rows[0];
    const corpo = Buffer.from((l && l.j) || "{}", "utf8");
    res.statusCode = 200;
    res.setHeader("Content-Type", "application/json; charset=utf-8");
    res.setHeader("Cache-Control", "no-store");
    // o fornecedor com mais lançamentos (milhares de linhas) passa de 500 KB: vai comprimido
    if (/\bgzip\b/.test(req.headers["accept-encoding"] || "") && corpo.length > 2048) {
      const z = zlib.gzipSync(corpo, { level: 6 });
      res.setHeader("Content-Encoding", "gzip");
      res.setHeader("Content-Length", z.length);
      return res.end(z);
    }
    res.setHeader("Content-Length", corpo.length);
    res.end(corpo);
  } catch (e) {
    erroBanco(res, e);
  }
};
