# Arquitetura: core puro e adaptadores

Este documento explica a única decisão de arquitetura que não vem do documento de
projeto original, e porque é que ela foi tomada.

## O problema

O projeto é desenvolvido com TDD desde o início. Para TDD valer a pena, o ciclo
vermelho-verde-refactor tem de ser rápido: se correr os testes custar meio minuto,
deixas de os correr.

As opções para testar Luau são três:

| Opção | Fidelidade | Velocidade | Estado |
|---|---|---|---|
| **TestEZ** (Roblox) | Alta, corre no Studio | Lenta | **Arquivado** desde março de 2024 |
| **Jest Lua** + run-in-roblox | Alta, APIs reais | 20-30s por corrida | Exige Wally; parado desde 2024 |
| **Lune** | Só Luau, sem runtime do Roblox | ~30ms | Ativo, mesma equipa do Rojo |

O Lune é a escolha óbvia pela velocidade, mas tem uma limitação decisiva: suporta
`Instance.new` e propriedades, mas **não tem serviços de runtime**. Não existe
`Players`, `RunService`, `PathfindingService`, nem eventos. É um runtime de Luau,
não um simulador do Roblox.

## A consequência

Se a lógica do jogo estiver misturada com chamadas ao Roblox, não é testável no
Lune. Logo, a lógica tem de ficar separada das chamadas ao Roblox.

Isto não é um sacrifício feito por causa da ferramenta — é o padrão
*ports and adapters*, e dá o mesmo resultado que se chegaria por outras razões:
a lógica de um jogo é mais fácil de raciocinar quando não está entrelaçada com
`WaitForChild` e `Humanoid.WalkSpeed`.

## Como está organizado

```
src/Server/
  Core/        LÓGICA PURA. Zero requires. Não conhece game, Instance,
               Vector3 nem os.time. Recebe tudo por parâmetro.
  Services/    ADAPTADORES. Traduzem entre o mundo do Roblox e o Core.
```

### O Core não faz um único `require`

Isto parece estranho até se perceber o motivo: em Roblox, um módulo faz
`require(script.Parent.Foo)`; no Lune faz `require("./Foo")`. As duas formas são
incompatíveis, e `script` não existe fora do Roblox.

A solução é injeção de dependências. O Core recebe o que precisa:

```lua
-- Em vez de o Core ir buscar o Config...
local validador = ValidacaoCore.novo(Config.interacao)

-- ...e em vez de chamar os.time() lá dentro, o instante vem no pedido:
validador:podeInteragir({ agora = os.time(), ... })
```

Receber o tempo por parâmetro tem um segundo benefício, maior que o primeiro:
**torna o tempo testável**. Testar um cooldown de meio segundo não exige esperar
meio segundo — passa-se `agora = 100` e depois `agora = 100.25`. O mesmo vale
para o temporizador da fuga.

### Posições são tabelas, não `Vector3`

O `ValidacaoCore` recebe `{ x = 0, y = 0, z = 0 }`. Converter de `Vector3` é
trabalho do adaptador — três linhas, num sítio só.

### O linter aplica a regra

Uma regra que vive num comentário é uma regra que se vai quebrar. O
[selene.toml](../selene.toml) usa `std = "luau"` — sem os globais do Roblox — e é
essa a configuração usada para verificar `src/Server/Core/`. Escrever `game` ali
passa a ser erro:

```
error[undefined_variable]: `game` is not defined
  = `game` was found in the roblox standard library
```

A mensagem é perfeita: o global existe no Roblox, mas não é permitido aqui.

Os adaptadores são verificados com [selene-roblox.toml](../selene-roblox.toml),
que carrega [roblox-minimo.toml](../roblox-minimo.toml).

## O que fica testado e o que não fica

| Camada | Como é verificada |
|---|---|
| `Core/` | Testes em Lune, exaustivos. Correm em ~30ms. |
| `Services/`, `Client/` | Testes manuais no Studio com 2 jogadores, mais o lint. |

Os adaptadores são **finos de propósito**: quanto menos lógica tiverem, menos
código fica fora da rede de segurança. Se um adaptador começar a ganhar `if`s e
contas, é sinal de que essa parte pertence ao Core.

Sinais de que a fronteira foi quebrada:

- um `.Magnitude <` dentro de um serviço — a distância é do `ValidacaoCore`
- um `require` dentro de um ficheiro do `Core/`
- um controlador do cliente a guardar estado de jogo — o cliente pede, não decide

## O harness de testes

Está em [tests/harness.luau](../tests/harness.luau), tem cerca de 200 linhas e
não tem dependências. Foi escrito em vez de se usar algo existente porque o
TestEZ está arquivado e o Jest Lua obrigaria ao Wally e a corridas de 20-30s.

Tem [auto-teste próprio](../.lune/autoteste-harness.luau): 24 verificações que
confirmam que cada matcher **falha quando deve**. Um framework de testes com um
bug que faça tudo passar é pior do que não ter testes, porque dá confiança falsa.

## Arranque: duas fases

O `Main.server.luau` chama `init()` em todos os serviços e só depois `start()`.
Isto existe para resolver um problema concreto: o `LootService` avisa o
`HeistService` quando um saco é entregue, e o `AlarmService` muda o estado do
assalto. Se cada um fizesse `require` do outro, haveria requires circulares.

Com duas fases, nenhum serviço faz `require` de outro serviço — as dependências
são passadas pelo `Main`, e a ordem de arranque fica visível num único ficheiro
em vez de implícita nos imports.
