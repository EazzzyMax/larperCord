#!/usr/bin/env bash
# Compila o que a versão portátil para Linux leva dentro do binário, em .deps/linux
# (versões e hashes fixos; hash errado para tudo). Roda no CI, num Ubuntu antigo: é
# a glibc de lá que decide em quais distros o binário abre.
#   tools/linux_deps.sh && PKG_CONFIG_PATH=$PWD/.deps/linux/lib/pkgconfig zig build -Dportable=true
#
# SDL3: várias distros ainda não têm o pacote. Ela abre X11, Wayland e o áudio só ao
# rodar, então nada disso vira dependência do binário.
# curl: muitas distros trazem uma versão sem WebSocket.
# OpenSSL: compilado aqui (a versão LTS) e estático, porque as distros já estão trocando
# a versão da libssl. Os certificados continuam os da distro de quem usa (sys.curlTls).
#
# Só entra o que o app usa. Tudo com uma seção por função, para o ligador jogar fora o
# que ninguém chama, e sem tabelas de unwind: nada nessas bibliotecas lança exceção.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$PWD/.deps/linux
dl=$out/dl
mkdir -p "$dl"
export PKG_CONFIG_PATH=$out/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
secoes="-ffunction-sections -fdata-sections -fno-asynchronous-unwind-tables -fno-unwind-tables"
get() { # url sha256
    local f="$dl/$(basename "$1")"
    [ -f "$f" ] || curl -fsSL --retry 3 -o "$f" "$1"
    echo "$2  $f" | sha256sum -c --quiet -
    echo "$f"
}

# OpenSSL: o TLS do curl e a criptografia do DAVE (libdave e mlspp, em third_party).
# Com o OpenSSL do Ubuntu, o libcurl.pc pedia -lssl -lcrypto sem caminho, a libssl.so
# do sistema entrava na ligação (o --as-needed só a tirava do NEEDED depois) e o ld.lld
# exportava os ~5 mil símbolos que ela e o binário tinham em comum. Agora o curl aponta
# para este OpenSSL e os símbolos dele nascem escondidos: nada sai na tabela dinâmica,
# e o que ninguém chama o ligador joga fora.
# Fora: SSL 3, TLS 1.0 e 1.1, DTLS e QUIC; cifras e hashes que o TLS de hoje e o DAVE
# não usam (o scrypt fica: o DAVE usa na impressão digital do par); DSA e curvas
# binárias; assinaturas pós-quânticas (o ML-KEM fica, é a troca de chaves híbrida do
# TLS 1.3 e do MLS); ENGINE, módulos e o provedor legacy; OCSP, CT, CMS e companhia;
# nomes de arquivo nas mensagens de erro. O openssl.cnf é procurado em /usr/lib/ssl,
# como no OpenSSL do Ubuntu que ia antes, e -O2, como ele: a cifra é assembly, mas o
# C em volta dela (EVP, GCM) com -Os deixava cada quadro do DAVE uns 50% mais lento.
f=$(get https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz 603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a)
t=$(mktemp -d)
tar -xf "$f" -C "$t"
(
    cd "$t"/openssl-*
    # Sem o AES-GCM e o AES-XTS de AVX-512 (~700 KB de assembly desenrolado), como num
    # assembler velho: nessas CPUs fica o AES-NI com AVX, que passa de 1 GB/s, e um
    # quadro de voz tem uns 100 bytes.
    perl -0pi -e 's/^open OUT/\$avx512vaes = 0;\nopen OUT/m' crypto/modes/asm/aes-gcm-avx512.pl crypto/aes/asm/aesni-xts-avx512.pl
    ./Configure --prefix="$out" --libdir=lib --openssldir=/usr/lib/ssl \
        no-shared no-module no-engine no-legacy no-apps no-tests no-docs no-filenames \
        no-ssl3 no-tls1 no-tls1_1 no-tls1-method no-tls1_1-method no-dtls no-quic no-srtp no-sctp no-dgram \
        no-nextprotoneg no-srp no-integrity-only-ciphers no-tls-deprecated-ec no-ssl-trace no-sslkeylog \
        no-aria no-bf no-camellia no-cast no-des no-idea no-mdc2 no-md4 no-rc2 no-rc4 no-rc5 no-rmd160 \
        no-seed no-sm2 no-sm3 no-sm4 no-whirlpool no-gost no-siv no-ocb no-siphash no-blake2 no-argon2 \
        no-dsa no-ec2m no-ml-dsa no-slh-dsa \
        no-ocsp no-ct no-cms no-ts no-cmp no-http no-rfc3779 no-comp no-async no-ui-console \
        no-thread-pool no-default-thread-pool \
        -O2 $secoes -fvisibility=hidden
    make -j"$(nproc)" build_libs
    make install_dev
)
rm -rf "$t"

# SDL3 sem joystick, controle, vibração, sensores, câmera, bateria e udev, sem KMS/DRM
# (o app precisa de X11 ou Wayland) e sem os áudios de disco, OSS e sndio. Ficam todos
# os renderizadores, porque LARPER_RENDERER escolhe entre eles, e os drivers offscreen
# e dummy, que o CI e o QA usam. Continua no -O3 do Release: é ela que desenha cada
# quadro. Fora também as superfícies YUV (o vídeo chega do ffmpeg em RGBA) e o RLE de
# cor-chave: com SDL_LEAN_AND_MEAN, cada parte que fica é ligada pelo nome.
sdl_partes="-DSDL_LEAN_AND_MEAN -DSDL_HAVE_BLIT_0=1 -DSDL_HAVE_BLIT_1=1 -DSDL_HAVE_BLIT_A=1 -DSDL_HAVE_BLIT_N=1 -DSDL_HAVE_BLIT_N_RGB565=1 -DSDL_HAVE_BLIT_AUTO=1 -DSDL_VIDEO_RENDER_SW=1"
f=$(get https://github.com/libsdl-org/SDL/releases/download/release-3.4.20/SDL3-3.4.20.tar.gz f3bb06f55bed9557227a700af2ea62e49497ebdf58037732a731a5fb3ef8581f)
t=$(mktemp -d)
tar -xf "$f" -C "$t"
cmake -S "$t"/SDL3-* -B "$t/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$secoes $sdl_partes" \
    -DCMAKE_INSTALL_PREFIX="$out" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DSDL_SHARED=OFF -DSDL_STATIC=ON \
    -DSDL_DEPS_SHARED=ON \
    -DSDL_X11=ON -DSDL_WAYLAND=ON -DSDL_WAYLAND_SHARED=ON \
    -DSDL_WAYLAND_LIBDECOR=ON -DSDL_WAYLAND_LIBDECOR_SHARED=ON \
    -DSDL_JOYSTICK=OFF -DSDL_HAPTIC=OFF -DSDL_HIDAPI=OFF -DSDL_SENSOR=OFF -DSDL_CAMERA=OFF -DSDL_POWER=OFF \
    -DSDL_LIBUDEV=OFF -DSDL_KMSDRM=OFF -DSDL_DISKAUDIO=OFF -DSDL_OSS=OFF -DSDL_SNDIO=OFF -DSDL_LIBURING=OFF \
    -DSDL_TESTS=OFF -DSDL_TEST_LIBRARY=OFF -DSDL_EXAMPLES=OFF
config="$t/build/include-config-release/build_config/SDL_build_config.h"
for backend in X11 WAYLAND; do
    if ! grep -Eq "^#define SDL_VIDEO_DRIVER_${backend} 1$" "$config"; then
        echo "SDL3 sem $backend: instale os headers de desenvolvimento (veja .github/workflows/linux-portable.yml)." >&2
        exit 1
    fi
done
cmake --build "$t/build"
cmake --install "$t/build"
rm -rf "$t"

# curl só com HTTP(S) e WebSocket, que é o que o app pede (CURLOPT_PROTOCOLS_STR), e o
# proxy. Fora também NTLM, cookies, HSTS, alt-svc, DoH e outras APIs que o app não chama.
# -Os: ele espera a rede, não a CPU.
f=$(get https://curl.se/download/curl-8.23.0.tar.xz 8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5)
t=$(mktemp -d)
tar -xf "$f" -C "$t"
(
    cd "$t"/curl-*
    CFLAGS="-Os $secoes" ./configure --prefix="$out" --libdir="$out/lib" \
        --disable-shared --enable-static --with-pic \
        --with-openssl="$out" --enable-websockets \
        --without-ca-bundle --without-ca-path --with-ca-fallback \
        --without-libpsl --without-brotli --without-zstd --without-nghttp2 --without-libidn2 --without-librtmp \
        --disable-ldap --disable-ldaps --disable-rtsp --disable-dict --disable-telnet --disable-tftp \
        --disable-pop3 --disable-imap --disable-smtp --disable-gopher --disable-mqtt --disable-smb \
        --disable-ftp --disable-file --disable-ipfs --disable-ntlm --disable-aws --disable-cookies \
        --disable-hsts --disable-alt-svc --disable-doh --disable-netrc --disable-unix-sockets \
        --disable-form-api --disable-get-easy-options --disable-headers-api --disable-bindlocal \
        --disable-progress-meter --disable-sha512-256 \
        --disable-manual --disable-docs
    make -j"$(nproc)"
    make install
)
rm -rf "$t"
rm -rf "$out/bin" "$out/share"
echo "pronto: $out"
