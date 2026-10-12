--!strict
--[[
	Sacos de dinheiro (secção 5 do documento) -- ADAPTADOR.

	Toda a decisao sobre sacos esta no LootCore, que e puro e tem 34 testes:
	quem tem que saco, o limite por jogador, que velocidade aplicar e se uma
	entrega e valida. Este ficheiro so faz a parte que exige o Roblox:

	  - criar as Parts dos sacos nos marcadores de Workspace/Loot
	  - anexar e largar com WeldConstraint
	  - escrever o Humanoid.WalkSpeed
	  - ouvir os Remotes PickUpBag e DropBag
	  - ver quem entrou na EscapeZone

	Nao ha aqui uma unica conta de distancia: as validacoes dos Remotes passam
	todas pelo ValidacaoCore, que tambem e puro e testado.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local HeistState = require(ReplicatedStorage.Shared.HeistState)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local LootCore = require(ServerScriptService.Core.LootCore)
local ValidacaoCore = require(ServerScriptService.Core.ValidacaoCore)

local LootService = {}

export type Deps = {
	validacao: ValidacaoCore.Validador,
	heist: {
		estadoAtual: () -> string,
		registarSacoEntregue: (jogador: Player, tipoSaco: string) -> (),
	},
}

-- Estados em que se pode mexer em sacos. Passado ao ValidacaoCore.
local ESTADOS_COM_SAQUE = { HeistState.Furtivo, HeistState.Alarme, HeistState.Fuga }

-- De quanto em quanto tempo verificamos quem esta na zona de entrega. Com 4
-- jogadores no maximo, 5 vezes por segundo e barato e imperceptivel.
local INTERVALO_ENTREGA = 0.2

local deps: Deps
local core: LootCore.Core
local pastaSacos: Folder
local tempoDesdeUltimaVerificacao = 0

-- O core trabalha com tabelas simples; converter de Vector3 e trabalho daqui.
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

local function humanoideDe(jogador: Player): Humanoid?
	local personagem = jogador.Character
	if not personagem then
		return nil
	end
	return personagem:FindFirstChildOfClass("Humanoid")
end

local function estaVivo(jogador: Player): boolean
	local humanoide = humanoideDe(jogador)
	return humanoide ~= nil and humanoide.Health > 0
end

-- Aplica no Humanoid a velocidade que o core decidiu.
local function aplicarVelocidade(jogador: Player)
	local humanoide = humanoideDe(jogador)
	if humanoide then
		humanoide.WalkSpeed = core:velocidadeDe(jogador.UserId)
	end
end

local function parteDoSaco(sacoId: string): Part?
	return pastaSacos:FindFirstChild(sacoId) :: Part?
end

--[[
	Pousa o saco no chao, livre para quem o quiser.

	Anchored = true de proposito: um saco solto com fisica rolava pela loja e
	podia ficar preso debaixo do balcao ou atravessar uma parede.
]]
local function pousarSaco(saco: Part, posicao: Vector3)
	for _, filho in saco:GetChildren() do
		if filho:IsA("WeldConstraint") then
			filho:Destroy()
		end
	end

	saco.Anchored = true
	saco.CanCollide = false
	saco.CFrame = CFrame.new(posicao)

	local prompt = saco:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = true
	end
end

--[[
	Cola o saco as costas do jogador.

	O WeldConstraint mantem a posicao RELATIVA que as partes tem no momento em
	que e criado, por isso a CFrame tem de ser acertada antes -- ao contrario, o
	saco ficava colado onde estava no chao.
]]
local function anexarSaco(saco: Part, jogador: Player): boolean
	local raiz = raizDe(jogador)
	if not raiz then
		return false
	end

	local prompt = saco:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		-- Sem isto, outro jogador podia abrir o prompt de um saco ja carregado.
		prompt.Enabled = false
	end

	saco.Anchored = false
	saco.CanCollide = false
	saco.CFrame = raiz.CFrame * CFrame.new(0, 0.6, 1.4)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = raiz
	weld.Part1 = saco
	weld.Parent = saco

	return true
end

-- Cria a Part de um saco em cima do marcador do mapa.
local function criarSaco(sacoId: string, tipoSaco: string, marcador: BasePart)
	local definicao = Config.sacos[tipoSaco]

	local saco = Instance.new("Part")
	saco.Name = sacoId
	saco.Size = if tipoSaco == "grande" then Vector3.new(3, 3, 2) else Vector3.new(2, 2, 1.5)
	saco.Color = if tipoSaco == "grande"
		then Color3.fromRGB(70, 140, 70)
		else Color3.fromRGB(110, 180, 110)
	saco.Material = Enum.Material.Fabric
	saco.Anchored = true
	saco.CanCollide = false
	saco.CFrame = CFrame.new(marcador.Position + Vector3.new(0, marcador.Size.Y / 2 + 1.5, 0))
	saco.Parent = pastaSacos

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Apanhar saco"
	prompt.ObjectText = string.format("Saco (%d)", definicao.valor)
	prompt.MaxActivationDistance = Config.interacao.distanciaMaxima
	prompt.HoldDuration = 0.3
	prompt.RequiresLineOfSight = false
	prompt.Parent = saco
end

--[[
	Le os marcadores de Workspace/Loot e cria um saco em cada um.

	O tipo vem do NOME do marcador: "Montra*" da saco pequeno, "Cofre*" da saco
	grande. E assim que o mapa feito a mao mais tarde continua a funcionar sem
	alterar codigo -- basta respeitar os nomes.
]]
local function povoarSaque()
	local loot = workspace:FindFirstChild("Loot")
	if not loot then
		warn("[LootService] Workspace/Loot nao existe; o MapBuilder correu?")
		return
	end

	for _, marcador in loot:GetChildren() do
		if not marcador:IsA("BasePart") then
			continue
		end

		local tipoSaco = if string.find(marcador.Name, "Cofre", 1, true)
			then "grande"
			else "pequeno"
		local sacoId = "Saco_" .. marcador.Name

		if core:registarSaco(sacoId, tipoSaco) then
			criarSaco(sacoId, tipoSaco, marcador)
		else
			warn(
				string.format(
					"[LootService] nao registei %s (id repetido ou tipo invalido)",
					sacoId
				)
			)
		end
	end
end

-- Validacao comum a PickUpBag e DropBag. O `objeto` e a Part do saco.
local function podeMexerNoSaco(jogador: Player, saco: Part, acao: string): boolean
	local raiz = raizDe(jogador)
	if not raiz then
		return false
	end

	local ok, motivo = deps.validacao:podeInteragir({
		jogadorId = jogador.UserId,
		vivo = estaVivo(jogador),
		posicaoJogador = paraPosicao(raiz.Position),
		posicaoObjeto = paraPosicao(saco.Position),
		estadoAtual = deps.heist.estadoAtual(),
		estadosPermitidos = ESTADOS_COM_SAQUE,
		acao = acao,
		agora = os.clock(),
	})

	if not ok then
		-- So para o Output do servidor. Nao avisamos o cliente do motivo: nao lhe
		-- interessa, e dizer-lhe ensinava-o a afinar tentativas.
		print(
			string.format(
				"[LootService] %s recusado a %s: %s",
				acao,
				jogador.Name,
				tostring(motivo)
			)
		)
	end

	return ok
end

local function aoPedirApanhar(jogador: Player, sacoId: unknown)
	if type(sacoId) ~= "string" then
		return
	end

	local saco = parteDoSaco(sacoId)
	if not saco then
		return
	end
	if not podeMexerNoSaco(jogador, saco, "PickUpBag") then
		return
	end

	local ok, motivo = core:apanhar(jogador.UserId, sacoId)
	if not ok then
		print(
			string.format(
				"[LootService] %s nao apanhou %s: %s",
				jogador.Name,
				sacoId,
				tostring(motivo)
			)
		)
		return
	end

	if not anexarSaco(saco, jogador) then
		-- O personagem desapareceu entre a validacao e agora: desfazer para o
		-- saco nao ficar preso a ninguem.
		core:largar(jogador.UserId, sacoId)
		return
	end

	aplicarVelocidade(jogador)
end

local function aoPedirLargar(jogador: Player, sacoId: unknown)
	if type(sacoId) ~= "string" then
		return
	end

	local saco = parteDoSaco(sacoId)
	if not saco then
		return
	end
	if not podeMexerNoSaco(jogador, saco, "DropBag") then
		return
	end

	if not core:largar(jogador.UserId, sacoId) then
		return
	end

	local raiz = raizDe(jogador)
	pousarSaco(saco, if raiz then raiz.Position + Vector3.new(0, -1, 0) else saco.Position)
	aplicarVelocidade(jogador)
end

--[[
	Entrega: verifica quem esta dentro da zona da carrinha.

	E o SERVIDOR a decidir, por isso nao ha nada a revalidar -- a posicao e lida
	daqui, nao enviada pelo cliente. Mudar o WalkSpeed localmente nao ajuda:
	continua a ser preciso estar fisicamente na zona.
]]
local function verificarEntregas()
	local escape = workspace:FindFirstChild("EscapeZone")
	local zona = escape and escape:FindFirstChild("Zona") :: BasePart?
	if not zona then
		return
	end

	for _, jogador in Players:GetPlayers() do
		local raiz = raizDe(jogador)
		if not raiz then
			continue
		end

		-- Dentro da caixa da zona, eixo a eixo. Mais previsivel do que confiar
		-- em eventos Touched de uma parte sem colisao.
		local relativo = zona.CFrame:PointToObjectSpace(raiz.Position)
		local metade = zona.Size / 2

		local dentro = math.abs(relativo.X) <= metade.X
			and math.abs(relativo.Y) <= metade.Y
			and math.abs(relativo.Z) <= metade.Z

		if not dentro then
			continue
		end

		for _, sacoId in core:sacosDoJogador(jogador.UserId) do
			local ok, _, tipoSaco = core:entregar(jogador.UserId, sacoId)
			if ok and tipoSaco then
				local saco = parteDoSaco(sacoId)
				if saco then
					saco:Destroy()
				end

				deps.heist.registarSacoEntregue(jogador, tipoSaco)
			end
		end

		aplicarVelocidade(jogador)
	end
end

function LootService.init(dependencias: Deps)
	deps = dependencias
	core = LootCore.novo({
		config = {
			velocidadeNormal = Config.velocidadeNormal,
			limiteSacosPorJogador = Config.limiteSacosPorJogador,
			sacos = Config.sacos,
		},
	})
end

function LootService.start()
	pastaSacos = Instance.new("Folder")
	pastaSacos.Name = "Sacos"
	pastaSacos.Parent = workspace

	povoarSaque()

	Remotes.PickUpBag.OnServerEvent:Connect(aoPedirApanhar)
	Remotes.DropBag.OnServerEvent:Connect(aoPedirLargar)

	RunService.Heartbeat:Connect(function(delta)
		tempoDesdeUltimaVerificacao += delta
		if tempoDesdeUltimaVerificacao < INTERVALO_ENTREGA then
			return
		end
		tempoDesdeUltimaVerificacao = 0

		verificarEntregas()
	end)

	--[[
		Jogador sai: os sacos dele voltam para o chao em vez de desaparecerem.
		Se o saque desaparecesse com quem se desliga, o assalto podia ficar
		impossivel de terminar por falta de sacos para atingir o minimo da fuga.
	]]
	Players.PlayerRemoving:Connect(function(jogador)
		local raiz = raizDe(jogador)
		local ondeCaiu = if raiz then raiz.Position else Vector3.new(0, 3, 0)

		for _, sacoId in core:esquecerJogador(jogador.UserId) do
			local saco = parteDoSaco(sacoId)
			if saco then
				pousarSaco(saco, ondeCaiu)
			end
		end
	end)

	-- Ao reaparecer, o WalkSpeed volta ao valor por omissao do Roblox; se o
	-- jogador ainda tiver um saco registado, reaplicamos o peso.
	Players.PlayerAdded:Connect(function(jogador)
		jogador.CharacterAdded:Connect(function()
			aplicarVelocidade(jogador)
		end)
	end)
end

-- Chamado pelo HeistService no fim do assalto: limpa o mapa e volta a povoar.
function LootService.reiniciar()
	core:reiniciar()
	pastaSacos:ClearAllChildren()
	povoarSaque()

	for _, jogador in Players:GetPlayers() do
		aplicarVelocidade(jogador)
	end
end

return LootService
