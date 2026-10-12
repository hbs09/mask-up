--[[
	A regra de ouro nº2 do documento: "Nunca confiar no cliente. Cada RemoteEvent
	valida: o jogador esta vivo? Esta perto do objeto? O assalto esta no estado
	certo? Ja fez isto ha pouco (cooldown)?"

	Este modulo e o unico sitio onde essas quatro perguntas sao respondidas, por
	isso e o sitio mais importante do projeto para estar testado.

	Os valores (distancias, cooldowns) sao explicitos aqui de proposito: afinar o
	equilibrio do jogo no Config nao deve partir estes testes.
]]

local ValidacaoCore = require("../src/Server/Core/ValidacaoCore")

local DISTANCIA_MAXIMA = 10
local COOLDOWN = 0.5

local function novoValidador()
	return ValidacaoCore.novo({
		distanciaMaximaInteracao = DISTANCIA_MAXIMA,
		cooldownInteracao = COOLDOWN,
	})
end

--[[
	Sentinela para apagar um campo do pedido.

	Em Lua, `{ posicaoObjeto = nil }` constroi uma tabela VAZIA, por isso nao da
	para pedir "sem este campo" so passando nil -- o campo ficava com o valor
	por omissao e o teste passava por acidente. Esta constante torna a intencao
	explicita.
]]
local SEM = newproxy(false)

-- Um pedido valido, para cada teste alterar so o campo que lhe interessa.
local function pedido(alteracoes)
	local base = {
		jogadorId = 1,
		vivo = true,
		posicaoJogador = { x = 0, y = 0, z = 0 },
		posicaoObjeto = { x = 0, y = 0, z = 0 },
		estadoAtual = "Furtivo",
		estadosPermitidos = { "Furtivo", "Alarme" },
		acao = "PickUpBag",
		agora = 100,
	}

	for chave, valor in alteracoes or {} do
		base[chave] = if valor == SEM then nil else valor
	end

	return base
end

return function(t)
	t.describe("ValidacaoCore", function()
		t.describe("caso normal", function()
			t.it("permite quando tudo esta em ordem", function()
				local v = novoValidador()
				local ok, motivo = v:podeInteragir(pedido())

				t.expect(ok).toBe(true)
				t.expect(motivo).toBeNil()
			end)
		end)

		t.describe("jogador vivo", function()
			t.it("recusa um jogador morto", function()
				local v = novoValidador()
				local ok, motivo = v:podeInteragir(pedido({ vivo = false }))

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("morto")
			end)
		end)

		t.describe("distancia", function()
			t.it("permite dentro da distancia maxima", function()
				local v = novoValidador()
				local ok = v:podeInteragir(pedido({ posicaoObjeto = { x = 5, y = 0, z = 0 } }))

				t.expect(ok).toBe(true)
			end)

			t.it("permite exatamente na distancia maxima", function()
				local v = novoValidador()
				local ok = v:podeInteragir(
					pedido({ posicaoObjeto = { x = DISTANCIA_MAXIMA, y = 0, z = 0 } })
				)

				t.expect(ok).toBe(true)
			end)

			t.it("recusa um stud acima da distancia maxima", function()
				local v = novoValidador()
				local ok, motivo = v:podeInteragir(
					pedido({ posicaoObjeto = { x = DISTANCIA_MAXIMA + 1, y = 0, z = 0 } })
				)

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("longe")
			end)

			t.it("recusa o exploit classico: disparar o remote do outro lado do mapa", function()
				local v = novoValidador()
				local ok, motivo =
					v:podeInteragir(pedido({ posicaoObjeto = { x = 200, y = 0, z = 0 } }))

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("longe")
			end)

			t.it("mede em tres dimensoes, nao so no plano", function()
				local v = novoValidador()
				-- Logo acima do objeto, mais alto que a distancia maxima:
				-- um bug que ignorasse o Y deixaria isto passar.
				local ok, motivo = v:podeInteragir(
					pedido({ posicaoObjeto = { x = 0, y = DISTANCIA_MAXIMA + 5, z = 0 } })
				)

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("longe")
			end)
		end)

		t.describe("estado do assalto", function()
			t.it("recusa quando o estado atual nao esta na lista permitida", function()
				local v = novoValidador()
				local ok, motivo = v:podeInteragir(pedido({ estadoAtual = "Lobby" }))

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("estado")
			end)

			t.it("aceita qualquer um dos estados permitidos", function()
				local v = novoValidador()

				t.expect(v:podeInteragir(pedido({ estadoAtual = "Furtivo" }))).toBe(true)
				t.expect(v:podeInteragir(pedido({ estadoAtual = "Alarme", jogadorId = 2 })))
					.toBe(true)
			end)
		end)

		t.describe("cooldown", function()
			t.it("recusa a segunda acao dentro do cooldown", function()
				local v = novoValidador()

				t.expect(v:podeInteragir(pedido({ agora = 100 }))).toBe(true)

				local ok, motivo = v:podeInteragir(pedido({ agora = 100 + COOLDOWN / 2 }))
				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("cooldown")
			end)

			t.it("permite outra vez depois de passar o cooldown", function()
				local v = novoValidador()

				t.expect(v:podeInteragir(pedido({ agora = 100 }))).toBe(true)
				t.expect(v:podeInteragir(pedido({ agora = 100 + COOLDOWN }))).toBe(true)
			end)

			t.it("aguenta spam: de dez tentativas seguidas so a primeira passa", function()
				local v = novoValidador()
				local aceites = 0

				for i = 0, 9 do
					local ok = v:podeInteragir(pedido({ agora = 100 + i * 0.01 }))
					if ok then
						aceites += 1
					end
				end

				t.expect(aceites).toBe(1)
			end)

			t.it("o cooldown e por jogador: o jogador 2 nao e travado pelo jogador 1", function()
				local v = novoValidador()

				t.expect(v:podeInteragir(pedido({ jogadorId = 1, agora = 100 }))).toBe(true)
				t.expect(v:podeInteragir(pedido({ jogadorId = 2, agora = 100 }))).toBe(true)
			end)

			t.it("o cooldown e por acao: apanhar um saco nao trava largar", function()
				local v = novoValidador()

				t.expect(v:podeInteragir(pedido({ acao = "PickUpBag", agora = 100 }))).toBe(true)
				t.expect(v:podeInteragir(pedido({ acao = "DropBag", agora = 100 }))).toBe(true)
			end)

			t.it("uma acao recusada nao arranca o cooldown", function()
				local v = novoValidador()

				-- Recusada por estar longe...
				t.expect(
					v:podeInteragir(
						pedido({ posicaoObjeto = { x = 500, y = 0, z = 0 }, agora = 100 })
					)
				).toBe(false)
				-- ...por isso a tentativa boa logo a seguir deve passar.
				t.expect(v:podeInteragir(pedido({ agora = 100 }))).toBe(true)
			end)
		end)

		t.describe("pedidos malformados (cliente a mentir)", function()
			t.it("recusa sem posicao do objeto", function()
				local v = novoValidador()
				local ok, motivo = v:podeInteragir(pedido({ posicaoObjeto = SEM }))

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("invalido")
			end)

			t.it("recusa sem posicao do jogador", function()
				local v = novoValidador()
				local ok, motivo = v:podeInteragir(pedido({ posicaoJogador = SEM }))

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("invalido")
			end)

			t.it("recusa coordenadas que nao sao numeros", function()
				local v = novoValidador()
				local ok, motivo =
					v:podeInteragir(pedido({ posicaoObjeto = { x = "perto", y = 0, z = 0 } }))

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("invalido")
			end)

			t.it("recusa coordenadas NaN (dava para enganar comparacoes)", function()
				local v = novoValidador()
				local ok, motivo =
					v:podeInteragir(pedido({ posicaoObjeto = { x = 0 / 0, y = 0, z = 0 } }))

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("invalido")
			end)

			t.it("recusa sem acao (nao daria para aplicar cooldown)", function()
				local v = novoValidador()
				local ok, motivo = v:podeInteragir(pedido({ acao = SEM }))

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("invalido")
			end)

			t.it("recusa um pedido que nao e tabela", function()
				local v = novoValidador()
				local ok, motivo = v:podeInteragir("nao sou um pedido" :: any)

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("invalido")
			end)
		end)

		t.describe("ordem das verificacoes", function()
			-- Com varios problemas ao mesmo tempo, o motivo devolvido tem de ser
			-- estavel e util nos logs do servidor. A ordem segue a do documento.
			t.it("malformado tem prioridade sobre tudo", function()
				local _, motivo = novoValidador():podeInteragir(pedido({
					posicaoObjeto = SEM,
					vivo = false,
					estadoAtual = "Lobby",
				}))

				t.expect(motivo).toBe("invalido")
			end)

			t.it("morto tem prioridade sobre longe e estado", function()
				local _, motivo = novoValidador():podeInteragir(pedido({
					vivo = false,
					posicaoObjeto = { x = 500, y = 0, z = 0 },
					estadoAtual = "Lobby",
				}))

				t.expect(motivo).toBe("morto")
			end)

			t.it("estado tem prioridade sobre longe", function()
				local _, motivo = novoValidador():podeInteragir(pedido({
					estadoAtual = "Lobby",
					posicaoObjeto = { x = 500, y = 0, z = 0 },
				}))

				t.expect(motivo).toBe("estado")
			end)
		end)
	end)
end
