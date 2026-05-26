-- ============================================
-- VALEO v2.1 - Dead Rails Combat Suite
-- Custom raw UI (no external libraries)
-- ============================================

-- ============================================
-- SERVICES
-- ============================================
local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService   = game:GetService("TweenService")
local Camera         = workspace.CurrentCamera
local LocalPlayer    = Players.LocalPlayer

-- ============================================
-- FEATURE FLAGS
-- ============================================
local Features = {
    Aimbot = {
        Enabled   = false,
        Locked    = false,
        Smoothing = 0.04,
        FOV       = 250
    },
    FpsBoost = {
        Enabled   = false,
        Intensity = 0.5
    },
    Spoofers = {
        HardwareIdSpoof = false,
        HumanoidSpoof   = false,
        InputSpoof      = false,
        BehaviorSpoof   = false
    },
    ESP = {
        Enabled     = false,
        ShowNames   = false,
        ShowHealth  = false,
        ShowDistance = false,
        ShowBoxes   = false,
        TeamCheck   = false,
    },
    Chams = {
        Enabled     = false,
        TeamCheck   = false,
        EnemyColor  = Color3.fromRGB(255, 50, 50),
        FriendColor = Color3.fromRGB(50, 200, 255),
    }
}

-- ============================================
-- AIMBOT
-- ============================================
local aimbotTarget     = nil
local aimbotConnection = nil
local mouseVariation   = 0

-- FIX: use UserInputService instead of deprecated GetMouse()
local function getClosestPlayerToMouse()
    local closest, shortest = nil, math.huge
    local mousePos = UserInputService:GetMouseLocation()

    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            -- FIX: fallback to HumanoidRootPart if no Head
            local target = player.Character:FindFirstChild("Head")
                        or player.Character:FindFirstChild("HumanoidRootPart")
            if target then
                local screenPos, onScreen = Camera:WorldToViewportPoint(target.Position)
                if onScreen then
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if dist < Features.Aimbot.FOV and dist < shortest then
                        closest  = player
                        shortest = dist
                    end
                end
            end
        end
    end
    return closest
end

local function smoothLockToTarget(target)
    -- FIX: validate target is still alive and in game
    if not target or not target.Parent then
        aimbotTarget = nil
        Features.Aimbot.Locked = false
        return
    end
    if not target.Character then return end

    local aimPart = target.Character:FindFirstChild("Head")
                 or target.Character:FindFirstChild("HumanoidRootPart")
    if not aimPart then return end

    local cameraPos   = Camera.CFrame.Position
    local targetPos   = aimPart.Position
    local targetCFrame = CFrame.new(cameraPos, targetPos)

    -- FIX: apply mouseVariation from behavior spoof if enabled
    if Features.Spoofers.BehaviorSpoof then
        targetCFrame = targetCFrame * CFrame.Angles(mouseVariation, mouseVariation, 0)
    end

    Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, Features.Aimbot.Smoothing)
end

local function startAimbot()
    if aimbotConnection then aimbotConnection:Disconnect() aimbotConnection = nil end
    if not Features.Aimbot.Enabled then return end
    aimbotConnection = RunService.RenderStepped:Connect(function()
        if not Features.Aimbot.Enabled then return end
        if Features.Aimbot.Locked and aimbotTarget then
            smoothLockToTarget(aimbotTarget)
        end
    end)
end

local function stopAimbot()
    if aimbotConnection then aimbotConnection:Disconnect() aimbotConnection = nil end
    aimbotTarget = nil
    Features.Aimbot.Locked = false
end

-- ============================================
-- SPOOFERS
-- ============================================
local function spoofHardwareId()
    pcall(function()
        local id = string.format("%016x", math.random(0, 2^52))
        if getgenv then
            getgenv().HardwareID  = id
            getgenv().PCIdentifier = id
        end
    end)
end

local function spoofHumanoid()
    pcall(function()
        local function setup()
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                LocalPlayer.Character.Humanoid.Changed:Connect(function() end)
            end
        end
        setup()
        LocalPlayer.CharacterAdded:Connect(setup)
    end)
end

local inputSpooferConnected = false
local function spoofInput()
    if inputSpooferConnected then return end
    inputSpooferConnected = true
    UserInputService.InputBegan:Connect(function(input, gp)
        if Features.Spoofers.InputSpoof and not gp then
            local _ = math.random(5, 25) / 1000
        end
    end)
end

local behaviorConnected = false
local function spoofBehavior()
    if behaviorConnected then return end
    behaviorConnected = true
    RunService.RenderStepped:Connect(function()
        if Features.Spoofers.BehaviorSpoof and Features.Aimbot.Enabled then
            mouseVariation = (math.random() - 0.5) * 0.001
        end
    end)
end

-- ============================================
-- FPS BOOST
-- ============================================
local lastProcessTime = 0

local function degradeRivalGraphics(player)
    if not player or not player.Character then return end
    pcall(function()
        for _, part in pairs(player.Character:GetDescendants()) do
            if part:IsA("BasePart") then
                if Features.FpsBoost.Intensity > 0.3 then part.CanCollide = false end
                if Features.FpsBoost.Intensity > 0.6 then
                    part.Transparency = math.min(part.Transparency + 0.2, 0.8)
                end
            end
        end
    end)
end

RunService.RenderStepped:Connect(function()
    if Features.FpsBoost.Enabled and Features.FpsBoost.Intensity > 0 then
        local now = tick()
        if now - lastProcessTime > 0.5 then
            for _, player in pairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then degradeRivalGraphics(player) end
            end
            lastProcessTime = now
        end
    end
end)

-- ============================================
-- ESP & CHAMS
-- ============================================
local espObjects  = {}  -- [player] = { box, name, health, distance }
local chamsObjects = {} -- [player] = { parts with saved properties }

local function isEnemy(player)
    if not Features.ESP.TeamCheck and not Features.Chams.TeamCheck then return true end
    return player.Team == nil or player.Team ~= LocalPlayer.Team
end

-- ---- ESP ----
local function createESPForPlayer(player)
    if espObjects[player] then return end
    local folder = {}

    local billBoard = Instance.new("BillboardGui")
    billBoard.Name                  = "ValeoESP"
    billBoard.AlwaysOnTop           = true
    billBoard.Size                  = UDim2.new(0, 100, 0, 60)
    billBoard.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
    billBoard.ResetOnSpawn          = false
    billBoard.LightInfluence        = 0
    billBoard.Enabled               = false
    billBoard.Parent                = game:GetService("CoreGui") -- must have parent or gets GC'd

    -- Name label
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size                   = UDim2.new(1, 0, 0, 18)
    nameLabel.Position               = UDim2.new(0, 0, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text                   = player.Name
    nameLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
    nameLabel.Font                   = Enum.Font.GothamBold
    nameLabel.TextSize               = 12
    nameLabel.TextStrokeTransparency = 0.3
    nameLabel.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
    nameLabel.Visible                = false
    nameLabel.Parent                 = billBoard

    -- Health label
    local healthLabel = Instance.new("TextLabel")
    healthLabel.Size                   = UDim2.new(1, 0, 0, 16)
    healthLabel.Position               = UDim2.new(0, 0, 0, 20)
    healthLabel.BackgroundTransparency = 1
    healthLabel.Text                   = "HP: 100"
    healthLabel.TextColor3             = Color3.fromRGB(100, 255, 100)
    healthLabel.Font                   = Enum.Font.Gotham
    healthLabel.TextSize               = 11
    healthLabel.TextStrokeTransparency = 0.3
    healthLabel.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
    healthLabel.Visible                = false
    healthLabel.Parent                 = billBoard

    -- Distance label
    local distLabel = Instance.new("TextLabel")
    distLabel.Size                   = UDim2.new(1, 0, 0, 16)
    distLabel.Position               = UDim2.new(0, 0, 0, 38)
    distLabel.BackgroundTransparency = 1
    distLabel.Text                   = "0m"
    distLabel.TextColor3             = Color3.fromRGB(180, 180, 255)
    distLabel.Font                   = Enum.Font.Gotham
    distLabel.TextSize               = 11
    distLabel.TextStrokeTransparency = 0.3
    distLabel.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
    distLabel.Visible                = false
    distLabel.Parent                 = billBoard

    -- Highlight for through-wall outline (separate from chams)
    local highlight = Instance.new("Highlight")
    highlight.Name                  = "ValeoESPHighlight"
    highlight.FillTransparency      = 1
    highlight.OutlineColor          = Color3.fromRGB(255, 50, 50)
    highlight.OutlineTransparency   = 0
    highlight.DepthMode             = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Enabled               = false
    highlight.Parent                = game:GetService("CoreGui") -- must have parent or gets GC'd

    folder.billboard   = billBoard
    folder.nameLabel   = nameLabel
    folder.healthLabel = healthLabel
    folder.distLabel   = distLabel
    folder.highlight   = highlight
    folder.adornee     = nil

    espObjects[player] = folder
end

local function removeESPForPlayer(player)
    if espObjects[player] then
        espObjects[player].billboard:Destroy()
        if espObjects[player].highlight then
            espObjects[player].highlight:Destroy()
        end
        espObjects[player] = nil
    end
end

local function updateESP()
    if not Features.ESP.Enabled then return end

    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            if not espObjects[player] then
                createESPForPlayer(player)
            end

            local esp  = espObjects[player]
            local char = player.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head"))

            if not char or not root then
                esp.billboard.Enabled = false
                if esp.highlight then esp.highlight.Enabled = false end
                continue
            end

            if Features.ESP.TeamCheck and not isEnemy(player) then
                esp.billboard.Enabled = false
                if esp.highlight then esp.highlight.Enabled = false end
                continue
            end

            -- Parent billboard and highlight to root so they follow through walls
            if esp.adornee ~= root then
                esp.billboard.Parent      = root
                esp.highlight.Adornee     = char
                esp.highlight.Parent      = root
                esp.adornee               = root
            end

            esp.billboard.Enabled     = true
            esp.highlight.Enabled     = true

            -- Name
            esp.nameLabel.Visible = Features.ESP.ShowNames
            esp.nameLabel.Text    = player.Name

            -- Health
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                local hp    = math.floor(hum.Health)
                local maxhp = math.max(math.floor(hum.MaxHealth), 1)
                local ratio = hum.Health / maxhp
                esp.healthLabel.Visible    = Features.ESP.ShowHealth
                esp.healthLabel.Text       = "HP: " .. hp .. "/" .. maxhp
                esp.healthLabel.TextColor3 = Color3.fromRGB(
                    math.floor((1 - ratio) * 255),
                    math.floor(ratio * 220),
                    50
                )
            end

            -- Distance
            local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if localRoot then
                local dist = math.floor((root.Position - localRoot.Position).Magnitude)
                esp.distLabel.Visible = Features.ESP.ShowDistance
                esp.distLabel.Text    = dist .. "m"
            end
        end
    end

    -- Cleanup for players who left
    for player in pairs(espObjects) do
        if not player or not player.Parent then
            removeESPForPlayer(player)
        end
    end
end

-- ---- CHAMS (Highlight) ----
local function applyChamsToPlayer(player)
    if chamsObjects[player] then return end
    local char = player.Character
    if not char then return end

    local highlight = Instance.new("SelectionBox")
    highlight.Name           = "ValeoCham"
    highlight.Color3         = isEnemy(player) and Features.Chams.EnemyColor or Features.Chams.FriendColor
    highlight.LineThickness  = 0.05
    highlight.SurfaceTransparency = 0.6
    highlight.SurfaceColor3  = isEnemy(player) and Features.Chams.EnemyColor or Features.Chams.FriendColor
    highlight.Adornee        = char
    highlight.Parent         = game:GetService("CoreGui")

    chamsObjects[player] = highlight
end

local function removeChamsFromPlayer(player)
    if chamsObjects[player] then
        chamsObjects[player]:Destroy()
        chamsObjects[player] = nil
    end
end

local function updateChams()
    if not Features.Chams.Enabled then
        -- If disabled, clear all
        for player, _ in pairs(chamsObjects) do
            removeChamsFromPlayer(player)
        end
        return
    end

    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = player.Character
            if char then
                if Features.Chams.TeamCheck and not isEnemy(player) then
                    removeChamsFromPlayer(player)
                    continue
                end
                if not chamsObjects[player] then
                    applyChamsToPlayer(player)
                else
                    -- Update color if team changed
                    chamsObjects[player].Color3 = isEnemy(player) and Features.Chams.EnemyColor or Features.Chams.FriendColor
                    chamsObjects[player].SurfaceColor3 = chamsObjects[player].Color3
                end
            else
                removeChamsFromPlayer(player)
            end
        end
    end

    -- Clean up players who left
    for player, _ in pairs(chamsObjects) do
        if not player or not player.Parent then
            removeChamsFromPlayer(player)
        end
    end
end

-- Hook player added/removed for cleanup
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        -- Re-apply chams on respawn if enabled
        if Features.Chams.Enabled then
            task.wait(0.5)
            removeChamsFromPlayer(player)
            applyChamsToPlayer(player)
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    removeESPForPlayer(player)
    removeChamsFromPlayer(player)
end)

-- Main visual update loop (runs only when features are on)
RunService.RenderStepped:Connect(function()
    if Features.ESP.Enabled then
        updateESP()
    end
    if Features.Chams.Enabled then
        updateChams()
    end
end)

-- ============================================
-- RAW UI BUILDER
-- Disguised as a generic CoreGui element
-- ============================================
local uiVisible = true
local activeTab  = "Combat"

-- Random-looking name so it doesn't stand out in explorer
local guiName = "RobloxGui_" .. math.random(1000, 9999)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name            = guiName
ScreenGui.ResetOnSpawn    = false
ScreenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder    = 99

-- Try to parent to CoreGui to avoid detection via PlayerGui scan
pcall(function()
    ScreenGui.Parent = game:GetService("CoreGui")
end)
if not ScreenGui.Parent then
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

-- ---- COLORS ----
local C = {
    bg      = Color3.fromRGB(18,  18,  24),
    panel   = Color3.fromRGB(26,  26,  34),
    accent  = Color3.fromRGB(100, 60, 220),
    accentHover = Color3.fromRGB(120, 80, 240),
    text    = Color3.fromRGB(220, 220, 230),
    subtext = Color3.fromRGB(140, 140, 155),
    toggle_on  = Color3.fromRGB(80, 200, 120),
    toggle_off = Color3.fromRGB(60,  60,  75),
    slider_bg  = Color3.fromRGB(40,  40,  55),
    tab_active = Color3.fromRGB(100, 60, 220),
    tab_idle   = Color3.fromRGB(30,  30,  40),
    border     = Color3.fromRGB(50,  50,  65),
}

local function makeCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 6)
    c.Parent = parent
    return c
end

local function makeStroke(parent, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color     = color or C.border
    s.Thickness = thickness or 1
    s.Parent    = parent
    return s
end

local function makePadding(parent, px)
    local p = Instance.new("UIPadding")
    p.PaddingLeft   = UDim.new(0, px)
    p.PaddingRight  = UDim.new(0, px)
    p.PaddingTop    = UDim.new(0, px)
    p.PaddingBottom = UDim.new(0, px)
    p.Parent        = parent
    return p
end

-- ---- MAIN FRAME ----
local Main = Instance.new("Frame")
Main.Name            = "Main"
Main.Size            = UDim2.new(0, 480, 0, 340)
Main.Position        = UDim2.new(0.5, -240, 0.5, -170)
Main.BackgroundColor3 = C.bg
Main.BorderSizePixel = 0
Main.Parent          = ScreenGui
makeCorner(Main, 10)
makeStroke(Main, C.border, 1)

-- ---- TITLEBAR ----
local TitleBar = Instance.new("Frame")
TitleBar.Name              = "TitleBar"
TitleBar.Size              = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3  = C.panel
TitleBar.BorderSizePixel   = 0
TitleBar.Parent            = Main
makeCorner(TitleBar, 10)

-- Cover bottom corners of titlebar
local TitleFill = Instance.new("Frame")
TitleFill.Size             = UDim2.new(1, 0, 0, 10)
TitleFill.Position         = UDim2.new(0, 0, 1, -10)
TitleFill.BackgroundColor3 = C.panel
TitleFill.BorderSizePixel  = 0
TitleFill.Parent           = TitleBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size            = UDim2.new(1, -70, 1, 0)
TitleLabel.Position        = UDim2.new(0, 14, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text            = "VALEO  v2.1"
TitleLabel.TextColor3      = C.text
TitleLabel.Font            = Enum.Font.GothamBold
TitleLabel.TextSize        = 14
TitleLabel.TextXAlignment  = Enum.TextXAlignment.Left
TitleLabel.Parent          = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size              = UDim2.new(0, 28, 0, 20)
CloseBtn.Position          = UDim2.new(1, -36, 0.5, -10)
CloseBtn.BackgroundColor3  = Color3.fromRGB(200, 60, 60)
CloseBtn.Text              = "✕"
CloseBtn.TextColor3        = Color3.fromRGB(255,255,255)
CloseBtn.Font              = Enum.Font.GothamBold
CloseBtn.TextSize          = 12
CloseBtn.BorderSizePixel   = 0
CloseBtn.Parent            = TitleBar
makeCorner(CloseBtn, 5)

CloseBtn.MouseButton1Click:Connect(function()
    uiVisible = not uiVisible
    Main.Visible = uiVisible
end)

-- ---- DRAG ----
local dragging, dragStart, startPos
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging  = true
        dragStart = input.Position
        startPos  = Main.Position
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

-- ---- TAB BAR ----
local TabBar = Instance.new("Frame")
TabBar.Name              = "TabBar"
TabBar.Size              = UDim2.new(1, 0, 0, 32)
TabBar.Position          = UDim2.new(0, 0, 0, 36)
TabBar.BackgroundColor3  = C.panel
TabBar.BorderSizePixel   = 0
TabBar.Parent            = Main

local TabLayout = Instance.new("UIListLayout")
TabLayout.FillDirection  = Enum.FillDirection.Horizontal
TabLayout.SortOrder      = Enum.SortOrder.LayoutOrder
TabLayout.Padding        = UDim.new(0, 2)
TabLayout.Parent         = TabBar

local TabPad = Instance.new("UIPadding")
TabPad.PaddingLeft  = UDim.new(0, 6)
TabPad.PaddingTop   = UDim.new(0, 5)
TabPad.Parent       = TabBar

-- ---- CONTENT AREA ----
local Content = Instance.new("Frame")
Content.Name             = "Content"
Content.Size             = UDim2.new(1, -16, 1, -88)
Content.Position         = UDim2.new(0, 8, 0, 76)
Content.BackgroundTransparency = 1
Content.Parent           = Main

-- ---- UI HELPERS ----
local tabButtons = {}
local tabFrames  = {}

local function setTab(name)
    activeTab = name
    for n, btn in pairs(tabButtons) do
        btn.BackgroundColor3 = n == name and C.tab_active or C.tab_idle
        btn.TextColor3       = n == name and C.text or C.subtext
    end
    for n, frame in pairs(tabFrames) do
        frame.Visible = n == name
    end
end

local function addTab(name, order)
    local btn = Instance.new("TextButton")
    btn.Size             = UDim2.new(0, 88, 0, 22)
    btn.BackgroundColor3 = C.tab_idle
    btn.Text             = name
    btn.TextColor3       = C.subtext
    btn.Font             = Enum.Font.GothamSemibold
    btn.TextSize         = 12
    btn.BorderSizePixel  = 0
    btn.LayoutOrder      = order
    btn.Parent           = TabBar
    makeCorner(btn, 5)

    local frame = Instance.new("ScrollingFrame")
    frame.Name                   = name
    frame.Size                   = UDim2.new(1, 0, 1, 0)
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel        = 0
    frame.ScrollBarThickness     = 3
    frame.ScrollBarImageColor3   = C.accent
    frame.CanvasSize             = UDim2.new(0, 0, 0, 0)
    frame.AutomaticCanvasSize    = Enum.AutomaticSize.Y
    frame.Visible                = false
    frame.Parent                 = Content

    local layout = Instance.new("UIListLayout")
    layout.SortOrder   = Enum.SortOrder.LayoutOrder
    layout.Padding     = UDim.new(0, 6)
    layout.Parent      = frame

    tabButtons[name] = btn
    tabFrames[name]  = frame

    btn.MouseButton1Click:Connect(function() setTab(name) end)

    return frame
end

-- Widget builders
local widgetOrder = 0
local function nextOrder()
    widgetOrder = widgetOrder + 1
    return widgetOrder
end

local function addSection(tab, title)
    local label = Instance.new("TextLabel")
    label.Size              = UDim2.new(1, 0, 0, 18)
    label.BackgroundTransparency = 1
    label.Text              = "  " .. title:upper()
    label.TextColor3        = C.accent
    label.Font              = Enum.Font.GothamBold
    label.TextSize          = 11
    label.TextXAlignment    = Enum.TextXAlignment.Left
    label.LayoutOrder       = nextOrder()
    label.Parent            = tab
end

local function addToggle(tab, labelText, default, callback)
    local row = Instance.new("Frame")
    row.Size             = UDim2.new(1, 0, 0, 34)
    row.BackgroundColor3 = C.panel
    row.BorderSizePixel  = 0
    row.LayoutOrder      = nextOrder()
    row.Parent           = tab
    makeCorner(row, 6)

    local lbl = Instance.new("TextLabel")
    lbl.Size             = UDim2.new(1, -56, 1, 0)
    lbl.Position         = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text             = labelText
    lbl.TextColor3       = C.text
    lbl.Font             = Enum.Font.Gotham
    lbl.TextSize         = 13
    lbl.TextXAlignment   = Enum.TextXAlignment.Left
    lbl.Parent           = row

    local track = Instance.new("Frame")
    track.Size           = UDim2.new(0, 36, 0, 18)
    track.Position       = UDim2.new(1, -48, 0.5, -9)
    track.BackgroundColor3 = default and C.toggle_on or C.toggle_off
    track.BorderSizePixel = 0
    track.Parent         = row
    makeCorner(track, 9)

    local knob = Instance.new("Frame")
    knob.Size            = UDim2.new(0, 14, 0, 14)
    knob.Position        = default and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent          = track
    makeCorner(knob, 7)

    local state = default or false

    local btn = Instance.new("TextButton")
    btn.Size             = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text             = ""
    btn.Parent           = row

    btn.MouseButton1Click:Connect(function()
        state = not state
        local ti = TweenService:Create(track, TweenInfo.new(0.15), {BackgroundColor3 = state and C.toggle_on or C.toggle_off})
        local tk = TweenService:Create(knob,  TweenInfo.new(0.15), {Position = state and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7)})
        ti:Play() tk:Play()
        callback(state)
    end)

    return function() return state end
end

local function addSlider(tab, labelText, min, max, default, callback)
    local row = Instance.new("Frame")
    row.Size             = UDim2.new(1, 0, 0, 50)
    row.BackgroundColor3 = C.panel
    row.BorderSizePixel  = 0
    row.LayoutOrder      = nextOrder()
    row.Parent           = tab
    makeCorner(row, 6)

    local lbl = Instance.new("TextLabel")
    lbl.Size             = UDim2.new(1, -50, 0, 22)
    lbl.Position         = UDim2.new(0, 12, 0, 4)
    lbl.BackgroundTransparency = 1
    lbl.Text             = labelText
    lbl.TextColor3       = C.text
    lbl.Font             = Enum.Font.Gotham
    lbl.TextSize         = 13
    lbl.TextXAlignment   = Enum.TextXAlignment.Left
    lbl.Parent           = row

    local valLabel = Instance.new("TextLabel")
    valLabel.Size        = UDim2.new(0, 44, 0, 22)
    valLabel.Position    = UDim2.new(1, -52, 0, 4)
    valLabel.BackgroundTransparency = 1
    valLabel.Text        = tostring(default)
    valLabel.TextColor3  = C.accent
    valLabel.Font        = Enum.Font.GothamBold
    valLabel.TextSize    = 12
    valLabel.TextXAlignment = Enum.TextXAlignment.Right
    valLabel.Parent      = row

    local trackBg = Instance.new("Frame")
    trackBg.Size         = UDim2.new(1, -24, 0, 6)
    trackBg.Position     = UDim2.new(0, 12, 0, 32)
    trackBg.BackgroundColor3 = C.slider_bg
    trackBg.BorderSizePixel = 0
    trackBg.Parent       = row
    makeCorner(trackBg, 3)

    local fill = Instance.new("Frame")
    local pct  = (default - min) / (max - min)
    fill.Size            = UDim2.new(pct, 0, 1, 0)
    fill.BackgroundColor3 = C.accent
    fill.BorderSizePixel = 0
    fill.Parent          = trackBg
    makeCorner(fill, 3)

    local value = default

    local function updateSlider(inputX)
        local rel = math.clamp((inputX - trackBg.AbsolutePosition.X) / trackBg.AbsoluteSize.X, 0, 1)
        value = math.floor((min + (max - min) * rel) * 100 + 0.5) / 100
        fill.Size = UDim2.new(rel, 0, 1, 0)
        valLabel.Text = tostring(value)
        callback(value)
    end

    local sliding = false
    local sliderBtn = Instance.new("TextButton")
    sliderBtn.Size   = UDim2.new(1, 0, 1, 0)
    sliderBtn.BackgroundTransparency = 1
    sliderBtn.Text   = ""
    sliderBtn.Parent = trackBg

    sliderBtn.MouseButton1Down:Connect(function()
        sliding = true
    end)
    UserInputService.InputChanged:Connect(function(input)
        if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then
            updateSlider(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliding = false
        end
    end)

    return function() return value end
end

local function addButton(tab, labelText, callback)
    local btn = Instance.new("TextButton")
    btn.Size             = UDim2.new(1, 0, 0, 34)
    btn.BackgroundColor3 = C.accent
    btn.Text             = labelText
    btn.TextColor3       = C.text
    btn.Font             = Enum.Font.GothamBold
    btn.TextSize         = 13
    btn.BorderSizePixel  = 0
    btn.LayoutOrder      = nextOrder()
    btn.Parent           = tab
    makeCorner(btn, 6)

    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = C.accentHover}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = C.accent}):Play()
    end)
    btn.MouseButton1Click:Connect(function()
        task.spawn(callback)
    end)
end

local function addLabel(tab, text)
    local lbl = Instance.new("TextLabel")
    lbl.Size             = UDim2.new(1, 0, 0, 22)
    lbl.BackgroundTransparency = 1
    lbl.Text             = text
    lbl.TextColor3       = C.subtext
    lbl.Font             = Enum.Font.Gotham
    lbl.TextSize         = 12
    lbl.TextXAlignment   = Enum.TextXAlignment.Left
    lbl.LayoutOrder      = nextOrder()
    lbl.Parent           = tab
end

-- ============================================
-- BUILD TABS
-- ============================================
local CombatTab   = addTab("Combat",   1)
local VisualsTab  = addTab("Visuals",  2)
local SkinsTab    = addTab("Skins",    3)
local SpooferTab  = addTab("Spoofers", 4)
local SettingsTab = addTab("Settings", 5)

-- ============================================
-- COMBAT TAB
-- ============================================
addSection(CombatTab, "Aimbot")

addToggle(CombatTab, "Enable Aimbot", false, function(state)
    Features.Aimbot.Enabled = state
    if state then
        startAimbot()
    else
        stopAimbot()
    end
end)

addSlider(CombatTab, "Smoothing", 0.01, 1, 0.04, function(v)
    Features.Aimbot.Smoothing = v
end)

addSlider(CombatTab, "FOV", 50, 600, 250, function(v)
    Features.Aimbot.FOV = v
end)

-- ============================================
-- VISUALS TAB
-- ============================================
addSection(VisualsTab, "ESP")

addToggle(VisualsTab, "Enable ESP", false, function(state)
    Features.ESP.Enabled = state
    if not state then
        for player, _ in pairs(espObjects) do
            removeESPForPlayer(player)
        end
    end
end)

addToggle(VisualsTab, "Show Names", false, function(state)
    Features.ESP.ShowNames = state
end)

addToggle(VisualsTab, "Show Health", false, function(state)
    Features.ESP.ShowHealth = state
end)

addToggle(VisualsTab, "Show Distance", false, function(state)
    Features.ESP.ShowDistance = state
end)

addToggle(VisualsTab, "Team Check (ESP)", false, function(state)
    Features.ESP.TeamCheck = state
end)

addSection(VisualsTab, "Chams")

addToggle(VisualsTab, "Enable Chams", false, function(state)
    Features.Chams.Enabled = state
    if not state then
        for player, _ in pairs(chamsObjects) do
            removeChamsFromPlayer(player)
        end
    end
end)

addToggle(VisualsTab, "Team Check (Chams)", false, function(state)
    Features.Chams.TeamCheck = state
end)

-- ============================================
-- SKINS TAB
-- ============================================
addSection(SkinsTab, "Skin Unlocker")

addButton(SkinsTab, "Unlock All Skins", function()
    pcall(function()
        loadstring(game:HttpGet("https://pastebin.com/raw/4rVNKnw0"))()
    end)
end)

addSection(SkinsTab, "FPS Boost")

addToggle(SkinsTab, "Enable FPS Boost", false, function(state)
    Features.FpsBoost.Enabled = state
end)

addSlider(SkinsTab, "Intensity", 0, 1, 0.5, function(v)
    Features.FpsBoost.Intensity = v
end)

-- ============================================
-- SPOOFERS TAB
-- ============================================
addSection(SpooferTab, "Anti-Detection")

addToggle(SpooferTab, "Hardware ID Spoof", false, function(state)
    Features.Spoofers.HardwareIdSpoof = state
    if state then spoofHardwareId() end
end)

addToggle(SpooferTab, "Humanoid Spoof", false, function(state)
    Features.Spoofers.HumanoidSpoof = state
    if state then spoofHumanoid() end
end)

addToggle(SpooferTab, "Input Spoof", false, function(state)
    Features.Spoofers.InputSpoof = state
    if state then spoofInput() end
end)

addToggle(SpooferTab, "Behavior Spoof", false, function(state)
    Features.Spoofers.BehaviorSpoof = state
    if state then spoofBehavior() end
end)

-- ============================================
-- VISUAL SPOOFERS
-- ============================================
addSection(SpooferTab, "Visual")

local winStreakSpoofActive = false
local winStreakValue = 999
local winStreakConnection = nil

local function applyWinStreakSpoof()
    -- Search the character and its descendants for any TextLabel showing the streak
    pcall(function()
        local char = LocalPlayer.Character
        if not char then return end

        -- Dead Rails puts the streak inside a BillboardGui on the character
        -- Scan all BillboardGuis and change any numeric TextLabel
        for _, obj in pairs(char:GetDescendants()) do
            if obj:IsA("TextLabel") or obj:IsA("TextButton") then
                -- Match labels that contain only a number (the streak count)
                if obj.Text:match("^%d+$") then
                    obj.Text = tostring(winStreakValue)
                end
            end
        end

        -- Also scan PlayerGui in case it's mirrored there
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if playerGui then
            for _, obj in pairs(playerGui:GetDescendants()) do
                if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.Text:match("^%d+$") then
                    obj.Text = tostring(winStreakValue)
                end
            end
        end
    end)
end

local function startWinStreakSpoof()
    if winStreakConnection then winStreakConnection:Disconnect() end
    -- Re-apply every 0.2s so the game can't overwrite it back
    winStreakConnection = RunService.Heartbeat:Connect(function()
        if not winStreakSpoofActive then return end
        applyWinStreakSpoof()
    end)
end

local function stopWinStreakSpoof()
    if winStreakConnection then
        winStreakConnection:Disconnect()
        winStreakConnection = nil
    end
end

addToggle(SpooferTab, "Win Streak Spoof", false, function(state)
    winStreakSpoofActive = state
    if state then
        startWinStreakSpoof()
    else
        stopWinStreakSpoof()
    end
end)

addSlider(SpooferTab, "Streak Value", 0, 9999, 999, function(v)
    winStreakValue = math.floor(v)
    if winStreakSpoofActive then
        applyWinStreakSpoof()
    end
end)

-- ============================================
-- KEYS SPOOF
-- ============================================
local keysSpoofActive = false
local keysValue = 31
local keysConnection = nil

local function applyKeysSpoof()
    pcall(function()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then return end

        -- Keys display is typically a small number at top of screen (coin icon area)
        -- Search through all TextLabels for numeric values near top
        for _, obj in pairs(playerGui:GetDescendants()) do
            if obj:IsA("TextLabel") or obj:IsA("TextButton") then
                local text = obj.Text
                
                -- Look for numeric text (keys are usually 1-4 digits)
                if text:match("^%d+$") and #text <= 4 then
                    local absPos = obj.AbsolutePosition
                    local absSize = obj.AbsoluteSize
                    
                    -- Keys typically display at top with reasonable size
                    if absSize.X > 10 and absSize.X < 150 and absSize.Y > 10 and absSize.Y < 80 then
                        if absPos.Y < 200 then  -- Near top of screen
                            obj.Text = tostring(keysValue)
                        end
                    end
                end
            end
        end
    end)
end

local function startKeysSpoof()
    if keysConnection then keysConnection:Disconnect() end
    keysConnection = RunService.Heartbeat:Connect(function()
        if not keysSpoofActive then return end
        applyKeysSpoof()
    end)
end

local function stopKeysSpoof()
    if keysConnection then
        keysConnection:Disconnect()
        keysConnection = nil
    end
end

addToggle(SpooferTab, "Keys Spoof", false, function(state)
    keysSpoofActive = state
    if state then
        startKeysSpoof()
    else
        stopKeysSpoof()
    end
end)

addSlider(SpooferTab, "Keys Value", 0, 99999, 31, function(v)
    keysValue = math.floor(v)
    if keysSpoofActive then
        applyKeysSpoof()
    end
end)

-- ============================================
-- CASH SPOOF
-- ============================================
local cashSpoofActive = false
local cashValue = 9999
local cashConnection = nil

local function applyCashSpoof()
    pcall(function()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then return end

        -- Cash display is typically a larger number, often at bottom of screen
        -- Search through all TextLabels for numeric values
        for _, obj in pairs(playerGui:GetDescendants()) do
            if obj:IsA("TextLabel") or obj:IsA("TextButton") then
                local text = obj.Text
                local name = obj.Name:lower()
                local parent = obj.Parent
                local parentName = (parent and parent.Name:lower()) or ""
                
                -- Method 1: Check if name/parent mentions cash/money
                if name:match("cash") or name:match("money") or 
                   parentName:match("cash") or parentName:match("money") then
                    if text:match("^%d+") or text:match("%$%d+") then
                        obj.Text = tostring(cashValue)
                        return
                    end
                end
            end
        end

        -- Method 2: If not found by name, look for large numbers at bottom of screen
        local candidates = {}
        for _, obj in pairs(playerGui:GetDescendants()) do
            if obj:IsA("TextLabel") or obj:IsA("TextButton") then
                local text = obj.Text
                if text:match("^%d+$") and #text <= 8 then  -- Cash is usually up to 8 digits
                    local absPos = obj.AbsolutePosition
                    local absSize = obj.AbsoluteSize
                    
                    if absSize.X > 20 and absSize.X < 200 and absSize.Y > 12 and absSize.Y < 50 then
                        if absPos.Y > 500 then  -- Bottom area of screen
                            table.insert(candidates, {obj = obj, y = absPos.Y})
                        end
                    end
                end
            end
        end
        
        -- Pick the one furthest down (most likely cash display)
        if #candidates > 0 then
            table.sort(candidates, function(a, b) return a.y > b.y end)
            candidates[1].obj.Text = tostring(cashValue)
        end
    end)
end

local function startCashSpoof()
    if cashConnection then cashConnection:Disconnect() end
    cashConnection = RunService.Heartbeat:Connect(function()
        if not cashSpoofActive then return end
        applyCashSpoof()
    end)
end

local function stopCashSpoof()
    if cashConnection then
        cashConnection:Disconnect()
        cashConnection = nil
    end
end

addToggle(SpooferTab, "Cash Spoof", false, function(state)
    cashSpoofActive = state
    if state then
        startCashSpoof()
    else
        stopCashSpoof()
    end
end)

addSlider(SpooferTab, "Cash Value", 0, 999999, 9999, function(v)
    cashValue = math.floor(v)
    if cashSpoofActive then
        applyCashSpoof()
    end
end)

-- ============================================
-- DEVICE TYPE SPOOFERS (VR, PC, MOBILE)
-- ============================================
addSection(SpooferTab, "Device Spoofer")

local deviceSpoofActive = false
local currentDevice = "PC"  -- Default: PC
local deviceConnection = nil

local function applyDeviceSpoof()
    pcall(function()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then return end

        -- Search for device indicator images/labels
        -- Dead Rails shows device type as an icon/label usually in player info area
        for _, obj in pairs(playerGui:GetDescendants()) do
            -- Check for image labels (device icons typically have images)
            if obj:IsA("ImageLabel") then
                local imageName = obj.Name:lower()
                
                -- Look for existing device indicators
                if imageName:match("device") or imageName:match("platform") or 
                   imageName:match("pc") or imageName:match("mobile") or imageName:match("vr") then
                    -- Change the image based on current device setting
                    if currentDevice == "VR" then
                        obj.Image = "rbxasset://textures/Ui/VRIcon.png"  -- VR icon
                        obj.Name = "VRIcon"
                    elseif currentDevice == "Mobile" then
                        obj.Image = "rbxasset://textures/Ui/MobileIcon.png"  -- Mobile icon
                        obj.Name = "MobileIcon"
                    else  -- PC (default)
                        obj.Image = "rbxasset://textures/Ui/PCIcon.png"  -- PC icon
                        obj.Name = "PCIcon"
                    end
                end
            end
            
            -- Also check text labels that might show device type
            if obj:IsA("TextLabel") or obj:IsA("TextButton") then
                local text = obj.Text:lower()
                
                if text:match("device") or text:match("platform") then
                    if currentDevice == "VR" then
                        obj.Text = "VR"
                    elseif currentDevice == "Mobile" then
                        obj.Text = "Mobile"
                    else
                        obj.Text = "PC"
                    end
                end
            end
        end
    end)
end

local function startDeviceSpoof()
    if deviceConnection then deviceConnection:Disconnect() end
    deviceConnection = RunService.Heartbeat:Connect(function()
        if not deviceSpoofActive then return end
        applyDeviceSpoof()
    end)
end

local function stopDeviceSpoof()
    if deviceConnection then
        deviceConnection:Disconnect()
        deviceConnection = nil
    end
end

addToggle(SpooferTab, "Device Spoof", false, function(state)
    deviceSpoofActive = state
    if state then
        startDeviceSpoof()
    else
        stopDeviceSpoof()
    end
end)

-- Device type selection buttons
local function createDeviceButton(deviceName, device)
    addButton(SpooferTab, "Spoof as " .. deviceName, function()
        currentDevice = device
        print("[Valeo] Device spoofed to: " .. device)
        if deviceSpoofActive then
            applyDeviceSpoof()
        end
    end)
end

createDeviceButton("PC", "PC")
createDeviceButton("Mobile", "Mobile")
createDeviceButton("VR", "VR")

-- ============================================
-- SETTINGS TAB
-- ============================================
addSection(SettingsTab, "Server Hop")

-- Roblox server ping ranges by region (approximate ms)
-- EU  = 20-80ms,  NA = 20-80ms,  AS = 100-200ms
-- We sort by ping and pick servers in the target range

local TeleportService = game:GetService("TeleportService")

local function getServers()
    local allServers = {}
    local cursor = ""
    -- Fetch up to 3 pages for a wider pool
    for _ = 1, 3 do
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        if cursor ~= "" then url = url .. "&cursor=" .. cursor end

        local ok, data = pcall(function() return game:HttpGet(url) end)
        if not ok then break end

        for jobId, ping in data:gmatch('"id":"([^"]+)"[^}]-"ping":(%d+)') do
            if jobId ~= game.JobId then
                table.insert(allServers, { id = jobId, ping = tonumber(ping) })
            end
        end

        local nextCursor = data:match('"nextPageCursor":"([^"]+)"')
        if not nextCursor or nextCursor == "" then break end
        cursor = nextCursor
    end
    return allServers
end

local function hopToRegion(minPing, maxPing, label)
    print("[Valeo] Searching for " .. label .. " servers...")
    local servers = getServers()

    -- Filter by ping range
    local matches = {}
    for _, s in pairs(servers) do
        if s.ping >= minPing and s.ping <= maxPing then
            table.insert(matches, s)
        end
    end

    -- Sort by lowest ping
    table.sort(matches, function(a, b) return a.ping < b.ping end)

    if #matches == 0 then
        -- Fallback: pick lowest ping overall
        table.sort(servers, function(a, b) return a.ping < b.ping end)
        if #servers == 0 then
            print("[Valeo] No servers found.")
            return
        end
        matches = { servers[1] }
        print("[Valeo] No " .. label .. " servers found, using lowest ping: " .. matches[1].ping .. "ms")
    else
        print("[Valeo] Found " .. #matches .. " " .. label .. " servers. Best ping: " .. matches[1].ping .. "ms")
    end

    -- Pick randomly from top 5 matches to avoid always same server
    local pick = matches[math.random(1, math.min(5, #matches))]
    print("[Valeo] Hopping to " .. label .. " server (" .. pick.ping .. "ms)")

    pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, pick.id, LocalPlayer)
    end)
end

-- NA  ~ 20-80ms  (US East/West)
addButton(SettingsTab, "Hop to NA Server", function()
    hopToRegion(20, 80, "NA")
end)

-- EU  ~ 20-80ms  (same ping range, different pool depending on your location)
addButton(SettingsTab, "Hop to EU Server", function()
    hopToRegion(20, 80, "EU")
end)

-- Asia ~ 100-200ms
addButton(SettingsTab, "Hop to Asia Server", function()
    hopToRegion(100, 200, "Asia")
end)

-- Low ping (best possible regardless of region)
addButton(SettingsTab, "Hop to Low Ping Server", function()
    hopToRegion(0, 60, "Low Ping")
end)

-- Random (no filter)
addButton(SettingsTab, "Hop to Random Server", function()
    local servers = getServers()
    if #servers == 0 then print("[Valeo] No servers found.") return end
    local pick = servers[math.random(1, #servers)]
    print("[Valeo] Hopping to random server (" .. pick.ping .. "ms)")
    pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, pick.id, LocalPlayer)
    end)
end)

addSection(SettingsTab, "Info")
addLabel(SettingsTab, "  Valeo v2.1 - Dead Rails")
addLabel(SettingsTab, "  RightShift = Toggle UI")
addLabel(SettingsTab, "  Right Click = Aimbot Lock")

-- ============================================
-- RIGHT CLICK AIMBOT LOCK
-- ============================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end

    -- Strictly require aimbot toggle to be ON
    if not Features.Aimbot.Enabled then return end

    -- Block if clicking inside the UI window
    if Main.Visible then
        local mousePos = UserInputService:GetMouseLocation()
        local mainPos  = Main.AbsolutePosition
        local mainSize = Main.AbsoluteSize
        if mousePos.X >= mainPos.X and mousePos.X <= mainPos.X + mainSize.X
        and mousePos.Y >= mainPos.Y and mousePos.Y <= mainPos.Y + mainSize.Y then
            return
        end
    end

    if not Features.Aimbot.Locked then
        aimbotTarget = getClosestPlayerToMouse()
        if aimbotTarget then
            Features.Aimbot.Locked = true
        end
    else
        Features.Aimbot.Locked = false
        aimbotTarget = nil
    end
end)

-- ============================================
-- RIGHTSHIFT TOGGLE UI
-- ============================================
UserInputService.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.RightShift then
        uiVisible = not uiVisible
        Main.Visible = uiVisible
    end
end)

-- ============================================
-- INIT - show Combat tab by default
-- ============================================
setTab("Combat")

print("[Valeo] Loaded.")
