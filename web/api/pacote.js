/**
 * /api/pacote?v=<versão> — o pacote da lista (um resumo por fornecedor), comprimido.
 *
 * Quem monta é o AGENTE LUBE: depois de gravar, ele roda pendencias.atualizar_pacote(), que só
 * troca a versão quando o conteúdo mudou. O banco guarda texto; a compressão é aqui. Bytes crus
 * (application/octet-stream + X-Pacote: gzip), como o Relatório 146. Dado da empresa: cache só
 * no navegador de quem entrou.
 */
"use strict";
const zlib = require("zlib");
const { consultar, json, semConfiguracao, erroBanco } = require("./_db");

module.exports = async function handler(req, res) {
  if (semConfiguracao(res)) return;
  try {
    const v = new URL(req.url, "http://x").searchParams.get("v");
    const l = (await consultar("SELECT versao, payload FROM pendencias.pacote WHERE nome = 'lista'", [])).rows[0];
    if (!l) return json(res, 404, { erro: "sem_pacote", mensagem: "O pacote da lista ainda não foi montado: o agente monta depois da primeira leitura do WinThor." });
    const corpo = zlib.gzipSync(Buffer.from(l.payload, "utf8"), { level: 6 });
    res.statusCode = 200;
    res.setHeader("Content-Type", "application/octet-stream");
    res.setHeader("X-Pacote", "gzip");
    res.setHeader("X-Versao", l.versao);
    res.setHeader("Content-Length", corpo.length);
    res.setHeader("Cache-Control", v && v === l.versao ? "private, max-age=31536000, immutable" : "private, no-cache");
    res.end(corpo);
  } catch (e) {
    erroBanco(res, e);
  }
};
