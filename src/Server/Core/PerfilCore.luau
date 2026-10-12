--!strict
--[[
	O perfil guardado por jogador (secção 7 do documento) e as contas que mexem
	nele: dinheiro, xp/niveis, estatisticas, mascaras e migracao de versao.

	Modulo PURO: nao sabe o que e um DataStore nem um Player. O DataService (a
	Fase 3 do plano) e que vai buscar os bytes e guarda-los; aqui so decidimos o
	que e um perfil valido e como ele evolui.

	A regra que justifica metade deste ficheiro: tudo o que vem do armazenamento
	e suspeito. Um perfil pode ter sido guardado por uma versao antiga do jogo,
	pode vir incompleto de uma escrita interrompida, ou pode ter sido editado.
	Por isso `migrar` reconstroi o perfil campo a campo a partir de um perfil
	novo, aceitando do antigo so o que tem o tipo certo.
]]

local PerfilCore = {}
PerfilCore.__index = PerfilCore

-- Subir isto quando a forma do perfil mudar de maneira incompativel.
local VERSAO_ATUAL = 1

export type Estatisticas = { assaltos: number, furtivos: number }

export type Perfil = {
	versao: number,
	dinheiro: number,
	xp: number,
	nivel: number,
	kitsEmergencia: number,
	armas: { string },
	mascaras: { string },
	mascaraEquipada: string,
	desafios: { diario: { [string]: any }, semanal: { [string]: any } },
	ultimaRecompensaDiaria: number,
	estatisticas: Estatisticas,
}

export type Config = {
	xpBase: number,
	nivelMaximo: number,
}

type Campos = {
	xpBase: number,
	nivelMaximo: number,
}

export type Core = typeof(setmetatable({} :: Campos, PerfilCore))

local function numeroFinito(valor: unknown): boolean
	return type(valor) == "number" and valor == valor and valor ~= math.huge and valor ~= -math.huge
end

-- Uma lista de texto, como `armas` e `mascaras`. Rejeita tabelas com buracos
-- ou com valores que nao sao texto.
local function listaDeTexto(valor: unknown): { string }?
	if type(valor) ~= "table" then
		return nil
	end

	local lista = valor :: { any }
	local resultado = {}

	for indice, item in ipairs(lista) do
		if type(item) ~= "string" then
			return nil
		end
		resultado[indice] = item
	end

	return resultado
end

local function copiaProfunda<T>(valor: T): T
	if type(valor) ~= "table" then
		return valor
	end

	local copia = {}
	for chave, item in valor :: any do
		copia[chave] = copiaProfunda(item)
	end

	return copia :: any
end

function PerfilCore.novo(config: Config): Core
	return setmetatable({
		xpBase = config.xpBase,
		nivelMaximo = config.nivelMaximo,
	}, PerfilCore)
end

--[[
	Um perfil de estreia. Devolve sempre tabelas NOVAS: se devolvessemos sempre
	a mesma tabela, a mascara comprada por um jogador aparecia a todos.
]]
function PerfilCore.perfilNovo(_self: Core): Perfil
	return {
		versao = VERSAO_ATUAL,
		dinheiro = 0,
		xp = 0,
		nivel = 1,
		kitsEmergencia = 0,
		armas = { "Pistola" },
		mascaras = { "Basica" },
		mascaraEquipada = "Basica",
		desafios = { diario = {}, semanal = {} },
		ultimaRecompensaDiaria = 0,
		estatisticas = { assaltos = 0, furtivos = 0 },
	}
end

--[[
	Nivel correspondente a uma quantidade de xp.

	Custo do nivel n para n+1 = xpBase * n, logo o xp acumulado para chegar ao
	nivel L e xpBase * (L-1) * L / 2. Com xpBase = 100: nivel 2 aos 100, nivel 3
	aos 300, nivel 4 aos 600, nivel 5 aos 1000.
]]
function PerfilCore.nivelPara(self: Core, xp: number): number
	if not numeroFinito(xp) or xp < 0 then
		return 1
	end

	local nivel = 1
	while nivel < self.nivelMaximo do
		local necessarioParaProximo = self.xpBase * nivel * (nivel + 1) / 2
		if xp < necessarioParaProximo then
			break
		end
		nivel += 1
	end

	return nivel
end

-- Devolve o dinheiro depois da operacao. Nunca fica negativo nem fracionado.
function PerfilCore.adicionarDinheiro(_self: Core, perfil: Perfil, quantia: number): number
	if not numeroFinito(quantia) then
		return perfil.dinheiro
	end

	perfil.dinheiro = math.max(0, math.floor(perfil.dinheiro + quantia))
	return perfil.dinheiro
end

-- Devolve quantos niveis subiu, para o ecra final poder festejar.
function PerfilCore.adicionarXp(self: Core, perfil: Perfil, quantia: number): number
	if not numeroFinito(quantia) or quantia <= 0 then
		return 0
	end

	local nivelAntes = perfil.nivel

	perfil.xp = math.floor(perfil.xp + quantia)
	perfil.nivel = self:nivelPara(perfil.xp)

	return perfil.nivel - nivelAntes
end

function PerfilCore.registarAssalto(_self: Core, perfil: Perfil, foiFurtivo: boolean)
	perfil.estatisticas.assaltos += 1

	if foiFurtivo then
		perfil.estatisticas.furtivos += 1
	end
end

-- Devolve true se desbloqueou agora, false se ja a tinha.
function PerfilCore.desbloquearMascara(_self: Core, perfil: Perfil, mascara: string): boolean
	if table.find(perfil.mascaras, mascara) then
		return false
	end

	table.insert(perfil.mascaras, mascara)
	return true
end

-- Devolve false se o jogador nao tem a mascara (pedido de um cliente a mentir).
function PerfilCore.equiparMascara(_self: Core, perfil: Perfil, mascara: string): boolean
	if not table.find(perfil.mascaras, mascara) then
		return false
	end

	perfil.mascaraEquipada = mascara
	return true
end

--[[
	Converte o que veio do armazenamento num perfil valido da versao atual.

	Comeca de um perfil novo e aceita do guardado so os campos com o tipo certo.
	Qualquer coisa inesperada (texto onde devia estar numero, campo em falta,
	perfil corrompido, nil) cai no valor por omissao em vez de rebentar mais
	tarde no meio de um assalto.
]]
function PerfilCore.migrar(self: Core, guardado: any): Perfil
	local perfil = self:perfilNovo()

	if type(guardado) ~= "table" then
		return perfil
	end

	if numeroFinito(guardado.dinheiro) then
		perfil.dinheiro = math.max(0, math.floor(guardado.dinheiro))
	end
	if numeroFinito(guardado.xp) and guardado.xp >= 0 then
		perfil.xp = math.floor(guardado.xp)
	end
	if numeroFinito(guardado.kitsEmergencia) and guardado.kitsEmergencia >= 0 then
		perfil.kitsEmergencia = math.floor(guardado.kitsEmergencia)
	end
	if numeroFinito(guardado.ultimaRecompensaDiaria) and guardado.ultimaRecompensaDiaria >= 0 then
		perfil.ultimaRecompensaDiaria = math.floor(guardado.ultimaRecompensaDiaria)
	end

	local armas = listaDeTexto(guardado.armas)
	if armas and #armas > 0 then
		perfil.armas = armas
	end

	local mascaras = listaDeTexto(guardado.mascaras)
	if mascaras and #mascaras > 0 then
		perfil.mascaras = mascaras
	end

	-- So aceitamos a mascara equipada se ela estiver na lista das que tem.
	if
		type(guardado.mascaraEquipada) == "string"
		and table.find(perfil.mascaras, guardado.mascaraEquipada)
	then
		perfil.mascaraEquipada = guardado.mascaraEquipada
	end

	if type(guardado.desafios) == "table" then
		if type(guardado.desafios.diario) == "table" then
			perfil.desafios.diario = copiaProfunda(guardado.desafios.diario)
		end
		if type(guardado.desafios.semanal) == "table" then
			perfil.desafios.semanal = copiaProfunda(guardado.desafios.semanal)
		end
	end

	if type(guardado.estatisticas) == "table" then
		if numeroFinito(guardado.estatisticas.assaltos) and guardado.estatisticas.assaltos >= 0 then
			perfil.estatisticas.assaltos = math.floor(guardado.estatisticas.assaltos)
		end
		if numeroFinito(guardado.estatisticas.furtivos) and guardado.estatisticas.furtivos >= 0 then
			perfil.estatisticas.furtivos = math.floor(guardado.estatisticas.furtivos)
		end
	end

	-- O nivel e sempre recalculado a partir do xp, nunca lido do guardado: se um
	-- bug antigo ou uma edicao manual gravou um nivel errado, isto corrige-o.
	perfil.nivel = self:nivelPara(perfil.xp)
	perfil.versao = VERSAO_ATUAL

	return perfil
end

PerfilCore.VERSAO_ATUAL = VERSAO_ATUAL

return PerfilCore
