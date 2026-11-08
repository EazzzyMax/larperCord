// Gerador de plugin: monta um .lua pronto para editar, só com o que a API de
// plugins tem (docs/plugins.md, src/plugins/runtime.zig). A parte de cima não
// mexe na página e roda também no Node (tools/test_plugin_starter.js); a de
// baixo desenha o formulário. Nada sai do navegador: o arquivo é montado aqui.
(function (root, make) {
  var lib = make();
  if (typeof module === "object" && module.exports) module.exports = lib;
  else root.LC_STARTER = lib;
})(this, function () {
  "use strict";

  var DOCS = { en: "https://rshacudevidro.github.io/larperCord/guide/plugins.html", pt: "https://rshacudevidro.github.io/larperCord/pt/guide/plugins.html" };
  // Os mesmos limites de src/plugins/manifest.zig: passou disso, o app corta.
  var MAX = { name: 48, description: 320, version: 16 };
  // O `contains` de larper.on (runtime.zig optNeedles): passou disso, o plugin não carrega.
  var NEEDLES = { max: 16, bytes: 64 };
  var TRIGGERS = [";", "!", "$", "%", "&", "+", "=", "?", "^"];
  // A lista de src/plugins/host.zig (keyCode): o resto o app recusa.
  var NAMED_KEYS = ["enter", "space", "tab", "backspace", "delete", "insert", "home", "end", "pageup", "pagedown",
    "up", "down", "left", "right", ",", ".", "/", ";", "-", "="];
  // Fallback para o Node sem plugin-api.js: a lista de manifest.zig (isDiscord).
  var DISCORD = ["discord.com", "discordapp.com", "discord.gg", "discordapp.net", "discord.media", "discordcdn.com",
    "discordstatus.com", "discord.gift", "discord.new", "discord.co", "discord.dev", "dis.gd"];

  // Cada parte: o grupo no formulário, as capacidades que pede e os textos.
  var FEATURES = [
    { id: "command", group: "start", caps: [], en: "A command you type, like /hello", pt: "Um comando que você digita, como /ola" },
    { id: "keybind", group: "start", caps: [], en: "A keyboard shortcut", pt: "Um atalho de teclado" },
    { id: "menuMessage", group: "start", caps: ["menu"], en: "An entry on a message's right-click menu", pt: "Uma entrada no botão direito de uma mensagem" },
    { id: "menuUser", group: "start", caps: ["menu"], en: "An entry on a person's right-click menu", pt: "Uma entrada no botão direito de uma pessoa" },
    { id: "panel", group: "start", caps: ["panel"], en: "A side panel with a text field, buttons and a list", pt: "Um painel lateral com campo de texto, botões e uma lista" },
    { id: "onMessage", group: "listen", caps: ["messages"], en: "New messages, in any channel", pt: "Mensagens novas, em qualquer canal" },
    { id: "onEdit", group: "listen", caps: ["messages"], en: "Edited and deleted messages", pt: "Mensagens editadas e apagadas" },
    { id: "onChannel", group: "listen", caps: [], en: "You opening another channel", pt: "Você abrindo outro canal" },
    { id: "onReady", group: "listen", caps: [], en: "The app connecting", pt: "O app conectando" },
    { id: "notify", group: "do", caps: ["notify"], en: "Show a notice", pt: "Mostrar um aviso" },
    { id: "decorate", group: "do", caps: ["decorate"], en: "Mark messages: notes under them and collapse rules", pt: "Marcar mensagens: notas embaixo e regras para recolher" },
    { id: "storage", group: "do", caps: ["storage"], en: "Remember things between restarts", pt: "Lembrar coisas entre uma abertura e outra" },
    { id: "settings", group: "do", caps: ["settings", "storage"], en: "An option on its card in Settings → Plugins", pt: "Uma opção no cartão dele em Configurações → Plugins" },
    { id: "timers", group: "do", caps: ["timers"], en: "Run something every few minutes", pt: "Rodar algo a cada tantos minutos" },
    { id: "send", group: "do", caps: ["send"], gesture: true, en: "Send what you type after the command", pt: "Enviar o que você digita depois do comando" },
    { id: "composer", group: "do", caps: ["composer"], gesture: true, en: "Put text in the message box (never sends)", pt: "Pôr texto na caixa de mensagem (nunca envia)" },
    { id: "links", group: "do", caps: ["links"], gesture: true, en: "Open a link in the browser", pt: "Abrir um link no navegador" },
    { id: "http", group: "do", caps: ["http"], en: "Fetch data from a site, over HTTPS", pt: "Buscar dados de um site, por HTTPS" },
    { id: "completions", group: "do", caps: ["completions"], en: "Suggestions while you type", pt: "Sugestões enquanto você digita" },
    { id: "rewrite", group: "do", caps: ["rewrite"], en: "Change what you send: clean links, expand words", pt: "Mudar o que você envia: limpar links, trocar palavras" },
    { id: "lsp", group: "do", caps: ["lsp"], en: "Propose a language server for code blocks", pt: "Propor um servidor de linguagem para blocos de código" },
  ];
  var GESTURES = ["command", "keybind", "menuMessage", "menuUser", "panel"];

  function defaults() {
    return {
      lang: "en", name: "My plugin", namePt: "", desc: "", descPt: "", file: "", version: "1.0.0",
      features: { command: true, notify: true },
      command: "/hello", keybind: "ctrl+shift+h", contains: "larper", hosts: "api.example.com",
      trigger: ";", lspLang: "python", lspCmd: "pylsp",
    };
  }

  function bytes(s) {
    var n = 0;
    for (var i = 0; i < s.length; i++) {
      var c = s.charCodeAt(i);
      if (c < 0x80) n += 1;
      else if (c < 0x800) n += 2;
      else if (c >= 0xd800 && c <= 0xdbff) { n += 4; i++; }
      else n += 3;
    }
    return n;
  }

  // Uma linha do cabeçalho: sem quebra nem caractere de controle.
  function oneLine(s) {
    return String(s || "").replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim();
  }

  function luaStr(s) {
    return '"' + String(s).replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, "").replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r?\n/g, "\\n") + '"';
  }

  function slug(s) {
    var t = String(s || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    return t.replace(/[^a-z0-9_-]+/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "").slice(0, 40);
  }

  function validFile(f) { return /^[a-z0-9][a-z0-9_-]{0,39}$/.test(f); }

  // runtime.zig validCommand: "/" e até 31 letras, números, _ ou -.
  function validCommand(c) { return /^\/[A-Za-z0-9_-]{1,31}$/.test(c); }

  // runtime.zig parseKeys: os modificadores e a tecla, ou null se o formato não serve.
  function parseKeys(spec) {
    var mods = { ctrl: false, shift: false, alt: false, super: false }, key = null;
    var parts = String(spec).split("+");
    for (var i = 0; i < parts.length; i++) {
      var w = parts[i].trim().toLowerCase();
      if (!w || w.length > 16) return null;
      if (w === "ctrl" || w === "control") mods.ctrl = true;
      else if (w === "shift") mods.shift = true;
      else if (w === "alt") mods.alt = true;
      else if (w === "super" || w === "meta" || w === "win" || w === "cmd") mods.super = true;
      else if (key !== null) return null;
      else key = w;
    }
    return key === null ? null : { mods: mods, key: key };
  }

  // runtime.zig parseKeys + host.zig keyCode.
  function checkKeybind(spec) {
    var k = parseKeys(spec);
    if (!k) return "format";
    var mods = k.mods, key = k.key;
    var fkey = /^f\d/.test(key);
    if (!(/^[a-z0-9]$/.test(key) || (fkey && /^f([1-9]|1\d|2[0-4])$/.test(key)) || NAMED_KEYS.indexOf(key) >= 0)) return "key";
    if (!mods.ctrl && !mods.alt && !mods.super && !fkey) return "modifier";
    if (mods.ctrl && !mods.shift && !mods.alt && !mods.super && key.length === 1 && "acvxyz".indexOf(key) >= 0) return "typing";
    return null;
  }

  // "Control+Shift+M" -> "ctrl+shift+m": a mesma forma das teclas do app em plugin-api.js.
  function canonKeys(spec) {
    var k = parseKeys(spec);
    if (!k) return "";
    return ["ctrl", "shift", "alt", "super"].filter(function (m) { return k.mods[m]; }).concat(k.key).join("+");
  }

  // manifest.zig validHost + isDiscord.
  function checkHost(h, discord) {
    var fam = discord || DISCORD;
    var low = h.toLowerCase();
    for (var i = 0; i < fam.length; i++) {
      if (low === fam[i] || (low.length > fam[i].length && low.slice(-fam[i].length - 1) === "." + fam[i])) return "discord";
    }
    if (h.length < 4 || h.length > 96 || h[0] === "." || h[0] === "-" || h[h.length - 1] === ".") return "bad";
    if (!/^[A-Za-z0-9.-]+$/.test(h) || h.indexOf(".") < 0 || !/[A-Za-z]/.test(h)) return "bad";
    if (/\.local(host)?$/i.test(h) || /\.\d+$/.test(h)) return "bad";
    return null;
  }

  function validLspLang(s) { return /^[a-z0-9_+-]{1,16}$/.test(s); }

  var MSG = {
    nameEmpty: { en: "Give it a name.", pt: "Dê um nome." },
    tooLong: { en: "{f} is over {n} bytes; the app would cut it.", pt: "{f} passa de {n} bytes; o app cortaria." },
    file: { en: "The file name takes lowercase letters, numbers, - and _ (up to 40).", pt: "O nome do arquivo aceita letras minúsculas, números, - e _ (até 40)." },
    command: { en: "A command is / and up to 31 letters, numbers, _ or -.", pt: "Um comando é / e até 31 letras, números, _ ou -." },
    keyformat: { en: "Write the shortcut like ctrl+shift+h: modifiers and one key, joined by +.", pt: "Escreva o atalho como ctrl+shift+h: modificadores e uma tecla, unidos por +." },
    keykey: { en: "Unknown key. Use a–z, 0–9, f1–f24 or one of: " + NAMED_KEYS.join(" "), pt: "Tecla desconhecida. Use a–z, 0–9, f1–f24 ou uma destas: " + NAMED_KEYS.join(" ") },
    keymodifier: { en: "Only F1–F24 can go alone; other keys need ctrl, alt or super.", pt: "Só F1–F24 vão sozinhas; as outras teclas pedem ctrl, alt ou super." },
    keytyping: { en: "Ctrl plus a, c, v, x, y or z happens all the time while typing: add shift or alt.", pt: "Ctrl com a, c, v, x, y ou z acontece o tempo todo digitando: some shift ou alt." },
    keyApp: { en: "{k} is also an app shortcut ({a}): both would run. Pick another combination.", pt: "{k} também é um atalho do app ({a}): os dois rodariam. Escolha outra combinação." },
    wordsMany: { en: "“Only messages with” takes at most {max} words; there are {n}.", pt: "“Só mensagens com” aceita no máximo {max} palavras; tem {n}." },
    wordLong: { en: "“{w}” is over {max} bytes: each word in “Only messages with” takes 1 to {max}.", pt: "“{w}” passa de {max} bytes: cada palavra de “Só mensagens com” vai de 1 a {max}." },
    hostsEmpty: { en: "Fetching needs at least one host, like api.example.com.", pt: "Buscar dados pede pelo menos um host, como api.exemplo.com." },
    hostsMany: { en: "At most {n} hosts.", pt: "No máximo {n} hosts." },
    hostdiscord: { en: "{h} is Discord: plugins can't talk to Discord directly.", pt: "{h} é o Discord: plugins não falam direto com o Discord." },
    hostbad: { en: "{h} isn't a plain host name: no https://, port, path or IP address.", pt: "{h} não é só um nome de host: sem https://, porta, caminho nem endereço IP." },
    lspLang: { en: "The language is the code block tag: up to 16 lowercase letters, numbers, _, - or +.", pt: "A linguagem é a etiqueta do bloco: até 16 letras minúsculas, números, _, - ou +." },
    lspCmd: { en: "Write the language server's command, like pylsp.", pt: "Escreva o comando do servidor de linguagem, como pylsp." },
    trigger: { en: "Pick one of the trigger characters.", pt: "Escolha um dos caracteres de gatilho." },
    autoCommand: { en: "Sending, typing in the box and opening links only work from your gesture, so a command was added.", pt: "Enviar, escrever na caixa e abrir links só funcionam a partir de um gesto seu, então um comando foi incluído." },
    autoCommandHttp: { en: "In this starter the request runs from your command, so a command was added.", pt: "Neste começo o pedido roda a partir do seu comando, então um comando foi incluído." },
    sendNeedsCommand: { en: "Sending uses the text after the command, so a command was added.", pt: "Enviar usa o texto depois do comando, então um comando foi incluído." },
    noFilter: { en: "With no words, the plugin runs for every new message. A few words keep the rest from even reaching Lua.", pt: "Sem palavras, o plugin roda para toda mensagem nova. Algumas palavras impedem que o resto chegue no Lua." },
  };

  function say(lang, key, vars) {
    var s = MSG[key][lang === "pt" ? "pt" : "en"];
    for (var k in vars || {}) s = s.split("{" + k + "}").join(vars[k]);
    return s;
  }

  // Monta o arquivo. `api` é window.LC_PLUGIN_API (caps, maxHosts, discord), opcional no Node.
  function build(input, api) {
    var o = Object.assign(defaults(), input || {});
    o.features = Object.assign({}, (input && input.features) || defaults().features);
    var lang = o.lang === "pt" ? "pt" : "en";
    var C = function (en, pt) { return lang === "pt" ? pt : en; };
    var errors = [], notes = [];
    var f = {};
    FEATURES.forEach(function (x) { f[x.id] = !!o.features[x.id]; });

    var name = oneLine(o.name), namePt = oneLine(o.namePt), desc = oneLine(o.desc), descPt = oneLine(o.descPt);
    var version = oneLine(o.version);
    if (!name) errors.push(say(lang, "nameEmpty"));
    [[name, "name", C("The name", "O nome")], [namePt, "name", C("The Portuguese name", "O nome em português")],
     [desc, "description", C("The description", "A descrição")], [descPt, "description", C("The Portuguese description", "A descrição em português")],
     [version, "version", C("The version", "A versão")]].forEach(function (x) {
      if (bytes(x[0]) > MAX[x[1]]) errors.push(say(lang, "tooLong", { f: x[2], n: MAX[x[1]] }));
    });
    var file = oneLine(o.file) ? slug(o.file.replace(/\.lua$/i, "")) : slug(name) || "plugin";
    if (!validFile(file)) errors.push(say(lang, "file"));

    // O que só funciona num gesto precisa de um jeito de a pessoa pedir.
    if (f.send && !f.command) { f.command = true; notes.push(say(lang, "sendNeedsCommand")); }
    var anyGesture = GESTURES.some(function (g) { return f[g]; });
    if ((f.composer || f.links) && !anyGesture) { f.command = true; anyGesture = true; notes.push(say(lang, "autoCommand")); }
    if (f.http && !anyGesture) { f.command = true; anyGesture = true; notes.push(say(lang, "autoCommandHttp")); }

    var command = oneLine(o.command);
    if (f.command && !validCommand(command)) errors.push(say(lang, "command"));
    var keybind = oneLine(o.keybind).toLowerCase();
    if (f.keybind) {
      var kb = checkKeybind(keybind);
      if (kb) errors.push(say(lang, "key" + kb));
      else {
        // O app não troca os próprios atalhos pelo do plugin: os dois disparam.
        var canon = canonKeys(keybind);
        var clash = ((api && api.appKeys) || []).filter(function (a) { return a.k === canon; })[0];
        if (clash) notes.push(say(lang, "keyApp", { k: keybind, a: clash[lang] }));
      }
    }
    // runtime.zig optNeedles: de 1 a 16 textos, cada um de 1 a 64 bytes; fora disso o plugin nem carrega.
    var words = String(o.contains || "").split(/[,\n]/).map(oneLine).filter(Boolean);
    if (f.onMessage) {
      if (!words.length) notes.push(say(lang, "noFilter"));
      if (words.length > NEEDLES.max) errors.push(say(lang, "wordsMany", { max: NEEDLES.max, n: words.length }));
      words.forEach(function (w) {
        var cut = Array.from(w);
        if (bytes(w) > NEEDLES.bytes) errors.push(say(lang, "wordLong", { w: cut.length > 24 ? cut.slice(0, 24).join("") + "…" : w, max: NEEDLES.bytes }));
      });
    }
    var hosts = [];
    if (f.http) {
      hosts = String(o.hosts || "").split(/[\s,]+/).filter(Boolean);
      var maxHosts = (api && api.maxHosts) || 8;
      if (!hosts.length) errors.push(say(lang, "hostsEmpty"));
      if (hosts.length > maxHosts) errors.push(say(lang, "hostsMany", { n: maxHosts }));
      hosts.forEach(function (h) { var e = checkHost(h, api && api.discord); if (e) errors.push(say(lang, "host" + e, { h: h })); });
    }
    if (f.completions && TRIGGERS.indexOf(o.trigger) < 0) errors.push(say(lang, "trigger"));
    var lspArgv = oneLine(o.lspCmd).split(" ").filter(Boolean);
    if (f.lsp) {
      if (!validLspLang(oneLine(o.lspLang))) errors.push(say(lang, "lspLang"));
      if (!lspArgv.length) errors.push(say(lang, "lspCmd"));
    }

    var caps = [];
    FEATURES.forEach(function (x) { if (f[x.id]) x.caps.forEach(function (c) { if (caps.indexOf(c) < 0) caps.push(c); }); });
    var order = (api && api.caps) || caps.slice();
    caps.sort(function (a, b) { return order.indexOf(a) - order.indexOf(b); });

    var L = [];
    function line(s) { L.push(s === undefined ? "" : s); }
    // O cabeçalho: o app lê sem rodar nada (src/plugins/manifest.zig).
    line("-- @name " + name);
    if (namePt) line("-- @name:pt " + namePt);
    if (desc) line("-- @description " + desc);
    if (descPt) line("-- @description:pt " + descPt);
    if (version) line("-- @version " + version);
    if (caps.length) line("-- @capabilities " + caps.join(", "));
    if (f.http && hosts.length) line("-- @hosts " + hosts.join(", "));
    line();
    line("-- " + file + ".lua, " + C("started with the larperCord plugin starter.", "começado no gerador de plugin do larperCord."));
    line("-- " + C("Save it in the plugins folder and click Reload in Settings > Plugins:", "Salve na pasta de plugins e clique em Recarregar em Configurações > Plugins:"));
    line("--   Linux:   ~/.config/larpercord/plugins/");
    line("--   Windows: %APPDATA%\\larpercord\\plugins\\");
    line("-- " + C("Every function is described at ", "Toda função está descrita em ") + DOCS[lang]);
    line();
    line("local tr = larper.tr");
    line("local NAME = tr(" + luaStr(namePt || name) + ", " + luaStr(name) + ")");
    line();
    line("-- " + C("Cuts a text at a character boundary, for notices and lists.", "Corta um texto sem partir um caractere, para avisos e listas."));
    line("local function short(text, max)");
    line("  text = (text or \"\"):gsub(\"%s+\", \" \")");
    line("  if #text <= max then return text end");
    line("  local cut = max");
    line("  while cut > 0 and (text:byte(cut + 1) or 0) & 0xC0 == 0x80 do cut = cut - 1 end");
    line("  return text:sub(1, cut) .. \"…\"");
    line("end");
    line();

    if (f.storage || f.settings) {
      line("-- " + C("larper.storage keeps data between restarts, per plugin and per account (up to 1 MB).", "larper.storage guarda dados entre aberturas, por plugin e por conta (até 1 MB)."));
      line("local data = larper.storage.get(\"data\") or { uses = 0 }");
      line("local function save() larper.storage.set(\"data\", data) end");
      line();
    }
    if (f.settings) {
      line("-- " + C("An option on the plugin's card. The plugin keeps the value itself.", "Uma opção no cartão do plugin. O próprio plugin guarda o valor."));
      line("local active = larper.storage.get(\"active\") ~= false");
      line("local function options()");
      line("  larper.settings.set({");
      line("    { type = \"toggle\", key = \"active\", label = tr(\"Ligado\", \"Active\"), value = active,");
      line("      hint = tr(\"Desligado, o plugin fica quieto.\", \"Off, the plugin stays quiet.\"),");
      line("      on_change = function(on) active = on; larper.storage.set(\"active\", on) end },");
      line("  })");
      line("end");
      line("larper.on(\"lang\", options)");
      line("options()");
      line();
    }
    if (f.panel) {
      line("-- " + C("What the panel lists, newest first. It lives only in memory.", "O que o painel lista, do mais novo para o mais velho. Fica só na memória."));
      line("local log = {}");
      line("local query = \"\"");
      line("local draw");
      line();
    }
    line("-- " + C("Where the plugin tells you things.", "Onde o plugin conta as coisas para você."));
    line("local function report(text)");
    if (f.settings) line("  if not active then return end");
    line("  print(text) -- " + C("goes to the terminal, if you started larpercord from one", "vai para o terminal, se você abriu o larpercord por um"));
    if (f.notify) line("  larper.notify(short(text, 200))");
    if (f.panel) {
      line("  table.insert(log, 1, { title = short(text, 200), meta = os.date(\"%H:%M\") })");
      line("  if #log > 50 then table.remove(log) end");
      line("  if draw then draw() end");
    }
    line("end");
    line();

    if (f.http) {
      line("local HOST = " + luaStr(hosts[0] || "api.example.com"));
      line("-- " + C("Nothing goes out until you approve the host on the plugin's card. The text is cut", "Nada sai antes de você aprovar o host no cartão do plugin. O texto é cortado"));
      line("-- " + C("first: the app refuses a URL over 2048 bytes.", "antes: o app recusa uma URL com mais de 2048 bytes."));
      line("local function fetch(text)");
      line("  larper.http.get(\"https://\" .. HOST .. \"/?q=\" .. larper.urlencode(short(text, 200)), function(res)");
      line("    if res.ok then");
      line("      report(HOST .. \": \" .. short(res.body, 120))");
      line("    elseif res.error == \"not_approved\" then");
      line("      report(tr(\"Aprove \", \"Approve \") .. HOST .. tr(\" no cartão do plugin.\", \" on the plugin's card.\"))");
      line("    else");
      line("      report(HOST .. \": \" .. tostring(res.error or res.status))");
      line("    end");
      line("  end)");
      line("end");
      line("larper.on(\"hosts\", function()");
      line("  print(HOST .. (larper.http.allowed(HOST) and \" approved\" or \" not approved\"))");
      line("end)");
      line();
    }

    if (anyGesture) {
      line("-- " + C("What happens when you use the plugin: its command, shortcut, menu entry or panel", "O que acontece quando você usa o plugin: o comando, o atalho, a entrada do menu ou o"));
      line("-- " + C("button. These run from your gesture, so they may type in the box and open links.", "botão do painel. Rodam a partir de um gesto seu, então podem escrever na caixa e abrir links."));
      line("local function act(text)");
      line("  text = text or \"\"");
      if (f.storage || f.settings) {
        line("  data.uses = data.uses + 1");
        line("  save()");
      }
      line("  report(tr(\"Você pediu: \", \"You asked: \") .. (text ~= \"\" and short(text, 80) or \"-\")" + (f.storage || f.settings ? " .. \" (\" .. data.uses .. \")\"" : "") + ")");
      if (f.composer) line("  larper.insert(text ~= \"\" and text or tr(\"olá\", \"hello\"))");
      if (f.links) line("  larper.open(\"https://example.com/?q=\" .. larper.urlencode(short(text, 200))) -- " + C("change to the site you want (URLs up to 2000 bytes)", "troque pelo site que quiser (URLs de até 2000 bytes)"));
      if (f.http) line("  fetch(text)");
      if (f.panel) line("  larper.panel.open()");
      line("end");
      line();
    }

    if (f.command) {
      line("-- " + C("Type ", "Digite ") + command + C(" in the message box. The command itself never goes to Discord.", " na caixa de mensagem. O comando em si nunca vai para o Discord."));
      line("larper.command(" + luaStr(command) + ", function(args)");
      if (f.send) {
        line("  if args ~= \"\" then");
        line("    -- " + C("Sends the text after the command to the open channel, as if you typed it.", "Envia o texto depois do comando para o canal aberto, como se você digitasse."));
        line("    if #args > 2000 then");
        line("      report(tr(\"Longo demais para enviar: o máximo é 2000 bytes.\", \"Too long to send: 2000 bytes at most.\"))");
        line("      return");
        line("    end");
        line("    larper.send(nil, args)");
        line("    return");
        line("  end");
      }
      line("  act(args)");
      line("end)");
      line();
    }
    if (f.keybind) {
      line("larper.keybind(" + luaStr(keybind) + ", function() act(\"\") end)");
      line();
    }
    if (f.menuMessage) {
      line("larper.menu(\"message\", { pt = " + luaStr(namePt || name) + ", en = " + luaStr(name) + " }, function(msg)");
      line("  act(msg.content)");
      if (f.decorate) line("  larper.decorate(msg.id, { note = tr(\"Marcada por \", \"Marked by \") .. NAME })");
      line("end)");
      line();
    }
    if (f.menuUser) {
      line("larper.menu(\"user\", { pt = " + luaStr(namePt || name) + ", en = " + luaStr(name) + " }, function(user)");
      line("  act(user.name)");
      line("end)");
      line();
    }
    if (f.panel) {
      line("-- " + C("The panel opens from the channel header button, the palette (Panel: name) or the", "O painel abre pelo botão no topo do canal, pela paleta (Painel: nome) ou pelo"));
      line("-- " + C("plugin's card. Publish it again whenever something changes.", "cartão do plugin. Publique de novo sempre que algo mudar."));
      line("draw = function()");
      line("  local items = {}");
      line("  for i, e in ipairs(log) do items[i] = { title = e.title, meta = e.meta } end");
      line("  larper.panel.set({");
      line("    title = NAME,");
      line("    { type = \"text\", text = tr(\"Escreva e aperte Enter.\", \"Type and press Enter.\"), style = \"muted\" },");
      line("    { type = \"input\", key = \"text\", placeholder = tr(\"Algum texto\", \"Some text\"), value = query, clear = true,");
      line("      on_change = function(v) query = v end,");
      line("      on_submit = function(v) query = \"\"; act(v) end },");
      line("    { type = \"row\",");
      line("      { type = \"button\", label = tr(\"Usar\", \"Use\"), style = \"accent\", on_click = function() act(query) end },");
      line("      { type = \"button\", label = tr(\"Limpar\", \"Clear\"), on_click = function() log = {}; draw() end },");
      line("    },");
      line("    { type = \"separator\" },");
      line("    { type = \"list\", empty = tr(\"Nada ainda.\", \"Nothing yet.\"), items = items },");
      line("  })");
      line("end");
      line("larper.on(\"lang\", draw)");
      line("draw()");
      line();
    }

    if (f.onMessage) {
      line("-- " + C("Live messages only: the history loaded when you open a channel doesn't count.", "Só mensagens ao vivo: o histórico carregado ao abrir um canal não conta."));
      line("larper.on(\"message\", function(msg)");
      line("  if msg.mine or msg.ignored then return end");
      line("  report(msg.author.name .. \" #\" .. msg.channel.name .. \": \" .. short(msg.content, 80))");
      if (f.decorate) line("  larper.decorate(msg.id, { note = tr(\"Vista por \", \"Seen by \") .. NAME })");
      if (words.length) {
        line("end, { contains = { " + words.map(luaStr).join(", ") + " } }) -- " + C("only messages with one of these (ignoring case)", "só mensagens com uma destas (sem diferenciar maiúsculas)"));
      } else line("end)");
      line();
    }
    if (f.onEdit) {
      line("larper.on(\"edit\", function(msg)");
      line("  print(tr(\"editada: \", \"edited: \") .. msg.id)");
      line("end)");
      line("-- " + C("A deleted message only brings its ID: the text is gone, for plugins too.", "Uma mensagem apagada só traz o ID: o texto some, para os plugins também."));
      line("larper.on(\"delete\", function(m)");
      line("  print(tr(\"apagada: \", \"deleted: \") .. m.id)");
      line("end)");
      line();
    }
    if (f.decorate) {
      line("-- " + C("Rules the app applies on its own, also to messages that arrive later.", "Regras que o app aplica sozinho, também nas mensagens que chegarem depois."));
      line("larper.rules({");
      line("  { word = \"spoiler\", collapse = true, label = tr(\"Recolhida pelo \", \"Collapsed by \") .. NAME },");
      line("})");
      line("larper.on(\"dismiss\", function(m) print(tr(\"nota fechada: \", \"note closed: \") .. m.id) end)");
      line();
    }
    if (f.onChannel) {
      line("larper.on(\"channel\", function(ch)");
      line("  if ch then print(tr(\"abriu #\", \"opened #\") .. ch.name) end");
      line("end)");
      line();
    }
    if (f.onReady) {
      line("larper.on(\"ready\", function()");
      line("  print(tr(\"conectado\", \"connected\"))");
      line("end)");
      line();
    }
    if (f.timers) {
      line("-- " + C("Every 10 minutes while the plugin is on. larper.after runs once.", "A cada 10 minutos enquanto o plugin estiver ligado. larper.after roda uma vez."));
      line("larper.every(600, function()");
      line("  print(tr(\"ainda aqui\", \"still here\"))");
      line("end)");
      line();
    }
    if (f.completions) {
      line("-- " + C("Type ", "Digite ") + o.trigger + C("h in the box to see the list. Picking one puts its text in the box; it never sends.", "h na caixa para ver a lista. Escolher uma põe o texto na caixa; nunca envia."));
      line("local function suggestions()");
      line("  larper.completions(" + luaStr(o.trigger) + ", {");
      line("    { name = \"hi\", text = tr(\"Olá, tudo bem?\", \"Hello, how are you?\"), hint = tr(\"saudação\", \"greeting\") },");
      line("    { name = \"brb\", text = tr(\"Já volto.\", \"Be right back.\"), hint = tr(\"ausente\", \"away\") },");
      line("  })");
      line("end");
      line("larper.on(\"lang\", suggestions)");
      line("suggestions()");
      line();
    }
    if (f.rewrite) {
      line("-- " + C("Fixed rules the app applies when you send. The plugin never sees what you write.", "Regras fixas que o app aplica ao enviar. O plugin nunca vê o que você escreve."));
      line("larper.rewrite({");
      line("  { strip_params = { \"utm_*\", \"fbclid\" } },");
      line("  " + (lang === "pt" ? "{ word = \"vlw\", with = \"valeu\" }," : "{ word = \"btw\", with = \"by the way\" },"));
      line("})");
      line();
    }
    if (f.lsp) {
      line("-- " + C("Nothing runs here: the proposal shows up off under Settings > Code diagnostics,", "Aqui nada roda: a proposta aparece desligada em Configurações > Erros no código,"));
      line("-- " + C("with the full command, and only runs after you turn it on.", "com o comando inteiro, e só roda depois que você ligar."));
      line("larper.lsp(" + luaStr(oneLine(o.lspLang)) + ", { " + lspArgv.map(luaStr).join(", ") + " })");
      line();
    }
    line("print(tr(\"carregado\", \"loaded\"))");

    var warn = null;
    if (caps.indexOf("messages") >= 0 && (caps.indexOf("http") >= 0 || caps.indexOf("links") >= 0)) {
      warn = caps.indexOf("http") >= 0 ? "http" : "links";
    }
    return { file: file + ".lua", source: L.join("\n") + "\n", caps: caps, hosts: hosts, features: f, errors: errors, notes: notes, warn: warn };
  }

  return { FEATURES: FEATURES, TRIGGERS: TRIGGERS, MAX: MAX, NEEDLES: NEEDLES, defaults: defaults, build: build, checkKeybind: checkKeybind,
           canonKeys: canonKeys, checkHost: checkHost, validCommand: validCommand, slug: slug, bytes: bytes };
});

// O formulário. Só no navegador.
(function () {
  if (typeof document === "undefined") return;
  var box = document.querySelector("[data-starter]");
  if (!box) return;
  var lib = window.LC_STARTER, api = window.LC_PLUGIN_API || null;
  var lang = document.documentElement.dataset.lang === "pt" ? "pt" : "en";
  var C = function (en, pt) { return lang === "pt" ? pt : en; };
  var state = lib.defaults();
  state.lang = lang;
  if (lang === "pt") { state.name = "Meu plugin"; state.command = "/ola"; }

  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }

  var extra = {
    command: '<label class="st-sub">' + C("Command", "Comando") + ' <input data-k="command" value="' + esc(state.command) + '" spellcheck="false" autocomplete="off"></label>',
    keybind: '<label class="st-sub">' + C("Keys", "Teclas") + ' <input data-k="keybind" value="' + esc(state.keybind) + '" spellcheck="false" autocomplete="off"></label>',
    onMessage: '<label class="st-sub">' + C("Only messages with (comma-separated)", "Só mensagens com (separe por vírgula)") + ' <input data-k="contains" value="' + esc(state.contains) + '" spellcheck="false"></label>',
    http: '<label class="st-sub">' + C("Hosts (just the name)", "Hosts (só o nome)") + ' <input data-k="hosts" value="' + esc(state.hosts) + '" spellcheck="false" autocomplete="off"></label>',
    completions: '<label class="st-sub">' + C("Trigger", "Gatilho") + ' <select data-k="trigger">' + lib.TRIGGERS.map(function (t) { return '<option' + (t === state.trigger ? " selected" : "") + ">" + esc(t) + "</option>"; }).join("") + "</select></label>",
    lsp: '<label class="st-sub">' + C("Language", "Linguagem") + ' <input data-k="lspLang" value="' + esc(state.lspLang) + '" spellcheck="false" autocomplete="off"></label>' +
         '<label class="st-sub">' + C("Command", "Comando") + ' <input data-k="lspCmd" value="' + esc(state.lspCmd) + '" spellcheck="false" autocomplete="off"></label>',
  };
  var groups = [
    ["start", C("How you use it", "Como você usa")],
    ["listen", C("What it listens to", "O que ele escuta")],
    ["do", C("What it does", "O que ele faz")],
  ];
  function capNames(caps) {
    return caps.map(function (c) { var l = api && api.labels[c]; return l ? (lang === "pt" ? l.pt : l.en) : c; }).join(", ");
  }
  var html = '<form class="st-form" novalidate onsubmit="return false">' +
    '<fieldset><legend>' + C("About it", "Sobre ele") + "</legend>" +
    '<div class="st-grid">' +
    '<label>' + C("Name", "Nome") + ' <input data-k="name" value="' + esc(state.name) + '" maxlength="48" required></label>' +
    '<label>' + C("Name in Portuguese (optional)", "Nome em inglês (opcional)") + ' <input data-k="' + (lang === "pt" ? "nameEn" : "namePt") + '" maxlength="48"></label>' +
    '<label class="st-wide">' + C("What it does, in a sentence or two", "O que ele faz, em uma ou duas frases") + ' <textarea data-k="desc" rows="2" maxlength="320"></textarea></label>' +
    '<label class="st-wide">' + C("The same in Portuguese (optional)", "O mesmo em inglês (opcional)") + ' <textarea data-k="' + (lang === "pt" ? "descEn" : "descPt") + '" rows="2" maxlength="320"></textarea></label>' +
    '<label>' + C("File name", "Nome do arquivo") + ' <span class="st-file"><input data-k="file" placeholder="' + esc(lib.slug(state.name)) + '" spellcheck="false" autocomplete="off"><i>.lua</i></span></label>' +
    '<label>' + C("Version", "Versão") + ' <input data-k="version" value="' + esc(state.version) + '" maxlength="16"></label>' +
    "</div></fieldset>";
  groups.forEach(function (g) {
    html += '<fieldset><legend>' + g[1] + "</legend>";
    lib.FEATURES.forEach(function (x) {
      if (x.group !== g[0]) return;
      var on = !!state.features[x.id];
      var caps = x.caps.length ? '<small class="st-asks">' + C("asks for: ", "pede: ") + esc(capNames(x.caps)) + "</small>" : '<small class="st-asks">' + C("asks for nothing", "não pede nada") + "</small>";
      html += '<div class="st-opt"><label class="st-check"><input type="checkbox" data-f="' + x.id + '"' + (on ? " checked" : "") + "> <span>" + esc(x[lang]) + "</span> " + caps + "</label>" +
        (extra[x.id] ? '<div class="st-more" data-more="' + x.id + '"' + (on ? "" : " hidden") + ">" + extra[x.id] + "</div>" : "") + "</div>";
    });
    html += "</fieldset>";
  });
  html += "</form>" +
    '<div class="st-out">' +
    '<p class="st-caps" data-caps></p>' +
    '<p class="st-warn" data-warn hidden></p>' +
    '<ul class="st-msgs" data-msgs aria-live="polite"></ul>' +
    '<div class="st-actions"><button type="button" class="btn primary" data-download></button> <button type="button" class="btn" data-copy-file>' + C("Copy", "Copiar") + "</button></div>" +
    '<div class="code" data-lang="lua"><span class="code-lang">lua</span><pre><code data-preview></code></pre></div>' +
    "</div>";
  box.innerHTML = html;

  var out = { caps: box.querySelector("[data-caps]"), warn: box.querySelector("[data-warn]"), msgs: box.querySelector("[data-msgs]"),
              dl: box.querySelector("[data-download]"), copy: box.querySelector("[data-copy-file]"), code: box.querySelector("[data-preview]") };
  var last = null;

  // O mesmo realce dos blocos de código do site (HL["lua"] em tools/gen_site.py).
  var HL = /(--[^\n]*)|("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|(\b\d+\b)|(\b(?:local|function|end|if|then|else|elseif|for|in|do|while|return|not|and|or|nil|true|false)\b)|(\blarper\.\w+)/g;
  function highlight(src) {
    var cls = ["c", "s", "n", "k", "p"], outp = "", lastI = 0, m;
    HL.lastIndex = 0;
    while ((m = HL.exec(src))) {
      outp += esc(src.slice(lastI, m.index));
      for (var i = 1; i <= 5; i++) if (m[i] !== undefined) { outp += '<span class="t-' + cls[i - 1] + '">' + esc(m[0]) + "</span>"; break; }
      lastI = HL.lastIndex;
    }
    return outp + esc(src.slice(lastI));
  }

  function read() {
    box.querySelectorAll("[data-k]").forEach(function (el) { state[el.dataset.k] = el.value; });
    // Em português, o campo principal é o nome em português e o opcional é o inglês.
    if (lang === "pt") {
      state.namePt = state.name; state.descPt = state.desc;
      var en = { name: state.nameEn || "", desc: state.descEn || "" };
      return Object.assign({}, state, { name: en.name || state.namePt, namePt: en.name ? state.namePt : "", desc: en.desc || state.descPt, descPt: en.desc ? state.descPt : "" });
    }
    return state;
  }

  function render() {
    box.querySelectorAll("[data-f]").forEach(function (el) {
      state.features[el.dataset.f] = el.checked;
      var more = box.querySelector('[data-more="' + el.dataset.f + '"]');
      if (more) more.hidden = !el.checked;
    });
    var r = lib.build(read(), api);
    last = r;
    out.caps.innerHTML = "<strong>" + C("It will ask for: ", "Vai pedir: ") + "</strong>" + (r.caps.length ? r.caps.map(function (c) {
      var l = api && api.labels[c];
      var tip = l ? (lang === "pt" ? l.tipPt : l.tipEn) : "";
      return '<span class="st-chip' + (l && l.strong ? " strong" : "") + '" title="' + esc(tip) + '">' + esc(l ? (lang === "pt" ? l.pt : l.en) : c) + " <code>" + esc(c) + "</code></span>";
    }).join(" ") : C("nothing beyond its own commands", "nada além dos próprios comandos"));
    if (r.warn && api) {
      out.warn.hidden = false;
      out.warn.textContent = C("Its card will say: ", "O cartão vai dizer: ") + api.warn[r.warn][lang];
    } else out.warn.hidden = true;
    out.msgs.innerHTML = r.errors.map(function (e) { return '<li class="err">' + esc(e) + "</li>"; }).join("") +
      r.notes.map(function (e) { return '<li class="note">' + esc(e) + "</li>"; }).join("");
    out.dl.textContent = C("Download ", "Baixar ") + r.file;
    out.dl.disabled = r.errors.length > 0;
    out.code.innerHTML = highlight(r.source);
    var fileInput = box.querySelector('[data-k="file"]');
    fileInput.placeholder = lib.slug(lang === "pt" ? (state.nameEn || state.name) : state.name) || "plugin";
  }

  box.addEventListener("input", render);
  box.addEventListener("change", render);
  out.dl.addEventListener("click", function () {
    if (!last || last.errors.length) return;
    var url = URL.createObjectURL(new Blob([last.source], { type: "text/plain;charset=utf-8" }));
    var a = document.createElement("a");
    a.href = url;
    a.download = last.file;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  });
  // "Copiado" só depois que a área de transferência aceitou; se não deu, o código fica selecionado.
  function copied(ok) {
    out.copy.textContent = ok ? C("Copied", "Copiado") : C("Couldn't copy: the code is selected", "Não deu para copiar: o código ficou selecionado");
    if (!ok) {
      var range = document.createRange(), sel = window.getSelection();
      range.selectNodeContents(out.code);
      sel.removeAllRanges();
      sel.addRange(range);
    }
    setTimeout(function () { out.copy.textContent = C("Copy", "Copiar"); }, ok ? 1200 : 3000);
  }
  out.copy.addEventListener("click", function () {
    if (!last) return;
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(last.source).then(function () { copied(true); }, function () { copied(false); });
    } else copied(false);
  });
  render();
})();
