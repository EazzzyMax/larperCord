// O núcleo do criador de temas: sem DOM, para a página e o teste (tools/theme_builder_test.js)
// usarem o mesmo código. Leitor de KDL, cores e o carregamento do tema seguem
// src/theme/kdl.zig, color.zig, theme.zig e fx.zig; o arquivo gerado é o que o app lê.
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.LC_TB = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  function own(o, k) { return Object.prototype.hasOwnProperty.call(o, k); }

  // ------------------------------------------------------- Mensagens ----
  // Cada erro tem um código; o texto sai no idioma da página. O português usa as
  // mesmas palavras do app (src/theme/kdl.zig, theme.zig, fx.zig).
  var MSG = {
    en: {
      comment: "unclosed /* comment", depth: "too many nested blocks", close: "missing '}'", "extra-close": "unexpected '}'",
      "long-number": "number too long", number: "invalid number", name: "expected a name", string: "unterminated string", escape: "invalid escape",
      "option-name": "option without a name", "option-string": "option name must be a string",
      palette: "invalid palette color", token: "unknown color token: {0}", "missing-color": "missing color", "color-string": "the color must be a string",
      "color-expr": "invalid color expression", role: "invalid role color", "style-name": "style without a name", "style-string": "style name must be a string",
      invalid: "{0} is invalid", "no-layout": "the theme needs a `layout` node", "c-token": "unknown color token in c-…",
      "gradient-count": "a gradient needs 2 or 3 colors", "gradient-color": "invalid color in the gradient",
      "pattern-kind": "pattern: dots, lines, grid or diagonal", "pattern-color": "pattern needs pattern-color", side: "invalid side border",
      corners: "corners: all, left, right, top or bottom", weight: "weight: regular, medium, semibold, bold or italic",
      "span-text": "span without text", "span-color": "invalid color in the span",
      "link-version": "it comes from another version of this page", "link-broken": "it is incomplete or damaged",
      "link-layout": "it names a layout this page doesn't have", "link-unsupported": "this browser can't open compressed links",
      "css-too-big": "the CSS is bigger than 500 KB", "css-slow": "the CSS took too long to read",
      "css-empty": "no Discord color variables this page knows were found in the CSS",
      "community-missing": "this community theme couldn't be loaded from the site",
    },
    pt: {
      comment: "comentário /* sem fechar", depth: "blocos aninhados demais", close: "faltou fechar '}'", "extra-close": "'}' sobrando",
      "long-number": "número longo demais", number: "número inválido", name: "esperava um nome", string: "string sem fechar", escape: "escape inválido",
      "option-name": "opção sem nome", "option-string": "nome da opção deve ser string",
      palette: "cor inválida na paleta", token: "token de cor desconhecido: {0}", "missing-color": "faltou a cor", "color-string": "a cor deve ser uma string",
      "color-expr": "expressão de cor inválida", role: "cor de cargo inválida", "style-name": "estilo sem nome", "style-string": "nome do estilo deve ser string",
      invalid: "{0} inválido", "no-layout": "o tema precisa de um nó `layout`", "c-token": "token de cor desconhecido em c-…",
      "gradient-count": "gradiente pede 2 ou 3 cores", "gradient-color": "cor inválida no gradiente",
      "pattern-kind": "pattern: dots, lines, grid ou diagonal", "pattern-color": "pattern precisa de pattern-color", side: "borda de lado inválida",
      corners: "corners: all, left, right, top ou bottom", weight: "weight: regular, medium, semibold, bold ou italic",
      "span-text": "span sem texto", "span-color": "cor inválida no span",
      "link-version": "ele é de outra versão desta página", "link-broken": "ele está incompleto ou danificado",
      "link-layout": "ele cita um layout que esta página não tem", "link-unsupported": "este navegador não abre links comprimidos",
      "css-too-big": "o CSS passa de 500 KB", "css-slow": "o CSS demorou demais para ser lido",
      "css-empty": "o CSS não tem nenhuma variável de cor do Discord que esta página conheça",
      "community-missing": "não deu para carregar este tema da comunidade do site",
    },
  };
  // As propriedades femininas, como o app escreve ("border inválida", "grain inválido").
  var FEM = ["border", "vignette", "inner-shadow", "drop-shadow", "pattern-color", "shadow", "color"];
  function errorText(e, lang) {
    var L = lang === "pt" ? "pt" : "en";
    if (!e || !e.code || !own(MSG[L], e.code)) return e && e.message ? String(e.message) : String(e);
    var t = MSG[L][e.code];
    if (L === "pt" && e.code === "invalid" && FEM.indexOf(e.arg) >= 0) t = "{0} inválida";
    return t.replace("{0}", e.arg === undefined ? "" : String(e.arg));
  }

  // ------------------------------------------------------------ KDL ----
  function KdlError(code, line, column, arg) {
    this.code = code;
    this.arg = arg;
    this.message = errorText(this, "en");
    this.line = line;
    this.column = column;
  }
  KdlError.prototype.toString = function () { return this.line + ":" + this.column + ": " + this.message; };

  // Mesmo subconjunto de src/theme/kdl.zig. Cada nó guarda onde começa e termina no
  // texto, e cada propriedade onde está o valor: assim um ajuste troca só aquele pedaço.
  function parseKdl(src) {
    var i = 0, line = 1, lineStart = 0, depth = 0, n = src.length;
    function fail(code) { throw new KdlError(code, line, i - lineStart + 1); }
    function peek() { return i < n ? src[i] : ""; }
    function starts(s) { return src.startsWith(s, i); }
    function adv() {
      if (i < n && src[i] === "\n") { line++; lineStart = i + 1; }
      i++;
    }
    function skipSpace(nl) {
      while (i < n) {
        var ch = src[i];
        if (ch === " " || ch === "\t" || ch === "\r") adv();
        else if (ch === "\n" && nl) adv();
        else if (ch === "\\") {
          adv();
          while (peek() === " " || peek() === "\t" || peek() === "\r") adv();
          if (starts("//")) while (peek() !== "\n" && peek() !== "") adv();
          if (peek() === "\n") adv();
        } else if (starts("//")) {
          while (peek() !== "\n" && peek() !== "") adv();
        } else if (starts("/*")) {
          var d = 0;
          while (i < n) {
            if (starts("/*")) { d++; adv(); adv(); }
            else if (starts("*/")) { d--; adv(); adv(); if (d === 0) break; }
            else adv();
          }
          if (d !== 0) fail("comment");
        } else break;
      }
    }
    function isNumberStart() {
      var ch = peek();
      if (ch >= "0" && ch <= "9") return true;
      if ((ch === "-" || ch === "+" || ch === ".") && i + 1 < n) {
        var c2 = src[i + 1];
        return c2 >= "0" && c2 <= "9";
      }
      return false;
    }
    var STOP = " \t\r\n=;{}\"()\\";
    function identOrString() {
      if (peek() === '"') return string();
      var s = i;
      while (i < n && STOP.indexOf(src[i]) < 0) i++;
      if (i === s) fail("name");
      return src.slice(s, i);
    }
    function string() {
      adv();
      var out = "";
      for (;;) {
        if (i >= n) fail("string");
        var ch = src[i];
        if (ch === '"') { adv(); break; }
        if (ch === "\\") {
          adv();
          var e = peek(), r = { n: "\n", t: "\t", r: "\r", '"': '"', "\\": "\\", "/": "/" }[e];
          if (r === undefined) fail("escape");
          out += r;
          adv();
          continue;
        }
        out += ch;
        adv();
      }
      return out;
    }
    function number() {
      var s = i;
      while (i < n && /[0-9.+\-_eE]/.test(src[i])) i++;
      var txt = src.slice(s, i).replace(/_/g, "");
      if (txt.length > 64) fail("long-number");
      if (!/^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(txt)) fail("number");
      return +txt;
    }
    function value() {
      if (peek() === '"') return string();
      if (isNumberStart()) return number();
      var w = identOrString();
      if (w === "true" || w === "#true") return true;
      if (w === "false" || w === "#false") return false;
      if (w === "null" || w === "#null") return null;
      return w;
    }
    function node() {
      var nd = { name: "", args: [], props: [], kids: [], line: line, col: i - lineStart + 1, start: i, headEnd: 0, end: 0 };
      nd.name = identOrString();
      nd.headEnd = i;
      for (;;) {
        skipSpace(false);
        var ch = peek();
        if (ch === "" || ch === "\n" || ch === ";" || ch === "}") break;
        if (ch === "{") {
          nd.open = i;
          adv();
          nd.kids = nodeList(true);
          nd.end = i;
          return nd;
        }
        var skip = false;
        if (starts("/-")) {
          skip = true;
          adv(); adv();
          skipSpace(false);
          if (peek() === "{") { adv(); nodeList(true); continue; }
        }
        var s = i;
        if (peek() !== '"' && !isNumberStart()) {
          var key = identOrString();
          if (peek() === "=") {
            adv();
            var vs = i, v = value();
            if (!skip) nd.props.push({ k: key, v: v, ks: s, vs: vs, ve: i });
            nd.headEnd = i;
            continue;
          }
          i = s;
        } else if (peek() === '"') {
          var k2 = string();
          if (peek() === "=") {
            adv();
            var vs2 = i, v2 = value();
            if (!skip) nd.props.push({ k: k2, v: v2, ks: s, vs: vs2, ve: i });
            nd.headEnd = i;
            continue;
          }
          if (!skip) nd.args.push({ v: k2, s: s, e: i });
          nd.headEnd = i;
          continue;
        }
        var as = i, av = value();
        if (!skip) nd.args.push({ v: av, s: as, e: i });
        nd.headEnd = i;
      }
      nd.end = nd.headEnd;
      return nd;
    }
    function nodeList(inBlock) {
      if (depth >= 64) fail("depth");
      depth++;
      var list = [];
      for (;;) {
        skipSpace(true);
        while (peek() === ";") { adv(); skipSpace(true); }
        if (i >= n) {
          if (inBlock) fail("close");
          break;
        }
        if (peek() === "}") {
          if (!inBlock) fail("extra-close");
          adv();
          break;
        }
        var skip = false;
        if (starts("/-")) { skip = true; adv(); adv(); skipSpace(true); }
        var nd = node();
        if (!skip) list.push(nd);
      }
      depth--;
      return list;
    }
    return nodeList(false);
  }

  function prop(nd, key) {
    for (var i = nd.props.length - 1; i >= 0; i--) if (nd.props[i].k === key) return nd.props[i];
    return null;
  }
  function pv(nd, key) { var p = prop(nd, key); return p ? p.v : undefined; }
  function str(nd, key) { var v = pv(nd, key); return typeof v === "string" ? v : null; }
  function num(nd, key) { var v = pv(nd, key); return typeof v === "number" ? v : null; }
  function flag(nd, key) {
    var v = pv(nd, key);
    if (typeof v === "boolean") return v;
    if (typeof v === "number") return v !== 0;
    return null;
  }
  function arg(nd, i) { return i < nd.args.length ? nd.args[i].v : undefined; }

  // ------------------------------------------------------------ Cores ----
  var TOKENS = ["bg", "rail", "sidebar", "surface", "elevated", "overlay", "text", "muted", "faint", "accent",
    "accent-text", "border", "hover", "selected", "online", "idle", "dnd", "danger", "mention", "link",
    "code-bg", "bubble-self", "bubble-self-text", "bubble-other", "shadow"];
  var FALLBACK = ["#15161b", "#e06c75", "#98c379", "#e5c07b", "#7aa2f7", "#c678dd", "#56b6c2", "#d7dae0",
    "#5c6370", "#e06c75", "#98c379", "#e5c07b", "#7aa2f7", "#c678dd", "#56b6c2", "#f0f2f5"];
  var BLACK = [0, 0, 0, 1], WHITE = [1, 1, 1, 1], CLEAR = [0, 0, 0, 0];

  function tokenName(name) {
    var t = String(name).replace(/_/g, "-");
    return TOKENS.indexOf(t) >= 0 ? t : null;
  }

  function parseHex(h) {
    if (!/^[0-9a-fA-F]+$/.test(h)) return null;
    var v = parseInt(h, 16), x = function (d) { return d * 17 / 255; };
    switch (h.length) {
      case 3: return [x(v >> 8 & 15), x(v >> 4 & 15), x(v & 15), 1];
      case 4: return [x(v >> 12 & 15), x(v >> 8 & 15), x(v >> 4 & 15), x(v & 15)];
      case 6: return [(v >> 16 & 255) / 255, (v >> 8 & 255) / 255, (v & 255) / 255, 1];
      case 8: return [(v >>> 24 & 255) / 255, (v >> 16 & 255) / 255, (v >> 8 & 255) / 255, (v & 255) / 255];
    }
    return null;
  }
  function hexRgba(s) {
    var c = parseHex(String(s).trim().replace(/^#/, ""));
    if (!c) throw new Error("bad hex " + s);
    return c;
  }
  function mix(a, b, k) { return [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k]; }
  function alpha(c, k) { return [c[0], c[1], c[2], c[3] * k]; }
  function luma(c) { return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; }
  function luminance(c) {
    var q = function (x) { return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4); };
    return 0.2126 * q(c[0]) + 0.7152 * q(c[1]) + 0.0722 * q(c[2]);
  }
  function contrast(a, b) {
    var la = luminance(a), lb = luminance(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
  }
  function clamp01(x) { return x < 0 ? 0 : x > 1 ? 1 : x; }
  // `a` por cima de `b` (b opaco): o que se vê.
  function over(a, b) {
    var k = a[3] === undefined ? 1 : a[3];
    return [a[0] * k + b[0] * (1 - k), a[1] * k + b[1] * (1 - k), a[2] * k + b[2] * (1 - k), 1];
  }
  function byte(x) { return Math.round(clamp01(x) * 255); }
  function toHex(c) {
    var h = "#" + [c[0], c[1], c[2]].map(function (x) { return (256 + byte(x)).toString(16).slice(1); }).join("");
    var a = byte(c[3] === undefined ? 1 : c[3]);
    return a === 255 ? h : h + (256 + a).toString(16).slice(1);
  }
  function normHex(s) { return toHex(hexRgba(s)); }
  function cssColor(c) {
    var a = c[3] === undefined ? 1 : c[3];
    if (a >= 0.999) return toHex([c[0], c[1], c[2], 1]);
    return "rgba(" + byte(c[0]) + "," + byte(c[1]) + "," + byte(c[2]) + "," + (+clamp01(a).toFixed(3)) + ")";
  }

  function ColorError(msg) { this.message = msg; }

  // `eval` de color.zig. `bare`: aceita o nome do token sem arroba quando ele é a
  // expressão inteira, como `color.compile` faz para estilos e nós.
  function evalColor(src, pal, lookup, bare) {
    var s = String(src), i = 0, depth = 0;
    if (bare) {
      var t = s.replace(/^[ \t]+|[ \t]+$/g, "");
      if (tokenName(t)) { var v0 = lookup(tokenName(t)); if (v0) return v0; }
    }
    function bad() { throw new ColorError("invalid color: " + src); }
    function skip() { while (i < s.length && (s[i] === " " || s[i] === "\t")) i++; }
    function word() {
      var st = i;
      while (i < s.length && /[A-Za-z0-9\-_:@#.]/.test(s[i])) i++;
      return s.slice(st, i);
    }
    function expect(ch) { skip(); if (i >= s.length || s[i] !== ch) bad(); i++; }
    function number() {
      skip();
      var w = word();
      if (!/^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(w)) bad();
      return +w;
    }
    function atom(w) {
      if (w[0] === "#") return parseHex(w.slice(1)) || bad();
      if (w[0] === "@") {
        var tn = tokenName(w.slice(1));
        var v = tn && lookup(tn);
        return v || bad();
      }
      if (w.indexOf("wal:") === 0) {
        var idx = w.slice(4);
        if (!/^\+?\d+$/.test(idx) || +idx >= 16) bad();
        return pal[+idx];
      }
      if (w === "black") return BLACK;
      if (w === "white") return WHITE;
      if (w === "transparent") return CLEAR;
      return bad();
    }
    function expr() {
      if (depth >= 16) bad();
      depth++;
      skip();
      var w = word();
      if (!w.length) bad();
      skip();
      var out;
      if (i < s.length && s[i] === "(") {
        i++;
        var a = expr();
        if (w === "mix") {
          expect(",");
          var b = expr();
          expect(",");
          var k = number();
          expect(")");
          out = mix(a, b, k);
        } else {
          expect(",");
          var k2 = number();
          expect(")");
          if (w === "alpha") out = alpha(a, k2);
          else if (w === "lighten") out = mix(a, alpha(WHITE, a[3]), k2);
          else if (w === "darken") out = mix(a, alpha(BLACK, a[3]), k2);
          else bad();
        }
      } else out = atom(w);
      depth--;
      return out;
    }
    var v = expr();
    skip();
    if (i !== s.length) bad();
    return v;
  }

  // `splitColors` de fx.zig: espaços fora dos parênteses separam as cores.
  function splitColors(src) {
    var out = [], depth = 0, start = -1;
    for (var i = 0; i < src.length; i++) {
      var ch = src[i];
      if (ch === "(") depth++;
      if (ch === ")" && depth > 0) depth--;
      var sep = depth === 0 && (ch === " " || ch === "\t");
      if (sep) { if (start >= 0) { out.push(src.slice(start, i)); start = -1; } }
      else if (start < 0) start = i;
    }
    if (start >= 0) out.push(src.slice(start));
    return out;
  }

  // ------------------------------------------------------ O tema em si ----
  // Os padrões derivados da paleta, iguais a `defaults` e `lightDefaults` de theme.zig.
  function defaults(pal, mode) {
    var t = {};
    if (mode === "light") {
      var tint = pal[0], bgL = mix(WHITE, tint, 0.035), ink = mix(mix(tint, BLACK, 0.55), pal[15], 0.05);
      var acc = luma(pal[4]) > 0.5 ? mix(pal[4], BLACK, 0.3) : pal[4], onL = luma(acc) > 0.6 ? BLACK : WHITE;
      t.bg = bgL; t.rail = mix(WHITE, tint, 0.12); t.sidebar = mix(WHITE, tint, 0.07); t.surface = bgL;
      t.elevated = mix(WHITE, tint, 0.09); t.overlay = WHITE; t.text = ink; t.muted = mix(ink, bgL, 0.4);
      t.faint = mix(ink, bgL, 0.6); t.accent = acc; t["accent-text"] = onL; t.border = alpha(ink, 0.1);
      t.hover = alpha(ink, 0.05); t.selected = alpha(acc, 0.13); t.online = hexRgba("23a55a"); t.idle = hexRgba("d08a12");
      t.dnd = hexRgba("d83a42"); t.danger = hexRgba("d83a42"); t.mention = acc; t.link = mix(acc, BLACK, 0.1);
      t["code-bg"] = mix(bgL, ink, 0.07); t["bubble-self"] = acc; t["bubble-self-text"] = onL;
      t["bubble-other"] = mix(WHITE, tint, 0.1); t.shadow = alpha(BLACK, 0.12);
      return t;
    }
    var bg = pal[0], fg = pal[15], on = luma(pal[4]) > 0.6 ? BLACK : WHITE;
    t.bg = mix(bg, fg, 0.035); t.rail = mix(bg, BLACK, 0.38); t.sidebar = mix(bg, BLACK, 0.18);
    t.surface = mix(bg, fg, 0.035); t.elevated = mix(bg, fg, 0.085); t.overlay = mix(bg, BLACK, 0.55);
    t.text = fg; t.muted = mix(fg, bg, 0.42); t.faint = mix(fg, bg, 0.62); t.accent = pal[4]; t["accent-text"] = on;
    t.border = alpha(fg, 0.08); t.hover = alpha(fg, 0.05); t.selected = alpha(fg, 0.1);
    t.online = hexRgba("45b36b"); t.idle = hexRgba("e5a83b"); t.dnd = hexRgba("e5484d"); t.danger = hexRgba("e5484d");
    t.mention = pal[4]; t.link = mix(pal[4], fg, 0.25); t["code-bg"] = mix(bg, BLACK, 0.45);
    t["bubble-self"] = pal[4]; t["bubble-self-text"] = on; t["bubble-other"] = mix(bg, fg, 0.1); t.shadow = alpha(BLACK, 0.35);
    return t;
  }

  function defaultRoles(pal, mode) {
    var r = [pal[4], pal[1], pal[3], pal[5], pal[6], pal[12], pal[9], pal[13]];
    if (mode === "light") r = r.map(function (c) { return luma(c) > 0.45 ? mix(c, BLACK, 0.35) : c; });
    return r;
  }

  // O texto secundário que o app garante (`legibleText`): muted >= 5,5:1 e faint >= 4,5:1
  // contra bg, surface, sidebar e elevated. Sobe em direção ao texto só o quanto precisa.
  var LEGIBLE = [{ tok: "muted", min: 5.5 }, { tok: "faint", min: 4.5 }];
  var BACKS = ["bg", "surface", "sidebar", "elevated"];
  function legibleFor(toks, tok, min) {
    var base = toks[tok], text = toks.text;
    // Passo em f32, como o laço do Zig: a soma de 0,05 vinte vezes passa de 1.
    for (var k = 0; k <= 1; k = Math.fround(k + Math.fround(0.05))) {
      var col = mix(base, text, k), ok = true;
      for (var j = 0; j < BACKS.length; j++) if (contrast(col, toks[BACKS[j]]) < min) { ok = false; break; }
      if (ok) return col;
    }
    return text;
  }
  function legibleText(toks) {
    LEGIBLE.forEach(function (w) { toks[w.tok] = legibleFor(toks, w.tok, w.min); });
  }

  function applies(nd, mode, opts) {
    var m = str(nd, "mode");
    if (m !== null && m !== mode) return false;
    var w = str(nd, "when");
    if (w !== null && !opts[w]) return false;
    var u = str(nd, "unless");
    if (u !== null && opts[u]) return false;
    return true;
  }

  function optionList(nodes) {
    var list = [];
    nodes.forEach(function (nd) {
      if (nd.name !== "options") return;
      nd.kids.forEach(function (ch) {
        var name = arg(ch, 0);
        if (typeof name !== "string") throw new KdlError(name === undefined ? "option-name" : "option-string", ch.line, ch.col);
        var d = flag(ch, "default");
        list.push({
          name: name, label: str(ch, "label") || name, desc: str(ch, "description") || "",
          labelEn: str(ch, "label-en") || "", descEn: str(ch, "description-en") || "", def: d === null ? true : d, node: ch,
        });
      });
    });
    return list;
  }

  function ThemeError(code, line, arg) {
    this.code = code;
    this.arg = arg;
    this.message = errorText(this, "en");
    this.line = line || 0;
    this.column = 0;
  }
  ThemeError.prototype.toString = function () { return this.line + ": " + this.message; };

  // Porta de `loadWith` (theme.zig) mais a validação das primitivas (fx.zig):
  // se isto aceita, o app aceita. `opt.wal` é a paleta do pywal (o site não tem uma).
  function loadTheme(src, opt) {
    opt = opt || {};
    var mode = opt.mode === "light" ? "light" : "dark";
    var nodes = typeof src === "string" ? parseKdl(src) : src;
    // Sem protótipo: uma opção ou um estilo chamado "constructor" não acha nada de fora.
    var options = optionList(nodes), values = Object.create(null);
    options.forEach(function (o) {
      values[o.name] = opt.overrides && o.name in opt.overrides ? !!opt.overrides[o.name] : o.def;
    });
    values["modo-claro"] = mode === "light";
    values["modo-escuro"] = mode === "dark";

    var pal = FALLBACK.map(hexRgba), usesWal = false;
    nodes.forEach(function (nd) {
      if (nd.name !== "palette" || !applies(nd, mode, values)) return;
      if (nd.args.length && nd.args[0].v === "wal") {
        usesWal = true;
        if (opt.wal) pal = opt.wal.slice();
        return;
      }
      nd.args.forEach(function (a, i) {
        if (i >= 16 || typeof a.v !== "string") return;
        var c = parseHex(a.v.replace(/^#+/, ""));
        if (!c) throw new ThemeError("palette", nd.line);
        pal[i] = c;
      });
    });

    var th = {
      mode: mode, name: "sem nome", description: "", descriptionEn: "", author: "", license: "", preview: "classic",
      tokens: defaults(pal, mode), roles: defaultRoles(pal, mode), palette: pal, usesWal: usesWal,
      fontUi: "Inter", fontMono: "JetBrains Mono", fontSize: 16, radius: 6, transparent: false,
      styles: Object.create(null), layout: null, options: options, values: values, nodes: nodes,
    };
    var lookup = function (name) { return th.tokens[name]; };
    function color(e, nd, code, arg) {
      try { return evalColor(e, pal, lookup, false); } catch (err) { throw new ThemeError(code, nd.line, arg); }
    }
    nodes.forEach(function (nd) {
      if (!applies(nd, mode, values)) return;
      switch (nd.name) {
        case "theme":
          if (typeof arg(nd, 0) === "string") th.name = arg(nd, 0);
          th.description = str(nd, "description") || th.description;
          th.descriptionEn = str(nd, "description-en") || th.descriptionEn;
          th.author = str(nd, "author") || th.author;
          // O app não lê `license` (nem reclama dela): é para a galeria da comunidade.
          th.license = str(nd, "license") || th.license;
          th.preview = str(nd, "preview") || th.preview;
          break;
        case "colors":
          nd.kids.forEach(function (ch) {
            var tok = tokenName(ch.name);
            if (!tok) throw new ThemeError("token", ch.line, ch.name);
            var e = arg(ch, 0);
            if (e === undefined) throw new ThemeError("missing-color", ch.line);
            if (typeof e !== "string") throw new ThemeError("color-string", ch.line);
            th.tokens[tok] = color(e, ch, "color-expr");
          });
          break;
        case "roles":
          nd.args.forEach(function (a, i) {
            if (i >= 8 || typeof a.v !== "string") return;
            th.roles[i] = color(a.v, nd, "role");
          });
          break;
        case "fonts":
          if (str(nd, "ui") !== null) th.fontUi = str(nd, "ui");
          if (str(nd, "mono") !== null) th.fontMono = str(nd, "mono");
          if (num(nd, "size") !== null) th.fontSize = Math.min(72, Math.max(6, num(nd, "size")));
          break;
        case "metrics":
          if (num(nd, "radius") !== null) th.radius = Math.min(64, Math.max(0, num(nd, "radius")));
          break;
        case "window":
          if (flag(nd, "transparent") !== null) th.transparent = flag(nd, "transparent");
          break;
        case "styles":
          nd.kids.forEach(function (ch) {
            var sname = arg(ch, 0);
            if (sname === undefined) throw new ThemeError("style-name", ch.line);
            if (typeof sname !== "string") throw new ThemeError("style-string", ch.line);
            ["bg", "border", "glow"].forEach(function (k) { if (str(ch, k) !== null) color(str(ch, k), ch, "invalid", k); });
            th.styles[sname] = ch;
          });
          break;
        case "layout":
          th.layout = nd;
          break;
      }
    });
    th.authored = Object.assign({}, th.tokens);
    legibleText(th.tokens);
    if (!th.layout) throw new ThemeError("no-layout", 0);
    // As primitivas são checadas com os tokens do fim, como o app compila.
    Object.keys(th.styles).forEach(function (k) { checkBox(th, th.styles[k], true); });
    checkLayout(th, th.layout);
    th.transparent = th.transparent || th.tokens.bg[3] < 0.999;
    return th;
  }

  // ---------------------------------------- Primitivas (checagem, fx.zig) ----
  var SIDES = ["border-top", "border-right", "border-bottom", "border-left"];
  var PAINTED = ["shape", "rule", "starfield", "orbit", "aurora", "dunes", "topography", "radar", "window-controls"];
  var PAINT_KEYS = ["color", "color2", "color3", "fill", "dot", "ornament-color"];

  function fxColor(th, e, nd, code, arg) {
    try { return evalColor(e, th.palette, function (n) { return th.tokens[n]; }, true); } catch (err) { throw new ThemeError(code, nd.line, arg); }
  }
  function checkGradient(th, nd, key) {
    var parts = splitColors(str(nd, key));
    if (parts.length < 2 || parts.length > 3) throw new ThemeError("gradient-count", nd.line);
    parts.forEach(function (p) { fxColor(th, p, nd, "gradient-color"); });
  }
  function checkBox(th, nd, isStyle) {
    if (str(nd, "gradient") !== null) checkGradient(th, nd, "gradient");
    if (str(nd, "pattern") !== null) {
      if (["dots", "lines", "grid", "diagonal"].indexOf(str(nd, "pattern")) < 0) throw new ThemeError("pattern-kind", nd.line);
      if (str(nd, "pattern-color") === null) throw new ThemeError("pattern-color", nd.line);
      fxColor(th, str(nd, "pattern-color"), nd, "invalid", "pattern-color");
    }
    ["grain", "vignette", "inner-shadow", "drop-shadow", "hover-bg"].forEach(function (k) {
      if (str(nd, k) !== null) fxColor(th, str(nd, k), nd, "invalid", k);
    });
    if (str(nd, "border-gradient") !== null) checkGradient(th, nd, "border-gradient");
    if (!isStyle && str(nd, "border") !== null) fxColor(th, str(nd, "border"), nd, "invalid", "border");
    SIDES.forEach(function (k) { if (str(nd, k) !== null) fxColor(th, str(nd, k), nd, "side"); });
    var c = str(nd, "corners");
    if (c !== null && ["all", "left", "right", "top", "bottom"].indexOf(c) < 0) throw new ThemeError("corners", nd.line);
  }
  var WEIGHTS = ["regular", "medium", "semibold", "bold", "italic"];
  function checkLabel(th, ch) {
    // Como `labelWantsFx` de fx.zig: o rótulo simples não passa por esta leitura.
    var col = str(ch, "color"), colExpr = col !== null && !tokenName(col);
    var wants = colExpr || ch.kids.some(function (k) { return k.name === "span"; }) ||
      ["tracking", "shadow", "outline", "text-gradient", "text-en"].some(function (k) { return prop(ch, k) !== null; });
    if (!wants) return;
    if (col !== null) fxColor(th, col, ch, "invalid", "color");
    if (str(ch, "weight") !== null && WEIGHTS.indexOf(str(ch, "weight")) < 0) throw new ThemeError("weight", ch.line);
    ["shadow", "outline"].forEach(function (k) { if (str(ch, k) !== null) fxColor(th, str(ch, k), ch, "invalid", k); });
    if (str(ch, "text-gradient") !== null) checkGradient(th, ch, "text-gradient");
    ch.kids.forEach(function (sp) {
      if (sp.name !== "span") return;
      var txt = typeof arg(sp, 0) === "string" ? arg(sp, 0) : str(sp, "text");
      if (txt === null) throw new ThemeError("span-text", sp.line);
      if (str(sp, "weight") !== null && WEIGHTS.indexOf(str(sp, "weight")) < 0) throw new ThemeError("weight", sp.line);
      if (str(sp, "color") !== null) fxColor(th, str(sp, "color"), sp, "span-color");
    });
  }
  function checkLayout(th, nd) {
    nd.kids.forEach(function (ch) {
      var bg = str(ch, "bg");
      if (bg !== null && !tokenName(bg)) fxColor(th, bg, ch, "invalid", "bg");
      checkBox(th, ch, false);
      if (ch.name === "label") {
        checkLabel(th, ch);
      } else if (PAINTED.indexOf(ch.name) >= 0) {
        PAINT_KEYS.forEach(function (k) { if (str(ch, k) !== null) fxColor(th, str(ch, k), ch, "invalid", "color"); });
      }
      ch.props.forEach(function (p) {
        var m = /^(c|cl|cd)-(.+)$/.exec(p.k);
        if (!m || (m[1] === "cl" && th.mode !== "light") || (m[1] === "cd" && th.mode !== "dark")) return;
        if (!tokenName(m[2])) throw new ThemeError("c-token", ch.line);
        if (typeof p.v !== "string") throw new ThemeError("color-string", ch.line);
        try { evalColor(p.v, th.palette, function (n) { return th.tokens[n]; }, false); } catch (e) { throw new ThemeError("color-expr", ch.line); }
      });
      if (ch.name !== "label") checkLayout(th, ch);
    });
  }

  // ------------------------------------------------- Estado do criador ----
  // O que a página edita. Cores sempre resolvidas em hex; o resto do arquivo
  // (opções, estilos, layout, blocos condicionais) fica como texto em `structure`.
  var ABSORB_MODED = ["palette", "colors", "roles"];
  var ABSORB_PLAIN = ["theme", "fonts", "metrics", "window"];

  function absorbable(nd) {
    var cond = str(nd, "when") !== null || str(nd, "unless") !== null;
    if (ABSORB_MODED.indexOf(nd.name) >= 0) return !cond;
    if (ABSORB_PLAIN.indexOf(nd.name) >= 0) return !cond && str(nd, "mode") === null;
    return false;
  }

  // O pedaço do texto de um nó de topo, com os comentários colados logo acima.
  function chunk(src, nd) {
    var s = src.lastIndexOf("\n", nd.start - 1) + 1;
    if (src.slice(s, nd.start).trim()) return src.slice(nd.start, nd.end);
    for (;;) {
      if (s === 0) break;
      var prevEnd = s - 1, prevStart = src.lastIndexOf("\n", prevEnd - 1) + 1;
      var prev = src.slice(prevStart, prevEnd);
      if (/^\s*\/\//.test(prev)) s = prevStart;
      else break;
    }
    return src.slice(s, nd.end).replace(/\s+$/, "");
  }

  function fromSource(src, info) {
    info = info || {};
    var nodes = parseKdl(src);
    var state = {
      v: 1, base: info.base || null, layoutFrom: info.base || null,
      meta: { name: info.name || "", author: "", desc: "", descEn: "", preview: "classic", license: "" },
      palette: {}, colors: {}, roles: {},
      fonts: { ui: "Inter", mono: "JetBrains Mono", size: 16 }, radius: 6, transparent: false, usesWal: false,
      structure: "",
    };
    var kept = nodes.filter(function (nd) { return absorbable(nd); });
    ["dark", "light"].forEach(function (mode) {
      var th = loadTheme(kept.concat([{ name: "layout", args: [], props: [], kids: [], line: 0 }]), { mode: mode });
      state.palette[mode] = th.palette.map(toHex);
      state.colors[mode] = {};
      TOKENS.forEach(function (t) { state.colors[mode][t] = toHex(th.authored[t]); });
      state.roles[mode] = th.roles.map(toHex);
      if (th.usesWal) state.usesWal = true;
      if (mode === "dark") {
        state.meta.name = state.meta.name || (th.name !== "sem nome" ? th.name : "");
        state.meta.author = th.author;
        state.meta.license = th.license;
        state.meta.desc = th.description;
        state.meta.descEn = th.descriptionEn;
        state.meta.preview = th.preview;
        state.fonts = { ui: th.fontUi, mono: th.fontMono, size: th.fontSize };
        state.radius = th.radius;
        state.transparent = kept.reduce(function (v, nd) { return nd.name === "window" && flag(nd, "transparent") !== null ? flag(nd, "transparent") : v; }, false);
      }
    });
    state.structure = nodes.filter(function (nd) { return !absorbable(nd); }).map(function (nd) { return chunk(src, nd); }).join("\n\n");
    return state;
  }

  // ------------------------------------------------------ Gerar o .kdl ----
  function q(s) {
    return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/\t/g, "\\t") + '"';
  }
  function fmtNum(v) {
    var r = Math.round(v * 1000) / 1000;
    return String(r);
  }
  function slug(s) {
    var t = String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
    t = t.replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 48);
    return t || "my-theme";
  }
  var PREVIEWS = ["classic", "glass", "terminal", "bubbles", "zen", "mirror", "office", "desktop"];

  function samePalette(a, b) { return a.every(function (x, i) { return normHex(x) === normHex(b[i]); }); }

  function toKdl(state, extra) {
    extra = extra || {};
    var m = state.meta, file = slug(m.name), out = [];
    var desc = m.desc || m.descEn, descEn = m.descEn && m.descEn !== desc ? m.descEn : "";
    out.push("// " + file + ".kdl" + (desc || descEn ? ": " + (descEn || desc).replace(/\s+/g, " ") : ""));
    // O nome do tema de partida vai num comentário: só letras, números e hífen, nunca uma quebra de linha.
    var base = String(state.base || "").replace(/[^a-z0-9-]/g, "");
    out.push("// Made in the larperCord theme builder" + (base ? ", starting from " + base : "") + ".");
    if (extra.url) out.push("// " + extra.url);
    var head = "theme " + q(m.name || file);
    if (desc) head += " description=" + q(desc);
    if (descEn) head += " description-en=" + q(descEn);
    if (m.author) head += " author=" + q(m.author);
    if (m.license) head += " license=" + q(m.license);
    head += " preview=" + (PREVIEWS.indexOf(m.preview) >= 0 ? m.preview : "classic");
    out.push(head);
    var pd = state.palette.dark.map(normHex), pl = state.palette.light.map(normHex);
    if (samePalette(pd, pl)) out.push("palette " + pd.map(q).join(" "));
    else {
      out.push("palette mode=dark " + pd.map(q).join(" "));
      out.push("palette mode=light " + pl.map(q).join(" "));
    }
    ["dark", "light"].forEach(function (mode) {
      out.push("");
      out.push("colors mode=" + mode + " {");
      TOKENS.forEach(function (t) {
        var pad = t.length < 16 ? new Array(17 - t.length).join(" ") : " ";
        out.push("    " + t + pad + q(normHex(state.colors[mode][t])));
      });
      out.push("}");
      out.push("roles mode=" + mode + " " + state.roles[mode].map(function (c) { return q(normHex(c)); }).join(" "));
    });
    out.push("");
    out.push("fonts ui=" + q(state.fonts.ui || "Inter") + " mono=" + q(state.fonts.mono || "JetBrains Mono") + " size=" + fmtNum(state.fonts.size || 16));
    out.push("metrics radius=" + fmtNum(state.radius));
    if (state.transparent) out.push("window transparent=#true");
    out.push("");
    out.push(String(state.structure || "").replace(/\s+$/, ""));
    return out.join("\n") + "\n";
  }

  // ---------------------------------------------- Ajustes no texto do layout ----
  // Troca (ou acrescenta, ou tira) uma propriedade de um nó, mexendo só naquele pedaço.
  function findNode(nodes, start) {
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].start === start) return nodes[i];
      var f = findNode(nodes[i].kids, start);
      if (f) return f;
    }
    return null;
  }
  function valueText(v) {
    if (v === true) return "#true";
    if (v === false) return "#false";
    if (typeof v === "number") return fmtNum(v);
    if (typeof v === "string" && /^[A-Za-z][A-Za-z0-9_-]*$/.test(v) && ["true", "false", "null"].indexOf(v) < 0) return v;
    return q(v);
  }
  function setProp(text, start, key, value) {
    var nodes = parseKdl(text), nd = findNode(nodes, start);
    if (!nd) return text;
    var p = prop(nd, key);
    if (value === null || value === undefined || value === "") {
      if (!p) return text;
      var s = p.ks;
      while (s > 0 && (text[s - 1] === " " || text[s - 1] === "\t")) s--;
      return text.slice(0, s) + text.slice(p.ve);
    }
    if (p) return text.slice(0, p.vs) + valueText(value) + text.slice(p.ve);
    return text.slice(0, nd.headEnd) + " " + key + "=" + valueText(value) + text.slice(nd.headEnd);
  }

  // As propriedades de cada componente (themes/README.md), para os ajustes da página.
  var COMPONENTS = {
    "guild-bar": [["variant", ["bar", "dock", "list"]], ["icon-style", ["fill", "soft", "outline"]], ["orientation", ["vertical", "horizontal"]],
      ["shape", ["circle", "squircle", "square", "text"]], ["size", "num"], ["labels", "bool"], ["home", "bool"], ["indicators", "bool"]],
    "channel-list": [["variant", ["discord", "tree", "pills"]], ["header", "bool"], ["banner", "bool"]],
    "user-panel": [["variant", ["discord", "tty"]]],
    header: [["variant", ["discord", "minimal", "tty"]], ["divider", "bool"]],
    tabs: [["variant", ["pills", "underline", "tty"]]],
    messages: [["variant", ["cozy", "irc", "bubbles"]], ["avatar", ["circle", "squircle", "square", "none"]], ["avatar-size", "num"],
      ["spacing", "num"], ["font-size", "num"], ["ruled", "bool"], ["margin-line", "bool"], ["ticks", "bool"], ["typing-bubble", "bool"]],
    composer: [["variant", ["box", "pill", "prompt"]], ["typing", "bool"]],
    "member-list": [["variant", ["discord", "tty"]]],
    "status-bar": [["variant", ["pills", "tty", "plain"]], ["items", "text"]],
    // Fundos procedurais e enfeites (src/ui/backdrop.zig e comp_extra.zig leem estas).
    starfield: [["density", "num"], ["seed", "num"], ["motion", "bool"]],
    orbit: [["center-x", "num"], ["center-y", "num"], ["rings", "num"], ["seed", "num"], ["motion", "bool"]],
    radar: [["center-x", "num"], ["center-y", "num"], ["rings", "num"], ["seed", "num"], ["motion", "bool"]],
    topography: [["levels", "num"], ["seed", "num"]],
    aurora: [["seed", "num"], ["motion", "bool"]],
    dunes: [["seed", "num"], ["motion", "bool"]],
    crt: [["spacing", "num"], ["strength", "num"]],
    logo: [["variant", ["wordmark", "ascii"]], ["size", "num"]],
    "window-controls": [["size", "num"], ["gap", "num"], ["align", ["left", "center", "right"]]],
  };
  var CONTAINERS = ["row", "column", "stack"];
  // A faixa dos controles deslizantes de cada número: [mínimo, máximo, passo]. É só a régua da
  // página; o campo ao lado aceita qualquer valor que o app aceita (ele mesmo limita alguns).
  var RANGES = {
    size: [16, 80, 1], "avatar-size": [16, 72, 1], spacing: [0, 48, 1], "font-size": [10, 24, 0.5],
    width: [40, 520, 1], height: [16, 240, 1], gap: [0, 40, 1], padding: [0, 64, 1],
    density: [0.1, 6, 0.1], "center-x": [-1, 2, 0.01], "center-y": [-1, 2, 0.01], rings: [1, 12, 1],
    levels: [4, 40, 1], seed: [1, 999, 1], strength: [0, 0.4, 0.01],
    "crt.spacing": [1, 10, 1], "logo.size": [8, 40, 1], "window-controls.size": [6, 24, 1], "window-controls.gap": [2, 24, 1],
  };
  function range(comp, key) { return own(RANGES, comp + "." + key) ? RANGES[comp + "." + key] : own(RANGES, key) ? RANGES[key] : [0, 400, 1]; }

  function listTweaks(structure) {
    var nodes = parseKdl(structure), out = [];
    function walk(nd, depth, parent) {
      var spec = COMPONENTS[nd.name], fields = [];
      if (parent && parent.name !== "stack" && CONTAINERS.indexOf(parent.name) >= 0) {
        var axis = parent.name === "row" ? "width" : "height";
        if (prop(nd, axis) && typeof pv(nd, axis) === "number") fields.push({ key: axis, kind: "num", value: pv(nd, axis) });
      }
      if (spec) spec.forEach(function (f) { fields.push({ key: f[0], kind: Array.isArray(f[1]) ? "enum" : f[1], options: Array.isArray(f[1]) ? f[1] : null, value: pv(nd, f[0]) }); });
      if (CONTAINERS.indexOf(nd.name) >= 0) ["gap", "padding"].forEach(function (k) { if (typeof pv(nd, k) === "number") fields.push({ key: k, kind: "num", value: pv(nd, k) }); });
      // Componentes com as propriedades deles, e contêineres com tamanho fixo (as colunas).
      // Rótulos, réguas e espaços ficam para o editor de texto: só fariam barulho aqui.
      if (fields.length && (spec || CONTAINERS.indexOf(nd.name) >= 0)) {
        out.push({ start: nd.start, name: nd.name, line: nd.line, depth: depth, when: str(nd, "when"), unless: str(nd, "unless"), component: !!spec, fields: fields });
      }
      nd.kids.forEach(function (k) { if (nd.name !== "label") walk(k, depth + 1, nd); });
    }
    nodes.forEach(function (top) { if (top.name === "layout") top.kids.forEach(function (k) { walk(k, 0, top); }); });
    return out;
  }

  function structureOptions(structure) {
    try { return optionList(parseKdl(structure)); } catch (e) { return []; }
  }

  // A árvore do layout como camadas (o painel Layout da página): cada nó com o pai, a posição
  // entre os irmãos, se aparece (`show`) e os campos que a página sabe editar.
  function outline(structure) {
    var nodes = parseKdl(structure), out = [];
    function walk(nd, depth, parent) {
      var spec = COMPONENTS[nd.name], fields = [], box = CONTAINERS.indexOf(nd.name) >= 0;
      if (parent && parent.name !== "stack" && CONTAINERS.indexOf(parent.name) >= 0) {
        var axis = parent.name === "row" ? "width" : "height";
        if (typeof pv(nd, axis) === "number") fields.push({ key: axis, kind: "num", value: pv(nd, axis), range: range(nd.name, axis) });
      }
      if (spec) spec.forEach(function (f) {
        var en = Array.isArray(f[1]);
        fields.push({ key: f[0], kind: en ? "enum" : f[1], options: en ? f[1] : null, value: pv(nd, f[0]), range: f[1] === "num" ? range(nd.name, f[0]) : null });
      });
      if (box) ["gap", "padding"].forEach(function (k) { if (typeof pv(nd, k) === "number") fields.push({ key: k, kind: "num", value: pv(nd, k), range: range(nd.name, k) }); });
      var sibs = parent ? parent.kids : [];
      out.push({ start: nd.start, name: nd.name, line: nd.line, depth: depth, parent: parent && parent.name !== "layout" ? parent.start : null,
        index: sibs.indexOf(nd), count: sibs.length, show: flag(nd, "show"), when: str(nd, "when"), unless: str(nd, "unless"),
        container: box, component: !!spec, variant: str(nd, "variant"), fields: fields });
      if (nd.name !== "label") nd.kids.forEach(function (k) { walk(k, depth + 1, nd); });
    }
    nodes.forEach(function (top) { if (top.name === "layout") top.kids.forEach(function (k) { walk(k, 0, top); }); });
    return out;
  }

  // Troca um nó de lugar com o irmão de antes (dir -1) ou de depois (+1): a ordem no arquivo é a
  // ordem na tela (e, num `stack`, a ordem de desenho). Só os dois pedaços de texto mudam.
  function findParent(nodes, start) {
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].start === start) return { list: nodes, at: i };
      var f = findParent(nodes[i].kids, start);
      if (f) return f;
    }
    return null;
  }
  function moveNode(text, start, dir) {
    var nodes = parseKdl(text), f = findParent(nodes, start);
    if (!f) return text;
    var j = f.at + (dir < 0 ? -1 : 1);
    if (j < 0 || j >= f.list.length) return text;
    var a = f.list[Math.min(f.at, j)], b = f.list[Math.max(f.at, j)];
    if (a.name === "layout" || b.name === "layout") return text;
    var ta = text.slice(a.start, a.end), tb = text.slice(b.start, b.end);
    return text.slice(0, a.start) + tb + text.slice(a.end, b.start) + ta + text.slice(b.end);
  }

  // ------------------------------------------- Cores que vêm do layout ----
  // Blocos `colors`, `palette` e `roles` que ficaram no texto do layout (os que dependem
  // de uma opção, como `colors mode=dark when=verde`). Os que valem neste modo, com as
  // opções no padrão, trocam por cima o que a aba Cores edita.
  function layoutColorBlocks(state, mode) {
    var nodes, opts;
    try {
      nodes = parseKdl(String(state.structure || ""));
      opts = optionList(nodes);
    } catch (e) { return []; }
    var values = Object.create(null);
    opts.forEach(function (o) { values[o.name] = o.def; });
    values["modo-claro"] = mode === "light";
    values["modo-escuro"] = mode === "dark";
    var out = [];
    nodes.forEach(function (nd) {
      if (ABSORB_MODED.indexOf(nd.name) < 0 || !applies(nd, mode, values)) return;
      out.push({ kind: nd.name, line: nd.line, when: str(nd, "when"), unless: str(nd, "unless"),
        tokens: nd.name === "colors" ? nd.kids.map(function (k) { return tokenName(k.name); }).filter(Boolean) : [] });
    });
    return out;
  }
  // Os tokens como o app vai usar: os da aba Cores, menos os que um bloco do layout troca.
  function effectiveColors(state, mode) {
    var toks = {}, gated = {};
    TOKENS.forEach(function (t) { toks[t] = hexRgba(state.colors[mode][t]); });
    layoutColorBlocks(state, mode).forEach(function (b) { b.tokens.forEach(function (t) { gated[t] = b; }); });
    if (Object.keys(gated).length) {
      try {
        var th = loadTheme(toKdl(state), { mode: mode });
        Object.keys(gated).forEach(function (t) { toks[t] = th.authored[t]; });
      } catch (e) {}
    }
    return { toks: toks, gated: gated };
  }

  // ----------------------------------------------------------- Contraste ----
  // O conserto de um clique: a primeira cor no caminho até o texto que passa depois de
  // virar hex de 8 bits (é o que o arquivo guarda). Sem isso, 5,4907:1 contra 5,5:1 fica marcado.
  function legibleFix(toks, tok, min) {
    function ok(c) {
      for (var j = 0; j < BACKS.length; j++) if (contrast(c, toks[BACKS[j]]) < min) return false;
      return true;
    }
    for (var k = 0; k <= 1; k = Math.fround(k + Math.fround(0.05))) {
      var hx = toHex(mix(toks[tok], toks.text, k));
      if (ok(hexRgba(hx))) return { value: hx, ok: true };
    }
    var t = toHex(toks.text);
    return { value: t, ok: ok(hexRgba(t)) };
  }

  function contrastReport(state, mode) {
    var eff = effectiveColors(state, mode), toks = eff.toks;
    function gate(tok) { return own(eff.gated, tok) ? eff.gated[tok] : null; }
    var rows = [];
    LEGIBLE.forEach(function (w) {
      var worst = 99, fails = [];
      BACKS.forEach(function (b) {
        var r = contrast(toks[w.tok], toks[b]);
        if (r < worst) worst = r;
        if (r < w.min) fails.push(b);
      });
      var g = gate(w.tok);
      var row = { id: w.tok, fg: w.tok, backs: BACKS.slice(), min: w.min, ratio: worst, fails: fails, app: true, gated: g, fix: null, lift: null, stuck: false };
      if (fails.length) {
        // O que o app faz ao carregar, e o valor que deixa o aviso limpo.
        row.lift = toHex(legibleFor(toks, w.tok, w.min));
        var f = legibleFix(toks, w.tok, w.min);
        if (!f.ok) row.stuck = true;
        else if (!g) row.fix = { tok: w.tok, value: f.value };
      }
      rows.push(row);
    });
    // O resto não é regra do app: é o mínimo da WCAG para texto (AA), medido como a cor
    // aparece: a translúcida por cima do fundo (e o fundo translúcido por cima do preto ou branco).
    var ground = over(toks.bg, mode === "light" ? WHITE : BLACK);
    function seen(fg, back) {
      var b = back === "bg" ? ground : over(toks[back], ground);
      return [over(toks[fg], b), b];
    }
    function pair(fg, backs, min, fixer) {
      var worst = 99, fails = [];
      backs.forEach(function (b) {
        var s = seen(fg, b), r = contrast(s[0], s[1]);
        if (r < worst) worst = r;
        if (r < min) fails.push(b);
      });
      var g = gate(fg);
      rows.push({ id: fg, fg: fg, backs: backs, min: min, ratio: worst, fails: fails, app: false, gated: g, fix: fails.length && !g ? fixer() : null, lift: null, stuck: false });
    }
    function towards(tok, backs, min) {
      var base = toks[tok], avg = backs.reduce(function (a, b) { return a + luminance(seen(tok, b)[1]); }, 0) / backs.length;
      var target = avg > 0.18 ? BLACK : WHITE;
      for (var k = 0.05; k <= 1.0001; k += 0.05) {
        // Conferido já em hex, como vai para o arquivo.
        var hx = toHex(mix(base, target, k)), col = hexRgba(hx);
        if (backs.every(function (b) { var s = seen(tok, b); return contrast(over(col, s[1]), s[1]) >= min; })) return { tok: tok, value: hx };
      }
      return { tok: tok, value: toHex(target) };
    }
    function blackOrWhite(tok, back) {
      var b = seen(tok, back)[1];
      return { tok: tok, value: contrast(BLACK, b) >= contrast(WHITE, b) ? "#000000" : "#ffffff" };
    }
    pair("text", BACKS, 4.5, function () { return towards("text", BACKS, 4.5); });
    pair("accent-text", ["accent"], 4.5, function () { return blackOrWhite("accent-text", "accent"); });
    pair("bubble-self-text", ["bubble-self"], 4.5, function () { return blackOrWhite("bubble-self-text", "bubble-self"); });
    pair("link", ["bg", "surface"], 4.5, function () { return towards("link", ["bg", "surface"], 4.5); });
    return rows;
  }

  // ------------------------------------------------------ OKLCH e geração ----
  function lin(x) { return x <= 0.04045 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4); }
  function gam(x) { return x <= 0.0031308 ? 12.92 * x : 1.055 * Math.pow(x, 1 / 2.4) - 0.055; }
  function toOklab(c) {
    var r = lin(c[0]), g = lin(c[1]), b = lin(c[2]);
    var l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    var m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    var s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return [0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s, 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s, 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s];
  }
  function fromOklab(L, a, b) {
    var l = Math.pow(L + 0.3963377774 * a + 0.2158037573 * b, 3);
    var m = Math.pow(L - 0.1055613458 * a - 0.0638541728 * b, 3);
    var s = Math.pow(L - 0.0894841775 * a - 1.291485548 * b, 3);
    return [gam(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s), gam(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s), gam(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s)];
  }
  function toOklch(c) {
    var lab = toOklab(c), C = Math.sqrt(lab[1] * lab[1] + lab[2] * lab[2]);
    var h = Math.atan2(lab[2], lab[1]) * 180 / Math.PI;
    return [lab[0], C, h < 0 ? h + 360 : h];
  }
  function inGamut(rgb) { return rgb.every(function (x) { return x >= -0.0005 && x <= 1.0005; }); }
  // Cor OKLCH dentro do sRGB: diminui o croma até caber.
  function oklch(L, C, h) {
    L = clamp01(L);
    var hr = h * Math.PI / 180, lo = 0, hi = C, rgb = fromOklab(L, C * Math.cos(hr), C * Math.sin(hr));
    if (!inGamut(rgb)) {
      for (var k = 0; k < 18; k++) {
        var mid = (lo + hi) / 2, t = fromOklab(L, mid * Math.cos(hr), mid * Math.sin(hr));
        if (inGamut(t)) lo = mid; else hi = mid;
      }
      rgb = fromOklab(L, lo * Math.cos(hr), lo * Math.sin(hr));
    }
    return [clamp01(rgb[0]), clamp01(rgb[1]), clamp01(rgb[2]), 1];
  }

  function rng(seed) {
    var a = seed >>> 0 || 1;
    return function () {
      a = (a + 0x6d2b79f5) >>> 0;
      var t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  var SCHEMES = {
    analogous: [38, -38], complementary: [180, 205], split: [150, 210], triadic: [120, 240], mono: [14, -18],
  };

  // Uma paleta inteira (os dois modos) a partir de poucas sementes. Tudo em OKLCH,
  // com o texto secundário já acima do mínimo do app.
  function generate(seed) {
    var H = seed.hue, A = seed.accentHue, S = seed.secondHue, Lk = seed.linkHue, cn = seed.neutral, ca = seed.accentChroma;
    function on(c, back) { return contrast(WHITE, c) >= contrast(back, c) ? WHITE : back; }
    function build(mode) {
      var t = {}, d = mode === "dark";
      var n = function (L, k) { return oklch(L, cn * (k || 1), H); };
      if (d) {
        t.bg = n(0.19); t.rail = n(0.145); t.sidebar = n(0.168); t.surface = n(0.205); t.elevated = n(0.255, 1.2);
        t.overlay = n(0.178); t["code-bg"] = n(0.155); t.text = oklch(0.94, Math.min(cn, 0.012), H);
        t.muted = n(0.75, 1.5); t.faint = n(0.62, 1.5); t.border = n(0.3, 1.3);
        t.accent = oklch(seed.accentL || 0.74, ca, A); t.mention = oklch(0.79, ca * 0.85, S); t.link = oklch(0.8, Math.min(ca, 0.12), Lk);
        t.online = oklch(0.76, 0.15, 150); t.idle = oklch(0.81, 0.14, 80); t.dnd = oklch(0.68, 0.18, 22); t.danger = t.dnd;
        t["bubble-other"] = n(0.27); t.shadow = alpha(BLACK, 0.45);
        t["accent-text"] = on(t.accent, t.rail);
      } else {
        t.bg = n(0.972, 0.5); t.rail = n(0.932, 0.8); t.sidebar = n(0.952, 0.7); t.surface = n(0.988, 0.3); t.elevated = oklch(1, 0, H);
        t.overlay = WHITE; t["code-bg"] = n(0.94); t.text = n(0.24, 1.2);
        t.muted = n(0.46, 1.5); t.faint = n(0.56, 1.5); t.border = n(0.885, 1.2);
        t.accent = oklch(0.53, Math.max(ca, 0.1), A); t.mention = oklch(0.51, ca * 0.9, S); t.link = oklch(0.48, Math.min(Math.max(ca, 0.09), 0.14), Lk);
        t.online = oklch(0.56, 0.15, 150); t.idle = oklch(0.6, 0.14, 70); t.dnd = oklch(0.55, 0.19, 25); t.danger = t.dnd;
        t["bubble-other"] = n(0.935); t.shadow = alpha(BLACK, 0.12);
        t["accent-text"] = on(t.accent, t.text);
      }
      t.hover = alpha(t.text, 0.05);
      t.selected = alpha(t.accent, d ? 0.16 : 0.12);
      t["bubble-self"] = t.accent;
      t["bubble-self-text"] = t["accent-text"];
      legibleText(t);
      var o = {};
      TOKENS.forEach(function (k) { o[k] = toHex(t[k]); });
      var roles = [A, S, Lk, A + 90, S + 60, 150, 25, 80].map(function (h, i) {
        return toHex(d ? oklch(0.79, 0.12 + (i % 2) * 0.02, h) : oklch(0.5, 0.13, h));
      });
      return { colors: o, roles: roles, toks: t };
    }
    var dk = build("dark"), lt = build("light");
    var pal = [dk.toks.bg, oklch(0.66, 0.17, 25), oklch(0.72, 0.15, 145), oklch(0.82, 0.14, 90), dk.toks.accent, dk.toks.mention, dk.toks.link,
      dk.toks.muted, dk.toks.faint, oklch(0.76, 0.14, 25), oklch(0.82, 0.13, 145), oklch(0.89, 0.11, 90),
      oklch(0.84, ca * 0.8, A), oklch(0.86, ca * 0.7, S), oklch(0.88, 0.08, Lk), dk.toks.text].map(toHex);
    return { palette: { dark: pal, light: pal.slice() }, colors: { dark: dk.colors, light: lt.colors }, roles: { dark: dk.roles, light: lt.roles } };
  }

  function randomSeed(seed) {
    var r = rng(seed), names = Object.keys(SCHEMES), scheme = names[Math.floor(r() * names.length)], off = SCHEMES[scheme];
    var A = r() * 360, hueOfBg = r() < 0.6 ? A : (A + 180 + (r() - 0.5) * 40) % 360;
    return {
      scheme: scheme, hue: hueOfBg, accentHue: A, secondHue: (A + off[0] + 360) % 360, linkHue: (A + off[1] + 360) % 360,
      neutral: 0.006 + r() * 0.03, accentChroma: 0.11 + r() * 0.08, accentL: 0.7 + r() * 0.1,
    };
  }

  // Cores de uma imagem: k-means em OKLab sobre os pixels (RGBA, 0–255).
  function imageColors(data, k, seed) {
    k = k || 8;
    var pts = [], r = rng(seed || 7);
    for (var i = 0; i < data.length; i += 4) {
      if (data[i + 3] < 128) continue;
      pts.push(toOklab([data[i] / 255, data[i + 1] / 255, data[i + 2] / 255]));
    }
    if (!pts.length) return [];
    var cents = [pts[Math.floor(r() * pts.length)]];
    while (cents.length < Math.min(k, pts.length)) {
      // k-means++: o próximo centro tende a ficar longe dos que já existem.
      var dist = pts.map(function (p) {
        return cents.reduce(function (m, c) { var d = (p[0] - c[0]) * (p[0] - c[0]) + (p[1] - c[1]) * (p[1] - c[1]) + (p[2] - c[2]) * (p[2] - c[2]); return Math.min(m, d); }, 9);
      });
      var total = dist.reduce(function (a, b) { return a + b; }, 0), pick = r() * total, idx = 0;
      while (idx < dist.length - 1 && (pick -= dist[idx]) > 0) idx++;
      cents.push(pts[idx]);
    }
    var assign = new Array(pts.length);
    for (var it = 0; it < 12; it++) {
      var sums = cents.map(function () { return [0, 0, 0, 0]; });
      pts.forEach(function (p, pi) {
        var best = 0, bd = 9;
        cents.forEach(function (c, ci) {
          var d = (p[0] - c[0]) * (p[0] - c[0]) + (p[1] - c[1]) * (p[1] - c[1]) + (p[2] - c[2]) * (p[2] - c[2]);
          if (d < bd) { bd = d; best = ci; }
        });
        assign[pi] = best;
        var s = sums[best];
        s[0] += p[0]; s[1] += p[1]; s[2] += p[2]; s[3]++;
      });
      cents = cents.map(function (c, ci) { var s = sums[ci]; return s[3] ? [s[0] / s[3], s[1] / s[3], s[2] / s[3]] : c; });
    }
    var counts = cents.map(function () { return 0; });
    assign.forEach(function (a) { counts[a]++; });
    return cents.map(function (c, i) {
      var rgb = fromOklab(c[0], c[1], c[2]).map(clamp01), C = Math.sqrt(c[1] * c[1] + c[2] * c[2]);
      var h = Math.atan2(c[2], c[1]) * 180 / Math.PI;
      return { hex: toHex([rgb[0], rgb[1], rgb[2], 1]), weight: counts[i] / pts.length, L: c[0], C: C, h: h < 0 ? h + 360 : h };
    }).filter(function (x) { return x.weight > 0; }).sort(function (a, b) { return b.weight - a.weight; });
  }

  function hueDist(a, b) { var d = Math.abs(a - b) % 360; return d > 180 ? 360 - d : d; }

  function seedFromImage(colors) {
    if (!colors.length) return randomSeed(1);
    var dom = colors[0];
    var score = function (c) { return c.C * (0.45 + Math.sqrt(c.weight)) * (c.L > 0.3 && c.L < 0.92 ? 1 : 0.35); };
    var ranked = colors.slice().sort(function (a, b) { return score(b) - score(a); });
    var acc = ranked[0], grey = acc.C < 0.035;
    var A = grey ? dom.h : acc.h;
    var second = ranked.filter(function (c) { return c !== acc && c.C > 0.03 && hueDist(c.h, A) > 35; })[0];
    var S = second ? second.h : (A + 150) % 360;
    var third = ranked.filter(function (c) { return c !== acc && c !== second && c.C > 0.03 && hueDist(c.h, A) > 25 && hueDist(c.h, S) > 25; })[0];
    var mid = (A + S) / 2;
    if (Math.abs(A - S) > 180) mid = (mid + 180) % 360;
    return {
      scheme: "image", hue: dom.h, accentHue: A, secondHue: S, linkHue: third ? third.h : mid,
      neutral: Math.max(0.006, Math.min(0.04, dom.C * 0.35)), accentChroma: grey ? 0.1 : Math.max(0.1, Math.min(0.19, acc.C)),
      accentL: grey ? 0.74 : Math.max(0.68, Math.min(0.82, acc.L)),
    };
  }

  // Sementes de um modo já pronto, para montar o outro modo parecido.
  function seedFromColors(colors) {
    var bg = toOklch(hexRgba(colors.bg)), ac = toOklch(hexRgba(colors.accent)), me = toOklch(hexRgba(colors.mention)), li = toOklch(hexRgba(colors.link));
    var A = ac[1] < 0.02 ? bg[2] : ac[2];
    return {
      scheme: "derived", hue: bg[1] < 0.004 ? A : bg[2], accentHue: A, secondHue: me[1] < 0.03 ? (A + 150) % 360 : me[2],
      linkHue: li[1] < 0.03 ? (A + 210) % 360 : li[2], neutral: Math.max(0.004, Math.min(0.045, bg[1])),
      accentChroma: Math.max(0.08, Math.min(0.2, ac[1])), accentL: Math.max(0.66, Math.min(0.84, ac[0])),
    };
  }

  // Tokens do modo a partir da paleta, do jeito que o app faz quando o tema não diz nada.
  function fromPalette(pal, mode) {
    var p = pal.map(hexRgba), t = defaults(p, mode), o = {};
    TOKENS.forEach(function (k) { o[k] = toHex(t[k]); });
    return { colors: o, roles: defaultRoles(p, mode).map(toHex) };
  }

  // ------------------------------------------------ Gerador de paletas ----
  // Harmonias a partir de uma cor base: o destaque fica na base, a menção e o link nas cores
  // que a harmonia pede (graus no círculo do OKLCH). `generate` faz o resto, nos dois modos.
  var HARMONY = { mono: [0, 0], analogous: [32, -32], complementary: [180, 205], split: [150, 210], triadic: [120, 240] };
  function clampTo(v, lo, hi, d) { return typeof v === "number" && isFinite(v) ? Math.min(hi, Math.max(lo, v)) : d; }
  function seedFromBase(hex, scheme, opt) {
    opt = opt || {};
    var c = toOklch(hexRgba(hex)), off = own(HARMONY, scheme) ? HARMONY[scheme] : HARMONY.analogous, A = c[2], grey = c[1] < 0.03;
    return {
      scheme: own(HARMONY, scheme) ? scheme : "analogous", hue: A, accentHue: A,
      secondHue: (A + off[0] + 360) % 360, linkHue: (A + off[1] + 360) % 360,
      neutral: clampTo(opt.neutral, 0, 0.06, grey ? 0.004 : 0.016),
      accentChroma: clampTo(opt.chroma, 0, 0.24, grey ? 0.02 : Math.max(0.06, Math.min(0.22, c[1]))),
      accentL: clampTo(opt.lightness, 0.55, 0.9, Math.max(0.62, Math.min(0.86, c[0]))),
    };
  }
  // A cor que mais contrasta (preto ou branco) para texto em cima de `back`.
  function onColor(back) { var b = hexRgba(back); return contrast(BLACK, b) >= contrast(WHITE, b) ? "#000000" : "#ffffff"; }
  var ON_PAIRS = [["accent-text", "accent"], ["bubble-self-text", "bubble-self"]];
  // Põe uma paleta gerada no estado, sem mexer nos tokens travados (`locks`: { token: true }).
  // O texto em cima de um preenchimento travado segue o preenchimento, e muted/faint ficam na regra do app.
  function applyGenerated(state, gen, locks) {
    locks = locks || {};
    var next = clone(state);
    ["dark", "light"].forEach(function (mode) {
      var old = state.colors[mode], out = {};
      TOKENS.forEach(function (t) { out[t] = own(locks, t) && locks[t] ? old[t] : gen.colors[mode][t]; });
      ON_PAIRS.forEach(function (p) { if (locks[p[1]] && !locks[p[0]]) out[p[0]] = onColor(out[p[1]]); });
      if (locks.accent && !locks.selected) out.selected = toHex(alpha(hexRgba(out.accent), mode === "dark" ? 0.16 : 0.12));
      if (locks.accent && !locks["bubble-self"]) { out["bubble-self"] = out.accent; if (!locks["bubble-self-text"]) out["bubble-self-text"] = onColor(out.accent); }
      var toks = {};
      TOKENS.forEach(function (t) { toks[t] = hexRgba(out[t]); });
      LEGIBLE.forEach(function (w) {
        if (locks[w.tok]) return;
        var f = legibleFix(toks, w.tok, w.min);
        out[w.tok] = f.value;
        toks[w.tok] = hexRgba(f.value);
      });
      next.colors[mode] = out;
      next.roles[mode] = gen.roles[mode].slice();
    });
    next.palette = { dark: gen.palette.dark.slice(), light: gen.palette.light.slice() };
    return next;
  }

  // ------------------------------------------- Do escuro para o claro ----
  // Um ponto de partida para o outro modo: a luminosidade (L do OKLCH) é espelhada por uma
  // curva que leva os fundos escuros para papel claro e o texto claro para tinta escura,
  // com o matiz e o croma de cada cor. Os preenchimentos de cor (destaque, status, balões)
  // ficam numa faixa em que continuam coloridos. Depois, os consertos de contraste de sempre.
  var FLIP = [[0, 1], [0.12, 0.995], [0.22, 0.975], [0.32, 0.93], [0.45, 0.78], [0.62, 0.55], [0.78, 0.38], [0.95, 0.22], [1, 0.16]];
  var FILLS = ["accent", "mention", "online", "idle", "dnd", "danger", "bubble-self"];
  // Fundos que já estão do lado certo (a barra escura de um tema claro, como a do escritorio)
  // ficam onde estão: virar papel claro deixaria o texto claro de cima ilegível.
  var GROUNDS = ["bg", "rail", "sidebar", "surface", "elevated", "overlay", "code-bg", "bubble-other"];
  function flipL(L, toLight) {
    var pts = toLight ? FLIP : FLIP.map(function (p) { return [p[1], p[0]]; }).reverse();
    L = clamp01(L);
    for (var i = 1; i < pts.length; i++) {
      if (L <= pts[i][0]) {
        var a = pts[i - 1], b = pts[i], k = b[0] === a[0] ? 0 : (L - a[0]) / (b[0] - a[0]);
        return a[1] + (b[1] - a[1]) * k;
      }
    }
    return pts[pts.length - 1][1];
  }
  function flipColor(hex, toLight, fill, ground) {
    var c = hexRgba(hex), lch = toOklch(c), L = flipL(lch[0], toLight);
    if (ground && (toLight ? lch[0] > 0.62 : lch[0] < 0.45)) L = lch[0];
    if (fill && lch[1] > 0.04) L = toLight ? Math.min(0.62, Math.max(0.42, L)) : Math.min(0.86, Math.max(0.64, L));
    var out = oklch(L, lch[1], lch[2]);
    out[3] = c[3];
    return toHex(out);
  }
  function invertMode(state, from) {
    var to = from === "light" ? "dark" : "light", toLight = to === "light", next = clone(state), src = state.colors[from === "light" ? "light" : "dark"], out = {};
    TOKENS.forEach(function (t) {
      if (t === "shadow") {
        var a = hexRgba(src.shadow)[3];
        out.shadow = toHex(alpha(BLACK, toLight ? Math.min(a, 0.14) : Math.max(a, 0.35)));
        return;
      }
      out[t] = flipColor(src[t], toLight, FILLS.indexOf(t) >= 0, GROUNDS.indexOf(t) >= 0);
    });
    ON_PAIRS.forEach(function (p) { out[p[0]] = onColor(out[p[1]]); });
    next.colors[to] = out;
    next.roles[to] = state.roles[from === "light" ? "light" : "dark"].map(function (r) { return flipColor(r, toLight, true); });
    next.palette[to] = state.palette[from === "light" ? "light" : "dark"].slice();
    // O texto, o muted/faint e o link passam a ler: o mesmo "Consertar tudo" do painel de contraste.
    for (var round = 0; round < 4; round++) {
      var fixes = contrastReport(next, to).filter(function (r) { return r.fails.length && r.fix; });
      if (!fixes.length) break;
      fixes.forEach(function (r) { next.colors[to][r.fix.tok] = r.fix.value; });
    }
    return next;
  }

  // ------------------------------------------------ Galeria da comunidade ----
  // O que um tema precisa para entrar em themes/community/. São as mesmas regras de
  // `check_community` em tools/gen_site.py (o build do site recusa o que falhar).
  var COMMUNITY = { name: 48, author: 80, desc: 240, license: 64 }, COMMUNITY_MAX = 64 * 1024;
  // As licenças abertas que a galeria aceita (identificadores SPDX), a mesma lista de `LICENSES`
  // em tools/gen_site.py. Sozinhas ou juntas com AND / OR: "CC0-1.0", "GPL-3.0-or-later OR MIT".
  var LICENSES = ["CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0", "CC-BY-3.0", "CC-BY-SA-3.0", "MIT", "MIT-0", "ISC", "0BSD",
    "BSD-2-Clause", "BSD-3-Clause", "Apache-2.0", "MPL-2.0", "Zlib", "Unlicense", "WTFPL", "EUPL-1.2",
    "GPL-2.0-only", "GPL-2.0-or-later", "GPL-3.0-only", "GPL-3.0-or-later", "LGPL-2.1-only", "LGPL-2.1-or-later",
    "LGPL-3.0-only", "LGPL-3.0-or-later", "AGPL-3.0-only", "AGPL-3.0-or-later"];
  function licenseOk(s) {
    s = String(s || "");
    if (s.length > COMMUNITY.license) return false;
    var parts = s.split(" ");
    if (parts.length % 2 === 0 || parts.length > 9) return false;
    return parts.every(function (p, i) { return i % 2 ? p === "AND" || p === "OR" : LICENSES.indexOf(p) >= 0; });
  }
  function plainText(s, max) { s = String(s || ""); return s.trim().length > 0 && s.length <= max && !/[\u0000-\u001f\u007f]/.test(s); }
  // `descs`: as descrições dos temas embutidos (um tema que parte de um deles começa com a dele).
  function communityCheck(state, builtins, descs) {
    var m = state.meta, file = slug(m.name), desc = m.descEn || m.desc;
    var copied = (descs || []).some(function (d) { return !!d && (d === m.desc || d === m.descEn); });
    return [
      { id: "name", ok: plainText(m.name, COMMUNITY.name) && (builtins || []).indexOf(file) < 0, file: file, builtin: (builtins || []).indexOf(file) >= 0 },
      { id: "author", ok: plainText(m.author, COMMUNITY.author) },
      { id: "description", ok: plainText(desc, COMMUNITY.desc) && (!m.desc || m.desc.length <= COMMUNITY.desc) && (!m.descEn || m.descEn.length <= COMMUNITY.desc) && !copied, copied: copied },
      { id: "license", ok: licenseOk(m.license) },
    ];
  }

  // ------------------------------------------- Cores de um tema do Discord ----
  // Lê um tema do BetterDiscord ou do Vencord (CSS) e tira só as variáveis com cor.
  // Nada do CSS roda nem entra na página: é um leitor de texto, limitado em tamanho
  // e em tempo, que devolve cores já convertidas em hex. @import vira só uma lista.
  var CSS_MAX = 500 * 1024, CSS_BUDGET = 1500, CSS_DECLS = 60000, CSS_VALUE = 2000, CSS_DEPTH = 32;
  var VAR_DEPTH = 8, VAR_OUT = 1200, VAR_STEPS = 20000;

  function cssError(code) { var e = new Error(MSG.en[code]); e.code = code; return e; }

  function stripComments(s) {
    var out = "", i = 0;
    for (;;) {
      var k = s.indexOf("/*", i);
      if (k < 0) return out + s.slice(i);
      out += s.slice(i, k) + " ";
      var e = s.indexOf("*/", k + 2);
      if (e < 0) return out;
      i = e + 2;
    }
  }

  // Seletor de "raiz": :root, html, body, #app-mount e as classes de tema do Discord.
  // Um pedaço por vez, sem expressão regular que possa voltar atrás muitas vezes.
  // Um `:not(…)` simples não tira a raiz (`.theme-dark:not(.custom-user-profile-theme)`), e o
  // que está dentro dele não conta para o modo.
  var ROOT_PART = /^(?:html|body|\*|:root|&|#app-mount)?(?:\.theme-[a-z0-9-]+|\.visual-refresh|:not\([^()\s]*\))*$/;
  function selectorInfo(sel, env) {
    var s = stripComments(sel).toLowerCase().trim();
    if (s.length > 4000) return { mode: env.mode, root: false };
    var plain = s.replace(/:not\([^()]*\)/g, "");
    var light = plain.indexOf("theme-light") >= 0;
    var dark = plain.indexOf("theme-dark") >= 0 || plain.indexOf("theme-midnight") >= 0;
    var mode = light && !dark ? "light" : dark && !light ? "dark" : env.mode;
    var root = s.length > 0 && s.split(",").every(function (part) {
      var bits = part.split(/[\s>+~]+/).filter(Boolean);
      return bits.length > 0 && bits.every(function (b) { return ROOT_PART.test(b); });
    });
    return { mode: mode, root: env.root && root };
  }

  function mediaMode(prelude) {
    var p = stripComments(prelude).toLowerCase().replace(/\s+/g, "");
    if (p.indexOf("prefers-color-scheme:light") >= 0) return "light";
    if (p.indexOf("prefers-color-scheme:dark") >= 0) return "dark";
    return null;
  }

  // O endereço de um @import, só para mostrar na lista. Lido à mão com indexOf (uma expressão
  // regular com `\s*` dos dois lados de `[^)]*` volta atrás em tempo cúbico num `url(` sem fim)
  // e só nos primeiros 2 KB: o resto de um prelúdio enorme não muda o que aparece.
  function cleanUrl(prelude) {
    var p = stripComments(prelude.slice(0, 2048)).trim(), u = p, q, e;
    if (p.slice(0, 4).toLowerCase() === "url(") {
      p = p.slice(4).trim();
      q = p[0];
      if (q === '"' || q === "'") { e = p.indexOf(q, 1); u = p.slice(1, e < 0 ? p.length : e); }
      else { e = p.indexOf(")"); u = e < 0 ? p : p.slice(0, e); }
    } else if (p[0] === '"' || p[0] === "'") {
      e = p.indexOf(p[0], 1);
      u = p.slice(1, e < 0 ? p.length : e);
    }
    u = u.replace(/[\u0000-\u001f\u007f]/g, "").trim();
    return u.length > 200 ? u.slice(0, 199) + "…" : u;
  }

  // As declarações `--nome: valor` de cada bloco, com o modo (claro, escuro ou os dois)
  // e se o seletor é de raiz. Tolerante: CSS quebrado vira avisos, não erro.
  function parseCss(text, opt) {
    opt = opt || {};
    text = String(text);
    if (text.length > CSS_MAX) throw cssError("css-too-big");
    var now = opt.now || Date.now, budget = opt.budget || CSS_BUDGET, start = now(), ticks = 0;
    var n = text.length, i = 0;
    var out = { decls: [], imports: [], rules: 0, notes: Object.create(null) };
    function note(k) { out.notes[k] = (out.notes[k] || 0) + 1; }
    function tick() { if ((++ticks & 1023) === 0 && now() - start > budget) throw cssError("css-slow"); }
    function skipComment() {
      var e = text.indexOf("*/", i + 2);
      if (e < 0) { note("comment"); i = n; } else i = e + 2;
    }
    function skipString() {
      var qch = text[i++];
      while (i < n) {
        tick();
        var ch = text[i];
        if (ch === "\\") { i += 2; continue; }
        if (ch === qch) { i++; return; }
        if (ch === "\n") { note("string"); return; }
        i++;
      }
      note("string");
    }
    // Anda até um dos `stops`. Chaves sempre param (CSS quebrado não engole o resto);
    // `;` dentro de parênteses não para (url(data:…;base64,…)).
    function scan(stops) {
      var depth = 0;
      while (i < n) {
        tick();
        var ch = text[i];
        if (ch === "/" && text[i + 1] === "*") { skipComment(); continue; }
        if (ch === '"' || ch === "'") { skipString(); continue; }
        if (ch === "\\") { i += 2; continue; }
        if (stops.indexOf(ch) >= 0 && (depth === 0 || ch === "{" || ch === "}")) return ch;
        if (ch === "(" || ch === "[") depth++;
        else if ((ch === ")" || ch === "]") && depth > 0) depth--;
        i++;
      }
      return "";
    }
    function skipBlock() {
      var depth = 1;
      while (i < n && depth > 0) {
        var st = scan("{}");
        if (st === "") break;
        i++;
        depth += st === "{" ? 1 : -1;
      }
      if (depth > 0) note("unclosed");
    }
    function declaration(piece, env) {
      var c = piece.indexOf(":");
      if (c < 0) { if (piece.trim()) note("decl"); return; }
      var name = stripComments(piece.slice(0, c)).trim();
      if (name.slice(0, 2) !== "--") return;
      if (!/^--[A-Za-z0-9_-]{1,120}$/.test(name)) { note("name"); return; }
      if (piece.length - c > CSS_VALUE * 2) { note("long"); return; }
      var value = stripComments(piece.slice(c + 1)).trim(), imp = false;
      if (value.length > CSS_VALUE) { note("long"); return; }
      var m = /!\s*important\s*$/i.exec(value);
      if (m) { imp = true; value = value.slice(0, m.index).trim(); }
      if (out.decls.length >= CSS_DECLS) { note("many"); return; }
      out.decls.push({ name: name, value: value, mode: env.mode, root: env.root, imp: imp, at: out.decls.length });
    }
    function atRule(env, depth) {
      i++;
      var s = i;
      while (i < n && /[A-Za-z0-9-]/.test(text[i])) i++;
      var name = text.slice(s, i).toLowerCase(), ps = i, stop = scan(";{}"), prelude = text.slice(ps, i);
      if (name === "import" && stop !== "{") out.imports.push(cleanUrl(prelude));
      if (stop === ";") { i++; return; }
      if (stop !== "{") return;
      i++;
      if (name === "media") block({ mode: mediaMode(prelude) || env.mode, root: env.root }, depth + 1, false);
      else if (["supports", "layer", "container", "document", "scope", "-moz-document"].indexOf(name) >= 0) block(env, depth + 1, false);
      else skipBlock();
    }
    // `decls`: dentro de uma regra (declarações e, com CSS aninhado, outras regras).
    function block(env, depth, decls) {
      if (depth > CSS_DEPTH) { note("depth"); skipBlock(); return; }
      while (i < n) {
        tick();
        var ch = text[i];
        if (ch === " " || ch === "\t" || ch === "\n" || ch === "\r" || ch === "\f" || ch === ";") { i++; continue; }
        if (ch === "/" && text[i + 1] === "*") { skipComment(); continue; }
        if (ch === "}") {
          i++;
          if (depth > 0) return;
          note("brace");
          continue;
        }
        if (ch === "@") { atRule(env, depth); continue; }
        var s = i, stop = scan(decls ? ";{}" : "{};"), piece = text.slice(s, i);
        if (stop === "{") {
          i++;
          out.rules++;
          block(selectorInfo(piece, env), depth + 1, true);
        } else if (decls) {
          if (stop === ";") i++;
          declaration(piece, env);
        } else {
          note("rule");
          if (stop === ";") i++;
        }
      }
      if (depth > 0) note("unclosed");
    }
    block({ mode: null, root: true }, 0, false);
    return out;
  }

  // A declaração que vale para cada variável neste modo: a de raiz (:root, .theme-dark…) ganha
  // da de um componente (`.theme-dark .popout`), qualquer que seja o modo; entre as de raiz, a do
  // modo ganha da geral; depois !important, depois a última. `scoped`: de raiz e só deste modo.
  function cssTable(decls, mode) {
    var best = Object.create(null);
    decls.forEach(function (d) {
      if (d.mode !== null && d.mode !== mode) return;
      var score = (d.root ? 4 : 0) + (d.mode ? 2 : 0) + (d.imp ? 1 : 0), cur = best[d.name];
      if (!cur || score > cur.score || (score === cur.score && d.at > cur.at)) best[d.name] = { value: d.value, score: score, at: d.at, scoped: d.root && d.mode !== null };
    });
    return best;
  }

  // Troca cada var(--x, reserva) pelo valor, com limite de profundidade, de tamanho e de passos.
  // `get.scoped(nome)`: o valor dependeu de alguma declaração de raiz só deste modo?
  function varResolver(table) {
    var memo = Object.create(null), memoScoped = Object.create(null), busy = Object.create(null), steps = 0, hit = false;
    function expand(value, depth) {
      if (depth > VAR_DEPTH || ++steps > VAR_STEPS) return null;
      var low = value.toLowerCase(), out = "", i = 0;
      for (;;) {
        var k = low.indexOf("var(", i);
        if (k < 0) { out += value.slice(i); break; }
        out += value.slice(i, k);
        var j = k + 4, d = 1, comma = -1;
        while (j < value.length && d > 0) {
          var ch = value[j];
          if (ch === "(") d++;
          else if (ch === ")") d--;
          else if (ch === "," && d === 1 && comma < 0) comma = j;
          j++;
        }
        if (d !== 0) return null;
        var name = value.slice(k + 4, comma >= 0 ? comma : j - 1).trim(), rep = get(name, depth + 1);
        if (rep === null && comma >= 0) rep = expand(value.slice(comma + 1, j - 1), depth + 1);
        if (rep === null) return null;
        out += rep;
        if (out.length > VAR_OUT) return null;
        i = j;
      }
      return out.length > VAR_OUT ? null : out;
    }
    function get(name, depth) {
      if (!own(table, name)) return null;
      if (own(memo, name)) { hit = hit || memoScoped[name]; return memo[name]; }
      if (busy[name]) return null;
      busy[name] = true;
      var outer = hit;
      hit = false;
      var v = expand(table[name].value, depth || 0);
      var scoped = hit || table[name].scoped;
      busy[name] = false;
      memoScoped[name] = scoped;
      hit = outer || scoped;
      return (memo[name] = v === null ? null : v.trim());
    }
    get.scoped = function (name) {
      hit = false;
      get(name);
      return hit;
    };
    return get;
  }

  // Cores do CSS: #hex, rgb()/rgba(), hsl()/hsla() (com vírgula ou espaço, alfa com /) e alguns nomes.
  var NAMED = { black: "#000000", white: "#ffffff", red: "#ff0000", green: "#008000", lime: "#00ff00", blue: "#0000ff", yellow: "#ffff00",
    orange: "#ffa500", purple: "#800080", magenta: "#ff00ff", fuchsia: "#ff00ff", cyan: "#00ffff", aqua: "#00ffff", pink: "#ffc0cb",
    gray: "#808080", grey: "#808080", silver: "#c0c0c0", navy: "#000080", teal: "#008080", maroon: "#800000", olive: "#808000",
    gold: "#ffd700", indigo: "#4b0082", violet: "#ee82ee", crimson: "#dc143c", coral: "#ff7f50", salmon: "#fa8072", tomato: "#ff6347" };
  var CSS_NUM = /^[+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?$/;
  function cssNumber(s, pct) {
    s = s.trim();
    if (s === "none") return 0;
    var isPct = s.slice(-1) === "%";
    if (isPct) s = s.slice(0, -1);
    if (!CSS_NUM.test(s)) return null;
    var v = +s;
    return isFinite(v) ? (isPct ? v * pct / 100 : v) : null;
  }
  function cssHue(s) {
    var m = /^(.*?)(deg|grad|rad|turn)?$/.exec(s.trim()), v = m && CSS_NUM.test(m[1]) ? +m[1] : null;
    if (v === null || !isFinite(v)) return null;
    return m[2] === "turn" ? v * 360 : m[2] === "rad" ? v * 180 / Math.PI : m[2] === "grad" ? v * 0.9 : v;
  }
  function hslRgb(h, s, l) {
    h = ((h % 360) + 360) % 360 / 360;
    function f(t) {
      t = t < 0 ? t + 1 : t > 1 ? t - 1 : t;
      return t < 1 / 6 ? p + (q2 - p) * 6 * t : t < 1 / 2 ? q2 : t < 2 / 3 ? p + (q2 - p) * (2 / 3 - t) * 6 : p;
    }
    var q2 = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q2;
    return s === 0 ? [l, l, l] : [f(h + 1 / 3), f(h), f(h - 1 / 3)];
  }
  function rgbHsl(c) {
    var r = c[0], g = c[1], b = c[2], mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, d = mx - mn, h = 0, s = 0;
    if (d > 1e-9) {
      s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
      h = 60 * (mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4);
    }
    return [h, s, l, d <= 1e-9];
  }
  // Separa por vírgula (ou por espaço) fora dos parênteses.
  function splitTop(s, comma) {
    var out = [], depth = 0, st = 0;
    for (var i = 0; i < s.length; i++) {
      var ch = s[i];
      if (ch === "(") depth++;
      else if (ch === ")") depth--;
      else if (depth === 0 && (comma ? ch === "," : ch === " " || ch === "\t" || ch === "\n" || ch === "\r" || ch === "\f")) { out.push(s.slice(st, i)); st = i + 1; }
    }
    out.push(s.slice(st));
    return out;
  }
  // color-mix(): os espaços que o CSS dos temas usa. A conta é a do CSS Color 5: porcentagens
  // normalizadas, alfa pré-multiplicado, o matiz pelo caminho mais curto, e o matiz de uma cor
  // sem croma (ou de `transparent`) não conta. Outros espaços (lab, display-p3…) ficam de fora.
  var MIX_SPACES = ["srgb", "srgb-linear", "oklab", "oklch", "hsl"];
  function inSpace(c, sp) {
    if (sp === "srgb") return [c[0], c[1], c[2], false];
    if (sp === "srgb-linear") return [lin(c[0]), lin(c[1]), lin(c[2]), false];
    if (sp === "oklab") { var lab = toOklab(c); return [lab[0], lab[1], lab[2], false]; }
    if (sp === "oklch") { var lch = toOklch(c); return [lch[0], lch[1], lch[2], lch[1] < 2e-4]; }
    return rgbHsl(c);
  }
  function fromSpace(v, sp) {
    if (sp === "srgb") return v;
    if (sp === "srgb-linear") return v.map(function (x) { return gam(clamp01(x)); });
    if (sp === "oklab") return oklch(v[0], Math.sqrt(v[1] * v[1] + v[2] * v[2]), Math.atan2(v[2], v[1]) * 180 / Math.PI);
    if (sp === "oklch") return oklch(v[0], Math.max(0, v[1]), v[2]);
    return hslRgb(v[0], clamp01(v[1]), clamp01(v[2]));
  }
  function mixArg(s, depth) {
    var t = splitTop(s.trim(), false).filter(function (x) { return x; }), p = null, col = t[0];
    if (t.length === 2) {
      var k = t[0].slice(-1) === "%" ? 0 : t[1].slice(-1) === "%" ? 1 : -1;
      if (k < 0) return null;
      p = cssNumber(t[k], 100);
      col = t[1 - k];
      if (p === null) return null;
    } else if (t.length !== 1) return null;
    var c = parseCssColor(col, depth + 1);
    return c ? { c: c, p: p } : null;
  }
  function colorMix(body, depth) {
    var args = splitTop(body, true);
    if (args.length !== 3) return null;
    var how = args[0].trim().split(/\s+/), sp = how[1];
    if (how[0] !== "in" || MIX_SPACES.indexOf(sp) < 0) return null;
    if (how.length !== 2 && !(how.length === 4 && how[2] === "shorter" && how[3] === "hue")) return null;
    var A = mixArg(args[1], depth), B = mixArg(args[2], depth);
    if (!A || !B) return null;
    var p1 = A.p, p2 = B.p;
    if (p1 === null && p2 === null) p1 = p2 = 50;
    else if (p1 === null) p1 = 100 - p2;
    else if (p2 === null) p2 = 100 - p1;
    if (!(p1 >= 0 && p2 >= 0 && p1 <= 100 && p2 <= 100 && p1 + p2 > 0)) return null;
    var sum = p1 + p2, w1 = p1 / sum, w2 = p2 / sum, x = inSpace(A.c, sp), y = inSpace(B.c, sp);
    var a1 = A.c[3], a2 = B.c[3], al = a1 * w1 + a2 * w2, hue = sp === "hsl" ? 0 : sp === "oklch" ? 2 : -1, out = [0, 0, 0];
    for (var k = 0; k < 3; k++) {
      if (k === hue) {
        var d = y[k] - x[k];
        if (d > 180) d -= 360; else if (d < -180) d += 360;
        out[k] = x[3] && y[3] ? 0 : x[3] ? y[k] : y[3] ? x[k] : x[k] + d * w2;
      } else out[k] = al > 0 ? (x[k] * a1 * w1 + y[k] * a2 * w2) / al : x[k] * w1 + y[k] * w2;
    }
    var rgb = fromSpace(out, sp);
    if (!rgb.slice(0, 3).every(isFinite)) return null;
    return [clamp01(rgb[0]), clamp01(rgb[1]), clamp01(rgb[2]), clamp01(al * (sum < 100 ? sum / 100 : 1))];
  }
  function parseCssColor(v, depth) {
    depth = depth || 0;
    var s = String(v).trim().toLowerCase();
    if (!s || s.length > VAR_OUT || depth > 4) return null;
    if (s[0] === "#") return parseHex(s.slice(1));
    if (s === "transparent") return [0, 0, 0, 0];
    if (own(NAMED, s)) return hexRgba(NAMED[s]);
    var m = /^([a-z-]+)\(([\s\S]*)\)$/.exec(s);
    if (!m) return null;
    if (m[1] === "color-mix") return colorMix(m[2], depth);
    if (/[()]/.test(m[2])) return null;
    var body = m[2], a = 1, slash = body.split("/");
    if (slash.length > 2) return null;
    if (slash.length === 2) { a = cssNumber(slash[1], 1); body = slash[0]; }
    var parts = (body.indexOf(",") >= 0 ? body.split(",") : body.trim().split(/\s+/)).map(function (x) { return x.trim(); });
    if (slash.length === 1 && parts.length === 4) a = cssNumber(parts.pop(), 1);
    if (parts.length !== 3 || a === null) return null;
    var c, fn = m[1];
    if (fn === "rgb" || fn === "rgba") {
      c = parts.map(function (x) { var k = cssNumber(x, 255); return k === null ? null : clamp01(k / 255); });
    } else if (fn === "hsl" || fn === "hsla") {
      var h = cssHue(parts[0]), sat = cssNumber(parts[1].replace(/%$/, ""), 1), lig = cssNumber(parts[2].replace(/%$/, ""), 1);
      c = h === null || sat === null || lig === null ? [null] : hslRgb(h, clamp01(sat / 100), clamp01(lig / 100));
    } else if (fn === "oklch" || fn === "oklab") {
      // L: 0–1 ou %; croma e a/b: número ou % (100% = 0,4); fora do sRGB, o croma diminui até caber.
      var L = cssNumber(parts[0], 1), p = cssNumber(parts[1], 0.4), q = fn === "oklch" ? (parts[2] === "none" ? 0 : cssHue(parts[2])) : cssNumber(parts[2], 0.4);
      if (L === null || p === null || q === null) return null;
      c = fn === "oklch" ? oklch(L, Math.max(0, p), q) : fromSpace([L, p, q], "oklab");
    } else return null;
    if (c.slice(0, 3).some(function (x) { return x === null || !isFinite(x); })) return null;
    return [c[0], c[1], c[2], clamp01(a)];
  }

  // De onde vem cada token: a primeira variável da lista que existe e é uma cor que dá para ler.
  // Os nomes antigos (--background-primary…) e os novos (--bg-base-*, --text-*, --background-base-*).
  var CSS_MAP = [
    ["bg", ["--background-primary", "--bg-base-primary", "--background-base-low"]],
    ["surface", ["--background-primary", "--bg-base-primary", "--background-base-low"]],
    ["sidebar", ["--background-secondary", "--bg-base-secondary", "--background-base-lower"]],
    ["rail", ["--background-tertiary", "--bg-base-tertiary", "--background-base-lowest"]],
    ["elevated", ["--channeltextarea-background", "--bg-surface-raised", "--background-surface-high", "--background-floating"]],
    ["overlay", ["--background-floating", "--bg-surface-overlay", "--background-surface-highest"]],
    ["code-bg", ["--background-secondary", "--bg-base-secondary", "--background-base-lower"]],
    ["text", ["--text-normal", "--text-default", "--text-primary", "--header-primary", "--interactive-hover"]],
    ["muted", ["--channels-default", "--text-secondary", "--header-secondary", "--interactive-normal"]],
    ["faint", ["--text-muted", "--text-tertiary", "--interactive-muted"]],
    ["link", ["--text-link"]],
    ["accent", ["--brand-experiment", "--brand-500", "--bg-brand", "--text-brand"]],
    ["mention", ["--mention-foreground", "--text-brand", "--brand-experiment", "--brand-500", "--bg-brand"]],
    ["selected", ["--background-modifier-selected", "--bg-mod-strong", "--background-mod-strong"]],
    ["hover", ["--background-modifier-hover", "--bg-mod-faint", "--background-mod-subtle", "--background-mod-normal"]],
    ["border", ["--background-modifier-accent", "--border-subtle", "--border-faint"]],
    ["online", ["--status-online", "--status-positive", "--text-positive", "--text-feedback-positive", "--green-360"]],
    ["idle", ["--status-idle", "--status-warning", "--text-warning", "--text-feedback-warning", "--yellow-300"]],
    ["dnd", ["--status-dnd", "--status-danger", "--text-danger", "--text-feedback-critical", "--red-400"]],
    ["danger", ["--status-danger", "--button-danger-background", "--text-danger", "--text-feedback-critical", "--red-400"]],
    ["bubble-self", ["--brand-experiment", "--brand-500", "--bg-brand"]],
    ["bubble-other", ["--background-secondary-alt", "--bg-surface-raised", "--background-surface-high", "--background-floating"]],
  ];
  // Estes podem ser translúcidos de verdade; os outros, quase invisíveis, viram "transparente no CSS".
  // Os outros, meio translúcidos (um tema com imagem de fundo), são postos sobre o fundo: o app
  // desenha a cor como ela é, e um campo de texto a 20% deixaria ver o que está atrás.
  var SHEER = ["hover", "selected", "border", "shadow"];
  // O texto em cima do destaque: preto ou branco, o que contrastar mais.
  var DERIVED = [["accent-text", "accent"], ["bubble-self-text", "bubble-self"]];

  // `scoped`: algum token veio de uma declaração de raiz deste modo (.theme-light, o bloco
  // prefers-color-scheme: light…). Sem isso, o modo claro do CSS é só o geral, e não entra.
  function mapCss(decls, mode) {
    var get = varResolver(cssTable(decls, mode)), got = Object.create(null), by = Object.create(null);
    var res = { mapped: [], derived: [], skipped: [], kept: [], scoped: false };
    CSS_MAP.forEach(function (row) {
      var tok = row[0], why = null;
      for (var k = 0; k < row[1].length; k++) {
        var name = row[1][k], raw = get(name);
        if (raw === null) continue;
        var c = parseCssColor(raw);
        if (!c) { why = why || { tok: tok, from: name, why: "unreadable" }; continue; }
        if (c[3] < 0.05 && SHEER.indexOf(tok) < 0) { why = why || { tok: tok, from: name, why: "transparent" }; continue; }
        got[tok] = c;
        if (get.scoped(name)) res.scoped = true;
        res.mapped.push(by[tok] = { tok: tok, from: name, value: toHex(c) });
        return;
      }
      if (why) res.skipped.push(why);
    });
    // O fundo translúcido vai sobre preto (escuro) ou branco (claro); o resto, sobre o fundo.
    var base = mode === "light" ? WHITE : BLACK;
    var bg = got.bg ? over(got.bg, base) : base;
    res.mapped.forEach(function (m) {
      var c = got[m.tok];
      if (SHEER.indexOf(m.tok) >= 0 || m.value.length === 7) return;
      m.alpha = c[3];
      m.over = m.tok === "bg" ? mode : "bg";
      got[m.tok] = over(c, m.tok === "bg" ? base : bg);
      m.value = toHex(got[m.tok]);
    });
    // faint é o texto mais apagado. Quando o CSS dá o contrário (os nomes novos usam --text-muted
    // para um cinza mais claro que o dos canais), os dois trocam de lugar.
    if (by.muted && by.faint && contrast(got.faint, bg) > contrast(got.muted, bg) + 0.05) {
      var f = by.faint, mu = by.muted, t = [f.from, f.value, f.alpha, f.over];
      f.from = mu.from; f.value = mu.value; f.alpha = mu.alpha; f.over = mu.over;
      mu.from = t[0]; mu.value = t[1]; mu.alpha = t[2]; mu.over = t[3];
      var g = got.faint; got.faint = got.muted; got.muted = g;
      f.swapped = mu.swapped = true;
    }
    res.mapped.forEach(function (m) { if (m.alpha === undefined) { delete m.alpha; delete m.over; } });
    DERIVED.forEach(function (d) {
      if (!got[d[1]]) return;
      var back = got[d[1]];
      res.derived.push({ tok: d[0], from: d[1], value: contrast(BLACK, back) >= contrast(WHITE, back) ? "#000000" : "#ffffff" });
    });
    var done = res.mapped.concat(res.derived).map(function (x) { return x.tok; });
    res.kept = TOKENS.filter(function (t) { return done.indexOf(t) < 0; });
    return res;
  }

  function importDiscordCss(text, opt) {
    var p = parseCss(text, opt), names = Object.create(null);
    p.decls.forEach(function (d) { names[d.name] = true; });
    var light = mapCss(p.decls, "light");
    var modes = { dark: mapCss(p.decls, "dark"), light: light.scoped ? light : null };
    var count = modes.dark.mapped.length + (modes.light ? modes.light.mapped.length : 0);
    if (!count) throw cssError("css-empty");
    return { modes: modes, imports: p.imports, vars: Object.keys(names).length, rules: p.rules, notes: p.notes };
  }

  // Põe as cores lidas no estado do criador; o que não veio do CSS fica como estava.
  function applyCssImport(state, res) {
    var s = clone(state);
    ["dark", "light"].forEach(function (mode) {
      var r = res.modes[mode];
      if (!r) return;
      r.mapped.concat(r.derived).forEach(function (m) { s.colors[mode][m.tok] = m.value; });
    });
    return s;
  }

  // ------------------------------------------------------ Link de compartilhar ----
  function b64url(bytes) {
    var s = "";
    for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
    var b = typeof btoa === "function" ? btoa(s) : Buffer.from(s, "binary").toString("base64");
    return b.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }
  function unb64url(t) {
    var b = t.replace(/-/g, "+").replace(/_/g, "/");
    while (b.length % 4) b += "=";
    var s = typeof atob === "function" ? atob(b) : Buffer.from(b, "base64").toString("binary");
    var out = new Uint8Array(s.length);
    for (var i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
    return out;
  }
  function utf8(s) { return new TextEncoder().encode(s); }
  function fromUtf8(b) { return new TextDecoder().decode(b); }

  // Todas as cores separadas por ponto: uma cor translúcida tem 8 dígitos, não 6.
  function compact(state, builtinStructure) {
    var hx = function (h) { return normHex(h).slice(1); };
    var c = { v: 1, b: state.base || "", m: [state.meta.name, state.meta.author, state.meta.desc, state.meta.descEn, state.meta.preview, state.meta.license || ""],
      f: [state.fonts.ui, state.fonts.mono, state.fonts.size], r: state.radius, w: state.transparent ? 1 : 0 };
    ["dark", "light"].forEach(function (mode) {
      var k = mode[0];
      c["p" + k] = state.palette[mode].map(hx).join(".");
      c["c" + k] = TOKENS.map(function (t) { return hx(state.colors[mode][t]); }).join(".");
      c["r" + k] = state.roles[mode].map(hx).join(".");
    });
    var ref = state.layoutFrom && builtinStructure && builtinStructure(state.layoutFrom) === state.structure;
    if (ref) c.l = state.layoutFrom; else c.s = state.structure;
    return c;
  }
  function linkError(code) { var e = new Error(MSG.en[code]); e.code = code; return e; }
  // O link vem de qualquer pessoa: cada campo é conferido antes de virar estado.
  function expand(c, builtinStructure) {
    if (!c || typeof c !== "object" || Array.isArray(c)) throw linkError("link-broken");
    if (c.v !== 1) throw linkError("link-version");
    function text(v) { return typeof v === "string" ? v : typeof v === "number" ? String(v) : ""; }
    function colors(v, n) {
      var s = text(v);
      // Os primeiros links juntavam a paleta e os cargos em 6 dígitos, sem separador.
      var parts = s.indexOf(".") >= 0 ? s.split(".") : s.length === n * 6 ? s.match(/.{6}/g) : [];
      if (parts.length !== n) throw linkError("link-broken");
      return parts.map(function (p) {
        if (!/^([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(p)) throw linkError("link-broken");
        return normHex("#" + p);
      });
    }
    function clampNum(v, lo, hi, d) { var x = +v; return isFinite(x) && v !== "" && v !== null ? Math.min(hi, Math.max(lo, x)) : d; }
    var m = Array.isArray(c.m) ? c.m : [], f = Array.isArray(c.f) ? c.f : [];
    var base = /^[a-z0-9-]{1,40}$/.test(text(c.b)) ? c.b : null;
    var structure;
    if (c.l !== undefined && c.l !== null && c.l !== "") {
      structure = /^[a-z0-9-]{1,40}$/.test(text(c.l)) && builtinStructure ? builtinStructure(c.l) : undefined;
      if (typeof structure !== "string") throw linkError("link-layout");
    } else structure = text(c.s);
    var state = { v: 1, base: base, layoutFrom: typeof c.l === "string" && c.l ? c.l : null,
      meta: { name: text(m[0]), author: text(m[1]), desc: text(m[2]), descEn: text(m[3]), preview: PREVIEWS.indexOf(m[4]) >= 0 ? m[4] : "classic", license: text(m[5]) },
      fonts: { ui: text(f[0]) || "Inter", mono: text(f[1]) || "JetBrains Mono", size: clampNum(f[2], 6, 72, 16) },
      radius: clampNum(c.r, 0, 64, 6), transparent: !!c.w, usesWal: false,
      palette: {}, colors: {}, roles: {}, structure: structure };
    ["dark", "light"].forEach(function (mode) {
      var k = mode[0], toks = colors(c["c" + k], TOKENS.length);
      state.palette[mode] = colors(c["p" + k], 16);
      state.roles[mode] = colors(c["r" + k], 8);
      state.colors[mode] = {};
      TOKENS.forEach(function (t, i) { state.colors[mode][t] = toks[i]; });
    });
    return state;
  }
  // Um tema de themes/community/, o .kdl que o criador busca no site pelo link da galeria:
  // vazio ou grande demais é "community-missing"; o resto são os erros do leitor de sempre.
  function communityFromSource(src) {
    if (typeof src !== "string" || !src.trim() || src.length > COMMUNITY_MAX) throw linkError("community-missing");
    var cs = fromSource(src, { name: "" });
    loadTheme(toKdl(cs), { mode: "dark" });
    cs.base = null;
    cs.layoutFrom = null;
    return cs;
  }

  function encodeSync(state, builtinStructure) { return "j." + b64url(utf8(JSON.stringify(compact(state, builtinStructure)))); }
  function encode(state, builtinStructure) {
    var json = JSON.stringify(compact(state, builtinStructure));
    if (typeof CompressionStream === "undefined") return Promise.resolve("j." + b64url(utf8(json)));
    var cs = new CompressionStream("deflate-raw");
    var stream = new Blob([utf8(json)]).stream().pipeThrough(cs);
    return new Response(stream).arrayBuffer().then(function (buf) { return "d." + b64url(new Uint8Array(buf)); });
  }
  // Um tema tem poucos KB: um link que descomprime para mais que isto não é de tema.
  var LINK_MAX = 1 << 20;
  function decode(token, builtinStructure) {
    token = String(token);
    var kind = token.slice(0, 2), body = token.slice(2);
    function done(json) { return expand(JSON.parse(json), builtinStructure); }
    // Só os nossos códigos passam: DOMException e zlib também têm `code`, com outro sentido.
    function why(e) { return e && typeof e.code === "string" && own(MSG.en, e.code) ? e : linkError("link-broken"); }
    if (kind === "j.") {
      try { return Promise.resolve(done(fromUtf8(unb64url(body)))); } catch (e) { return Promise.reject(why(e)); }
    }
    if (kind !== "d.") return Promise.reject(linkError("link-broken"));
    if (typeof DecompressionStream === "undefined") return Promise.reject(linkError("link-unsupported"));
    var reader, chunks = [], size = 0;
    try { reader = new Blob([unb64url(body)]).stream().pipeThrough(new DecompressionStream("deflate-raw")).getReader(); } catch (e) { return Promise.reject(why(e)); }
    function pump() {
      return reader.read().then(function (r) {
        if (r.done) {
          var out = new Uint8Array(size), at = 0;
          chunks.forEach(function (ch) { out.set(ch, at); at += ch.length; });
          return done(fromUtf8(out));
        }
        size += r.value.length;
        if (size > LINK_MAX) { reader.cancel(); throw linkError("link-broken"); }
        chunks.push(r.value);
        return pump();
      });
    }
    return pump().catch(function (e) { throw why(e); });
  }

  function clone(s) { return JSON.parse(JSON.stringify(s)); }

  return {
    KdlError: KdlError, ThemeError: ThemeError, ColorError: ColorError, MSG: MSG, errorText: errorText, own: own,
    parseKdl: parseKdl, prop: prop, pv: pv, str: str, num: num, flag: flag, arg: arg,
    TOKENS: TOKENS, FALLBACK: FALLBACK, BACKS: BACKS, LEGIBLE: LEGIBLE, PREVIEWS: PREVIEWS, COMPONENTS: COMPONENTS,
    tokenName: tokenName, parseHex: parseHex, hexRgba: hexRgba, toHex: toHex, normHex: normHex, cssColor: cssColor,
    mix: mix, alpha: alpha, luma: luma, luminance: luminance, contrast: contrast,
    evalColor: evalColor, splitColors: splitColors, defaults: defaults, defaultRoles: defaultRoles, legibleText: legibleText,
    loadTheme: loadTheme, fromSource: fromSource, toKdl: toKdl, slug: slug, quote: q,
    setProp: setProp, listTweaks: listTweaks, structureOptions: structureOptions, findNode: findNode,
    outline: outline, moveNode: moveNode, RANGES: RANGES, range: range,
    HARMONY: HARMONY, seedFromBase: seedFromBase, applyGenerated: applyGenerated, onColor: onColor,
    flipL: flipL, invertMode: invertMode, toOklab: toOklab, fromOklab: fromOklab,
    contrastReport: contrastReport, layoutColorBlocks: layoutColorBlocks, effectiveColors: effectiveColors, oklch: oklch, toOklch: toOklch, rng: rng,
    generate: generate, randomSeed: randomSeed, imageColors: imageColors, seedFromImage: seedFromImage,
    seedFromColors: seedFromColors, fromPalette: fromPalette,
    COMMUNITY: COMMUNITY, COMMUNITY_MAX: COMMUNITY_MAX, LICENSES: LICENSES, licenseOk: licenseOk, communityCheck: communityCheck, communityFromSource: communityFromSource,
    CSS_MAX: CSS_MAX, CSS_MAP: CSS_MAP, parseCss: parseCss, parseCssColor: parseCssColor, importDiscordCss: importDiscordCss, applyCssImport: applyCssImport,
    encode: encode, encodeSync: encodeSync, decode: decode, compact: compact, expand: expand, clone: clone,
  };
});
