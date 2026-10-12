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

local AlarmService = {}

export type Deps = {
	heist: {
		dispararAlarme: (motivo: string) -> boolean,
	},
}

local deps: Deps

function AlarmService.init(dependencias: Deps)
	deps = dependencias
end

--[[
	Nao ha nada para ligar no arranque.

	Ate agora este servico tratava o Remote RequestInteract, por causa de um
	BotaoAlarmeTeste que existia como muleta para exercitar o caminho do alarme
	antes de haver guardas. Com o GuardService, o alarme passou a ser disparado
	por quem devia, e o botao saiu.

	O RequestInteract volta na Fase 1, com o painel de seguranca das cameras, e
	ai pertence a um InteractService proprio -- generico, em vez de escondido
	aqui.
]]
function AlarmService.start() end

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
