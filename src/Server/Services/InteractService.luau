--!strict
--[[
	O Remote RequestInteract (secçao 6 do documento) -- ADAPTADOR.

	Um registo de nome de objeto -> funcao. Cada servico diz "trato do
	PainelSeguranca" e este ficheiro faz a validacao antes de o chamar, sempre
	igual, sempre pelo ValidacaoCore.

	PORQUE E QUE EXISTE SEPARADO

	Isto esteve escondido no AlarmService, quando o unico objeto interagivel era
	o BotaoAlarmeTeste. Quando o botao saiu, ficou anotado que o RequestInteract
	voltaria num servico proprio em vez de ficar na barriga de outro -- caso
	contrario o minijogo do cabo punha um segundo handler no mesmo Remote, e dois
	servicos a ouvir o mesmo evento e a decidir cada um se a mensagem e para si e
	uma forma garantida de duplicar validacoes e deixar de as ter todas iguais.

	Com o registo, ha um unico `OnServerEvent` e uma unica validacao.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ValidacaoCore = require(ServerScriptService.Core.ValidacaoCore)

local InteractService = {}

export type Deps = {
	validacao: ValidacaoCore.Validador,
	heist: {
		estadoAtual: () -> string,
	},
}

export type Handler = {
	-- Estados do assalto em que este objeto responde.
	estados: { string },
	aoInteragir: (jogador: Player, objeto: BasePart) -> (),
}

local deps: Deps
local handlers: { [string]: Handler } = {}

--[[
	Registar quem trata de um objeto, pelo NOME da Part.

	Pelo nome e nao pela instancia porque os objetos sao criados pelos servicos
	depois do arranque, e porque um mapa feito a mao na Fase 2 vai trazer as
	suas proprias Parts com os mesmos nomes.
]]
function InteractService.registar(nomeDoObjeto: string, handler: Handler)
	if handlers[nomeDoObjeto] then
		warn(string.format("[InteractService] %s ja tinha handler; substituido", nomeDoObjeto))
	end

	handlers[nomeDoObjeto] = handler
end

local function aoPedirInteragir(jogador: Player, objeto: unknown)
	-- O que chega do cliente pode ser qualquer coisa.
	if typeof(objeto) ~= "Instance" then
		return
	end

	local instancia = objeto :: Instance
	if not instancia:IsA("BasePart") then
		return
	end

	local parte = instancia :: BasePart
	local handler = handlers[parte.Name]
	if not handler then
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
		estadosPermitidos = handler.estados,
		-- O cooldown e por acao, por isso o nome do objeto entra na chave: mexer
		-- no painel nao deve travar a leitura do esquema.
		acao = "RequestInteract:" .. parte.Name,
		agora = os.clock(),
	})

	if not ok then
		-- So para o Output do servidor. Nao dizemos o motivo ao cliente: nao lhe
		-- interessa, e dizer-lhe ensinava-o a afinar tentativas.
		print(
			string.format(
				"[InteractService] %s recusado a %s: %s",
				parte.Name,
				jogador.Name,
				tostring(motivo)
			)
		)
		return
	end

	handler.aoInteragir(jogador, parte)
end

function InteractService.init(dependencias: Deps)
	deps = dependencias
end

function InteractService.start()
	Remotes.RequestInteract.OnServerEvent:Connect(aoPedirInteragir)
end

return InteractService
