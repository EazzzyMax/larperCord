// O criador de temas: um editor de tela inteira em volta da prévia do app.
// As contas (KDL, cores, carregamento do tema, geração, gerador de paletas, inversão do
// modo) ficam em theme-builder-core.js e o desenho em theme-builder-preview.js, os mesmos
// arquivos que tools/theme_builder_test.js testa. Aqui só há a página: nada do tema vira
// marcação (tudo passa por createElement e textContent; a prévia escapa o que desenha).
(function () {
  var box = document.querySelector("[data-builder]");
  if (!box || !window.LC_TB || !window.LC_TB_PREVIEW) return;
  var TB = window.LC_TB;
  var html = document.documentElement;
  var lang = html.dataset.lang === "pt" ? "pt" : "en";
  var DATA = JSON.parse(document.getElementById("tb-data").textContent);
  var P = window.LC_TB_PREVIEW(TB, lang);
  var W = P.W, H = P.H;
  var pt = lang === "pt";
  function L(en, ptText) { return pt ? ptText : en; }

  // ----------------------------------------------------------- Textos ----
  var S = pt ? {
    groups: { surfaces: "Superfícies", text: "Texto", accent: "Destaque", status: "Status", bubbles: "Balões", shadow: "Sombra" },
    tok: { bg: "Fundo da janela e da conversa", rail: "A faixa mais escura: servidores, barras de título e de status", sidebar: "Listas de canais e de membros", surface: "Cartões e painéis", elevated: "Campos, popups, item com o mouse em cima", overlay: "Menus e diálogos", "code-bg": "Blocos de código", text: "Texto principal", muted: "Texto secundário: canais, horários", faint: "Dicas, texto de exemplo, membros offline", link: "Links", accent: "Botões, seleção, destaques", "accent-text": "Texto em cima do destaque", mention: "Menções a você", selected: "Canal ou linha selecionada", hover: "Linha com o mouse em cima", border: "Bordas e divisórias", online: "Status: online", idle: "Status: ausente", dnd: "Status: não perturbe", danger: "Erros, apagar, contador de não lidas", "bubble-self": "Seus balões de conversa", "bubble-self-text": "Texto nos seus balões", "bubble-other": "Balões dos outros", shadow: "Sombras" },
    role: "cargo", roleDesc: "Nomes de usuário e ícones de servidor", palDesc: "Cor da paleta base, para os layouts que usam wal:", baseName: "cor base", baseDesc: "O gerador monta os dois modos a partir dela",
    mode: { dark: "escuro", light: "claro" }, editing: "Editando: ", cap: { dark: "Escuro", light: "Claro" },
    def: "padrão", on: "ligado", off: "desligado", follows: "segue ", when: "só com ", unless: "sem ",
    advOk: "ok: o layout é válido", kept: "a prévia anterior continua", fallback: function (n) { return "até isto ser corrigido, a prévia usa o layout " + n; }, errAt: "Erro no arquivo, linha ",
    custom: "personalizado", layoutNow: "Layout: ", noOptions: "Este layout não tem opções.", noProps: "Nada para ajustar nesta camada além de esconder e mover.",
    hide: "Esconder", show: "Mostrar", up: "Subir", down: "Descer", reset: "Voltar ao padrão",
    contrastOk: "Tudo legível neste modo.",
    issues: function (b, l) { var p = []; if (b) p.push(b === 1 ? "1 problema" : b + " problemas"); if (l) p.push(l + " abaixo do AA para texto pequeno"); return p.join(", ") + " neste modo."; },
    chipOk: "Contraste ok", chipBad: function (n) { return n === 1 ? "1 problema de contraste" : n + " problemas de contraste"; },
    chipLow: function (n) { return n === 1 ? "1 cor para revisar" : n + " cores para revisar"; },
    lowNote: "Serve para texto grande e ícones (3:1); texto pequeno pede 4,5:1.", autoMark: "o app ajusta", lowMark: "abaixo do AA",
    shownAs: function (v) { return "Aparece como " + v + ": o app clareia ao carregar."; }, keepLift: function (v) { return "Escrever " + v + " no arquivo"; },
    showAll: "Mostrar todas as checagens", hideOk: "Mostrar só os problemas",
    on_: " sobre ", needs: "o app pede ", wcag: "mínimo AA ", lifts: "O app clareia esta cor para ", liftsEnd: " ao carregar o tema.", use: "Usar ", fix: "Consertar",
    otherIssues: function (m, n) { return n ? "No modo " + m + ": " + n + (n === 1 ? " ponto." : " pontos.") : "No modo " + m + ": tudo legível."; },
    passes: "passa", fails: "não passa", stuck: "Nem o text chega nisso. Aumente o contraste do text primeiro.",
    fromLayout: function (line) { return "Esta cor vem do layout (linha " + line + "): mude lá, na aba Código."; },
    gatedTag: "trocada pelo layout",
    gated: function (b, list) {
      var what = b.kind === "colors" ? "estas cores: " + list.join(", ") : b.kind === "roles" ? "as cores de cargo" : "a paleta base (wal:0–15)";
      var head = b.when ? "Com a opção " + b.when + " ligada (como ela começa), o layout troca " : b.unless ? "Com a opção " + b.unless + " desligada (como ela começa), o layout troca " : "Um bloco no texto do layout troca ";
      return head + what + " neste modo. " + (b.when ? "Os campos delas só valem com a " + b.when + " desligada." : b.unless ? "Os campos delas só valem com a " + b.unless + " ligada." : "Os campos delas não têm efeito.") +
        " Para mudar o que o app mostra, edite o bloco na linha " + b.line + " do layout (aba Código).";
    },
    warnGated: function (line) { return "Neste modo, um bloco do layout (linha " + line + ") troca esta cor: mudar aqui não muda o que o app mostra. Edite na aba Código."; },
    warnOver: function (tok, line) { return "Esta parte troca " + tok + " no próprio layout (c-" + tok + ", linha " + line + "): mudar aqui vale para o resto do app, não para ela."; },
    warnLit: function (line) { return "O fundo desta parte é uma cor escrita no layout (linha " + line + "), não um token."; },
    layer: function (n, line) { return "Camada: " + n + " · linha " + line + " ›"; },
    hoverHint: "Passe o mouse na prévia e clique para editar uma cor.",
    copied: "Copiado.", linkCopied: "Link copiado. Ele guarda o tema inteiro.", kdlCopied: ".kdl copiado.", downloaded: "Baixado: ",
    harmonies: { mono: "Monocromática", analogous: "Análoga", complementary: "Complementar", split: "Complementar dividida", triadic: "Tríade" },
    surprise: "Paleta nova: ", genDone: "Paleta aplicada aos dois modos.", imageDone: "Cores tiradas da imagem.", imageFail: "Não deu para ler essa imagem.", imageBig: "Imagem grande demais (até 20 MB).",
    fromImage: "Da imagem: clique numa cor para usar como base.",
    undoNothing: "Nada para desfazer.", importOk: "Tema importado.", started: "Começando de ", badHex: "Use #RGB, #RRGGBB ou #RRGGBBAA", linkFail: "Esse link não abriu: ",
    invert: { dark: "Copiar o escuro para o claro, invertido", light: "Copiar o claro para o escuro, invertido" },
    inverted: { dark: "O modo claro agora parte do escuro. Desfazer traz o de antes.", light: "O modo escuro agora parte do claro. Desfazer traz o de antes." },
    other: { dark: "Gerar um claro parecido", light: "Gerar um escuro parecido" },
    unlock: "Destravar ", lock: "Travar esta cor",
    lines: function (n, kb) { return n + " linhas · " + kb + " KB · gerado nesta página"; },
    defaultName: "meu-", importFallback: "tema", community: "Tema da comunidade: ", noCommunity: "Ainda não há temas na galeria da comunidade.", seeGallery: "Ver a galeria",
    preview: "Prévia do tema no modo ", zoomFit: "ajustado",
    zoomInfo: function (w, h, p) { return "A prévia desenha o app numa janela de " + w + "×" + h + ", em " + p; }, zoomTo100: "Tamanho real", zoomToFit: "Caber no espaço",
    hidEssential: function (n, list) { return "“" + n + "” ficou escondida, e com ela " + list.join(", ") + ": no app, isso some da janela."; }, undo: "Desfazer",
    lifted: function (n) { return n === 1 ? "O app clareia 1 cor ao carregar." : "O app clareia " + n + " cores ao carregar."; },
    ready: { name: "Nome", author: "Autor", description: "Descrição", license: "Licença" },
    readyBad: {
      name: function (c) { return c.builtin ? c.file + " é o nome de um tema embutido: escolha outro nome" : "falta o nome, de até 48 caracteres"; },
      author: "falta o autor",
      description: function (c) { return c.copied ? "ainda é a descrição do tema embutido de onde ele partiu: descreva o seu" : "falta uma descrição, em inglês ou português, de até 240 caracteres"; },
      license: "falta, ou não está na lista da galeria: uma licença aberta como CC0-1.0, CC-BY-4.0 ou MIT (o campo sugere as outras)",
    },
    readyOk: function (f) { return "Pronto para a galeria: coloque " + f + " em themes/community/ num pull request."; },
    readyMissing: function (n) { return n === 1 ? "Falta 1 item para a galeria." : "Faltam " + n + " itens para a galeria."; },
    readyShort: function (n) { return n ? (n === 1 ? "Falta 1 item para a galeria da comunidade" : "Faltam " + n + " itens para a galeria da comunidade") : "Pronto para a galeria da comunidade"; },
    radii: ["Reto", "Suave", "Redondo", "Bem redondo"],
    css: {
      summary: function (d, l, v) { return "Cores lidas de " + v + (v === 1 ? " variável" : " variáveis") + " do CSS: " + d + " no modo escuro" + (l === null ? "." : " e " + l + " no claro."); },
      noLight: "O CSS não tem bloco do modo claro: o claro ficou como estava.",
      mode: { dark: "Modo escuro", light: "Modo claro" }, from: " ← ", derived: function (t, from) { return t + ": preto ou branco, o que contrasta mais com " + from; },
      skipped: { transparent: function (t, v) { return t + ": " + v + " é transparente no CSS (o tema deve desenhar uma imagem atrás), então não entrou"; },
        unreadable: function (t, v) { return t + ": " + v + " não é uma cor que esta página lê (gradiente, imagem, lab(), cor relativa…), então não entrou"; } },
      flat: function (a, o) { return " · " + Math.round(a * 100) + "% opaca no CSS, posta sobre " + (o === "bg" ? "bg" : o === "light" ? "branco" : "preto") + " para ficar sólida"; },
      swapped: " · muted e faint trocaram de lugar: faint é o texto mais apagado, e no CSS era o contrário",
      kept: "Ficaram como estavam: ", noneKept: "Nenhum token ficou como estava.", rest: "As cores de cargo e a paleta base não mudam.",
      imports: function (n) { return n === 1 ? "1 link de @import não foi aberto (as cores dele não entram):" : n + " links de @import não foram abertos (as cores deles não entram):"; },
      notes: function (n) { return "O CSS tinha " + n + (n === 1 ? " trecho quebrado, pulado." : " trechos quebrados, pulados."); },
      contrast: function (d, l) { return "Contraste agora: modo escuro, " + (d ? d + (d === 1 ? " ponto" : " pontos") + " para olhar" : "tudo legível") + "; modo claro, " + (l ? l + (l === 1 ? " ponto" : " pontos") + " para olhar" : "tudo legível") + ". O painel Cores tem os consertos."; },
      done: "Cores importadas do CSS.", fail: "Não deu para ler: ", readFail: "Não deu para abrir esse arquivo.",
    },
  } : {
    groups: { surfaces: "Surfaces", text: "Text", accent: "Accent", status: "Status", bubbles: "Bubbles", shadow: "Shadow" },
    tok: { bg: "Window and conversation background", rail: "The darkest strip: servers, title and status bars", sidebar: "Channel and member lists", surface: "Cards and panels", elevated: "Inputs, popups, the item under the mouse", overlay: "Menus and dialogs", "code-bg": "Code blocks", text: "Main text", muted: "Secondary text: channels, timestamps", faint: "Hints, placeholder text, offline members", link: "Links", accent: "Buttons, selection, highlights", "accent-text": "Text on top of the accent", mention: "Mentions of you", selected: "Selected channel or row", hover: "Row under the mouse", border: "Borders and dividers", online: "Status: online", idle: "Status: idle", dnd: "Status: do not disturb", danger: "Errors, delete, unread counters", "bubble-self": "Your chat bubbles", "bubble-self-text": "Text in your bubbles", "bubble-other": "Other people's bubbles", shadow: "Shadows" },
    role: "role", roleDesc: "Usernames and server icons", palDesc: "Base palette color, for layouts that use wal:", baseName: "base color", baseDesc: "The generator builds both modes from it",
    mode: { dark: "dark", light: "light" }, editing: "Editing: ", cap: { dark: "Dark", light: "Light" },
    def: "default", on: "on", off: "off", follows: "follows ", when: "only with ", unless: "without ",
    advOk: "ok: the layout is valid", kept: "the previous preview stays", fallback: function (n) { return "until this is fixed, the preview uses the " + n + " layout"; }, errAt: "Error in the file, line ",
    custom: "custom", layoutNow: "Layout: ", noOptions: "This layout has no options.", noProps: "Nothing to tweak on this layer besides hiding and moving it.",
    hide: "Hide", show: "Show", up: "Move up", down: "Move down", reset: "Back to the default",
    contrastOk: "Everything is readable in this mode.",
    issues: function (b, l) { var p = []; if (b) p.push(b === 1 ? "1 problem" : b + " problems"); if (l) p.push(l + " below AA for small text"); return p.join(", ") + " in this mode."; },
    chipOk: "Contrast ok", chipBad: function (n) { return n === 1 ? "1 contrast problem" : n + " contrast problems"; },
    chipLow: function (n) { return n === 1 ? "1 color to review" : n + " colors to review"; },
    lowNote: "Fine for large text and icons (3:1); small text needs 4.5:1.", autoMark: "the app adjusts it", lowMark: "below AA",
    shownAs: function (v) { return "Shows as " + v + ": the app lifts it on load."; }, keepLift: function (v) { return "Write " + v + " in the file"; },
    showAll: "Show every check", hideOk: "Show only the problems",
    on_: " on ", needs: "the app needs ", wcag: "AA minimum ", lifts: "The app lifts this color to ", liftsEnd: " when it loads the theme.", use: "Use ", fix: "Fix",
    otherIssues: function (m, n) { return n ? "In " + m + " mode: " + n + (n === 1 ? " thing." : " things.") : "In " + m + " mode: all readable."; },
    passes: "passes", fails: "fails", stuck: "Even text doesn't reach this. Raise the contrast of text first.",
    fromLayout: function (line) { return "This color comes from the layout (line " + line + "): change it there, in the Code tab."; },
    gatedTag: "replaced by the layout",
    gated: function (b, list) {
      var what = b.kind === "colors" ? "these colors: " + list.join(", ") : b.kind === "roles" ? "the role colors" : "the base palette (wal:0–15)";
      var head = b.when ? "With option " + b.when + " on (as it starts), the layout replaces " : b.unless ? "With option " + b.unless + " off (as it starts), the layout replaces " : "A block in the layout text replaces ";
      return head + what + " in this mode. " + (b.when ? "Their values here only count with " + b.when + " off." : b.unless ? "Their values here only count with " + b.unless + " on." : "Their values here have no effect.") +
        " To change what the app shows, edit the block at layout line " + b.line + " (Code tab).";
    },
    warnGated: function (line) { return "In this mode a block in the layout (line " + line + ") replaces this color: changing it here won't change what the app shows. Edit it in the Code tab."; },
    warnOver: function (tok, line) { return "This part replaces " + tok + " in the layout itself (c-" + tok + ", line " + line + "): changing it here applies to the rest of the app, not to this part."; },
    warnLit: function (line) { return "This part's background is a color written in the layout (line " + line + "), not a token."; },
    layer: function (n, line) { return "Layer: " + n + " · line " + line + " ›"; },
    hoverHint: "Hover the preview and click to edit a color.",
    copied: "Copied.", linkCopied: "Link copied. It holds the whole theme.", kdlCopied: ".kdl copied.", downloaded: "Downloaded: ",
    harmonies: { mono: "Monochrome", analogous: "Analogous", complementary: "Complementary", split: "Split complementary", triadic: "Triadic" },
    surprise: "New palette: ", genDone: "Palette applied to both modes.", imageDone: "Colors taken from the image.", imageFail: "Couldn't read that image.", imageBig: "That image is too big (20 MB at most).",
    fromImage: "From the image: click a color to use it as the base.",
    undoNothing: "Nothing to undo.", importOk: "Theme imported.", started: "Starting from ", badHex: "Use #RGB, #RRGGBB or #RRGGBBAA", linkFail: "That link didn't open: ",
    invert: { dark: "Copy dark to light, inverted", light: "Copy light to dark, inverted" },
    inverted: { dark: "Light mode now starts from dark mode. Undo brings the old one back.", light: "Dark mode now starts from light mode. Undo brings the old one back." },
    other: { dark: "Generate a matching light mode", light: "Generate a matching dark mode" },
    unlock: "Unlock ", lock: "Lock this color",
    lines: function (n, kb) { return n + " lines · " + kb + " KB · made in this page"; },
    defaultName: "my-", importFallback: "theme", community: "Community theme: ", noCommunity: "No themes in the community gallery yet.", seeGallery: "See the gallery",
    preview: "Theme preview in ", zoomFit: "fit",
    zoomInfo: function (w, h, p) { return "The preview draws the app in a " + w + "×" + h + " window, at " + p; }, zoomTo100: "Actual size", zoomToFit: "Fit to the space",
    hidEssential: function (n, list) { return "“" + n + "” is hidden, and " + list.join(", ") + " with it: in the app, that goes missing from the window."; }, undo: "Undo",
    lifted: function (n) { return n === 1 ? "The app lifts 1 color when it loads." : "The app lifts " + n + " colors when it loads."; },
    ready: { name: "Name", author: "Author", description: "Description", license: "License" },
    readyBad: {
      name: function (c) { return c.builtin ? c.file + " is the name of a built-in theme: pick another name" : "missing, up to 48 characters"; },
      author: "missing",
      description: function (c) { return c.copied ? "still the description of the built-in theme it started from: describe yours" : "missing: one in English or Portuguese, up to 240 characters"; },
      license: "missing, or not on the gallery's list: an open license such as CC0-1.0, CC-BY-4.0 or MIT (the field suggests the others)",
    },
    readyOk: function (f) { return "Ready for the gallery: put " + f + " in themes/community/ in a pull request."; },
    readyMissing: function (n) { return n === 1 ? "1 thing missing for the gallery." : n + " things missing for the gallery."; },
    readyShort: function (n) { return n ? (n === 1 ? "1 thing missing for the community gallery" : n + " things missing for the community gallery") : "Ready for the community gallery"; },
    radii: ["Sharp", "Soft", "Round", "Rounder"],
    css: {
      summary: function (d, l, v) { return "Colors read from " + v + (v === 1 ? " CSS variable" : " CSS variables") + ": " + d + " in dark mode" + (l === null ? "." : " and " + l + " in light mode."); },
      noLight: "The CSS has no light mode block: light mode stayed as it was.",
      mode: { dark: "Dark mode", light: "Light mode" }, from: " ← ", derived: function (t, from) { return t + ": black or white, whichever stands out more on " + from; },
      skipped: { transparent: function (t, v) { return t + ": " + v + " is transparent in the CSS (the theme probably draws an image behind it), so it was left out"; },
        unreadable: function (t, v) { return t + ": " + v + " isn't a color this page reads (a gradient, an image, lab(), a relative color…), so it was left out"; } },
      flat: function (a, o) { return " · " + Math.round(a * 100) + "% opaque in the CSS, laid over " + (o === "bg" ? "bg" : o === "light" ? "white" : "black") + " to make it solid"; },
      swapped: " · muted and faint swapped places: faint is the quieter text, and the CSS had it the other way round",
      kept: "Kept their previous value: ", noneKept: "No token kept its previous value.", rest: "Role colors and the base palette don't change.",
      imports: function (n) { return n === 1 ? "1 @import link was not opened (its colors are not included):" : n + " @import links were not opened (their colors are not included):"; },
      notes: function (n) { return "The CSS had " + n + (n === 1 ? " broken piece, skipped." : " broken pieces, skipped."); },
      contrast: function (d, l) { return "Contrast now: dark mode, " + (d ? d + (d === 1 ? " thing" : " things") + " to look at" : "all readable") + "; light mode, " + (l ? l + (l === 1 ? " thing" : " things") + " to look at" : "all readable") + ". The Colors panel has the fixes."; },
      done: "Colors imported from the CSS.", fail: "Couldn't read it: ", readFail: "Couldn't open that file.",
    },
  };

  var GROUPS = [["surfaces", ["bg", "rail", "sidebar", "surface", "elevated", "overlay", "code-bg"]], ["text", ["text", "muted", "faint", "link"]],
    ["accent", ["accent", "accent-text", "mention", "selected", "hover", "border"]], ["status", ["online", "idle", "dnd", "danger"]],
    ["bubbles", ["bubble-self", "bubble-self-text", "bubble-other"]], ["shadow", ["shadow"]]];
  // Tokens de texto: ganham a etiqueta de contraste na lista.
  var TEXT_TOKS = ["text", "muted", "faint", "link", "accent-text", "bubble-self-text"];
  var MODES = ["dark", "light"];

  // ------------------------------------------------------------ Ícones ----
  var IC = {
    panel: "M4 5h16v14H4zM9.5 5v14", pen: "M15.5 4.5l4 4L8 20H4v-4zM13.5 6.5l4 4", undo: "M9 14 4 9l5-5M4 9h10.5a5.5 5.5 0 0 1 0 11H11", redo: "M15 14l5-5-5-5M20 9H9.5a5.5 5.5 0 0 0 0 11H13",
    moon: "M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z", sun: "M12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM12 2.5v2M12 19.5v2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M2.5 12h2M19.5 12h2M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4",
    split: ["M3.5 5.5h17v13h-17zM12 5.5v13", "F:M3.5 5.5H12v13H3.5z"], fit: "M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5", expand: "M14 4h6v6M10 20H4v-6M20 4l-7 7M4 20l7-7", compress: "M4 14h6v6M20 10h-6V4M10 14l-7 7M14 10l7-7",
    folder: "M3 6.5A1.5 1.5 0 0 1 4.5 5H9l2 2h8.5A1.5 1.5 0 0 1 21 8.5v9a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 17.5z", caret: "m7 10 5 5 5-5",
    file: "M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8zM14 3v5h5", css: "M8 7 4 12l4 5M16 7l4 5-4 5M13.5 5l-3 14",
    image: "M4 5h16v14H4zM4 16l5-5 4 4 2-2 5 5M15.5 9.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z",
    link: "M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1.2 1.2M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1.2-1.2", download: "M12 4v11M7 10l5 5 5-5M5 20h14",
    drop: "M12 3.5s6.5 7 6.5 11a6.5 6.5 0 0 1-13 0c0-4 6.5-11 6.5-11z", wand: "M4 20 14 10M13 4.5l1 2.5 2.5 1-2.5 1-1 2.5-1-2.5-2.5-1 2.5-1zM18.5 12l.6 1.4 1.4.6-1.4.6-.6 1.4-.6-1.4-1.4-.6 1.4-.6z",
    layout: "M4 4h16v16H4zM9.5 4v16M9.5 10H20", type: "M5 7V5h14v2M12 5v14M9 19h6", code: "M8 7 3 12l5 5M16 7l5 5-5 5", tag: "M3.5 12V4h8l9 9-8 8zM7.8 8.2h.01",
    search: "M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16zM21 21l-4.3-4.3", lock: "M6 11h12v9H6zM8.5 11V8a3.5 3.5 0 0 1 7 0v3", unlock: "M6 11h12v9H6zM8.5 11V8a3.5 3.5 0 0 1 6.8-1.2",
    close: "M6 6l12 12M18 6 6 18", eyedrop: "M19 5a2.8 2.8 0 0 0-4 0l-2 2-1-1-1.5 1.5 1 1L4 16v4h4l7.5-7.5 1 1L18 12l-1-1 2-2a2.8 2.8 0 0 0 0-4z",
    copy: "M9 9h11v11H9zM5 15H4V4h11v1", keys: "M3 7h18v10H3zM7 11h.01M11 11h.01M15 11h.01M8 14h8", flip: ["M12 3v18M8 7l-4 5 4 5z", "F:M16 7l4 5-4 5z"],
    dice: "M5 5h14v14H5zM9 9h.01M15 15h.01M15 9h.01M9 15h.01M12 12h.01", users: "M16 20v-1.5a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4V20M9.5 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zM21 20v-1.5a4 4 0 0 0-3-3.8M15.5 4.2a3.5 3.5 0 0 1 0 6.6",
    eye: "M2.5 12s3.5-6.5 9.5-6.5 9.5 6.5 9.5 6.5-3.5 6.5-9.5 6.5S2.5 12 2.5 12zM12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z",
    eyeoff: "M3 3l18 18M10.6 5.6A9 9 0 0 1 12 5.5c6 0 9.5 6.5 9.5 6.5a16 16 0 0 1-3 3.6M6.6 6.9C4 8.6 2.5 12 2.5 12s3.5 6.5 9.5 6.5a9 9 0 0 0 4.9-1.4M9.9 9.9a3 3 0 0 0 4.2 4.2",
    up: "m6 15 6-6 6 6", down: "m6 9 6 6 6-6", chev: "m9 6 6 6-6 6", row: "M3 6h18v12H3zM9 6v12M15 6v12", column: "M5 3h14v18H5zM5 9h14M5 15h14", stack: "M12 3 3 8l9 5 9-5zM3 13l9 5 9-5",
    comp: "M4 7h16v10H4zM8 11h8", check: "m5 12 5 5 9-10", reset: "M4 12a8 8 0 1 0 2.3-5.7M4 4v4h4", minus: "M6 12h12", plus: "M12 6v12M6 12h12",
  };
  var SVGNS = "http://www.w3.org/2000/svg";
  function icon(name) {
    var s = document.createElementNS(SVGNS, "svg");
    s.setAttribute("viewBox", "0 0 24 24");
    s.setAttribute("aria-hidden", "true");
    s.setAttribute("focusable", "false");
    [].concat(IC[name] || IC.comp).forEach(function (d) {
      var p = document.createElementNS(SVGNS, "path");
      if (d.slice(0, 2) === "F:") { p.setAttribute("class", "fill"); d = d.slice(2); p.setAttribute("opacity", ".35"); }
      p.setAttribute("d", d);
      s.appendChild(p);
    });
    return s;
  }
  function placeIcons(root) {
    [].forEach.call((root || document).querySelectorAll("i[data-ic]"), function (i) { i.replaceWith(icon(i.dataset.ic)); });
  }

  // ----------------------------------------------------------- Ajudas ----
  function $(sel, el) { return (el || box).querySelector(sel); }
  function $$(sel, el) { return Array.prototype.slice.call((el || box).querySelectorAll(sel)); }
  function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
  function h(tag, attrs, kids) {
    var el = document.createElement(tag);
    if (attrs) Object.keys(attrs).forEach(function (k) {
      var v = attrs[k];
      if (k === "text") el.textContent = v;
      else if (k.slice(0, 2) === "on") el.addEventListener(k.slice(2), v);
      else if (v !== null && v !== undefined && v !== false) el.setAttribute(k, v === true ? "" : v);
    });
    (kids || []).forEach(function (k) { if (k) el.appendChild(typeof k === "string" ? document.createTextNode(k) : k); });
    return el;
  }
  function store(k, v) { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) { return null; } return null; }
  function readHex(v) {
    var t = String(v).trim().replace(/^#/, "");
    if (!/^([0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(t)) return null;
    return TB.normHex("#" + t);
  }
  function rgbPart(hex) { return TB.normHex(hex).slice(0, 7); }
  function css(hex) { return TB.cssColor(TB.hexRgba(hex)); }
  function swatch(el, hex) { el.style.background = css(hex); }
  function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }
  function fmtRatio(r) { return (Math.floor(r * 10) / 10).toFixed(1) + ":1"; }
  // HSL de 0–360, 0–1, 0–1, a partir do RGB de 0–1 e de volta.
  function toHsl(c) {
    var r = c[0], g = c[1], b = c[2], mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, d = mx - mn, hh = 0, s = 0;
    if (d > 1e-9) {
      s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
      hh = 60 * (mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4);
    }
    return [hh, s, l];
  }
  function fromHsl(hh, s, l) {
    hh = ((hh % 360) + 360) % 360 / 360;
    if (s === 0) return [l, l, l];
    var q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
    function f(t) { t = t < 0 ? t + 1 : t > 1 ? t - 1 : t; return t < 1 / 6 ? p + (q - p) * 6 * t : t < 1 / 2 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p; }
    return [f(hh + 1 / 3), f(hh), f(hh - 1 / 3)];
  }

  // ------------------------------------------------------------ Estado ----
  var structures = {}, startSwatches = {}, startMeta = {};
  DATA.order.forEach(function (n) {
    var st = TB.fromSource(DATA.themes[n].src, { base: n, name: n });
    structures[n] = st.structure;
    startMeta[n] = { desc: st.meta.desc, descEn: st.meta.descEn, preview: st.meta.preview };
    startSwatches[n] = ["rail", "sidebar", "bg", "elevated", "accent", "mention", "text"].map(function (t) { return st.colors.dark[t]; });
  });
  function builtinStructure(n) { return TB.own(structures, n) ? structures[n] : undefined; }
  function startFrom(name) {
    var s = TB.fromSource(DATA.themes[name].src, { base: name, name: S.defaultName + name });
    s.meta.author = "";
    return s;
  }

  var state = null, undoStack = [], redoStack = [], lastKey = null, lastTime = 0, hashReady = false;
  var view = html.dataset.mode === "light" ? "light" : "dark", mode = view, zoom = "fit";
  var lastGood = { dark: null, light: null }, kdlNow = "", structBase = 0;
  var locks = {};

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
    requestAnimationFrame(function () { queued = false; refresh(); });
  }

  // ------------------------------------------------------------- Aviso ----
  // `action` ({ label, run }): um botão no aviso, que fica mais tempo na tela.
  var toast = null, toastTimer = 0;
  // Com o editor de cor aberto, o aviso vai para perto dele sem cobri-lo (o rodapé do editor e as
  // amostras continuam à vista); sem o editor, fica no canto de sempre (o CSS).
  function placeToast() {
    var st = toast.style;
    st.top = st.left = st.right = st.bottom = "";
    if (!popState || pop.hidden) return;
    var p = pop.getBoundingClientRect(), th = toast.offsetHeight, tw = toast.offsetWidth, vw = innerWidth, vh = innerHeight, x = p.left, y;
    if (p.top - th - 10 >= 8) y = p.top - th - 10;
    else if (p.bottom + 10 + th <= vh - 8) y = p.bottom + 10;
    else {
      y = Math.max(8, p.top);
      x = p.left - tw - 10 >= 8 ? p.left - tw - 10 : p.right + 10;
    }
    st.top = Math.round(y) + "px";
    st.left = Math.round(clamp(x, 8, Math.max(8, vw - tw - 8))) + "px";
    st.right = st.bottom = "auto";
  }
  function say(text, action) {
    if (!toast) {
      toast = h("div", { "class": "toast tb-toast", role: "status" });
      document.body.appendChild(toast);
    }
    toast.textContent = "";
    toast.appendChild(h("span", { text: text }));
    toast.classList.toggle("act", !!action);
    if (action) {
      var b = h("button", { type: "button", "class": "tbx-b sm", text: action.label });
      b.addEventListener("click", function () { toast.classList.remove("on"); action.run(); });
      toast.appendChild(b);
    }
    placeToast();
    toast.classList.add("on");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toast.classList.remove("on"); }, action ? 7000 : 2400);
  }

  // ------------------------------------------- Cores por identificador ----
  // "bg" (um token), "role:3" (cor de cargo), "pal:12" (paleta base) ou "base" (do gerador).
  var gen = { base: "#7aa2f7", scheme: "analogous", neutral: 0.016, chroma: 0.14, lightness: 0.74, live: true, image: [] };
  function idKind(id) { return id === "base" ? "base" : id.slice(0, 5) === "role:" ? "role" : id.slice(0, 4) === "pal:" ? "pal" : "tok"; }
  function idIndex(id) { return +id.split(":")[1]; }
  function colorOf(id, m) {
    var k = idKind(id);
    if (k === "base") return gen.base;
    if (k === "role") return state.roles[m][idIndex(id)];
    if (k === "pal") return state.palette[m][idIndex(id)];
    return state.colors[m][id];
  }
  function setColor(id, m, hex, key) {
    var k = idKind(id);
    if (k === "base") { setBase(hex, true); return; }
    set(function (s) {
      if (k === "role") s.roles[m][idIndex(id)] = hex;
      else if (k === "pal") s.palette[m][idIndex(id)] = hex;
      else s.colors[m][id] = hex;
    }, key || "c:" + id + ":" + m);
  }
  function idLabel(id) {
    var k = idKind(id);
    return k === "base" ? S.baseName : k === "role" ? S.role + " " + (idIndex(id) + 1) : k === "pal" ? "wal:" + idIndex(id) : id;
  }
  function idDesc(id) {
    var k = idKind(id);
    return k === "base" ? S.baseDesc : k === "role" ? S.roleDesc : k === "pal" ? S.palDesc + idIndex(id) : S.tok[id] || "";
  }

  // ------------------------------------------------------ A prévia ----
  var stage = $("[data-stage]"), canvas = $("[data-canvas]"), screensBox = $("[data-screens]"), errBox = $("[data-error]"), emptyNote = $("[data-empty-note]");
  var screens = $$("[data-screen]").map(function (sc) { return { el: sc, fbox: $("[data-fbox]", sc), frame: $("[data-frame]", sc), cap: $("[data-cap]", sc), mode: "dark", k: 1 }; });
  // A janela que a prévia imita (fit() escolhe pelo espaço do palco) e a escala de agora.
  var frameSize = { w: W, h: H }, curK = 1, fitK = 1, stacked = false, pinch = null;
  // Com o editor de cor aberto numa tela estreita (popKind), só o modo que está sendo editado:
  // os dois lado a lado ficariam pequenos demais no espaço acima do editor.
  var popKind = "";
  function screenModes() { return view === "split" && !popKind ? ["dark", "light"] : [mode]; }
  function renderPreviews() {
    var modes = screenModes(), noMessages = false;
    screens.forEach(function (sc, i) {
      var m = modes[i];
      sc.el.hidden = !m;
      if (!m) return;
      sc.mode = m;
      var th = lastGood[m];
      sc.frame.style.width = frameSize.w + "px";
      sc.frame.style.height = frameSize.h + "px";
      if (th) {
        P.mount(sc.frame, th, frameSize);
        if (!sc.frame.querySelector(".pv-msgs")) noMessages = true;
      }
      sc.cap.textContent = S.cap[m] + " · " + TB.slug(state.meta.name) + ".kdl";
      if (sc.capMode !== m) { var ci = sc.el.querySelector(".tbx-cap svg"); if (ci) ci.replaceWith(icon(m === "dark" ? "moon" : "sun")); sc.capMode = m; }
      sc.el.classList.toggle("edit", m === mode);
      sc.fbox.style.setProperty("--pv-bg", th ? TB.cssColor(th.tokens.bg) : "#111");
    });
    emptyNote.hidden = !noMessages;
    stage.setAttribute("aria-label", S.preview + modes.map(function (m) { return S.mode[m]; }).join(" + ") + " · " + TB.slug(state.meta.name) + ".kdl");
  }
  // Quanto espaço o palco dá: lê o espaçamento de verdade do CSS (nada fixo aqui) e, com os dois
  // modos, escolhe lado a lado ou um embaixo do outro, o que der a prévia maior. Devolve true
  // quando a janela imitada mudou de tamanho (a prévia precisa ser desenhada de novo).
  function measure() {
    // Dois modos na tela (com o editor aberto num celular, mesmo em "os dois" fica um só).
    var two = screenModes().length > 1;
    stage.classList.toggle("tbx-split", two);
    // offsetWidth/Height contam a barra de rolagem: com zoom ela aparece, e a janela imitada não
    // deve mudar por isso (nem a prévia ser refeita no meio de uma pinça).
    var cw = canvas.offsetWidth, ch = canvas.offsetHeight;
    if (!cw || !ch) return false;
    var cs = getComputedStyle(screensBox);
    var padX = (parseFloat(cs.paddingLeft) || 0) + (parseFloat(cs.paddingRight) || 0), padY = (parseFloat(cs.paddingTop) || 0) + (parseFloat(cs.paddingBottom) || 0);
    var gap = parseFloat(cs.columnGap) || parseFloat(cs.gap) || 0, capH = 0;
    if (two) {
      var fig = screens[0].el, cap = fig.querySelector(".tbx-cap");
      capH = (cap ? cap.offsetHeight : 0) + (parseFloat(getComputedStyle(fig).rowGap) || 0);
    }
    // Um pixel de folga contra o arredondamento.
    var aw = cw - padX - 1, ah = ch - padY - 1;
    var row = P.frameFit(two ? (aw - gap) / 2 : aw, ah - capH), col = two ? P.frameFit(aw, (ah - gap) / 2 - capH) : null;
    var g = col && col.k > row.k + 0.001 ? col : row;
    stacked = g === col;
    fitK = g.k;
    var changedSize = !pinch && (g.w !== frameSize.w || g.h !== frameSize.h);
    if (!pinch) frameSize = { w: g.w, h: g.h };
    curK = zoom === "fit" ? fitK : clamp(+zoom, 0.1, 3);
    return changedSize;
  }
  function applyScale() {
    var k = curK, fw = Math.floor(frameSize.w * k), fh = Math.floor(frameSize.h * k);
    screensBox.style.flexDirection = stacked ? "column" : "row";
    screens.forEach(function (sc) {
      sc.k = k;
      sc.el.style.width = fw + "px";
      sc.fbox.style.width = fw + "px";
      sc.fbox.style.height = fh + "px";
      sc.frame.style.transform = "scale(" + k + ")";
    });
    canvas.classList.toggle("fits", zoom === "fit");
    var pct = Math.round(k * 100) + "%", lbl = $("[data-zoom-label]"), tg = $("[data-zoom-toggle]");
    lbl.textContent = pct;
    if (zoom === "fit") lbl.appendChild(h("small", { text: S.zoomFit }));
    tg.classList.toggle("fit", zoom === "fit");
    var info = S.zoomInfo(frameSize.w, frameSize.h, pct);
    tg.title = info + " · " + (zoom === "fit" ? S.zoomTo100 + " (1)" : S.zoomToFit + " (0)");
    tg.setAttribute("aria-label", info + ". " + (zoom === "fit" ? S.zoomTo100 : S.zoomToFit));
    hideHl();
  }
  function fit() {
    if (measure() && state) renderPreviews();
    applyScale();
  }
  // O palco mudou de tamanho: refaz no próximo quadro, e só se mudou mesmo (assim o observador
  // não dispara de novo dentro dele mesmo).
  var lastCanvas = "", fitQueued = false;
  function fitSoon() {
    if (fitQueued) return;
    fitQueued = true;
    requestAnimationFrame(function () {
      fitQueued = false;
      var sz = canvas.offsetWidth + "x" + canvas.offsetHeight;
      if (sz === lastCanvas) return;
      lastCanvas = sz;
      fit();
    });
  }
  if (window.ResizeObserver) new ResizeObserver(fitSoon).observe(canvas);
  else addEventListener("resize", fitSoon);
  // A barra de cima: esconde rótulos aos poucos (c1, c2…) até caber, seja qual for o idioma ou a fonte.
  var topBar = $(".tbx-top"), lastBar = -1, barQueued = false;
  function fitToolbar() {
    lastBar = topBar.clientWidth;
    for (var i = 1; i <= 5; i++) topBar.classList.remove("c" + i);
    for (var lv = 1; lv <= 5 && topBar.scrollWidth > topBar.clientWidth + 1; lv++) topBar.classList.add("c" + lv);
  }
  function fitToolbarSoon() {
    if (barQueued) return;
    barQueued = true;
    requestAnimationFrame(function () { barQueued = false; if (topBar.clientWidth !== lastBar) fitToolbar(); });
  }
  if (window.ResizeObserver) new ResizeObserver(fitToolbarSoon).observe(topBar);
  else addEventListener("resize", fitToolbarSoon);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(fitToolbar);
  // Zoom: "fit" ou um número. `at` (um ponto da tela) fica parado embaixo do ponteiro ou dos dedos.
  var ZOOMS = [0.25, 0.33, 0.5, 0.67, 0.75, 0.9, 1, 1.25, 1.5, 2, 3];
  function setZoom(z, at) {
    var oldK = curK, r = canvas.getBoundingClientRect();
    var ax = at ? at.x - r.left : canvas.clientWidth / 2, ay = at ? at.y - r.top : canvas.clientHeight / 2;
    var px = canvas.scrollLeft + ax, py = canvas.scrollTop + ay;
    zoom = z === "fit" ? "fit" : String(clamp(+z, 0.1, 3));
    fit();
    if (zoom === "fit") return;
    var q = curK / oldK;
    canvas.scrollLeft = px * q - ax;
    canvas.scrollTop = py * q - ay;
  }
  function zoomStep(dir) {
    var k = curK, next = null;
    if (dir > 0) { for (var i = 0; i < ZOOMS.length; i++) if (ZOOMS[i] > k + 0.005) { next = ZOOMS[i]; break; } }
    else for (var j = ZOOMS.length - 1; j >= 0; j--) if (ZOOMS[j] < k - 0.005) { next = ZOOMS[j]; break; }
    if (next !== null) setZoom(next);
  }
  $("[data-zoom-in]").addEventListener("click", function () { zoomStep(1); });
  $("[data-zoom-out]").addEventListener("click", function () { zoomStep(-1); });
  $("[data-zoom-toggle]").addEventListener("click", function () { setZoom(zoom === "fit" ? 1 : "fit"); });
  // Ctrl + roda (e a pinça do touchpad, que chega assim) e a pinça na tela de toque.
  canvas.addEventListener("wheel", function (e) {
    if (!e.ctrlKey && !e.metaKey) return;
    e.preventDefault();
    setZoom(curK * Math.exp(-clamp(e.deltaY, -60, 60) * 0.006), { x: e.clientX, y: e.clientY });
  }, { passive: false });
  function touchInfo(e) {
    var a = e.touches[0], b = e.touches[1];
    return { d: Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY) || 1, x: (a.clientX + b.clientX) / 2, y: (a.clientY + b.clientY) / 2 };
  }
  canvas.addEventListener("touchstart", function (e) {
    if (e.touches.length === 2) { pinch = touchInfo(e); pinch.k = curK; hideHl(); }
  }, { passive: true });
  canvas.addEventListener("touchmove", function (e) {
    if (!pinch || e.touches.length !== 2) return;
    e.preventDefault();
    var t = touchInfo(e);
    setZoom(pinch.k * t.d / pinch.d, t);
  }, { passive: false });
  canvas.addEventListener("touchend", function (e) { if (e.touches.length < 2) pinch = null; });
  canvas.addEventListener("touchcancel", function () { pinch = null; });
  function setView(v) {
    view = v;
    if (v !== "split") mode = v;
    $$("[data-view]").forEach(function (b) { var on = b.dataset.view === v; b.setAttribute("aria-checked", on ? "true" : "false"); b.tabIndex = on ? 0 : -1; });
    closePop();
    changed();
  }
  function setEditMode(m) {
    if (mode === m) return;
    // Num celular o editor aberto mostra só o modo dele: trocar de modo fecha o editor.
    if (popKind) closePop();
    mode = m;
    if (view !== "split") view = m;
    changed();
  }
  radioKeys($$("[data-view]"), function (b) { setView(b.dataset.view); });
  $("[data-empty-undo]").addEventListener("click", function () { undo(); });
  $("[data-empty-layers]").addEventListener("click", function () { selectTab("tbx-t-layout"); });
  // Grupo de rádio: clique, setas e Home/End.
  function radioKeys(list, pick) {
    list.forEach(function (b, i) {
      b.addEventListener("click", function () { pick(b); });
      b.addEventListener("keydown", function (e) {
        var d = e.key === "ArrowRight" || e.key === "ArrowDown" ? 1 : e.key === "ArrowLeft" || e.key === "ArrowUp" ? -1 : 0;
        if (e.key === "Home") d = -i;
        if (e.key === "End") d = list.length - 1 - i;
        if (!d) return;
        e.preventDefault();
        var n = list[(i + d + list.length) % list.length];
        pick(n);
        n.focus();
      });
    });
  }

  // --------------------------------------------- Clique para editar ----
  var hlBox = $("[data-hl]"), hlTag = $("[data-hl-tag]"), hoverInfo = $("[data-hover-info]"), hovered = null, hlQueued = false, lastPointer = null;
  function screenOf(el) {
    for (var i = 0; i < screens.length; i++) if (!screens[i].el.hidden && screens[i].fbox.contains(el)) return screens[i];
    return null;
  }
  function showHl(rectEl, label, hex, sub) {
    var r = rectEl.getBoundingClientRect(), c = canvas.getBoundingClientRect();
    hlBox.hidden = false;
    hlBox.style.transform = "translate(" + (r.left - c.left + canvas.scrollLeft) + "px," + (r.top - c.top + canvas.scrollTop) + "px)";
    hlBox.style.width = Math.max(4, r.width) + "px";
    hlBox.style.height = Math.max(4, r.height) + "px";
    hlTag.textContent = "";
    if (hex) { var i = h("i"); swatch(i, hex); hlTag.appendChild(i); }
    hlTag.appendChild(document.createTextNode(label));
    if (sub) hlTag.appendChild(h("small", { text: sub }));
    hlTag.classList.toggle("below", r.top - c.top < 30);
  }
  function hideHl() { hlBox.hidden = true; hovered = null; }
  function hoverText(info, m) {
    hoverInfo.textContent = "";
    if (!info) { hoverInfo.textContent = S.hoverHint; return; }
    var id = info.tokens[0], hex = colorOf(id, m), i = h("i");
    swatch(i, hex);
    hoverInfo.appendChild(i);
    if (info.comp) hoverInfo.appendChild(document.createTextNode(info.comp.name + " › "));
    hoverInfo.appendChild(h("b", { text: idLabel(id) }));
    hoverInfo.appendChild(document.createTextNode(" " + TB.normHex(hex) + " · " + S.mode[m] + (info.tokens.length > 1 ? " · +" + info.tokens.slice(1).map(idLabel).join(", ") : "")));
  }
  canvas.addEventListener("pointermove", function (e) {
    lastPointer = e;
    if (hlQueued) return;
    hlQueued = true;
    requestAnimationFrame(function () {
      hlQueued = false;
      var ev = lastPointer, sc = ev && screenOf(ev.target);
      if (!sc || ev.pointerType === "touch") { if (hovered) hideHl(); hoverText(null); return; }
      var info = P.tokensAt(ev.target, sc.frame);
      hovered = { info: info, sc: sc };
      var id = info.tokens[0];
      showHl(info.el, idLabel(id), colorOf(id, sc.mode), info.comp ? info.comp.name : "");
      hoverText(info, sc.mode);
    });
  });
  canvas.addEventListener("pointerleave", function () { hideHl(); hoverText(null); });
  canvas.addEventListener("scroll", hideHl, { passive: true });
  canvas.addEventListener("click", function (e) {
    var sc = screenOf(e.target);
    if (!sc) return;
    var info = P.tokensAt(e.target, sc.frame), fr = sc.fbox.getBoundingClientRect();
    var at = { x: e.clientX, y: e.clientY, fx: (e.clientX - fr.left) / fr.width, fy: (e.clientY - fr.top) / fr.height };
    if (view === "split") setEditMode(sc.mode);
    openPop(info.tokens, info.tokens[0], sc.mode, at, info);
  });

  // ---------------------------------------------- O editor de cor ----
  var NARROW = "(max-width: 899.98px)", SIDEWAYS = "(max-width: 899.98px) and (orientation: landscape)";
  var pop = $("[data-cpop]"), popState = null, recent = [];
  try { recent = JSON.parse(store("lc-tb-recent") || "[]").filter(function (x) { return typeof x === "string" && readHex(x); }).slice(0, 20); } catch (e) { recent = []; }
  var model = store("lc-tb-model") === "hsl" ? "hsl" : "oklch";
  var cp = { sw: $("[data-cp-sw]", pop), title: $("[data-cp-title]", pop), desc: $("[data-cp-desc]", pop), toks: $("[data-cp-toks]", pop), warn: $("[data-cp-warn]", pop),
    hex: $("[data-cp-hex]", pop), sliders: $("[data-cp-sliders]", pop), contrast: $("[data-cp-contrast]", pop), theme: $("[data-cp-theme]", pop), recent: $("[data-cp-recent]", pop),
    recentLbl: $("[data-cp-recent-lbl]", pop), lock: $("[data-cp-lock]", pop), layer: $("[data-cp-layer]", pop), eye: $("[data-cp-eye]", pop) };
  cp.swi = h("i");
  cp.sw.appendChild(cp.swi);
  if (window.EyeDropper) cp.eye.hidden = false;
  // Os controles deslizantes: [chave, rótulo, mínimo, máximo, passo].
  var SL = { oklch: [["L", "L", 0, 1, 0.005], ["C", "C", 0, 0.37, 0.002], ["H", "H", 0, 360, 1], ["a", "A", 0, 1, 0.01]], hsl: [["h", "H", 0, 360, 1], ["s", "S", 0, 1, 0.01], ["l", "L", 0, 1, 0.01], ["a", "A", 0, 1, 0.01]] };
  var sliderEls = {};
  function buildSliders() {
    cp.sliders.textContent = "";
    sliderEls = {};
    SL[model].forEach(function (d) {
      var inp = h("input", { type: "range", min: d[2], max: d[3], step: d[4], "aria-label": d[1], "class": d[0] === "a" ? "alpha" : null });
      var out = h("output");
      inp.addEventListener("input", function () { sliderInput(d[0], +inp.value); });
      cp.sliders.appendChild(h("label", { "class": "tbx-cs" }, [h("span", { text: d[1] }), inp, out]));
      sliderEls[d[0]] = { inp: inp, out: out };
    });
    $$("[data-cp-model]", pop).forEach(function (b) { var on = b.dataset.cpModel === model; b.setAttribute("aria-checked", on ? "true" : "false"); b.tabIndex = on ? 0 : -1; });
  }
  radioKeys($$("[data-cp-model]", pop), function (b) { model = b.dataset.cpModel; store("lc-tb-model", model); buildSliders(); syncPop(true); });
  // O modelo guarda os valores dos controles: com croma zero o matiz não pula.
  var pm = { L: 0, C: 0, H: 0, h: 0, s: 0, l: 0, a: 1 }, pmHex = null;
  function loadModel(hex) {
    var c = TB.hexRgba(hex), o = TB.toOklch(c), hs = toHsl(c);
    pm.L = o[0];
    if (o[1] > 0.002) pm.H = o[2];
    pm.C = o[1];
    if (hs[1] > 0.004) pm.h = hs[0];
    pm.s = hs[1];
    pm.l = hs[2];
    pm.a = c[3];
    pmHex = TB.normHex(hex);
  }
  function modelHex() {
    var c = model === "oklch" ? TB.oklch(pm.L, pm.C, pm.H) : fromHsl(pm.h, pm.s, pm.l).concat([1]);
    c[3] = pm.a;
    return TB.toHex(c);
  }
  function sliderInput(k, v) {
    if (!popState) return;
    pm[k] = v;
    var hex = modelHex();
    pmHex = hex;
    var keep = model === "oklch" ? { L: pm.L, C: pm.C, H: pm.H } : { h: pm.h, s: pm.s, l: pm.l };
    loadModel(hex);
    Object.keys(keep).forEach(function (x) { pm[x] = keep[x]; });
    applyPop(hex);
  }
  function applyPop(hex) {
    var p = popState;
    setColor(p.id, p.mode, hex, "pop:" + p.id + ":" + p.mode);
    paintSliders();
    cp.swi.style.background = css(hex);
    if (document.activeElement !== cp.hex) cp.hex.value = hex;
    clearTimeout(p.recentTimer);
    p.recentTimer = setTimeout(function () { pushRecent(hex); }, 900);
  }
  function grad(fn, steps) {
    var out = [];
    for (var i = 0; i <= steps; i++) out.push(TB.cssColor(fn(i / steps)));
    return "linear-gradient(90deg," + out.join(",") + ")";
  }
  function paintSliders() {
    var vals = model === "oklch" ? { L: pm.L, C: pm.C, H: pm.H, a: pm.a } : { h: pm.h, s: pm.s, l: pm.l, a: pm.a };
    var tracks = model === "oklch" ? {
      L: grad(function (t) { return TB.oklch(t, pm.C, pm.H); }, 10), C: grad(function (t) { return TB.oklch(pm.L, t * 0.37, pm.H); }, 10),
      H: grad(function (t) { return TB.oklch(pm.L, Math.max(pm.C, 0.06), t * 360); }, 12),
    } : {
      h: grad(function (t) { return fromHsl(t * 360, Math.max(pm.s, 0.5), clamp(pm.l, 0.3, 0.7)).concat([1]); }, 12), s: grad(function (t) { return fromHsl(pm.h, t, pm.l).concat([1]); }, 6),
      l: grad(function (t) { return fromHsl(pm.h, pm.s, t).concat([1]); }, 8),
    };
    var solid = TB.hexRgba(pmHex || "#000");
    tracks.a = "linear-gradient(90deg,rgba(" + Math.round(solid[0] * 255) + "," + Math.round(solid[1] * 255) + "," + Math.round(solid[2] * 255) + ",0),rgb(" + Math.round(solid[0] * 255) + "," + Math.round(solid[1] * 255) + "," + Math.round(solid[2] * 255) + "))";
    Object.keys(sliderEls).forEach(function (k) {
      var s = sliderEls[k], v = vals[k];
      s.inp.style.setProperty("--track", tracks[k]);
      if (document.activeElement !== s.inp) s.inp.value = v;
      s.out.textContent = k === "H" || k === "h" ? Math.round(v) + "°" : k === "C" ? v.toFixed(3) : k === "a" ? Math.round(v * 100) + "%" : k === "L" ? (v * 100).toFixed(1) : Math.round(v * 100) + "%";
    });
  }
  cp.hex.addEventListener("input", function () {
    var v = readHex(cp.hex.value);
    cp.hex.setAttribute("aria-invalid", v ? "false" : "true");
    cp.hex.title = v ? "" : S.badHex;
    if (!v || !popState) return;
    loadModel(v);
    applyPop(v);
  });
  cp.hex.addEventListener("blur", function () { cp.hex.setAttribute("aria-invalid", "false"); if (popState) cp.hex.value = TB.normHex(colorOf(popState.id, popState.mode)); });
  cp.eye.addEventListener("click", function () {
    if (!window.EyeDropper || !popState) return;
    new window.EyeDropper().open().then(function (r) {
      var v = readHex(r && r.sRGBHex);
      if (!v) return;
      var a = TB.hexRgba(colorOf(popState.id, popState.mode))[3], c = TB.hexRgba(v);
      c[3] = a;
      v = TB.toHex(c);
      loadModel(v);
      applyPop(v);
      pushRecent(v);
    }, function () {});
  });
  $("[data-cp-copy]", pop).addEventListener("click", function () { if (popState) copyText(TB.normHex(colorOf(popState.id, popState.mode)), function () { say(S.copied); }); });
  $("[data-cp-close]", pop).addEventListener("click", function () { closePop(true); });
  $("[data-cp-revert]", pop).addEventListener("click", function () {
    if (!popState) return;
    var v = popState.orig[popState.id + "@" + popState.mode];
    if (!v) return;
    loadModel(v);
    applyPop(v);
  });
  cp.lock.addEventListener("click", function () {
    if (!popState || idKind(popState.id) !== "tok") return;
    toggleLock(popState.id);
  });
  cp.layer.addEventListener("click", function () {
    if (!popState || !popState.info || !popState.info.comp) return;
    var start = popState.info.comp.start - structBase;
    closePop();
    selectTab("tbx-t-layout");
    openLayerAt(start);
  });
  function pushRecent(hex) {
    hex = TB.normHex(hex);
    recent = [hex].concat(recent.filter(function (x) { return x !== hex; })).slice(0, 20);
    store("lc-tb-recent", JSON.stringify(recent));
    if (popState) fillSwatches();
  }
  function swatchButton(hex, title, onPick) {
    var b = h("button", { type: "button", "class": "tbx-sw", title: title, "aria-label": title }), i = h("i");
    swatch(i, hex);
    b.appendChild(i);
    b.addEventListener("click", onPick);
    return b;
  }
  function fillSwatches() {
    var p = popState, seen = {}, list = [];
    TB.TOKENS.forEach(function (t) { var v = rgbPart(state.colors[p.mode][t]); if (!seen[v]) { seen[v] = 1; list.push([v, t]); } });
    state.roles[p.mode].forEach(function (c, i) { var v = rgbPart(c); if (!seen[v]) { seen[v] = 1; list.push([v, S.role + " " + (i + 1)]); } });
    cp.theme.textContent = "";
    list.slice(0, 30).forEach(function (x) {
      cp.theme.appendChild(swatchButton(x[0], x[1] + " · " + x[0], function () {
        var a = TB.hexRgba(colorOf(p.id, p.mode))[3], c = TB.hexRgba(x[0]);
        c[3] = a;
        var v = TB.toHex(c);
        loadModel(v);
        applyPop(v);
      }));
    });
    cp.recent.textContent = "";
    cp.recentLbl.hidden = !recent.length;
    recent.forEach(function (hex) {
      cp.recent.appendChild(swatchButton(hex, hex, function () { loadModel(hex); applyPop(hex); }));
    });
  }
  // As linhas de contraste que envolvem esta cor (como texto ou como fundo).
  function fillPopContrast() {
    var p = popState;
    cp.contrast.textContent = "";
    if (idKind(p.id) !== "tok") return;
    var rows = TB.contrastReport(state, p.mode).filter(function (r) { return r.fg === p.id || r.backs.indexOf(p.id) >= 0; });
    rows.forEach(function (r) {
      var ok = !r.fails.length, lv = r.level || (ok ? "ok" : "bad");
      var li = h("div", { "class": "tbx-cc " + lv }, [
        h("span", { "class": "tbx-badge " + lv, text: ({ ok: "✓ ", auto: "↑ ", low: "~ ", bad: "! " })[lv] + fmtRatio(r.ratio) }),
        h("span", {}, [h("code", { text: r.fg }), S.on_ + (ok ? r.backs : r.fails).join(", ")]),
        h("span", { "class": "tbx-tok-v", text: (r.app ? S.needs : S.wcag) + r.min + ":1" }),
      ]);
      if (!ok && r.fix) {
        var b = lv === "auto" ? h("button", { type: "button", "class": "tbx-link", text: S.keepLift(r.fix.value) })
          : h("button", { type: "button", "class": "tbx-b sm" }, [h("i", { "class": "tb-dot", style: "background:" + r.fix.value }), (r.app ? S.use : S.fix + " · ") + r.fix.value]);
        b.addEventListener("click", function () { set(function (s) { s.colors[p.mode][r.fix.tok] = r.fix.value; }); if (r.fix.tok === p.id) { loadModel(r.fix.value); } });
        li.appendChild(b);
      }
      cp.contrast.appendChild(li);
    });
  }
  function fillPopTokens() {
    var p = popState;
    cp.toks.textContent = "";
    if (p.ids.length < 2) return;
    p.ids.forEach(function (id) {
      var i = h("i"), b = h("button", { type: "button", role: "tab", "aria-selected": id === p.id ? "true" : "false" }, [i, idLabel(id)]);
      swatch(i, colorOf(id, p.mode));
      b.addEventListener("click", function () { p.id = id; p.orig[id + "@" + p.mode] = p.orig[id + "@" + p.mode] || colorOf(id, p.mode); syncPop(true); });
      cp.toks.appendChild(b);
    });
  }
  function popWarning() {
    var p = popState, w = "";
    if (idKind(p.id) === "tok") {
      var eff = TB.effectiveColors(state, p.mode);
      if (TB.own(eff.gated, p.id)) w = S.warnGated(eff.gated[p.id].line);
      else if (p.info && TB.own(p.info.over, p.id)) w = S.warnOver(p.id, p.info.over[p.id]);
    }
    if (!w && p.info && p.info.literal && p.id === p.info.tokens[p.info.tokens.length - 1]) w = S.warnLit(p.info.literal);
    cp.warn.hidden = !w;
    cp.warn.textContent = w;
  }
  function syncPop(fromState) {
    var p = popState;
    if (!p) return;
    var hex = TB.normHex(colorOf(p.id, p.mode));
    if (fromState && hex !== pmHex) loadModel(hex);
    cp.title.textContent = idLabel(p.id);
    cp.title.appendChild(h("small", { text: S.mode[p.mode] }));
    cp.desc.textContent = idDesc(p.id);
    cp.swi.style.background = css(hex);
    if (document.activeElement !== cp.hex) cp.hex.value = hex;
    var tok = idKind(p.id) === "tok";
    cp.lock.hidden = !tok;
    cp.lock.setAttribute("aria-pressed", tok && locks[p.id] ? "true" : "false");
    cp.lock.title = tok && locks[p.id] ? S.unlock + p.id : S.lock;
    cp.lock.replaceChild(icon(tok && locks[p.id] ? "lock" : "unlock"), cp.lock.querySelector("svg"));
    cp.layer.hidden = !(p.info && p.info.comp);
    if (p.info && p.info.comp) cp.layer.textContent = S.layer(p.info.comp.name, p.info.comp.line - (kdlNow.slice(0, structBase).split("\n").length - 1));
    paintSliders();
    fillPopTokens();
    popWarning();
    fillPopContrast();
    fillSwatches();
    $$(".tbx-tok", box).forEach(function (t) { t.classList.toggle("on", t.dataset.id === p.id); });
  }
  function placePop(anchor) {
    if (matchMedia("(max-width: 899.98px)").matches) { pop.style.left = ""; pop.style.top = ""; return; }
    // Fica acima da barra de baixo do palco (o zoom e o contraste continuam à vista), não só dentro da janela.
    var cb = canvas.getBoundingClientRect().bottom, vw = innerWidth, vh = Math.min(innerHeight, cb), top0 = popTop(), x, y;
    pop.style.maxHeight = Math.max(240, vh - top0 - 10) + "px";
    var w = pop.offsetWidth || 316, hh = pop.offsetHeight || 480;
    if (anchor.width !== undefined) {
      x = anchor.right + 10;
      if (x + w > vw - 10) x = anchor.left - w - 10;
      y = anchor.top - 20;
    } else {
      x = anchor.x + 18;
      if (x + w > vw - 10) x = anchor.x - w - 18;
      y = anchor.y - 60;
    }
    pop.style.left = clamp(x, 10, vw - w - 10) + "px";
    pop.style.top = clamp(y, top0, Math.max(top0, vh - hh - 10)) + "px";
  }
  // O topo do site fica por cima do palco (o main tem z-index 0 e o topo, 45), então o editor
  // começa abaixo dele: numa janela baixa, o título, o cadeado e o fechar ficariam sem clique.
  // Na tela cheia, ou com a prévia ocupando a janela, o topo fica por baixo e vale a janela toda.
  function popTop() {
    var nav = document.querySelector("[data-topnav]");
    return fullOn() || !nav ? 10 : Math.max(10, nav.getBoundingClientRect().bottom + 10);
  }
  // `kbd`: aberto pelo teclado (Enter ou Espaço numa cor do painel): o foco vai para o campo hex.
  // Pelo mouse ou pelo toque o foco fica onde está (num celular, focar o campo abriria o teclado).
  function openPop(ids, id, m, anchor, info, opener, kbd) {
    var orig = popState && popState.mode === m ? popState.orig : {};
    popState = { ids: ids, id: id, mode: m, info: info || null, orig: orig, opener: opener || null };
    ids.forEach(function (x) { if (!orig[x + "@" + m]) orig[x + "@" + m] = colorOf(x, m); });
    loadModel(colorOf(id, m));
    pop.hidden = false;
    syncPop(false);
    placePop(anchor);
    hideHl();
    popRoom(anchor);
    if (kbd) { cp.hex.focus(); cp.hex.select(); }
  }
  // Numa tela estreita o editor é uma folha (embaixo; com o aparelho deitado, uma coluna à direita)
  // e cobriria a prévia. Então o palco encolhe para o espaço que sobra (o CSS lê --pop-h e --pop-w),
  // a prévia é ajustada de novo ali, mostra só o modo editado e, com zoom, rola até o ponto clicado.
  function popSize() {
    body.style.setProperty("--pop-h", pop.offsetHeight + "px");
    body.style.setProperty("--pop-w", pop.offsetWidth + "px");
  }
  function popRoom(anchor) {
    var kind = popState && matchMedia(NARROW).matches ? (matchMedia(SIDEWAYS).matches ? "side" : "bottom") : "";
    if (kind) popSize();
    if (kind !== popKind) {
      popKind = kind;
      if (kind) body.dataset.pop = kind; else delete body.dataset.pop;
      // O tema dos dois modos é refeito: o que mudou enquanto um deles estava fora da vista aparece.
      if (state) refresh();
      lastCanvas = canvas.offsetWidth + "x" + canvas.offsetHeight;
    }
    if (kind && anchor && anchor.fx !== undefined && zoom !== "fit") reveal(anchor);
  }
  function reveal(a) {
    var sc = screens.filter(function (x) { return !x.el.hidden && x.mode === popState.mode; })[0];
    if (!sc) return;
    var r = sc.fbox.getBoundingClientRect(), c = canvas.getBoundingClientRect();
    canvas.scrollLeft += r.left + a.fx * r.width - (c.left + canvas.clientWidth / 2);
    canvas.scrollTop += r.top + a.fy * r.height - (c.top + canvas.clientHeight / 2);
  }
  if (window.ResizeObserver) new ResizeObserver(function () { if (popKind) popSize(); }).observe(pop);
  addEventListener("resize", function () { if (popState || popKind) popRoom(); });
  // Enquanto o foco está no editor, o Tab dá a volta dentro dele; Esc fecha e devolve o foco.
  pop.addEventListener("keydown", function (e) {
    if (e.key !== "Tab") return;
    var f = [].slice.call(pop.querySelectorAll("button,input,[tabindex='0']")).filter(function (x) { return !x.disabled && x.tabIndex >= 0 && x.offsetParent !== null; });
    if (!f.length) return;
    var i = f.indexOf(document.activeElement);
    if (e.shiftKey && i <= 0) { e.preventDefault(); f[f.length - 1].focus(); }
    else if (!e.shiftKey && (i === f.length - 1 || i < 0)) { e.preventDefault(); f[0].focus(); }
  });
  function closePop(focusBack) {
    if (!popState) return;
    var back = focusBack && popState.opener && popState.opener.isConnected ? popState.opener : null;
    popState = null;
    pop.hidden = true;
    $$(".tbx-tok.on", box).forEach(function (t) { t.classList.remove("on"); });
    // Primeiro o painel volta (numa tela estreita ele desceu), depois o foco vai para quem abriu.
    popRoom();
    if (back) back.focus();
  }
  document.addEventListener("pointerdown", function (e) {
    if (!popState || pop.contains(e.target)) return;
    // A barra de baixo (zoom, contraste) também não fecha: numa tela estreita, fechar ali mexeria o
    // palco antes do clique chegar ao botão.
    if (e.target.closest(".tbx-fbox,[data-pop-src],.tbx-status")) return;
    closePop();
  });
  buildSliders();

  // ------------------------------------------------------- Painéis ----
  var tabs = $$('[role="tab"]', $(".tbx-rail")), panelEl = $("[data-panel]");
  function selectTab(id, keepPanel) {
    var t = document.getElementById(id) || tabs[0];
    tabs.forEach(function (x) {
      var on = x === t;
      x.setAttribute("aria-selected", on ? "true" : "false");
      x.tabIndex = on ? 0 : -1;
      document.getElementById(x.getAttribute("aria-controls")).hidden = !on;
    });
    if (!keepPanel) setPanel(true);
    if (sheetIs("peek")) setSheet("half");
    store("lc-tb-tab", t.id);
    if (t.id === "tbx-t-layout") scheduleThumbs(true);
    if (t.id === "tbx-t-code") fillCode();
  }
  tabs.forEach(function (t, i) {
    t.addEventListener("click", function () {
      if (t.getAttribute("aria-selected") === "true" && !box.classList.contains("panel-off") && !matchMedia("(max-width: 899.98px)").matches) return;
      selectTab(t.id);
    });
    t.addEventListener("keydown", function (e) {
      var d = e.key === "ArrowDown" || e.key === "ArrowRight" ? 1 : e.key === "ArrowUp" || e.key === "ArrowLeft" ? -1 : 0;
      if (e.key === "Home") d = -i;
      if (e.key === "End") d = tabs.length - 1 - i;
      if (!d) return;
      e.preventDefault();
      var n = tabs[(i + d + tabs.length) % tabs.length];
      selectTab(n.id);
      n.focus();
    });
  });
  var panelToggle = $("[data-panel-toggle]");
  function setPanel(on) {
    box.classList.toggle("panel-off", !on);
    panelToggle.setAttribute("aria-expanded", on ? "true" : "false");
    store("lc-tb-panel", on ? "on" : "off");
  }
  panelToggle.addEventListener("click", function () { setPanel(box.classList.contains("panel-off")); });
  $$("[data-goto]", document).forEach(function (b) {
    b.addEventListener("click", function () {
      closeExport();
      selectTab("tbx-t-" + b.dataset.goto);
      var f = $("[data-m-name]");
      if (b.dataset.goto === "file" && f) setTimeout(function () { f.focus(); f.select(); }, 60);
    });
  });

  // A folha de baixo (tablet e celular): fechada, metade, inteira.
  var side = $("[data-side]"), body = $("[data-body]");
  function sheetIs(s) { return matchMedia("(max-width: 899.98px)").matches && side.dataset.sheet === s; }
  function setSheet(s) {
    side.dataset.sheet = s;
    body.dataset.sheet = s;
  }
  $("[data-sheet-handle]").addEventListener("click", function () {
    var order = ["peek", "half", "full"];
    setSheet(order[(order.indexOf(side.dataset.sheet) + 1) % 3]);
  });

  // Rola só o painel (scrollIntoView também rolaria a página).
  function scrollPanelTo(el, mid) {
    var pr = panelEl.getBoundingClientRect(), r = el.getBoundingClientRect();
    var to = panelEl.scrollTop + r.top - pr.top - (mid ? (pr.height - r.height) / 2 : 44);
    if (panelEl.scrollTo) panelEl.scrollTo({ top: Math.max(0, to), behavior: "smooth" }); else panelEl.scrollTop = to;
  }

  // ---- Cores
  var groupsBox = $("[data-token-groups]"), tokenRows = {};
  function buildColors() {
    groupsBox.textContent = "";
    GROUPS.forEach(function (g) {
      var sec = h("div", { "class": "tbx-group" }, [h("h3", { text: S.groups[g[0]] })]);
      g[1].forEach(function (tok) {
        var swi = h("i"), val = h("span", { "class": "tbx-tok-v" }), badge = h("span", { "class": "tbx-badge", hidden: true });
        var gtag = h("em", { text: S.gatedTag, hidden: true });
        var row = h("button", { type: "button", "class": "tbx-tok", "data-id": tok, "data-pop-src": "", "aria-label": tok + " · " + S.tok[tok] }, [
          h("span", { "class": "tbx-tok-sw" }, [swi]), h("span", { "class": "tbx-tok-n" }, [tok, gtag]), h("span", { "class": "tbx-tok-m" }, [badge, val]),
          h("span", { "class": "tbx-tok-d", text: S.tok[tok] }),
        ]);
        row.addEventListener("click", function (e) {
          if (popState && popState.id === tok && popState.mode === mode && !pop.hidden) return closePop(e.detail === 0);
          openPop([tok], tok, mode, row.getBoundingClientRect(), null, row, e.detail === 0);
        });
        row.addEventListener("pointerenter", function () { flashToken(tok); });
        row.addEventListener("pointerleave", function () { if (!popState) hideHl(); });
        var lk = h("button", { type: "button", "class": "tbx-lock", "aria-pressed": "false", title: S.lock, "aria-label": S.lock + ": " + tok, "data-pop-src": "" }, [icon("unlock")]);
        lk.addEventListener("click", function () { toggleLock(tok); });
        var wrap = h("div", { "class": "tbx-tokwrap", "data-s": tok + " " + S.tok[tok] }, [row, lk]);
        sec.appendChild(wrap);
        tokenRows[tok] = { row: row, sw: swi, val: val, badge: badge, gtag: gtag, lock: lk };
      });
      groupsBox.appendChild(sec);
    });
    var roles = $("[data-roles]"), pal = $("[data-pal]");
    for (var i = 0; i < 8; i++) roles.appendChild(idSwatch("role:" + i));
    for (var j = 0; j < 16; j++) pal.appendChild(idSwatch("pal:" + j, String(j)));
  }
  function idSwatch(id, small) {
    var i = h("i"), b = h("button", { type: "button", "class": "tbx-sw", "data-sw": id, "data-pop-src": "", "aria-label": idLabel(id) }, [i, small ? h("small", { text: small }) : null]);
    b.addEventListener("click", function (e) { openPop([id], id, mode, b.getBoundingClientRect(), null, b, e.detail === 0); });
    return b;
  }
  // Passar o mouse numa cor do painel acende onde ela aparece na prévia.
  function flashToken(tok) {
    var sc = screens.filter(function (s) { return !s.el.hidden && s.mode === mode; })[0];
    if (!sc) return;
    var sels = P.INSPECT.filter(function (e) { return e[1][0] === tok; }).map(function (e) { return e[0]; });
    sels.push('.pv-b[data-tk^="' + tok + '"]', '.pv-b[data-fg="' + tok + '"]');
    var best = null, area = 0;
    [].forEach.call(sc.frame.querySelectorAll(sels.join(",")), function (el) {
      if (P.tokensAt(el, sc.frame).tokens[0] !== tok) return;
      var r = el.getBoundingClientRect(), a = r.width * r.height;
      if (a > area) { area = a; best = el; }
    });
    if (best) showHl(best, tok, state.colors[mode][tok], ""); else hideHl();
  }
  function fillColors() {
    var c = state.colors[mode];
    $("[data-edit-mode]").textContent = "";
    $("[data-edit-mode]").appendChild(icon(mode === "dark" ? "moon" : "sun"));
    $("[data-edit-mode]").appendChild(document.createTextNode(S.editing + S.mode[mode]));
    var blocks = TB.layoutColorBlocks(state, mode).filter(function (b) { return b.kind !== "colors" || b.tokens.length; }), gatedToks = {}, note = $("[data-gated]");
    note.textContent = "";
    blocks.forEach(function (b) {
      b.tokens.forEach(function (t) { gatedToks[t] = true; });
      note.appendChild(h("p", { text: S.gated(b, b.tokens) }));
    });
    note.hidden = !blocks.length;
    var report = {};
    TB.contrastReport(state, mode).forEach(function (r) { report[r.fg] = r; });
    TB.TOKENS.forEach(function (tok) {
      var r = tokenRows[tok], v = c[tok];
      swatch(r.sw, v);
      r.val.textContent = TB.normHex(v);
      r.gtag.hidden = !gatedToks[tok];
      var cr = report[tok];
      if (cr && TEXT_TOKS.indexOf(tok) >= 0) {
        var lv = cr.level || (cr.fails.length ? "bad" : "ok");
        r.badge.hidden = false;
        r.badge.className = "tbx-badge " + lv;
        r.badge.textContent = ({ ok: "", auto: "↑ ", low: "~ ", bad: "! " })[lv] + fmtRatio(cr.ratio);
        r.badge.title = (cr.app ? S.needs : S.wcag) + cr.min + ":1" + (lv === "auto" ? " · " + S.autoMark : lv === "low" ? " · " + S.lowMark : "");
      } else r.badge.hidden = true;
      r.lock.setAttribute("aria-pressed", locks[tok] ? "true" : "false");
      r.lock.replaceChild(icon(locks[tok] ? "lock" : "unlock"), r.lock.firstChild);
    });
    $$("[data-sw]").forEach(function (b) { swatch(b.firstChild, colorOf(b.dataset.sw, mode)); b.title = idLabel(b.dataset.sw) + " · " + TB.normHex(colorOf(b.dataset.sw, mode)); });
    $("[data-invert-label]").textContent = S.invert[mode];
    $("[data-other-label]").textContent = S.other[mode];
  }
  function toggleLock(tok) {
    if (locks[tok]) delete locks[tok]; else locks[tok] = true;
    fillColors();
    fillLocks();
    if (popState) syncPop(false);
  }
  $("[data-recolor]").addEventListener("click", function () {
    set(function (s) { var p = TB.fromPalette(s.palette[mode], mode); s.colors[mode] = p.colors; s.roles[mode] = p.roles; });
  });
  $("[data-invert]").addEventListener("click", function () {
    var from = mode;
    set(function (s) { var n = TB.invertMode(s, from); s.colors = n.colors; s.roles = n.roles; s.palette = n.palette; });
    say(S.inverted[from]);
    if (view !== "split") setView("split");
  });
  $("[data-other]").addEventListener("click", function () {
    var g = TB.generate(TB.seedFromColors(state.colors[mode])), o = mode === "dark" ? "light" : "dark";
    set(function (s) { s.colors[o] = g.colors[o]; s.roles[o] = g.roles[o]; });
    if (view !== "split") setView("split");
  });
  $("[data-view-split]").addEventListener("click", function () { setView("split"); });

  // ---- Contraste
  var contrastList = $("[data-contrast]"), contrastSum = $("[data-contrast-sum]"), chip = $("[data-contrast-chip]");
  var showAllChecks = false;
  var allBtn = h("button", { type: "button", "class": "tbx-link" });
  allBtn.addEventListener("click", function () { showAllChecks = !showAllChecks; renderContrast(); });
  $("[data-contrast-box]").insertBefore(allBtn, $(".tbx-more", $("[data-contrast-box]")));
  // Três níveis além do "ok": o que o app ajusta sozinho (neutro), o que só passa para texto
  // grande (âmbar) e o que vai aparecer mesmo (vermelho). O chip e o resumo só alarmam pelo último.
  function needsLook(r) { return r.level === "bad" || r.level === "low"; }
  function renderContrast() {
    var rows = TB.contrastReport(state, mode), bad = rows.filter(function (r) { return r.level === "bad"; }), low = rows.filter(function (r) { return r.level === "low"; });
    var auto = rows.filter(function (r) { return r.level === "auto"; }).length;
    var other = mode === "dark" ? "light" : "dark", otherBad = TB.contrastReport(state, other).filter(needsLook).length;
    contrastSum.textContent = (bad.length || low.length ? S.issues(bad.length, low.length) : S.contrastOk) + (auto ? " " + S.lifted(auto) : "") + " " + S.otherIssues(S.mode[other], otherBad);
    contrastList.textContent = "";
    contrastList.classList.toggle("all", showAllChecks);
    allBtn.textContent = showAllChecks ? S.hideOk : S.showAll;
    var seen = TB.effectiveColors(state, mode).toks, order = { bad: 0, low: 1, auto: 2, ok: 3 };
    // O que pede atenção primeiro; o que o app ajusta sozinho depois, numa linha curta.
    rows.slice().sort(function (a, b) { return order[a.level || "ok"] - order[b.level || "ok"]; }).forEach(function (r) {
      var ok = !r.fails.length, lv = r.level || (ok ? "ok" : "bad");
      var li = h("li", { "class": lv }, [
        h("span", { "class": "tbx-mark" }, [h("span", { "aria-hidden": "true", text: { ok: "✓", auto: "↑", low: "~", bad: "!" }[lv] }), h("span", { "class": "tbx-sr", text: { ok: S.passes, auto: S.autoMark, low: S.lowMark, bad: S.fails }[lv] })]),
        h("span", { "class": "tbx-pair" }, [h("i", { "class": "tb-dot", style: "background:" + TB.cssColor(seen[r.fg]) }), h("code", { text: r.fg }), S.on_ + (ok ? r.backs : r.fails).join(", "), h("small", { text: (r.app ? S.needs : S.wcag) + r.min + ":1" })]),
        h("span", { "class": "tbx-ratio" }, [h("strong", { text: fmtRatio(r.ratio) })]),
      ]);
      if (!ok) {
        if (lv === "low") li.appendChild(h("p", { "class": "tbx-lift", text: S.lowNote }));
        if (r.app && r.lift) li.appendChild(h("p", { "class": "tbx-lift", text: lv === "auto" ? S.shownAs(r.lift) : S.lifts + r.lift + S.liftsEnd }));
        if (r.gated) li.appendChild(h("p", { "class": "tbx-lift", text: S.fromLayout(r.gated.line) }));
        else if (r.stuck) li.appendChild(h("p", { "class": "tbx-lift", text: S.stuck }));
      }
      if (!ok && r.fix) {
        var b = lv === "auto" ? h("button", { type: "button", "class": "tbx-link tbx-fix", text: S.keepLift(r.fix.value) })
          : h("button", { type: "button", "class": "tbx-b sm tbx-fix" }, [h("i", { "class": "tb-dot", style: "background:" + r.fix.value }), (r.app ? S.use + r.fix.value : S.fix + " · " + r.fix.value)]);
        b.addEventListener("click", function () { set(function (s) { s.colors[mode][r.fix.tok] = r.fix.value; }); });
        li.appendChild(b);
      }
      contrastList.appendChild(li);
    });
    $("[data-fixall]").hidden = !rows.some(function (r) { return r.fix && needsLook(r); });
    chip.classList.toggle("bad", bad.length > 0);
    chip.classList.toggle("low", !bad.length && low.length > 0);
    $("[data-contrast-chip-t]").textContent = bad.length ? S.chipBad(bad.length) : low.length ? S.chipLow(low.length) : S.chipOk;
  }
  $("[data-fixall]").addEventListener("click", function () {
    set(function (s) {
      for (var round = 0; round < 4; round++) {
        var fixes = TB.contrastReport(s, mode).filter(function (r) { return r.fix && needsLook(r); });
        if (!fixes.length) break;
        fixes.forEach(function (r) { s.colors[mode][r.fix.tok] = r.fix.value; });
      }
    });
  });
  chip.addEventListener("click", function () {
    closePop();
    selectTab("tbx-t-colors");
    var c = $("[data-contrast-box]");
    scrollPanelTo(c, false);
    c.animate([{ boxShadow: "0 0 0 2px var(--accent)" }, { boxShadow: "0 0 0 0 transparent" }], { duration: 900 });
  });

  // ---- Gerador
  var genHex = $("[data-gen-hex]"), genBase = $("[data-gen-base]"), harmBox = $("[data-harmonies]");
  var genSliders = { neutral: $("[data-gen-neutral]"), chroma: $("[data-gen-chroma]"), lightness: $("[data-gen-light]") };
  var genOuts = { neutral: $("[data-gen-neutral-out]"), chroma: $("[data-gen-chroma-out]"), lightness: $("[data-gen-light-out]") };
  var genLive = $("[data-gen-live]");
  if (store("lc-tb-genlive") === "off") genLive.checked = false;
  genLive.addEventListener("change", function () { store("lc-tb-genlive", genLive.checked ? "on" : "off"); });
  var harmButtons = {};
  Object.keys(TB.HARMONY).forEach(function (k) {
    var wheel = h("span", { "class": "tbx-wheel", "aria-hidden": "true" });
    var b = h("button", { type: "button", role: "radio", "aria-checked": "false", "data-h": k }, [wheel, S.harmonies[k]]);
    harmBox.appendChild(b);
    harmButtons[k] = { b: b, wheel: wheel };
  });
  radioKeys(Object.keys(harmButtons).map(function (k) { return harmButtons[k].b; }), function (b) { gen.scheme = b.dataset.h; fillGen(); genChanged(); });
  // Cada roda: o anel com os matizes (OKLCH, de 30 em 30 graus, 0° no alto) e um ponto em cada
  // matiz que a harmonia vai usar a partir da cor base (destaque, menção e link). Na escolhida,
  // os pontos têm as cores que o gerador vai pôr no modo escuro.
  var ringCss = (function () {
    var st = [];
    for (var d = 0; d <= 360; d += 30) st.push(TB.toHex(TB.oklch(0.74, 0.13, d)).slice(0, 7) + " " + d + "deg");
    return "conic-gradient(" + st.join(",") + ")";
  })();
  function drawWheels(g) {
    var A = TB.toOklch(TB.hexRgba(gen.base))[2];
    Object.keys(harmButtons).forEach(function (k) {
      var w = harmButtons[k].wheel, off = TB.HARMONY[k], mono = k === "mono";
      w.textContent = "";
      w.style.setProperty("--ring", ringCss);
      w.appendChild(h("i"));
      if (!mono) { var u = h("u"); u.style.setProperty("--c", gen.base); w.appendChild(u); }
      var real = k === gen.scheme && g ? [g.colors.dark.accent, g.colors.dark.mention, g.colors.dark.link] : null;
      [0, off[0], off[1]].forEach(function (d, i) {
        var hue = ((A + d) % 360 + 360) % 360, rad = hue * Math.PI / 180, r = mono ? [41, 28, 15][i] : 41;
        var c = real ? real[i] : TB.toHex(TB.oklch(clamp(gen.lightness - (mono ? i * 0.14 : 0), 0.3, 0.95), Math.max(0.07, gen.chroma), hue));
        var b = h("b");
        b.style.left = (50 + r * Math.sin(rad)).toFixed(2) + "%";
        b.style.top = (50 - r * Math.cos(rad)).toFixed(2) + "%";
        b.style.setProperty("--c", TB.normHex(c).slice(0, 7));
        w.appendChild(b);
      });
    });
  }
  function genSeed() { return TB.seedFromBase(gen.base, gen.scheme, { neutral: gen.neutral, chroma: gen.chroma, lightness: gen.lightness }); }
  function fillGen() {
    swatch(genBase.firstChild, gen.base);
    if (document.activeElement !== genHex) genHex.value = TB.normHex(gen.base).slice(0, 7);
    Object.keys(harmButtons).forEach(function (k) { var on = k === gen.scheme; harmButtons[k].b.setAttribute("aria-checked", on ? "true" : "false"); harmButtons[k].b.tabIndex = on ? 0 : -1; });
    Object.keys(genSliders).forEach(function (k) {
      if (document.activeElement !== genSliders[k]) genSliders[k].value = gen[k];
      genOuts[k].textContent = k === "lightness" ? Math.round(gen[k] * 100) + "%" : gen[k].toFixed(3);
    });
    var g = TB.generate(genSeed()), strip = $("[data-gen-strip]");
    drawWheels(g);
    strip.textContent = "";
    [g.colors.dark.bg, g.colors.dark.surface, g.colors.dark.text, g.colors.dark.accent, g.colors.dark.mention, g.colors.dark.link, g.colors.light.bg, g.colors.light.accent].forEach(function (c) {
      var i = h("i"); swatch(i, c); strip.appendChild(i);
    });
  }
  function fillLocks() {
    var holder = $("[data-locks]"), names = Object.keys(locks);
    holder.textContent = "";
    $("[data-locks-empty]").hidden = names.length > 0;
    names.forEach(function (t) {
      var i = h("i"), b = h("button", { type: "button", title: S.unlock + t, "aria-label": S.unlock + t }, [i, t, icon("close")]);
      swatch(i, state.colors[mode][t]);
      b.addEventListener("click", function () { toggleLock(t); });
      holder.appendChild(b);
    });
  }
  function applyGen(msg) {
    var g = TB.generate(genSeed());
    set(function (s) { var n = TB.applyGenerated(s, g, locks); s.colors = n.colors; s.roles = n.roles; s.palette = n.palette; }, "gen");
    if (msg) say(msg);
  }
  function genChanged() { if (genLive.checked) applyGen(); }
  function setBase(hex, fromPop) {
    gen.base = TB.normHex(hex).slice(0, 7);
    var o = TB.toOklch(TB.hexRgba(gen.base));
    gen.chroma = clamp(Math.round(o[1] / 0.005) * 0.005, 0, 0.24);
    gen.lightness = clamp(Math.round(o[0] * 100) / 100, 0.55, 0.9);
    fillGen();
    if (fromPop) { cp.swi.style.background = css(gen.base); paintSliders(); }
    genChanged();
  }
  genBase.addEventListener("click", function (e) { openPop(["base"], "base", mode, genBase.getBoundingClientRect(), null, genBase, e.detail === 0); });
  genBase.setAttribute("data-pop-src", "");
  genHex.addEventListener("input", function () {
    var v = readHex(genHex.value);
    genHex.setAttribute("aria-invalid", v ? "false" : "true");
    if (v) setBase(v);
  });
  $("[data-gen-from-accent]").addEventListener("click", function () { setBase(state.colors[mode].accent); });
  Object.keys(genSliders).forEach(function (k) {
    genSliders[k].addEventListener("input", function () { gen[k] = +genSliders[k].value; fillGen(); genChanged(); });
  });
  $("[data-gen-apply]").addEventListener("click", function () { applyGen(S.genDone); });
  function surprise() {
    var r = Math.random, schemes = Object.keys(TB.HARMONY);
    gen.scheme = schemes[Math.floor(r() * schemes.length)];
    gen.base = TB.toHex(TB.oklch(0.66 + r() * 0.16, 0.09 + r() * 0.11, r() * 360)).slice(0, 7);
    gen.neutral = Math.round((0.004 + r() * 0.034) * 500) / 500;
    var o = TB.toOklch(TB.hexRgba(gen.base));
    gen.chroma = Math.round(o[1] / 0.005) * 0.005;
    gen.lightness = Math.round(o[0] * 100) / 100;
    fillGen();
    applyGen(S.surprise + S.harmonies[gen.scheme]);
  }
  $("[data-surprise]").addEventListener("click", surprise);

  // Imagem: soltar na prévia ou no painel, ou escolher. Lida aqui, nunca enviada.
  var imgInput = document.querySelector("[data-image-file]");
  function readImage(file) {
    if (!file || !/^image\//.test(file.type || "image/")) return;
    if (file.size > 20 * 1024 * 1024) return say(S.imageBig);
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
        gen.image = colors.map(function (c) { return c.hex; });
        var seed = TB.seedFromImage(colors), gg = TB.generate(seed);
        gen.base = gg.colors.dark.accent.slice(0, 7);
        set(function (s) { var n = TB.applyGenerated(s, gg, locks); s.colors = n.colors; s.roles = n.roles; s.palette = n.palette; });
        fillImageSwatches();
        fillGen();
        say(S.imageDone);
      } catch (e) {
        say(S.imageFail);
      }
      URL.revokeObjectURL(url);
    };
    img.onerror = function () { URL.revokeObjectURL(url); say(S.imageFail); };
    img.src = url;
  }
  function fillImageSwatches() {
    var holder = $("[data-imgs]");
    holder.textContent = "";
    holder.hidden = !gen.image.length;
    if (!gen.image.length) return;
    holder.appendChild(h("p", { text: S.fromImage }));
    gen.image.forEach(function (hex) { holder.appendChild(swatchButton(hex, hex, function () { setBase(hex); })); });
  }
  imgInput.addEventListener("change", function () { var f = imgInput.files && imgInput.files[0]; imgInput.value = ""; readImage(f); });
  $("[data-drop]").addEventListener("click", function () { imgInput.click(); });
  $$("[data-image]").forEach(function (b) { b.addEventListener("click", function () { closeMenu(); imgInput.click(); }); });
  var dropzone = $("[data-dropzone]"), dragDepth = 0;
  function hasImage(e) { return e.dataTransfer && [].some.call(e.dataTransfer.types || [], function (t) { return t === "Files"; }); }
  [stage, $("[data-drop]")].forEach(function (zone) {
    zone.addEventListener("dragenter", function (e) { if (!hasImage(e)) return; e.preventDefault(); dragDepth++; if (zone === stage) dropzone.hidden = false; else zone.classList.add("over"); });
    zone.addEventListener("dragover", function (e) { if (hasImage(e)) { e.preventDefault(); e.dataTransfer.dropEffect = "copy"; } });
    zone.addEventListener("dragleave", function () { dragDepth = Math.max(0, dragDepth - 1); if (!dragDepth) { dropzone.hidden = true; zone.classList.remove("over"); } });
    zone.addEventListener("drop", function (e) {
      if (!hasImage(e)) return;
      e.preventDefault();
      dragDepth = 0;
      dropzone.hidden = true;
      zone.classList.remove("over");
      readImage(e.dataTransfer.files && e.dataTransfer.files[0]);
    });
  });

  // ---- Layout: miniaturas
  var thumbsBox = $("[data-thumbs]"), thumbs = {}, thumbTimer = 0, thumbKey = "";
  DATA.order.forEach(function (n) {
    var frame = h("div", { "class": "tb-frame", "aria-hidden": "true" }), mini = h("span", { "class": "tbx-mini" }, [frame]);
    var b = h("button", { type: "button", "class": "tbx-thumb", "aria-pressed": "false", "data-s": n + " layout" }, [mini, h("span", { text: n })]);
    b.title = (lang === "pt" ? DATA.themes[n].desc : DATA.themes[n].descEn) || n;
    b.addEventListener("click", function () {
      set(function (s) {
        // A miniatura nas Configurações e a descrição que vieram do layout anterior sem ninguém
        // mexer acompanham o layout novo; o que a pessoa escreveu ou escolheu fica.
        var from = s.layoutFrom || s.base, old = from && TB.own(startMeta, from) ? startMeta[from] : null, nw = startMeta[n];
        if (old && from !== n) {
          if (s.meta.preview === old.preview) s.meta.preview = nw.preview;
          if (s.meta.desc === old.desc) s.meta.desc = nw.desc;
          if (s.meta.descEn === old.descEn) s.meta.descEn = nw.descEn;
        }
        s.structure = structures[n];
        s.layoutFrom = n;
      });
      say(S.layoutNow + n);
    });
    thumbsBox.appendChild(b);
    thumbs[n] = { b: b, frame: frame, mini: mini };
  });
  function scheduleThumbs(now) {
    clearTimeout(thumbTimer);
    if ($("#tbx-p-layout").hidden && !$(".tbx-panel").classList.contains("searching")) return;
    thumbTimer = setTimeout(renderThumbs, now ? 30 : 450);
  }
  function renderThumbs() {
    if (!state) return;
    var key = JSON.stringify([state.colors[mode], state.roles[mode], state.palette[mode], state.fonts, state.radius, mode]);
    if (key === thumbKey) return;
    thumbKey = key;
    var names = DATA.order.slice(), i = 0;
    (function next() {
      if (i >= names.length) return;
      var n = names[i++], t = thumbs[n];
      try {
        var s = TB.clone(state);
        s.structure = structures[n];
        P.mount(t.frame, TB.loadTheme(TB.toKdl(s), { mode: mode }));
        var w = t.mini.clientWidth || 140;
        t.frame.style.transform = "scale(" + w / W + ")";
      } catch (e) { t.frame.textContent = ""; }
      requestAnimationFrame(next);
    })();
  }
  if (window.ResizeObserver) new ResizeObserver(function () {
    Object.keys(thumbs).forEach(function (n) { var w = thumbs[n].mini.clientWidth; if (w) thumbs[n].frame.style.transform = "scale(" + w / W + ")"; });
  }).observe(thumbsBox);

  // ---- Layout: opções e camadas
  var layersBox = $("[data-layers]"), optBox = $("[data-options]"), layerShape = "", openPath = null, outlineNow = [];
  function pathOf(list) {
    var byStart = {};
    list.forEach(function (o) { byStart[o.start] = o; o.path = (o.parent !== null && byStart[o.parent] ? byStart[o.parent].path + "." : "") + o.index; });
    return list;
  }
  function outlineOf(structure) { try { return pathOf(TB.outline(structure)); } catch (e) { return null; } }
  function startAt(structure, path) {
    var o = outlineOf(structure);
    if (!o) return null;
    for (var i = 0; i < o.length; i++) if (o[i].path === path) return o[i].start;
    return null;
  }
  function editNode(path, fn, key) {
    set(function (s) {
      var st = startAt(s.structure, path);
      if (st === null) return;
      s.structure = fn(s.structure, st);
      if (s.layoutFrom && structures[s.layoutFrom] !== s.structure) s.layoutFrom = null;
    }, key);
  }
  var LAYER_IC = { row: "row", column: "column", stack: "stack" };
  function fieldLabel(v) {
    if (v === true) return S.on;
    if (v === false) return S.off;
    if (typeof v === "string" && v.charAt(0) === "$") return S.follows + v.replace(/^\$/, "");
    return String(v);
  }
  function chipGroup(path, f, opts) {
    var g = h("div", { "class": "tbx-chips", role: "radiogroup", "aria-label": f.key });
    var cur = f.value === undefined ? "" : f.value;
    var list = [["", S.def]].concat(opts);
    if (cur !== "" && !list.some(function (o) { return o[0] === cur; })) list.push([cur, fieldLabel(cur)]);
    list.forEach(function (o) {
      var b = h("button", { type: "button", role: "radio", "aria-checked": o[0] === cur ? "true" : "false", "class": o[0] === "" ? "def" : null, "data-ctl": path + ":" + f.key, "data-v": JSON.stringify(o[0]), text: o[1] });
      b.addEventListener("click", function () {
        editNode(path, function (t, st) { return TB.setProp(t, st, f.key, o[0] === "" ? null : o[0]); }, "tw:" + path + ":" + f.key);
      });
      g.appendChild(b);
    });
    return g;
  }
  var STATUS_ITEMS = ["conn", "ping", "ram", "frame", "voice", "spacer", "theme", "keys", "clock", "me", "mic", "deaf"];
  function propControl(o, f) {
    var path = o.path, wrap = h("div", { "class": "tbx-prop" }), head = h("p", {}, [h("code", { text: f.key })]);
    // Os números levam o nome na mesma linha do campo, e o controle deslizante ganha a largura toda.
    if (f.kind !== "num") wrap.appendChild(head);
    if (f.kind === "enum") wrap.appendChild(chipGroup(path, f, f.options.map(function (x) { return [x, x]; })));
    else if (f.kind === "bool") wrap.appendChild(chipGroup(path, f, [[true, S.on], [false, S.off]]));
    else if (f.kind === "num") {
      var rg = f.range || [0, 400, 1], v = typeof f.value === "number" ? f.value : null;
      var slider = h("input", { type: "range", min: rg[0], max: rg[1], step: rg[2], "aria-label": f.key, "data-ctl": path + ":" + f.key });
      var number = h("input", { type: "number", "class": "tbx-num", step: rg[2], min: Math.min(rg[0], -1), max: 4000, placeholder: "—", "aria-label": f.key, "data-ctl": path + ":" + f.key });
      var reset = h("button", { type: "button", "class": "tbx-reset", title: S.reset, "aria-label": S.reset + ": " + f.key, disabled: v === null }, [icon("close")]);
      slider.value = v === null ? rg[0] : v;
      number.value = v === null ? "" : v;
      var apply = function (val) { editNode(path, function (t, st) { return TB.setProp(t, st, f.key, val); }, "tw:" + path + ":" + f.key); };
      slider.addEventListener("input", function () { number.value = slider.value; apply(+slider.value); });
      number.addEventListener("input", function () {
        var n = parseFloat(number.value);
        if (number.value === "") return apply(null);
        if (isFinite(n)) { slider.value = n; apply(clamp(n, -1, 4000)); }
      });
      reset.addEventListener("click", function () { apply(null); });
      wrap.appendChild(h("div", { "class": "tbx-propnum" }, [h("code", { text: f.key }), number, reset, slider]));
    } else {
      var inp = h("input", { type: "text", "class": "tbx-in mono", spellcheck: "false", value: f.value === undefined ? "" : String(f.value), "data-ctl": path + ":" + f.key, "aria-label": f.key });
      inp.addEventListener("input", function () { editNode(path, function (t, st) { return TB.setProp(t, st, f.key, inp.value === "" ? null : inp.value); }, "tw:" + path + ":" + f.key); });
      wrap.appendChild(inp);
      if (o.name === "status-bar" && f.key === "items") {
        var items = String(f.value || "conn ping ram spacer theme keys clock").split(/\s+/), chips = h("div", { "class": "tbx-chips" });
        STATUS_ITEMS.forEach(function (it) {
          var on = items.indexOf(it) >= 0, b = h("button", { type: "button", "aria-pressed": on ? "true" : "false", text: it });
          b.addEventListener("click", function () {
            var now = items.indexOf(it) >= 0 ? items.filter(function (x) { return x !== it; }) : items.concat([it]);
            editNode(path, function (t, st) { return TB.setProp(t, st, "items", now.join(" ")); }, "tw:" + path + ":items");
          });
          chips.appendChild(b);
        });
        chips.style.marginTop = "6px";
        wrap.appendChild(chips);
      }
    }
    return wrap;
  }
  function highlightLayer(o) {
    if (!o) return hideHl();
    var sc = screens.filter(function (s) { return !s.el.hidden; })[0];
    var el = sc && sc.frame.querySelector('.pv-b[data-start="' + (o.start + structBase) + '"]');
    if (el) showHl(el, o.name, null, o.variant || ""); else hideHl();
  }
  function buildLayers(list) {
    var focus = document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.ctl : null;
    layersBox.textContent = "";
    list.forEach(function (o) {
      var isOpen = o.path === openPath, hidden = o.show === false;
      var li = h("li", { "class": "tbx-layer" + (isOpen ? " open" : "") + (hidden ? " hidden-node" : ""), style: "--d:" + Math.min(o.depth, 8), "data-path": o.path });
      var name = h("button", { type: "button", "class": "tbx-lname", "aria-expanded": isOpen ? "true" : "false" }, [
        (function () { var s = icon("chev"); s.setAttribute("class", "tbx-chev"); return s; })(), icon(LAYER_IC[o.name] || "comp"), h("span", { text: o.name }),
        o.variant ? h("em", { text: o.variant }) : null, o.when || o.unless ? h("em", { "class": "tbx-cond", text: o.when ? S.when + o.when : S.unless + o.unless }) : null,
      ]);
      name.addEventListener("click", function () { openPath = openPath === o.path ? null : o.path; buildLayers(outlineNow); });
      var eye = h("button", { type: "button", "class": "tbx-ib", "aria-pressed": hidden ? "true" : "false", title: hidden ? S.show : S.hide, "aria-label": (hidden ? S.show : S.hide) + ": " + o.name }, [icon(hidden ? "eyeoff" : "eye")]);
      eye.addEventListener("click", function () {
        editNode(o.path, function (t, st) { return TB.setProp(t, st, "show", hidden ? null : false); });
        // Esconder uma camada que tem as mensagens, a caixa de mensagem ou os canais: avisa, com Desfazer.
        if (!hidden) {
          var lost = TB.essentialInside(outlineNow, o.start);
          if (lost.length) say(S.hidEssential(o.name, lost), { label: S.undo, run: undo });
        }
      });
      var up = h("button", { type: "button", "class": "tbx-ib", title: S.up, "aria-label": S.up + ": " + o.name, disabled: o.index <= 0 }, [icon("up")]);
      var down = h("button", { type: "button", "class": "tbx-ib", title: S.down, "aria-label": S.down + ": " + o.name, disabled: o.index >= o.count - 1 }, [icon("down")]);
      function move(dir) {
        var newPath = o.path.replace(/\d+$/, String(o.index + dir));
        editNode(o.path, function (t, st) { return TB.moveNode(t, st, dir); });
        if (openPath === o.path) openPath = newPath;
      }
      up.addEventListener("click", function () { move(-1); });
      down.addEventListener("click", function () { move(1); });
      var row = h("div", { "class": "tbx-lrow" }, [name, h("span", { "class": "tbx-lctl" }, [eye, up, down])]);
      row.addEventListener("pointerenter", function () { highlightLayer(o); });
      row.addEventListener("pointerleave", hideHl);
      li.appendChild(row);
      if (isOpen) {
        var props = h("div", { "class": "tbx-lprops" });
        if (!o.fields.length) props.appendChild(h("p", { "class": "tbx-noprops", text: S.noProps }));
        o.fields.forEach(function (f) { props.appendChild(propControl(o, f)); });
        li.appendChild(props);
      }
      layersBox.appendChild(li);
    });
    if (focus) { var el = layersBox.querySelector('[data-ctl="' + focus + '"]'); if (el && el.focus) el.focus(); }
  }
  // Mesma árvore: só os valores mudam (assim o controle que está sendo arrastado não some).
  function updateLayerValues(list) {
    var by = {};
    list.forEach(function (o) { o.fields.forEach(function (f) { by[o.path + ":" + f.key] = f; }); });
    $$("[data-ctl]", layersBox).forEach(function (el) {
      var f = by[el.dataset.ctl];
      if (!f || el === document.activeElement) return;
      if (el.getAttribute("role") === "radio") {
        var cur = f.value === undefined ? "" : f.value;
        el.setAttribute("aria-checked", JSON.stringify(cur) === el.dataset.v ? "true" : "false");
      } else if (el.type === "range") el.value = typeof f.value === "number" ? f.value : el.min;
      else if (el.type === "number") el.value = typeof f.value === "number" ? f.value : "";
      else if (el.type === "text") el.value = f.value === undefined ? "" : String(f.value);
    });
    $$(".tbx-reset", layersBox).forEach(function (b) { var n = b.parentElement.querySelector(".tbx-num"); b.disabled = !n || n.value === ""; });
  }
  function openLayerAt(start) {
    var o = outlineNow.filter(function (x) { return x.start === start; })[0];
    if (!o) return;
    openPath = o.path;
    buildLayers(outlineNow);
    var li = layersBox.querySelector('[data-path="' + o.path + '"]');
    if (li) { scrollPanelTo(li, true); var b = li.querySelector(".tbx-lname"); if (b) b.focus({ preventScroll: true }); }
  }
  function fillLayout() {
    $("[data-layout-now]").textContent = S.layoutNow + (state.layoutFrom || S.custom);
    Object.keys(thumbs).forEach(function (n) { thumbs[n].b.setAttribute("aria-pressed", state.layoutFrom === n ? "true" : "false"); });
    var list = outlineOf(state.structure);
    if (!list) return;
    outlineNow = list;
    var shape = list.map(function (o) { return o.path + o.name + (o.show === false ? "-" : "+") + (o.variant || "") + (o.when || "") + (o.unless || ""); }).join("|") + "@" + openPath;
    if (shape !== layerShape) { layerShape = shape; buildLayers(list); } else updateLayerValues(list);
    var opts = TB.structureOptions(state.structure), sig = JSON.stringify(opts.map(function (o) { return [o.name, o.def]; }));
    if (optBox.dataset.sig === sig) return;
    optBox.dataset.sig = sig;
    optBox.textContent = "";
    if (!opts.length) optBox.appendChild(h("p", { "class": "tbx-hint", text: S.noOptions }));
    opts.forEach(function (o) {
      var label = lang === "en" ? o.labelEn || o.label : o.label, desc = lang === "en" ? o.descEn || o.desc : o.desc;
      var cb = h("input", { type: "checkbox", checked: o.def });
      cb.addEventListener("change", function () {
        set(function (s) {
          var cur = TB.structureOptions(s.structure).filter(function (x) { return x.name === o.name; })[0];
          if (cur) s.structure = TB.setProp(s.structure, cur.node.start, "default", cb.checked);
          if (s.layoutFrom && structures[s.layoutFrom] !== s.structure) s.layoutFrom = null;
        });
      });
      optBox.appendChild(h("label", { "class": "tbx-switch", "data-s": o.name + " " + label + " " + (desc || "") }, [cb, h("span", { "class": "tbx-sw-ui", "aria-hidden": "true" }),
        h("span", {}, [h("b", { text: label }), " ", h("code", { text: o.name }), desc ? h("small", { text: desc }) : null])]));
    });
  }

  // ---- Letra e forma
  var FONT_UI = ["Inter", "Noto Sans", "IBM Plex Sans", "Fira Sans", "DejaVu Sans", "Liberation Sans", "Segoe UI", "Georgia", "Liberation Serif"];
  var FONT_MONO = ["JetBrains Mono", "Fira Code", "Iosevka", "DejaVu Sans Mono", "Liberation Mono", "Cascadia Code", "Consolas", "Monaspace Argon"];
  [["ui", FONT_UI, "system-ui,sans-serif"], ["mono", FONT_MONO, "ui-monospace,monospace"]].forEach(function (d) {
    var holder = $('[data-font-chips="' + d[0] + '"]');
    d[1].forEach(function (name) {
      var b = h("button", { type: "button", "aria-pressed": "false", "data-font": name, title: name }, [h("b", { text: "Ag" }), h("small", { text: name })]);
      b.firstChild.style.fontFamily = '"' + name + '",' + d[2];
      b.addEventListener("click", function () { set(function (s) { s.fonts[d[0]] = name; }); });
      holder.appendChild(b);
    });
  });
  function bindField(sel, apply, key) {
    var el = $(sel);
    el.addEventListener(el.type === "checkbox" ? "change" : "input", function () {
      var v = el.type === "checkbox" ? el.checked : el.value;
      set(function (s) { apply(s, v); }, key);
    });
  }
  function num(v, lo, hi, d) { var n = parseFloat(v); return isFinite(n) ? Math.min(hi, Math.max(lo, n)) : d; }
  bindField("[data-f-ui]", function (s, v) { s.fonts.ui = v.trim() || "Inter"; }, "font-ui");
  bindField("[data-f-mono]", function (s, v) { s.fonts.mono = v.trim() || "JetBrains Mono"; }, "font-mono");
  bindField("[data-f-size]", function (s, v) { s.fonts.size = num(v, 6, 72, 16); }, "font-size");
  bindField("[data-f-size-n]", function (s, v) { s.fonts.size = num(v, 6, 72, 16); }, "font-size");
  bindField("[data-f-radius]", function (s, v) { s.radius = num(v, 0, 64, 6); }, "radius");
  bindField("[data-f-radius-n]", function (s, v) { s.radius = num(v, 0, 64, 6); }, "radius");
  bindField("[data-f-transparent]", function (s, v) { s.transparent = v; });
  bindField("[data-m-name]", function (s, v) { s.meta.name = v; }, "name");
  bindField("[data-m-author]", function (s, v) { s.meta.author = v; }, "author");
  bindField("[data-m-license]", function (s, v) { s.meta.license = v.trim(); }, "license");
  bindField("[data-m-desc]", function (s, v) { s.meta.desc = v; }, "desc");
  bindField("[data-m-desc-en]", function (s, v) { s.meta.descEn = v; }, "desc-en");
  var RADII = [0, 6, 12, 20];
  RADII.forEach(function (r, i) {
    var t = h("i"), b = h("button", { type: "button", "aria-pressed": "false", "data-r": r }, [t, S.radii[i] + " · " + r]);
    t.style.borderTopLeftRadius = Math.min(r, 20) + "px";
    b.addEventListener("click", function () { set(function (s) { s.radius = r; }); });
    $("[data-radii]").appendChild(b);
  });
  // As miniaturas das Configurações: um esboço de cada uma (retângulos em %).
  var KINDS = {
    classic: [[0, 0, 12, 100, 1], [12, 0, 22, 100], [38, 20, 40, 8], [38, 40, 50, 8], [38, 60, 34, 8]],
    glass: [[4, 6, 26, 88], [34, 6, 62, 88], [40, 30, 40, 8, 1]],
    terminal: [[6, 14, 60, 7], [6, 30, 74, 7], [6, 46, 44, 7, 1], [6, 62, 66, 7]],
    bubbles: [[8, 16, 40, 16], [52, 40, 40, 16, 1], [8, 64, 46, 16]],
    zen: [[30, 20, 40, 8], [30, 40, 40, 8], [30, 60, 30, 8, 1]],
    mirror: [[88, 0, 12, 100, 1], [66, 0, 22, 100], [8, 30, 50, 8]],
    office: [[0, 0, 100, 16, 1], [0, 16, 22, 84], [28, 34, 56, 8], [28, 54, 44, 8]],
    desktop: [[6, 10, 50, 50], [40, 36, 54, 54, 1]],
  };
  Object.keys(KINDS).forEach(function (k) {
    var pic = h("span", { "class": "tbx-kind" });
    KINDS[k].forEach(function (r) {
      var e = h(r[4] ? "b" : "i");
      e.style.cssText = "left:" + r[0] + "%;top:" + r[1] + "%;width:" + r[2] + "%;height:" + r[3] + "%";
      pic.appendChild(e);
    });
    var b = h("button", { type: "button", role: "radio", "aria-checked": "false", "data-kind": k }, [pic, k]);
    $("[data-kinds]").appendChild(b);
  });
  radioKeys($$("[data-kind]"), function (b) { set(function (s) { s.meta.preview = b.dataset.kind; }); });
  function put(sel, v) {
    var el = $(sel);
    if (!el || document.activeElement === el) return;
    if (el.type === "checkbox") el.checked = !!v; else el.value = v;
  }
  function fillType() {
    put("[data-f-ui]", state.fonts.ui);
    put("[data-f-mono]", state.fonts.mono);
    put("[data-f-size]", state.fonts.size);
    put("[data-f-size-n]", state.fonts.size);
    put("[data-f-radius]", Math.min(24, state.radius));
    put("[data-f-radius-n]", state.radius);
    put("[data-f-transparent]", state.transparent);
    // Janela transparente com o bg opaco: nada muda, no app nem na prévia. O aviso diz o que falta.
    $("[data-f-clear-note]").hidden = !(state.transparent && MODES.every(function (m) { return TB.hexRgba(colorOf("bg", m))[3] >= 0.999; }));
    $$("[data-font]").forEach(function (b) { b.setAttribute("aria-pressed", b.dataset.font === state.fonts.ui || b.dataset.font === state.fonts.mono ? "true" : "false"); });
    $$("[data-r]").forEach(function (b) { b.setAttribute("aria-pressed", +b.dataset.r === state.radius ? "true" : "false"); });
    $$("[data-kind]").forEach(function (b) { var on = b.dataset.kind === state.meta.preview; b.setAttribute("aria-checked", on ? "true" : "false"); b.tabIndex = on ? 0 : -1; });
    var sample = $("[data-type-sample]");
    sample.style.fontFamily = P.fontOf(state.fonts.ui).replace("var(--f-ui)", "system-ui,sans-serif");
    sample.style.fontSize = clamp(state.fonts.size, 8, 32) + "px";
    sample.style.borderRadius = clamp(state.radius, 0, 24) + "px";
  }
  function fillFile() {
    put("[data-m-name]", state.meta.name);
    put("[data-m-author]", state.meta.author);
    put("[data-m-license]", state.meta.license || "");
    put("[data-m-desc]", state.meta.desc);
    put("[data-m-desc-en]", state.meta.descEn);
  }

  // ---- Código
  var adv = $("[data-adv]"), advStatus = $("[data-adv-status]"), advPre = $("[data-adv-hl]"), shownStructure = null, advTimer = 0;
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
  adv.addEventListener("scroll", function () { advPre.parentElement.scrollTop = adv.scrollTop; advPre.parentElement.scrollLeft = adv.scrollLeft; });
  adv.addEventListener("keydown", function (e) {
    if (e.key === "Tab" && !e.shiftKey && !e.ctrlKey && !e.altKey) {
      e.preventDefault();
      adv.setRangeText("    ", adv.selectionStart, adv.selectionEnd, "end");
      adv.dispatchEvent(new Event("input"));
    }
  });
  // Realce do KDL: o texto passa por esc() antes de virar HTML.
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
  var codeShown = "";
  function fillCode() {
    if (!state) return;
    if (shownStructure !== state.structure && document.activeElement !== adv) {
      shownStructure = state.structure;
      adv.value = state.structure;
      advPre.innerHTML = hl(adv.value);
    }
    if ($("#tbx-p-code").hidden || codeShown === kdlNow) return;
    codeShown = kdlNow;
    $("[data-code]").innerHTML = hl(kdlNow);
  }

  // ---- Pronto para a galeria?
  var builtinDescs = [];
  DATA.order.forEach(function (n) { builtinDescs.push(DATA.themes[n].desc, DATA.themes[n].descEn); });
  function renderReady() {
    var checks = TB.communityCheck(state, DATA.order, builtinDescs), bad = checks.filter(function (c) { return !c.ok; }).length, list = $("[data-ready]");
    list.textContent = "";
    checks.forEach(function (c) {
      var val = c.id === "name" ? c.file + ".kdl" : c.id === "author" ? state.meta.author : c.id === "license" ? state.meta.license : "";
      var why = c.ok ? val : typeof S.readyBad[c.id] === "function" ? S.readyBad[c.id](c) : S.readyBad[c.id];
      list.appendChild(h("li", { "class": c.ok ? "ok" : "bad" }, [
        h("span", { "class": "tbx-mark" }, [h("span", { "aria-hidden": "true", text: c.ok ? "✓" : "!" }), h("span", { "class": "tbx-sr", text: c.ok ? S.passes : S.fails })]),
        h("span", {}, [h("strong", { text: S.ready[c.id] }), why ? " · " + why : null]),
      ]));
    });
    $("[data-ready-sum]").textContent = bad ? S.readyMissing(bad) : S.readyOk(TB.slug(state.meta.name) + ".kdl");
    $("[data-export-ready]", document).textContent = S.readyShort(bad);
  }

  // ---------------------------------------------------------- Tudo ----
  function refresh() {
    if (!state) return;
    var kdl = TB.toKdl(state, { url: DATA.url }), file = TB.slug(state.meta.name), trimmed = String(state.structure || "").replace(/\s+$/, "");
    kdlNow = kdl;
    structBase = trimmed ? kdl.lastIndexOf(trimmed) : kdl.length;
    $$("[data-fname]", document).forEach(function (e) { e.textContent = file + ".kdl"; });
    $$("[data-tname]", document).forEach(function (e) { e.textContent = file; });
    $("[data-export-size]", document).textContent = S.lines(kdl.split("\n").length - 1, (new Blob([kdl]).size / 1024).toFixed(1));
    var failed = null;
    MODES.forEach(function (m) {
      if (screenModes().indexOf(m) < 0 && lastGood[m]) return;
      try { lastGood[m] = TB.loadTheme(kdl, { mode: m }); } catch (e) { failed = failed || e; }
    });
    // Nada desenhado ainda (um link com o layout estragado, logo ao abrir): em vez do palco vazio,
    // as suas cores no layout de que o tema partiu, e o aviso diz isso.
    var fellBack = "";
    if (failed) MODES.forEach(function (m) {
      if (lastGood[m]) return;
      var n = [state.layoutFrom, state.base, html.dataset.theme, "orbital"].filter(function (x) { return x && TB.own(structures, x); })[0];
      if (!n) return;
      try { var alt = TB.clone(state); alt.structure = structures[n]; lastGood[m] = TB.loadTheme(TB.toKdl(alt, { url: DATA.url }), { mode: m }); fellBack = n; }
      catch (e) { try { lastGood[m] = TB.loadTheme(DATA.themes[n].src, { mode: m }); fellBack = n; } catch (e2) {} }
    });
    if (failed) {
      var line = failed.line ? failed.line - (kdl.slice(0, structBase).split("\n").length - 1) : 0, why = TB.errorText(failed, lang), kept = fellBack ? S.fallback(fellBack) : S.kept;
      errBox.hidden = false;
      errBox.textContent = S.errAt + (failed.line || "?") + (failed.column ? ":" + failed.column : "") + ": " + why + " · " + kept;
      advStatus.className = "tbx-adv-status err";
      advStatus.textContent = (line > 0 ? "layout:" + line + (failed.column ? ":" + failed.column : "") + ": " : "") + why + " · " + kept;
    } else {
      errBox.hidden = true;
      advStatus.className = "tbx-adv-status";
      advStatus.textContent = S.advOk;
    }
    measure();
    renderPreviews();
    applyScale();
    fillColors();
    renderContrast();
    fillType();
    fillFile();
    fillLayout();
    fillLocks();
    fillCode();
    renderReady();
    if (popState) syncPop(true);
    $("[data-undo]").disabled = !undoStack.length;
    $("[data-redo]").disabled = !redoStack.length;
    scheduleThumbs();
    scheduleHash();
  }

  // ----------------------------------------------------------- Busca ----
  var search = $("[data-search]");
  function norm(s) { return String(s).toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, ""); }
  // Um item aparece se ele, algo dentro dele ou a seção em volta casa com a busca.
  function runSearch() {
    var q = norm(search.value.trim()), items = $$("[data-s]", panelEl), any = false;
    panelEl.classList.toggle("searching", !!q);
    items.forEach(function (el) { el.hidden = false; el.dataset.hit = !q || norm(el.dataset.s + " " + el.textContent).indexOf(q) >= 0 ? "1" : ""; });
    if (q) items.forEach(function (el) {
      var up = el.parentElement && el.parentElement.closest("[data-s]"), show = !!el.dataset.hit;
      while (!show && up) { if (up.dataset.hit) show = true; up = up.parentElement && up.parentElement.closest("[data-s]"); }
      if (!show) show = $$("[data-s]", el).some(function (k) { return !!k.dataset.hit; });
      el.hidden = !show;
      if (el.dataset.hit) any = true;
    });
    $$(".tbx-group", panelEl).forEach(function (g) { g.hidden = !!q && !$$(".tbx-tokwrap", g).some(function (w) { return !w.hidden; }); });
    $("[data-noresult]").hidden = !q || any;
    if (q) scheduleThumbs(true);
  }
  search.addEventListener("input", runSearch);
  search.addEventListener("keydown", function (e) { if (e.key === "Escape" && search.value) { e.preventDefault(); e.stopPropagation(); search.value = ""; runSearch(); } });

  // --------------------------------------------------- Menu Abrir ----
  var menuBtn = $("[data-menu-btn]"), menu = $("[data-menu]");
  DATA.order.forEach(function (n) {
    var strip = h("i");
    startSwatches[n].forEach(function (c) { var b = h("b"); swatch(b, c); strip.appendChild(b); });
    var b = h("button", { type: "button", "class": "tbx-start", title: (lang === "pt" ? DATA.themes[n].desc : DATA.themes[n].descEn) || n }, [strip, n]);
    b.addEventListener("click", function () { closeMenu(); replace(startFrom(n), S.started + n); });
    $("[data-starts]").appendChild(b);
  });
  (function () {
    var holder = $("[data-community-list]");
    var names = Array.isArray(DATA.community) ? DATA.community.filter(function (n) { return /^[a-z0-9-]{1,48}$/.test(n); }) : [];
    if (!names.length) {
      holder.appendChild(h("p", {}, [S.noCommunity + " ", DATA.gallery ? h("a", { href: DATA.gallery, text: S.seeGallery }) : null]));
      return;
    }
    names.forEach(function (n) {
      var a = h("a", { href: "#community=" + n }, [n + ".kdl"]);
      a.addEventListener("click", function (e) { e.preventDefault(); closeMenu(); loadCommunity(n); });
      holder.appendChild(a);
    });
    if (DATA.gallery) holder.appendChild(h("p", {}, [h("a", { href: DATA.gallery, text: S.seeGallery })]));
  })();
  function openMenu() {
    menu.hidden = false;
    menuBtn.setAttribute("aria-expanded", "true");
    var r = menuBtn.getBoundingClientRect(), w = menu.offsetWidth;
    menu.style.left = clamp(r.right - w, 10, innerWidth - w - 10) + "px";
    menu.style.top = (r.bottom + 8) + "px";
    var first = menu.querySelector("button,a");
    if (first) first.focus();
  }
  function closeMenu(focusBack) {
    if (menu.hidden) return;
    menu.hidden = true;
    menuBtn.setAttribute("aria-expanded", "false");
    if (focusBack) menuBtn.focus();
  }
  menuBtn.addEventListener("click", function () { if (menu.hidden) openMenu(); else closeMenu(); });
  document.addEventListener("pointerdown", function (e) { if (!menu.hidden && !menu.contains(e.target) && !menuBtn.contains(e.target)) closeMenu(); });

  // --------------------------------------------------- Exportar ----
  var sheet = document.querySelector("[data-export]"), scrim = null, sheetOpener = null;
  function openExport() {
    closePop();
    closeMenu();
    var a = document.activeElement;
    sheetOpener = a && a !== document.body && a.focus && !sheet.contains(a) ? a : null;
    sheet.classList.add("open");
    sheet.removeAttribute("aria-hidden");
    if (!scrim) {
      scrim = h("div", { "class": "tbx-scrim" });
      scrim.addEventListener("click", closeExport);
    }
    // Na mesma camada da folha (dentro de <main>, que tem o seu próprio z-index): no <body>, o
    // fundo escuro ficaria por cima da folha e engoliria os cliques.
    sheet.parentNode.insertBefore(scrim, sheet);
    setTimeout(function () { var b = sheet.querySelector("[data-download]"); if (b) b.focus(); }, 40);
  }
  function closeExport() {
    if (!sheet.classList.contains("open")) return;
    sheet.classList.remove("open");
    sheet.setAttribute("aria-hidden", "true");
    if (scrim && scrim.parentNode) scrim.remove();
    // Quem abriu pode ter sumido (ou era o <body>, pelo atalho E): então o botão Exportar da barra.
    var back = sheetOpener && sheetOpener.isConnected && sheetOpener.offsetParent !== null ? sheetOpener : $(".tbx-top [data-export-open]");
    if (back) back.focus();
  }
  sheet.setAttribute("aria-hidden", "true");
  $$("[data-export-open]").forEach(function (b) { b.addEventListener("click", openExport); });
  sheet.querySelector("[data-export-close]").addEventListener("click", closeExport);
  sheet.addEventListener("keydown", function (e) {
    if (e.key !== "Tab") return;
    var f = [].slice.call(sheet.querySelectorAll("button,a,[tabindex='0']")).filter(function (x) { return x.offsetParent !== null; });
    var i = f.indexOf(document.activeElement);
    if (e.shiftKey && i <= 0) { e.preventDefault(); f[f.length - 1].focus(); }
    else if (!e.shiftKey && i === f.length - 1) { e.preventDefault(); f[0].focus(); }
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
  function shareUrl() { return TB.encode(state, builtinStructure).then(function (tok) { return location.href.split("#")[0] + "#t=" + tok; }); }
  $$("[data-share]", document).forEach(function (b) {
    b.addEventListener("click", function () {
      shareUrl().then(function (u) { history.replaceState(null, "", u); copyText(u, function () { say(S.linkCopied); }); });
    });
  });
  document.querySelector("[data-copy-kdl]").addEventListener("click", function () { copyText(TB.toKdl(state, { url: DATA.url }), function () { say(S.kdlCopied); }); });
  document.querySelector("[data-download]").addEventListener("click", function () {
    var name = TB.slug(state.meta.name) + ".kdl", blob = new Blob([TB.toKdl(state, { url: DATA.url })], { type: "text/plain;charset=utf-8" });
    var a = h("a", { href: URL.createObjectURL(blob), download: name });
    document.body.appendChild(a);
    a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 500);
    say(S.downloaded + name);
  });
  // As abas das instruções (Linux, Windows).
  (function () {
    var list = [].slice.call(document.querySelectorAll("[data-ostabs] [role=tab]"));
    function pick(t) {
      list.forEach(function (x) {
        var on = x === t;
        x.setAttribute("aria-selected", on ? "true" : "false");
        x.tabIndex = on ? 0 : -1;
        document.getElementById(x.getAttribute("aria-controls")).hidden = !on;
      });
    }
    radioKeys(list, pick);
    if (/Windows/i.test(navigator.userAgent)) pick(list[1]);
  })();

  // --------------------------------------------- Importar (.kdl e CSS) ----
  var dlg = document.querySelector("[data-import-dialog]"), dlgText = $("[data-import-text]", dlg), dlgErr = $("[data-import-error]", dlg), dlgFile = $("[data-import-file]", dlg);
  var importName = "";
  $$("[data-import]").forEach(function (b) {
    b.addEventListener("click", function () {
      closeMenu();
      dlgErr.textContent = "";
      if (dlg.showModal) dlg.showModal(); else dlg.setAttribute("open", "");
      dlgText.focus();
    });
  });
  dlgFile.addEventListener("change", function () {
    var f = dlgFile.files && dlgFile.files[0];
    if (!f) return;
    importName = f.name.replace(/\.kdl$/i, "");
    f.text().then(function (t) { dlgText.value = t; dlgErr.textContent = ""; });
  });
  $("[data-import-cancel]", dlg).addEventListener("click", function () { dlg.close ? dlg.close() : dlg.removeAttribute("open"); });
  $("[data-import-load]", dlg).addEventListener("click", function () {
    try {
      var next = TB.fromSource(dlgText.value, { name: importName });
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
  // O CSS só passa pelo leitor de theme-builder-core.js: nunca vira HTML, estilo ou pedido de rede.
  var cssDlg = document.querySelector("[data-css-dialog]"), cssText = $("[data-css-text]", cssDlg), cssErr = $("[data-css-error]", cssDlg);
  var cssReportBox = $("[data-css-report]", cssDlg), cssFile = $("[data-css-file]", cssDlg);
  function cssReset() { cssErr.textContent = ""; cssReportBox.hidden = true; cssReportBox.textContent = ""; }
  $$("[data-css]").forEach(function (b) {
    b.addEventListener("click", function () {
      closeMenu();
      cssReset();
      if (cssDlg.showModal) cssDlg.showModal(); else cssDlg.setAttribute("open", "");
      cssText.focus();
    });
  });
  $("[data-css-cancel]", cssDlg).addEventListener("click", function () { cssDlg.close ? cssDlg.close() : cssDlg.removeAttribute("open"); });
  cssFile.addEventListener("change", function () {
    var f = cssFile.files && cssFile.files[0];
    cssFile.value = "";
    if (!f) return;
    cssReset();
    if (f.size > TB.CSS_MAX) { cssErr.textContent = S.css.fail + TB.errorText({ code: "css-too-big" }, lang); return; }
    f.text().then(function (t) { cssText.value = t; }, function () { cssErr.textContent = S.css.readFail; });
  });
  function cssRow(tok, m, extra) {
    return h("li", {}, [h("i", { "class": "tb-dot", style: "background:" + TB.cssColor(TB.hexRgba(state.colors[m][tok])) }), h("code", { text: tok }), extra]);
  }
  function cssReport(res) {
    var bx = cssReportBox, cs = S.css;
    bx.textContent = "";
    var d = res.modes.dark.mapped.length, l = res.modes.light ? res.modes.light.mapped.length : null;
    bx.appendChild(h("p", { "class": "tb-css-sum", text: cs.summary(d, l, res.vars) }));
    MODES.forEach(function (m) {
      var r = res.modes[m];
      if (!r) return;
      var list = h("ul", { "class": "tb-css-map" });
      r.mapped.forEach(function (x) {
        list.appendChild(cssRow(x.tok, m, h("span", {}, [cs.from, h("code", { text: x.from }), x.alpha !== undefined ? cs.flat(x.alpha, x.over) : null, x.swapped && x.tok === "faint" ? cs.swapped : null])));
      });
      r.derived.forEach(function (x) { list.appendChild(cssRow(x.tok, m, h("span", { text: " · " + cs.derived(x.value, x.from) }))); });
      var sec = h("details", { "class": "tb-css-mode", open: m === mode }, [h("summary", { text: cs.mode[m] + " · " + (r.mapped.length + r.derived.length) }), list]);
      r.skipped.forEach(function (x) { sec.appendChild(h("p", { "class": "tb-lift", text: cs.skipped[x.why](x.tok, x.from) })); });
      sec.appendChild(h("p", { "class": "tb-lift", text: r.kept.length ? cs.kept + r.kept.join(", ") : cs.noneKept }));
      bx.appendChild(sec);
    });
    if (!res.modes.light) bx.appendChild(h("p", { "class": "tb-lift", text: cs.noLight }));
    bx.appendChild(h("p", { "class": "tb-lift", text: cs.rest }));
    if (res.imports.length) {
      bx.appendChild(h("p", { "class": "tb-lift", text: cs.imports(res.imports.length) }));
      var ul = h("ul", { "class": "tb-css-imports" });
      res.imports.slice(0, 20).forEach(function (u) { ul.appendChild(h("li", {}, [h("code", { text: u })])); });
      bx.appendChild(ul);
    }
    var broken = Object.keys(res.notes).reduce(function (a, k) { return a + res.notes[k]; }, 0);
    if (broken) bx.appendChild(h("p", { "class": "tb-lift", text: cs.notes(broken) }));
    var bad = function (m) { return TB.contrastReport(state, m).filter(needsLook).length; };
    bx.appendChild(h("p", { "class": "tb-css-sum", text: cs.contrast(bad("dark"), bad("light")) }));
    bx.hidden = false;
  }
  $("[data-css-load]", cssDlg).addEventListener("click", function () {
    cssReset();
    var res;
    try { res = TB.importDiscordCss(cssText.value); } catch (e) { cssErr.textContent = S.css.fail + TB.errorText(e, lang); return; }
    set(function (s) { s.colors = TB.applyCssImport(s, res).colors; });
    cssReport(res);
    say(S.css.done);
  });

  // -------------------------------------------------- Tela cheia ----
  function fullOn() { return document.fullscreenElement === stage || box.classList.contains("max"); }
  // Sem a API de tela cheia (ou se o navegador recusar), a prévia ocupa a janela inteira.
  function maximize(on) {
    box.classList.toggle("max", on);
    html.classList.toggle("tbx-max", on);
    $$("[data-fullscreen]").forEach(function (b) { b.replaceChild(icon(on ? "compress" : "expand"), b.querySelector("svg")); b.setAttribute("aria-pressed", on ? "true" : "false"); });
    setTimeout(fit, 30);
  }
  function toggleFull() {
    if (document.fullscreenElement) return document.exitFullscreen();
    if (box.classList.contains("max")) return maximize(false);
    if (stage.requestFullscreen) stage.requestFullscreen().catch(function () { maximize(true); });
    else maximize(true);
  }
  $$("[data-fullscreen]").forEach(function (b) { b.addEventListener("click", toggleFull); });
  document.addEventListener("fullscreenchange", function () {
    $$("[data-fullscreen]").forEach(function (b) { b.replaceChild(icon(fullOn() ? "compress" : "expand"), b.querySelector("svg")); b.setAttribute("aria-pressed", fullOn() ? "true" : "false"); });
    setTimeout(fit, 60);
  });

  // ------------------------------------------------------ Atalhos ----
  var keysDlg = document.querySelector("[data-keys]"), keysOpener = null;
  function openKeys() { keysOpener = document.activeElement; keysDlg.hidden = false; keysDlg.querySelector("[data-keys-close]").focus(); }
  function closeKeys() { keysDlg.hidden = true; if (keysOpener && keysOpener.focus) keysOpener.focus(); }
  $("[data-shortcuts]").addEventListener("click", openKeys);
  keysDlg.querySelector("[data-keys-close]").addEventListener("click", closeKeys);
  keysDlg.addEventListener("click", function (e) { if (e.target === keysDlg) closeKeys(); });
  $("[data-undo]").addEventListener("click", undo);
  $("[data-redo]").addEventListener("click", redo);
  document.addEventListener("keydown", function (e) {
    var t = e.target, typing = t && (t.tagName === "TEXTAREA" || t.tagName === "SELECT" || (t.tagName === "INPUT" && !/^(checkbox|radio|range|button)$/.test(t.type)) || t.isContentEditable);
    var modal = (dlg.open || cssDlg.open);
    if (e.key === "Escape") {
      if (!keysDlg.hidden) { e.preventDefault(); return closeKeys(); }
      if (sheet.classList.contains("open")) { e.preventDefault(); return closeExport(); }
      if (!menu.hidden) { e.preventDefault(); return closeMenu(true); }
      if (popState) { e.preventDefault(); return closePop(true); }
      if (box.classList.contains("max")) maximize(false);
      return;
    }
    if (modal) return;
    if ((e.ctrlKey || e.metaKey) && !e.altKey) {
      var k = e.key.toLowerCase();
      if (typing && t !== cp.hex) return;
      if (k === "z" && !e.shiftKey) { e.preventDefault(); undo(); }
      else if ((k === "z" && e.shiftKey) || k === "y") { e.preventDefault(); redo(); }
      return;
    }
    if (typing || e.altKey || e.ctrlKey || e.metaKey || !keysDlg.hidden) return;
    var key = e.key;
    if (key === "m" || key === "M") { if (view === "split") setEditMode(mode === "dark" ? "light" : "dark"); else setView(mode === "dark" ? "light" : "dark"); }
    else if (key === "b" || key === "B") setView(view === "split" ? mode : "split");
    else if (key === "0") setZoom("fit");
    else if (key === "1") setZoom(1);
    else if (key === "2") setZoom(1.5);
    else if (key === "+" || key === "=") zoomStep(1);
    else if (key === "-" || key === "_") zoomStep(-1);
    else if (key === "f" || key === "F") toggleFull();
    else if (key === "\\") { if (!matchMedia("(max-width: 899.98px)").matches) setPanel(box.classList.contains("panel-off")); }
    else if (key === "/") { setPanel(true); if (sheetIs("peek")) setSheet("half"); search.focus(); search.select(); }
    else if (key === "r" || key === "R") surprise();
    else if (key === "e" || key === "E") openExport();
    else if (key === "?") openKeys();
    else return;
    e.preventDefault();
  });

  // ------------------------------------------- O endereço guarda o tema ----
  var hashTimer = 0;
  function scheduleHash() {
    if (!hashReady) return;
    clearTimeout(hashTimer);
    hashTimer = setTimeout(function () {
      TB.encode(state, builtinStructure).then(function (tok) { history.replaceState(null, "", "#t=" + tok); });
    }, 700);
  }
  // Da galeria da comunidade: o .kdl vem de docs/community/, do próprio site (a CSP só deixa
  // buscar dele), e só os nomes que gen_site.py conferiu. Um nome fora da lista (tema renomeado
  // ou tirado da galeria, link cortado) não busca nada, mas diz por que o tema não abriu.
  function loadCommunity(name) {
    if (!Array.isArray(DATA.community) || DATA.community.indexOf(name) < 0 || !/^[a-z0-9-]{1,48}$/.test(name)) {
      say(S.linkFail + TB.errorText({ code: "community-missing" }, lang));
      return;
    }
    fetch(DATA.communityBase + name + ".kdl", { credentials: "same-origin" }).then(function (r) {
      if (!r.ok) throw { code: "community-missing" };
      return r.text();
    }).then(function (src) {
      var cs = TB.communityFromSource(src);
      DATA.order.forEach(function (n) { if (structures[n] === cs.structure) cs.layoutFrom = n; });
      if (hashReady) return replace(cs, S.community + name);
      state = cs;
      changed();
      say(S.community + name);
    }).catch(function (e) {
      say(S.linkFail + TB.errorText(e && e.code ? e : { code: "community-missing" }, lang));
    });
  }

  function boot() {
    placeIcons(box);
    placeIcons(document.querySelector("[data-export]"));
    placeIcons(document.querySelector("[data-keys]"));
    fitToolbar();
    buildColors();
    hoverText(null);
    var first = DATA.order.indexOf(html.dataset.theme) >= 0 ? html.dataset.theme : "orbital";
    var t = store("lc-tb-tab");
    selectTab(t && document.getElementById(t) && /^tbx-t-/.test(t) ? t : "tbx-t-colors", true);
    if (store("lc-tb-panel") === "off" && !matchMedia("(max-width: 899.98px)").matches) setPanel(false);
    // Em pé (celular, tablet), a folha já abre pela metade: a prévia fica com a largura toda e o
    // painel aparece embaixo, em vez de um espaço vazio.
    setSheet(innerHeight > innerWidth && innerHeight >= 560 ? "half" : "peek");
    setView(view);
    if (!fromHash(location.hash.slice(1))) { state = startFrom(first); ready(); }
    // Um link que só troca o #… nesta mesma página (#base=, #community=, #t=) também abre o tema,
    // como um passo que Desfazer volta. O endereço que a própria página escreve não dispara isto.
    addEventListener("hashchange", function () { fromHash(location.hash.slice(1)); });
  }
  function ready() {
    gen.base = TB.normHex(state.colors.dark.accent).slice(0, 7);
    var o = TB.toOklch(TB.hexRgba(gen.base));
    gen.chroma = clamp(Math.round(o[1] / 0.005) * 0.005, 0, 0.24);
    gen.lightness = clamp(Math.round(o[0] * 100) / 100, 0.55, 0.9);
    fillGen();
    changed();
  }
  function take(next, msg) {
    if (state) replace(next, msg);
    else { state = next; ready(); if (msg) say(msg); }
  }
  function fromHash(hash) {
    var m;
    if ((m = /^t=(.+)$/.exec(hash))) {
      TB.decode(m[1], builtinStructure).then(function (s) {
        if (state && JSON.stringify(s) === JSON.stringify(state)) return;
        hashReady = true;
        take(s);
      }, function (e) {
        if (!state) { state = startFrom(DATA.order.indexOf(html.dataset.theme) >= 0 ? html.dataset.theme : "orbital"); hashReady = true; ready(); }
        say(S.linkFail + TB.errorText(e, lang));
      });
      return true;
    }
    if ((m = /^base=([a-z]+)$/.exec(hash)) && DATA.order.indexOf(m[1]) >= 0) { take(startFrom(m[1]), state ? S.started + m[1] : ""); return true; }
    // Qualquer #community=…: o loadCommunity só busca os nomes da lista e explica o resto.
    if ((m = /^community=(.*)$/.exec(hash))) {
      if (!state) { state = startFrom(DATA.order.indexOf(html.dataset.theme) >= 0 ? html.dataset.theme : "orbital"); ready(); }
      loadCommunity(m[1]);
      return true;
    }
    return false;
  }
  boot();
})();
