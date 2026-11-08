// O criador de temas: controles, desfazer/refazer, a prévia e a exportação.
// As contas (KDL, cores, carregamento do tema, geração) ficam em theme-builder-core.js,
// o mesmo arquivo que tools/theme_builder_test.js testa.
(function () {
  var box = document.querySelector("[data-builder]");
  if (!box || !window.LC_TB || !window.LC_TB_PREVIEW) return;
  var TB = window.LC_TB;
  var html = document.documentElement;
  var lang = html.dataset.lang === "pt" ? "pt" : "en";
  var DATA = JSON.parse(document.getElementById("tb-data").textContent);
  // Os componentes da prévia viram HTML em theme-builder-preview.js (o teste usa o mesmo).
  var P = window.LC_TB_PREVIEW(TB, lang);
  var W = P.W, H = P.H;

  var S = lang === "pt" ? {
    groups: { surfaces: "Superfícies", text: "Texto", accent: "Destaque", status: "Status", bubbles: "Balões", shadow: "Sombra" },
    tok: { bg: "Fundo da janela e da conversa", rail: "A faixa mais escura: servidores, barras de título e de status", sidebar: "Listas de canais e de membros", surface: "Cartões e painéis", elevated: "Campos, popups, item com o mouse em cima", overlay: "Menus e diálogos", "code-bg": "Blocos de código", text: "Texto principal", muted: "Texto secundário: canais, horários", faint: "Dicas, texto de exemplo, membros offline", link: "Links", accent: "Botões, seleção, destaques", "accent-text": "Texto em cima do destaque", mention: "Menções a você", selected: "Canal ou linha selecionada", hover: "Linha com o mouse em cima", border: "Bordas e divisórias", online: "Status: online", idle: "Status: ausente", dnd: "Status: não perturbe", danger: "Erros, apagar, contador de não lidas", "bubble-self": "Seus balões de conversa", "bubble-self-text": "Texto nos seus balões", "bubble-other": "Balões dos outros", shadow: "Sombras" },
    color: "cor", opacity: "opacidade", roles: "Cores de cargo", rolesHint: "Nomes de usuário e ícones de servidor.", role: "cargo",
    palette: "Paleta base (wal:0–15)", paletteHint: "As 16 cores que o arquivo chama de wal:0 … wal:15. Alguns layouts usam elas direto.",
    recolor: "Recolorir este modo a partir da paleta", other: { dark: "Montar o modo claro parecido com este", light: "Montar o modo escuro parecido com este" },
    editing: { dark: "Editando as cores do modo escuro", light: "Editando as cores do modo claro" },
    fromImage: "Da sua imagem (nada sai do navegador):", imgUse: "usar como destaque",
    def: "(padrão do tema)", on: "ligado", off: "desligado", follows: "segue a opção ", none: "nenhum ajuste neste layout",
    options: "Opções do tema", optionsHint: "O que já vem ligado. Quem usar o tema ainda muda em Configurações → Aparência.", noOptions: "Este layout não tem opções.",
    components: "Componentes", line: "linha", when: "só com ", unless: "sem ",
    advOk: "ok: o layout é válido", advErr: "erro", kept: "a prévia anterior continua", errAt: "Erro no arquivo, linha ",
    custom: "personalizado", layoutNow: "Layout atual: ",
    contrastOk: "Tudo legível neste modo.", issues: function (n) { return n === 1 ? "1 ponto para olhar neste modo." : n + " pontos para olhar neste modo."; },
    on_: " sobre ", needs: "o app pede ", wcag: "mínimo da WCAG (AA) ", lifts: "O app clareia esta cor para ", liftsEnd: " ao carregar o tema.", use: "Usar ", fix: "Consertar",
    otherMode: { dark: "modo claro", light: "modo escuro" }, otherIssues: function (m, n) { return n ? "No " + m + ": " + n + (n === 1 ? " ponto." : " pontos.") : "No " + m + ": tudo legível."; },
    passes: "passa", fails: "não passa", stuck: "Nem o text chega nisso. Aumente o contraste do text primeiro.",
    fromLayout: function (line) { return "Esta cor vem do layout (linha " + line + "): mude lá, em Layout → Avançado."; },
    gatedTag: "trocada pelo layout",
    gated: function (b, list) {
      var what = b.kind === "colors" ? "estas cores: " + list.join(", ") : b.kind === "roles" ? "as cores de cargo" : "a paleta base (wal:0–15)";
      var head = b.when ? "Com a opção " + b.when + " ligada (como ela começa), o layout troca " : b.unless ? "Com a opção " + b.unless + " desligada (como ela começa), o layout troca " : "Um bloco no texto do layout troca ";
      return head + what + " neste modo. " + (b.when ? "Os campos delas aqui embaixo só valem com a " + b.when + " desligada." : b.unless ? "Os campos delas aqui embaixo só valem com a " + b.unless + " ligada." : "Os campos delas aqui embaixo não têm efeito.") +
        " Para mudar o que o app mostra, edite o bloco na linha " + b.line + " do layout (Layout → Avançado).";
    },
    copied: "copiado", linkCopied: "Link copiado. Ele guarda o tema inteiro.", kdlCopied: ".kdl copiado.", downloaded: "Baixado: ",
    random: "Cores novas: ", schemes: { analogous: "análogas", complementary: "complementares", split: "complementares divididas", triadic: "tríade", mono: "monocromáticas" },
    imageDone: "Cores tiradas da imagem.", imageFail: "Não deu para ler essa imagem.", loaded: "Carregado: ", undoNothing: "Nada para desfazer.",
    importOk: "Tema importado.", started: "Começando de ", badHex: "Use #RGB, #RRGGBB ou #RRGGBBAA", linkFail: "Esse link não abriu: ",
    fileName: "Arquivo: ", preview: "Prévia do tema no modo ", dark: "escuro", light: "claro", defaultName: "meu-", importFallback: "tema",
  } : {
    groups: { surfaces: "Surfaces", text: "Text", accent: "Accent", status: "Status", bubbles: "Bubbles", shadow: "Shadow" },
    tok: { bg: "Window and conversation background", rail: "The darkest strip: servers, title and status bars", sidebar: "Channel and member lists", surface: "Cards and panels", elevated: "Inputs, popups, the item under the mouse", overlay: "Menus and dialogs", "code-bg": "Code blocks", text: "Main text", muted: "Secondary text: channels, timestamps", faint: "Hints, placeholder text, offline members", link: "Links", accent: "Buttons, selection, highlights", "accent-text": "Text on top of the accent", mention: "Mentions of you", selected: "Selected channel or row", hover: "Row under the mouse", border: "Borders and dividers", online: "Status: online", idle: "Status: idle", dnd: "Status: do not disturb", danger: "Errors, delete, unread counters", "bubble-self": "Your chat bubbles", "bubble-self-text": "Text in your bubbles", "bubble-other": "Other people's bubbles", shadow: "Shadows" },
    color: "color", opacity: "opacity", roles: "Role colors", rolesHint: "Usernames and server icons.", role: "role",
    palette: "Base palette (wal:0–15)", paletteHint: "The 16 colors the file calls wal:0 … wal:15. Some layouts use them directly.",
    recolor: "Recolor this mode from the palette", other: { dark: "Build a matching light mode", light: "Build a matching dark mode" },
    editing: { dark: "Editing the dark mode colors", light: "Editing the light mode colors" },
    fromImage: "From your image (nothing leaves the browser):", imgUse: "use as accent",
    def: "(theme default)", on: "on", off: "off", follows: "follows option ", none: "nothing to tweak in this layout",
    options: "Theme options", optionsHint: "What starts switched on. People can still change them in Settings → Appearance.", noOptions: "This layout has no options.",
    components: "Components", line: "line", when: "only with ", unless: "without ",
    advOk: "ok: the layout is valid", advErr: "error", kept: "the previous preview stays", errAt: "Error in the file, line ",
    custom: "custom", layoutNow: "Current layout: ",
    contrastOk: "Everything is readable in this mode.", issues: function (n) { return n === 1 ? "1 thing to look at in this mode." : n + " things to look at in this mode."; },
    on_: " on ", needs: "the app needs ", wcag: "WCAG AA minimum ", lifts: "The app lifts this color to ", liftsEnd: " when it loads the theme.", use: "Use ", fix: "Fix",
    otherMode: { dark: "light mode", light: "dark mode" }, otherIssues: function (m, n) { return n ? "In " + m + ": " + n + (n === 1 ? " thing." : " things.") : "In " + m + ": all readable."; },
    passes: "passes", fails: "fails", stuck: "Even text doesn't reach this. Raise the contrast of text first.",
    fromLayout: function (line) { return "This color comes from the layout (line " + line + "): change it there, in Layout → Advanced."; },
    gatedTag: "replaced by the layout",
    gated: function (b, list) {
      var what = b.kind === "colors" ? "these colors: " + list.join(", ") : b.kind === "roles" ? "the role colors" : "the base palette (wal:0–15)";
      var head = b.when ? "With option " + b.when + " on (as it starts), the layout replaces " : b.unless ? "With option " + b.unless + " off (as it starts), the layout replaces " : "A block in the layout text replaces ";
      return head + what + " in this mode. " + (b.when ? "Their fields below only count with " + b.when + " off." : b.unless ? "Their fields below only count with " + b.unless + " on." : "Their fields below have no effect.") +
        " To change what the app shows, edit the block at layout line " + b.line + " (Layout → Advanced).";
    },
    copied: "copied", linkCopied: "Link copied. It holds the whole theme.", kdlCopied: ".kdl copied.", downloaded: "Downloaded: ",
    random: "New colors: ", schemes: { analogous: "analogous", complementary: "complementary", split: "split complementary", triadic: "triadic", mono: "monochrome" },
    imageDone: "Colors taken from the image.", imageFail: "Couldn't read that image.", loaded: "Loaded: ", undoNothing: "Nothing to undo.",
    importOk: "Theme imported.", started: "Starting from ", badHex: "Use #RGB, #RRGGBB or #RRGGBBAA", linkFail: "That link didn't open: ",
    fileName: "File: ", preview: "Theme preview in ", dark: "dark", light: "light", defaultName: "my-", importFallback: "theme",
  };

  var GROUPS = [["surfaces", ["bg", "rail", "sidebar", "surface", "elevated", "overlay", "code-bg"]], ["text", ["text", "muted", "faint", "link"]],
    ["accent", ["accent", "accent-text", "mention", "selected", "hover", "border"]], ["status", ["online", "idle", "dnd", "danger"]],
    ["bubbles", ["bubble-self", "bubble-self-text", "bubble-other"]], ["shadow", ["shadow"]]];

  function $(sel, el) { return (el || box).querySelector(sel); }
  function $$(sel, el) { return Array.prototype.slice.call((el || box).querySelectorAll(sel)); }
  function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
  function h(tag, attrs, kids) {
    var el = document.createElement(tag);
    if (attrs) Object.keys(attrs).forEach(function (k) {
      if (k === "text") el.textContent = attrs[k];
      else if (k === "html") el.innerHTML = attrs[k];
      else if (k.slice(0, 2) === "on") el.addEventListener(k.slice(2), attrs[k]);
      else if (attrs[k] !== null && attrs[k] !== undefined && attrs[k] !== false) el.setAttribute(k, attrs[k] === true ? "" : attrs[k]);
    });
    (kids || []).forEach(function (k) { if (k) el.appendChild(typeof k === "string" ? document.createTextNode(k) : k); });
    return el;
  }

  // ------------------------------------------------------------ Estado ----
  var structures = {};
  DATA.order.forEach(function (n) { structures[n] = TB.fromSource(DATA.themes[n].src, { base: n, name: n }).structure; });
  function builtinStructure(n) { return TB.own(structures, n) ? structures[n] : undefined; }
  function startFrom(name) {
    var s = TB.fromSource(DATA.themes[name].src, { base: name, name: S.defaultName + name });
    s.meta.author = "";
    return s;
  }

  var state = null, undoStack = [], redoStack = [], lastKey = null, lastTime = 0, hashReady = false;
  var viewMode = html.dataset.mode === "light" ? "light" : "dark";
  var lastGood = null, imageSwatches = [];

  function set(fn, key) {
    var before = JSON.stringify(state), next = TB.clone(state);
    fn(next);
    var after = JSON.stringify(next);
    if (after === before) return;
    var now = Date.now();
    if (!key || key !== lastKey || now - lastTime > 1200) {
      undoStack.push(before);
      if (undoStack.length > 300) undoStack.shift();
    }
    lastKey = key || null;
    lastTime = now;
    redoStack = [];
    state = next;
    hashReady = true;
    changed();
  }
  function replace(next, msg) {
    if (state) {
      undoStack.push(JSON.stringify(state));
      redoStack = [];
    }
    lastKey = null;
    state = next;
    hashReady = true;
    changed();
    if (msg) say(msg);
  }
  function undo() {
    if (!undoStack.length) return say(S.undoNothing);
    redoStack.push(JSON.stringify(state));
    state = JSON.parse(undoStack.pop());
    lastKey = null;
    hashReady = true;
    changed();
  }
  function redo() {
    if (!redoStack.length) return;
    undoStack.push(JSON.stringify(state));
    state = JSON.parse(redoStack.pop());
    lastKey = null;
    changed();
  }

  var queued = false;
  function changed() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(function () {
      queued = false;
      refresh();
    });
  }

  // ------------------------------------------------------------- Aviso ----
  var toast = null, toastTimer = 0;
  function say(text) {
    if (!toast) {
      toast = h("div", { "class": "toast tb-toast", role: "status" });
      document.body.appendChild(toast);
    }
    toast.textContent = text;
    toast.classList.add("on");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toast.classList.remove("on"); }, 2200);
  }

  // ------------------------------------------------------------ Cores ----
  function readHex(v) {
    var t = String(v).trim().replace(/^#/, "");
    if (!/^([0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(t)) return null;
    return TB.normHex("#" + t);
  }
  function rgbPart(hex) { return TB.normHex(hex).slice(0, 7); }
  function alphaOf(hex) { return Math.round(TB.hexRgba(hex)[3] * 100); }
  function withAlpha(hex, pct) {
    var c = TB.hexRgba(hex);
    c[3] = Math.max(0, Math.min(100, pct)) / 100;
    return TB.toHex(c);
  }
  function swatchBg(hex) { return "linear-gradient(" + TB.cssColor(TB.hexRgba(hex)) + "," + TB.cssColor(TB.hexRgba(hex)) + "),var(--tb-check)"; }

  // Linha de um token: amostra (seletor nativo), nome, hex e opacidade.
  function tokenRow(tok) {
    var id = "tb-hex-" + tok;
    var pick = h("input", { type: "color", "aria-label": tok + " · " + S.color, "data-pick": tok });
    var sw = h("span", { "class": "tb-sw" }, [pick]);
    var hex = h("input", { id: id, "class": "tb-hex", type: "text", spellcheck: "false", autocomplete: "off", maxlength: "9", "data-hex": tok, "aria-describedby": id + "-d" });
    var al = h("input", { type: "range", min: "0", max: "100", step: "1", "class": "tb-alpha", "aria-label": tok + " · " + S.opacity, "data-alpha": tok });
    pick.addEventListener("input", function () {
      set(function (s) { s.colors[viewMode][tok] = withAlpha(pick.value, alphaOf(s.colors[viewMode][tok])); }, "pick:" + tok);
    });
    hex.addEventListener("input", function () {
      var v = readHex(hex.value);
      hex.setAttribute("aria-invalid", v ? "false" : "true");
      hex.title = v ? "" : S.badHex;
      if (v) set(function (s) { s.colors[viewMode][tok] = v; }, "hex:" + tok);
    });
    hex.addEventListener("blur", function () { hex.setAttribute("aria-invalid", "false"); hex.title = ""; fillColors(); });
    al.addEventListener("input", function () {
      set(function (s) { s.colors[viewMode][tok] = withAlpha(s.colors[viewMode][tok], +al.value); }, "alpha:" + tok);
    });
    return h("div", { "class": "tb-tok", "data-tok": tok }, [
      sw,
      h("label", { "for": id }, [h("code", { text: tok }), h("em", { "class": "tb-gtag", text: S.gatedTag, hidden: true }), h("small", { id: id + "-d", text: S.tok[tok] })]),
      hex, al,
    ]);
  }

  function swatchRow(kind, count, labelFn) {
    var row = h("div", { "class": "tb-swatches tb-" + kind });
    for (var i = 0; i < count; i++) (function (i) {
      var attrs = { type: "color", "aria-label": labelFn(i) };
      attrs["data-" + kind] = String(i);
      var pick = h("input", attrs);
      pick.addEventListener("input", function () {
        set(function (s) {
          var list = kind === "role" ? s.roles[viewMode] : s.palette[viewMode];
          list[i] = withAlpha(pick.value, alphaOf(list[i]));
        }, kind + ":" + i);
      });
      row.appendChild(h("span", { "class": "tb-sw", title: labelFn(i) }, [pick, kind === "pal" ? h("i", { text: String(i) }) : null]));
    })(i);
    return row;
  }

  var colorsPanel = $("#tb-p-colors");
  function buildColors() {
    colorsPanel.innerHTML = "";
    colorsPanel.appendChild(h("p", { "class": "tb-editing", "data-editing": "" }));
    colorsPanel.appendChild(h("div", { "class": "tb-gated", "data-gated": "", hidden: true }));
    colorsPanel.appendChild(h("div", { "class": "tb-img", "data-imgs": "", hidden: true }));
    GROUPS.forEach(function (g) {
      var fs = h("fieldset", { "class": "tb-group" }, [h("legend", { text: S.groups[g[0]] })]);
      g[1].forEach(function (tok) { fs.appendChild(tokenRow(tok)); });
      colorsPanel.appendChild(fs);
    });
    colorsPanel.appendChild(h("fieldset", { "class": "tb-group" }, [
      h("legend", { text: S.roles }), h("p", { "class": "tb-hint", text: S.rolesHint }),
      swatchRow("role", 8, function (i) { return S.role + " " + (i + 1); }),
    ]));
    var other = h("button", { type: "button", "class": "tb-b", "data-other": "" });
    other.addEventListener("click", function () {
      var gen = TB.generate(TB.seedFromColors(state.colors[viewMode])), o = viewMode === "dark" ? "light" : "dark";
      set(function (s) { s.colors[o] = gen.colors[o]; s.roles[o] = gen.roles[o]; });
      setMode(o);
    });
    var recolor = h("button", { type: "button", "class": "tb-b", text: S.recolor });
    recolor.addEventListener("click", function () {
      set(function (s) {
        var p = TB.fromPalette(s.palette[viewMode], viewMode);
        s.colors[viewMode] = p.colors;
        s.roles[viewMode] = p.roles;
      });
    });
    colorsPanel.appendChild(h("div", { "class": "tb-row" }, [other]));
    colorsPanel.appendChild(h("details", { "class": "tb-group tb-details" }, [
      h("summary", { text: S.palette }), h("p", { "class": "tb-hint", text: S.paletteHint }),
      swatchRow("pal", 16, function (i) { return "wal:" + i; }), h("div", { "class": "tb-row" }, [recolor]),
    ]));
  }

  function fillColors() {
    var c = state.colors[viewMode];
    $("[data-editing]").textContent = S.editing[viewMode];
    // Blocos do layout que trocam estas cores (os de uma opção, como `colors when=verde`).
    var blocks = TB.layoutColorBlocks(state, viewMode), gatedToks = {}, note = $("[data-gated]");
    note.innerHTML = "";
    blocks = blocks.filter(function (b) { return b.kind !== "colors" || b.tokens.length; });
    blocks.forEach(function (b) {
      b.tokens.forEach(function (t) { gatedToks[t] = true; });
      note.appendChild(h("p", { text: S.gated(b, b.tokens) }));
    });
    note.hidden = !blocks.length;
    $("[data-other]").textContent = S.other[viewMode];
    TB.TOKENS.forEach(function (tok) {
      var row = $('[data-tok="' + tok + '"]'), v = c[tok];
      row.querySelector(".tb-sw").style.background = swatchBg(v);
      row.classList.toggle("gated", !!gatedToks[tok]);
      row.querySelector(".tb-gtag").hidden = !gatedToks[tok];
      var pick = row.querySelector("[data-pick]"), hex = row.querySelector("[data-hex]"), al = row.querySelector("[data-alpha]");
      if (document.activeElement !== pick) pick.value = rgbPart(v);
      if (document.activeElement !== hex) hex.value = v;
      if (document.activeElement !== al) al.value = alphaOf(v);
    });
    $$("[data-role]").forEach(function (p) {
      var v = state.roles[viewMode][+p.dataset.role];
      p.parentElement.style.background = swatchBg(v);
      p.parentElement.title = S.role + " " + (+p.dataset.role + 1) + " · " + v;
      if (document.activeElement !== p) p.value = rgbPart(v);
    });
    $$("[data-pal]").forEach(function (p) {
      var v = state.palette[viewMode][+p.dataset.pal];
      p.parentElement.style.background = swatchBg(v);
      p.parentElement.title = "wal:" + p.dataset.pal + " · " + v;
      if (document.activeElement !== p) p.value = rgbPart(v);
    });
    var imgs = $("[data-imgs]");
    imgs.hidden = !imageSwatches.length;
    if (imageSwatches.length && !imgs.childNodes.length) {
      imgs.appendChild(h("span", { text: S.fromImage }));
      imageSwatches.forEach(function (c) {
        var b = h("button", { type: "button", "class": "tb-sw", style: "background:" + c.hex, title: c.hex + " · " + S.imgUse, "aria-label": c.hex + " · " + S.imgUse });
        b.addEventListener("click", function () {
          set(function (s) {
            var t = s.colors[viewMode], col = c.hex;
            t.accent = col;
            t["bubble-self"] = col;
            var on = TB.contrast([0, 0, 0, 1], TB.hexRgba(col)) >= TB.contrast([1, 1, 1, 1], TB.hexRgba(col)) ? "#000000" : "#ffffff";
            t["accent-text"] = on;
            t["bubble-self-text"] = on;
            t.selected = withAlpha(col, viewMode === "dark" ? 16 : 12);
          });
        });
        imgs.appendChild(b);
      });
    }
  }

  // ----------------------------------------------------- Tipografia ----
  var typePanel = $("#tb-p-type");
  function bindField(sel, apply, key) {
    var el = $(sel, typePanel) || $(sel);
    el.addEventListener(el.type === "checkbox" || el.tagName === "SELECT" ? "change" : "input", function () {
      var v = el.type === "checkbox" ? el.checked : el.value;
      set(function (s) { apply(s, v); }, key);
    });
    return el;
  }
  function num(v, lo, hi, d) {
    var n = parseFloat(v);
    return isFinite(n) ? Math.min(hi, Math.max(lo, n)) : d;
  }
  bindField("[data-f-ui]", function (s, v) { s.fonts.ui = v.trim() || "Inter"; }, "font-ui");
  bindField("[data-f-mono]", function (s, v) { s.fonts.mono = v.trim() || "JetBrains Mono"; }, "font-mono");
  bindField("[data-f-size]", function (s, v) { s.fonts.size = num(v, 6, 72, 16); }, "font-size");
  bindField("[data-f-size-n]", function (s, v) { s.fonts.size = num(v, 6, 72, 16); }, "font-size");
  bindField("[data-f-radius]", function (s, v) { s.radius = num(v, 0, 64, 6); }, "radius");
  bindField("[data-f-radius-n]", function (s, v) { s.radius = num(v, 0, 64, 6); }, "radius");
  bindField("[data-f-transparent]", function (s, v) { s.transparent = v; });
  bindField("[data-f-preview]", function (s, v) { s.meta.preview = v; });
  bindField("[data-m-name]", function (s, v) { s.meta.name = v; }, "name");
  bindField("[data-m-author]", function (s, v) { s.meta.author = v; }, "author");
  bindField("[data-m-desc]", function (s, v) { s.meta.desc = v; }, "desc");
  bindField("[data-m-desc-en]", function (s, v) { s.meta.descEn = v; }, "desc-en");

  function put(sel, v) {
    var el = $(sel);
    if (!el || document.activeElement === el) return;
    if (el.type === "checkbox") el.checked = !!v;
    else el.value = v;
  }
  function fillType() {
    put("[data-f-ui]", state.fonts.ui);
    put("[data-f-mono]", state.fonts.mono);
    put("[data-f-size]", state.fonts.size);
    put("[data-f-size-n]", state.fonts.size);
    put("[data-f-radius]", Math.min(24, state.radius));
    put("[data-f-radius-n]", state.radius);
    put("[data-f-transparent]", state.transparent);
    put("[data-f-preview]", state.meta.preview);
    put("[data-m-name]", state.meta.name);
    put("[data-m-author]", state.meta.author);
    put("[data-m-desc]", state.meta.desc);
    put("[data-m-desc-en]", state.meta.descEn);
  }

  // ---------------------------------------------------------- Layout ----
  var layoutPanel = $("#tb-p-layout");
  var adv = $("[data-adv]"), advStatus = $("[data-adv-status]"), advPre = $("[data-adv-hl]");
  var shownStructure = null;
  $("[data-layout-apply]").addEventListener("click", function () {
    var n = $("[data-layout-from]").value;
    set(function (s) { s.structure = structures[n]; s.layoutFrom = n; });
    say(S.layoutNow + n);
  });
  var advTimer = 0;
  adv.addEventListener("input", function () {
    advPre.innerHTML = hl(adv.value);
    clearTimeout(advTimer);
    advTimer = setTimeout(function () {
      set(function (s) {
        s.structure = adv.value;
        if (s.layoutFrom && structures[s.layoutFrom] !== s.structure) s.layoutFrom = null;
      }, "adv");
    }, 220);
  });
  adv.addEventListener("scroll", function () {
    advPre.parentElement.scrollTop = adv.scrollTop;
    advPre.parentElement.scrollLeft = adv.scrollLeft;
  });
  adv.addEventListener("keydown", function (e) {
    if (e.key === "Tab" && !e.shiftKey && !e.ctrlKey && !e.altKey) {
      e.preventDefault();
      adv.setRangeText("    ", adv.selectionStart, adv.selectionEnd, "end");
      adv.dispatchEvent(new Event("input"));
    }
  });

  function fieldControl(t, f) {
    var id = "tw-" + t.start + "-" + f.key, key = t.start + ":" + f.key, el;
    function apply(v) {
      set(function (s) {
        s.structure = TB.setProp(s.structure, t.start, f.key, v);
        if (s.layoutFrom && structures[s.layoutFrom] !== s.structure) s.layoutFrom = null;
      }, "tw:" + key);
    }
    if (f.kind === "num") {
      el = h("input", { id: id, type: "number", step: "1", min: "0", max: "4000", value: f.value === undefined ? "" : f.value, placeholder: "—", "data-tw": key });
      el.addEventListener("input", function () { apply(el.value === "" ? null : num(el.value, 0, 4000, 0)); });
    } else if (f.kind === "text") {
      el = h("input", { id: id, type: "text", spellcheck: "false", value: f.value === undefined ? "" : String(f.value), "data-tw": key });
      el.addEventListener("input", function () { apply(el.value === "" ? null : el.value); });
    } else {
      el = h("select", { id: id, "data-tw": key });
      var opts = [["", S.def]];
      if (f.kind === "bool") opts.push(["true", S.on], ["false", S.off]);
      else f.options.forEach(function (o) { opts.push([o, o]); });
      var cur = f.value === undefined ? "" : String(f.value);
      if (cur && !opts.some(function (o) { return o[0] === cur; })) opts.push([cur, cur.charAt(0) === "$" ? S.follows + cur.replace(/^\$!?/, (cur.charAt(1) === "!" ? "!" : "")) : cur]);
      opts.forEach(function (o) { el.appendChild(h("option", { value: o[0], text: o[1], selected: o[0] === cur })); });
      el.addEventListener("change", function () {
        var v = el.value;
        apply(v === "" ? null : v === "true" ? true : v === "false" ? false : v);
      });
    }
    return h("label", { "class": "tb-tw", "for": id }, [h("span", { text: f.key }), el]);
  }

  function buildLayout() {
    var holder = $("[data-tweaks]"), optBox = $("[data-options]");
    var focus = document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.tw : null;
    var caret = focus && document.activeElement.selectionStart;
    holder.innerHTML = "";
    optBox.innerHTML = "";
    var tweaks, opts;
    try {
      tweaks = TB.listTweaks(state.structure);
      opts = TB.structureOptions(state.structure);
    } catch (e) {
      holder.appendChild(h("p", { "class": "tb-hint tb-bad", text: S.advErr + ": " + (e.line || "?") + ":" + (e.column || "?") + ": " + TB.errorText(e, lang) }));
      return;
    }
    if (!opts.length) optBox.appendChild(h("p", { "class": "tb-hint", text: S.noOptions }));
    opts.forEach(function (o) {
      var id = "tb-opt-" + o.name, label = lang === "en" ? o.labelEn || o.label : o.label, desc = lang === "en" ? o.descEn || o.desc : o.desc;
      var cb = h("input", { type: "checkbox", id: id, checked: o.def });
      cb.addEventListener("change", function () {
        set(function (s) {
          var cur = TB.structureOptions(s.structure).filter(function (x) { return x.name === o.name; })[0];
          if (cur) s.structure = TB.setProp(s.structure, cur.node.start, "default", cb.checked);
          if (s.layoutFrom && structures[s.layoutFrom] !== s.structure) s.layoutFrom = null;
        });
      });
      optBox.appendChild(h("div", { "class": "tb-opt" }, [cb, h("label", { "for": id }, [h("strong", { text: label }), " ", h("code", { text: o.name }), desc ? h("small", { text: desc }) : null])]));
    });
    if (!tweaks.length) holder.appendChild(h("p", { "class": "tb-hint", text: S.none }));
    tweaks.forEach(function (t) {
      var cond = t.when ? " · " + S.when + t.when : t.unless ? " · " + S.unless + t.unless : "";
      var fs = h("fieldset", { "class": "tb-comp" + (t.component ? "" : " tb-box") }, [
        h("legend", {}, [h("code", { text: t.name }), h("small", { text: " " + S.line + " " + (t.line) + cond })]),
      ]);
      t.fields.forEach(function (f) { fs.appendChild(fieldControl(t, f)); });
      holder.appendChild(fs);
    });
    if (focus) {
      var el = holder.querySelector('[data-tw="' + focus + '"]');
      if (el) {
        el.focus();
        if (caret !== null && caret !== undefined && el.setSelectionRange && el.type === "text") el.setSelectionRange(caret, caret);
      }
    }
  }

  function fillLayout() {
    $("[data-layout-now]").textContent = S.layoutNow + (state.layoutFrom || S.custom);
    if (state.layoutFrom) $("[data-layout-from]").value = state.layoutFrom;
    if (shownStructure !== state.structure) {
      shownStructure = state.structure;
      buildLayout();
      if (document.activeElement !== adv) {
        adv.value = state.structure;
        advPre.innerHTML = hl(adv.value);
      }
    }
  }

  // ------------------------------------------------------- Realce KDL ----
  function hl(src) {
    var re = /(\/\/[^\n]*)|("(?:\\.|[^"\\\n])*")|(#true|#false|\b\d+(?:\.\d+)?\b)|([\w-]+(?==))|(^[ \t]*[\w-]+)/gm;
    var out = "", last = 0, m;
    while ((m = re.exec(src))) {
      if (m[0] === "") { re.lastIndex++; continue; }
      out += esc(src.slice(last, m.index));
      var c = m[1] ? "c" : m[2] ? "s" : m[3] ? "n" : m[4] ? "p" : "k";
      out += '<span class="t-' + c + '">' + esc(m[0]) + "</span>";
      last = m.index + m[0].length;
    }
    return out + esc(src.slice(last)) + "\n";
  }

  // ------------------------------------------------------- Contraste ----
  var contrastList = $("[data-contrast]"), contrastSum = $("[data-contrast-sum]");
  function fmtRatio(r) { return (Math.floor(r * 10) / 10).toFixed(1) + ":1"; }
  function renderContrast() {
    var rows = TB.contrastReport(state, viewMode), bad = rows.filter(function (r) { return r.fails.length; });
    var other = viewMode === "dark" ? "light" : "dark", otherBad = TB.contrastReport(state, other).filter(function (r) { return r.fails.length; }).length;
    contrastSum.textContent = (bad.length ? S.issues(bad.length) : S.contrastOk) + " " + S.otherIssues(S.otherMode[viewMode], otherBad);
    contrastList.innerHTML = "";
    // As cores como o app usa (um bloco do layout pode trocar algumas).
    var seen = TB.effectiveColors(state, viewMode).toks;
    rows.forEach(function (r) {
      var ok = !r.fails.length;
      // Passa ou não: o símbolo, a forma e um texto para leitor de tela, não só a cor.
      var li = h("li", { "class": ok ? "ok" : "bad" }, [
        h("span", { "class": "tb-mark" }, [h("span", { "aria-hidden": "true", text: ok ? "✓" : "!" }), h("span", { "class": "tb-sr", text: ok ? S.passes : S.fails })]),
        h("span", { "class": "tb-pair" }, [
          h("i", { "class": "tb-dot", style: "background:" + TB.cssColor(seen[r.fg]) }),
          h("code", { text: r.fg }), S.on_, h("span", { text: (ok ? r.backs : r.fails).join(", ") }),
        ]),
        h("span", { "class": "tb-ratio" }, [h("strong", { text: fmtRatio(r.ratio) }), h("small", { text: (r.app ? S.needs : S.wcag) + r.min + ":1" })]),
      ]);
      if (!ok) {
        if (r.app && r.lift) li.appendChild(h("p", { "class": "tb-lift", text: S.lifts + r.lift + S.liftsEnd }));
        if (r.gated) li.appendChild(h("p", { "class": "tb-lift", text: S.fromLayout(r.gated.line) }));
        else if (r.stuck) li.appendChild(h("p", { "class": "tb-lift", text: S.stuck }));
      }
      if (!ok && r.fix) {
        var b = h("button", { type: "button", "class": "tb-b tb-fix" }, [h("i", { "class": "tb-dot", style: "background:" + r.fix.value }), (r.app ? S.use + r.fix.value : S.fix + " · " + r.fix.value)]);
        b.addEventListener("click", function () { set(function (s) { s.colors[viewMode][r.fix.tok] = r.fix.value; }); });
        li.appendChild(b);
      }
      contrastList.appendChild(li);
    });
    $("[data-fixall]").hidden = !rows.some(function (r) { return r.fix; });
  }
  $("[data-fixall]").addEventListener("click", function () {
    set(function (s) {
      // Um conserto pode mudar o próximo (texto antes de muted e faint): repete até parar.
      for (var round = 0; round < 4; round++) {
        var fixes = TB.contrastReport(s, viewMode).filter(function (r) { return r.fails.length && r.fix; });
        if (!fixes.length) break;
        fixes.forEach(function (r) { s.colors[viewMode][r.fix.tok] = r.fix.value; });
      }
    });
  });

  // ---------------------------------------------------------- Prévia ----
  var screen = $("[data-screen]"), frame = $("[data-frame]"), errBox = $("[data-error]");
  function fit() {
    var w = screen.clientWidth;
    if (!w) return;
    frame.style.transform = "scale(" + w / W + ")";
  }
  if (window.ResizeObserver) new ResizeObserver(fit).observe(screen);
  else addEventListener("resize", fit);

  var CONTAINERS = { row: 1, column: 1, stack: 1 };
  function build(th, nd, parentAxis, toks) {
    var n = document.createElement("div");
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
    var b = document.createElement("div");
    b.className = "pv-b";
    // O nome do nó só vira classe se for um nome simples (um link pode trazer qualquer coisa).
    if (/^[a-z][a-z0-9-]{0,40}$/.test(nd.name)) b.classList.add("pv-k-" + nd.name);
    var mw = TB.num(nd, "max-width");
    if (mw !== null) { b.style.maxWidth = mw + "px"; b.style.marginLeft = b.style.marginRight = "auto"; }
    over.forEach(function (o) { b.style.setProperty("--t-" + o[0], o[1]); });
    var f = P.fontOf(TB.str(nd, "font"));
    if (f && nd.name !== "label") b.style.fontFamily = f;
    var box2 = TB.own(CONTAINERS, nd.name);
    P.paintBox(th, b, nd, local);
    if (box2) {
      b.classList.add("pv-" + (nd.name === "stack" ? "stack" : "flex"));
      if (nd.name !== "stack") b.style.flexDirection = nd.name === "row" ? "row" : "column";
      var pad = TB.num(nd, "padding") || 0, px = TB.num(nd, "padding-x"), py = TB.num(nd, "padding-y");
      px = px === null ? pad : px;
      py = py === null ? pad : py;
      b.style.padding = py + "px " + px + "px";
      if (nd.name !== "stack" && TB.num(nd, "gap")) b.style.gap = TB.num(nd, "gap") + "px";
      nd.kids.forEach(function (k) { if (P.visible(th, k)) b.appendChild(build(th, k, nd.name, local)); });
    } else {
      var c = document.createElement("div");
      c.className = "pv-c";
      var ix = TB.num(nd, "inset-x") || 0, iy = TB.num(nd, "inset-y") || 0;
      c.style.inset = iy + "px " + ix + "px";
      var inner = P.component(nd.name, th, nd, local);
      if (inner !== null) c.innerHTML = inner;
      else {
        c.className += " pv-bad";
        c.textContent = (lang === "pt" ? "componente desconhecido: " : "unknown component: ") + nd.name + " · " + S.line + " " + nd.line;
      }
      b.appendChild(c);
      if (P.flagOpt(th, nd, "autohide", false)) n.classList.add("pv-autohide");
    }
    n.appendChild(b);
    return n;
  }

  function renderPreview(th) {
    var f = frame;
    f.innerHTML = "";
    TB.TOKENS.forEach(function (k) { f.style.setProperty("--t-" + k, TB.cssColor(th.tokens[k])); });
    th.roles.forEach(function (c, i) { f.style.setProperty("--r" + i, TB.cssColor(c)); });
    f.style.setProperty("--f-ui", '"' + th.fontUi.replace(/["\\<>;{}]/g, "") + '",Inter,Archivo,system-ui,sans-serif');
    f.style.setProperty("--f-mono", '"' + th.fontMono.replace(/["\\<>;{}]/g, "") + '","JetBrains Mono",ui-monospace,monospace');
    f.style.setProperty("--pv-fs", th.fontSize * 0.9 + "px");
    f.style.setProperty("--pv-r", th.radius + "px");
    f.classList.toggle("pv-clear", th.transparent);
    f.classList.toggle("pv-light", th.mode === "light");
    f.style.setProperty("--pv-bg", TB.cssColor(th.tokens.bg));
    var root = th.layout.kids.filter(function (k) { return P.visible(th, k); })[0];
    if (!root) return;
    var tree = build(th, root, null, th.tokens);
    tree.classList.add("pv-root");
    f.appendChild(tree);
    screen.setAttribute("aria-label", S.preview + S[th.mode] + " · " + TB.slug(state.meta.name) + ".kdl");
  }

  // ---------------------------------------------------------- Tudo ----
  var code = $("[data-code]");
  function refresh() {
    var kdl = TB.toKdl(state, { url: DATA.url });
    var file = TB.slug(state.meta.name);
    $$("[data-fname]", document).forEach(function (e) { e.textContent = file + ".kdl"; });
    $$("[data-tname]", document).forEach(function (e) { e.textContent = file; });
    code.innerHTML = hl(kdl);
    $$("[data-mode]").forEach(function (b) { b.setAttribute("aria-checked", b.dataset.mode === viewMode ? "true" : "false"); });
    var th = null;
    try {
      th = TB.loadTheme(kdl, { mode: viewMode });
      lastGood = th;
      errBox.hidden = true;
      advStatus.className = "tb-adv-status";
      advStatus.textContent = S.advOk;
    } catch (e) {
      var head = kdl.slice(0, kdl.indexOf(state.structure)).split("\n").length - 1;
      var line = e.line ? e.line - head : 0;
      errBox.hidden = false;
      var why = TB.errorText(e, lang);
      errBox.textContent = S.errAt + (e.line || "?") + (e.column ? ":" + e.column : "") + ": " + why + " · " + S.kept;
      advStatus.className = "tb-adv-status err";
      advStatus.textContent = (line > 0 ? "layout:" + line + (e.column ? ":" + e.column : "") + ": " : "") + why + " · " + S.kept;
      th = lastGood;
    }
    if (th) renderPreview(th);
    fit();
    fillColors();
    fillType();
    fillLayout();
    renderContrast();
    $("[data-undo]").disabled = !undoStack.length;
    $("[data-redo]").disabled = !redoStack.length;
    scheduleHash();
  }

  function setMode(m) {
    viewMode = m;
    changed();
  }
  $$("[data-mode]").forEach(function (b) {
    b.addEventListener("click", function () { setMode(b.dataset.mode); });
    b.addEventListener("keydown", function (e) {
      if (e.key !== "ArrowLeft" && e.key !== "ArrowRight") return;
      e.preventDefault();
      var o = b.dataset.mode === "dark" ? "light" : "dark";
      setMode(o);
      $('[data-mode="' + o + '"]').focus();
    });
  });

  // Abas do painel, com as setas do teclado.
  var tabs = $$('[role="tab"]', $(".tb-tabs"));
  function selectTab(t) {
    tabs.forEach(function (x) {
      var on = x === t;
      x.setAttribute("aria-selected", on ? "true" : "false");
      x.tabIndex = on ? 0 : -1;
      document.getElementById(x.getAttribute("aria-controls")).hidden = !on;
    });
    try { localStorage.setItem("lc-tb-tab", t.id); } catch (e) {}
  }
  tabs.forEach(function (t, i) {
    t.addEventListener("click", function () { selectTab(t); });
    t.addEventListener("keydown", function (e) {
      var d = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
      if (e.key === "Home") d = -i;
      if (e.key === "End") d = tabs.length - 1 - i;
      if (!d) return;
      e.preventDefault();
      var n = tabs[(i + d + tabs.length) % tabs.length];
      selectTab(n);
      n.focus();
    });
  });
  // As abas das instruções (Linux, Windows): o mesmo jeito, num grupo à parte.
  $$("[data-ostabs]", document).forEach(function (group) {
    var list = $$('[role="tab"]', group);
    function pick(t) {
      list.forEach(function (x) {
        var on = x === t;
        x.setAttribute("aria-selected", on ? "true" : "false");
        x.tabIndex = on ? 0 : -1;
        document.getElementById(x.getAttribute("aria-controls")).hidden = !on;
      });
    }
    list.forEach(function (t, i) {
      t.addEventListener("click", function () { pick(t); });
      t.addEventListener("keydown", function (e) {
        var d = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
        if (!d) return;
        e.preventDefault();
        var n = list[(i + d + list.length) % list.length];
        pick(n);
        n.focus();
      });
    });
    if (/Windows/i.test(navigator.userAgent)) pick(list[1]);
  });

  // ------------------------------------------------------- Ações ----
  $("[data-start]").addEventListener("change", function (e) {
    var n = e.target.value;
    replace(startFrom(n), S.started + n);
  });
  $("[data-random]").addEventListener("click", function () {
    var seed = TB.randomSeed((Math.random() * 4294967295) >>> 0), gen = TB.generate(seed);
    imageSwatches = [];
    $("[data-imgs]").innerHTML = "";
    set(function (s) { s.palette = gen.palette; s.colors = gen.colors; s.roles = gen.roles; });
    say(S.random + (S.schemes[seed.scheme] || seed.scheme));
  });
  var imgInput = $("[data-image-file]");
  $("[data-image]").addEventListener("click", function () { imgInput.click(); });
  imgInput.addEventListener("change", function () {
    var file = imgInput.files && imgInput.files[0];
    imgInput.value = "";
    if (!file) return;
    var url = URL.createObjectURL(file), img = new Image();
    img.onload = function () {
      try {
        var k = Math.min(1, 96 / Math.max(img.naturalWidth, img.naturalHeight)), cw = Math.max(1, Math.round(img.naturalWidth * k)), ch = Math.max(1, Math.round(img.naturalHeight * k));
        var cv = document.createElement("canvas");
        cv.width = cw;
        cv.height = ch;
        var g = cv.getContext("2d");
        g.drawImage(img, 0, 0, cw, ch);
        var colors = TB.imageColors(g.getImageData(0, 0, cw, ch).data, 8, 5);
        if (!colors.length) throw new Error("empty");
        var gen = TB.generate(TB.seedFromImage(colors));
        imageSwatches = colors;
        $("[data-imgs]").innerHTML = "";
        set(function (s) { s.palette = gen.palette; s.colors = gen.colors; s.roles = gen.roles; });
        say(S.imageDone);
      } catch (e) {
        say(S.imageFail);
      }
      URL.revokeObjectURL(url);
    };
    img.onerror = function () { URL.revokeObjectURL(url); say(S.imageFail); };
    img.src = url;
  });
  $("[data-undo]").addEventListener("click", undo);
  $("[data-redo]").addEventListener("click", redo);
  document.addEventListener("keydown", function (e) {
    var t = e.target, typing = t && (t.tagName === "TEXTAREA" || (t.tagName === "INPUT" && /^(text|number|search)$/.test(t.type)));
    if (typing || !(e.ctrlKey || e.metaKey) || e.altKey) return;
    var k = e.key.toLowerCase();
    if (k === "z" && !e.shiftKey) { e.preventDefault(); undo(); }
    else if ((k === "z" && e.shiftKey) || k === "y") { e.preventDefault(); redo(); }
  });

  function copyText(text, done) {
    function fallback() {
      var ta = h("textarea", { style: "position:fixed;left:-9999px;top:0", "aria-hidden": "true" });
      ta.value = text;
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand("copy"); } catch (e) {}
      ta.remove();
      done();
    }
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, fallback);
    else fallback();
  }
  function shareUrl() {
    return TB.encode(state, builtinStructure).then(function (tok) { return location.href.split("#")[0] + "#t=" + tok; });
  }
  $("[data-share]").addEventListener("click", function () {
    shareUrl().then(function (u) {
      history.replaceState(null, "", u);
      copyText(u, function () { say(S.linkCopied); });
    });
  });
  $("[data-copy-kdl]").addEventListener("click", function () {
    copyText(TB.toKdl(state, { url: DATA.url }), function () { say(S.kdlCopied); });
  });
  $("[data-download]").addEventListener("click", function () {
    var name = TB.slug(state.meta.name) + ".kdl", blob = new Blob([TB.toKdl(state, { url: DATA.url })], { type: "text/plain;charset=utf-8" });
    var a = h("a", { href: URL.createObjectURL(blob), download: name });
    document.body.appendChild(a);
    a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 500);
    say(S.downloaded + name);
  });

  // Importar: colar ou escolher um .kdl.
  var dlg = $("[data-import-dialog]"), dlgText = $("[data-import-text]", dlg), dlgErr = $("[data-import-error]", dlg), dlgFile = $("[data-import-file]", dlg);
  var importName = "";
  $("[data-import]").addEventListener("click", function () {
    dlgErr.textContent = "";
    if (dlg.showModal) dlg.showModal(); else dlg.setAttribute("open", "");
    dlgText.focus();
  });
  dlgFile.addEventListener("change", function () {
    var f = dlgFile.files && dlgFile.files[0];
    if (!f) return;
    importName = f.name.replace(/\.kdl$/i, "");
    f.text().then(function (t) { dlgText.value = t; dlgErr.textContent = ""; });
  });
  $("[data-import-cancel]", dlg).addEventListener("click", function () { dlg.close ? dlg.close() : dlg.removeAttribute("open"); });
  $("[data-import-load]", dlg).addEventListener("click", function () {
    var src = dlgText.value;
    try {
      var next = TB.fromSource(src, { name: importName });
      TB.loadTheme(TB.toKdl(next), { mode: "dark" });
      next.base = null;
      next.layoutFrom = null;
      DATA.order.forEach(function (n) { if (structures[n] === next.structure) next.layoutFrom = n; });
      importName = "";
      dlg.close ? dlg.close() : dlg.removeAttribute("open");
      replace(next, S.importOk);
    } catch (e) {
      dlgErr.textContent = (importName || S.importFallback) + ".kdl:" + (e.line || "?") + (e.column ? ":" + e.column : "") + ": " + TB.errorText(e, lang);
    }
  });

  // O endereço guarda o tema: recarregar a página não perde nada.
  var hashTimer = 0;
  function scheduleHash() {
    if (!hashReady) return;
    clearTimeout(hashTimer);
    hashTimer = setTimeout(function () {
      TB.encode(state, builtinStructure).then(function (tok) { history.replaceState(null, "", "#t=" + tok); });
    }, 700);
  }

  function boot() {
    buildColors();
    var hash = location.hash.slice(1), m;
    var first = DATA.order.indexOf(html.dataset.theme) >= 0 ? html.dataset.theme : "orbital";
    try {
      var t = localStorage.getItem("lc-tb-tab");
      if (t && document.getElementById(t)) selectTab(document.getElementById(t));
    } catch (e) {}
    if ((m = /^t=(.+)$/.exec(hash))) {
      TB.decode(decodeURIComponent(m[1]), builtinStructure).then(function (s) {
        state = s;
        $("[data-start]").value = s.base && DATA.order.indexOf(s.base) >= 0 ? s.base : first;
        hashReady = true;
        changed();
      }, function (e) {
        state = startFrom(first);
        hashReady = true;
        changed();
        say(S.linkFail + TB.errorText(e, lang));
      });
      return;
    }
    if ((m = /^base=([a-z]+)$/.exec(hash)) && DATA.order.indexOf(m[1]) >= 0) first = m[1];
    state = startFrom(first);
    $("[data-start]").value = first;
    changed();
  }
  boot();
})();
