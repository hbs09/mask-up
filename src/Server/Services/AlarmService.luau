--!strict
--[[
	A unica porta de entrada para disparar o alarme (secção 5 do documento).

	Guardas, cameras, cabos cortados a direito e civis a fugir NAO mudam o estado
	do assalto por si: chamam `AlarmService.Trigger(motivo)`. Assim ha um unico
	sitio para registar o motivo e, mais tarde, tocar a sirene e acender as
	luzes -- em vez de essa decisao andar espalhada por cinco servicos.

	A regra "ignora se ja esta em Alarme" nao esta aqui: vive no HeistCore, que
	tem testes para ela. Este ficheiro nao a repete, porque duas copias da mesma
	regra acabam sempre por discordar uma da outra.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local HeistState = require(ReplicatedStorage.Shared.HeistState)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ValidacaoCore = require(ServerScriptService.Core.ValidacaoCore)

local AlarmService = {}

export type Deps = {
	validacao: ValidacaoCore.Validador,
	heist: {
		estadoAtual: () -> string,
		dispararAlarme: (motivo: string) -> boolean,
	},
}

-- Nome da Part de teste que o MapBuilder cria. Sai na Fase 1, com os guardas.
local BOTAO_TESTE = "BotaoAlarmeTeste"

local deps: Deps

function AlarmService.init(dependencias: Deps)
	deps = dependencias
end

--[[
	Trata o Remote RequestInteract (secção 6 do documento).

	Por agora o unico objeto interagivel e o botao de alarme de teste, por isso
	vive aqui. Quando houver painel de seguranca, cofre e portas, isto passa para
	um InteractService proprio -- a validacao e que nao muda, porque ja esta
	toda no ValidacaoCore.
]]
local function aoPedirInteragir(jogador: Player, objeto: unknown)
	if typeof(objeto) ~= "Instance" then
		return
	end

	local parte = objeto :: Instance
	if not parte:IsA("BasePart") or parte.Name ~= BOTAO_TESTE then
		return
	end

	local personagem = jogador.Character
	local raiz = personagem and personagem:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoide = personagem and personagem:FindFirstChildOfClass("Humanoid")
	if not raiz then
		return
	end

	local ok, motivo = deps.validacao:podeInteragir({
		jogadorId = jogador.UserId,
		vivo = humanoide ~= nil and humanoide.Health > 0,
		posicaoJogador = { x = raiz.Position.X, y = raiz.Position.Y, z = raiz.Position.Z },
		posicaoObjeto = { x = parte.Position.X, y = parte.Position.Y, z = parte.Position.Z },
		estadoAtual = deps.heist.estadoAtual(),
		estadosPermitidos = { HeistState.Furtivo },
		acao = "RequestInteract",
		agora = os.clock(),
	})

	if not ok then
		print(
			string.format(
				"[AlarmService] interacao recusada a %s: %s",
				jogador.Name,
				tostring(motivo)
			)
		)
		return
	end

	AlarmService.Trigger("botao_teste")
end

function AlarmService.start()
	Remotes.RequestInteract.OnServerEvent:Connect(aoPedirInteragir)
end

--[[
	Dispara o alarme.

	`motivo` entra nos logs do servidor para se perceber o que correu mal num
	assalto: "guarda_viu", "camara_viu", "cabo_errado", "civil_fugiu",
	"botao_teste".

	Devolve true se foi este chamador que disparou o alarme, e false se nao
	houve nada a fazer -- porque ja estava a tocar, ou porque o assalto nao esta
	em Furtivo. Tres guardas a verem o mesmo jogador dao um alarme, nao tres.
]]
function AlarmService.Trigger(motivo: string): boolean
	local disparou = deps.heist.dispararAlarme(motivo)

	if disparou then
		print(string.format("[AlarmService] ALARME: %s", motivo))
	end

	return disparou
end

return AlarmService
