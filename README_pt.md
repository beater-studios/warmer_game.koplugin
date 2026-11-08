# Warmer

[Read this in English](README.md)

Descubra a palavra secreta pelo sentido. Cada palpite mostra o quanto você chegou perto. Um jogo de adivinhar palavras para o [KOReader](https://koreader.rocks), em português, inglês e espanhol.

Um jogo da [Beater Studios](https://beaterstudios.com/).

| Início | Partida | Mais próximas |
|---|---|---|
| ![Tela inicial com idioma, sequência e menu](docs/screenshots/title.png) | ![Uma partida com os palpites ordenados pela posição e barras de proximidade](docs/screenshots/game.png) | ![As palavras mais próximas da palavra secreta depois de encontrá-la](docs/screenshots/result.png) |

## O jogo

- **Posições:** cada palpite recebe uma posição num ranking de proximidade de sentido com a palavra secreta. A palavra secreta é a posição 1. A barra ao lado de cada palpite mostra o quanto ele está perto.
- **Palavra do dia:** quem joga no mesmo idioma recebe a mesma palavra, sem precisar de internet.
- **Modo livre:** palavras sorteadas, sem limite por dia e sem mexer na sequência.
- **Dicas:** uma dica revela uma palavra na metade do caminho entre o seu melhor palpite e a palavra secreta.
- **Desistir:** revela a palavra secreta e as 100 palavras mais próximas dela.
- **Três idiomas:** português, inglês e espanhol. A interface segue o idioma escolhido.
- **Digitação:** o jogo tem teclado próprio, sempre na tela. Acentos são opcionais e o plural conta como singular. Palavras desconhecidas não contam, e uma palavra enviada de novo é mostrada onde já está na lista.
- **Estatísticas:** sequência, vitórias e média de palpites por idioma.
- **Compartilhar:** o resultado da palavra do dia vira um QR code que mostra o quanto os palpites chegaram perto, sem revelar nenhuma palavra.
- **Sem internet:** funciona offline e não coleta dados. O progresso é salvo a cada palpite.

## Instalação

Cada release tem três pacotes. O jogo é o mesmo; muda só o tamanho dos dados de sentido:

| Pacote | Tamanho | |
|---|---|---|
| `warmer_game.koplugin.zip` | cerca de 14 MB | Recomendado. |
| `warmer_game.koplugin-100d.zip` | cerca de 10 MB | Mais leve. As palavras próximas vêm numa ordem um pouco diferente. |
| `warmer_game.koplugin-300d.zip` | cerca de 28 MB | Dados completos, o ranking de referência. |

1. Baixe um deles na [última release](https://github.com/beater-studios/warmer_game.koplugin/releases/latest).
2. Extraia em `koreader/plugins/`, de modo que exista `koreader/plugins/warmer_game.koplugin/main.lua`.
3. Reinicie o KOReader. O jogo fica no menu Ferramentas, como **Warmer**.

Para trocar de pacote, extraia outro por cima da mesma pasta. As partidas em andamento continuam, com as posições recalculadas. A tela Sobre mostra quais dados estão instalados, e o resultado compartilhado também, para você saber se está comparando o mesmo ranking.

O progresso fica em `koreader/settings/warmer_game.lua`. Para desinstalar, apague a pasta do plugin e, se quiser, esse arquivo.

## Compatibilidade

- Testado no emulador do KOReader em 600x800, 758x1024, 1072x1448 e 1264x1680. A velocidade do ranking e a memória foram medidas num Kindle básico da 10ª geração: menos de um segundo para começar uma partida e cerca de 11 MB de memória.
- Precisa de tela sensível ao toque.
- O jogo é sempre em retrato. Aberto em paisagem, ele gira a tela e devolve a rotação ao sair.

## Desenvolvimento

Com o [LuaJIT](https://luajit.org) instalado, a partir da raiz do repositório:

```sh
luajit tools/validate_data.lua --no-vectors
luajit tests/engine_spec.lua
luajit tests/vectors_spec.lua
```

Os dados de sentido não ficam no repositório: `tools/data/fetch_sources.sh` baixa as fontes e `tools/data/build_data.py` gera os dados. As regras, os dados, as demais ferramentas e o processo de release estão em [docs/design.md](docs/design.md), em inglês. Para sugerir a remoção de uma palavra, abra uma issue. Contribuições são aceitas sob a licença do projeto.

## Licença

O código está sob a [GPL-3.0](LICENSE), somente a versão 3. Você pode usar, estudar, modificar e redistribuir, mantendo-o aberto sob a mesma licença.

Os dados do jogo são adaptados dos vetores de palavras do FastText, da Meta, e são distribuídos sob CC BY-SA 3.0. Créditos e licenças estão em [NOTICE](NOTICE).

Estes termos não dão direito aos nomes "Warmer" e "Beater Studios". Para outros usos, fale com a [Beater Studios](https://beaterstudios.com/).
