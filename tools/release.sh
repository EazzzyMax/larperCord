#!/usr/bin/env bash
# Publica uma versão: pega os arquivos de Linux e de Windows que o CI compilou (o
# workflow linux-portable, com o atestado de cada um), assina o SHA256SUMS e cria a
# release no GitHub com o trecho do CHANGELOG.md. Nada é compilado aqui além do
# pequeno assinador. Rode do main, sem nada pendente, depois que o linux-portable
# passar neste commit.
#   tools/release.sh            (a versão vem de src/core/version.zig)
# A chave fica em ~/.config/larpercord-release/ed25519.seed, fora do repositório.
set -euo pipefail
cd "$(dirname "$0")/.."
ver=$(sed -n 's/^pub const number = "\(.*\)";/\1/p' src/core/version.zig)
key="${LARPER_RELEASE_KEY:-$HOME/.config/larpercord-release/ed25519.seed}"
[ -f "$key" ] || { echo "sem a chave em $key"; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "há mudanças sem commit"; exit 1; }
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "rode do main"; exit 1; }
grep -q "^## $ver\$" CHANGELOG.md || { echo "CHANGELOG.md sem a seção $ver"; exit 1; }
if gh release view "v$ver" >/dev/null 2>&1; then echo "v$ver já existe"; exit 1; fi

# A pasta temporária não é um repositório: o gh precisa ouvir qual é, e de que commit.
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
commit=$(git rev-parse HEAD)
run=$(gh run list --repo "$repo" --workflow linux-portable --commit "$commit" --status success --limit 1 --json databaseId --jq '.[0].databaseId // empty')
[ -n "$run" ] || { echo "o linux-portable ainda não passou em $commit"; exit 1; }

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# O de Linux não sai daqui: um build local só abriria em distros tão novas quanto esta.
gh run download "$run" --repo "$repo" --name larpercord-linux-x86_64 --dir "$out/linux"
gh attestation verify "$out/linux/larpercord" --repo "$repo" --source-ref refs/heads/main --source-digest "$commit"
install -m 755 "$out/linux/larpercord" "$out/larpercord-linux-x86_64"
# O de Windows também vem do CI: o .exe, as DLLs e o zip que junta os dois, cada um
# com o atestado de que saiu deste commit.
gh run download "$run" --repo "$repo" --name larpercord-windows-x86_64 --dir "$out/win"
for f in larpercord-windows-x86_64.zip larpercord-windows-x86_64.exe SDL3.dll libcurl-x64.dll libcrypto-3-x64.dll; do
    gh attestation verify "$out/win/$f" --repo "$repo" --source-ref refs/heads/main --source-digest "$commit"
    cp "$out/win/$f" "$out/"
done
assets=(larpercord-linux-x86_64 larpercord-windows-x86_64.zip larpercord-windows-x86_64.exe SDL3.dll libcurl-x64.dll libcrypto-3-x64.dll)
(cd "$out" && sha256sum "${assets[@]}" > SHA256SUMS)
zig run tools/release_sign.zig -- sign "$key" "$out/SHA256SUMS"
awk -v v="## $ver" '$0==v{on=1;next} /^## /{on=0} on' CHANGELOG.md > "$out/notes.md"
cd "$out"
gh release create "v$ver" --repo "$repo" --target "$commit" --title "larperCord $ver" --notes-file notes.md "${assets[@]}" SHA256SUMS SHA256SUMS.sig
