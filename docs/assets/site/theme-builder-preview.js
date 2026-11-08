// A prévia do criador de temas: cada componente do layout vira um pedaço de HTML.
// Sem DOM (só `paintBox`, que escreve no `style` do elemento que recebe, e `mount`, que
// cria os elementos no documento do quadro), para a página, a galeria da comunidade e o
// teste (tools/theme_builder_test.js) usarem o mesmo código.
//
// Um link compartilhado traz o layout de outra pessoa, então nada do arquivo entra cru
// no HTML: valor de lista (variant, shape, align…) só passa se o app conhece, senão vale
// o padrão do componente; texto passa por esc(); cor sai de TB.cssColor; número é número.
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory;
  else root.LC_TB_PREVIEW = factory;
})(typeof self !== "undefined" ? self : this, function (TB, lang) {
  "use strict";
  var W = 1280, H = 800, own = TB.own, sizeNow = null;
  lang = lang === "pt" ? "pt" : "en";

  function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;"); }
  // O valor se o app conhece, senão o padrão (como `stringToEnum(...) orelse` no Zig).
  function pick(nd, key, list, def) {
    var v = TB.str(nd, key);
    return v !== null && list.indexOf(v) >= 0 ? v : def;
  }
  function spec(comp, key) {
    var s = TB.COMPONENTS[comp] || [];
    for (var i = 0; i < s.length; i++) if (s[i][0] === key && Array.isArray(s[i][1])) return s[i][1];
    return [];
  }
  function n(v, d) { return typeof v === "number" && isFinite(v) ? v : d; }
  function num(nd, key, d) { return n(TB.num(nd, key), d); }
  // Os mesmos limites do app (src/ui/backdrop.zig): um número enorme não trava a página.
  function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }
  var ALIGN = ["left", "center", "right"];
  var SHAPE_KINDS = ["circle", "ring", "arc", "rounded", "line"];
  var RULE_KINDS = ["solid", "dashed", "dotted", "double", "oxford"];
  var ORNAMENTS = { diamond: "◆", dot: "●", ring: "○", star: "✦" };
  var WGT = { regular: 400, medium: 500, semibold: 600, bold: 700, italic: 400 };

  var IC = {
    hash: "M4 9h16M4 15h16M10 3 8 21M16 3l-2 18", chev: "m6 9 6 6 6-6", plus: "M12 5v14M5 12h14", x: "M18 6 6 18M6 6l12 12",
    mic: "M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3ZM19 10v2a7 7 0 0 1-14 0v-2M12 19v3",
    head: "M3 14h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a9 9 0 0 1 18 0v7a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3",
    gear: "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM19 12l2-1-1-3-2 .3-1.4-1.4L17 5l-3-1-1 2h-2l-1-2-3 1 .3 2-1.4 1.4L4 8l-1 3 2 1v2l-2 1 1 3 2-.3 1.4 1.4L7 19l3 1 1-2h2l1 2 3-1-.3-2 1.4-1.4 2 .4 1-3-2-1z",
    pin: "M12 17v5M9 10.8V4h6v6.8l2 3.2H7zM8 3h8", inbox: "M22 12h-6l-2 3h-4l-2-3H2M5.5 5.1 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.5-6.9A2 2 0 0 0 16.8 4H7.2a2 2 0 0 0-1.7 1.1Z",
    mark: "m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2Z", search: "M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16ZM21 21l-4.3-4.3",
    users: "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM22 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8",
    smile: "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20ZM8 14s1.5 2 4 2 4-2 4-2M9 9h.01M15 9h.01", chat: "M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2Z",
    speaker: "M11 5 6 9H2v6h4l5 4zM15.5 8.5a5 5 0 0 1 0 7", back: "m15 18-6-6 6-6", fwd: "m9 18 6-6-6-6",
    help: "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20ZM9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3M12 17h.01",
  };
  function ic(name, cls) { return '<svg class="pv-ic' + (cls ? " " + cls : "") + '" viewBox="0 0 24 24" aria-hidden="true"><path d="' + IC[name] + '"/></svg>'; }

  // O conteúdo de mentira da prévia (fixo, escrito aqui).
  var M = lang === "pt"
    ? { general: "geral", topic: "conversa livre, sem spam", server: "larperCord dev", today: "Hoje às ", newm: "NOVAS MENSAGENS", place: "Conversar em #geral", delivered: "Entregue", search: "Buscar", online: "Online", home: "Mensagens diretas" }
    : { general: "general", topic: "free talk, no spam", server: "larperCord dev", today: "Today at ", newm: "NEW MESSAGES", place: "Message #general", delivered: "Delivered", search: "Search", online: "Online", home: "Direct Messages" };
  var CHANNELS = lang === "pt"
    ? [["INFO", [["regras"], ["anúncios", 1, 1]]], ["GERAL", [["geral", 0, 0, 1], ["memes", 1], ["setups"], ["música"]]], ["PROJETOS", [["zig", 1], ["interface", 1, 1], ["bugs"]]]]
    : [["INFO", [["rules"], ["announcements", 1, 1]]], ["GENERAL", [["general", 0, 0, 1], ["memes", 1], ["setups"], ["music"]]], ["PROJECTS", [["zig", 1], ["interface", 1, 1], ["bugs"]]]];
  var VOICE = lang === "pt" ? ["VOZ", "Call de madrugada"] : ["VOICE", "Late-night call"];
  var SERVERS = [["LC", "larperCord dev", 0], ["Z", "Zig Brasil", 1], ["A", "Arch Linux BR", 2], ["M", "Minecraft SMP", 3], ["C26", "C26", 4], ["S", "setups", 5], ["Ca", "café", 6]];
  var MEMBERS = lang === "pt"
    ? [["FUNDADORES — 2", [["rsha", 0, "on", "Programando em Zig"], ["ana.exe", 4, "on", "Ouvindo Spotify"]]], ["MODERADORES — 1", [["brunão", 2, "dnd", "Jogando Hollow Knight"]]],
      ["ONLINE — 4", [["kaique", 3, "on"], ["lulu", 5, "idle", "Vendo YouTube"], ["thiaguinho", 1, "idle"], ["mari", 6, "on", "Jogando Minecraft"]]], ["OFFLINE — 3", [["gustavo", 7, "off"], ["nanda", 1, "off"], ["joão vitor", 2, "off"]]]]
    : [["FOUNDERS — 2", [["rsha", 0, "on", "Coding in Zig"], ["ana.exe", 4, "on", "Listening to Spotify"]]], ["MODERATORS — 1", [["brunão", 2, "dnd", "Playing Hollow Knight"]]],
      ["ONLINE — 4", [["kaique", 3, "on"], ["lulu", 5, "idle", "Watching YouTube"], ["thiaguinho", 1, "idle"], ["mari", 6, "on", "Playing Minecraft"]]], ["OFFLINE — 3", [["gustavo", 7, "off"], ["nanda", 1, "off"], ["joão vitor", 2, "off"]]]];
  // Este texto tem marcação de propósito (<b>): é fixo, não vem do arquivo.
  var CHAT = lang === "pt" ? {
    a: "o tema novo ficou bom demais", b: "<b>urgente</b>: alguém tem carregador usb-c de notebook aí?", c: "é só um arquivo .kdl. salva e a janela muda.",
    d: "e dá pra mexer no layout também?", embedT: "Linguagem de Programação Zig", embedD: "Zig é uma linguagem de uso geral para software <b>robusto</b>, <b>ótimo</b> e <b>reutilizável</b>.",
  } : {
    a: "the new theme looks so good", b: "<b>urgent</b>: anyone got a usb-c laptop charger in the room?", c: "it's just a .kdl file. save it and the window changes.",
    d: "can you move the layout around too?", embedT: "Zig Programming Language", embedD: "Zig is a general-purpose language for <b>robust</b>, <b>optimal</b> and <b>reusable</b> software.",
  };

  // Cor de uma expressão do arquivo, já no formato do CSS (hex ou rgba com números), ou null.
  function evalCss(th, expr, toks, bare) {
    try { return TB.cssColor(TB.evalColor(expr, th.palette, function (k) { return toks[k]; }, bare)); } catch (e) { return null; }
  }
  function flagOpt(th, nd, key, def) {
    var v = TB.pv(nd, key);
    if (typeof v === "string" && v.length > 1 && v.charAt(0) === "$") {
      var inv = v.charAt(1) === "!", name = v.slice(inv ? 2 : 1), o = th.values[name];
      return o === undefined ? def : inv ? !o : o;
    }
    if (typeof v === "boolean") return v;
    if (typeof v === "number") return v !== 0;
    return def;
  }
  // `size` é a janela que a prévia imita ({ w, h }); sem ela, 1280×800.
  function visible(th, nd, size) {
    size = size || sizeNow;
    var p = function (k) { return TB.pv(nd, k); }, ww = size ? size.w : W, wh = size ? size.h : H;
    if (TB.flag(nd, "show") === false) return false;
    if (typeof p("hide-below") === "number" && ww < p("hide-below")) return false;
    if (typeof p("hide-below-height") === "number" && wh < p("hide-below-height")) return false;
    if (typeof p("only-below-height") === "number" && wh >= p("only-below-height")) return false;
    var w = TB.str(nd, "when"), u = TB.str(nd, "unless");
    if (w !== null && !th.values[w]) return false;
    if (u !== null && th.values[u]) return false;
    return true;
  }
  // A família para o CSS. Quem põe isto dentro de um atributo HTML passa por esc().
  function fontOf(f) {
    if (!f) return null;
    if (f === "mono") return "var(--f-mono)";
    if (f === "ui") return "var(--f-ui)";
    return '"' + String(f).replace(/["\\<>;{}]/g, "") + '",var(--f-ui)';
  }

  // O ruído do grão: um SVG pequeno, gerado aqui (data: URI, sem pedir nada à rede).
  var grainCache = {};
  function grainUrl(css) {
    if (own(grainCache, css)) return grainCache[css];
    var m = /rgba?\((\d+),(\d+),(\d+)(?:,([\d.]+))?\)/.exec(css), c = m ? [+m[1], +m[2], +m[3], m[4] === undefined ? 1 : +m[4]] : null;
    if (!c) { var x = TB.hexRgba(css); c = [x[0] * 255, x[1] * 255, x[2] * 255, x[3]]; }
    var a = Math.min(1, c[3] * 2.4).toFixed(3);
    var svg = "<svg xmlns='http://www.w3.org/2000/svg' width='180' height='180'><filter id='g'><feTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2' stitchTiles='stitch'/>" +
      "<feColorMatrix values='0 0 0 0 " + (c[0] / 255).toFixed(3) + " 0 0 0 0 " + (c[1] / 255).toFixed(3) + " 0 0 0 0 " + (c[2] / 255).toFixed(3) + " " + a + " 0 0 0 " + (-a * 0.35).toFixed(3) + "'/></filter>" +
      "<rect width='100%' height='100%' filter='url(%23g)'/></svg>";
    return (grainCache[css] = "url(\"data:image/svg+xml," + svg.replace(/"/g, "'").replace(/</g, "%3C").replace(/>/g, "%3E") + "\")");
  }

  function gradientCss(th, list, angle, toks) {
    var parts = TB.splitColors(list).map(function (p) { return evalCss(th, p, toks, true); });
    if (parts.length < 2 || parts.length > 3 || parts.some(function (p) { return !p; })) return null;
    return "linear-gradient(" + (n(angle, 90) + 90) + "deg," + parts.join(",") + ")";
  }

  // Fundo, borda e sombras de um nó: o estilo nomeado primeiro, depois o próprio nó.
  // Escreve em `el.style` (propriedades do CSS, não HTML).
  function paintBox(th, el, nd, toks) {
    var layers = [], shadows = [], radius = null, corners = null, borderGrad = null, borderW = 1, sheen = false;
    var sn = TB.str(nd, "style"), st = sn !== null && own(th.styles, sn) ? th.styles[sn] : null;
    function fills(src, isStyle) {
      var bg = TB.str(src, "bg");
      if (bg !== null) {
        var c = isStyle ? evalCss(th, bg, toks, false) : evalCss(th, bg, toks, true);
        if (c) layers.push("linear-gradient(" + c + "," + c + ")");
      }
      var g = TB.str(src, "gradient");
      if (g !== null) { var gc = gradientCss(th, g, num(src, "gradient-angle", 90), toks); if (gc) layers.push(gc); }
      var pat = TB.str(src, "pattern"), pc = TB.str(src, "pattern-color");
      if (pat && pc) {
        var c2 = evalCss(th, pc, toks, true), size = Math.max(2, Math.min(128, num(src, "pattern-size", 16) || 16)), pw = Math.max(0.5, Math.min(32, num(src, "pattern-width", 1) || 1));
        if (c2) {
          if (pat === "dots") layers.push("radial-gradient(circle," + c2 + " " + pw + "px,transparent " + (pw + 0.7) + "px) 0 0/" + size + "px " + size + "px");
          else if (pat === "lines") layers.push("linear-gradient(to bottom," + c2 + " " + pw + "px,transparent " + pw + "px) 0 0/100% " + size + "px");
          else if (pat === "grid") layers.push("linear-gradient(to bottom," + c2 + " " + pw + "px,transparent " + pw + "px) 0 0/" + size + "px " + size + "px", "linear-gradient(to right," + c2 + " " + pw + "px,transparent " + pw + "px) 0 0/" + size + "px " + size + "px");
          else if (pat === "diagonal") layers.push("repeating-linear-gradient(45deg," + c2 + " 0 " + pw + "px,transparent " + pw + "px " + size + "px)");
        }
      }
      var gr = TB.str(src, "grain");
      if (gr !== null) { var gcol = evalCss(th, gr, toks, true); if (gcol) layers.push(grainUrl(gcol)); }
      var vg = TB.str(src, "vignette");
      if (vg !== null) {
        var vc = evalCss(th, vg, toks, true), vs = Math.max(0, Math.min(0.95, num(src, "vignette-size", 0.55)));
        if (vc) layers.push("radial-gradient(farthest-corner,transparent " + Math.round(vs * 100) + "%," + vc + ")");
      }
      var ds = TB.str(src, "drop-shadow");
      if (ds !== null) {
        var dc = evalCss(th, ds, toks, true);
        if (dc) shadows.push("0 " + num(src, "drop-shadow-y", 10) + "px " + Math.max(1, num(src, "drop-shadow-size", 32)) + "px " + dc);
      }
      var is = TB.str(src, "inner-shadow");
      if (is !== null) {
        var ic2 = evalCss(th, is, toks, true);
        if (ic2) shadows.push("inset 0 0 " + num(src, "inner-shadow-size", 14) + "px " + ic2);
      }
      var bgr = TB.str(src, "border-gradient");
      if (bgr !== null) {
        borderGrad = gradientCss(th, bgr, num(src, "border-gradient-angle", 90), toks);
        borderW = num(src, "border-width", 1) || 1;
      }
      var bw0 = num(src, "border-width", 1) || 1;
      var bd = TB.str(src, "border");
      if (bd !== null) { var bc = evalCss(th, bd, toks, !isStyle); if (bc) shadows.push("inset 0 0 0 " + bw0 + "px " + bc); }
      [["border-top", "0 W"], ["border-right", "-W 0"], ["border-bottom", "0 -W"], ["border-left", "W 0"]].forEach(function (sd) {
        var v = TB.str(src, sd[0]);
        if (v === null) return;
        var c3 = evalCss(th, v, toks, true), w = num(src, sd[0] + "-width", bw0);
        if (c3) shadows.push("inset " + sd[1].replace(/W/g, w + "px") + " 0 0 " + c3);
      });
      var sh = num(src, "shadow", 0);
      if (isStyle && sh) shadows.push("0 " + sh / 2 + "px " + sh + "px " + TB.cssColor(toks.shadow));
      if (TB.num(src, "radius") !== null) radius = num(src, "radius", 0);
      var cn = TB.str(src, "corners");
      if (cn !== null && ["all", "left", "right", "top", "bottom"].indexOf(cn) >= 0) corners = cn;
      if (isStyle && flagOpt(th, src, "sheen", false)) sheen = true;
    }
    if (st) fills(st, true);
    fills(nd, false);
    if (!layers.length && !shadows.length && !borderGrad && radius === null && !sheen) return;
    if (sheen) {
      layers.push("linear-gradient(to bottom,rgba(255,255,255,.10),rgba(255,255,255,0) 34%)");
      shadows.push("inset 0 1px 0 rgba(255,255,255,.16)");
    }
    var css = layers.slice().reverse();
    if (borderGrad) {
      css = css.map(function (l) { return l + " padding-box"; });
      css.push(borderGrad + " border-box");
      el.style.border = borderW + "px solid transparent";
    }
    if (css.length) el.style.background = css.join(",");
    if (shadows.length) el.style.boxShadow = shadows.join(",");
    if (radius !== null) {
      var r = radius + "px", z = "0";
      el.style.borderRadius = corners === "left" ? r + " " + z + " " + z + " " + r : corners === "right" ? z + " " + r + " " + r + " " + z :
        corners === "top" ? r + " " + r + " " + z + " " + z : corners === "bottom" ? z + " " + z + " " + r + " " + r : r;
    }
  }

  // Avatar de mentira. `shape` já vem da lista do app (circle, squircle, square).
  function av(name, role, shape, size) {
    var st = "--c:var(--r" + role + ")" + (size ? ";width:" + size + "px;height:" + size + "px;font-size:" + Math.round(size * 0.42) + "px" : "");
    return '<i class="pv-av ' + (shape || "") + '" style="' + st + '">' + esc(name.charAt(0).toUpperCase()) + "</i>";
  }
  function paint(th, nd, key, toks, def) {
    var v = TB.str(nd, key);
    return (v !== null && evalCss(th, v, toks, true)) || def;
  }
  function textColor(th, v, toks) {
    if (v === null) return null;
    if (TB.tokenName(v)) return "var(--t-" + TB.tokenName(v) + ")";
    return evalCss(th, v, toks, true);
  }

  var C = Object.create(null);
  C["guild-bar"] = function (th, nd) {
    var variant = pick(nd, "variant", spec("guild-bar", "variant"), "bar"), shape = pick(nd, "shape", spec("guild-bar", "shape"), "circle"), size = num(nd, "size", 48) || 48;
    var style = pick(nd, "icon-style", spec("guild-bar", "icon-style"), "fill"), horiz = TB.str(nd, "orientation") === "horizontal" || variant === "dock";
    var labels = flagOpt(th, nd, "labels", variant === "list"), home = flagOpt(th, nd, "home", true), ind = flagOpt(th, nd, "indicators", true);
    if (shape === "text") {
      return '<div class="pv-gtext">' + SERVERS.map(function (s, i) { return '<span class="' + (i ? "" : "on") + '">' + (i + 1) + ":" + esc(s[1]) + "</span>"; }).join("") + "</div>";
    }
    var icons = SERVERS.map(function (s, i) {
      return '<span class="pv-gi' + (i ? "" : " on") + '"><b class="pv-gico ' + shape + " " + style + '" style="--c:var(--r' + s[2] + ");width:" + size + "px;height:" + size + "px;font-size:" + Math.round(size * 0.32) + 'px">' + esc(s[0]) +
        (i === 0 ? '<em class="pv-badge">2</em>' : "") + "</b>" + (labels ? "<span>" + esc(s[1]) + "</span>" : "") + "</span>";
    }).join("");
    var homeEl = home ? '<span class="pv-gi"><b class="pv-gico ' + shape + ' home" style="width:' + size + "px;height:" + size + 'px">' + ic("chat") + "</b>" + (labels ? "<span>" + esc(M.home) + "</span>" : "") + "</span><hr>" : "";
    return '<div class="pv-guild ' + variant + (horiz ? " pv-hz" : "") + (labels ? " lab" : "") + (ind ? " ind" : "") + '">' + homeEl + icons + "</div>";
  };
  C["channel-list"] = function (th, nd) {
    var v = pick(nd, "variant", spec("channel-list", "variant"), "discord"), out = "";
    if (flagOpt(th, nd, "banner", false)) out += '<div class="pv-banner"><b>' + esc(M.server) + "</b>" + ic("chev") + "</div>";
    else if (flagOpt(th, nd, "header", true)) out += '<div class="pv-shead"><b>' + esc(M.server) + "</b>" + ic("chev") + "</div>";
    var rows = "";
    CHANNELS.forEach(function (cat) {
      rows += "<small>" + ic("chev", "s") + esc(cat[0]) + "</small>";
      cat[1].forEach(function (c, i) {
        var pre = v === "tree" ? '<u class="pv-tree">' + (i === cat[1].length - 1 ? "└─" : "├─") + "</u>" : ic("hash");
        rows += '<span class="pv-ch' + (c[3] ? " on" : "") + (c[1] ? " unread" : "") + '">' + pre + "<em>" + esc(c[0]) + "</em>" + (c[2] ? '<b class="pv-badge">1</b>' : "") + "</span>";
      });
    });
    rows += "<small>" + ic("chev", "s") + esc(VOICE[0]) + "</small>";
    rows += '<span class="pv-ch">' + ic("speaker") + "<em>" + esc(VOICE[1]) + "</em></span>";
    [["ana.exe", 4], ["duda", 2], ["kaique", 3]].forEach(function (u) { rows += '<span class="pv-vu">' + av(u[0], u[1], "", 20) + "<em>" + esc(u[0]) + "</em>" + ic("mic") + "</span>"; });
    return '<div class="pv-chan ' + v + '">' + out + '<div class="pv-chrows">' + rows + "</div></div>";
  };
  C["user-panel"] = function (th, nd) {
    if (TB.str(nd, "variant") === "tty") return '<div class="pv-user tty"><span><i class="pv-st on"></i>rsha</span><span class="pv-tty">M&nbsp;&nbsp;F&nbsp;&nbsp;' + ic("gear") + "</span></div>";
    return '<div class="pv-user"><span class="pv-avs">' + av("rsha", 0, "", 32) + '<i class="pv-st on"></i></span><span class="pv-who"><b>rsha</b><small>' + esc(M.online) + "</small></span>" + ic("mic") + ic("head") + ic("gear") + "</div>";
  };
  C.header = function (th, nd) {
    var v = pick(nd, "variant", spec("header", "variant"), "discord"), div = flagOpt(th, nd, "divider", true) ? " div" : "";
    var icons = '<span class="pv-hicons">' + ic("pin") + ic("inbox") + ic("mark") + (v === "discord" ? ic("search") + ic("users") + '<span class="pv-hsearch">' + esc(M.search) + " Ctrl+K" + ic("search") + "</span>" : "") + "</span>";
    if (v === "tty") return '<div class="pv-head tty' + div + '"><b>[#' + esc(M.general) + "]</b><span>" + esc(M.topic) + "</span></div>";
    if (v === "minimal") return '<div class="pv-head min' + div + '"><span class="pv-ht"><b>' + esc(M.general) + "</b><small>" + esc(M.server) + " · " + esc(M.topic) + "</small></span>" + icons + "</div>";
    return '<div class="pv-head' + div + '">' + ic("hash") + "<b>" + esc(M.general) + '</b><i class="pv-hdiv"></i><span>' + esc(M.topic) + "</span>" + icons + "</div>";
  };
  C.tabs = function (th, nd) {
    var v = pick(nd, "variant", spec("tabs", "variant"), "pills"), t = ["#" + M.general, "#zig", "#memes"], roles = [0, 1, 3];
    if (v === "tty") return '<div class="pv-tabs tty">' + t.map(function (x, i) { return "<span" + (i ? "" : ' class="on"') + ">" + (i + 1) + ":" + esc(x) + "</span>"; }).join("") + "</div>";
    return '<div class="pv-tabs ' + v + '">' + t.map(function (x, i) { return "<span" + (i ? "" : ' class="on"') + '><u style="--c:var(--r' + roles[i] + ')">LC</u>' + esc(x) + (i ? "" : ic("x")) + "</span>"; }).join("") + ic("plus") + "</div>";
  };
  C.messages = function (th, nd) {
    var v = pick(nd, "variant", spec("messages", "variant"), "cozy"), avatar = pick(nd, "avatar", spec("messages", "avatar"), "circle"), size = num(nd, "avatar-size", 40) || 40;
    var gap = TB.num(nd, "spacing") === null ? null : num(nd, "spacing", 16), fs = num(nd, "font-size", 0);
    var ruled = flagOpt(th, nd, "ruled", false), margin = flagOpt(th, nd, "margin-line", false);
    var ticks = flagOpt(th, nd, "ticks", false), typing = flagOpt(th, nd, "typing-bubble", false);
    var list = [
      { who: "duda", r: 2, t: "06:52", pic: true },
      { who: "kaique", r: 3, t: "06:54", faces: true },
      { div: true },
      { who: "kaique", r: 3, t: "06:58", link: true },
      { who: "duda", r: 2, t: "07:00", text: CHAT.a, re: [3, 1] },
      { who: "ana.exe", r: 4, t: "07:02", text: '<span class="pv-men">@rsha</span> ' + CHAT.b, re: [2], men: true },
      { who: "rsha", r: 0, t: "07:03", text: CHAT.c, me: true },
    ];
    var styleAttr = 'style="' + (gap !== null ? "--gap:" + gap + "px;" : "") + (fs ? "font-size:" + fs * 0.9 + "px;" : "") + '"';
    var out = "";
    if (v === "irc") {
      list.forEach(function (m) {
        if (m.div) { out += '<p class="pv-newm"><span>' + esc(M.newm) + "</span></p>"; return; }
        var body = m.pic ? '<i class="pv-pic sm"></i>' : m.faces ? '<i class="pv-face"></i><i class="pv-face pv-f2"></i>' : m.link ? '<a class="pv-link">https://ziglang.org</a>' : m.text;
        out += '<p class="pv-irc' + (m.men ? " men" : "") + '"><time>' + m.t + '</time> <b style="color:var(--r' + m.r + ')">&lt;' + esc(m.who) + "&gt;</b> " + body + "</p>";
      });
    } else if (v === "bubbles") {
      list.forEach(function (m) {
        if (m.div) return;
        var body = m.pic ? '<i class="pv-pic"></i>' : m.faces ? '<i class="pv-face"></i><i class="pv-face pv-f2"></i>' : m.link ? '<a class="pv-link">https://ziglang.org</a>' : m.text;
        var a = avatar === "none" || m.me ? "" : av(m.who, m.r, avatar, Math.min(size, 34));
        out += '<div class="pv-bub' + (m.me ? " me" : "") + '">' + a + '<div class="pv-bb">' + (m.me ? "" : '<b style="color:var(--r' + m.r + ')">' + esc(m.who) + "</b>") + "<p>" + body + "</p></div></div>";
        if (m.me && ticks) out += '<p class="pv-ticks">' + esc(M.delivered) + " ✓✓</p>";
      });
      out += '<div class="pv-bub me"><div class="pv-bb"><p>' + CHAT.d + "</p></div></div>";
      if (typing) out += '<div class="pv-bub"><div class="pv-bb pv-typing"><i></i><i></i><i></i></div></div>';
    } else {
      list.forEach(function (m) {
        if (m.div) { out += '<p class="pv-newm"><span>' + esc(M.newm) + "</span></p>"; return; }
        var body = m.pic ? '<i class="pv-pic"></i>' : m.faces ? '<span class="pv-faces"><i class="pv-face"></i><i class="pv-face pv-f2"></i></span>' :
          m.link ? '<a class="pv-link">https://ziglang.org</a><div class="pv-embed"><div><small>ziglang.org</small><b>' + esc(CHAT.embedT) + "</b><p>" + CHAT.embedD + '</p></div><i class="pv-thumb"></i></div>' : "<p>" + m.text + "</p>";
        var re = m.re ? '<span class="pv-re">' + m.re.map(function (k, i) { return '<em class="' + (i ? "" : "mine") + '"><i class="pv-face s' + (i ? " pv-f2" : "") + '"></i>' + k + "</em>"; }).join("") + "</span>" : "";
        var a = avatar === "none" ? "" : av(m.who, m.r, avatar, size);
        out += '<div class="pv-msg' + (m.men ? " men" : "") + (avatar === "none" ? " noav" : "") + '">' + a + '<div class="pv-mb"><div class="pv-mh"><b style="color:var(--r' + m.r + ')">' + esc(m.who) + "</b><time>" + esc(M.today) + m.t + "</time></div>" + body + re + "</div></div>";
      });
    }
    return '<div class="pv-msgs ' + v + (ruled ? " ruled" : "") + (margin ? " margin" : "") + '" ' + styleAttr + '><div class="pv-mlist">' + out + "</div></div>";
  };
  C.composer = function (th, nd) {
    var v = pick(nd, "variant", spec("composer", "variant"), "box");
    if (v === "prompt") return '<div class="pv-comp prompt"><div><b>rsha@#' + esc(M.general) + ' ❯</b><i class="pv-caret"></i><span class="pv-sp"></span><u>[+]</u>' + ic("smile") + "</div></div>";
    return '<div class="pv-comp ' + v + '"><div>' + ic("plus", "pv-cplus") + "<span>" + esc(M.place) + '</span><span class="pv-sp"></span>' + ic("smile") + "</div></div>";
  };
  C["member-list"] = function (th, nd) {
    var tty = TB.str(nd, "variant") === "tty", out = "", glyph = { on: "●", idle: "◐", dnd: "⊘", off: "○" };
    MEMBERS.forEach(function (g) {
      out += "<small>" + esc(g[0]) + "</small>";
      g[1].forEach(function (m) {
        var off = m[2] === "off";
        if (tty) out += '<span class="pv-mem tty' + (off ? " off" : "") + '"><u class="' + m[2] + '">' + glyph[m[2]] + '</u><b style="' + (off ? "" : "color:var(--r" + m[1] + ")") + '">' + esc(m[0]) + "</b></span>";
        else out += '<span class="pv-mem' + (off ? " off" : "") + '"><span class="pv-avs">' + av(m[0], m[1], "", 32) + '<i class="pv-st ' + m[2] + '"></i></span><span class="pv-who"><b style="' + (off ? "" : "color:var(--r" + m[1] + ")") + '">' + esc(m[0]) + "</b>" + (m[3] ? "<small>" + esc(m[3]) + "</small>" : "") + "</span></span>";
      });
    });
    return '<div class="pv-members' + (tty ? " tty" : "") + '">' + out + "</div>";
  };
  C["status-bar"] = function (th, nd) {
    var v = pick(nd, "variant", spec("status-bar", "variant"), "pills"), items = String(TB.str(nd, "items") || "conn ping ram spacer theme keys clock").split(/\s+/);
    var map = { conn: '<i class="pv-st on"></i>demo', ping: "~0 ms", ram: "26.7 MB", frame: "0.4 ms", voice: "", theme: esc(TB.slug(th.name)), keys: "Ctrl+K", clock: "07:05",
      me: av("rsha", 0, "", 16) + "rsha", mic: ic("mic"), deaf: ic("head") };
    return '<div class="pv-status ' + v + '">' + items.map(function (x) {
      if (x === "spacer") return '<span class="pv-sp"></span>';
      return own(map, x) && map[x] ? "<span>" + map[x] + "</span>" : "";
    }).join("") + "</div>";
  };
  C.label = function (th, nd, toks) {
    var fx = nd.kids.some(function (k) { return k.name === "span"; }) || ["tracking", "shadow", "outline", "text-gradient", "text-en"].some(function (k) { return TB.prop(nd, k); });
    var size = num(nd, "size", 14) || 14, weight = TB.str(nd, "weight") || (fx ? "semibold" : "regular");
    var st = "font-size:" + size * 0.9 + "px;font-weight:" + (own(WGT, weight) ? WGT[weight] : 400) + ";" + (weight === "italic" ? "font-style:italic;" : "");
    var col = textColor(th, TB.str(nd, "color"), toks);
    if (col) st += "color:" + col + ";";
    if (TB.num(nd, "tracking") !== null) st += "letter-spacing:" + num(nd, "tracking", 0) + "px;";
    var f = fontOf(TB.str(nd, "font"));
    if (f) st += "font-family:" + f + ";";
    var sh = TB.str(nd, "shadow");
    if (sh) {
      var sc = evalCss(th, sh, toks, true), blur = num(nd, "shadow-blur", 0);
      if (sc) st += "text-shadow:" + num(nd, "shadow-x", 0) + "px " + num(nd, "shadow-y", blur ? 0 : 1) + "px " + blur * 3 + "px " + sc + ";";
    }
    var ol = TB.str(nd, "outline");
    if (ol) { var oc = evalCss(th, ol, toks, true); if (oc) st += "-webkit-text-stroke:" + (num(nd, "outline-width", 1) || 1) + "px " + oc + ";paint-order:stroke fill;"; }
    var tg = TB.str(nd, "text-gradient"), grad = tg ? gradientCss(th, tg, num(nd, "text-gradient-angle", 0), toks) : null;
    var align = pick(nd, "align", ALIGN, "left");
    var spans = nd.kids.filter(function (k) { return k.name === "span"; });
    var inner;
    if (spans.length) {
      inner = spans.map(function (sp) {
        var en = TB.str(sp, "en") || TB.str(sp, "text-en");
        var t = lang === "en" && en ? en : typeof TB.arg(sp, 0) === "string" ? TB.arg(sp, 0) : TB.str(sp, "text") || "";
        var s2 = "";
        if (TB.num(sp, "size") !== null) s2 += "font-size:" + num(sp, "size", 14) * 0.9 + "px;";
        var w2 = TB.str(sp, "weight");
        if (w2) s2 += "font-weight:" + (own(WGT, w2) ? WGT[w2] : 400) + ";" + (w2 === "italic" ? "font-style:italic;" : "");
        var c2 = textColor(th, TB.str(sp, "color"), toks);
        if (c2) s2 += "color:" + c2 + ";";
        if (TB.num(sp, "tracking") !== null) s2 += "letter-spacing:" + num(sp, "tracking", 0) + "px;";
        var f2 = fontOf(TB.str(sp, "font"));
        if (f2) s2 += "font-family:" + f2 + ";";
        return '<span style="' + esc(s2) + '">' + esc(t) + "</span>";
      }).join("");
    } else {
      var txt = lang === "en" && TB.str(nd, "text-en") ? TB.str(nd, "text-en") : TB.str(nd, "text") || "";
      inner = grad ? '<span class="pv-tg" style="background-image:' + esc(grad) + '">' + esc(txt) + "</span>" : esc(txt);
    }
    if (TB.num(nd, "span-gap") !== null) st += "gap:" + num(nd, "span-gap", 0) + "px;";
    return '<div class="pv-label ' + align + '" style="' + esc(st) + '">' + inner + "</div>";
  };
  C.shape = function (th, nd, toks) {
    var kind = pick(nd, "kind", SHAPE_KINDS, "circle"), col = paint(th, nd, "color", toks, "var(--t-accent)"), fill = paint(th, nd, "fill", toks, "none");
    var t = num(nd, "thickness", 1.5) || 1.5, size = TB.num(nd, "size") === null ? null : num(nd, "size", 24), align = pick(nd, "align", ALIGN, "center");
    var ox = num(nd, "offset-x", 0), oy = num(nd, "offset-y", 0), s = size || 24, svg = "";
    if (kind === "rounded") {
      var r = num(nd, "radius", 6) || 6;
      return '<div class="pv-shape rounded" style="transform:translate(' + ox + "px," + oy + 'px)"><i style="border:' + t + "px solid " + col + ";background:" + (fill === "none" ? "transparent" : fill) + ";border-radius:" + r + 'px"></i></div>';
    }
    if (kind === "circle") svg = '<circle cx="' + s / 2 + '" cy="' + s / 2 + '" r="' + s / 2 + '" fill="' + col + '"/>';
    else if (kind === "ring") svg = '<circle cx="' + s / 2 + '" cy="' + s / 2 + '" r="' + (s - t) / 2 + '" fill="' + fill + '" stroke="' + col + '" stroke-width="' + t + '"/>';
    else if (kind === "arc") {
      var a0 = num(nd, "start", 0) * Math.PI / 180, sw = num(nd, "sweep", 270) * Math.PI / 180, rr = (s - t) / 2, c = s / 2;
      var x0 = c + rr * Math.cos(a0), y0 = c + rr * Math.sin(a0), x1 = c + rr * Math.cos(a0 + sw), y1 = c + rr * Math.sin(a0 + sw);
      svg = '<path d="M' + x0 + " " + y0 + "A" + rr + " " + rr + " 0 " + (Math.abs(sw) > Math.PI ? 1 : 0) + " " + (sw > 0 ? 1 : 0) + " " + x1 + " " + y1 + '" fill="none" stroke="' + col + '" stroke-width="' + t + '" stroke-linecap="round"/>';
      var dot = TB.str(nd, "dot");
      if (dot) svg += '<circle cx="' + x1 + '" cy="' + y1 + '" r="' + (num(nd, "dot-size", 2) || 2) + '" fill="' + (evalCss(th, dot, toks, true) || col) + '"/>';
    } else if (kind === "line") {
      var ang = num(nd, "angle", 0) * Math.PI / 180, L = s / 2;
      svg = '<line x1="' + (s / 2 - L * Math.cos(ang)) + '" y1="' + (s / 2 - L * Math.sin(ang)) + '" x2="' + (s / 2 + L * Math.cos(ang)) + '" y2="' + (s / 2 + L * Math.sin(ang)) + '" stroke="' + col + '" stroke-width="' + t + '"/>';
    }
    var dim = size ? "width:" + s + "px;height:" + s + "px" : "height:100%;aspect-ratio:1";
    return '<div class="pv-shape ' + align + '" style="transform:translate(' + ox + "px," + oy + 'px)"><svg viewBox="0 0 ' + s + " " + s + '" style="' + dim + ';overflow:visible">' + svg + "</svg></div>";
  };
  C.rule = function (th, nd, toks) {
    var kind = pick(nd, "kind", RULE_KINDS, "solid"), col = paint(th, nd, "color", toks, "var(--t-border)"), t = num(nd, "thickness", 1) || 1;
    var vert = flagOpt(th, nd, "vertical", false), fade = flagOpt(th, nd, "fade", false);
    var line;
    if (kind === "dashed") {
      var d = num(nd, "dash", 4) || 4, g = num(nd, "gap", 3) || 3;
      line = "background:repeating-linear-gradient(" + (vert ? "180deg" : "90deg") + "," + col + " 0 " + d + "px,transparent " + d + "px " + (d + g) + "px);" + (vert ? "width:" + t + "px" : "height:" + t + "px");
    } else if (kind === "dotted") {
      line = "background:radial-gradient(circle," + col + " " + t * 0.6 + "px,transparent " + (t * 0.6 + 0.6) + "px) 0 0/" + t * 3 + "px " + t * 3 + "px;" + (vert ? "width:" : "height:") + t * 2 + "px";
    } else if (kind === "double") line = (vert ? "border-left:" : "border-top:") + t + "px solid " + col + ";" + (vert ? "border-right:" : "border-bottom:") + t + "px solid " + col + ";" + (vert ? "width:" : "height:") + "calc(100% - 2px)";
    else if (kind === "oxford") line = (vert ? "border-left:" : "border-top:") + (t * 2.5) + "px solid " + col + ";" + (vert ? "border-right:" : "border-bottom:") + t + "px solid " + col + ";" + (vert ? "width:" : "height:") + "calc(100% - 1px)";
    else line = "background:" + col + ";" + (vert ? "width:" + t + "px" : "height:" + t + "px");
    var orn = "", ot = TB.str(nd, "ornament-text"), o = TB.str(nd, "ornament");
    if (ot || (o !== null && own(ORNAMENTS, o))) {
      var oc = paint(th, nd, "ornament-color", toks, col), os = num(nd, "ornament-size", 8) || 8, gap = num(nd, "ornament-gap", 6) || 6;
      var glyph = ot ? esc(ot) : ORNAMENTS[o];
      var of = ot ? fontOf(TB.str(nd, "font")) : null;
      orn = '<b style="' + esc("color:" + oc + ";font-size:" + os + "px;padding:0 " + gap + "px;" + (of ? "font-family:" + of : "")) + '">' + glyph + "</b>";
    }
    var seg = '<i style="' + esc(line) + '"></i>';
    return '<div class="pv-rule' + (vert ? " v" : "") + (fade ? " fade" : "") + '">' + seg + (orn ? orn + seg : "") + "</div>";
  };

  // Fundos procedurais: SVG com o mesmo tamanho da janela, sementes fixas.
  function bgSvg(inner) { return '<svg class="pv-bgsvg" viewBox="0 0 ' + W + " " + H + '" preserveAspectRatio="xMidYMid slice" aria-hidden="true">' + inner + "</svg>"; }
  C.starfield = function (th, nd, toks) {
    var r = TB.rng(num(nd, "seed", 1) * 977), count = Math.round(170 * clamp(num(nd, "density", 1), 0.1, 6)), far = paint(th, nd, "color", toks, "var(--t-muted)"), near = paint(th, nd, "color2", toks, "var(--t-accent)"), out = "";
    for (var i = 0; i < count; i++) {
      var close = r() < 0.14;
      out += '<circle cx="' + (r() * W).toFixed(1) + '" cy="' + (r() * H).toFixed(1) + '" r="' + (close ? 1.1 + r() * 0.9 : 0.4 + r() * 0.7).toFixed(2) + '" fill="' + (close ? near : far) + '" opacity="' + (0.4 + r() * 0.6).toFixed(2) + '"/>';
    }
    return bgSvg(out);
  };
  C.orbit = function (th, nd, toks) {
    var cx = num(nd, "center-x", 0.7) * W, cy = num(nd, "center-y", 0.35) * H;
    var rings = Math.round(clamp(num(nd, "rings", 6), 1, 12)), col = paint(th, nd, "color", toks, "var(--t-border)"), moon = paint(th, nd, "color2", toks, "var(--t-accent)"), r = TB.rng(num(nd, "seed", 1) * 31), out = "";
    for (var i = 1; i <= rings; i++) {
      var rad = 46 + i * i * 9 + i * 34, a = r() * Math.PI * 2;
      out += '<circle cx="' + cx + '" cy="' + cy + '" r="' + rad + '" fill="none" stroke="' + col + '" stroke-width="1"' + (i % 3 === 0 ? ' stroke-dasharray="2 5"' : "") + "/>";
      out += '<circle cx="' + (cx + rad * Math.cos(a)).toFixed(1) + '" cy="' + (cy + rad * Math.sin(a)).toFixed(1) + '" r="' + (2 + r() * 3).toFixed(1) + '" fill="' + moon + '"/>';
    }
    return bgSvg(out + '<circle cx="' + cx + '" cy="' + cy + '" r="9" fill="' + moon + '"/>');
  };
  C.aurora = function (th, nd, toks) {
    var a = paint(th, nd, "color", toks, "var(--t-accent)"), b = paint(th, nd, "color2", toks, "var(--t-mention)");
    return '<div class="pv-aurora" style="background:radial-gradient(48% 34% at 28% 30%,' + a + ',transparent 70%),radial-gradient(44% 38% at 74% 66%,' + b + ',transparent 72%),radial-gradient(30% 22% at 60% 20%,' + b + ',transparent 70%)"></div>';
  };
  C.dunes = function (th, nd, toks) {
    var cols = [paint(th, nd, "color", toks, "var(--t-elevated)"), paint(th, nd, "color2", toks, "var(--t-accent)"), paint(th, nd, "color3", toks, "var(--t-rail)")], out = "";
    [[0.52, 70, 1.3], [0.66, 60, 2.1], [0.8, 46, 1.7]].forEach(function (d, i) {
      var y = d[0] * H, p = "M0 " + H + " L0 " + y;
      for (var x = 0; x <= W; x += 40) p += " L" + x + " " + (y - Math.sin(x / W * Math.PI * d[2] + i) * d[1] - Math.sin(x / 170 + i * 2) * 10).toFixed(1);
      out += '<path d="' + p + " L" + W + " " + H + ' Z" fill="' + cols[i] + '"/>';
    });
    return bgSvg(out);
  };
  C.topography = function (th, nd, toks) {
    var r = TB.rng(num(nd, "seed", 1) * 131), levels = Math.round(clamp(num(nd, "levels", 14), 4, 40)), col = paint(th, nd, "color", toks, "var(--t-border)"), out = "";
    var centers = [[r() * W, r() * H], [r() * W, r() * H], [r() * W, r() * H]];
    var ph = [r() * 6, r() * 6, r() * 6, r() * 6];
    centers.forEach(function (c, ci) {
      for (var l = 1; l <= Math.ceil(levels / 3); l++) {
        var base = l * 46 + ci * 9, d = "";
        for (var k = 0; k <= 48; k++) {
          var a = k / 48 * Math.PI * 2, rr = base * (1 + 0.16 * Math.sin(3 * a + ph[ci]) + 0.08 * Math.sin(5 * a + ph[3] + l * 0.3));
          d += (k ? " L" : "M") + (c[0] + rr * Math.cos(a)).toFixed(1) + " " + (c[1] + rr * 0.72 * Math.sin(a)).toFixed(1);
        }
        out += '<path d="' + d + 'Z" fill="none" stroke="' + col + '" stroke-width="1"/>';
      }
    });
    return bgSvg(out);
  };
  C.radar = function (th, nd, toks) {
    var cx = num(nd, "center-x", 0.5) * W, cy = num(nd, "center-y", 0.5) * H;
    var rings = Math.round(clamp(num(nd, "rings", 5), 1, 12)), col = paint(th, nd, "color", toks, "var(--t-border)"), sw = paint(th, nd, "color2", toks, "var(--t-accent)"), out = "", R = 0;
    for (var i = 1; i <= rings; i++) { R = i * 70; out += '<circle cx="' + cx + '" cy="' + cy + '" r="' + R + '" fill="none" stroke="' + col + '"/>'; }
    out += '<path d="M' + (cx - R) + " " + cy + "H" + (cx + R) + "M" + cx + " " + (cy - R) + "V" + (cy + R) + '" stroke="' + col + '"/>';
    out += '<path d="M' + cx + " " + cy + "L" + (cx + R) + " " + cy + "A" + R + " " + R + " 0 0 0 " + (cx + R * Math.cos(-0.7)).toFixed(1) + " " + (cy + R * Math.sin(-0.7)).toFixed(1) + 'Z" fill="' + sw + '" opacity=".22"/>';
    return bgSvg(out + '<line x1="' + cx + '" y1="' + cy + '" x2="' + (cx + R) + '" y2="' + cy + '" stroke="' + sw + '" stroke-width="2"/>');
  };
  C["window-controls"] = function (th, nd, toks) {
    var s = num(nd, "size", 12) || 12, g = num(nd, "gap", 8) || 8, cols = [paint(th, nd, "color", toks, "#ff5f57"), paint(th, nd, "color2", toks, "#febc2e"), paint(th, nd, "color3", toks, "#28c840")];
    return '<div class="pv-wc ' + pick(nd, "align", ALIGN, "left") + '" style="gap:' + g + 'px">' + cols.map(function (c) { return '<i style="width:' + s + "px;height:" + s + "px;background:" + c + '"></i>'; }).join("") + "</div>";
  };
  C.logo = function (th, nd) {
    var size = num(nd, "size", 14) || 14;
    if (TB.str(nd, "variant") === "ascii") return '<pre class="pv-logo ascii" style="font-size:' + size * 0.9 + 'px">┬  ┌─┐┬─┐┌─┐┌─┐┬─┐\n│  ├─┤├┬┘├─┘├┤ ├┬┘\n┴─┘┴ ┴┴└─┴  └─┘┴└─ cord</pre>';
    return '<div class="pv-logo" style="font-size:' + size * 0.9 + 'px">larperCord</div>';
  };
  C.topbar = function () {
    return '<div class="pv-top">' + ic("back") + ic("fwd") + '<span class="pv-tsearch">' + ic("search") + esc(M.search) + "<kbd>Ctrl+K</kbd></span>" + ic("help") + "</div>";
  };
  C.crt = function (th, nd) {
    var sp = Math.max(2, num(nd, "spacing", 3) || 3), k = num(nd, "strength", 0.08);
    return '<div class="pv-crt" style="background:repeating-linear-gradient(to bottom,transparent 0 ' + (sp - 1) + "px,rgba(0,0,0," + Math.max(0, Math.min(0.9, k * 2.6)).toFixed(3) + ") " + (sp - 1) + "px " + sp + 'px),radial-gradient(ellipse at center,transparent 62%,rgba(0,0,0,' + Math.max(0, Math.min(0.6, k * 3)).toFixed(3) + '))"></div>';
  };
  C.spacer = function () { return ""; };

  // O HTML de um componente, ou null se o app não conhece o nome (a página mostra o aviso).
  function component(name, th, nd, toks) {
    return own(C, name) ? C[name](th, nd, toks) : null;
  }

  // A árvore do layout em elementos de verdade. Este pedaço precisa de DOM (o documento
  // do `frame`); o criador de temas e a galeria da comunidade desenham por aqui.
  var CONTAINERS = { row: 1, column: 1, stack: 1 };
  function build(doc, th, nd, parentAxis, toks) {
    var n = doc.createElement("div");
    n.className = "pv-n";
    var main = parentAxis === "row" ? "width" : parentAxis === "column" ? "height" : null;
    if (main) {
      var fixed = TB.num(nd, main);
      if (fixed !== null) n.style.flex = "0 0 " + Math.max(0, fixed) + "px";
      else n.style.flex = (TB.num(nd, "flex") === null ? 1 : Math.max(0, TB.num(nd, "flex"))) + " 1 0";
    }
    // Cores sobrescritas neste pedaço (c-…, cl-… só no claro, cd-… só no escuro).
    var local = toks, over = [];
    nd.props.forEach(function (p) {
      var m = /^(c|cl|cd)-(.+)$/.exec(p.k);
      if (!m || (m[1] === "cl" && th.mode !== "light") || (m[1] === "cd" && th.mode !== "dark") || !TB.tokenName(m[2]) || typeof p.v !== "string") return;
      try {
        var c = TB.evalColor(p.v, th.palette, function (x) { return th.tokens[x]; }, false);
        if (local === toks) local = Object.assign({}, toks);
        local[TB.tokenName(m[2])] = c;
        over.push([TB.tokenName(m[2]), TB.cssColor(c)]);
      } catch (e) {}
    });
    var b = doc.createElement("div");
    b.className = "pv-b";
    // O nome do nó só vira classe se for um nome simples (um link pode trazer qualquer coisa).
    if (/^[a-z][a-z0-9-]{0,40}$/.test(nd.name)) b.classList.add("pv-k-" + nd.name);
    // Para o clique-para-editar do criador: a camada (início do nó no texto e linha), os tokens
    // do fundo e da cor do nó, e os que ele troca (c-…). Só nomes da lista de tokens e números.
    var ds = b.dataset;
    if (ds) {
      ds.start = String(nd.start);
      ds.line = String(nd.line);
      if (/^[a-z][a-z0-9-]{0,40}$/.test(nd.name)) ds.node = nd.name;
      var fill = boxTokens(th, nd);
      if (fill.toks.length) ds.tk = fill.toks.join(" ");
      else if (fill.literal) ds.lit = "1";
      var fg = refTokens(TB.str(nd, "color"), true);
      if (fg.length) ds.fg = fg[0];
      if (over.length) ds.over = over.map(function (o) { return o[0]; }).join(" ");
    }
    var mw = TB.num(nd, "max-width");
    if (mw !== null) { b.style.maxWidth = mw + "px"; b.style.marginLeft = b.style.marginRight = "auto"; }
    over.forEach(function (o) { b.style.setProperty("--t-" + o[0], o[1]); });
    var f = fontOf(TB.str(nd, "font"));
    if (f && nd.name !== "label") b.style.fontFamily = f;
    paintBox(th, b, nd, local);
    if (own(CONTAINERS, nd.name)) {
      b.classList.add("pv-" + (nd.name === "stack" ? "stack" : "flex"));
      if (nd.name !== "stack") b.style.flexDirection = nd.name === "row" ? "row" : "column";
      var pad = TB.num(nd, "padding") || 0, px = TB.num(nd, "padding-x"), py = TB.num(nd, "padding-y");
      px = px === null ? pad : px;
      py = py === null ? pad : py;
      b.style.padding = py + "px " + px + "px";
      if (nd.name !== "stack" && TB.num(nd, "gap")) b.style.gap = TB.num(nd, "gap") + "px";
      nd.kids.forEach(function (k) { if (visible(th, k)) b.appendChild(build(doc, th, k, nd.name, local)); });
    } else {
      var c = doc.createElement("div");
      c.className = "pv-c";
      var ix = TB.num(nd, "inset-x") || 0, iy = TB.num(nd, "inset-y") || 0;
      c.style.inset = iy + "px " + ix + "px";
      // Só o HTML de `component`, que já passou por esc() e pelas listas do app.
      var inner = component(nd.name, th, nd, local);
      if (inner !== null) c.innerHTML = inner;
      else {
        c.className += " pv-bad";
        c.textContent = (lang === "pt" ? "componente desconhecido: " : "unknown component: ") + nd.name + " · " + (lang === "pt" ? "linha " : "line ") + nd.line;
      }
      b.appendChild(c);
      if (flagOpt(th, nd, "autohide", false)) n.classList.add("pv-autohide");
      // As linhas do CRT ficam por cima de tudo, mas o ponteiro passa (o clique-para-editar chega no que está embaixo).
      if (nd.name === "crt") n.classList.add("pv-pass");
    }
    n.appendChild(b);
    return n;
  }

  // Os tokens citados numa expressão de cor ("@surface", "alpha(@accent, 0.4)" ou, num nó, o
  // nome puro "sidebar"). Só nomes que existem na lista de tokens saem daqui.
  function refTokens(expr, bare) {
    if (typeof expr !== "string") return [];
    var out = [], m, re = /@([a-z][a-z0-9_-]*)/g;
    if (bare && TB.tokenName(expr.trim())) out.push(TB.tokenName(expr.trim()));
    while ((m = re.exec(expr)) && out.length < 4) { var t = TB.tokenName(m[1]); if (t && out.indexOf(t) < 0) out.push(t); }
    return out;
  }
  // O fundo de um nó: o do estilo nomeado e o do próprio nó (bg, depois o gradiente).
  function boxTokens(th, nd) {
    var toks = [], literal = false, sn = TB.str(nd, "style"), st = sn !== null && own(th.styles, sn) ? th.styles[sn] : null;
    [[nd, true], [st, false]].forEach(function (p) {
      if (!p[0]) return;
      ["bg", "gradient"].forEach(function (k) {
        var v = TB.str(p[0], k);
        if (v === null) return;
        var r = refTokens(v, p[1] && k === "bg");
        if (!r.length) literal = true;
        r.forEach(function (t) { if (toks.indexOf(t) < 0) toks.push(t); });
      });
    });
    return { toks: toks, literal: literal && !toks.length };
  }

  // Que token cada pedaço da prévia usa (as regras de theme-builder.css). O primeiro da lista é o
  // que o clique abre; "r" é a cor de cargo do elemento (style --c ou color com var(--rN)).
  // Ordem: do mais específico para o mais geral; vale o elemento mais perto do ponteiro.
  var INSPECT = [
    [".pv-men", ["mention"]], [".pv-msg.men", ["mention"]], [".pv-irc.men", ["mention", "text"]],
    [".pv-badge", ["danger"]], [".pv-newm span", ["danger"]], [".pv-newm", ["danger"]],
    [".pv-st.idle", ["idle"]], [".pv-st.dnd", ["dnd"]], [".pv-st.off", ["faint"]], [".pv-st", ["online"]],
    [".pv-mem.tty u.idle", ["idle"]], [".pv-mem.tty u.dnd", ["dnd"]], [".pv-mem.tty u.off", ["faint"]], [".pv-mem.tty u", ["online"]],
    [".pv-link", ["link"]], [".pv-embed>div>b", ["link"]], [".pv-embed small", ["muted"]], [".pv-embed", ["elevated", "idle", "text"]],
    [".pv-gi.on .pv-gico", ["accent", "accent-text"]], [".pv-gico.home", ["elevated", "text"]], [".pv-gico", ["r"]],
    [".pv-guild.list .pv-gi.on", ["selected", "text"]], [".pv-gtext .on", ["accent", "accent-text"]], [".pv-gtext", ["muted"]],
    [".pv-guild hr", ["border"]], [".pv-gi>span", ["muted"]], [".pv-guild.dock", ["elevated", "border"]],
    [".pv-banner", ["accent", "sidebar"]], [".pv-shead", ["text", "border"]], [".pv-chrows small", ["faint"]], [".pv-tree", ["faint"]],
    [".pv-chan.pills .pv-ch.on", ["accent", "accent-text"]], [".pv-chan.tree .pv-ch.on", ["accent", "accent-text"]],
    [".pv-ch.on", ["selected", "text"]], [".pv-ch.unread", ["text"]], [".pv-ch", ["muted"]], [".pv-vu", ["muted"]],
    [".pv-user .pv-who b", ["text"]], [".pv-user .pv-who small", ["muted"]], [".pv-user", ["muted"]],
    [".pv-hsearch", ["elevated", "faint"]], [".pv-head.tty b", ["accent"]], [".pv-head.min .pv-ht b", ["text"]], [".pv-head.min .pv-ht small", ["faint"]],
    [".pv-hdiv", ["border"]], [".pv-head>b", ["text"]], [".pv-head", ["muted", "border"]],
    [".pv-tabs.tty span.on", ["accent", "accent-text"]], [".pv-tabs.underline span.on", ["accent", "text"]], [".pv-tabs span.on", ["selected", "text"]],
    [".pv-tabs span u", ["r"]], [".pv-tabs", ["muted"]],
    [".pv-mh time", ["faint"]], [".pv-irc time", ["faint"]], [".pv-mh b", ["r"]], [".pv-irc b", ["r"]], [".pv-bb>b", ["r"]],
    [".pv-re em.mine", ["accent", "text"]], [".pv-re em", ["elevated", "muted"]],
    [".pv-bub.me .pv-bb", ["bubble-self", "bubble-self-text"]], [".pv-bb", ["bubble-other", "text"]], [".pv-ticks", ["muted"]], [".pv-typing i", ["muted"]],
    [".pv-mb p", ["text"]], [".pv-irc", ["text"]], [".pv-av", ["r"]],
    [".pv-comp.prompt>div", ["accent"]], [".pv-caret", ["accent"]], [".pv-comp .pv-cplus", ["muted", "elevated"]], [".pv-comp>div", ["elevated", "faint"]],
    [".pv-members small", ["faint"]], [".pv-mem.off b", ["faint"]], [".pv-mem .pv-who small", ["muted"]], [".pv-mem b", ["r"]], [".pv-members", ["muted"]],
    [".pv-status.pills span", ["elevated", "muted"]], [".pv-status", ["muted"]],
    [".pv-logo", ["accent"]], [".pv-tsearch", ["elevated", "faint"]], [".pv-top", ["muted"]],
    [".pv-msgs.ruled", ["border"]],
  ];
  // O que está embaixo do ponteiro: os tokens (o primeiro é o que o clique abre), o elemento que
  // casou, a camada do layout e os tokens que algum nó acima troca. Precisa de DOM (`closest`).
  function tokensAt(el, frame) {
    var hit = null, toks = [], role = null, comp = null, over = {}, lit = null, boxTok = null;
    function roleOf(e) {
      var v = (e.style && (e.style.getPropertyValue("--c") || e.style.color)) || "";
      var m = /var\(--r([0-7])\)/.exec(v);
      return m ? +m[1] : null;
    }
    for (var e = el; e && e !== frame && e.nodeType === 1; e = e.parentElement) {
      if (!hit) {
        for (var i = 0; i < INSPECT.length; i++) {
          if (!e.matches(INSPECT[i][0])) continue;
          hit = e;
          toks = INSPECT[i][1].slice();
          if (toks.indexOf("r") >= 0) {
            for (var r = e; r && r !== frame && role === null; r = r.parentElement) role = roleOf(r);
            toks = toks.filter(function (t) { return t !== "r"; });
            if (role !== null) toks.unshift("role:" + role);
          }
          break;
        }
      }
      if (e.classList && e.classList.contains("pv-b")) {
        var d = e.dataset || {};
        if (!comp && d.node && ["row", "column", "stack"].indexOf(d.node) < 0) comp = { name: d.node, line: +d.line || 0, start: +d.start };
        if (d.over) d.over.split(" ").forEach(function (t) { if (!own(over, t)) over[t] = +d.line || 0; });
        if (!hit && d.fg) { hit = e; toks = [d.fg]; }
        if (!boxTok && d.tk) { boxTok = d.tk.split(" "); if (!hit) hit = e; }
        if (!boxTok && d.lit && lit === null) { lit = +d.line || 0; if (!hit) hit = e; }
      }
    }
    (boxTok || ["bg"]).forEach(function (t) { if (toks.indexOf(t) < 0) toks.push(t); });
    return { el: hit || frame, tokens: toks, comp: comp, over: over, literal: lit };
  }

  // Desenha o tema `th` (de TB.loadTheme) dentro de `frame`, que tem a classe tb-frame e o
  // tamanho `size` ({ w, h }, a janela que a prévia imita; sem ele, 1280×800). O que some abaixo
  // de uma largura ou altura (hide-below…) segue esse tamanho, como no app.
  function mount(frame, th, size) {
    var prev = sizeNow;
    sizeNow = size && size.w > 0 && size.h > 0 ? { w: Math.round(size.w), h: Math.round(size.h) } : null;
    try { draw(frame, th); } finally { sizeNow = prev; }
  }
  function draw(frame, th) {
    var doc = frame.ownerDocument, f = frame;
    f.textContent = "";
    TB.TOKENS.forEach(function (k) { f.style.setProperty("--t-" + k, TB.cssColor(th.tokens[k])); });
    th.roles.forEach(function (c, i) { f.style.setProperty("--r" + i, TB.cssColor(c)); });
    f.style.setProperty("--f-ui", '"' + th.fontUi.replace(/["\\<>;{}]/g, "") + '",Inter,Archivo,system-ui,sans-serif');
    f.style.setProperty("--f-mono", '"' + th.fontMono.replace(/["\\<>;{}]/g, "") + '","JetBrains Mono",ui-monospace,monospace');
    f.style.setProperty("--pv-fs", th.fontSize * 0.9 + "px");
    f.style.setProperty("--pv-r", th.radius + "px");
    f.classList.toggle("pv-clear", th.transparent);
    f.classList.toggle("pv-light", th.mode === "light");
    f.style.setProperty("--pv-bg", TB.cssColor(th.tokens.bg));
    var root = th.layout.kids.filter(function (k) { return visible(th, k); })[0];
    if (!root) return;
    var tree = build(doc, th, root, null, th.tokens);
    tree.classList.add("pv-root");
    f.appendChild(tree);
  }

  // A janela que a prévia imita e a escala para caber em aw×ah (pixels da página), no "ajustar".
  // A janela nunca fica menor que 1200×720 (abaixo disso os layouts embutidos começam a esconder
  // a lista de membros), nem maior que 1920×1200, e fica entre 1,25:1 e 2:1. A escala não passa
  // de 100% enquanto a janela couber nesse limite: numa tela grande a prévia é o app em tamanho real.
  var MIN_W = 1200, MIN_H = 720, MAX_W = 1920, MAX_H = 1200;
  function frameFit(aw, ah) {
    aw = Math.max(1, aw);
    ah = Math.max(1, ah);
    var k = Math.min(1, aw / MIN_W, ah / MIN_H);
    k = Math.max(k, Math.min(aw / MAX_W, ah / MAX_H, 2));
    var w = Math.min(MAX_W, Math.max(MIN_W, aw / k)), h = Math.min(MAX_H, Math.max(MIN_H, ah / k));
    w = Math.min(w, h * 2);
    h = Math.min(h, w / 1.25);
    return { k: k, w: Math.floor(w), h: Math.floor(h) };
  }

  return { W: W, H: H, MIN_W: MIN_W, MIN_H: MIN_H, MAX_W: MAX_W, MAX_H: MAX_H, frameFit: frameFit, esc: esc, fontOf: fontOf, flagOpt: flagOpt, visible: visible, paintBox: paintBox, component: component, mount: mount, names: Object.keys(C),
    INSPECT: INSPECT, tokensAt: tokensAt, refTokens: refTokens, boxTokens: boxTokens };
});
