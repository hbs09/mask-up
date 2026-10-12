--[[
	O perfil guardado por jogador (secção 7 do documento).

	Porque e que isto esta testado antes de haver DataStore: a FORMA do perfil e
	um contrato. Quando a Fase 3 trocar o armazenamento em memoria por DataStore
	real, estes testes nao mudam -- e a migracao de versao, que e a parte mais
	perigosa de qualquer jogo com progressao, ja esta coberta aqui.
]]

local PerfilCore = require("../src/Server/Core/PerfilCore")

local XP_BASE = 100

local function novoCore()
	return PerfilCore.novo({ xpBase = XP_BASE, nivelMaximo = 10 })
end

return function(t)
	t.describe("PerfilCore", function()
		t.describe("perfil por omissao", function()
			t.it("tem exatamente a forma da secção 7 do documento", function()
				local p = novoCore():perfilNovo()

				t.expect(p).toEqual({
					versao = 1,
					dinheiro = 0,
					xp = 0,
					nivel = 1,
					kitsEmergencia = 0,
					armas = { "Pistola" },
					mascaras = { "Basica" },
					mascaraEquipada = "Basica",
					desafios = { diario = {}, semanal = {} },
					ultimaRecompensaDiaria = 0,
					estatisticas = { assaltos = 0, furtivos = 0 },
				})
			end)

			t.it("dois perfis novos nao partilham as tabelas aninhadas", function()
				-- O bug classico: devolver sempre a MESMA tabela por omissao faz
				-- com que a mascara comprada por um jogador apareca a todos.
				local core = novoCore()
				local a = core:perfilNovo()
				local b = core:perfilNovo()

				table.insert(a.mascaras, "Caveira")
				a.estatisticas.assaltos = 7

				t.expect(#b.mascaras).toBe(1)
				t.expect(b.estatisticas.assaltos).toBe(0)
			end)
		end)

		t.describe("dinheiro", function()
			t.it("soma o que foi ganho", function()
				local core = novoCore()
				local p = core:perfilNovo()

				core:adicionarDinheiro(p, 5000)
				core:adicionarDinheiro(p, 2500)

				t.expect(p.dinheiro).toBe(7500)
			end)

			t.it("permite perder dinheiro (ser preso, pagar advogado)", function()
				local core = novoCore()
				local p = core:perfilNovo()

				core:adicionarDinheiro(p, 1000)
				core:adicionarDinheiro(p, -400)

				t.expect(p.dinheiro).toBe(600)
			end)

			t.it("nunca deixa o dinheiro ficar negativo", function()
				local core = novoCore()
				local p = core:perfilNovo()

				core:adicionarDinheiro(p, 100)
				core:adicionarDinheiro(p, -99999)

				t.expect(p.dinheiro).toBe(0)
			end)

			t.it("ignora valores que nao sao numeros", function()
				local core = novoCore()
				local p = core:perfilNovo()

				core:adicionarDinheiro(p, "muito" :: any)
				core:adicionarDinheiro(p, nil :: any)

				t.expect(p.dinheiro).toBe(0)
			end)

			t.it("ignora NaN e infinito (dariam dinheiro corrompido para sempre)", function()
				local core = novoCore()
				local p = core:perfilNovo()

				core:adicionarDinheiro(p, 0 / 0)
				core:adicionarDinheiro(p, math.huge)

				t.expect(p.dinheiro).toBe(0)
			end)

			t.it("arredonda para inteiro (nao ha centimos no jogo)", function()
				local core = novoCore()
				local p = core:perfilNovo()

				core:adicionarDinheiro(p, 100.7)

				t.expect(p.dinheiro).toBe(100)
			end)
		end)

		t.describe("xp e niveis", function()
			-- Custo do nivel n para n+1 = XP_BASE * n, logo o XP acumulado para
			-- chegar ao nivel L e XP_BASE * (L-1) * L / 2.
			t.it("comeca no nivel 1 com 0 xp", function()
				local core = novoCore()
				t.expect(core:nivelPara(0)).toBe(1)
			end)

			t.it("sobe de nivel nos limites certos", function()
				local core = novoCore()

				t.expect(core:nivelPara(99)).toBe(1)
				t.expect(core:nivelPara(100)).toBe(2)
				t.expect(core:nivelPara(299)).toBe(2)
				t.expect(core:nivelPara(300)).toBe(3)
				t.expect(core:nivelPara(600)).toBe(4)
				t.expect(core:nivelPara(1000)).toBe(5)
			end)

			t.it("nunca passa do nivel maximo", function()
				local core = novoCore()
				t.expect(core:nivelPara(999999999)).toBe(10)
			end)

			t.it("adicionarXp atualiza o nivel no perfil", function()
				local core = novoCore()
				local p = core:perfilNovo()

				core:adicionarXp(p, 350)

				t.expect(p.xp).toBe(350)
				t.expect(p.nivel).toBe(3)
			end)

			t.it("devolve quantos niveis subiu, para o ecra final poder festejar", function()
				local core = novoCore()
				local p = core:perfilNovo()

				t.expect(core:adicionarXp(p, 100)).toBe(1)
				t.expect(core:adicionarXp(p, 200)).toBe(1)
				t.expect(core:adicionarXp(p, 10)).toBe(0)
			end)

			t.it("ignora xp negativo (nao se perde progresso)", function()
				local core = novoCore()
				local p = core:perfilNovo()

				core:adicionarXp(p, 300)
				core:adicionarXp(p, -1000)

				t.expect(p.xp).toBe(300)
				t.expect(p.nivel).toBe(3)
			end)
		end)

		t.describe("estatisticas", function()
			t.it("conta um assalto barulhento", function()
				local core = novoCore()
				local p = core:perfilNovo()

				core:registarAssalto(p, false)

				t.expect(p.estatisticas.assaltos).toBe(1)
				t.expect(p.estatisticas.furtivos).toBe(0)
			end)

			t.it("um assalto furtivo conta nas duas contagens", function()
				local core = novoCore()
				local p = core:perfilNovo()

				core:registarAssalto(p, true)

				t.expect(p.estatisticas.assaltos).toBe(1)
				t.expect(p.estatisticas.furtivos).toBe(1)
			end)
		end)

		t.describe("mascaras", function()
			t.it("desbloquear acrescenta a lista", function()
				local core = novoCore()
				local p = core:perfilNovo()

				t.expect(core:desbloquearMascara(p, "Caveira")).toBe(true)
				t.expect(p.mascaras).toEqual({ "Basica", "Caveira" })
			end)

			t.it("nao duplica uma mascara que ja tem", function()
				local core = novoCore()
				local p = core:perfilNovo()

				core:desbloquearMascara(p, "Caveira")
				t.expect(core:desbloquearMascara(p, "Caveira")).toBe(false)
				t.expect(#p.mascaras).toBe(2)
			end)

			t.it("equipar funciona se a mascara for dele", function()
				local core = novoCore()
				local p = core:perfilNovo()

				core:desbloquearMascara(p, "Caveira")

				t.expect(core:equiparMascara(p, "Caveira")).toBe(true)
				t.expect(p.mascaraEquipada).toBe("Caveira")
			end)

			t.it("recusa equipar uma mascara que nao tem (cliente a mentir)", function()
				local core = novoCore()
				local p = core:perfilNovo()

				t.expect(core:equiparMascara(p, "MascaraDoChefe")).toBe(false)
				t.expect(p.mascaraEquipada).toBe("Basica")
			end)
		end)

		t.describe("migracao de versao", function()
			t.it("um perfil novo passa pela migracao sem mudar", function()
				local core = novoCore()
				local p = core:perfilNovo()

				t.expect(core:migrar(p)).toEqual(p)
			end)

			t.it("preenche campos que faltam sem apagar o que ja existia", function()
				local core = novoCore()

				-- Um perfil guardado numa versao antiga do jogo: so tinha dinheiro.
				local antigo = { versao = 1, dinheiro = 12345 }
				local migrado = core:migrar(antigo)

				t.expect(migrado.dinheiro).toBe(12345)
				t.expect(migrado.nivel).toBe(1)
				t.expect(migrado.mascaraEquipada).toBe("Basica")
				t.expect(migrado.estatisticas).toEqual({ assaltos = 0, furtivos = 0 })
			end)

			t.it("aceita um perfil sem campo versao (guardado antes de haver versoes)", function()
				local core = novoCore()
				local migrado = core:migrar({ dinheiro = 500 })

				t.expect(migrado.dinheiro).toBe(500)
				t.expect(migrado.versao).toBe(1)
			end)

			t.it("nil devolve um perfil novo (jogador que nunca entrou)", function()
				local core = novoCore()
				t.expect(core:migrar(nil)).toEqual(core:perfilNovo())
			end)

			t.it("lixo em vez de perfil devolve um perfil novo, sem rebentar", function()
				local core = novoCore()

				t.expect(core:migrar("corrompido" :: any)).toEqual(core:perfilNovo())
				t.expect(core:migrar(42 :: any)).toEqual(core:perfilNovo())
			end)

			t.it("recalcula o nivel a partir do xp, em vez de confiar no valor guardado", function()
				local core = novoCore()

				-- Nivel guardado errado (bug antigo, ou DataStore editado a mao).
				local migrado = core:migrar({ versao = 1, xp = 300, nivel = 99 })

				t.expect(migrado.nivel).toBe(3)
			end)

			t.it("nao deixa passar tipos errados vindos do armazenamento", function()
				local core = novoCore()
				local migrado = core:migrar({
					versao = 1,
					dinheiro = "muito" :: any,
					armas = "Pistola" :: any,
					estatisticas = 5 :: any,
				})

				t.expect(migrado.dinheiro).toBe(0)
				t.expect(migrado.armas).toEqual({ "Pistola" })
				t.expect(migrado.estatisticas).toEqual({ assaltos = 0, furtivos = 0 })
			end)
		end)
	end)
end
