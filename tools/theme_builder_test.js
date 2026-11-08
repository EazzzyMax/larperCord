#!/usr/bin/env node
// Teste do criador de temas do site (docs/assets/site/theme-builder-core.js, o mesmo
// arquivo que a página usa). Exporta um tema a partir de cada tema embutido e de
// várias edições, e confere que o .kdl gerado é lido do jeito que o app lê:
// mesmo leitor de KDL, mesmas contas de cor e as mesmas regras de theme.zig e fx.zig.
// Também testa o link de compartilhar, as mensagens de erro nos dois idiomas, o contraste
// e a prévia (theme-builder-preview.js): nada que vem do arquivo pode virar marcação.
//
//   node tools/theme_builder_test.js            roda os testes
//   node tools/theme_builder_test.js --out DIR  também grava os .kdl gerados em DIR
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const assert = require("assert");
const { spawnSync } = require("child_process");

const ROOT = path.resolve(__dirname, "..");
const TB = require(path.join(ROOT, "docs/assets/site/theme-builder-core.js"));
const THEMES = ["classico", "vidro", "terminal", "subsolo", "orbital", "editorial", "bolhas", "zen", "papel", "escritorio", "cupertino"];
const MODES = ["dark", "light"];
const outIdx = process.argv.indexOf("--out");
const OUT = outIdx > 0 ? path.resolve(process.argv[outIdx + 1]) : null;

let passed = 0;
const failures = [];
function test(name, fn) {
  try {
    const r = fn();
    if (r && typeof r.then === "function") return r.then(() => { passed++; }, (e) => { failures.push([name, e]); });
    passed++;
  } catch (e) {
    failures.push([name, e]);
  }
  return Promise.resolve();
}

const sources = {};
for (const t of THEMES) sources[t] = fs.readFileSync(path.join(ROOT, "themes", t + ".kdl"), "utf8");
const structureOf = {};
for (const t of THEMES) structureOf[t] = TB.fromSource(sources[t], { base: t, name: t }).structure;
const builtinStructure = (n) => structureOf[n];

function hexes(th) {
  const o = {};
  for (const k of TB.TOKENS) o[k] = TB.toHex(th.tokens[k]);
  return o;
}
// O arquivo guarda as cores em 8 bits. Quando o app clareia muted ou faint
// (`legibleText`), ele parte do valor já arredondado: pode sobrar 1 ou 2 de diferença.
const LIFTED = ["muted", "faint"];
function close(a, b) {
  const x = TB.hexRgba(a), y = TB.hexRgba(b);
  return x.every((v, i) => Math.abs(v - y[i]) * 255 <= 2.01);
}
function snapshot(src, mode, overrides) {
  const th = TB.loadTheme(src, { mode, overrides });
  return {
    tokens: hexes(th), roles: th.roles.map(TB.toHex), ui: th.fontUi, mono: th.fontMono, size: th.fontSize,
    radius: th.radius, transparent: th.transparent, styles: Object.keys(th.styles).sort(),
    options: th.options.map((o) => o.name + "=" + o.def), name: th.name,
  };
}
// O .kdl gerado tem de passar pelo leitor de KDL e pelo carregamento do tema nos dois modos.
function checkLoads(kdl, label) {
  TB.parseKdl(kdl);
  for (const mode of MODES) {
    try {
      TB.loadTheme(kdl, { mode });
    } catch (e) {
      throw new Error(label + " (" + mode + "): " + e.message + (e.line ? " at line " + e.line : ""));
    }
  }
}
function save(name, kdl) {
  if (!OUT) return;
  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, name + ".kdl"), kdl);
}
function allOptionSets(src) {
  const opts = TB.structureOptions(src);
  const sets = [undefined];
  for (const o of opts) sets.push({ [o.name]: !o.def });
  if (opts.length) {
    const flipped = {};
    for (const o of opts) flipped[o.name] = !o.def;
    sets.push(flipped);
  }
  return sets;
}
function withColors(state, gen) {
  const s = TB.clone(state);
  s.palette = gen.palette;
  s.colors = gen.colors;
  s.roles = gen.roles;
  return s;
}

const tasks = [];

// 1. Cada tema embutido: o exportado se comporta igual ao original, com qualquer opção.
for (const t of THEMES) {
  tasks.push(test("built-in " + t + " exports an equivalent theme", () => {
    const state = TB.fromSource(sources[t], { base: t, name: t });
    const kdl = TB.toKdl(state);
    checkLoads(kdl, t);
    for (const ov of allOptionSets(sources[t])) {
      for (const mode of MODES) {
        const a = snapshot(sources[t], mode, ov);
        const b = snapshot(kdl, mode, ov);
        for (const k of LIFTED) {
          assert.ok(close(a.tokens[k], b.tokens[k]), t + " " + mode + " " + k + " " + a.tokens[k] + " vs " + b.tokens[k]);
          b.tokens[k] = a.tokens[k];
        }
        assert.deepStrictEqual(b, a, t + " " + mode + " " + JSON.stringify(ov || {}));
      }
    }
    save("tb-" + t, kdl);
  }));
  tasks.push(test("built-in " + t + " round-trips through import", () => {
    const state = TB.fromSource(sources[t], { base: t, name: t });
    const kdl = TB.toKdl(state);
    const again = TB.toKdl(TB.fromSource(kdl, { base: t, name: t }));
    assert.strictEqual(again, kdl);
  }));
}

// O formato de `css()` em gen_site.py, com o `round()` do Python (meio para o par).
function pyRound(v) {
  const f = Math.floor(v), d = v - f;
  if (Math.abs(d - 0.5) < 1e-9) return f % 2 === 0 ? f : f + 1;
  return Math.round(v);
}
function pyCss(c) {
  const b = (x) => pyRound(Math.max(0, Math.min(255, x * 255)));
  if (c[3] >= 0.999) return "#" + [c[0], c[1], c[2]].map((x) => b(x).toString(16).padStart(2, "0")).join("");
  return "rgba(" + b(c[0]) + "," + b(c[1]) + "," + b(c[2]) + "," + c[3].toFixed(3) + ")";
}

// 2. As contas de cor batem com as do gerador do site (tools/gen_site.py), fora do que
// o `legibleText` do app mexe (muted e faint) e do que o gerador não lê (paleta por modo).
tasks.push(test("color math matches gen_site.py", () => {
  const raw = fs.readFileSync(path.join(ROOT, "docs/assets/site/data.js"), "utf8");
  const data = JSON.parse(raw.slice(raw.indexOf("=") + 1).trim().replace(/;$/, ""));
  let compared = 0;
  for (const t of THEMES) {
    if (/^palette mode=/m.test(sources[t])) continue;
    for (const mode of MODES) {
      const th = TB.loadTheme(sources[t], { mode });
      for (const k of TB.TOKENS) {
        if (k === "muted" || k === "faint") continue;
        assert.strictEqual(pyCss(th.authored[k]), data.themes[t][mode][k], t + " " + mode + " " + k);
        compared++;
      }
    }
  }
  assert.ok(compared > 400, "compared " + compared);
}));

// 3. Paletas aleatórias em cima de cada layout: arquivo válido e texto secundário legível.
for (let seed = 1; seed <= 24; seed++) {
  tasks.push(test("random palette " + seed, () => {
    const base = THEMES[seed % THEMES.length];
    const seedInfo = TB.randomSeed(seed * 7919);
    const state = withColors(TB.fromSource(sources[base], { base, name: "aleatorio-" + seed }), TB.generate(seedInfo));
    const kdl = TB.toKdl(state);
    checkLoads(kdl, "random " + seed);
    for (const mode of MODES) {
      for (const row of TB.contrastReport(state, mode)) {
        if (row.app) assert.deepStrictEqual(row.fails, [], "seed " + seed + " " + mode + " " + row.fg + " " + row.ratio.toFixed(2));
      }
      // O app não precisa mexer em nada: o que sai do arquivo é o que se vê.
      const th = TB.loadTheme(kdl, { mode });
      assert.strictEqual(TB.toHex(th.tokens.muted), TB.toHex(th.authored.muted));
      assert.strictEqual(TB.toHex(th.tokens.faint), TB.toHex(th.authored.faint));
    }
    if (seed <= 3) save("tb-aleatorio-" + seed, kdl);
  }));
}

// 4. Cores de uma imagem (pixels sintéticos: degradê, cinza, duas cores, transparente).
function pixels(w, h, fn) {
  const d = new Uint8ClampedArray(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const c = fn(x / (w - 1), y / (h - 1));
    d.set(c.length === 4 ? c : c.concat(255), (y * w + x) * 4);
  }
  return d;
}
const images = {
  sunset: pixels(48, 32, (x, y) => [Math.round(40 + 200 * y), Math.round(20 + 90 * x * y), Math.round(90 - 60 * y)]),
  grey: pixels(32, 32, (x) => { const v = Math.round(30 + 200 * x); return [v, v, v]; }),
  duo: pixels(32, 32, (x) => (x < 0.5 ? [16, 24, 64] : [250, 180, 30])),
  seethrough: pixels(16, 16, (x) => [200, 30, 90, x < 0.5 ? 0 : 255]),
};
for (const [name, data] of Object.entries(images)) {
  tasks.push(test("palette from image: " + name, () => {
    const colors = TB.imageColors(data, 8, 3);
    assert.ok(colors.length > 0);
    const state = withColors(TB.fromSource(sources.orbital, { base: "orbital", name: "imagem-" + name }), TB.generate(TB.seedFromImage(colors)));
    const kdl = TB.toKdl(state);
    checkLoads(kdl, "image " + name);
    for (const mode of MODES) for (const row of TB.contrastReport(state, mode)) if (row.app) assert.deepStrictEqual(row.fails, []);
    if (name === "sunset") save("tb-imagem-por-do-sol", kdl);
  }));
}

// 5. Edições: layout de outro tema, ajustes de componente, opções, nome com aspas e acentos.
tasks.push(test("swap layout and tweak components", () => {
  const state = TB.fromSource(sources.classico, { base: "classico", name: "classico-orbital" });
  state.structure = structureOf.orbital;
  state.layoutFrom = "orbital";
  const tweaks = TB.listTweaks(state.structure);
  const msgs = tweaks.find((t) => t.name === "messages");
  assert.ok(msgs, "messages tweak");
  state.structure = TB.setProp(state.structure, msgs.start, "variant", "bubbles");
  const t2 = TB.listTweaks(state.structure).find((t) => t.name === "messages");
  assert.strictEqual(t2.fields.find((f) => f.key === "variant").value, "bubbles");
  // Tirar uma propriedade e pôr uma nova.
  state.structure = TB.setProp(state.structure, t2.start, "avatar-size", null);
  const comp = TB.listTweaks(state.structure).find((t) => t.name === "composer");
  state.structure = TB.setProp(state.structure, comp.start, "variant", "pill");
  const col = TB.listTweaks(state.structure).find((t) => t.name === "column" && t.fields.some((f) => f.key === "width"));
  state.structure = TB.setProp(state.structure, col.start, "width", 300);
  const kdl = TB.toKdl(state);
  checkLoads(kdl, "swap");
  const tw = TB.listTweaks(TB.fromSource(kdl).structure);
  assert.strictEqual(tw.find((t) => t.name === "messages").fields.find((f) => f.key === "avatar-size").value, undefined);
  assert.strictEqual(tw.find((t) => t.name === "composer").fields.find((f) => f.key === "variant").value, "pill");
  assert.ok(kdl.includes("width=300"));
  save("tb-classico-com-orbital", kdl);
}));

tasks.push(test("option defaults can be flipped", () => {
  const state = TB.fromSource(sources.vidro, { base: "vidro", name: "vidro-opaco" });
  const opaco = TB.structureOptions(state.structure).find((o) => o.name === "opaco");
  state.structure = TB.setProp(state.structure, opaco.node.start, "default", true);
  const kdl = TB.toKdl(state);
  checkLoads(kdl, "vidro opaco");
  const th = TB.loadTheme(kdl, { mode: "dark" });
  assert.strictEqual(th.values.opaco, true);
  // Com a opção ligada, o bloco `colors mode=dark when=opaco` vale: fundo opaco.
  assert.ok(th.tokens.bg[3] > 0.999, "opaque bg");
  assert.strictEqual(th.transparent, true, "window transparent=#true stays");
  save("tb-vidro-opaco", kdl);
}));

tasks.push(test("text fields are escaped", () => {
  const state = TB.fromSource(sources.zen, { base: "zen", name: "zen" });
  state.meta.name = 'Meu "tema" \\ de café';
  state.meta.author = "Zé\tda Silva";
  state.meta.desc = "Linha um\nlinha dois";
  state.meta.descEn = "Quotes \" and slashes / \\";
  state.fonts.ui = 'Font "With" Quotes';
  state.fonts.mono = "Iosevka Term";
  state.fonts.size = 13.5;
  state.radius = 0;
  state.transparent = true;
  state.meta.preview = "terminal";
  const kdl = TB.toKdl(state);
  checkLoads(kdl, "escapes");
  const th = TB.loadTheme(kdl, { mode: "dark" });
  assert.strictEqual(th.name, state.meta.name);
  assert.strictEqual(th.author, state.meta.author);
  assert.strictEqual(th.description, state.meta.desc);
  assert.strictEqual(th.descriptionEn, state.meta.descEn);
  assert.strictEqual(th.fontUi, state.fonts.ui);
  assert.strictEqual(th.fontSize, 13.5);
  assert.strictEqual(th.radius, 0);
  assert.strictEqual(th.transparent, true);
  assert.strictEqual(th.preview, "terminal");
  assert.strictEqual(TB.slug(state.meta.name), "meu-tema-de-cafe");
  save("tb-aspas", kdl);
}));

tasks.push(test("translucent and per-mode palettes survive", () => {
  const state = TB.fromSource(sources.cupertino, { base: "cupertino", name: "cupertino-2" });
  assert.notDeepStrictEqual(state.palette.dark, state.palette.light);
  state.colors.dark.surface = "#20304080";
  const kdl = TB.toKdl(state);
  assert.ok(/^palette mode=dark /m.test(kdl) && /^palette mode=light /m.test(kdl));
  checkLoads(kdl, "cupertino");
  const th = TB.loadTheme(kdl, { mode: "dark" });
  assert.strictEqual(TB.toHex(th.tokens.surface), "#20304080");
}));

// 6. O contraste: o conserto sugerido é o que o app faria, e depois dele nada falha.
tasks.push(test("contrast fix matches the app", () => {
  const state = TB.fromSource(sources.terminal, { base: "terminal", name: "t" });
  state.colors.dark.faint = state.colors.dark.bg;
  state.colors.dark.muted = state.colors.dark.surface;
  const before = TB.contrastReport(state, "dark").filter((r) => r.app && r.fails.length);
  assert.strictEqual(before.length, 2);
  for (const r of before) state.colors.dark[r.fix.tok] = r.fix.value;
  const after = TB.contrastReport(state, "dark").filter((r) => r.app && r.fails.length);
  assert.deepStrictEqual(after, []);
  const th = TB.loadTheme(TB.toKdl(state), { mode: "dark" });
  assert.strictEqual(TB.toHex(th.tokens.faint), state.colors.dark.faint);
}));

// 7. Link de compartilhar: ida e volta, com e sem compressão.
tasks.push(test("share link round-trips", () => {
  const state = TB.fromSource(sources.editorial, { base: "editorial", name: "edição" });
  state.meta.desc = "ç ã ü 日本";
  const token = TB.encodeSync(state, builtinStructure);
  return TB.decode(token, builtinStructure).then((back) => {
    assert.strictEqual(TB.toKdl(back), TB.toKdl(state));
    assert.strictEqual(TB.compact(state, builtinStructure).l, "editorial");
  });
}));
tasks.push(test("share link with a custom layout, compressed", () => {
  const state = TB.fromSource(sources.bolhas, { base: "bolhas", name: "b" });
  state.structure = state.structure.replace("variant=bubbles", "variant=irc");
  return TB.encode(state, builtinStructure).then((token) => {
    if (typeof CompressionStream !== "undefined") assert.ok(token.startsWith("d."));
    return TB.decode(token, builtinStructure);
  }).then((back) => {
    assert.ok(back.structure.includes("variant=irc"));
    assert.strictEqual(TB.toKdl(back), TB.toKdl(state));
  });
}));

// Cores translúcidas na paleta e nos cargos (8 dígitos) e links do formato antigo.
tasks.push(test("share link keeps translucent palette and role colors", () => {
  const src = sources.orbital.replace(/\npalette [^\n]*/, "") + '\npalette "#11223380" "#ff0000"\nroles "alpha(#ff0000, 0.5)" "#00ff00"\n';
  const state = TB.fromSource(src, { name: "translucido" });
  assert.strictEqual(state.palette.dark[0], "#11223380");
  assert.strictEqual(state.roles.dark[0], "#ff000080");
  return Promise.all([TB.encode(state, builtinStructure), Promise.resolve(TB.encodeSync(state, builtinStructure))]).then((tokens) =>
    Promise.all(tokens.map((tk) => TB.decode(tk, builtinStructure)))).then((backs) => {
    for (const back of backs) assert.strictEqual(TB.toKdl(back), TB.toKdl(state));
  });
}));
tasks.push(test("share links from the first format still open", () => {
  const state = TB.fromSource(sources.papel, { base: "papel", name: "antigo" });
  const c = TB.compact(state, builtinStructure);
  for (const k of ["pd", "pl", "rd", "rl"]) c[k] = c[k].split(".").join("");
  assert.strictEqual(TB.toKdl(TB.expand(c, builtinStructure)), TB.toKdl(state));
}));
tasks.push(test("damaged or hostile share links are refused with a reason", () => {
  const state = TB.fromSource(sources.zen, { base: "zen", name: "z" });
  const good = TB.compact(state, builtinStructure);
  const bad = (patch) => Object.assign(TB.clone(good), patch);
  const cases = [
    [bad({ v: 2 }), "link-version"],
    [bad({ pd: good.pd.replace(/^[0-9a-f]+/, "zz") }), "link-broken"],
    [bad({ rd: good.rd.split(".").slice(1).join(".") }), "link-broken"],
    [bad({ cd: "" }), "link-broken"],
    [bad({ l: "__proto__" }), "link-layout"],
    [bad({ l: "nao-existe" }), "link-layout"],
    [[1, 2], "link-broken"],
  ];
  for (const [c, code] of cases) assert.throws(() => TB.expand(c, builtinStructure), (e) => e.code === code, code);
  // Campos de texto viram texto; o tema de partida só aceita um nome simples (ele vai num comentário do arquivo).
  assert.strictEqual(TB.expand(bad({ r: "1e999" }), builtinStructure).radius, 6);
  const odd = TB.expand(bad({ b: "zen\nlayout { }", m: [{}, 7, null, ["x"], "nada"], f: [null, 3, "x"], r: 999 }), builtinStructure);
  assert.strictEqual(odd.base, null);
  assert.deepStrictEqual(odd.meta, { name: "", author: "7", desc: "", descEn: "", preview: "classic", license: "" });
  assert.deepStrictEqual(odd.fonts, { ui: "Inter", mono: "3", size: 16 });
  assert.strictEqual(odd.radius, 64);
  assert.strictEqual(TB.toKdl(Object.assign(odd, { base: "x\nlayout {}" })).split("\n")[1], "// Made in the larperCord theme builder, starting from xlayout.");
  return Promise.all([
    TB.decode("j.@@@", builtinStructure).then(() => { throw new Error("accepted j.@@@"); }, (e) => assert.strictEqual(e.code, "link-broken")),
    TB.decode("d.AAAA", builtinStructure).then(() => { throw new Error("accepted d.AAAA"); }, (e) => assert.strictEqual(e.code, "link-broken")),
    TB.decode("x.", builtinStructure).then(() => { throw new Error("accepted x."); }, (e) => assert.strictEqual(e.code, "link-broken")),
    // Um % estragado (link cortado por um app de conversa, "%%") é um link danificado, não uma exceção
    // que deixaria a página sem tema nenhum.
    ...["d.%%%%", "j.%E0%A4%A", "d.abc%", "j.%ZZ"].map((tk) => TB.decode(tk, builtinStructure).then(() => { throw new Error("accepted " + tk); }, (e) => assert.strictEqual(e.code, "link-broken", tk))),
  ]);
}));
// Um link que algum app codificou com % continua abrindo o mesmo tema.
tasks.push(test("share links still open after percent-encoding", () => {
  const state = TB.fromSource(sources.bolhas, { base: "bolhas", name: "b" });
  return TB.encode(state, builtinStructure).then((token) => {
    const mangled = token.replace(/[.\-_]/g, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase());
    assert.notStrictEqual(mangled, token);
    return Promise.all([TB.decode(token, builtinStructure), TB.decode(mangled, builtinStructure)]).then(([a, b]) => assert.deepStrictEqual(b, a));
  });
}));

// 8. Erros: o leitor aponta linha e coluna, como o app.
tasks.push(test("syntax errors point to line and column", () => {
  assert.throws(() => TB.parseKdl('layout {\n  row {\n    messages "sem fim\n'), (e) => e instanceof TB.KdlError && e.line >= 3);
  assert.throws(() => TB.loadTheme("colors {\n  nao-existe \"#fff\"\n}\nlayout { messages }"), (e) => e.line === 2);
  assert.throws(() => TB.loadTheme("layout {\n  row {\n    label tracking=2 color=\"@nada\"\n  }\n}"), (e) => e.line === 3);
}));

// Cada erro tem código e texto nos dois idiomas; o português usa as palavras do app.
tasks.push(test("every error has English and Portuguese text", () => {
  const en = Object.keys(TB.MSG.en).sort(), pt = Object.keys(TB.MSG.pt).sort();
  assert.deepStrictEqual(pt, en);
  const L = (s) => TB.loadTheme(s);
  const cases = [
    ["comment", () => TB.parseKdl("/* x")], ["depth", () => TB.parseKdl("a {".repeat(70))], ["close", () => TB.parseKdl("a {")],
    ["extra-close", () => TB.parseKdl("}")], ["long-number", () => TB.parseKdl("a " + "1".repeat(70))], ["number", () => TB.parseKdl("a 1.2.3")],
    ["name", () => TB.parseKdl("= x")], ["string", () => TB.parseKdl('a "abc')], ["escape", () => TB.parseKdl('a "\\q"')],
    ["option-name", () => L("options { option }\nlayout { }")], ["option-string", () => L("options { option 1 }\nlayout { }")],
    ["palette", () => L('palette "zz"\nlayout { }')], ["token", () => L('colors { nope "#fff" }\nlayout { }'), "nope"],
    ["missing-color", () => L("colors { bg }\nlayout { }")], ["color-string", () => L("colors { bg 1 }\nlayout { }")],
    ["color-expr", () => L('colors { bg "nope(" }\nlayout { }')], ["role", () => L('roles "nope"\nlayout { }')],
    ["style-name", () => L("styles { style }\nlayout { }")], ["style-string", () => L("styles { style 1 }\nlayout { }")],
    ["invalid", () => L('styles { style "s" bg="nope" }\nlayout { }'), "bg"], ["invalid", () => L('layout { row { messages vignette="nope" } }'), "vignette"],
    ["no-layout", () => L('theme "x"')], ["c-token", () => L('layout { row c-nope="#fff" { messages } }')],
    ["gradient-count", () => L('layout { row gradient="#fff" { messages } }')], ["gradient-color", () => L('layout { row gradient="#fff nope" { messages } }')],
    ["pattern-kind", () => L('layout { row pattern="x" pattern-color="#fff" { messages } }')], ["pattern-color", () => L('layout { row pattern="dots" { messages } }')],
    ["side", () => L('layout { row border-top="nope" { messages } }')], ["corners", () => L('layout { row corners="x" { messages } }')],
    ["weight", () => L('layout { row { label tracking=1 weight="gorda" } }')], ["span-text", () => L("layout { row { label { span } } }")],
    ["span-color", () => L('layout { row { label { span "x" color="nope" } } }')],
    ["link-version", () => TB.expand({ v: 9 })], ["link-broken", () => TB.expand(null)], ["link-layout", () => TB.expand(Object.assign(TB.compact(TB.fromSource(sources.zen)), { l: "nada" }), builtinStructure)],
    ["css-too-big", () => TB.importDiscordCss("a".repeat(TB.CSS_MAX + 1))], ["css-empty", () => TB.importDiscordCss(":root { --nothing-here: #fff }")],
    ["css-slow", () => { let clock = 0; TB.importDiscordCss(":root{" + "--v: #fff;".repeat(5000) + "}", { now: () => (clock += 100), budget: 1000 }); }],
    ["community-missing", () => TB.communityFromSource("// " + "x".repeat(TB.COMMUNITY_MAX))],
  ];
  const seen = new Set();
  for (const [code, fn, arg] of cases) {
    let err = null;
    try { fn(); } catch (e) { err = e; }
    assert.ok(err, code + " was not thrown");
    assert.strictEqual(err.code, code, "expected " + code + ", got " + err.code + " (" + err.message + ")");
    if (arg !== undefined) assert.strictEqual(err.arg, arg);
    const ptText = TB.errorText(err, "pt"), enText = TB.errorText(err, "en");
    assert.strictEqual(enText, err.message);
    assert.notStrictEqual(ptText, enText, code);
    seen.add(code);
  }
  assert.strictEqual(TB.errorText(cases[12][1] && (() => { try { cases[12][1](); } catch (e) { return e; } })(), "pt"), "token de cor desconhecido: nope");
  assert.strictEqual(TB.errorText({ code: "invalid", arg: "border" }, "pt"), "border inválida");
  assert.strictEqual(TB.errorText({ code: "invalid", arg: "grain" }, "pt"), "grain inválido");
  // Sem DecompressionStream, o link comprimido diz que o navegador não abre.
  const saved = global.DecompressionStream;
  delete global.DecompressionStream;
  return TB.decode("d.AAAA", builtinStructure).then(() => { throw new Error("accepted"); }, (e) => {
    global.DecompressionStream = saved;
    assert.strictEqual(e.code, "link-unsupported");
    seen.add("link-unsupported");
    assert.deepStrictEqual([...seen].sort(), en, "every message is reachable");
  });
}));

// 9. A prévia: nada do arquivo vira marcação. Um link compartilhado pode trazer
// qualquer layout, então cada componente é desenhado com valores hostis em todas as
// propriedades que ele lê, e o HTML só pode ter as tags e os atributos da própria prévia.
const PREVIEW = require(path.join(ROOT, "docs/assets/site/theme-builder-preview.js"));
const TAGS = new Set(["div", "span", "b", "i", "em", "small", "u", "a", "p", "time", "hr", "svg", "path", "circle", "line", "pre", "kbd", "strong"]);
const ATTRS = new Set(["class", "style", "viewBox", "aria-hidden", "d", "cx", "cy", "r", "fill", "stroke", "stroke-width", "stroke-dasharray", "stroke-linecap", "opacity", "x1", "y1", "x2", "y2", "preserveAspectRatio"]);
// Lê o HTML como o navegador lê os atributos entre aspas duplas: uma aspa sem escape
// fecharia o valor, e o resto viraria outro atributo (pego pela lista acima).
function scanHtml(html) {
  const tags = [], attrs = [];
  let i = 0;
  while (i < html.length) {
    const lt = html.indexOf("<", i);
    if (lt < 0) break;
    const m = /^<(\/?)([a-zA-Z][a-zA-Z0-9-]*)/.exec(html.slice(lt));
    if (!m) throw new Error("stray < at " + lt + ": " + html.slice(lt, lt + 40));
    if (!m[1]) tags.push(m[2]);
    let j = lt + m[0].length;
    for (;;) {
      while (/\s/.test(html[j])) j++;
      if (html[j] === ">") { j++; break; }
      if (html.startsWith("/>", j)) { j += 2; break; }
      const am = /^([^\s=>\/"']+)(?:="([^"]*)")?/.exec(html.slice(j));
      if (!am) throw new Error("bad attribute at " + j + ": " + html.slice(j, j + 40));
      attrs.push(am[1]);
      if (am[2] !== undefined && /[<>]/.test(am[2])) throw new Error("< or > inside an attribute: " + am[2].slice(0, 60));
      j += am[0].length;
    }
    i = j;
  }
  return { tags, attrs };
}
const HOSTILE = 'x" onmouseover="alert(1)" a=\'<img src=x onerror=alert(2)>\' b="';
const KEYS = ["variant", "shape", "icon-style", "orientation", "avatar", "align", "kind", "font", "items", "ornament", "ornament-text", "text", "text-en",
  "weight", "color", "color2", "color3", "fill", "dot", "ornament-color", "style", "corners", "labels", "home", "indicators", "banner", "header", "divider",
  "ruled", "ticks", "vertical", "fade", "bg", "gradient", "pattern", "pattern-color", "grain", "border", "border-top", "vignette", "drop-shadow", "inner-shadow"];
for (const lang of ["en", "pt"]) {
  tasks.push(test("preview escapes everything from the file (" + lang + ")", () => {
    const P = PREVIEW(TB, lang);
    const th = TB.loadTheme(sources.orbital, { mode: "dark" });
    const props = KEYS.map((k) => k + "=" + TB.quote(HOSTILE)).join(" ");
    const kids = " {\n  span " + TB.quote(HOSTILE) + " en=" + TB.quote(HOSTILE) + " font=" + TB.quote(HOSTILE) + " weight=" + TB.quote(HOSTILE) + " color=" + TB.quote(HOSTILE) + "\n}";
    for (const name of P.names) {
      for (const src of [name + " " + props, name + " " + props + kids, name + " size=1e999 spacing=1e999 density=1e999 rings=1e999 levels=1e999 thickness=-5"]) {
        const nd = TB.parseKdl(src)[0];
        const out = P.component(name, th, nd, th.tokens);
        assert.strictEqual(typeof out, "string", name);
        const { tags, attrs } = scanHtml(out);
        for (const t of tags) assert.ok(TAGS.has(t), name + ": tag <" + t + ">");
        for (const a of attrs) assert.ok(ATTRS.has(a), name + ": attribute " + a);
      }
      // A caixa do nó (fundo, borda, sombra) com cores hostis: nada é escrito.
      const el = { style: {} };
      P.paintBox(th, el, TB.parseKdl("x " + props)[0], th.tokens);
      assert.deepStrictEqual(el.style, {}, name + " paintBox");
    }
    // Nomes que existem em todo objeto do JavaScript não são componentes.
    for (const name of ["constructor", "__proto__", "toString", "hasOwnProperty", "valueOf"]) assert.strictEqual(P.component(name, th, TB.parseKdl("x")[0], th.tokens), null, name);
    // Valores que o app conhece passam; os outros caem no padrão do componente, como no app.
    const msg = (s) => P.component("messages", th, TB.parseKdl("messages " + s)[0], th.tokens);
    assert.ok(msg("variant=irc").includes('class="pv-msgs irc'));
    assert.ok(msg("avatar=square").includes('class="pv-av square"'));
    assert.ok(msg('variant="weird"').includes('class="pv-msgs cozy'));
    const rule = P.component("rule", th, TB.parseKdl('rule ornament-text="§" font="Liberation Serif"')[0], th.tokens);
    assert.ok(rule.includes("font-family:&quot;Liberation Serif&quot;,var(--f-ui)"), rule);
  }));
}

// Opções e estilos com nomes de propriedades do JavaScript não confundem o carregamento.
tasks.push(test("option and style names like constructor are plain names", () => {
  const th = TB.loadTheme('styles { style "card" bg="#fff" }\nlayout { row { messages when=constructor style="toString" } }', { mode: "dark" });
  assert.strictEqual(th.values.constructor, undefined);
  assert.strictEqual(th.styles.toString, undefined);
}));

// Contraste: blocos do layout que trocam cores contam, e o conserto de um clique limpa o aviso.
tasks.push(test("contrast uses the colors an option block puts in place", () => {
  const state = TB.fromSource(sources.terminal, { base: "terminal", name: "t" });
  const verde = TB.structureOptions(state.structure).find((o) => o.name === "verde");
  state.structure = TB.setProp(state.structure, verde.node.start, "default", true);
  state.colors.dark.text = "#555555";
  const blocks = TB.layoutColorBlocks(state, "dark");
  assert.ok(blocks.some((b) => b.kind === "colors" && b.when === "verde" && b.tokens.includes("text")));
  assert.ok(blocks.some((b) => b.kind === "roles" && b.when === "verde"));
  assert.deepStrictEqual(TB.layoutColorBlocks(state, "light"), []);
  const th = TB.loadTheme(TB.toKdl(state), { mode: "dark" });
  const text = TB.contrastReport(state, "dark").find((r) => r.id === "text");
  assert.strictEqual(TB.toHex(TB.effectiveColors(state, "dark").toks.text), TB.toHex(th.authored.text));
  assert.deepStrictEqual(text.fails, []);
  // Um token trocado pelo layout que falha não ganha botão: mudar o campo não mudaria nada.
  state.structure = state.structure.replace(/(colors mode=dark when=verde \{[^}]*?)(\n\s*muted\s+)"[^"]+"/, '$1$2"#0a0a0a"');
  const muted = TB.contrastReport(state, "dark").find((r) => r.id === "muted");
  assert.ok(muted.fails.length && muted.gated && muted.fix === null, JSON.stringify(muted));
}));
tasks.push(test("one-click contrast fix always clears the warning", () => {
  let fixes = 0;
  for (let seed = 1; seed <= 300; seed++) {
    const s = TB.fromSource(sources.orbital, { name: "z" });
    const r = TB.rng(seed);
    for (const m of MODES) {
      const bg = TB.hexRgba(s.colors[m].bg);
      for (const tok of ["muted", "faint", "link"]) s.colors[m][tok] = TB.toHex(TB.mix(TB.hexRgba(s.colors[m][tok]), bg, 0.3 + r() * 0.65));
      for (const row of TB.contrastReport(s, m).filter((x) => x.fails.length && x.fix)) {
        s.colors[m][row.fix.tok] = row.fix.value;
        assert.deepStrictEqual(TB.contrastReport(s, m).find((x) => x.id === row.id).fails, [], m + " " + row.id + " " + row.fix.value);
        fixes++;
      }
    }
  }
  assert.ok(fixes > 500, "fixes " + fixes);
  // Quando nem o texto chega no mínimo, a linha diz isso em vez de sugerir uma cor que não resolve.
  const s = TB.fromSource(sources.orbital, { name: "z" });
  s.colors.dark.text = "#6b6b6b";
  s.colors.dark.muted = "#202020";
  const row = TB.contrastReport(s, "dark").find((x) => x.id === "muted");
  assert.ok(row.stuck && row.fix === null && row.lift, JSON.stringify(row));
}));

// 10. A prévia montada (theme-builder-preview.js `mount`), com um DOM de mentira: o criador
// e a galeria da comunidade desenham por ela.
function fakeDocument() {
  const made = [];
  function el(tag) {
    const e = {
      tag, kids: [], className: "", _text: "", _html: "", ownerDocument: doc, dataset: {},
      style: { setProperty(k, v) { this[k] = v; } },
      classList: { set: new Set(), add(c) { this.set.add(c); }, remove(c) { this.set.delete(c); }, toggle(c, on) { if (on) this.set.add(c); else this.set.delete(c); } },
      appendChild(k) { this.kids.push(k); return k; },
      set textContent(v) { this._text = v; this.kids = []; }, get textContent() { return this._text; },
      set innerHTML(v) { this._html = v; }, get innerHTML() { return this._html; },
    };
    made.push(e);
    return e;
  }
  const doc = { createElement: el, made };
  return doc;
}
tasks.push(test("mount draws every built-in layout with the shared renderer", () => {
  const P = PREVIEW(TB, "en");
  for (const t of THEMES) {
    for (const mode of MODES) {
      const doc = fakeDocument(), frame = doc.createElement("div"), th = TB.loadTheme(sources[t], { mode });
      P.mount(frame, th);
      assert.strictEqual(frame.kids.length, 1, t + " root");
      assert.strictEqual(frame.style["--t-bg"], TB.cssColor(th.tokens.bg));
      const comps = doc.made.filter((e) => e.className === "pv-c");
      assert.ok(comps.length >= 3, t + " " + mode + " components " + comps.length);
      for (const c of comps) if (c._html) scanHtml(c._html);
      assert.ok(!doc.made.some((e) => e.className.includes("pv-bad")), t + " has no unknown component");
      // As caixas levam a camada e os tokens para o clique-para-editar: só números e nomes da lista.
      const boxes = doc.made.filter((e) => e.className === "pv-b");
      assert.ok(boxes.length && boxes.every((b) => /^\d+$/.test(b.dataset.start) && /^\d+$/.test(b.dataset.line)), t + " layer data");
      for (const b of boxes) {
        for (const k of ["tk", "over"]) if (b.dataset[k]) for (const tok of b.dataset[k].split(" ")) assert.ok(TB.TOKENS.includes(tok), t + " " + k + " " + tok);
        if (b.dataset.fg) assert.ok(TB.TOKENS.includes(b.dataset.fg), t + " fg " + b.dataset.fg);
        if (b.dataset.node) assert.ok(/^[a-z][a-z0-9-]*$/.test(b.dataset.node));
      }
      assert.ok(boxes.some((b) => b.dataset.tk), t + " has panels with a token background");
    }
  }
}));

// 11. Metadados da galeria: licença no arquivo e no link, e a lista do que falta.
tasks.push(test("license goes in the file and in the share link", () => {
  const state = TB.fromSource(sources.zen, { base: "zen", name: "Calma" });
  state.meta.author = "Ana";
  state.meta.license = "CC-BY-4.0";
  const kdl = TB.toKdl(state);
  assert.ok(/^theme "Calma" .*author="Ana" license="CC-BY-4.0" preview=/m.test(kdl), kdl.split("\n")[2]);
  checkLoads(kdl, "license");
  assert.strictEqual(TB.fromSource(kdl).meta.license, "CC-BY-4.0");
  const c = TB.compact(state, builtinStructure);
  assert.strictEqual(TB.expand(c, builtinStructure).meta.license, "CC-BY-4.0");
  c.m = c.m.slice(0, 5);
  assert.strictEqual(TB.expand(c, builtinStructure).meta.license, "");
}));
tasks.push(test("community checklist", () => {
  const bad = (s) => TB.communityCheck(s, THEMES).filter((c) => !c.ok).map((c) => c.id);
  const s = TB.fromSource(sources.orbital, { base: "orbital", name: "my-orbital" });
  s.meta.author = "";
  s.meta.license = "";
  s.meta.desc = s.meta.descEn = "";
  assert.deepStrictEqual(bad(s), ["author", "description", "license"]);
  Object.assign(s.meta, { author: "Ana", descEn: "Mint on graphite.", license: "CC0-1.0" });
  assert.deepStrictEqual(bad(s), []);
  // Só licenças abertas da lista, com AND / OR; um nome inventado com cara de SPDX não passa.
  for (const lic of ["my license", "CC0-1.0 OR", "", "x".repeat(70), "MIT\nGPL", "NOT-A-LICENSE", "Proprietary", "All-Rights-Reserved",
    "mit", "CC-BY-NC-4.0", "CC-BY-ND-4.0", "MIT WITH Classpath-exception-2.0", "MIT  OR ISC", "OR MIT", "MIT OR"]) { s.meta.license = lic; assert.deepStrictEqual(bad(s), ["license"], lic); }
  for (const lic of ["MIT", "CC-BY-SA-4.0", "GPL-3.0-or-later OR MIT", "CC-BY-4.0 AND MIT", "0BSD"]) { s.meta.license = lic; assert.deepStrictEqual(bad(s), [], lic); }
  // A lista do criador é a mesma do gerador do site.
  const py = spawnSync("python3", ["-I", "-B", "-c", "import sys, json; sys.path.insert(0, sys.argv[1]); import gen_site; print(json.dumps(gen_site.LICENSES))", path.join(ROOT, "tools")], { encoding: "utf8" });
  assert.strictEqual(py.status, 0, py.stderr);
  assert.deepStrictEqual(JSON.parse(py.stdout), TB.LICENSES);
  // Partiu do orbital e não mudou a descrição: a lista pede uma própria.
  const descs = THEMES.flatMap((t) => { const m = TB.fromSource(sources[t]).meta; return [m.desc, m.descEn]; });
  s.meta.license = "MIT";
  s.meta.descEn = TB.fromSource(sources.orbital).meta.descEn;
  const d = TB.communityCheck(s, THEMES, descs).find((c) => c.id === "description");
  assert.ok(!d.ok && d.copied);
  s.meta.descEn = "Mint on graphite.";
  s.meta.license = "GPL-3.0-or-later OR MIT";
  s.meta.name = "Orbital";
  const name = TB.communityCheck(s, THEMES)[0];
  assert.ok(!name.ok && name.builtin && name.file === "orbital");
}));

// 12. Cores de um tema do Discord. Três CSS escritos à mão para o teste (nenhum copiado de
// um tema de verdade): um com os nomes antigos, um com os novos e um quebrado e hostil.
const CSS_OLD = `/**
 * @name Lilac Night
 * @author test fixture
 * @description Handwritten sample for the importer test.
 */
@import url("https://example.invalid/lilac/base.css");
@import 'https://example.invalid/lilac/fonts.css';
:root {
  --lilac-hue: 265;
  --lilac-bg: hsl(var(--lilac-hue) 18% 12%);
  --accent-rgb: 167, 139, 250;
}
.theme-dark {
  --background-primary: var(--lilac-bg);
  --background-secondary: #17141f;
  --background-secondary-alt: #1f1b2b;
  --background-tertiary: rgb(14 12 20);
  --background-floating: #0f0d16;
  --channeltextarea-background: #241f33;
  --background-modifier-hover: rgba(200, 180, 255, 0.06);
  --background-modifier-selected: hsla(265, 60%, 70%, 0.16);
  --background-modifier-accent: rgb(200 180 255 / 10%);
  --text-normal: #ece8f6;
  --channels-default: #b3aac8;
  --text-muted: #8f86a6; /* timestamps */
  --text-link: #7dd3fc;
  --brand-experiment: rgb(var(--accent-rgb));
  --status-positive: #4ade80;
  --status-warning: #fbbf24;
  --status-danger: #f87171;
}
.theme-light {
  --background-primary: #fbf9ff;
  --background-secondary: #f1edf9;
  --background-tertiary: #e6e0f2;
  --text-normal: #1d1730;
  --text-muted: #6b6280;
  --brand-experiment: #6d28d9;
}`;
const CSS_NEW = `/* Moss: handwritten sample with the newer variable names */
.visual-refresh.theme-dark {
  --background-base-lowest: #0d1210;
  --background-base-lower: #121916;
  --background-base-low: #17201c;
  --background-surface-high: #1e2a25;
  --background-surface-highest: #24332d;
  --text-default: #e3efe8;
  --text-secondary: #b5c9bf;
  --text-muted: #8aa397;
  --text-link: #6ee7b7;
  --bg-brand: #34d399;
  --bg-mod-faint: rgb(255 255 255 / 0.04);
  --bg-mod-strong: rgb(255 255 255 / 0.12);
  --border-subtle: #ffffff14;
  --text-feedback-positive: #4ade80;
  --text-feedback-warning: #facc15;
  --text-feedback-critical: #fb7185;
}
@media (prefers-color-scheme: light) {
  :root {
    --bg-base-primary: #f6faf8;
    --bg-base-secondary: #edf4f0;
    --bg-base-tertiary: #e2ece7;
    --text-default: #10201a;
    --bg-brand: #047857;
  }
}`;
const CSS_HOSTILE = `@import url(javascript:alert(1));
@import "</style><script>alert(2)</script>";
:root{--background-primary:#202225;--text-normal:</style><script>alert(3)</script>;--brand-experiment:expression(alert(4));--text-link:url("javascript:alert(5)")}
.chat-3bRxxu .messages { --background-primary: #ff0000 !important; }
.theme-dark { --background-secondary: transparent; --background-tertiary: color-mix(in lab, red 50%, blue); --background-floating: #18191c }
--x</style>: red;
</style><script>alert(6)</script> { --background-secondary-alt: #000 }
.weird { content: "}"; --text-muted: #72767d; }
.a { --a: var(--b); --b: var(--a); --header-primary: var(--a, #dcddde) }
}}}
@media screen { .theme-dark { --background-modifier-hover: rgba(79,84,92,.16) } }
.unclosed { --interactive-normal: #b9bbbe`;
function mapOf(r) { const o = {}; for (const m of r.mapped.concat(r.derived)) o[m.tok] = m.value; return o; }
function fromOf(r) { const o = {}; for (const m of r.mapped) o[m.tok] = m.from; return o; }
function importAndApply(css, base, name) {
  const res = TB.importDiscordCss(css);
  const state = TB.applyCssImport(TB.fromSource(sources[base], { base, name }), res);
  const kdl = TB.toKdl(state);
  checkLoads(kdl, name);
  for (const mode of MODES) {
    assert.ok(Array.isArray(TB.contrastReport(state, mode)));
    for (const t of TB.TOKENS) assert.ok(/^#[0-9a-f]{6}([0-9a-f]{2})?$/.test(state.colors[mode][t]), name + " " + mode + " " + t);
  }
  return { res, state, kdl };
}
tasks.push(test("Discord CSS, older variable names", () => {
  const { res, state, kdl } = importAndApply(CSS_OLD, "orbital", "lilac-night");
  const d = mapOf(res.modes.dark), l = mapOf(res.modes.light);
  assert.deepStrictEqual(res.imports, ["https://example.invalid/lilac/base.css", "https://example.invalid/lilac/fonts.css"]);
  assert.strictEqual(d.bg, "#1e1924");          // hsl(var(--lilac-hue) 18% 12%)
  assert.strictEqual(d.sidebar, "#17141f");
  assert.strictEqual(d.rail, "#0e0c14");        // rgb(14 12 20)
  assert.strictEqual(d.overlay, "#0f0d16");
  assert.strictEqual(d.elevated, "#241f33");
  assert.strictEqual(d["bubble-other"], "#1f1b2b");
  assert.strictEqual(d.text, "#ece8f6");
  assert.strictEqual(d.muted, "#b3aac8");
  assert.strictEqual(d.faint, "#8f86a6");
  assert.strictEqual(d.link, "#7dd3fc");
  assert.strictEqual(d.accent, "#a78bfa");      // rgb(var(--accent-rgb))
  assert.strictEqual(d["bubble-self"], "#a78bfa");
  assert.strictEqual(d["accent-text"], "#000000");
  assert.strictEqual(d.hover, "#c8b4ff0f");
  assert.strictEqual(d.selected, "#ab85e029");   // hsla(265, 60%, 70%, 0.16)
  assert.strictEqual(d.border, "#c8b4ff1a");
  assert.deepStrictEqual([d.online, d.idle, d.dnd, d.danger], ["#4ade80", "#fbbf24", "#f87171", "#f87171"]);
  assert.strictEqual(fromOf(res.modes.dark).text, "--text-normal");
  assert.deepStrictEqual(res.modes.dark.kept, ["shadow"]);
  // O claro só tem o que o bloco .theme-light diz; o resto fica como estava no tema de partida.
  assert.deepStrictEqual([l.bg, l.sidebar, l.rail, l.text, l.faint, l.accent, l["accent-text"]], ["#fbf9ff", "#f1edf9", "#e6e0f2", "#1d1730", "#6b6280", "#6d28d9", "#ffffff"]);
  const orig = TB.fromSource(sources.orbital, { base: "orbital", name: "x" });
  for (const t of res.modes.light.kept) assert.strictEqual(state.colors.light[t], orig.colors.light[t], "light kept " + t);
  assert.ok(res.modes.light.kept.includes("muted") && res.modes.light.kept.includes("link"));
  assert.deepStrictEqual(state.roles, orig.roles);
  assert.strictEqual(state.structure, orig.structure);
  save("tb-css-lilac-night", kdl);
}));
tasks.push(test("Discord CSS, newer variable names and a light media block", () => {
  const { res, kdl } = importAndApply(CSS_NEW, "classico", "moss");
  const d = mapOf(res.modes.dark), l = mapOf(res.modes.light), f = fromOf(res.modes.dark);
  assert.deepStrictEqual([d.bg, d.sidebar, d.rail, d.elevated, d.overlay], ["#17201c", "#121916", "#0d1210", "#1e2a25", "#24332d"]);
  assert.deepStrictEqual([f.bg, f.rail, f.text, f.accent, f.mention], ["--background-base-low", "--background-base-lowest", "--text-default", "--bg-brand", "--bg-brand"]);
  assert.deepStrictEqual([d.text, d.muted, d.faint, d.link, d.accent], ["#e3efe8", "#b5c9bf", "#8aa397", "#6ee7b7", "#34d399"]);
  assert.deepStrictEqual([d.hover, d.selected, d.border], ["#ffffff0a", "#ffffff1f", "#ffffff14"]);
  assert.deepStrictEqual([d.online, d.idle, d.dnd, d.danger], ["#4ade80", "#facc15", "#fb7185", "#fb7185"]);
  assert.deepStrictEqual([l.bg, l.sidebar, l.rail, l.text, l.accent], ["#f6faf8", "#edf4f0", "#e2ece7", "#10201a", "#047857"]);
  assert.strictEqual(fromOf(res.modes.light).bg, "--bg-base-primary");
  assert.ok(res.modes.light.kept.includes("faint"), "the light block has no --text-muted");
  save("tb-css-moss", kdl);
}));
tasks.push(test("Discord CSS that is broken and hostile maps only real colors", () => {
  const { res, state, kdl } = importAndApply(CSS_HOSTILE, "orbital", "hostil");
  const d = mapOf(res.modes.dark), skipped = {};
  for (const x of res.modes.dark.skipped) skipped[x.tok] = x.why;
  assert.strictEqual(res.modes.light, null);
  assert.strictEqual(d.bg, "#202225", "a component's !important doesn't beat :root");
  assert.strictEqual(d.overlay, "#18191c");
  assert.strictEqual(d.text, "#dcddde", "var() cycle falls back");
  assert.strictEqual(d.faint, "#72767d", "a } inside a string doesn't end the rule");
  assert.strictEqual(d.muted, "#b9bbbe", "unclosed rule at the end still counts");
  assert.strictEqual(d.hover, "#4f545c29");
  assert.deepStrictEqual([skipped.sidebar, skipped.rail, skipped.accent, skipped.link], ["transparent", "unreadable", "unreadable", "unreadable"]);
  assert.ok(!("accent-text" in d), "no accent, no derived text");
  // Como no CSS, url( sem aspas termina no primeiro ")". A lista é só para ler: nada é aberto.
  assert.deepStrictEqual(res.imports, ["javascript:alert(1", "</style><script>alert(2)</script>"]);
  assert.ok(res.notes.brace >= 3 && res.notes.unclosed >= 1 && res.notes.rule >= 1, JSON.stringify(res.notes));
  // Nada do CSS chega ao arquivo nem ao estado: só cores em hex e nomes de variáveis da lista.
  assert.ok(!/<script|<\/style|alert\(|javascript:/i.test(kdl));
  assert.ok(!/<|alert/.test(JSON.stringify(state)));
  for (const m of res.modes.dark.mapped.concat(res.modes.dark.skipped)) assert.ok(/^--[a-z0-9-]+$/.test(m.from), m.from);
}));
tasks.push(test("Discord CSS limits: size, time and pathological input", () => {
  assert.throws(() => TB.importDiscordCss("a".repeat(TB.CSS_MAX + 1)), (e) => e.code === "css-too-big");
  assert.throws(() => TB.importDiscordCss(""), (e) => e.code === "css-empty");
  assert.throws(() => TB.importDiscordCss("body { color: red; background: #fff }"), (e) => e.code === "css-empty");
  // Quase 500 KB de variáveis de verdade: lê rápido e acha a do fim.
  let big = ":root {\n";
  for (let i = 0; big.length < TB.CSS_MAX - 200; i++) big += "  --v" + i + ": #" + ((i * 2654435761) >>> 8).toString(16).padStart(6, "0").slice(-6) + ";\n";
  big += "  --background-primary: #123456;\n}";
  assert.ok(big.length <= TB.CSS_MAX && big.length > 480 * 1024);
  let t0 = Date.now();
  assert.strictEqual(mapOf(TB.importDiscordCss(big).modes.dark).bg, "#123456");
  assert.ok(Date.now() - t0 < 3000, "big CSS took " + (Date.now() - t0) + " ms");
  const evil = {
    parens: ":root{--background-primary:#111;}" + "(".repeat(490000),
    comment: ":root{--background-primary:#111;}/*" + "x".repeat(490000),
    braces: ":root{--background-primary:#111;}" + "{".repeat(240000) + "}".repeat(240000),
    strings: ":root{--background-primary:#111;}" + "'\\".repeat(240000),
    nesting: ":root{--background-primary:#111;}" + ".a{".repeat(100000),
    fanout: ":root{--background-primary:#111;--z0:#fff;" + Array.from({ length: 12 }, (_, k) => "--z" + (k + 1) + ":" + ("var(--z" + k + ") ").repeat(300) + ";").join("") + "--text-normal:var(--z12)}",
    cycle: ":root{--background-primary:#111;" + Array.from({ length: 2000 }, (_, k) => "--c" + k + ":var(--c" + ((k + 1) % 2000) + ");").join("") + "--text-normal:var(--c0)}",
  };
  for (const [k, css] of Object.entries(evil)) {
    t0 = Date.now();
    const r = TB.importDiscordCss(css);
    assert.strictEqual(mapOf(r.modes.dark).bg, "#111111", k);
    assert.ok(!("text" in mapOf(r.modes.dark)), k + " text");
    assert.ok(Date.now() - t0 < 3000, k + " took " + (Date.now() - t0) + " ms");
  }
  // O relógio passa do limite: para com o erro de tempo em vez de travar a página.
  let clock = 0;
  assert.throws(() => TB.importDiscordCss(big, { now: () => (clock += 5), budget: 200 }), (e) => e.code === "css-slow");
  // Cores do CSS que o leitor entende, e as que ele recusa.
  const C = (s) => { const c = TB.parseCssColor(s); return c && TB.toHex(c); };
  assert.deepStrictEqual(["#abc", "#AABBCC80", "rgb(255 0 0 / 50%)", "rgba(0,0,255,.25)", "hsl(120deg 100% 25%)", "hsl(0.5turn, 100%, 50%)", "white", "transparent", "rgb(100%, 50%, 0%)"].map(C),
    ["#aabbcc", "#aabbcc80", "#ff000080", "#0000ff40", "#008000", "#00ffff", "#ffffff", "#00000000", "#ff8000"]);
  // oklch()/oklab() (OKLab de referência: vermelho puro é L 0.62796, C 0.25768, h 29.234) e color-mix()
  // com as contas do CSS Color 5: porcentagens que somam menos de 100 baixam o alfa, `transparent` não puxa o matiz.
  assert.deepStrictEqual(["oklch(62.796% 0.25768 29.234)", "oklab(0.62796 0.22486 0.12585)", "oklch(70% 0.1 215)", "oklch(0.7 25% 215 / 50%)", "oklch(100% 0.4 30)", "oklch(0 0 none)"].map(C),
    ["#ff0000", "#ff0000", "#46aec5", "#46aec580", "#ffffff", "#000000"]);
  assert.deepStrictEqual(["color-mix(in srgb, red 50%, blue)", "color-mix(in srgb, red, blue)", "color-mix(in srgb, 25% red, blue)", "color-mix(in srgb, red 30%, blue 30%)",
    "color-mix(in hsl, #ff0000, transparent 80%)", "color-mix(in hsl, white, black)", "color-mix(in oklch, red, transparent)", "color-mix(in srgb-linear, black, white)",
    "color-mix(in hsl, color-mix(in hsl, hsl(220, 20%, 60%), transparent 95%) 40%, transparent)"].map(C),
    ["#800080", "#800080", "#4000bf", "#80008099", "#ff000033", "#808080", "#ff000080", "#bcbcbc", "#8592ad05"]);
  for (const s of ["", "#ggg", "rgb(1,2)", "rgb(1,2,3,4,5)", "hsl(x 1% 1%)", "url(x)", "var(--x)", "rgb(1 2 3) x", "linear-gradient(red, blue)",
    "color-mix(in lab, red, blue)", "color-mix(in srgb, red 120%, blue)", "color-mix(in srgb, red 0%, blue 0%)", "color-mix(in srgb, red)", "color-mix(srgb, red, blue)",
    "color-mix(in hsl longer hue, red, blue)", "rgb(from red r g b)", "oklch(x 0.1 200)", "oklch(0.5 0.1)",
    "color-mix(in srgb, " + "color-mix(in srgb, ".repeat(8) + "red, blue" + ", blue)".repeat(8) + ", blue)"]) assert.strictEqual(C(s), null, s);
}));
tasks.push(test("Discord CSS: a url( that never closes doesn't freeze the page", () => {
  // Uma expressão regular com \s* dos dois lados de [^)]* levava minutos com poucos KB disto.
  const fills = [" ", "\t", "(", "'", "\\", "/*", "url(", "a"];
  for (const head of ["@import url(", "@import url(\"", "@import url('", "@import ", "@media (", ":root{--background-primary:#111;--x:url(", ":root{--background-primary:#111;--x:var("]) {
    for (const fill of fills) {
      const css = ":root{--background-primary:#111}" + head + fill.repeat(Math.floor(200000 / fill.length)) + "x";
      const t0 = Date.now();
      let r = null;
      try { r = TB.importDiscordCss(css); } catch (e) { assert.ok(["css-empty", "css-slow"].includes(e.code), e.message); }
      const ms = Date.now() - t0;
      assert.ok(ms < 1000, JSON.stringify(head) + " + " + JSON.stringify(fill) + " took " + ms + " ms");
      if (r) for (const u of r.imports) assert.ok(u.length <= 200, "import shown in full: " + u.length);
    }
  }
  const t0 = Date.now();
  const r = TB.importDiscordCss(":root{--background-primary:#222}\n@import url(" + " ".repeat(50000) + "x");
  assert.ok(Date.now() - t0 < 1000, "took " + (Date.now() - t0) + " ms");
  assert.strictEqual(r.imports.length, 1, "listed, read only up to 2 KB");
  assert.strictEqual(mapOf(r.modes.dark).bg, "#222222");
  assert.deepStrictEqual(TB.importDiscordCss(":root{--background-primary:#222}\n@import url(  x" + " ".repeat(50000)).imports, ["x"]);
}));
tasks.push(test("Discord CSS: root rules beat component rules, and light mode needs a real light block", () => {
  // Uma regra de componente com o modo no seletor não ganha da definição em :root.
  let r = TB.importDiscordCss(":root{--text-normal:#dddddd;--background-primary:#202020} .theme-dark .mention-pill{--text-normal:#ff0000} .theme-light .popout{--background-primary:#ffffff}");
  assert.deepStrictEqual([mapOf(r.modes.dark).text, mapOf(r.modes.dark).bg], ["#dddddd", "#202020"]);
  assert.strictEqual(r.modes.light, null, "a popout's light color is not a light mode");
  // Uma variável qualquer num bloco claro de componente não faz o claro copiar as cores escuras de :root.
  r = TB.importDiscordCss(":root{--background-primary:#111111;--text-normal:#eeeeee} .theme-light .tooltip{--tooltip-pad:4px}");
  assert.strictEqual(r.modes.light, null);
  r = TB.importDiscordCss(":root{--background-primary:#111111} .theme-light{--tooltip-pad:4px}");
  assert.strictEqual(r.modes.light, null, "a light root block without color variables");
  // Entre regras de raiz, a do modo ganha da geral, e um var() que passa pelo bloco claro conta como claro.
  r = TB.importDiscordCss(":root{--background-primary:var(--base);--base:#111111;--text-normal:#eeeeee} .theme-light{--base:#fafafa}");
  assert.deepStrictEqual([mapOf(r.modes.dark).bg, mapOf(r.modes.light).bg], ["#111111", "#fafafa"]);
  assert.strictEqual(mapOf(r.modes.light).text, "#eeeeee", "general values still fill the rest of light mode");
  r = TB.importDiscordCss(":root{--background-primary:#111111} .theme-dark{--background-primary:#222222} :root{--background-primary:#333333 !important}");
  assert.strictEqual(mapOf(r.modes.dark).bg, "#222222");
  // `.theme-dark:not(.custom-user-profile-theme)` ainda é raiz (como no Midnight), e um componente depois não ganha dela.
  r = TB.importDiscordCss("@container root style(--colors: on) { body, .theme-dark:not(.custom-user-profile-theme), .theme-light:not(.custom-user-profile-theme) { --status-danger: #ff5555; --background-primary: #101010 } } .numberBadge_x { --status-danger: #00aaff }");
  assert.deepStrictEqual([mapOf(r.modes.dark).dnd, mapOf(r.modes.dark).danger], ["#ff5555", "#ff5555"]);
  r = TB.importDiscordCss(".theme-dark:not(.theme-light) { --background-primary: #101010 } .theme-light { --background-primary: #fafafa }");
  assert.deepStrictEqual([mapOf(r.modes.dark).bg, mapOf(r.modes.light).bg], ["#101010", "#fafafa"]);
}));
tasks.push(test("Discord CSS: translucent surfaces, newer names, oklch and the muted/faint order", () => {
  const css = `.visual-refresh.theme-dark {
    --background-base-low: #101010;
    --channeltextarea-background: rgba(255, 255, 255, 0.2);
    --background-surface-highest: hsla(0, 0%, 100%, 0.5);
    --background-mod-subtle: rgb(255 255 255 / 0.06);
    --background-mod-strong: rgba(255, 255, 255, 0.18);
    --border-subtle: #ffffff14;
    --text-default: #eeeeee;
    --channels-default: #999999;
    --text-muted: #bbbbbb;
    --brand-500: oklch(70% 0.1 215);
    --status-positive: color-mix(in srgb, #00ff00 80%, black);
  }
  .visual-refresh.theme-light { --background-base-low: rgba(255, 255, 255, 0.5); --text-default: #111111; --channeltextarea-background: rgba(0, 0, 0, 0.1) }`;
  const r = TB.importDiscordCss(css), d = mapOf(r.modes.dark), l = mapOf(r.modes.light);
  const byTok = (res) => Object.fromEntries(res.mapped.map((m) => [m.tok, m]));
  const D = byTok(r.modes.dark), Lm = byTok(r.modes.light);
  // Sobre o fundo: o app desenha a cor como ela é, e o campo de texto não pode deixar ver o que está atrás.
  assert.deepStrictEqual([d.elevated, d.overlay], ["#404040", "#888888"]);
  assert.deepStrictEqual([D.elevated.alpha, D.elevated.over, D.overlay.over], [0.2, "bg", "bg"]);
  assert.ok(!("alpha" in D.bg) && !("alpha" in D.text), "opaque colors carry no note");
  // hover, selected e border continuam translúcidos.
  assert.deepStrictEqual([d.hover, d.selected, d.border], ["#ffffff0f", "#ffffff2e", "#ffffff14"]);
  assert.deepStrictEqual([fromOf(r.modes.dark).hover, fromOf(r.modes.dark).selected], ["--background-mod-subtle", "--background-mod-strong"]);
  // faint é o mais apagado: aqui --text-muted era mais claro que --channels-default, então trocam.
  assert.deepStrictEqual([d.muted, d.faint], ["#bbbbbb", "#999999"]);
  assert.deepStrictEqual([D.muted.from, D.faint.from, D.faint.swapped], ["--text-muted", "--channels-default", true]);
  assert.strictEqual(d.accent, "#46aec5");
  assert.strictEqual(d.online, "#00cc00");
  assert.strictEqual(d["accent-text"], "#000000");
  // No claro, o fundo translúcido vai sobre branco, e o resto sobre esse fundo.
  assert.deepStrictEqual([l.bg, l.elevated, Lm.bg.over, Lm.elevated.over], ["#ffffff", "#e6e6e6", "light", "bg"]);
  // E o tema resultante carrega no app.
  checkLoads(TB.toKdl(TB.applyCssImport(TB.fromSource(sources.classico, { base: "classico", name: "mix" }), r)), "translucent import");
}));

// 13. A galeria da comunidade: tools/gen_site.py confere themes/community/ e recusa o que
// não carrega ou não tem os metadados. Cada caso numa pasta própria, rodando o gerador de verdade.
function communityCheck(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "lc-community-"));
  try {
    for (const [name, text] of Object.entries(files)) fs.writeFileSync(path.join(dir, name), text);
    const r = spawnSync("python3", [path.join(ROOT, "tools/gen_site.py"), "--check-community", dir], { encoding: "utf8" });
    if (r.error) throw r.error;
    return { code: r.status, out: r.stdout + r.stderr };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}
function submission(edit) {
  const state = withColors(TB.fromSource(sources.orbital, { base: "orbital", name: "Neon Dusk" }), TB.generate(TB.randomSeed(4242)));
  Object.assign(state.meta, { author: "Ana Test", descEn: "Purple dusk over a dark city.", desc: "Crepúsculo roxo sobre uma cidade escura.", license: "CC0-1.0" });
  if (edit) edit(state);
  return state;
}
tasks.push(test("community gallery accepts a theme exported by the builder", () => {
  const state = submission();
  assert.deepStrictEqual(TB.communityCheck(state, THEMES).filter((c) => !c.ok), []);
  const kdl = TB.toKdl(state);
  checkLoads(kdl, "neon dusk");
  const r = communityCheck({ "neon-dusk.kdl": kdl, "README.md": "# notes\n" });
  assert.strictEqual(r.code, 0, r.out);
  assert.ok(r.out.includes("ok: 1 community theme"), r.out);
  save("tb-community-neon-dusk", kdl);
  // O que o app aceita, o gerador aceita: espaço antes do parêntese, alpha() de uma cor translúcida.
  const spaced = kdl.replace(/^(\s+accent\s+)"#[0-9a-f]+"/m, '$1"mix (#3a8bc0, #000000, 0.2)"').replace(/^(\s+hover\s+)"[^"]+"/m, '$1"alpha( @accent , 0.5 )"');
  assert.notStrictEqual(spaced, kdl);
  checkLoads(spaced, "spaced colors");
  const r2 = communityCheck({ "neon-dusk.kdl": spaced });
  assert.strictEqual(r2.code, 0, r2.out);
  // Uma pasta que não existe é erro, não "0 temas".
  const r3 = spawnSync("python3", [path.join(ROOT, "tools/gen_site.py"), "--check-community", path.join(os.tmpdir(), "lc-no-such-folder-" + process.pid)], { encoding: "utf8" });
  assert.strictEqual(r3.status, 2, r3.stdout + r3.stderr);
  assert.ok(/no such folder/.test(r3.stderr), r3.stderr);
}));
tasks.push(test("community gallery refuses broken themes and missing metadata", () => {
  const good = TB.toKdl(submission());
  const meta = (fn) => TB.toKdl(submission(fn));
  const copy = TB.fromSource(sources.orbital, { base: "orbital", name: "Orbital Copy" });
  Object.assign(copy.meta, { author: "Ana", desc: "", descEn: "Just a copy.", license: "MIT" });
  const cases = [
    ["syntax error", { "neon-dusk.kdl": good.replace(/\n}\s*$/, "\n") }, /neon-dusk\.kdl:\d+:\d+: missing '\}'/],
    ["unterminated string", { "neon-dusk.kdl": good + 'label "never closed\n' }, /neon-dusk\.kdl:\d+:\d+: unterminated string/],
    ["no license", { "neon-dusk.kdl": meta((s) => { s.meta.license = ""; }) }, /missing license=/],
    ["license that isn't SPDX", { "neon-dusk.kdl": meta((s) => { s.meta.license = "do what you want"; }) }, /license="do what you want": use one license identifier/],
    ["license not on the list", { "neon-dusk.kdl": meta((s) => { s.meta.license = "NOT-A-LICENSE"; }) }, /NOT-A-LICENSE isn't one of the open licenses the gallery takes/],
    ["closed license", { "neon-dusk.kdl": meta((s) => { s.meta.license = "All-Rights-Reserved"; }) }, /All-Rights-Reserved isn't one of the open licenses/],
    ["license in the wrong case", { "neon-dusk.kdl": meta((s) => { s.meta.license = "cc0-1.0"; }) }, /write cc0-1\.0 as CC0-1\.0/],
    ["byte order mark", { "neon-dusk.kdl": "\ufeff" + good }, /neon-dusk\.kdl:1:1: the file starts with a byte order mark/],
    ["no author", { "neon-dusk.kdl": meta((s) => { s.meta.author = ""; }) }, /missing author=/],
    ["no description", { "neon-dusk.kdl": meta((s) => { s.meta.desc = s.meta.descEn = ""; }) }, /missing a description/],
    ["description of a built-in", { "neon-dusk.kdl": meta((s) => { s.meta.descEn = ""; s.meta.desc = TB.fromSource(sources.zen).meta.desc; }) }, /still the one from the built-in theme zen/],
    ["no theme node", { "neon-dusk.kdl": good.replace(/^theme .*$/m, "") }, /missing the `theme` node/],
    ["file named differently", { "dusk.kdl": good }, /must be named neon-dusk\.kdl/],
    ["built-in name", { "orbital.kdl": meta((s) => { s.meta.name = "Orbital"; }) }, /orbital is a built-in theme/],
    ["built-in with another name", { "orbital-copy.kdl": TB.toKdl(copy) }, /built-in theme orbital with another name/],
    // Comentários, espaços e a ordem das propriedades não fazem um tema novo.
    ["built-in with another name and a comment", { "orbital-copy.kdl": TB.toKdl(copy).replace(/^layout \{$/m, "layout {\n    // mine\n    /* all mine */").replace(/\n(\s+)(\S)/, "\n$1  $2") }, /built-in theme orbital with another name/],
    ["same theme twice", { "neon-dusk.kdl": good, "neon-dusk-2.kdl": good.replace('theme "Neon Dusk"', 'theme "Neon Dusk 2"') }, /neon-dusk(-2)?\.kdl: same colors and layout as neon-dusk(-2)?\.kdl/],
    ["unknown color token", { "neon-dusk.kdl": good.replace(/^colors mode=dark \{$/m, "colors mode=dark {\n    glitter \"#fff\"") }, /unknown color token: glitter/],
    ["invalid color", { "neon-dusk.kdl": good.replace(/^(\s+accent\s+)"#[0-9a-f]+"/m, '$1"mix(#fff, nope, 0.5)"') }, /invalid color expression/],
    ["unknown component", { "neon-dusk.kdl": good.replace(/(\n\s*)messages\b/, "$1marquee flex=1$1messages") }, /unknown component: marquee/],
    ["no layout", { "neon-dusk.kdl": good.slice(0, good.indexOf("\nlayout")) }, /needs a `layout` node/],
    ["an image in the folder", { "neon-dusk.kdl": good, "logo.png": "\x89PNG" }, /logo\.png: only \.kdl theme files/],
    ["not UTF-8", { "neon-dusk.kdl": Buffer.from([0x74, 0x68, 0xff, 0xfe]) }, /not UTF-8/],
    ["too big", { "neon-dusk.kdl": good + "// " + "x".repeat(70000) + "\n" }, /the limit is 65536/],
  ];
  for (const [label, files, want] of cases) {
    const r = communityCheck(files);
    assert.strictEqual(r.code, 1, label + ": expected a failure\n" + r.out);
    assert.ok(want.test(r.out), label + ": " + r.out);
  }
  // O leitor do criador concorda com os erros de sintaxe e de cor do gerador.
  const file = (label) => cases.find((c) => c[0] === label)[1]["neon-dusk.kdl"];
  assert.throws(() => TB.parseKdl(file("syntax error")), (e) => e.code === "close");
  assert.throws(() => TB.loadTheme(file("unknown color token")), (e) => e.code === "token");
  assert.throws(() => TB.loadTheme(file("invalid color")), (e) => e.code === "color-expr");
}));
// Os temas que já estão na pasta: o gerador aceita, e cada um carrega como no app, com qualquer opção.
const COMMUNITY = path.join(ROOT, "themes/community");
const communityFiles = fs.existsSync(COMMUNITY) ? fs.readdirSync(COMMUNITY).filter((f) => f.endsWith(".kdl")).sort() : [];
tasks.push(test("themes/community passes the site build check (" + communityFiles.length + " themes)", () => {
  const r = spawnSync("python3", [path.join(ROOT, "tools/gen_site.py"), "--check-community"], { encoding: "utf8" });
  assert.strictEqual(r.status, 0, r.stdout + r.stderr);
  assert.ok(r.stdout.includes("ok: " + communityFiles.length + " community theme"), r.stdout);
}));
for (const f of communityFiles) {
  tasks.push(test("community theme " + f + " loads like in the app", () => {
    const src = fs.readFileSync(path.join(COMMUNITY, f), "utf8");
    checkLoads(src, f);
    for (const ov of allOptionSets(src)) for (const mode of MODES) TB.loadTheme(src, { mode, overrides: ov });
    const state = TB.fromSource(src, { name: "" });
    assert.deepStrictEqual(TB.communityCheck(state, THEMES).filter((c) => !c.ok), [], f);
    assert.strictEqual(TB.slug(state.meta.name) + ".kdl", f);
  }));
}
// O bloco de dados de uma página: até o primeiro "</script>", sem nenhum "<" dentro. Com um "<"
// cru, um "<!--<script>" no texto de um tema faria o navegador passar desse "</script>" e engolir
// o resto da página (o rodapé e os scripts) como texto.
function blobOf(page, id) {
  const at = page.indexOf('id="' + id + '">') + id.length + 6;
  assert.ok(at > id.length + 6, id + " missing");
  const end = page.indexOf("</script>", at), raw = page.slice(at, end);
  assert.ok(!/[<>&]/.test(raw), id + " has a raw < > or &");
  return { data: JSON.parse(raw), after: page.slice(end) };
}
// Gera o criador e a galeria numa pasta à parte, com os temas de `files` no lugar de themes/community/.
function buildPages(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "lc-community-")), out = fs.mkdtempSync(path.join(os.tmpdir(), "lc-site-"));
  try {
    for (const [name, text] of Object.entries(files)) fs.writeFileSync(path.join(dir, name), text);
    const py = ["import sys", "from pathlib import Path", "sys.path.insert(0, sys.argv[1])", "import gen_site as g", "g.OUT = Path(sys.argv[2])",
      "community, problems = g.check_community(Path(sys.argv[3]))", "assert not problems, problems", "themes = g.load_themes()",
      "for lang in g.LANGS:", "    g.build_builder(lang, themes, community)", "    g.build_community(lang, community)", "g.write_community_files(community)"].join("\n");
    const r = spawnSync("python3", ["-I", "-B", "-c", py, path.join(ROOT, "tools"), out, dir], { encoding: "utf8" });
    assert.strictEqual(r.status, 0, r.stdout + r.stderr);
    const read = (p) => fs.readFileSync(path.join(out, p), "utf8");
    return { read, exists: (p) => fs.existsSync(path.join(out, p)) };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
    setTimeout(() => fs.rmSync(out, { recursive: true, force: true }), 0);
  }
}
tasks.push(test("a community theme with <!--<script> in its text doesn't break the pages", () => {
  const nasty = "Notes: <!--<script> is just text </script><!-- & > here";
  const kdl = TB.toKdl(submission((s) => { s.meta.descEn = nasty; s.meta.author = "Ana <!--<script>"; })) + "// <!--<script> in a comment </script>\n";
  checkLoads(kdl, "nasty");
  const site = buildPages({ "neon-dusk.kdl": kdl });
  for (const [file, id, script] of [["community-themes.html", "cg-data", "community.js"], ["pt/community-themes.html", "cg-data", "community.js"],
    ["theme-builder.html", "tb-data", "theme-builder.js"], ["pt/theme-builder.html", "tb-data", "theme-builder.js"]]) {
    const page = site.read(file), b = blobOf(page, id);
    // O resto da página continua sendo página: o fim do <main>, o rodapé e os scripts.
    assert.ok(b.after.includes("</main>") && /<footer/.test(b.after) && b.after.includes("assets/site/" + script), file + " lost its end");
    // Nenhum "<!--" dentro de um <script> (o estado em que o navegador para de achar o "</script>").
    for (const m of page.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)) assert.ok(!m[1].includes("<!--"), file + " script has <!--");
    if (id === "cg-data") {
      assert.strictEqual(b.data.themes["neon-dusk"].src, kdl, "the source survives the escaping");
      const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
      if (file.startsWith("pt/")) assert.ok(page.includes(esc("Crepúsculo roxo")), file + " card");
      else assert.ok(page.includes(esc(nasty)), file + " card text is escaped");
      assert.ok(page.includes(esc("Ana <!--<script>")), file + " author is escaped");
    } else {
      assert.deepStrictEqual(b.data.community, ["neon-dusk"], "the builder only lists the names");
      assert.ok(!JSON.stringify(b.data).includes("Notes:"), "no community source in the builder page");
      assert.strictEqual(b.data.communityBase, file.startsWith("pt/") ? "../community/" : "community/");
    }
  }
  assert.strictEqual(site.read("community/neon-dusk.kdl"), kdl);
  // O criador lê o arquivo que buscou do mesmo jeito.
  assert.strictEqual(TB.communityFromSource(kdl).meta.descEn, nasty);
}));
// A página gerada: o convite quando a pasta está vazia, a grade quando não, e a mesma CSP do criador.
tasks.push(test("community gallery page matches the folder", () => {
  for (const [file, lang] of [["docs/community-themes.html", "en"], ["docs/pt/community-themes.html", "pt"]]) {
    const page = fs.readFileSync(path.join(ROOT, file), "utf8");
    assert.ok(page.includes("Content-Security-Policy\" content=\"default-src 'self'; script-src 'self';"), file + " CSP");
    assert.ok(!/<script[^>]+src="https?:/.test(page), file + " external script");
    const empty = page.includes('class="cg-empty"'), grid = page.includes('class="cg-grid"');
    assert.strictEqual(empty, communityFiles.length === 0, file + " empty state");
    assert.strictEqual(grid, communityFiles.length > 0, file + " grid");
    assert.strictEqual((page.match(/data-cg-card="/g) || []).length, communityFiles.length);
    if (!communityFiles.length) assert.ok(page.includes(lang === "en" ? "Be the first" : "Seja a primeira"), file);
    assert.deepStrictEqual(blobOf(page, "cg-data").data.order, communityFiles.map((f) => f.slice(0, -4)));
  }
  for (const file of ["docs/theme-builder.html", "docs/pt/theme-builder.html"]) {
    const builder = blobOf(fs.readFileSync(path.join(ROOT, file), "utf8"), "tb-data").data;
    assert.deepStrictEqual(builder.community, communityFiles.map((f) => f.slice(0, -4)));
    for (const t of THEMES) assert.ok(!builder.community.includes(t), "built-in " + t + " is not in the community list");
    for (const n of builder.community) assert.ok(fs.existsSync(path.join(ROOT, "docs/community", n + ".kdl")), n + ".kdl is published");
  }
  assert.ok(fs.readFileSync(path.join(ROOT, "docs/index.html"), "utf8").includes('href="community-themes.html"'), "nav link");
}));


// 14. O editor novo: gerador de paletas por harmonia, cores travadas, inversão do modo,
// camadas (esconder e mover) e o mapa do clique-para-editar.
function hueGap(a, b) { const d = Math.abs(a - b) % 360; return d > 180 ? 360 - d : d; }
tasks.push(test("harmony generator: every scheme and base gives a theme the app loads, with readable text", () => {
  const bases = ["#e8590c", "#7aa2f7", "#22c55e", "#d946ef", "#9ca3af", "#000000", "#ffffff"];
  let n = 0;
  for (const scheme of Object.keys(TB.HARMONY)) {
    for (const base of bases) {
      for (const layout of ["orbital", "classico", "papel"]) {
        const seed = TB.seedFromBase(base, scheme, {});
        assert.strictEqual(seed.scheme, scheme);
        const s0 = TB.fromSource(sources[layout], { base: layout, name: "h" });
        const s = TB.applyGenerated(s0, TB.generate(seed), {});
        const kdl = TB.toKdl(s);
        checkLoads(kdl, scheme + " " + base + " " + layout);
        for (const m of MODES) {
          const app = TB.contrastReport(s, m).filter((r) => r.app && r.fails.length && !r.gated);
          assert.deepStrictEqual(app.map((r) => r.id), [], scheme + " " + base + " " + m);
          for (const t of TB.TOKENS) assert.ok(/^#[0-9a-f]{6}([0-9a-f]{2})?$/.test(s.colors[m][t]), t);
        }
        n++;
      }
    }
    // A menção e o link ficam nos ângulos da harmonia (medidos no escuro, em OKLCH).
    const seed = TB.seedFromBase("#e8590c", scheme, { chroma: 0.16 }), g = TB.generate(seed), off = TB.HARMONY[scheme];
    const h = (hex) => TB.toOklch(TB.hexRgba(hex))[2];
    assert.ok(hueGap(h(g.colors.dark.mention), seed.accentHue + off[0]) < 14, scheme + " mention hue");
    assert.ok(hueGap(h(g.colors.dark.link), seed.accentHue + off[1]) < 14, scheme + " link hue");
  }
  assert.ok(n === Object.keys(TB.HARMONY).length * 21);
  // Valores fora da faixa ou que não são número caem no padrão.
  const odd = TB.seedFromBase("#336699", "nope", { neutral: 9, chroma: -1, lightness: "x" });
  assert.strictEqual(odd.scheme, "analogous");
  assert.ok(odd.neutral <= 0.06 && odd.accentChroma >= 0 && odd.accentL >= 0.55 && odd.accentL <= 0.9);
}));
tasks.push(test("locked colors survive a new palette, and text on a locked fill stays readable", () => {
  const s0 = TB.fromSource(sources.orbital, { base: "orbital", name: "l" });
  s0.colors.dark.accent = "#ffd400";
  s0.colors.light.accent = "#1a1a8c";
  for (let i = 1; i <= 40; i++) {
    const g = TB.generate(TB.randomSeed(i * 7919));
    const locks = { accent: true, bg: i % 2 === 0, muted: i % 3 === 0 };
    const s = TB.applyGenerated(s0, g, locks);
    for (const m of MODES) {
      assert.strictEqual(s.colors[m].accent, s0.colors[m].accent, "accent locked");
      if (locks.bg) assert.strictEqual(s.colors[m].bg, s0.colors[m].bg, "bg locked");
      if (locks.muted) assert.strictEqual(s.colors[m].muted, s0.colors[m].muted, "muted locked");
      else assert.notStrictEqual(s.colors[m].muted, undefined);
      assert.strictEqual(s.colors[m]["accent-text"], TB.onColor(s.colors[m].accent));
      assert.strictEqual(s.colors[m]["bubble-self"], s.colors[m].accent);
      const a = TB.hexRgba(s.colors[m].accent), t = TB.hexRgba(s.colors[m]["accent-text"]);
      assert.ok(TB.contrast(t, a) >= Math.max(TB.contrast([0, 0, 0, 1], a), TB.contrast([1, 1, 1, 1], a)) - 1e-9);
    }
    checkLoads(TB.toKdl(s), "locks " + i);
  }
}));
tasks.push(test("dark to light (and back) with lightness inversion loads and reads", () => {
  for (const t of THEMES) {
    const s = TB.fromSource(sources[t], { base: t, name: t });
    for (const from of MODES) {
      const to = from === "dark" ? "light" : "dark", n = TB.invertMode(s, from);
      checkLoads(TB.toKdl(n), t + " " + from + "→" + to);
      assert.deepStrictEqual(n.colors[from], s.colors[from], "the source mode doesn't change");
      const bad = TB.contrastReport(n, to).filter((r) => r.fails.length && !r.gated && !r.stuck);
      assert.deepStrictEqual(bad.map((r) => r.id), [], t + " " + to + " contrast");
      const bgL = TB.toOklch(TB.hexRgba(n.colors[to].bg))[0], textL = TB.toOklch(TB.hexRgba(n.colors[to].text))[0];
      assert.ok(to === "light" ? bgL > textL : bgL < textL, t + " " + to + " lightness flipped");
      // A transparência de cada cor vem junto (o vidro continua vidro).
      for (const k of ["bg", "surface", "sidebar", "elevated", "overlay", "accent", "border", "hover", "selected"]) assert.ok(Math.abs(TB.hexRgba(n.colors[to][k])[3] - TB.hexRgba(s.colors[from][k])[3]) < 0.01, t + " " + k + " alpha");
    }
  }
  // A curva vai e volta (as duas metades são a mesma linha).
  for (let L = 0; L <= 1.0001; L += 0.05) assert.ok(Math.abs(TB.flipL(TB.flipL(L, true), false) - L) < 1e-9, "flip " + L);
}));
tasks.push(test("layers: outline, hide and reorder edit only the layout tree", () => {
  for (const t of THEMES) {
    const s = TB.fromSource(sources[t], { base: t, name: t }), out = TB.outline(s.structure);
    assert.ok(out.length >= 5, t + " layers");
    for (const o of out) {
      assert.ok(o.index >= 0 && o.index < o.count, t + " " + o.name + " index");
      for (const f of o.fields) if (f.kind === "num") assert.ok(f.range && f.range[0] < f.range[1] && f.range[2] > 0, t + " " + o.name + "." + f.key + " range");
    }
    // Mover para baixo e de volta devolve o mesmo texto; o arquivo movido carrega.
    const movable = out.filter((o) => o.count > 1 && o.index < o.count - 1);
    for (const o of movable.slice(0, 4)) {
      const moved = TB.moveNode(s.structure, o.start, 1);
      assert.notStrictEqual(moved, s.structure, t + " " + o.name + " moved");
      checkLoads(TB.toKdl(Object.assign({}, s, { structure: moved })), t + " moved " + o.name);
      const again = TB.outline(moved).find((x) => x.name === o.name && x.parent === o.parent && x.index === o.index + 1 && x.depth === o.depth);
      assert.ok(again, t + " " + o.name + " is one step down");
      assert.strictEqual(TB.moveNode(moved, again.start, -1), s.structure, t + " " + o.name + " back");
    }
    // O primeiro não sobe e o último não desce.
    const first = out.find((o) => o.index === 0), last = out.find((o) => o.index === o.count - 1);
    assert.strictEqual(TB.moveNode(s.structure, first.start, -1), s.structure);
    assert.strictEqual(TB.moveNode(s.structure, last.start, 1), s.structure);
    // Esconder: show=#false no nó, o app deixa de desenhar e a prévia também.
    const comp = out.find((o) => o.component);
    const hidden = TB.setProp(s.structure, comp.start, "show", false);
    assert.strictEqual(TB.outline(hidden).find((o) => o.start === comp.start).show, false);
    const th = TB.loadTheme(TB.toKdl(Object.assign({}, s, { structure: hidden })), { mode: "dark" });
    const P = PREVIEW(TB, "en");
    const nd = TB.findNode(th.nodes, comp.start + TB.toKdl(Object.assign({}, s, { structure: hidden })).lastIndexOf(hidden.replace(/\s+$/, "")));
    assert.ok(nd && !P.visible(th, nd), t + " hidden layer is not drawn");
    assert.strictEqual(TB.setProp(hidden, comp.start, "show", null), s.structure, t + " show again");
  }
}));
tasks.push(test("every option the builder offers is one the app reads", () => {
  // Cada propriedade de componente aparece como "nome" no código do app (src/ui, src/theme).
  const zig = [];
  for (const dir of ["src/ui", "src/theme"]) for (const f of fs.readdirSync(path.join(ROOT, dir))) if (f.endsWith(".zig")) zig.push(fs.readFileSync(path.join(ROOT, dir, f), "utf8"));
  const all = zig.join("\n");
  for (const [comp, spec] of Object.entries(TB.COMPONENTS)) {
    assert.ok(all.includes('"' + comp + '"'), "component " + comp);
    for (const [key] of spec) assert.ok(all.includes('"' + key + '"'), comp + "." + key + " is read by the app");
  }
  for (const key of ["show", "width", "height", "gap", "padding", "default"]) assert.ok(all.includes('"' + key + '"'), key);
  for (const top of ["radius", "transparent", "ui", "mono", "size"]) assert.ok(all.includes('"' + top + '"'), top);
  for (const k of Object.keys(TB.RANGES)) assert.ok(TB.RANGES[k][0] < TB.RANGES[k][1], k);
}));
tasks.push(test("click-to-edit map: only real tokens, only the preview's own classes", () => {
  const P = PREVIEW(TB, "en");
  const cssText = fs.readFileSync(path.join(ROOT, "docs/assets/site/theme-builder.css"), "utf8");
  const previewJs = fs.readFileSync(path.join(ROOT, "docs/assets/site/theme-builder-preview.js"), "utf8");
  assert.ok(P.INSPECT.length > 40);
  for (const [sel, toks] of P.INSPECT) {
    assert.ok(toks.length >= 1);
    for (const t of toks) assert.ok(t === "r" || TB.TOKENS.includes(t), sel + " " + t);
    for (const cls of sel.match(/\.[a-z][\w-]*/g)) assert.ok(cssText.includes(cls) || previewJs.includes(cls.slice(1)), sel + " uses " + cls);
  }
  // Os tokens citados numa expressão de cor: só nomes da lista, nunca o texto do arquivo.
  assert.deepStrictEqual(P.refTokens("alpha(@surface, 0.9)", false), ["surface"]);
  assert.deepStrictEqual(P.refTokens("sidebar", true), ["sidebar"]);
  assert.deepStrictEqual(P.refTokens('@x" onclick="y @constructor @__proto__ #fff', false), []);
  assert.deepStrictEqual(P.refTokens("mix(@accent, @bg, .2) @accent", false), ["accent", "bg"]);
  const th = TB.loadTheme(sources.orbital, { mode: "dark" });
  const box = P.boxTokens(th, TB.parseKdl('column bg="#ff0000"')[0]);
  assert.deepStrictEqual(box, { toks: [], literal: true });
  assert.deepStrictEqual(P.boxTokens(th, TB.parseKdl("column bg=rail")[0]).toks, ["rail"]);
}));
// O tamanho da prévia: a janela imitada nunca fica menor que 1200×720 nem sai de 1,25:1 a 2:1,
// e a prévia cabe no espaço dado (nada de barra de rolagem no "ajustar").
tasks.push(test("preview size: fits the space, never below 1200×720, between 1.25:1 and 2:1", () => {
  const P = PREVIEW(TB, "en");
  for (let aw = 120; aw <= 3200; aw += 37) {
    for (let ah = 90; ah <= 2000; ah += 41) {
      const g = P.frameFit(aw, ah), tag = aw + "×" + ah + " → " + JSON.stringify(g);
      assert.ok(g.k > 0 && g.k <= 2, tag);
      assert.ok(g.w >= P.MIN_W && g.h >= P.MIN_H && g.w <= P.MAX_W && g.h <= P.MAX_H, tag);
      assert.ok(Math.floor(g.w * g.k) <= aw && Math.floor(g.h * g.k) <= ah, tag + " overflows");
      assert.ok(g.w / g.h >= 1.25 - 0.01 && g.w / g.h <= 2 + 0.01, tag + " aspect");
      // Até a janela passar de 1920×1200, a escala não passa de 100%.
      if (aw / P.MAX_W < 1 || ah / P.MAX_H < 1) assert.ok(g.k <= 1, tag + " upscaled");
    }
  }
  // O espaço do palco num notebook de 1366×768 com o painel aberto: a prévia passa de 80%
  // (antes, com 1280×800 fixo e as barras do site, ficava em 63%).
  assert.ok(P.frameFit(989, 603).k >= 0.8, JSON.stringify(P.frameFit(989, 603)));
  // Com o painel escondido, o espaço a mais vira janela mais larga, não barras vazias.
  const open = P.frameFit(989, 603), closed = P.frameFit(1273, 603);
  assert.ok(closed.w > open.w && closed.k >= open.k, JSON.stringify([open, closed]));
}));
tasks.push(test("preview follows the simulated window: hide-below uses its size", () => {
  const P = PREVIEW(TB, "en");
  // bolhas: member-list hide-below=1150; editorial: a manchete só com 900 ou mais de altura.
  const has = (src, size, node) => {
    const doc = fakeDocument(), frame = doc.createElement("div");
    P.mount(frame, TB.loadTheme(src, { mode: "dark" }), size);
    return doc.made.some((e) => e.className === "pv-b" && e.dataset.node === node);
  };
  assert.ok(!has(sources.bolhas, { w: 1100, h: 800 }, "member-list"), "hidden below 1150");
  assert.ok(has(sources.bolhas, { w: 1200, h: 800 }, "member-list"), "shown at 1200");
  assert.ok(has(sources.bolhas, undefined, "member-list"), "default 1280×800");
  // Sem tamanho, a prévia continua 1280×800 (as miniaturas e a galeria dependem disso).
  const th = TB.loadTheme(sources.editorial, { mode: "dark" });
  const lines = (size) => {
    const doc = fakeDocument(), frame = doc.createElement("div");
    P.mount(frame, th, size);
    assert.strictEqual(frame.kids.length, 1, "editorial draws at " + JSON.stringify(size));
    return doc.made.filter((e) => e.className === "pv-b").map((e) => e.dataset.line).join(",");
  };
  // A manchete do editorial troca de forma em 900 px de altura, como no app.
  assert.notStrictEqual(lines({ w: 1200, h: 720 }), lines({ w: 1600, h: 1000 }), "editorial headline follows the height");
  assert.strictEqual(lines(undefined), lines({ w: 1280, h: 800 }), "no size is 1280×800");
  // O minimo da prévia mostra a lista de membros de todos os temas embutidos.
  for (const t of THEMES) assert.ok(has(sources[t], { w: P.MIN_W, h: P.MIN_H }, "member-list") || !/member-list/.test(sources[t]), t + " member list at the minimum size");
}));
// Contraste em níveis: o que o app clareia sozinho não é erro; abaixo de 4,5 e acima de 3 é revisão.
tasks.push(test("contrast levels: what the app lifts is not an error", () => {
  for (const t of THEMES) {
    const s = TB.fromSource(sources[t], { base: t, name: t });
    for (const m of MODES) {
      for (const r of TB.contrastReport(s, m)) {
        assert.ok(["ok", "auto", "low", "bad"].includes(r.level), t + " " + m + " " + r.id);
        if (!r.fails.length) assert.strictEqual(r.level, "ok", t + " " + m + " " + r.id);
        else if (r.app) assert.strictEqual(r.level, r.stuck ? "bad" : "auto", t + " " + m + " " + r.id);
        else assert.strictEqual(r.level, r.ratio >= 3 ? "low" : "bad", t + " " + m + " " + r.id + " " + r.ratio);
      }
    }
  }
  const lv = (t, m, id) => TB.contrastReport(TB.fromSource(sources[t], { base: t, name: t }), m).find((r) => r.id === id).level;
  assert.strictEqual(lv("orbital", "dark", "faint"), "auto");
  assert.strictEqual(lv("cupertino", "dark", "accent-text"), "low");
  assert.strictEqual(lv("escritorio", "light", "text"), "bad");
  // orbital no modo escuro (o começo padrão do criador): nada vermelho nem âmbar.
  assert.ok(!TB.contrastReport(TB.fromSource(sources.orbital, { base: "orbital", name: "o" }), "dark").some((r) => r.level === "bad" || r.level === "low"));
}));
tasks.push(test("hiding a layer reports when messages, composer or channels go with it", () => {
  for (const t of THEMES) {
    const out = TB.outline(TB.fromSource(sources[t], { base: t, name: t }).structure);
    const msgs = out.find((o) => o.name === "messages");
    assert.ok(msgs, t + " has messages");
    assert.deepStrictEqual(TB.essentialInside(out, msgs.start), ["messages"], t);
    // Cada ancestral das mensagens leva elas junto.
    const by = Object.fromEntries(out.map((o) => [o.start, o]));
    for (let p = msgs.parent; p !== null; p = by[p].parent) assert.ok(TB.essentialInside(out, p).includes("messages"), t + " ancestor " + by[p].name);
    const members = out.find((o) => o.name === "member-list");
    if (members) assert.deepStrictEqual(TB.essentialInside(out, members.start), [], t + " member list");
  }
  // Um ramo que já está escondido não conta de novo.
  const s = TB.fromSource(sources.bolhas, { base: "bolhas", name: "b" });
  const out = TB.outline(s.structure), comp = out.find((o) => o.name === "composer");
  const hid = TB.outline(TB.setProp(s.structure, comp.start, "show", false));
  const root = hid.find((o) => o.parent === null && o.container);
  assert.ok(!TB.essentialInside(hid, root.start).includes("composer"));
  assert.ok(TB.essentialInside(hid, root.start).includes("messages"));
  // Nomes do arquivo nunca saem daqui: só os três da lista.
  assert.deepStrictEqual(TB.essentialInside([{ start: 1, parent: null, name: "__proto__", show: null }], 1), []);
}));
// O criador na página: a folha de exportar e o fundo escuro dela na mesma camada (no <body>, o
// fundo ficava por cima e engolia os cliques), rótulos que somem só da vista, e o zoom à mão.
tasks.push(test("builder page: export overlay in the sheet's layer, labels stay names, zoom at every width", () => {
  const js = fs.readFileSync(path.join(ROOT, "docs/assets/site/theme-builder.js"), "utf8");
  const cssText = fs.readFileSync(path.join(ROOT, "docs/assets/site/theme-builder.css"), "utf8");
  assert.ok(js.includes("sheet.parentNode.insertBefore(scrim, sheet)") && !/body\.appendChild\(scrim\)/.test(js), "overlay next to the sheet");
  const z = (sel) => +new RegExp(sel.replace(/[.]/g, "\\.") + "\\{[^}]*z-index:(\\d+)").exec(cssText)[1];
  assert.ok(z(".tbx-scrim") < z(".tbx-sheet"), "overlay under the sheet");
  // Os rótulos da barra e das abas nunca levam display:none (sairiam do nome do botão).
  for (const m of cssText.matchAll(/([^{}]+)\{([^}]*)\}/g)) if (/\.tbx-(bl|tl)\b/.test(m[1])) assert.ok(!/display:none/.test(m[2]), m[1] + " hides a label with display:none");
  for (const file of ["docs/theme-builder.html", "docs/pt/theme-builder.html"]) {
    const page = fs.readFileSync(path.join(ROOT, file), "utf8");
    const bar = page.slice(page.indexOf('<header class="tbx-top"'), page.indexOf("</header>", page.indexOf('<header class="tbx-top"')));
    for (const b of bar.match(/<button[\s\S]*?<\/button>/g)) {
      const named = /aria-label="[^"]+"/.test(b) || /class="(sr-only|tbx-bl)">[^<]+</.test(b) || /<span data-fname>/.test(b) || /<b>[^<]+<\/b>/.test(b);
      assert.ok(named, file + " toolbar button without a name: " + b.slice(0, 90));
    }
    for (const b of page.match(/<button type="button" role="tab" id="tbx-t-[\s\S]*?<\/button>/g)) assert.ok(/class="tbx-tl">[^<]+</.test(b), file + " tab label");
    for (const k of ["data-zoom-in", "data-zoom-out", "data-zoom-toggle"]) assert.ok(page.includes(k), file + " " + k);
    // O zoom fica na barra de baixo do palco, que não esconde nada em tela estreita.
    assert.ok(page.indexOf("data-zoom-in") > page.indexOf('class="tbx-status"'), file + " zoom in the stage bar");
    assert.ok(page.includes("data-next-theme") && page.includes("data-toggle-mode"), file + " page theme still reachable");
  }
  assert.ok(!/\.tbx-zoom[^{]*\{[^}]*display:none/.test(cssText), "zoom never hidden");
}));
// A prévia é o desenho do app: os ícones do editor (.tbx svg) não podem encolher os SVGs dela
// (fundos procedurais, formas, ícones) para 18 px, como aconteceu. E o resto do que esta rodada
// conferiu na página: texto pequeno legível, controles deslizantes largos, o editor de cor num
// celular sem cobrir a prévia, o aviso fora do editor e o foco que volta para um botão que existe.
tasks.push(test("builder page: editor icons stay out of the preview, readable small text, phone color editor", () => {
  const js = fs.readFileSync(path.join(ROOT, "docs/assets/site/theme-builder.js"), "utf8");
  const cssText = fs.readFileSync(path.join(ROOT, "docs/assets/site/theme-builder.css"), "utf8");
  const rules = [...cssText.replace(/\/\*[\s\S]*?\*\//g, "").matchAll(/([^{}@]+)\{([^{}]*)\}/g)].map((m) => ({ sel: m[1].trim(), body: m[2] }));
  const ruleOf = (sel) => rules.find((r) => r.sel.split(",").map((x) => x.trim()).includes(sel));
  let generic = 0;
  for (const r of rules) for (const sel of r.sel.split(",").map((x) => x.trim())) {
    // Um "svg" solto logo depois de .tbx (sem classe própria) alcança qualquer SVG da página, a prévia também.
    if (/^\.tbx\s+svg(?![.\[#\w-])/.test(sel)) { generic++; assert.ok(sel.includes(":where(:not(.tb-frame svg))"), "reaches the preview: " + sel); }
  }
  assert.ok(generic >= 1, "the editor icon rule is still there");
  assert.ok(/width:100%;height:100%/.test(ruleOf(".pv-bgsvg").body), "backdrops fill the frame");
  assert.ok(/width:1\.15em;height:1\.15em/.test(ruleOf(".pv-ic").body), "preview icons follow the text");
  // Texto do editor em --faint ficava abaixo de 4,5:1 nos dois modos da página.
  for (const r of rules) if (/^\.tbx/.test(r.sel) && !/\.pv-/.test(r.sel)) assert.ok(!/(^|;)color:var\(--faint\)/.test(r.body), r.sel + " uses --faint for text");
  const fsOf = (sel) => +/font:[^;]*?([\d.]+)px/.exec(ruleOf(sel).body)[1];
  assert.ok(fsOf(".tbx-rail [role=tab]") >= 11, "tab labels at least 11px");
  assert.ok(+/font-size:([\d.]+)px/.exec(ruleOf(".tbx-zv small").body)[1] >= 11, "zoom suffix at least 11px");
  assert.ok(!/outline:none/.test(ruleOf(".tbx-pane:focus-visible").body), "tab panels show focus");
  // Controle deslizante com a linha toda, embaixo do rótulo e do valor.
  assert.ok(/grid-template-areas:"l v" "r r"/.test(ruleOf(".tbx-slider").body) && /grid-template-areas:"k n x" "r r r"/.test(ruleOf(".tbx-propnum").body), "sliders on their own row");
  assert.ok(js.includes('h("div", { "class": "tbx-propnum" }, [h("code", { text: f.key }), number, reset, slider])'), "layer numbers: name, field, reset, then the slider");
  // Celular: o palco encolhe para o espaço acima do editor (ou à esquerda, deitado) e mostra um modo só.
  assert.ok(/min-height:0/.test(ruleOf(".tbx-stage").body), "the stage can shrink");
  const phone = cssText.slice(cssText.indexOf("@media (max-width:899.98px){"));
  assert.ok(/\.tbx-body\[data-pop\]\{padding-bottom:var\(--pop-h/.test(phone) && /\.tbx-body\[data-pop\] \.tbx-side\{visibility:hidden/.test(phone), "room above the editor sheet");
  assert.ok(/orientation:landscape\)\{[^]*?\.tbx-body\[data-pop\]\{padding-bottom:0;padding-right:var\(--pop-w/.test(cssText), "room beside the editor when sideways");
  assert.ok(js.includes('return view === "split" && !popKind ? ["dark", "light"] : [mode];') && js.includes("var two = screenModes().length > 1;"), "one mode while the phone editor is open");
  assert.ok(js.includes('closest(".tbx-fbox,[data-pop-src],.tbx-status")'), "zooming doesn't close the editor");
  assert.ok(/function say\([^]*?placeToast\(\);/.test(js) && js.includes("function placeToast()"), "the toast keeps clear of the editor");
  assert.ok(js.includes('$(".tbx-top [data-export-open]")') && !/sheetOpener = document\.activeElement;/.test(js), "focus returns to a real button");
  assert.ok(!/TB\.decode\(decodeURIComponent/.test(js), "a bad % never throws in the page");
  // O topo do criador é o mesmo das outras páginas (só mais baixo): logo e margens iguais.
  assert.ok(!/html\[data-page=builder\] \.brand/.test(cssText) && !/html\[data-page=builder\] \.topnav\{padding/.test(cssText), "same logo and margins as the other pages");
}));
// A inicial não pergunta nada a ninguém: a versão vem do build, como no topo da página.
tasks.push(test("landing page makes no request to another site", () => {
  const version = /number = "(.+?)"/.exec(fs.readFileSync(path.join(ROOT, "src/core/version.zig"), "utf8"))[1];
  for (const file of ["docs/index.html", "docs/pt/index.html"]) {
    const page = fs.readFileSync(path.join(ROOT, file), "utf8");
    assert.ok(!page.includes("api.github.com") && !/fetch\(/.test(page), file + " asks another site");
    assert.ok(page.includes('<span id="dl-version">v' + version + " · </span>"), file + " version");
  }
}));
// O topo do site: grupos com menu, que sem JavaScript são links, e a demonstração só com o build dela.
tasks.push(test("site header: grouped menus, plain links without JS, try link only with the demo build", () => {
  for (const [file, lang] of [["docs/index.html", "en"], ["docs/pt/index.html", "pt"], ["docs/guide/shortcuts.html", "en"], ["docs/pt/theme-builder.html", "pt"]]) {
    const page = fs.readFileSync(path.join(ROOT, file), "utf8");
    const head = page.slice(page.indexOf('<header class="topnav"'), page.indexOf("</header>"));
    assert.strictEqual((head.match(/data-nav-group/g) || []).length, 2, file + " groups");
    for (const m of head.matchAll(/<a class="nav-trig" href="([^"]+)"/g)) assert.ok(/#(themes|features)$/.test(m[1]), file + " trigger links somewhere: " + m[1]);
    assert.ok(/class="nav-burger"[^>]*aria-controls="site-nav"[^>]*aria-expanded="false"/.test(head), file + " burger");
    assert.ok(head.includes('id="site-nav"') && head.includes('id="nav-m-themes"') && head.includes('id="nav-m-why"'), file + " ids");
    assert.ok(head.includes("ko-fi.com") && head.includes("github.com/RshaCuDeVidro/larperCord"), file + " links");
    assert.ok(/class="nav-lang"[^>]*hreflang="(pt-BR|en)"/.test(head), file + " language");
    assert.ok(!/<img/.test(head), file + " no images in the header");
  }
  const py = ["import sys", "sys.path.insert(0, sys.argv[1])", "import gen_site as g",
    "a = g.topnav('pt', 'pt/index.html', 'index.html', 'landing', None)", "g.TRY_SIZE = '1.0 MB'",
    "b = g.topnav('pt', 'pt/index.html', 'index.html', 'landing', None)", "print('nav-try' in a, 'nav-try' in b, 'Testar no navegador' in b)"].join("\n");
  const r = spawnSync("python3", ["-I", "-B", "-c", py, path.join(ROOT, "tools")], { encoding: "utf8" });
  assert.strictEqual(r.stdout.trim(), "False True True", r.stdout + r.stderr);
  // Na gaveta (abaixo de 1100 px) a .nav sai do fluxo: os botões vão para a direita sozinhos.
  const siteCss = fs.readFileSync(path.join(ROOT, "docs/assets/site/site.css"), "utf8");
  const drawer = siteCss.slice(siteCss.indexOf("@media (max-width:1099.98px){"));
  assert.ok(/\.nav-actions\{margin-left:auto\}/.test(drawer.slice(0, drawer.indexOf("\n}"))), "nav actions pushed right in drawer mode");
  // A gaveta prende o Tab e deixa o resto da página inerte.
  const siteJs = fs.readFileSync(path.join(ROOT, "docs/assets/site/site.js"), "utf8");
  assert.ok(siteJs.includes('setAttribute("inert", "")') && siteJs.includes('removeAttribute("inert")'), "drawer makes the page inert");
}));
// A página do criador: a mesma CSP estrita, nada de fora, e as instruções de instalar na página.
tasks.push(test("builder page keeps the strict CSP and the install instructions", () => {
  for (const [file, lang] of [["docs/theme-builder.html", "en"], ["docs/pt/theme-builder.html", "pt"]]) {
    const page = fs.readFileSync(path.join(ROOT, file), "utf8");
    assert.ok(page.includes("Content-Security-Policy\" content=\"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:;"), file + " CSP");
    assert.ok(page.includes("object-src 'none'; frame-src 'none'; worker-src 'none'; base-uri 'self'; form-action 'none'"), file + " CSP rest");
    assert.ok(!/<script[^>]+src="https?:/.test(page) && !/<link[^>]+href="https?:\/\/(?!rshacudevidro)/.test(page.replace(/<link rel="(canonical|alternate)"[^>]*>/g, "")), file + " nothing from outside");
    assert.ok(!/<script(?![^>]*\bsrc=)(?![^>]*application\/json)[^>]*>/.test(page), file + " no inline script");
    for (const id of ["tbx-os-p-linux", "tbx-os-p-win", "tbx-export", "tbx-p-colors", "tbx-p-gen", "tbx-p-layout", "tbx-p-type", "tbx-p-code", "tbx-p-file"]) assert.ok(page.includes('id="' + id + '"'), file + " " + id);
    assert.ok(page.includes(".config/larpercord/themes") && page.includes("$env:APPDATA"), file + " both systems");
    assert.ok(page.includes("data-css-dialog") && page.includes("data-import-dialog"), file + " importers");
  }
}));

Promise.all(tasks).then(() => {
  for (const [name, e] of failures) console.error("FAIL " + name + "\n  " + (e && e.stack ? e.stack.split("\n").slice(0, 12).join("\n  ") : e));
  console.log(passed + " passed, " + failures.length + " failed" + (OUT ? " · files in " + OUT : ""));
  process.exit(failures.length ? 1 : 0);
});
