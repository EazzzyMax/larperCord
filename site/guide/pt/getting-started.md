# Primeiros passos

O larperCord é um cliente de Discord nativo para Linux e Windows, escrito em Zig. Você pode rodar sem conta: `--demo` abre o **modo demonstração**, com servidores e pessoas falsos, sem conectar em nada. Sem token configurado, o app abre a tela de login, que também oferece a demonstração.

> [!WARNING]
> **Clientes de terceiros violam os Termos de Uso do Discord**, e a sua conta pode ser banida. Use uma conta real por sua conta e risco, de preferência uma secundária. Este projeto não tem relação com a Discord Inc.

## O que você precisa

| | Linux | Windows |
|---|---|---|
| Sistema | x86_64 com glibc 2.34 ou mais nova, distros de 2022 para cá (testado todo dia no Arch com Hyprland) | Windows 10 ou 11, x64 |
| Para rodar o download | FreeType, fontconfig, libwebp, Opus e zlib do sistema; uma distro de desktop costuma já ter. SDL3, libcurl e OpenSSL vêm dentro do arquivo | Nada além dele: SDL3, libcurl e OpenSSL vêm como DLLs ao lado do `larpercord.exe` |
| Fontes | Inter, JetBrains Mono e Noto Color Emoji são recomendadas. O fontconfig escolhe substitutas se faltar alguma | Nada para instalar: Segoe UI, Consolas, Georgia e Segoe UI Emoji de `C:\Windows\Fonts` ([por quê](page:themes#fontes-no-windows)) |
| Vídeo dentro do app (opcional) | FFmpeg 7, 8 ou 9 (libavformat 61–63) da distro. Qualquer outra versão é ignorada e os vídeos abrem no navegador | Configurações → Chat → **Baixar FFmpeg**, cerca de 80 MB, conferidos com um SHA-256 fixo |
| Para compilar | Zig 0.17, SDL3, FreeType, fontconfig, libcurl (com suporte a WebSocket, 7.86 ou mais nova), zlib, libwebp, Opus, OpenSSL | Compilado a partir do Linux com Zig 0.17: o `tools/windows_deps.sh` baixa as bibliotecas do Windows |

## Instalar

Escolha o seu sistema. O site mostra o seu primeiro; os outros ficam a um clique.

:::: os-pick
::: os arch | Arch Linux e distros baseadas nele
O pacote é o [`larpercord-bin`](https://aur.archlinux.org/packages/larpercord-bin), no AUR. Instale com o seu ajudante do AUR:

```bash
yay -S larpercord-bin
# ou
paru -S larpercord-bin
```

É o mesmo arquivo do download para Linux, instalado em `/usr/bin` com o ícone no menu de aplicativos. As atualizações vêm pelo seu ajudante do AUR: quando sai uma versão nova, Configurações → Atualizações avisa e deixa a instalação com o pacote.
:::
::: os linux | Outras distros Linux
Um comando instala, sem sudo: o programa vai para `~/.local/bin`, com entrada no menu de aplicativos e ícone. Ele confere o download com o `SHA256SUMS` e lista as bibliotecas do sistema que faltam:

```bash
curl -fsSL https://raw.githubusercontent.com/RshaCuDeVidro/larperCord/main/install.sh | sh
```

Ou pegue o arquivo portátil: [larpercord-linux-x86_64](https://github.com/RshaCuDeVidro/larperCord/releases/latest/download/larpercord-linux-x86_64). Marque como executável e rode: `chmod +x larpercord-linux-x86_64 && ./larpercord-linux-x86_64`. Ele pode ficar com esse nome: a atualização troca esse mesmo arquivo. Deixe-o numa pasta sua, como `~/.local/bin`, para ele conseguir se atualizar.

Ele roda em distros de 2022 para cá (glibc 2.34 ou mais nova). SDL3, libcurl e OpenSSL vêm dentro dele. FreeType, fontconfig, libwebp, Opus e zlib vêm do sistema, e uma distro de desktop costuma já ter. Antes de cada versão, ele é aberto em contêineres de Ubuntu 22.04 e 24.04, Debian 12 e 13, Fedora, openSUSE e Arch, na demonstração e sem GPU.

O GitHub Actions compila esse arquivo a partir do código deste repositório. Com o GitHub CLI dá para conferir: `gh attestation verify larpercord-linux-x86_64 --repo RshaCuDeVidro/larperCord`. Na pasta com o arquivo e o `SHA256SUMS` da mesma versão, `sha256sum -c --ignore-missing SHA256SUMS` confere com a lista da versão.
:::
::: os windows | Windows 10 e 11
No PowerShell, para o seu usuário, sem administrador. Ele instala em `%LOCALAPPDATA%\Programs\larperCord` com uma entrada no menu Iniciar, fecha o larperCord antes se ele estiver aberto e confere o download com o `SHA256SUMS`:

```powershell
irm https://raw.githubusercontent.com/RshaCuDeVidro/larperCord/main/install.ps1 | iex
```

Ou baixe o [zip](https://github.com/RshaCuDeVidro/larperCord/releases/latest/download/larpercord-windows-x86_64.zip), descompacte e abra o `larpercord.exe` da pasta `larperCord`. Deixe as três DLLs ao lado dele (`SDL3.dll`, `libcurl-x64.dll`, `libcrypto-3-x64.dll`) e descompacte num lugar onde você pode gravar, fora de `C:\Program Files`, para ele conseguir se atualizar. Ele ainda não tem assinatura de código: se o SmartScreen disser "O Windows protegeu o computador", clique em **Mais informações** e depois em **Executar assim mesmo**. Na página de versões, pegue o zip: o `.exe` e as DLLs soltos lá são para o atualizador e o script de instalação.

Os arquivos para Windows ainda não têm atestado. Para conferir o zip com o `SHA256SUMS` da mesma versão, no PowerShell, na pasta com os dois arquivos (`True` quer dizer que bate):

```powershell
(Get-FileHash .\larpercord-windows-x86_64.zip).Hash -eq ((Select-String 'larpercord-windows-x86_64.zip' .\SHA256SUMS).Line -split '\s+')[0]
```
:::
::::

Depois disso o app se atualiza sozinho em Configurações → Atualizações (menos o pacote do AUR, que se atualiza pelo seu ajudante do AUR, como o yay ou o paru). Rodar um script de instalação de novo também instala a versão mais nova. Versões antigas e checksums: [todas as versões](https://github.com/RshaCuDeVidro/larperCord/releases).

A última linha da tabela vale para quem compila do código, abaixo.

## Compilar e rodar

```bash
# Arch Linux
sudo pacman -S zig sdl3 freetype2 fontconfig curl zlib libwebp opus openssl \
    inter-font ttf-jetbrains-mono noto-fonts-emoji

git clone https://github.com/RshaCuDeVidro/larperCord
cd larperCord

zig build -Doptimize=ReleaseFast
./zig-out/bin/larpercord --demo
```

O resto já está no repositório: Dear ImGui, Lua, stb_image, libdave, MLSpp e nlohmann/json estão copiados em `third_party/`, então o build para Linux não baixa nada.

A versão para Windows também é compilada no Linux. O `tools/windows_deps.sh` baixa as bibliotecas dela uma vez, em versões fixas e com hash conferido:

```bash
tools/windows_deps.sh
zig build -Dtarget=x86_64-windows-gnu
```

O `zig-out/bin/` fica com o `larpercord.exe` e as DLLs `SDL3.dll`, `libcurl-x64.dll` e `libcrypto-3-x64.dll`. Copie os quatro arquivos juntos para o Windows e abra o `larpercord.exe`.

## Seus primeiros cinco minutos

1. Aperte `F2` algumas vezes. Cada toque troca o arquivo de tema inteiro.
2. Aperte `Ctrl+K` e digite `tema`, ou o nome de um canal. Essa é a paleta de comandos, e quase tudo está nela.
3. Aperte `Ctrl+,` para abrir as configurações. Olhe a página Aparência, onde cada tema tem as próprias opções.
4. Clique com o botão direito numa mensagem, num usuário, num canal e num servidor. Tudo tem um menu.
5. Copie um tema e edite com o app aberto. Os temas embutidos ficam dentro do app, então baixe o arquivo (ou copie de `themes/`, se você clonou o repositório). No Linux:

```bash
mkdir -p ~/.config/larpercord/themes
curl -fsSL https://raw.githubusercontent.com/RshaCuDeVidro/larperCord/main/themes/orbital.kdl -o ~/.config/larpercord/themes/mine.kdl
${EDITOR:-nano} ~/.config/larpercord/themes/mine.kdl
```

No Windows, no PowerShell:

```powershell
New-Item -ItemType Directory -Force "$env:APPDATA\larpercord\themes" | Out-Null
Invoke-WebRequest https://raw.githubusercontent.com/RshaCuDeVidro/larperCord/main/themes/orbital.kdl -OutFile "$env:APPDATA\larpercord\themes\mine.kdl" -UseBasicParsing
notepad "$env:APPDATA\larpercord\themes\mine.kdl"
```

Se a pasta `themes` é nova, reinicie o larperCord uma vez (Configurações → Atualizações → **Reiniciar o larperCord**) para ele passar a vigiar a pasta. Fechar a janela não basta, porque por padrão ela só esconde o app na bandeja. Troque a linha `theme "orbital"` por `theme "mine"`, escolha-o com `F2` ou na paleta, e cada salvamento recarrega a janela. Se você errar, um aviso mostra `arquivo:linha:coluna` e a versão anterior continua na tela. [Escrevendo temas](page:themes) tem a linguagem inteira.

## Próximos passos

- [Conectar a sua conta](page:account), se você aceita o risco.
- [Tour de recursos](page:features), para ver o que tem lá dentro.
- [Atalhos e linha de comando](page:shortcuts), com todas as teclas e opções.
