#!/usr/bin/env bash
# Experimental: o .exe único para Windows, sem SDL3.dll, libcurl-x64.dll nem
# libcrypto-3-x64.dll ao lado. Põe em .deps/windows-static o que o build normal leva
# em DLLs (versões e hashes fixos; hash errado para tudo):
#   tools/windows_deps.sh && tools/windows_static_deps.sh
#   zig build -Dtarget=x86_64-windows-gnu -Dsingle-exe=true
# O OpenSSL estático vem do mesmo pacote do MSYS2 que o build normal usa, e a SDL3
# estática, do pacote do MSYS2 da mesma versão. O curl é compilado aqui pelo próprio
# zig: o do MSYS2 arrastaria nghttp2, libssh2, brotli e companhia, e o oficial traz
# outro OpenSSL dentro, além do que o DAVE usa. Opus, zlib, libwebp e FreeType
# continuam vindo de tools/windows_deps.sh.
# Os pacotes do MSYS2 não têm uma seção por função, então o ligador leva cada objeto
# inteiro: compilar a SDL3 e o OpenSSL aqui, como no binário portátil de Linux, é o
# que falta para o .exe encolher de verdade.
set -euo pipefail
cd "$(dirname "$0")/.."
win=$PWD/.deps/windows
[ -f "$win/lib/libz.a" ] || { echo "rode tools/windows_deps.sh antes" >&2; exit 1; }
out=$PWD/.deps/windows-static
dl=$out/dl
mkdir -p "$dl"
rm -rf "$out/include" "$out/lib"
mkdir -p "$out/include" "$out/lib"
msys=https://repo.msys2.org/mingw/ucrt64
get() { # url sha256
    local f="$dl/$(basename "$1")"
    [ -f "$f" ] || curl -fsSL --retry 3 -o "$f" "$1"
    echo "$2  $f" | sha256sum -c --quiet -
    echo "$f"
}
pkg() { # pacote sha256 bibliotecas...: só os headers e as bibliotecas estáticas pedidas.
    local f t lib
    f=$(get "$msys/$1" "$2")
    shift 2
    t=$(mktemp -d)
    tar --zstd -xf "$f" -C "$t" ucrt64/include ucrt64/lib
    cp -r "$t"/ucrt64/include/. "$out/include/"
    for lib in "$@"; do cp "$t/ucrt64/lib/$lib" "$out/lib/"; done
    rm -rf "$t"
}
pkg mingw-w64-ucrt-x86_64-sdl3-3.4.20-1-any.pkg.tar.zst 4a44381560c433ff42da3a6aff788fba2bba84a44b7f63ea396dec9c1cf79f78 libSDL3.a
pkg mingw-w64-ucrt-x86_64-libiconv-1.19.1-1-any.pkg.tar.zst 8a45dc317a285a036bddd79e01505d67b79e44ff49fc3f6e7177a5ea98d098cf libiconv.a
pkg mingw-w64-ucrt-x86_64-openssl-3.6.5-1-any.pkg.tar.zst 773e021ebad83f14b5c103db467411e8ff064663e1c7e7f730e2be72f4117064 libssl.a libcrypto.a

# O zig como compilador cruzado do CMake.
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
for tool in cc ar ranlib; do
    case $tool in
        cc) cmd='zig cc -target x86_64-windows-gnu' ;;
        *) cmd="zig $tool" ;;
    esac
    printf '#!/bin/sh\nexec %s "$@"\n' "$cmd" > "$t/z$tool"
    chmod +x "$t/z$tool"
done

# curl: só HTTP(S), WebSocket e o proxy, como no binário portátil de Linux. Sem ler o
# openssl.cnf: o OpenSSL do MSYS2 procura em <pasta do .exe>\..\etc\ssl, que outro usuário
# da máquina pode criar, e o arquivo carrega DLLs (provider/engine) no processo.
f=$(get https://curl.se/download/curl-8.23.0.tar.xz 8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5)
tar -xf "$f" -C "$t"
cmake -S "$t"/curl-* -B "$t/curl" -G Ninja \
    -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=x86_64 \
    -DCMAKE_C_COMPILER="$t/zcc" -DCMAKE_AR="$t/zar" -DCMAKE_RANLIB="$t/zranlib" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS_RELEASE="-Os -DNDEBUG" -DCMAKE_C_FLAGS="-ffunction-sections -fdata-sections" \
    -DCMAKE_INSTALL_PREFIX="$out" -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_CURL_EXE=OFF -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF \
    -DBUILD_LIBCURL_DOCS=OFF -DBUILD_MISC_DOCS=OFF -DENABLE_CURL_MANUAL=OFF -DCURL_USE_PKGCONFIG=OFF \
    -DCURL_USE_OPENSSL=ON -DOPENSSL_ROOT_DIR="$out" -DOPENSSL_USE_STATIC_LIBS=ON -DCURL_DISABLE_OPENSSL_AUTO_LOAD_CONFIG=ON \
    -DZLIB_INCLUDE_DIR="$win/include" -DZLIB_LIBRARY="$win/lib/libz.a" \
    -DCURL_USE_LIBPSL=OFF -DCURL_USE_LIBSSH2=OFF -DUSE_NGHTTP2=OFF -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF \
    -DUSE_LIBIDN2=OFF -DUSE_WIN32_IDN=OFF -DCURL_WINDOWS_SSPI=OFF -DENABLE_UNIX_SOCKETS=OFF \
    -DCURL_DISABLE_DICT=ON -DCURL_DISABLE_FILE=ON -DCURL_DISABLE_FTP=ON -DCURL_DISABLE_GOPHER=ON -DCURL_DISABLE_IMAP=ON \
    -DCURL_DISABLE_LDAP=ON -DCURL_DISABLE_LDAPS=ON -DCURL_DISABLE_MQTT=ON -DCURL_DISABLE_POP3=ON -DCURL_DISABLE_RTSP=ON \
    -DCURL_DISABLE_SMTP=ON -DCURL_DISABLE_TELNET=ON -DCURL_DISABLE_TFTP=ON -DCURL_DISABLE_IPFS=ON \
    -DCURL_ENABLE_NTLM=OFF -DCURL_DISABLE_AWS=ON -DCURL_DISABLE_COOKIES=ON \
    -DCURL_DISABLE_HSTS=ON -DCURL_DISABLE_ALTSVC=ON -DCURL_DISABLE_DOH=ON -DCURL_DISABLE_NETRC=ON \
    -DCURL_DISABLE_FORM_API=ON -DCURL_DISABLE_GETOPTIONS=ON -DCURL_DISABLE_HEADERS_API=ON -DCURL_DISABLE_BINDLOCAL=ON \
    -DCURL_DISABLE_PROGRESS_METER=ON -DCURL_DISABLE_SHA512_256=ON -DCURL_DISABLE_KERBEROS_AUTH=ON \
    -DCURL_DISABLE_NEGOTIATE_AUTH=ON -DCURL_CA_BUNDLE=none -DCURL_CA_PATH=none
cmake --build "$t/curl"
cmake --install "$t/curl"
rm -rf "$out/bin" "$out/share" "$out/lib/cmake" "$out/lib/pkgconfig"
echo "pronto: $out"
