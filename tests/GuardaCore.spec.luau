--[[
	Visao dos guardas e barra de suspeicao (secção 5 do documento:
	"visao = angulo (ex.: 90°) + distancia + raycast sem obstaculos; barra de
	suspeita antes de dar o alarme").

	O raycast nao esta aqui: precisa do mundo fisico, logo e trabalho do
	GuardService. Este core responde as duas perguntas que sao matematica pura
	("esta no cone?") e maquina de estados pura ("ja viu durante tempo
	suficiente?").

	Nenhum destes testes espera tempo real: o `dt` e passado a mao. Testar uma
	barra que leva 1.5s a encher nao custa 1.5s.
]]

local GuardaCore = require("../src/Server/Core/GuardaCore")

-- Valores explicitos: afinar o Config nao deve partir estes testes.
local CONFIG = {
	angulo = 90, -- cone total, 45° para cada lado
	distancia = 40,
	segundosParaDetetar = 2,
	segundosParaEsquecer = 4,
}

local function novoCore(alteracoes)
	local config = table.clone(CONFIG)
	for chave, valor in alteracoes or {} do
		config[chave] = valor
	end
	return GuardaCore.novo({ config = config })
end

local function p(x, y, z)
	return { x = x, y = y, z = z }
end

-- Guarda na origem a olhar para +Z. O alvo e colocado a `graus` do eixo de
-- visao, no plano horizontal, a `distancia` de distancia.
local function alvoA(graus, distancia)
	local radianos = math.rad(graus)
	return p(math.sin(radianos) * distancia, 0, math.cos(radianos) * distancia)
end

local ORIGEM = p(0, 0, 0)
local OLHAR_PARA_Z = p(0, 0, 1)

return function(t)
	t.describe("GuardaCore", function()
		t.describe("cone de visao: angulo", function()
			t.it("ve um alvo em frente", function()
				t.expect(novoCore():dentroDoCone(ORIGEM, OLHAR_PARA_Z, alvoA(0, 10))).toBe(true)
			end)

			t.it("ve exactamente no limite do cone", function()
				-- Cone de 90° = 45° para cada lado.
				t.expect(novoCore():dentroDoCone(ORIGEM, OLHAR_PARA_Z, alvoA(45, 10))).toBe(true)
			end)

			t.it("nao ve um grau alem do limite", function()
				t.expect(novoCore():dentroDoCone(ORIGEM, OLHAR_PARA_Z, alvoA(46, 10))).toBe(false)
			end)

			t.it("o limite e simetrico para os dois lados", function()
				local core = novoCore()
				t.expect(core:dentroDoCone(ORIGEM, OLHAR_PARA_Z, alvoA(-45, 10))).toBe(true)
				t.expect(core:dentroDoCone(ORIGEM, OLHAR_PARA_Z, alvoA(-46, 10))).toBe(false)
			end)

			t.it("nao ve um alvo atras", function()
				t.expect(novoCore():dentroDoCone(ORIGEM, OLHAR_PARA_Z, alvoA(180, 10))).toBe(false)
			end)

			t.it("nao ve um alvo de lado", function()
				t.expect(novoCore():dentroDoCone(ORIGEM, OLHAR_PARA_Z, alvoA(90, 10))).toBe(false)
			end)

			t.it("um cone mais largo ve mais", function()
				local largo = novoCore({ angulo = 180 })
				t.expect(largo:dentroDoCone(ORIGEM, OLHAR_PARA_Z, alvoA(80, 10))).toBe(true)
				t.expect(largo:dentroDoCone(ORIGEM, OLHAR_PARA_Z, alvoA(100, 10))).toBe(false)
			end)
		end)

		t.describe("cone de visao: distancia", function()
			t.it("ve exactamente a distancia maxima", function()
				t.expect(novoCore():dentroDoCone(ORIGEM, OLHAR_PARA_Z, alvoA(0, 40))).toBe(true)
			end)

			t.it("nao ve um stud alem da distancia maxima", function()
				t.expect(novoCore():dentroDoCone(ORIGEM, OLHAR_PARA_Z, alvoA(0, 41))).toBe(false)
			end)

			t.it("nao ve do outro lado do mapa, mesmo em frente", function()
				t.expect(novoCore():dentroDoCone(ORIGEM, OLHAR_PARA_Z, alvoA(0, 500))).toBe(false)
			end)
		end)

		t.describe("cone de visao: tres dimensoes", function()
			t.it("conta o angulo na vertical, nao so no plano", function()
				-- Alvo a 60° acima, em frente. Um bug que ignorasse o Y punha-o
				-- dentro do cone, e um guarda veria alguem no andar de cima.
				local acima = p(0, math.sin(math.rad(60)) * 10, math.cos(math.rad(60)) * 10)
				t.expect(novoCore():dentroDoCone(ORIGEM, OLHAR_PARA_Z, acima)).toBe(false)
			end)

			t.it("ve um alvo ligeiramente acima, dentro do cone", function()
				local poucoAcima = p(0, math.sin(math.rad(20)) * 10, math.cos(math.rad(20)) * 10)
				t.expect(novoCore():dentroDoCone(ORIGEM, OLHAR_PARA_Z, poucoAcima)).toBe(true)
			end)

			t.it("respeita a direcao do olhar, nao assume +Z", function()
				local core = novoCore()
				-- Guarda a olhar para -X; alvo a -X esta em frente dele.
				t.expect(core:dentroDoCone(ORIGEM, p(-1, 0, 0), p(-10, 0, 0))).toBe(true)
				t.expect(core:dentroDoCone(ORIGEM, p(-1, 0, 0), p(10, 0, 0))).toBe(false)
			end)

			t.it("funciona com o guarda fora da origem", function()
				local core = novoCore()
				local guarda = p(100, 5, -50)
				t.expect(core:dentroDoCone(guarda, OLHAR_PARA_Z, p(100, 5, -40))).toBe(true)
				t.expect(core:dentroDoCone(guarda, OLHAR_PARA_Z, p(100, 5, -60))).toBe(false)
			end)
		end)

		t.describe("cone de visao: entradas invalidas", function()
			t.it("nao ve com posicoes NaN", function()
				local core = novoCore()
				t.expect(core:dentroDoCone(ORIGEM, OLHAR_PARA_Z, p(0 / 0, 0, 10))).toBe(false)
				t.expect(core:dentroDoCone(p(0 / 0, 0, 0), OLHAR_PARA_Z, alvoA(0, 10))).toBe(false)
			end)

			t.it("nao ve com direcao de olhar nula", function()
				-- Um vetor zero nao tem direcao; normalizar daria divisao por zero.
				t.expect(novoCore():dentroDoCone(ORIGEM, p(0, 0, 0), alvoA(0, 10))).toBe(false)
			end)

			t.it("um alvo exactamente na posicao do guarda conta como visto", function()
				-- Distancia zero: nao ha angulo definido, mas estar dentro do
				-- guarda nao pode contar como escondido.
				t.expect(novoCore():dentroDoCone(ORIGEM, OLHAR_PARA_Z, ORIGEM)).toBe(true)
			end)
		end)

		t.describe("barra de suspeicao", function()
			t.it("comeca a zero", function()
				t.expect(novoCore():suspeitaDe(1, 10)).toBe(0)
			end)

			t.it("sobe proporcional ao tempo a vista", function()
				local core = novoCore()

				-- 2 segundos para detetar, logo 1 segundo = metade.
				local nivel = core:atualizarSuspeita(1, 10, 1, true)
				t.expect(nivel).toBeCloseTo(0.5)
			end)

			t.it("chega a 1.0 no tempo configurado", function()
				local core = novoCore()
				core:atualizarSuspeita(1, 10, 1, true)
				local nivel = core:atualizarSuspeita(1, 10, 1, true)

				t.expect(nivel).toBeCloseTo(1)
			end)

			t.it("nao passa de 1.0 por muito que insista", function()
				local core = novoCore()
				for _ = 1, 20 do
					core:atualizarSuspeita(1, 10, 1, true)
				end

				t.expect(core:suspeitaDe(1, 10)).toBe(1)
			end)

			t.it("decai quando deixa de ver", function()
				local core = novoCore()
				core:atualizarSuspeita(1, 10, 2, true) -- cheia
				t.expect(core:suspeitaDe(1, 10)).toBeCloseTo(1)

				-- 4 segundos para esquecer, logo 2 segundos = metade.
				local nivel = core:atualizarSuspeita(1, 10, 2, false)
				t.expect(nivel).toBeCloseTo(0.5)
			end)

			t.it("nao desce abaixo de zero", function()
				local core = novoCore()
				for _ = 1, 20 do
					core:atualizarSuspeita(1, 10, 1, false)
				end

				t.expect(core:suspeitaDe(1, 10)).toBe(0)
			end)

			t.it("esquecer e mais lento que detetar (da tempo de fugir)", function()
				local core = novoCore()
				core:atualizarSuspeita(1, 10, 1, true) -- meio segundo de vista -> 0.5
				local depoisDeVer = core:suspeitaDe(1, 10)

				core:atualizarSuspeita(1, 10, 1, false) -- 1s escondido
				local depoisDeEsconder = core:suspeitaDe(1, 10)

				-- Com segundosParaEsquecer (4) > segundosParaDetetar (2), um
				-- segundo escondido recupera menos do que um segundo visto custou.
				t.expect(depoisDeEsconder > 0).toBeTruthy()
				t.expect(depoisDeEsconder < depoisDeVer).toBeTruthy()
			end)
		end)

		t.describe("acabouDeDetetar", function()
			t.it("e falso enquanto a barra nao enche", function()
				local core = novoCore()
				local _, detetou = core:atualizarSuspeita(1, 10, 1, true)

				t.expect(detetou).toBe(false)
			end)

			t.it("e verdadeiro na travessia para 1.0", function()
				local core = novoCore()
				core:atualizarSuspeita(1, 10, 1, true)
				local _, detetou = core:atualizarSuspeita(1, 10, 1, true)

				t.expect(detetou).toBe(true)
			end)

			t.it("e verdadeiro UMA so vez, nao a cada chamada", function()
				-- Sem isto, o alarme era pedido 5 vezes por segundo enquanto o
				-- jogador continuasse a vista.
				local core = novoCore()
				core:atualizarSuspeita(1, 10, 5, true) -- enche de uma vez

				local vezes = 0
				for _ = 1, 10 do
					local _, detetou = core:atualizarSuspeita(1, 10, 1, true)
					if detetou then
						vezes += 1
					end
				end

				t.expect(vezes).toBe(0)
			end)

			t.it("conta a primeira travessia mesmo quando enche de uma vez", function()
				local core = novoCore()
				local _, detetou = core:atualizarSuspeita(1, 10, 99, true)

				t.expect(detetou).toBe(true)
			end)

			t.it("volta a poder detetar depois de esquecer por completo", function()
				local core = novoCore()
				core:atualizarSuspeita(1, 10, 5, true) -- detetou
				core:atualizarSuspeita(1, 10, 99, false) -- esqueceu tudo
				t.expect(core:suspeitaDe(1, 10)).toBe(0)

				local _, detetou = core:atualizarSuspeita(1, 10, 5, true)
				t.expect(detetou).toBe(true)
			end)
		end)

		t.describe("independencia", function()
			t.it("a suspeicao e por guarda", function()
				local core = novoCore()
				core:atualizarSuspeita(1, 10, 2, true)

				t.expect(core:suspeitaDe(1, 10)).toBeCloseTo(1)
				t.expect(core:suspeitaDe(2, 10)).toBe(0)
			end)

			t.it("a suspeicao e por alvo", function()
				local core = novoCore()
				core:atualizarSuspeita(1, 10, 2, true)

				t.expect(core:suspeitaDe(1, 10)).toBeCloseTo(1)
				t.expect(core:suspeitaDe(1, 20)).toBe(0)
			end)

			t.it("um guarda a ver nao faz o outro deteta-lo", function()
				local core = novoCore()

				local _, guarda1 = core:atualizarSuspeita(1, 10, 5, true)
				local _, guarda2 = core:atualizarSuspeita(2, 10, 1, true)

				t.expect(guarda1).toBe(true)
				t.expect(guarda2).toBe(false)
			end)
		end)

		t.describe("maior suspeicao de um alvo", function()
			t.it("devolve a do guarda que mais o notou, para o indicador", function()
				local core = novoCore()
				core:atualizarSuspeita(1, 10, 0.5, true) -- 0.25
				core:atualizarSuspeita(2, 10, 1.5, true) -- 0.75
				core:atualizarSuspeita(3, 10, 1, true) -- 0.5

				t.expect(core:maiorSuspeitaDe(10)).toBeCloseTo(0.75)
			end)

			t.it("e zero para um alvo que ninguem viu", function()
				t.expect(novoCore():maiorSuspeitaDe(99)).toBe(0)
			end)
		end)

		t.describe("limpeza", function()
			t.it("esquecer um alvo limpa-o de todos os guardas", function()
				-- Jogador saiu do jogo: a tabela nao pode crescer sem fim.
				local core = novoCore()
				core:atualizarSuspeita(1, 10, 2, true)
				core:atualizarSuspeita(2, 10, 2, true)

				core:esquecerAlvo(10)

				t.expect(core:suspeitaDe(1, 10)).toBe(0)
				t.expect(core:suspeitaDe(2, 10)).toBe(0)
				t.expect(core:maiorSuspeitaDe(10)).toBe(0)
			end)

			t.it("esquecer um alvo nao afeta os outros", function()
				local core = novoCore()
				core:atualizarSuspeita(1, 10, 2, true)
				core:atualizarSuspeita(1, 20, 2, true)

				core:esquecerAlvo(10)

				t.expect(core:suspeitaDe(1, 20)).toBeCloseTo(1)
			end)

			t.it("reiniciar limpa tudo, para o assalto seguinte", function()
				local core = novoCore()
				core:atualizarSuspeita(1, 10, 2, true)

				core:reiniciar()

				t.expect(core:suspeitaDe(1, 10)).toBe(0)
				-- E volta a poder detetar de novo.
				local _, detetou = core:atualizarSuspeita(1, 10, 5, true)
				t.expect(detetou).toBe(true)
			end)
		end)

		t.describe("dt invalido", function()
			t.it("ignora dt negativo", function()
				local core = novoCore()
				core:atualizarSuspeita(1, 10, 1, true)
				core:atualizarSuspeita(1, 10, -100, true)

				t.expect(core:suspeitaDe(1, 10)).toBeCloseTo(0.5)
			end)

			t.it("ignora dt NaN", function()
				local core = novoCore()
				core:atualizarSuspeita(1, 10, 0 / 0, true)

				t.expect(core:suspeitaDe(1, 10)).toBe(0)
			end)
		end)
	end)
end
