# Roteiro

Secção 10 do documento de projeto, com caixas para marcar. Cada fase tem um
critério de conclusão concreto — resiste à tentação de avançar sem ele.

---

## Fase 0 — Preparação (2 a 3 semanas)

- [x] Instalar o Studio, explorar Explorer, Properties e Output
- [x] Script vs LocalScript; primeiro script (porta com E)
- [ ] Luau: variáveis, if, ciclos, funções, tabelas, eventos
- [x] Escolher nome do jogo: **Mask Up**
- [x] ~~Escolher nome da gangue~~ → **não é uma decisão, é uma funcionalidade**

> **O nome da gangue é escolhido pelo anfitrião do lobby**, não fixado no jogo.
>
> Encaixa no papel que a secção 4 do documento já estabelece — *"o anfitrião
> escolhe a dificuldade"* — e reforça o cooperativo, que o documento chama o
> trunfo do jogo. Cada grupo tem a sua identidade em vez de todos pertencerem à
> mesma gangue inventada por mim.
>
> Implementação na Fase 2, com o lobby. Ver `docs/arquitetura.md`.

**Concluída quando:** crias e ligas um script a um objeto sem seguir um tutorial
passo a passo.

> Além do previsto nesta fase, já está montado: Rojo a sincronizar com o Studio,
> Lune a correr testes em ~30ms, StyLua e Selene, CI no GitHub Actions, e a
> arquitetura core puro + adaptadores. Ver [arquitetura.md](arquitetura.md).

## Fase 1 — Mecânicas base (4 a 6 semanas)

- [ ] Saco de dinheiro
- [ ] Zona de fuga
- [ ] Alarme — *`AlarmService` feito; falta quem o dispare*
- [ ] Minijogo do cabo
- [ ] Broca
- [x] Guarda que patrulha
- [x] Guarda que vê
- [ ] Vagas de polícia
- [x] HUD

**Concluída quando:** todas as peças funcionam sozinhas, com a lógica no servidor.

### ✅ Guardas concluídos — 12 de outubro de 2026

`GuardaCore` (45 testes) + `GuardService`. Confirmado no Studio: 3 guardas em
ronda, barra de suspeição a subir e descer, raycast a bloquear a visão atrás do
balcão, e o alarme a disparar pelo `AlarmService`. O `BotaoAlarmeTeste` saiu.

Os guardas vigiam em `Furtivo` **e** em `Fuga` — ser visto a caminho da carrinha
tira o bónus furtivo sem rebobinar o estado.

**Equilíbrio, que falhou à primeira:** com `visao.distancia = 40`, os três cones
cobriam **157% da área da loja** e o assalto era impossível (apanhado em 17 a 45
segundos). Baixado para 20 (39% de cobertura). A invariante em
`tests/Config.spec.luau` fixa agora essa relação — a versão anterior do teste era
folgada demais para notar.

### Em curso: a fatia vertical

Antes das peças todas, o objetivo imediato é um assalto mínimo que corra do
início ao fim — a regra de ouro nº5 ("pequeno e completo antes de grande"):

- [x] `ValidacaoCore` — as quatro verificações da regra de ouro nº2 (24 testes)
- [x] `PerfilCore` — perfil e migração de versão (27 testes)
- [x] `Config` e `HeistState` — invariantes do jogo (20 testes)
- [x] `DataService` — adaptador, perfil de sessão
- [x] `AlarmService` — porta de entrada única
- [x] `HeistCore` — transições, contagem de sacos, pagamento (51 testes)
- [x] `LootCore` — posse de sacos, limite, WalkSpeed, entrega (34 testes)
- [x] `MapBuilder` — joalharia de teste gerada por código
- [x] `HeistService` e `LootService` — adaptadores sobre o core
- [x] `HUDController` e `InteractController`
- [x] Jogar `Lobby → Furtivo → saco → carrinha → Fuga → Fim` com 2 jogadores

### ✅ Fatia vertical concluída — 12 de outubro de 2026

Confirmada no Studio com 2 jogadores. Do log do servidor:

```
Lobby -> Furtivo              15s depois do arranque
Furtivo -> Fuga               2 sacos entregues
Fuga -> Fim                   exactamente 60s (tempos.fuga)
fim do assalto: 2 sacos, 25000 bruto, 31250 por jogador, furtivo=true
Fim -> Lobby                  exactamente 10s (tempos.fim)
```

O pagamento confere: 5000 (montra) + 20000 (cofre) = 25000, × 1.25 de bónus
furtivo = 31250.

A validação de segurança também ficou provada em runtime, e não apenas nos
testes — o botão do alarme premido durante o `Lobby` foi recusado com motivo
`estado`, funcionou em `Furtivo`, e voltou a ser recusado já em `Alarme`.

## Fase 2 — Primeiro assalto completo (3 a 4 semanas)

- [ ] Mapa da joalharia (a sério, não o gerado por código)
  - [ ] **Recalibrar a invariante de cobertura** — ver aviso abaixo
  - [ ] Colocar `Waypoints/` à mão, com rotas que façam sentido no mapa real
  - [ ] Apagar o `MapBuilder` e o `tests/_geometria.luau`

### ⚠️ A invariante de cobertura vai mentir no mapa novo

`tests/Config.spec.luau` tem a área da loja **fixa no código**:

```luau
local AREA_DA_LOJA = 60 * 40
```

É o tamanho da joalharia gerada pelo `MapBuilder`. Num mapa real maior, essa
invariante passa a dizer que a cobertura está confortável quando não está — e um
teste que dá falsa confiança é pior do que não ter teste.

Foi esta conta que apanhou o assalto impossível (157% de cobertura), por isso
não é um detalhe: é o guarda que nos protege de voltar a lá cair.

**Quando o mapa real chegar:** a área tem de vir do mapa, não de um número
escrito à mão. Opções, por ordem de preferência:

1. Uma Part invisível `Map/AreaJogavel` cujo tamanho o teste lê — mas isso obriga
   o teste a abrir um ficheiro `.rbxlx`, o que o Lune até sabe fazer
2. A área declarada no `Config` e verificada contra o mapa num teste de
   integração no Studio
3. No mínimo, uma constante no `Config` em vez de literal no teste, para haver um
   único sítio a mudar

### O que sobrevive à troca de mapa

Útil ter isto claro antes de a Fase 2 começar:

| | Portável? |
|---|---|
| `src/Server/Core/` — 1337 linhas, 238 testes | ✅ Intacto. Trabalha com ids, posições e tempo injetado; não sabe que o mapa existe |
| `Services/` e `Controllers/` | ✅ Procuram tudo **por nome** (`Loot/`, `Waypoints/`, `Guards/`, `EscapeZone/Zona`), não por posição |
| Modelos, Parts, geometria | ❌ Substituídos pelos modelos a sério |
| Números do equilíbrio no `Config` | ⚠️ Calibrados para 60×40 — recalibrar |
| `MapBuilder`, `tests/_geometria.luau` | ❌ Descartáveis por desenho |
- [ ] Lobby
  - [ ] O anfitrião escolhe a dificuldade (secção 4 do documento)
  - [ ] **O anfitrião escolhe o nome da gangue** (ver abaixo)
- [ ] Caminhos furtivo e barulhento
- [ ] Ecrã final
- [ ] Derrota e reanimar

### Nome da gangue: três partes, não uma

O anfitrião escreve o nome e ele aparece no lobby, no HUD e no ecrã final.

**O filtro não é opcional.** Texto escrito por um jogador e mostrado a outros tem
de passar por `TextService:FilterStringAsync` **no servidor** antes de ser
guardado ou enviado. É política da Roblox, e com um público que inclui crianças é
o tipo de omissão que dá moderação ao jogo.

| Parte | Onde |
|---|---|
| Interface, visível só ao anfitrião | `Controllers/` (cliente) |
| Filtrar e guardar | servidor — nunca confiar no texto que chega |
| Mostrar no lobby, HUD e ecrã final | `HUDController` |

Por decidir quando se implementar:

- **Quem é o anfitrião?** O primeiro jogador a entrar, ou quem criou o servidor
  privado? Afeta o que acontece quando ele sai a meio.
- **O nome persiste?** Guardado no perfil do anfitrião (e o `PerfilCore` ganha um
  campo) ou só dura a sessão?

**Concluída quando:** 4 amigos jogam do início ao fim sem bugs graves, nos dois
modos.

## Fase 3 — Progressão (3 a 4 semanas)

- [ ] DataStore — *`PerfilCore` já pronto e testado; falta só o armazenamento*
- [ ] Níveis e XP — *já feito no `PerfilCore`*
- [ ] Loja e máscaras
- [ ] Recompensa diária e desafios
- [ ] Segundo assalto
- [ ] Dificuldades

**Concluída quando:** o progresso fica guardado e há sempre algo novo para
desbloquear.

## Fase 4 — Testes e polimento (2 a 3 semanas)

- [ ] Testes com amigos
- [ ] Tutorial
- [ ] Sons e iluminação
- [ ] Telemóvel e tablet
- [ ] Testes de segurança
- [ ] Ícone e miniaturas

**Concluída quando:** alguém novo percebe o jogo sem ajuda e quer jogar outra vez.

## Fase 5 — Monetização (2 semanas)

- [ ] Criar produtos e passes
- [ ] `MarketplaceService` e `ProcessReceipt`
- [ ] Ligar o kit ao minijogo do cabo
- [ ] **Disfarce** — consumível para evitar o alarme (ver decisão abaixo)

**Concluída quando:** as compras funcionam em teste e nenhuma é obrigatória.

### Decisão: o "Disfarce", e porque não é um pop-up

**Ideia original:** quando um guarda te vê durante a fuga e perdes o bónus
furtivo, oferecer *"paga X para não perderes o bónus"*.

**Rejeitada nessa forma.** É literalmente o que a secção 9 do documento manda
evitar:

> muitos jogadores são crianças, por isso nada de temporizadores falsos nem
> **pop-ups de compra a cada falhanço**

Uma oferta de pagamento no momento da perda, com pressão de tempo porque estás a
fugir, é um padrão escuro. Num público com crianças atrai queixas de pais e
atenção regulatória, e é má fama para o jogo.

**Forma aprovada** — o mesmo modelo do Kit de emergência que o documento já
prevê:

- Um consumível (`Disfarce`) que o jogador **leva para o assalto**
- Comprado **antes**, no esconderijo: dinheiro do jogo **ou** Robux
- **Também se ganha a jogar**, como o documento exige
- Usado com uma tecla, por decisão do jogador: limpa a suspeição de quem o está
  a notar e evita o alarme uma vez

A diferença que importa: é uma **decisão tática tomada com calma**, não uma
compra por impulso num momento de frustração. Monetiza o mesmo momento sem o
padrão escuro.

Implementar a mecânica (perfil, loja com dinheiro do jogo, tecla, ligação ao
`GuardaCore`) antes do `MarketplaceService` — assim descobrimos se é divertido
antes de montar pagamentos.

## Fase 6 — Lançamento (contínuo)

- [ ] Publicar
- [ ] Grupo Roblox e Discord
- [ ] Estatísticas de retenção (dia 1 e dia 7)
- [ ] Atualização a cada 3 a 4 semanas

**Concluída quando:** os jogadores voltam no dia seguinte sem ser preciso
lembrá-los.

---

## Testes de segurança (Fase 4, mas vale fazer já)

A regra de ouro nº2 não é teórica. Na consola do cliente, dentro do Studio:

- [ ] `PickUpBag` disparado a 200 studs de distância → servidor recusa
- [ ] `PickUpBag` com um objeto inventado ou `nil` → recusa sem erro no Output
- [ ] `PickUpBag` em espiral rápido → o cooldown aguenta
- [ ] `RequestInteract` durante o estado `Lobby` → recusado
- [ ] Alterar `WalkSpeed` localmente → não acelera a entrega

> Os quatro primeiros já estão cobertos por testes automáticos em
> `tests/ValidacaoCore.spec.luau`. Confirmar no Studio serve para validar que o
> adaptador liga os Remotes ao validador corretamente.
