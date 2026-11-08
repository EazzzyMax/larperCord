"""FreeType com PNG para a demonstração no navegador (zig build web).

A porta freetype do Emscripten compila sem FT_CONFIG_OPTION_USE_PNG, e o emoji
colorido (Noto Color Emoji, tabela CBDT) guarda cada desenho em PNG: sem isso o
FreeType não abre nenhum e todo emoji vira "?". Esta é a mesma porta, com a mesma
versão e o mesmo download da do Emscripten, mais o PNG pela porta libpng dele.

O build.zig passa este arquivo ao embuilder e ao emcc (--use-port=<arquivo>) no
lugar de -sUSE_FREETYPE=1. O emcc só carrega este módulo: nada aqui roda fora dele.
"""
import os

from tools.ports import freetype as upstream

deps = ['zlib', 'libpng']

LIB = 'libfreetype-png.a'

# Os mesmos fontes que a porta do Emscripten compila (tools/ports/freetype.py).
SRCS = [
    'builds/unix/ftsystem.c',
    'src/autofit/autofit.c',
    'src/base/ftbase.c',
    'src/base/ftbbox.c',
    'src/base/ftbdf.c',
    'src/base/ftbitmap.c',
    'src/base/ftcid.c',
    'src/base/ftdebug.c',
    'src/base/ftfstype.c',
    'src/base/ftgasp.c',
    'src/base/ftglyph.c',
    'src/base/ftgxval.c',
    'src/base/ftinit.c',
    'src/base/ftmm.c',
    'src/base/ftotval.c',
    'src/base/ftpatent.c',
    'src/base/ftpfr.c',
    'src/base/ftstroke.c',
    'src/base/ftsynth.c',
    'src/base/fttype1.c',
    'src/base/ftwinfnt.c',
    'src/bdf/bdf.c',
    'src/bzip2/ftbzip2.c',
    'src/cache/ftcache.c',
    'src/cff/cff.c',
    'src/cid/type1cid.c',
    'src/gzip/ftgzip.c',
    'src/lzw/ftlzw.c',
    'src/pcf/pcf.c',
    'src/pfr/pfr.c',
    'src/psaux/psaux.c',
    'src/pshinter/pshinter.c',
    'src/psnames/psnames.c',
    'src/raster/raster.c',
    'src/sdf/sdf.c',
    'src/sfnt/sfnt.c',
    'src/smooth/smooth.c',
    'src/svg/svg.c',
    'src/truetype/truetype.c',
    'src/type1/type1.c',
    'src/type42/type42.c',
    'src/winfonts/winfnt.c',
]


def get(ports, settings, shared):
    ports.fetch_project('freetype', f'https://github.com/freetype/freetype/archive/{upstream.TAG}.zip', sha512hash=upstream.HASH)

    def create(final):
        source_path = ports.get_dir('freetype', f'freetype-{upstream.TAG}')
        ports.install_header_dir(os.path.join(source_path, 'include'), target='freetype2')
        # Sem -pthread (a porta do Emscripten põe): a página não tem threads.
        flags = [
            '-DFT2_BUILD_LIBRARY',
            '-DFT_CONFIG_OPTION_SYSTEM_ZLIB',
            '-DFT_CONFIG_OPTION_USE_PNG',
            '-DHAVE_UNISTD_H',
            '-DHAVE_FCNTL_H',
            '-I' + os.path.join(source_path, 'include'),
        ]
        ports.build_port(source_path, final, 'freetype_png', flags=flags, srcs=SRCS)

    return [shared.cache.get_lib(LIB, create, what='port')]


def clear(ports, settings, shared):
    shared.cache.erase_lib(LIB)


def process_args(ports):
    return ['-isystem', ports.get_include_dir('freetype2')]


def show():
    return 'freetype_png (FreeType com PNG para o emoji colorido; FreeType License)'
