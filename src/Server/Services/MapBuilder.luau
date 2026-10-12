--!strict
--[[
	Constroi a joalharia de teste com Parts -- ADAPTADOR.

	Porque e que o mapa e gerado por codigo: desbloqueia toda a programacao antes
	de existir um mapa bonito. Os nomes seguem a secção 3 do documento, por isso
	quando substituires isto por um mapa feito a mao no Studio, os servicos
	continuam a encontrar tudo sem uma linha alterada -- procuram por nome, nao
	por posicao.

	Arvore criada (quantidades em Config.mapa):
	  Workspace/Map/Joalharia/   chao, paredes, balcao
	  Workspace/Loot/            Montra1..4 (sacos pequenos), Cofre (saco grande)
	  Workspace/EscapeZone/      Carrinha + Zona, nas traseiras
	  Workspace/Waypoints/       W1..W6, rotas dos guardas (prontas p/ Fase 1)
	  Workspace/Guards/          vazia por agora
	  Workspace/Cameras/         vazia por agora
	  Workspace/Lobby/           chao e SpawnLocation, afastado da loja

	A pasta Guards fica vazia: e o GuardService que a povoa a partir dos
	Waypoints, da mesma maneira que o LootService povoa os Sacos a partir dos
	marcadores de Loot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MapBuilder = {}

-- Medidas da loja, em studs. A loja fica centrada na origem e o lobby afastado
-- no +Z, para os jogadores nao caírem dentro do assalto ao entrar no jogo.
local LOJA = {
	largura = 60,
	profundidade = 40,
	altura = 14,
	espessuraParede = 2,
	larguraEntrada = 10,
}

local LOBBY_Z = 90
local ESCAPE_Z = -(LOJA.profundidade / 2 + 18) -- traseiras da loja

local CORES = {
	chao = Color3.fromRGB(90, 85, 80),
	parede = Color3.fromRGB(150, 140, 125),
	montra = Color3.fromRGB(120, 200, 230),
	cofre = Color3.fromRGB(70, 70, 75),
	carrinha = Color3.fromRGB(40, 60, 100),
	zonaFuga = Color3.fromRGB(80, 200, 120),
	lobby = Color3.fromRGB(60, 70, 90),
	waypoint = Color3.fromRGB(255, 200, 0),
	terreno = Color3.fromRGB(70, 110, 70),
	caminho = Color3.fromRGB(130, 125, 115),
}

type PropsParte = {
	nome: string,
	tamanho: Vector3,
	posicao: Vector3,
	cor: Color3,
	pai: Instance,
	transparencia: number?,
	colide: boolean?,
	material: Enum.Material?,
}

local function criarParte(props: PropsParte): Part
	local parte = Instance.new("Part")

	parte.Name = props.nome
	parte.Size = props.tamanho
	parte.Position = props.posicao
	parte.Color = props.cor
	parte.Anchored = true -- sem isto o mapa cai assim que o jogo arranca

	-- Enum.SurfaceType, nao Enum.NormalId: sao dois enums diferentes e o Roblox
	-- rejeita a atribuicao em runtime. Smooth tira os pinos e reentrancias que
	-- as Parts tem por omissao.
	parte.TopSurface = Enum.SurfaceType.Smooth
	parte.BottomSurface = Enum.SurfaceType.Smooth
	parte.Transparency = props.transparencia or 0
	parte.CanCollide = if props.colide == nil then true else props.colide
	parte.Material = props.material or Enum.Material.SmoothPlastic
	parte.Parent = props.pai

	return parte
end

local function criarPasta(nome: string, pai: Instance): Folder
	local pasta = Instance.new("Folder")
	pasta.Name = nome
	pasta.Parent = pai
	return pasta
end

--[[
	Terreno: um chao unico por baixo de tudo.

	Porque e que existe: sem ele, o lobby e a loja eram duas plataformas a
	flutuar com 50 studs de vazio entre as duas. Quem andasse para a frente no
	lobby caía e morria antes de chegar a joalharia.

	O topo fica exatamente em y = 0, ao nivel do chao da loja e do lobby, para
	nao haver degrau nem queda em nenhuma transicao.
]]
local function construirTerreno(pai: Instance)
	local terreno = criarPasta("Terreno", pai)

	criarParte({
		nome = "Chao",
		-- Cobre do lobby (z ~110) ate atras da carrinha (z ~-60), com folga.
		tamanho = Vector3.new(160, 2, 200),
		posicao = Vector3.new(0, -1, 30),
		cor = CORES.terreno,
		pai = terreno,
		material = Enum.Material.Grass,
	})

	-- Caminho do lobby ate a entrada da loja, para se ver para onde ir.
	criarParte({
		nome = "CaminhoEntrada",
		tamanho = Vector3.new(LOJA.larguraEntrada, 0.4, LOBBY_Z - 20 - LOJA.profundidade / 2),
		posicao = Vector3.new(0, 0.2, (LOBBY_Z - 20 + LOJA.profundidade / 2) / 2),
		cor = CORES.caminho,
		pai = terreno,
		material = Enum.Material.Concrete,
	})

	-- E das traseiras da loja ate a carrinha.
	criarParte({
		nome = "CaminhoFuga",
		tamanho = Vector3.new(LOJA.larguraEntrada, 0.4, 16),
		posicao = Vector3.new(0, 0.2, -(LOJA.profundidade / 2) - 8),
		cor = CORES.caminho,
		pai = terreno,
		material = Enum.Material.Concrete,
	})
end

--[[
	Uma parede com um vao ao meio, feita de dois pedacos.

	Usada na frente (entrada) e nas traseiras (saida para a carrinha). Sem a
	saida de tras, o percurso ate a carrinha obrigava a dar a volta ao edificio
	inteiro a carregar um saco em marcha lenta.
]]
local function paredeComVao(props: { nome: string, z: number, pai: Instance })
	local larguraPedaco = (LOJA.largura - LOJA.larguraEntrada) / 2
	local centroPedaco = LOJA.larguraEntrada / 2 + larguraPedaco / 2

	for _, lado in { -1, 1 } do
		criarParte({
			nome = props.nome .. (if lado == -1 then "Esquerda" else "Direita"),
			tamanho = Vector3.new(larguraPedaco, LOJA.altura, LOJA.espessuraParede),
			posicao = Vector3.new(lado * centroPedaco, LOJA.altura / 2, props.z),
			cor = CORES.parede,
			pai = props.pai,
		})
	end
end

-- Chao e paredes, com vao de entrada a frente (+Z) e de saida atras (-Z).
local function construirLoja(pai: Instance)
	local joalharia = criarPasta("Joalharia", pai)

	criarParte({
		nome = "Chao",
		tamanho = Vector3.new(LOJA.largura, 1, LOJA.profundidade),
		posicao = Vector3.new(0, -0.5, 0),
		cor = CORES.chao,
		pai = joalharia,
		material = Enum.Material.Concrete,
	})

	local metadeX = LOJA.largura / 2
	local metadeZ = LOJA.profundidade / 2
	local alturaMeio = LOJA.altura / 2

	-- Paredes laterais, inteiras.
	criarParte({
		nome = "ParedeEsquerda",
		tamanho = Vector3.new(LOJA.espessuraParede, LOJA.altura, LOJA.profundidade),
		posicao = Vector3.new(-metadeX, alturaMeio, 0),
		cor = CORES.parede,
		pai = joalharia,
	})
	criarParte({
		nome = "ParedeDireita",
		tamanho = Vector3.new(LOJA.espessuraParede, LOJA.altura, LOJA.profundidade),
		posicao = Vector3.new(metadeX, alturaMeio, 0),
		cor = CORES.parede,
		pai = joalharia,
	})

	-- Frente e traseiras com vao, alinhados com o lobby e com a carrinha: o
	-- percurso fica uma linha reta, lobby -> loja -> carrinha.
	paredeComVao({ nome = "ParedeFrente", z = metadeZ, pai = joalharia })
	paredeComVao({ nome = "ParedeTras", z = -metadeZ, pai = joalharia })

	-- Balcao no meio, so para o espaco nao ser uma caixa vazia e para dar
	-- obstaculos aos raycasts de visao dos guardas na Fase 1.
	criarParte({
		nome = "Balcao",
		tamanho = Vector3.new(24, 4, 3),
		posicao = Vector3.new(0, 2, 4),
		cor = CORES.parede,
		pai = joalharia,
		material = Enum.Material.Wood,
	})
end

--[[
	Os pontos de saque. Estes sao MARCADORES: e o LootService que cria os sacos
	em cima deles. Assim o mapa nao precisa de saber o que e um saco.

	As montras ficam encostadas as paredes laterais e o cofre ao fundo, longe da
	entrada -- o saco grande obriga a atravessar a loja inteira devagar, que e a
	tensao que o documento quer no caminho barulhento.
]]
local function construirSaque(pai: Instance)
	local loot = criarPasta("Loot", pai)

	local montras = Config.mapa.montras
	local espacamento = LOJA.profundidade / (math.ceil(montras / 2) + 1)

	for indice = 1, montras do
		-- Alterna entre a parede esquerda e a direita.
		local ladoEsquerdo = indice % 2 == 1
		local posicaoNaFila = math.ceil(indice / 2)

		criarParte({
			nome = "Montra" .. indice,
			tamanho = Vector3.new(6, 4, 3),
			posicao = Vector3.new(
				if ladoEsquerdo then -(LOJA.largura / 2 - 5) else LOJA.largura / 2 - 5,
				2,
				LOJA.profundidade / 2 - posicaoNaFila * espacamento
			),
			cor = CORES.montra,
			pai = loot,
			transparencia = 0.4,
			material = Enum.Material.Glass,
		})
	end

	for indice = 1, Config.mapa.cofres do
		criarParte({
			-- Um unico cofre chama-se "Cofre"; vários passam a Cofre1, Cofre2...
			nome = if Config.mapa.cofres == 1 then "Cofre" else "Cofre" .. indice,
			tamanho = Vector3.new(8, 8, 4),
			-- Encostado a esquerda da parede de tras, nao ao centro: ao centro
			-- tapava o vao de saida para a carrinha.
			posicao = Vector3.new(-18 + (indice - 1) * 12, 4, -(LOJA.profundidade / 2 - 4)),
			cor = CORES.cofre,
			pai = loot,
			material = Enum.Material.Metal,
		})
	end
end

-- A carrinha nas traseiras e a zona onde os sacos sao entregues.
local function construirFuga(pai: Instance)
	local escape = criarPasta("EscapeZone", pai)

	criarParte({
		nome = "Carrinha",
		tamanho = Vector3.new(10, 8, 18),
		posicao = Vector3.new(0, 4, ESCAPE_Z - 4),
		cor = CORES.carrinha,
		pai = escape,
		material = Enum.Material.Metal,
	})

	--[[
		A zona de entrega. Nao colide, para se poder entrar nela a correr com um
		saco. O LootService usa a posicao e o tamanho desta parte para saber se
		uma entrega e valida -- e revalida no servidor, nunca confiando no
		cliente.
	]]
	criarParte({
		nome = "Zona",
		tamanho = Vector3.new(16, 8, 12),
		posicao = Vector3.new(0, 4, ESCAPE_Z + 7),
		cor = CORES.zonaFuga,
		pai = escape,
		transparencia = 0.6,
		colide = false,
		material = Enum.Material.Neon,
	})
end

--[[
	Rotas dos guardas. Nao fazem nada ainda: ficam prontas para o GuardService da
	Fase 1 ligar o PathfindingService entre elas.

	Sao invisiveis e nao colidem -- sao pontos de referencia, nao geometria.
]]
local function construirWaypoints(pai: Instance)
	local waypoints = criarPasta("Waypoints", pai)

	local posicoes = {
		Vector3.new(-20, 2, 14),
		Vector3.new(20, 2, 14),
		Vector3.new(20, 2, -14),
		Vector3.new(-20, 2, -14),
		Vector3.new(0, 2, 0),
		Vector3.new(0, 2, -14),
	}

	for indice, posicao in posicoes do
		criarParte({
			nome = "W" .. indice,
			tamanho = Vector3.new(2, 2, 2),
			posicao = posicao,
			cor = CORES.waypoint,
			pai = waypoints,
			transparencia = 1,
			colide = false,
		})
	end
end

local function construirLobby(pai: Instance)
	local lobby = criarPasta("Lobby", pai)

	criarParte({
		nome = "Chao",
		tamanho = Vector3.new(40, 1, 40),
		posicao = Vector3.new(0, -0.5, LOBBY_Z),
		cor = CORES.lobby,
		pai = lobby,
		material = Enum.Material.Concrete,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLobby"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 0.5, LOBBY_Z)
	spawn.Color = CORES.lobby
	spawn.Anchored = true
	spawn.Duration = 0 -- sem escudo de reaparecimento, que atrapalhava os testes
	spawn.Parent = lobby
end

function MapBuilder.init() end

--[[
	Constroi o mapa. Apaga primeiro o que ja existe, para poder ser chamado outra
	vez sem duplicar nada -- acontece a cada sincronizacao do Rojo durante o
	desenvolvimento.
]]
function MapBuilder.start()
	local aApagar =
		{ "Terreno", "Map", "Loot", "EscapeZone", "Waypoints", "Guards", "Cameras", "Lobby" }
	for _, nome in aApagar do
		local existente = workspace:FindFirstChild(nome)
		if existente then
			existente:Destroy()
		end
	end

	-- O terreno primeiro: e o chao em que tudo o resto assenta.
	construirTerreno(workspace)

	local map = criarPasta("Map", workspace)
	construirLoja(map)

	construirSaque(workspace)
	construirFuga(workspace)
	construirWaypoints(workspace)
	construirLobby(workspace)

	-- O GuardService povoa a pasta Guards a partir dos Waypoints, da mesma
	-- maneira que o LootService povoa os Sacos a partir dos marcadores de Loot.
	criarPasta("Guards", workspace)

	-- Vazia por agora; as cameras entram na Fase 1 e reutilizam o cone de visao
	-- do GuardaCore.
	criarPasta("Cameras", workspace)

	print("[MapBuilder] joalharia de teste construida")
end

return MapBuilder
