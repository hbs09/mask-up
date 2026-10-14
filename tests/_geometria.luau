--[[
	Confere a geometria do mapa SEM abrir o Studio.

	Nao e um spec normal (nao corre no `lune run .lune/tests.luau`): repete a
	aritmetica do MapBuilder para confirmar que as pecas encaixam, em vez de
	descobrir uma queda no vazio a jogar. Correr com:

		lune run tests/_geometria.luau

	Vale sobretudo depois de mexer nas medidas da LOJA ou nas posicoes.
]]

local LOJA =
	{ largura = 60, profundidade = 40, altura = 14, espessuraParede = 2, larguraEntrada = 10 }
local LOBBY_Z = 90
local ESCAPE_Z = -(LOJA.profundidade / 2 + 18)

local problemas = {}

-- Intervalo ocupado por uma peca num eixo.
local function faixa(centro, tamanho)
	return { min = centro - tamanho / 2, max = centro + tamanho / 2 }
end

local function verificar(descricao, condicao, detalhe)
	if condicao then
		print(string.format("ok  %s", descricao))
	else
		print(string.format("XX  %s  %s", descricao, detalhe or ""))
		table.insert(problemas, descricao)
	end
end

local function contido(dentro, fora, nome)
	return dentro.min >= fora.min and dentro.max <= fora.max,
		string.format(
			"%s [%g..%g] fora de [%g..%g]",
			nome,
			dentro.min,
			dentro.max,
			fora.min,
			fora.max
		)
end

local function sobrepoem(a, b)
	return a.min <= b.max and b.min <= a.max
end

-- === Terreno ===
local terrenoZ = faixa(30, 200)
local terrenoX = faixa(0, 160)

-- === Pecas ===
local lojaZ = faixa(0, LOJA.profundidade)
local lojaX = faixa(0, LOJA.largura)
local lobbyZ = faixa(LOBBY_Z, 40)
local caminhoEntradaZ =
	faixa((LOBBY_Z - 20 + LOJA.profundidade / 2) / 2, LOBBY_Z - 20 - LOJA.profundidade / 2)
local caminhoFugaZ = faixa(-(LOJA.profundidade / 2) - 8, 16)
local zonaZ = faixa(ESCAPE_Z + 7, 12)
local carrinhaZ = faixa(ESCAPE_Z - 4, 18)

print("=== tudo assenta no terreno (nada no vazio) ===")
verificar("loja", contido(lojaZ, terrenoZ, "loja Z"))
verificar("lobby", contido(lobbyZ, terrenoZ, "lobby Z"))
verificar("carrinha", contido(carrinhaZ, terrenoZ, "carrinha Z"))
verificar("zona de entrega", contido(zonaZ, terrenoZ, "zona Z"))
verificar("loja no eixo X", contido(lojaX, terrenoX, "loja X"))

print("")
print("=== o percurso nao tem buracos ===")
verificar(
	"caminho liga a frente da loja ao lobby",
	math.abs(caminhoEntradaZ.min - lojaZ.max) < 0.01
		and math.abs(caminhoEntradaZ.max - lobbyZ.min) < 0.01,
	string.format(
		"caminho [%g..%g], loja acaba em %g, lobby comeca em %g",
		caminhoEntradaZ.min,
		caminhoEntradaZ.max,
		lojaZ.max,
		lobbyZ.min
	)
)
verificar(
	"caminho de fuga arranca nas traseiras da loja",
	math.abs(caminhoFugaZ.max - lojaZ.min) < 0.01,
	string.format("caminho acaba em %g, loja comeca em %g", caminhoFugaZ.max, lojaZ.min)
)
verificar(
	"a zona de entrega e alcancavel pelo caminho de fuga",
	sobrepoem(caminhoFugaZ, zonaZ),
	string.format(
		"caminho [%g..%g], zona [%g..%g]",
		caminhoFugaZ.min,
		caminhoFugaZ.max,
		zonaZ.min,
		zonaZ.max
	)
)

print("")
print("=== o cofre nao tapa o vao de saida ===")
local vaoX = faixa(0, LOJA.larguraEntrada)
local cofreX = faixa(-18, 8)
verificar(
	"cofre fora do vao",
	not sobrepoem(cofreX, vaoX),
	string.format("cofre [%g..%g], vao [%g..%g]", cofreX.min, cofreX.max, vaoX.min, vaoX.max)
)
verificar("cofre dentro da loja", contido(cofreX, lojaX, "cofre X"))

print("")
print("=== montras dentro das paredes ===")
local espacamento = LOJA.profundidade / (math.ceil(4 / 2) + 1)
local interiorX = faixa(0, LOJA.largura - LOJA.espessuraParede * 2)
for indice = 1, 4 do
	local ladoEsquerdo = indice % 2 == 1
	local posicaoNaFila = math.ceil(indice / 2)
	local x = if ladoEsquerdo then -(LOJA.largura / 2 - 5) else LOJA.largura / 2 - 5
	local z = LOJA.profundidade / 2 - posicaoNaFila * espacamento

	local mx = faixa(x, 6)
	local mz = faixa(z, 3)
	verificar(string.format("Montra%d dentro da loja", indice), contido(mx, interiorX, "X"))
	verificar(string.format("Montra%d dentro da loja (Z)", indice), contido(mz, lojaZ, "Z"))
end

print("")
print("=== cameras dentro da loja e a olhar para dentro ===")
--[[
	As posicoes e angulos estao duplicados do CameraService, como as da loja
	estao do MapBuilder. Vale a pena: uma camera montada dentro de uma parede ou
	a apontar para fora da loja nao da erro nenhum em runtime -- simplesmente
	nunca ve ninguem, e isso descobre-se depois de muito tempo a jogar sem nunca
	ser apanhado por uma.
]]
local CAMARAS = {
	{ nome = "Camera1", x = -26, y = 10, z = -16, angulo = 135 },
	{ nome = "Camera2", x = 26, y = 10, z = -16, angulo = -135 },
}

local interiorDaLojaX = faixa(0, LOJA.largura - LOJA.espessuraParede * 2)
local interiorDaLojaZ = faixa(0, LOJA.profundidade - LOJA.espessuraParede * 2)

for _, c in CAMARAS do
	verificar(
		string.format("%s dentro das paredes (X)", c.nome),
		contido(faixa(c.x, 1.6), interiorDaLojaX, "X")
	)
	verificar(
		string.format("%s dentro das paredes (Z)", c.nome),
		contido(faixa(c.z, 2.4), interiorDaLojaZ, "Z")
	)
	verificar(
		string.format("%s abaixo do teto", c.nome),
		c.y + 0.6 <= LOJA.altura,
		string.format("topo em %g, teto em %g", c.y + 0.6, LOJA.altura)
	)

	-- Direcao de olhar, igual a do CameraService: (sin, 0, -cos) do angulo.
	local radianos = math.rad(c.angulo)
	local dirX = math.sin(radianos)
	local dirZ = -math.cos(radianos)

	-- Um ponto a meio do alcance tem de cair dentro da loja; se cair fora, a
	-- camera esta a olhar para uma parede.
	local alvoX = c.x + dirX * 11
	local alvoZ = c.z + dirZ * 11

	verificar(
		string.format("%s olha para dentro da loja", c.nome),
		math.abs(alvoX) < LOJA.largura / 2 and math.abs(alvoZ) < LOJA.profundidade / 2,
		string.format("a 11 studs aponta para (%.0f, %.0f)", alvoX, alvoZ)
	)
end

verificar(
	"as duas cameras nao estao no mesmo sitio",
	math.abs(CAMARAS[1].x - CAMARAS[2].x) > 4 or math.abs(CAMARAS[1].z - CAMARAS[2].z) > 4,
	"duas cameras sobrepostas cobrem metade do que parecem"
)

verificar(
	"as cameras nao ficam dentro do cofre",
	not (sobrepoem(faixa(CAMARAS[1].x, 1.6), cofreX) and CAMARAS[1].y < 8),
	"o cofre vai do chao aos 8 studs"
)

print("")
if #problemas > 0 then
	print(string.format("%d problemas de geometria", #problemas))
	local process = require("@lune/process")
	process.exit(1)
end
print("Geometria coerente: nada no vazio, percurso continuo.")
