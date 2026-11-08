#!/usr/bin/env node
// Testa o gerador de plugin do site (docs/assets/site/plugin-starter.js) contra o
// próprio app: as capacidades vêm de src/plugins/manifest.zig, o que cada função
// pede vem dos need(...) de src/plugins/runtime.zig e os nomes da API vêm do
// registro de lá. Cada plugin gerado tem o cabeçalho conferido como o app lê,
// passa pelo luac e roda num larper de mentira (tools/test_plugin_starter.lua),
// quando o lua está instalado.
//
//   node tools/test_plugin_starter.js                 os testes
//   node tools/test_plugin_starter.js --write PASTA   e grava dois plugins para abrir no app
"use strict";
const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawnSync } = require("child_process");

const ROOT = path.resolve(__dirname, "..");
const read = (p) => fs.readFileSync(path.join(ROOT, p), "utf8");
const starter = require(path.join(ROOT, "docs/assets/site/plugin-starter.js"));

let failures = 0, checks = 0;
function ok(cond, what) {
  checks++;
  if (!cond) { failures++; console.error("FALHOU: " + what); }
}

// --- O que o app aceita, lido do código dele -----------------------------------
const manifestZig = read("src/plugins/manifest.zig");
const CAPS = manifestZig.match(/pub const Cap = enum\(\w+\) \{([^}]*)\}/)[1].match(/\w+/g);
const MAX = {
  name: +manifestZig.match(/const max_name = (\d+);/)[1],
  description: +manifestZig.match(/const max_desc = (\d+);/)[1],
  version: +manifestZig.match(/const max_version = (\d+);/)[1],
  hosts: +manifestZig.match(/pub const max_hosts = (\d+);/)[1],
};
const DISCORD = manifestZig.match(/const family = \[_\]\[\]const u8\{([^}]*)\}/)[1].match(/"[^"]+"/g).map((s) => s.slice(1, -1));
const runtimeZig = read("src/plugins/runtime.zig");
// need(L, p, .cap, "larper.x") -> x: cap. Os temporizadores e o http usam outra forma.
const NEED = {};
for (const m of runtimeZig.matchAll(/need\(L, [^,]+, \.(\w+), "larper\.([\w.]+)"\)/g)) NEED[m[2]] = m[1];
if (/need\(L, p, \.timers, if \(every\) "larper\.every" else "larper\.after"\)/.test(runtimeZig)) NEED.after = NEED.every = "timers";
if (/need\(L, p, \.http, api\)/.test(runtimeZig)) NEED.http = "http";
delete NEED.on; // os eventos têm regra própria, abaixo
const EVENT_CAP = {};
for (const m of runtimeZig.matchAll(/if \((.*?)\) need\(L, p, \.(\w+), "larper\.on"\);/g)) {
  for (const e of m[1].matchAll(/"(\w+)"/g)) EVENT_CAP[e[1]] = m[2];
}
const EVENTS = runtimeZig.match(/const lists = \[_\]\[\*:0\]const u8\{([^}]*)\}/)[1].match(/"(\w+)"/g).map((s) => s.slice(1, -1))
  .filter((e) => ["message", "edit", "dismiss", "hosts", "ready", "delete", "channel", "lang", "panel"].includes(e));
const apiBlock = runtimeZig.match(/const api = \[_\]Fn\{([\s\S]*?)\n    \};/)[1];
const API = new Set([...apiBlock.matchAll(/\.name = "(\w+)"/g)].map((m) => m[1]));
const groupsBlock = runtimeZig.match(/const groups = \[_\]struct[\s\S]*?\n    \};/)[0];
for (const g of groupsBlock.matchAll(/\.name = "(\w+)", \.fns = &\.\{([\s\S]*?)\} \}/g)) {
  for (const f of g[2].matchAll(/\.name = "(\w+)"/g)) API.add(g[1] + "." + f[1]);
}

// Se a leitura do código quebrar, os testes abaixo passariam à toa: confere o básico.
ok(CAPS.length >= 15 && CAPS.includes("messages") && CAPS.includes("links"), "capacidades lidas de manifest.zig: " + CAPS);
ok(NEED.send === "send" && NEED.notify === "notify" && NEED.storage === "storage" && NEED.panel === "panel" && NEED.after === "timers" && NEED.http === "http" && NEED.insert === "composer" && NEED.open === "links", "need() lidos de runtime.zig: " + JSON.stringify(NEED));
ok(EVENT_CAP.message === "messages" && EVENT_CAP.dismiss === "decorate" && EVENT_CAP.hosts === "http", "regras dos eventos: " + JSON.stringify(EVENT_CAP));
ok(API.has("command") && API.has("storage.get") && API.has("http.allowed") && API.has("panel.open"), "API lida de runtime.zig");
ok(EVENTS.length === 9, "eventos: " + EVENTS);
for (const f of starter.FEATURES) for (const c of f.caps) ok(CAPS.includes(c), `a parte ${f.id} pede ${c}, que o app não conhece`);
ok(starter.MAX.name === MAX.name && starter.MAX.description === MAX.description && starter.MAX.version === MAX.version, "limites do cabeçalho iguais aos de manifest.zig");

// O `contains` de larper.on: quantos textos e quantos bytes cada um (runtime.zig optNeedles).
const needles = runtimeZig.match(/fn optNeedles[\s\S]*?n == 0 or n > (\d+)\)[\s\S]*?s\.len == 0 or s\.len > (\d+)\)/);
ok(needles && starter.NEEDLES.max === +needles[1] && starter.NEEDLES.bytes === +needles[2], "limites do contains iguais aos de runtime.zig: " + (needles && needles.slice(1)));
// Os atalhos do app saem de src/ui/atalhos.zig para plugin-api.js (tools/gen_site.py).
const PLUGIN_API = JSON.parse(read("docs/assets/site/plugin-api.js").replace(/^window\.LC_PLUGIN_API=/, "").replace(/;\s*$/, ""));
const APP_KEYS = PLUGIN_API.appKeys || [];
for (const k of ["ctrl+k", "ctrl+shift+m", "ctrl+shift+d", "ctrl+w", "ctrl+t", "ctrl+shift+t", "f2", "shift+f2", "f11", "alt+enter", "alt+1", "alt+9", "ctrl+=", "ctrl+-", "ctrl+0", "ctrl+enter", "ctrl+tab", "ctrl+d"]) {
  ok(APP_KEYS.some((a) => a.k === k), "atalho do app em plugin-api.js: " + k);
}
ok(!APP_KEYS.some((a) => /click|clique|esc|^[a-z]$|^shift\+enter$/.test(a.k)), "plugin-api.js só tem teclas que um plugin pode pedir");

const API_DATA = { caps: CAPS, maxHosts: MAX.hosts, discord: DISCORD, appKeys: APP_KEYS };

// --- O cabeçalho, lido como src/plugins/manifest.zig lê -------------------------
function parseManifest(src) {
  const m = { caps: null, hosts: [], legacy: true, problems: [] };
  const lines = src.replace(/^﻿/, "").split("\n");
  for (let i = 0; i < Math.min(lines.length, 80); i++) {
    const line = lines[i].trim();
    if (!line) continue;
    if (!line.startsWith("--")) break;
    const text = line.slice(2).trimStart();
    if (!text.startsWith("@")) continue;
    const sp = text.search(/[ \t]/);
    const key = sp < 0 ? text.slice(1) : text.slice(1, sp);
    const value = sp < 0 ? "" : text.slice(sp).trim();
    if (["name", "name:pt", "description", "description:pt", "version"].includes(key)) {
      m[key] = value;
      m.legacy = false;
    } else if (key === "capabilities") {
      m.caps = value.split(/[,\s]+/).filter(Boolean);
      m.legacy = false;
      for (const c of m.caps) if (!CAPS.includes(c)) m.problems.push("capacidade desconhecida " + c);
    } else if (key === "hosts") {
      m.hosts = value.split(/[,\s]+/).filter(Boolean);
      m.legacy = false;
      if (m.hosts.length > MAX.hosts) m.problems.push("hosts demais");
      for (const h of m.hosts) if (starter.checkHost(h, DISCORD)) m.problems.push("host ruim " + h);
    }
  }
  if (m.caps === null) m.caps = [];
  if (m.caps.includes("http") && !m.hosts.length) m.problems.push("http sem @hosts");
  if (!m.caps.includes("http") && m.hosts.length) m.problems.push("@hosts sem http");
  return m;
}

// O app usa Lua 5.4: só vale um lua/luac dessa versão.
function find(names) {
  for (const n of names) {
    const r = spawnSync(n, ["-v"], { encoding: "utf8" });
    if (!r.error && /Lua 5\.4/.test((r.stdout || "") + (r.stderr || ""))) return n;
  }
  return null;
}
const LUA = find(["lua5.4", "lua"]);
const LUAC = find(["luac5.4", "luac"]);
const HAS_LUA = !!LUA, HAS_LUAC = !!LUAC;
function luacOk(src) {
  const r = spawnSync(LUAC, ["-p", "-"], { input: src, encoding: "utf8" });
  return r.status === 0 ? true : r.stderr;
}
const NEED_ARG = Object.entries(NEED).map(([k, v]) => k + "=" + v).join(";");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "starter-"));

function validate(opts, label) {
  const r = starter.build(opts, API_DATA);
  ok(r.errors.length === 0, `${label}: erros inesperados: ${r.errors.join(" | ")}`);
  if (r.errors.length) return r;
  const m = parseManifest(r.source);
  ok(!m.legacy, `${label}: o app leria como plugin antigo`);
  ok(m.problems.length === 0, `${label}: cabeçalho com problema: ${m.problems.join(", ")}`);
  ok(JSON.stringify(m.caps) === JSON.stringify(r.caps), `${label}: @capabilities diferente do esperado`);
  const enc = (s) => Buffer.byteLength(s || "", "utf8");
  ok(enc(m.name) <= MAX.name && enc(m.description) <= MAX.description && enc(m.version) <= MAX.version, `${label}: texto que o app cortaria`);
  // Cada chamada à API existe no app e tem a capacidade pedida no cabeçalho.
  const code = r.source.split("\n").filter((l) => !l.trim().startsWith("--")).join("\n");
  for (const c of code.matchAll(/\blarper\.(\w+)(?:\.(\w+))?\s*\(/g)) {
    const name = c[2] ? c[1] + "." + c[2] : c[1];
    ok(API.has(name), `${label}: larper.${name} não existe no app`);
    const cap = NEED[name] || NEED[c[1]];
    if (cap) ok(m.caps.includes(cap), `${label}: larper.${name} pede ${cap}, que não está no cabeçalho`);
  }
  for (const e of code.matchAll(/larper\.on\("(\w+)"/g)) {
    ok(EVENTS.includes(e[1]), `${label}: evento desconhecido ${e[1]}`);
    if (EVENT_CAP[e[1]]) ok(m.caps.includes(EVENT_CAP[e[1]]), `${label}: larper.on("${e[1]}") pede ${EVENT_CAP[e[1]]}`);
  }
  for (const c of code.matchAll(/larper\.command\("([^"]+)"/g)) ok(starter.validCommand(c[1]), `${label}: comando inválido ${c[1]}`);
  for (const k of code.matchAll(/larper\.keybind\("([^"]+)"/g)) ok(starter.checkKeybind(k[1]) === null, `${label}: atalho inválido ${k[1]}`);
  ok(!/\b(io|require|load|loadfile|dofile|debug|package|coroutine|collectgarbage)\s*[.(]/.test(code), `${label}: usa algo que não existe no app`);
  if (HAS_LUAC) {
    const s = luacOk(r.source);
    ok(s === true, `${label}: luac recusou: ${s}`);
  }
  if (HAS_LUA) {
    const file = path.join(tmp, r.file);
    fs.writeFileSync(file, r.source);
    const h = spawnSync(LUA, [path.join(ROOT, "tools/test_plugin_starter.lua"), file, r.caps.join(","), NEED_ARG, r.hosts.join(","), opts.lang || "en"], { encoding: "utf8" });
    ok(h.status === 0, `${label}: falhou rodando: ${h.stderr.trim()}`);
  }
  return r;
}

// --- Combinações -----------------------------------------------------------------
const ids = starter.FEATURES.map((f) => f.id);
const base = { name: "Teste", namePt: "Teste pt", desc: "A test plugin.", descPt: "Um plugin de teste.", version: "1.2.3",
  command: "/teste", keybind: "ctrl+shift+y", contains: "larper, cve-", hosts: "api.example.com, data.example.org",
  trigger: "!", lspLang: "zig", lspCmd: "zls --enable-build-on-save" };
let combos = 0;
for (const lang of ["en", "pt"]) {
  validate(Object.assign({}, base, { lang, features: {} }), `${lang}: nada marcado`);
  validate(Object.assign({}, base, { lang, features: Object.fromEntries(ids.map((i) => [i, true])) }), `${lang}: tudo marcado`);
  for (const id of ids) { validate(Object.assign({}, base, { lang, features: { [id]: true } }), `${lang}: só ${id}`); combos++; }
  // Sorteio com semente fixa: as mesmas combinações em toda rodada.
  let seed = lang === "en" ? 12345 : 54321;
  const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  for (let n = 0; n < 150; n++) {
    const features = {};
    for (const id of ids) if (rnd() < 0.35) features[id] = true;
    validate(Object.assign({}, base, { lang, features, contains: rnd() < 0.3 ? "" : base.contains }), `${lang}: sorteio ${n} ${Object.keys(features).join(",")}`);
    combos++;
  }
}

// O que só funciona num gesto ganha um comando.
for (const id of ["send", "composer", "links", "http"]) {
  const r = starter.build(Object.assign({}, base, { features: { [id]: true } }), API_DATA);
  ok(r.features.command && /larper\.command\(/.test(r.source), `${id} sozinho ganha um comando`);
  ok(r.notes.length > 0, `${id} sozinho explica por que ganhou um comando`);
}
// Plugin que lê mensagens e manda algo para fora: o mesmo aviso do cartão.
ok(starter.build(Object.assign({}, base, { features: { onMessage: true, http: true } }), API_DATA).warn === "http", "aviso de leitura + internet");
ok(starter.build(Object.assign({}, base, { features: { onMessage: true, links: true } }), API_DATA).warn === "links", "aviso de leitura + links");
ok(starter.build(Object.assign({}, base, { features: { onMessage: true } }), API_DATA).warn === null, "sem aviso só lendo");

// --- Entradas recusadas ------------------------------------------------------------
function refuses(over, label) {
  const r = starter.build(Object.assign({}, base, over), API_DATA);
  ok(r.errors.length > 0, `devia recusar: ${label}`);
}
refuses({ name: "" }, "nome vazio");
refuses({ name: "x".repeat(49) }, "nome com 49 bytes");
refuses({ name: "ã".repeat(25) }, "nome com 50 bytes em UTF-8");
refuses({ desc: "y".repeat(321) }, "descrição longa");
refuses({ version: "1.0.0-muito-longa" }, "versão longa");
refuses({ file: "!!!" }, "arquivo sem letras");
for (const c of ["hello", "/", "/a b", "/" + "x".repeat(32), "/ção"]) refuses({ features: { command: true }, command: c }, "comando " + c);
for (const k of ["x", "shift+x", "ctrl+c", "ctrl+v", "ctrl+foo", "ctrl+a+b", "enter", "f25", "ctrl+"]) refuses({ features: { keybind: true }, keybind: k }, "atalho " + k);
for (const k of ["ctrl+shift+c", "alt+x", "f5", "super+enter", "ctrl+,", "ctrl+f24"]) ok(starter.checkKeybind(k) === null, "atalho aceito " + k);
for (const h of ["discord.com", "cdn.discordapp.com", "127.0.0.1", "localhost", "a.com:443", "https://a.com", "printer.local", "a.com/path", "-a.com"]) {
  refuses({ features: { http: true }, hosts: h }, "host " + h);
}
refuses({ features: { http: true }, hosts: "" }, "http sem host");
refuses({ features: { http: true }, hosts: "a.com b.com c.com d.com e.com f.com g.com h.com i.com" }, "nove hosts");
refuses({ features: { lsp: true }, lspLang: "Python" }, "linguagem com maiúscula");
refuses({ features: { lsp: true }, lspCmd: "" }, "lsp sem comando");
refuses({ features: { completions: true }, trigger: "#" }, "gatilho que o app não aceita");
// O plugin não carregaria: runtime.zig recusa a lista inteira.
refuses({ features: { onMessage: true }, contains: "x".repeat(65) }, "palavra com 65 bytes");
refuses({ features: { onMessage: true }, contains: "ok, " + "ã".repeat(33) }, "palavra com 66 bytes em UTF-8");
refuses({ features: { onMessage: true }, contains: Array.from({ length: 17 }, (_, i) => "w" + i).join(", ") }, "17 palavras");
validate(Object.assign({}, base, { features: { onMessage: true }, contains: Array.from({ length: 16 }, (_, i) => String(i % 10).repeat(64 - 2) + "ç").join(", ") }), "16 palavras de 64 bytes");
ok(starter.build(Object.assign({}, base, { features: { command: true }, contains: "x".repeat(70) }), API_DATA).errors.length === 0, "palavras não contam sem o evento de mensagem");
// Atalho que o app já usa: os dois disparam, então o gerador avisa (sem recusar).
for (const k of ["ctrl+shift+m", "Control+Shift+D", "ctrl+w", "ctrl+k", "ctrl+t", "f2", "alt+3", "shift+ctrl+t"]) {
  const r = starter.build(Object.assign({}, base, { features: { keybind: true }, keybind: k }), API_DATA);
  ok(r.errors.length === 0 && r.notes.some((n) => /app shortcut/.test(n)), "aviso de atalho do app: " + k);
}
for (const lang of ["en", "pt"]) {
  const r = starter.build(Object.assign({}, base, { lang, features: { keybind: true }, keybind: "ctrl+shift+m" }), API_DATA);
  const want = APP_KEYS.find((a) => a.k === "ctrl+shift+m")[lang];
  ok(r.notes.some((n) => n.includes(want)), `aviso em ${lang} com o nome do atalho: ${want}`);
}
ok(starter.build(Object.assign({}, base, { features: { keybind: true } }), API_DATA).notes.length === 0, "ctrl+shift+y não é do app: sem aviso");
// Texto do usuário vira string Lua sem escapar do lugar.
const tricky = validate(Object.assign({}, base, { name: 'Aspas "duplas" \\ e\nquebra', features: { menuMessage: true, panel: true } }), "nome com aspas e barra");
ok(!/\n-- @name:pt .*\n.*quebra/.test(tricky.source.split("\n").slice(0, 3).join("\n")), "quebra de linha não sai do cabeçalho");
ok(starter.slug("Meu Plugin Ótimo!") === "meu-plugin-otimo", "nome do arquivo a partir do nome");

// O larper de mentira pega os limites do app: sem isso, os testes acima passariam à toa.
if (HAS_LUA) {
  const fakeFails = (src, caps, hosts, label) => {
    const file = path.join(tmp, "quebrado.lua");
    fs.writeFileSync(file, src + '\nprint("loaded")\n');
    const h = spawnSync(LUA, [path.join(ROOT, "tools/test_plugin_starter.lua"), file, caps, NEED_ARG, hosts, "en"], { encoding: "utf8" });
    ok(h.status !== 0, "o larper de mentira devia recusar: " + label);
  };
  fakeFails('larper.on("message", function() end, { contains = { string.rep("x", 65) } })', "messages", "", "palavra de 65 bytes");
  fakeFails('larper.on("message", function() end, { contains = {} })', "messages", "", "contains vazio");
  fakeFails('larper.command("/a", function(t) larper.open("https://example.com/?q=" .. larper.urlencode(t)) end)', "links", "", "URL de larper.open acima de 2000 bytes");
  fakeFails('larper.command("/a", function(t) larper.http.get("https://api.example.com/?q=" .. larper.urlencode(t), function() end) end)', "http", "api.example.com", "URL de larper.http acima de 2048 bytes");
  fakeFails('larper.command("/a", function(t) if t ~= "" then larper.send(nil, t) end end)', "send", "", "larper.send acima de 2000 bytes");
  fakeFails('larper.menu("message", "x", function(m) larper.open("https://example.com/?q=" .. larper.urlencode(m.content)) end)', "menu,links", "", "mensagem longa direto na URL");
}

console.log(`${checks} conferências, ${combos} combinações, luac ${HAS_LUAC ? "sim" : "ausente"}, lua ${HAS_LUA ? "sim" : "ausente"}`);

// --- Dois plugins para abrir no app de verdade --------------------------------------
const w = process.argv.indexOf("--write");
if (w > 0) {
  const dir = path.resolve(process.argv[w + 1]);
  fs.mkdirSync(dir, { recursive: true });
  const all = starter.build(Object.assign({}, base, { lang: "en", name: "Starter everything", namePt: "Gerador tudo", file: "starter-tudo",
    command: "/tudo", keybind: "ctrl+alt+u", features: Object.fromEntries(ids.map((i) => [i, true])) }), API_DATA);
  const panel = starter.build(Object.assign({}, base, { lang: "pt", name: "Starter panel", namePt: "Gerador painel", file: "starter-painel",
    desc: "", descPt: "", command: "/painel", contains: "", features: { command: true, panel: true, onMessage: true, storage: true, notify: true, settings: true, onChannel: true } }), API_DATA);
  for (const r of [all, panel]) {
    ok(r.errors.length === 0, "plugin para o app sem erro: " + r.file);
    fs.writeFileSync(path.join(dir, r.file), r.source);
    console.log("gravado " + path.join(dir, r.file) + " (" + r.caps.join(", ") + ")");
  }
}
fs.rmSync(tmp, { recursive: true, force: true });
if (failures) { console.error(`${failures} falha(s)`); process.exit(1); }
console.log("ok");
