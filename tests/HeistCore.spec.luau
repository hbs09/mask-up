--[[
	A maquina de estados do assalto (secção 4 do documento) e as contas do
	pagamento.

	E o modulo com mais regras do projeto, por isso e onde os testes dao mais
	retorno. Repara que nenhum destes testes espera tempo real: o core nao conhece
	temporizadores. Quem decide que o tempo acabou e o adaptador, que depois pede
	a transicao -- e por isso testar o fim da fuga e instantaneo.
]]

local HeistCore = require("../src/Server/Core/HeistCore")

local ESTADOS = {
	Lobby = "Lobby",
	Furtivo = "Furtivo",
	Alarme = "Alarme",
	Fuga = "Fuga",
	Fim = "Fim",
}

-- Valores explicitos: afinar o Config nao deve partir estes testes.
local CONFIG = {
	minimoSacosParaFuga = 2,
	sacos = {
		pequeno = { valor = 1000, velocidade = 14 },
		grande = { valor = 5000, velocidade = 10 },
	},
	recompensas = {
		bonusFurtivo = 1.5,
		xpPorSacoPequeno = 10,
		xpPorSacoGrande = 50,
	},
}

local function novoCore()
	return HeistCore.novo({ config = CONFIG, estados = ESTADOS })
end

-- Leva o assalto ate ao estado pedido pelo caminho normal.
local function levarAte(core, estado)
	if estado == ESTADOS.Lobby then
		return core
	end

	core:transitar(ESTADOS.Furtivo)
	if estado == ESTADOS.Furtivo then
		return core
	end

	if estado == ESTADOS.Alarme then
		core:dispararAlarme("teste")
		return core
	end

	core:transitar(estado)
	return core
end

return function(t)
	t.describe("HeistCore", function()
		t.describe("arranque", function()
			t.it("comeca no Lobby", function()
				t.expect(novoCore():estadoAtual()).toBe(ESTADOS.Lobby)
			end)

			t.it("comeca sem sacos entregues", function()
				t.expect(novoCore():totalSacosEntregues()).toBe(0)
			end)

			t.it("comeca a contar como furtivo", function()
				t.expect(novoCore():foiFurtivo()).toBe(true)
			end)
		end)

		t.describe("transicoes legais (secção 4 do documento)", function()
			t.it("Lobby -> Furtivo", function()
				local core = novoCore()
				t.expect(core:transitar(ESTADOS.Furtivo)).toBe(true)
				t.expect(core:estadoAtual()).toBe(ESTADOS.Furtivo)
			end)

			t.it("Furtivo -> Alarme", function()
				local core = levarAte(novoCore(), ESTADOS.Furtivo)
				t.expect(core:transitar(ESTADOS.Alarme)).toBe(true)
			end)

			t.it("Furtivo -> Fuga", function()
				local core = levarAte(novoCore(), ESTADOS.Furtivo)
				t.expect(core:transitar(ESTADOS.Fuga)).toBe(true)
			end)

			t.it("Alarme -> Fuga", function()
				local core = levarAte(novoCore(), ESTADOS.Alarme)
				t.expect(core:transitar(ESTADOS.Fuga)).toBe(true)
			end)

			t.it("Fuga -> Fim", function()
				local core = levarAte(novoCore(), ESTADOS.Fuga)
				t.expect(core:transitar(ESTADOS.Fim)).toBe(true)
			end)

			t.it("Fim -> Lobby, fechando o ciclo", function()
				local core = levarAte(novoCore(), ESTADOS.Fim)
				t.expect(core:transitar(ESTADOS.Lobby)).toBe(true)
				t.expect(core:estadoAtual()).toBe(ESTADOS.Lobby)
			end)

			t.it("Furtivo -> Fim (tempo esgotado sem nada entregue)", function()
				-- O documento diz que se entra em Fim por "tempo esgotado", e isso
				-- pode acontecer antes de haver saque para chamar a fuga.
				local core = levarAte(novoCore(), ESTADOS.Furtivo)
				t.expect(core:transitar(ESTADOS.Fim)).toBe(true)
			end)

			t.it("Alarme -> Fim (todos presos)", function()
				-- O documento lista "todos presos" como forma de entrar em Fim, e
				-- so se e preso depois do alarme: sem esta transicao, essa
				-- condicao do proprio documento era inalcancavel.
				local core = levarAte(novoCore(), ESTADOS.Alarme)
				t.expect(core:transitar(ESTADOS.Fim)).toBe(true)
			end)
		end)

		t.describe("transicoes ilegais", function()
			t.it("Lobby -> Fuga e recusado", function()
				local core = novoCore()
				local ok, motivo = core:transitar(ESTADOS.Fuga)

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("transicao_ilegal")
				t.expect(core:estadoAtual()).toBe(ESTADOS.Lobby)
			end)

			t.it("Lobby -> Fim e recusado", function()
				t.expect(novoCore():transitar(ESTADOS.Fim)).toBe(false)
			end)

			t.it("nao se volta atras: Fuga -> Furtivo e recusado", function()
				local core = levarAte(novoCore(), ESTADOS.Fuga)
				t.expect(core:transitar(ESTADOS.Furtivo)).toBe(false)
			end)

			t.it("nao se desliga o alarme: Alarme -> Furtivo e recusado", function()
				local core = levarAte(novoCore(), ESTADOS.Alarme)
				t.expect(core:transitar(ESTADOS.Furtivo)).toBe(false)
				t.expect(core:estadoAtual()).toBe(ESTADOS.Alarme)
			end)

			t.it("transitar para o mesmo estado e recusado", function()
				local core = novoCore()
				t.expect(core:transitar(ESTADOS.Lobby)).toBe(false)
			end)

			t.it("um estado inventado e recusado", function()
				local core = novoCore()
				local ok, motivo = core:transitar("Inventado")

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("estado_desconhecido")
			end)

			t.it("nil nao rebenta nem muda o estado", function()
				local core = novoCore()
				local ok, motivo = core:transitar(nil :: any)

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("estado_desconhecido")
				t.expect(core:estadoAtual()).toBe(ESTADOS.Lobby)
			end)

			t.it("cada estado tem transicoes definidas (nenhum beco sem saida)", function()
				-- Um estado sem saidas prendia o assalto para sempre, e esse bug
				-- so apareceria num jogo a sério.
				for _, estado in ESTADOS do
					t.expect(#novoCore():transicoesPossiveis(estado) > 0).toBeTruthy()
				end
			end)
		end)

		t.describe("alarme", function()
			t.it("dispara de Furtivo para Alarme", function()
				local core = levarAte(novoCore(), ESTADOS.Furtivo)

				t.expect(core:dispararAlarme("guarda_viu")).toBe(true)
				t.expect(core:estadoAtual()).toBe(ESTADOS.Alarme)
			end)

			t.it("o segundo disparo e ignorado em silencio", function()
				-- O documento: "ignora se ja esta em Alarme". Tres guardas a ver o
				-- mesmo jogador nao podem disparar o alarme tres vezes.
				local core = levarAte(novoCore(), ESTADOS.Furtivo)

				t.expect(core:dispararAlarme("guarda_viu")).toBe(true)
				t.expect(core:dispararAlarme("camara_viu")).toBe(false)
				t.expect(core:estadoAtual()).toBe(ESTADOS.Alarme)
			end)

			t.it("nao dispara no Lobby", function()
				local core = novoCore()

				t.expect(core:dispararAlarme("teste")).toBe(false)
				t.expect(core:estadoAtual()).toBe(ESTADOS.Lobby)
			end)

			t.it("dispara durante a Fuga, mas SEM mudar de estado", function()
				--[[
					Ser visto a fugir tem de contar. Mas mandar o assalto de volta
					para Alarme rebobinava o jogador: perdia o temporizador e a
					carrinha, e ficava num estado sem saida.

					Por isso o alarme dispara (perde-se o bonus furtivo) e o estado
					continua Fuga, porque a carrinha esta la e o relogio corre.
				]]
				local core = levarAte(novoCore(), ESTADOS.Fuga)

				t.expect(core:dispararAlarme("guarda_viu")).toBe(true)
				t.expect(core:estadoAtual()).toBe(ESTADOS.Fuga)
				t.expect(core:foiFurtivo()).toBe(false)
			end)

			t.it("na Fuga tambem so conta uma vez", function()
				local core = levarAte(novoCore(), ESTADOS.Fuga)

				t.expect(core:dispararAlarme("guarda_viu")).toBe(true)
				t.expect(core:dispararAlarme("outro_guarda")).toBe(false)
			end)

			t.it("quem ja vinha de Alarme nao volta a disparar na Fuga", function()
				local core = levarAte(novoCore(), ESTADOS.Alarme)
				core:transitar(ESTADOS.Fuga)

				t.expect(core:dispararAlarme("guarda_viu")).toBe(false)
				t.expect(core:motivoDoAlarme()).toBe("teste") -- o do levarAte
			end)

			t.it("ser visto na Fuga tira o bonus furtivo do pagamento", function()
				local core = levarAte(novoCore(), ESTADOS.Furtivo)
				core:registarSacoEntregue(1, "grande") -- 5000
				core:transitar(ESTADOS.Fuga)

				-- Ate aqui era furtivo e o bonus aplicava-se.
				t.expect(core:calcularPagamento().dinheiroPorJogador).toBe(7500)

				core:dispararAlarme("guarda_viu")

				t.expect(core:calcularPagamento().dinheiroPorJogador).toBe(5000)
				t.expect(core:calcularPagamento().bonusFurtivoAplicado).toBe(false)
			end)

			t.it("nao dispara no Fim (o assalto ja acabou)", function()
				local core = levarAte(novoCore(), ESTADOS.Fim)

				t.expect(core:dispararAlarme("teste")).toBe(false)
				t.expect(core:foiFurtivo()).toBe(true)
			end)

			t.it("guarda o motivo do primeiro disparo, para os logs", function()
				local core = levarAte(novoCore(), ESTADOS.Furtivo)

				core:dispararAlarme("cabo_errado")
				core:dispararAlarme("civil_fugiu")

				t.expect(core:motivoDoAlarme()).toBe("cabo_errado")
			end)

			t.it("sem alarme, o motivo e nil", function()
				t.expect(novoCore():motivoDoAlarme()).toBeNil()
			end)
		end)

		t.describe("entregar sacos", function()
			t.it("conta um saco entregue", function()
				local core = levarAte(novoCore(), ESTADOS.Furtivo)
				local r = core:registarSacoEntregue(1, "pequeno")

				t.expect(r.aceite).toBe(true)
				t.expect(r.totalSacos).toBe(1)
				t.expect(core:totalSacosEntregues()).toBe(1)
			end)

			t.it("atingir o minimo chama a fuga", function()
				local core = levarAte(novoCore(), ESTADOS.Furtivo)

				local primeiro = core:registarSacoEntregue(1, "pequeno")
				t.expect(primeiro.chamouFuga).toBe(false)
				t.expect(core:estadoAtual()).toBe(ESTADOS.Furtivo)

				local segundo = core:registarSacoEntregue(1, "pequeno")
				t.expect(segundo.chamouFuga).toBe(true)
				t.expect(core:estadoAtual()).toBe(ESTADOS.Fuga)
			end)

			t.it("so chama a fuga uma vez", function()
				local core = levarAte(novoCore(), ESTADOS.Furtivo)

				core:registarSacoEntregue(1, "pequeno")
				core:registarSacoEntregue(1, "pequeno")
				local terceiro = core:registarSacoEntregue(1, "grande")

				t.expect(terceiro.aceite).toBe(true)
				t.expect(terceiro.chamouFuga).toBe(false)
			end)

			t.it("continua a aceitar sacos durante a Fuga", function()
				-- De proposito: dar para continuar a saquear enquanto se corre para
				-- a carrinha e uma decisao de jogo, nao um descuido.
				local core = levarAte(novoCore(), ESTADOS.Fuga)
				local r = core:registarSacoEntregue(1, "grande")

				t.expect(r.aceite).toBe(true)
				t.expect(core:totalSacosEntregues()).toBe(1)
			end)

			t.it("a partir do Alarme tambem chama a fuga", function()
				local core = levarAte(novoCore(), ESTADOS.Alarme)

				core:registarSacoEntregue(1, "pequeno")
				local segundo = core:registarSacoEntregue(2, "pequeno")

				t.expect(segundo.chamouFuga).toBe(true)
				t.expect(core:estadoAtual()).toBe(ESTADOS.Fuga)
			end)

			t.it("recusa entregas no Lobby", function()
				local core = novoCore()
				local r = core:registarSacoEntregue(1, "pequeno")

				t.expect(r.aceite).toBe(false)
				t.expect(r.motivo).toBe("estado")
				t.expect(core:totalSacosEntregues()).toBe(0)
			end)

			t.it("recusa entregas no Fim", function()
				local core = levarAte(novoCore(), ESTADOS.Fim)
				t.expect(core:registarSacoEntregue(1, "pequeno").aceite).toBe(false)
			end)

			t.it("recusa um tipo de saco que nao existe", function()
				local core = levarAte(novoCore(), ESTADOS.Furtivo)
				local r = core:registarSacoEntregue(1, "diamantes")

				t.expect(r.aceite).toBe(false)
				t.expect(r.motivo).toBe("tipo_desconhecido")
			end)

			t.it("conta por jogador, para as estatisticas", function()
				local core = levarAte(novoCore(), ESTADOS.Furtivo)

				core:registarSacoEntregue(1, "pequeno")
				core:registarSacoEntregue(2, "grande")
				core:registarSacoEntregue(1, "pequeno")

				t.expect(core:sacosDoJogador(1)).toBe(2)
				t.expect(core:sacosDoJogador(2)).toBe(1)
				t.expect(core:sacosDoJogador(99)).toBe(0)
			end)
		end)

		t.describe("furtivo ou barulhento", function()
			t.it("terminar sem alarme conta como furtivo", function()
				local core = levarAte(novoCore(), ESTADOS.Furtivo)
				core:transitar(ESTADOS.Fuga)
				core:transitar(ESTADOS.Fim)

				t.expect(core:foiFurtivo()).toBe(true)
			end)

			t.it("passar pelo Alarme deixa de ser furtivo, para sempre", function()
				local core = levarAte(novoCore(), ESTADOS.Alarme)
				core:transitar(ESTADOS.Fuga)

				t.expect(core:foiFurtivo()).toBe(false)
			end)
		end)

		t.describe("pagamento", function()
			t.it("soma o valor dos sacos entregues", function()
				local core = levarAte(novoCore(), ESTADOS.Alarme) -- sem bonus
				core:registarSacoEntregue(1, "pequeno") -- 1000
				core:registarSacoEntregue(1, "grande") -- 5000

				local pagamento = core:calcularPagamento()

				t.expect(pagamento.valorBruto).toBe(6000)
				t.expect(pagamento.dinheiroPorJogador).toBe(6000)
				t.expect(pagamento.bonusFurtivoAplicado).toBe(false)
			end)

			t.it("aplica o bonus furtivo quando nunca houve alarme", function()
				local core = levarAte(novoCore(), ESTADOS.Furtivo)
				core:registarSacoEntregue(1, "grande") -- 5000

				local pagamento = core:calcularPagamento()

				t.expect(pagamento.valorBruto).toBe(5000)
				t.expect(pagamento.dinheiroPorJogador).toBe(7500) -- 5000 * 1.5
				t.expect(pagamento.bonusFurtivoAplicado).toBe(true)
			end)

			t.it("cada jogador recebe o total, nao uma fatia", function()
				-- Decisao de jogo: dividir penalizava equipas maiores, o que
				-- contraria "o cooperativo e o trunfo do jogo". E a convencao do
				-- genero. Mudar isto e uma linha em HeistCore.calcularPagamento.
				local core = levarAte(novoCore(), ESTADOS.Alarme)
				core:registarSacoEntregue(1, "pequeno")
				core:registarSacoEntregue(2, "pequeno")

				t.expect(core:calcularPagamento().dinheiroPorJogador).toBe(2000)
			end)

			t.it("paga xp conforme o tipo de saco", function()
				local core = levarAte(novoCore(), ESTADOS.Alarme)
				core:registarSacoEntregue(1, "pequeno") -- 10
				core:registarSacoEntregue(1, "grande") -- 50

				t.expect(core:calcularPagamento().xpPorJogador).toBe(60)
			end)

			t.it("o bonus furtivo nao se aplica ao xp", function()
				-- O bonus e sobre o dinheiro. Multiplicar tambem o xp fazia a
				-- progressao disparar de maneira dificil de equilibrar.
				local core = levarAte(novoCore(), ESTADOS.Furtivo)
				core:registarSacoEntregue(1, "grande")

				t.expect(core:calcularPagamento().xpPorJogador).toBe(50)
			end)

			t.it("sem sacos entregues nao ha pagamento", function()
				local core = levarAte(novoCore(), ESTADOS.Furtivo)
				local pagamento = core:calcularPagamento()

				t.expect(pagamento.valorBruto).toBe(0)
				t.expect(pagamento.dinheiroPorJogador).toBe(0)
				t.expect(pagamento.xpPorJogador).toBe(0)
			end)

			t.it("o dinheiro e sempre inteiro", function()
				local core = HeistCore.novo({
					config = {
						minimoSacosParaFuga = 2,
						sacos = { pequeno = { valor = 333, velocidade = 14 } },
						recompensas = {
							bonusFurtivo = 1.5,
							xpPorSacoPequeno = 10,
							xpPorSacoGrande = 50,
						},
					},
					estados = ESTADOS,
				})
				levarAte(core, ESTADOS.Furtivo)
				core:registarSacoEntregue(1, "pequeno") -- 333 * 1.5 = 499.5

				t.expect(core:calcularPagamento().dinheiroPorJogador).toBe(499)
			end)
		end)

		t.describe("reiniciar para o assalto seguinte", function()
			t.it("volta ao Lobby e limpa tudo", function()
				local core = levarAte(novoCore(), ESTADOS.Alarme)
				core:registarSacoEntregue(1, "grande")
				core:transitar(ESTADOS.Fuga)
				core:transitar(ESTADOS.Fim)

				core:reiniciar()

				t.expect(core:estadoAtual()).toBe(ESTADOS.Lobby)
				t.expect(core:totalSacosEntregues()).toBe(0)
				t.expect(core:sacosDoJogador(1)).toBe(0)
				t.expect(core:foiFurtivo()).toBe(true)
				t.expect(core:motivoDoAlarme()).toBeNil()
			end)

			t.it("depois de reiniciar da para fazer outro assalto do inicio ao fim", function()
				local core = novoCore()

				for volta = 1, 3 do
					t.expect(core:transitar(ESTADOS.Furtivo)).toBe(true)
					core:registarSacoEntregue(1, "pequeno")
					core:registarSacoEntregue(1, "pequeno")
					t.expect(core:estadoAtual()).toBe(ESTADOS.Fuga)
					t.expect(core:transitar(ESTADOS.Fim)).toBe(true)
					t.expect(core:calcularPagamento().dinheiroPorJogador).toBe(3000) -- 2000 * 1.5

					core:reiniciar()
					t.expect(core:estadoAtual()).toBe(ESTADOS.Lobby)

					-- A volta seguinte nao pode herdar nada desta.
					t.expect(volta).toBe(volta)
				end
			end)
		end)

		t.describe("notificar quem ouve", function()
			t.it("avisa o adaptador em cada mudanca de estado", function()
				-- E assim que o HeistService sabe que tem de enviar o Remote
				-- HeistStateChanged, sem o core conhecer Remotes.
				local core = novoCore()
				local mudancas = {}

				core:aoMudarEstado(function(novo, anterior)
					table.insert(mudancas, anterior .. "->" .. novo)
				end)

				core:transitar(ESTADOS.Furtivo)
				core:dispararAlarme("teste")
				core:transitar(ESTADOS.Fuga)

				t.expect(mudancas).toEqual({
					"Lobby->Furtivo",
					"Furtivo->Alarme",
					"Alarme->Fuga",
				})
			end)

			t.it("nao avisa quando a transicao e recusada", function()
				local core = novoCore()
				local avisos = 0

				core:aoMudarEstado(function()
					avisos += 1
				end)

				core:transitar(ESTADOS.Fuga) -- ilegal a partir do Lobby
				core:transitar("Inventado")

				t.expect(avisos).toBe(0)
			end)

			t.it("aguenta varios ouvintes", function()
				local core = novoCore()
				local a, b = 0, 0

				core:aoMudarEstado(function()
					a += 1
				end)
				core:aoMudarEstado(function()
					b += 1
				end)

				core:transitar(ESTADOS.Furtivo)

				t.expect(a).toBe(1)
				t.expect(b).toBe(1)
			end)

			t.it("um ouvinte que rebenta nao impede os outros nem a transicao", function()
				-- Se o HUD de um jogador falhar, o assalto tem de continuar para
				-- os outros.
				local core = novoCore()
				local segundoCorreu = false

				core:aoMudarEstado(function()
					error("ouvinte com bug")
				end)
				core:aoMudarEstado(function()
					segundoCorreu = true
				end)

				t.expect(core:transitar(ESTADOS.Furtivo)).toBe(true)
				t.expect(segundoCorreu).toBe(true)
				t.expect(core:estadoAtual()).toBe(ESTADOS.Furtivo)
			end)

			t.it("reporta o erro do ouvinte pelo avisador injetado", function()
				--[[
					O core nao pode chamar `warn` diretamente: `warn` e um global
					do Roblox e isso quebrava a pureza do modulo (o selene recusa
					globais do Roblox em Core/). Mas engolir o erro em silencio
					tambem nao serve, porque esconderia bugs no HUD.

					Por isso o avisador e injetado: o HeistService passa `warn` e
					nos testes passamos uma funcao que recolhe as mensagens.
				]]
				local avisos = {}
				local core = HeistCore.novo({
					config = CONFIG,
					estados = ESTADOS,
					avisar = function(mensagem)
						table.insert(avisos, mensagem)
					end,
				})

				core:aoMudarEstado(function()
					error("ouvinte com bug")
				end)
				core:transitar(ESTADOS.Furtivo)

				t.expect(#avisos).toBe(1)
				t.expect(string.find(avisos[1], "Lobby", 1, true) ~= nil).toBeTruthy()
				t.expect(string.find(avisos[1], "Furtivo", 1, true) ~= nil).toBeTruthy()
				t.expect(string.find(avisos[1], "ouvinte com bug", 1, true) ~= nil).toBeTruthy()
			end)

			t.it("funciona sem avisador (e opcional)", function()
				local core = novoCore()
				core:aoMudarEstado(function()
					error("ouvinte com bug")
				end)

				t.expect(core:transitar(ESTADOS.Furtivo)).toBe(true)
			end)
		end)
	end)
end
