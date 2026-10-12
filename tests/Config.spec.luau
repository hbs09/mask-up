--[[
	O Config e a tabela unica com os numeros do jogo (regra de ouro nº4 do
	documento: "Configuracao em tabelas, nunca numeros espalhados pelo codigo").

	Estes testes nao verificam valores concretos -- afinar o equilibrio e normal
	e nao deve partir testes. Verificam INVARIANTES: relacoes entre valores que,
	se forem quebradas, tornam o jogo impossivel ou absurdo. Um erro de um digito
	no minimo de sacos tornaria o assalto impossível de terminar, e isso nao
	aparece em nenhum teste de logica.
]]

local Config = require("../src/Shared/Config")
local HeistState = require("../src/Shared/HeistState")

return function(t)
	t.describe("Config", function()
		t.describe("sacos", function()
			t.it("todos os tipos de saco tem valor e velocidade", function()
				for nome, saco in Config.sacos do
					t.expect(type(saco.valor)).toBe("number")
					t.expect(type(saco.velocidade)).toBe("number")
					t.expect(saco.valor > 0).toBeTruthy()
					t.expect(saco.velocidade > 0).toBeTruthy()

					-- O nome entra em mensagens de erro para saber qual falhou.
					t.expect(type(nome)).toBe("string")
				end
			end)

			t.it("carregar um saco deixa sempre mais lento que andar sem nada", function()
				-- O documento: "carregar um saco deixa o jogador mais lento".
				-- Se um saco ficasse mais rapido que o normal, era um exploit.
				for _, saco in Config.sacos do
					t.expect(saco.velocidade < Config.velocidadeNormal).toBeTruthy()
				end
			end)

			t.it("o saco grande vale mais e pesa mais que o pequeno", function()
				t.expect(Config.sacos.grande.valor > Config.sacos.pequeno.valor).toBeTruthy()
				t.expect(Config.sacos.grande.velocidade < Config.sacos.pequeno.velocidade)
					.toBeTruthy()
			end)
		end)

		t.describe("o assalto tem de ser ganhavel", function()
			t.it("ha saque suficiente no mapa para atingir o minimo da fuga", function()
				-- A invariante mais importante deste ficheiro: se o minimo para
				-- chamar a fuga for maior que o numero de sacos que existem no
				-- mapa, o assalto nunca termina e ninguem percebe porque.
				local sacosNoMapa = Config.mapa.montras + Config.mapa.cofres

				t.expect(Config.minimoSacosParaFuga <= sacosNoMapa).toBeTruthy()
			end)

			t.it("uma equipa de um jogador consegue fazer as viagens necessarias", function()
				-- Com limite de 1 saco por jogador, um jogador sozinho tem de
				-- poder ir e voltar: isso exige apenas que o limite seja >= 1.
				t.expect(Config.limiteSacosPorJogador >= 1).toBeTruthy()
				t.expect(Config.minimoSacosParaFuga >= 1).toBeTruthy()
			end)

			t.it("o tempo de fuga da para percorrer o mapa", function()
				t.expect(Config.tempos.fuga > 0).toBeTruthy()
			end)
		end)

		t.describe("tempos", function()
			t.it("sao todos positivos", function()
				for nome, segundos in Config.tempos do
					t.expect(type(segundos)).toBe("number")
					t.expect(segundos > 0).toBeTruthy()
					t.expect(type(nome)).toBe("string")
				end
			end)

			t.it("a duracao alvo do assalto e coerente (minimo < maximo)", function()
				local alvo = Config.assalto.duracaoAlvoSegundos
				t.expect(alvo.minimo < alvo.maximo).toBeTruthy()
				t.expect(alvo.minimo > 0).toBeTruthy()
			end)
		end)

		t.describe("interacao", function()
			t.it("tem a forma que o ValidacaoCore espera", function()
				-- O adaptador faz `ValidacaoCore.novo(Config.interacao)`, por isso
				-- os nomes dos campos tem de corresponder exatamente.
				t.expect(type(Config.interacao.distanciaMaxima)).toBe("number")
				t.expect(type(Config.interacao.cooldown)).toBe("number")
			end)

			t.it("a distancia maxima e maior que zero mas nao absurda", function()
				t.expect(Config.interacao.distanciaMaxima > 0).toBeTruthy()
				-- Um valor enorme aqui anulava a protecao contra interagir de longe.
				t.expect(Config.interacao.distanciaMaxima <= 50).toBeTruthy()
			end)

			t.it("o cooldown e maior que zero (senao nao travava spam)", function()
				t.expect(Config.interacao.cooldown > 0).toBeTruthy()
			end)
		end)

		t.describe("recompensas", function()
			t.it("o bonus furtivo premeia, nunca penaliza", function()
				-- Multiplicador abaixo de 1 faria do caminho furtivo um castigo,
				-- ao contrario do que o documento pretende.
				t.expect(Config.recompensas.bonusFurtivo >= 1).toBeTruthy()
			end)

			t.it("o saco grande da mais xp que o pequeno", function()
				t.expect(Config.recompensas.xpPorSacoGrande > Config.recompensas.xpPorSacoPequeno)
					.toBeTruthy()
			end)
		end)

		t.describe("progressao", function()
			t.it("tem a forma que o PerfilCore espera", function()
				t.expect(type(Config.progressao.xpBase)).toBe("number")
				t.expect(type(Config.progressao.nivelMaximo)).toBe("number")
			end)

			t.it("xpBase positivo e nivel maximo pelo menos 2", function()
				t.expect(Config.progressao.xpBase > 0).toBeTruthy()
				t.expect(Config.progressao.nivelMaximo >= 2).toBeTruthy()
			end)
		end)

		t.describe("protecao contra alteracoes em runtime", function()
			t.it("o Config esta congelado", function()
				-- Um servico que escrevesse no Config mudava o jogo para todos,
				-- e o bug seria dificil de encontrar. table.freeze torna isso erro.
				t.expect(function()
					(Config :: any).velocidadeNormal = 999
				end).toThrow()
			end)

			t.it("as tabelas aninhadas tambem estao congeladas", function()
				-- O table.freeze e superficial: sem congelamento profundo, estas
				-- escritas passavam em silencio e eram o bug mais provavel.
				t.expect(function()
					(Config.sacos.pequeno :: any).valor = 999999
				end).toThrow()

				t.expect(function()
					(Config.tempos :: any).fuga = 1
				end).toThrow()

				t.expect(function()
					(Config.assalto.duracaoAlvoSegundos :: any).minimo = 0
				end).toThrow()
			end)
		end)
	end)

	t.describe("HeistState", function()
		t.it("tem exatamente os cinco estados da secção 4 do documento", function()
			t.expect(HeistState).toEqual({
				Lobby = "Lobby",
				Furtivo = "Furtivo",
				Alarme = "Alarme",
				Fuga = "Fuga",
				Fim = "Fim",
			})
		end)

		t.it("cada chave e igual ao seu valor", function()
			-- Assim um estado pode ser enviado pelo Remote como texto e comparado
			-- do outro lado sem tabela de traducao.
			for chave, valor in HeistState do
				t.expect(chave).toBe(valor)
			end
		end)

		t.it("esta congelado", function()
			t.expect(function()
				(HeistState :: any).Inventado = "Inventado"
			end).toThrow()
		end)
	end)
end
