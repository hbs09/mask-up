--!strict
--[[
	Maquina de estados do assalto (secção 4 do documento) -- ADAPTADOR.

	As regras estao todas no HeistCore, que e puro e tem 51 testes: que
	transicoes sao legais, quando se chama a fuga, quanto se paga. Este ficheiro
	faz so o que exige o Roblox:

	  - temporizadores com task.delay
	  - enviar HeistStateChanged e UpdateHUD
	  - pagar no fim, via DataService

	So o servidor muda o estado. O cliente recebe HeistStateChanged e desenha.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local HeistState = require(ReplicatedStorage.Shared.HeistState)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local HeistCore = require(ServerScriptService.Core.HeistCore)

local HeistService = {}

export type Deps = {
	dados: {
		adicionarDinheiro: (jogador: Player, quantia: number) -> number?,
		adicionarXp: (jogador: Player, quantia: number) -> number,
		registarAssalto: (jogador: Player, foiFurtivo: boolean) -> (),
		obterPerfil: (jogador: Player) -> { dinheiro: number }?,
	},
	saque: {
		reiniciar: () -> (),
	},
}

local deps: Deps
local core: HeistCore.Core

--[[
	Instante em que o temporizador do estado atual acaba, no relogio do servidor
	(workspace:GetServerTimeNow). Enviamos o INSTANTE e nao os segundos que
	faltam, para o cliente poder contar sozinho sem o servidor ter de enviar uma
	atualizacao por segundo.
]]
local fimDoTemporizador: number? = nil

--[[
	Cada temporizador tem um numero de geracao. Se o estado mudar antes do
	task.delay disparar, a geracao muda e o temporizador antigo nao faz nada.

	Sem isto: entregar os sacos minimos durante o Lobby faria o temporizador do
	Lobby disparar mais tarde e empurrar o assalto para Furtivo outra vez.
]]
local geracao = 0

local function agendar(segundos: number, acao: () -> ())
	geracao += 1
	local minhaGeracao = geracao
	fimDoTemporizador = workspace:GetServerTimeNow() + segundos

	task.delay(segundos, function()
		if minhaGeracao ~= geracao then
			return -- o estado mudou entretanto; este temporizador ja nao conta
		end
		acao()
	end)
end

-- O HUD e por jogador, porque o dinheiro vem do perfil de cada um.
local function enviarHUD(jogador: Player)
	local perfil = deps.dados.obterPerfil(jogador)

	Remotes.UpdateHUD:FireClient(jogador, {
		estado = core:estadoAtual(),
		sacosEntregues = core:totalSacosEntregues(),
		sacosMinimos = Config.minimoSacosParaFuga,
		fimDoTemporizador = fimDoTemporizador,
		dinheiro = if perfil then perfil.dinheiro else 0,
	})
end

local function enviarHUDaTodos()
	for _, jogador in Players:GetPlayers() do
		enviarHUD(jogador)
	end
end

--[[
	Paga a todos e registra as estatisticas.

	Cada jogador recebe o total, nao uma fatia -- a decisao esta explicada no
	HeistCore.calcularPagamento.
]]
local function pagar()
	local pagamento = core:calcularPagamento()
	local furtivo = core:foiFurtivo()

	print(
		string.format(
			"[HeistService] fim do assalto: %d sacos, %d bruto, %d por jogador, furtivo=%s",
			core:totalSacosEntregues(),
			pagamento.valorBruto,
			pagamento.dinheiroPorJogador,
			tostring(furtivo)
		)
	)

	for _, jogador in Players:GetPlayers() do
		deps.dados.adicionarDinheiro(jogador, pagamento.dinheiroPorJogador)
		deps.dados.adicionarXp(jogador, pagamento.xpPorJogador)
		deps.dados.registarAssalto(jogador, furtivo)
	end
end

--[[
	O que fazer ao ENTRAR em cada estado. E aqui que os temporizadores nascem.

	O Alarme nao aparece aqui de proposito: o relogio do assalto arrancou no
	Furtivo e continua a correr, porque disparar o alarme nao deve dar tempo
	extra a quem foi descoberto.
]]
local function aoEntrarEm(estado: string)
	if estado == HeistState.Lobby then
		--[[
			Arranca o assalto depois da espera do lobby. Na Fase 2 isto passa a
			depender de "todos prontos" em vez de so do tempo.

			Se o servidor estiver vazio quando o temporizador dispara, voltamos a
			esperar em vez de desistir -- senao o assalto nunca arrancava para
			quem entrasse depois, e o servidor ficava preso no Lobby.
		]]
		agendar(Config.tempos.lobby, function()
			if #Players:GetPlayers() > 0 then
				HeistService.comecarAssalto()
			else
				aoEntrarEm(HeistState.Lobby)
			end
		end)
	elseif estado == HeistState.Furtivo then
		-- Limite de tempo do assalto inteiro. Continua a contar durante o
		-- Alarme: disparar o alarme nao da tempo extra.
		agendar(Config.assalto.duracaoAlvoSegundos.maximo, function()
			core:transitar(HeistState.Fim)
		end)
	elseif estado == HeistState.Fuga then
		agendar(Config.tempos.fuga, function()
			core:transitar(HeistState.Fim)
		end)
	elseif estado == HeistState.Fim then
		pagar()
		agendar(Config.tempos.fim, function()
			HeistService.reiniciar()
		end)
	end
end

function HeistService.init(dependencias: Deps)
	deps = dependencias

	core = HeistCore.novo({
		config = {
			minimoSacosParaFuga = Config.minimoSacosParaFuga,
			sacos = Config.sacos,
			recompensas = Config.recompensas,
		},
		estados = HeistState,
		-- O core nao pode chamar `warn` (e um global do Roblox e isso quebrava a
		-- pureza dele), por isso passamos-lhe o nosso.
		avisar = function(mensagem)
			warn(mensagem)
		end,
	})
end

function HeistService.start()
	core:aoMudarEstado(function(novo, anterior)
		print(string.format("[HeistService] %s -> %s", anterior, novo))

		-- Enviado a todos, porque o estado e igual para a equipa inteira.
		Remotes.HeistStateChanged:FireAllClients(novo)

		aoEntrarEm(novo)
		enviarHUDaTodos()
	end)

	-- Quem entra a meio recebe logo o estado atual, senao ficava com um HUD vazio.
	Players.PlayerAdded:Connect(function(jogador)
		Remotes.HeistStateChanged:FireClient(jogador, core:estadoAtual())
		enviarHUD(jogador)
	end)

	-- Arranca o ciclo: entra no Lobby e deixa o temporizador fazer o resto.
	aoEntrarEm(HeistState.Lobby)
	enviarHUDaTodos()
end

function HeistService.estadoAtual(): string
	return core:estadoAtual()
end

-- Lobby -> Furtivo. Separado do temporizador para a Fase 2 poder chamar isto a
-- partir de "todos prontos".
function HeistService.comecarAssalto(): boolean
	local ok = core:transitar(HeistState.Furtivo)
	return ok
end

-- Chamado pelo AlarmService, a unica porta de entrada do alarme.
function HeistService.dispararAlarme(motivo: string): boolean
	return core:dispararAlarme(motivo)
end

-- Chamado pelo LootService quando um saco chega a carrinha.
function HeistService.registarSacoEntregue(jogador: Player, tipoSaco: string)
	local resultado = core:registarSacoEntregue(jogador.UserId, tipoSaco)

	if not resultado.aceite then
		warn(string.format("[HeistService] entrega recusada: %s", tostring(resultado.motivo)))
		return
	end

	-- Se chamou a fuga, o aoMudarEstado ja enviou o HUD; evitamos enviar duas vezes.
	if not resultado.chamouFuga then
		enviarHUDaTodos()
	end
end

--[[
	Fim -> Lobby, limpando tudo para o assalto seguinte.

	A transicao e que faz o trabalho de aviso: `core:transitar` dispara o
	ouvinte registado no start, que envia o HeistStateChanged e agenda o
	temporizador do Lobby. Fazer isso outra vez aqui mandava o Remote duas vezes
	e criava dois temporizadores.
]]
function HeistService.reiniciar()
	local ok = core:transitar(HeistState.Lobby)
	if not ok then
		-- Ja estamos no Lobby. Acontece se isto for chamado duas vezes; nao ha
		-- nada a limpar e cancelar o temporizador aqui deixaria o servidor preso.
		return
	end

	-- Depois da transicao, para as contagens ficarem a zero no HUD que se segue.
	core:reiniciar()
	deps.saque.reiniciar()
	enviarHUDaTodos()
end

return HeistService
