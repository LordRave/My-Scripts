-- Forgotten Memories - Linoria monitor
-- Features: live status, infinite stamina, local power override,
-- oxygen puzzle helper, Fullbright, animatronic ESP and teleports.

local ENV = getgenv()

if ENV.FM_LINORIA_MONITOR and ENV.FM_LINORIA_MONITOR.Library then
    pcall(function()
        ENV.FM_LINORIA_MONITOR.Running = false
        ENV.FM_LINORIA_MONITOR.Library:Unload()
    end)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local LinoriaRepo = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"
local Library = loadstring(game:HttpGet(LinoriaRepo .. "Library.lua"))()

local State = {
    Library = Library,
    Running = true,
    ESP = {},
    LastError = "None",
}

ENV.FM_LINORIA_MONITOR = State

local Window = Library:CreateWindow({
    Title = "Forgotten Memories | Monitor",
    Center = true,
    AutoShow = true,
    Size = UDim2.fromOffset(700, 570),
    TabPadding = 8,
    MenuFadeTime = 0.2,
})

local Tabs = {
    Monitor = Window:AddTab("Monitor"),
    Features = Window:AddTab("Features / ESP"),
    Teleports = Window:AddTab("Teleports"),
    Settings = Window:AddTab("UI Settings"),
}

local PlayerBox = Tabs.Monitor:AddLeftGroupbox("Player")
local ResourceBox = Tabs.Monitor:AddRightGroupbox("Resources")
local ObjectiveBox = Tabs.Monitor:AddLeftGroupbox("Current Objective")
local SessionBox = Tabs.Monitor:AddRightGroupbox("Session")
local ThreatBox = Tabs.Features:AddLeftGroupbox("Nearest Animatronics")
local FeatureBox = Tabs.Features:AddRightGroupbox("Features")
local AutomationBox = Tabs.Features:AddRightGroupbox("Automation Status")
local ZoneBox = Tabs.Teleports:AddLeftGroupbox("Important Zones")
local OxygenTPBox = Tabs.Teleports:AddRightGroupbox("Oxygen Minigames")
local ControlBox = Tabs.Settings:AddLeftGroupbox("Monitor")
local MenuBox = Tabs.Settings:AddRightGroupbox("Menu")

local Labels = {
    Health = PlayerBox:AddLabel("Health: --"),
    Stamina = PlayerBox:AddLabel("Stamina: --"),
    Position = PlayerBox:AddLabel("Position: --"),
    Flashlight = PlayerBox:AddLabel("Flashlight: --"),
    Hiding = PlayerBox:AddLabel("Hiding: --"),

    ObjectiveTitle = ObjectiveBox:AddLabel("OBJECTIVE"),
    Objective = ObjectiveBox:AddLabel("Waiting...", true),

    Batteries = ResourceBox:AddLabel("Batteries: --"),
    Lives = ResourceBox:AddLabel("Lives: --"),
    Power = ResourceBox:AddLabel("Power: --"),
    Oxygen = ResourceBox:AddLabel("Oxygen: --"),
    Timer = ResourceBox:AddLabel("Timer: --"),
    Night = ResourceBox:AddLabel("Night: --"),

    Players = SessionBox:AddLabel("Players: --"),
    Ping = SessionBox:AddLabel("Ping: --"),
    Status = SessionBox:AddLabel("Status: --"),

    PowerStatus = AutomationBox:AddLabel("Power override: initializing", true),
    OxygenStatus = AutomationBox:AddLabel("Oxygen solver: initializing", true),
}

Labels.Threats = {}
for index = 1, 9 do
    Labels.Threats[index] = ThreatBox:AddLabel(("#%d --"):format(index))
end

FeatureBox:AddToggle("FMInfiniteStamina", {
    Text = "Infinite stamina",
    Default = true,
})

FeatureBox:AddToggle("FMAutoPower", {
    Text = "Local infinite power",
    Default = true,
    Tooltip = "Forces the client power state and displays to 100%.",
})

FeatureBox:AddToggle("FMAutoOxygen", {
    Text = "Auto-solve oxygen puzzles",
    Default = true,
})

FeatureBox:AddToggle("FMFullbright", {
    Text = "Fullbright",
    Default = true,
})

FeatureBox:AddDivider()

FeatureBox:AddToggle("FMAnimatronicESP", {
    Text = "Animatronic ESP",
    Default = true,
})

FeatureBox:AddToggle("FMESPNames", {
    Text = "ESP names and distance",
    Default = true,
})

FeatureBox:AddSlider("FMESPDistance", {
    Text = "ESP max distance",
    Default = 500,
    Min = 25,
    Max = 1500,
    Rounding = 0,
    Suffix = " studs",
})

ControlBox:AddToggle("FMMonitorEnabled", {
    Text = "Live updates",
    Default = true,
})

ControlBox:AddSlider("FMRefreshRate", {
    Text = "Refresh interval",
    Default = 0.5,
    Min = 0.2,
    Max = 2,
    Rounding = 1,
    Suffix = "s",
})

ControlBox:AddToggle("FMShowWatermark", {
    Text = "Status watermark",
    Default = true,
})

MenuBox:AddLabel("Menu keybind"):AddKeyPicker("FMMenuKeybind", {
    Default = "RightShift",
    NoUI = true,
    Text = "Menu keybind",
})

Library.ToggleKeybind = ENV.Options.FMMenuKeybind

MenuBox:AddButton({
    Text = "Unload monitor",
    Func = function()
        State.Running = false
        Library:Unload()
    end,
    DoubleClick = true,
})

local function child(parent, name)
    return parent and parent:FindFirstChild(name)
end

local function getValue(parent, name, fallback)
    local object = child(parent, name)
    if object and object:IsA("ValueBase") then
        local ok, result = pcall(function()
            return object.Value
        end)
        if ok then
            return result
        end
    end
    return fallback
end

local function setValue(parent, name, newValue)
    local object = child(parent, name)
    if object and object:IsA("ValueBase") then
        pcall(function()
            object.Value = newValue
        end)
    end
end

local function getCharacter()
    return LocalPlayer.Character
end

local function getRoot()
    local character = getCharacter()
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function getPosition(object)
    if not object then
        return nil
    end
    if object:IsA("BasePart") then
        return object.Position
    end
    if object:IsA("Model") then
        local ok, result = pcall(function()
            return object:GetPivot().Position
        end)
        if ok then
            return result
        end
    end
    return nil
end

local function getDistance(object)
    local root = getRoot()
    local position = getPosition(object)
    if root and position then
        return (root.Position - position).Magnitude
    end
    return math.huge
end

local function getAnimatronicName(model)
    if model.Name == "AnimatronicBones" then
        local cosmetic = model:FindFirstChild("Cosmetic")
        if cosmetic then
            for _, descendant in ipairs(cosmetic:GetDescendants()) do
                if descendant:IsA("Model") and descendant.Name ~= "Cosmetic" then
                    return descendant.Name
                end
            end
        end
    end
    return model.Name
end

local function isEffectivelyVisible(object)
    while object do
        if object:IsA("GuiObject") and not object.Visible then
            return false
        end
        if object:IsA("LayerCollector") and not object.Enabled then
            return false
        end
        object = object.Parent
    end
    return true
end

local Modules = ReplicatedStorage:FindFirstChild("Modules")
local GameSettings = child(Modules, "GameSettings")
local PlayersData = child(Modules, "PlayersData")
local PlayerConfig = LocalPlayer.PlayerScripts.Client.PlayerConfig

local MovementController = require(PlayerConfig.Controllers.MovementController)
local PowerController = require(PlayerConfig.Controllers.PowerSystemClient)
local VentTaskController = require(PlayerConfig.Systems.VentTaskClient)
local StabilizerController = require(PlayerConfig.Systems.StabilizersClient)

local MovementState
local PowerState

pcall(function()
    MovementState = debug.getupvalues(MovementController.GetStamina)[1]
end)

pcall(function()
    PowerState = debug.getupvalues(PowerController.GetFuseCharge)[1]
end)

State.Movement = MovementController
State.Power = PowerController
State.Vent = VentTaskController
State.Stabilizers = StabilizerController

local Map = workspace:FindFirstChild("Map")
local MapInteractables = Map and Map:FindFirstChild("interactables")
local Builds = Map and Map:FindFirstChild("Builds")
local TaskContainers = MapInteractables and MapInteractables:FindFirstChild("TaskContainers")
local VentTaskObjects = TaskContainers and TaskContainers:GetChildren() or {}

table.sort(VentTaskObjects, function(left, right)
    return (getPosition(left) or Vector3.zero).X < (getPosition(right) or Vector3.zero).X
end)

local Zones = {}

local function addZone(label, object, preferredPart)
    if object then
        Zones[label] = {
            Object = object,
            Part = preferredPart,
        }
    end
end

addZone("Spawn", workspace:FindFirstChild("SpawnLocation"))
addZone("Security Office", Builds and Builds:FindFirstChild("SecurityOffice"))
addZone("Phone / Shift Start", MapInteractables and MapInteractables:FindFirstChild("Phone"))
addZone("Generator", MapInteractables and MapInteractables:FindFirstChild("Generator"))
addZone("Fuse Charger", MapInteractables and MapInteractables:FindFirstChild("FuseBox"))
addZone("FNAF 1 Office", workspace:FindFirstChild("Fnaf1Clock"))
addZone("Task Sheet", MapInteractables and MapInteractables:FindFirstChild("Poster"))
addZone("Service Bell", Builds and Builds:FindFirstChild("Service Bell"))
addZone("Stabilizer Left", MapInteractables and MapInteractables:FindFirstChild("StabilizerLeft"))
addZone("Stabilizer Right", MapInteractables and MapInteractables:FindFirstChild("StabilizerRight"))

for index, object in ipairs(VentTaskObjects) do
    addZone("Vent Puzzle " .. index, object, object:FindFirstChild("CameraPart"))
end

local ZoneNames = {}
for label in pairs(Zones) do
    table.insert(ZoneNames, label)
end
table.sort(ZoneNames)

ZoneBox:AddDropdown("FMTPZone", {
    Text = "Destination",
    Values = ZoneNames,
    Default = 1,
    Multi = false,
})

local function teleportTo(label)
    local zone = Zones[label]
    local root = getRoot()
    if not zone or not root then
        Library:Notify("Destination unavailable", 3)
        return false
    end

    local target = zone.Part or zone.Object
    local position = target and (target:IsA("BasePart") and target.Position or getPosition(target))
    if not position then
        Library:Notify("Destination has no valid position", 3)
        return false
    end

    root.CFrame = CFrame.lookAt(position + Vector3.new(0, 4, 4), position)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    Library:Notify("Teleported to " .. label, 2)
    return true
end

ZoneBox:AddButton({
    Text = "Teleport",
    Func = function()
        teleportTo(ENV.Options.FMTPZone.Value)
    end,
})

ZoneBox:AddButton({ Text = "Security Office", Func = function() teleportTo("Security Office") end })
ZoneBox:AddButton({ Text = "Generator", Func = function() teleportTo("Generator") end })
ZoneBox:AddButton({ Text = "Fuse Charger", Func = function() teleportTo("Fuse Charger") end })
ZoneBox:AddButton({ Text = "Phone / Start", Func = function() teleportTo("Phone / Shift Start") end })

OxygenTPBox:AddButton({ Text = "Stabilizer Left", Func = function() teleportTo("Stabilizer Left") end })
OxygenTPBox:AddButton({ Text = "Stabilizer Right", Func = function() teleportTo("Stabilizer Right") end })

for index = 1, math.min(3, #VentTaskObjects) do
    OxygenTPBox:AddButton({
        Text = "Vent Puzzle " .. index,
        Func = function()
            teleportTo("Vent Puzzle " .. index)
        end,
    })
end

local LightingOriginal = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    GlobalShadows = Lighting.GlobalShadows,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    FogEnd = Lighting.FogEnd,
    Effects = {},
}

for _, effect in ipairs(Lighting:GetChildren()) do
    if effect:IsA("PostEffect") then
        LightingOriginal.Effects[effect] = effect.Enabled
    end
end

local function setFullbright(enabled)
    pcall(function()
        if enabled then
            Lighting.Brightness = 4
            Lighting.ClockTime = 14
            Lighting.GlobalShadows = false
            Lighting.Ambient = Color3.new(1, 1, 1)
            Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
            Lighting.FogEnd = 100000
            for effect in pairs(LightingOriginal.Effects) do
                if effect.Parent then
                    effect.Enabled = false
                end
            end
        else
            Lighting.Brightness = LightingOriginal.Brightness
            Lighting.ClockTime = LightingOriginal.ClockTime
            Lighting.GlobalShadows = LightingOriginal.GlobalShadows
            Lighting.Ambient = LightingOriginal.Ambient
            Lighting.OutdoorAmbient = LightingOriginal.OutdoorAmbient
            Lighting.FogEnd = LightingOriginal.FogEnd
            for effect, originalValue in pairs(LightingOriginal.Effects) do
                if effect.Parent then
                    effect.Enabled = originalValue
                end
            end
        end
    end)
end

ENV.Toggles.FMFullbright:OnChanged(function()
    setFullbright(ENV.Toggles.FMFullbright.Value)
end)

local ESPRoot = Instance.new("Folder")
ESPRoot.Name = "FM_AnimatronicESP"
ESPRoot.Parent = (type(gethui) == "function" and gethui()) or CoreGui
State.ESPRoot = ESPRoot

local function getESPColor(distance)
    if distance <= 20 then
        return Color3.fromRGB(255, 50, 50)
    elseif distance <= 50 then
        return Color3.fromRGB(255, 165, 35)
    end
    return Color3.fromRGB(40, 200, 255)
end

local function removeESP(model)
    local entry = State.ESP[model]
    if entry then
        pcall(function() entry.Highlight:Destroy() end)
        pcall(function() entry.Billboard:Destroy() end)
        State.ESP[model] = nil
    end
end

local function ensureESP(model)
    local adornee = model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart", true)

    if not adornee then
        return nil
    end

    local current = State.ESP[model]
    if current and current.Adornee == adornee then
        return current
    end
    if current then
        removeESP(model)
    end

    local highlight = Instance.new("Highlight")
    highlight.Adornee = model
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 0.78
    highlight.Parent = ESPRoot

    local billboard = Instance.new("BillboardGui")
    billboard.Adornee = adornee
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.fromOffset(220, 45)
    billboard.StudsOffset = Vector3.new(0, 4, 0)
    billboard.Parent = ESPRoot

    local text = Instance.new("TextLabel")
    text.BackgroundTransparency = 1
    text.Size = UDim2.fromScale(1, 1)
    text.Font = Enum.Font.Code
    text.TextSize = 15
    text.TextStrokeTransparency = 0
    text.TextWrapped = true
    text.Parent = billboard

    local entry = {
        Highlight = highlight,
        Billboard = billboard,
        Text = text,
        Adornee = adornee,
    }
    State.ESP[model] = entry
    return entry
end

local function collectAnimatronics()
    local results = {}
    local folder = workspace:FindFirstChild("Animatronics")
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") then
                local distance = getDistance(model)
                if distance < math.huge then
                    table.insert(results, {
                        Model = model,
                        Distance = distance,
                    })
                end
            end
        end
    end

    table.sort(results, function(left, right)
        return left.Distance < right.Distance
    end)
    return results
end

local function updateESP(animatronics)
    local seen = {}
    for _, info in ipairs(animatronics) do
        seen[info.Model] = true
        local entry = ensureESP(info.Model)
        if entry then
            local active = ENV.Toggles.FMAnimatronicESP.Value
                and info.Distance <= ENV.Options.FMESPDistance.Value
            local color = getESPColor(info.Distance)

            entry.Highlight.Enabled = active
            entry.Highlight.FillColor = color
            entry.Highlight.OutlineColor = color
            entry.Billboard.Enabled = active and ENV.Toggles.FMESPNames.Value
            entry.Text.TextColor3 = color
            entry.Text.Text = ("%s\n%.1f studs"):format(
                getAnimatronicName(info.Model),
                info.Distance
            )
        end
    end

    for model in pairs(State.ESP) do
        if not seen[model] or not model:IsDescendantOf(workspace) then
            removeESP(model)
        end
    end
end

local function getObjective()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local tip = child(child(playerGui, "HUD"), "Tip")
    local title = child(tip, "Title")
    local description = child(tip, "Desc")

    local titleText = title and title.Text or "OBJECTIVE"
    local descriptionText = description and description.Text or "No active objective"
    if description and not isEffectivelyVisible(description) then
        descriptionText = "No visible objective"
    end
    return titleText, descriptionText
end

local function applyLocalPowerOverride()
    if not ENV.Toggles.FMAutoPower.Value then
        return
    end

    if PowerState then
        PowerState.fuseCharge = 100
        PowerState.hasFuse = true
        PowerState.isPowerOn = true
    end
    setValue(GameSettings, "POWER", 100)

    pcall(function()
        local television = MapInteractables and MapInteractables:FindFirstChild("Flatscreentv")
        local plane = television and child(child(television, "Screen"), "Plane")
        local onScreen = plane and child(plane, "On")
        local offScreen = plane and child(plane, "Off")

        if onScreen then
            onScreen.Enabled = true
            local percentage = onScreen:FindFirstChild("Percentage")
            if percentage then
                percentage.Text = "100%"
            end
        end
        if offScreen then
            offScreen.Enabled = false
        end

        local monitors = MapInteractables and MapInteractables:FindFirstChild("Monitors")
        if monitors then
            for _, object in ipairs(monitors:GetDescendants()) do
                if object:IsA("TextLabel") and object.Text == "[NO POWER]" then
                    object.Visible = false
                end
            end
        end
    end)
end

local function solveOxygenPuzzles()
    if not ENV.Toggles.FMAutoOxygen.Value then
        return "disabled"
    end

    setValue(GameSettings, "OXYGEN", 100)

    if VentTaskController:IsInTask() then
        pcall(function()
            VentTaskController:CompleteTask()
        end)
        return "vent task completed"
    end

    local solved = false
    pcall(function()
        if StabilizerController.IsInteracting then
            StabilizerController.Stability = 100
            StabilizerController.IsCritical = false
            StabilizerController.IsComplete = true
            solved = true
        end

        for _, stabilizerState in pairs(StabilizerController:GetAllStates()) do
            if type(stabilizerState) == "table"
                and (stabilizerState.IsCritical
                    or (stabilizerState.Stability and stabilizerState.Stability < 100)) then
                stabilizerState.Stability = 100
                stabilizerState.IsCritical = false
                stabilizerState.IsComplete = true
                pcall(function()
                    StabilizerController:Stop(stabilizerState)
                end)
                solved = true
            end
        end
    end)

    return solved and "stabilizer completed" or "monitoring puzzles"
end

Library:GiveSignal(RunService.Heartbeat:Connect(function()
    if not State.Running then
        return
    end

    if ENV.Toggles.FMInfiniteStamina.Value and MovementState then
        MovementState.stamina = MovementController:GetMaxStamina()
        MovementState.lastSprintTime = time()
    end

    applyLocalPowerOverride()
    if ENV.Toggles.FMAutoOxygen.Value then
        setValue(GameSettings, "OXYGEN", 100)
    end
end))

local function updateMonitor()
    local character = getCharacter()
    local root = getRoot()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local properties = child(character, "Properties")
    local data = PlayersData and child(PlayersData, LocalPlayer.Name .. " Data")

    local stamina, maxStamina = "--", "--"
    pcall(function()
        stamina = math.floor(MovementController:GetStamina() + 0.5)
        maxStamina = math.floor(MovementController:GetMaxStamina() + 0.5)
    end)

    Labels.Health:SetText(("Health: %s / %s"):format(
        tostring(humanoid and math.floor(humanoid.Health + 0.5) or "--"),
        tostring(humanoid and math.floor(humanoid.MaxHealth + 0.5) or "--")
    ))
    Labels.Stamina:SetText(("Stamina: %s / %s%s"):format(
        tostring(stamina),
        tostring(maxStamina),
        ENV.Toggles.FMInfiniteStamina.Value and " [INFINITE]" or ""
    ))

    if root then
        Labels.Position:SetText(("Position: %.0f, %.0f, %.0f"):format(
            root.Position.X,
            root.Position.Y,
            root.Position.Z
        ))
    else
        Labels.Position:SetText("Position: unavailable")
    end

    Labels.Flashlight:SetText(("Flashlight: %s (%s)"):format(
        tostring(character and character:GetAttribute("EquippedFlashlight") or "None"),
        character and character:GetAttribute("FlashlightOn") and "ON" or "OFF"
    ))
    Labels.Hiding:SetText("Hiding: " .. tostring(getValue(properties, "Hiding", false)))

    Labels.Batteries:SetText(("Batteries: %s / %s"):format(
        tostring(getValue(data, "Batteries", "--")),
        tostring(getValue(data, "MaxBatteries", "--"))
    ))
    Labels.Lives:SetText("Lives: " .. tostring(getValue(data, "Lives", "--")))
    Labels.Power:SetText("Power: " .. tostring(getValue(GameSettings, "POWER", "--")))
    Labels.Oxygen:SetText("Oxygen: " .. tostring(getValue(GameSettings, "OXYGEN", "--")))
    Labels.Timer:SetText("Timer: " .. tostring(getValue(GameSettings, "TIMER", "--")))
    Labels.Night:SetText("Night: " .. tostring(getValue(GameSettings, "NIGHT", "--")))

    Labels.Players:SetText("Players: " .. #Players:GetPlayers())
    local ping = "--"
    pcall(function()
        ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5) .. " ms"
    end)
    Labels.Ping:SetText("Ping: " .. ping)
    Labels.Status:SetText("Status: " .. (
        getValue(GameSettings, "IN PROGRESS", false) and "in progress" or "idle"
    ))

    local objectiveTitle, objectiveText = getObjective()
    Labels.ObjectiveTitle:SetText(objectiveTitle)
    Labels.Objective:SetText(objectiveText)

    local animatronics = collectAnimatronics()
    for index, label in ipairs(Labels.Threats) do
        local info = animatronics[index]
        if info then
            label:SetText(("#%d %s - %.1f studs"):format(
                index,
                getAnimatronicName(info.Model),
                info.Distance
            ))
        else
            label:SetText(("#%d --"):format(index))
        end
    end
    updateESP(animatronics)

    applyLocalPowerOverride()
    Labels.PowerStatus:SetText("Power override: local 100% (server validates fuse)")
    Labels.OxygenStatus:SetText("Oxygen solver: " .. solveOxygenPuzzles())

    if ENV.Toggles.FMShowWatermark.Value then
        Library:SetWatermarkVisibility(true)
        Library:SetWatermark(("FM | HP %s | STA %s | PWR %s | O2 %s | BAT %s | %s"):format(
            tostring(humanoid and math.floor(humanoid.Health + 0.5) or "--"),
            tostring(stamina),
            tostring(getValue(GameSettings, "POWER", "--")),
            tostring(getValue(GameSettings, "OXYGEN", "--")),
            tostring(getValue(data, "Batteries", "--")),
            tostring(ping)
        ))
    else
        Library:SetWatermarkVisibility(false)
    end
end

Library:OnUnload(function()
    State.Running = false
    setFullbright(false)
    for model in pairs(State.ESP) do
        removeESP(model)
    end
    pcall(function()
        ESPRoot:Destroy()
    end)
    Library.Unloaded = true
    if ENV.FM_LINORIA_MONITOR == State then
        ENV.FM_LINORIA_MONITOR = nil
    end
    print("[FM Monitor] Unloaded")
end)

task.spawn(function()
    while State.Running and not Library.Unloaded do
        if ENV.Toggles.FMMonitorEnabled.Value then
            local ok, errorMessage = pcall(updateMonitor)
            if not ok then
                State.LastError = tostring(errorMessage)
                Labels.Status:SetText("Error: " .. State.LastError)
            end
        end
        task.wait(ENV.Options.FMRefreshRate.Value)
    end
end)

ENV.Toggles.FMFullbright:SetValue(true)
ENV.Toggles.FMAutoPower:SetValue(true)
ENV.Toggles.FMAutoOxygen:SetValue(true)
ENV.Toggles.FMInfiniteStamina:SetValue(true)
ENV.Toggles.FMAnimatronicESP:SetValue(true)

setFullbright(true)
applyLocalPowerOverride()
updateMonitor()

Library:Notify("Forgotten Memories monitor loaded", 5)
print("[FM Monitor] Loaded successfully | zones=" .. tostring(#ZoneNames))
