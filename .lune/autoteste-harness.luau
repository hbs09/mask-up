--[[
	Auto-teste do harness: lune run .lune/autoteste-harness.luau

	Um harness de testes com um bug que faca tudo passar e pior do que nao ter
	testes, porque da confianca falsa. Este script usa o harness para correr
	testes que DEVEM passar e testes que DEVEM falhar, e confirma que ele contou
	bem. Nao usa o proprio harness para se validar (seria circular) -- usa
	assert() direto.
]]

local process = require("@lune/process")
local stdio = require("@lune/stdio")

local Harness = require("../tests/harness")

local problemas = {}

local function verificar(descricao, condicao)
	if condicao then
		print(stdio.color("green") .. "ok " .. stdio.color("reset") .. descricao)
	else
		print(stdio.color("red") .. "XX " .. descricao .. stdio.color("reset"))
		table.insert(problemas, descricao)
	end
end

-- 1. Um teste que passa conta como passagem, e nenhum como falha.
do
	local t, resultados = Harness.novaCorrida()
	t.describe("grupo", function()
		t.it("passa", function()
			t.expect(1).toBe(1)
		end)
	end)

	local r = resultados()
	verificar("teste que passa -> 1 passou, 0 falhas", r.passaram == 1 and #r.falhas == 0)
end

-- 2. Um teste que falha e REGISTADO como falha (o cenario que importa).
do
	local t, resultados = Harness.novaCorrida()
	t.describe("grupo", function()
		t.it("falha", function()
			t.expect(1).toBe(2)
		end)
	end)

	local r = resultados()
	verificar("teste que falha -> 0 passaram, 1 falha", r.passaram == 0 and #r.falhas == 1)
	verificar(
		"a mensagem de falha diz o esperado e o recebido",
		#r.falhas == 1
			and string.find(r.falhas[1].mensagem, "esperado 2, recebeu 1", 1, true) ~= nil
	)
	verificar(
		"a falha guarda o caminho 'grupo > falha'",
		#r.falhas == 1 and r.falhas[1].caminho == "grupo > falha"
	)
end

-- 3. Um erro inesperado (nao um expect) tambem conta como falha.
do
	local t, resultados = Harness.novaCorrida()
	t.describe("grupo", function()
		t.it("rebenta", function()
			local nada = nil :: any
			return nada.campo
		end)
	end)

	local r = resultados()
	verificar("erro de runtime -> conta como falha", r.passaram == 0 and #r.falhas == 1)
end

-- 4. Um erro no corpo do describe (setup) nao passa despercebido.
do
	local t, resultados = Harness.novaCorrida()
	t.describe("grupo", function()
		error("setup mal feito")
	end)

	local r = resultados()
	verificar("erro no describe -> conta como falha", #r.falhas == 1)
end

-- 5. Os matchers, cada um no caso que passa e no caso que falha.
do
	local casos = {
		{
			nome = "toBe",
			passa = function(t)
				t.expect("a").toBe("a")
			end,
			falha = function(t)
				t.expect("a").toBe("b")
			end,
		},
		{
			nome = "toEqual profundo",
			passa = function(t)
				t.expect({ a = { b = 1 } }).toEqual({ a = { b = 1 } })
			end,
			falha = function(t)
				t.expect({ a = { b = 1 } }).toEqual({ a = { b = 2 } })
			end,
		},
		{
			nome = "toEqual deteta chave a mais",
			passa = function(t)
				t.expect({ a = 1 }).toEqual({ a = 1 })
			end,
			falha = function(t)
				t.expect({ a = 1, b = 2 }).toEqual({ a = 1 })
			end,
		},
		{
			nome = "toEqual deteta chave a menos",
			passa = function(t)
				t.expect({ a = 1 }).toEqual({ a = 1 })
			end,
			falha = function(t)
				t.expect({ a = 1 }).toEqual({ a = 1, b = 2 })
			end,
		},
		{
			nome = "toBeTruthy",
			passa = function(t)
				t.expect(1).toBeTruthy()
			end,
			falha = function(t)
				t.expect(false).toBeTruthy()
			end,
		},
		{
			nome = "toBeFalsy",
			passa = function(t)
				t.expect(nil).toBeFalsy()
			end,
			falha = function(t)
				t.expect(1).toBeFalsy()
			end,
		},
		{
			nome = "toBeNil",
			passa = function(t)
				t.expect(nil).toBeNil()
			end,
			falha = function(t)
				t.expect(0).toBeNil()
			end,
		},
		{
			nome = "toBeCloseTo",
			passa = function(t)
				t.expect(0.1 + 0.2).toBeCloseTo(0.3)
			end,
			falha = function(t)
				t.expect(1).toBeCloseTo(2)
			end,
		},
		{
			nome = "toThrow",
			passa = function(t)
				t.expect(function()
					error("x")
				end).toThrow()
			end,
			falha = function(t)
				t.expect(function() end).toThrow()
			end,
		},
		{
			nome = "toThrowMatching",
			passa = function(t)
				t.expect(function()
					error("sem municao")
				end).toThrowMatching("municao")
			end,
			falha = function(t)
				t.expect(function()
					error("outro erro")
				end).toThrowMatching("municao")
			end,
		},
		{
			nome = "never.toBe",
			passa = function(t)
				t.expect(1).never.toBe(2)
			end,
			falha = function(t)
				t.expect(1).never.toBe(1)
			end,
		},
		{
			nome = "never.toEqual",
			passa = function(t)
				t.expect({ a = 1 }).never.toEqual({ a = 2 })
			end,
			falha = function(t)
				t.expect({ a = 1 }).never.toEqual({ a = 1 })
			end,
		},
	}

	for _, caso in casos do
		local t, resultados = Harness.novaCorrida()
		t.describe("m", function()
			-- `it` chama o corpo sem argumentos, por isso fechamos sobre o `t`
			-- desta corrida em vez de o receber por parametro.
			t.it("caso que passa", function()
				caso.passa(t)
			end)
			t.it("caso que falha", function()
				caso.falha(t)
			end)
		end)

		local r = resultados()
		verificar(
			string.format("matcher %s: passa quando deve, falha quando deve", caso.nome),
			r.passaram == 1 and #r.falhas == 1
		)
	end
end

-- 6. A comparacao profunda nao se engana com tipos nem com tabelas aninhadas.
do
	verificar(
		"iguaisProfundo: aninhado igual",
		Harness.iguaisProfundo({ a = { b = { c = 1 } } }, { a = { b = { c = 1 } } })
	)
	verificar(
		"iguaisProfundo: aninhado diferente",
		not Harness.iguaisProfundo({ a = { b = 1 } }, { a = { b = 2 } })
	)
	verificar("iguaisProfundo: 1 nao e '1'", not Harness.iguaisProfundo(1, "1"))
	verificar("iguaisProfundo: tabela nao e numero", not Harness.iguaisProfundo({}, 0))
	verificar("iguaisProfundo: listas", Harness.iguaisProfundo({ 1, 2, 3 }, { 1, 2, 3 }))
	verificar(
		"iguaisProfundo: listas de tamanho diferente",
		not Harness.iguaisProfundo({ 1, 2 }, { 1, 2, 3 })
	)
end

print("")
if #problemas > 0 then
	print(
		string.format(
			"%s%d problemas no harness%s",
			stdio.color("red"),
			#problemas,
			stdio.color("reset")
		)
	)
	process.exit(1)
end
print(
	stdio.color("green")
		.. "Harness validado: deteta passagens e falhas corretamente."
		.. stdio.color("reset")
)
