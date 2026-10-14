--!strict
--[[
	Arranca os servicos pela ordem certa (secção 3 do documento).

	Porque e que isto existe em vez de cada servico se arrancar sozinho: os
	servicos precisam uns dos outros -- o LootService avisa o HeistService quando
	um saco chega a carrinha, e o AlarmService muda o estado do assalto. Se cada
	um fizesse `require` do outro, tinhamos requires circulares, que em Luau
	falham de maneiras confusas.

	A solucao e injecao de dependencias em duas fases:
	  1. init(deps)  -- cada servico recebe referencias; ninguem corre logica
	  2. start()     -- agora que todos existem, ligar eventos e arrancar loops

	Assim nenhum servico faz `require` de outro servico, e a ordem de arranque
	fica visivel num unico ficheiro em vez de implicita nos imports.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local ValidacaoCore = require(ServerScriptService.Core.ValidacaoCore)

local Services = ServerScriptService.Services

local DataService = require(Services.DataService)
local MapBuilder = require(Services.MapBuilder)
local AlarmService = require(Services.AlarmService)
local LootService = require(Services.LootService)
local GuardService = require(Services.GuardService)
local CameraService = require(Services.CameraService)
local InteractService = require(Services.InteractService)
local WireMinigame = require(Services.WireMinigame)
local HeistService = require(Services.HeistService)

--[[
	UM validador para todo o servidor, partilhado por todos os servicos.

	E deliberado: o cooldown e por jogador E por acao, por isso um validador
	unico faz com que o spam de PickUpBag seja travado com a mesma contagem em
	qualquer sitio que o verifique. Um validador por servico daria a cada um o
	seu proprio cooldown, e um cliente podia alternar entre servicos para os
	contornar.
]]
local validacao = ValidacaoCore.novo(Config.interacao)

-- === Fase 1: init. Ninguem toca no Workspace nem liga eventos aqui. ===

DataService.init()
MapBuilder.init()

AlarmService.init({
	-- Passamos funcoes em vez do servico inteiro, para a dependencia ser
	-- explicita e pequena: o AlarmService nao pode pagar dinheiro por engano.
	heist = {
		dispararAlarme = HeistService.dispararAlarme,
	},
})

LootService.init({
	validacao = validacao,
	heist = {
		estadoAtual = HeistService.estadoAtual,
		registarSacoEntregue = HeistService.registarSacoEntregue,
	},
})

--[[
	O GuardService so precisa de saber o estado (para vigiar apenas em Furtivo) e
	de poder tocar o alarme. Nao conhece sacos, dinheiro nem o mapa.

	Passa pelo AlarmService e nao diretamente pelo HeistService, porque o alarme
	tem uma porta de entrada unica -- e agora e um guarda a usa-la, em vez do
	botao de teste.
]]
GuardService.init({
	heist = {
		estadoAtual = HeistService.estadoAtual,
	},
	alarme = {
		Trigger = AlarmService.Trigger,
	},
})

-- As cameras tem exactamente as mesmas dependencias que os guardas: saber o
-- estado e poder tocar o alarme. E o sinal de que a abstracao esta no sitio
-- certo -- uma camera e um guarda que nao anda.
CameraService.init({
	heist = {
		estadoAtual = HeistService.estadoAtual,
	},
	alarme = {
		Trigger = AlarmService.Trigger,
	},
})

--[[
	O RequestInteract passa a ter um servico proprio, com um registo de
	nome -> handler. Esteve escondido no AlarmService enquanto o unico objeto
	interagivel era o botao de teste; dois servicos a ouvir o mesmo Remote e a
	decidir cada um se a mensagem e para si duplicava validacoes.
]]
InteractService.init({
	validacao = validacao,
	heist = {
		estadoAtual = HeistService.estadoAtual,
	},
})

WireMinigame.init({
	interagir = {
		registar = InteractService.registar,
	},
	cameras = {
		desligar = CameraService.desligar,
		estaoLigadas = CameraService.estaoLigadas,
	},
	alarme = {
		Trigger = AlarmService.Trigger,
	},
})

HeistService.init({
	dados = {
		adicionarDinheiro = DataService.adicionarDinheiro,
		adicionarXp = DataService.adicionarXp,
		registarAssalto = DataService.registarAssalto,
		obterPerfil = DataService.obterPerfil,
	},
	saque = {
		reiniciar = LootService.reiniciar,
	},
	vigilancia = {
		reiniciar = function()
			GuardService.reiniciar()
			CameraService.reiniciar()
			-- Sorteia um fio novo: herdar a resposta tornava o assalto seguinte
			-- trivial para quem a tivesse decorado.
			WireMinigame.reiniciar()
		end,
	},
})

-- === Fase 2: start. O mapa primeiro, porque os outros procuram objetos nele. ===

MapBuilder.start()
DataService.start()
AlarmService.start()
LootService.start()
GuardService.start()
CameraService.start()
-- O InteractService antes do WireMinigame, que se registra nele.
InteractService.start()
WireMinigame.start()
HeistService.start()

print("[Main] servidor pronto")
