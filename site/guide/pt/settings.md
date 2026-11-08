# Configurações e arquivos

Abra as configurações com `Ctrl+,`. As mudanças valem na hora e são salvas no `settings.kdl`, na pasta do larperCord: `~/.config/larpercord/` no Linux e `%APPDATA%\larpercord\` no Windows.

## As páginas

| Página | O que tem |
|---|---|
| **Minha conta** | Dados da conta, o nome que aparece, os pronomes e o Sobre mim, e sair |
| **Privacidade** | Indicador de digitação, animação do Tenor e do Giphy, modo streamer, registro de mensagens, guardar mensagens no disco, limpar o cache, Rich Presence, o aviso antes de entrar num servidor e um botão para a página Rede |
| **Alertas e filtros** | Palavras de alerta, filtro de palavras, pessoas ignoradas (na conta ou neste computador) e modo foco |
| **Aparência** | Modo (escuro, claro, seguir o sistema), tema com miniaturas e as opções dele, escala da fonte, modo compacto, avatares, relógio de 24 horas, status em anel, cor de destaque, cantos, cores personalizadas do tema, restaurar a largura dos painéis, lista de membros e barra de status |
| **Acessibilidade** | Reduzir movimento, cores dos cargos, sublinhar links |
| **Chat** | Reproduzir GIFs automaticamente, imagens de links, modo economia, vídeo, sempre mostrar spoilers, prévia do markdown, abrir na primeira não lida. **Escolher a pasta do FFmpeg…** aponta o app para um FFmpeg 7, 8 ou 9 "shared" que você já tem. Sem o FFmpeg, a parte de vídeo diz por que ele não foi encontrado, qual pacote instalar no Linux, e tem um botão **Baixar FFmpeg** no Windows |
| **Voz** | Microfone e saída, volumes, detecção de voz ou aperte para falar, teste do microfone, filtros e um som para cada evento da call. Veja [Chamadas de voz](page:voice) |
| **Notificações** | Notificações na área de trabalho e piscar na barra de tarefas |
| **Atalhos de teclado** | A lista de atalhos e a navegação estilo vim |
| **Idioma** | Seguir o sistema, Português (Brasil), English (US) ou 日本語 (japonês) |
| **Rede** | O proxy (tipo, endereço, porta, login e senha) e **Usar o proxy em tudo**. A tela de entrada tem o mesmo formulário em **Conectar por um proxy**. Veja [Proxy](page:privacy#proxy) |
| **Avançado** | Modo desenvolvedor (IDs das mensagens, "Copiar ID"), recarregar temas ao salvar, fechar para a bandeja, peso do texto, o registro de depuração e quantas vezes o Discord pediu captcha ou verificação |
| **Desempenho** | RAM, CPU por quadro, CPU parado e mensagens por canal |
| **Plugins** | Um cartão para cada plugin (o que ele é e o que pede), ligar e desligar, erros, aprovação de hosts, o painel dele, Recarregar e Instalar os incluídos |
| **Sobre** | Versão e com o que foi feito |

**Fechar para a bandeja** vem ligado: o ícone do larperCord fica na bandeja do sistema da abertura até sair, com **Abrir o larperCord** e **Sair** no menu dele mesmo com a janela aberta, e fechar a janela deixa o app conectado lá. No Windows, o clique esquerdo no ícone mostra ou esconde a janela e o direito abre o menu; no Linux o painel abre o menu com qualquer clique. Desligado, não há ícone nenhum e fechar a janela encerra o app. O Windows sempre tem bandeja. No Linux ela precisa de um painel com bandeja StatusNotifier: sem ele a opção fica apagada, com o motivo, e fechar a janela encerra o app. No Linux o ícone mora num processo pequeno à parte (cerca de 14 MB), que volta sozinho se cair.

**Salvar registro de depuração** grava o `debug.log` na pasta de cache (`~/.cache/larpercord/` no Linux, `%LOCALAPPDATA%\larpercord\` no Windows) até você desligar ou fechar o app. **Abrir a pasta do registro** e **Copiar o caminho do arquivo** levam até ele. O token nunca entra no arquivo. No Windows é assim que se vê o registro do app, porque a versão para Windows não tem console.

## Escolhas de privacidade que valem conhecer

| Opção | Padrão | Efeito |
|---|---|---|
| Enviar indicador de digitação | ligado | Os outros veem "digitando…" enquanto você escreve |
| Animar GIFs do Tenor e do Giphy | desligado | Baixa do site deles, que vê o seu IP. Desligado, você recebe uma prévia parada pelo Discord |
| Modo streamer | desligado | Esconde o seu e-mail e o seu nome de usuário nas configurações |
| Registro de mensagens | desligado | As mensagens apagadas continuam visíveis, marcadas, e as edições guardam o original. Só local |
| Guardar mensagens no disco | ligado | As conversas abrem na hora e o `Ctrl+F` funciona offline. Só o seu usuário lê os arquivos |

## Arquivos no disco

Tudo fica em duas pastas:

| | Linux | Windows |
|---|---|---|
| Configurações e seus arquivos | `~/.config/larpercord/` | `%APPDATA%\larpercord\` |
| Cache e registro | `~/.cache/larpercord/` | `%LOCALAPPDATA%\larpercord\` |

`XDG_CONFIG_HOME` e `XDG_CACHE_HOME` substituem a primeira parte quando estão definidas, nos dois sistemas. No Windows, digite `%APPDATA%\larpercord` na barra de endereço do Explorador de Arquivos (ou no `Win+R`) para abrir a pasta. Configurações → Plugins mostra o caminho completo da pasta de plugins.

Na pasta de configurações:

| Arquivo | O que é |
|---|---|
| `settings.kdl` | Configurações, incluindo as opções e cores de cada tema |
| `themes/*.kdl` | Seus temas. Crie a pasta antes de abrir o app, ou reinicie ele uma vez (Configurações → Atualizações → Reiniciar o larperCord) |
| `plugins/*.lua` | Seus plugins |
| `plugins.kdl` | Quais plugins estão desligados, os hosts aprovados e o painel lateral |
| `plugin-data/` | O que cada plugin guarda, por conta |
| `drafts.kdl` | Rascunhos não enviados por canal |
| `saved-<conta>.json` | Mensagens salvas e anotações |
| `accounts` | Contas guardadas: só ID, nome e foto |
| `tokens/<ID>` | Tokens lembrados, só quando não há chaveiro (Linux) ou o Gerenciador de Credenciais falha (Windows) |
| `sons/` | Cópias dos arquivos de som escolhidos em Configurações → Voz |
| `instance.lock`, `instance.port` | Impedem uma segunda cópia do app de abrir; ela traz a primeira para a frente |

Na pasta de cache:

| Arquivo | O que é |
|---|---|
| `messages/` | Cache de mensagens: 200 mensagens por canal, teto de 50 MB |
| `debug.log` | Só é gravado com Configurações → Avançado → Salvar registro de depuração ligado. Recomeça depois de 4 MB |
| `lsp-scratch/` | Pasta onde roda o servidor de [erros no código](page:lsp); esvaziada antes de cada início |
| `ffmpeg/` | Só no Windows: o que Configurações → Chat → Baixar FFmpeg instala |

No Linux, as pastas do app ficam com `700` e os arquivos com os seus dados com `600`, então só o seu usuário lê. No Windows, elas ficam dentro do seu perfil de usuário, que os outros usuários não abrem.

Mais dois, que ficam na sua pasta pessoal mesmo com `XDG_CONFIG_HOME` ou `XDG_CACHE_HOME` definida:

| Caminho | O que é |
|---|---|
| `~/.config/larpercord/token` | Só no Linux: arquivo de token opcional (`chmod 600`), de antes das várias contas |
| `~/.cache/wal/colors` | Só leitura: a paleta do pywal, para os temas que a usam. No Windows só é lida quando `HOME` existe (`%HOME%\.cache\wal\colors`), e as mudanças não são acompanhadas |

Para voltar ao padrão, encerre o app e apague o `settings.kdl` da pasta de configurações (`~/.config/larpercord/` no Linux, `%APPDATA%\larpercord\` no Windows). Fechar a janela não basta enquanto o app fica na bandeja: use **Sair** no menu do ícone da bandeja.
