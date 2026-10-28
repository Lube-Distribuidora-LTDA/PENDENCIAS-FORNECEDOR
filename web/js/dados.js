/* =============================================================================
 * dados.js — o pacote da lista (um resumo por fornecedor), a cópia no navegador, o
 * ao vivo e a ponte com o AGENTE LUBE.
 *
 * O banco guarda o pacote pronto (pendencias.pacote), que o agente remonta depois de
 * gravar. A cópia fica no navegador (IndexedDB): abrir de novo só baixa se a versão mudou.
 * O detalhe de um fornecedor vem à parte (api/fornecedor), lido na hora.
 * ========================================================================== */
(function () {
"use strict";
var L = window.L;

/* ------------------------------ cópia no navegador ------------------------------ */
var IDB = "pendencias-fornecedor-lube", LOJA = "pacotes";
function idbAbrir() {
  return new Promise(function (ok, erro) {
    if (!window.indexedDB) return erro(new Error("sem IndexedDB"));
    var r = indexedDB.open(IDB, 1);
    r.onupgradeneeded = function () { r.result.createObjectStore(LOJA); };
    r.onsuccess = function () { ok(r.result); }; r.onerror = function () { erro(r.error); };
  });
}
function idbLer(nome) {
  return idbAbrir().then(function (db) { return new Promise(function (ok) {
    var q = db.transaction(LOJA, "readonly").objectStore(LOJA).get(nome);
    q.onsuccess = function () { ok(q.result || null); }; q.onerror = function () { ok(null); };
  }); }).catch(function () { return null; });
}
function idbGravar(nome, obj) {
  return idbAbrir().then(function (db) { return new Promise(function (ok) {
    var tx = db.transaction(LOJA, "readwrite"); tx.objectStore(LOJA).put(obj, nome);
    tx.oncomplete = function () { ok(true); }; tx.onerror = function () { ok(false); };
  }); }).catch(function () { return false; });
}
function erroHttp(r, oque) {
  return r.json().catch(function () { return {}; }).then(function (j) {
    if (r.status === 401) throw new Error("Sua sessão do Painel Lube expirou. Entre de novo pelo portal.");
    throw new Error("Não foi possível ler " + oque + " (" + r.status + (j && j.mensagem ? ": " + j.mensagem : j && j.erro ? ": " + j.erro : "") + ").");
  });
}
L.erroHttp = erroHttp;
function baixarPacote(versao) {
  return fetch("api/pacote?v=" + encodeURIComponent(versao || "x"), { cache: "no-store" }).then(function (r) {
    if (!r.ok) return erroHttp(r, "a lista de fornecedores");
    var corpo = r.body;
    if (r.headers.get("X-Pacote") === "gzip" && window.DecompressionStream) corpo = corpo.pipeThrough(new DecompressionStream("gzip"));
    return new Response(corpo).text();
  }).then(function (txt) { return JSON.parse(txt); });
}
L.versaoNoBanco = function () { return fetch("api/versao?_=" + Date.now(), { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : erroHttp(r, "a versão dos dados"); }); };

/* ------------------------------ carga e ao vivo ------------------------------ */
L.PAC = null;             // { versao, gerado_em, j }
L.carregarTudo = function (aviso) {
  aviso = aviso || function () {};
  return L.versaoNoBanco().then(function (ver) {
    L.ULTIMA_VERSAO = ver; L.CONFERIDO_EM = new Date();
    if (!ver.pacote) throw new Error("A lista ainda não foi montada no banco: o agente monta depois da primeira leitura do WinThor.");
    return idbLer("lista").then(function (c) {
      if (c && c.versao === ver.pacote.versao) { L.PAC = c; L.ORIGEM = "copia"; return montar(); }
      aviso("Baixando a lista de fornecedores" + (c ? " (mudou)" : " (só na primeira vez)") + "…");
      return baixarPacote(ver.pacote.versao).then(function (j) {
        L.PAC = { versao: ver.pacote.versao, gerado_em: ver.pacote.gerado_em, j: j }; idbGravar("lista", L.PAC); L.ORIGEM = "banco"; montar();
      });
    });
  }, function (e) {
    // sem o servidor: abre com a cópia guardada, avisando
    return idbLer("lista").then(function (c) {
      if (!c) throw e;
      L.PAC = c; L.ORIGEM = "offline"; L.toast("Sem conexão com o servidor: mostrando a lista guardada neste computador", "erro");
      montar();
    });
  });
};
/* baixa o pacote só se a versão mudou; devolve true se remontou */
L.atualizarAoVivo = function (ver) {
  L.ULTIMA_VERSAO = ver; L.CONFERIDO_EM = new Date();
  if (!ver.pacote || (L.PAC && L.PAC.versao === ver.pacote.versao)) return Promise.resolve(false);
  return baixarPacote(ver.pacote.versao).then(function (j) {
    L.PAC = { versao: ver.pacote.versao, gerado_em: ver.pacote.gerado_em, j: j }; idbGravar("lista", L.PAC); L.ORIGEM = "banco"; montar(); return true;
  });
};

/* ------------------------------ a ponte até o agente ------------------------------ */
L.pedirAtualizacao = function () {
  return fetch("api/atualizar", { method: "POST", cache: "no-store" }).then(function (r) {
    if (r.status === 404) return { agente: false, mensagem: "Este painel ainda não tem a ponte com o agente." };
    return r.ok ? r.json() : erroHttp(r, "o pedido de leitura do WinThor");
  });
};
L.esperarPedido = function (id, limiteMs) {
  var fim = Date.now() + (limiteMs || 45000);
  return new Promise(function (ok, falha) {
    (function olhar() {
      fetch("api/versao?pedido=" + encodeURIComponent(id) + "&_=" + Date.now(), { cache: "no-store" })
        .then(function (r) { return r.ok ? r.json() : erroHttp(r, "o pedido de leitura do WinThor"); })
        .then(function (v) {
          var p = v.pedido;
          if (p && /^(atendido|erro|expirado)$/.test(p.status)) return ok(v);
          if (Date.now() > fim) { v.pedido = Object.assign({}, p || {}, { status: "demorou" }); return ok(v); }
          setTimeout(olhar, 600);
        }, falha);
    })();
  });
};
/* o que mudou no WinThor, em português, a partir da resposta do agente */
// [singular, plural, "nova(s)" ou "novo(s)"]
var NOMES_FLUXO = {
  "pendencias.verba": ["verba", "verbas", "a"], "pendencias.lancamento": ["lançamento", "lançamentos", "o"],
  "pendencias.avaria": ["produto avariado", "produtos avariados", "o"], "pendencias.saldo": ["saldo guardado", "saldos guardados", "o"],
  "pendencias.fornecedor": ["fornecedor no cadastro", "fornecedores no cadastro", "o"],
};
L.textoMudancas = function (p) {
  var d = (p && p.detalhe) || {}, partes = [];
  Object.keys(NOMES_FLUXO).forEach(function (k) {
    var x = d[k]; if (!x) return;
    var n = NOMES_FLUXO[k], q = function (v) { return L.fInt(v) + " " + (v === 1 ? n[0] : n[1]); };
    if (x.novas) partes.push(q(x.novas) + " nov" + n[2] + (x.novas === 1 ? "" : "s"));
    if (x.alteradas) partes.push(q(x.alteradas) + (x.alteradas === 1 ? " mudou" : " mudaram"));
    if (x.apagadas) partes.push(q(x.apagadas) + (x.apagadas === 1 ? " saiu" : " saíram"));
  });
  return partes.length ? partes.join(", ") : "nada mudou desde a última leitura";
};

/* ------------------------------ o detalhe de um fornecedor ------------------------------ */
L.lerFornecedor = function (cod) {
  return fetch("api/fornecedor?cod=" + encodeURIComponent(cod) + "&_=" + Date.now(), { cache: "no-store" })
    .then(function (r) { return r.ok ? r.json() : erroHttp(r, "o fornecedor " + cod); });
};

/* ------------------------------ montar a lista ------------------------------ */
/* L.F: um objeto por fornecedor. pend = alguma das três rotinas com valor (≠ R$ 0,00). */
L.F = []; L.PORCOD = new Map();
function montar() {
  var r = L.PAC.j.r, n = r.n, F = new Array(n), por = new Map(), compradores = new Map();
  for (var i = 0; i < n; i++) {
    var sa = r.sa[i] == null ? 0 : +r.sa[i], sf = r.sf[i] == null ? 0 : +r.sf[i], av = r.av[i] == null ? 0 : +r.av[i];
    var f = {
      c: r.c[i], n: r.n_[i] || "(sem cadastro)", fa: r.fa[i] || "", cj: r.cj[i] || "", uf: r.uf[i] || "", ci: r.ci[i] || "",
      cc: r.cc[i], cp: r.cp[i] || "", pr: r.pr[i], rv: !!r.rv[i], at: !!r.at[i], bl: !!r.bl[i],
      sa: sa, nva: r.nva[i], nv: r.nv[i], sf: sf, sg: r.sg[i] == null ? null : +r.sg[i], nl: r.nl[i],
      av: av, npa: r.npa[i], qta: r.qta[i] == null ? 0 : +r.qta[i], um: r.um[i],
      // 1825: o saldo final soma o grupo do principal (cadastro). pg = principal; sfp = o que este código lançou e
      // que entra no saldo do principal (só quando o principal é outro); ng = fornecedores somados neste código
      pg: r.pg ? r.pg[i] : r.c[i], sfp: r.sfp && r.sfp[i] != null ? +r.sfp[i] : 0, ng: r.ng ? r.ng[i] : 0,
      // 8073: a avaria também soma no principal (desde 2026-10-28); avp = a avaria deste código que vai para o principal
      avp: r.avp && r.avp[i] != null ? +r.avp[i] : 0, nga: r.nga ? r.nga[i] : 0,
    };
    f.membro = f.pg != null && f.pg !== f.c;
    f.t1809 = Math.abs(sa) >= 0.005; f.t1825 = Math.abs(sf) >= 0.005; f.t8073 = av >= 0.005;
    f.pend = f.t1809 || f.t1825 || f.t8073;
    f.busca = L.norm(f.c + " " + f.n + " " + f.fa + " " + f.cj + " " + String(f.cj).replace(/\D/g, ""));
    F[i] = f; por.set(f.c, f);
    if (f.cc != null && f.cp) compradores.set(f.cc, f.cp);
  }
  L.F = F; L.PORCOD = por;
  L.COMPRADORES = Array.from(compradores.entries()).map(function (x) { return { id: x[0], n: x[1] }; }).sort(function (a, b) { return a.n.localeCompare(b.n, "pt-BR"); });
  L.META = { gerado_em: L.PAC.gerado_em, hoje: L.PAC.j.meta.hoje, totais: L.PAC.j.meta };
}

/* ------------------------------ formatos daqui ------------------------------ */
L.fCnpj = function (s) {
  var d = String(s || "").replace(/\D/g, "");
  return d.length === 14 ? d.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5") : String(s || "");
};
L.fHora = function (iso) { return iso ? new Date(iso).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit", second: "2-digit" }) : "—"; };
L.destacar = function (texto, termos) {
  var t = String(texto == null ? "" : texto), nt = L.norm(t), marcas = [];
  termos.forEach(function (q) { var i = nt.indexOf(q); if (q && i >= 0) marcas.push([i, i + q.length]); });
  if (!marcas.length) return L.esc(t);
  marcas.sort(function (a, b) { return a[0] - b[0]; });
  var out = "", pos = 0;
  marcas.forEach(function (m) { if (m[0] < pos) return; out += L.esc(t.slice(pos, m[0])) + "<mark>" + L.esc(t.slice(m[0], m[1])) + "</mark>"; pos = m[1]; });
  return out + L.esc(t.slice(pos));
};
/* texto dos filtros que vai dentro da planilha (padrão da casa) */
L.descricaoFiltros = function () { return L.textoFiltros ? L.textoFiltros() : "Sem filtros"; };

})();
