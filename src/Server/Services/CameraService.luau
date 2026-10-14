--!strict
--[[
	Cameras de seguranca (secção 8 do documento) -- ADAPTADOR.

	> Cameras: 1 a 2 (desligam-se no painel de seguranca com o minijogo do cabo)

	REUTILIZA O GuardaCore INTEIRO. Uma camera e um guarda que nao anda: o cone
	em 3D, a barra de suspeicao e a regra de so disparar o alarme uma vez por
	travessia vem todos de la, com 45 testes. Este ficheiro so acrescenta o que
	e diferente -- varrer em vaivem em vez de patrulhar, e poder ser desligada.

	Instancia PROPRIA do GuardaCore, com Config.camaras: cone mais estreito e
	alcance maior que um guarda. E isso que distingue uma camera de uma pessoa,
	e e por isso que nao partilham o mesmo core -- a suspeicao de uma camera e
	independente da de um guarda, como deve ser.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local HeistState = require(ReplicatedStorage.Shared.HeistState)
local GuardaCore = require(ServerScriptService.Core.GuardaCore)

local CameraService = {}

export type Deps = {
	heist: {
		estadoAtual: () -> string,
	},
	alarme: {
		Trigger: (motivo: string) -> boolean,
	},
}

-- Mesmo ritmo do GuardService e do LootService.
local INTERVALO_VISAO = 0.2

-- Os mesmos estados que os guardas vigiam: ser visto a fugir tambem conta.
local ESTADOS_VIGIADOS = { HeistState.Furtivo, HeistState.Fuga }

local CORES = {
	corpo = Color3.fromRGB(55, 55, 60),
	ligada = Color3.fromRGB(230, 70, 70),
	desligada = Color3.fromRGB(80, 220, 110),
}

type Camera = {
	id: number,
	modelo: Model,
	lente: BasePart,
	luz: BasePart,
	arestasDoCone: { BasePart },
	-- Base do varrimento: o angulo central para onde a camera aponta.
	anguloBase: number,
	-- Desfasamento inicial, para as cameras nao varrerem em sincronia.
	faseInicial: number,
	direcao: Vector3,
}

local deps: Deps
local core: GuardaCore.Core
local camaras: { Camera } = {}
local pastaCamaras: Folder
local ligadas = true
local tempoDesdeUltimaVisao = 0
local decorridoTotal = 0

local parametrosRaycast = RaycastParams.new()

local function paraPosicao(v: Vector3)
	return { x = v.X, y = v.Y, z = v.Z }
end

local function raizDe(jogador: Player): BasePart?
	local personagem = jogador.Character
	if not personagem then
		return nil
	end
	return personagem:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function estaVivo(jogador: Player): boolean
	local personagem = jogador.Character
	local humanoide = personagem and personagem:FindFirstChildOfClass("Humanoid")
	return humanoide ~= nil and humanoide.Health > 0
end

-- === Construcao ===

--[[
	As duas arestas do cone, rasteiras ao chao, como nos guardas.

	Mesma razao: sem ver a fronteira, saber se estas dentro do campo de visao e
	adivinhar. Aqui sao ainda mais necessarias, porque uma camera no teto nao
	tem corpo que indique para onde olha.
]]
local function criarArestasDoCone(modelo: Model, posicao: Vector3): { BasePart }
	if not Config.guardas.mostrarCone then
		return {}
	end

	local arestas: { BasePart } = {}
	local meioAngulo = math.rad(Config.camaras.angulo / 2)
	local alcance = Config.camaras.distancia

	for _, lado in { -1, 1 } do
		local direcao = Vector3.new(math.sin(lado * meioAngulo), 0, -math.cos(meioAngulo))
		local centro = posicao + direcao * (alcance / 2)

		local aresta = Instance.new("Part")
		aresta.Name = if lado == -1 then "ArestaEsquerda" else "ArestaDireita"
		aresta.Size = Vector3.new(0.25, 0.1, alcance)
		aresta.CFrame = CFrame.lookAt(centro, centro + direcao)
		aresta.Color = CORES.ligada
		aresta.Material = Enum.Material.Neon
		aresta.Transparency = 0.6
		aresta.Anchored = true
		aresta.CanCollide = false
		-- Como nos guardas: sem isto as arestas apareciam nos raycasts.
		aresta.CanQuery = false
		aresta.CanTouch = false
		aresta.Parent = modelo

		table.insert(arestas, aresta)
	end

	return arestas
end

local function criarCamera(id: number, posicao: Vector3, anguloBase: number): Camera
	local modelo = Instance.new("Model")
	modelo.Name = "Camera" .. id

	local corpo = Instance.new("Part")
	corpo.Name = "Corpo"
	corpo.Size = Vector3.new(1.6, 1.2, 2.4)
	corpo.Color = CORES.corpo
	corpo.Material = Enum.Material.Metal
	corpo.Anchored = true
	corpo.CanCollide = false
	corpo.TopSurface = Enum.SurfaceType.Smooth
	corpo.BottomSurface = Enum.SurfaceType.Smooth
	corpo.Position = posicao
	corpo.Parent = modelo

	-- A lente e a origem dos raycasts, como a cabeca de um guarda. No -Z, que e
	-- a frente da CFrame -- o mesmo erro de sinal que me custou a viseira dos
	-- guardas nas costas.
	local lente = Instance.new("Part")
	lente.Name = "Lente"
	lente.Shape = Enum.PartType.Cylinder
	lente.Size = Vector3.new(0.5, 0.9, 0.9)
	lente.Color = Color3.fromRGB(25, 25, 30)
	lente.Material = Enum.Material.Glass
	lente.Anchored = true
	lente.CanCollide = false
	lente.CFrame = CFrame.new(posicao + Vector3.new(0, 0, -1.3)) * CFrame.Angles(0, 0, math.rad(90))
	lente.Parent = modelo

	-- Luz de estado: vermelha ligada, verde desligada. E o retorno que diz ao
	-- jogador que o minijogo do cabo funcionou.
	local luz = Instance.new("Part")
	luz.Name = "Luz"
	luz.Shape = Enum.PartType.Ball
	luz.Size = Vector3.new(0.4, 0.4, 0.4)
	luz.Color = CORES.ligada
	luz.Material = Enum.Material.Neon
	luz.Anchored = true
	luz.CanCollide = false
	luz.Position = posicao + Vector3.new(0, 0.7, -0.6)
	luz.Parent = modelo

	modelo.PrimaryPart = corpo
	modelo.Parent = pastaCamaras

	return {
		id = id,
		modelo = modelo,
		lente = lente,
		luz = luz,
		arestasDoCone = criarArestasDoCone(modelo, posicao),
		anguloBase = anguloBase,
		-- Meia volta de desfasamento entre cameras pares e impares, para nao
		-- varrerem em sincronia e deixarem sempre a mesma zona livre.
		faseInicial = if id % 2 == 0 then math.pi else 0,
		direcao = Vector3.new(0, 0, -1),
	}
end

-- === Varrimento ===

--[[
	Vaivem suave com um seno.

	Um seno e nao um ir-e-vir linear porque desacelera nas pontas: a camera
	demora-se mais nos extremos do arco, o que da janelas legiveis em vez de um
	movimento uniforme que obriga a cronometrar.
]]
local function varrer(camera: Camera)
	local arco = math.rad(Config.camaras.arcoDeVarrimento)
	local velocidade = math.rad(Config.camaras.velocidadeDeVarrimento)

	local fase = decorridoTotal * velocidade / (arco / 2) + camera.faseInicial
	local desvio = math.sin(fase) * (arco / 2)
	local angulo = camera.anguloBase + desvio

	camera.direcao = Vector3.new(math.sin(angulo), 0, -math.cos(angulo))

	local pivot = camera.modelo:GetPivot().Position
	camera.modelo:PivotTo(CFrame.lookAt(pivot, pivot + camera.direcao))
end

-- === Visao ===

local function temLinhaDeVista(camera: Camera, jogador: Player, posAlvo: Vector3): boolean
	local personagem = jogador.Character
	if not personagem then
		return false
	end

	local origem = camera.lente.Position

	parametrosRaycast.FilterType = Enum.RaycastFilterType.Exclude
	parametrosRaycast.FilterDescendantsInstances = { pastaCamaras, personagem }
	parametrosRaycast.RespectCanCollide = true

	return workspace:Raycast(origem, posAlvo - origem, parametrosRaycast) == nil
end

local function atualizarVisao(dt: number)
	local aVigiar = ligadas and table.find(ESTADOS_VIGIADOS, deps.heist.estadoAtual()) ~= nil
	local jogadores = Players:GetPlayers()

	for _, camera in camaras do
		local posLente = paraPosicao(camera.lente.Position)
		local olharPara = paraPosicao(camera.direcao)

		for _, jogador in jogadores do
			local raiz = raizDe(jogador)
			local viu = false

			if aVigiar and raiz and estaVivo(jogador) then
				-- Cone primeiro, raycast depois: o mesmo cuidado do GuardService.
				if core:dentroDoCone(posLente, olharPara, paraPosicao(raiz.Position)) then
					viu = temLinhaDeVista(camera, jogador, raiz.Position)
				end
			end

			local _, acabouDeDetetar = core:atualizarSuspeita(camera.id, jogador.UserId, dt, viu)

			if acabouDeDetetar then
				print(string.format("[CameraService] Camera%d viu %s", camera.id, jogador.Name))
				deps.alarme.Trigger("camara_viu")
			end
		end

		local maior = 0
		for _, jogador in jogadores do
			local nivel = core:suspeitaDe(camera.id, jogador.UserId)
			if nivel > maior then
				maior = nivel
			end
		end

		if ligadas then
			local cor = Color3.fromRGB(230, math.floor(70 + 130 * (1 - maior)), 70)
			for _, aresta in camera.arestasDoCone do
				aresta.Color = cor
				aresta.Transparency = 0.6 - 0.35 * maior
			end
		end
	end
end

-- === Ciclo de vida ===

function CameraService.init(dependencias: Deps)
	deps = dependencias
	core = GuardaCore.novo({
		config = {
			angulo = Config.camaras.angulo,
			distancia = Config.camaras.distancia,
			segundosParaDetetar = Config.camaras.segundosParaDetetar,
			segundosParaEsquecer = Config.camaras.segundosParaEsquecer,
		},
	})
end

function CameraService.start()
	pastaCamaras = workspace:FindFirstChild("Cameras") :: Folder
	if not pastaCamaras then
		warn("[CameraService] Workspace/Cameras nao existe; o MapBuilder correu?")
		return
	end

	--[[
		Montagens nos cantos de tras da loja, a olhar para a entrada.

		Nos cantos e nao no meio das paredes: do canto o cone cobre a diagonal e
		cruza-se com o da outra camera no centro da loja, o que deixa os lados
		mais livres. Uma camera no meio de uma parede cobriria a parede oposta e
		nao havia rota nenhuma.
	]]
	local montagens = {
		{ posicao = Vector3.new(-26, 10, -16), angulo = math.rad(135) },
		{ posicao = Vector3.new(26, 10, -16), angulo = math.rad(-135) },
	}

	for id = 1, Config.camaras.quantidade do
		local m = montagens[((id - 1) % #montagens) + 1]
		table.insert(camaras, criarCamera(id, m.posicao, m.angulo))
	end

	RunService.Heartbeat:Connect(function(dt)
		decorridoTotal += dt

		for _, camera in camaras do
			varrer(camera)
		end

		tempoDesdeUltimaVisao += dt
		if tempoDesdeUltimaVisao < INTERVALO_VISAO then
			return
		end

		local decorrido = tempoDesdeUltimaVisao
		tempoDesdeUltimaVisao = 0
		atualizarVisao(decorrido)
	end)

	Players.PlayerRemoving:Connect(function(jogador)
		core:esquecerAlvo(jogador.UserId)
	end)

	print(string.format("[CameraService] %d cameras a varrer", #camaras))
end

--[[
	Desligar, chamado pelo WireMinigame quando o fio certo e cortado.

	As cameras ficam no mapa, apagadas: ver a luz verde e as arestas sumirem e o
	retorno que diz ao jogador que o minijogo funcionou. Apaga-las por completo
	seria mais barato e muito menos legivel.
]]
function CameraService.desligar()
	if not ligadas then
		return
	end
	ligadas = false

	-- A suspeicao acumulada tambem se apaga: uma camera desligada nao se lembra.
	core:reiniciar()

	for _, camera in camaras do
		camera.luz.Color = CORES.desligada

		for _, aresta in camera.arestasDoCone do
			aresta.Transparency = 1
		end
	end

	print("[CameraService] cameras desligadas")
end

function CameraService.estaoLigadas(): boolean
	return ligadas
end

-- Chamado pelo HeistService no fim do assalto.
function CameraService.reiniciar()
	ligadas = true
	core:reiniciar()

	for _, camera in camaras do
		camera.luz.Color = CORES.ligada

		for _, aresta in camera.arestasDoCone do
			aresta.Transparency = 0.6
			aresta.Color = CORES.ligada
		end
	end
end

return CameraService
