#!/usr/bin/env python3
"""Gera o site do GitHub Pages em docs/ (inglês na raiz, português em docs/pt/).

Entradas:
  site/landing.html         a página inicial, com os textos como {{inglês||português}}
  site/guide/{en,pt}/*.md   os guias
  docs/plugins*.md, themes/README*.md   guias que também vivem fora do site
  site/theme-builder.html   o criador de temas (o código fica em docs/assets/site/theme-builder*.js)
  site/community-themes.html  a galeria da comunidade (o código fica em docs/assets/site/community.js)
  themes/*.kdl              paletas, opções e layouts dos temas (a fonte de verdade)
  src/ui/atalhos.zig        os atalhos de teclado ({{keys}} nos guias)
  docs/plugins/*.lua        os plugins que vêm com o app (diretório de plugins)
  src/plugins/manifest.zig, src/ui/plugins_page.zig   capacidades e rótulos dos plugins
  themes/community/*.kdl    temas mandados por pull request: conferidos aqui, e o build para no primeiro erro
  site/try.html             a demonstração no navegador, só quando docs/try/ tem o build dela

Só usa a biblioteca padrão. Rode: python3 tools/gen_site.py
Só conferir os temas da comunidade (o mesmo que o CI faz):
  python3 tools/gen_site.py --check-community [PASTA]
"""
import gzip
import html
import json
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs"
SITE = ROOT / "site"
REPO = "https://github.com/RshaCuDeVidro/larperCord"
VERSION = re.search(r'number = "(.+?)"', (ROOT / "src/core/version.zig").read_text()).group(1)
BASE_URL = "https://rshacudevidro.github.io/larperCord/"
THEMES = ["classico", "vidro", "terminal", "subsolo", "orbital", "editorial", "bolhas", "zen", "papel", "escritorio", "cupertino"]
LANGS = ["en", "pt"]


# ---------------------------------------------------------------- KDL ----
class Node:
    def __init__(self, name, start):
        self.name, self.start, self.end = name, start, start
        self.args, self.props, self.children = [], {}, []


def kdl_tokens(src):
    i, n = 0, len(src)
    while i < n:
        ch = src[i]
        if src.startswith("//", i):
            while i < n and src[i] != "\n":
                i += 1
        elif src.startswith("/*", i):
            i = src.index("*/", i) + 2
        elif ch == "\n" or ch == ";":
            yield ("nl", ch, i, i + 1)
            i += 1
        elif ch in " \t\r":
            i += 1
        elif ch == "\\":
            i += 1
            while i < n and src[i] in " \t\r\n":
                i += 1
        elif ch in "{}=":
            yield (ch, ch, i, i + 1)
            i += 1
        elif ch == '"':
            j, out = i + 1, []
            while src[j] != '"':
                if src[j] == "\\":
                    j += 1
                    out.append({"n": "\n", "t": "\t"}.get(src[j], src[j]))
                else:
                    out.append(src[j])
                j += 1
            yield ("str", "".join(out), i, j + 1)
            i = j + 1
        else:
            j = i
            while j < n and src[j] not in ' \t\r\n{}=;"':
                j += 1
            yield ("word", src[i:j], i, j)
            i = j


def kdl_value(tok):
    kind, val = tok[0], tok[1]
    if kind == "str":
        return val
    if val == "#true":
        return True
    if val == "#false":
        return False
    try:
        return float(val) if "." in val else int(val)
    except ValueError:
        return val


def kdl_parse(src):
    toks = list(kdl_tokens(src))
    pos = [0]

    def block():
        nodes = []
        while pos[0] < len(toks):
            t = toks[pos[0]]
            if t[0] == "nl":
                pos[0] += 1
            elif t[0] == "}":
                pos[0] += 1
                return nodes
            else:
                node = Node(t[1], t[2])
                node.end = t[3]
                pos[0] += 1
                while pos[0] < len(toks) and toks[pos[0]][0] not in ("nl", "}"):
                    a = toks[pos[0]]
                    if a[0] == "{":
                        pos[0] += 1
                        node.children = block()
                        node.end = toks[pos[0] - 1][3]
                        break
                    if pos[0] + 1 < len(toks) and toks[pos[0] + 1][0] == "=":
                        node.props[a[1]] = kdl_value(toks[pos[0] + 2])
                        node.end = toks[pos[0] + 2][3]
                        pos[0] += 3
                    else:
                        node.args.append(kdl_value(a))
                        node.end = a[3]
                        pos[0] += 1
                nodes.append(node)
        return nodes

    return block()


# -------------------------------------------------------------- Cores ----
# As mesmas contas de src/theme/color.zig e dos padrões de src/theme/theme.zig.
FALLBACK = ["15161b", "e06c75", "98c379", "e5c07b", "7aa2f7", "c678dd", "56b6c2", "d7dae0",
            "5c6370", "e06c75", "98c379", "e5c07b", "7aa2f7", "c678dd", "56b6c2", "f0f2f5"]


def rgb(hexstr):
    h = hexstr.lstrip("#")
    if len(h) in (3, 4):
        h = "".join(c * 2 for c in h)
    a = int(h[6:8], 16) / 255 if len(h) == 8 else 1.0
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


WHITE, BLACK = (255, 255, 255, 1.0), (0, 0, 0, 1.0)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(4))


def alpha(a, t):
    # Como `Rgba.alpha` de color.zig: multiplica a opacidade que a cor já tem.
    return (a[0], a[1], a[2], a[3] * t)


def luma(c):
    return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255


def css(c):
    r, g, b = (round(max(0, min(255, v))) for v in c[:3])
    if c[3] >= 0.999:
        return f"#{r:02x}{g:02x}{b:02x}"
    return f"rgba({r},{g},{b},{c[3]:.3f})"


def default_tokens(p, mode):
    if mode == "dark":
        bg, fg = p[0], p[15]
        accent = p[4]
        on = BLACK if luma(accent) > 0.6 else WHITE
        return {"bg": mix(bg, fg, .035), "rail": mix(bg, BLACK, .38), "sidebar": mix(bg, BLACK, .18),
                "surface": mix(bg, fg, .035), "elevated": mix(bg, fg, .085), "overlay": mix(bg, BLACK, .55),
                "text": fg, "muted": mix(fg, bg, .42), "faint": mix(fg, bg, .62), "accent": accent, "accent-text": on,
                "border": alpha(fg, .08), "hover": alpha(fg, .05), "selected": alpha(fg, .10),
                "online": rgb("45b36b"), "idle": rgb("e5a83b"), "dnd": rgb("e5484d"), "danger": rgb("e5484d"),
                "mention": accent, "link": mix(accent, fg, .25), "code-bg": mix(bg, BLACK, .45),
                "bubble-self": accent, "bubble-self-text": on, "bubble-other": mix(bg, fg, .1), "shadow": alpha(BLACK, .35)}
    tint = p[0]
    bg = mix(WHITE, tint, .035)
    ink = mix(mix(tint, BLACK, .55), p[15], .05)
    accent = mix(p[4], BLACK, .3) if luma(p[4]) > .5 else p[4]
    on = BLACK if luma(accent) > .6 else WHITE
    return {"bg": bg, "rail": mix(WHITE, tint, .12), "sidebar": mix(WHITE, tint, .07), "surface": bg,
            "elevated": mix(WHITE, tint, .09), "overlay": WHITE, "text": ink, "muted": mix(ink, bg, .4),
            "faint": mix(ink, bg, .6), "accent": accent, "accent-text": on, "border": alpha(ink, .1),
            "hover": alpha(ink, .05), "selected": alpha(accent, .13), "online": rgb("23a55a"), "idle": rgb("d08a12"),
            "dnd": rgb("d83a42"), "danger": rgb("d83a42"), "mention": accent, "link": mix(accent, BLACK, .1),
            "code-bg": mix(bg, ink, .07), "bubble-self": accent, "bubble-self-text": on,
            "bubble-other": mix(WHITE, tint, .1), "shadow": alpha(BLACK, .12)}


# O "estilo" do site em cada tema: tipografia e efeitos. As cores vêm do .kdl.
FLAVOR = {
    "classico": {"display": "grotesk", "fx": ""},
    "vidro": {"display": "grotesk", "fx": "glass"},
    "terminal": {"display": "mono", "fx": "crt"},
    "subsolo": {"display": "mono", "fx": "crt"},
    "orbital": {"display": "wide", "fx": ""},
    "editorial": {"display": "serif", "fx": ""},
    "bolhas": {"display": "round", "fx": ""},
    "zen": {"display": "thin", "fx": ""},
    "papel": {"display": "serif", "fx": "ruled"},
    "escritorio": {"display": "plain", "fx": ""},
    "cupertino": {"display": "plain", "fx": ""},
}


def load_themes():
    out = {}
    for name in THEMES:
        src = (ROOT / "themes" / f"{name}.kdl").read_text(encoding="utf-8")
        nodes = kdl_parse(src)
        top = {n.name: n for n in nodes}
        t = top["theme"]
        options = []
        if "options" in top:
            for o in top["options"].children:
                options.append({"name": o.args[0], "default": o.props.get("default", True),
                                "label": o.props.get("label", o.args[0]), "desc": o.props.get("description", ""),
                                "labelEn": o.props.get("label-en", o.props.get("label", o.args[0])),
                                "descEn": o.props.get("description-en", o.props.get("description", ""))})
        on = {o["name"] for o in options if o["default"]}
        pal = [rgb(x) for x in FALLBACK]
        if "palette" in top and top["palette"].args and top["palette"].args[0] != "wal":
            pal = [rgb(x) for x in top["palette"].args] + pal[len(top["palette"].args):]
        modes, raw = {}, {}
        for mode in ("dark", "light"):
            toks = default_tokens(pal, mode)
            for n in nodes:
                if n.name != "colors":
                    continue
                if n.props.get("mode", mode) != mode:
                    continue
                if "when" in n.props and n.props["when"] not in on:
                    continue
                for c in n.children:
                    toks[c.name] = color_eval(c.args[0], pal, toks)
            modes[mode] = {k: css(v) for k, v in toks.items()}
            raw[mode] = toks
        radius = top["metrics"].props.get("radius", 6) if "metrics" in top else 6
        # O que o playground abre: o layout e os estilos do arquivo, como estão,
        # mais as cores já resolvidas (no arquivo podem depender do pywal).
        keep = ["bg", "rail", "sidebar", "surface", "elevated", "text", "muted", "faint", "accent", "accent-text",
                "border", "selected", "online", "mention", "bubble-self", "bubble-self-text", "bubble-other"]
        lines = [f"// themes/{name}.kdl: try changing a width", src[top["layout"].start:top["layout"].end], ""]
        if options:
            lines.append("options {")
            lines += [f'    option "{o["name"]}" default={"#true" if o["default"] else "#false"}' for o in options]
            lines.append("}")
        if "styles" in top:
            lines.append(src[top["styles"].start:top["styles"].end])
        lines.append("colors {")
        lines += [f'    {k} "{modes["dark"][k]}"' for k in keep]
        lines.append("}")
        out[name] = {"desc": t.props.get("description", ""), "descEn": t.props.get("description-en", t.props.get("description", "")),
                     "radius": radius, "options": options, "dark": modes["dark"], "light": modes["light"],
                     "preset": "\n".join(lines), "nodes": layout_nodes(src, top, on, pal, raw), **FLAVOR[name]}
    return out


# O tema do próprio site: neon sobre preto, terminal e zine. Não existe no app.
BRAND = {
    "desc": "", "descEn": "", "radius": 0, "options": [], "display": "pixel", "fx": "zine", "preset": "",
    "dark": {"bg": "#050505", "rail": "#030208", "sidebar": "#0a050f", "surface": "#0a050f", "elevated": "#140a1f",
             "overlay": "#0a050f", "text": "#e5e7eb", "muted": "#9c95ab", "faint": "#5e5669", "accent": "#d946ef",
             "accent-text": "#0a0210", "border": "#2a1740", "hover": "rgba(217,70,239,.08)", "selected": "rgba(217,70,239,.15)",
             "online": "#22c55e", "idle": "#f59e0b", "dnd": "#ef4444", "danger": "#ef4444", "mention": "#06b6d4",
             "link": "#22d3ee", "code-bg": "#0a0a0a", "bubble-self": "#9333ea", "bubble-self-text": "#fff",
             "bubble-other": "#140a1f", "shadow": "rgba(0,0,0,.6)"},
    "light": {"bg": "#ffffff", "rail": "#f1f5f9", "sidebar": "#f8fafc", "surface": "#f8fafc", "elevated": "#ffffff",
              "overlay": "#ffffff", "text": "#111827", "muted": "#4b5563", "faint": "#9ca3af", "accent": "#7c3aed",
              "accent-text": "#ffffff", "border": "#d1d5db", "hover": "rgba(124,58,237,.07)", "selected": "rgba(124,58,237,.12)",
              "online": "#166534", "idle": "#92400e", "dnd": "#b91c1c", "danger": "#dc2626", "mention": "#0e7490",
              "link": "#0e7490", "code-bg": "#f6f8fa", "bubble-self": "#6d28d9", "bubble-self-text": "#fff",
              "bubble-other": "#e5e7eb", "shadow": "rgba(40,10,60,.12)"},
}


# ------------------------------------------------------------- Realce ----
HL = {
    "kdl": r'''(?P<c>//[^\n]*)|(?P<s>"(?:\\.|[^"\\])*")|(?P<n>\#true|\#false|\b\d+(?:\.\d+)?\b)|(?P<p>[\w-]+(?==))|(?P<k>^[ \t]*[\w-]+)''',
    "lua": r'''(?P<c>--[^\n]*)|(?P<s>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|(?P<n>\b\d+\b)|(?P<k>\b(?:local|function|end|if|then|else|elseif|for|in|do|while|return|not|and|or|nil|true|false)\b)|(?P<p>\blarper\.\w+)''',
    "bash": r'''(?P<c>(?:^|(?<=\s))\#[^\n]*)|(?P<s>"(?:\\.|[^"\\])*"|'[^']*')|(?P<k>^[ \t]*(?:sudo\s+)?[\w./-]+)|(?P<p>(?<=\s)--?[\w-]+)''',
    "zig": r'''(?P<c>//[^\n]*)|(?P<s>"(?:\\.|[^"\\])*")|(?P<n>\b\d+\b)|(?P<k>\b(?:const|var|fn|pub|return|if|else|while|for|try|struct)\b)''',
}


def highlight(code, lang):
    pat = HL.get({"sh": "bash", "shell": "bash"}.get(lang, lang))
    if not pat:
        return html.escape(code, quote=False)
    out, last = [], 0
    for m in re.finditer(pat, code, re.M):
        if m.start() == m.end():
            continue
        out.append(html.escape(code[last:m.start()], quote=False))
        out.append(f'<span class="t-{m.lastgroup}">{html.escape(m.group(0), quote=False)}</span>')
        last = m.end()
    out.append(html.escape(code[last:], quote=False))
    return "".join(out)


def code_block(code, lang):
    label = f'<span class="code-lang">{html.escape(lang)}</span>' if lang else ""
    return (f'<div class="code" data-lang="{html.escape(lang)}">{label}<button class="copy" type="button" data-copy>copy</button>'
            f'<pre><code>{highlight(code, lang)}</code></pre></div>')


# ----------------------------------------------------------- Markdown ----
def slugify(s):
    s = re.sub(r"<[^>]+>", "", s).lower()
    s = re.sub(r"[`*]", "", s)
    table = str.maketrans("áàãâéêíóõôúç", "aaaaeeiooouc")
    s = s.translate(table)
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", s)).strip("-")


def inline(text, rewrite):
    keep = []

    def stash(v):
        keep.append(v)
        return f"\x00{len(keep) - 1}\x00"

    text = re.sub(r"`([^`]+)`", lambda m: stash(f"<code>{html.escape(m.group(1), quote=False)}</code>"), text)
    # HTML que os documentos usam de propósito (<sub>, <kbd>) passa; o resto é escapado.
    text = re.sub(r"</?(?:sub|kbd)>", lambda m: stash(m.group(0)), text)
    text = html.escape(text, quote=False)
    text = re.sub(r"!\[([^\]]*)\]\(([^)]+)\)", lambda m: stash(f'<img src="{rewrite(m.group(2))}" alt="{m.group(1)}" loading="lazy">'), text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", lambda m: f'<a href="{rewrite(m.group(2))}">{m.group(1)}</a>', text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*([^*\n]+)\*(?![\w*])", r"<em>\1</em>", text)
    text = re.sub(r"~~([^~]+)~~", r"<s>\1</s>", text)
    return re.sub(r"\x00(\d+)\x00", lambda m: keep[int(m.group(1))], text)


def split_row(line):
    line = line.strip().strip("|")
    cells, cur, in_code = [], "", False
    i = 0
    while i < len(line):
        ch = line[i]
        if ch == "`":
            in_code = not in_code
        if ch == "\\" and i + 1 < len(line) and line[i + 1] == "|":
            cur += "|"
            i += 2
            continue
        if ch == "|" and not in_code:
            cells.append(cur.strip())
            cur = ""
        else:
            cur += ch
        i += 1
    cells.append(cur.strip())
    return cells


ALERTS = {"WARNING": "warn", "IMPORTANT": "warn", "NOTE": "note", "TIP": "note"}


def markdown(src, rewrite, skip_h1=False):
    lines = src.split("\n")
    out, heads = [], []
    i = 0
    seen = {}

    def heading(level, text):
        base = slugify(text) or "section"
        n = seen.get(base, 0)
        seen[base] = n + 1
        hid = base if n == 0 else f"{base}-{n}"
        heads.append((level, re.sub(r"`", "", text), hid))
        return f'<h{level} id="{hid}"><a class="anchor" href="#{hid}" aria-hidden="true">#</a>{inline(text, rewrite)}</h{level}>'

    # Blocos ":::" (como no pandoc): o seletor de sistema da instalação.
    #   :::: os-pick            um grupo de opções; o site mostra primeiro a do visitante
    #   ::: os arch | Título    uma opção, com um título que entra no índice da página
    #   :::                     fecha (o mesmo número de dois-pontos)
    fences = []

    def blocks_list(start):
        j = start
        kind = "ol" if re.match(r"\s*\d+\.\s", lines[j]) else "ul"
        items = []
        while j < len(lines):
            m = re.match(r"(\s*)(?:[-*]|\d+\.)\s+(.*)", lines[j])
            if m and not m.group(1):
                items.append(m.group(2))
                j += 1
            elif m or (lines[j].startswith("  ") and lines[j].strip()):
                items[-1] += "\n" + lines[j].strip()
                j += 1
            elif not lines[j].strip() and j + 1 < len(lines) and re.match(r"(?:[-*]|\d+\.)\s", lines[j + 1]):
                j += 1
            else:
                break
        body = []
        for it in items:
            if "```" in it:
                body.append("<li>" + markdown(it, rewrite)[0] + "</li>")
                continue
            task = re.match(r"\[( |x)\]\s+(.*)", it, re.S)
            if task:
                state = "done" if task.group(1) == "x" else "todo"
                body.append(f'<li class="task {state}">{inline(task.group(2), rewrite)}</li>')
            else:
                body.append(f"<li>{inline(it, rewrite)}</li>")
        return f"<{kind}>" + "".join(body) + f"</{kind}>", j

    while i < len(lines):
        ln = lines[i]
        if not ln.strip():
            i += 1
        elif ln.startswith("```"):
            lang = ln[3:].strip()
            j = i + 1
            while not lines[j].startswith("```"):
                j += 1
            out.append(code_block("\n".join(lines[i + 1:j]), lang))
            i = j + 1
        elif re.match(r":{3,}", ln):
            head = ln.lstrip(":").strip()
            kind, _, rest = head.partition(" ")
            if not head:
                out.append(fences.pop())
            elif kind == "os-pick":
                out.append('<div class="os-pick" data-os-pick>')
                fences.append('</div>\n<link rel="stylesheet" href="@@ROOT@@assets/site/extra.css">'
                              '<script src="@@ROOT@@assets/site/os.js" defer></script>')
            elif kind == "os":
                key, _, title = rest.partition("|")
                out.append(f'<section class="os-opt" data-os="{html.escape(key.strip())}">')
                out.append(heading(3, title.strip()))
                fences.append("</section>")
            else:
                raise SystemExit(f"bloco ::: desconhecido: {ln}")
            i += 1
        elif re.match(r"#{1,6}\s", ln):
            lv = len(ln) - len(ln.lstrip("#"))
            text = ln[lv:].strip()
            if not (lv == 1 and skip_h1):
                out.append(heading(lv, text))
            i += 1
        elif ln.startswith(">"):
            j = i
            quote = []
            while j < len(lines) and lines[j].startswith(">"):
                quote.append(lines[j][1:].lstrip(" "))
                j += 1
            kind = "note"
            m = re.match(r"\[!(\w+)\]", quote[0])
            if m:
                kind = ALERTS.get(m.group(1), "note")
                quote = quote[1:]
            inner, _ = markdown("\n".join(quote), rewrite)
            out.append(f'<aside class="callout {kind}">{inner}</aside>')
            i = j
        elif ln.startswith("|") and i + 1 < len(lines) and re.match(r"\s*\|?[\s:|-]+\|?\s*$", lines[i + 1]):
            head = split_row(ln)
            j = i + 2
            rows = []
            while j < len(lines) and lines[j].startswith("|"):
                rows.append(split_row(lines[j]))
                j += 1
            th = "".join(f"<th>{inline(c, rewrite)}</th>" for c in head)
            tr = "".join("<tr>" + "".join(f"<td>{inline(c, rewrite)}</td>" for c in r) + "</tr>" for r in rows)
            out.append(f'<div class="table-wrap"><table><thead><tr>{th}</tr></thead><tbody>{tr}</tbody></table></div>')
            i = j
        elif re.match(r"\s*(?:[-*]|\d+\.)\s", ln):
            block, i = blocks_list(i)
            out.append(block)
        elif re.match(r"-{3,}\s*$", ln):
            out.append("<hr>")
            i += 1
        else:
            # A primeira linha é sempre do parágrafo: um "|" que não abre tabela chega aqui.
            j = i + 1
            para = [ln]
            while j < len(lines) and lines[j].strip() and not re.match(r"(?:```|#{1,6}\s|>|\||:{3})", lines[j]) and not re.match(r"\s*(?:[-*]|\d+\.)\s", lines[j]):
                para.append(lines[j])
                j += 1
            out.append(f"<p>{inline(' '.join(para), rewrite)}</p>")
            i = j
    return "\n".join(out), heads


# ------------------------------------------------------------- Mascote ----
# O desenho de assets/logo-mark.svg, em peças que o site anima (site.css e site.js).
BODY = "M340 258 L568 188 L625 268 Q700 262 778 268 L838 182 Q960 200 1048 248 C1180 420 1260 620 1262 812 C1180 880 1080 920 985 945 L930 830 Q700 850 482 802 L428 938 C320 910 220 870 148 830 C150 620 220 420 340 258 Z"
EYE_L = "M338 600 L660 548 C640 640 590 702 482 705 C400 705 346 662 338 600 Z"
EYE_R = "M698 540 L1068 455 C1086 540 1048 612 950 614 C842 614 736 600 698 540 Z"
MOUTH = "M728 742 C830 722 922 700 980 652 C988 668 980 680 962 690 C900 722 822 742 732 750 Z"
SPARK = "M1095 160 C1105 250 1120 282 1240 296 C1130 310 1112 340 1110 436 C1100 340 1080 322 940 322 C1060 306 1088 272 1095 160 Z"


def shrink(path, cx, cy, k, nx, ny):
    """A forma do olho é a da lente, menor: a pálpebra reta dá a cara de deboche."""
    xy = 0

    def repl(m):
        nonlocal xy
        v = float(m.group(0))
        xy += 1
        return f"{(nx + (v - cx) * k) if xy % 2 else (ny + (v - cy) * k):.1f}"

    return re.sub(r"-?\d+(?:\.\d+)?", repl, path)


EYE_LS = shrink(EYE_L, 499, 626, 0.6, 496, 628)
EYE_RS = shrink(EYE_R, 885, 535, 0.6, 884, 536)


def mascot(uid):
    return f'''<svg class="ma" viewBox="100 110 1200 900" aria-hidden="true" focusable="false"><defs><clipPath id="ma-b{uid}"><path d="{BODY}"/></clipPath><clipPath id="ma-l{uid}"><path d="{EYE_L}"/><path d="{EYE_R}"/></clipPath><clipPath id="ma-e{uid}"><path d="{EYE_LS}"/><path d="{EYE_RS}"/></clipPath><linearGradient id="ma-lens{uid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2b0a44"/><stop offset=".55" stop-color="#0c0316"/><stop offset="1" stop-color="#040108"/></linearGradient></defs><g class="ma-rig"><path class="ma-ghost ma-g1" d="{BODY}"/><path class="ma-ghost ma-g2" d="{BODY}"/><g clip-path="url(#ma-b{uid})"><path class="ma-edge" d="{BODY}"/><path class="ma-core" d="{BODY}" transform="translate(12.5 45) scale(0.95)"/><path class="ma-shade" d="M150 690 C230 810 330 870 470 900 L440 980 L100 980 L100 690 Z"/></g><path class="ma-line" d="{BODY}"/><g class="ma-eyes"><path class="ma-white" d="{EYE_LS}"/><path class="ma-white" d="{EYE_RS}"/><g clip-path="url(#ma-e{uid})"><ellipse class="ma-iris" cx="520" cy="634" rx="30" ry="36"/><ellipse class="ma-iris" cx="908" cy="538" rx="30" ry="36"/></g><path class="ma-lid" d="{EYE_LS}"/><path class="ma-lid" d="{EYE_RS}"/></g><path class="ma-mouth ma-ink" d="{MOUTH}"/><g class="ma-shades"><path class="ma-arm" d="M345 596 L196 566"/><path class="ma-arm" d="M1066 458 L1196 424"/><path class="ma-arm" d="M655 554 Q680 528 702 544"/><path class="ma-lens" fill="url(#ma-lens{uid})" d="{EYE_L}"/><path class="ma-lens" fill="url(#ma-lens{uid})" d="{EYE_R}"/><g clip-path="url(#ma-l{uid})"><path class="ma-tint" d="M300 640 L1100 450 L1100 520 L300 700 Z"/><path class="ma-glare" d="M250 760 L350 760 L620 420 L520 420 Z M400 760 L440 760 L710 420 L670 420 Z"/></g></g><path class="ma-spark" d="{SPARK}"/></g></svg>'''


def live_icon():
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><style>@keyframes t{{0%,80%,100%{{transform:scale(1) rotate(0)}}90%{{transform:scale(1.35) rotate(90deg)}}}}@keyframes g{{0%,70%{{transform:translateX(-420px)}}90%,100%{{transform:translateX(900px)}}}}#s{{transform-box:fill-box;transform-origin:center;animation:t 3.4s infinite}}#g{{animation:g 3.6s infinite}}</style><defs><clipPath id="c"><path d="{EYE_L}"/><path d="{EYE_R}"/></clipPath></defs><rect width="512" height="512" rx="116" fill="#0a050f"/><g transform="translate(28 85) scale(0.38) translate(-100 -110)"><path d="{BODY}" fill="#F03CFF"/><path d="{BODY}" fill="#7A0BD0" transform="translate(12.5 45) scale(0.95)"/><path d="{BODY}" fill="none" stroke="#12061F" stroke-width="26" stroke-linejoin="round"/><path d="M345 596 L196 566M1066 458 L1196 424M655 554 Q680 528 702 544" fill="none" stroke="#12061F" stroke-width="26"/><path d="{EYE_L}" fill="#12061F"/><path d="{EYE_R}" fill="#12061F"/><g clip-path="url(#c)"><path id="g" d="M300 760 L420 760 L690 420 L570 420 Z" fill="#fff" opacity=".55"/></g><path d="{MOUTH}" fill="#12061F"/><path id="s" d="{SPARK}" fill="#FF3CF0" stroke="#12061F" stroke-width="18"/></g></svg>'''


# ------------------------------------------------------------ Layouts ----
# Os retângulos de cada tema numa janela de 1280x800, como src/theme/layout.zig
# calcula: é o que a interface 3D do topo da página mostra.
CONTAINERS = ("row", "column", "stack")


def layout_nodes(src, top, on, pal, raw):
    styles = {}
    if "styles" in top:
        for st in top["styles"].children:
            styles[st.args[0]] = st.props
    radius_default = top["metrics"].props.get("radius", 6) if "metrics" in top else 6

    def color(expr, mode):
        if expr is None:
            return None
        toks = raw[mode]
        try:
            return css(toks[expr]) if expr in toks else css(color_eval(expr, pal, toks))
        except (KeyError, ValueError, IndexError):
            return None

    def visible(n):
        p = n.props
        if p.get("show") is False:
            return False
        if "when" in p and p["when"] not in on:
            return False
        if "unless" in p and p["unless"] in on:
            return False
        if "hide-below" in p and 1280 < p["hide-below"]:
            return False
        return True

    out = []

    def walk(n, x, y, w, h):
        p = n.props
        style = styles.get(p.get("style"), {}) if p.get("style") else {}
        fill = style.get("bg", p.get("bg"))
        c = [color(fill, "dark"), color(fill, "light")] if fill else None
        if "max-width" in p and w > p["max-width"]:
            x += (w - p["max-width"]) / 2
            w = p["max-width"]
        r = p.get("radius", style.get("radius", 0 if n.name in CONTAINERS else radius_default if fill else 0))
        r = r if isinstance(r, (int, float)) else 0
        line = " ".join(src[n.start:n.end].split("{")[0].split())
        if n.name in CONTAINERS:
            if c and c[0]:
                out.append({"k": "box", "x": x, "y": y, "w": w, "h": h, "c": c, "r": r, "n": line[:44]})
            pad = p.get("padding", 0)
            px, py = p.get("padding-x", pad), p.get("padding-y", pad)
            x, y, w, h = x + px, y + py, w - 2 * px, h - 2 * py
            kids = [k for k in n.children if visible(k)]
            if n.name == "stack":
                for k in kids:
                    walk(k, x, y, w, h)
                return
            horiz = n.name == "row"
            main, size = ("width", w) if horiz else ("height", h)
            gap = p.get("gap", 0)
            free = size - gap * max(len(kids) - 1, 0)
            weights = 0
            for k in kids:
                if main in k.props:
                    free -= k.props[main]
                else:
                    weights += k.props.get("flex", 1)
            at = x if horiz else y
            for k in kids:
                length = k.props[main] if main in k.props else max(free, 0) * k.props.get("flex", 1) / (weights or 1)
                if horiz:
                    walk(k, at, y, length, h)
                else:
                    walk(k, x, at, w, length)
                at += length + gap
            return
        if n.name in ("spacer", "crt"):
            return
        ix, iy = p.get("inset-x", 0), p.get("inset-y", 0)
        node = {"k": n.name, "x": round(x + ix, 1), "y": round(y + iy, 1), "w": round(w - 2 * ix, 1), "h": round(h - 2 * iy, 1), "r": r, "n": line[:44]}
        if c and c[0]:
            node["c"] = c
        for key, short in (("variant", "v"), ("shape", "s")):
            if key in p:
                node[short] = p[key]
        if n.name == "label":
            node["t"] = p.get("text", "")
            node["fs"] = p.get("size", 12)
        out.append(node)

    root = top["layout"].children[0]
    walk(root, 0, 0, 1280, 800)
    for o in out:
        for key in ("x", "y", "w", "h"):
            o[key] = round(o[key], 1)
    return out


# ------------------------------------------------------- Fontes do app ----
# Páginas que saem do próprio código, para nunca ficarem para trás: os atalhos
# (src/ui/atalhos.zig), os plugins que vêm com o app (docs/plugins/) e o que um
# plugin pode pedir (src/plugins/manifest.zig e os rótulos de src/ui/plugins_page.zig).
ZSTR = r'"((?:\\.|[^"\\])*)"'


def zig_unescape(s):
    def rep(m):
        e = m.group(1)
        if e.startswith("u{"):
            return chr(int(e[2:-1], 16))
        return {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'"}[e]
    return re.sub(r"\\(u\{[0-9a-fA-F]+\}|[ntr\\\"'])", rep, s)


def zig_entries(path, decl):
    """As entradas `.{ .campo = valor, ... },` (uma por linha) de `const decl = [_]T{ ... };`."""
    src = path.read_text(encoding="utf-8")
    m = re.search(rf"^(?:pub )?const {decl}\s*=\s*\[_\]\w+\{{\n(.*?)\n\}};", src, re.S | re.M)
    if not m:
        raise SystemExit(f"{path.relative_to(ROOT)}: não achei a lista `{decl}`")
    out = []
    for ln in m.group(1).split("\n"):
        ln = ln.strip()
        if not ln or ln.startswith("//"):
            continue
        if not (ln.startswith(".{") and ln.endswith("},")):
            raise SystemExit(f"{path.relative_to(ROOT)}: `{decl}` precisa de uma entrada por linha: {ln[:80]}")
        fields = {}
        for f in re.finditer(r"\.(\w+) = (?:" + ZSTR + r"|\.(\w+)|(true|false)\b)", ln):
            if f.group(2) is not None:
                fields[f.group(1)] = zig_unescape(f.group(2))
            elif f.group(3) is not None:
                fields[f.group(1)] = f.group(3)
            else:
                fields[f.group(1)] = f.group(4) == "true"
        out.append(fields)
    return out


def load_keys():
    path = ROOT / "src" / "ui" / "atalhos.zig"
    groups, rows = zig_entries(path, "grupos"), zig_entries(path, "lista")
    ids = [g["id"] for g in groups]
    for r in rows:
        if not all(k in r for k in ("grupo", "pt", "en", "teclas")) or r["grupo"] not in ids:
            raise SystemExit(f"src/ui/atalhos.zig: linha incompleta ou grupo desconhecido: {r}")
    return groups, rows


def keys_html(spec):
    """"Ctrl+Shift+P / F2" -> teclas em <kbd>. "Ctrl +" é Ctrl com a tecla +."""
    def caps(piece):
        m = re.fullmatch(r"(\S+) (\S)", piece)
        parts = [m.group(1), m.group(2)] if m else re.split(r"(?<=\S)\+(?=\S)", piece)
        return "+".join(f"<kbd>{p}</kbd>" for p in parts)
    return " / ".join(caps(a) for a in spec.split(" / "))


PLUGIN_KEY = re.compile(r"[a-z0-9]|f(?:[1-9]|1\d|2[0-4])|enter|space|tab|backspace|delete|insert|home|end|pageup|pagedown|up|down|left|right|[,./;=-]")


def plugin_keys(spec):
    """"F2 / Ctrl+T" -> ["f2", "ctrl+t"]: as teclas na forma de larper.keybind, para o gerador
    de plugin avisar quando um atalho dele também é do app. Mouse e teclas que um plugin nem
    pode pedir ficam de fora. "Ctrl +" é a tecla = (root.zig zoomKeys); "Alt+1…9" vira nove."""
    out = []
    for alt in spec.split(" / "):
        m = re.fullmatch(r"(\S+) (\S)", alt)
        parts = [m.group(1), m.group(2)] if m else re.split(r"(?<=\S)\+(?=\S)", alt)
        *mods, key = [p.lower() for p in parts]
        key = {"+": "=", "↑": "up", "↓": "down", "←": "left", "→": "right"}.get(key, key)
        if set(mods) - {"ctrl", "shift", "alt", "super"}:
            continue
        r = re.fullmatch(r"(\d)…(\d)", key)
        for k in [str(d) for d in range(int(r.group(1)), int(r.group(2)) + 1)] if r else [key]:
            fkey = re.fullmatch(r"f\d+", k)
            # As regras de runtime.zig parseKeys: fora F1–F24, pede ctrl, alt ou super, e
            # ctrl sozinho com a, c, v, x, y ou z fica para a digitação.
            if not PLUGIN_KEY.fullmatch(k) or not (fkey or {"ctrl", "alt", "super"} & set(mods)):
                continue
            if mods == ["ctrl"] and k in ("a", "c", "v", "x", "y", "z"):
                continue
            out.append("+".join([x for x in ("ctrl", "shift", "alt", "super") if x in mods] + [k]))
    return out


def keys_md(lang, which):
    """As tabelas de atalhos, em markdown: `{{keys}}` são todos os grupos menos o vim."""
    groups, rows = load_keys()
    out = []
    for g in groups:
        if (g["id"] == "vim") != (which == "vim"):
            continue
        mine = [r for r in rows if r["grupo"] == g["id"]]
        if not mine:
            continue
        if which != "vim":
            out += [f"### {g['en'] if lang == 'en' else g['pt']}", ""]
        out += [t(lang, "| Action | Keys |", "| Ação | Teclas |"), "|---|---|"]
        for r in mine:
            spec = r.get("teclas_pt") if lang == "pt" and r.get("teclas_pt") else r["teclas"]
            out.append(f"| {r['en'] if lang == 'en' else r['pt']} | {keys_html(spec)} |")
        out.append("")
    return "\n".join(out)


def lua_manifest(src):
    """O cabeçalho de um plugin, lido como src/plugins/manifest.zig lê."""
    out = {}
    for raw in src.split("\n")[:80]:
        s = raw.strip()
        if not s:
            continue
        if not s.startswith("--"):
            break
        s = s[2:].lstrip()
        if s.startswith("@"):
            parts = re.split(r"[ \t]+", s[1:], maxsplit=1)
            out[parts[0]] = parts[1].strip() if len(parts) > 1 else ""
    return out


def load_plugin_api():
    """O que um plugin pode pedir, com os rótulos e as explicações do cartão do app."""
    man = (ROOT / "src" / "plugins" / "manifest.zig").read_text(encoding="utf-8")
    caps = re.findall(r"(\w+),", re.search(r"pub const Cap = enum\(\w+\) \{(.*?)\};", man, re.S).group(1))
    page = ROOT / "src" / "ui" / "plugins_page.zig"
    labels = {e["cap"]: e for e in zig_entries(page, "labels")}
    if set(caps) - set(labels):
        raise SystemExit(f"src/ui/plugins_page.zig: capacidade sem rótulo: {sorted(set(caps) - set(labels))}")
    alert = re.search(r"fn alertLine\(.*?\n\}\n", page.read_text(encoding="utf-8"), re.S).group(0)
    warn = [tuple(zig_unescape(x) for x in m) for m in re.findall(r"i18n\.tr\(" + ZSTR + r", " + ZSTR + r"\)", alert)]
    if len(warn) != 2:
        raise SystemExit("src/ui/plugins_page.zig: alertLine mudou; ajuste load_plugin_api")
    family = re.findall(ZSTR, re.search(r"const family = \[_\]\[\]const u8\{(.*?)\};", man, re.S).group(1))
    # Os atalhos do app (src/ui/atalhos.zig): um plugin com a mesma combinação dispara junto.
    groups, rows = load_keys()
    gname = {g["id"]: g for g in groups}
    app_keys = {}
    for r in rows:
        en, pt = r["en"], r["pt"]
        if r["grupo"] == "vim":
            en, pt = f"{gname['vim']['en']}: {en}", f"{gname['vim']['pt']}: {pt}"
        for k in plugin_keys(r["teclas"]):
            app_keys.setdefault(k, {"k": k, "en": en, "pt": pt})
    return {
        "caps": caps,
        "labels": {c: {"en": labels[c]["en"], "pt": labels[c]["pt"], "tipEn": labels[c]["tip_en"], "tipPt": labels[c]["tip_pt"],
                       "strong": labels[c].get("strong", False)} for c in caps},
        "warn": {"http": {"pt": warn[0][0], "en": warn[0][1]}, "links": {"pt": warn[1][0], "en": warn[1][1]}},
        "maxHosts": int(re.search(r"pub const max_hosts = (\d+);", man).group(1)),
        "discord": family,
        "appKeys": list(app_keys.values()),
    }


def load_bundled_plugins():
    """Os plugins embutidos no executável (docs/plugins/exemplos.zig), com o cabeçalho de cada um."""
    lst = (ROOT / "docs" / "plugins" / "exemplos.zig").read_text(encoding="utf-8")
    out = []
    for name in re.findall(r'\.name = "([\w-]+\.lua)"', lst):
        src = (ROOT / "docs" / "plugins" / name).read_text(encoding="utf-8")
        m = lua_manifest(src)
        out.append({
            "file": name, "name": m.get("name", name), "namePt": m.get("name:pt", m.get("name", name)),
            "desc": m.get("description", ""), "descPt": m.get("description:pt", m.get("description", "")),
            "version": m.get("version", ""), "caps": re.split(r"[,\s]+", m.get("capabilities", "").strip()) if m.get("capabilities") else [],
            "hosts": re.split(r"[,\s]+", m["hosts"].strip()) if m.get("hosts") else [],
            "commands": re.findall(r'larper\.command\("(/[\w-]+)"', src),
            "keys": re.findall(r'larper\.keybind\("([^"]+)"', src),
            "menus": [{"pt": zig_unescape(a), "en": zig_unescape(b)} for a, b in re.findall(r'larper\.menu\("\w+", \{ pt = ' + ZSTR + r", en = " + ZSTR, src)],
            "panel": "larper.panel.set" in src,
        })
    return out


def plugins_md(lang, api):
    """A página com os plugins que vêm com o app."""
    plugins = load_bundled_plugins()
    # O nome do botão, como o app mostra (src/ui/plugins_page.zig).
    page = (ROOT / "src" / "ui" / "plugins_page.zig").read_text(encoding="utf-8")
    btn = re.search(r"p\.button\(i18n\.tr\(" + ZSTR + r', "(Install bundled[^"]*)"\)', page)
    if not btn:
        raise SystemExit("src/ui/plugins_page.zig: não achei o botão Install bundled plugins; ajuste plugins_md")
    install = zig_unescape(btn.group(2) if lang == "en" else btn.group(1))
    out = [t(lang, "# Plugin directory", "# Diretório de plugins"), "",
           t(lang, f"The {len(plugins)} plugins that come inside the app, with what each one asks for. **Settings → Plugins → {install}** copies the ones you don't have into your plugins folder; it never overwrites a file you've edited. The ones that use the internet send nothing until you approve the host on their card.",
             f"Os {len(plugins)} plugins que vêm dentro do app, com o que cada um pede. **Configurações → Plugins → {install}** copia os que você não tem para a sua pasta de plugins; nunca sobrescreve um arquivo que você editou. Os que usam a internet não mandam nada antes de você aprovar o host no cartão deles."),
           "",
           t(lang, "This page is generated from the files themselves (`docs/plugins/`) and from the labels the app shows on each plugin's card, so it matches what you'll see in Settings. To write your own, start with the [plugin starter](page:plugin-starter) and the [API](page:plugins).",
             "Esta página é gerada dos próprios arquivos (`docs/plugins/`) e dos rótulos que o app mostra no cartão de cada plugin, então bate com o que você vê nas Configurações. Para escrever o seu, comece pelo [gerador de plugin](page:plugin-starter) e pela [API](page:plugins)."),
           ""]
    for p in sorted(plugins, key=lambda p: (p["name"] if lang == "en" else p["namePt"]).lower()):
        out += [f"## {p['name'] if lang == 'en' else p['namePt']}", ""]
        meta = [f"`{p['file']}`"]
        if p["version"]:
            meta.append(t(lang, f"version {p['version']}", f"versão {p['version']}"))
        meta.append(f"[{t(lang, 'source', 'código')}]({REPO}/blob/main/docs/plugins/{p['file']})")
        out += [" · ".join(meta), "", p["desc"] if lang == "en" else p["descPt"], ""]
        if p["caps"]:
            out += [t(lang, "| It asks for | What that allows |", "| Pede | O que isso permite |"), "|---|---|"]
            for c in p["caps"]:
                lb = api["labels"][c]
                name = lb["en"] if lang == "en" else lb["pt"]
                out.append(f"| {'**' + name + '**' if lb['strong'] else name} (`{c}`) | {lb['tipEn'] if lang == 'en' else lb['tipPt']} |")
            out.append("")
        else:
            out += [t(lang, "It asks for nothing beyond its own commands.", "Não pede nada além dos próprios comandos."), ""]
        facts = []
        if p["hosts"]:
            hosts = ", ".join(f"`{h}`" for h in p["hosts"])
            facts.append(t(lang, f"**Talks to:** {hosts}, only after you approve it on the card", f"**Fala com:** {hosts}, só depois de você aprovar no cartão"))
        if p["commands"]:
            facts.append(t(lang, "**Commands:** ", "**Comandos:** ") + ", ".join(f"`{c}`" for c in p["commands"]))
        if p["keys"]:
            facts.append(t(lang, "**Keybinds:** ", "**Atalhos:** ") + ", ".join(f"`{k}`" for k in p["keys"]))
        if p["menus"]:
            facts.append(t(lang, "**Right-click on a message:** ", "**Botão direito numa mensagem:** ") + ", ".join(m["en"] if lang == "en" else m["pt"] for m in p["menus"]))
        if p["panel"]:
            facts.append(t(lang, "**Panel:** from the channel header button or the palette (`Panel: name`)", "**Painel:** pelo botão no topo do canal ou pela paleta (`Painel: nome`)"))
        if facts:
            out += [f"- {f}" for f in facts] + [""]
        if "messages" in p["caps"] and ("http" in p["caps"] or "links" in p["caps"]):
            w = api["warn"]["http" if "http" in p["caps"] else "links"]
            out += ["> [!WARNING]", t(lang, f"> The card shows: “{w['en']}”", f"> O cartão mostra: “{w['pt']}”"), ""]
    return "\n".join(out)


def starter_embed(lang, path):
    root = root_of(path)
    return (f'<div class="starter" data-starter><noscript><p class="callout warn">'
            f'{t(lang, "The generator needs JavaScript. Without it, copy the example on the API page and edit the header by hand.", "O gerador precisa de JavaScript. Sem ele, copie o exemplo da página da API e edite o cabeçalho à mão.")}'
            f'</p></noscript></div>\n<link rel="stylesheet" href="{root}assets/site/extra.css">'
            f'<script src="{root}assets/site/plugin-api.js"></script><script src="{root}assets/site/plugin-starter.js" defer></script>')


# ------------------------------------------------- Temas da comunidade ----
# themes/community/*.kdl entra na galeria do site. Cada arquivo é conferido com as regras
# do app (o mesmo leitor de KDL e a mesma checagem de cores de theme-builder-core.js, que
# segue src/theme/kdl.zig, color.zig, theme.zig e fx.zig) e com as da galeria (metadados,
# nome único, sem cópia de tema embutido). Um problema para o build com arquivo:linha:coluna.
# As mensagens são em inglês: quem lê é quem manda o pull request.
COMMUNITY_DIR = ROOT / "themes" / "community"
COMMUNITY_MAX_BYTES = 64 * 1024
COMMUNITY_LIMITS = {"name": 48, "author": 80, "desc": 240, "license": 64}
# As licenças abertas que a galeria aceita (identificadores SPDX), sozinhas ou juntas com AND / OR.
# Todas deixam usar e mudar o tema. A mesma lista está em theme-builder-core.js (`LICENSES`); o teste confere.
LICENSES = ["CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0", "CC-BY-3.0", "CC-BY-SA-3.0", "MIT", "MIT-0", "ISC", "0BSD",
            "BSD-2-Clause", "BSD-3-Clause", "Apache-2.0", "MPL-2.0", "Zlib", "Unlicense", "WTFPL", "EUPL-1.2",
            "GPL-2.0-only", "GPL-2.0-or-later", "GPL-3.0-only", "GPL-3.0-or-later", "LGPL-2.1-only", "LGPL-2.1-or-later",
            "LGPL-3.0-only", "LGPL-3.0-or-later", "AGPL-3.0-only", "AGPL-3.0-or-later"]
LICENSE_EXAMPLES = "CC0-1.0, CC-BY-4.0, CC-BY-SA-4.0, MIT, Apache-2.0, GPL-3.0-or-later…"
TOKENS = ["bg", "rail", "sidebar", "surface", "elevated", "overlay", "text", "muted", "faint", "accent",
          "accent-text", "border", "hover", "selected", "online", "idle", "dnd", "danger", "mention", "link",
          "code-bg", "bubble-self", "bubble-self-text", "bubble-other", "shadow"]
PREVIEWS = ["classic", "glass", "terminal", "bubbles", "zen", "mirror", "office", "desktop"]
# Os componentes que src/ui/root.zig desenha, mais os contêineres de src/theme/layout.zig.
COMPONENTS = {"guild-bar", "channel-list", "user-panel", "header", "tabs", "messages", "composer", "member-list",
              "status-bar", "label", "logo", "topbar", "crt", "shape", "rule", "window-controls", "starfield",
              "orbit", "aurora", "dunes", "topography", "radar", "spacer"}
PAINTED = {"shape", "rule", "starfield", "orbit", "aurora", "dunes", "topography", "radar", "window-controls"}
WEIGHTS = {"regular", "medium", "semibold", "bold", "italic"}


class ThemeProblem(Exception):
    def __init__(self, msg, line=0, col=0):
        super().__init__(msg)
        self.msg, self.line, self.col = msg, line, col


class KNode:
    __slots__ = ("name", "args", "props", "kids", "line", "col", "start", "end")

    def __init__(self, line, col, start):
        self.name, self.args, self.props, self.kids = "", [], {}, []
        self.line, self.col, self.start, self.end = line, col, start, start

    def s(self, key):
        v = self.props.get(key)
        return v if isinstance(v, str) else None


def kdl_strict(src):
    """O leitor de KDL de theme-builder-core.js (`parseKdl`), que segue o do app: erra onde o app erra."""
    st = {"i": 0, "line": 1, "ls": 0, "depth": 0}
    n = len(src)
    stop = set(' \t\r\n=;{}"()\\')

    def fail(msg):
        raise ThemeProblem(msg, st["line"], st["i"] - st["ls"] + 1)

    def peek():
        return src[st["i"]] if st["i"] < n else ""

    def adv():
        if st["i"] < n and src[st["i"]] == "\n":
            st["line"] += 1
            st["ls"] = st["i"] + 1
        st["i"] += 1

    def skip_space(nl):
        while st["i"] < n:
            ch = src[st["i"]]
            if ch in " \t\r" or (ch == "\n" and nl):
                adv()
            elif ch == "\\":
                adv()
                while peek() in (" ", "\t", "\r") and peek():
                    adv()
                if src.startswith("//", st["i"]):
                    while peek() not in ("\n", ""):
                        adv()
                if peek() == "\n":
                    adv()
            elif src.startswith("//", st["i"]):
                while peek() not in ("\n", ""):
                    adv()
            elif src.startswith("/*", st["i"]):
                d = 0
                while st["i"] < n:
                    if src.startswith("/*", st["i"]):
                        d += 1
                        adv()
                        adv()
                    elif src.startswith("*/", st["i"]):
                        d -= 1
                        adv()
                        adv()
                        if d == 0:
                            break
                    else:
                        adv()
                if d != 0:
                    fail("unclosed /* comment")
            else:
                break

    def number_start():
        ch = peek()
        if ch.isdigit() and ch.isascii():
            return True
        return ch in ("-", "+", ".") and st["i"] + 1 < n and src[st["i"] + 1] in "0123456789"

    def string():
        adv()
        out = []
        while True:
            if st["i"] >= n:
                fail("unterminated string")
            ch = src[st["i"]]
            if ch == '"':
                adv()
                return "".join(out)
            if ch == "\\":
                adv()
                r = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\", "/": "/"}.get(peek())
                if r is None:
                    fail("invalid escape")
                out.append(r)
                adv()
                continue
            out.append(ch)
            adv()

    def ident_or_string():
        if peek() == '"':
            return string()
        s = st["i"]
        while st["i"] < n and src[st["i"]] not in stop:
            st["i"] += 1
        if st["i"] == s:
            fail("expected a name")
        return src[s:st["i"]]

    def number():
        s = st["i"]
        while st["i"] < n and src[st["i"]] in "0123456789.+-_eE":
            st["i"] += 1
        txt = src[s:st["i"]].replace("_", "")
        if len(txt) > 64:
            fail("number too long")
        if not re.fullmatch(r"[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?", txt):
            fail("invalid number")
        return float(txt) if re.search(r"[.eE]", txt) else int(txt)

    def value():
        if peek() == '"':
            return string()
        if number_start():
            return number()
        w = ident_or_string()
        return {"true": True, "#true": True, "false": False, "#false": False, "null": None, "#null": None}.get(w, w)

    def node():
        nd = KNode(st["line"], st["i"] - st["ls"] + 1, st["i"])
        nd.name = ident_or_string()
        nd.end = st["i"]
        while True:
            skip_space(False)
            ch = peek()
            if ch in ("", "\n", ";", "}"):
                break
            if ch == "{":
                adv()
                nd.kids = node_list(True)
                nd.end = st["i"]
                return nd
            skip = False
            if src.startswith("/-", st["i"]):
                skip = True
                adv()
                adv()
                skip_space(False)
                if peek() == "{":
                    adv()
                    node_list(True)
                    continue
            s = st["i"]
            if peek() != '"' and not number_start():
                key = ident_or_string()
                if peek() == "=":
                    adv()
                    v = value()
                    if not skip:
                        nd.props[key] = v
                    nd.end = st["i"]
                    continue
                st["i"] = s
            elif peek() == '"':
                k2 = string()
                if peek() == "=":
                    adv()
                    v = value()
                    if not skip:
                        nd.props[k2] = v
                    nd.end = st["i"]
                    continue
                if not skip:
                    nd.args.append(k2)
                nd.end = st["i"]
                continue
            v = value()
            if not skip:
                nd.args.append(v)
            nd.end = st["i"]
        return nd

    def node_list(in_block):
        if st["depth"] >= 64:
            fail("too many nested blocks")
        st["depth"] += 1
        out = []
        while True:
            skip_space(True)
            while peek() == ";":
                adv()
                skip_space(True)
            if st["i"] >= n:
                if in_block:
                    fail("missing '}'")
                break
            if peek() == "}":
                if not in_block:
                    fail("unexpected '}'")
                adv()
                break
            skip = False
            if src.startswith("/-", st["i"]):
                skip = True
                adv()
                adv()
                skip_space(True)
            nd = node()
            if not skip:
                out.append(nd)
        st["depth"] -= 1
        return out

    return node_list(False)


def token_name(name):
    t = str(name).replace("_", "-")
    return t if t in TOKENS else None


def color_expr(expr, pal, toks, bare=False):
    """A expressão de cor do app (`eval` de color.zig, `evalColor` no criador): a cor, ou ValueError.
    Um leitor só para conferir e para calcular, então o que passa na checagem sempre dá uma cor."""
    s = str(expr)
    if bare and token_name(s.strip(" \t")):
        return toks[token_name(s.strip(" \t"))]
    pos = [0, 0]

    def bad():
        raise ValueError("invalid color expression")

    def skip():
        while pos[0] < len(s) and s[pos[0]] in " \t":
            pos[0] += 1

    def word():
        a = pos[0]
        while pos[0] < len(s) and re.match(r"[A-Za-z0-9\-_:@#.]", s[pos[0]]):
            pos[0] += 1
        return s[a:pos[0]]

    def expect(ch):
        skip()
        if pos[0] >= len(s) or s[pos[0]] != ch:
            bad()
        pos[0] += 1

    def num():
        skip()
        w = word()
        if not re.fullmatch(r"[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?", w):
            bad()
        return float(w)

    def atom(w):
        if w.startswith("#"):
            if not re.fullmatch(r"[0-9a-fA-F]+", w[1:]) or len(w) - 1 not in (3, 4, 6, 8):
                bad()
            return rgb(w)
        if w.startswith("@"):
            if not token_name(w[1:]):
                bad()
            return toks[token_name(w[1:])]
        if w.startswith("wal:"):
            if not re.fullmatch(r"\+?\d+", w[4:]) or int(w[4:]) >= 16:
                bad()
            return pal[int(w[4:])]
        if w in COLOR_WORDS:
            return COLOR_WORDS[w]
        bad()

    def expr():
        if pos[1] >= 16:
            bad()
        pos[1] += 1
        skip()
        w = word()
        if not w:
            bad()
        skip()
        if pos[0] < len(s) and s[pos[0]] == "(":
            pos[0] += 1
            a = expr()
            if w == "mix":
                expect(",")
                b = expr()
                expect(",")
                k = num()
                expect(")")
                out = mix(a, b, k)
            elif w in ("alpha", "lighten", "darken"):
                expect(",")
                k = num()
                expect(")")
                out = alpha(a, k) if w == "alpha" else mix(a, alpha(WHITE if w == "lighten" else BLACK, a[3]), k)
            else:
                bad()
        else:
            out = atom(w)
        pos[1] -= 1
        return out

    v = expr()
    skip()
    if pos[0] != len(s):
        bad()
    return v


COLOR_WORDS = {"black": BLACK, "white": WHITE, "transparent": (0, 0, 0, 0.0)}
_ANY_PAL = [BLACK] * 16
_ANY_TOKS = {t: BLACK for t in TOKENS}


def color_ok(expr, bare=False):
    """Só diz se a expressão vale (o mesmo leitor de `color_expr`)."""
    try:
        color_expr(expr, _ANY_PAL, _ANY_TOKS, bare)
        return True
    except ValueError:
        return False


def color_eval(expr, pal, toks):
    return color_expr(expr, pal, toks)


def split_colors(s):
    out, depth, start = [], 0, -1
    for i, ch in enumerate(s):
        if ch == "(":
            depth += 1
        if ch == ")" and depth > 0:
            depth -= 1
        if depth == 0 and ch in " \t":
            if start >= 0:
                out.append(s[start:i])
                start = -1
        elif start < 0:
            start = i
    if start >= 0:
        out.append(s[start:])
    return out


def theme_slug(s):
    """O nome do arquivo que o criador de temas dá (`slug` em theme-builder-core.js)."""
    t = unicodedata.normalize("NFD", str(s or "").lower())
    t = re.sub(r"[̀-ͯ]", "", t)
    t = re.sub(r"[^a-z0-9]+", "-", t).strip("-")[:48]
    return t or "my-theme"


def check_theme_nodes(nodes):
    """As regras de carregamento do app (`loadTheme`, `checkBox`, `checkLabel`, `checkLayout`)."""
    def bad(nd, msg):
        raise ThemeProblem(msg, nd.line, nd.col)

    def need(nd, key, msg, bare=True):
        v = nd.s(key)
        if v is not None and not color_ok(v, bare):
            bad(nd, msg)

    def gradient(nd, key):
        v = nd.s(key)
        if v is None:
            return
        parts = split_colors(v)
        if not 2 <= len(parts) <= 3:
            bad(nd, f"{key}: a gradient needs 2 or 3 colors")
        if not all(color_ok(p, True) for p in parts):
            bad(nd, f"{key}: invalid color in the gradient")

    def box(nd, is_style):
        gradient(nd, "gradient")
        if nd.s("pattern") is not None:
            if nd.s("pattern") not in ("dots", "lines", "grid", "diagonal"):
                bad(nd, "pattern: dots, lines, grid or diagonal")
            if nd.s("pattern-color") is None:
                bad(nd, "pattern needs pattern-color")
            need(nd, "pattern-color", "pattern-color is invalid")
        for k in ("grain", "vignette", "inner-shadow", "drop-shadow", "hover-bg"):
            need(nd, k, f"{k} is invalid")
        gradient(nd, "border-gradient")
        if not is_style:
            need(nd, "border", "border is invalid")
        for k in ("border-top", "border-right", "border-bottom", "border-left"):
            need(nd, k, f"{k} is invalid")
        if nd.s("corners") is not None and nd.s("corners") not in ("all", "left", "right", "top", "bottom"):
            bad(nd, "corners: all, left, right, top or bottom")

    def label(nd):
        need(nd, "color", "color is invalid")
        if nd.s("weight") is not None and nd.s("weight") not in WEIGHTS:
            bad(nd, "weight: regular, medium, semibold, bold or italic")
        for k in ("shadow", "outline"):
            need(nd, k, f"{k} is invalid")
        gradient(nd, "text-gradient")
        for sp in nd.kids:
            if sp.name != "span":
                bad(sp, f"only span goes inside a label, not {sp.name}")
            text = sp.args[0] if sp.args and isinstance(sp.args[0], str) else sp.s("text")
            if text is None:
                bad(sp, "span without text")
            if sp.s("weight") is not None and sp.s("weight") not in WEIGHTS:
                bad(sp, "weight: regular, medium, semibold, bold or italic")
            need(sp, "color", "invalid color in the span")

    def walk(nd):
        for ch in nd.kids:
            if ch.name not in COMPONENTS and ch.name not in CONTAINERS:
                bad(ch, f"unknown component: {ch.name}")
            bg = ch.s("bg")
            if bg is not None and not token_name(bg) and not color_ok(bg, True):
                bad(ch, "bg is invalid")
            box(ch, False)
            if ch.name == "label":
                label(ch)
            elif ch.name in PAINTED:
                for k in ("color", "color2", "color3", "fill", "dot", "ornament-color"):
                    need(ch, k, f"{k} is invalid")
            for k, v in ch.props.items():
                m = re.fullmatch(r"(c|cl|cd)-(.+)", k)
                if not m:
                    continue
                if not token_name(m.group(2)):
                    bad(ch, f"unknown color token in {k}")
                if not isinstance(v, str):
                    bad(ch, "the color must be a string")
                if not color_ok(v):
                    bad(ch, f"invalid color expression in {k}")
            if ch.name == "label":
                continue
            if ch.name not in CONTAINERS and ch.kids:
                bad(ch.kids[0], f"{ch.name} doesn't take children")
            walk(ch)

    layouts = [nd for nd in nodes if nd.name == "layout"]
    if not layouts:
        raise ThemeProblem("the theme needs a `layout` node")
    for nd in nodes:
        if nd.name == "options":
            for o in nd.kids:
                if not o.args:
                    bad(o, "option without a name")
                if not isinstance(o.args[0], str):
                    bad(o, "option name must be a string")
        elif nd.name == "palette":
            if nd.args and nd.args[0] == "wal":
                continue
            for a in nd.args[:16]:
                if not isinstance(a, str) or not re.fullmatch(r"#*([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})", a):
                    bad(nd, "invalid palette color")
        elif nd.name == "colors":
            for c in nd.kids:
                if not token_name(c.name):
                    bad(c, f"unknown color token: {c.name}")
                if not c.args:
                    bad(c, "missing color")
                if not isinstance(c.args[0], str):
                    bad(c, "the color must be a string")
                if not color_ok(c.args[0]):
                    bad(c, "invalid color expression")
        elif nd.name == "roles":
            for a in nd.args[:8]:
                if isinstance(a, str) and not color_ok(a):
                    bad(nd, "invalid role color")
        elif nd.name == "styles":
            for stl in nd.kids:
                if not stl.args:
                    bad(stl, "style without a name")
                if not isinstance(stl.args[0], str):
                    bad(stl, "style name must be a string")
                for k in ("bg", "border", "glow"):
                    need(stl, k, f"{k} is invalid", bare=False)
                box(stl, True)
        elif nd.name == "layout":
            if not nd.kids:
                bad(nd, "the layout is empty: it needs one root (row, column or stack)")
            walk(nd)


def theme_modes(nodes):
    """As cores resolvidas nos dois modos, com as opções no padrão (como `load_themes`)."""
    top = {n.name: n for n in nodes}
    on = set()
    if "options" in top:
        on = {o.args[0] for o in top["options"].kids if o.args and o.props.get("default", True) is not False}
    pal = [rgb(x) for x in FALLBACK]
    if "palette" in top and top["palette"].args and top["palette"].args[0] != "wal":
        pal = [rgb(x.lstrip("#")) for x in top["palette"].args[:16]] + pal[len(top["palette"].args[:16]):]
    out = {}
    for mode in ("dark", "light"):
        toks = default_tokens(pal, mode)
        for nd in nodes:
            if nd.name != "colors" or nd.props.get("mode", mode) != mode:
                continue
            if "when" in nd.props and nd.props["when"] not in on:
                continue
            if "unless" in nd.props and nd.props["unless"] in on:
                continue
            for c in nd.kids:
                try:
                    toks[token_name(c.name)] = color_eval(c.args[0], pal, toks)
                except (ValueError, KeyError, IndexError, TypeError):
                    raise ThemeProblem(f"{c.name}: couldn't work out the color {c.args[0]!r} in {mode} mode", c.line, c.col)
        out[mode] = toks
    return out


def same_colors(a, b):
    return all(all(abs(a[k][i] - b[k][i]) <= 2.01 for i in range(3)) and abs(a[k][3] - b[k][3]) <= 0.01 for k in TOKENS)


def layout_key(nodes):
    """O layout como árvore (nomes, argumentos e propriedades), sem comentários nem espaços:
    um comentário a mais não faz de um tema embutido renomeado um tema novo."""
    def value(v):
        if isinstance(v, bool) or v is None or isinstance(v, str):
            return v
        return float(v)

    def node(n):
        return [n.name, [value(a) for a in n.args], sorted((k, value(v)) for k, v in n.props.items()), [node(k) for k in n.kids]]
    return json.dumps([node(n) for n in nodes if n.name == "layout"], ensure_ascii=False)


def check_community_file(path, builtins, src_bytes):
    """Um arquivo de themes/community/. Devolve os dados do cartão da galeria ou levanta ThemeProblem."""
    stem = path.stem
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,47}", stem):
        raise ThemeProblem("the file name must be lowercase letters, digits and hyphens, up to 48 (the builder names it after the theme)")
    if stem in builtins:
        raise ThemeProblem(f"{stem} is a built-in theme: a file with this name would replace it in the app. Pick another name")
    if len(src_bytes) > COMMUNITY_MAX_BYTES:
        raise ThemeProblem(f"the file has {len(src_bytes)} bytes; the limit is {COMMUNITY_MAX_BYTES}")
    try:
        src = src_bytes.decode("utf-8")
    except UnicodeDecodeError:
        raise ThemeProblem("the file is not UTF-8")
    if src.startswith("\ufeff"):
        raise ThemeProblem("the file starts with a byte order mark (BOM), which the app reads as part of the first line: save it as UTF-8 without BOM", 1, 1)
    if "\x00" in src:
        raise ThemeProblem("the file has a NUL byte")
    nodes = kdl_strict(src)
    check_theme_nodes(nodes)

    heads = [nd for nd in nodes if nd.name == "theme"]
    if not heads:
        raise ThemeProblem('missing the `theme` node with the metadata: theme "Name" author=… description-en=… license=…')
    if len(heads) > 1:
        raise ThemeProblem("only one `theme` node, please", heads[1].line, heads[1].col)
    th = heads[0]
    for k in ("mode", "when", "unless"):
        if k in th.props:
            raise ThemeProblem(f"the `theme` node can't depend on {k}=", th.line, th.col)
    L = COMMUNITY_LIMITS

    def text(value, what, limit, required=True):
        if value is None or (isinstance(value, str) and not value.strip()):
            if required:
                raise ThemeProblem(f"missing {what} on the `theme` node", th.line, th.col)
            return ""
        if not isinstance(value, str):
            raise ThemeProblem(f"{what} must be a string", th.line, th.col)
        if len(value) > limit:
            raise ThemeProblem(f"{what} has {len(value)} characters; the limit is {limit}", th.line, th.col)
        if re.search(r"[\x00-\x1f\x7f]", value):
            raise ThemeProblem(f"{what} can't have line breaks or control characters", th.line, th.col)
        return value

    title = text(th.args[0] if th.args else None, 'the name (theme "Name")', L["name"])
    if theme_slug(title) != stem:
        raise ThemeProblem(f'the file for theme "{title}" must be named {theme_slug(title)}.kdl', th.line, th.col)
    author = text(th.props.get("author"), "author=", L["author"])
    desc = text(th.props.get("description"), "description=", L["desc"], required=False)
    desc_en = text(th.props.get("description-en"), "description-en=", L["desc"], required=False)
    if not desc and not desc_en:
        raise ThemeProblem("missing a description: description-en=… (English) and/or description=… (Portuguese)", th.line, th.col)
    for name, b in builtins.items():
        if (desc and desc in b["descs"]) or (desc_en and desc_en in b["descs"]):
            raise ThemeProblem(f"the description is still the one from the built-in theme {name}: describe your theme", th.line, th.col)
    lic = text(th.props.get("license"), "license=", L["license"])
    why = license_problem(lic)
    if why:
        raise ThemeProblem(f'license="{lic}": {why}', th.line, th.col)
    preview = th.props.get("preview", "classic")
    if preview not in PREVIEWS:
        raise ThemeProblem(f"preview= must be one of: {', '.join(PREVIEWS)}", th.line, th.col)

    try:
        modes = theme_modes(nodes)
    except (ValueError, KeyError, IndexError, TypeError):
        raise ThemeProblem("couldn't work out the theme's colors (palette or color blocks)")
    lay = layout_key(nodes)
    for name, b in builtins.items():
        if lay == b["layout"] and same_colors(modes["dark"], b["modes"]["dark"]) and same_colors(modes["light"], b["modes"]["light"]):
            raise ThemeProblem(f"this is the built-in theme {name} with another name: change its colors or its layout")
    return {"name": stem, "title": title, "author": author, "desc": desc, "descEn": desc_en, "license": lic,
            "preview": preview, "src": src, "layout": lay, "modes": modes,
            "swatches": [css(modes["dark"][k]) for k in ("rail", "sidebar", "bg", "elevated", "accent", "mention", "link", "text")]}


def builtin_fingerprints():
    out = {}
    for name in THEMES:
        src = (ROOT / "themes" / f"{name}.kdl").read_text(encoding="utf-8")
        nodes = kdl_strict(src)
        head = next(n for n in nodes if n.name == "theme")
        descs = {head.s("description"), head.s("description-en")} - {None, ""}
        out[name] = {"layout": layout_key(nodes), "modes": theme_modes(nodes), "descs": descs}
    return out


def license_problem(lic):
    """O que falta em `license=`, ou None. Um identificador da lista, ou vários com AND / OR."""
    parts = lic.split(" ")
    ids, ops = parts[0::2], parts[1::2]
    if len(parts) % 2 == 0 or len(ids) > 5 or any(o not in ("AND", "OR") for o in ops) or not all(ids):
        return f"use one license identifier, or a few joined with AND / OR, such as {LICENSE_EXAMPLES}"
    for i in ids:
        if i in LICENSES:
            continue
        same = [x for x in LICENSES if x.lower() == i.lower()]
        if same:
            return f"write {i} as {same[0]}"
        return (f"{i} isn't one of the open licenses the gallery takes ({LICENSE_EXAMPLES}). "
                "The full list is in the themes guide, \"Sharing your theme\"")
    return None


def check_community(folder=COMMUNITY_DIR):
    """Todos os temas da pasta: (temas, problemas). Cada problema já vem como `arquivo:linha:coluna: texto`."""
    themes, problems = [], []
    if not folder.exists():
        return themes, problems
    builtins = builtin_fingerprints()
    try:
        shown = folder.relative_to(ROOT)
    except ValueError:
        shown = folder
    seen = {}
    for f in sorted(folder.iterdir()):
        where = f"{shown}/{f.name}"
        if f.name.startswith(".") or re.fullmatch(r"README(\.[a-zA-Z-]+)?\.md", f.name):
            continue
        if f.is_dir() or f.suffix != ".kdl":
            problems.append(f"{where}: only .kdl theme files go in this folder (no images, fonts or other files)")
            continue
        try:
            th = check_community_file(f, builtins, f.read_bytes())
        except ThemeProblem as e:
            pos = f":{e.line}:{e.col}" if e.line else ""
            problems.append(f"{where}{pos}: {e.msg}")
            continue
        key = th["title"].casefold()
        if key in seen:
            problems.append(f"{where}: the name \"{th['title']}\" is already used by {seen[key]}")
            continue
        for other in themes:
            if th["layout"] == other["layout"] and same_colors(th["modes"]["dark"], other["modes"]["dark"]) and same_colors(th["modes"]["light"], other["modes"]["light"]):
                problems.append(f"{where}: same colors and layout as {other['name']}.kdl")
                break
        else:
            seen[key] = f.name
            themes.append(th)
    return themes, problems


# ------------------------------------------------------------- Páginas ----
GUIDE = [
    ("Start", "Comece", [
        ("getting-started", "Getting started", "Primeiros passos"),
        ("account", "Connect your account", "Conectar sua conta"),
        ("vs-discord", "What Discord doesn't have", "O que o Discord não tem"),
    ]),
    ("Use", "Use", [
        ("features", "Feature tour", "Tour dos recursos"),
        ("shortcuts", "Shortcuts and CLI", "Atalhos e linha de comando"),
        ("settings", "Settings and files", "Configurações e arquivos"),
        ("voice", "Voice calls", "Chamadas de voz"),
    ]),
    ("Customize", "Personalize", [
        ("themes", "Writing themes", "Escrevendo temas"),
        ("theme-gallery", "Built-in themes", "Temas embutidos"),
        ("plugins", "Lua plugins", "Plugins em Lua"),
        ("plugin-directory", "Plugin directory", "Diretório de plugins"),
        ("plugin-starter", "Plugin starter", "Gerador de plugin"),
        ("lsp", "Code diagnostics", "Erros no código"),
    ]),
    ("Internals", "Por dentro", [
        ("architecture", "Architecture", "Arquitetura"),
        ("performance", "Performance", "Desempenho"),
        ("privacy", "Privacy and security", "Privacidade e segurança"),
    ]),
    ("Project", "Projeto", [
        ("status", "Status and roadmap", "Estado e roteiro"),
        ("contributing", "Contributing", "Contribuir"),
    ]),
]
FLAT = [p for _, _, ps in GUIDE for p in ps]


def t(lang, en, pt):
    return en if lang == "en" else pt


def page_url(lang, slug=None):
    """Caminho a partir da raiz do site."""
    prefix = "" if lang == "en" else "pt/"
    return f"{prefix}guide/{slug}.html" if slug else (prefix or "./")


def builder_url(lang):
    return "theme-builder.html" if lang == "en" else "pt/theme-builder.html"


def community_url(lang):
    return "community-themes.html" if lang == "en" else "pt/community-themes.html"


def root_of(path):
    return "../" * path.count("/")


def rel(path_from, target):
    return root_of(path_from) + target


# O topo do site: a marca, dois grupos com menu (Temas, Por que larperCord), o guia, a
# demonstração (quando o build dela existe) e, à direita, GitHub, Ko-fi e idioma em botões
# pequenos. Sem JavaScript cada grupo é um link e o menu abre com o mouse ou o Tab; com ele,
# vira um botão com aria-expanded (site.js). Abaixo de 1100 px tudo vai para uma gaveta.
KOFI = "https://ko-fi.com/M7E72A1EGZ"
NAV_IC = {
    "caret": '<path d="m7 10 5 5 5-5"/>',
    "star": '<path d="m12 3.6 2.5 5.2 5.7.8-4.1 4 1 5.7-5.1-2.7-5.1 2.7 1-5.7-4.1-4 5.7-.8z"/>',
    "gh": '<path class="fill" d="M12 2.2a10 10 0 0 0-3.2 19.5c.5.1.7-.2.7-.5v-1.8c-2.8.6-3.4-1.2-3.4-1.2-.5-1.2-1.1-1.5-1.1-1.5-.9-.6.1-.6.1-.6 1 .1 1.5 1 1.5 1 .9 1.5 2.4 1.1 3 .8.1-.7.4-1.1.6-1.3-2.2-.3-4.6-1.1-4.6-5 0-1.1.4-2 1-2.7-.1-.3-.4-1.3.1-2.7 0 0 .8-.3 2.8 1a9.6 9.6 0 0 1 5 0c1.9-1.3 2.8-1 2.8-1 .5 1.4.2 2.4.1 2.7.6.7 1 1.6 1 2.7 0 3.9-2.4 4.7-4.6 5 .4.3.7.9.7 1.9v2.8c0 .3.2.6.7.5A10 10 0 0 0 12 2.2"/>',
    "cup": '<path d="M5 9h12v4.5A5.5 5.5 0 0 1 11.5 19h-1A5.5 5.5 0 0 1 5 13.5zM17 10.5h1.2a2.6 2.6 0 0 1 0 5.2H16.6M9 3.8c-.8.9.8 1.6 0 2.6M12.6 3.8c-.8.9.8 1.6 0 2.6"/>',
    "globe": '<path d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM3.5 9h17M3.5 15h17M12 3c-2.6 2.6-3.6 5.6-3.6 9s1 6.4 3.6 9M12 3c2.6 2.6 3.6 5.6 3.6 9s-1 6.4-3.6 9"/>',
    "menu": '<path d="M4 7h16M4 12h16M4 17h10"/>',
    "close": '<path d="M6 6l12 12M18 6 6 18"/>',
    "play": '<path class="fill" d="M8 5.5v13l10.5-6.5z"/>',
    "swatch": '<path d="M12 21a9 9 0 1 1 9-9c0 2.5-2 3-3.5 3H15a2 2 0 0 0-1.4 3.4c.6.6.4 2.6-1.6 2.6z"/><circle class="fill" cx="7.5" cy="11" r="1.4"/><circle class="fill" cx="10.5" cy="7" r="1.4"/><circle class="fill" cx="15.5" cy="7.5" r="1.4"/>',
    "brush": '<path d="M14.5 4.5 19.5 9.5 11 18l-5-5zM6 13l-2.5 6.5L10 17M16.5 2.5l5 5"/>',
    "users": '<path d="M16 20v-1.5a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4V20M9.5 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zM21 20v-1.5a4 4 0 0 0-3-3.8M15.5 4.2a3.5 3.5 0 0 1 0 6.6"/>',
    "layout": '<path d="M4 4h16v16H4zM9.5 4v16M9.5 10H20"/>',
    "spark": '<path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M18 6l-2.5 2.5M8.5 15.5 6 18"/>',
    "versus": '<path d="M5 5l4 14 4-14M14.5 17.5c.8.9 2 1.5 3.2 1.5 1.8 0 3-1 3-2.5 0-3.6-6-2.4-6-6 0-1.4 1.2-2.5 3-2.5 1.1 0 2.1.4 2.8 1.2"/>',
    "gauge": '<path d="M4.5 18a9 9 0 1 1 15 0M12 13l4-5"/><circle class="fill" cx="12" cy="13" r="1.6"/>',
    "book": '<path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v15H6.5A2.5 2.5 0 0 0 4 20.5zM4 20.5A2.5 2.5 0 0 0 6.5 23H20M8 7.5h8"/>',
}


def nav_icon(name, cls="nav-svg"):
    return f'<svg class="{cls}" viewBox="0 0 24 24" aria-hidden="true" focusable="false">{NAV_IC[name]}</svg>'


def topnav(lang, path, alt_path, kind, slug):
    """O cabeçalho de todas as páginas."""
    e = html.escape
    home = rel(path, page_url(lang) if lang == "pt" else "") or "./"
    anchor_home = home if kind != "landing" else ""
    other = "pt" if lang == "en" else "en"
    groups = [
        ("themes", t(lang, "Themes", "Temas"), f"{anchor_home}#themes", [
            ("swatch", t(lang, "Built-in themes", "Temas embutidos"), t(lang, "11 themes, each in light and dark", "11 temas, cada um em claro e escuro"), f"{anchor_home}#themes", False),
            ("brush", t(lang, "Theme builder", "Criador de temas"), t(lang, "Colors, layout and fonts, live", "Cores, layout e fontes, ao vivo"), rel(path, builder_url(lang)), kind == "builder"),
            ("users", t(lang, "Community themes", "Temas da comunidade"), t(lang, "Made and sent by people who use it", "Feitos e mandados por quem usa"), rel(path, community_url(lang)), kind == "community"),
            ("layout", t(lang, "Layout playground", "Playground de layout"), t(lang, "Edit a layout and watch it move", "Edite um layout e veja mudar"), f"{anchor_home}#playground", False),
        ]),
        ("why", t(lang, "Why larperCord", "Por que larperCord"), f"{anchor_home}#features", [
            ("spark", t(lang, "Features", "Recursos"), t(lang, "Voice, plugins, offline search…", "Voz, plugins, busca offline…"), f"{anchor_home}#features", False),
            ("versus", "vs. Discord", t(lang, "What it does that the official app doesn't", "O que ele faz e o app oficial não"), rel(path, page_url(lang, "vs-discord")), slug == "vs-discord"),
            ("gauge", t(lang, "The numbers", "Os números"), t(lang, "About 130 MB of RAM, 0% CPU at idle", "Cerca de 130 MB de RAM, 0% de CPU parado"), f"{anchor_home}#numbers", False),
        ]),
    ]
    items = []
    for gid, label, href, links in groups:
        current = any(c for *_, c in links)
        menu = []
        for icon, name, desc, url, cur in links:
            menu.append(f'<li><a class="nav-mi" href="{url}"{" aria-current=page" if cur else ""}>{nav_icon(icon, "nav-mi-ic")}'
                        f'<span class="nav-mi-t"><b>{e(name)}</b><small>{e(desc)}</small></span></a></li>')
        items.append(f'<li class="nav-item nav-group" data-nav-group>'
                     f'<a class="nav-trig" href="{href}" data-nav-trig{" data-current" if current else ""}>{e(label)}{nav_icon("caret", "nav-caret")}</a>'
                     f'<div class="nav-menu" id="nav-m-{gid}"><p class="nav-sect">{e(label)}</p><ul>{"".join(menu)}</ul></div></li>')
    guide_cur = kind == "guide" and slug != "vs-discord"
    items.append(f'<li class="nav-item"><a class="nav-link" href="{rel(path, page_url(lang, "getting-started"))}"{" aria-current=page" if guide_cur else ""}>'
                 f'{nav_icon("book", "nav-svg nav-only-drawer")}{t(lang, "Guide", "Guia")}</a></li>')
    if TRY_SIZE:
        try_url = rel(path, "try/" if lang == "en" else "pt/try/")
        items.append(f'<li class="nav-item"><a class="nav-try" href="{try_url}"{" aria-current=page" if kind == "try" else ""}>'
                     f'<i class="nav-try-dot" aria-hidden="true"></i>{nav_icon("play")}{t(lang, "Try in browser", "Testar no navegador")}</a></li>')
    lang_href = rel(path, alt_path.removesuffix("index.html")) or "./"
    lang_attrs = f'hreflang="{"pt-BR" if other == "pt" else "en"}" lang="{"pt-BR" if other == "pt" else "en"}"'
    other_label = "Português" if lang == "en" else "English"
    star = t(lang, "Star on GitHub", "Dar estrela no GitHub")
    coffee = t(lang, "Buy me a coffee on Ko-fi", "Me pague um café no Ko-fi")
    # Na gaveta (telas estreitas), os mesmos três com o nome por extenso.
    extra = (f'<div class="nav-extra">'
             f'<a class="nav-xl" href="{REPO}" rel="noopener">{nav_icon("gh")}<span>{star}</span>{nav_icon("star", "nav-svg nav-star")}</a>'
             f'<a class="nav-xl nav-xl-kofi" href="{KOFI}" target="_blank" rel="noopener">{nav_icon("cup")}<span>{coffee}</span></a>'
             f'<a class="nav-xl" href="{lang_href}" {lang_attrs}>{nav_icon("globe")}<span>{other_label}</span></a></div>')
    return f'''<header class="topnav" data-topnav>
  <a class="brand" href="{home}" aria-label="larperCord">{mascot("n")}<span data-brand>larperCord</span></a>
  <nav class="nav" id="site-nav" aria-label="{t(lang, 'Main', 'Principal')}" data-nav>
    <ul class="nav-list">{"".join(items)}</ul>
    {extra}
  </nav>
  <div class="nav-actions">
    <a class="nav-ic nav-gh" href="{REPO}" rel="noopener" aria-label="{star}" title="{star}">{nav_icon("gh")}{nav_icon("star", "nav-svg nav-star")}</a>
    <a class="nav-ic nav-kofi" href="{KOFI}" target="_blank" rel="noopener" aria-label="{coffee}" title="{coffee}">{nav_icon("cup")}</a>
    <a class="nav-lang" href="{lang_href}" {lang_attrs} title="{other_label}">{nav_icon("globe")}<span aria-hidden="true">{other.upper()}</span><span class="sr-only">{other_label}</span></a>
    <button type="button" class="nav-burger" data-nav-burger aria-controls="site-nav" aria-expanded="false" aria-label="{t(lang, 'Menu', 'Menu')}">{nav_icon("menu", "nav-svg nav-open-ic")}{nav_icon("close", "nav-svg nav-close-ic")}</button>
  </div>
</header>
<div class="nav-scrim" data-nav-scrim hidden></div>'''


def shell(lang, path, alt_path, title, desc, body, kind, slug=None, head=""):
    root = root_of(path)
    return f'''<!doctype html>
<html lang="{'en' if lang == 'en' else 'pt-BR'}" data-lang="{lang}" data-root="{root}" data-page="{kind}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(desc, quote=True)}">
<meta name="color-scheme" content="dark light">
<link rel="canonical" href="{BASE_URL}{path.removesuffix('index.html')}">
<link rel="alternate" hreflang="en" href="{BASE_URL}{(path if lang == 'en' else alt_path).removesuffix('index.html')}">
<link rel="alternate" hreflang="pt-BR" href="{BASE_URL}{(alt_path if lang == 'en' else path).removesuffix('index.html')}">
<meta property="og:type" content="website">
<meta property="og:title" content="{html.escape(title, quote=True)}">
<meta property="og:description" content="{html.escape(desc, quote=True)}">
<meta property="og:image" content="{BASE_URL}assets/og.png">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" type="image/svg+xml" href="{root}assets/icon-live.svg">
<link rel="icon" type="image/png" sizes="32x32" href="{root}assets/icon-32.png">
<link rel="apple-touch-icon" href="{root}assets/icon-180.png">
<link rel="preload" href="{root}assets/fonts/departure-mono.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="{root}assets/fonts/jetbrains-mono-400.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="{root}assets/site/site.css">{head}
<script src="{root}assets/site/data.js"></script>
<script src="{root}assets/site/boot.js"></script>
</head>
<body>
<a class="skip" href="#main">{t(lang, 'Skip to content', 'Pular para o conteúdo')}</a>
{topnav(lang, path, alt_path, kind, slug)}
{body}
<footer class="statusbar" aria-label="{t(lang, 'Page theme', 'Tema da página')}">
  <button type="button" class="buddy" data-next-theme aria-label="{t(lang, 'Next theme', 'Próximo tema')}">{mascot("b")}</button>
  <i class="sb-prog" aria-hidden="true"></i>
  <span class="sb-dot" aria-hidden="true"></span>
  <button type="button" class="sb-btn" data-next-theme title="F2"><span data-theme-name>larper</span></button>
  <button type="button" class="sb-btn" data-toggle-mode><span data-mode-name>dark</span></button>
  <span class="sb-spacer"></span>
  <button type="button" class="sb-btn sb-keys" data-open-palette><kbd>Ctrl</kbd><kbd>K</kbd> {t(lang, 'palette', 'paleta')}</button>
  <span class="sb-keys sb-hint"><kbd>F2</kbd> {t(lang, 'next theme', 'próximo tema')}</span>
  <a class="sb-btn sb-kofi" href="{KOFI}" target="_blank" rel="noopener">&#9829; ko-fi</a>
  <span class="sb-pos" data-scroll-pos></span>
  <time class="sb-clock" data-clock></time>
</footer>
<div class="fx-layer" aria-hidden="true"></div>
<script src="{root}assets/site/site.js"></script>
</body>
</html>
'''


def external_sources(slug, lang):
    """Guias que moram fora de site/: o .md de lá é a fonte."""
    if slug == "plugins":
        return ROOT / "docs" / ("plugins.md" if lang == "en" else "plugins.pt-BR.md")
    if slug == "lsp":
        return ROOT / "docs" / ("lsp.md" if lang == "en" else "lsp.pt-BR.md")
    if slug == "themes":
        return ROOT / "themes" / ("README.md" if lang == "en" else "README.pt-BR.md")
    return None


def rewriter(lang, slug, path):
    def rewrite(url):
        # Link para o próprio site (os .md também são lidos no GitHub): vira relativo aqui.
        if url.startswith(BASE_URL):
            return rel(path, url[len(BASE_URL):])
        if re.match(r"(?:https?:|mailto:|#)", url):
            return url
        target, _, frag = url.partition("#")
        frag = f"#{frag}" if frag else ""
        name = Path(target).name
        if name.startswith("guide:"):
            return rel(path, page_url(lang, name[6:])) + frag
        if slug == "themes" and name.endswith(".kdl"):
            return f"{REPO}/blob/main/themes/{name}"
        if slug == "plugins" and target.rstrip("/").startswith("plugins"):
            return f"{REPO}/tree/main/docs/{target}"
        return f"{REPO}/blob/main/{target}"
    return rewrite


def gallery_md(lang, themes):
    out = [t(lang, "# Built-in themes", "# Temas embutidos"), "",
           t(lang, "Generated from `themes/*.kdl`. Every theme has a light and a dark mode, and the options below show up in Settings → Appearance.",
             "Gerado a partir de `themes/*.kdl`. Todo tema tem modo claro e escuro, e as opções abaixo aparecem em Configurações → Aparência."), "",
           t(lang, "Themes made by other people are in the [community gallery](community:), and [Sharing your theme](page:themes#sharing-your-theme) explains how to add yours.",
             "Os temas feitos por outras pessoas estão na [galeria da comunidade](community:), e [Compartilhar seu tema](page:themes#compartilhar-seu-tema) explica como mandar o seu."), ""]
    for name in THEMES:
        th = themes[name]
        out += [f"## {name}", "", th["descEn"] if lang == "en" else th["desc"], ""]
        out.append(f"![{name}](shot:{name})")
        out.append("")
        if th["options"]:
            out += [t(lang, "| Option | Default | What it does |", "| Opção | Padrão | O que faz |"), "|---|---|---|"]
            for o in th["options"]:
                label = o["labelEn"] if lang == "en" else o["label"]
                desc = o["descEn"] if lang == "en" else o["desc"]
                state = t(lang, "on" if o["default"] else "off", "ligada" if o["default"] else "desligada")
                out.append(f"| {label} (`{o['name']}`) | {state} | {desc} |")
            out.append("")
        out += [t(lang, f"Source: [`{name}.kdl`]({REPO}/blob/main/themes/{name}.kdl) · [open it in the theme builder](builder:{name})",
                  f"Fonte: [`{name}.kdl`]({REPO}/blob/main/themes/{name}.kdl) · [abrir no criador de temas](builder:{name})"), ""]
    return "\n".join(out)


def build_guide(lang, themes):
    index = []
    plugin_api = load_plugin_api()
    for gi, (slug, ten, tpt) in enumerate(FLAT):
        path = page_url(lang, slug)
        alt = page_url("pt" if lang == "en" else "en", slug)
        title = ten if lang == "en" else tpt
        if slug == "theme-gallery":
            src = gallery_md(lang, themes)
        elif slug == "plugin-directory":
            src = plugins_md(lang, plugin_api)
        else:
            f = external_sources(slug, lang) or SITE / "guide" / lang / f"{slug}.md"
            if not f.exists():
                f = external_sources(slug, "en") or SITE / "guide" / "en" / f"{slug}.md"
            src = f.read_text(encoding="utf-8")
        # A linha de idioma dos .md não faz sentido aqui: o site tem a dele.
        src = re.sub(r"^(?:\*\*English\*\*|\[English\]\(.*?\)) · .*$", "", src, flags=re.M)
        # Pedaços que saem do código do app: {{keys}}, {{keys:vim}} e o gerador de plugin.
        embeds = []

        def directive(m, lang=lang, path=path, embeds=embeds):
            name = m.group(1)
            if name in ("keys", "keys:vim"):
                return keys_md(lang, "vim" if name == "keys:vim" else "all")
            if name == "starter":
                embeds.append(starter_embed(lang, path))
                return f"@@embed-{len(embeds) - 1}@@"
            raise SystemExit(f"{slug}: diretiva desconhecida {{{{{name}}}}}")

        src = re.sub(r"^\{\{([\w:-]+)\}\}$", directive, src, flags=re.M)
        base_rw = rewriter(lang, slug, path)

        def rw(url, base_rw=base_rw, path=path):
            if url.startswith("#"):
                # Os .md de fora têm âncoras no estilo do GitHub, com acento.
                return "#" + slugify(url[1:])
            if url.startswith("shot:"):
                return rel(path, f"assets/shots/{lang}/{url[5:]}.webp")
            if url.startswith("home:"):
                return rel(path, "pt/index.html" if lang == "pt" else "index.html") + "#" + url[5:]
            if url.startswith("builder:"):
                return rel(path, builder_url(lang)) + "#base=" + url[8:]
            if url.startswith("community:"):
                return rel(path, community_url(lang))
            if url.startswith("page:"):
                name, _, frag = url[5:].partition("#")
                return rel(path, page_url(lang, name)) + (f"#{frag}" if frag else "")
            return base_rw(url)

        lead = ""
        m = re.search(r"^#\s+.*$", src, re.M)
        body_md = src[m.end():] if m else src
        content, heads = markdown(body_md, rw)
        for n, block in enumerate(embeds):
            content = content.replace(f"<p>@@embed-{n}@@</p>", block)
        content = content.replace("@@ROOT@@", root_of(path))
        side = []
        for gten, gpt, pages in GUIDE:
            links = "".join(
                f'<a href="{rel(path, page_url(lang, s))}"{" aria-current=page" if s == slug else ""}>{te if lang == "en" else tp}</a>'
                for s, te, tp in pages)
            side.append(f'<div class="side-group"><p>{gten if lang == "en" else gpt}</p>{links}</div>')
        toc = "".join(f'<a class="l{lv}" href="#{hid}">{inline(text, lambda u: u)}</a>' for lv, text, hid in heads if lv in (2, 3))
        prev_ = FLAT[gi - 1] if gi else None
        next_ = FLAT[gi + 1] if gi + 1 < len(FLAT) else None
        pager = '<nav class="pager">'
        if prev_:
            pager += f'<a href="{rel(path, page_url(lang, prev_[0]))}"><small>{t(lang, "Previous", "Anterior")}</small>{prev_[1] if lang == "en" else prev_[2]}</a>'
        else:
            pager += "<span></span>"
        if next_:
            pager += f'<a class="next" href="{rel(path, page_url(lang, next_[0]))}"><small>{t(lang, "Next", "Próximo")}</small>{next_[1] if lang == "en" else next_[2]}</a>'
        pager += "</nav>"
        edit = f"{REPO}/blob/main/" + str((external_sources(slug, lang) or SITE / "guide" / lang / f"{slug}.md").relative_to(ROOT)) if slug != "theme-gallery" else f"{REPO}/tree/main/themes"
        if slug == "plugin-directory":
            edit = f"{REPO}/tree/main/docs/plugins"
        body = f'''<div class="guide">
<aside class="side" aria-label="{t(lang, 'Guide pages', 'Páginas do guia')}">
<button type="button" class="side-search" data-open-palette>{t(lang, 'Search the guide', 'Buscar no guia')}<span><kbd>Ctrl</kbd><kbd>K</kbd></span></button>
{''.join(side)}
</aside>
<main id="main" class="prose">
<h1>{html.escape(title)}</h1>
{content}
<p class="edit"><a href="{edit}" rel="noopener">{t(lang, 'Source of this page on GitHub', 'Fonte desta página no GitHub')}</a></p>
{pager}
</main>
<nav class="toc" aria-label="{t(lang, 'On this page', 'Nesta página')}"><p>{t(lang, 'On this page', 'Nesta página')}</p>{toc}</nav>
</div>'''
        plain = re.sub(r"<[^>]+>", " ", content)
        desc = " ".join(plain.split())[:155]
        full = f"{title} · larperCord"
        write(path, shell(lang, path, alt, full, desc, body, "guide", slug))
        index.append({"t": title, "s": t(lang, "Guide", "Guia"), "u": path})
        # Cada seção entra na busca com um trecho do que vem depois do título.
        for lv, text, hid in heads:
            if lv > 3:
                continue
            at = content.find(f'id="{hid}"')
            snippet = " ".join(re.sub(r"<[^>]+>", " ", content[at:at + 900]).split())
            snippet = snippet[len(text) + 12:220] if at >= 0 else ""
            index.append({"t": re.sub(r"[*]", "", text), "s": title, "u": f"{path}#{hid}", "x": snippet})
    return index


# A demonstração no navegador (zig build web, ver tools/web/README.md; no site, o
# workflow pages.yml). A página e o link da inicial só entram quando o build inteiro
# dela está em docs/try/: sem ele, nada aparece e as páginas de uma geração anterior saem.
TRY_SIZE = None
TRY_PAGES = ["try/index.html", "pt/try/index.html"]


def wasm_shared_memory(data):
    """A memória do wasm é compartilhada? Só com threads, e aí a página precisaria de
    SharedArrayBuffer, que pede os cabeçalhos COOP/COEP que o GitHub Pages não manda."""
    pos = 8

    def leb():
        nonlocal pos
        n = shift = 0
        while True:
            byte = data[pos]
            pos += 1
            n |= (byte & 0x7F) << shift
            shift += 7
            if byte < 0x80:
                return n

    def limits():
        nonlocal pos
        flags = data[pos]
        pos += 1
        leb()
        if flags & 1:
            leb()
        if flags & 8:
            leb()
        return bool(flags & 2)

    if data[:4] != b"\0asm":
        raise ValueError("não é um wasm")
    while pos < len(data):
        section = data[pos]
        pos += 1
        size = leb()
        end = pos + size
        if section == 2:  # importações: módulo, nome e o tipo do que vem de fora
            for _ in range(leb()):
                for _ in range(2):
                    n = leb()
                    pos += n
                kind = data[pos]
                pos += 1
                if kind == 0:  # função
                    leb()
                elif kind == 1:  # tabela
                    pos += 1
                    limits()
                elif kind == 2:  # memória
                    if limits():
                        return True
                elif kind == 3:  # global
                    pos += 2
                elif kind == 4:  # tag
                    pos += 1
                    leb()
                else:
                    raise ValueError(f"importação de tipo {kind}")
        elif section == 5:  # memórias do próprio módulo
            for _ in range(leb()):
                if limits():
                    return True
        pos = end
    return False


def try_size():
    """O tamanho do download da demonstração, ou None quando o build não serve para o site."""
    d = OUT / "try"
    js, wasm, data = (d / f"larpercord.{ext}" for ext in ("js", "wasm", "data"))
    if not js.exists() and not wasm.exists():
        return None
    missing = [f.name for f in (js, wasm) if not f.exists()]
    # As fontes vão no .data (--preload-file): o .js pede por ele ao abrir.
    if js.exists() and "larpercord.data" in js.read_text(encoding="utf-8", errors="replace") and not data.exists():
        missing.append(data.name)
    if missing:
        print(f"try/: falta {', '.join(missing)} em {d}; a página da demonstração fica de fora")
        return None
    try:
        shared = wasm_shared_memory(wasm.read_bytes())
    except (ValueError, IndexError) as e:
        print(f"try/: não deu para ler {wasm.name} ({e}); a página da demonstração fica de fora")
        return None
    if shared:
        print("try/: o wasm usa memória compartilhada (threads), que precisa de SharedArrayBuffer e de"
              " cabeçalhos COOP/COEP que o GitHub Pages não manda; a página da demonstração fica de fora")
        return None
    # Uma estimativa do download: o .js e o .wasm com gzip, e o .data (as fontes, servido
    # como application/octet-stream) contado sem compressão.
    total = sum(len(gzip.compress(f.read_bytes(), 9)) for f in (js, wasm))
    total += data.stat().st_size if data.exists() else 0
    return f"{total / 1e6:.1f} MB"


def drop_try_pages():
    for p in TRY_PAGES:
        f = OUT / p
        f.unlink(missing_ok=True)
        if f.parent.is_dir() and not any(f.parent.iterdir()):
            f.parent.rmdir()


def build_try(lang):
    src = (SITE / "try.html").read_text(encoding="utf-8")
    src = re.sub(r"\{\{(.*?)\|\|(.*?)\}\}", lambda m: m.group(1 if lang == "en" else 2), src, flags=re.S)
    path = "try/index.html" if lang == "en" else "pt/try/index.html"
    alt = "pt/try/index.html" if lang == "en" else "try/index.html"
    home = rel(path, page_url(lang) if lang == "pt" else "") or "./"
    size = TRY_SIZE if lang == "en" else TRY_SIZE.replace(".", ",")
    src = (src.replace("%TRY_SIZE%", size).replace("%TRY_THEMES%", json.dumps(THEMES)).replace("%HOME%", home)
           .replace("%ROOT%", root_of(path)).replace("%LANG%", lang)
           .replace("%GUIDE%", rel(path, page_url(lang, "x")).removesuffix("x.html")))
    title = t(lang, "Try larperCord in your browser", "Experimente o larperCord no navegador")
    desc = t(lang, "The real larperCord app compiled to WebAssembly, running its demo mode with fake data. No network, no account.",
             "O app larperCord de verdade compilado para WebAssembly, rodando o modo demonstração com dados falsos. Sem rede, sem conta.")
    write(path, shell(lang, path, alt, title, desc, src, "try"))
    return [{"t": title, "s": "larperCord", "u": path}]


def write(path, text):
    f = OUT / path
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(text, encoding="utf-8")


def build_landing(lang, themes):
    src = (SITE / "landing.html").read_text(encoding="utf-8")
    src = re.sub(r"\{\{(.*?)\|\|(.*?)\}\}", lambda m: m.group(1 if lang == "en" else 2), src, flags=re.S)
    path = "index.html" if lang == "en" else "pt/index.html"
    alt = "pt/index.html" if lang == "en" else "index.html"
    root = root_of(path)
    src = src.replace("%BUILDER%", rel(path, builder_url(lang))).replace("%ROOT%", root).replace("%LANG%", lang).replace("%REPO%", REPO).replace("%VERSION%", VERSION).replace("%GUIDE%", rel(path, page_url(lang, "x")).removesuffix("x.html"))

    def code(m):
        return code_block(html.unescape(m.group(2)).strip("\n"), m.group(1))

    src = re.sub(r'<code-block lang="(\w+)">(.*?)</code-block>', code, src, flags=re.S)
    cards = []
    for i, name in enumerate(THEMES):
        th = themes[name]
        cards.append(f'''<figure class="tcard" data-card="{name}">
  <button type="button" class="tcard-shots" data-apply="{name}" aria-label="{t(lang, f'Dress this page in {name}', f'Vestir esta página de {name}')}">
    <img class="dark" src="{root}assets/shots/{lang}/{name}.webp" alt="{t(lang, f'{name} theme, dark mode', f'Tema {name}, modo escuro')}" loading="lazy" width="1280" height="800">
    <img class="light" src="{root}assets/shots/{lang}/{name}-claro.webp" alt="" loading="lazy" width="1280" height="800">
    <span class="tcard-split" aria-hidden="true"></span>
  </button>
  <figcaption><span class="tnum">{i + 1:02d}</span><strong>{name}</strong><span class="tdesc">{html.escape(th['descEn'] if lang == 'en' else th['desc'])}</span></figcaption>
</figure>''')
    src = src.replace("%THEME_CARDS%", "\n".join(cards)).replace("%MASCOT%", mascot("h"))
    try_cta = f'<a class="btn" href="try/">{t(lang, "Try it in your browser", "Testar no navegador")}</a>'
    src = re.sub(r"([ \t]*)%TRY_CTA%\n", lambda m: f"{m.group(1)}{try_cta}\n" if TRY_SIZE else "", src)
    tabs = [f'<button type="button" role="tab" data-apply="larper" class="tab"><i>0</i>larper</button>']
    tabs += [f'<button type="button" role="tab" data-apply="{n}" class="tab"><i>{i + 1}</i>{n}</button>' for i, n in enumerate(THEMES)]
    src = src.replace("%THEME_TABS%", "".join(tabs))
    presets = "".join(f'<option value="{n}"{" selected" if n == "subsolo" else ""}>{n}.kdl</option>' for n in THEMES)
    src = src.replace("%PRESET_OPTIONS%", presets)
    title = t(lang, "larperCord: a native Discord client whose whole UI is one file", "larperCord: um cliente nativo de Discord cuja interface inteira é um arquivo")
    desc = t(lang, "Unofficial native Discord client in Zig. About 130 MB of RAM with a real account, 0% CPU at idle, and a whole interface described by hot-reloading KDL theme files. Voice calls, Lua plugins, offline search.",
             "Cliente nativo e não oficial de Discord em Zig. Cerca de 130 MB de RAM com uma conta real, 0% de CPU parado e a interface inteira descrita em temas KDL que recarregam ao salvar. Voz, plugins em Lua, busca offline.")
    src = src.replace('loading="lazy"', 'loading="lazy" decoding="async"')
    write(path, shell(lang, path, alt, title, desc, src, "landing"))
    return [
        {"t": t(lang, "Home", "Início"), "s": "larperCord", "u": page_url(lang) if lang == "pt" else "index.html"},
        *[{"t": label, "s": t(lang, "Home", "Início"), "u": f"{'' if lang == 'en' else 'pt/'}index.html#{a}"} for label, a in [
            (t(lang, "Numbers", "Números"), "numbers"), (t(lang, "Layout playground", "Playground de layout"), "playground"),
            (t(lang, "Themes", "Temas"), "themes"), (t(lang, "Features", "Recursos"), "features"),
            (t(lang, "Voice", "Voz"), "voice"), (t(lang, "Plugins", "Plugins"), "plugins"),
            (t(lang, "How it stays light", "Como fica leve"), "light"), (t(lang, "What works today", "O que funciona hoje"), "status"),
            (t(lang, "Install", "Instalar"), "install")]],
    ]


# A página desenha temas que chegam por link: só roda script dos arquivos do próprio site
# e não pede nada a outro endereço (CSP). A prévia usa style="…", por isso o estilo inline.
BUILDER_CSP = ("default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; "
               "font-src 'self'; connect-src 'self'; object-src 'none'; frame-src 'none'; worker-src 'none'; base-uri 'self'; form-action 'none'")


def script_json(data):
    """JSON para dentro de <script type="application/json">. Nenhum `<`, `>` ou `&` fica cru (vira \\u003c…),
    então nada do texto de um tema (um `</script>`, um `<!--<script>`) muda onde o navegador acha o fim do
    bloco. Fora de strings o JSON não tem esses caracteres, e JSON.parse devolve o mesmo texto."""
    s = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    for ch, esc in (("<", "\\u003c"), (">", "\\u003e"), ("&", "\\u0026"), ("\u2028", "\\u2028"), ("\u2029", "\\u2029")):
        s = s.replace(ch, esc)
    return s


def build_builder(lang, themes, community):
    """O criador de temas: os .kdl embutidos vão junto, dentro da página. Um tema da comunidade
    (#community=nome) vem de docs/community/nome.kdl, do próprio site, só quando o link pede."""
    src = (SITE / "theme-builder.html").read_text(encoding="utf-8")
    src = re.sub(r"\{\{(.*?)\|\|(.*?)\}\}", lambda m: m.group(1 if lang == "en" else 2), src, flags=re.S)
    path = builder_url(lang)
    alt = builder_url("pt" if lang == "en" else "en")
    root = root_of(path)
    data = {"order": THEMES, "url": BASE_URL + path,
            "themes": {n: {"src": (ROOT / "themes" / f"{n}.kdl").read_text(encoding="utf-8"), "desc": themes[n]["desc"], "descEn": themes[n]["descEn"]} for n in THEMES},
            "community": [c["name"] for c in community], "communityBase": rel(path, "community/"), "gallery": rel(path, community_url(lang))}
    blob = script_json(data)
    licenses = "".join(f'<option value="{x}">' for x in LICENSES)
    src = (src.replace("%ROOT%", root).replace("%REPO%", REPO).replace("%GUIDE%", rel(path, page_url(lang, "x")).removesuffix("x.html"))
           .replace("%COMMUNITY%", rel(path, community_url(lang))).replace("%LICENSE_OPTIONS%", licenses).replace("%BUILDER_DATA%", blob))
    title = t(lang, "Theme builder · larperCord", "Criador de temas · larperCord")
    desc = t(lang, "Build a larperCord theme in the browser: click any part of the live preview to change its color, generate palettes, pick a layout, and download the .kdl.",
             "Monte um tema do larperCord no navegador: clique em qualquer parte da prévia ao vivo para mudar a cor, gere paletas, escolha um layout e baixe o .kdl.")
    head = f'\n<meta http-equiv="Content-Security-Policy" content="{BUILDER_CSP}">\n<link rel="stylesheet" href="{root}assets/site/theme-builder.css">'
    write(path, shell(lang, path, alt, title, desc, src, "builder", head=head))
    return [{"t": t(lang, "Theme builder", "Criador de temas"), "s": "larperCord", "u": path,
             "x": t(lang, "Colors, fonts, layout, contrast check and a .kdl to download.", "Cores, fontes, layout, checagem de contraste e um .kdl para baixar.")}]


def community_card(lang, path, th):
    e = html.escape
    name = th["name"]
    desc = (th["descEn"] or th["desc"]) if lang == "en" else (th["desc"] or th["descEn"])
    sw = "".join(f'<i style="background:{c}"></i>' for c in th["swatches"])
    return f'''<article class="cg-card" data-cg-card="{name}">
  <div class="tb-screen cg-screen" data-cg-screen role="img" aria-label="{e(t(lang, 'Preview of ', 'Prévia de ') + th['title'])}"><div class="tb-frame" data-cg-frame aria-hidden="true"></div><span class="cg-swatches" aria-hidden="true">{sw}</span></div>
  <div class="cg-body">
    <h2 class="cg-name">{e(th["title"])}</h2>
    <p class="cg-meta">{t(lang, "by", "por")} <strong>{e(th["author"])}</strong> · <span title="{t(lang, 'License', 'Licença')}">{e(th["license"])}</span> · <code>{name}.kdl</code></p>
    <p class="cg-desc">{e(desc)}</p>
    <div class="cg-actions"><a class="tb-b primary" href="{rel(path, builder_url(lang))}#community={name}">{t(lang, "Open in builder", "Abrir no criador")}</a><a class="tb-b" href="{rel(path, "community/" + name + ".kdl")}" download="{name}.kdl">{t(lang, "Download .kdl", "Baixar .kdl")}</a><a class="cg-src" href="{REPO}/blob/main/themes/community/{name}.kdl" rel="noopener">{t(lang, "Source", "Fonte")}</a></div>
  </div>
</article>'''


def build_community(lang, community):
    """A galeria: um cartão por tema de themes/community/, com prévia ao vivo (a mesma do criador)."""
    src = (SITE / "community-themes.html").read_text(encoding="utf-8")
    src = re.sub(r"\{\{(.*?)\|\|(.*?)\}\}", lambda m: m.group(1 if lang == "en" else 2), src, flags=re.S)
    path = community_url(lang)
    alt = community_url("pt" if lang == "en" else "en")
    root = root_of(path)
    # Sem temas, a página mostra o convite; com temas, a grade. Um dos dois blocos sai.
    keep, drop = ("THEMES", "EMPTY") if community else ("EMPTY", "THEMES")
    src = re.sub(rf"<!--{drop}-->.*?<!--/{drop}-->\n?", "", src, flags=re.S)
    src = src.replace(f"<!--{keep}-->\n", "").replace(f"<!--/{keep}-->\n", "")
    data = {"order": [c["name"] for c in community], "themes": {c["name"]: {"src": c["src"]} for c in community}}
    blob = script_json(data)
    count = len(community)
    src = (src.replace("%ROOT%", root).replace("%REPO%", REPO).replace("%GUIDE%", rel(path, page_url(lang, "x")).removesuffix("x.html"))
           .replace("%BUILDER%", rel(path, builder_url(lang))).replace("%CARDS%", "\n".join(community_card(lang, path, c) for c in community))
           .replace("%COUNT%", t(lang, f"{count} theme" + ("" if count == 1 else "s"), f"{count} tema" + ("" if count == 1 else "s")))
           .replace("%DATA%", blob))
    title = t(lang, "Community themes · larperCord", "Temas da comunidade · larperCord")
    desc = t(lang, "larperCord themes made by people who use it: a live preview of each, a link to open it in the theme builder and the .kdl to download. How to send yours.",
             "Temas do larperCord feitos por quem usa: prévia ao vivo de cada um, link para abrir no criador de temas e o .kdl para baixar. Como mandar o seu.")
    head = (f'\n<meta http-equiv="Content-Security-Policy" content="{BUILDER_CSP}">\n<link rel="stylesheet" href="{root}assets/site/theme-builder.css">'
            f'\n<link rel="stylesheet" href="{root}assets/site/community.css">')
    write(path, shell(lang, path, alt, title, desc, src, "community", head=head))
    return [{"t": t(lang, "Community themes", "Temas da comunidade"), "s": "larperCord", "u": path,
             "x": t(lang, "Themes people sent, with a live preview, and how to send yours.", "Temas que as pessoas mandaram, com prévia ao vivo, e como mandar o seu.")}]


def write_community_files(community):
    """O .kdl de cada tema em docs/community/, para o botão de baixar. Os que saíram da pasta somem."""
    out = OUT / "community"
    names = {c["name"] + ".kdl" for c in community}
    if out.exists():
        for f in out.iterdir():
            if f.name not in names:
                f.unlink()
    for c in community:
        write(f"community/{c['name']}.kdl", c["src"])
    if out.exists() and not any(out.iterdir()):
        out.rmdir()


def report_community(problems):
    for p in problems:
        print(p, file=sys.stderr)
    print(f"{len(problems)} problem(s) in the community themes. See the themes guide, \"Sharing your theme\".", file=sys.stderr)


def main():
    global TRY_SIZE
    if len(sys.argv) > 1 and sys.argv[1] == "--check-community":
        folder = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else COMMUNITY_DIR
        if len(sys.argv) > 2 and not folder.is_dir():
            print(f"{sys.argv[2]}: no such folder", file=sys.stderr)
            raise SystemExit(2)
        community, problems = check_community(folder)
        if problems:
            report_community(problems)
            raise SystemExit(1)
        print(f"ok: {len(community)} community theme(s)")
        return
    # Os temas da comunidade primeiro: um arquivo ruim para o build antes de escrever qualquer coisa.
    community, problems = check_community()
    if problems:
        report_community(problems)
        raise SystemExit(1)
    TRY_SIZE = try_size()
    if not TRY_SIZE:
        drop_try_pages()
    themes = load_themes()
    data = {"order": THEMES, "themes": {**{k: {x: v[x] for x in v if x not in ("preset", "options", "desc", "descEn", "nodes")} for k, v in themes.items()},
                                        "larper": {k: BRAND[k] for k in ("radius", "display", "fx", "dark", "light")}}}
    write("assets/site/data.js", "window.LC_DATA=" + json.dumps(data, ensure_ascii=False, separators=(",", ":")) + ";\n")
    write("assets/site/layouts.js", "window.LC_LAYOUTS=" + json.dumps({k: {"nodes": v["nodes"], "en": v["descEn"], "pt": v["desc"]} for k, v in themes.items()}, ensure_ascii=False, separators=(",", ":")) + ";\n")
    write("assets/site/presets.js", "window.LC_PRESETS=" + json.dumps({k: v["preset"] for k, v in themes.items()}, ensure_ascii=False) + ";\n")
    # O gerador de plugin (plugin-starter.js) pega daqui as capacidades e os rótulos do app.
    write("assets/site/plugin-api.js", "window.LC_PLUGIN_API=" + json.dumps(load_plugin_api(), ensure_ascii=False, separators=(",", ":")) + ";\n")
    for lang in LANGS:
        index = build_landing(lang, themes)
        index += build_builder(lang, themes, community)
        index += build_community(lang, community)
        index += build_guide(lang, themes)
        if TRY_SIZE:
            index += build_try(lang)
        write(f"assets/site/search-{lang}.js", "window.LC_SEARCH=" + json.dumps(index, ensure_ascii=False, separators=(",", ":")) + ";\n")
    urls = (["", "pt/"] + [builder_url(la) for la in LANGS] + [community_url(la) for la in LANGS] + [page_url(la, s) for la in LANGS for s, _, _ in FLAT]
            + (["try/", "pt/try/"] if TRY_SIZE else []))
    write_community_files(community)
    write("sitemap.xml", '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
          + "".join(f"  <url><loc>{BASE_URL}{u}</loc></url>\n" for u in urls) + "</urlset>\n")
    write("robots.txt", f"User-agent: *\nAllow: /\nSitemap: {BASE_URL}sitemap.xml\n")
    write(".nojekyll", "")
    write("assets/icon-live.svg", live_icon())
    # O 404 é servido em qualquer profundidade: os caminhos são absolutos a partir do projeto.
    body = (f'<main id="main" class="lost"><img src="/larperCord/assets/logo.svg" alt="" width="320">'
            f'<h1>404</h1><p class="aside">nothing here. <span lang="pt-BR">nada aqui.</span></p>'
            f'<p><a class="btn primary" href="/larperCord/">Home</a> <a class="btn" href="/larperCord/pt/">Início</a></p></main>')
    page = shell("en", "index.html", "pt/index.html", "404 · larperCord", "Page not found.", body, "lost")
    page = page.replace('data-root=""', 'data-root="/larperCord/"')
    page = re.sub(r'(href|src)="(?!https?:|/|#)(?:\./)?([^"]*)"', r'\1="/larperCord/\2"', page)
    write("404.html", page)
    print(f"site gerado em {OUT} ({len(urls)} páginas no sitemap)")
    print(f"demonstração no navegador: {f'try/, cerca de {TRY_SIZE}' if TRY_SIZE else 'fora (sem um build que sirva em docs/try/)'}")


if __name__ == "__main__":
    main()
