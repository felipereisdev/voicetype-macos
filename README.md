# VoiceType

App de barra de menu para macOS: você segura um atalho, fala, e o texto transcrito e refinado é colado no app em foco. Também grava reuniões (Teams, Meet, Zoom…) e gera nota com resumo no Obsidian, e captura ideias por voz direto na daily note.

> macOS 14+ (Sonoma) · Apple Silicon (arm64) · Swift 5.10 + SwiftUI + AppKit · uso pessoal (single-user).

## O que faz

### Ditado
- **Segure** o atalho (padrão na primeira execução: `Fn` em teclado Apple, senão `Control+Alt`), fale, **solte**: o texto refinado é colado no app em foco.
- **Mãos livres:** toque duplo no atalho trava a gravação; outro toque encerra e cola. `Espaço` enquanto segura também trava. `Esc` cancela.
- **Tradução** (opcional, `Cmd+Shift+E`): transcreve e traduz para o idioma configurado.
- Transcrição **on-device** (WhisperKit) com fallback Groq; refino **on-device** (Apple Intelligence / FoundationModels, quando disponível) com fallback Groq. Sem rede, cola o texto cru.
- Estilo de refino por app/categoria, vocabulário próprio, contexto do cursor, aprender com suas edições (Configurações → Estilo por app / Vocabulário).
- Histórico com Recolar / Copiar / Apagar.
- Limite de 5 min por gravação: ao atingir, encerra e processa o que foi gravado.

### Nota de voz (`Alt+N`)
Segure `Alt+N` e fale uma ideia. O texto vira uma nota com título e tags em `<pasta>/Ideas/AAAA/AAAA-MM-DD HHmm Título.md`, com link na daily note do dia (`<pasta>/Daily/AAAA/AAAA-MM-DD.md`, seção `## Ideias`). Título e tags vêm do Claude CLI; sem ele, a ideia entra na daily sem título.

### Gravação de reunião
- **Detecção automática:** quando um app de reunião (Teams, Zoom, Meet/WebRTC no navegador…) abre o microfone, aparece um cartão no canto superior direito com contagem de 10 s: "Gravar" / "Agora não" (passar o mouse pausa a contagem). Modo configurável: perguntar, gravar automático ou desligado. Para sozinha quando a chamada termina.
- Enquanto grava, o ícone da barra de menu ganha um ponto vermelho. Também dá para iniciar/parar manualmente pelo menu ("Gravar reunião").
- Grava microfone + áudio do sistema, transcreve localmente (WhisperKit) e gera o resumo com o **Claude CLI** (`claude -p`, usa sua assinatura, não API paga).
- Separa as vozes remotas localmente (FluidAudio, macOS 15+): no transcript e no resumo você é "Você" e os demais viram "Outro 1", "Outro 2"… (sem nomes). No macOS 14 ou com uma voz só, fica "Outros".
- **Calendário (opcional):** com acesso concedido em Configurações → Reuniões, o app acha no Calendário do Mac o evento que coincide com a gravação. Contas Exchange/Outlook e Google adicionadas em Ajustes → Contas de Internet também contam. O título do convite orienta o da nota, organizador e convidados viram `[[Nome]]` no frontmatter, e o resumo pode sugerir quem é cada "Outro N" ("provavelmente [[Ana Silva]]") quando a conversa deixa claro. O rótulo original da transcrição nunca é trocado. O calendário nunca inicia nem para gravações.
- Saída em Markdown pronta para **Obsidian**:
  - `<pasta>/Meetings/AAAA/…md` — nota com resumo, decisões e tarefas (formato Dataview `[owner::] [due::]`), frontmatter com organização/cliente;
  - `<pasta>/Transcripts/AAAA/…md` — transcrição completa;
  - `<pasta>/<Organização>.md` — nota-índice por organização (criada uma vez).
- O áudio (`.caf`) é apagado após N dias (padrão 7) quando a nota já existe. "Reprocessar última reunião" no menu refaz a nota.

## Instalação (para quem recebeu o repositório)

O app não é distribuído assinado pela Apple. Você compila e instala localmente com um **certificado de assinatura próprio**, que é o que faz o macOS lembrar as permissões (Microfone, Acessibilidade) entre reinstalações. Sem ele, cada reinstalação faz o macOS "esquecer" o app.

### 1. Pré-requisitos

- Mac Apple Silicon com macOS 14+.
- **Xcode** completo (App Store), aberto uma vez para aceitar a licença e instalar componentes.
- Chave da **Groq** (grátis): https://console.groq.com/keys
- Opcional, para resumo de reunião e título das ideias: **Claude Code CLI** instalado e logado (`claude` no terminal; o app procura em `~/.local/bin`, `/opt/homebrew/bin` e `/usr/local/bin`, ou configure o caminho em Configurações → Reuniões).
- Opcional: **Obsidian** apontando para a pasta das notas, com o plugin **Dataview** para as tarefas.

### 2. Criar o certificado de assinatura (uma vez só)

Crie um certificado autoassinado chamado exatamente **`VoiceType Local`**.

**Opção A — Acesso às Chaves (Keychain Access):**
1. Abra **Acesso às Chaves** → menu **Acesso às Chaves → Assistente de Certificado → Criar um Certificado…**
2. Nome: `VoiceType Local` · Tipo de Identidade: **Raiz Autoassinada** · Tipo de Certificado: **Assinatura de Código** → Criar.

**Opção B — Terminal (OpenSSL 3):**
```bash
brew install openssl@3
OPENSSL=$(brew --prefix openssl@3)/bin/openssl
$OPENSSL req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=VoiceType Local" \
  -addext "extendedKeyUsage=codeSigning" -addext "keyUsage=digitalSignature" \
  -keyout key.pem -out cert.pem
$OPENSSL pkcs12 -export -legacy -inkey key.pem -in cert.pem -out id.p12 -passout pass:tmp
security import id.p12 -k ~/Library/Keychains/login.keychain-db -P tmp -T /usr/bin/codesign
rm key.pem cert.pem id.p12
```

Confira:
```bash
security find-identity -p codesigning | grep "VoiceType Local"
```
O certificado não precisa ser "confiável" no sistema; o `codesign` só precisa da chave privada. Para usar outro nome: `VOICETYPE_SIGN_IDENTITY="Meu Cert" ./macos/scripts/install.sh`.

### 3. Compilar e instalar

Da raiz do repositório:
```bash
./macos/scripts/install.sh
```
Compila em Release, copia para `/Applications/VoiceType.app`, assina com `VoiceType Local` e abre o app. Na primeira assinatura o macOS pode pedir a senha do chaveiro para o `codesign` — escolha **Sempre Permitir**. Para atualizar depois: `git pull` e rodar o mesmo comando (não rode durante uma gravação de reunião: o app é reiniciado).

### 4. Permissões (primeira execução)

- **Microfone:** o macOS pergunta → Permitir.
- **Acessibilidade:** Ajustes do Sistema → Privacidade e Segurança → Acessibilidade → ativar VoiceType (necessário para o atalho global e para colar). O atalho passa a funcionar sozinho em ~1 s, sem reabrir.
- **Gravação de áudio do sistema:** pedida na primeira gravação de reunião → Permitir.
- **Calendário (opcional):** Configurações → Reuniões → Permitir acesso.
- **Notificações:** permitir, para ver avisos de erro e de "ideia salva".

### 5. Configurar

Ícone na barra de menu → **Configurações…**:
- **Geral:** cole a chave Groq (`gsk_…`) e clique em Testar.
- **Atalhos:** ditado, tradução, nota de voz, mãos livres.
- **Reuniões:** pasta das notas (padrão `~/Documents/Meetings`; aponte para dentro do seu vault Obsidian), modo de detecção, retenção do áudio, caminho do Claude CLI e o **catálogo de organizações/clientes** usado para classificar as notas. O catálogo começa só com "Pessoal"; adicione suas organizações e clientes (ficam só no seu `config.json`).
- Áudio, transcrição/refino local, estilo, vocabulário, aparência, histórico, inicialização (abrir no login + status das permissões).

Tudo salva automaticamente.

## Desenvolvimento

```bash
open macos/VoiceType.xcodeproj   # Cmd+R roda em Debug
```

| Comando | Descrição |
|---|---|
| `xcodebuild -project macos/VoiceType.xcodeproj -scheme VoiceType -configuration Debug build` | Build Debug |
| `cd macos/VoiceTypeCore && swift test` | Testes do Core (swift-testing) |
| `xcodebuild test -project macos/VoiceType.xcodeproj -scheme VoiceType -only-testing:VoiceTypeTests` | Testes do app |
| `./macos/scripts/install.sh` | Release → `/Applications`, assinado com `VoiceType Local` |
| `./macos/scripts/release.sh` | DMG ad-hoc (`dist/`) |
| `./macos/scripts/make-icons.sh [icon.svg]` | Regenera o AppIcon |

Se `xcode-select -p` apontar para CommandLineTools, prefixe os comandos com `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Troubleshooting

**Atalho não funciona / texto não cola** — Acessibilidade não concedida. Ajustes → Privacidade e Segurança → Acessibilidade → VoiceType ligado. Se outro app usa a mesma combinação, troque em Configurações → Atalhos.

**Permissões somem após reinstalar** — o app não foi assinado com `VoiceType Local` (instale só via `install.sh`). Para limpar permissões órfãs uma vez:
```bash
pkill -9 -f VoiceType
tccutil reset Microphone com.macsilva.VoiceType
tccutil reset Accessibility com.macsilva.VoiceType
open /Applications/VoiceType.app
```
Depois, em Acessibilidade, `+` → `/Applications/VoiceType.app` → ligar.

**`install.sh`: "code-signing identity not found"** — falta o passo 2.

**Transcrição vira "E aí," repetido / "Áudio silencioso"** — o microfone escolhido não está entregando som. Troque o dispositivo em Configurações → Áudio (ou Ajustes → Som → Entrada).

**Reunião sem resumo** — Claude CLI ausente ou deslogado. Rode `claude` no terminal para logar e use "Reprocessar última reunião" no menu.

**Reset completo:**
```bash
rm ~/Library/Application\ Support/VoiceType/config.json
rm ~/Library/Application\ Support/VoiceType/history.json
```

## Limitações

- Sem assinatura Apple/notarização nem auto-update: atualizar = `git pull` + `install.sh`.
- Apple Silicon apenas.
- Refino on-device só com Apple Intelligence ativo (idioma do Mac = idioma da Siri); senão usa Groq.

## Documentação técnica

- `docs/architecture.md` — componentes, fluxo, permissões, armazenamento.
- `docs/decisions.md` — ADRs.
- `docs/gotchas.md` — armadilhas e contornos.
- `docs/follow-ups.md` — débitos técnicos.

## Licença

MIT.
