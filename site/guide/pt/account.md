# Conectar a sua conta

> [!WARNING]
> **Usar uma conta de usuário fora do cliente oficial viola os Termos de Uso do Discord, e a conta pode ser banida.** Use por sua conta e risco, de preferência com uma conta secundária. Nada neste projeto elimina esse risco.

## Como o app encontra o seu token

O token nunca fica no código, e nunca vai para logs nem mensagens de erro. Ele também é apagado da memória quando o app fecha.

O jeito mais simples, no Linux e no Windows, é a tela de login com **Lembrar neste computador** ligado (abaixo). O token vai para o lugar seguro do sistema: o chaveiro no Linux, o Gerenciador de Credenciais no Windows.

Ao abrir, o app procura nesta ordem:

1. A variável de ambiente `LARPER_TOKEN`. Ela nunca é guardada.
2. As contas que você guardou com **Lembrar**, começando pela última usada.
3. Só no Linux, de antes das várias contas: a entrada `service larpercord` do chaveiro e depois o arquivo `~/.config/larpercord/token`, que precisa ter `chmod 600` (se outros usuários conseguirem ler, o app ignora o arquivo e avisa no registro). Para pôr um token no chaveiro você mesmo:
   ```bash
   secret-tool store --label='larperCord' service larpercord   # cole o token quando pedir
   ```
   O `secret-tool` precisa de um chaveiro rodando, como o GNOME Keyring. Sem ele, o **Lembrar** salva num arquivo.

Para usar o `LARPER_TOKEN` numa vez só, sem guardar em lugar nenhum, no bash ou no zsh:

```bash
read -rs LARPER_TOKEN && LARPER_TOKEN="$LARPER_TOKEN" larpercord
```

No Windows, no PowerShell. A última linha tira a variável da janela; o app já ficou com a cópia dele:

```powershell
$env:LARPER_TOKEN = [Net.NetworkCredential]::new('', (Read-Host 'Token' -AsSecureString)).Password
& "$env:LOCALAPPDATA\Programs\larperCord\larpercord.exe"
Remove-Item Env:LARPER_TOKEN
```

Esse caminho é onde o `install.ps1` instala o app; se você descompactou o zip, use essa pasta. Se o larperCord já estiver aberto, mesmo só na bandeja, encerre antes (**Sair** no menu do ícone da bandeja): abrir de novo só traz de volta a janela aberta e ignora a variável.

## A tela de login

Sem token, o app abre a tela de login (`--login` força). Você pode colar um token ou escolher **Explorar o modo demonstração**, e a tela tem o próprio link de ajuda. Com **Lembrar neste computador** ligado, o token só é salvo depois que o Discord o aceita.

## Várias contas

Clique no seu próprio nome para abrir o menu de contas. Ele lista as contas guardadas com nome e foto, e a troca vale na hora. **Adicionar conta** volta à tela de login sem esquecer as outras.

A tela de login também lista as contas guardadas, então dá para entrar em outra se uma sessão acabar. Quando o Discord recusa um token, o app esquece esse token em vez de tentar de novo a cada abertura.

| O quê | Linux | Windows |
|---|---|---|
| Cada token lembrado | Uma entrada própria do chaveiro (`service larpercord-account account <ID>`). Sem chaveiro: `~/.config/larpercord/tokens/<ID>`, `chmod 600` | Uma entrada própria no Gerenciador de Credenciais (Credenciais do Windows → Credenciais Genéricas, `larperCord/account/<ID>`). Se falhar: `%APPDATA%\larpercord\tokens\<ID>` |
| A lista de contas (só ID, nome e foto) | `~/.config/larpercord/accounts` | `%APPDATA%\larpercord\accounts` |

No Linux, a entrada do chaveiro da primeira seção continua valendo para a conta que já estava nela. **Sair** apaga o token da conta de onde ele estiver.

## Sair

Configurações → **Sair**. Para forçar o modo demonstração mesmo com um token salvo, abra o app com `--demo`: `larpercord --demo` no Linux. No Windows, ponha ` --demo` no fim do **Destino** de um atalho, ou rode `& "$env:LOCALAPPDATA\Programs\larperCord\larpercord.exe" --demo` no PowerShell. O `--demo` abre mesmo com outra cópia na bandeja.

## O que passa pela rede

Com um token, o app fala com o gateway e a API REST do Discord, e com os servidores de mídia do Discord para as imagens. Veja [Privacidade e segurança](page:privacy) para os detalhes, incluindo o proxy opcional.
