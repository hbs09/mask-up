--!strict
--[[
	Minijogo do cabo (secçao 5 do documento) -- ADAPTADOR.

	> O servidor escolhe o fio certo e guarda-o; o cliente so envia o fio
	> escolhido; erro = alarme, ou usar kit de emergencia

	Toda a decisao esta no CaboCore, que e puro e tem 25 testes: qual o fio
	certo, uma tentativa so, e -- o que mais importa -- que a resposta nunca sai
	de la. Este ficheiro cria as duas Parts, ouve os Remotes e liga o resultado
	as cameras e ao alarme.

	A PISTA NAO ESTA NO MAPA

	O esquema e uma Part SEM texto. Escrever "corta o azul" numa propriedade
	replicada -- um BillboardGui, um StringValue, o Name -- deixava qualquer
	cliente ler a resposta sem ninguem ir la, e o esconderijo nao valia nada.
	O texto so e enviado, por Remote, a quem interagiu de facto com a Part e
	passou a validacao de distancia.

	O kit de emergencia (segunda tentativa) fica para a Fase 5, com o resto da
	monetizacao. O Remote UseEmergencyKit ja esta declarado e sem handler.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local HeistState = require(ReplicatedStorage.Shared.HeistState)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CaboCore = require(ServerScriptService.Core.CaboCore)

local WireMinigame = {}

export type Deps = {
	interagir: {
		registar: (nomeDoObjeto: string, handler: any) -> (),
	},
	cameras: {
		desligar: () -> (),
		estaoLigadas: () -> boolean,
	},
	alarme: {
		Trigger: (motivo: string) -> boolean,
	},
}

local NOME_PAINEL = "PainelSeguranca"
local NOME_ESQUEMA = "Esquema"

-- O painel so responde em Furtivo: depois do alarme as cameras ja nao sao o
-- problema, e deixar o minijogo aberto seria confundir o jogador.
local ESTADOS_DO_PAINEL = { HeistState.Furtivo }

local CORES_DA_PARTE = {
	painelLigado = Color3.fromRGB(200, 170, 60),
	painelResolvido = Color3.fromRGB(80, 220, 110),
	painelFalhado = Color3.fromRGB(150, 60, 60),
	esquema = Color3.fromRGB(235, 230, 215),
}

local deps: Deps
local core: CaboCore.Core
local painel: Part
local esquema: Part

local function criarPrompt(pai: Part, acao: string, objeto: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = acao
	prompt.ObjectText = objeto
	prompt.MaxActivationDistance = Config.interacao.distanciaMaxima
	prompt.HoldDuration = 0.4
	prompt.RequiresLineOfSight = false
	prompt.Parent = pai
	return prompt
end

local function criarPartes()
	local pasta = Instance.new("Folder")
	pasta.Name = "Seguranca"
	pasta.Parent = workspace

	-- Painel na parede direita, por dentro, visivel de longe: tem de ser obvio
	-- que existe, porque o jogo esta a dizer "ha aqui algo para resolver".
	painel = Instance.new("Part")
	painel.Name = NOME_PAINEL
	painel.Size = Vector3.new(1, 5, 4)
	painel.Position = Vector3.new(29 - 1, 4, -10)
	painel.Color = CORES_DA_PARTE.painelLigado
	painel.Material = Enum.Material.Metal
	painel.Anchored = true
	painel.TopSurface = Enum.SurfaceType.Smooth
	painel.BottomSurface = Enum.SurfaceType.Smooth
	painel.Parent = pasta
	criarPrompt(painel, "Abrir painel", "Seguranca")

	--[[
		Esquema atras do balcao, rente ao chao.

		Escondido mas nao injusto: o balcao esta no meio da loja e e o primeiro
		sitio onde se olha ao dar a volta. Com dois jogadores um procura enquanto
		o outro vigia, que e o cooperativo que o documento quer.
	]]
	esquema = Instance.new("Part")
	esquema.Name = NOME_ESQUEMA
	esquema.Size = Vector3.new(3, 0.2, 2)
	esquema.Position = Vector3.new(0, 0.2, 1.5)
	esquema.Color = CORES_DA_PARTE.esquema
	esquema.Material = Enum.Material.SmoothPlastic
	esquema.Anchored = true
	esquema.CanCollide = false
	esquema.Parent = pasta
	criarPrompt(esquema, "Ler esquema", "Papel")
end

local function aoLerEsquema(jogador: Player)
	local cor = core:pista()
	if not cor then
		return
	end

	-- A resposta viaja agora, e so para quem foi la.
	Remotes.EstadoDoCabo:FireClient(jogador, { tipo = "pista", cor = cor })
	print(string.format("[WireMinigame] %s leu o esquema", jogador.Name))
end

local function aoAbrirPainel(jogador: Player)
	if not deps.cameras.estaoLigadas() then
		return -- ja resolvido; nao ha nada a fazer
	end

	if not core:abrir(jogador.UserId) then
		return -- painel ja gasto
	end

	Remotes.EstadoDoCabo:FireClient(jogador, {
		tipo = "abrir",
		-- Ordem do Config, sem a resposta. Ver CaboCore.coresDoPuzzle.
		cores = core:coresDoPuzzle(),
	})
end

local function aoEscolherFio(jogador: Player, cor: unknown)
	--[[
		Sem validacao de distancia aqui de proposito: ela ja foi feita no
		InteractService para ABRIR o painel, e o CaboCore so aceita de quem o
		tem aberto. Um cliente a disparar WireChoice sem ter aberto leva
		"nao_aberto" e nao acontece nada.
	]]
	local acertou, motivo = core:escolher(jogador.UserId, cor)

	if
		not acertou and (motivo == "nao_aberto" or motivo == "cor_invalida" or motivo == "fechado")
	then
		print(string.format("[WireMinigame] %s recusado: %s", jogador.Name, tostring(motivo)))
		-- Uma cor invalida nao gasta a tentativa (ver CaboCore), por isso o
		-- painel continua aberto e nao mandamos "fechar".
		if motivo ~= "cor_invalida" then
			Remotes.EstadoDoCabo:FireClient(jogador, { tipo = "fechar", acertou = false })
		end
		return
	end

	Remotes.EstadoDoCabo:FireClient(jogador, { tipo = "fechar", acertou = acertou })

	if acertou then
		painel.Color = CORES_DA_PARTE.painelResolvido
		deps.cameras.desligar()
		print(string.format("[WireMinigame] %s cortou o fio certo", jogador.Name))
	else
		painel.Color = CORES_DA_PARTE.painelFalhado
		print(string.format("[WireMinigame] %s cortou o fio errado", jogador.Name))
		deps.alarme.Trigger("cabo_errado")
	end
end

function WireMinigame.init(dependencias: Deps)
	deps = dependencias

	core = CaboCore.novo({
		config = Config.cabo,
		-- O Random do Roblox fica aqui, no adaptador: o CaboCore recebe o
		-- aleatorio injetado para os testes nao serem uma moeda ao ar.
		aleatorio = function(quantas)
			return math.random(1, quantas)
		end,
	})
end

function WireMinigame.start()
	criarPartes()
	core:gerarPuzzle()

	deps.interagir.registar(NOME_PAINEL, {
		estados = ESTADOS_DO_PAINEL,
		aoInteragir = aoAbrirPainel,
	})

	-- O esquema le-se tambem em Alarme: se o alarme ja tocou, ler um papel nao
	-- faz mal a ninguem, e fechar isso seria uma frustracao sem razao.
	deps.interagir.registar(NOME_ESQUEMA, {
		estados = { HeistState.Furtivo, HeistState.Alarme },
		aoInteragir = aoLerEsquema,
	})

	Remotes.WireChoice.OnServerEvent:Connect(aoEscolherFio)

	print("[WireMinigame] painel e esquema prontos")
end

-- Chamado pelo HeistService no fim do assalto.
function WireMinigame.reiniciar()
	core:reiniciar()
	core:gerarPuzzle()

	if painel then
		painel.Color = CORES_DA_PARTE.painelLigado
	end
end

return WireMinigame
