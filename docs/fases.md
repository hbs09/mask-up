# Roteiro

Secção 10 do documento de projeto, com caixas para marcar. Cada fase tem um
critério de conclusão concreto — resiste à tentação de avançar sem ele.

---

## Fase 0 — Preparação (2 a 3 semanas)

- [x] Instalar o Studio, explorar Explorer, Properties e Output
- [x] Script vs LocalScript; primeiro script (porta com E)
- [ ] Luau: variáveis, if, ciclos, funções, tabelas, eventos
- [ ] **Escolher nome do jogo e da gangue** ← única tarefa a bloquear o resto

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
- [ ] Guarda que patrulha
- [ ] Guarda que vê
- [ ] Vagas de polícia
- [ ] HUD

**Concluída quando:** todas as peças funcionam sozinhas, com a lógica no servidor.

### Em curso: a fatia vertical

Antes das peças todas, o objetivo imediato é um assalto mínimo que corra do
início ao fim — a regra de ouro nº5 ("pequeno e completo antes de grande"):

- [x] `ValidacaoCore` — as quatro verificações da regra de ouro nº2 (24 testes)
- [x] `PerfilCore` — perfil e migração de versão (27 testes)
- [x] `Config` e `HeistState` — invariantes do jogo (20 testes)
- [x] `DataService` — adaptador, perfil de sessão
- [x] `AlarmService` — porta de entrada única
- [ ] `HeistCore` — transições, contagem de sacos, pagamento com bónus furtivo
- [ ] `LootCore` — posse de sacos, limite, WalkSpeed, entrega
- [ ] `MapBuilder` — joalharia de teste gerada por código
- [ ] `HeistService` e `LootService` — adaptadores sobre o core
- [ ] `HUDController` e `InteractController`
- [ ] Jogar `Lobby → Furtivo → saco → carrinha → Fuga → Fim` com 2 jogadores

## Fase 2 — Primeiro assalto completo (3 a 4 semanas)

- [ ] Mapa da joalharia (a sério, não o gerado por código)
- [ ] Lobby
- [ ] Caminhos furtivo e barulhento
- [ ] Ecrã final
- [ ] Derrota e reanimar

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

**Concluída quando:** as compras funcionam em teste e nenhuma é obrigatória.

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
