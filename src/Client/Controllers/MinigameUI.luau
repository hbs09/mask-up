--!strict
--[[
	Interface do minijogo do cabo (secçao 3 do documento: MinigameUI).

	Mostra os fios quando o painel abre e envia a escolha. Nao sabe qual e o
	certo -- essa informacao nunca sai do servidor -- e por isso nao pode
	decidir nada: so desenha o que recebe e devolve o clique.

	A pista chega pelo mesmo Remote, quando o jogador le o esquema, e aparece
	num aviso no ecra. Fica guardada aqui em memoria para o painel a poder
	lembrar: ter de decorar uma cor entre encontrar o papel e chegar ao painel
	seria dificuldade a custa da memoria do jogador, nao da pericia dele.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local MinigameUI = {}

--[[
	As tres mensagens que o Remote EstadoDoCabo traz. Um alias nomeado em vez do
	tipo escrito na assinatura: o stylua nao e idempotente com um tipo de tabela
	inline num parametro -- formata-o de uma maneira e o --check pede outra.
]]
type Mensagem = {
	tipo: string,
	cor: string?,
	cores: { string }?,
	acertou: boolean?,
}

-- Nomes do Config traduzidos para cor no ecra. Um fio chamado "azul" tem de
-- aparecer azul, senao o esquema nao serve de nada.
local CORES: { [string]: Color3 } = {
	vermelho = Color3.fromRGB(220, 70, 70),
	azul = Color3.fromRGB(70, 130, 230),
	verde = Color3.fromRGB(80, 200, 110),
	amarelo = Color3.fromRGB(235, 205, 70),
}

local gui: ScreenGui
local painelDosFios: Frame
local rotuloAviso: TextLabel
local listaDeFios: Frame

local pistaConhecida: string? = nil

local function construirInterface()
	local jogador = Players.LocalPlayer

	gui = Instance.new("ScreenGui")
	gui.Name = "MinigameCabo"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = true
	gui.Parent = jogador:WaitForChild("PlayerGui")

	-- Aviso central curto, para a pista e para o resultado.
	rotuloAviso = Instance.new("TextLabel")
	rotuloAviso.Name = "Aviso"
	rotuloAviso.AnchorPoint = Vector2.new(0.5, 0)
	rotuloAviso.Position = UDim2.new(0.5, 0, 0, 100)
	rotuloAviso.Size = UDim2.new(0, 420, 0, 32)
	rotuloAviso.BackgroundTransparency = 1
	rotuloAviso.Font = Enum.Font.GothamBold
	rotuloAviso.TextSize = 20
	rotuloAviso.TextColor3 = Color3.fromRGB(255, 255, 255)
	rotuloAviso.TextStrokeTransparency = 0.3
	rotuloAviso.Text = ""
	rotuloAviso.Visible = false
	rotuloAviso.Parent = gui

	-- Painel dos fios, ao centro.
	painelDosFios = Instance.new("Frame")
	painelDosFios.Name = "Fios"
	painelDosFios.AnchorPoint = Vector2.new(0.5, 0.5)
	painelDosFios.Position = UDim2.fromScale(0.5, 0.5)
	painelDosFios.Size = UDim2.new(0, 340, 0, 190)
	painelDosFios.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	painelDosFios.BackgroundTransparency = 0.1
	painelDosFios.BorderSizePixel = 0
	painelDosFios.Visible = false
	painelDosFios.Parent = gui

	local cantos = Instance.new("UICorner")
	cantos.CornerRadius = UDim.new(0, 10)
	cantos.Parent = painelDosFios

	local titulo = Instance.new("TextLabel")
	titulo.Position = UDim2.new(0, 0, 0, 10)
	titulo.Size = UDim2.new(1, 0, 0, 24)
	titulo.BackgroundTransparency = 1
	titulo.Font = Enum.Font.GothamBold
	titulo.TextSize = 18
	titulo.TextColor3 = Color3.fromRGB(255, 255, 255)
	titulo.Text = "Corta um fio"
	titulo.Parent = painelDosFios

	local subtitulo = Instance.new("TextLabel")
	subtitulo.Name = "Subtitulo"
	subtitulo.Position = UDim2.new(0, 0, 0, 34)
	subtitulo.Size = UDim2.new(1, 0, 0, 18)
	subtitulo.BackgroundTransparency = 1
	subtitulo.Font = Enum.Font.Gotham
	subtitulo.TextSize = 13
	subtitulo.TextColor3 = Color3.fromRGB(200, 200, 210)
	subtitulo.Text = "uma tentativa"
	subtitulo.Parent = painelDosFios

	listaDeFios = Instance.new("Frame")
	listaDeFios.Name = "Lista"
	listaDeFios.Position = UDim2.new(0, 16, 0, 64)
	listaDeFios.Size = UDim2.new(1, -32, 0, 110)
	listaDeFios.BackgroundTransparency = 1
	listaDeFios.Parent = painelDosFios

	local grelha = Instance.new("UIGridLayout")
	grelha.CellSize = UDim2.new(0.5, -6, 0, 46)
	grelha.CellPadding = UDim2.new(0, 12, 0, 12)
	grelha.Parent = listaDeFios
end

local function fechar()
	painelDosFios.Visible = false
	listaDeFios:ClearAllChildren()

	local grelha = Instance.new("UIGridLayout")
	grelha.CellSize = UDim2.new(0.5, -6, 0, 46)
	grelha.CellPadding = UDim2.new(0, 12, 0, 12)
	grelha.Parent = listaDeFios
end

local function mostrarAviso(texto: string, cor: Color3)
	rotuloAviso.Text = texto
	rotuloAviso.TextColor3 = cor
	rotuloAviso.Visible = true

	task.delay(5, function()
		if rotuloAviso.Text == texto then
			rotuloAviso.Visible = false
		end
	end)
end

local function abrir(cores: { string })
	fechar()

	local subtitulo = painelDosFios:FindFirstChild("Subtitulo") :: TextLabel?
	if subtitulo then
		subtitulo.Text = if pistaConhecida
			then string.format("o esquema dizia: %s", string.upper(pistaConhecida))
			else "uma tentativa - nao sabes qual"
	end

	for _, cor in cores do
		local botao = Instance.new("TextButton")
		botao.Name = cor
		botao.BackgroundColor3 = CORES[cor] or Color3.fromRGB(150, 150, 150)
		botao.BorderSizePixel = 0
		botao.Font = Enum.Font.GothamBold
		botao.TextSize = 15
		botao.TextColor3 = Color3.fromRGB(20, 20, 20)
		botao.Text = string.upper(cor)
		botao.Parent = listaDeFios

		local cantos = Instance.new("UICorner")
		cantos.CornerRadius = UDim.new(0, 6)
		cantos.Parent = botao

		botao.Activated:Connect(function()
			-- Fechamos logo: o servidor decide, mas deixar os botoes clicaveis
			-- convidava a tentar outra vez quando a tentativa ja esta gasta.
			fechar()
			Remotes.WireChoice:FireServer(cor)
		end)
	end

	painelDosFios.Visible = true
end

local function aoReceberEstado(dados: Mensagem)
	if dados.tipo == "pista" and dados.cor then
		pistaConhecida = dados.cor
		mostrarAviso(
			string.format("O esquema diz: corta o %s", string.upper(dados.cor)),
			CORES[dados.cor] or Color3.fromRGB(255, 255, 255)
		)
	elseif dados.tipo == "abrir" and dados.cores then
		abrir(dados.cores)
	elseif dados.tipo == "fechar" then
		fechar()

		if dados.acertou then
			mostrarAviso("Cameras desligadas", Color3.fromRGB(80, 220, 110))
		else
			mostrarAviso("Fio errado - alarme!", Color3.fromRGB(235, 90, 80))
		end
	end
end

function MinigameUI.init() end

function MinigameUI.start()
	construirInterface()

	Remotes.EstadoDoCabo.OnClientEvent:Connect(aoReceberEstado)

	-- Assalto novo: a pista anterior ja nao serve, porque o servidor sorteia
	-- outro fio. Guarda-la seria pior que nao ter nenhuma.
	Remotes.HeistStateChanged.OnClientEvent:Connect(function(estado)
		if estado == "Lobby" then
			pistaConhecida = nil
			fechar()
		end
	end)
end

return MinigameUI
