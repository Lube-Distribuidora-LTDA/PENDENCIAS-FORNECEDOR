/* =============================================================================
 * app.js — a lista de fornecedores: filtros, os números das três rotinas, a tabela,
 * a busca, o ao vivo (AGENTE LUBE) e o botão Atualizar. O clique num fornecedor abre
 * a tela dele (fornecedor.js).
 * ========================================================================== */
(function () {
"use strict";
var L = window.L;
var F = L.estado.filtros = { sit: "todos", rot: [], comp: [] };
var tabEl = null, ordPadrao = { id: "sa", desc: true };
var ROTINAS = [
  { id: "1809", campo: "sa", rot: "Saldo a aplicar", ic: "dinheiro", cls: "r1809", tit: "Relação de verbas por fornecedor" },
  { id: "1825", campo: "sf", rot: "Saldo final", ic: "carteira", cls: "r1825", tit: "Débito e crédito de fornecedor" },
  { id: "8073", campo: "av", rot: "Valor avaria", ic: "alerta", cls: "r8073", tit: "AVARIA 2" },
];

/* ------------------------------ filtros ------------------------------ */
function filtrados(ignorar) {
  var comp = F.comp.length ? new Set(F.comp) : null;
  return L.F.filter(function (f) {
    if (ignorar !== "sit") { if (F.sit === "pend" && !f.pend) return false; if (F.sit === "sem" && f.pend) return false; }
    if (ignorar !== "rot" && F.rot.length && !F.rot.some(function (r) { return f["t" + r]; })) return false;
    if (ignorar !== "comp" && comp && !comp.has(f.cc)) return false;
    return true;
  });
}
function nomeComprador(id) { var c = L.COMPRADORES.filter(function (x) { return x.id === id; })[0]; return c ? c.n : String(id); }
L.textoFiltros = function () {
  var p = [];
  p.push(F.sit === "pend" ? "Só fornecedores com pendência" : F.sit === "sem" ? "Só fornecedores sem pendência" : "Todos os fornecedores");
  if (F.rot.length) p.push("Rotina: " + F.rot.map(function (r) { return r + " " + ROTINAS.filter(function (x) { return x.id === r; })[0].rot; }).join(", "));
  if (F.comp.length) p.push("Comprador: " + F.comp.map(nomeComprador).join(", "));
  p.push("Período " + periodoLista() + " · todas as filiais");
  return p.join(" · ");
};
function mudou() { construirFiltros(); renderizar(); }
/* chip da casa: de "Todos", o clique escolhe só aquele; depois cada clique soma ou tira; vazio = todos */
function alternarLista(lista, v, total) {
  var i = lista.indexOf(v);
  if (i >= 0) lista.splice(i, 1); else lista.push(v);
  if (total && lista.length >= total) lista.length = 0;
}

function construirFiltros() {
  var fx = L.limpar(L.$("faixa-filtros"));
  fx.appendChild(L.h("span", { class: "fx-rot", html: L.ic("filtro") + "Situação" }));
  var base = filtrados("sit"), nPend = base.filter(function (f) { return f.pend; }).length;
  [["todos", "Todos", base.length], ["pend", "Com pendência", nPend], ["sem", "Sem pendência", base.length - nPend]].forEach(function (o) {
    fx.appendChild(L.h("button", { class: "fx-btn" + (F.sit === o[0] ? " on" : ""), type: "button", onclick: function () { F.sit = o[0]; mudou(); } },
      o[1], L.h("span", { class: "ct", text: L.fInt(o[2]) })));
  });
  fx.appendChild(L.h("span", { class: "fx-sep" }));
  fx.appendChild(L.h("span", { class: "fx-rot", text: "Rotina" }));
  var baseR = filtrados("rot");
  ROTINAS.forEach(function (r) {
    var n = baseR.filter(function (f) { return f["t" + r.id]; }).length;
    fx.appendChild(L.h("button", { class: "fx-btn" + (F.rot.indexOf(r.id) >= 0 ? " on" : ""), type: "button", title: "Rotina " + r.id + " · " + r.tit + ": fornecedores com valor nela",
      onclick: function () { alternarLista(F.rot, r.id, 3); mudou(); } }, r.id + " · " + r.rot, L.h("span", { class: "ct", text: L.fInt(n) })));
  });
  fx.appendChild(L.h("span", { class: "fx-sep" }));
  var bc = L.h("button", { class: "fx-btn" + (F.comp.length ? " on" : ""), type: "button", onclick: function (ev) { abrirCompradores(ev.currentTarget); } },
    L.h("span", { html: L.ic("pessoas") }), F.comp.length === 1 ? nomeComprador(F.comp[0]) : "Comprador",
    F.comp.length > 1 ? L.h("span", { class: "n", text: String(F.comp.length) }) : null, L.h("span", { html: L.ic("baixo") }));
  fx.appendChild(bc);
  if (F.sit !== "todos" || F.rot.length || F.comp.length) {
    fx.appendChild(L.h("button", { class: "fx-limpar", type: "button", text: "Limpar filtros", onclick: function () { F.sit = "todos"; F.rot = []; F.comp = []; mudou(); } }));
  }
  // fixo, como o Júlio pediu: começa sempre em 01/01/2011, termina no dia de hoje, todas as filiais
  fx.appendChild(L.h("span", { class: "fx-periodo", title: "Período fixo das rotinas: começa sempre em 01/01/2011 e vai até hoje, com todas as filiais",
    html: L.ic("calendario") + "<b>" + L.esc(periodoLista()) + "</b> · todas as filiais" }));
}

var popAberto = null;
function fecharPop() { if (popAberto) { popAberto.remove(); popAberto = null; } }
L.fecharPopover = fecharPop;
function abrirCompradores(ancora) {
  fecharPop();
  var base = filtrados("comp"), cont = new Map();
  base.forEach(function (f) { if (f.cc != null) cont.set(f.cc, (cont.get(f.cc) || 0) + 1); });
  var itens = L.COMPRADORES.filter(function (c) { return cont.has(c.id); });
  var pop = L.h("div", { class: "pop" }), inp = L.h("input", { type: "search", placeholder: "Buscar comprador…", autocomplete: "off" }), lista = L.h("div", { class: "pop-lista" });
  function desenhar() {
    var q = L.norm(inp.value).split(/\s+/).filter(Boolean);
    L.limpar(lista);
    var vis = itens.filter(function (c) { var n = L.norm(c.n + " " + c.id); return q.every(function (x) { return n.indexOf(x) >= 0; }); });
    if (!vis.length) lista.appendChild(L.h("div", { class: "pop-vazio", text: "Nenhum comprador" }));
    vis.forEach(function (c) {
      var on = F.comp.indexOf(c.id) >= 0;
      lista.appendChild(L.h("button", { class: "pop-item" + (on ? " on" : ""), type: "button", onclick: function () { alternarLista(F.comp, c.id, itens.length); construirFiltros(); renderizar(); desenhar(); } },
        L.h("span", { class: "cx" }), L.h("span", { class: "tx", html: L.destacar(c.n, q) }), L.h("span", { class: "cn", text: L.fInt(cont.get(c.id)) })));
    });
  }
  inp.addEventListener("input", desenhar);
  pop.appendChild(L.h("div", { class: "pop-topo" }, inp));
  pop.appendChild(lista);
  pop.appendChild(L.h("div", { class: "pop-rodape" }, L.h("span", { text: F.comp.length ? L.fInt(F.comp.length) + " escolhido(s)" : "Todos os compradores" }),
    L.h("button", { class: "mini-btn", type: "button", text: "Todos", onclick: function () { F.comp = []; fecharPop(); mudou(); } })));
  desenhar();
  document.body.appendChild(pop); popAberto = pop;
  var r = ancora.getBoundingClientRect(); pop.style.left = Math.max(8, Math.min(innerWidth - 328, r.left)) + "px"; pop.style.top = (r.bottom + 6) + "px";
  setTimeout(function () { inp.focus(); }, 0);
}
document.addEventListener("mousedown", function (ev) { if (popAberto && !popAberto.contains(ev.target) && !ev.target.closest(".fx-btn")) fecharPop(); });

/* ------------------------------ a página ------------------------------ */
function moedaCel(v) {
  if (v == null || Math.abs(v) < 0.005) return { html: '<span class="zero">—</span>' };
  return { html: '<span class="' + (v < 0 ? "neg" : "") + '">' + L.esc(L.fBRL(v)) + "</span>" };
}
/* valor de código que soma outros fornecedores (o grupo do principal): sublinhado pontilhado e a dica dizem quanto é só dele */
function grupoCel(v, proprio, oque) {
  var c = moedaCel(v);
  if (v != null && Math.abs(v - (proprio || 0)) >= 0.005)
    c.html = '<span class="com-grupo" title="Como na rotina: soma os ' + oque + ' deste código (' + L.esc(L.fBRL(proprio || 0)) + ') e os dos fornecedores que têm ele como principal">' + c.html + "</span>";
  return c;
}
/* 1825: todo código mostra a conta corrente do grupo do principal dele, como a rotina; a dica diz quanto é só dele */
function contaCel(v, r) {
  var c = moedaCel(v);
  if (v != null && Math.abs(v - (r.sfo || 0)) >= 0.005)
    c.html = '<span class="com-grupo" title="Como na rotina 1825: a conta corrente do grupo do principal ' + L.esc(r.pg) + " (" + L.fInt(r.ng) +
      ' fornecedores com lançamento); todo código do grupo mostra este saldo. Só deste código: ' + L.esc(L.fBRL(r.sfo || 0)) + '">' + c.html + "</span>";
  return c;
}
function periodoLista() { var h = (L.META || {}).hoje; return "01/01/2011 a " + (h ? L.fData(h) : "hoje"); }
/* filiais que a 8073 não soma, como o relatório da rotina (pendencias.filial_fora_8073, vem no pacote) */
function fora8073() {
  var f = ((L.META || {}).totais || {}).fora_8073 || ["7", "11"];
  return f.length === 1 ? "a filial " + f[0] : "as filiais " + f.slice(0, -1).join(", ") + " e " + f[f.length - 1];
}
/* soma da 1825 sem repetir: cada grupo do principal entra uma vez (os códigos do grupo mostram o mesmo saldo) */
function somaGrupos(lin) {
  var vistos = new Set(), s = 0;
  lin.forEach(function (f) { if (!vistos.has(f.pg)) { vistos.add(f.pg); s += f.sf; } });
  return s;
}
/* soma da 8073 (avo) sem contar duas vezes: cada código entra com o que é só dele, mais os fornecedores que somam num
   principal da lista sem estarem nela. Com um principal só, dá o mesmo valor da linha dele. */
function somaUnica(lin, k) {
  var em = new Set(), s = 0;
  lin.forEach(function (f) { em.add(f.c); s += f[k]; });
  L.F.forEach(function (m) { if (m.membro && em.has(m.pg) && !em.has(m.c)) s += m[k]; });
  return s;
}
function renderizar() {
  if (!L.F.length) return;
  var cont = L.$("conteudo"), lin = filtrados();
  var est = tabEl && tabEl.estado ? { pag: tabEl.estado.pag, porPag: tabEl.estado.porPag, ord: tabEl.estado.ord, busca: tabEl.estado.busca, todas: tabEl.estado.todas } : null;
  var raiz = L.h("div", { class: "pagina" });

  // os números das três rotinas (com os filtros)
  var t = { sa: 0, nva: 0, npa: 0, f1809: 0, f1825: 0, f8073: 0, pend: 0 }, contas = new Set();
  lin.forEach(function (f) {
    t.sa += f.sa; t.nva += f.nva; t.npa += f.npa;
    if (f.t1809) t.f1809++; if (f.t1825) { t.f1825++; contas.add(f.pg); } if (f.t8073) t.f8073++; if (f.pend) t.pend++;
  });
  t.sf = somaGrupos(lin); t.av = somaUnica(lin, "avo");
  var legs = {
    "1809": L.fInt(t.f1809) + " fornecedores · " + L.fInt(t.nva) + " verbas com saldo",
    // a 1825 é por grupo do principal (migração 09): o número conta as contas correntes, não os códigos que mostram cada uma
    "1825": L.fInt(contas.size) + (contas.size === 1 ? " conta com saldo" : " contas com saldo") + " (grupo do principal) · todas as filiais · " + periodoLista(),
    // as filiais que a rotina não soma vêm do banco (pendencias.filial_fora_8073, migrações 08 e 11)
    "8073": L.fInt(t.f8073) + " fornecedores · " + L.fInt(t.npa) + " produtos avariados · como a rotina, sem " + fora8073(),
  };
  var kpis = L.kpis();
  ROTINAS.forEach(function (r) {
    var v = t[r.campo], so = F.rot.length === 1 && F.rot[0] === r.id;
    var k = L.kpi({ icone: r.ic, rot: r.rot, valor: v, fmt: function (x) { return L.fBRL(x); }, classe: r.cls + (Math.abs(v) < 0.005 ? " zero" : "") + (so ? " ativo" : ""),
      leg: legs[r.id], ajuda: "Rotina " + r.id + " · " + r.tit + ". Clique para ver só os fornecedores com valor nela.",
      aoClicar: function () {
        F.rot = so ? [] : [r.id];
        if (!so && tabEl && tabEl.estado) { tabEl.estado.ord = { id: r.campo, desc: true }; tabEl.estado.pag = 0; }
        mudou();
      } });
    k.querySelector(".rot").appendChild(L.h("small", { text: r.id }));
    if (v < -0.005) k.querySelector(".val").classList.add("neg");
    kpis.appendChild(k);
  });
  kpis.appendChild(L.kpi({ icone: "caixa", rot: "Com pendência", texto: L.fInt(t.pend) + " de " + L.fInt(lin.length), classe: "heroi",
    leg: "fornecedores com valor em alguma das três rotinas", ajuda: "Clique para ver só eles",
    aoClicar: function () { F.sit = F.sit === "pend" ? "todos" : "pend"; mudou(); } }));
  raiz.appendChild(kpis);

  // a tabela
  var cols = [
    { id: "c", titulo: "Código", valor: function (r) { return r.c; }, fmt: function (v) { return { html: '<span class="cod">' + L.esc(v) + "</span>" }; }, alinhar: "esq", exportarTipo: "inteiro", somar: false },
    { id: "n", titulo: "Fornecedor", tipo: "texto", valor: function (r) { return r.n; },
      fmt: function (v, r) { return { html: '<span class="forn-nome"><b>' + L.esc(v) + "</b>" + (r.fa && r.fa !== v ? "<small>" + L.esc(r.fa) + "</small>" : "") + "</span>" }; }, titleTd: function (r) { return r.n + (r.fa ? " · " + r.fa : ""); } },
    { id: "cp", titulo: "Comprador", tipo: "texto", valor: function (r) { return r.cp; } },
    { id: "ro", titulo: "Rotinas", tipo: "tag", valor: function (r) { return (r.t1809 ? 1 : 0) + (r.t1825 ? 1 : 0) + (r.t8073 ? 1 : 0); }, dica: "Em quais das três rotinas o fornecedor tem valor",
      fmt: function (v, r) { return { html: '<span class="rotinas">' + ROTINAS.map(function (x) { return '<i class="' + (r["t" + x.id] ? "on" + x.id : "") + '">' + x.id + "</i>"; }).join("") + "</span>" }; },
      exp: function (r) { return ROTINAS.filter(function (x) { return r["t" + x.id]; }).map(function (x) { return x.id; }).join(", "); }, exportarTipo: "texto" },
    { id: "sa", titulo: "Saldo a aplicar", tipo: "moeda", valor: function (r) { return r.sa; }, fmt: moedaCel, exportarTipo: "moeda", barra: true, dica: "Rotina 1809: valor das verbas menos o aplicado" },
    { id: "sf", titulo: "Saldo final", tipo: "moeda", valor: function (r) { return r.sf; }, exportarTipo: "moeda", barra: true, corBarra: "rgba(167,139,250,.16)",
      dica: "Rotina 1825: débitos − créditos da conta corrente do grupo do principal do cadastro (todo código do grupo mostra o mesmo saldo, como na rotina), todas as filiais do cadastro, de 01/01/2011 até hoje",
      fmt: contaCel },
    { id: "av", titulo: "Valor avaria", tipo: "moeda", valor: function (r) { return r.av; }, exportarTipo: "moeda", barra: true, corBarra: "rgba(255,107,116,.16)",
      dica: "Rotina 8073: quantidade avariada × valor da última entrada: a deste código + a dos fornecedores que têm ele como principal; todas as filiais menos " + fora8073().replace(/^(a|as) /, "") + ", como o relatório da rotina",
      fmt: function (v, r) { return grupoCel(v, r.avo, "produtos"); } },
    { id: "fa", titulo: "Fantasia", tipo: "texto", valor: function (r) { return r.fa; }, essencial: false },
    { id: "cj", titulo: "CNPJ", tipo: "texto", valor: function (r) { return r.cj ? L.fCnpj(r.cj) : ""; }, essencial: false },
    { id: "ci", titulo: "Cidade / UF", tipo: "texto", valor: function (r) { return [r.ci, r.uf].filter(Boolean).join(" / "); }, essencial: false },
    { id: "nva", titulo: "Verbas com saldo", tipo: "inteiro", valor: function (r) { return r.nva; }, essencial: false },
    { id: "nl", titulo: "Lançamentos", tipo: "inteiro", valor: function (r) { return r.nl; }, essencial: false },
    { id: "pg", titulo: "Principal", tipo: "texto", valor: function (r) { return r.pg; }, essencial: false, dica: "Fornecedor principal no cadastro: a 1825 mostra a conta corrente do grupo dele" },
    { id: "npa", titulo: "Produtos avariados", tipo: "inteiro", valor: function (r) { return r.npa; }, essencial: false },
    { id: "um", titulo: "Último movimento", tipo: "data", valor: function (r) { return r.um; }, essencial: false },
    { id: "cad", titulo: "Cadastro", tipo: "texto", valor: function (r) { return !r.at ? "Excluído" : r.bl ? "Bloqueado" : r.rv ? "Revenda" : "Ativo"; }, essencial: false },
  ];
  tabEl = L.tabela({
    titulo: "Pendências Fornecedor", arquivo: "pendencias-fornecedores", aba: "Fornecedores", porPagina: est ? est.porPag : 50,
    linhas: lin, ordem: est && est.ord ? est.ord : ordPadrao, todasColunas: est ? est.todas : false,
    buscaTexto: function (r) { return r.busca; }, buscaDica: "Buscar por código, nome ou CNPJ…",
    totais: function (res) {
      var l = res.todas || res.linhas, s = function (k) { var x = 0; l.forEach(function (f) { x += f[k]; }); return x; };
      return [{ rot: "Fornecedores", valor: L.fInt(l.length) }, { rot: "Saldo a aplicar", valor: L.fBRL(s("sa")) },
              { rot: "Saldo final", valor: L.fBRL(somaGrupos(l)) }, { rot: "Valor avaria", valor: L.fBRL(somaUnica(l, "avo")) }];
    },
    colunas: cols,
    aoClicar: function (r) { L.abrirFornecedor(r.c); },
    vazioTitulo: "Nenhum fornecedor", vazio: "Nenhum fornecedor com os filtros atuais.",
  });
  if (est) { tabEl.estado.pag = est.pag; tabEl.estado.busca = est.busca || ""; tabEl.recarregar(); }
  raiz.appendChild(L.painel({ titulo: "Fornecedores", sub: "Clique em um fornecedor para abrir as pendências dele (o WinThor responde na hora)", corpo: tabEl, semPad: true }));
  L.limpar(cont).appendChild(raiz);
}
L.aoMudarLista = function () { L.semAnimar = true; rodape(); construirFiltros(); renderizar(); mostrarVivo(); setTimeout(function () { L.semAnimar = false; }, 1500); };

/* ------------------------------ menu e rodapé ------------------------------ */
function construirMenu() {
  var nav = L.limpar(L.$("menu-itens"));
  nav.appendChild(L.h("div", { class: "grupo-menu", text: "Pendências" }));
  nav.appendChild(L.h("button", { class: "item-menu ativo", type: "button", html: L.ic("caixa") + "<span>Fornecedores</span>",
    onclick: function () { L.fecharFornecedor(); document.body.classList.remove("menu-aberto"); window.scrollTo({ top: 0 }); } }));
  rodape();
}
function rodape() {
  var a = (L.ULTIMA_VERSAO || {}).agente || {}, M = L.META || {}, tt = M.totais || {};
  L.$("menu-rodape").innerHTML =
    '<div><span class="vivo"></span><b>Lido no WinThor às ' + L.esc(L.fHora(a.lido_em)) + "</b></div>" +
    "<div>Pelo AGENTE LUBE · lista de " + L.esc(L.fHora(M.gerado_em)) + (L.ORIGEM === "offline" ? " · <b>sem conexão</b>" : "") + "</div>" +
    "<div>" + L.fInt(tt.fornecedores) + " fornecedores · " + L.fInt(tt.verbas) + " verbas · " + L.fInt(tt.lancamentos) + " lançamentos · " + L.fInt(tt.avarias) + " linhas de avaria</div>" +
    '<div class="versao">versão ' + L.esc(window.VERSAO || "") + "</div>";
}

/* ------------------------------ busca: código, nome ou CNPJ → abre o fornecedor ------------------------------ */
function iniciarBusca() {
  var inp = L.$("busca-global"), box = L.$("busca-box"), pop = null;
  function fechar() { if (pop) { pop.remove(); pop = null; } }
  function buscar() {
    var bruto = inp.value.trim(), q = L.norm(bruto).split(/\s+/).filter(Boolean);
    fechar();
    if (!q.length) return;
    var exato = /^\d+$/.test(bruto) ? L.PORCOD.get(+bruto) : null, achou = exato ? [exato] : [];
    for (var i = 0; i < L.F.length && achou.length < 60; i++) { var f = L.F[i]; if (f !== exato && q.every(function (x) { return f.busca.indexOf(x) >= 0; })) achou.push(f); }
    achou = achou.slice(0, 1).concat(achou.slice(1).sort(function (a, b) { return (b.pend - a.pend) || (Math.abs(b.sa) + Math.abs(b.sf) + b.av - Math.abs(a.sa) - Math.abs(a.sf) - a.av); })).slice(0, 10);
    pop = L.h("div", { class: "pop", style: { width: "460px", maxHeight: "72vh" } });
    var lista = L.h("div", { class: "pop-lista" }), primeiro = null;
    if (!achou.length) lista.appendChild(L.h("div", { class: "pop-vazio", text: "Nenhum fornecedor para “" + bruto + "”" }));
    achou.forEach(function (f) {
      var resumo = f.pend ? [f.t1809 ? "1809 " + L.fAbrev(f.sa, true) : "", f.t1825 ? "1825 " + L.fAbrev(f.sf, true) : "", f.t8073 ? "8073 " + L.fAbrev(f.av, true) : ""].filter(Boolean).join(" · ") : "sem pendência";
      var b = L.h("button", { class: "pop-item", type: "button", onclick: function () { fechar(); inp.value = ""; inp.blur(); L.abrirFornecedor(f.c); } },
        L.h("span", { class: "cod", html: L.destacar(String(f.c), q) }), L.h("span", { class: "tx", html: L.destacar(f.n, q), title: f.n }), L.h("span", { class: "pend", text: resumo }));
      if (!primeiro) primeiro = b;
      lista.appendChild(b);
    });
    pop.appendChild(lista); pop._primeiro = primeiro;
    var r = box.getBoundingClientRect();
    pop.style.left = Math.max(8, Math.min(innerWidth - 468, r.left)) + "px"; pop.style.top = (r.bottom + 6) + "px";
    document.body.appendChild(pop);
  }
  inp.addEventListener("input", L.debounce(buscar, 120));
  inp.addEventListener("keydown", function (ev) { if (ev.key === "Enter" && pop && pop._primeiro) pop._primeiro.click(); if (ev.key === "Escape") { fechar(); inp.value = ""; inp.blur(); } });
  document.addEventListener("mousedown", function (ev) { if (pop && !pop.contains(ev.target) && !box.contains(ev.target)) fechar(); });
  document.addEventListener("keydown", function (ev) { if (ev.key === "/" && !/^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName)) { ev.preventDefault(); inp.focus(); } });
}

/* ------------------------------ tema ------------------------------ */
function aplicarTema(t) {
  document.documentElement.setAttribute("data-tema", t);
  try { localStorage.setItem("pf-tema", t); } catch (e) {}
  L.estado.tema = t;
  L.$("btn-tema").innerHTML = L.ic(t === "escuro" ? "sol" : "lua");
}

/* ------------------------------ ao vivo (AGENTE LUBE) ------------------------------ */
/* De 15 em 15 s, com a aba à vista, pergunta se o pacote mudou (/api/versao). Se o agente remontou, baixa
   e redesenha sem animar, no mesmo filtro; com uma lista de filtro aberta, espera fechar. */
var AO_VIVO_MS = 15000, vivoOcupado = false;
function mostrarVivo() {
  var el = L.$("ao-vivo"); if (!el) return;
  var a = (L.ULTIMA_VERSAO || {}).agente || {}, vivo = !!a.vivo;
  el.classList.toggle("on", vivo);
  el.querySelector("b").textContent = vivo ? "Ao vivo · " + L.fHora(a.lido_em) : "Agente parado · " + L.fHora(a.lido_em);
  el.title = vivo
    ? "O AGENTE LUBE lê as verbas, a conta corrente e a avaria no WinThor de minuto em minuto, e a tela muda sozinha. Última leitura às " + L.fHora(a.lido_em) + "."
    : "O agente do WinThor não está ligado: o painel mostra o que ele leu por último (" + L.fHora(a.lido_em) + ") e volta a mudar sozinho quando ele voltar.";
}
function cicloAoVivo() {
  if (vivoOcupado || document.hidden || !L.F.length || L.$("btn-atualizar").classList.contains("girando")) return;
  vivoOcupado = true;
  L.versaoNoBanco().then(function (v) {
    if (popAberto) { L.ULTIMA_VERSAO = v; mostrarVivo(); return; }
    return L.atualizarAoVivo(v).then(function (mudou) {
      if (mudou) { L.aoMudarLista(); if (L.fornecedorAberto()) L.recarregarFornecedor(); } else { mostrarVivo(); rodape(); }
    });
  }).catch(function (e) {
    console.warn("Ao vivo: não consegui perguntar a versão", e);
    var el = L.$("ao-vivo"); if (el) { el.classList.remove("on"); el.querySelector("b").textContent = "Sem conexão"; }
  }).then(function () { vivoOcupado = false; });
}

/* ------------------------------ botão Atualizar: pede ao agente uma leitura agora ------------------------------ */
function atualizarDados() {
  var b = L.$("btn-atualizar");
  if (b.classList.contains("girando")) return;
  b.classList.add("girando");
  var fim = function () { b.classList.remove("girando"); };
  L.pedirAtualizacao().then(function (r) {
    if (!r || !r.agente) {
      return L.versaoNoBanco().then(function (v) { return L.atualizarAoVivo(v); }).then(function (mudou) {
        if (mudou) L.aoMudarLista(); else mostrarVivo();
        fim(); L.toast((r && r.mensagem ? r.mensagem + " " : "") + "O painel mostra a última leitura (" + L.fHora(((L.ULTIMA_VERSAO || {}).agente || {}).lido_em) + ").", "erro");
      });
    }
    L.toast("Lendo o WinThor agora…", "ok");
    return L.esperarPedido(r.pedido, 45000).then(function (v) {
      return L.atualizarAoVivo(v).then(function (mudou) {
        if (mudou) L.aoMudarLista(); else { mostrarVivo(); rodape(); }
        if (L.fornecedorAberto()) L.recarregarFornecedor();
        fim();
        var p = v.pedido || {};
        L.toast(p.status === "atendido" ? "WinThor lido agora" + (p.segundos != null ? " (" + L.fNum(p.segundos, 1) + " s)" : "") + ": " + L.textoMudancas(p) + "."
          : p.status === "demorou" ? "O agente ainda está lendo o WinThor; a tela muda sozinha assim que terminar."
          : "O agente não conseguiu ler o WinThor agora" + (p.mensagem ? ": " + p.mensagem : "."), p.status === "atendido" ? "ok" : "erro");
      });
    });
  }).catch(function (e) { fim(); L.toast("Não foi possível atualizar: " + (e.message || e), "erro"); });
}

/* ------------------------------ início ------------------------------ */
function iniciar() {
  L.$("ic-busca").innerHTML = L.ic("busca");
  L.$("btn-menu").innerHTML = L.ic("menu");
  L.$("btn-atualizar").innerHTML = L.ic("relogio");
  aplicarTema(document.documentElement.getAttribute("data-tema") || "escuro");
  L.$("btn-tema").addEventListener("click", function () { aplicarTema(L.estado.tema === "escuro" ? "claro" : "escuro"); });
  L.$("btn-menu").addEventListener("click", function () { document.body.classList.toggle("menu-aberto"); });
  L.$("btn-atualizar").addEventListener("click", atualizarDados);

  var cont = L.$("conteudo"), espera = L.espera("Abrindo as pendências dos fornecedores…");
  L.limpar(cont).appendChild(espera);
  var aviso = function (t) { var x = espera.querySelector(".espera-txt div"); if (x) x.textContent = t; };
  if (!window.DecompressionStream) { L.limpar(cont).appendChild(L.erroTela("Navegador antigo", "Este painel precisa do Chrome ou do Edge atualizados.")); return; }
  L.carregarTudo(aviso).then(function () {
    construirMenu(); iniciarBusca(); construirFiltros(); renderizar(); mostrarVivo();
    var m = /#f=(\d+)/.exec(location.hash || "");
    if (m) L.abrirFornecedor(+m[1]);
    setInterval(cicloAoVivo, AO_VIVO_MS);
    document.addEventListener("visibilitychange", function () { if (!document.hidden) cicloAoVivo(); });
  }).catch(function (e) {
    console.error(e);
    L.limpar(cont).appendChild(L.erroTela("Não foi possível carregar os dados", (e && e.message) || String(e)));
  });
}
if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", iniciar); else iniciar();
})();
