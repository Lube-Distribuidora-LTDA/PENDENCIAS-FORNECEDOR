/**
 * /api/versao — o que há de novo, numa consulta pequena e sem cache:
 *   pacote    a versão do pacote da lista (um resumo por fornecedor); o navegador só baixa
 *             (/api/pacote) quando ela muda
 *   agente    o AGENTE LUBE está ligado? (batimento com menos de 3 minutos) e quando ele leu
 *             cada rotina no WinThor pela última vez
 *   pedido    com ?pedido=<id>: como está o pedido de leitura do WinThor (botão Atualizar ou
 *             o clique num fornecedor)
 * O navegador pergunta isto de 15 em 15 segundos com a aba aberta.
 */
"use strict";
const { consultar, json, semConfiguracao, erroBanco } = require("./_db");

const SQL =
  `SELECT pc.versao, pc.gerado_em, pc.linhas, pc.bytes_json,
          b.visto AS agente_visto, coalesce(b.ligado, false) AS agente_ligado,
          (SELECT json_object_agg(fluxo, json_build_object('lido_em', lido_em, 'mudou_em', mudou_em, 'status', status))
             FROM agente.estado WHERE fluxo LIKE 'pendencias.%') AS fluxos,
          p.id AS pedido_id, p.status AS pedido_status, p.mensagem AS pedido_mensagem, p.detalhe AS pedido_detalhe,
          p.segundos AS pedido_segundos, p.atendido_em AS pedido_atendido_em
     FROM (SELECT 1) x
     LEFT JOIN pendencias.pacote pc ON pc.nome = 'lista'
     LEFT JOIN (SELECT max(visto_em) AS visto, bool_or(ligado) AS ligado FROM agente.batimento
                 WHERE visto_em > now() - interval '3 minutes') b ON true
     LEFT JOIN agente.pedido p ON p.id = $1 AND p.sistema = 'pendencias'`;

module.exports = async function handler(req, res) {
  if (semConfiguracao(res)) return;
  try {
    const bruto = new URL(req.url, "http://x").searchParams.get("pedido");
    const pedido = /^\d{1,15}$/.test(bruto || "") ? bruto : null;
    const l = (await consultar(SQL, [pedido])).rows[0] || {};
    const fluxos = l.fluxos || {};
    // "lido" = a leitura mais recente das rotinas de minuto em minuto (sem novidade, o agente só anota a leitura de 5 em
    // 5 min: a mais antiga atrasaria a hora da tela); "lido_mais_antigo" fica para a dica, para ver se uma rotina parou.
    // O cadastro de fornecedores (10 em 10 min) fica de fora.
    const lidos = Object.keys(fluxos).filter((k) => k !== "pendencias.fornecedor").map((k) => fluxos[k].lido_em).filter(Boolean).sort();
    const out = {
      pacote: l.versao ? { versao: l.versao, gerado_em: l.gerado_em, linhas: l.linhas, bytes: l.bytes_json } : null,
      agente: { vivo: !!(l.agente_visto && l.agente_ligado), visto_em: l.agente_visto || null, lido_em: lidos[lidos.length - 1] || null,
                lido_mais_antigo: lidos[0] || null, fluxos },
    };
    if (pedido) {
      out.pedido = l.pedido_id ? { id: Number(l.pedido_id), status: l.pedido_status, mensagem: l.pedido_mensagem,
        detalhe: l.pedido_detalhe, segundos: l.pedido_segundos == null ? null : Number(l.pedido_segundos), atendido_em: l.pedido_atendido_em } : null;
    }
    json(res, 200, out);
  } catch (e) {
    erroBanco(res, e);
  }
};
