--!strict
--[[
	A unica porta de entrada para disparar o alarme (secção 5 do documento).

	Guardas, camaras, cabos cortados a direito e civis a fugir NAO mudam o estado
	do assalto por si: chamam `AlarmService.Trigger(motivo)`. Assim ha um unico
	sitio para registar o motivo, tocar a sirene e decidir o que acontece, em vez
	de essa decisao andar espalhada por cinco servicos.

	Se ja estamos em Alarme, ignora em silencio -- exatamente como o documento
	especifica. Isso evita que tres guardas a verem o mesmo jogador disparem o
	alarme tres vezes.
]]

local AlarmService = {}

type Deps = {
	heist: {
		estadoAtual: () -> string,
		dispararAlarme: (motivo: string) -> (),
	},
}

local deps: Deps

function AlarmService.init(dependencias: Deps)
	deps = dependencias
end

function AlarmService.start() end

--[[
	Dispara o alarme. `motivo` entra nos logs do servidor para se perceber o que
	correu mal num assalto ("guarda_viu", "camara_viu", "cabo_errado",
	"civil_fugiu", "botao_teste").

	Devolve true se foi este chamador que disparou o alarme, false se ja estava
	a tocar.
]]
function AlarmService.Trigger(motivo: string): boolean
	if deps.heist.estadoAtual() ~= "Furtivo" then
		-- Ja em Alarme, ou o assalto ainda nao comecou / ja acabou.
		return false
	end

	print(string.format("[AlarmService] alarme disparado: %s", motivo))
	deps.heist.dispararAlarme(motivo)

	return true
end

return AlarmService
