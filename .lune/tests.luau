--[[
	Corre todos os testes do projeto.

		lune run .lune/tests.luau          -- todos
		lune run .lune/tests.luau Heist    -- so os specs cujo nome contem "Heist"

	Tem de ser corrido a partir da raiz do projeto (os caminhos do fs sao
	relativos ao diretorio atual, ao contrario dos do require).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local Harness = require("../tests/harness")

local PASTA_TESTES = "tests"
local SUFIXO = ".spec.luau"

local filtro = process.args[1]

-- Descobre os ficheiros de especificacao, incluindo em subpastas.
local function procurarSpecs(pasta, encontrados)
	for _, nome in fs.readDir(pasta) do
		local caminho = pasta .. "/" .. nome

		if fs.isDir(caminho) then
			procurarSpecs(caminho, encontrados)
		elseif string.sub(nome, -#SUFIXO) == SUFIXO then
			table.insert(encontrados, caminho)
		end
	end

	return encontrados
end

local specs = procurarSpecs(PASTA_TESTES, {})
table.sort(specs)

if filtro then
	local filtrados = {}
	for _, caminho in specs do
		if string.find(string.lower(caminho), string.lower(filtro), 1, true) then
			table.insert(filtrados, caminho)
		end
	end
	specs = filtrados
end

if #specs == 0 then
	print(
		stdio.color("yellow")
			.. "Nenhum ficheiro "
			.. SUFIXO
			.. " encontrado em "
			.. PASTA_TESTES
			.. "/"
			.. stdio.color("reset")
	)
	process.exit(1)
end

local inicio = os.clock()
local t, resultados = Harness.novaCorrida()

for _, caminho in specs do
	-- O require e relativo a ESTE ficheiro (.lune/), o fs e relativo ao cwd.
	local moduloRelativo = "../" .. string.sub(caminho, 1, -#".luau" - 1)

	local ok, spec = pcall(require, moduloRelativo)
	if not ok then
		print(stdio.color("red") .. "Falhou a carregar " .. caminho .. stdio.color("reset"))
		print("  " .. tostring(spec))
		process.exit(1)
	end

	if type(spec) ~= "function" then
		print(
			stdio.color("red")
				.. caminho
				.. " devia devolver uma funcao(t), devolveu "
				.. type(spec)
				.. stdio.color("reset")
		)
		process.exit(1)
	end

	spec(t)
end

local r = resultados()
local decorrido = (os.clock() - inicio) * 1000

print("")
for _, linha in r.linhas do
	local recuo = string.rep("  ", linha.nivel + 1)

	if linha.tipo == "describe" then
		print(
			string.rep("  ", linha.nivel)
				.. stdio.style("bold")
				.. linha.texto
				.. stdio.style("reset")
		)
	elseif linha.tipo == "passou" then
		print(recuo .. stdio.color("green") .. "ok " .. stdio.color("reset") .. linha.texto)
	else
		print(recuo .. stdio.color("red") .. "XX " .. linha.texto .. stdio.color("reset"))
		if linha.erro then
			for pedaco in string.gmatch(linha.erro, "[^\n]+") do
				print(recuo .. "     " .. stdio.color("red") .. pedaco .. stdio.color("reset"))
			end
		end
	end
end

print("")
local resumo = string.format("%d passaram", r.passaram)
if #r.falhas > 0 then
	resumo ..= string.format(
		", %s%d falharam%s",
		stdio.color("red"),
		#r.falhas,
		stdio.color("reset")
	)
end
resumo ..= string.format("  (%d specs, %.0fms)", #specs, decorrido)
print(resumo)

if #r.falhas > 0 then
	process.exit(1)
end
