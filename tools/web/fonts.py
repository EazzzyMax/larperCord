#!/usr/bin/env python3
"""Fontes da demonstração no navegador (zig build web / web-sim).

A página não tem o fontconfig nem as fontes do sistema de quem visita: leva um
punhado de arquivos, recortados só com as letras que o app usa em português e
inglês (latim, pontuação, setas, símbolos) e os emojis que a demonstração mostra.
ui/fonts.zig (`resolveWeb`) procura estes nomes na pasta.

As fontes vêm deste sistema, pelo fc-match: Inter, JetBrains Mono (ou DejaVu Sans
Mono), DejaVu Sans e Noto Color Emoji. Precisa do fontTools (pip install fonttools).

uso: python3 tools/web/fonts.py [pasta]   (padrão: zig-out/web-fonts)
"""
import glob
import os
import subprocess
import sys

try:
    from fontTools import subset
    from fontTools.ttLib import TTFont
except ImportError:
    sys.exit("fonts.py: precisa do fontTools (pip install fonttools)")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Latim (com o latim-1 e o estendido A), pontuação, moedas, letras-símbolo, setas,
# matemática, técnico, caixas e formas, símbolos e dingbats que a interface desenha.
TEXT = [(0x20, 0x7E), (0xA0, 0x17F), (0x2000, 0x206F), (0x20A0, 0x20CF), (0x2100, 0x214F),
        (0x2190, 0x21FF), (0x2200, 0x22FF), (0x2300, 0x23FF), (0x2500, 0x25FF), (0x2600, 0x27BF)]


def demo_emoji():
    """Os emojis dos dados da demonstração (net/fake_*.zig, core/) e os da própria interface
    (ui/, menos a lista inteira do seletor em emoji_data.zig)."""
    cps = set()
    files = glob.glob(os.path.join(ROOT, "src/net/fake_*.zig")) + glob.glob(os.path.join(ROOT, "src/core/*.zig"))
    files += [f for f in glob.glob(os.path.join(ROOT, "src/ui/*.zig")) + glob.glob(os.path.join(ROOT, "src/app*.zig")) if not f.endswith("emoji_data.zig")]
    for f in files:
        with open(f, encoding="utf-8") as fh:
            for ch in fh.read():
                o = ord(ch)
                if o >= 0x1F000 or 0x2600 <= o <= 0x27BF or 0x2B00 <= o <= 0x2BFF:
                    cps.add(o)
    return cps


def match(pattern):
    out = subprocess.run(["fc-match", "-f", "%{file}\t%{index}\t%{family}", pattern], capture_output=True, text=True, check=True).stdout
    path, index, family = out.split("\t", 2)
    return path, int(index or 0), family


def covered(pattern):
    path, index, _ = match(pattern)
    return set(TTFont(path, fontNumber=index, lazy=True).getBestCmap())


def cut(src, index, unicodes, dest, keep_color=False):
    opts = subset.Options()
    # O ImGui desenha letra por letra, sem moldar o texto: GSUB/GPOS não servem.
    opts.layout_features = []
    opts.drop_tables += ["GSUB", "GPOS", "GDEF", "FFTM"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    # O ImGui pede o desenho ao FreeType com o hinting automático: o da fonte só pesa.
    opts.hinting = False
    opts.desubroutinize = True
    if keep_color:
        opts.drop_tables = [t for t in opts.drop_tables if t not in ("CBDT", "CBLC", "COLR", "CPAL", "sbix")]
    font = TTFont(src, fontNumber=index, lazy=False)
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=unicodes)
    sub.subset(font)
    font.save(dest)
    return os.path.getsize(dest)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "zig-out", "web-fonts")
    os.makedirs(out, exist_ok=True)
    text = set()
    for a, b in TEXT:
        text.update(range(a, b + 1))
    jobs = [
        ("ui-regular.ttf", "Inter:weight=80", text),
        ("ui-medium.ttf", "Inter:weight=100", text),
        ("ui-semibold.ttf", "Inter:weight=180", text),
        ("ui-bold.ttf", "Inter:weight=200", text),
        ("ui-italic.ttf", "Inter:weight=80:slant=100", text),
        ("mono.ttf", "JetBrains Mono:weight=80", text),
        ("mono-bold.ttf", "JetBrains Mono:weight=200", text),
        # Só os símbolos que a Inter não tem (⌁ ▣ ◐ ♪ …): o resto ela já desenha.
        ("symbols.ttf", "DejaVu Sans", set(range(0x2190, 0x27C0)) - covered("Inter:weight=80")),
        ("emoji.ttf", "emoji:color=true", demo_emoji()),
    ]
    total = 0
    notice = []
    for name, pattern, cps in jobs:
        path, index, family = match(pattern)
        size = cut(path, index, cps, os.path.join(out, name), keep_color=name == "emoji.ttf")
        total += size
        notice.append(f"{name}: {family} ({os.path.basename(path)})")
        print(f"{name:16} {size // 1024:5d} KB  {family}")
    with open(os.path.join(out, "NOTICE.txt"), "w", encoding="utf-8") as fh:
        fh.write("Fonts subset for the larperCord browser demo. Inter, JetBrains Mono and Noto Color Emoji:\n"
                 "SIL Open Font License 1.1. DejaVu: Bitstream Vera license.\n\n" + "\n".join(notice) + "\n")
    print(f"total {total // 1024} KB em {out}")


if __name__ == "__main__":
    main()
