--[[
	O minijogo do cabo (secção 5 do documento).

	O requisito e de seguranca, nao de jogo:

	> O servidor escolhe o fio certo e guarda-o; o cliente so envia o fio
	> escolhido

	Por isso o teste mais importante deste ficheiro nao e nenhum dos de
	comportamento -- e o que confirma que NADA do que sai deste modulo para o
	cliente contem a resposta. Um `escolher` que devolvesse o fio certo, ou um
	`coresDoPuzzle` que o pusesse sempre na mesma posicao, seria um exploit.

	O gerador de aleatorios e injetado: sem isso estes testes seriam uma moeda
	ao ar e nao se poderia afirmar nada sobre qual o fio escolhido.
]]

local CaboCore = require("../src/Server/Core/CaboCore")

local CORES = { "vermelho", "azul", "verde", "amarelo" }

-- Aleatorio previsivel: devolve sempre o indice pedido.
local function sempre(indice)
	return function(_quantas)
		return indice
	end
end

local function novoCore(indiceEscolhido)
	return CaboCore.novo({
		config = { cores = CORES },
		aleatorio = sempre(indiceEscolhido or 2), -- azul, por omissao
	})
end

return function(t)
	t.describe("CaboCore", function()
		t.describe("gerar o puzzle", function()
			t.it("devolve todas as cores configuradas", function()
				local core = novoCore()
				core:gerarPuzzle()

				t.expect(core:coresDoPuzzle()).toEqual(CORES)
			end)

			t.it("a pista aponta para o fio que o servidor escolheu", function()
				local core = novoCore(2) -- azul
				core:gerarPuzzle()

				t.expect(core:pista()).toBe("azul")
			end)

			t.it("respeita o aleatorio injetado", function()
				for indice, cor in CORES do
					local core = novoCore(indice)
					core:gerarPuzzle()
					t.expect(core:pista()).toBe(cor)
				end
			end)

			t.it("comeca por resolver", function()
				local core = novoCore()
				core:gerarPuzzle()

				t.expect(core:estaResolvido()).toBe(false)
			end)

			t.it("sem puzzle gerado nao ha cores nem pista", function()
				local core = novoCore()

				t.expect(core:coresDoPuzzle()).toEqual({})
				t.expect(core:pista()).toBeNil()
			end)
		end)

		t.describe("NAO revelar a resposta", function()
			t.it("coresDoPuzzle mantem a ordem do Config, nao a do sorteio", function()
				--[[
					Se a ordem mudasse com o fio escolhido -- por exemplo pondo o
					certo em primeiro, ou embaralhando a partir dele -- a posicao
					revelava a resposta a quem comparasse duas partidas.
				]]
				for indice = 1, #CORES do
					local core = novoCore(indice)
					core:gerarPuzzle()
					t.expect(core:coresDoPuzzle()).toEqual(CORES)
				end
			end)

			t.it("escolher errado nao diz qual era o certo", function()
				local core = novoCore(2) -- azul
				core:gerarPuzzle()
				core:abrir(1)

				local acertou, motivo = core:escolher(1, "vermelho")

				t.expect(acertou).toBe(false)
				-- O motivo e um codigo, nao a resposta.
				t.expect(motivo).toBe("errado")
				t.expect(motivo).never.toBe("azul")
			end)

			t.it("escolher certo tambem nao precisa de devolver a cor", function()
				local core = novoCore(2)
				core:gerarPuzzle()
				core:abrir(1)

				local acertou, motivo = core:escolher(1, "azul")

				t.expect(acertou).toBe(true)
				t.expect(motivo).toBeNil()
			end)

			t.it("a lista de cores e uma copia, nao a tabela interna", function()
				-- Senao um servico podia alterar o puzzle por engano a partir de
				-- fora, ou o cliente receber uma referencia viva.
				local core = novoCore()
				core:gerarPuzzle()

				local cores = core:coresDoPuzzle()
				table.insert(cores, "roxo")

				t.expect(#core:coresDoPuzzle()).toBe(#CORES)
			end)
		end)

		t.describe("abrir e escolher", function()
			t.it("acertar resolve o puzzle", function()
				local core = novoCore(2)
				core:gerarPuzzle()
				core:abrir(1)

				t.expect(core:escolher(1, "azul")).toBe(true)
				t.expect(core:estaResolvido()).toBe(true)
			end)

			t.it("errar nao resolve", function()
				local core = novoCore(2)
				core:gerarPuzzle()
				core:abrir(1)

				core:escolher(1, "verde")

				t.expect(core:estaResolvido()).toBe(false)
			end)

			t.it("uma tentativa: depois de errar o painel fecha", function()
				-- O documento: "erro = alarme, ou usar kit de emergencia". Sem o
				-- kit, nao ha segunda tentativa.
				local core = novoCore(2)
				core:gerarPuzzle()
				core:abrir(1)

				core:escolher(1, "verde")

				local acertou, motivo = core:escolher(1, "azul")
				t.expect(acertou).toBe(false)
				t.expect(motivo).toBe("fechado")
			end)

			t.it("depois de acertar tambem nao da para repetir", function()
				local core = novoCore(2)
				core:gerarPuzzle()
				core:abrir(1)
				core:escolher(1, "azul")

				local acertou, motivo = core:escolher(1, "azul")
				t.expect(acertou).toBe(false)
				t.expect(motivo).toBe("fechado")
			end)

			t.it("recusa escolher sem ter aberto", function()
				local core = novoCore(2)
				core:gerarPuzzle()

				local acertou, motivo = core:escolher(1, "azul")

				t.expect(acertou).toBe(false)
				t.expect(motivo).toBe("nao_aberto")
			end)

			t.it("recusa uma cor que nao esta no puzzle", function()
				local core = novoCore(2)
				core:gerarPuzzle()
				core:abrir(1)

				local acertou, motivo = core:escolher(1, "roxo")

				t.expect(acertou).toBe(false)
				t.expect(motivo).toBe("cor_invalida")
			end)

			t.it("uma cor invalida nao gasta a tentativa", function()
				-- Senao um cliente a enviar lixo tirava a tentativa ao jogador.
				local core = novoCore(2)
				core:gerarPuzzle()
				core:abrir(1)

				core:escolher(1, "roxo")

				t.expect(core:escolher(1, "azul")).toBe(true)
			end)

			t.it("recusa algo que nao e texto", function()
				local core = novoCore(2)
				core:gerarPuzzle()
				core:abrir(1)

				local acertou, motivo = core:escolher(1, 42 :: any)

				t.expect(acertou).toBe(false)
				t.expect(motivo).toBe("cor_invalida")
			end)

			t.it("recusa escolher sem puzzle gerado", function()
				local core = novoCore(2)
				core:abrir(1)

				local acertou, motivo = core:escolher(1, "azul")

				t.expect(acertou).toBe(false)
				t.expect(motivo).toBe("nao_aberto")
			end)
		end)

		t.describe("um painel, um jogador", function()
			t.it("o jogador B nao pode escolher no painel aberto pelo A", function()
				local core = novoCore(2)
				core:gerarPuzzle()
				core:abrir(1)

				local acertou, motivo = core:escolher(2, "azul")

				t.expect(acertou).toBe(false)
				t.expect(motivo).toBe("nao_aberto")
			end)

			t.it("abrir por outro jogador substitui quem o tinha aberto", function()
				-- Um painel, nao um por pessoa: quem chega depois fica com ele.
				local core = novoCore(2)
				core:gerarPuzzle()
				core:abrir(1)
				core:abrir(2)

				t.expect(core:escolher(1, "azul")).toBe(false)
				t.expect(core:escolher(2, "azul")).toBe(true)
			end)

			t.it("nao da para abrir um painel ja resolvido", function()
				local core = novoCore(2)
				core:gerarPuzzle()
				core:abrir(1)
				core:escolher(1, "azul")

				t.expect(core:abrir(2)).toBe(false)
			end)

			t.it("nao da para abrir um painel ja falhado", function()
				local core = novoCore(2)
				core:gerarPuzzle()
				core:abrir(1)
				core:escolher(1, "verde")

				t.expect(core:abrir(2)).toBe(false)
			end)
		end)

		t.describe("assalto seguinte", function()
			t.it("reiniciar apaga o puzzle", function()
				local core = novoCore(2)
				core:gerarPuzzle()
				core:abrir(1)
				core:escolher(1, "azul")

				core:reiniciar()

				t.expect(core:estaResolvido()).toBe(false)
				t.expect(core:coresDoPuzzle()).toEqual({})
				t.expect(core:pista()).toBeNil()
			end)

			t.it("o puzzle novo pode ter outro fio certo", function()
				-- Herdar a resposta do assalto anterior tornava o segundo assalto
				-- trivial para quem tivesse decorado.
				local escolhas = { 2, 4 }
				local vez = 0
				local core = CaboCore.novo({
					config = { cores = CORES },
					aleatorio = function()
						vez += 1
						return escolhas[vez]
					end,
				})

				core:gerarPuzzle()
				t.expect(core:pista()).toBe("azul")

				core:reiniciar()
				core:gerarPuzzle()
				t.expect(core:pista()).toBe("amarelo")
			end)
		end)

		t.describe("aleatorio mal comportado", function()
			t.it("indice fora da gama nao rebenta e escolhe algo valido", function()
				for _, mau in { 0, -1, 99, 1.5 } do
					local core = CaboCore.novo({
						config = { cores = CORES },
						aleatorio = sempre(mau),
					})
					core:gerarPuzzle()

					local pista = core:pista()
					t.expect(table.find(CORES, pista) ~= nil).toBeTruthy()
				end
			end)
		end)
	end)
end
