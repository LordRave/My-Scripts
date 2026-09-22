-- RaveHub - Napoleonic War Bots
local env = getgenv()
local previousAim = false
local previousESP = true
local previousHub = env.RaveHub or env.NWBBotAim
if previousHub then
    previousAim = previousHub.AimEnabled == true or previousHub.Enabled == true
    if previousHub.ESPEnabled ~= nil then previousESP = previousHub.ESPEnabled == true end
    if previousHub.Unload then pcall(previousHub.Unload) end
end

assert(game.PlaceId == 129117266875770, "RaveHub only supports Napoleonic War Bots.")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared")
local Musket = require(Modules:WaitForChild("MusketUtils"))
local Settings = require(Modules:WaitForChild("GameSettings"))
assert(type(Musket._spawnOwnerBullet) == "function" and not table.isfrozen(Musket), "The firing interface has changed.")

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"))()

local State = {
    Alive = true,
    AimEnabled = previousAim,
    AimRange = 400,
    AimCone = 35,
    Redirected = 0,
    OwnedShots = 0,
    ESPEnabled = previousESP,
    ESPRange = 700,
    ESPColor = Color3.fromRGB(255, 65, 65),
    ESPFillTransparency = 0.72,
    ESPObjects = {},
    ArtilleryEnabled = true,
    ArtilleryColor = Color3.fromRGB(255, 145, 45),
    ArtilleryObjects = {},
    ObjectiveEnabled = true,
    ObjectiveColor = Color3.fromRGB(255, 220, 55),
    ObjectiveObjects = {},
    IndicatorsEnabled = true,
    IndicatorColor = Color3.fromRGB(255, 65, 65),
    IndicatorRange = 2000,
    IndicatorLimit = 12,
    Indicators = {},
    IndicatorVisibleCount = 0,
    AutoDoctrine = true,
    DoctrineCloseRange = 120,
    DoctrineRippleRange = 260,
    DoctrinePending = {},
    DoctrineLastSent = {},
    DoctrineAccepted = 0,
    DoctrineRejected = 0,
    DoctrineDisplay = "Waiting for company state..."
}

for _, instance in ipairs(workspace:GetDescendants()) do
    if instance.Name == "RaveHubEnemyTag" or instance.Name == "RaveHubEnemyHighlight"
        or instance.Name == "RaveHubEnemyChams" or instance.Name == "RaveHubArtilleryCham"
        or instance.Name == "RaveHubObjectiveESP" then
        instance:Destroy()
    end
end

local function getOwnedTeam()
    local registry = workspace:FindFirstChild("Npc_Registry")
    if registry then
        for _, model in ipairs(registry:GetChildren()) do
            if model:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
                local team = model:GetAttribute("TeamName")
                if team == "ATTACKERS" or team == "DEFENDERS" then return team end
            end
        end
    end

    local playerTeam = LocalPlayer.Team and LocalPlayer.Team.Name
    if playerTeam == "ATTACKERS" or playerTeam == "DEFENDERS" then return playerTeam end

    local side = tonumber(LocalPlayer:GetAttribute("SideIndex"))
        or tonumber(LocalPlayer:GetAttribute("NWB_DeploymentSideIndex"))
        or tonumber(LocalPlayer:GetAttribute("NWB_LastUsedSideIndex"))
    if side == 1 then return "ATTACKERS" end
    if side == 2 then return "DEFENDERS" end
    return nil
end

local function getOwnedSide()
    local team = getOwnedTeam()
    if team == "ATTACKERS" then return 1 end
    if team == "DEFENDERS" then return 2 end
    local side = tonumber(LocalPlayer:GetAttribute("SideIndex"))
        or tonumber(LocalPlayer:GetAttribute("NWB_DeploymentSideIndex"))
        or tonumber(LocalPlayer:GetAttribute("NWB_LastUsedSideIndex"))
    return side
end

local OriginalSpawn = Musket._spawnOwnerBullet
local AimWrapper

local function selectTarget(model, origin, direction)
    local registry = workspace:FindFirstChild("Npc_Registry")
    if not registry then return nil end

    local team = model:GetAttribute("TeamName")
    if not team then return nil end

    local maxRange = math.min(State.AimRange, Settings.COMBAT_RANGE or 500)
    local minimumDot = math.cos(math.rad(State.AimCone))
    local bestPart, bestScore

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.RespectCanCollide = false
    local ignored = {model}
    local serverRegistry = workspace:FindFirstChild("Npc_Registry_Server")
    if serverRegistry then table.insert(ignored, serverRegistry) end
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then table.insert(ignored, player.Character) end
    end
    params.FilterDescendantsInstances = ignored

    for _, npc in ipairs(registry:GetChildren()) do
        local root = npc:FindFirstChild("HumanoidRootPart")
        local humanoid = npc:FindFirstChildOfClass("Humanoid")
        local otherTeam = npc:GetAttribute("TeamName")
        if npc ~= model and root and humanoid and humanoid.Health > 0 and otherTeam and otherTeam ~= team then
            local offset = root.Position - origin
            local distance = offset.Magnitude
            if distance > 0.1 and distance <= maxRange then
                local dot = direction.Unit:Dot(offset.Unit)
                if dot >= minimumDot then
                    local hit = workspace:Raycast(origin, offset, params)
                    if not hit or hit.Instance:IsDescendantOf(npc) then
                        local score = (1 - dot) * 1000 + distance * 0.01
                        if not bestScore or score < bestScore then
                            bestScore = score
                            bestPart = root
                        end
                    end
                end
            end
        end
    end
    return bestPart
end

AimWrapper = function(self, origin, direction, shotId)
    local model = self._model
    local owned = model and model:GetAttribute("OwnerUserId") == LocalPlayer.UserId
    if owned then State.OwnedShots += 1 end

    if State.Alive and State.AimEnabled and owned and typeof(direction) == "Vector3" and direction.Magnitude > 0 then
        local ok, adjusted = pcall(function()
            local target = selectTarget(model, origin, direction)
            if not target then return nil end
            local speed = Settings.BULLET_SPEED or 1000
            local travelTime = (target.Position - origin).Magnitude / speed
            local predicted = target.Position + target.AssemblyLinearVelocity * travelTime
            predicted += Vector3.new(0, 0.5 * (Settings.BULLET_GRAVITY or 10) * travelTime * travelTime, 0)
            local offset = predicted - origin
            return offset.Magnitude > 0.01 and offset.Unit or nil
        end)
        if ok and adjusted then
            direction = adjusted
            State.Redirected += 1
        end
    end

    return OriginalSpawn(self, origin, direction, shotId)
end
Musket._spawnOwnerBullet = AimWrapper

local BodyParts = {
    Head = true,
    Torso = true,
    UpperTorso = true,
    LowerTorso = true,
    ["Left Arm"] = true,
    ["Right Arm"] = true,
    ["Left Leg"] = true,
    ["Right Leg"] = true,
    LeftUpperArm = true,
    LeftLowerArm = true,
    RightUpperArm = true,
    RightLowerArm = true,
    LeftUpperLeg = true,
    LeftLowerLeg = true,
    RightUpperLeg = true,
    RightLowerLeg = true
}

local function addChamPart(data, part)
    if not part:IsA("BasePart") or not BodyParts[part.Name] or data.Parts[part] then return end
    local cham = Instance.new("BoxHandleAdornment")
    cham.Name = "RaveHubBodyCham"
    cham.Adornee = part
    cham.AlwaysOnTop = true
    cham.ZIndex = 5
    cham.Size = part.Size + Vector3.new(0.035, 0.035, 0.035)
    cham.Color3 = State.ESPColor
    cham.Transparency = State.ESPFillTransparency
    cham.Visible = false
    cham.Parent = data.Container
    data.Parts[part] = cham
end

local function removeESP(model)
    local data = State.ESPObjects[model]
    if not data then return end
    if data.Connection then data.Connection:Disconnect() end
    if data.Container then data.Container:Destroy() end
    State.ESPObjects[model] = nil
end

local function createESP(model)
    if State.ESPObjects[model] or not model:IsA("Model") then return end

    local container = Instance.new("Folder")
    container.Name = "RaveHubEnemyChams"
    container.Parent = model

    local data = {
        Container = container,
        Parts = {}
    }
    State.ESPObjects[model] = data

    for _, child in ipairs(model:GetChildren()) do
        addChamPart(data, child)
    end
    data.Connection = model.ChildAdded:Connect(function(child)
        addChamPart(data, child)
    end)
end

local registryConnections = {}
local function bindRegistry()
    for _, connection in ipairs(registryConnections) do connection:Disconnect() end
    table.clear(registryConnections)

    local registry = workspace:FindFirstChild("Npc_Registry")
    if not registry then return end
    for _, model in ipairs(registry:GetChildren()) do createESP(model) end
    table.insert(registryConnections, registry.ChildAdded:Connect(createESP))
    table.insert(registryConnections, registry.ChildRemoved:Connect(removeESP))
end
bindRegistry()

local espAccumulator = 0
local renderConnection = RunService.Heartbeat:Connect(function(deltaTime)
    espAccumulator += deltaTime
    if espAccumulator < 0.12 then return end
    espAccumulator = 0

    local camera = workspace.CurrentCamera
    local cameraPosition = camera and camera.CFrame.Position
    local ownedTeam = getOwnedTeam()

    for model, data in pairs(State.ESPObjects) do
        if not model.Parent then
            removeESP(model)
        else
            local root = model:FindFirstChild("HumanoidRootPart")
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local team = model:GetAttribute("TeamName")
            local isEnemy = ownedTeam and team and team ~= ownedTeam
            local distance = root and cameraPosition and (root.Position - cameraPosition).Magnitude or math.huge
            local visible = State.ESPEnabled and isEnemy and humanoid and humanoid.Health > 0 and distance <= State.ESPRange

            for part, cham in pairs(data.Parts) do
                if not part.Parent then
                    cham:Destroy()
                    data.Parts[part] = nil
                else
                    cham.Visible = visible
                    cham.Color3 = State.ESPColor
                    cham.Transparency = State.ESPFillTransparency
                    cham.Size = part.Size + Vector3.new(0.035, 0.035, 0.035)
                end
            end
        end
    end
end)


local RuntimeConnections = {}
local ArtilleryConnections = {}

local function removeArtillery(model)
    local highlight = State.ArtilleryObjects[model]
    if highlight then highlight:Destroy() end
    State.ArtilleryObjects[model] = nil
end

local function createArtillery(model)
    if State.ArtilleryObjects[model] or not model:IsA("Model") then return end
    local highlight = Instance.new("Highlight")
    highlight.Name = "RaveHubArtilleryCham"
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 0.66
    highlight.OutlineTransparency = 0
    highlight.FillColor = State.ArtilleryColor
    highlight.OutlineColor = State.ArtilleryColor
    highlight.Enabled = false
    highlight.Adornee = model
    highlight.Parent = model
    State.ArtilleryObjects[model] = highlight
end

local function bindArtillery()
    for _, connection in ipairs(ArtilleryConnections) do connection:Disconnect() end
    table.clear(ArtilleryConnections)
    for model in pairs(State.ArtilleryObjects) do removeArtillery(model) end

    local folder = workspace:FindFirstChild("NWB_Artillery")
    if not folder then return end
    for _, model in ipairs(folder:GetChildren()) do createArtillery(model) end
    table.insert(ArtilleryConnections, folder.ChildAdded:Connect(createArtillery))
    table.insert(ArtilleryConnections, folder.ChildRemoved:Connect(removeArtillery))
end
bindArtillery()
table.insert(RuntimeConnections, workspace.ChildAdded:Connect(function(child)
    if child.Name == "NWB_Artillery" then bindArtillery() end
end))

local function objectiveKind(instance)
    if not (instance:IsA("Model") or instance:IsA("BasePart")) then return nil end
    local registry = workspace:FindFirstChild("Npc_Registry")
    if instance:IsA("Model") and instance.Parent == registry then
        if instance:GetAttribute("IsFlagBearer") == true or instance:FindFirstChild("HeldFlag") then
            return "FLAG_BEARER"
        end
        return nil
    end

    local lower = instance.Name:lower()
    if lower:match("^droppedflag_") then return "DROPPED_FLAG" end
    if lower == "objective" or lower == "objectiveanchor" or lower == "capturepoint"
        or lower == "capture_point" or lower == "kothobjective" or lower == "koth_objective" then
        return "OBJECTIVE"
    end

    for key in pairs(instance:GetAttributes()) do
        local attribute = key:lower()
        if attribute:find("objectiveid", 1, true) or attribute:find("capturepointid", 1, true)
            or attribute:find("kothobjective", 1, true) then
            return "OBJECTIVE"
        end
    end
    return nil
end

local function removeObjective(instance)
    local data = State.ObjectiveObjects[instance]
    if not data then return end
    if data.Highlight then data.Highlight:Destroy() end
    State.ObjectiveObjects[instance] = nil
end

local function createObjective(instance, kind)
    kind = kind or objectiveKind(instance)
    if not kind or State.ObjectiveObjects[instance] then return end
    local highlight = Instance.new("Highlight")
    highlight.Name = "RaveHubObjectiveESP"
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 0.55
    highlight.OutlineTransparency = 0
    highlight.FillColor = State.ObjectiveColor
    highlight.OutlineColor = State.ObjectiveColor
    highlight.Enabled = false
    highlight.Adornee = instance
    highlight.Parent = instance
    State.ObjectiveObjects[instance] = {Highlight = highlight, Kind = kind}
end

local function scanObjectives()
    local registry = workspace:FindFirstChild("Npc_Registry")
    if registry then
        for _, model in ipairs(registry:GetChildren()) do
            local isBearer = model:GetAttribute("IsFlagBearer") == true or model:FindFirstChild("HeldFlag") ~= nil
            if isBearer then
                createObjective(model, "FLAG_BEARER")
            elseif State.ObjectiveObjects[model] and State.ObjectiveObjects[model].Kind == "FLAG_BEARER" then
                removeObjective(model)
            end
        end
    end

    for instance, data in pairs(State.ObjectiveObjects) do
        if not instance.Parent then
            removeObjective(instance)
        elseif data.Kind == "FLAG_BEARER" and not (instance:GetAttribute("IsFlagBearer") == true or instance:FindFirstChild("HeldFlag")) then
            removeObjective(instance)
        end
    end
end

for _, instance in ipairs(workspace:GetDescendants()) do
    local kind = objectiveKind(instance)
    if kind then createObjective(instance, kind) end
end
table.insert(RuntimeConnections, workspace.DescendantAdded:Connect(function(instance)
    local kind = objectiveKind(instance)
    if kind then createObjective(instance, kind) end
end))
table.insert(RuntimeConnections, workspace.DescendantRemoving:Connect(function(instance)
    if State.ObjectiveObjects[instance] then removeObjective(instance) end
end))

for i = 1, 20 do
    local indicator = Drawing.new("Triangle")
    indicator.Color = State.IndicatorColor
    indicator.Filled = true
    indicator.Thickness = 1
    indicator.Transparency = 1
    indicator.Visible = false
    State.Indicators[i] = indicator
end

local function hideIndicators()
    State.IndicatorVisibleCount = 0
    for _, indicator in ipairs(State.Indicators) do
        indicator.Visible = false
    end
end

local indicatorConnection = RunService.RenderStepped:Connect(function()
    hideIndicators()
    if not State.Alive or not State.IndicatorsEnabled then return end

    local camera = workspace.CurrentCamera
    local registry = workspace:FindFirstChild("Npc_Registry")
    local ownedTeam = getOwnedTeam()
    if not camera or not registry or not ownedTeam then return end

    local candidates = {}
    local cameraPosition = camera.CFrame.Position
    for _, model in ipairs(registry:GetChildren()) do
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        local root = model:FindFirstChild("HumanoidRootPart")
        if model:GetAttribute("TeamName") ~= ownedTeam and humanoid and humanoid.Health > 0 and root then
            local distance = (root.Position - cameraPosition).Magnitude
            if distance <= State.IndicatorRange then
                local viewport, onScreen = camera:WorldToViewportPoint(root.Position)
                if not onScreen or viewport.Z <= 0 then
                    table.insert(candidates, {Position = root.Position, Distance = distance})
                end
            end
        end
    end
    table.sort(candidates, function(a, b) return a.Distance < b.Distance end)

    local viewportSize = camera.ViewportSize
    local center = viewportSize / 2
    local half = Vector2.new(math.max(20, center.X - 32), math.max(20, center.Y - 32))
    local limit = math.min(State.IndicatorLimit, #State.Indicators, #candidates)

    for i = 1, limit do
        local relative = camera.CFrame:PointToObjectSpace(candidates[i].Position)
        local direction = Vector2.new(relative.X, -relative.Y)
        if relative.Z > 0 then direction = -direction end
        if direction.Magnitude < 0.001 then direction = Vector2.new(0, -1) end
        direction = direction.Unit

        local scaleX = math.abs(direction.X) > 0.001 and half.X / math.abs(direction.X) or math.huge
        local scaleY = math.abs(direction.Y) > 0.001 and half.Y / math.abs(direction.Y) or math.huge
        local edge = center + direction * math.min(scaleX, scaleY)
        local perpendicular = Vector2.new(-direction.Y, direction.X)
        local base = edge - direction * 15
        local indicator = State.Indicators[i]
        indicator.PointA = edge
        indicator.PointB = base + perpendicular * 7
        indicator.PointC = base - perpendicular * 7
        indicator.Color = State.IndicatorColor
        indicator.Visible = true
    end
    State.IndicatorVisibleCount = limit
end)

local tacticalAccumulator = 0
local tacticalConnection = RunService.Heartbeat:Connect(function(deltaTime)
    tacticalAccumulator += deltaTime
    if tacticalAccumulator < 0.2 then return end
    tacticalAccumulator = 0

    local ownedSide = getOwnedSide()
    for model, highlight in pairs(State.ArtilleryObjects) do
        if not model.Parent then
            removeArtillery(model)
        else
            local side = tonumber(model:GetAttribute("NWB_ArtillerySideIndex"))
            local integrity = tonumber(model:GetAttribute("NWB_ArtilleryIntegrity")) or 0
            highlight.Enabled = State.ArtilleryEnabled and ownedSide and side and side ~= ownedSide and integrity > 0
            highlight.FillColor = State.ArtilleryColor
            highlight.OutlineColor = State.ArtilleryColor
        end
    end

    scanObjectives()
    for instance, data in pairs(State.ObjectiveObjects) do
        local visible = State.ObjectiveEnabled and instance.Parent ~= nil
        if data.Kind == "FLAG_BEARER" then
            local humanoid = instance:FindFirstChildOfClass("Humanoid")
            visible = visible and humanoid and humanoid.Health > 0
        end
        data.Highlight.Enabled = visible
        data.Highlight.FillColor = State.ObjectiveColor
        data.Highlight.OutlineColor = State.ObjectiveColor
    end
end)

local RemoteFolder = ReplicatedStorage:FindFirstChild("NapoleonicWarsRojo")
local CommandRequest = RemoteFolder and RemoteFolder:FindFirstChild("NWBCommandRequest")
local CommandResult = RemoteFolder and RemoteFolder:FindFirstChild("NWBCommandResult")
local CompanyStateQuery = RemoteFolder and RemoteFolder:FindFirstChild("NWBCompanyStateQuery")
local doctrineCounter = 0

local function allowedDoctrine(state, doctrine)
    if type(state) ~= "table" or type(state.allowedFireDoctrines) ~= "table" then return false end
    for _, value in ipairs(state.allowedFireDoctrines) do
        if value == doctrine then return true end
    end
    return false
end

local function desiredDoctrine(companyIndex)
    local registry = workspace:FindFirstChild("Npc_Registry")
    if not registry then return nil, math.huge end

    local owned = {}
    local enemies = {}
    local ownedTeam = getOwnedTeam()
    local nonArtillery = false
    for _, model in ipairs(registry:GetChildren()) do
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        local root = model:FindFirstChild("HumanoidRootPart")
        if humanoid and humanoid.Health > 0 and root then
            if model:GetAttribute("OwnerUserId") == LocalPlayer.UserId
                and tonumber(model:GetAttribute("CompanyIndex")) == companyIndex then
                table.insert(owned, root)
                if model:GetAttribute("ClassKey") ~= "Artillery" then nonArtillery = true end
            elseif ownedTeam and model:GetAttribute("TeamName") ~= ownedTeam then
                table.insert(enemies, root)
            end
        end
    end
    if #owned == 0 or not nonArtillery then return nil, math.huge end

    local nearest = math.huge
    for _, ownRoot in ipairs(owned) do
        for _, enemyRoot in ipairs(enemies) do
            local distance = (ownRoot.Position - enemyRoot.Position).Magnitude
            if distance < nearest then nearest = distance end
        end
    end

    if nearest <= State.DoctrineCloseRange then
        return "FireAtWill", nearest
    elseif nearest <= math.max(State.DoctrineRippleRange, State.DoctrineCloseRange + 1) then
        return "Ripple", nearest
    elseif nearest <= (Settings.COMBAT_RANGE or 500) then
        return "Volley", nearest
    end
    return "HoldFire", nearest
end

if CommandResult and CommandResult:IsA("RemoteEvent") then
    table.insert(RuntimeConnections, CommandResult.OnClientEvent:Connect(function(result)
        if type(result) ~= "table" then return end
        local requestId = tostring(result.requestId or "")
        local pending = State.DoctrinePending[requestId]
        if not pending then return end
        State.DoctrinePending[requestId] = nil
        if result.accepted == true then
            State.DoctrineAccepted += 1
            State.DoctrineDisplay = string.format("Company %d: %s accepted", pending.CompanyIndex, pending.Value)
        else
            State.DoctrineRejected += 1
            State.DoctrineDisplay = string.format("Company %d: rejected (%s)", pending.CompanyIndex, tostring(result.code or "UNKNOWN"))
        end
        print("RAVEHUB_DOCTRINE_RESULT", requestId, result.accepted == true, tostring(result.code), tostring(result.value))
    end))
end

local function updateDoctrine()
    if not State.AutoDoctrine then
        State.DoctrineDisplay = "Automatic doctrine disabled"
        return
    end
    if workspace:GetAttribute("MatchStage") ~= "MATCH" then
        State.DoctrineDisplay = "Waiting for an active match..."
        return
    end
    if not (CommandRequest and CommandRequest:IsA("RemoteEvent") and CompanyStateQuery and CompanyStateQuery:IsA("RemoteFunction")) then
        State.DoctrineDisplay = "Doctrine remotes unavailable"
        return
    end

    local ok, companyState = pcall(function() return CompanyStateQuery:InvokeServer() end)
    if not ok or type(companyState) ~= "table" or type(companyState.companies) ~= "table" then
        State.DoctrineDisplay = "Company state unavailable"
        return
    end

    local display = {}
    for _, company in ipairs(companyState.companies) do
        local companyIndex = math.floor(tonumber(company.companyIndex) or 0)
        local desired, nearest = desiredDoctrine(companyIndex)
        if desired and allowedDoctrine(companyState, desired) then
            local distanceText = nearest < math.huge and string.format("%.0f", nearest) or "none"
            table.insert(display, string.format("C%d %s -> %s (%s studs)", companyIndex, tostring(company.fireDoctrine), desired, distanceText))

            local hasPending = false
            for _, pending in pairs(State.DoctrinePending) do
                if pending.CompanyIndex == companyIndex then hasPending = true break end
            end
            local lastSent = State.DoctrineLastSent[companyIndex] or 0
            if tostring(company.fireDoctrine) ~= desired and not hasPending and os.clock() - lastSent >= 3 then
                doctrineCounter += 1
                local requestId = string.format("RaveHub-%d-%d-%d", LocalPlayer.UserId, companyIndex, doctrineCounter):sub(1, 64)
                State.DoctrinePending[requestId] = {CompanyIndex = companyIndex, Value = desired, SentAt = os.clock()}
                State.DoctrineLastSent[companyIndex] = os.clock()
                CommandRequest:FireServer({
                    action = "SetFireDoctrine",
                    companyIndex = companyIndex,
                    value = desired,
                    requestId = requestId
                })
            end
        end
    end
    if #display > 0 then State.DoctrineDisplay = table.concat(display, " | ") end
end

local Window = Library:CreateWindow({
    Title = "RaveHub | Napoleonic War Bots",
    Center = true,
    AutoShow = true
})

local CombatTab = Window:AddTab("Combat")
local AimBox = CombatTab:AddLeftGroupbox("Bot Silent Aim")
AimBox:AddToggle("RaveHubAim", {
    Text = "Enable silent aim",
    Default = State.AimEnabled,
    Callback = function(value) State.AimEnabled = value end
})
AimBox:AddSlider("RaveHubAimRange", {
    Text = "Maximum range",
    Default = State.AimRange,
    Min = 25,
    Max = Settings.COMBAT_RANGE or 500,
    Rounding = 0,
    Suffix = " studs",
    Callback = function(value) State.AimRange = value end
})
AimBox:AddSlider("RaveHubAimCone", {
    Text = "Maximum aim angle",
    Default = State.AimCone,
    Min = 1,
    Max = 180,
    Rounding = 0,
    Callback = function(value) State.AimCone = value end
})
local AimStatus = AimBox:AddLabel("Owned shots: 0 | Redirected: 0")

local DoctrineBox = CombatTab:AddRightGroupbox("Automatic Fire Doctrine")
DoctrineBox:AddToggle("RaveHubAutoDoctrine", {
    Text = "Enable automatic doctrine",
    Default = State.AutoDoctrine,
    Callback = function(value) State.AutoDoctrine = value end
})
DoctrineBox:AddSlider("RaveHubDoctrineClose", {
    Text = "Free fire below",
    Default = State.DoctrineCloseRange,
    Min = 40,
    Max = 220,
    Rounding = 0,
    Suffix = " studs",
    Callback = function(value) State.DoctrineCloseRange = value end
})
DoctrineBox:AddSlider("RaveHubDoctrineRipple", {
    Text = "Ripple below",
    Default = State.DoctrineRippleRange,
    Min = 100,
    Max = 450,
    Rounding = 0,
    Suffix = " studs",
    Callback = function(value) State.DoctrineRippleRange = value end
})
local DoctrineStatus = DoctrineBox:AddLabel("Waiting for company state...", true)

local VisualsTab = Window:AddTab("Visuals")
local ESPBox = VisualsTab:AddLeftGroupbox("Enemy Chams")
ESPBox:AddToggle("RaveHubESP", {
    Text = "Enable enemy chams",
    Default = State.ESPEnabled,
    Callback = function(value) State.ESPEnabled = value end
})
ESPBox:AddSlider("RaveHubESPRange", {
    Text = "Maximum range",
    Default = State.ESPRange,
    Min = 50,
    Max = 2000,
    Rounding = 0,
    Suffix = " studs",
    Callback = function(value) State.ESPRange = value end
})
ESPBox:AddSlider("RaveHubESPFill", {
    Text = "Fill transparency",
    Default = math.floor(State.ESPFillTransparency * 100),
    Min = 0,
    Max = 100,
    Rounding = 0,
    Suffix = "%",
    Callback = function(value) State.ESPFillTransparency = value / 100 end
})
ESPBox:AddLabel("Chams color"):AddColorPicker("RaveHubESPColor", {
    Default = State.ESPColor,
    Title = "Enemy chams color",
    Callback = function(value) State.ESPColor = value end
})

local TacticalBox = VisualsTab:AddRightGroupbox("Tactical ESP")
TacticalBox:AddToggle("RaveHubArtillery", {
    Text = "Enemy artillery chams",
    Default = State.ArtilleryEnabled,
    Callback = function(value) State.ArtilleryEnabled = value end
})
TacticalBox:AddLabel("Artillery color"):AddColorPicker("RaveHubArtilleryColor", {
    Default = State.ArtilleryColor,
    Title = "Enemy artillery color",
    Callback = function(value) State.ArtilleryColor = value end
})
TacticalBox:AddToggle("RaveHubObjectives", {
    Text = "Flag and objective ESP",
    Default = State.ObjectiveEnabled,
    Callback = function(value) State.ObjectiveEnabled = value end
})
TacticalBox:AddLabel("Objective color"):AddColorPicker("RaveHubObjectiveColor", {
    Default = State.ObjectiveColor,
    Title = "Flag and objective color",
    Callback = function(value) State.ObjectiveColor = value end
})
TacticalBox:AddToggle("RaveHubIndicators", {
    Text = "Off-screen enemy indicators",
    Default = State.IndicatorsEnabled,
    Callback = function(value) State.IndicatorsEnabled = value end
})
TacticalBox:AddSlider("RaveHubIndicatorLimit", {
    Text = "Maximum indicators",
    Default = State.IndicatorLimit,
    Min = 1,
    Max = 20,
    Rounding = 0,
    Callback = function(value) State.IndicatorLimit = value end
})
TacticalBox:AddSlider("RaveHubIndicatorRange", {
    Text = "Indicator range",
    Default = State.IndicatorRange,
    Min = 250,
    Max = 4000,
    Rounding = 0,
    Suffix = " studs",
    Callback = function(value) State.IndicatorRange = value end
})
TacticalBox:AddLabel("Indicator color"):AddColorPicker("RaveHubIndicatorColor", {
    Default = State.IndicatorColor,
    Title = "Off-screen indicator color",
    Callback = function(value) State.IndicatorColor = value end
})

local SettingsTab = Window:AddTab("Settings")
local MenuBox = SettingsTab:AddLeftGroupbox("Menu")
MenuBox:AddLabel("Menu keybind"):AddKeyPicker("RaveHubMenuKey", {
    Default = "End",
    NoUI = true,
    Text = "Menu keybind"
})
Library.ToggleKeybind = Options.RaveHubMenuKey

local function cleanupRuntime()
    if not State.Alive then return end
    State.Alive = false
    State.AimEnabled = false
    State.ESPEnabled = false
    State.ArtilleryEnabled = false
    State.ObjectiveEnabled = false
    State.IndicatorsEnabled = false
    State.AutoDoctrine = false

    if Musket._spawnOwnerBullet == AimWrapper then
        Musket._spawnOwnerBullet = OriginalSpawn
    end
    if renderConnection then renderConnection:Disconnect() end
    if tacticalConnection then tacticalConnection:Disconnect() end
    if indicatorConnection then indicatorConnection:Disconnect() end

    for _, connection in ipairs(registryConnections) do connection:Disconnect() end
    for _, connection in ipairs(ArtilleryConnections) do connection:Disconnect() end
    for _, connection in ipairs(RuntimeConnections) do connection:Disconnect() end

    for model in pairs(State.ESPObjects) do removeESP(model) end
    for model in pairs(State.ArtilleryObjects) do removeArtillery(model) end
    for instance in pairs(State.ObjectiveObjects) do removeObjective(instance) end
    for _, indicator in ipairs(State.Indicators) do
        pcall(function() indicator:Destroy() end)
    end
    table.clear(State.Indicators)

    if env.RaveHub == State then env.RaveHub = nil end
    if env.NWBBotAim == State then env.NWBBotAim = nil end
end

local function unload()
    if not State.Alive then return end
    cleanupRuntime()
    Library:Unload()
end

State.Unload = unload
env.RaveHub = State
env.NWBBotAim = State
MenuBox:AddButton({Text = "Unload RaveHub", Func = unload})

Library:OnUnload(cleanupRuntime)

task.spawn(function()
    while State.Alive do
        AimStatus:SetText(string.format("Owned shots: %d | Redirected: %d", State.OwnedShots, State.Redirected))
        DoctrineStatus:SetText(State.DoctrineDisplay)
        task.wait(0.5)
    end
end)

task.spawn(function()
    while State.Alive do
        local ok, err = pcall(updateDoctrine)
        if not ok then
            State.DoctrineDisplay = "Doctrine error: " .. tostring(err)
            warn("[RaveHub] Automatic doctrine error:", err)
        end
        task.wait(2)
    end
end)

print("RAVEHUB_READY", State.AimEnabled, State.ESPEnabled, State.ArtilleryEnabled, State.ObjectiveEnabled, State.IndicatorsEnabled, State.AutoDoctrine)
