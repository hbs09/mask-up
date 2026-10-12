--!strict
--[[
	Responde as quatro perguntas da regra de ouro nº2 do documento, uma unica vez
	para todo o projeto: o jogador esta vivo? Esta perto do objeto? O assalto esta
	no estado certo? Ja fez isto ha pouco?

	Este modulo e PURO: nao conhece `game`, `Instance`, `Vector3` nem `os.time`.
	Recebe posicoes como { x, y, z } e o instante atual no proprio pedido. E o
	adaptador (Services/) que traduz do mundo do Roblox para este formato. E por
	isso que isto corre em milissegundos no terminal, sem abrir o Studio.

	Nenhum handler de Remote deve fazer as suas proprias contas de distancia:
	se aparecer um `.Magnitude <` solto num servico, e um bug.
]]

local ValidacaoCore = {}
ValidacaoCore.__index = ValidacaoCore

export type Posicao = { x: number, y: number, z: number }

-- Corresponde a Config.interacao, para o adaptador poder fazer
-- `ValidacaoCore.novo(Config.interacao)` sem traduzir nomes de campos.
export type Config = {
	distanciaMaxima: number,
	cooldown: number,
}

-- O motivo e um codigo estavel (nao uma frase), para os testes e os logs do
-- servidor nao dependerem de texto que se pode querer reescrever.
export type Motivo = "invalido" | "morto" | "estado" | "longe" | "cooldown"

type Campos = {
	distanciaMaxima: number,
	cooldown: number,
	-- [jogadorId][acao] = instante em que a acao foi aceite pela ultima vez
	ultimaAcao: { [number]: { [string]: number } },
}

export type Validador = typeof(setmetatable({} :: Campos, ValidacaoCore))

-- Rejeita nil, texto, NaN e infinito. O NaN importa: comparacoes com NaN sao
-- sempre falsas, por isso um `distancia > maxima` deixaria passar NaN.
local function numeroValido(valor: unknown): boolean
	return type(valor) == "number" and valor == valor and valor ~= math.huge and valor ~= -math.huge
end

local function posicaoValida(posicao: unknown): boolean
	if type(posicao) ~= "table" then
		return false
	end

	local p = posicao :: Posicao
	return numeroValido(p.x) and numeroValido(p.y) and numeroValido(p.z)
end

function ValidacaoCore.novo(config: Config): Validador
	return setmetatable({
		distanciaMaxima = config.distanciaMaxima,
		cooldown = config.cooldown,
		ultimaAcao = {},
	}, ValidacaoCore)
end

--[[
	Devolve (true) se a interacao pode acontecer, ou (false, motivo) se nao.

	A ordem das verificacoes e deliberada e esta fixada nos testes: primeiro o
	que indica um cliente a mentir (invalido), depois as regras de jogo. Assim o
	motivo registado nos logs e sempre o mais informativo.

	Uma acao recusada NAO arranca o cooldown -- senao um jogador a falhar
	interacoes legitimas (ex.: a andar para o saco) ficaria bloqueado.
]]
function ValidacaoCore.podeInteragir(self: Validador, pedido: any): (boolean, Motivo?)
	-- 0. O pedido vem do cliente, por isso pode ser qualquer coisa.
	if type(pedido) ~= "table" then
		return false, "invalido"
	end
	if type(pedido.jogadorId) ~= "number" or type(pedido.acao) ~= "string" then
		return false, "invalido"
	end
	if not numeroValido(pedido.agora) then
		return false, "invalido"
	end
	if not posicaoValida(pedido.posicaoJogador) or not posicaoValida(pedido.posicaoObjeto) then
		return false, "invalido"
	end
	if type(pedido.estadosPermitidos) ~= "table" then
		return false, "invalido"
	end

	-- 1. Esta vivo?
	if not pedido.vivo then
		return false, "morto"
	end

	-- 2. O assalto esta no estado certo?
	local estadoPermitido = false
	for _, estado in pedido.estadosPermitidos do
		if estado == pedido.estadoAtual then
			estadoPermitido = true
			break
		end
	end
	if not estadoPermitido then
		return false, "estado"
	end

	-- 3. Esta perto do objeto? Comparamos quadrados para nao chamar sqrt e para
	-- a fronteira exata (distancia == maxima) nao sofrer erro de arredondamento.
	local dx = pedido.posicaoJogador.x - pedido.posicaoObjeto.x
	local dy = pedido.posicaoJogador.y - pedido.posicaoObjeto.y
	local dz = pedido.posicaoJogador.z - pedido.posicaoObjeto.z

	local distanciaQuadrada = dx * dx + dy * dy + dz * dz
	local maximaQuadrada = self.distanciaMaxima * self.distanciaMaxima

	if distanciaQuadrada > maximaQuadrada then
		return false, "longe"
	end

	-- 4. Ja fez isto ha pouco? O cooldown e por jogador e por acao.
	local acoes = self.ultimaAcao[pedido.jogadorId]
	if acoes == nil then
		acoes = {}
		self.ultimaAcao[pedido.jogadorId] = acoes
	end

	local ultimoInstante = acoes[pedido.acao]
	if ultimoInstante ~= nil and pedido.agora - ultimoInstante < self.cooldown then
		return false, "cooldown"
	end

	acoes[pedido.acao] = pedido.agora

	return true
end

-- Chamar quando um jogador sai, para a tabela de cooldowns nao crescer sem fim.
function ValidacaoCore.esquecerJogador(self: Validador, jogadorId: number)
	self.ultimaAcao[jogadorId] = nil
end

return ValidacaoCore
