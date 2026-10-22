# Wakeful (nome provisório)

App de barra de menus para macOS que impede o Mac de dormir, concorrente do Caffeinated e do Amphetamine,
com foco em quem deixa agentes de IA, builds e scripts rodando. Interface em 34 idiomas, página da App Store
pronta para 39 locais.

## Rodar

```bash
xcodegen generate
open Wakeful.xcodeproj
```

Build local assinado com o certificado Apple Development (sem perfil de provisionamento):

```bash
scripts/build-dev.sh
```

Para testar a compra do Pro, rode pelo Xcode: o esquema já usa `StoreKit/Wakeful.storekit`.
No Debug, `-debugUnlockPro YES` nos argumentos de lançamento libera o Pro sem comprar.

## Recursos

**Grátis**
- Clique esquerdo liga/desliga, clique direito abre o menu (invertível)
- Durações de 15 min a 8 h, personalizada, contagem regressiva na barra
- Atalho global, abrir no login, notificação ao terminar, deixar só a tela apagar
- Proteção de bateria (para na bateria ou abaixo de X%)
- Atalhos (App Intents com frases em 34 idiomas), widget de mesa, controle na Central de Controle (macOS 26)
- URL `wakeful://start?minutes=45`, `stop`, `toggle`, `settings?tab=automation`

**Pro (compra única `com.dionlima.wakeful.pro`)**
- Modo agente de IA: liga sozinho enquanto `claude`, `codex`, `gemini`, `aider`… rodam
- Gatilhos: monitor externo, carregador, Wi‑Fi, app aberto, app em primeiro plano, câmera/microfone, agenda
- Manter acordado enquanto um processo/app roda (`bin/wakeful run <comando>` ou `wakeful://watch?pid=`)
- Tampa fechada (assertion `PreventSystemSleep`, só vale na tomada)
- Histórico local com gráfico dos últimos 7 dias

Notas técnicas
- No App Sandbox, `proc_listallpids` não enxerga nada; a lista de processos usa `sysctl(KERN_PROC_ALL)`.
- Widget e Central de Controle leem o estado via App Group `UL28GCBV3R.com.dionlima.wakeful` e mandam
  comandos ao app pelo esquema de URL.
- `ImageRenderer` não desenha `NSImage` direito (cobre a imagem de cinza); o gerador de screenshots só usa SwiftUI puro.

## Traduções

Fonte: `scripts/l10n/keys.json` (lista numerada) + `scripts/l10n/<idioma>.txt` (`N|tradução`).

```bash
python3 scripts/l10n/build_catalogs.py
```

O script recusa gravar se faltar uma linha ou se algum `%@`/`%lld` mudar. Ao adicionar texto novo no código:
rode `scripts/build-dev.sh` e `python3 scripts/l10n/extract_keys.py`, que acrescenta as frases novas no fim de
`keys.json` e lista os números para traduzir em cada `<idioma>.txt`.

## Publicação

```bash
python3 scripts/store/build_metadata.py   # textos da loja: fastlane/metadata (39 locais)
scripts/render-screenshots.sh             # screenshots 2880×1800: fastlane/screenshots (39 locais)
swift scripts/make-icon.swift Wakeful/Assets.xcassets/AppIcon.appiconset
```

Fontes dos textos da loja: `store/metadata/<idioma>.txt`. Notas para o revisor da Apple: `store/review-notes.txt`.
Nomes e descrições da compra Pro por local: `store/iap-pro.json`. Site e política de privacidade: `docs/` (GitHub Pages).

### Falta fazer (precisa da sua conta)
- [ ] Criar o app no App Store Connect (bundle `com.dionlima.wakeful`, nome "Wakeful: Keep Mac Awake")
- [ ] Criar a compra não consumível `com.dionlima.wakeful.pro`, com Compartilhamento Familiar
- [ ] Definir o preço do app (grátis) e do Pro; disponibilidade em todos os países
- [ ] Preencher telefone e e-mail em `fastlane/metadata/review_information/` e `SUPPORT_EMAIL` em `scripts/store/build_metadata.py`
- [ ] Publicar o repositório no GitHub e ativar o Pages na pasta `docs/`
- [ ] Responder o questionário de privacidade do App Store Connect: "Dados não coletados"
- [ ] Archive no Xcode, enviar o build e rodar `fastlane deliver` com uma chave da API do App Store Connect
- [ ] Testar fisicamente: tampa fechada na tomada, gatilho de câmera/microfone numa chamada, widget e controle da Central de Controle
- [ ] Revisão das traduções por falantes nativos (foram feitas por IA)
