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
	validacao = validacao,
	-- Passamos funcoes em vez do servico inteiro, para a dependencia ser
	-- explicita e pequena: o AlarmService nao pode pagar dinheiro por engano.
	heist = {
		estadoAtual = HeistService.estadoAtual,
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
})

-- === Fase 2: start. O mapa primeiro, porque os outros procuram objetos nele. ===

MapBuilder.start()
DataService.start()
AlarmService.start()
LootService.start()
HeistService.start()

print("[Main] servidor pronto")
