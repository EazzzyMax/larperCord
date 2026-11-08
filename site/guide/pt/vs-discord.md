# O que o Discord não tem

O que o larperCord faz e o app oficial do Discord para computador não faz sozinho, comparado em novembro de 2026. Mods do cliente oficial não contam. Cada recurso leva para onde o assunto é explicado, e a [última seção](#o-que-o-app-oficial-tem-e-o-larpercord-nao) lista o que o app oficial ainda faz melhor. Se o Discord ganhar um destes, [abra uma issue](https://github.com/RshaCuDeVidro/larperCord/issues) e a linha sai daqui.

> [!WARNING]
> **Clientes de terceiros violam os Termos de Uso do Discord**, e a sua conta pode ser bloqueada. Use uma conta secundária. Veja [Se o Discord bloquear a sua conta](page:privacy#se-o-discord-bloquear-a-sua-conta).

## Leveza e desempenho

Alguns itens aqui são o jeito como o larperCord fica leve, e o app oficial pode fazer coisas parecidas por dentro.

- **[Nada de navegador dentro](page:architecture#a-renderizacao).** Código nativo que desenha com Dear ImGui sobre o SDL3. O app oficial roda em Electron, um navegador empacotado como app, por enquanto: em 4 de novembro de 2026, o CTO do Discord mostrou uma versão nativa em Rust que ainda não saiu ([os primeiros números](page:performance#os-numeros)).
- **[Cerca de 130 MB de RAM](page:performance#os-numeros)** com uma conta real. ¹
- **[0–0,4% de CPU parado](page:performance#os-numeros).** O app dorme e só acorda com a rede, uma tecla ou o relógio. ²
- **[Cerca de 15 MB](page:performance#os-numeros)** no download para Linux, num arquivo só. ³
- **[As coisas nascem quando você pede](page:performance#dez-decisoes).** A thread de voz quando você entra numa call, e ela para quando você sai, o FFmpeg no primeiro vídeo, e nenhuma thread de plugins enquanto nenhum plugin estiver ligado.
- **[Escondido, fica mais leve](page:performance#dez-decisoes).** Depois de um minuto na bandeja ou minimizado, as imagens saem da memória, menos as pequenas que estavam na tela.
- **[Limites de memória que você escolhe](page:settings#as-paginas).** Configurações → Desempenho mostra a RAM ao vivo e para onde ela vai, e define quanto fica para imagens, cada GIF e mensagens.

¹ PSS: 125–140 MB no uso normal de uma conta e cerca de 70 MB logo depois de abrir, num PC com Arch Linux, Hyprland, um i5-2400S, uma GTX 1050 Ti e janela de 1280×800. Cerca de 35 MB disso são o driver da NVIDIA, as bibliotecas e as fontes. Medido num build que usa as bibliotecas do sistema; lado a lado na demonstração, o arquivo publicado usou cerca de 2 MB a mais. O seu depende dos seus servidores, membros e imagens.

² Medido com `tools/membench.sh` nos 11 temas, com dados de demonstração, janela de verdade num workspace escondido do Hyprland e reprodução automática de GIFs desligada. Uma janela à vista pode medir diferente. Um GIF animado na tela custa cerca de 2,5%.

³ Com SDL3, libcurl e OpenSSL dentro. [Como tudo isso foi medido](page:performance).

## Privacidade e controle

- **[Código aberto](https://github.com/RshaCuDeVidro/larperCord)**, sob a GPL-3.0. Dá para ler cada linha e compilar você mesmo.
- **[Sem telemetria nem análise de uso](page:privacy#o-que-passa-pela-rede)** no app, então não há nada para desligar.
- **[Proxy nas configurações](page:privacy#proxy)** para HTTP, HTTPS, SOCKS5 e Tor, com login e senha, só para a mídia de fora do Discord ou também para a API, o gateway e a mídia do Discord. As calls de voz sempre conectam direto.
- **[Modo economia](page:features#midia).** Imagens, anexos e até fotos de perfil esperam um clique, uma por uma, e os emojis personalizados aparecem como `:nome:`.
- **[Configurações num arquivo de texto](page:settings#arquivos-no-disco).** O `settings.kdl` é texto simples: dá para ler, editar e fazer backup.

## Lendo e escrevendo

- **[Busca offline](page:features#achando-as-coisas).** O `Ctrl+F` procura nas mensagens que você já viu enquanto você digita, sem internet.
- **[Registro de mensagens](page:settings#escolhas-de-privacidade-que-valem-conhecer)**, desligado por padrão. As mensagens apagadas continuam na tela, marcadas, e as editadas guardam o original. Só no seu computador.
- **[Mensagens salvas](page:features#achando-as-coisas)** (`Ctrl+Shift+S`), de graça, com anotação e só no seu computador, até 500. Os favoritos do Discord pedem Nitro e ficam nos servidores dele.
- **[Palavras de alerta](page:features#atencao)** contam como menção: destaque, contador e notificação.
- **[Filtro de palavras](page:features#atencao)** recolhe as mensagens que combinam atrás de um clique, e elas nunca notificam.
- **[Modo foco](page:features#atencao).** Por 15 minutos, 30 minutos, uma hora ou até você desligar, só DMs e menções notificam.
- **[Números de linha nos blocos de código](page:features#markdown)**, que ficam fora do que você copia.
- **[Erros enquanto você digita código](page:lsp).** Um servidor de linguagem que você escolhe confere o bloco de código na caixa de texto. Desligado por padrão.

## Ferramentas para quem quer mais

- **[Tela dividida](page:features#layout).** Até três conversas lado a lado, cada uma com o próprio histórico e posição de rolagem.
- **[Abas](page:shortcuts#teclado)** para os canais abertos: `Ctrl+Clique` abre uma nova, `Ctrl+Tab` e `Alt+1…9` trocam, `Ctrl+W` fecha.
- **[Uma paleta de comandos que faz coisas](page:features#achando-as-coisas).** O `Ctrl+K` também muda configurações, temas e o seu status, e não só pula para canais.
- **[Teclas de vim](page:shortcuts#navegacao-estilo-vim)**, desligadas por padrão: `j`/`k`, `gg`/`G`, e `J`/`K` entre canais.
- **[Opções de linha de comando](page:shortcuts#linha-de-comando).** Abrir com um tema, idioma ou modo, entrar direto nas configurações, ou salvar um print e sair.
- **[Modo demonstração](page:getting-started).** O app inteiro com dados falsos, sem conta e sem rede: `--demo`.

## Voz

- **[Mixer da call](page:voice#usando)** com o volume e um botão de mudo de cada pessoa numa janela só. O app oficial ajusta uma pessoa por vez, pelo menu de cada uma.

## Temas e plugins

- **[O layout inteiro é um arquivo de texto](page:themes).** Mova, redimensione e troque as partes da janela num arquivo `.kdl`, não só as cores.
- **[Recarrega ao salvar](page:themes).** Salvar o arquivo redesenha a janela na hora. Um erro aponta `arquivo:linha:coluna` e o tema anterior continua na tela.
- **[11 layouts embutidos](page:theme-gallery)**, não só esquemas de cores, de um terminal de IRC a uma área de trabalho estilo Mac, cada um com modo claro e escuro e opções próprias.
- **[Cores do seu wallpaper](page:themes#cores)** pelo pywal, nos temas com `palette "wal"`, no Linux (no Windows só com a variável `HOME` definida, e sem acompanhar ao vivo).
- **[Transparência de verdade](page:theme-gallery#vidro).** O tema `vidro` tem fundo transparente, e no Linux o seu compositor (Hyprland, KDE…) aplica o desfoque. No Windows não tem desfoque.
- **[Todas as cores, por tema e por modo](page:themes#cores-personalizadas-sem-editar-o-kdl):** cada token de cor do tema e as oito cores de cargo, escolhidas em hex nas Configurações, de graça e sem editar o arquivo. O tema personalizado do Discord é um degradê de até cinco cores, com Nitro.
- **[Plugins em Lua](page:plugins)** somam painéis, entradas no botão direito, notas embaixo das mensagens, comandos e atalhos, sem recompilar.
- **[Plugins num sandbox](page:plugins#limites).** Uma thread separada da interface, um Lua e 8 MB para cada plugin, cerca de 5 milhões de instruções por chamada, sem arquivos, processos nem sockets, e HTTPS só para hosts que você aprova. Eles nunca veem o seu token.
- **[Nove plugins vêm com o app](page:plugins#os-plugins-que-vem-com-o-app):** anti-golpe, radar de CVE, cartões do GitHub, o que perdi, tradução, lembretes, destaques, links limpos, e links e arquivos.

## O que o app oficial tem e o larperCord não

- **[Compartilhar tela (mandar ou assistir), câmera e chamada de vídeo](page:voice#limites-hoje).** O larperCord só faz voz, e isso não está nos planos.
- **[Aperte para falar fora da janela](page:voice#limites-hoje).** Aqui só funciona com a janela em foco, porque o SDL não tem atalho global portátil. Um atalho global está no roteiro.
- **[Notificação que abre a conversa](page:status#o-que-funciona-hoje).** Clicar numa ainda não abre o canal.
- **[Configurações de servidor e de cargos](page:features#servidores-e-grupos).** Aqui dá para editar nome, descrição, ícone e banner de um servidor, dar ou tirar cargos, e expulsar, banir, castigar, ou silenciar e ensurdecer membros no servidor. O resto está no roteiro.
- **Criar servidores e canais.** Dá para criar threads e posts de fórum, mas não servidores nem canais.
- **Canais de palco.** Um palco aparece como um canal de voz comum, sem a divisão entre quem fala e a plateia e sem como pedir para falar.
- **Atividades e soundboard.** Não existem no app.
- **[Vídeo em qualidade cheia](page:features#midia).** Os vídeos da conversa tocam até 480p, a cerca de 30 qps, e precisam do FFmpeg: o da distro no Linux, o botão **Baixar FFmpeg** em Configurações → Chat no Windows. Sem ele, abrem no navegador.
- **[macOS, celular e navegador](page:getting-started#o-que-voce-precisa).** O larperCord roda no Linux e no Windows 10/11.
- **[Acessibilidade](page:status#o-que-funciona-hoje).** Tem escala da fonte, reduzir movimento, a paleta de comandos e as teclas de vim, mas não tem foco visível do teclado, modo de alto contraste nem suporte a leitor de tela.

O que funciona, o que está parcial e o que vem a seguir está em [Estado e roteiro](page:status).
