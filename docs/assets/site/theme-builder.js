// O criador de temas: controles, desfazer/refazer, a prévia e a exportação.
// As contas (KDL, cores, carregamento do tema, geração) ficam em theme-builder-core.js,
// o mesmo arquivo que tools/theme_builder_test.js testa.
(function () {
  var box = document.querySelector("[data-builder]");
  if (!box || !window.LC_TB) return;
  var TB = window.LC_TB;
  var html = document.documentElement;
  var lang = html.dataset.lang === "pt" ? "pt" : "en";
  var DATA = JSON.parse(document.getElementById("tb-data").textContent);
  var W = 1280, H = 800;

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
    copied: "copiado", linkCopied: "Link copiado. Ele guarda o tema inteiro.", kdlCopied: ".kdl copiado.", downloaded: "Baixado: ",
    random: "Cores novas: ", schemes: { analogous: "análogas", complementary: "complementares", split: "complementares divididas", triadic: "tríade", mono: "monocromáticas" },
    imageDone: "Cores tiradas da imagem.", imageFail: "Não deu para ler essa imagem.", loaded: "Carregado: ", undoNothing: "Nada para desfazer.",
    importOk: "Tema importado.", started: "Começando de ", badHex: "Use #RGB, #RRGGBB ou #RRGGBBAA", linkFail: "Esse link não abriu: ",
    fileName: "Arquivo: ", preview: "Prévia do tema no modo ", dark: "escuro", light: "claro", defaultName: "meu-",
    msg: { general: "geral", topic: "conversa livre, sem spam", server: "larperCord dev", today: "Hoje às ", newm: "NOVAS MENSAGENS", place: "Conversar em #geral", typing: "ana.exe está digitando…", delivered: "Entregue", search: "Buscar", online: "Online" },
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
    copied: "copied", linkCopied: "Link copied. It holds the whole theme.", kdlCopied: ".kdl copied.", downloaded: "Downloaded: ",
    random: "New colors: ", schemes: { analogous: "analogous", complementary: "complementary", split: "split complementary", triadic: "triadic", mono: "monochrome" },
    imageDone: "Colors taken from the image.", imageFail: "Couldn't read that image.", loaded: "Loaded: ", undoNothing: "Nothing to undo.",
    importOk: "Theme imported.", started: "Starting from ", badHex: "Use #RGB, #RRGGBB or #RRGGBBAA", linkFail: "That link didn't open: ",
    fileName: "File: ", preview: "Theme preview in ", dark: "dark", light: "light", defaultName: "my-",
    msg: { general: "general", topic: "free talk, no spam", server: "larperCord dev", today: "Today at ", newm: "NEW MESSAGES", place: "Message #general", typing: "ana.exe is typing…", delivered: "Delivered", search: "Search", online: "Online" },
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
  function builtinStructure(n) { return structures[n]; }
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
      h("label", { "for": id }, [h("code", { text: tok }), h("small", { id: id + "-d", text: S.tok[tok] })]),
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
    $("[data-other]").textContent = S.other[viewMode];
    TB.TOKENS.forEach(function (tok) {
      var row = $('[data-tok="' + tok + '"]'), v = c[tok];
      row.querySelector(".tb-sw").style.background = swatchBg(v);
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
      holder.appendChild(h("p", { "class": "tb-hint tb-bad", text: S.advErr + ": " + e.line + ":" + e.column + ": " + e.message }));
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
    rows.forEach(function (r) {
      var ok = !r.fails.length;
      var li = h("li", { "class": ok ? "ok" : "bad" }, [
        h("span", { "class": "tb-mark", "aria-hidden": "true", text: ok ? "✓" : "!" }),
        h("span", { "class": "tb-pair" }, [
          h("i", { "class": "tb-dot", style: "background:" + TB.cssColor(TB.hexRgba(state.colors[viewMode][r.fg])) }),
          h("code", { text: r.fg }), S.on_, h("span", { text: (ok ? r.backs : r.fails).join(", ") }),
        ]),
        h("span", { "class": "tb-ratio" }, [h("strong", { text: fmtRatio(r.ratio) }), h("small", { text: (r.app ? S.needs : S.wcag) + r.min + ":1" })]),
      ]);
      if (!ok && r.fix) {
        if (r.app) li.appendChild(h("p", { "class": "tb-lift", text: S.lifts + r.fix.value + S.liftsEnd }));
        var b = h("button", { type: "button", "class": "tb-b tb-fix" }, [h("i", { "class": "tb-dot", style: "background:" + r.fix.value }), (r.app ? S.use + r.fix.value : S.fix + " · " + r.fix.value)]);
        b.addEventListener("click", function () { set(function (s) { s.colors[viewMode][r.fix.tok] = r.fix.value; }); });
        li.appendChild(b);
      }
      contrastList.appendChild(li);
    });
    $("[data-fixall]").hidden = !bad.length;
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
  function ic(n, cls) { return '<svg class="pv-ic' + (cls ? " " + cls : "") + '" viewBox="0 0 24 24" aria-hidden="true"><path d="' + IC[n] + '"/></svg>'; }

  var M = S.msg;
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
  var CHAT = lang === "pt" ? {
    a: "o tema novo ficou bom demais", b: "<b>urgente</b>: alguém tem carregador usb-c de notebook aí?", c: "é só um arquivo .kdl. salva e a janela muda.",
    d: "e dá pra mexer no layout também?", e: "dá. a largura, a ordem, tudo.", embedT: "Linguagem de Programação Zig", embedD: "Zig é uma linguagem de uso geral para software <b>robusto</b>, <b>ótimo</b> e <b>reutilizável</b>.",
  } : {
    a: "the new theme looks so good", b: "<b>urgent</b>: anyone got a usb-c laptop charger in the room?", c: "it's just a .kdl file. save it and the window changes.",
    d: "can you move the layout around too?", e: "yep. widths, order, all of it.", embedT: "Zig Programming Language", embedD: "Zig is a general-purpose language for <b>robust</b>, <b>optimal</b> and <b>reusable</b> software.",
  };

  // Contexto de um nó: tokens efetivos (com os c-… dos pais), opções e o tema.
  function evalCss(th, expr, toks, bare) {
    try { return TB.cssColor(TB.evalColor(expr, th.palette, function (n) { return toks[n]; }, bare)); } catch (e) { return null; }
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
  function visible(th, nd) {
    var p = function (k) { return TB.pv(nd, k); };
    if (TB.flag(nd, "show") === false) return false;
    if (typeof p("hide-below") === "number" && W < p("hide-below")) return false;
    if (typeof p("hide-below-height") === "number" && H < p("hide-below-height")) return false;
    if (typeof p("only-below-height") === "number" && H >= p("only-below-height")) return false;
    var w = TB.str(nd, "when"), u = TB.str(nd, "unless");
    if (w !== null && !th.values[w]) return false;
    if (u !== null && th.values[u]) return false;
    return true;
  }
  function fontOf(f) {
    if (!f) return null;
    if (f === "mono") return "var(--f-mono)";
    if (f === "ui") return "var(--f-ui)";
    return '"' + String(f).replace(/["\\]/g, "") + '",var(--f-ui)';
  }

  // O ruído do grão: um SVG pequeno, gerado aqui (data: URI, sem pedir nada à rede).
  var grainCache = {};
  function grainUrl(css) {
    if (grainCache[css]) return grainCache[css];
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
    return "linear-gradient(" + (angle + 90) + "deg," + parts.join(",") + ")";
  }

  // Fundo, borda e sombras de um nó: o estilo nomeado primeiro, depois o próprio nó.
  function paintBox(th, el, nd, toks, isComp) {
    var layers = [], shadows = [], radius = null, corners = null, borderGrad = null, borderW = 1, sheen = false;
    var st = TB.str(nd, "style") ? th.styles[TB.str(nd, "style")] : null;
    function fills(src, isStyle) {
      var bg = TB.str(src, "bg");
      if (bg !== null) {
        var c = isStyle ? evalCss(th, bg, toks, false) : evalCss(th, bg, toks, true);
        if (c) layers.push("linear-gradient(" + c + "," + c + ")");
      }
      var g = TB.str(src, "gradient");
      if (g !== null) { var gc = gradientCss(th, g, TB.num(src, "gradient-angle") === null ? 90 : TB.num(src, "gradient-angle"), toks); if (gc) layers.push(gc); }
      var pat = TB.str(src, "pattern"), pc = TB.str(src, "pattern-color");
      if (pat && pc) {
        var c2 = evalCss(th, pc, toks, true), size = Math.max(2, Math.min(128, TB.num(src, "pattern-size") || 16)), pw = Math.max(0.5, Math.min(32, TB.num(src, "pattern-width") || 1));
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
        var vc = evalCss(th, vg, toks, true), vs = TB.num(src, "vignette-size");
        vs = vs === null ? 0.55 : Math.max(0, Math.min(0.95, vs));
        if (vc) layers.push("radial-gradient(farthest-corner,transparent " + Math.round(vs * 100) + "%," + vc + ")");
      }
      var ds = TB.str(src, "drop-shadow");
      if (ds !== null) {
        var dc = evalCss(th, ds, toks, true), dsz = TB.num(src, "drop-shadow-size"), dy = TB.num(src, "drop-shadow-y");
        if (dc) shadows.push("0 " + (dy === null ? 10 : dy) + "px " + (dsz === null ? 32 : Math.max(1, dsz)) + "px " + dc);
      }
      var is = TB.str(src, "inner-shadow");
      if (is !== null) {
        var ic2 = evalCss(th, is, toks, true), isz = TB.num(src, "inner-shadow-size");
        if (ic2) shadows.push("inset 0 0 " + (isz === null ? 14 : isz) + "px " + ic2);
      }
      var bgr = TB.str(src, "border-gradient");
      if (bgr !== null) {
        borderGrad = gradientCss(th, bgr, TB.num(src, "border-gradient-angle") === null ? 90 : TB.num(src, "border-gradient-angle"), toks);
        borderW = TB.num(src, "border-width") || 1;
      }
      var bw0 = TB.num(src, "border-width") || 1;
      var bd = TB.str(src, "border");
      if (bd !== null) { var bc = evalCss(th, bd, toks, !isStyle); if (bc) shadows.push("inset 0 0 0 " + bw0 + "px " + bc); }
      [["border-top", "0 W"], ["border-right", "-W 0"], ["border-bottom", "0 -W"], ["border-left", "W 0"]].forEach(function (sd) {
        var v = TB.str(src, sd[0]);
        if (v === null) return;
        var c3 = evalCss(th, v, toks, true), w = TB.num(src, sd[0] + "-width");
        w = w === null ? bw0 : w;
        if (c3) shadows.push("inset " + sd[1].replace(/W/g, w + "px") + " 0 0 " + c3);
      });
      if (isStyle && TB.num(src, "shadow")) shadows.push("0 " + TB.num(src, "shadow") / 2 + "px " + TB.num(src, "shadow") + "px " + TB.cssColor(toks.shadow));
      if (TB.num(src, "radius") !== null) radius = TB.num(src, "radius");
      if (TB.str(src, "corners")) corners = TB.str(src, "corners");
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

  function av(name, role, cls, size) {
    var st = "--c:var(--r" + role + ")" + (size ? ";width:" + size + "px;height:" + size + "px;font-size:" + Math.round(size * 0.42) + "px" : "");
    return '<i class="pv-av ' + (cls || "") + '" style="' + st + '">' + esc(name.charAt(0).toUpperCase()) + "</i>";
  }

  var C = {};
  C["guild-bar"] = function (th, nd) {
    var variant = TB.str(nd, "variant") || "bar", shape = TB.str(nd, "shape") || "circle", size = TB.num(nd, "size") || 48;
    var style = TB.str(nd, "icon-style") || "fill", horiz = TB.str(nd, "orientation") === "horizontal" || variant === "dock";
    var labels = flagOpt(th, nd, "labels", variant === "list"), home = flagOpt(th, nd, "home", true), ind = flagOpt(th, nd, "indicators", true);
    if (shape === "text") {
      return '<div class="pv-gtext">' + SERVERS.map(function (s, i) { return '<span class="' + (i ? "" : "on") + '">' + (i + 1) + ":" + esc(s[1]) + "</span>"; }).join("") + "</div>";
    }
    var icons = SERVERS.map(function (s, i) {
      return '<span class="pv-gi' + (i ? "" : " on") + '"><b class="pv-gico ' + shape + " " + style + '" style="--c:var(--r' + s[2] + ");width:" + size + "px;height:" + size + "px;font-size:" + Math.round(size * 0.32) + 'px">' + esc(s[0]) +
        (i === 0 ? '<em class="pv-badge">2</em>' : "") + "</b>" + (labels ? "<span>" + esc(s[1]) + "</span>" : "") + "</span>";
    }).join("");
    var homeEl = home ? '<span class="pv-gi"><b class="pv-gico ' + shape + ' home" style="width:' + size + "px;height:" + size + 'px">' + ic("chat") + "</b>" + (labels ? "<span>Home</span>" : "") + "</span><hr>" : "";
    return '<div class="pv-guild ' + variant + (horiz ? " pv-hz" : "") + (labels ? " lab" : "") + (ind ? " ind" : "") + '">' + homeEl + icons + "</div>";
  };
  C["channel-list"] = function (th, nd) {
    var v = TB.str(nd, "variant") || "discord", out = "";
    if (flagOpt(th, nd, "banner", false)) out += '<div class="pv-banner"><b>' + esc(M.server) + "</b>" + ic("chev") + "</div>";
    else if (flagOpt(th, nd, "header", true)) out += '<div class="pv-shead"><b>' + esc(M.server) + "</b>" + ic("chev") + "</div>";
    var rows = "";
    CHANNELS.forEach(function (cat) {
      rows += "<small>" + ic("chev", "s") + cat[0] + "</small>";
      cat[1].forEach(function (c, i) {
        var pre = v === "tree" ? '<u class="pv-tree">' + (i === cat[1].length - 1 ? "└─" : "├─") + "</u>" : ic("hash");
        rows += '<span class="pv-ch' + (c[3] ? " on" : "") + (c[1] ? " unread" : "") + '">' + pre + "<em>" + esc(c[0]) + "</em>" + (c[2] ? '<b class="pv-badge">1</b>' : "") + "</span>";
      });
    });
    rows += "<small>" + ic("chev", "s") + VOICE[0] + "</small>";
    rows += '<span class="pv-ch">' + ic("speaker") + "<em>" + esc(VOICE[1]) + "</em></span>";
    [["ana.exe", 4], ["duda", 2], ["kaique", 3]].forEach(function (u) { rows += '<span class="pv-vu">' + av(u[0], u[1], "", 20) + "<em>" + u[0] + "</em>" + ic("mic") + "</span>"; });
    return '<div class="pv-chan ' + v + '">' + out + '<div class="pv-chrows">' + rows + "</div></div>";
  };
  C["user-panel"] = function (th, nd) {
    if (TB.str(nd, "variant") === "tty") return '<div class="pv-user tty"><span><i class="pv-st on"></i>rsha</span><span class="pv-tty">M&nbsp;&nbsp;F&nbsp;&nbsp;' + ic("gear") + "</span></div>";
    return '<div class="pv-user"><span class="pv-avs">' + av("rsha", 0, "", 32) + '<i class="pv-st on"></i></span><span class="pv-who"><b>rsha</b><small>' + esc(M.online) + "</small></span>" + ic("mic") + ic("head") + ic("gear") + "</div>";
  };
  C.header = function (th, nd) {
    var v = TB.str(nd, "variant") || "discord", div = flagOpt(th, nd, "divider", true) ? " div" : "";
    var icons = '<span class="pv-hicons">' + ic("pin") + ic("inbox") + ic("mark") + (v === "discord" ? ic("search") + ic("users") + '<span class="pv-hsearch">' + esc(M.search) + " Ctrl+K" + ic("search") + "</span>" : "") + "</span>";
    if (v === "tty") return '<div class="pv-head tty' + div + '"><b>[#' + esc(M.general) + "]</b><span>" + esc(M.topic) + "</span></div>";
    if (v === "minimal") return '<div class="pv-head min' + div + '"><span class="pv-ht"><b>' + esc(M.general) + "</b><small>" + esc(M.server) + " · " + esc(M.topic) + "</small></span>" + icons + "</div>";
    return '<div class="pv-head' + div + '">' + ic("hash") + "<b>" + esc(M.general) + '</b><i class="pv-hdiv"></i><span>' + esc(M.topic) + "</span>" + icons + "</div>";
  };
  C.tabs = function (th, nd) {
    var v = TB.str(nd, "variant") || "pills", t = ["#" + M.general, "#zig", "#memes"];
    if (v === "tty") return '<div class="pv-tabs tty">' + t.map(function (x, i) { return "<span" + (i ? "" : ' class="on"') + ">" + (i + 1) + " " + esc(x) + "</span>"; }).join("") + "</div>";
    return '<div class="pv-tabs ' + v + '">' + t.map(function (x, i) { return "<span" + (i ? "" : ' class="on"') + '><u>LC</u>' + esc(x) + (i ? "" : ic("x")) + "</span>"; }).join("") + ic("plus") + "</div>";
  };
  C.messages = function (th, nd) {
    var v = TB.str(nd, "variant") || "cozy", avatar = TB.str(nd, "avatar") || "circle", size = TB.num(nd, "avatar-size") || 40;
    var gap = TB.num(nd, "spacing"), fs = TB.num(nd, "font-size");
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
      list.forEach(function (m, i) {
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
        var re = m.re ? '<span class="pv-re">' + m.re.map(function (n, i) { return '<em class="' + (i ? "" : "mine") + '"><i class="pv-face s' + (i ? " pv-f2" : "") + '"></i>' + n + "</em>"; }).join("") + "</span>" : "";
        var a = avatar === "none" ? "" : av(m.who, m.r, avatar, size);
        out += '<div class="pv-msg' + (m.men ? " men" : "") + (avatar === "none" ? " noav" : "") + '">' + a + '<div class="pv-mb"><div class="pv-mh"><b style="color:var(--r' + m.r + ')">' + esc(m.who) + "</b><time>" + esc(M.today) + m.t + "</time></div>" + body + re + "</div></div>";
      });
    }
    return '<div class="pv-msgs ' + v + (ruled ? " ruled" : "") + (margin ? " margin" : "") + '" ' + styleAttr + '><div class="pv-mlist">' + out + "</div></div>";
  };
  C.composer = function (th, nd) {
    var v = TB.str(nd, "variant") || "box";
    if (v === "prompt") return '<div class="pv-comp prompt"><div><b>rsha@#' + esc(M.general) + ' ❯</b><i class="pv-caret"></i><span class="pv-sp"></span><u>[+]</u>' + ic("smile") + "</div></div>";
    return '<div class="pv-comp ' + v + '"><div>' + ic("plus", "pv-cplus") + "<span>" + esc(M.place) + '</span><span class="pv-sp"></span>' + ic("smile") + "</div></div>";
  };
  C["member-list"] = function (th, nd) {
    var tty = TB.str(nd, "variant") === "tty", out = "";
    MEMBERS.forEach(function (g) {
      out += "<small>" + esc(g[0]) + "</small>";
      g[1].forEach(function (m) {
        var off = m[2] === "off";
        if (tty) out += '<span class="pv-mem tty' + (off ? " off" : "") + '"><u class="' + m[2] + '">' + { on: "●", idle: "◐", dnd: "⊘", off: "○" }[m[2]] + '</u><b style="' + (off ? "" : "color:var(--r" + m[1] + ")") + '">' + esc(m[0]) + "</b></span>";
        else out += '<span class="pv-mem' + (off ? " off" : "") + '"><span class="pv-avs">' + av(m[0], m[1], "", 32) + '<i class="pv-st ' + m[2] + '"></i></span><span class="pv-who"><b style="' + (off ? "" : "color:var(--r" + m[1] + ")") + '">' + esc(m[0]) + "</b>" + (m[3] ? "<small>" + esc(m[3]) + "</small>" : "") + "</span></span>";
      });
    });
    return '<div class="pv-members' + (tty ? " tty" : "") + '">' + out + "</div>";
  };
  C["status-bar"] = function (th, nd) {
    var v = TB.str(nd, "variant") || "pills", items = String(TB.str(nd, "items") || "conn ping ram spacer theme keys clock").split(/\s+/);
    var map = { conn: '<i class="pv-st on"></i>demo', ping: "~0 ms", ram: "26.7 MB", frame: "0.4 ms", voice: "", theme: esc(TB.slug(state.meta.name)), keys: "Ctrl+K", clock: "07:05",
      me: av("rsha", 0, "", 16) + "rsha", mic: ic("mic"), deaf: ic("head") };
    return '<div class="pv-status ' + v + '">' + items.map(function (x) {
      if (x === "spacer") return '<span class="pv-sp"></span>';
      return map[x] ? "<span>" + map[x] + "</span>" : "";
    }).join("") + "</div>";
  };
  var WGT = { regular: 400, medium: 500, semibold: 600, bold: 700 };
  function textColor(th, v, toks) {
    if (v === null) return null;
    if (TB.tokenName(v)) return "var(--t-" + TB.tokenName(v) + ")";
    return evalCss(th, v, toks, true);
  }
  C.label = function (th, nd, toks) {
    var fx = nd.kids.some(function (k) { return k.name === "span"; }) || ["tracking", "shadow", "outline", "text-gradient", "text-en"].some(function (k) { return TB.prop(nd, k); });
    var size = TB.num(nd, "size") || 14, weight = TB.str(nd, "weight") || (fx ? "semibold" : "regular");
    var st = "font-size:" + size * 0.9 + "px;font-weight:" + (WGT[weight] || 400) + ";" + (weight === "italic" ? "font-style:italic;" : "");
    var col = textColor(th, TB.str(nd, "color"), toks);
    if (col) st += "color:" + col + ";";
    if (TB.num(nd, "tracking") !== null) st += "letter-spacing:" + TB.num(nd, "tracking") + "px;";
    var f = fontOf(TB.str(nd, "font"));
    if (f) st += "font-family:" + f + ";";
    var sh = TB.str(nd, "shadow");
    if (sh) {
      var sc = evalCss(th, sh, toks, true), blur = TB.num(nd, "shadow-blur") || 0;
      if (sc) st += "text-shadow:" + (TB.num(nd, "shadow-x") || 0) + "px " + (TB.num(nd, "shadow-y") === null ? (blur ? 0 : 1) : TB.num(nd, "shadow-y")) + "px " + blur * 3 + "px " + sc + ";";
    }
    var ol = TB.str(nd, "outline");
    if (ol) { var oc = evalCss(th, ol, toks, true); if (oc) st += "-webkit-text-stroke:" + (TB.num(nd, "outline-width") || 1) + "px " + oc + ";paint-order:stroke fill;"; }
    var tg = TB.str(nd, "text-gradient"), grad = tg ? gradientCss(th, tg, TB.num(nd, "text-gradient-angle") || 0, toks) : null;
    var align = TB.str(nd, "align") || "left";
    var spans = nd.kids.filter(function (k) { return k.name === "span"; });
    var inner;
    if (spans.length) {
      inner = spans.map(function (sp) {
        var t = lang === "en" && (TB.str(sp, "en") || TB.str(sp, "text-en")) ? TB.str(sp, "en") || TB.str(sp, "text-en") : typeof TB.arg(sp, 0) === "string" ? TB.arg(sp, 0) : TB.str(sp, "text") || "";
        var s2 = "";
        if (TB.num(sp, "size") !== null) s2 += "font-size:" + TB.num(sp, "size") * 0.9 + "px;";
        var w2 = TB.str(sp, "weight");
        if (w2) s2 += "font-weight:" + (WGT[w2] || 400) + ";" + (w2 === "italic" ? "font-style:italic;" : "");
        var c2 = textColor(th, TB.str(sp, "color"), toks);
        if (c2) s2 += "color:" + c2 + ";";
        if (TB.num(sp, "tracking") !== null) s2 += "letter-spacing:" + TB.num(sp, "tracking") + "px;";
        if (fontOf(TB.str(sp, "font"))) s2 += "font-family:" + fontOf(TB.str(sp, "font")) + ";";
        return '<span style="' + esc(s2) + '">' + esc(t) + "</span>";
      }).join("");
    } else {
      var txt = lang === "en" && TB.str(nd, "text-en") ? TB.str(nd, "text-en") : TB.str(nd, "text") || "";
      inner = grad ? '<span class="pv-tg" style="background-image:' + esc(grad) + '">' + esc(txt) + "</span>" : esc(txt);
    }
    return '<div class="pv-label ' + align + '" style="' + esc(st) + (TB.num(nd, "span-gap") !== null ? "gap:" + TB.num(nd, "span-gap") + "px;" : "") + '">' + inner + "</div>";
  };
  function paint(th, nd, key, toks, def) {
    var v = TB.str(nd, key);
    return (v !== null && evalCss(th, v, toks, true)) || def;
  }
  C.shape = function (th, nd, toks) {
    var kind = TB.str(nd, "kind") || "circle", col = paint(th, nd, "color", toks, "var(--t-accent)"), fill = paint(th, nd, "fill", toks, "none");
    var t = TB.num(nd, "thickness") || 1.5, size = TB.num(nd, "size"), align = TB.str(nd, "align") || "center";
    var ox = TB.num(nd, "offset-x") || 0, oy = TB.num(nd, "offset-y") || 0, s = size || 24, svg = "";
    if (kind === "rounded") {
      var r = TB.num(nd, "radius") || 6;
      return '<div class="pv-shape rounded" style="transform:translate(' + ox + "px," + oy + 'px)"><i style="border:' + t + "px solid " + col + ";background:" + (fill === "none" ? "transparent" : fill) + ";border-radius:" + r + 'px"></i></div>';
    }
    if (kind === "circle") svg = '<circle cx="' + s / 2 + '" cy="' + s / 2 + '" r="' + s / 2 + '" fill="' + col + '"/>';
    else if (kind === "ring") svg = '<circle cx="' + s / 2 + '" cy="' + s / 2 + '" r="' + (s - t) / 2 + '" fill="' + fill + '" stroke="' + col + '" stroke-width="' + t + '"/>';
    else if (kind === "arc") {
      var a0 = (TB.num(nd, "start") || 0) * Math.PI / 180, sw = (TB.num(nd, "sweep") === null ? 270 : TB.num(nd, "sweep")) * Math.PI / 180, rr = (s - t) / 2, c = s / 2;
      var x0 = c + rr * Math.cos(a0), y0 = c + rr * Math.sin(a0), x1 = c + rr * Math.cos(a0 + sw), y1 = c + rr * Math.sin(a0 + sw);
      svg = '<path d="M' + x0 + " " + y0 + "A" + rr + " " + rr + " 0 " + (Math.abs(sw) > Math.PI ? 1 : 0) + " " + (sw > 0 ? 1 : 0) + " " + x1 + " " + y1 + '" fill="none" stroke="' + col + '" stroke-width="' + t + '" stroke-linecap="round"/>';
      var dot = TB.str(nd, "dot");
      if (dot) svg += '<circle cx="' + x1 + '" cy="' + y1 + '" r="' + (TB.num(nd, "dot-size") || 2) + '" fill="' + (evalCss(th, dot, toks, true) || col) + '"/>';
    } else if (kind === "line") {
      var ang = (TB.num(nd, "angle") || 0) * Math.PI / 180, L = s / 2;
      svg = '<line x1="' + (s / 2 - L * Math.cos(ang)) + '" y1="' + (s / 2 - L * Math.sin(ang)) + '" x2="' + (s / 2 + L * Math.cos(ang)) + '" y2="' + (s / 2 + L * Math.sin(ang)) + '" stroke="' + col + '" stroke-width="' + t + '"/>';
    }
    var dim = size ? "width:" + s + "px;height:" + s + "px" : "height:100%;aspect-ratio:1";
    return '<div class="pv-shape ' + align + '" style="transform:translate(' + ox + "px," + oy + 'px)"><svg viewBox="0 0 ' + s + " " + s + '" style="' + dim + ';overflow:visible">' + svg + "</svg></div>";
  };
  C.rule = function (th, nd, toks) {
    var kind = TB.str(nd, "kind") || "solid", col = paint(th, nd, "color", toks, "var(--t-border)"), t = TB.num(nd, "thickness") || 1;
    var vert = flagOpt(th, nd, "vertical", false), fade = flagOpt(th, nd, "fade", false);
    var line;
    if (kind === "dashed") {
      var d = TB.num(nd, "dash") || 4, g = TB.num(nd, "gap") || 3;
      line = "background:repeating-linear-gradient(" + (vert ? "180deg" : "90deg") + "," + col + " 0 " + d + "px,transparent " + d + "px " + (d + g) + "px);" + (vert ? "width:" + t + "px" : "height:" + t + "px");
    } else if (kind === "dotted") {
      line = "background:radial-gradient(circle," + col + " " + t * 0.6 + "px,transparent " + (t * 0.6 + 0.6) + "px) 0 0/" + t * 3 + "px " + t * 3 + "px;" + (vert ? "width:" : "height:") + t * 2 + "px";
    } else if (kind === "double") line = (vert ? "border-left:" : "border-top:") + t + "px solid " + col + ";" + (vert ? "border-right:" : "border-bottom:") + t + "px solid " + col + ";" + (vert ? "width:" : "height:") + "calc(100% - 2px)";
    else if (kind === "oxford") line = (vert ? "border-left:" : "border-top:") + (t * 2.5) + "px solid " + col + ";" + (vert ? "border-right:" : "border-bottom:") + t + "px solid " + col + ";" + (vert ? "width:" : "height:") + "calc(100% - 1px)";
    else line = "background:" + col + ";" + (vert ? "width:" + t + "px" : "height:" + t + "px");
    var orn = "", ot = TB.str(nd, "ornament-text"), o = TB.str(nd, "ornament");
    if (ot || o) {
      var oc = paint(th, nd, "ornament-color", toks, col), os = TB.num(nd, "ornament-size") || 8, gap = TB.num(nd, "ornament-gap") || 6;
      var glyph = ot ? esc(ot) : { diamond: "◆", dot: "●", ring: "○", star: "✦" }[o] || "◆";
      orn = '<b style="color:' + oc + ";font-size:" + os + "px;padding:0 " + gap + "px;" + (ot && fontOf(TB.str(nd, "font")) ? "font-family:" + fontOf(TB.str(nd, "font")) : "") + '">' + glyph + "</b>";
    }
    var seg = '<i style="' + line + '"></i>';
    return '<div class="pv-rule' + (vert ? " v" : "") + (fade ? " fade" : "") + '">' + seg + (orn ? orn + seg : "") + "</div>";
  };

  // Fundos procedurais: SVG com o mesmo tamanho da janela, sementes fixas.
  function bgSvg(inner) { return '<svg class="pv-bgsvg" viewBox="0 0 ' + W + " " + H + '" preserveAspectRatio="xMidYMid slice" aria-hidden="true">' + inner + "</svg>"; }
  C.starfield = function (th, nd, toks) {
    var r = TB.rng((TB.num(nd, "seed") || 1) * 977), n = Math.round(170 * (TB.num(nd, "density") || 1)), far = paint(th, nd, "color", toks, "var(--t-muted)"), near = paint(th, nd, "color2", toks, "var(--t-accent)"), out = "";
    for (var i = 0; i < n; i++) {
      var close = r() < 0.14;
      out += '<circle cx="' + (r() * W).toFixed(1) + '" cy="' + (r() * H).toFixed(1) + '" r="' + (close ? 1.1 + r() * 0.9 : 0.4 + r() * 0.7).toFixed(2) + '" fill="' + (close ? near : far) + '" opacity="' + (0.4 + r() * 0.6).toFixed(2) + '"/>';
    }
    return bgSvg(out);
  };
  C.orbit = function (th, nd, toks) {
    var cx = (TB.num(nd, "center-x") === null ? 0.7 : TB.num(nd, "center-x")) * W, cy = (TB.num(nd, "center-y") === null ? 0.35 : TB.num(nd, "center-y")) * H;
    var rings = TB.num(nd, "rings") || 6, col = paint(th, nd, "color", toks, "var(--t-border)"), moon = paint(th, nd, "color2", toks, "var(--t-accent)"), r = TB.rng((TB.num(nd, "seed") || 1) * 31), out = "";
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
    var r = TB.rng((TB.num(nd, "seed") || 1) * 131), levels = TB.num(nd, "levels") || 14, col = paint(th, nd, "color", toks, "var(--t-border)"), out = "";
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
    var cx = (TB.num(nd, "center-x") === null ? 0.5 : TB.num(nd, "center-x")) * W, cy = (TB.num(nd, "center-y") === null ? 0.5 : TB.num(nd, "center-y")) * H;
    var rings = TB.num(nd, "rings") || 5, col = paint(th, nd, "color", toks, "var(--t-border)"), sw = paint(th, nd, "color2", toks, "var(--t-accent)"), out = "", R = 0;
    for (var i = 1; i <= rings; i++) { R = i * 70; out += '<circle cx="' + cx + '" cy="' + cy + '" r="' + R + '" fill="none" stroke="' + col + '"/>'; }
    out += '<path d="M' + (cx - R) + " " + cy + "H" + (cx + R) + "M" + cx + " " + (cy - R) + "V" + (cy + R) + '" stroke="' + col + '"/>';
    out += '<path d="M' + cx + " " + cy + "L" + (cx + R) + " " + cy + "A" + R + " " + R + " 0 0 0 " + (cx + R * Math.cos(-0.7)).toFixed(1) + " " + (cy + R * Math.sin(-0.7)).toFixed(1) + 'Z" fill="' + sw + '" opacity=".22"/>';
    return bgSvg(out + '<line x1="' + cx + '" y1="' + cy + '" x2="' + (cx + R) + '" y2="' + cy + '" stroke="' + sw + '" stroke-width="2"/>');
  };
  C["window-controls"] = function (th, nd, toks) {
    var s = TB.num(nd, "size") || 12, g = TB.num(nd, "gap") || 8, cols = [paint(th, nd, "color", toks, "#ff5f57"), paint(th, nd, "color2", toks, "#febc2e"), paint(th, nd, "color3", toks, "#28c840")];
    return '<div class="pv-wc ' + (TB.str(nd, "align") || "left") + '" style="gap:' + g + 'px">' + cols.map(function (c) { return '<i style="width:' + s + "px;height:" + s + "px;background:" + c + '"></i>'; }).join("") + "</div>";
  };
  C.logo = function (th, nd) {
    var size = TB.num(nd, "size") || 14;
    if (TB.str(nd, "variant") === "ascii") return '<pre class="pv-logo ascii" style="font-size:' + size * 0.9 + 'px">┬  ┌─┐┬─┐┌─┐┌─┐┬─┐\n│  ├─┤├┬┘├─┘├┤ ├┬┘\n┴─┘┴ ┴┴└─┴  └─┘┴└─ cord</pre>';
    return '<div class="pv-logo" style="font-size:' + size * 0.9 + 'px">larperCord</div>';
  };
  C.topbar = function () {
    return '<div class="pv-top">' + ic("back") + ic("fwd") + '<span class="pv-tsearch">' + ic("search") + esc(M.search) + "<kbd>Ctrl+K</kbd></span>" + ic("help") + "</div>";
  };
  C.crt = function (th, nd) {
    var sp = Math.max(2, TB.num(nd, "spacing") || 3), k = TB.num(nd, "strength") === null ? 0.08 : TB.num(nd, "strength");
    return '<div class="pv-crt" style="background:repeating-linear-gradient(to bottom,transparent 0 ' + (sp - 1) + "px,rgba(0,0,0," + Math.min(0.9, k * 2.6).toFixed(3) + ") " + (sp - 1) + "px " + sp + 'px),radial-gradient(ellipse at center,transparent 62%,rgba(0,0,0,' + Math.min(0.6, k * 3).toFixed(3) + '))"></div>';
  };
  C.spacer = function () { return ""; };

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
    b.className = "pv-b pv-k-" + nd.name;
    var mw = TB.num(nd, "max-width");
    if (mw !== null) { b.style.maxWidth = mw + "px"; b.style.marginLeft = b.style.marginRight = "auto"; }
    over.forEach(function (o) { b.style.setProperty("--t-" + o[0], o[1]); });
    var f = fontOf(TB.str(nd, "font"));
    if (f && nd.name !== "label") b.style.fontFamily = f;
    paintBox(th, b, nd, local, !CONTAINERS[nd.name]);
    if (CONTAINERS[nd.name]) {
      b.classList.add("pv-" + (nd.name === "stack" ? "stack" : "flex"));
      if (nd.name !== "stack") b.style.flexDirection = nd.name === "row" ? "row" : "column";
      var pad = TB.num(nd, "padding") || 0, px = TB.num(nd, "padding-x"), py = TB.num(nd, "padding-y");
      px = px === null ? pad : px;
      py = py === null ? pad : py;
      b.style.padding = py + "px " + px + "px";
      if (nd.name !== "stack" && TB.num(nd, "gap")) b.style.gap = TB.num(nd, "gap") + "px";
      nd.kids.forEach(function (k) { if (visible(th, k)) b.appendChild(build(th, k, nd.name, local)); });
    } else {
      var c = document.createElement("div");
      c.className = "pv-c";
      var ix = TB.num(nd, "inset-x") || 0, iy = TB.num(nd, "inset-y") || 0;
      c.style.inset = iy + "px " + ix + "px";
      if (C[nd.name]) c.innerHTML = C[nd.name](th, nd, local);
      else {
        c.className += " pv-bad";
        c.textContent = (lang === "pt" ? "componente desconhecido: " : "unknown component: ") + nd.name + " · " + S.line + " " + nd.line;
      }
      b.appendChild(c);
      if (flagOpt(th, nd, "autohide", false)) n.classList.add("pv-autohide");
    }
    n.appendChild(b);
    return n;
  }

  function renderPreview(th) {
    var f = frame;
    f.innerHTML = "";
    TB.TOKENS.forEach(function (k) { f.style.setProperty("--t-" + k, TB.cssColor(th.tokens[k])); });
    th.roles.forEach(function (c, i) { f.style.setProperty("--r" + i, TB.cssColor(c)); });
    f.style.setProperty("--f-ui", '"' + th.fontUi.replace(/["\\]/g, "") + '",Inter,Archivo,system-ui,sans-serif');
    f.style.setProperty("--f-mono", '"' + th.fontMono.replace(/["\\]/g, "") + '","JetBrains Mono",ui-monospace,monospace');
    f.style.setProperty("--pv-fs", th.fontSize * 0.9 + "px");
    f.style.setProperty("--pv-r", th.radius + "px");
    f.classList.toggle("pv-clear", th.transparent);
    f.classList.toggle("pv-light", th.mode === "light");
    f.style.setProperty("--pv-bg", TB.cssColor(th.tokens.bg));
    var root = th.layout.kids.filter(function (k) { return visible(th, k); })[0];
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
      errBox.textContent = S.errAt + (e.line || "?") + (e.column ? ":" + e.column : "") + ": " + e.message + " · " + S.kept;
      advStatus.className = "tb-adv-status err";
      advStatus.textContent = (line > 0 ? "layout:" + line + (e.column ? ":" + e.column : "") + ": " : "") + e.message + " · " + S.kept;
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
      dlgErr.textContent = (importName || "theme") + ".kdl:" + (e.line || "?") + (e.column ? ":" + e.column : "") + ": " + e.message;
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
        say(S.linkFail + e.message);
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
