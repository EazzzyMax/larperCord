#!/usr/bin/env bash
# QA completo: a bateria geral no tema classico, a tela de login e a bateria
# por tema em todos os temas, no escuro e no claro. No Linux roda fora da tela;
# no macOS abre uma janela nativa. Prints e registros em qa-out/.
set -uo pipefail
cd "$(dirname "$0")/.."
# Debug (com as checagens de segurança), instalado à parte para não trocar
# o executável de zig-out/ (que é ReleaseFast).
if [ "$(uname -s)" = Darwin ]; then
    sh tools/macos_build.sh -Doptimize=debug -p .zig-cache/qa || exit 1
else
    "${ZIG:-zig}" build -Doptimize=debug -p .zig-cache/qa || exit 1
fi
rm -rf qa-out && mkdir -p qa-out
bin=./.zig-cache/qa/bin/larpercord
total_fail=0
run() {
    local label="$1"; shift
    # Cada bateria começa sem o cache de mensagens da anterior.
    rm -rf qa-out/cache
    local out status=0
    out=$("$@" 2>&1) || status=$?
    printf '%s\n' "$out" > "qa-out/$label.log"
    # O registro guarda tudo; na tela, sem as linhas de info.
    out=$(printf '%s\n' "$out" | grep -v '^info:')
    local line; line=$(echo "$out" | grep 'passaram')
    local summary="${line%%(*}"
    printf "%-24s %s\n" "$label" "${summary:-saiu antes do fim, sem o resumo}"
    if [ "$status" != 0 ] || ! echo "$line" | grep -q ' 0 falharam'; then
        total_fail=1
        if [ -z "$line" ]; then
            # Caiu ou travou no meio: o fim da saída mostra onde (o panic do Debug).
            echo "$out" | tail -n 25 | sed 's/^/    /'
        else
            echo "$out" | sed -n '/^Falhas:/,$p' | sed 's/^/    /'
            [ "$status" != 0 ] && echo "    saiu com o código $status"
        fi
    fi
}
run "geral (classico)" $bin --qa --theme classico
QA_SUITE=extras LARPER_NO_FFMPEG=1 run "extras" $bin --qa --theme classico
QA_SUITE=envio run "envio" $bin --qa --theme classico
QA_SUITE=limites run "limites" $bin --qa --theme classico
# Pedidos de mensagem e grupo: aceitar, recusar e sair mudam a lista de DMs para o resto.
QA_SUITE=social run "social" $bin --qa --theme classico
QA_SUITE=midia run "midia" $bin --qa --theme classico
# Rich Presence: o discord-ipc num XDG_RUNTIME_DIR só do QA (nunca o de um Discord aberto).
mkdir -p qa-out/run && chmod 700 qa-out/run
QA_SUITE=presenca XDG_RUNTIME_DIR="$PWD/qa-out/run" run "presença" $bin --qa --theme classico
QA_SUITE=moderacao run "moderação" $bin --qa --theme classico
QA_SUITE=entrada run "entrada" $bin --qa --theme classico
QA_SUITE=interacoes run "interações" $bin --qa --theme classico
# Fontes reserva (CJK) só quando um texto pede, e o mixer da call: fora da geral.
QA_SUITE=escritas run "escritas" $bin --qa --theme classico
# Sem fonte nenhuma no sistema (o fontconfig sem pasta de fontes): abre com a do ImGui.
printf '<?xml version="1.0"?>\n<fontconfig><cachedir>%s/qa-out/fc-cache</cachedir></fontconfig>\n' "$PWD" > qa-out/sem-fontes.conf
QA_SUITE=sem-fontes FONTCONFIG_FILE="$PWD/qa-out/sem-fontes.conf" run "sem fontes" $bin --qa --theme classico
QA_SUITE=voice run "mixer da call" $bin --qa --theme classico
# As outras baterias do qa_runner.zig rodam dentro da geral ou da "tema" (threads, conta,
# proxy, chamada, voz, dispositivos, rtl...) ou têm script próprio: lsp-quit em
# tools/qa_lsp.sh, bandeja-* em tools/qa_bandeja.sh, plugins-tls em tools/qa_http_tls.sh.
# ffmpeg, plugins-real, vitrine e lsp-real usam a rede ou programas de verdade.
# Plugins: o que fica gravado ao fechar continua lá ao abrir de novo (outro processo).
QA_SUITE=plugins-a run "plugins (antes)" $bin --qa
sleep 2.5
QA_SUITE=plugins-b run "plugins (depois)" $bin --qa
for m in escuro claro; do
    QA_SUITE=login QA_PREFIX="$m-" run "login ($m)" $bin --qa --mode "$m"
done
for t in classico vidro terminal subsolo orbital editorial bolhas zen papel escritorio cupertino; do
    for m in escuro claro; do
        QA_SUITE=tema QA_PREFIX="$t-$m-" run "$t ($m)" $bin --qa --theme "$t" --mode "$m"
    done
done
[ "$total_fail" = 0 ] && echo "tudo passou ✓" || { echo "houve falhas"; exit 1; }
