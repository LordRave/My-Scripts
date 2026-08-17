pcall(function() if Library then Library:Unload() end end)
task.wait(0.2)

local repo = 'https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/'
local Library = loadstring(game:HttpGet(repo .. 'Library.lua'))()
local ThemeManager = loadstring(game:HttpGet(repo .. 'addons/ThemeManager.lua'))()
local SaveManager = loadstring(game:HttpGet(repo .. 'addons/SaveManager.lua'))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

local OriginalLighting = {
    FogEnd = Lighting.FogEnd,
    Ambient = Lighting.Ambient,
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime
}

local Window = Library:CreateWindow({
    Title = 'The Rake Remastered RaveHub!',
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.2
})

local Tabs = {
    Player = Window:AddTab('Player'),
    GameInfo = Window:AddTab('Game Info'),
    Notifs = Window:AddTab('Notifs & Visuals'),
    Troll = Window:AddTab('Troll Mods'),
    ['UI Settings'] = Window:AddTab('UI Settings'),
}

local PlayerESPGroup = Tabs.Notifs:AddLeftGroupbox('Player ESP')
local RakeESPGroup = Tabs.Notifs:AddRightGroupbox('Rake ESP')
local ItemsESPGroup = Tabs.Notifs:AddLeftGroupbox('Items ESP')

PlayerESPGroup:AddToggle('PlayerESP', {Text = 'Player ESP', Default = false})
RakeESPGroup:AddToggle('RakeESP', {Text = 'Rake ESP', Default = false})
ItemsESPGroup:AddToggle('FlareGunESP', {Text = 'Flare Gun ESP', Default = false})
ItemsESPGroup:AddToggle('ScrapESP', {Text = 'Scrap ESP', Default = false})
ItemsESPGroup:AddToggle('SupplyCrateESP', {Text = 'Supply Crate ESP', Default = false})
ItemsESPGroup:AddToggle('LocationsESP', {Text = 'Locations ESP (SafeHouse etc)', Default = false})

local ESPFolder = Instance.new("Folder")
ESPFolder.Name = "TheRakeESP"
local success, err = pcall(function() ESPFolder.Parent = CoreGui end)
if not success then ESPFolder.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local ESPObjects = {}
local Connections = {}

local CachedPrompts = {}
for _, v in ipairs(Workspace:GetDescendants()) do
    if v:IsA("ProximityPrompt") then table.insert(CachedPrompts, v) end
end
table.insert(Connections, Workspace.DescendantAdded:Connect(function(desc)
    if desc:IsA("ProximityPrompt") then table.insert(CachedPrompts, desc) end
end))

local function createBillboard(name, color, textOffset)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = name
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.new(0, 100, 0, 40)
    billboard.StudsOffset = textOffset or Vector3.new(0, 2, 0)
    
    local textLabel = Instance.new("TextLabel")
    textLabel.Parent = billboard
    textLabel.BackgroundTransparency = 1
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.Font = Enum.Font.Code
    textLabel.TextSize = 14
    textLabel.TextColor3 = color
    textLabel.TextStrokeTransparency = 0
    textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    
    return billboard, textLabel
end

local function createHighlight(name, color)
    local highlight = Instance.new("Highlight")
    highlight.Name = name
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = 0.8
    highlight.OutlineTransparency = 0.2
    return highlight
end

RunService:BindToRenderStep("RaveHub_ESP", Enum.RenderPriority.Camera.Value, function()
    pcall(function()
        local pEspOn = Toggles.PlayerESP.Value
        local rEspOn = Toggles.RakeESP.Value
        local fEspOn = Toggles.FlareGunESP.Value
        local sEspOn = Toggles.ScrapESP.Value
        local cEspOn = Toggles.SupplyCrateESP.Value
        local lEspOn = Toggles.LocationsESP.Value

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local char = player.Character
                if char and char:FindFirstChild("Head") and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Humanoid") then
                    local head = char.Head
                    local humanoid = char.Humanoid
                    local isDead = false
                    if player:FindFirstChild("Dead") and player.Dead.Value == true then isDead = true end
                    if char:FindFirstChild("Downed") and char.Downed.Value == true then isDead = true end
                    local espId = "Player_" .. player.Name
                    local espData = ESPObjects[espId]
                    
                    if pEspOn then
                        if not espData then
                            local bb, lbl = createBillboard(espId, Color3.new(0, 1, 0))
                            local hl = createHighlight(espId, Color3.new(0, 1, 0))
                            local bgBar = Instance.new("Frame")
                            bgBar.Parent = bb
                            bgBar.Size = UDim2.new(0, 40, 0, 4)
                            bgBar.Position = UDim2.new(0.5, -20, 1, 0)
                            bgBar.BackgroundColor3 = Color3.new(1, 0, 0)
                            bgBar.BorderSizePixel = 1
                            local healthBar = Instance.new("Frame")
                            healthBar.Parent = bgBar
                            healthBar.Size = UDim2.new(1, 0, 1, 0)
                            healthBar.BackgroundColor3 = Color3.new(0, 1, 0)
                            healthBar.BorderSizePixel = 0
                            bb.Parent = ESPFolder
                            hl.Parent = ESPFolder
                            ESPObjects[espId] = {Billboard = bb, Label = lbl, Highlight = hl, Adornee = head, Char = char, HealthBar = healthBar}
                            espData = ESPObjects[espId]
                        end
                        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                            local dist = math.floor((LocalPlayer.Character.HumanoidRootPart.Position - head.Position).Magnitude)
                            local hpPercent = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
                            local color = Color3.new(0, 1, 0)
                            if isDead then color = Color3.new(1, 0, 0) end
                            espData.Label.TextColor3 = color
                            espData.Highlight.FillColor = color
                            espData.Highlight.OutlineColor = color
                            espData.Label.Text = string.format("%s [%d]\n[ %d studs ]", player.Name, humanoid.Health, dist)
                            espData.HealthBar.Size = UDim2.new(hpPercent, 0, 1, 0)
                            espData.Billboard.Adornee = head
                            espData.Highlight.Adornee = char
                            espData.Billboard.Enabled = true
                            espData.Highlight.Enabled = true
                        end
                    else
                        if espData then
                            espData.Billboard.Enabled = false
                            espData.Highlight.Enabled = false
                        end
                    end
                else
                    local espId = "Player_" .. player.Name
                    if ESPObjects[espId] then
                        ESPObjects[espId].Billboard:Destroy()
                        ESPObjects[espId].Highlight:Destroy()
                        ESPObjects[espId] = nil
                    end
                end
            end
        end
        
        local rake = Workspace:FindFirstChild("Rake")
        local rakeEspId = "Monster_Rake"
        local rakeData = ESPObjects[rakeEspId]
        if rEspOn and rake and rake:FindFirstChild("HumanoidRootPart") then
            if not rakeData then
                local bb, lbl = createBillboard(rakeEspId, Color3.new(1, 0, 0))
                local hl = createHighlight(rakeEspId, Color3.new(1, 0, 0))
                lbl.Font = Enum.Font.Code
                lbl.TextSize = 16
                bb.Parent = ESPFolder
                hl.Parent = ESPFolder
                ESPObjects[rakeEspId] = {Billboard = bb, Label = lbl, Highlight = hl}
                rakeData = ESPObjects[rakeEspId]
            end
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                local dist = math.floor((LocalPlayer.Character.HumanoidRootPart.Position - rake.HumanoidRootPart.Position).Magnitude)
                rakeData.Label.Text = string.format(" RAKE \n[ %d studs ]", dist)
                rakeData.Billboard.Adornee = rake:FindFirstChild("Head") or rake.HumanoidRootPart
                rakeData.Highlight.Adornee = rake
                rakeData.Billboard.Enabled = true
                rakeData.Highlight.Enabled = true
            end
        else
            if rakeData then
                rakeData.Billboard.Enabled = false
                rakeData.Highlight.Enabled = false
            end
        end
        
        local flarePickups = {}
        for _, v in ipairs(Workspace:GetChildren()) do
            if v.Name == "FlareGunPickUp" then table.insert(flarePickups, v) end
        end
        for i, flareGun in ipairs(flarePickups) do
            local fgPart = flareGun:FindFirstChild("FlareGun")
            if fgPart then
                local fgId = "FlareGun_" .. tostring(flareGun) .. i
                local fgData = ESPObjects[fgId]
                if fEspOn then
                    if not fgData then
                        local bb, lbl = createBillboard(fgId, Color3.fromRGB(255, 128, 0))
                        local hl = createHighlight(fgId, Color3.fromRGB(255, 128, 0))
                        bb.Parent = ESPFolder
                        hl.Parent = ESPFolder
                        ESPObjects[fgId] = {Billboard = bb, Label = lbl, Highlight = hl, Item = flareGun}
                        fgData = ESPObjects[fgId]
                    end
                    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                        local dist = math.floor((LocalPlayer.Character.HumanoidRootPart.Position - fgPart.Position).Magnitude)
                        fgData.Label.Text = string.format(" Flare Gun\n[ %d studs ]", dist)
                        fgData.Billboard.Adornee = fgPart
                        fgData.Highlight.Adornee = fgPart
                        fgData.Billboard.Enabled = true
                        fgData.Highlight.Enabled = true
                    end
                else
                    if fgData then fgData.Billboard.Enabled = false; fgData.Highlight.Enabled = false end
                end
            end
        end
        
        local scrapModels = {}
        if Workspace:FindFirstChild("Filter") and Workspace.Filter:FindFirstChild("ScrapSpawns") then
            for _, spawnFolder in ipairs(Workspace.Filter.ScrapSpawns:GetChildren()) do
                for _, scrap in ipairs(spawnFolder:GetChildren()) do
                    if string.match(scrap.Name, "Scrap") then table.insert(scrapModels, scrap) end
                end
            end
        end
        if Workspace:FindFirstChild("Debris") and Workspace.Debris:FindFirstChild("SupplyCrates") then
            for _, crate in ipairs(Workspace.Debris.SupplyCrates:GetChildren()) do
                local iparts = crate:FindFirstChild("InsideParts")
                if iparts then
                    for _, scrap in ipairs(iparts:GetChildren()) do
                        if string.match(scrap.Name, "Scrap") then table.insert(scrapModels, scrap) end
                    end
                end
            end
        end
        for i, scrap in ipairs(scrapModels) do
            local mesh = scrap:FindFirstChild("Scrap")
            local levelVal = scrap:FindFirstChild("LevelVal") and scrap.LevelVal.Value or 1
            local pointsVal = scrap:FindFirstChild("PointsVal") and scrap.PointsVal.Value or 0
            if mesh then
                local sId = "Scrap_" .. tostring(scrap)
                local sData = ESPObjects[sId]
                if sEspOn then
                    if not sData then
                        local bb, lbl = createBillboard(sId, Color3.new(1, 1, 1))
                        bb.Parent = ESPFolder
                        ESPObjects[sId] = {Billboard = bb, Label = lbl, Item = scrap}
                        sData = ESPObjects[sId]
                    end
                    local color = Color3.new(1,1,1)
                    if levelVal == 2 then color = Color3.new(0,1,0)
                    elseif levelVal == 3 then color = Color3.new(0,0.5,1)
                    elseif levelVal >= 4 then color = Color3.fromRGB(170, 0, 255) end
                    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                        local dist = math.floor((LocalPlayer.Character.HumanoidRootPart.Position - mesh.Position).Magnitude)
                        sData.Label.TextColor3 = color
                        sData.Label.Text = string.format("Scrap Lv.%d [%dpts]\n[ %d studs ]", levelVal, pointsVal, dist)
                        sData.Billboard.Adornee = mesh
                        sData.Billboard.Enabled = true
                    end
                else
                    if sData then sData.Billboard.Enabled = false end
                end
            end
        end
        
        local crates = {}
        if Workspace:FindFirstChild("Debris") and Workspace.Debris:FindFirstChild("SupplyCrates") then
            for _, crate in ipairs(Workspace.Debris.SupplyCrates:GetChildren()) do
                if string.match(crate.Name, "Box") then table.insert(crates, crate) end
            end
        end
        for i, crate in ipairs(crates) do
            local primary = crate.PrimaryPart or crate:FindFirstChildWhichIsA("BasePart")
            if primary then
                local cId = "Crate_" .. tostring(crate)
                local cData = ESPObjects[cId]
                if cEspOn then
                    if not cData then
                        local bb, lbl = createBillboard(cId, Color3.new(1, 1, 0))
                        bb.Parent = ESPFolder
                        ESPObjects[cId] = {Billboard = bb, Label = lbl, Item = crate}
                        cData = ESPObjects[cId]
                    end
                    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                        local dist = math.floor((LocalPlayer.Character.HumanoidRootPart.Position - primary.Position).Magnitude)
                        cData.Label.Text = string.format(" Supply Crate\n[ %d studs ]", dist)
                        cData.Billboard.Adornee = primary
                        cData.Billboard.Enabled = true
                    end
                else
                    if cData then cData.Billboard.Enabled = false end
                end
            end
        end
        
        local locNames = {"PowerStation", "SafeHouse", "ObservationTower", "Shack", "BaseCamp"}
        local mapFolder = Workspace:FindFirstChild("Map")
        if mapFolder then
            for _, locName in ipairs(locNames) do
                local model = mapFolder:FindFirstChild(locName)
                if model then
                    local part = model:IsA("Model") and model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
                    if part then
                        local lId = "Location_" .. locName
                        local lData = ESPObjects[lId]
                        if lEspOn then
                            if not lData then
                                local bb, lbl = createBillboard(lId, Color3.new(0, 1, 1))
                                bb.Parent = ESPFolder
                                ESPObjects[lId] = {Billboard = bb, Label = lbl, Item = model}
                                lData = ESPObjects[lId]
                            end
                            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                                local dist = math.floor((LocalPlayer.Character.HumanoidRootPart.Position - part.Position).Magnitude)
                                local displayName = locName:gsub("(%u)", " %1"):match("^%s*(.-)$")
                                lData.Label.Text = string.format(" 📍 %s\n[ %d studs ]", displayName, dist)
                                lData.Billboard.Adornee = part
                                lData.Billboard.Enabled = true
                            end
                        else
                            if lData then lData.Billboard.Enabled = false end
                        end
                    end
                end
            end
        end
        
        for id, data in pairs(ESPObjects) do
            if data.Item and not data.Item.Parent then
                data.Billboard:Destroy()
                if data.Highlight then data.Highlight:Destroy() end
                ESPObjects[id] = nil
            end
        end
    end)
end)

local PlayerModsGroup = Tabs.Player:AddLeftGroupbox('Player Mods')
local HitboxGroup = Tabs.Player:AddLeftGroupbox('Hitbox Mods')

local LightingGroup = Tabs.Notifs:AddRightGroupbox('Lighting Mods')

local TrollGroup = Tabs.Troll:AddLeftGroupbox('Troll Features')
TrollGroup:AddToggle('FlingAura', {Text = 'Fling Aura (Spin fast)', Default = false})
TrollGroup:AddToggle('SpamInteract', {Text = 'Spam Crates (Noise Troll)', Default = false})

PlayerModsGroup:AddSlider('WalkSpeed', {Text = 'WalkSpeed', Default = 11, Min = 11, Max = 29, Rounding = 1})
PlayerModsGroup:AddSlider('JumpPower', {Text = 'JumpPower', Default = 50, Min = 50, Max = 100, Rounding = 1})
PlayerModsGroup:AddToggle('FastInteract', {Text = 'Fast Interact (Crates/Scrap)', Default = false})
PlayerModsGroup:AddToggle('NoClip', {Text = 'Noclip (Walk Through Walls)', Default = false})

HitboxGroup:AddToggle('HitboxExtender', {Text = 'Hitbox Extender (Rake)', Default = false})
HitboxGroup:AddSlider('HitboxSize', {Text = 'Hitbox Size', Default = 10, Min = 5, Max = 30, Rounding = 1})

LightingGroup:AddToggle('Fullbright', {Text = 'Fullbright', Default = false})
LightingGroup:AddToggle('NoFog', {Text = 'No Fog', Default = false})

local OriginalHitboxSize = Vector3.new(2, 2, 1)

RunService:BindToRenderStep("RaveHub_PlayerMods", Enum.RenderPriority.Last.Value, function()
    pcall(function()
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") then
            local hum = char.Humanoid
            hum.WalkSpeed = Options.WalkSpeed.Value
            hum.JumpPower = Options.JumpPower.Value
            if hum.UseJumpPower == false then hum.UseJumpPower = true end
            
            if Toggles.NoClip.Value then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
            
            if Toggles.FlingAura and Toggles.FlingAura.Value and char:FindFirstChild("HumanoidRootPart") then
                char.HumanoidRootPart.RotVelocity = Vector3.new(50000, 50000, 50000)
            end
        end
        
        local rake = Workspace:FindFirstChild("Rake")
        if rake and rake:FindFirstChild("HumanoidRootPart") then
            local hrp = rake.HumanoidRootPart
            if Toggles.HitboxExtender.Value then
                hrp.Size = Vector3.new(Options.HitboxSize.Value, Options.HitboxSize.Value, Options.HitboxSize.Value)
                hrp.Transparency = 0.5
                hrp.BrickColor = BrickColor.new("Bright red")
                hrp.Material = Enum.Material.ForceField
                hrp.CanCollide = false
            else
                hrp.Size = OriginalHitboxSize
                hrp.Transparency = 1
            end
        end
        
        if Toggles.Fullbright.Value then
            Lighting.Ambient = Color3.new(1, 1, 1)
            Lighting.Brightness = 2
        else
            Lighting.Ambient = OriginalLighting.Ambient
            Lighting.Brightness = OriginalLighting.Brightness
        end
        
        if Toggles.NoFog.Value then
            Lighting.FogEnd = 999999
        else
            Lighting.FogEnd = OriginalLighting.FogEnd
        end
        
        if Toggles.FastInteract.Value then
            for _, prompt in ipairs(CachedPrompts) do
                if prompt.Parent then prompt.HoldDuration = 0 end
            end
        end
    end)
end)

task.spawn(function()
    while task.wait(0.1) do
        pcall(function()
            if Toggles.SpamInteract and Toggles.SpamInteract.Value then
                for _, prompt in ipairs(CachedPrompts) do
                    if prompt.Parent then
                        pcall(function() fireproximityprompt(prompt, 0) end)
                    end
                end
            end
        end)
    end
end)

local InfoGroup = Tabs.GameInfo:AddLeftGroupbox('Live Stats')
local InfoLabels = {
    GameState = InfoGroup:AddLabel('Game State: '),
    RakeStatus = InfoGroup:AddLabel('Rake Status: '),
    PowerInfo = InfoGroup:AddLabel('Power Info: '),
    ActiveDevices = InfoGroup:AddLabel('Active Devices: '),
    PlayerStats = InfoGroup:AddLabel('Player Stats: '),
    PlayerList = InfoGroup:AddLabel('Player List: ', true)
}

task.spawn(function()
    while task.wait(0.5) do
        pcall(function()
            local isNight = ReplicatedStorage:FindFirstChild("Night") and ReplicatedStorage.Night.Value
            local timer = ReplicatedStorage:FindFirstChild("Timer") and ReplicatedStorage.Timer.Value or 0
            local timeState = isNight and "Night" or "Day"
            InfoLabels.GameState:SetText(string.format("Game State: %s | Timer: %d | Time: %.2f", timeState, timer, Lighting.ClockTime))
            local isRakeDefeated = ReplicatedStorage:FindFirstChild("RakeDefeated") and ReplicatedStorage.RakeDefeated.Value
            local bloodHour = ReplicatedStorage:FindFirstChild("InitiateBloodHour") and ReplicatedStorage.InitiateBloodHour.Value
            local rakeSpawned = Workspace:FindFirstChild("Rake") ~= nil
            InfoLabels.RakeStatus:SetText(string.format("Rake Spawned: %s | Defeated: %s | Blood Hour: %s", tostring(rakeSpawned), tostring(isRakeDefeated), tostring(bloodHour)))
            if ReplicatedStorage:FindFirstChild("PowerValues") then
                local pv = ReplicatedStorage.PowerValues
                local powerLvl = pv:FindFirstChild("PowerLevel") and pv.PowerLevel.Value or 0
                local ppms = pv:FindFirstChild("PPMS") and pv.PPMS.Value or 0
                local stationOn = ReplicatedStorage:FindFirstChild("StationPower") and ReplicatedStorage.StationPower.Value
                InfoLabels.PowerInfo:SetText(string.format("Power: %d | PPMS: %.2f | Station: %s", powerLvl, ppms, stationOn and "ON" or "OFF"))
                local devices = {}
                if pv:FindFirstChild("UsingSHDoor") and pv.UsingSHDoor.Value then table.insert(devices, "SH Door") end
                if pv:FindFirstChild("UsingTowerDoor") and pv.UsingTowerDoor.Value then table.insert(devices, "Tower Door") end
                if pv:FindFirstChild("UsingTowerRadar") and pv.UsingTowerRadar.Value then table.insert(devices, "Radar") end
                if pv:FindFirstChild("UsingTowerLight") and pv.UsingTowerLight.Value then table.insert(devices, "Tower Light") end
                if pv:FindFirstChild("UsingSHLight") and pv.UsingSHLight.Value then table.insert(devices, "SH Light") end
                InfoLabels.ActiveDevices:SetText("Active Devices: " .. (#devices > 0 and table.concat(devices, ", ") or "None"))
            end
            local ls = LocalPlayer:FindFirstChild("leaderstats")
            if ls then
                local points = ls:FindFirstChild("Points") and ls.Points.Value or 0
                local survivals = ls:FindFirstChild("Survivals") and ls.Survivals.Value or 0
                local dist = LocalPlayer:FindFirstChild("DistanceTravelled") and LocalPlayer.DistanceTravelled.Value or 0
                InfoLabels.PlayerStats:SetText(string.format("Points: %d | Survivals: %d | Distance: %d", points, survivals, dist))
            end
            local aliveCount, deadCount = 0, 0
            for _, p in ipairs(Players:GetPlayers()) do
                if p:FindFirstChild("Dead") and p.Dead.Value then deadCount = deadCount + 1 else aliveCount = aliveCount + 1 end
            end
            InfoLabels.PlayerList:SetText(string.format("Players: %d Alive | %d Dead\nTotal: %d", aliveCount, deadCount, #Players:GetPlayers()))
        end)
    end
end)

local NotifsGroup = Tabs.Notifs:AddLeftGroupbox('Notifications')
local VisualsGroup = Tabs.Notifs:AddRightGroupbox('Visual Settings')

NotifsGroup:AddToggle('RakeNotif', {Text = 'Rake Spawns', Default = true})
NotifsGroup:AddToggle('NightNotif', {Text = 'Night Starts', Default = true})
NotifsGroup:AddToggle('BloodNotif', {Text = 'Blood Hour', Default = true})
NotifsGroup:AddToggle('PowerNotif', {Text = 'Power Offline', Default = true})
NotifsGroup:AddToggle('DeathNotif', {Text = 'Player Deaths', Default = true})

VisualsGroup:AddToggle('RemoveBlur', {Text = 'Remove Blur', Default = false})
VisualsGroup:AddToggle('RemoveDepth', {Text = 'Remove DepthOfField', Default = false})
VisualsGroup:AddSlider('BloomIntensity', {Text = 'Bloom Intensity', Default = 1, Min = 0, Max = 5, Rounding = 1})
VisualsGroup:AddSlider('TimeOfDay', {Text = 'Time Override', Default = 12, Min = 0, Max = 24, Rounding = 1})
VisualsGroup:AddToggle('OverrideTime', {Text = 'Enable Time Override', Default = false})

table.insert(Connections, Workspace.ChildAdded:Connect(function(child)
    pcall(function()
        if child.Name == "Rake" and Toggles.RakeNotif.Value then
            Library:Notify("[ALERT] The Rake has spawned!", 5)
        end
    end)
end))

if ReplicatedStorage:FindFirstChild("Night") then
    table.insert(Connections, ReplicatedStorage.Night.Changed:Connect(function(val)
        pcall(function()
            if val and Toggles.NightNotif.Value then
                Library:Notify("[NIGHT] Night has started. Get ready.", 4)
            end
        end)
    end))
end

if ReplicatedStorage:FindFirstChild("InitiateBloodHour") then
    table.insert(Connections, ReplicatedStorage.InitiateBloodHour.Changed:Connect(function(val)
        pcall(function()
            if val and Toggles.BloodNotif.Value then
                Library:Notify("[DANGER] Blood Hour has started!", 6)
            end
        end)
    end))
end

if ReplicatedStorage:FindFirstChild("StationPower") then
    table.insert(Connections, ReplicatedStorage.StationPower.Changed:Connect(function(val)
        pcall(function()
            if not val and Toggles.PowerNotif.Value then
                Library:Notify("[POWER] The power station is offline!", 5)
            end
        end)
    end))
end

for _, p in ipairs(Players:GetPlayers()) do
    table.insert(Connections, p.CharacterAdded:Connect(function(char)
        table.insert(Connections, char:WaitForChild("Humanoid").Died:Connect(function()
            pcall(function()
                if Toggles.DeathNotif.Value then
                    Library:Notify(string.format("[DEATH] Player %s has died.", p.Name), 3)
                end
            end)
        end))
    end))
end

table.insert(Connections, Players.PlayerAdded:Connect(function(p)
    table.insert(Connections, p.CharacterAdded:Connect(function(char)
        table.insert(Connections, char:WaitForChild("Humanoid").Died:Connect(function()
            pcall(function()
                if Toggles.DeathNotif.Value then
                    Library:Notify(string.format("[DEATH] Player %s has died.", p.Name), 3)
                end
            end)
        end))
    end))
end))

RunService:BindToRenderStep("RaveHub_Visuals", Enum.RenderPriority.Camera.Value, function()
    pcall(function()
        for _, child in ipairs(Lighting:GetChildren()) do
            if child:IsA("BlurEffect") then
                child.Enabled = not Toggles.RemoveBlur.Value
            end
        end
        
        local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
        if dof then dof.Enabled = not Toggles.RemoveDepth.Value end
        
        local bloom = Lighting:FindFirstChild("Bloom") or Lighting:FindFirstChildOfClass("BloomEffect")
        if bloom then bloom.Intensity = Options.BloomIntensity.Value end
        
        if Toggles.OverrideTime.Value then
            Lighting.ClockTime = Options.TimeOfDay.Value
        end
    end)
end)

local MenuGroup = Tabs['UI Settings']:AddLeftGroupbox('Menu')
MenuGroup:AddButton('Unload', function() Library:Unload() end)
MenuGroup:AddLabel('Menu bind'):AddKeyPicker('MenuKeybind', { Default = 'RightControl', NoUI = true, Text = 'Menu keybind' })
Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({'PlayerList', 'GameState', 'RakeStatus', 'PowerInfo', 'ActiveDevices', 'PlayerStats', 'MenuKeybind'})
ThemeManager:SetFolder('RaveHub')
SaveManager:SetFolder('RaveHub/Main')
SaveManager:BuildConfigSection(Tabs['UI Settings'])
ThemeManager:CreateThemeManager(Tabs['UI Settings']:AddRightGroupbox('Theme'))

Library:Notify('The Rake Remastered RaveHub! loaded. Press RightControl to toggle menu.', 5)

local function OnUnload()
    RunService:UnbindFromRenderStep("RaveHub_ESP")
    RunService:UnbindFromRenderStep("RaveHub_PlayerMods")
    RunService:UnbindFromRenderStep("RaveHub_Visuals")
    for _, conn in ipairs(Connections) do
        if conn.Disconnect then
            pcall(function() conn:Disconnect() end)
        end
    end
    if ESPFolder and ESPFolder.Parent then ESPFolder:Destroy() end
    print('[RaveHub] Cleanup completed.')
end

if Library.Unloaded then
    Library.Unloaded:Connect(OnUnload)
elseif Library.OnUnload then
    Library.OnUnload(OnUnload)
end
