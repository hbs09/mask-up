--!strict
--[[
	Quem tem que saco, o limite por jogador e a velocidade de quem carrega
	(secção 5 do documento).

	Modulo PURO: trabalha com ids. Um `sacoId` e o nome do saco no mapa e um
	`jogadorId` e o UserId -- este modulo nunca ve uma Part nem um Humanoid.
	Quem cria os sacos, faz o WeldConstraint ao HumanoidRootPart e escreve o
	Humanoid.WalkSpeed e o LootService.

	Porque e que vale a pena ter isto testado: e aqui que vivem os bugs de
	duplicacao de dinheiro. Dois jogadores a apanhar o mesmo saco, ou entregar
	o mesmo saco duas vezes, sao erros que so se notam quando alguem ja os esta
	a explorar.
]]

local LootCore = {}
LootCore.__index = LootCore

export type Saco = { valor: number, velocidade: number }

export type Config = {
	velocidadeNormal: number,
	limiteSacosPorJogador: number,
	sacos: { [string]: Saco },
}

export type Motivo = "saco_desconhecido" | "ja_tem_portador" | "limite" | "nao_tem_este_saco"

type Campos = {
	config: Config,
	-- [sacoId] = tipo. Um saco entregue sai desta tabela e deixa de existir.
	tipoPorSaco: { [string]: string },
	-- [sacoId] = jogadorId, so para sacos que estao na mao de alguem.
	portadorPorSaco: { [string]: number },
}

export type Core = typeof(setmetatable({} :: Campos, LootCore))

function LootCore.novo(deps: { config: Config }): Core
	return setmetatable({
		config = deps.config,
		tipoPorSaco = {},
		portadorPorSaco = {},
	}, LootCore)
end

--[[
	Registar um saco que existe no mapa. Chamado pelo LootService depois de criar
	as Parts nos marcadores de Loot/.

	Recusa ids repetidos: dois sacos com o mesmo id seria a receita para
	duplicar dinheiro.
]]
function LootCore.registarSaco(self: Core, sacoId: string, tipoSaco: string): boolean
	if self.tipoPorSaco[sacoId] ~= nil then
		return false
	end
	if self.config.sacos[tipoSaco] == nil then
		return false
	end

	self.tipoPorSaco[sacoId] = tipoSaco
	return true
end

-- nil se o saco nao existe (nunca existiu, ou ja foi entregue).
function LootCore.tipoDoSaco(self: Core, sacoId: string): string?
	return self.tipoPorSaco[sacoId]
end

-- nil se esta no chao ou nao existe.
function LootCore.portadorDe(self: Core, sacoId: string): number?
	return self.portadorPorSaco[sacoId]
end

function LootCore.sacosDoJogador(self: Core, jogadorId: number): { string }
	local sacos = {}

	for sacoId, portador in self.portadorPorSaco do
		if portador == jogadorId then
			table.insert(sacos, sacoId)
		end
	end

	-- Ordenado para o resultado ser estavel: a iteracao de uma tabela em Luau
	-- nao tem ordem garantida, e testes a dependerem dela seriam intermitentes.
	table.sort(sacos)

	return sacos
end

function LootCore.apanhar(self: Core, jogadorId: number, sacoId: string): (boolean, Motivo?)
	if self.tipoPorSaco[sacoId] == nil then
		return false, "saco_desconhecido"
	end
	if self.portadorPorSaco[sacoId] ~= nil then
		-- Inclui o caso de ser o proprio jogador a tentar apanhar outra vez.
		return false, "ja_tem_portador"
	end
	if #self:sacosDoJogador(jogadorId) >= self.config.limiteSacosPorJogador then
		return false, "limite"
	end

	self.portadorPorSaco[sacoId] = jogadorId
	return true
end

function LootCore.largar(self: Core, jogadorId: number, sacoId: string): (boolean, Motivo?)
	if self.tipoPorSaco[sacoId] == nil then
		return false, "saco_desconhecido"
	end
	if self.portadorPorSaco[sacoId] ~= jogadorId then
		return false, "nao_tem_este_saco"
	end

	self.portadorPorSaco[sacoId] = nil
	return true
end

--[[
	Entregar na carrinha. Devolve tambem o tipo do saco, para o HeistService
	poder passar ao HeistCore e este somar o valor.

	O saco sai do mundo: se pudesse ser apanhado outra vez, dava para entregar
	o mesmo saco infinitas vezes.
]]
function LootCore.entregar(
	self: Core,
	jogadorId: number,
	sacoId: string
): (boolean, Motivo?, string?)
	local tipo = self.tipoPorSaco[sacoId]
	if tipo == nil then
		return false, "saco_desconhecido", nil
	end
	if self.portadorPorSaco[sacoId] ~= jogadorId then
		return false, "nao_tem_este_saco", nil
	end

	self.portadorPorSaco[sacoId] = nil
	self.tipoPorSaco[sacoId] = nil

	return true, nil, tipo
end

--[[
	O WalkSpeed que o jogador deve ter agora.

	Com mais do que um saco manda o mais pesado, que e a regra intuitiva: se
	carregas o cofre, nao andas mais depressa por tambem levares uma montra.
]]
function LootCore.velocidadeDe(self: Core, jogadorId: number): number
	local velocidade = self.config.velocidadeNormal

	for _, sacoId in self:sacosDoJogador(jogadorId) do
		local tipo = self.tipoPorSaco[sacoId]
		local saco = if tipo then self.config.sacos[tipo] else nil

		if saco and saco.velocidade < velocidade then
			velocidade = saco.velocidade
		end
	end

	return velocidade
end

--[[
	Jogador saiu do jogo. Devolve os ids dos sacos que ele tinha, para o
	LootService os largar no mapa.

	Os sacos continuam a existir de proposito: o saque nao pode desaparecer
	porque alguem se desligou, senao o assalto podia ficar impossivel de
	terminar por falta de sacos para atingir o minimo da fuga.
]]
function LootCore.esquecerJogador(self: Core, jogadorId: number): { string }
	local largados = self:sacosDoJogador(jogadorId)

	for _, sacoId in largados do
		self.portadorPorSaco[sacoId] = nil
	end

	return largados
end

-- Preparar o assalto seguinte: o mapa vai registar os sacos outra vez.
function LootCore.reiniciar(self: Core)
	self.tipoPorSaco = {}
	self.portadorPorSaco = {}
end

return LootCore
