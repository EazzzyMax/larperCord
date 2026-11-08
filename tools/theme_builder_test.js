#!/usr/bin/env node
// Teste do criador de temas do site (docs/assets/site/theme-builder-core.js, o mesmo
// arquivo que a página usa). Exporta um tema a partir de cada tema embutido e de
// várias edições, e confere que o .kdl gerado é lido do jeito que o app lê:
// mesmo leitor de KDL, mesmas contas de cor e as mesmas regras de theme.zig e fx.zig.
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

// 8. Erros: o leitor aponta linha e coluna, como o app.
tasks.push(test("syntax errors point to line and column", () => {
  assert.throws(() => TB.parseKdl('layout {\n  row {\n    messages "sem fim\n'), (e) => e instanceof TB.KdlError && e.line >= 3);
  assert.throws(() => TB.loadTheme("colors {\n  nao-existe \"#fff\"\n}\nlayout { messages }"), (e) => e.line === 2);
  assert.throws(() => TB.loadTheme("layout {\n  row {\n    label tracking=2 color=\"@nada\"\n  }\n}"), (e) => e.line === 3);
}));

Promise.all(tasks).then(() => {
  for (const [name, e] of failures) console.error("FAIL " + name + "\n  " + (e && e.stack ? e.stack.split("\n").slice(0, 3).join("\n  ") : e));
  console.log(passed + " passed, " + failures.length + " failed" + (OUT ? " · files in " + OUT : ""));
  process.exit(failures.length ? 1 : 0);
});
