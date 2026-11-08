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
const path = require("path");
const assert = require("assert");

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
  assert.deepStrictEqual(odd.meta, { name: "", author: "7", desc: "", descEn: "", preview: "classic" });
  assert.deepStrictEqual(odd.fonts, { ui: "Inter", mono: "3", size: 16 });
  assert.strictEqual(odd.radius, 64);
  assert.strictEqual(TB.toKdl(Object.assign(odd, { base: "x\nlayout {}" })).split("\n")[1], "// Made in the larperCord theme builder, starting from xlayout.");
  return Promise.all([
    TB.decode("j.@@@", builtinStructure).then(() => { throw new Error("accepted j.@@@"); }, (e) => assert.strictEqual(e.code, "link-broken")),
    TB.decode("d.AAAA", builtinStructure).then(() => { throw new Error("accepted d.AAAA"); }, (e) => assert.strictEqual(e.code, "link-broken")),
    TB.decode("x.", builtinStructure).then(() => { throw new Error("accepted x."); }, (e) => assert.strictEqual(e.code, "link-broken")),
  ]);
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

Promise.all(tasks).then(() => {
  for (const [name, e] of failures) console.error("FAIL " + name + "\n  " + (e && e.stack ? e.stack.split("\n").slice(0, 3).join("\n  ") : e));
  console.log(passed + " passed, " + failures.length + " failed" + (OUT ? " · files in " + OUT : ""));
  process.exit(failures.length ? 1 : 0);
});
