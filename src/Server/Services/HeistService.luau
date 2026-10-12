--!strict
--[[
	Maquina de estados do assalto (secção 4 do documento) -- ADAPTADOR.

	ESTADO: esqueleto. O contrato abaixo ja esta fixado porque o Main e o
	AlarmService dependem dele, mas a logica ainda nao existe. Vai viver em
	src/Server/Core/HeistCore.luau, com testes, e este ficheiro passa a ser so a
	ponte: ouvir o core e enviar HeistStateChanged aos clientes.

	Divisao de responsabilidades quando estiver feito:
	  HeistCore (puro, testado)   tabela de transicoes legais, contagem de sacos
	                              entregues, quando se vai para Fuga, calculo do
	                              pagamento com bonus furtivo
	  HeistService (este)         temporizadores com task.delay, disparar o
	                              Remote, pagar via DataService

	Regra que isto protege: so o servidor muda o estado. O cliente recebe
	HeistStateChanged e desenha; nunca decide.
]]

local HeistState = require(game:GetService("ReplicatedStorage").Shared.HeistState)

local HeistService = {}

local estado: string = HeistState.Lobby

function HeistService.init() end

function HeistService.start() end

function HeistService.estadoAtual(): string
	return estado
end

-- Chamado pelo AlarmService, a unica porta de entrada do alarme.
function HeistService.dispararAlarme(_motivo: string)
	-- TODO: delegar no HeistCore e enviar HeistStateChanged.
end

-- Chamado pelo LootService quando um saco chega a carrinha.
function HeistService.registarSacoEntregue(_jogador: Player, _tipoSaco: string)
	-- TODO: delegar no HeistCore; ele decide quando se vai para Fuga.
end

return HeistService
