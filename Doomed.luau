if not game:IsLoaded() then
    game.Loaded:Wait()
end

local ENV = getgenv()

-- Limpia una ejecución anterior
if ENV.PotassiumPoppyHub and ENV.PotassiumPoppyHub.Cleanup then
    pcall(ENV.PotassiumPoppyHub.Cleanup)
end

if ENV.Library and ENV.Library.Unload then
    pcall(function()
        ENV.Library:Unload()
    end)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Library = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"
))()

local ThemeManager = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/ThemeManager.lua"
))()

local SaveManager = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/SaveManager.lua"
))()

ENV.Library = Library

-- Linoria expone estas tablas globalmente
local Toggles = ENV.Toggles
local Options = ENV.Options

local Hub = {
    Connections = {},
    ESP = {},
    NoclipParts = {},
    PromptDurations = {},
    EffectStates = {},
    OverlayStates = {},
    AtmosphereStates = {}
}

ENV.PotassiumPoppyHub = Hub

local State = {
    MonsterESP = true,
    PlayerESP = true,
    PuzzleESP = true,
    ItemESP = true,
    InteractableESP = false,

    Names = true,
    Distance = true,
    Health = true,
    MaxDistance = 1500,

    Fullbright = false,
    NoFog = false,
    NoEffects = false,
    NoOverlays = false,

    FOVEnabled = false,
    FOV = Camera and Camera.FieldOfView or 70,

    WalkEnabled = false,
    WalkSpeed = 24,

    JumpEnabled = false,
    JumpPower = 65,

    InfiniteJump = false,
    Noclip = false,
    InstantPrompts = false,

    Colors = {
        Monster = Color3.fromRGB(255, 70, 70),
        Player = Color3.fromRGB(65, 170, 255),
        Puzzle = Color3.fromRGB(255, 205, 55),
        Item = Color3.fromRGB(90, 255, 130),
        Interactable = Color3.fromRGB(210, 120, 255)
    }
}

local OriginalLighting = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    GlobalShadows = Lighting.GlobalShadows,
    ExposureCompensation = Lighting.ExposureCompensation,
    FogStart = Lighting.FogStart,
    FogEnd = Lighting.FogEnd,
    FogColor = Lighting.FogColor
}

local OriginalFOV = Camera and Camera.FieldOfView or 70
local OriginalHumanoid
local Unloaded = false

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(Hub.Connections, connection)
    return connection
end

local function getCharacter()
    return LocalPlayer.Character
end

local function getHumanoid()
    local character = getCharacter()
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function rememberHumanoid(humanoid)
    if not humanoid then
        return
    end

    OriginalHumanoid = {
        Object = humanoid,
        WalkSpeed = humanoid.WalkSpeed,
        JumpPower = humanoid.JumpPower,
        JumpHeight = humanoid.JumpHeight
    }
end

rememberHumanoid(getHumanoid())

-- Contenedor del ESP
local GUIParent = CoreGui

pcall(function()
    if type(gethui) == "function" then
        GUIParent = gethui()
    end
end)

local ESPGui = Instance.new("ScreenGui")
ESPGui.Name = "PotassiumPoppyESP"
ESPGui.ResetOnSpawn = false
ESPGui.IgnoreGuiInset = true
ESPGui.Parent = GUIParent

Hub.ESPGui = ESPGui

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function contains(text, words)
    text = lower(text)

    for _, word in ipairs(words) do
        if string.find(text, word, 1, true) then
            return true
        end
    end

    return false
end

local function getPart(instance)
    if not instance or not instance.Parent then
        return nil
    end

    if instance:IsA("BasePart") then
        return instance
    end

    if instance:IsA("Model") then
        return instance.PrimaryPart
            or instance:FindFirstChild("HumanoidRootPart")
            or instance:FindFirstChild("Head")
            or instance:FindFirstChildWhichIsA("BasePart", true)
    end

    return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function getAdornee(instance)
    if not instance or not instance.Parent then
        return nil
    end

    if instance:IsA("Model") or instance:IsA("BasePart") then
        return instance
    end

    return instance:FindFirstChildWhichIsA("Model", true)
        or instance:FindFirstChildWhichIsA("BasePart", true)
end

local function getNearestModel(instance)
    local current = instance

    while current and current ~= Workspace do
        if current:IsA("Model") then
            return current
        end

        current = current.Parent
    end

    return instance.Parent
end

local monsterNames = {
    huggywuggy = true,
    mommylonglegs = true,
    sleepingboxy = true,
    boxyboo = true,
    yarnaby = true
}

local itemWords = {
    "key",
    "fuse",
    "battery",
    "tape",
    "gear",
    "card",
    "grabpack",
    "grab pack"
}

local function ignoredMonster(model)
    local path = lower(model:GetFullName())

    return string.find(path, ".jumpscares.", 1, true)
        or string.find(path, ".storeanimations.", 1, true)
        or string.find(path, ".collisions.", 1, true)
end

local function isMonster(model)
    local name = lower(model.Name)

    return model:FindFirstChildOfClass("Humanoid") ~= nil
        or monsterNames[name]
        or string.sub(name, 1, 7) == "yarnaby"
        or string.sub(name, 1, 9) == "minihuggy"
end

local function addTarget(wanted, target, category, displayName, adorn)
    if not target or not target.Parent or wanted[target] then
        return
    end

    adorn = adorn or getAdornee(target)

    local part = getPart(adorn) or getPart(target)

    if not adorn or not part then
        return
    end

    wanted[target] = {
        Category = category,
        Name = displayName or target.Name,
        Adornee = adorn,
        Part = part
    }
end

local function collectTargets()
    local wanted = {}

    -- Jugadores
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            addTarget(
                wanted,
                player.Character,
                "Player",
                player.DisplayName .. " (@" .. player.Name .. ")",
                player.Character
            )
        end
    end

    -- Monstruos y NPC
    for _, model in ipairs(Workspace:GetDescendants()) do
        if model:IsA("Model")
            and not Players:GetPlayerFromCharacter(model)
            and not ignoredMonster(model)
            and isMonster(model)
        then
            local nestedMonster = false
            local ancestor = model.Parent

            while ancestor and ancestor ~= Workspace do
                if ancestor:IsA("Model")
                    and isMonster(ancestor)
                    and not ignoredMonster(ancestor)
                then
                    nestedMonster = true
                    break
                end

                ancestor = ancestor.Parent
            end

            if not nestedMonster then
                addTarget(wanted, model, "Monster", model.Name, model)
            end
        end
    end

    -- Tags especiales de monstruos
    for _, tag in ipairs({"YarnabyMonster", "Monster", "Enemy"}) do
        for _, object in ipairs(CollectionService:GetTagged(tag)) do
            if object:IsDescendantOf(Workspace) and not ignoredMonster(object) then
                addTarget(
                    wanted,
                    object,
                    "Monster",
                    object.Name,
                    getAdornee(object)
                )
            end
        end
    end

    -- Estaciones de puzzles
    local puzzleStations = Workspace:FindFirstChild("PuzzleStations")

    if puzzleStations then
        for _, station in ipairs(puzzleStations:GetChildren()) do
            addTarget(
                wanted,
                station,
                "Puzzle",
                station.Name,
                getAdornee(station)
            )
        end
    end

    -- Generadores
    local generators = Workspace:FindFirstChild("Generators")

    if generators then
        for index, generator in ipairs(generators:GetChildren()) do
            addTarget(
                wanted,
                generator,
                "Puzzle",
                "Generator " .. index,
                getAdornee(generator)
            )
        end
    end

    -- Otros objetivos conocidos
    for _, name in ipairs({
        "FixEnergy",
        "ExitDoor",
        "SlamDoorPower",
        "MommyToy"
    }) do
        local target = Workspace:FindFirstChild(name)

        if target then
            addTarget(
                wanted,
                target,
                "Puzzle",
                name,
                getAdornee(target)
            )
        end
    end

    -- Depositadores de juguetes
    local depositors = Workspace:FindFirstChild("ToyDepositors")

    if depositors then
        for index, depositor in ipairs(depositors:GetChildren()) do
            addTarget(
                wanted,
                depositor,
                "Puzzle",
                "Toy Depositor " .. index,
                getAdornee(depositor)
            )
        end
    end

    -- Objetos e interactuables
    for _, object in ipairs(Workspace:GetDescendants()) do
        if object:IsA("ProximityPrompt") or object:IsA("ClickDetector") then
            local owner = getNearestModel(object)
            local path = lower(object:GetFullName())

            local objective = string.find(path, "puzzlestations", 1, true)
                or string.find(path, "generators", 1, true)
                or string.find(path, "fixenergy", 1, true)
                or string.find(path, "toydepositors", 1, true)
                or string.find(path, "exitdoor", 1, true)
                or string.find(path, "slamdoorpower", 1, true)

            if not objective and owner then
                local action = owner.Name

                if object:IsA("ProximityPrompt") then
                    action = object.ActionText ~= "" and object.ActionText
                        or object.ObjectText ~= "" and object.ObjectText
                        or owner.Name
                end

                if contains(owner.Name .. " " .. path, itemWords) then
                    addTarget(
                        wanted,
                        owner,
                        "Item",
                        owner.Name,
                        getAdornee(owner)
                    )
                else
                    addTarget(
                        wanted,
                        owner,
                        "Interactable",
                        action,
                        getAdornee(owner)
                    )
                end
            end
        elseif object:IsA("Tool") then
            addTarget(
                wanted,
                object,
                "Item",
                object.Name,
                getAdornee(object)
            )
        end
    end

    return wanted
end

local function createESP(target, info)
    local highlight = Instance.new("Highlight")
    highlight.Name = "K_" .. info.Category
    highlight.Adornee = info.Adornee
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 0.72
    highlight.OutlineTransparency = 0
    highlight.Parent = ESPGui

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "K_Label"
    billboard.Adornee = info.Part
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.fromOffset(250, 50)
    billboard.StudsOffset = Vector3.new(0, 3.2, 0)
    billboard.MaxDistance = 100000
    billboard.Parent = ESPGui

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.Code
    label.TextSize = 14
    label.TextStrokeTransparency = 0.2
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextWrapped = true
    label.Parent = billboard

    return {
        Target = target,
        Adornee = info.Adornee,
        Part = info.Part,
        Category = info.Category,
        Name = info.Name,
        Highlight = highlight,
        Billboard = billboard,
        Label = label
    }
end

local function destroyESP(record)
    if record.Highlight then
        record.Highlight:Destroy()
    end

    if record.Billboard then
        record.Billboard:Destroy()
    end
end

local function syncESP()
    local wanted = collectTargets()

    for target, record in pairs(Hub.ESP) do
        local info = wanted[target]

        if not target.Parent
            or not info
            or info.Category ~= record.Category
        then
            destroyESP(record)
            Hub.ESP[target] = nil
        end
    end

    for target, info in pairs(wanted) do
        if not Hub.ESP[target] then
            Hub.ESP[target] = createESP(target, info)
        end
    end
end

local toggleIDs = {
    Monster = "MonsterESP",
    Player = "PlayerESP",
    Puzzle = "PuzzleESP",
    Item = "ItemESP",
    Interactable = "InteractableESP"
}

local colorIDs = {
    Monster = "MonsterColor",
    Player = "PlayerColor",
    Puzzle = "PuzzleColor",
    Item = "ItemColor",
    Interactable = "InteractableColor"
}

local function updateESP()
    local character = getCharacter()
    local root = character and character:FindFirstChild("HumanoidRootPart")

    for target, record in pairs(Hub.ESP) do
        if not target.Parent or not record.Part.Parent then
            destroyESP(record)
            Hub.ESP[target] = nil
        else
            local distance = root
                and (record.Part.Position - root.Position).Magnitude
                or 0

            local enabled = State[record.Category .. "ESP"]
                and distance <= State.MaxDistance

            local color = State.Colors[record.Category]
                or Color3.new(1, 1, 1)

            record.Highlight.Enabled = enabled
            record.Highlight.FillColor = color
            record.Highlight.OutlineColor = color

            record.Billboard.Enabled = enabled
                and (State.Names or State.Distance or State.Health)

            record.Label.TextColor3 = color

            local text = {}

            if State.Names then
                table.insert(text, record.Name)
            end

            if State.Distance then
                table.insert(
                    text,
                    string.format(
                        "[%dm]",
                        math.floor(distance / 3.571 + 0.5)
                    )
                )
            end

            if State.Health and record.Adornee:IsA("Model") then
                local humanoid =
                    record.Adornee:FindFirstChildOfClass("Humanoid")

                if humanoid then
                    table.insert(
                        text,
                        string.format(
                            "HP %d/%d",
                            math.max(0, math.floor(humanoid.Health + 0.5)),
                            math.floor(humanoid.MaxHealth + 0.5)
                        )
                    )
                end
            end

            record.Label.Text = table.concat(text, " ")
        end
    end
end

-- Iluminación

local function applyFullbright()
    Lighting.Brightness = 2.5
    Lighting.ClockTime = 14
    Lighting.Ambient = Color3.fromRGB(255, 255, 255)
    Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
    Lighting.GlobalShadows = false
    Lighting.ExposureCompensation = 0.15
end

local function restoreLighting()
    Lighting.Brightness = OriginalLighting.Brightness
    Lighting.ClockTime = OriginalLighting.ClockTime
    Lighting.Ambient = OriginalLighting.Ambient
    Lighting.OutdoorAmbient = OriginalLighting.OutdoorAmbient
    Lighting.GlobalShadows = OriginalLighting.GlobalShadows
    Lighting.ExposureCompensation =
        OriginalLighting.ExposureCompensation
end

local function applyNoFog()
    Lighting.FogStart = 0
    Lighting.FogEnd = 1000000

    for _, object in ipairs(Lighting:GetChildren()) do
        if object:IsA("Atmosphere") then
            if not Hub.AtmosphereStates[object] then
                Hub.AtmosphereStates[object] = {
                    Density = object.Density,
                    Haze = object.Haze,
                    Glare = object.Glare
                }
            end

            object.Density = 0
            object.Haze = 0
            object.Glare = 0
        end
    end
end

local function restoreFog()
    Lighting.FogStart = OriginalLighting.FogStart
    Lighting.FogEnd = OriginalLighting.FogEnd
    Lighting.FogColor = OriginalLighting.FogColor

    for object, properties in pairs(Hub.AtmosphereStates) do
        if object.Parent then
            object.Density = properties.Density
            object.Haze = properties.Haze
            object.Glare = properties.Glare
        end
    end

    table.clear(Hub.AtmosphereStates)
end

local effectClasses = {
    BloomEffect = true,
    BlurEffect = true,
    ColorCorrectionEffect = true,
    DepthOfFieldEffect = true,
    SunRaysEffect = true
}

local function disableEffects()
    for _, object in ipairs(Lighting:GetChildren()) do
        if effectClasses[object.ClassName] then
            if Hub.EffectStates[object] == nil then
                Hub.EffectStates[object] = object.Enabled
            end

            object.Enabled = false
        end
    end
end

local function restoreEffects()
    for object, enabled in pairs(Hub.EffectStates) do
        if object.Parent then
            object.Enabled = enabled
        end
    end

    table.clear(Hub.EffectStates)
end

local overlayNames = {
    VHS_effect = true,
    CameraEffect = true
}

local function updateOverlays()
    local playerGui =
        LocalPlayer:FindFirstChildOfClass("PlayerGui")

    if not playerGui then
        return
    end

    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and overlayNames[gui.Name] then
            if Hub.OverlayStates[gui] == nil then
                Hub.OverlayStates[gui] = gui.Enabled
            end

            gui.Enabled = not State.NoOverlays
        end
    end
end

local function restoreOverlays()
    for gui, enabled in pairs(Hub.OverlayStates) do
        if gui.Parent then
            gui.Enabled = enabled
        end
    end

    table.clear(Hub.OverlayStates)
end

-- Movimiento

local function restoreMovement()
    local original = OriginalHumanoid

    if original
        and original.Object
        and original.Object.Parent
    then
        original.Object.WalkSpeed = original.WalkSpeed
        original.Object.JumpPower = original.JumpPower
        original.Object.JumpHeight = original.JumpHeight
    end
end

local function restoreNoclip()
    for part, canCollide in pairs(Hub.NoclipParts) do
        if part.Parent then
            part.CanCollide = canCollide
        end
    end

    table.clear(Hub.NoclipParts)
end

local function applyInstantPrompts()
    for _, prompt in ipairs(Workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            if Hub.PromptDurations[prompt] == nil then
                Hub.PromptDurations[prompt] =
                    prompt.HoldDuration
            end

            prompt.HoldDuration = 0
        end
    end
end

local function restorePrompts()
    for prompt, duration in pairs(Hub.PromptDurations) do
        if prompt.Parent then
            prompt.HoldDuration = duration
        end
    end

    table.clear(Hub.PromptDurations)
end

-- Linoria UI

local Window = Library:CreateWindow({
    Title = "Doomed Playtime RaveHub!",
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.2
})

local Tabs = {
    Visuals = Window:AddTab("Visuals"),
    Player = Window:AddTab("Player"),
    Settings = Window:AddTab("UI Settings")
}

local ESPBox = Tabs.Visuals:AddLeftGroupbox("ESP")

ESPBox:AddToggle("MonsterESP", {
    Text = "Monsters",
    Default = true
})

ESPBox:AddToggle("PlayerESP", {
    Text = "Players",
    Default = true
})

ESPBox:AddToggle("PuzzleESP", {
    Text = "Puzzles & Objectives",
    Default = true
})

ESPBox:AddToggle("ItemESP", {
    Text = "Items",
    Default = true
})

ESPBox:AddToggle("InteractableESP", {
    Text = "Other Interactables",
    Default = false
})

ESPBox:AddDivider()

ESPBox:AddToggle("EspNames", {
    Text = "Names",
    Default = true
})

ESPBox:AddToggle("EspDistance", {
    Text = "Distance",
    Default = true
})

ESPBox:AddToggle("EspHealth", {
    Text = "Health",
    Default = true
})

ESPBox:AddSlider("EspMaxDistance", {
    Text = "Max Distance",
    Default = 1500,
    Min = 50,
    Max = 5000,
    Rounding = 0,
    Suffix = " studs"
})

Toggles.MonsterESP:OnChanged(function(value)
    State.MonsterESP = value
end)

Toggles.PlayerESP:OnChanged(function(value)
    State.PlayerESP = value
end)

Toggles.PuzzleESP:OnChanged(function(value)
    State.PuzzleESP = value
end)

Toggles.ItemESP:OnChanged(function(value)
    State.ItemESP = value
end)

Toggles.InteractableESP:OnChanged(function(value)
    State.InteractableESP = value
end)

Toggles.EspNames:OnChanged(function(value)
    State.Names = value
end)

Toggles.EspDistance:OnChanged(function(value)
    State.Distance = value
end)

Toggles.EspHealth:OnChanged(function(value)
    State.Health = value
end)

Options.EspMaxDistance:OnChanged(function(value)
    State.MaxDistance = value
end)

local ColorsBox = Tabs.Visuals:AddLeftGroupbox("Colors")

ColorsBox:AddLabel("Monsters"):AddColorPicker("MonsterColor", {
    Default = State.Colors.Monster,
    Title = "Monsters"
})

ColorsBox:AddLabel("Players"):AddColorPicker("PlayerColor", {
    Default = State.Colors.Player,
    Title = "Players"
})

ColorsBox:AddLabel("Puzzles & Objectives"):AddColorPicker("PuzzleColor", {
    Default = State.Colors.Puzzle,
    Title = "Puzzles"
})

ColorsBox:AddLabel("Items"):AddColorPicker("ItemColor", {
    Default = State.Colors.Item,
    Title = "Items"
})

ColorsBox:AddLabel("Interactables"):AddColorPicker("InteractableColor", {
    Default = State.Colors.Interactable,
    Title = "Interactables"
})

Options.MonsterColor:OnChanged(function(value)
    State.Colors.Monster = value
end)

Options.PlayerColor:OnChanged(function(value)
    State.Colors.Player = value
end)

Options.PuzzleColor:OnChanged(function(value)
    State.Colors.Puzzle = value
end)

Options.ItemColor:OnChanged(function(value)
    State.Colors.Item = value
end)

Options.InteractableColor:OnChanged(function(value)
    State.Colors.Interactable = value
end)

local LightingBox = Tabs.Visuals:AddRightGroupbox("Lighting")

LightingBox:AddToggle("Fullbright", {
    Text = "Fullbright",
    Default = false
})

LightingBox:AddToggle("NoFog", {
    Text = "No Fog",
    Default = false
})

LightingBox:AddToggle("NoEffects", {
    Text = "Disable Post-Processing",
    Default = false
})

LightingBox:AddToggle("NoOverlays", {
    Text = "Hide VHS & Camera Effects",
    Default = false
})

Toggles.Fullbright:OnChanged(function(value)
    State.Fullbright = value

    if value then
        applyFullbright()
    else
        restoreLighting()
    end
end)

Toggles.NoFog:OnChanged(function(value)
    State.NoFog = value

    if value then
        applyNoFog()
    else
        restoreFog()
    end
end)

Toggles.NoEffects:OnChanged(function(value)
    State.NoEffects = value

    if value then
        disableEffects()
    else
        restoreEffects()
    end
end)

Toggles.NoOverlays:OnChanged(function(value)
    State.NoOverlays = value

    if value then
        updateOverlays()
    else
        restoreOverlays()
    end
end)

local CameraBox = Tabs.Visuals:AddRightGroupbox("Camera")

CameraBox:AddToggle("FOVEnabled", {
    Text = "Override FOV",
    Default = false
})

CameraBox:AddSlider("FOVValue", {
    Text = "Field of View",
    Default = math.floor(State.FOV),
    Min = 40,
    Max = 120,
    Rounding = 0
})

Toggles.FOVEnabled:OnChanged(function(value)
    State.FOVEnabled = value

    if not value and Workspace.CurrentCamera then
        Workspace.CurrentCamera.FieldOfView = OriginalFOV
    end
end)

Options.FOVValue:OnChanged(function(value)
    State.FOV = value
end)

local MovementBox = Tabs.Player:AddLeftGroupbox("Movement")

MovementBox:AddToggle("WalkEnabled", {
    Text = "Override WalkSpeed",
    Default = false
})

MovementBox:AddSlider("WalkSpeed", {
    Text = "WalkSpeed",
    Default = 24,
    Min = 8,
    Max = 100,
    Rounding = 0
})

MovementBox:AddToggle("JumpEnabled", {
    Text = "Override Jump",
    Default = false
})

MovementBox:AddSlider("JumpPower", {
    Text = "Jump Power",
    Default = 65,
    Min = 20,
    Max = 150,
    Rounding = 0
})

Toggles.WalkEnabled:OnChanged(function(value)
    State.WalkEnabled = value

    if not value
        and OriginalHumanoid
        and OriginalHumanoid.Object.Parent
    then
        OriginalHumanoid.Object.WalkSpeed = OriginalHumanoid.WalkSpeed
    end
end)

Options.WalkSpeed:OnChanged(function(value)
    State.WalkSpeed = value
end)

Toggles.JumpEnabled:OnChanged(function(value)
    State.JumpEnabled = value

    if not value
        and OriginalHumanoid
        and OriginalHumanoid.Object.Parent
    then
        OriginalHumanoid.Object.JumpPower = OriginalHumanoid.JumpPower
        OriginalHumanoid.Object.JumpHeight = OriginalHumanoid.JumpHeight
    end
end)

Options.JumpPower:OnChanged(function(value)
    State.JumpPower = value
end)

local AbilitiesBox = Tabs.Player:AddRightGroupbox("Abilities")

AbilitiesBox:AddToggle("InfiniteJump", {
    Text = "Infinite Jump",
    Default = false
})

AbilitiesBox:AddToggle("Noclip", {
    Text = "Noclip",
    Default = false
})

AbilitiesBox:AddToggle("InstantPrompts", {
    Text = "Instant Interaction",
    Default = false
})

Toggles.InfiniteJump:OnChanged(function(value)
    State.InfiniteJump = value
end)

Toggles.Noclip:OnChanged(function(value)
    State.Noclip = value

    if not value then
        restoreNoclip()
    end
end)

Toggles.InstantPrompts:OnChanged(function(value)
    State.InstantPrompts = value

    if value then
        applyInstantPrompts()
    else
        restorePrompts()
    end
end)

local InfoBox = Tabs.Player:AddLeftGroupbox("Detected Game")

InfoBox:AddLabel("Main Mode - Night 1", true)
InfoBox:AddLabel("Huggy, Mommy, Boxy & Yarnaby", true)
InfoBox:AddLabel("6 puzzles, 2 generators & 5 depositors", true)

local MenuBox = Tabs.Settings:AddLeftGroupbox("Menu")

MenuBox:AddButton("Unload & Restore Everything", function()
    Library:Unload()
end)

MenuBox:AddLabel("Menu Key"):AddKeyPicker("MenuKeybind", {
    Default = "RightShift",
    NoUI = true,
    Text = "Menu Key"
})

Library.ToggleKeybind = Options.MenuKeybind

-- Temas y configuraciones
pcall(function()
    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)

    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({
        "MenuKeybind"
    })

    ThemeManager:SetFolder("DoomedPlaytimeRaveHub")
    SaveManager:SetFolder("DoomedPlaytimeRaveHub/Configs")
    

    SaveManager:BuildConfigSection(
        Tabs.Settings
    )

    ThemeManager:ApplyToTab(
        Tabs.Settings
    )
end)

-- Eventos

connect(UIS.JumpRequest, function()
    if State.InfiniteJump then
        local humanoid = getHumanoid()

        if humanoid then
            humanoid:ChangeState(
                Enum.HumanoidStateType.Jumping
            )
        end
    end
end)

connect(LocalPlayer.CharacterAdded, function(character)
    local humanoid =
        character:WaitForChild("Humanoid", 10)

    rememberHumanoid(humanoid)
    table.clear(Hub.NoclipParts)
end)

connect(Workspace.DescendantAdded, function(object)
    if State.InstantPrompts
        and object:IsA("ProximityPrompt")
    then
        if Hub.PromptDurations[object] == nil then
            Hub.PromptDurations[object] =
                object.HoldDuration
        end

        object.HoldDuration = 0
    end
end)

local scanClock = 2
local updateClock = 0

connect(RunService.RenderStepped, function(deltaTime)
    scanClock += deltaTime
    updateClock += deltaTime

    if scanClock >= 1.5 then
        scanClock = 0
        syncESP()
    end

    if updateClock >= 0.08 then
        updateClock = 0
        updateESP()
    end
end)

connect(RunService.Stepped, function()
    local character = getCharacter()
    local humanoid = getHumanoid()

    if humanoid then
        if State.WalkEnabled then
            humanoid.WalkSpeed =
                State.WalkSpeed
        end

        if State.JumpEnabled then
            if humanoid.UseJumpPower then
                humanoid.JumpPower =
                    State.JumpPower
            else
                humanoid.JumpHeight =
                    math.max(
                        7.2,
                        State.JumpPower / 7
                    )
            end
        end
    end

    if State.Noclip and character then
        for _, part in ipairs(
            character:GetDescendants()
        ) do
            if part:IsA("BasePart") then
                if Hub.NoclipParts[part] == nil then
                    Hub.NoclipParts[part] =
                        part.CanCollide
                end

                part.CanCollide = false
            end
        end
    end

    Camera = Workspace.CurrentCamera

    if Camera and State.FOVEnabled then
        Camera.FieldOfView = State.FOV
    end

    if State.Fullbright then
        applyFullbright()
    end

    if State.NoFog then
        applyNoFog()
    end

    if State.NoEffects then
        disableEffects()
    end
end)

function Hub.Cleanup()
    if Unloaded then
        return
    end

    Unloaded = true

    for _, connection in ipairs(Hub.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    for _, record in pairs(Hub.ESP) do
        pcall(destroyESP, record)
    end

    table.clear(Hub.ESP)

    restoreLighting()
    restoreFog()
    restoreEffects()
    restoreOverlays()
    restoreMovement()
    restoreNoclip()
    restorePrompts()

    if Workspace.CurrentCamera then
        Workspace.CurrentCamera.FieldOfView =
            OriginalFOV
    end

    if ESPGui then
        ESPGui:Destroy()
    end

    if ENV.PotassiumPoppyHub == Hub then
        ENV.PotassiumPoppyHub = nil
    end
end

Library:OnUnload(Hub.Cleanup)

syncESP()
updateESP()

pcall(function()
    SaveManager:LoadAutoloadConfig()
end)

Library:Notify(
    "Doomed Playtime RaveHub! loaded — RightShift to open/close",
    5
)

print("[DOOMED PLAYTIME RAVEHUB] Loaded successfully")
