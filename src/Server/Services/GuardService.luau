--!strict
--[[
	Guardas que patrulham e que veem (secção 5 do documento) -- ADAPTADOR.

	A matematica da visao esta toda no GuardaCore, que e puro e tem 45 testes:
	cone de angulo e distancia em 3D, barra de suspeicao, e a regra de so
	disparar o alarme uma vez por travessia. Este ficheiro faz o que exige o
	Roblox: criar os guardas, move-los, lancar os raycasts e desenhar a barra.

	SOBRE A PATRULHA

	O documento pede PathfindingService. Usamos-lo para CALCULAR a rota, mas
	movemos o guarda por interpolacao da CFrame em vez de `Humanoid:MoveTo`.

	Porque: o MoveTo exige um rig de personagem a funcionar (Humanoid +
	HumanoidRootPart + membros), que e fragil de montar a mao e dificil de
	depurar quando nao anda. Interpolar e deterministico, nao depende de fisica,
	e da-nos a direcao do olhar de graca (e a direcao do movimento). Mantemos o
	beneficio real do PathfindingService, que e contornar obstaculos.

	Se na Fase 2 os guardas precisarem de animacoes, troca-se isto por rigs a
	serio -- e o GuardaCore nao muda, porque so recebe posicoes.
]]

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local HeistState = require(ReplicatedStorage.Shared.HeistState)
local GuardaCore = require(ServerScriptService.Core.GuardaCore)

local GuardService = {}

export type Deps = {
	heist: {
		estadoAtual: () -> string,
	},
	alarme: {
		Trigger: (motivo: string) -> boolean,
	},
}

-- Mesmo ritmo do LootService: 5 vezes por segundo e barato e imperceptivel.
local INTERVALO_VISAO = 0.2

-- Altura dos olhos acima do centro do corpo, origem dos raycasts.
local ALTURA_CABECA = 3

type Guarda = {
	id: number,
	modelo: Model,
	cabeca: BasePart,
	barraSuspeita: Frame,
	indiceWaypoint: number,
	-- Rota devolvida pelo PathfindingService para o waypoint atual.
	rota: { Vector3 },
	passoDaRota: number,
	direcao: Vector3,
	esperarAte: number,
	-- Evita pedir duas rotas ao mesmo tempo (o ComputeAsync cede o controlo).
	aCalcularRota: boolean,
}

local deps: Deps
local core: GuardaCore.Core
local guardas: { Guarda } = {}
local pastaGuardas: Folder
local waypoints: { BasePart } = {}
local tempoDesdeUltimaVisao = 0

-- Parametros do raycast, reutilizados: criar um RaycastParams por verificacao
-- seriam centenas de tabelas por segundo.
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

local function criarBarraDeSuspeita(cabeca: BasePart): Frame
	--[[
		Indicador acima da cabeca, criado no SERVIDOR para replicar sozinho sem
		precisar de um Remote novo.

		Acima do guarda e nao no HUD de proposito: assim o jogador ve QUAL guarda
		o esta a notar, que e a informacao que lhe permite decidir para onde ir.
	]]
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Suspeita"
	billboard.Size = UDim2.new(0, 60, 0, 8)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = Config.visao.distancia * 1.5
	billboard.Parent = cabeca

	local fundo = Instance.new("Frame")
	fundo.Size = UDim2.fromScale(1, 1)
	fundo.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	fundo.BackgroundTransparency = 0.35
	fundo.BorderSizePixel = 0
	fundo.Parent = billboard

	local barra = Instance.new("Frame")
	barra.Name = "Nivel"
	barra.Size = UDim2.fromScale(0, 1)
	barra.BackgroundColor3 = Color3.fromRGB(240, 200, 60)
	barra.BorderSizePixel = 0
	barra.Parent = fundo

	return barra
end

local function criarGuarda(id: number, posicao: Vector3): Guarda
	local modelo = Instance.new("Model")
	modelo.Name = "Guarda" .. id

	local corpo = Instance.new("Part")
	corpo.Name = "Corpo"
	corpo.Size = Vector3.new(2, 4, 1.5)
	corpo.Color = Color3.fromRGB(45, 55, 75)
	corpo.Material = Enum.Material.Fabric
	corpo.Anchored = true
	corpo.TopSurface = Enum.SurfaceType.Smooth
	corpo.BottomSurface = Enum.SurfaceType.Smooth
	corpo.Position = posicao + Vector3.new(0, 2, 0)
	corpo.Parent = modelo

	local cabeca = Instance.new("Part")
	cabeca.Name = "Cabeca"
	cabeca.Size = Vector3.new(1.4, 1.4, 1.4)
	cabeca.Color = Color3.fromRGB(215, 180, 150)
	cabeca.Material = Enum.Material.SmoothPlastic
	cabeca.Anchored = true
	cabeca.TopSurface = Enum.SurfaceType.Smooth
	cabeca.BottomSurface = Enum.SurfaceType.Smooth
	cabeca.Position = posicao + Vector3.new(0, ALTURA_CABECA, 0)
	cabeca.Parent = modelo

	--[[
		Viseira na frente da cabeca.

		Nao e decoracao: sem ela nao se percebe para onde o guarda esta a olhar,
		e um jogo furtivo em que nao se le a direcao do olhar e um jogo de
		adivinhar.
	]]
	local viseira = Instance.new("Part")
	viseira.Name = "Viseira"
	viseira.Size = Vector3.new(1.2, 0.4, 0.2)
	viseira.Color = Color3.fromRGB(240, 240, 240)
	viseira.Material = Enum.Material.Neon
	viseira.Anchored = true
	viseira.CanCollide = false
	viseira.Position = posicao + Vector3.new(0, ALTURA_CABECA, 0.8)
	viseira.Parent = modelo

	modelo.PrimaryPart = corpo
	modelo.Parent = pastaGuardas

	return {
		id = id,
		modelo = modelo,
		cabeca = cabeca,
		barraSuspeita = criarBarraDeSuspeita(cabeca),
		indiceWaypoint = ((id - 1) % math.max(#waypoints, 1)) + 1,
		rota = {},
		passoDaRota = 1,
		direcao = Vector3.new(0, 0, 1),
		esperarAte = 0,
		aCalcularRota = false,
	}
end

-- === Patrulha ===

--[[
	Pede ao PathfindingService uma rota ate ao waypoint atual do guarda.

	Corre em task.spawn porque o ComputeAsync cede o controlo, e nao queremos
	travar o Heartbeat de todos os guardas por causa de um.
]]
local function calcularRota(guarda: Guarda)
	if guarda.aCalcularRota or #waypoints == 0 then
		return
	end
	guarda.aCalcularRota = true

	task.spawn(function()
		local destino = waypoints[guarda.indiceWaypoint]
		local origem = guarda.modelo:GetPivot().Position

		local caminho = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = false,
		})

		local ok = pcall(function()
			caminho:ComputeAsync(origem, destino.Position)
		end)

		local pontos: { Vector3 } = {}
		if ok and caminho.Status == Enum.PathStatus.Success then
			for _, passo in caminho:GetWaypoints() do
				table.insert(pontos, passo.Position)
			end
		else
			-- Sem rota: vai a direito. No mapa de teste os waypoints tem linha
			-- de vista entre si, por isso isto e suficiente; no mapa real da
			-- Fase 2 o pathfinding e que manda.
			table.insert(pontos, destino.Position)
		end

		guarda.rota = pontos
		guarda.passoDaRota = 1
		guarda.aCalcularRota = false
	end)
end

local function avancarParaProximoWaypoint(guarda: Guarda)
	guarda.indiceWaypoint = (guarda.indiceWaypoint % #waypoints) + 1
	guarda.esperarAte = os.clock() + Config.guardas.pausaNoWaypoint
	guarda.rota = {}
end

local function moverGuarda(guarda: Guarda, dt: number)
	if os.clock() < guarda.esperarAte then
		return -- em pausa num waypoint
	end

	if #guarda.rota == 0 then
		calcularRota(guarda)
		return
	end

	local pivot = guarda.modelo:GetPivot()
	local posicaoAtual = pivot.Position
	local alvo = guarda.rota[guarda.passoDaRota]

	if not alvo then
		avancarParaProximoWaypoint(guarda)
		return
	end

	-- Comparamos so no plano: a altura do pivot do guarda nao coincide com a do
	-- waypoint, e exigir coincidencia em Y fazia-o nunca "chegar".
	local paraAlvo = Vector3.new(alvo.X - posicaoAtual.X, 0, alvo.Z - posicaoAtual.Z)

	if paraAlvo.Magnitude < 1.5 then
		guarda.passoDaRota += 1
		if guarda.passoDaRota > #guarda.rota then
			avancarParaProximoWaypoint(guarda)
		end
		return
	end

	local direcao = paraAlvo.Unit
	local passo = math.min(Config.guardas.velocidade * dt, paraAlvo.Magnitude)
	local novaPosicao = posicaoAtual + direcao * passo

	guarda.direcao = direcao
	guarda.modelo:PivotTo(CFrame.lookAt(novaPosicao, novaPosicao + direcao))
end

-- === Visao ===

--[[
	Ha linha de vista livre entre a cabeca do guarda e o jogador?

	Excluimos os guardas (senao um guarda tapava o outro) e o personagem do
	proprio alvo (senao o raio batia nele e nunca "chegava"). Se depois disso o
	raio nao bate em nada, e porque nao ha parede pelo meio.

	RespectCanCollide para as partes decorativas sem colisao -- os sacos, a zona
	de entrega, os marcadores de waypoint -- nao servirem de esconderijo.
]]
local function temLinhaDeVista(guarda: Guarda, jogador: Player, posAlvo: Vector3): boolean
	local personagem = jogador.Character
	if not personagem then
		return false
	end

	local origem = guarda.cabeca.Position
	local paraAlvo = posAlvo - origem

	parametrosRaycast.FilterType = Enum.RaycastFilterType.Exclude
	parametrosRaycast.FilterDescendantsInstances = { pastaGuardas, personagem }
	parametrosRaycast.RespectCanCollide = true

	local resultado = workspace:Raycast(origem, paraAlvo, parametrosRaycast)

	return resultado == nil
end

--[[
	Estados em que os guardas vigiam.

	A Fuga esta incluida de proposito: ser visto a caminho da carrinha tem de
	contar, senao a parte mais tensa do assalto -- carregar o saque devagar com
	os guardas ainda de pe -- passava a ser uma caminhada sem risco. O
	HeistCore trata disso sem rebobinar o estado: marca o alarme, tira o bonus
	furtivo, e deixa o temporizador da fuga a correr.

	Fora destes dois nao ha nada a descobrir: no Lobby e no Fim o assalto nao
	esta a decorrer, e no Alarme o alarme ja toca.
]]
local ESTADOS_VIGIADOS = { HeistState.Furtivo, HeistState.Fuga }

local function atualizarVisao(dt: number)
	local aVigiar = table.find(ESTADOS_VIGIADOS, deps.heist.estadoAtual()) ~= nil
	local jogadores = Players:GetPlayers()

	for _, guarda in guardas do
		local posCabeca = paraPosicao(guarda.cabeca.Position)
		local olharPara = paraPosicao(guarda.direcao)

		for _, jogador in jogadores do
			local raiz = raizDe(jogador)
			local viu = false

			if aVigiar and raiz and estaVivo(jogador) then
				-- Cone primeiro: e barato. O raycast so para quem ja esta dentro.
				if core:dentroDoCone(posCabeca, olharPara, paraPosicao(raiz.Position)) then
					viu = temLinhaDeVista(guarda, jogador, raiz.Position)
				end
			end

			local _, acabouDeDetetar = core:atualizarSuspeita(guarda.id, jogador.UserId, dt, viu)

			if acabouDeDetetar then
				print(string.format("[GuardService] Guarda%d viu %s", guarda.id, jogador.Name))
				deps.alarme.Trigger("guarda_viu")
			end
		end

		-- A barra mostra o pior caso entre todos os jogadores que este guarda ve.
		local maior = 0
		for _, jogador in jogadores do
			local nivel = core:suspeitaDe(guarda.id, jogador.UserId)
			if nivel > maior then
				maior = nivel
			end
		end

		guarda.barraSuspeita.Size = UDim2.fromScale(maior, 1)
		-- Amarelo a vermelho conforme sobe, para se ler sem olhar para o tamanho.
		guarda.barraSuspeita.BackgroundColor3 =
			Color3.fromRGB(240, math.floor(200 - 140 * maior), 60)
	end
end

-- === Ciclo de vida ===

function GuardService.init(dependencias: Deps)
	deps = dependencias
	core = GuardaCore.novo({ config = Config.visao })
end

function GuardService.start()
	pastaGuardas = workspace:FindFirstChild("Guards") :: Folder
	if not pastaGuardas then
		warn("[GuardService] Workspace/Guards nao existe; o MapBuilder correu?")
		return
	end

	local pastaWaypoints = workspace:FindFirstChild("Waypoints")
	if not pastaWaypoints then
		warn("[GuardService] Workspace/Waypoints nao existe")
		return
	end

	for _, parte in pastaWaypoints:GetChildren() do
		if parte:IsA("BasePart") then
			table.insert(waypoints, parte)
		end
	end
	-- Ordenado por nome para a ronda ser W1 -> W2 -> ... e nao aleatoria.
	table.sort(waypoints, function(a, b)
		return a.Name < b.Name
	end)

	-- Cada guarda comeca num waypoint diferente, espalhados pela ronda.
	for id = 1, Config.guardas.quantidade do
		local inicio = waypoints[((id - 1) % #waypoints) + 1]
		table.insert(guardas, criarGuarda(id, inicio.Position))
	end

	RunService.Heartbeat:Connect(function(dt)
		for _, guarda in guardas do
			moverGuarda(guarda, dt)
		end

		tempoDesdeUltimaVisao += dt
		if tempoDesdeUltimaVisao < INTERVALO_VISAO then
			return
		end

		local decorrido = tempoDesdeUltimaVisao
		tempoDesdeUltimaVisao = 0
		atualizarVisao(decorrido)
	end)

	-- Jogador sai: limpar a suspeicao dele, para as tabelas do core nao
	-- crescerem sem fim num servidor que fica horas a correr.
	Players.PlayerRemoving:Connect(function(jogador)
		core:esquecerAlvo(jogador.UserId)
	end)

	print(string.format("[GuardService] %d guardas em ronda", #guardas))
end

-- Chamado pelo HeistService no fim do assalto.
function GuardService.reiniciar()
	core:reiniciar()

	for _, guarda in guardas do
		guarda.barraSuspeita.Size = UDim2.fromScale(0, 1)
	end
end

return GuardService
