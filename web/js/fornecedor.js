/* =============================================================================
 * fornecedor.js — a tela do fornecedor (gaveta lateral), aberta pelo clique na lista
 * ou pela busca.
 *
 * Abre na hora com o que o banco tem e, no mesmo clique, pede ao AGENTE LUBE uma leitura
 * do WinThor (as cinco rotinas, ~2 s): quando ele responde, a tela se refaz com o que veio
 * do WinThor e diz a hora. Em cima, os três números (saldo a aplicar 1809, saldo final 1825,
 * valor avaria 8073); embaixo, cada rotina com as suas linhas, FECHADA até alguém clicar.
 * ========================================================================== */
(function () {
"use strict";
var L = window.L;
var D = { cod: null, j: null, abertas: {}, tok: 0, tabelas: {}, so1809: true };

function el(id) { return L.$(id); }
function soma(a, f) { var s = 0; for (var i = 0; i < a.length; i++) s += +f(a[i]) || 0; return s; }
function qtd(v) { return v == null ? "—" : L.fNum(v, Math.abs(v % 1) > 1e-9 ? 2 : 0); }
function moedaCel(v) {
  if (v == null || Math.abs(v) < 0.005) return { html: '<span class="zero">—</span>' };
  return { html: '<span class="' + (v < 0 ? "neg" : "") + '">' + L.esc(L.fBRL(v)) + "</span>" };
}

/* ------------------------------ abrir e fechar ------------------------------ */
L.fornecedorAberto = function () { return D.cod; };
L.abrirFornecedor = function (cod) {
  cod = +cod;
  if (!cod) return;
  if (D.cod !== cod) { D.abertas = {}; D.so1809 = true; D.j = null; }
  D.cod = cod; D.tok++;
  document.body.style.overflow = "hidden";
  el("dossie-fundo").classList.add("on");
  el("dossie").classList.add("on");
  try { history.replaceState(null, "", "#f=" + cod); } catch (e) {}
  desenharCabecalho();
  if (!D.j) L.limpar(el("dos-corpo")).appendChild(L.h("div", { class: "esq-dos" }, L.h("div", { class: "esqueleto" }), L.h("div", { class: "esqueleto", style: { height: "64px" } }), L.h("div", { class: "esqueleto", style: { height: "64px" } })));
  status("", "Abrindo o fornecedor…");
  var tok = D.tok;
  L.lerFornecedor(cod).then(function (j) {
    if (tok !== D.tok) return;
    D.j = j; desenharCabecalho(); desenharCorpo();
    buscarNoWinThor();
  }).catch(function (e) {
    if (tok !== D.tok) return;
    L.limpar(el("dos-corpo")).appendChild(L.erroTela("Não foi possível abrir o fornecedor", e.message || String(e)));
    status("erro", "Não consegui ler o banco agora.");
  });
};
L.fecharFornecedor = function () {
  if (!D.cod) return;
  D.cod = null; D.tok++;
  el("dossie-fundo").classList.remove("on");
  el("dossie").classList.remove("on");
  document.body.style.overflow = "";
  try { history.replaceState(null, "", location.pathname + location.search); } catch (e) {}
};
/* ao vivo: o pacote mudou com a gaveta aberta — relê o fornecedor sem piscar */
L.recarregarFornecedor = function () {
  if (!D.cod) return Promise.resolve();
  var tok = D.tok, cod = D.cod;
  return L.lerFornecedor(cod).then(function (j) {
    if (tok !== D.tok || cod !== D.cod || chave(j) === chave(D.j)) return;
    D.j = j; desenharCabecalho(); desenharCorpo(true);
  }).catch(function () {});
};

/* ------------------------------ o WinThor responde ------------------------------ */
function buscarNoWinThor() {
  var tok = D.tok, cod = D.cod, t0 = performance.now(), b = el("dos-buscar");
  if (b) b.classList.add("girando");
  status("lendo", "Buscando no WinThor agora…");
  var fim = function () { if (b) b.classList.remove("girando"); };
  L.pedirAtualizacao().then(function (r) {
    if (tok !== D.tok) return fim();
    if (!r || !r.agente) {
      fim();
      var a = (L.ULTIMA_VERSAO || {}).agente || {};
      status("erro", (r && r.mensagem ? r.mensagem + " " : "") + "Mostrando a última leitura" + (a.lido_em ? " (" + L.fHora(a.lido_em) + ")." : "."));
      return;
    }
    return L.esperarPedido(r.pedido, 30000).then(function (v) {
      var p = v.pedido || {};
      return Promise.all([L.lerFornecedor(cod), L.atualizarAoVivo(v)]).then(function (res) {
        fim();
        if (tok !== D.tok) return;
        if (chave(res[0]) !== chave(D.j)) { D.j = res[0]; desenharCabecalho(); desenharCorpo(true); } else D.j = res[0];
        if (res[1] && L.aoMudarLista) L.aoMudarLista();
        var seg = L.fNum((performance.now() - t0) / 1000, 1);
        if (p.status === "atendido") status("ok", "Conferido no WinThor às " + L.fHora(p.atendido_em) + " · " + seg + " s", L.textoMudancas(p));
        else if (p.status === "demorou") status("lendo", "O agente ainda está lendo o WinThor; a tela muda sozinha quando ele terminar.");
        else status("erro", "O agente não conseguiu ler o WinThor agora" + (p.mensagem ? ": " + p.mensagem : "."));
      });
    });
  }).catch(function (e) { fim(); if (tok === D.tok) status("erro", "Não foi possível falar com o agente: " + (e.message || e)); });
}

function status(tipo, texto, extra) {
  var s = el("dos-status"); if (!s) return;
  s.className = "dos-status " + (tipo || "");
  s.innerHTML = "<i></i><b>" + L.esc(texto) + "</b>" + (extra ? "<span>· " + L.esc(extra) + "</span>" : "") +
    '<small title="O painel nunca fala com o WinThor: quem lê é o AGENTE LUBE, na SRV-IA">pelo AGENTE LUBE</small>';
}

/* ------------------------------ cabeçalho ------------------------------ */
function desenharCabecalho() {
  var f = (D.j && D.j.fornecedor) || {}, l = L.PORCOD.get(D.cod) || {};
  var nome = f.fornecedor || l.n || "Fornecedor " + D.cod;
  var sub = L.h("div", { class: "sub" });
  function item(ic, txt, cls) { if (txt) sub.appendChild(L.h("span", { class: cls || "", html: L.ic(ic) + L.esc(txt) })); }
  if (f.fantasia && f.fantasia !== nome) item("loja", f.fantasia);
  item("prancheta", f.cnpj ? "CNPJ " + L.fCnpj(f.cnpj) : "", "cnpj");
  item("pino", [f.cidade, f.uf].filter(Boolean).join(" / "));
  item("pessoas", f.comprador ? "Comprador: " + f.comprador : "");
  if (f.codfornecprinc && +f.codfornecprinc !== D.cod) item("camadas", "Principal: " + f.codfornecprinc + (f.fornecedor_principal ? " · " + f.fornecedor_principal : ""));
  item("calendario", periodo() + " · todas as filiais", "periodo");
  if (f.dtexclusao) sub.appendChild(L.h("span", { html: L.tag("Excluído em " + L.fData(f.dtexclusao), "perigo") }));
  if (f.bloqueio === "S") sub.appendChild(L.h("span", { html: L.tag("Bloqueado", "atencao") }));
  if (f.revenda === "S") sub.appendChild(L.h("span", { html: L.tag("Revenda", "info") }));

  var cab = L.h("div", { class: "dos-cab" },
    L.h("div", { style: { minWidth: 0, flex: 1 } },
      L.h("div", { class: "olho", html: L.ic("caixa") + "Fornecedor · código " + L.esc(D.cod) }),
      L.h("h2", { text: nome }), sub),
    L.h("div", { class: "dos-acoes" },
      L.h("button", { class: "btn pri", id: "dos-buscar", type: "button", html: L.ic("relogio") + "Buscar no WinThor", title: "O agente lê agora no WinThor as verbas, a conta corrente e a avaria", onclick: buscarNoWinThor }),
      L.h("button", { class: "btn-ic", type: "button", title: "Copiar o link deste fornecedor", html: L.ic("link"), onclick: function () {
        var url = location.href.split("#")[0] + "#f=" + D.cod;
        (navigator.clipboard ? navigator.clipboard.writeText(url) : Promise.reject()).then(function () { L.toast("Link do fornecedor copiado", "ok"); }, function () { L.toast("Não foi possível copiar o link", "erro"); });
      } }),
      L.h("button", { class: "btn-ic fechar", type: "button", title: "Fechar (Esc)", html: L.ic("x"), onclick: L.fecharFornecedor })));
  var antigo = el("dossie").querySelector(".dos-cab");
  if (antigo) antigo.replaceWith(cab); else el("dossie").insertBefore(cab, el("dossie").firstChild);
}

/* ------------------------------ corpo: os três números e as três rotinas ------------------------------ */
/* período das rotinas: começa sempre em 01/01/2011 e vai até hoje (o banco manda a data de hoje) */
function periodo() {
  var p = (D.j && (D.j.periodo_1825 || D.j.periodo)) || {};
  return "01/01/2011 a " + (p.ate ? L.fData(p.ate) : L.META && L.META.hoje ? L.fData(L.META.hoje) : "hoje");
}

/* o valor do código soma algum outro fornecedor (que tem ele como principal)? */
function outros(grupo) { return (grupo || []).some(function (g) { return +g.fo !== D.cod; }); }

function totais() {
  var j = D.j || {}, v = j.verbas || [], l = j.lancamentos || [], a = j.avaria || [];
  var deb = soma(l, function (x) { return x.ti === "D" ? x.vl : 0; }), cre = soma(l, function (x) { return x.ti === "C" ? x.vl : 0; });
  return {
    sa: soma(v, function (x) { return x.sa; }), nva: v.filter(function (x) { return Math.abs(x.sa) >= 0.005; }).length, nv: v.length,
    // 1825 como a rotina: a conta corrente do grupo do principal (pg) do cadastro; 8073: o deste código + o dos que têm ele
    // como principal (ng/nga = quantos fornecedores somam, quando há outro além deste)
    deb: deb, cre: cre, sf: deb - cre, nl: l.length, ng: outros(j.grupo) ? (j.grupo || []).length : 0,
    pg: j.grupo_1825 != null ? +j.grupo_1825 : D.cod,
    av: soma(a, function (x) { return x.va; }), npa: a.length, qta: soma(a, function (x) { return x.qt; }), nga: outros(j.avaria_grupo) ? (j.avaria_grupo || []).length : 0,
    filiais8073: (j.avaria_fora || []).length ? "todas as filiais menos a " + j.avaria_fora.map(function (x) { return x.fi; }).join(" e a ") : "todas as filiais",
    // se o principal do cadastro é OUTRO código, este também entra no valor dele (só informação, abaixo das rotinas)
    prin: j.principal || null,
  };
}

function desenharCorpo(manterRolagem) {
  var corpo = el("dos-corpo"), rol = corpo.scrollTop, t = totais();
  var raiz = L.h("div");
  D.cards = {};
  var defs = [
    { id: "1809", cls: "r1809", ic: "dinheiro", rot: "Saldo a aplicar", val: t.sa,
      leg: t.nv ? L.fInt(t.nva) + " de " + L.fInt(t.nv) + (t.nv === 1 ? " verba" : " verbas") + " com saldo" : "Nenhuma verba",
      abrir: "Ver as verbas", tit: "Relação de verbas por fornecedor", sub: L.fInt(t.nv) + (t.nv === 1 ? " verba" : " verbas") + " · " + L.fInt(t.nva) + " com saldo a aplicar", corpo: corpo1809 },
    { id: "1825", cls: "r1825", ic: "carteira", rot: "Saldo final", val: t.sf,
      leg: t.nl ? "Débitos " + L.fBRL(t.deb) + " · créditos " + L.fBRL(t.cre) + (t.ng ? " · grupo do " + t.pg + ", " + t.ng + " fornecedores" : "") : "Nenhum lançamento",
      abrir: "Ver a conta corrente", tit: "Débito e crédito de fornecedor", sub: L.fInt(t.nl) + (t.nl === 1 ? " lançamento" : " lançamentos") + " · todas as filiais · " + periodo() + (t.ng ? " · grupo do principal " + t.pg + ", " + t.ng + " fornecedores" : ""), corpo: corpo1825 },
    { id: "8073", cls: "r8073", ic: "alerta", rot: "Valor avaria", val: t.av,
      leg: t.npa ? L.fInt(t.npa) + (t.npa === 1 ? " produto" : " produtos") + " · " + qtd(t.qta) + " un. avariadas" + (t.nga ? " · soma " + t.nga + (t.nga === 1 ? " fornecedor" : " fornecedores") : "") : "Nenhum produto avariado",
      abrir: "Ver os produtos", tit: "Avaria (AVARIA 2)", sub: L.fInt(t.npa) + (t.npa === 1 ? " produto avariado" : " produtos avariados") + " · " + t.filiais8073 + (t.nga ? " · soma " + t.nga + (t.nga === 1 ? " fornecedor" : " fornecedores") : ""), corpo: corpo8073 },
  ];
  var cards = L.h("div", { class: "tres" }), secoes = L.h("div");
  defs.forEach(function (d) {
    var zero = Math.abs(d.val) < 0.005;
    var k = L.kpi({ icone: d.ic, rot: d.rot, valor: d.val, fmt: function (x) { return L.fBRL(x); }, classe: d.cls + (zero ? " zero" : "") + (D.abertas[d.id] ? " aberto ativo" : ""),
      leg: [L.h("span", { text: d.leg }), L.h("span", { class: "abrir", html: L.esc(D.abertas[d.id] ? "Fechar" : d.abrir) + L.ic("dir") })],
      ajuda: "Rotina " + d.id + " do WinThor · clique para " + (D.abertas[d.id] ? "fechar" : "ver") + " as linhas",
      aoClicar: function () { alternar(d.id, true); } });
    k._abrir = d.abrir; D.cards[d.id] = k;
    k.querySelector(".rot").appendChild(L.h("small", { text: d.id }));
    if (d.val < -0.005) k.querySelector(".val").classList.add("neg");
    cards.appendChild(k);

    var sec = L.h("section", { class: "rotina" + (D.abertas[d.id] ? " aberta" : ""), id: "rot-" + d.id });
    var cab = L.h("button", { class: "rotina-cab", type: "button", onclick: function () { alternar(d.id); } },
      L.h("span", { class: "sig", text: d.id }),
      L.h("span", { class: "tt" }, L.h("b", { text: d.tit }), L.h("small", { text: d.sub })),
      L.h("span", { class: "vv" + (d.val < -0.005 ? " neg" : ""), text: L.fBRL(d.val) }),
      L.h("span", { html: L.ic("dir", "seta") }));
    var corpoSec = L.h("div", { class: "rotina-corpo" });
    sec.appendChild(cab); sec.appendChild(corpoSec);
    sec._montar = function () { if (!corpoSec.firstChild) d.corpo(corpoSec, t); };
    if (D.abertas[d.id]) sec._montar();
    secoes.appendChild(sec);
  });
  raiz.appendChild(cards);
  raiz.appendChild(secoes);
  raiz.appendChild(L.nota("Cada rotina abre ao clicar no número ou na linha dela. As linhas vêm do WinThor pelo AGENTE LUBE (a tela nunca fala com o WinThor direto)."));
  L.limpar(corpo).appendChild(raiz);
  if (manterRolagem) corpo.scrollTop = rol;
}

/* abre ou fecha só aquela rotina (as outras ficam como estão, com a busca e a página delas) */
function alternar(id, rolar) {
  var on = D.abertas[id] = !D.abertas[id];
  var sec = el("rot-" + id), card = D.cards && D.cards[id];
  if (sec) { sec.classList.toggle("aberta", on); if (on) sec._montar(); }
  if (card) {
    card.classList.toggle("aberto", on); card.classList.toggle("ativo", on);
    var a = card.querySelector(".abrir"); if (a) a.innerHTML = L.esc(on ? "Fechar" : card._abrir) + L.ic("dir");
  }
  if (on && rolar && sec) setTimeout(function () { sec.scrollIntoView({ behavior: "smooth", block: "start" }); }, 30);
}
/* o que importa do detalhe (sem a hora de leitura): se não mudou, a tela não se refaz */
function chave(j) { return j ? JSON.stringify([j.fornecedor, j.verbas, j.lancamentos, j.lancamento_fora, j.saldos, j.avaria, j.avaria_fora]) : ""; }

function nomeForn() { var f = (D.j && D.j.fornecedor) || {}; return D.cod + " · " + (f.fornecedor || (L.PORCOD.get(D.cod) || {}).n || ""); }

/* ------------------------------ 1809: verbas ------------------------------ */
function corpo1809(box, t) {
  var todas = (D.j.verbas || []).slice();
  if (!todas.some(function (x) { return Math.abs(x.sa) >= 0.005; })) D.so1809 = false;
  // a rotina soma a verba cancelada também (migração 10): a que foi cancelada com o valor zerado e uma aplicação negativa
  // que ficou tem saldo; a nota diz qual é, para ninguém achar que é erro do painel
  var canc = todas.filter(function (x) { return x.dc && Math.abs(x.sa) >= 0.005; });
  var nota = canc.length ? L.h("div", { class: "rotina-nota atencao", html: L.ic("alerta") + "<span>Como na rotina 1809, " +
    (canc.length === 1 ? "esta verba cancelada entra" : "estas verbas canceladas entram") + " no saldo a aplicar: " +
    canc.map(function (x) { return "verba <b>" + L.esc(x.nv) + "</b>, cancelada em " + L.esc(L.fData(x.dc)) + " (valor " + L.esc(L.fBRL(x.vl)) +
      ", aplicado " + L.esc(L.fBRL(x.ap)) + ", saldo <b>" + L.esc(L.fBRL(x.sa)) + "</b>)"; }).join("; ") +
    ". O cancelamento zerou o valor, mas a aplicação ficou no WinThor.</span>" }) : null;
  function desenhar() {
    var linhas = D.so1809 ? todas.filter(function (x) { return Math.abs(x.sa) >= 0.005; }) : todas;
    var tab = L.tabela({
      titulo: "Rotina 1809 — Relação de verbas · " + nomeForn(), arquivo: "pendencias-1809", aba: "Verbas", porPagina: 25,
      linhas: linhas, ordem: { id: "em", desc: true },
      buscaTexto: function (r) { return r.nv + " " + (r.rf || "") + " " + (r.nn || "") + " " + (r.np || ""); }, buscaDica: "Buscar verba, referência, nota…",
      filtrosTexto: function () { return "Fornecedor " + nomeForn() + " · todas as filiais · emissão de " + periodo() + " · " + (D.so1809 ? "só verbas com saldo a aplicar" : "todas as verbas") + " · canceladas inclusive, como a rotina"; },
      extraTopo: function () {
        return L.h("div", { class: "seg" },
          L.h("button", { class: D.so1809 ? "on" : "", text: "Com saldo", title: "Verbas com saldo a aplicar (negativo = aplicado maior que a verba)", onclick: function () { D.so1809 = true; desenhar(); } }),
          L.h("button", { class: D.so1809 ? "" : "on", text: "Todas", onclick: function () { D.so1809 = false; desenhar(); } }));
      },
      totais: function (res) {
        var l = res.todas || res.linhas;
        return [{ rot: "Verbas", valor: L.fInt(l.length) }, { rot: "Valor", valor: L.fBRL(soma(l, function (x) { return x.vl; })) },
                { rot: "Aplicado", valor: L.fBRL(soma(l, function (x) { return x.ap; })) },
                { rot: "Saldo a aplicar", valor: L.fBRL(soma(l, function (x) { return x.sa; })), pri: true }];
      },
      colunas: [
        { id: "nv", titulo: "Verba", valor: function (r) { return r.nv; }, fmt: function (v, r) { return { html: '<span class="cod">' + L.esc(v) + "</span>" + (r.dc ? " " + L.tag("Cancelada", "perigo") : "") }; }, alinhar: "esq", exportarTipo: "inteiro", somar: false, exp: function (r) { return r.nv; } },
        { id: "dc", titulo: "Cancelada em", tipo: "data", valor: function (r) { return r.dc; }, essencial: linhas.some(function (x) { return x.dc; }), dica: "A rotina 1809 soma a verba cancelada também" },
        { id: "fi", titulo: "Filial", tipo: "texto", valor: function (r) { return r.fi; } },
        { id: "em", titulo: "Emissão", tipo: "data", valor: function (r) { return r.em; } },
        { id: "ve", titulo: "Vencimento", tipo: "data", valor: function (r) { return r.ve; } },
        { id: "ti", titulo: "Tipo", tipo: "texto", valor: function (r) { return r.ti; }, dica: "PCVERBA.TIPO, como no WinThor" },
        { id: "fp", titulo: "Forma pgto", tipo: "texto", valor: function (r) { return r.fp; }, dica: "PCVERBA.FORMAPGTO, como no WinThor" },
        { id: "rf", titulo: "Referência", tipo: "texto", valor: function (r) { return r.rf; } },
        { id: "vl", titulo: "Valor", tipo: "moeda", valor: function (r) { return r.vl; } },
        { id: "ap", titulo: "Aplicado", tipo: "moeda", valor: function (r) { return r.ap; }, fmt: moedaCel, exportarTipo: "moeda", dica: "Soma das aplicações (PCAPLICVERBA), estornos descontados" },
        { id: "sa", titulo: "Saldo a aplicar", tipo: "moeda", valor: function (r) { return r.sa; }, fmt: moedaCel, exportarTipo: "moeda", barra: true },
        { id: "ua", titulo: "Última aplicação", tipo: "data", valor: function (r) { return r.ua; } },
        { id: "qa", titulo: "Aplicações", tipo: "inteiro", valor: function (r) { return r.qa; }, essencial: false, dica: "Linhas de aplicação, contando os estornos" },
        { id: "nn", titulo: "Nota", tipo: "texto", valor: function (r) { return r.nn; }, essencial: false },
        { id: "np", titulo: "Pedido", tipo: "texto", valor: function (r) { return r.np; }, essencial: false },
        { id: "cd", titulo: "Débito na conta", tipo: "moeda", valor: function (r) { return r.cd; }, essencial: false, dica: "O que esta verba lançou de débito na conta corrente (1825)" },
        { id: "cr", titulo: "Crédito na conta", tipo: "moeda", valor: function (r) { return r.cr; }, essencial: false, dica: "O que foi abatido desta verba na conta corrente (1825)" },
        { id: "dq", titulo: "Quitação", tipo: "data", valor: function (r) { return r.dq; }, essencial: false },
        { id: "rl", titulo: "Rotina", tipo: "texto", valor: function (r) { return r.rl; }, essencial: false },
      ],
      vazioTitulo: "Nenhuma verba", vazio: D.so1809 ? "Nenhuma verba com saldo a aplicar." : "Este fornecedor não tem verba no WinThor.",
    });
    L.limpar(box);
    if (nota) box.appendChild(nota);
    box.appendChild(tab);
  }
  desenhar();
}

/* ------------------------------ 1825: conta corrente ------------------------------ */
function abrirCod(c) { return '<button type="button" class="link-forn" data-c="' + L.esc(c) + '">' + L.esc(c) + "</button>"; }
function ligarLinks(n) { n.addEventListener("click", function (ev) { var b = ev.target.closest(".link-forn"); if (b && +b.dataset.c !== D.cod) L.abrirFornecedor(+b.dataset.c); }); }

/* as notas de cima da 1825: de que grupo é a conta (com quanto cada fornecedor lançou) e o que a rotina deixa fora */
function notas1825(box, grupo, t) {
  var j = D.j, fora = j.lancamento_fora || [], notas = [];
  if (outros(grupo)) {
    var eu = grupo.filter(function (g) { return +g.fo === D.cod; })[0];
    var nomeP = t.pg === D.cod ? "" : (j.principal && j.principal.n) || (L.PORCOD.get(t.pg) || {}).n || "";
    var lista = grupo.slice().sort(function (a, b) { return Math.abs(b.sd) - Math.abs(a.sd); }), mais = Math.max(0, lista.length - 12);
    notas.push(L.h("div", { class: "rotina-nota info", html: L.ic("camadas") + "<span>Como na rotina 1825, o saldo final é o da conta corrente do grupo do principal " +
      (t.pg === D.cod ? "(este código)" : abrirCod(t.pg) + (nomeP ? " · " + L.esc(nomeP) : "")) + ": todo fornecedor que tem o " + L.esc(t.pg) +
      " como principal no cadastro mostra este mesmo saldo. Só deste código: <b>" + L.esc(L.fBRL(eu ? eu.sd : 0)) + "</b>" +
      (eu ? " (" + L.fInt(eu.nl) + (eu.nl === 1 ? " lançamento)." : " lançamentos).") : " (nenhum lançamento).") + "</span>" +
      '<span class="filiais">' + lista.slice(0, 12).map(function (g) { return abrirCod(g.fo) + " " + L.esc(g.fn || "") + ": <b>" + L.esc(L.fBRL(g.sd)) + "</b>"; }).join(" · ") +
      (mais ? " · e mais " + L.fInt(mais) + (mais === 1 ? " fornecedor" : " fornecedores") + " (veja a coluna Fornecedor)" : "") + "</span>" }));
  }
  // lançamento em filial que não existe no cadastro (PCFILIAL): a rotina com todas as filiais não soma (migração 09)
  if (fora.length)
    notas.push(L.h("div", { class: "rotina-nota", html: L.ic("info") + "<span>Como na rotina 1825, " +
      fora.map(function (x) { return "a filial " + L.esc(x.fi) + " fica fora (" + L.fInt(x.nl) + (x.nl === 1 ? " lançamento, " : " lançamentos, ") + "<b>" + L.esc(L.fBRL(x.va)) + "</b>)"; }).join("; ") +
      ": ela não existe no cadastro de filiais e a rotina com todas as filiais não a soma.</span>" }));
  notas.forEach(function (n) { ligarLinks(n); box.appendChild(n); });
}

/* 8073: quem soma neste código e, se o principal do cadastro é outro, em quem este código entra */
function notasGrupo(box, grupo, rotina, oque, valorDe, valorPrin) {
  var p = D.j.principal, notas = [];
  if (grupo.some(function (g) { return +g.fo !== D.cod; }))
    notas.push(L.h("div", { class: "rotina-nota info", html: L.ic("camadas") + "<span>Como na rotina " + rotina + ", " + oque + " deste código soma os fornecedores que têm ele como principal no cadastro:</span>" +
      '<span class="filiais">' + grupo.map(function (g) { return abrirCod(g.fo) + " " + L.esc(g.fn || "") + ": <b>" + L.esc(L.fBRL(valorDe(g))) + "</b>"; }).join(" · ") + "</span>" }));
  if (p)
    notas.push(L.h("div", { class: "rotina-nota", html: L.ic("info") + "<span>O principal deste código no cadastro é o " + abrirCod(p.c) + (p.n ? " · " + L.esc(p.n) : "") +
      ": na rotina " + rotina + " do " + L.esc(p.c) + " este código também entra (" + L.esc(L.fBRL(valorPrin(p) || 0)) + " lá).</span>" }));
  notas.forEach(function (n) { ligarLinks(n); box.appendChild(n); });
}

function corpo1825(box, t) {
  // Como a rotina 1825 (conferida com o Júlio em 2026-10-28 e 2026-10-29): todas as filiais do cadastro, de 01/01/2011
  // até hoje; o código mostra a conta corrente do grupo do principal dele (todo fornecedor com o mesmo principal).
  var j = D.j, grupo = j.grupo || [];
  notas1825(box, grupo, t);
  box.appendChild(L.tabela({
    titulo: "Rotina 1825 — Débito e crédito de fornecedor · " + nomeForn(), arquivo: "pendencias-1825", aba: "Conta corrente", porPagina: 25,
    linhas: j.lancamentos || [], ordem: { id: "nt", desc: true },
    buscaTexto: function (r) { return r.nt + " " + r.fo + " " + (r.hi || "") + " " + (r.nv || "") + " " + (r.np || "") + " " + (r.fu || ""); }, buscaDica: "Buscar histórico, verba, pedido…",
    filtrosTexto: function () {
      return "Fornecedor " + nomeForn() + (outros(grupo) ? " · conta corrente do grupo do principal " + t.pg + " (" + grupo.length + " fornecedores com lançamento)" : "") +
        " · todas as filiais do cadastro · " + periodo() + " · saldo corrido na ordem da transação";
    },
    totais: function (res) {
      var l = res.todas || res.linhas, d = soma(l, function (x) { return x.ti === "D" ? x.vl : 0; }), c = soma(l, function (x) { return x.ti === "C" ? x.vl : 0; });
      return [{ rot: "Lançamentos", valor: L.fInt(l.length) }, { rot: "Débitos", valor: L.fBRL(d) }, { rot: "Créditos", valor: L.fBRL(c) }, { rot: "Saldo (D − C)", valor: L.fBRL(d - c), pri: true }];
    },
    colunas: [
      { id: "nt", titulo: "Transação", valor: function (r) { return r.nt; }, fmt: function (v) { return { html: '<span class="cod">' + L.esc(v) + "</span>" }; }, alinhar: "esq", exportarTipo: "inteiro", somar: false, exp: function (r) { return r.nt; } },
      { id: "dt", titulo: "Data", tipo: "data", valor: function (r) { return r.dt; }, ordVal: function (r) { return (r.dt || "") + String(r.hr == null ? 0 : r.hr).padStart(2, "0") + String(r.mi == null ? 0 : r.mi).padStart(2, "0"); } },
      { id: "fo", titulo: "Fornecedor", tipo: "texto", valor: function (r) { return r.fo; }, essencial: outros(grupo), dica: "Código do fornecedor que lançou (o grupo soma no principal)" },
      { id: "fi", titulo: "Filial", tipo: "texto", valor: function (r) { return r.fi; } },
      { id: "ti", titulo: "Tipo", tipo: "tag", valor: function (r) { return r.ti; }, fmt: function (v) { return { html: '<span class="tag-tipo ' + L.esc(v) + '">' + (v === "D" ? "Débito" : v === "C" ? "Crédito" : L.esc(v || "")) + "</span>" }; }, exp: function (r) { return r.ti === "D" ? "Débito" : r.ti === "C" ? "Crédito" : r.ti; } },
      { id: "db", titulo: "Débito", tipo: "moeda", valor: function (r) { return r.ti === "D" ? r.vl : null; }, fmt: moedaCel, exportarTipo: "moeda" },
      { id: "cr", titulo: "Crédito", tipo: "moeda", valor: function (r) { return r.ti === "C" ? r.vl : null; }, fmt: moedaCel, exportarTipo: "moeda" },
      { id: "sd", titulo: "Saldo", tipo: "moeda", valor: function (r) { return r.sd; }, fmt: moedaCel, exportarTipo: "moeda", somar: false, dica: "Saldo corrido (débitos − créditos) na ordem da transação" },
      { id: "hi", titulo: "Histórico", tipo: "texto", valor: function (r) { return r.hi; } },
      { id: "nv", titulo: "Verba", tipo: "texto", valor: function (r) { return r.nv; } },
      { id: "fu", titulo: "Quem lançou", tipo: "texto", valor: function (r) { return r.fu; }, essencial: false },
      { id: "rl", titulo: "Rotina", tipo: "texto", valor: function (r) { return r.rl; }, essencial: false },
      { id: "np", titulo: "Pedido", tipo: "texto", valor: function (r) { return r.np; }, essencial: false },
      { id: "ne", titulo: "Transação de entrada", tipo: "texto", valor: function (r) { return r.ne; }, essencial: false },
      { id: "hr", titulo: "Hora", tipo: "texto", valor: function (r) { return r.hr == null ? null : String(r.hr).padStart(2, "0") + ":" + String(r.mi || 0).padStart(2, "0"); }, essencial: false },
      { id: "es", titulo: "Estorno", tipo: "data", valor: function (r) { return r.es; }, essencial: false },
    ],
    vazioTitulo: "Nenhum lançamento", vazio: "Este fornecedor não tem lançamento na conta corrente.",
  }));
}

/* ------------------------------ 8073: avaria ------------------------------ */
/* Como a rotina 8073 (conferida com o Júlio em 2026-10-28): o código mostra a avaria dos produtos dele + a dos fornecedores
   que têm ele como principal no cadastro — o mesmo desenho da 1825. */
function corpo8073(box, t) {
  var j = D.j, grupo = j.avaria_grupo || [], fora = j.avaria_fora || [];
  notasGrupo(box, grupo, "8073", "a avaria", function (g) { return g.va; }, function (p) { return p.av; });
  // a 8073 com todas as filiais não soma a filial 11 (depósito fechado; pendencias.filial_fora_8073): mostra o que ficou fora
  if (fora.length)
    box.appendChild(L.h("div", { class: "rotina-nota", html: L.ic("info") + "<span>Como na rotina 8073, " +
      fora.map(function (x) { return "a filial " + L.esc(x.fi) + " fica fora do valor (" + L.fInt(x.np) + (x.np === 1 ? " produto, " : " produtos, ") + "<b>" + L.esc(L.fBRL(x.va)) + "</b>)"; }).join("; ") +
      ": mesmo com todas as filiais, o relatório da rotina não traz essas linhas.</span>" }));
  box.appendChild(L.tabela({
    titulo: "Rotina 8073 — Avaria · " + nomeForn(), arquivo: "pendencias-8073", aba: "Avaria", porPagina: 25,
    linhas: j.avaria || [], ordem: { id: "va", desc: true },
    buscaTexto: function (r) { return r.cp + " " + (r.ds || "") + " " + (r.fo || ""); }, buscaDica: "Buscar produto por código ou nome…",
    filtrosTexto: function () {
      return "Fornecedor " + nomeForn() + " · estoque avariado de todas as filiais" + (fora.length ? " menos a " + fora.map(function (x) { return x.fi; }).join(" e a ") + " (como a rotina 8073)" : "") +
        (grupo.length > 1 ? " · com os fornecedores que têm ele como principal (" + grupo.map(function (g) { return g.fo; }).join(", ") + ")" : "");
    },
    totais: function (res) {
      var l = res.todas || res.linhas;
      return [{ rot: "Produtos", valor: L.fInt(l.length) }, { rot: "Quantidade", valor: qtd(soma(l, function (x) { return x.qt; })) },
              { rot: "Valor avaria", valor: L.fBRL(soma(l, function (x) { return x.va; })), pri: true }];
    },
    colunas: [
      { id: "cp", titulo: "Código", valor: function (r) { return r.cp; }, fmt: function (v) { return { html: '<span class="cod">' + L.esc(v) + "</span>" }; }, alinhar: "esq", exportarTipo: "inteiro", somar: false, exp: function (r) { return r.cp; } },
      { id: "ds", titulo: "Produto", tipo: "texto", valor: function (r) { return r.ds; } },
      { id: "fo", titulo: "Fornecedor", tipo: "texto", valor: function (r) { return r.fo; }, essencial: outros(grupo), dica: "Fornecedor do produto (o grupo soma no principal)" },
      { id: "fi", titulo: "Filial", tipo: "texto", valor: function (r) { return r.fi; } },
      { id: "em", titulo: "Embalagem", tipo: "texto", valor: function (r) { return r.em; } },
      { id: "qt", titulo: "Qt avariada", tipo: "num", valor: function (r) { return r.qt; }, fmt: qtd, exportarTipo: "moeda" },
      { id: "vu", titulo: "Valor última entrada", tipo: "moeda", valor: function (r) { return r.vu; }, somar: false },
      { id: "va", titulo: "Valor avaria", tipo: "moeda", valor: function (r) { return r.va; }, barra: true, corBarra: "rgba(255,107,116,.16)" },
      { id: "un", titulo: "Unidade", tipo: "texto", valor: function (r) { return r.un; }, essencial: false },
      { id: "qe", titulo: "Estoque", tipo: "num", valor: function (r) { return r.qe; }, fmt: qtd, essencial: false, somar: false },
      { id: "qb", titulo: "Bloqueado", tipo: "num", valor: function (r) { return r.qb; }, fmt: qtd, essencial: false, somar: false },
      { id: "cu", titulo: "Custo última entrada", tipo: "moeda", valor: function (r) { return r.cu; }, essencial: false, somar: false },
      { id: "cf", titulo: "Custo financeiro", tipo: "moeda", valor: function (r) { return r.cf; }, essencial: false, somar: false },
      { id: "de", titulo: "Última entrada", tipo: "data", valor: function (r) { return r.de; }, essencial: false },
    ],
    vazioTitulo: "Nenhum produto avariado", vazio: "Este fornecedor não tem produto com avaria no estoque.",
  }));
}

/* ------------------------------ montar a gaveta ------------------------------ */
function iniciar() {
  var dos = el("dossie");
  dos.appendChild(L.h("div", { class: "dos-status", id: "dos-status" }));
  dos.appendChild(L.h("div", { class: "dos-corpo", id: "dos-corpo" }));
  el("dossie-fundo").addEventListener("click", L.fecharFornecedor);
  document.addEventListener("keydown", function (ev) { if (ev.key === "Escape" && D.cod && !document.querySelector(".pop")) L.fecharFornecedor(); });
}
if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", iniciar); else iniciar();
})();
