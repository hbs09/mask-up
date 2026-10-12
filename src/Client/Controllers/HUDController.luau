--!strict
--[[
	HUD: estado do assalto, temporizador, sacos entregues e dinheiro.

	Construido por codigo em vez de ficheiros de interface, para nao haver uma
	arvore de GuiObjects a manter em paralelo com o Rojo.

	Ouve dois Remotes e mais nada:
	  HeistStateChanged  -- muda o texto do estado
	  UpdateHUD          -- dinheiro, sacos entregues / minimo, fim do temporizador

	Nao calcula nada sobre o jogo. A unica conta que faz e transformar o INSTANTE
	em que o temporizador acaba (que vem do servidor) nos segundos que faltam --
	e isso e so para nao ser preciso o servidor enviar uma atualizacao por
	segundo a cada jogador.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HeistState = require(ReplicatedStorage.Shared.HeistState)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local HUDController = {}

-- Uma cor por estado, para se perceber o que esta a acontecer sem ler o texto.
local CORES_ESTADO: { [string]: Color3 } = {
	[HeistState.Lobby] = Color3.fromRGB(140, 150, 170),
	[HeistState.Furtivo] = Color3.fromRGB(90, 200, 140),
	[HeistState.Alarme] = Color3.fromRGB(235, 90, 80),
	[HeistState.Fuga] = Color3.fromRGB(245, 185, 70),
	[HeistState.Fim] = Color3.fromRGB(170, 140, 230),
}

-- Texto mais humano que o nome do estado.
local LEGENDAS: { [string]: string } = {
	[HeistState.Lobby] = "A espera da equipa",
	[HeistState.Furtivo] = "Furtivo - nao sejas visto",
	[HeistState.Alarme] = "ALARME - a policia vem a caminho",
	[HeistState.Fuga] = "FUGA - corre para a carrinha",
	[HeistState.Fim] = "Fim do assalto",
}

local rotuloEstado: TextLabel
local rotuloLegenda: TextLabel
local rotuloTemporizador: TextLabel
local rotuloSacos: TextLabel
local rotuloDinheiro: TextLabel

local fimDoTemporizador: number? = nil

local function criarRotulo(props: {
	nome: string,
	pai: Instance,
	posicao: UDim2,
	tamanho: UDim2,
	tamanhoTexto: number,
	alinhamento: Enum.TextXAlignment,
	negrito: boolean?,
}): TextLabel
	local rotulo = Instance.new("TextLabel")

	rotulo.Name = props.nome
	rotulo.Position = props.posicao
	rotulo.Size = props.tamanho
	rotulo.BackgroundTransparency = 1
	rotulo.Font = if props.negrito then Enum.Font.GothamBold else Enum.Font.Gotham
	rotulo.TextSize = props.tamanhoTexto
	rotulo.TextColor3 = Color3.fromRGB(255, 255, 255)
	rotulo.TextXAlignment = props.alinhamento
	rotulo.Text = ""

	-- Contorno escuro, para o texto se ler sobre fundos claros do mapa.
	rotulo.TextStrokeTransparency = 0.4
	rotulo.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)

	rotulo.Parent = props.pai

	return rotulo
end

local function construirInterface()
	local jogador = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false -- senao o HUD desaparecia a cada morte
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = jogador:WaitForChild("PlayerGui")

	-- Painel do estado, em cima ao centro.
	local painelEstado = Instance.new("Frame")
	painelEstado.Name = "Estado"
	painelEstado.AnchorPoint = Vector2.new(0.5, 0)
	painelEstado.Position = UDim2.new(0.5, 0, 0, 12)
	painelEstado.Size = UDim2.new(0, 420, 0, 72)
	painelEstado.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	painelEstado.BackgroundTransparency = 0.25
	painelEstado.BorderSizePixel = 0
	painelEstado.Parent = gui

	local cantos = Instance.new("UICorner")
	cantos.CornerRadius = UDim.new(0, 8)
	cantos.Parent = painelEstado

	rotuloEstado = criarRotulo({
		nome = "Nome",
		pai = painelEstado,
		posicao = UDim2.new(0, 0, 0, 6),
		tamanho = UDim2.new(1, 0, 0, 28),
		tamanhoTexto = 24,
		alinhamento = Enum.TextXAlignment.Center,
		negrito = true,
	})

	rotuloLegenda = criarRotulo({
		nome = "Legenda",
		pai = painelEstado,
		posicao = UDim2.new(0, 0, 0, 34),
		tamanho = UDim2.new(1, 0, 0, 18),
		tamanhoTexto = 14,
		alinhamento = Enum.TextXAlignment.Center,
	})

	rotuloTemporizador = criarRotulo({
		nome = "Temporizador",
		pai = painelEstado,
		posicao = UDim2.new(0, 0, 0, 50),
		tamanho = UDim2.new(1, 0, 0, 20),
		tamanhoTexto = 16,
		alinhamento = Enum.TextXAlignment.Center,
		negrito = true,
	})

	-- Sacos e dinheiro, em baixo a esquerda.
	local painelEquipa = Instance.new("Frame")
	painelEquipa.Name = "Equipa"
	painelEquipa.AnchorPoint = Vector2.new(0, 1)
	painelEquipa.Position = UDim2.new(0, 16, 1, -16)
	painelEquipa.Size = UDim2.new(0, 260, 0, 64)
	painelEquipa.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	painelEquipa.BackgroundTransparency = 0.25
	painelEquipa.BorderSizePixel = 0
	painelEquipa.Parent = gui

	local cantos2 = cantos:Clone()
	cantos2.Parent = painelEquipa

	rotuloSacos = criarRotulo({
		nome = "Sacos",
		pai = painelEquipa,
		posicao = UDim2.new(0, 12, 0, 6),
		tamanho = UDim2.new(1, -24, 0, 26),
		tamanhoTexto = 18,
		alinhamento = Enum.TextXAlignment.Left,
		negrito = true,
	})

	rotuloDinheiro = criarRotulo({
		nome = "Dinheiro",
		pai = painelEquipa,
		posicao = UDim2.new(0, 12, 0, 32),
		tamanho = UDim2.new(1, -24, 0, 26),
		tamanhoTexto = 18,
		alinhamento = Enum.TextXAlignment.Left,
	})
end

local function mostrarEstado(estado: string)
	rotuloEstado.Text = string.upper(estado)
	rotuloEstado.TextColor3 = CORES_ESTADO[estado] or Color3.fromRGB(255, 255, 255)
	rotuloLegenda.Text = LEGENDAS[estado] or ""
end

local function aoAtualizarHUD(dados: {
	estado: string,
	sacosEntregues: number,
	sacosMinimos: number,
	fimDoTemporizador: number?,
	dinheiro: number,
})
	fimDoTemporizador = dados.fimDoTemporizador

	mostrarEstado(dados.estado)

	rotuloSacos.Text =
		string.format("Sacos entregues: %d / %d", dados.sacosEntregues, dados.sacosMinimos)
	rotuloDinheiro.Text = string.format("Dinheiro: %d", dados.dinheiro)
end

function HUDController.init() end

function HUDController.start()
	construirInterface()
	mostrarEstado(HeistState.Lobby)

	Remotes.HeistStateChanged.OnClientEvent:Connect(mostrarEstado)
	Remotes.UpdateHUD.OnClientEvent:Connect(aoAtualizarHUD)

	--[[
		Contagem decrescente feita aqui a partir do instante que o servidor
		enviou. O `workspace:GetServerTimeNow()` da o relogio do servidor visto
		do cliente, por isso a conta esta certa sem o servidor enviar nada a
		cada segundo.
	]]
	RunService.RenderStepped:Connect(function()
		if not fimDoTemporizador then
			rotuloTemporizador.Text = ""
			return
		end

		local faltam = math.max(0, fimDoTemporizador - workspace:GetServerTimeNow())
		rotuloTemporizador.Text = string.format("%d:%02d", faltam // 60, math.floor(faltam % 60))
	end)
end

return HUDController
