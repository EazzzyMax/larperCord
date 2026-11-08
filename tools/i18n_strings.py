#!/usr/bin/env python3
"""Textos da interface para as traduções em i18n/<idioma>.kdl.

A chave de cada tradução é o texto em inglês exatamente como está no código. Este
script acha esses textos em src/**/*.zig:

  - chamadas de i18n.tr, trZ, fmt, fmtZ e allocPrint (o inglês é o segundo texto);
  - funções que repassam o par português/inglês para elas (showToast, notice,
    setProblem...): achadas sozinhas, pelos parâmetros `pt` e `en`/`english`;
  - tabelas com o par em campos: `.en = "..."` ou `.<nome>_en = "..."` (e `.teclas`
    quando a linha tem `.teclas_pt`), fora dos dados da demonstração.

Junta textos separados por `++`, aceita strings de várias linhas (`\\\\`), escapes e
chamadas quebradas em linhas. Ignora blocos `test` e os roteiros de QA.

Uso (só a biblioteca padrão):
  python3 tools/i18n_strings.py                  todos os textos em inglês, ordenados, sem repetição
  python3 tools/i18n_strings.py --check          compara com i18n/ja.kdl: faltando e sobrando são
                                                 avisos; marcador errado, chave repetida ou arquivo
                                                 inválido saem com código 1
  python3 tools/i18n_strings.py --pending PASTA [--chunks N]
                                                 os textos ainda sem tradução, em N arquivos
                                                 (padrão 4), uma linha por texto com o lugar
  python3 tools/i18n_strings.py --merge ARQUIVO  junta as traduções preenchidas de ARQUIVO
                                                 (mesmo formato) em i18n/ja.kdl
  --lang XX                                      outro idioma (i18n/XX.kdl)

Marcadores (só nos textos de formato: fmt, fmtZ, allocPrint e quem repassa para eles):
  - copie os marcadores do inglês como estão ({s}, {d}, {d:.0}...): eles são
    preenchidos na mesma ordem do inglês;
  - para mudar a ordem, use {0}, {1}...: o N-ésimo marcador do texto em inglês
    (contando do zero), com a mesma formatação dele. Não misture os dois jeitos;
  - todo valor do inglês precisa aparecer; {{ e }} viram { e }.
Uma tradução que não segue isso aparece em inglês no app.
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"

# As funções do src/ui/i18n.zig: nome -> (posição do inglês, é texto de formato).
BASE = {
    "tr": (1, False),
    "trZ": (1, False),
    "fmt": (2, True),
    "fmtZ": (2, True),
    "allocPrint": (2, True),
}
FORMAT_FNS = {"fmt", "fmtZ", "allocPrint"}

# Fora da busca: roteiros de QA, os testes e o próprio i18n.zig.
SKIP_FILES = re.compile(r"^(qa_.*|tests)\.zig$")
# Tabelas `.en = "..."` que nunca passam por i18n.tr: dados da demonstração e nomes
# de emoji (só servem para a busca).
SKIP_TABLES = {
    "src/net/fake_gateway.zig",
    "src/net/fake_interactions.zig",
    "src/net/fake_conta.zig",
    "src/ui/emoji_data.zig",
}
# Recebem pt/en e de propósito não passam pelo i18n: mensagens para quem escreve
# plugins (o runtime não conhece o i18n) e os dados da demonstração.
NOT_I18N = {
    ("src/plugins/runtime.zig", "tr"),
    ("src/plugins/runtime.zig", "raiseFmt"),
    ("src/plugins/engine.zig", "runtime_tr"),
    ("src/net/fake_gateway.zig", "pick"),
}
KEYWORDS = {"if", "while", "for", "switch", "catch", "orelse", "return", "and", "or", "try", "else", "defer", "errdefer"}


# --- Lendo o Zig ----------------------------------------------------------------

TOKEN = re.compile(
    r"""
    (?P<nl>\n)
  | (?P<ws>[ \t\r]+)
  | (?P<comment>//[^\n]*)
  | (?P<mline>\\\\[^\n]*)
  | (?P<str>"(?:[^"\\\n]|\\.)*")
  | (?P<char>'(?:[^'\\\n]|\\.)*')
  | (?P<id>@"(?:[^"\\\n]|\\.)*"|@?[A-Za-z_][A-Za-z0-9_]*)
  | (?P<num>[0-9][0-9A-Za-z_.]*)
  | (?P<op>\+\+|.)
    """,
    re.X,
)


def zig_unescape(body):
    """O texto de uma string do Zig, sem as aspas, com os escapes resolvidos."""
    out = bytearray()
    i = 0
    while i < len(body):
        ch = body[i]
        if ch != "\\":
            out += ch.encode()
            i += 1
            continue
        e = body[i + 1]
        if e in 'nrt\\\'"':
            out += {"n": b"\n", "r": b"\r", "t": b"\t"}.get(e, e.encode())
            i += 2
        elif e == "x":
            out.append(int(body[i + 2 : i + 4], 16))
            i += 4
        elif e == "u":
            end = body.index("}", i)
            out += chr(int(body[i + 3 : end], 16)).encode()
            i = end + 1
        else:
            raise ValueError("escape desconhecido: \\" + e)
    return out.decode("utf-8", "surrogateescape")


class Tok:
    __slots__ = ("kind", "text", "value", "line")

    def __init__(self, kind, text, value, line):
        self.kind, self.text, self.value, self.line = kind, text, value, line

    def __repr__(self):
        return f"{self.kind}:{self.text!r}@{self.line}"


def lex(src):
    toks = []
    line = 1
    mline = None  # string de várias linhas em andamento
    for m in TOKEN.finditer(src):
        kind = m.lastgroup
        text = m.group()
        if kind == "nl":
            line += 1
            continue
        if kind == "ws":
            continue
        if kind == "mline":
            part = text[2:]
            if mline is not None and mline.line + mline.value.count("\n") + 1 == line:
                mline.value += "\n" + part
            else:
                mline = Tok("str", text, part, line)
                toks.append(mline)
            continue
        mline = None
        if kind == "comment":
            continue
        if kind == "str":
            toks.append(Tok("str", text, zig_unescape(text[1:-1]), line))
        else:
            toks.append(Tok(kind, text, None, line))
    return toks


def match_close(toks, i):
    """Índice do fechamento do (, [ ou { em toks[i]."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    depth = 0
    for j in range(i, len(toks)):
        t = toks[j].text
        if toks[j].kind != "op":
            continue
        if t in pairs:
            depth += 1
        elif t in (")", "]", "}"):
            depth -= 1
            if depth == 0:
                return j
    return len(toks) - 1


def split_args(toks, open_i, close_i):
    """Os argumentos entre toks[open_i] = '(' e toks[close_i] = ')'."""
    args, cur, depth = [], [], 0
    for t in toks[open_i + 1 : close_i]:
        if t.kind == "op" and t.text in "([{":
            depth += 1
        elif t.kind == "op" and t.text in ")]}":
            depth -= 1
        if depth == 0 and t.kind == "op" and t.text == ",":
            args.append(cur)
            cur = []
            continue
        cur.append(t)
    if cur:
        args.append(cur)
    return args


def literal(arg):
    """O texto de um argumento feito só de strings (com ++), ou None."""
    if not arg or len(arg) % 2 == 0:
        return None
    parts = []
    for k, t in enumerate(arg):
        if k % 2 == 0:
            if t.kind != "str":
                return None
            parts.append(t.value)
        elif not (t.kind == "op" and t.text == "++"):
            return None
    return "".join(parts)


def callee(toks, open_i):
    """`p.toggle` para o ( em toks[open_i]; None se não for chamada."""
    j = open_i - 1
    if j < 0 or toks[j].kind != "id":
        return None
    name = [toks[j].text]
    if j >= 2 and toks[j - 1].text == "." and toks[j - 2].kind == "id":
        name.insert(0, toks[j - 2].text)
    return ".".join(name)


class File:
    def __init__(self, path, text):
        self.path = path
        self.rel = path.relative_to(ROOT).as_posix()
        self.text = text
        self._toks = None
        self.skip = None

    @property
    def toks(self):
        if self._toks is None:
            self._toks = lex(self.text)
            self.skip = self._test_blocks()
        return self._toks

    def _test_blocks(self):
        """Faixas de tokens dentro de `test "..." { }`."""
        out = []
        toks = self.toks
        i = 0
        while i < len(toks):
            t = toks[i]
            if t.kind == "id" and t.text == "test" and (i == 0 or toks[i - 1].text in ("}", ";")):
                j = i + 1
                while j < len(toks) and toks[j].text != "{":
                    j += 1
                end = match_close(toks, j)
                out.append((i, end))
                i = end
            i += 1
        return out

    def in_test(self, i):
        _ = self.toks
        return any(a <= i <= b for a, b in self.skip)


# --- Funções que repassam o par -------------------------------------------------


class Wrapper:
    def __init__(self, f, name, pub, nparams, pt_i, en_i, calls):
        self.file, self.name, self.pub = f, name, pub
        self.nparams, self.pt_i, self.en_i = nparams, pt_i, en_i
        self.calls = calls  # (módulo ou None, nome) chamados com pt/en no corpo
        self.base = None  # o i18n.* a que chega, quando chega


def find_wrappers(files):
    found = []
    for f in files:
        if f.rel == "src/ui/i18n.zig":
            continue
        toks = f.toks
        for i, t in enumerate(toks):
            if not (t.kind == "id" and t.text == "fn" and i + 2 < len(toks) and toks[i + 1].kind == "id" and toks[i + 2].text == "("):
                continue
            close = match_close(toks, i + 2)
            params = split_args(toks, i + 2, close)
            names = []
            for p in params:
                ids = [x.text for x in p if x.kind == "id" and x.text not in ("comptime", "noalias")]
                names.append(ids[0] if ids else "")
            if "pt" not in names or not ({"en", "english"} & set(names)):
                continue
            pt_i = names.index("pt")
            en_i = names.index("en") if "en" in names else names.index("english")
            # O corpo: o primeiro { fora do tipo de retorno.
            j = close + 1
            while j < len(toks) and not (toks[j].text == "{" and toks[j - 1].text not in ("struct", "union", "enum", "error", "opaque")):
                if toks[j].text == ";":
                    break
                j += 1
            if j >= len(toks) or toks[j].text != "{":
                continue
            end = match_close(toks, j)
            calls = []
            for k in range(j, end):
                if toks[k].text == "(" and toks[k - 1].kind == "id":
                    args = split_args(toks, k, match_close(toks, k))
                    flat = [{x.text for x in a} for a in args]
                    if any("pt" in a for a in flat) and any(({"en", "english"} & a) for a in flat):
                        mod = toks[k - 3].text if k >= 3 and toks[k - 2].text == "." else None
                        calls.append((mod, toks[k - 1].text))
            pub = i > 0 and toks[i - 1].text == "pub"
            found.append(Wrapper(f, toks[i + 1].text, pub, len(params), pt_i, en_i, calls))
    # Chega ao i18n direto ou por outra que chega (até parar de mudar).
    changed = True
    while changed:
        changed = False
        for w in found:
            if w.base is not None:
                continue
            for mod, name in w.calls:
                if mod == "i18n" and name in BASE:
                    w.base = name
                else:
                    other = next((o for o in found if o.name == name and o.base is not None and (o.pub or o.file is w.file)), None)
                    if other is not None:
                        w.base = other.base
                if w.base is not None:
                    changed = True
                    break
    return found


# --- Os textos -------------------------------------------------------------------


class Use:
    __slots__ = ("key", "fmt", "file", "line", "ctx")

    def __init__(self, key, fmt, file, line, ctx):
        self.key, self.fmt, self.file, self.line, self.ctx = key, fmt, file, line, ctx


def enclosing(toks, i):
    """A chamada (ou o campo) em volta do token i, para dar contexto."""
    if i >= 3 and toks[i - 1].text == "=" and toks[i - 2].kind == "id" and toks[i - 3].text == ".":
        field = "." + toks[i - 2].text
    elif i >= 3 and toks[i - 1].text == "=" and toks[i - 2].kind == "id" and toks[i - 3].text in ("const", "var"):
        return toks[i - 3].text + " " + toks[i - 2].text
    else:
        field = None
    depth = 0
    for j in range(i - 1, max(-1, i - 400), -1):
        t = toks[j].text
        if toks[j].kind != "op":
            continue
        if t in (")", "]", "}"):
            depth += 1
        elif t in ("(", "[", "{"):
            if depth == 0:
                if t == "(":
                    name = callee(toks, j)
                    if name and name.split(".")[-1] not in KEYWORDS and not name.startswith("i18n."):
                        return f"{field} em {name}" if field else name
                elif t == "{" and field:
                    return field
            else:
                depth -= 1
    return field or ""


def collect(files):
    wrappers = [w for w in find_wrappers(files) if w.base is not None]
    uses = []
    dynamic = 0
    for f in files:
        toks = f.toks
        for i, t in enumerate(toks):
            if t.kind != "id" or i + 1 >= len(toks) or toks[i + 1].text != "(":
                # Tabela: `.en = "..."` dentro de .{ ... }.
                if t.kind == "id" and (t.text == "en" or t.text.endswith("_en") or t.text == "teclas") and i >= 2 and toks[i - 1].text == "." and toks[i - 2].text in ("{", ",") and i + 2 < len(toks) and toks[i + 1].text == "=":
                    if f.rel in SKIP_TABLES or f.in_test(i):
                        continue
                    end = i + 2
                    while end < len(toks) and not (toks[end].text in (",", "}") and toks[end].kind == "op"):
                        end += 1
                    value = literal(toks[i + 2 : end])
                    if value is None:
                        continue
                    # O resto da estrutura: com `.ja` ela tem o próprio japonês;
                    # `.teclas` só vale com `.teclas_pt`.
                    open_i = i - 2
                    while open_i > 0 and not (toks[open_i].text == "{" and toks[open_i - 1].text == "."):
                        open_i -= 1
                    close_i = match_close(toks, open_i)
                    fields = {toks[k].text for k in range(open_i, close_i) if toks[k].kind == "id" and toks[k - 1].text == "." and toks[k + 1].text == "="}
                    if "ja" in fields or (t.text == "teclas" and "teclas_pt" not in fields):
                        continue
                    uses.append(Use(value, False, f.rel, t.line, "tabela " + "." + t.text))
                continue
            if f.in_test(i) or (i > 0 and toks[i - 1].text == "fn"):
                continue
            name = t.text
            is_base = i >= 2 and toks[i - 1].text == "." and toks[i - 2].text == "i18n" and name in BASE
            cands = []
            if is_base:
                en_i, is_fmt = BASE[name]
                cands.append((en_i - 1, en_i, is_fmt, None))
            else:
                for w in wrappers:
                    if w.name == name and (w.pub or w.file is f):
                        cands.append((w.pt_i, w.en_i, w.base in FORMAT_FNS, w))
            if not cands:
                continue
            close = match_close(toks, i + 1)
            args = split_args(toks, i + 1, close)
            method = toks[i - 1].text == "." and not is_base
            for pt_i, en_i, is_fmt, w in cands:
                if w is not None:
                    shift = 1 if (method and len(args) == w.nparams - 1) else 0
                    if len(args) != w.nparams - shift:
                        continue
                    pt_i -= shift
                    en_i -= shift
                if en_i >= len(args):
                    continue
                en = literal(args[en_i])
                pt = literal(args[pt_i])
                if en is None or (w is not None and pt is None):
                    if is_base:
                        dynamic += 1
                    continue
                uses.append(Use(en, is_fmt, f.rel, args[en_i][0].line, enclosing(toks, i - 2) if is_base else name))
                break
    return uses, dynamic


_files = None


def source_files():
    """Os .zig que podem ter textos (os outros nem são lidos como Zig: é bem mais rápido)."""
    global _files
    if _files is not None:
        return _files
    every = [File(p, p.read_text(encoding="utf-8")) for p in sorted(SRC.rglob("*.zig")) if not SKIP_FILES.match(p.name)]
    maybe = [f for f in every if re.search(r"\bpt\s*:", f.text) and re.search(r"\b(en|english)\s*:", f.text)]
    names = {w.name for w in find_wrappers(maybe) if w.base is not None}
    call = re.compile(r"\b(" + "|".join(sorted(names)) + r")\s*\(") if names else None
    table = re.compile(r"\.(en|\w+_en|teclas)\s*=\s*\"")
    _files = [f for f in every if "i18n." in f.text or (call and call.search(f.text)) or (f.rel not in SKIP_TABLES and table.search(f.text))]
    return _files


# --- Marcadores ------------------------------------------------------------------


def parse_format(text):
    """Os marcadores de um texto de formato: lista de (argumento, interior), ou None
    quando o std.fmt não aceitaria ou quando o app não traduz (argumento com nome)."""
    out = []
    nxt = 0
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "}":
            if text[i + 1 : i + 2] == "}":
                i += 2
                continue
            return None
        if ch != "{":
            i += 1
            continue
        if text[i + 1 : i + 2] == "{":
            i += 2
            continue
        close = text.find("}", i + 1)
        if close < 0:
            return None
        inner = text[i + 1 : close]
        if "[" in inner or "{" in inner:
            return None
        m = re.match(r"\d*", inner)
        if m.group():
            arg = int(m.group())
        else:
            arg = nxt
            nxt += 1
        if arg >= 32 or len(out) >= 32:
            return None
        out.append((arg, inner))
        i = close + 1
    return out


def check_template(tpl, english):
    """None se a tradução serve para o texto de formato `english`; senão o porquê."""
    phs = parse_format(english)
    if phs is None:
        return None  # o app nunca traduz esse texto: nada a conferir
    need = {a for a, _ in phs}
    used = set()
    mode = None
    seq = 0
    i = 0
    while i < len(tpl):
        ch = tpl[i]
        if ch not in "{}":
            i += 1
            continue
        if tpl[i + 1 : i + 2] == ch:
            i += 2
            continue
        if ch == "}":
            return "'}' sozinha (use '}}')"
        close = tpl.find("}", i + 1)
        if close < 0:
            return "'{' sem fechar (use '{{' para a chave)"
        inner = tpl[i + 1 : close]
        if inner.isdigit():
            if mode == "copy":
                return "mistura {N} com marcadores copiados"
            mode = "index"
            k = int(inner)
            if k >= len(phs):
                return f"{{{inner}}}: o inglês só tem {len(phs)} marcador(es)"
        else:
            if mode == "index":
                return "mistura {N} com marcadores copiados"
            mode = "copy"
            if seq >= len(phs):
                return f"{{{inner}}} a mais: o inglês tem {len(phs)}"
            if inner != phs[seq][1]:
                return f"{{{inner}}} no lugar de {{{phs[seq][1]}}}"
            k = seq
            seq += 1
        used.add(phs[k][0])
        i = close + 1
    if mode == "copy" and seq != len(phs):
        return f"faltam marcadores: {seq} de {len(phs)}"
    if used != need:
        return "falta algum valor do inglês"
    return None


# --- O arquivo de tradução (subconjunto do KDL do src/theme/kdl.zig) ----------------


class KdlError(Exception):
    pass


def kdl_entries(text, name="arquivo"):
    """[(chave, tradução, linha)] de um arquivo de tradução. Cada nó é `"inglês" "tradução"`."""
    out = []
    i, n, line = 0, len(text), 1

    def fail(msg):
        raise KdlError(f"{name}:{line}: {msg}")

    def skip(newlines):
        nonlocal i, line
        while i < n:
            ch = text[i]
            if ch in " \t\r":
                i += 1
            elif ch == "\n" and newlines:
                i += 1
                line += 1
            elif ch == "\\":
                i += 1
                while i < n and text[i] in " \t\r":
                    i += 1
                if text.startswith("//", i):
                    while i < n and text[i] != "\n":
                        i += 1
                if i < n and text[i] == "\n":
                    i += 1
                    line += 1
            elif text.startswith("//", i):
                while i < n and text[i] != "\n":
                    i += 1
            elif text.startswith("/*", i):
                depth = 0
                while i < n:
                    if text.startswith("/*", i):
                        depth += 1
                        i += 2
                    elif text.startswith("*/", i):
                        depth -= 1
                        i += 2
                        if depth == 0:
                            break
                    else:
                        if text[i] == "\n":
                            line += 1
                        i += 1
                if depth != 0:
                    fail("comentário /* sem fechar")
            else:
                break

    def string():
        nonlocal i, line
        i += 1
        buf = []
        while True:
            if i >= n:
                fail("string sem fechar")
            ch = text[i]
            if ch == '"':
                i += 1
                return "".join(buf)
            if ch == "\\":
                e = text[i + 1 : i + 2]
                r = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\", "/": "/"}.get(e)
                if r is None:
                    fail("escape inválido: \\" + e)
                buf.append(r)
                i += 2
                continue
            if ch == "\n":
                line += 1
            buf.append(ch)
            i += 1

    def word():
        nonlocal i
        start = i
        while i < n and text[i] not in ' \t\r\n=;{}"()\\':
            i += 1
        if i == start:
            fail("esperava um texto entre aspas")
        return text[start:i]

    while True:
        skip(True)
        while i < n and text[i] == ";":
            i += 1
            skip(True)
        if i >= n:
            break
        dropped = False
        if text.startswith("/-", i):
            dropped = True
            i += 2
            skip(True)
        at = line
        key = string() if text[i] == '"' else word()
        vals = []
        while True:
            skip(False)
            if i >= n or text[i] in "\n;":
                break
            if text[i] in "{}=":
                fail("só `\"inglês\" \"tradução\"` por linha (sem blocos nem propriedades)")
            vals.append(string() if text[i] == '"' else word())
        if dropped:
            continue
        if len(vals) != 1:
            raise KdlError(f"{name}:{at}: esperava um texto depois da chave, achei {len(vals)}")
        out.append((key, vals[0], at))
    return out


def kdl_quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r") + '"'


def header_of(text):
    """O comentário do topo do arquivo (até o primeiro nó)."""
    lines = text.splitlines(keepends=True)
    out = []
    for ln in lines:
        s = ln.strip()
        if s == "" or s.startswith("//"):
            out.append(ln)
        else:
            break
    while out and out[-1].strip() == "":
        out.pop()
    return "".join(out)


def sort_key(k):
    return (k.casefold(), k)


# --- Comandos ---------------------------------------------------------------------


def load_lang(lang):
    path = ROOT / "i18n" / f"{lang}.kdl"
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    return path, text


def problems(entries, fmt_keys):
    """Chaves repetidas, vazias e marcadores errados: [(linha, mensagem)]."""
    out = []
    seen = {}
    for key, val, line in entries:
        if key in seen:
            out.append((line, f"chave repetida (a primeira na linha {seen[key]}): {key!r}"))
        seen.setdefault(key, line)
        if key == "" or val == "":
            out.append((line, f"texto vazio: {key!r}"))
        elif key in fmt_keys:
            why = check_template(val, key)
            if why:
                out.append((line, f"{why}: {key!r} -> {val!r}"))
    return out


def cmd_check(uses, dynamic, lang):
    path, text = load_lang(lang)
    rel = path.relative_to(ROOT).as_posix()
    try:
        entries = kdl_entries(text, rel)
    except KdlError as e:
        print(f"erro: {e}", file=sys.stderr)
        return 1
    keys = {u.key for u in uses}
    fmt_keys = {u.key for u in uses if u.fmt}
    have = {k for k, _, _ in entries}
    missing = keys - have
    stale = sorted(have - keys, key=sort_key)
    probs = problems(entries, fmt_keys)
    print(f"textos no código: {len(keys)} ({len(fmt_keys)} de formato; {dynamic} chamadas com texto de variável)")
    print(f"{rel}: {len(have)} traduções, {len(keys & have)} em uso")
    print(f"aviso: {len(missing)} sem tradução (aparecem em inglês)")
    if stale:
        print(f"aviso: {len(stale)} que o código não usa mais:")
        for k in stale:
            line = next(l for kk, _, l in entries if kk == k)
            print(f"  {rel}:{line}: {k!r}")
    for line, msg in probs:
        print(f"erro: {rel}:{line}: {msg}", file=sys.stderr)
    every = [File(p, p.read_text(encoding="utf-8")) for p in sorted(SRC.rglob("*.zig")) if not SKIP_FILES.match(p.name)]
    for w in find_wrappers([f for f in every if re.search(r"\bpt\s*:", f.text)]):
        if w.base is None and (w.file.rel, w.name) not in NOT_I18N:
            print(f"aviso: {w.file.rel}: {w.name}() recebe pt/en mas não passa pelo i18n (o {lang} não chega lá)")
    return 1 if probs else 0


def first_uses(uses):
    by_key = {}
    for u in uses:
        by_key.setdefault(u.key, []).append(u)
    return by_key


def cmd_pending(uses, lang, out_dir, chunks):
    path, text = load_lang(lang)
    have = {k for k, _, _ in kdl_entries(text, path.name)}
    by_key = first_uses(uses)
    pend = [(us[0], len(us)) for k, us in by_key.items() if k not in have]
    pend.sort(key=lambda p: (p[0].file, p[0].line, p[0].key))
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    for old in out_dir.glob("pendentes-*.kdl"):
        old.unlink()
    size = -(-len(pend) // chunks) if pend else 0
    paths = []
    for c in range(chunks):
        part = pend[c * size : (c + 1) * size]
        p = out_dir / f"pendentes-{c + 1}.kdl"
        lines = [
            f"// {lang}: textos sem tradução, parte {c + 1} de {chunks} ({len(part)} textos).",
            "// Preencha o segundo texto de cada linha; linhas com \"\" ficam de fora ao juntar.",
            "// O comentário diz onde o texto aparece (arquivo:linha, a função em volta);",
            "// \"formato\" = tem marcadores {…} (veja as regras no topo de i18n/" + lang + ".kdl).",
            "",
        ]
        for u, count in part:
            where = f"{u.file}:{u.line}"
            if u.ctx:
                where += f" {u.ctx}"
            if count > 1:
                where += f" (+{count - 1} lugar{'es' if count > 2 else ''})"
            if u.fmt and parse_format(u.key):
                where += " formato"
            lines.append(f'{kdl_quote(u.key)} ""  // {where}')
        p.write_text("\n".join(lines) + "\n", encoding="utf-8")
        paths.append((p, len(part)))
    for p, n in paths:
        print(f"{p}: {n}")
    print(f"total: {len(pend)}")
    return 0


def cmd_merge(uses, lang, src_file):
    path, text = load_lang(lang)
    rel = path.relative_to(ROOT).as_posix()
    entries = kdl_entries(text, rel)
    table = {k: v for k, v, _ in entries}
    fmt_keys = {u.key for u in uses if u.fmt}
    keys = {u.key for u in uses}
    added = replaced = 0
    bad = []
    for key, val, line in kdl_entries(Path(src_file).read_text(encoding="utf-8"), str(src_file)):
        if val == "":
            continue
        if key not in keys:
            bad.append(f"{src_file}:{line}: o código não usa este texto: {key!r}")
            continue
        if key in fmt_keys:
            why = check_template(val, key)
            if why:
                bad.append(f"{src_file}:{line}: {why}: {key!r} -> {val!r}")
                continue
        if key in table:
            replaced += table[key] != val
        else:
            added += 1
        table[key] = val
    write_lang(path, text, table)
    for b in bad:
        print(f"fora: {b}", file=sys.stderr)
    print(f"{rel}: {added} novas, {replaced} trocadas, {len(bad)} recusadas, {len(table)} no total")
    return 1 if bad else 0


def write_lang(path, old_text, table):
    head = header_of(old_text)
    body = "\n".join(f"{kdl_quote(k)} {kdl_quote(v)}" for k, v in sorted(table.items(), key=lambda kv: sort_key(kv[0])))
    path.write_text((head.rstrip("\n") + "\n\n" if head else "") + body + "\n", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser(description="Textos da interface para as traduções em i18n/<idioma>.kdl")
    ap.add_argument("--lang", default="ja")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--pending", metavar="PASTA")
    ap.add_argument("--chunks", type=int, default=4)
    ap.add_argument("--merge", metavar="ARQUIVO")
    ap.add_argument("--where", action="store_true", help="com --list: arquivo:linha de cada texto")
    a = ap.parse_args()
    files = source_files()
    uses, dynamic = collect(files)
    if a.check:
        return cmd_check(uses, dynamic, a.lang)
    if a.pending:
        return cmd_pending(uses, a.lang, a.pending, max(1, a.chunks))
    if a.merge:
        return cmd_merge(uses, a.lang, a.merge)
    by_key = first_uses(uses)
    for k in sorted(by_key, key=sort_key):
        if a.where:
            u = by_key[k][0]
            print(f"{kdl_quote(k)}  // {u.file}:{u.line} {u.ctx}{' formato' if any(x.fmt for x in by_key[k]) else ''}")
        else:
            print(kdl_quote(k))
    return 0


if __name__ == "__main__":
    sys.exit(main())
