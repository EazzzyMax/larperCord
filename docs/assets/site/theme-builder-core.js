// O núcleo do criador de temas: sem DOM, para a página e o teste (tools/theme_builder_test.js)
// usarem o mesmo código. Leitor de KDL, cores e o carregamento do tema seguem
// src/theme/kdl.zig, color.zig, theme.zig e fx.zig; o arquivo gerado é o que o app lê.
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.LC_TB = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  // ------------------------------------------------------------ KDL ----
  function KdlError(message, line, column) {
    this.message = message;
    this.line = line;
    this.column = column;
  }
  KdlError.prototype.toString = function () { return this.line + ":" + this.column + ": " + this.message; };

  // Mesmo subconjunto de src/theme/kdl.zig. Cada nó guarda onde começa e termina no
  // texto, e cada propriedade onde está o valor: assim um ajuste troca só aquele pedaço.
  function parseKdl(src) {
    var i = 0, line = 1, lineStart = 0, depth = 0, n = src.length;
    function fail(msg) { throw new KdlError(msg, line, i - lineStart + 1); }
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
          if (d !== 0) fail("unclosed /* comment");
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
      if (i === s) fail("expected a name");
      return src.slice(s, i);
    }
    function string() {
      adv();
      var out = "";
      for (;;) {
        if (i >= n) fail("unterminated string");
        var ch = src[i];
        if (ch === '"') { adv(); break; }
        if (ch === "\\") {
          adv();
          var e = peek(), r = { n: "\n", t: "\t", r: "\r", '"': '"', "\\": "\\", "/": "/" }[e];
          if (r === undefined) fail("invalid escape");
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
      if (txt.length > 64 || !/^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(txt)) fail("invalid number");
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
      if (depth >= 64) fail("too many nested blocks");
      depth++;
      var list = [];
      for (;;) {
        skipSpace(true);
        while (peek() === ";") { adv(); skipSpace(true); }
        if (i >= n) {
          if (inBlock) fail("missing '}'");
          break;
        }
        if (peek() === "}") {
          if (!inBlock) fail("unexpected '}'");
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
        if (typeof name !== "string") throw new KdlError(name === undefined ? "option without a name" : "option name must be a string", ch.line, ch.col);
        var d = flag(ch, "default");
        list.push({
          name: name, label: str(ch, "label") || name, desc: str(ch, "description") || "",
          labelEn: str(ch, "label-en") || "", descEn: str(ch, "description-en") || "", def: d === null ? true : d, node: ch,
        });
      });
    });
    return list;
  }

  function ThemeError(message, line) {
    this.message = message;
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
    var options = optionList(nodes), values = {};
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
        if (!c) throw new ThemeError("invalid palette color", nd.line);
        pal[i] = c;
      });
    });

    var th = {
      mode: mode, name: "sem nome", description: "", descriptionEn: "", author: "", preview: "classic",
      tokens: defaults(pal, mode), roles: defaultRoles(pal, mode), palette: pal, usesWal: usesWal,
      fontUi: "Inter", fontMono: "JetBrains Mono", fontSize: 16, radius: 6, transparent: false,
      styles: {}, layout: null, options: options, values: values, nodes: nodes,
    };
    var lookup = function (name) { return th.tokens[name]; };
    function color(e, nd, msg) {
      try { return evalColor(e, pal, lookup, false); } catch (err) { throw new ThemeError(msg, nd.line); }
    }
    nodes.forEach(function (nd) {
      if (!applies(nd, mode, values)) return;
      switch (nd.name) {
        case "theme":
          if (typeof arg(nd, 0) === "string") th.name = arg(nd, 0);
          th.description = str(nd, "description") || th.description;
          th.descriptionEn = str(nd, "description-en") || th.descriptionEn;
          th.author = str(nd, "author") || th.author;
          th.preview = str(nd, "preview") || th.preview;
          break;
        case "colors":
          nd.kids.forEach(function (ch) {
            var tok = tokenName(ch.name);
            if (!tok) throw new ThemeError("unknown color token: " + ch.name, ch.line);
            var e = arg(ch, 0);
            if (e === undefined) throw new ThemeError("missing color", ch.line);
            if (typeof e !== "string") throw new ThemeError("the color must be a string", ch.line);
            th.tokens[tok] = color(e, ch, "invalid color expression");
          });
          break;
        case "roles":
          nd.args.forEach(function (a, i) {
            if (i >= 8 || typeof a.v !== "string") return;
            th.roles[i] = color(a.v, nd, "invalid role color");
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
            if (sname === undefined) throw new ThemeError("style without a name", ch.line);
            if (typeof sname !== "string") throw new ThemeError("style name must be a string", ch.line);
            ["bg", "border", "glow"].forEach(function (k) { if (str(ch, k) !== null) color(str(ch, k), ch, k + " is invalid"); });
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
    if (!th.layout) throw new ThemeError("the theme needs a `layout` node", 0);
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

  function fxColor(th, e, nd, msg) {
    try { return evalColor(e, th.palette, function (n) { return th.tokens[n]; }, true); } catch (err) { throw new ThemeError(msg, nd.line); }
  }
  function checkGradient(th, nd, key) {
    var parts = splitColors(str(nd, key));
    if (parts.length < 2 || parts.length > 3) throw new ThemeError("a gradient needs 2 or 3 colors", nd.line);
    parts.forEach(function (p) { fxColor(th, p, nd, "invalid color in the gradient"); });
  }
  function checkBox(th, nd, isStyle) {
    if (str(nd, "gradient") !== null) checkGradient(th, nd, "gradient");
    if (str(nd, "pattern") !== null) {
      if (["dots", "lines", "grid", "diagonal"].indexOf(str(nd, "pattern")) < 0) throw new ThemeError("pattern: dots, lines, grid or diagonal", nd.line);
      if (str(nd, "pattern-color") === null) throw new ThemeError("pattern needs pattern-color", nd.line);
      fxColor(th, str(nd, "pattern-color"), nd, "invalid pattern-color");
    }
    ["grain", "vignette", "inner-shadow", "drop-shadow", "hover-bg"].forEach(function (k) {
      if (str(nd, k) !== null) fxColor(th, str(nd, k), nd, k + " is invalid");
    });
    if (str(nd, "border-gradient") !== null) checkGradient(th, nd, "border-gradient");
    if (!isStyle && str(nd, "border") !== null) fxColor(th, str(nd, "border"), nd, "invalid border");
    SIDES.forEach(function (k) { if (str(nd, k) !== null) fxColor(th, str(nd, k), nd, "invalid side border"); });
    var c = str(nd, "corners");
    if (c !== null && ["all", "left", "right", "top", "bottom"].indexOf(c) < 0) throw new ThemeError("corners: all, left, right, top or bottom", nd.line);
  }
  var WEIGHTS = ["regular", "medium", "semibold", "bold", "italic"];
  function checkLabel(th, ch) {
    // Como `labelWantsFx` de fx.zig: o rótulo simples não passa por esta leitura.
    var col = str(ch, "color"), colExpr = col !== null && !tokenName(col);
    var wants = colExpr || ch.kids.some(function (k) { return k.name === "span"; }) ||
      ["tracking", "shadow", "outline", "text-gradient", "text-en"].some(function (k) { return prop(ch, k) !== null; });
    if (!wants) return;
    if (col !== null) fxColor(th, col, ch, "invalid color");
    if (str(ch, "weight") !== null && WEIGHTS.indexOf(str(ch, "weight")) < 0) throw new ThemeError("weight: regular, medium, semibold, bold or italic", ch.line);
    ["shadow", "outline"].forEach(function (k) { if (str(ch, k) !== null) fxColor(th, str(ch, k), ch, k + " is invalid"); });
    if (str(ch, "text-gradient") !== null) checkGradient(th, ch, "text-gradient");
    ch.kids.forEach(function (sp) {
      if (sp.name !== "span") return;
      var txt = typeof arg(sp, 0) === "string" ? arg(sp, 0) : str(sp, "text");
      if (txt === null) throw new ThemeError("span without text", sp.line);
      if (str(sp, "weight") !== null && WEIGHTS.indexOf(str(sp, "weight")) < 0) throw new ThemeError("weight: regular, medium, semibold, bold or italic", sp.line);
      if (str(sp, "color") !== null) fxColor(th, str(sp, "color"), sp, "invalid color in the span");
    });
  }
  function checkLayout(th, nd) {
    nd.kids.forEach(function (ch) {
      var bg = str(ch, "bg");
      if (bg !== null && !tokenName(bg)) fxColor(th, bg, ch, "invalid bg");
      checkBox(th, ch, false);
      if (ch.name === "label") {
        checkLabel(th, ch);
      } else if (PAINTED.indexOf(ch.name) >= 0) {
        PAINT_KEYS.forEach(function (k) { if (str(ch, k) !== null) fxColor(th, str(ch, k), ch, "invalid color"); });
      }
      ch.props.forEach(function (p) {
        var m = /^(c|cl|cd)-(.+)$/.exec(p.k);
        if (!m || (m[1] === "cl" && th.mode !== "light") || (m[1] === "cd" && th.mode !== "dark")) return;
        if (!tokenName(m[2])) throw new ThemeError("unknown color token in c-…", ch.line);
        if (typeof p.v !== "string") throw new ThemeError("the color must be a string", ch.line);
        try { evalColor(p.v, th.palette, function (n) { return th.tokens[n]; }, false); } catch (e) { throw new ThemeError("invalid color expression", ch.line); }
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
      meta: { name: info.name || "", author: "", desc: "", descEn: "", preview: "classic" },
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
    out.push("// Made in the larperCord theme builder" + (state.base ? ", starting from " + state.base : "") + ".");
    if (extra.url) out.push("// " + extra.url);
    var head = "theme " + q(m.name || file);
    if (desc) head += " description=" + q(desc);
    if (descEn) head += " description-en=" + q(descEn);
    if (m.author) head += " author=" + q(m.author);
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
  };
  var CONTAINERS = ["row", "column", "stack"];

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

  // ----------------------------------------------------------- Contraste ----
  function contrastReport(state, mode) {
    var toks = {};
    TOKENS.forEach(function (t) { toks[t] = hexRgba(state.colors[mode][t]); });
    var rows = [];
    LEGIBLE.forEach(function (w) {
      var worst = 99, fails = [];
      BACKS.forEach(function (b) {
        var r = contrast(toks[w.tok], toks[b]);
        if (r < worst) worst = r;
        if (r < w.min) fails.push(b);
      });
      rows.push({ id: w.tok, fg: w.tok, backs: BACKS.slice(), min: w.min, ratio: worst, fails: fails, app: true,
        fix: fails.length ? { tok: w.tok, value: toHex(legibleFor(toks, w.tok, w.min)) } : null });
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
      rows.push({ id: fg, fg: fg, backs: backs, min: min, ratio: worst, fails: fails, app: false, fix: fails.length ? fixer() : null });
    }
    function towards(tok, backs, min) {
      var base = toks[tok], avg = backs.reduce(function (a, b) { return a + luminance(seen(tok, b)[1]); }, 0) / backs.length;
      var target = avg > 0.18 ? BLACK : WHITE;
      for (var k = 0.05; k <= 1.0001; k += 0.05) {
        var col = mix(base, target, k);
        if (backs.every(function (b) { var s = seen(tok, b); return contrast(over(col, s[1]), s[1]) >= min; })) return { tok: tok, value: toHex(col) };
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

  function compact(state, builtinStructure) {
    var hx = function (h) { return normHex(h).slice(1); };
    var c = { v: 1, b: state.base || "", m: [state.meta.name, state.meta.author, state.meta.desc, state.meta.descEn, state.meta.preview],
      f: [state.fonts.ui, state.fonts.mono, state.fonts.size], r: state.radius, w: state.transparent ? 1 : 0 };
    ["dark", "light"].forEach(function (mode) {
      var k = mode[0];
      c["p" + k] = state.palette[mode].map(hx).join("");
      c["c" + k] = TOKENS.map(function (t) { return hx(state.colors[mode][t]); }).join(".");
      c["r" + k] = state.roles[mode].map(hx).join("");
    });
    var ref = state.layoutFrom && builtinStructure && builtinStructure(state.layoutFrom) === state.structure;
    if (ref) c.l = state.layoutFrom; else c.s = state.structure;
    return c;
  }
  function expand(c, builtinStructure) {
    if (!c || c.v !== 1) throw new Error("unknown link version");
    var six = function (s) { var o = []; for (var i = 0; i < s.length; i += 6) o.push("#" + s.slice(i, i + 6)); return o; };
    var state = { v: 1, base: c.b || null, layoutFrom: c.l || null,
      meta: { name: c.m[0] || "", author: c.m[1] || "", desc: c.m[2] || "", descEn: c.m[3] || "", preview: c.m[4] || "classic" },
      fonts: { ui: c.f[0], mono: c.f[1], size: +c.f[2] || 16 }, radius: +c.r || 0, transparent: !!c.w,
      palette: {}, colors: {}, roles: {}, structure: c.l ? builtinStructure(c.l) : String(c.s || "") };
    ["dark", "light"].forEach(function (mode) {
      var k = mode[0], parts = String(c["c" + k]).split(".");
      state.palette[mode] = six(c["p" + k]).map(normHex);
      state.roles[mode] = six(c["r" + k]).map(normHex);
      state.colors[mode] = {};
      TOKENS.forEach(function (t, i) { state.colors[mode][t] = normHex("#" + parts[i]); });
    });
    if (state.palette.dark.length !== 16 || state.roles.dark.length !== 8) throw new Error("broken link");
    if (state.structure === undefined || state.structure === null) throw new Error("unknown layout");
    return state;
  }
  function encodeSync(state, builtinStructure) { return "j." + b64url(utf8(JSON.stringify(compact(state, builtinStructure)))); }
  function encode(state, builtinStructure) {
    var json = JSON.stringify(compact(state, builtinStructure));
    if (typeof CompressionStream === "undefined") return Promise.resolve("j." + b64url(utf8(json)));
    var cs = new CompressionStream("deflate-raw");
    var stream = new Blob([utf8(json)]).stream().pipeThrough(cs);
    return new Response(stream).arrayBuffer().then(function (buf) { return "d." + b64url(new Uint8Array(buf)); });
  }
  function decode(token, builtinStructure) {
    var kind = token.slice(0, 2), body = token.slice(2);
    if (kind === "j.") return Promise.resolve(expand(JSON.parse(fromUtf8(unb64url(body))), builtinStructure));
    if (kind !== "d." || typeof DecompressionStream === "undefined") return Promise.reject(new Error("unsupported link"));
    var stream = new Blob([unb64url(body)]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
    return new Response(stream).arrayBuffer().then(function (buf) { return expand(JSON.parse(fromUtf8(new Uint8Array(buf))), builtinStructure); });
  }

  function clone(s) { return JSON.parse(JSON.stringify(s)); }

  return {
    KdlError: KdlError, ThemeError: ThemeError, ColorError: ColorError,
    parseKdl: parseKdl, prop: prop, pv: pv, str: str, num: num, flag: flag, arg: arg,
    TOKENS: TOKENS, FALLBACK: FALLBACK, BACKS: BACKS, LEGIBLE: LEGIBLE, PREVIEWS: PREVIEWS, COMPONENTS: COMPONENTS,
    tokenName: tokenName, parseHex: parseHex, hexRgba: hexRgba, toHex: toHex, normHex: normHex, cssColor: cssColor,
    mix: mix, alpha: alpha, luma: luma, luminance: luminance, contrast: contrast,
    evalColor: evalColor, splitColors: splitColors, defaults: defaults, defaultRoles: defaultRoles, legibleText: legibleText,
    loadTheme: loadTheme, fromSource: fromSource, toKdl: toKdl, slug: slug, quote: q,
    setProp: setProp, listTweaks: listTweaks, structureOptions: structureOptions, findNode: findNode,
    contrastReport: contrastReport, oklch: oklch, toOklch: toOklch, rng: rng,
    generate: generate, randomSeed: randomSeed, imageColors: imageColors, seedFromImage: seedFromImage,
    seedFromColors: seedFromColors, fromPalette: fromPalette,
    encode: encode, encodeSync: encodeSync, decode: decode, compact: compact, expand: expand, clone: clone,
  };
});
