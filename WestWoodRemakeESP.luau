--------------------------------------------------------------------------------
-- OUTCOME ESP PRO - AUTO-CLEANUP & STATS PATCH
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- 1. LIMPIEZA DEL ENTORNO (MATA SCRIPTS ANTERIORES)
if _G.OUTCOME_ESP_LOOP then _G.OUTCOME_ESP_LOOP:Disconnect() end
if _G.OUTCOME_STATS_LOOP then _G.OUTCOME_STATS_LOOP:Disconnect() end
if _G.OUTCOME_ESP_OBJECTS then
    for _, data in pairs(_G.OUTCOME_ESP_OBJECTS) do
        if data.draw then data.draw:Remove() end
    end
end
for _, gui in ipairs(game:GetService("CoreGui"):GetChildren()) do
    if gui.Name:match("OUTCOME_Menu") then gui:Destroy() end
end

-- 2. CONFIGURACIÓN Y ESTADO
local Config = {
    players = true,
    monsters = true,
    items = true,
    infStats = true -- Estamina, hambre y sed infinita
}

_G.OUTCOME_ESP_OBJECTS = {}
local espObjects = _G.OUTCOME_ESP_OBJECTS

local function createText()
    local text = Drawing.new("Text")
    text.Visible = false
    text.Center = true
    text.Outline = true
    text.Font = 2
    text.Size = 13
    return text
end

local function addESP(instance, name, color, typeCategory)
    if not instance then return end
    if not espObjects[instance] then
        espObjects[instance] = {
            draw = createText(),
            name = name,
            color = color,
            category = typeCategory
        }
    end
end

local function removeESP(instance)
    if espObjects[instance] then
        espObjects[instance].draw:Remove()
        espObjects[instance] = nil
    end
end

-- 3. HOOKS DE ESP
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer and player.Character then
        addESP(player.Character, player.Name, Color3.new(1, 1, 1), "players")
    end
    player.CharacterAdded:Connect(function(char)
        addESP(char, player.Name, Color3.new(1, 1, 1), "players")
    end)
end
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        addESP(char, player.Name, Color3.new(1, 1, 1), "players")
    end)
end)
Players.PlayerRemoving:Connect(function(player)
    if player.Character then removeESP(player.Character) end
end)

local function checkPrompt(desc)
    if desc:IsA("ProximityPrompt") then
        if desc:FindFirstAncestor("Enemy") then return end
        local name = desc.ObjectText
        if not name or name == "" then name = desc.ActionText end
        if not name or name == "" then name = desc.Parent and desc.Parent.Name or "Item" end
        -- Limpiamos nombres para que sean directos
        addESP(desc, name, Color3.new(0, 1, 0), "items")
    end
end

local npcFolder = workspace:FindFirstChild("NPC")
if npcFolder then
    local enemyFolder = npcFolder:FindFirstChild("Enemy")
    if enemyFolder then
        for _, enemy in ipairs(enemyFolder:GetChildren()) do
            addESP(enemy, enemy.Name, Color3.new(1, 0, 0), "monsters")
        end
        enemyFolder.ChildAdded:Connect(function(enemy)
            addESP(enemy, enemy.Name, Color3.new(1, 0, 0), "monsters")
        end)
        enemyFolder.ChildRemoved:Connect(removeESP)
    end
end

for _, desc in ipairs(workspace:GetDescendants()) do checkPrompt(desc) end
workspace.DescendantAdded:Connect(checkPrompt)
workspace.DescendantRemoving:Connect(function(desc)
    if desc:IsA("ProximityPrompt") then removeESP(desc) end
end)

-- 4. BUCLE DE RENDERIZADO
_G.OUTCOME_ESP_LOOP = RunService.RenderStepped:Connect(function()
    for instance, data in pairs(espObjects) do
        local draw = data.draw
        
        if not Config[data.category] then
            draw.Visible = false
            continue
        end
        
        local targetPosition = nil
        
        if instance:IsA("ProximityPrompt") then
            local parent = instance.Parent
            if parent then
                if parent:IsA("Attachment") then targetPosition = parent.WorldPosition
                elseif parent:IsA("BasePart") then targetPosition = parent.Position
                elseif parent:IsA("Model") and parent.PrimaryPart then targetPosition = parent.PrimaryPart.Position
                end
            end
        elseif instance:IsA("Model") then
            local p = instance.PrimaryPart or instance:FindFirstChild("HumanoidRootPart") or instance:FindFirstChild("Head") or instance:FindFirstChildWhichIsA("BasePart", true)
            if p then targetPosition = p.Position end
        elseif instance:IsA("BasePart") then
            targetPosition = instance.Position
        end
        
        if targetPosition then
            local vector, onScreen = Camera:WorldToViewportPoint(targetPosition)
            if onScreen then
                local distance = math.floor((Camera.CFrame.Position - targetPosition).Magnitude)
                draw.Position = Vector2.new(vector.X, vector.Y)
                draw.Text = string.format("%s [%dm]", data.name, distance)
                draw.Color = data.color
                draw.Visible = true
            else
                draw.Visible = false
            end
        else
            draw.Visible = false
        end
    end
end)

-- 5. BUCLE DE ESTADÍSTICAS INFINITAS
local playerStatsFolder = ReplicatedStorage:FindFirstChild("PlayerInfo")
if playerStatsFolder then
    playerStatsFolder = playerStatsFolder:FindFirstChild("Stats")
    if playerStatsFolder then
        playerStatsFolder = playerStatsFolder:FindFirstChild(LocalPlayer.Name)
    end
end

_G.OUTCOME_STATS_LOOP = RunService.Heartbeat:Connect(function()
    if Config.infStats and playerStatsFolder then
        local stamina = playerStatsFolder:FindFirstChild("Stamina")
        local hunger = playerStatsFolder:FindFirstChild("Hunger")
        local thirst = playerStatsFolder:FindFirstChild("Thirst")
        
        if stamina and stamina:IsA("IntValue") then stamina.Value = 100 end
        if hunger and hunger:IsA("IntValue") then hunger.Value = 100 end
        if thirst and thirst:IsA("IntValue") then thirst.Value = 100 end
    end
end)

-- 6. INTERFAZ GRÁFICA
local function buildMenu()
    if typeof(software) == "table" and software.gui then
        local window = software.gui.add_window("OUTCOME PRO", 300, 250)
        local tab = window:add_tab("Hacks")
        tab:add_toggle("Jugadores", Config.players, function(s) Config.players = s end)
        tab:add_toggle("Monstruos", Config.monsters, function(s) Config.monsters = s end)
        tab:add_toggle("Loot/Items", Config.items, function(s) Config.items = s end)
        tab:add_toggle("Estamina/Hambre Infinita", Config.infStats, function(s) Config.infStats = s end)
        software.gui.show()
    else
        local ScreenGui = Instance.new("ScreenGui")
        ScreenGui.Name = "OUTCOME_Menu_PRO"
        ScreenGui.ResetOnSpawn = false
        local core = game:GetService("CoreGui")
        ScreenGui.Parent = core:FindFirstChild("RobloxGui") or core
        
        local Frame = Instance.new("Frame", ScreenGui)
        Frame.Size = UDim2.new(0, 220, 0, 180)
        Frame.Position = UDim2.new(0, 50, 0, 50)
        Frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
        Frame.BorderSizePixel = 2
        Frame.BorderColor3 = Color3.fromRGB(200, 0, 0)
        Frame.Active = true
        Frame.Draggable = true
        
        local Title = Instance.new("TextLabel", Frame)
        Title.Size = UDim2.new(1, 0, 0, 30)
        Title.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        Title.TextColor3 = Color3.fromRGB(255, 255, 255)
        Title.Text = "swag script"
        Title.Font = Enum.Font.Code
        Title.TextSize = 16
        Title.BorderSizePixel = 0
        
        local function createToggle(name, yPos, configKey)
            local btn = Instance.new("TextButton", Frame)
            btn.Size = UDim2.new(1, -20, 0, 25)
            btn.Position = UDim2.new(0, 10, 0, yPos)
            btn.BackgroundColor3 = Config[configKey] and Color3.fromRGB(0, 150, 0) or Color3.fromRGB(150, 0, 0)
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.Text = name .. " [" .. (Config[configKey] and "ON" or "OFF") .. "]"
            btn.Font = Enum.Font.Code
            btn.TextSize = 14
            
            btn.MouseButton1Click:Connect(function()
                Config[configKey] = not Config[configKey]
                btn.BackgroundColor3 = Config[configKey] and Color3.fromRGB(0, 150, 0) or Color3.fromRGB(150, 0, 0)
                btn.Text = name .. " [" .. (Config[configKey] and "ON" or "OFF") .. "]"
            end)
        end
        
        createToggle("Jugadores ESP", 40, "players")
        createToggle("Monstruos ESP", 70, "monsters")
        createToggle("Objetos ESP", 100, "items")
        createToggle("Estamina/Hambre Inf", 130, "infStats")
        
        local CloseBtn = Instance.new("TextButton", Frame)
        CloseBtn.Size = UDim2.new(0, 20, 0, 20)
        CloseBtn.Position = UDim2.new(1, -25, 0, 5)
        CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
        CloseBtn.Text = "X"
        CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        CloseBtn.MouseButton1Click:Connect(function()
            ScreenGui:Destroy()
        end)
    end
end

buildMenu()
print("OUTCOME PRO cargado. (Limpieza ejecutada, Stats parcheadas)")