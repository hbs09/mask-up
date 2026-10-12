--[[
	Quem tem que saco, o limite por jogador e a velocidade de quem carrega
	(secção 5 do documento).

	O core trabalha com ids: `sacoId` e `jogadorId` sao so numeros/texto. Quem
	cria as Parts, faz o WeldConstraint ao HumanoidRootPart e escreve o
	Humanoid.WalkSpeed e o LootService. Assim as regras de posse de sacos --
	que sao onde os bugs de duplicacao de dinheiro aparecem -- ficam testadas.
]]

local LootCore = require("../src/Server/Core/LootCore")

local CONFIG = {
	velocidadeNormal = 16,
	limiteSacosPorJogador = 1,
	sacos = {
		pequeno = { valor = 1000, velocidade = 14 },
		grande = { valor = 5000, velocidade = 10 },
	},
}

local function novoCore(limite)
	local config = table.clone(CONFIG)
	if limite then
		config.limiteSacosPorJogador = limite
	end
	return LootCore.novo({ config = config })
end

-- Core com alguns sacos ja registados no mapa.
local function comSacos(limite)
	local core = novoCore(limite)
	core:registarSaco("montra1", "pequeno")
	core:registarSaco("montra2", "pequeno")
	core:registarSaco("cofre1", "grande")
	return core
end

return function(t)
	t.describe("LootCore", function()
		t.describe("registar sacos do mapa", function()
			t.it("registar devolve true e o saco passa a existir", function()
				local core = novoCore()

				t.expect(core:registarSaco("montra1", "pequeno")).toBe(true)
				t.expect(core:tipoDoSaco("montra1")).toBe("pequeno")
			end)

			t.it("recusa um tipo de saco que nao existe no Config", function()
				local core = novoCore()

				t.expect(core:registarSaco("montra1", "diamantes")).toBe(false)
				t.expect(core:tipoDoSaco("montra1")).toBeNil()
			end)

			t.it("recusa registar o mesmo id duas vezes", function()
				-- Dois sacos com o mesmo id seria a receita para duplicar dinheiro.
				local core = novoCore()

				t.expect(core:registarSaco("montra1", "pequeno")).toBe(true)
				t.expect(core:registarSaco("montra1", "grande")).toBe(false)
				t.expect(core:tipoDoSaco("montra1")).toBe("pequeno")
			end)

			t.it("um saco que nao existe nao tem tipo", function()
				t.expect(novoCore():tipoDoSaco("inventado")).toBeNil()
			end)
		end)

		t.describe("apanhar", function()
			t.it("apanhar um saco livre funciona", function()
				local core = comSacos()
				local ok, motivo = core:apanhar(1, "montra1")

				t.expect(ok).toBe(true)
				t.expect(motivo).toBeNil()
				t.expect(core:portadorDe("montra1")).toBe(1)
				t.expect(core:sacosDoJogador(1)).toEqual({ "montra1" })
			end)

			t.it("recusa um saco que nao existe", function()
				local core = comSacos()
				local ok, motivo = core:apanhar(1, "inventado")

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("saco_desconhecido")
			end)

			t.it("recusa um saco que outro jogador ja tem", function()
				local core = comSacos()
				core:apanhar(1, "montra1")

				local ok, motivo = core:apanhar(2, "montra1")

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("ja_tem_portador")
				t.expect(core:portadorDe("montra1")).toBe(1)
			end)

			t.it("recusa apanhar outra vez o saco que ja tem", function()
				local core = comSacos()
				core:apanhar(1, "montra1")

				local ok, motivo = core:apanhar(1, "montra1")

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("ja_tem_portador")
				t.expect(#core:sacosDoJogador(1)).toBe(1)
			end)

			t.it("respeita o limite de um saco por jogador", function()
				local core = comSacos()
				core:apanhar(1, "montra1")

				local ok, motivo = core:apanhar(1, "montra2")

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("limite")
				t.expect(core:portadorDe("montra2")).toBeNil()
			end)

			t.it("com o Game Pass de 2 sacos, o limite sobe", function()
				-- Fase 5 do documento: "Carregar 2 sacos" e um Game Pass.
				local core = comSacos(2)

				t.expect(core:apanhar(1, "montra1")).toBe(true)
				t.expect(core:apanhar(1, "montra2")).toBe(true)
				t.expect(#core:sacosDoJogador(1)).toBe(2)

				local ok, motivo = core:apanhar(1, "cofre1")
				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("limite")
			end)

			t.it("jogadores diferentes podem ter sacos diferentes ao mesmo tempo", function()
				local core = comSacos()

				t.expect(core:apanhar(1, "montra1")).toBe(true)
				t.expect(core:apanhar(2, "montra2")).toBe(true)
				t.expect(core:apanhar(3, "cofre1")).toBe(true)
			end)
		end)

		t.describe("largar", function()
			t.it("largar liberta o saco", function()
				local core = comSacos()
				core:apanhar(1, "montra1")

				local ok = core:largar(1, "montra1")

				t.expect(ok).toBe(true)
				t.expect(core:portadorDe("montra1")).toBeNil()
				t.expect(core:sacosDoJogador(1)).toEqual({})
			end)

			t.it("um saco largado pode ser apanhado por outro jogador", function()
				local core = comSacos()
				core:apanhar(1, "montra1")
				core:largar(1, "montra1")

				t.expect(core:apanhar(2, "montra1")).toBe(true)
				t.expect(core:portadorDe("montra1")).toBe(2)
			end)

			t.it("largar liberta espaco para apanhar outro", function()
				local core = comSacos()
				core:apanhar(1, "montra1")
				core:largar(1, "montra1")

				t.expect(core:apanhar(1, "montra2")).toBe(true)
			end)

			t.it("recusa largar um saco que nao tem", function()
				local core = comSacos()
				core:apanhar(1, "montra1")

				local ok, motivo = core:largar(2, "montra1")

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("nao_tem_este_saco")
				t.expect(core:portadorDe("montra1")).toBe(1)
			end)

			t.it("recusa largar um saco que nao existe", function()
				local ok, motivo = comSacos():largar(1, "inventado")

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("saco_desconhecido")
			end)
		end)

		t.describe("entregar", function()
			t.it("entregar devolve o tipo, para o HeistCore somar o valor", function()
				local core = comSacos()
				core:apanhar(1, "cofre1")

				local ok, motivo, tipo = core:entregar(1, "cofre1")

				t.expect(ok).toBe(true)
				t.expect(motivo).toBeNil()
				t.expect(tipo).toBe("grande")
			end)

			t.it("um saco entregue sai do mundo e nao volta", function()
				-- Se um saco entregue pudesse ser apanhado outra vez, dava para
				-- entregar o mesmo saco infinitas vezes.
				local core = comSacos()
				core:apanhar(1, "montra1")
				core:entregar(1, "montra1")

				t.expect(core:tipoDoSaco("montra1")).toBeNil()
				t.expect(core:portadorDe("montra1")).toBeNil()

				local ok, motivo = core:apanhar(2, "montra1")
				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("saco_desconhecido")
			end)

			t.it("entregar liberta espaco para apanhar outro", function()
				local core = comSacos()
				core:apanhar(1, "montra1")
				core:entregar(1, "montra1")

				t.expect(core:apanhar(1, "montra2")).toBe(true)
			end)

			t.it("recusa entregar um saco que nao tem", function()
				local core = comSacos()
				core:apanhar(1, "montra1")

				local ok, motivo = core:entregar(2, "montra1")

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("nao_tem_este_saco")
				-- E continua a existir, na mao do jogador 1.
				t.expect(core:portadorDe("montra1")).toBe(1)
			end)

			t.it("recusa entregar um saco que esta no chao", function()
				local core = comSacos()

				local ok, motivo = core:entregar(1, "montra1")

				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("nao_tem_este_saco")
				t.expect(core:tipoDoSaco("montra1")).toBe("pequeno")
			end)

			t.it("recusa entregar duas vezes o mesmo saco", function()
				local core = comSacos()
				core:apanhar(1, "montra1")

				t.expect(core:entregar(1, "montra1")).toBe(true)

				local ok, motivo = core:entregar(1, "montra1")
				t.expect(ok).toBe(false)
				t.expect(motivo).toBe("saco_desconhecido")
			end)
		end)

		t.describe("velocidade", function()
			t.it("sem sacos anda a velocidade normal", function()
				t.expect(comSacos():velocidadeDe(1)).toBe(16)
			end)

			t.it("com saco pequeno fica mais lento", function()
				local core = comSacos()
				core:apanhar(1, "montra1")

				t.expect(core:velocidadeDe(1)).toBe(14)
			end)

			t.it("com saco grande fica ainda mais lento", function()
				local core = comSacos()
				core:apanhar(1, "cofre1")

				t.expect(core:velocidadeDe(1)).toBe(10)
			end)

			t.it("com dois sacos manda o mais pesado", function()
				local core = comSacos(2)
				core:apanhar(1, "montra1") -- 14
				core:apanhar(1, "cofre1") -- 10

				t.expect(core:velocidadeDe(1)).toBe(10)
			end)

			t.it("largar o saco devolve a velocidade normal", function()
				local core = comSacos()
				core:apanhar(1, "montra1")
				core:largar(1, "montra1")

				t.expect(core:velocidadeDe(1)).toBe(16)
			end)

			t.it("entregar o saco devolve a velocidade normal", function()
				local core = comSacos()
				core:apanhar(1, "cofre1")
				core:entregar(1, "cofre1")

				t.expect(core:velocidadeDe(1)).toBe(16)
			end)

			t.it("um jogador desconhecido anda a velocidade normal", function()
				t.expect(comSacos():velocidadeDe(999)).toBe(16)
			end)
		end)

		t.describe("jogador sai do jogo", function()
			t.it("devolve os sacos que ele tinha, para o adaptador os largar no mapa", function()
				local core = comSacos(2)
				core:apanhar(1, "montra1")
				core:apanhar(1, "cofre1")

				local largados = core:esquecerJogador(1)

				t.expect(#largados).toBe(2)
				t.expect(core:portadorDe("montra1")).toBeNil()
				t.expect(core:portadorDe("cofre1")).toBeNil()
			end)

			t.it("os sacos continuam a existir e podem ser apanhados", function()
				-- O saque nao pode desaparecer so porque alguem se desligou: isso
				-- podia tornar o assalto impossivel de terminar.
				local core = comSacos()
				core:apanhar(1, "montra1")
				core:esquecerJogador(1)

				t.expect(core:tipoDoSaco("montra1")).toBe("pequeno")
				t.expect(core:apanhar(2, "montra1")).toBe(true)
			end)

			t.it("esquecer um jogador sem sacos devolve lista vazia", function()
				t.expect(comSacos():esquecerJogador(1)).toEqual({})
			end)

			t.it("nao afeta os sacos dos outros jogadores", function()
				local core = comSacos()
				core:apanhar(1, "montra1")
				core:apanhar(2, "montra2")

				core:esquecerJogador(1)

				t.expect(core:portadorDe("montra2")).toBe(2)
			end)
		end)

		t.describe("reiniciar para o assalto seguinte", function()
			t.it("limpa sacos e portadores", function()
				local core = comSacos()
				core:apanhar(1, "montra1")

				core:reiniciar()

				t.expect(core:tipoDoSaco("montra1")).toBeNil()
				t.expect(core:sacosDoJogador(1)).toEqual({})
				t.expect(core:velocidadeDe(1)).toBe(16)
			end)
		end)
	end)
end
