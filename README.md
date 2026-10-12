# Mask Up

Jogo cooperativo de assaltos para Roblox, 1 a 4 jogadores. Inspirado no género
PayDay mas com nome, gangue, máscaras e música próprios — sem usar nada da marca
PayDay (Starbreeze).

O nome liga-se à progressão cosmética central do jogo: as máscaras
personalizáveis que desbloqueias na loja e no esconderijo.

**Ciclo de jogo:** entrar no lobby com a equipa → escolher o assalto → tentar em
furtivo → se o alarme disparar, aguentar as vagas de polícia → levar os sacos até
à carrinha → receber dinheiro e XP → comprar equipamento no esconderijo → próximo
assalto.

A especificação completa está em [docs/especificacao.md](docs/especificacao.md) e o
roteiro em [docs/fases.md](docs/fases.md).

> **Nome da gangue ainda por decidir.** `The Masked` é uma sugestão de arranque,
> não uma decisão. Aparece só neste README, por isso mudá-lo não custa nada.
>
> Antes de publicares no Roblox, confirma na pesquisa do próprio Roblox que
> `Mask Up` continua livre. A pesquisa na web não indexa todos os jogos da
> plataforma, por isso a verificação que fiz é um indício, não uma garantia.

## Estado atual

Fase 1 a arrancar. O que já existe e está testado:

| Módulo | Estado |
|---|---|
| `ValidacaoCore` | Completo, 24 testes — as quatro verificações da regra de ouro nº2 |
| `PerfilCore` | Completo, 27 testes — perfil da secção 7 e migração de versão |
| `Config` / `HeistState` | Completos, 20 testes de invariantes |
| `DataService` | Adaptador funcional, perfil só de sessão (DataStore é Fase 3) |
| `AlarmService` | Completo — porta de entrada única do alarme |
| `HeistCore` / `LootCore` | **Por fazer** — a lógica da fatia vertical |
| `HeistService` / `LootService` / `MapBuilder` | Esqueletos com o contrato definido |
| `HUDController` / `InteractController` | Esqueletos |

**Ainda não há jogo para jogar.** A place constrói e os serviços arrancam, mas o
assalto não corre do início ao fim até o `HeistCore` e o `LootCore` existirem.

## Começar

Precisas de Roblox Studio e VS Code. Nada mais — o script trata do resto.

```powershell
# 1. Ferramentas (Rojo, Lune, StyLua, Selene) + plugin do Rojo no Studio
.\scripts\instalar-ferramentas.ps1

# 2. Confirmar que está tudo bem
.\scripts\verificar.ps1
```

As ferramentas ficam em `tools\` (fora do Git) com as versões fixadas em
[rokit.toml](rokit.toml).

> **Nota sobre o Norton nesta máquina.** O `rokit install` não funciona aqui: o
> Norton 360 intercepta HTTPS e o Rokit, escrito em Rust, rejeita o certificado
> injetado. O erro que aparece (`reqwest middleware error`) parece ser de rede,
> mas não é. O `instalar-ferramentas.ps1` descarrega via PowerShell, que usa a
> loja de certificados do Windows. **Nenhuma proteção foi desligada.** O mesmo
> problema afeta o `selene generate-roblox-std` (daí o
> [roblox-minimo.toml](roblox-minimo.toml) escrito à mão) e o `winget` com a
> fonte `msstore`. No CI do GitHub, que corre em Linux, o Rokit funciona normalmente.

## Trabalhar no projeto

### Correr os testes

```powershell
.\scripts\verificar.ps1              # formatação + lint + testes + build
.\scripts\verificar.ps1 -Formatar    # corrige a formatação em vez de só avisar
```

Durante o desenvolvimento, só os testes (bastante mais rápido):

```powershell
$env:PATH = "$pwd\tools;$env:PATH"
lune run .lune/tests.luau            # todos, ~30ms
lune run .lune/tests.luau Heist      # só os specs com "Heist" no nome
```

### Ver no Studio

```powershell
$env:PATH = "$pwd\tools;$env:PATH"
rojo build --output assaltos.rbxlx   # cria a place; abrir no Studio
rojo serve                           # e depois clicar "Connect" no painel do Rojo
```

Com o `rojo serve` a correr, tudo o que guardares no VS Code aparece no Studio
imediatamente. Para testar o cooperativo: `Test → Clients and Servers → 2 Players`.

## Estrutura

```
src/
  Shared/              -> ReplicatedStorage.Shared   (servidor e cliente)
    Config.luau          todos os números do jogo, congelado
    HeistState.luau      os cinco estados do assalto
    Remotes.luau         resolve os RemoteEvents
  Server/
    Main.server.luau     arranca os serviços pela ordem certa
    Core/                LÓGICA PURA, 100% testada, sem Roblox
    Services/            adaptadores finos sobre o Core
  Client/
    Client.client.luau
    Controllers/         HUD e interação — pedem, nunca decidem

tests/                 *.spec.luau + o harness
.lune/                 runner dos testes e auto-teste do harness
docs/                  especificação, arquitetura e roteiro
scripts/               instalar ferramentas e verificar
```

A divisão `Core/` versus `Services/` é a decisão mais importante do projeto e
está explicada em [docs/arquitetura.md](docs/arquitetura.md). Em resumo: o Lune
corre Luau fora do Roblox em milissegundos, mas não tem `game` nem `Instance`.
Pôr a lógica em módulos puros é o que torna o TDD viável — e o
[selene.toml](selene.toml) usa `std = "luau"` no `Core/` para o linter **recusar**
globais do Roblox ali, em vez de a regra viver só num comentário.

## Regras de ouro

Do documento de projeto, e aplicadas no código:

1. **O servidor manda.** Dinheiro, alarme, danos, sacos e compras decidem-se no
   servidor. O cliente mostra e pede.
2. **Nunca confiar no cliente.** Todo o `RemoteEvent` passa pelo `ValidacaoCore`:
   está vivo? perto? no estado certo? fora do cooldown? Nenhum serviço faz as
   suas próprias contas de distância.
3. **Um sistema = um módulo.** Pequeno e com uma só responsabilidade.
4. **Configuração em tabelas**, nunca números espalhados pelo código.
5. **Pequeno e completo antes de grande.** Um assalto a funcionar do início ao
   fim antes do segundo.

## Licença

Projeto privado. Nada da marca PayDay (Starbreeze) é usado — nome, gangue,
máscaras, música e arte são originais.
