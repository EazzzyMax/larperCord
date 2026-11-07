<div align="center">

# larperCord

**Um cliente de Discord nativo, para Linux e Windows, com cerca de 130 MB de RAM, cuja interface inteira é um arquivo de tema.**

Zig · SDL3 · Dear ImGui · FreeType · zero Electron

[English](README.md) · **Português**

![Temas do larperCord](docs/themes.png)

*O mesmo binário e os mesmos dados, só trocando o arquivo `.kdl`. São 11 temas, cada um em claro e escuro. O último quadro é o `cupertino` no claro.*

</div>

> [!WARNING]
> **Clientes de terceiros violam os Termos de Uso do Discord**, e a sua conta pode ser
> bloqueada. Use por sua conta e risco, de preferência com uma conta secundária. Este
> projeto não tem relação com a Discord Inc. Sem token configurado, o app roda num **modo
> demonstração** com dados falsos.

### Se o Discord bloquear a sua conta

O Discord desativa contas ou força a troca de senha quando acha que a conta é um bot de spam ou foi invadida. Isso pode acontecer em qualquer cliente, mas clientes de terceiros costumam disparar mais. Já aconteceu com quem desenvolve este projeto, depois de um dia de testes. **Use uma conta secundária.**

Estes são os gatilhos que as pessoas costumam relatar, então faça isso pelo cliente oficial:

- entrar ou sair de servidores, o mais comum
- desconectar e reconectar com frequência, o que inclui reiniciar o app várias vezes
- abrir DMs com pessoas novas
- mexer na lista de amigos
- editar o perfil enquanto estiver conectado aqui

Se acontecer, redefina a senha pelo discord.com. Se a conta continuar bloqueada, [faça uma apelação aqui](https://support.discord.com/hc/en-us/requests/new?ticket_form_id=360000029731). O Discord não publica essas regras, então a lista vem da experiência de quem faz clientes de terceiros.

### Se o seu antivírus reclamar

A versão para Windows não é assinada, então o SmartScreen avisa. Um antivírus também pode chamá-la de ladrão de token do Discord, provavelmente porque um cliente de Discord está cheio das mesmas palavras que um ladrão tem, como "token" e "Authorization". Um sandbox deu essa nota à versão 0.5.0 por causa de uma regra de padrões, e o relatório de comportamento dele não mostrou acesso a credenciais e, no modo de demonstração, nenhuma conexão.

O token só vai para o Discord e fica no chaveiro do sistema (o Gerenciador de Credenciais, no Windows) ou, sem chaveiro, num arquivo privado. O código é público, então dá para ler ou compilar você mesmo. Baixe o larperCord só deste repositório.

## Por quê

O cliente oficial é um navegador inteiro disfarçado de app. No mesmo PC:

| | RAM (PSS) | CPU parado | Binário |
|---|---|---|---|
| Vesktop (Electron) | **1279 MB** | 12–47%¹ | 287 MB |
| Discord Phoenix (Rust) | ~290 MB² | 0,1%² | não lançado |
| **larperCord**, conta real | **~130 MB**³ | **0–0,4%**⁴ | **~14 MB** |

<sub>¹ média desde a abertura, medida pelo `ps`. Arch Linux, Hyprland, GTX 1050 Ti, janela de 1280×800, build `ReleaseFast`.
² Não medido por nós e não é um teste lado a lado: uma versão inicial para Windows 11, de um print do Gerenciador de Tarefas [postado pelo CTO do Discord](https://x.com/svishnevskiy/status/2118081920194203799). O app ainda não saiu.
³ 125–140 MB no uso normal de uma conta, no mesmo PC, cerca de 70 MB logo depois de abrir. O seu depende dos seus servidores, membros e imagens; Configurações → Desempenho mostra para onde vai. Cerca de 35 MB do total são o driver da NVIDIA, as bibliotecas e as fontes. O arquivo publicado para Linux traz SDL3, libcurl e OpenSSL dentro: lado a lado na demonstração, usou cerca de 2 MB a mais que um build com as cópias do sistema.
⁴ Medido com `tools/membench.sh`, com dados de demonstração, janela de verdade e reprodução automática de GIFs desligada. Um GIF animado na tela custa cerca de 2,5% de CPU.</sub>

## O que tem

- **Temas que reorganizam tudo.** Layout em árvore (`row`/`column`/`flex`/`gap`), 11 componentes
  com variantes, cores sobrescritas por pedaço do layout (`c-text="#fff"`), estilos, tokens de cor com expressões (`mix(wal:0, black, 0.4)`).
  [Guia de temas →](themes/README.pt-BR.md)
- **Recarrega ao salvar.** Edite o `.kdl` e a janela muda na hora (inotify no Linux, aviso de mudança
  na pasta no Windows; sem polling). Erros aparecem com `arquivo:linha:coluna`.
- **Segue o seu wallpaper.** No Linux, temas com `palette "wal"` usam as cores do pywal e acompanham a troca.
  No Windows as cores só são lidas quando a variável `HOME` existe, e não acompanham a troca ao vivo
  ([detalhes](themes/README.pt-BR.md#nós-de-topo)); senão esses temas usam a paleta padrão.
- **Blur de verdade no Linux.** O tema `vidro` tem fundo transparente e o compositor (Hyprland, KDE…)
  aplica o blur, sem custo pro app. No Windows não tem blur: lá, ligue a opção "Fundo opaco" do tema para
  ter cartões sólidos.
- **Conecta no Discord de verdade**: gateway por WebSocket com heartbeat, **RESUME de sessão**,
  **zlib-stream** e reconexão; IDENTIFY e cabeçalhos no formato do cliente web (a mesma
  abordagem do cliente web). REST pra histórico, envio, edição, exclusão, reações e "digitando",
  uma requisição por vez e respeitando o rate limit.
- **Chamadas de voz** de verdade: gateway de voz v8, UDP/RTP, Opus 48 kHz estéreo, **DAVE (E2EE)** via
  libdave/MLS, mic e saída pelo SDL3, mudo/ensurdecer, anel de "falando" e **mixer com volume
  individual** de cada pessoa. A thread de voz só nasce quando você entra numa call.
- **Calls em DM e grupo**: o botão de telefone no cabeçalho liga; uma chamada chegando mostra um cartão
  com Atender e Recusar, um toque (mudo no Não perturbe ou numa conversa silenciada), a notificação do
  sistema e a barra de tarefas piscando, mesmo da bandeja. Botão direito no microfone ou no fone troca o
  dispositivo no meio da call; `Ctrl+Shift+M` muta e `Ctrl+Shift+D` ensurdece.
- **Interações do Discord**: menu do botão direito em mensagens, usuários, canais e servidores;
  barra de ações ao passar o mouse; **responder** (com a "curvinha" e clique para pular até a
  original); **editar** (`↑` na caixa vazia edita a última); **excluir**; **reações**;
  **seleção de texto** com o mouse entre várias mensagens + `Ctrl+C`; **cartão de perfil** com
  "Mensagem @fulano"; **mensagens diretas**; menções em destaque pela regra do Discord (você, os seus
  cargos, @everyone e @here, como o servidor permitir).
- **Opções de envio**: escolha se a resposta menciona o autor, mande em silêncio (`@silent`), sem prévia
  de links ou sem mencionar ninguém, e marque cada arquivo como spoiler ou dê um texto alternativo. Vote
  em enquetes e veja quem votou, veja quem reagiu e passe por mais de 50 fixadas.
- **Abas de canal**, paleta de comandos com busca aproximada (`Ctrl+K` / `Ctrl+Shift+P`: canais, DMs,
  servidores, temas, status, marcar como lido e as opções liga/desliga), atalhos de teclado e
  navegação estilo vim opcional (`j`/`k`, `gg`/`G`, `J`/`K` troca de canal, `/` busca).
- **Painéis do seu tamanho**: arraste a borda da lista de canais, da lista de membros ou dos painéis da tela dividida; duplo clique volta à largura do tema. A escolha fica salva e vale nos outros temas, e a conversa sempre mantém espaço para ser usada.
- **Plugins em Lua**: arquivos `.lua` na sua pasta de plugins (`~/.config/larpercord/plugins/` no Linux,
  `%APPDATA%\larpercord\plugins\` no Windows) que somam painéis, entradas no
  botão direito, notas embaixo das mensagens, comandos e lembretes, numa thread só deles, com limite de
  instruções e de memória: não seguram a interface. Anti-golpe, radar de CVE, cartões do GitHub, o que perdi,
  tradução, lembretes, destaques, links limpos, e links e arquivos vêm com o app. [Guia e API →](docs/plugins.pt-BR.md)
- **Voz:** em Configurações → Voz você escolhe microfone e saída (lembrados pelo nome, voltam ao padrão se sumirem, trocam em plena call), ajusta os volumes, vê o nível do microfone ao vivo e usa "Testar microfone" para ouvir a si mesmo. A detecção de voz tem limiar ajustável sobre a barra ou modo automático que aprende o ruído de fundo. O modo "aperte para falar" aceita tecla ou botão do mouse e funciona com a janela em foco (atalho global não é portável pelo SDL). Há passa-altas contra ronco, porta de ruído e um som para cada evento da call (entrar, sair, outra pessoa entrar ou sair, mudo, ensurdecer, o toque), embutido ou um arquivo seu em WAV ou Ogg Opus, cada um desligável. O painel de voz mostra ping, qualidade por cor, quando você está transmitindo e avisa se o microfone não abrir ou se o servidor te mutou ou ensurdeceu; mudo e surdo dos outros aparecem na lista da call.
- **Roda no Linux e no Windows.** No Linux, prefere Wayland nativo numa sessão Wayland, com X11 como alternativa. O Windows 10/11 sai do mesmo código; os tokens ficam no Gerenciador de Credenciais.
- **Fica na bandeja.** O ícone fica na bandeja do sistema da abertura até sair, com Abrir e Sair no menu dele mesmo com a janela aberta, e fechar mantém o app conectado lá. O clique esquerdo no ícone mostra ou esconde a janela. "Fechar para a bandeja" em Configurações → Avançado desliga tudo isso: sem ícone, e fechar encerra. Sem bandeja, fechar encerra. Abrir de novo traz a janela que já está rodando. No Linux a bandeja precisa de um painel StatusNotifier.
- **Atualiza sozinho.** Verifica ao abrir ou em Configurações → Atualizações. Um botão baixa, instala e reinicia. As atualizações são assinadas, e uma versão sem a assinatura certa não é instalada. Há botão de reiniciar e uma página de Novidades com o que mudou em cada versão.
- **Volume dos vídeos.** O player do app tem um controle de volume, lembrado entre uma vez e outra.
- **Supressão de ruído no microfone.** Configurações → Voz → Supressão de ruído (Desligada / RNNoise), ligada por padrão e trocável em plena call. Usa o [RNNoise](https://github.com/xiph/rnnoise) 0.2 (BSD), embutido no executável e rodando neste computador, sem internet. Reduz ruído constante como ventilador, chiado e ar-condicionado; teclado e pancadas podem passar, outras vozes continuam e a sua pode abafar um pouco. Atrasa o microfone em 20 ms e custa de 2% a 3,5% de um núcleo num Core i5 de 2011 com o microfone aberto, e menos em processadores mais novos; desligada, no mudo ou com a tecla do aperte para falar solta, não custa nada.
- **Bots e apps.** Bots e webhooks levam a etiqueta BOT (com um ✓ quando verificados). As mensagens com componentes novos do Discord (Components V2) mostram texto, miniaturas, separadores, galerias, arquivos e botões de link. Botões, menus de seleção e formulários de bots (modais) funcionam, e `/` lista os comandos de barra dos bots do servidor e dos seus apps, com um painel para as opções e os arquivos. Encaminhadas aparecem como cartões.
- **Markdown do Discord.** Títulos, texto pequeno com `-#`, citações, listas e links `[texto](url)`, que mostram o endereço real ao passar o mouse. Blocos de código têm número de linha, e o texto de embeds pode ser selecionado e copiado.
- **Cuide do que é seu.** Edite um servidor (nome, descrição, ícone, banner) ou um grupo de DM (nome, ícone, pessoas), e edite ou exclua threads quando tiver permissão. O banner do servidor aparece no topo da lista de canais e nos cartões de convite; clique nele para ver a imagem inteira.
- **Moderação.** Expulsar, banir, castigar e silenciar ou ensurdecer no servidor pelo menu da pessoa, só quando o seu cargo permite, com motivo para o registro de auditoria; lista de Banimentos no menu do servidor. A caixa de mensagem mostra o modo lento e diz por que você não pode enviar (permissão, thread trancada, castigo, quarentena do AutoMod). Entrar por convite avisa antes, e servidores com regras ou boas-vindas abrem tudo no app.
- **Sua conta, sincronizada.** Bloquear, ignorar, pedidos de amizade (também pelo nome de usuário), silenciar e o nível das notificações, o status com prazo, o status personalizado e o nome que aparece, os pronomes e o Sobre mim do perfil ficam gravados na sua conta do Discord, como no app oficial. Pedidos de mensagem e spam ficam fora das suas DMs. O Rich Presence mostra o jogo que você está jogando, desligado por padrão.
- **Texto em qualquer idioma.** O árabe sai ligado e o texto da direita para a esquerda vem na ordem certa ([GNU FriBidi](https://github.com/fribidi/fribidi)). Uma letra que falta na fonte do tema, em qualquer escrita, vem de uma fonte do sistema que a tenha, procurada só quando um texto assim aparece.
- **Erros no código (opcional).** Veja erros enquanto digita um bloco de código, com o servidor de linguagem que você escolher. Desligado por padrão, nada embutido nem baixado. [Guia →](docs/lsp.pt-BR.md)
- **Threads e fóruns.** Threads ativas aninhadas abaixo do canal pai (recolhíveis, com não lidas), abrindo como conversa normal, com abas, tela dividida, rascunho, cache e busca; cartão "N mensagens · última há X" na mensagem que abriu; criar thread, entrar, sair, renomear, pôr tags, arquivar e trancar pelo menu, e ver as arquivadas, inclusive as privadas. Fóruns e canais de mídia mostram a lista de posts no lugar da conversa, com busca local, ordem por atividade, páginas sob demanda e "Novo post" com título, tags e texto. Permissões herdadas do canal pai; a lista de membros mostra quem está na thread.
- **Emoji e autocompletar.** Emoji personalizado aparece como imagem (animado inclusive), grande quando a mensagem é só emoji, e nas reações. Figurinhas PNG, APNG e GIF viram imagem, e a aba Figurinhas do seletor de GIFs envia. O seletor tem a lista Unicode inteira, busca em português e inglês, recentes e os emojis dos seus servidores, e avisa quando um emoji precisa de Nitro. Na caixa de texto, `@`, `#`, `:ab` e `/` (comandos de barra) abrem uma lista (setas, Tab/Enter, Esc ou clique); nomes com espaço viram menção de verdade ao enviar. No modo economia, emoji personalizado vira `:nome:`, sem baixar nada. Para regenerar a tabela: `tools/gen_emoji.py`.
- **Leitura sincronizada com o Discord**: não lidos e menções corretos ao abrir, `MESSAGE_ACK` de outro aparelho limpa aqui, confirmação como o cliente oficial (no máximo uma por canal a cada 3 s; nada sozinho com a janela sem foco), "marcar como lido" por canal e por servidor, "marcar como não lida" a partir de uma mensagem.
- **Linha NOVAS MENSAGENS** com botão "N novas mensagens · ir para a primeira" e "marcar como lida"; o canal abre na primeira não lida (dá para desligar em Configurações → Chat).
- **Mensagens fixadas**: alfinete no cabeçalho, fixar e desafixar pelo menu; ir para qualquer mensagem antiga busca em volta dela, com "Voltar ao presente".
- **Links do Discord abrem no app** (também ptb. e canary.); convites viram cartão com o servidor e os membros, um botão Entrar (Ir para o servidor quando você já está nele) e Abrir no navegador.
- Clicar em `@alguém` abre o perfil, em `#canal` abre o canal; o horário mostra a data completa ao passar o mouse.
- **Caixa de entrada** (`Ctrl+I`): DMs e menções não lidas de todos os servidores, por canal, com
  prévia, ir até a mensagem e "marcar tudo como lido"; aba com as menções recentes do Discord.
- **Mensagens salvas com anotação** (`Ctrl+Shift+S`, botão direito → Salvar mensagem): só no seu
  computador, em `~/.config/larpercord/saved-<conta>.json` (`%APPDATA%\larpercord\saved-<conta>.json`
  no Windows); nada vai para o Discord.
- **Cache local e busca offline.** As últimas 200 mensagens vistas de cada canal ficam em
  `~/.cache/larpercord/messages` (`%LOCALAPPDATA%\larpercord\messages` no Windows; teto de 50 MB e, no
  Linux, pastas 700 e arquivos 600): a conversa aparece
  na hora ao abrir e o histórico de verdade chega por cima, sem pular a rolagem. `Ctrl+F` busca
  na memória e no cache, a cada tecla e sem internet, com `from:nome`, `in:canal`, `has:link`,
  `has:imagem` e `has:arquivo`; clicar no resultado pula até a mensagem. Dá para desligar e
  apagar em Configurações → Privacidade.
- **Várias contas.** O menu do próprio nome lista as contas guardadas (nome e foto) e troca na
  hora; "Adicionar conta" volta ao login sem esquecer as outras. A tela de login também lista
  as contas, e um token recusado pelo Discord é esquecido em vez de ser tentado de novo.
- **Configurações no estilo Discord** (`Ctrl+,`): 18 páginas, troca de tema com miniaturas,
  cor de destaque/cantos, **cores personalizadas por tema e modo em hex**, escala de fonte,
  modo compacto, reduzir movimento, relógio 12/24 h, spoilers…, salvas em
  `~/.config/larpercord/settings.kdl` (`%APPDATA%\larpercord\settings.kdl` no Windows). Se
  `XDG_CONFIG_HOME` ou `XDG_CACHE_HOME` existir, o app usa essa pasta, nos dois sistemas.
- **Markdown do Discord**: **negrito**, *itálico*, ~~riscado~~, `código`, ||spoiler||, menções
  `<@id>`/`<#id>`, links e emoji colorido; blocos de código com realce pela etiqueta (zig, c/cpp,
  js/ts, py, rust, go, sh, json, lua…) e botão "Copiar"; prévia acima da caixa enquanto se digita.
- **Vídeos tocando na conversa** (anexos e links diretos para .mp4/.webm) com o **FFmpeg 7, 8 ou 9,
  se tiver** (carregado só no primeiro play, sem dependência de build): play/pausa,
  barra de progresso, som; até 480p e ~30 qps. Sem FFmpeg, o vídeo abre no navegador. No Linux, é o
  pacote `ffmpeg` da distro. O Windows não tem, então Configurações → Chat → Vídeos busca uma vez
  (Verificar se tem FFmpeg, depois Baixar FFmpeg): cerca de 80 MB de github.com/BtbN/FFmpeg-Builds,
  conferidos com um SHA-256 fixo, cerca de 128 MB em disco em `%LOCALAPPDATA%\larpercord\ffmpeg`.
  "Escolher a pasta do FFmpeg…" ali aceita uma versão "shared" do FFmpeg que você já tem, e sem o
  FFmpeg a página diz o porquê (um `ffmpeg` estático no PATH, sem as bibliotecas, uma versão que o app
  não usa, uma biblioteca que não carregou). Também anima os GIFs antigos do Tenor que só existem em MP4.
- **Mídia**: spoilers e mídias sensíveis ficam cobertos até você clicar, sem baixar nada antes; links de
  imagem do Discord vencidos são renovados sozinhos; mensagens de voz têm um player com a onda; GIFs
  longos tocam todos os quadros, e uma estrela em qualquer GIF põe nos seus favoritos.
- **Proxy** (HTTP, HTTPS, SOCKS5, SOCKS5h; Tor em `socks5h://127.0.0.1:9050`), com campos separados para
  endereço, porta, login e senha, para a mídia de fora do Discord ou para tudo menos as calls de voz, que
  sempre conectam direto (Configurações → Rede). A tela de entrada também tem ("Conectar por um
  proxy") e oferece o proxy quando não chega ao Discord.
- Mensagens agrupadas, separadores de dia, envio "pendente" confirmado pelo servidor,
  indicador de digitação, rolagem suave com lista virtualizada.

<div align="center">

![Menu do botão direito, perfil, seleção de texto e barra de ações](docs/interactions.png)

![Configurações](docs/settings.png)

</div>

## Temas embutidos

Todos têm **modo claro e escuro** e **opções próprias** em Configurações → Aparência.

| Tema | Ideia | Exclusivo |
|---|---|---|
| `classico` | o layout que todo mundo conhece, nas cores do pywal (ou na paleta padrão) | banner do servidor |
| `vidro` | cartões translúcidos com o blur do compositor (Linux) | reflexo de luz nos cartões |
| `terminal` | tmux + IRC; no claro, papel de impressora matricial | efeito CRT, logo em ASCII, fósforo verde |
| `subsolo` | terminal de hacking underground, verde ácido e scanlines | rack horizontal, ultravioleta, logo em ASCII |
| `orbital` | console de bordo entre as estrelas, com sistemas numerados | campo de estrelas e órbitas ao fundo, composer de comando, faixa de servidores no rodapé |
| `editorial` | revista impressa em papel com grão, masthead entre réguas e índice à direita | layout invertido, conversa em serifa, colofão |
| `bolhas` | mensageiro com balões de conversa | "Entregue ✓✓" e balão de digitando |
| `zen` | uma coluna central, letras maiores | a navegação se esconde sozinha |
| `papel` | caderno com índice na margem e títulos em serifa | folha pautada com margem vermelha |
| `escritorio` | ferramenta de trabalho, barra lateral escura | barra superior com busca e ajuda |
| `cupertino` | mesa de trabalho estilo Mac: papel de parede e janela flutuante | semáforo que funciona, barra lateral translúcida, Dock com lupa, balões |

## Instalação

**Baixar:** [Linux](https://github.com/RshaCuDeVidro/larperCord/releases/latest/download/larpercord-linux-x86_64) · [Windows](https://github.com/RshaCuDeVidro/larperCord/releases/latest/download/larpercord-windows-x86_64.zip) · [todas as versões](https://github.com/RshaCuDeVidro/larperCord/releases).

No Linux, marque o arquivo como executável e rode: `chmod +x larpercord-linux-x86_64 && ./larpercord-linux-x86_64`. Ele pode ficar com esse nome: a atualização troca esse mesmo arquivo. Deixe-o numa pasta sua, como `~/.local/bin`, para ele conseguir se atualizar.

No Windows, descompacte e abra o `larpercord.exe` da pasta `larperCord`. Deixe as três DLLs ao lado dele (`SDL3.dll`, `libcurl-x64.dll`, `libcrypto-3-x64.dll`) e descompacte num lugar onde você pode gravar, fora de `C:\Program Files`, para ele conseguir se atualizar. Ele ainda não tem assinatura de código: se o SmartScreen disser "O Windows protegeu o computador", clique em **Mais informações** e depois em **Executar assim mesmo**. Na página de versões, pegue o zip: o `.exe` e as DLLs soltos lá são para o atualizador e o script de instalação.

A versão para Linux roda em distros de 2022 para cá (glibc 2.34 ou mais nova). SDL3, libcurl e OpenSSL vêm dentro dela. FreeType, fontconfig, libwebp, Opus e zlib vêm do sistema, e uma distro de desktop costuma já ter. Antes de cada versão, ela é aberta em contêineres de Ubuntu 22.04 e 24.04, Debian 12 e 13, Fedora, openSUSE e Arch, na demonstração e sem GPU.

Num desktop Wayland, o app conecta nativamente pelo SDL3; não precisa de XWayland. Para as decorações da janela no GNOME, instale o pacote `libdecor` da distro e seu plugin de decoração. Para escolher um backend, rode `SDL_VIDEO_DRIVER=wayland larpercord` ou `SDL_VIDEO_DRIVER=x11 larpercord`. Acrescente `--stats` para ver o driver de vídeo e o renderizador escolhidos. O instalador fornece `dev.larpercord.desktop` para o ícone no lançador.

Quem desenvolve pode conferir Wayland nativo nas escalas 1× e 2×, a escolha explícita de backend e a alternativa X11 com `python3 tools/qa_wayland.py zig-out/bin/larpercord` depois de compilar (precisa de Weston, Xvfb e Python 3). O teste usa um compositor separado sem tela, dados de demonstração e nenhuma GPU ou conta do Discord.

O GitHub Actions compila o arquivo para Linux a partir do código deste repositório. Com o GitHub CLI dá para conferir: `gh attestation verify larpercord-linux-x86_64 --repo RshaCuDeVidro/larperCord`. Os arquivos para Windows ainda não têm atestado, então confira com o `SHA256SUMS` da mesma versão. No PowerShell, na pasta com os dois arquivos (`True` quer dizer que bate):

```powershell
(Get-FileHash .\larpercord-windows-x86_64.zip).Hash -eq ((Select-String 'larpercord-windows-x86_64.zip' .\SHA256SUMS).Line -split '\s+')[0]
```

No Linux, `sha256sum -c --ignore-missing SHA256SUMS` faz o mesmo.

Ou use um script:

**Linux** (x86_64, sem sudo: o programa em `~/.local/bin`, com entrada no menu de aplicativos e ícone):

```bash
curl -fsSL https://raw.githubusercontent.com/RshaCuDeVidro/larperCord/main/install.sh | sh
```

**Windows 10/11** (para o seu usuário, sem administrador: o programa em `%LOCALAPPDATA%\Programs\larperCord`, com entrada no menu Iniciar), no PowerShell. Se o larperCord estiver aberto, o script fecha antes:

```powershell
irm https://raw.githubusercontent.com/RshaCuDeVidro/larperCord/main/install.ps1 | iex
```

Os dois baixam a última [versão publicada](https://github.com/RshaCuDeVidro/larperCord/releases) e conferem com o `SHA256SUMS`. No Linux o script lista as bibliotecas do sistema que faltam. Numa distro de antes de 2022, [compile do código](#compilando). Depois disso, o app se atualiza sozinho: Configurações → Atualizações. Rodar um script de novo também instala a versão mais nova.

## Conectando sua conta

O token **nunca** fica no código, em log ou em mensagem de erro, e é apagado da memória ao
sair. No Linux e no Windows, o jeito mais simples é a tela de login: cole o token e deixe "Lembrar"
ligado. O app procura nesta ordem:

1. A variável `LARPER_TOKEN`, que nunca é guardada.
2. As contas guardadas com "Lembrar", começando pela última usada. Cada uma tem a sua entrada no
   lugar seguro do sistema: o chaveiro no Linux (`service larpercord-account account <ID>`), o
   Gerenciador de Credenciais no Windows (`larperCord/account/<ID>`). Sem ele, o token fica em
   `~/.config/larpercord/tokens/<ID>` com `chmod 600` no Linux, ou em
   `%APPDATA%\larpercord\tokens\<ID>` no Windows.
3. Só no Linux, a entrada única de antes, que ainda dá para criar à mão:
   ```bash
   secret-tool store --label='larperCord' service larpercord   # cole o token quando pedir
   ```
   ou o arquivo `~/.config/larpercord/token`, que precisa ter `chmod 600`.

A lista das contas guardadas (só ID, nome e avatar) fica em `~/.config/larpercord/accounts` no Linux
e em `%APPDATA%\larpercord\accounts` no Windows, e elas aparecem no menu do usuário para trocar.

Para usar o `LARPER_TOKEN` numa vez só, sem guardar em lugar nenhum, no bash ou no zsh:

```bash
read -rs LARPER_TOKEN && LARPER_TOKEN="$LARPER_TOKEN" larpercord
```

No PowerShell (troque o caminho pela pasta onde você descompactou, se não usou o script). A última
linha tira a variável da janela; o app já ficou com a cópia dele:

```powershell
$env:LARPER_TOKEN = [Net.NetworkCredential]::new('', (Read-Host 'Token' -AsSecureString)).Password
& "$env:LOCALAPPDATA\Programs\larperCord\larpercord.exe"
Remove-Item Env:LARPER_TOKEN
```

A variável só vale quando o app abre: se o larperCord já estiver aberto, mesmo só na bandeja,
encerre antes (**Sair** no menu do ícone da bandeja).

`--demo` força o modo demonstração mesmo com token. Ainda não tem: compartilhar tela e câmera. Canais
sem acesso só mostram um aviso. As notificações passam pelo `notify-send` no Linux (do libnotify) e
pela bandeja no Windows, e clicar numa delas ainda não abre o canal. A voz usa o backend de áudio do
sistema via SDL3 e só sobe a thread quando você entra numa call.

## Como ele fica leve

Nada de mágica, só muitas decisões pequenas:

1. **Dorme quando nada acontece.** O laço fica em `SDL_WaitEvent`. Rede, mudanças nos arquivos (inotify
   no Linux, avisos de pasta no Windows) e o relógio acordam o app por eventos. Sem animação, sem redesenho. Quadro que sai igual ao anterior nem chega
   à GPU, e o mouse só andando pede menos quadros.
2. **Nada de navegador.** Tudo é desenhado com o `ImDrawList` do Dear ImGui sobre o SDL_Renderer.
3. **Fontes mapeadas, não copiadas.** Cada arquivo de fonte vira um mapa de memória (`mmap` no Linux,
   `MapViewOfFile` no Windows) compartilhado por todos os pesos e famílias. Só as páginas lidas ficam na
   RAM. (Carregar 4 pesos do Inter + emoji do jeito ingênuo custava ~90 MB.)
4. **Só o driver de vídeo necessário.** Em máquinas Linux só com GPU NVIDIA, o glvnd também carregava o
   Mesa + LLVM (~23 MB) à toa. O app detecta e evita.
5. **Markdown interpretado uma vez**, quando a mensagem chega. A interface só faz layout dos
   trechos, com **cache de altura por largura**.
6. **Lista virtualizada**: busca binária pelo primeiro item visível, desenha só a tela.
7. **Memória com teto**: 1.500 mensagens por canal e 3.000 no total, e as antigas são liberadas. Depois
   de um minuto na bandeja ou minimizada, as imagens também saem da memória, menos as pequenas que estavam na tela.
8. **No Linux, o fontconfig é liberado** depois de resolver as fontes (`FcFini` + `malloc_trim`). O
   Windows não tem fontconfig: as fontes são abertas direto de `C:\Windows\Fonts`.
9. **Sem cursor piscando**: o cursor piscando sozinho manteria a CPU acordada.
10. **Binário enxuto**: build release sem símbolos de debug. O arquivo para Linux tem cerca de 14 MB com SDL3, libcurl e OpenSSL dentro, compilados só com as partes que o app usa e sem símbolos exportados, e cerca de 8 MB usando as cópias do sistema. No Windows, esses três vão como DLLs ao lado do `.exe`.

## Compilando

Para o build nativo experimental de **macOS / Apple Silicon** e o pacote `.app`,
veja [o guia do macOS](docs/macos.md) (em inglês).

No Linux, precisa de **Zig 0.17**, **SDL3**, **FreeType**, **fontconfig** e **libcurl** (com WebSocket, 7.86+).
Fontes recomendadas no Linux: Inter, JetBrains Mono e Noto Color Emoji (o fontconfig escolhe substitutas se faltar
alguma). No Windows o app usa Segoe UI, Consolas e Segoe UI Emoji.
Opcional: **FFmpeg 7, 8 ou 9** (libavformat 61–63) para tocar vídeo dentro do app; outra versão
é ignorada e o vídeo abre no navegador.

```bash
# Arch
sudo pacman -S zig sdl3 freetype2 fontconfig curl inter-font ttf-jetbrains-mono noto-fonts-emoji

zig build -Doptimize=ReleaseFast
./zig-out/bin/larpercord --theme vidro
```

A versão para Windows é compilada a partir do Linux. O `tools/windows_deps.sh` baixa SDL3, curl, OpenSSL,
FreeType, Opus, zlib e libwebp para Windows, em versões fixas e com hash conferido:

```bash
tools/windows_deps.sh && zig build -Dtarget=x86_64-windows-gnu
```

O `zig-out/bin/` fica com o `larpercord.exe` e as DLLs `SDL3.dll`, `libcurl-x64.dll` e `libcrypto-3-x64.dll`:
copie os quatro juntos. O Windows não precisa de fontconfig nem de fontes extras: o app usa Segoe UI, Consolas,
Georgia e Segoe UI Emoji de `C:\Windows\Fonts`.

| Comando | |
|---|---|
| `zig build test` | testes (KDL, cores, layout, markdown, Store, temas embutidos, configurações) |
| `tools/snapshots.sh` | gera os prints de `docs/` sem abrir janela |
| `tools/membench.sh 60` | mede RAM e CPU de cada tema e falha se passar de 60 MB |
| `tools/qa_quadros.py BIN [--slow]` | confere o pulo de quadros e a memória com a janela escondida, com janela de verdade num Xvfb |
| `zig build web -Demscripten=PASTA` | a demonstração no navegador em WebAssembly ([como](tools/web/README.pt-BR.md)) |

```
larpercord [--theme NOME] [--demo] [--settings] [--list-themes] [--no-live] [--shot ARQ.png] [--stats] [--version]
```

No Windows, o `larpercord.exe` não tem janela de console, então `--help`, `--list-themes`, `--stats` e `--version`
não mostram nada no terminal. Para ver a saída, mande para um arquivo (o `--version` escreve na saída padrão:
para ele, use `-RedirectStandardOutput`):

```powershell
Start-Process .\larpercord.exe -ArgumentList '--list-themes' -RedirectStandardError saida.txt -Wait; Get-Content saida.txt
```

Nos dois sistemas, opções como `--theme` só valem com o larperCord fechado: se ele estiver na bandeja, abrir
de novo só traz a janela de volta.

Atalhos: `Ctrl+K` paleta · `Ctrl+,` configurações · `Ctrl+I` caixa de entrada · `Ctrl+Shift+S` salvas · `F2` próximo tema · `Ctrl+Tab` abas ·
`Alt+1…9` · `Ctrl+W` fecha aba · `Ctrl+Clique` abre canal em nova aba · `↑` edita a última
mensagem · `Esc` cancela resposta/edição · `Ctrl+C` copia a seleção · `Ctrl+Shift+M` mudo ·
`Ctrl+Shift+D` ensurdecer · botão direito em tudo. [Todos os atalhos →](https://rshacudevidro.github.io/larperCord/pt/guide/shortcuts.html)

## Arquitetura

```
src/
  core/       dados puros, sem janela: tipos (snowflakes), Store, markdown, eventos
  net/        gateway real (Discord) e de demonstração, cada um na sua thread, mais as filas
  theme/      parser KDL, cores, carregador de tema, motor de layout, gerenciador + vigia de arquivos
  ui/         componentes, texto rico, paleta, configurações, animações
  platform/   janela, renderizador, "acordar" o laço; o único lugar que conhece o SDL
themes/       os temas embutidos (também compilados dentro do binário)
third_party/  Dear ImGui 1.93 + dear_bindings (C), com um patch pequeno para emoji em bitmap; GNU FriBidi
```

O fluxo é **interface → `Action` → app → `Command` → gateway → `Event` → Store → interface**.
A interface nunca muda dados direto: ela só lê o Store e pede ações. Com isso, trocar o
gateway falso pelo real não toca na interface.

## Roadmap

- [x] Gateway real (WebSocket, heartbeat, reconexão) e REST respeitando o rate limit
- [x] RESUME de sessão e zlib-stream
- [x] Presenças, membros e eventos de servidor/canal (GUILD_CREATE, CHANNEL_*)
- [x] Imagens: avatares, anexos e emojis personalizados com cache de tamanho fixo
- [x] Permissões por canal (cadeado no que não dá pra ler), threads e fóruns
- [x] Windows 10/11
- [x] Bandeja do sistema, atualização assinada e scripts de instalação
- [ ] Notificações nativas via D-Bus no Linux
- [x] Voz (DAVE/MLS + Opus)
- [x] Calls em DM e grupo
- [x] Rich Presence: mostrar o jogo que você está jogando, desligado por padrão
- [x] Moderação: expulsar, banir, castigo, e silenciar e ensurdecer no servidor
- [x] Botões, menus, formulários e comandos de barra dos bots
- [x] Árabe e hebraico, e fontes para qualquer escrita
- [ ] Backend por software (`wl_shm`, sem GPU) para ficar em ~15–20 MB
- [ ] Componentes de tema escritos em Lua (sandbox)

**A seguir**

- [ ] Abrir pelos servidores, canais e mensagens salvos, e sincronizar quando o Discord responder
- [ ] Atlas de texturas para avatares e emojis
- [ ] Configurar servidor e cargos
- [ ] Um editor de temas melhor
- [ ] Plugins mais versáteis e com mais poder
- [ ] Windows em um `.exe` só (uma opção experimental de build, `-Dsingle-exe=true`, já gera um)

## Licença

O larperCord usa a [GNU General Public License v3.0](LICENSE) (`GPL-3.0-only`). O código de terceiros mantém a própria licença, em cada pasta de `third_party/`: Dear ImGui e dear_bindings são MIT, RNNoise é BSD, GNU FriBidi é LGPL-2.1 ou posterior. O arquivo
`third_party/imgui/misc/freetype/imgui_freetype.cpp` tem alterações marcadas com `[larperCord]`.
