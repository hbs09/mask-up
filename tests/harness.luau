--[[
	Harness de testes minimo, para correr em Lune (fora do Roblox).

	Porque e que nao usamos um framework existente:
	  - O TestEZ da Roblox esta arquivado desde marco de 2024.
	  - O Jest Lua exige o Wally e corre dentro do Roblox (20-30s por corrida).
	Este harness corre em milissegundos no terminal, o que e o que faz o ciclo
	vermelho-verde-refactor valer a pena.

	Uso num ficheiro de especificacao (tests/*.spec.luau):

		local HeistCore = require("../src/Server/Core/HeistCore")

		return function(t)
			t.describe("HeistCore", function()
				t.it("vai de Lobby para Furtivo", function()
					t.expect(estado).toBe("Furtivo")
				end)
			end)
		end

	Matchers: toBe, toEqual (profundo), toBeTruthy, toBeFalsy, toBeNil,
	toBeCloseTo, toThrow, toThrowMatching. Todos aceitam o prefixo `never`.
]]

local Harness = {}

-- Comparacao profunda de tabelas, para comparar perfis e tabelas de config.
local function iguaisProfundo(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end

	for chave, valorA in a do
		if not iguaisProfundo(valorA, b[chave]) then
			return false
		end
	end
	for chave in b do
		if a[chave] == nil then
			return false
		end
	end

	return true
end

-- Representacao legivel de um valor dentro de uma mensagem de erro.
local function mostrar(valor, profundidade)
	profundidade = profundidade or 0

	if type(valor) == "string" then
		return string.format("%q", valor)
	end
	if type(valor) ~= "table" then
		return tostring(valor)
	end
	if profundidade >= 2 then
		return "{...}"
	end

	local partes = {}
	for chave, v in valor do
		table.insert(
			partes,
			string.format("%s = %s", tostring(chave), mostrar(v, profundidade + 1))
		)
	end
	table.sort(partes)

	return "{ " .. table.concat(partes, ", ") .. " }"
end

local function criarExpect(valor, negado)
	local matchers = {}

	local function falhar(mensagem)
		error(mensagem, 3)
	end

	-- Aplica um matcher respeitando o prefixo `never`.
	local function verificar(passou, mensagemNormal, mensagemNegada)
		if negado then
			if passou then
				falhar(mensagemNegada)
			end
		else
			if not passou then
				falhar(mensagemNormal)
			end
		end
	end

	function matchers.toBe(esperado)
		verificar(
			valor == esperado,
			string.format("esperado %s, recebeu %s", mostrar(esperado), mostrar(valor)),
			string.format("nao devia ser %s, mas era", mostrar(esperado))
		)
	end

	function matchers.toEqual(esperado)
		verificar(
			iguaisProfundo(valor, esperado),
			string.format("esperado (profundo) %s, recebeu %s", mostrar(esperado), mostrar(valor)),
			string.format("nao devia ser igual a %s, mas era", mostrar(esperado))
		)
	end

	function matchers.toBeTruthy()
		verificar(
			valor and true or false,
			string.format("esperado valor verdadeiro, recebeu %s", mostrar(valor)),
			string.format("esperado valor falso, recebeu %s", mostrar(valor))
		)
	end

	function matchers.toBeFalsy()
		verificar(
			not valor,
			string.format("esperado valor falso, recebeu %s", mostrar(valor)),
			string.format("esperado valor verdadeiro, recebeu %s", mostrar(valor))
		)
	end

	function matchers.toBeNil()
		verificar(
			valor == nil,
			string.format("esperado nil, recebeu %s", mostrar(valor)),
			"esperado algo diferente de nil, recebeu nil"
		)
	end

	-- Para contas com virgula flutuante (pagamentos, WalkSpeed, multiplicadores).
	function matchers.toBeCloseTo(esperado, tolerancia)
		tolerancia = tolerancia or 1e-6

		if type(valor) ~= "number" then
			falhar(string.format("toBeCloseTo precisa de um numero, recebeu %s", mostrar(valor)))
		end

		local diferenca = math.abs(valor - esperado)
		verificar(
			diferenca <= tolerancia,
			string.format(
				"esperado ~%s (tolerancia %s), recebeu %s (diferenca %s)",
				tostring(esperado),
				tostring(tolerancia),
				tostring(valor),
				tostring(diferenca)
			),
			string.format("nao devia estar perto de %s, mas estava", tostring(esperado))
		)
	end

	function matchers.toThrow()
		if type(valor) ~= "function" then
			falhar("toThrow precisa de uma funcao")
		end

		local ok = pcall(valor)
		verificar(
			not ok,
			"esperado que a funcao lancasse erro, mas correu bem",
			"esperado que a funcao nao lancasse erro, mas lancou"
		)
	end

	-- Garante que o erro e o esperado, e nao um erro acidental (ex.: typo).
	function matchers.toThrowMatching(pedaco)
		if type(valor) ~= "function" then
			falhar("toThrowMatching precisa de uma funcao")
		end

		local ok, erro = pcall(valor)
		if ok then
			verificar(
				false,
				string.format("esperado erro contendo %s, mas correu bem", mostrar(pedaco)),
				""
			)
			return
		end

		local texto = tostring(erro)
		verificar(
			string.find(texto, pedaco, 1, true) ~= nil,
			string.format("esperado erro contendo %s, recebeu %s", mostrar(pedaco), mostrar(texto)),
			string.format("o erro nao devia conter %s, mas continha", mostrar(pedaco))
		)
	end

	return matchers
end

--[[
	Cria uma corrida de testes. Devolve:
	  t          -- a tabela passada aos ficheiros de especificacao
	  resultados -- funcao que devolve { passaram, falhas, linhas }
]]
function Harness.novaCorrida()
	local pilha = {}
	local linhas = {}
	local passaram = 0
	local falhas = {}

	local t = {}

	function t.describe(nome, corpo)
		table.insert(linhas, { tipo = "describe", texto = nome, nivel = #pilha })
		table.insert(pilha, nome)

		local ok, erro = pcall(corpo)
		if not ok then
			-- Um erro no corpo do describe (fora de um it) e um problema de setup:
			-- conta como falha para nunca passar despercebido.
			table.insert(falhas, {
				caminho = table.concat(pilha, " > "),
				mensagem = "erro no corpo do describe: " .. tostring(erro),
			})
			table.insert(linhas, { tipo = "falha", texto = "(erro de setup)", nivel = #pilha })
		end

		table.remove(pilha)
	end

	function t.it(nome, corpo)
		local ok, erro = pcall(corpo)

		if ok then
			passaram += 1
			table.insert(linhas, { tipo = "passou", texto = nome, nivel = #pilha })
		else
			table.insert(pilha, nome)
			table.insert(
				falhas,
				{ caminho = table.concat(pilha, " > "), mensagem = tostring(erro) }
			)
			table.remove(pilha)

			table.insert(
				linhas,
				{ tipo = "falha", texto = nome, nivel = #pilha, erro = tostring(erro) }
			)
		end
	end

	function t.expect(valor)
		local api = criarExpect(valor, false)
		api.never = criarExpect(valor, true)
		return api
	end

	local function resultados()
		return { passaram = passaram, falhas = falhas, linhas = linhas }
	end

	return t, resultados
end

-- Exposto para o auto-teste do harness poder verificar a comparacao profunda.
Harness.iguaisProfundo = iguaisProfundo
Harness.mostrar = mostrar

return Harness
