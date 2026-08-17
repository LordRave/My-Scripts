if getgenv().ESP_Cleanup then
    pcall(getgenv().ESP_Cleanup)
end

local esp_elements = {}
local originalSizes = {}
local renderConnection = nil

local function restoreAllHitboxes()
    for part, original in pairs(originalSizes) do
        pcall(function()
            part.Size = original.Size
            part.Transparency = original.Transparency
            part.CanCollide = original.CanCollide
        end)
    end
    table.clear(originalSizes)
end

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

getgenv().AimbotEnabled = false
getgenv().AimbotSmoothness = 5
getgenv().SilentAimEnabled = false
getgenv().TargetPart = "Head"
getgenv().TeamCheck = true
getgenv().WallCheck = true
getgenv().WallbangEnabled = false
getgenv().FastReloadEnabled = false
getgenv().ReloadSpeedMultiplier = 5
getgenv().NoRecoilEnabled = false
getgenv().NoSpreadEnabled = false
getgenv().InfiniteStaminaEnabled = false
getgenv().HitboxExtenderEnabled = false
getgenv().HitboxPart = "Head"
getgenv().HitboxSize = 5
getgenv().HitboxTransparency = 0.5
getgenv().FOV_Radius = 100
getgenv().ShowFOV = true

getgenv().ESPEnabled = false
getgenv().ESP_Boxes = false
getgenv().ESP_Tracers = false
getgenv().ESP_Names = false
getgenv().ESP_Distances = false
getgenv().ESP_Color = Color3.fromRGB(255, 0, 0)
getgenv().SilentAimTarget = nil

local repo = 'https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/'
local Library = loadstring(game:HttpGet(repo .. 'Library.lua'))()
local ThemeManager = loadstring(game:HttpGet(repo .. 'addons/ThemeManager.lua'))()
local SaveManager = loadstring(game:HttpGet(repo .. 'addons/SaveManager.lua'))()

local Window = Library:CreateWindow({
    Title = 'Horizon Blue: 1919 | RaveHub',
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.2
})

local Tabs = {
    Combat = Window:AddTab('Combat'),
    Visuals = Window:AddTab('Visuals'),
    ['UI Settings'] = Window:AddTab('UI Settings'),
}

local CombatLeft = Tabs.Combat:AddLeftGroupbox('Aimbot Settings')
local CombatRight = Tabs.Combat:AddRightGroupbox('Silent Aim & FOV')
local CombatMods = Tabs.Combat:AddLeftGroupbox('Weapon Mods')
local CombatChar = Tabs.Combat:AddLeftGroupbox('Character Mods')
local CombatHitbox = Tabs.Combat:AddRightGroupbox('Hitbox Extender')

CombatLeft:AddToggle('AimbotToggle', {
    Text = 'Enable Aimbot',
    Default = false,
    Tooltip = 'Smoothly locks camera to target part',
})
Toggles.AimbotToggle:OnChanged(function()
    getgenv().AimbotEnabled = Toggles.AimbotToggle.Value
end)

CombatLeft:AddSlider('AimbotSmoothness', {
    Text = 'Smoothness',
    Default = 5,
    Min = 1,
    Max = 20,
    Rounding = 0,
    Compact = false,
})
Options.AimbotSmoothness:OnChanged(function()
    getgenv().AimbotSmoothness = Options.AimbotSmoothness.Value
end)

CombatLeft:AddDropdown('AimbotTargetPart', {
    Values = { 'Head', 'Torso', 'HumanoidRootPart' },
    Default = 1,
    Multi = false,
    Text = 'Target Part',
    Tooltip = 'Select body part to lock onto',
})
Options.AimbotTargetPart:OnChanged(function()
    getgenv().TargetPart = Options.AimbotTargetPart.Value
end)

CombatLeft:AddLabel('Aimbot Keybind'):AddKeyPicker('AimbotKeybind', {
    Default = 'MB2',
    SyncToggleState = false,
    Mode = 'Hold',
    Text = 'Aimbot Trigger',
})

CombatLeft:AddToggle('TeamCheckToggle', {
    Text = 'Team Check',
    Default = true,
    Tooltip = 'Ignore friendly players',
})
Toggles.TeamCheckToggle:OnChanged(function()
    getgenv().TeamCheck = Toggles.TeamCheckToggle.Value
end)

CombatLeft:AddToggle('WallCheckToggle', {
    Text = 'Wall Check (Visibility)',
    Default = true,
    Tooltip = 'Only target players visible to the camera',
})
Toggles.WallCheckToggle:OnChanged(function()
    getgenv().WallCheck = Toggles.WallCheckToggle.Value
end)

CombatRight:AddToggle('SilentAimToggle', {
    Text = 'Enable Silent Aim',
    Default = false,
    Tooltip = 'Redirects bullets directly to targets',
})
Toggles.SilentAimToggle:OnChanged(function()
    getgenv().SilentAimEnabled = Toggles.SilentAimToggle.Value
end)

CombatRight:AddToggle('WallbangToggle', {
    Text = 'Wallbang (Ignore Walls)',
    Default = false,
    Tooltip = 'Allows Silent Aim to bypass solid structures',
})
Toggles.WallbangToggle:OnChanged(function()
    getgenv().WallbangEnabled = Toggles.WallbangToggle.Value
end)

CombatRight:AddToggle('ShowFOVToggle', {
    Text = 'Show FOV Circle',
    Default = true,
    Tooltip = 'Visualizes target boundary circle',
})
Toggles.ShowFOVToggle:OnChanged(function()
    getgenv().ShowFOV = Toggles.ShowFOVToggle.Value
end)

CombatRight:AddSlider('FOVRadius', {
    Text = 'FOV Radius',
    Default = 100,
    Min = 20,
    Max = 500,
    Rounding = 0,
    Compact = false,
})
Options.FOVRadius:OnChanged(function()
    getgenv().FOV_Radius = Options.FOVRadius.Value
end)

CombatMods:AddToggle('NoRecoilToggle', {
    Text = 'No Recoil',
    Default = false,
    Tooltip = 'Removes gun recoil force and camera shake',
})
Toggles.NoRecoilToggle:OnChanged(function()
    getgenv().NoRecoilEnabled = Toggles.NoRecoilToggle.Value
end)

CombatMods:AddToggle('NoSpreadToggle', {
    Text = 'No Spread & Sway',
    Default = false,
    Tooltip = 'Eliminates bullet deviation and gun sway',
})
Toggles.NoSpreadToggle:OnChanged(function()
    getgenv().NoSpreadEnabled = Toggles.NoSpreadToggle.Value
end)

CombatMods:AddToggle('FastReloadToggle', {
    Text = 'Fast Reload & Bolt',
    Default = false,
    Tooltip = 'Speeds up reloading and bolt/firing animations',
})
Toggles.FastReloadToggle:OnChanged(function()
    getgenv().FastReloadEnabled = Toggles.FastReloadToggle.Value
end)

CombatMods:AddSlider('ReloadMultiplier', {
    Text = 'Speed Multiplier',
    Default = 5,
    Min = 1,
    Max = 10,
    Rounding = 1,
    Compact = false,
})
Options.ReloadMultiplier:OnChanged(function()
    getgenv().ReloadSpeedMultiplier = Options.ReloadMultiplier.Value
end)

CombatChar:AddToggle('InfStaminaToggle', {
    Text = 'Infinite Stamina',
    Default = false,
    Tooltip = 'Gives unlimited run and charge stamina',
})
Toggles.InfStaminaToggle:OnChanged(function()
    getgenv().InfiniteStaminaEnabled = Toggles.InfStaminaToggle.Value
end)

CombatHitbox:AddToggle('HitboxToggle', {
    Text = 'Enable Hitbox Extender',
    Default = false,
    Tooltip = 'Expands target hitboxes client-side',
})
Toggles.HitboxToggle:OnChanged(function()
    getgenv().HitboxExtenderEnabled = Toggles.HitboxToggle.Value
    if not getgenv().HitboxExtenderEnabled then
        restoreAllHitboxes()
    end
end)

CombatHitbox:AddDropdown('HitboxTargetDropdown', {
    Values = { 'Head', 'Torso', 'HumanoidRootPart' },
    Default = 1,
    Multi = false,
    Text = 'Target Part',
})
Options.HitboxTargetDropdown:OnChanged(function()
    restoreAllHitboxes()
    getgenv().HitboxPart = Options.HitboxTargetDropdown.Value
end)

CombatHitbox:AddSlider('HitboxSizeSlider', {
    Text = 'Hitbox Size',
    Default = 5,
    Min = 2,
    Max = 15,
    Rounding = 1,
    Compact = false,
})
Options.HitboxSizeSlider:OnChanged(function()
    getgenv().HitboxSize = Options.HitboxSizeSlider.Value
end)

CombatHitbox:AddSlider('HitboxTransparencySlider', {
    Text = 'Hitbox Transparency',
    Default = 5,
    Min = 0,
    Max = 10,
    Rounding = 0,
    Compact = false,
})
Options.HitboxTransparencySlider:OnChanged(function()
    getgenv().HitboxTransparency = Options.HitboxTransparencySlider.Value / 10
end)

local VisualsLeft = Tabs.Visuals:AddLeftGroupbox('ESP Options')
local VisualsRight = Tabs.Visuals:AddRightGroupbox('Customization')

VisualsLeft:AddToggle('ESPEnabledToggle', {
    Text = 'Enable ESP',
    Default = false,
    Tooltip = 'Enables player tracking ESP elements',
})
Toggles.ESPEnabledToggle:OnChanged(function()
    getgenv().ESPEnabled = Toggles.ESPEnabledToggle.Value
end)

VisualsLeft:AddToggle('ESPBoxesToggle', {
    Text = 'Draw Boxes',
    Default = false,
})
Toggles.ESPBoxesToggle:OnChanged(function()
    getgenv().ESP_Boxes = Toggles.ESPBoxesToggle.Value
end)

VisualsLeft:AddToggle('ESPTracersToggle', {
    Text = 'Draw Tracers',
    Default = false,
})
Toggles.ESPTracersToggle:OnChanged(function()
    getgenv().ESP_Tracers = Toggles.ESPTracersToggle.Value
end)

VisualsLeft:AddToggle('ESPNamesToggle', {
    Text = 'Draw Names',
    Default = false,
})
Toggles.ESPNamesToggle:OnChanged(function()
    getgenv().ESP_Names = Toggles.ESPNamesToggle.Value
end)

VisualsLeft:AddToggle('ESPDistancesToggle', {
    Text = 'Draw Distances',
    Default = false,
})
Toggles.ESPDistancesToggle:OnChanged(function()
    getgenv().ESP_Distances = Toggles.ESPDistancesToggle.Value
end)

VisualsRight:AddLabel('ESP Color'):AddColorPicker('ESPColorPicker', {
    Default = Color3.fromRGB(255, 0, 0),
    Title = 'Tracer / Box Color',
})
Options.ESPColorPicker:OnChanged(function()
    getgenv().ESP_Color = Options.ESPColorPicker.Value
end)

local function unloadScript()
    if renderConnection then
        pcall(function() renderConnection:Disconnect() end)
        renderConnection = nil
    end
    
    pcall(restoreAllHitboxes)
    
    for _, el in ipairs(esp_elements) do
        pcall(function() el:Remove() end)
    end
    table.clear(esp_elements)
    
    getgenv().AimbotEnabled = false
    getgenv().SilentAimEnabled = false
    getgenv().WallbangEnabled = false
    getgenv().FastReloadEnabled = false
    getgenv().NoRecoilEnabled = false
    getgenv().NoSpreadEnabled = false
    getgenv().InfiniteStaminaEnabled = false
    getgenv().HitboxExtenderEnabled = false
    getgenv().ESPEnabled = false
    
    pcall(function() Library:Unload() end)
    print("[RaveHub] LinoriaLib Suite Unloaded Successfully.")
end

getgenv().ESP_Cleanup = unloadScript

local SettingsTab = Tabs['UI Settings']
local UnloadGroupBox = SettingsTab:AddLeftGroupbox('Unload Script')
UnloadGroupBox:AddButton('Unload Suite', function()
    unloadScript()
end)

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({'AimbotKeybind'})
ThemeManager:ApplyToTab(Tabs['UI Settings'])
SaveManager:BuildConfigSection(Tabs['UI Settings'])

local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 1.5
FOVCircle.Color = Color3.fromRGB(255, 255, 255)
FOVCircle.Filled = false
FOVCircle.NumSides = 64
FOVCircle.Visible = false
table.insert(esp_elements, FOVCircle)

local playerESP = {}

local function createPlayerESP(player)
    if player == LocalPlayer then return end
    
    local esp = {
        box = Drawing.new("Square"),
        tracer = Drawing.new("Line"),
        name = Drawing.new("Text"),
        distance = Drawing.new("Text")
    }
    
    esp.box.Thickness = 1.5
    esp.box.Color = getgenv().ESP_Color
    esp.box.Filled = false
    esp.box.Visible = false
    
    esp.tracer.Thickness = 1.5
    esp.tracer.Color = getgenv().ESP_Color
    esp.tracer.Visible = false
    
    esp.name.Size = 13
    esp.name.Center = true
    esp.name.Outline = true
    esp.name.Color = Color3.fromRGB(255, 255, 255)
    esp.name.Visible = false
    
    esp.distance.Size = 13
    esp.distance.Center = true
    esp.distance.Outline = true
    esp.distance.Color = Color3.fromRGB(255, 255, 255)
    esp.distance.Visible = false
    
    table.insert(esp_elements, esp.box)
    table.insert(esp_elements, esp.tracer)
    table.insert(esp_elements, esp.name)
    table.insert(esp_elements, esp.distance)
    
    playerESP[player] = esp
end

local function removePlayerESP(player)
    local esp = playerESP[player]
    if esp then
        pcall(function() esp.box:Remove() end)
        pcall(function() esp.tracer:Remove() end)
        pcall(function() esp.name:Remove() end)
        pcall(function() esp.distance:Remove() end)
        playerESP[player] = nil
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    createPlayerESP(p)
end

Players.PlayerAdded:Connect(createPlayerESP)
Players.PlayerRemoving:Connect(removePlayerESP)

local function isPartVisible(part, character)
    local origin = Camera.CFrame.Position
    local destination = part.Position
    local direction = destination - origin
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character, character }
    params.IgnoreWater = true
    
    local result = workspace.Raycast(workspace, origin, direction, params)
    
    if result then
        if not result.Instance.CanCollide or result.Instance.Transparency > 0.8 then
            return true
        end
        return false
    end
    
    return true
end

local function updateHitboxes()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local isEnemy = not getgenv().TeamCheck or player.Team ~= LocalPlayer.Team
            local char = player.Character
            if char then
                local part = char.FindFirstChild(char, getgenv().HitboxPart)
                if part and part:IsA("BasePart") then
                    if getgenv().HitboxExtenderEnabled and isEnemy then
                        if not originalSizes[part] then
                            originalSizes[part] = {
                                Size = part.Size,
                                Transparency = part.Transparency,
                                CanCollide = part.CanCollide
                            }
                        end
                        part.Size = Vector3.new(getgenv().HitboxSize, getgenv().HitboxSize, getgenv().HitboxSize)
                        part.CanCollide = false
                        part.Transparency = getgenv().HitboxTransparency
                    else
                        local original = originalSizes[part]
                        if original then
                            part.Size = original.Size
                            part.Transparency = original.Transparency
                            part.CanCollide = original.CanCollide
                            originalSizes[part] = nil
                        end
                    end
                end
            end
        end
    end
end

local function getClosestEnemy()
    local closestPlayer = nil
    local shortestDistance = math.huge
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            if not getgenv().TeamCheck or player.Team ~= LocalPlayer.Team then
                local char = player.Character
                if char and char.FindFirstChild(char, "Humanoid") then
                    local hum = char.FindFirstChild(char, "Humanoid")
                    if hum.Health > 0 then
                        local part = char.FindFirstChild(char, getgenv().TargetPart)
                        if part then
                            local isVisible = true
                            if getgenv().WallCheck and not getgenv().WallbangEnabled then
                                isVisible = isPartVisible(part, char)
                            end
                            
                            if isVisible then
                                local screenPos, onScreen = Camera.WorldToViewportPoint(Camera, part.Position)
                                if onScreen then
                                    local screenPos2D = Vector2.new(screenPos.X, screenPos.Y)
                                    local distance = (screenPos2D - mousePos).Magnitude
                                    if distance < getgenv().FOV_Radius and distance < shortestDistance then
                                        closestPlayer = player
                                        shortestDistance = distance
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return closestPlayer
end

renderConnection = RunService.RenderStepped:Connect(function()
    if getgenv().ShowFOV then
        FOVCircle.Radius = getgenv().FOV_Radius
        FOVCircle.Position = Vector2.new(Mouse.X, Mouse.Y + 36)
        FOVCircle.Visible = true
    else
        FOVCircle.Visible = false
    end

    local target = getClosestEnemy()
    local targetPart = nil
    if target and target.Character then
        targetPart = target.Character.FindFirstChild(target.Character, getgenv().TargetPart)
    end
    getgenv().SilentAimTarget = targetPart

    if getgenv().AimbotEnabled and targetPart and Options.AimbotKeybind:GetState() then
        local targetCFrame = CFrame.lookAt(Camera.CFrame.Position, targetPart.Position)
        Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, 1 / getgenv().AimbotSmoothness)
    end

    updateHitboxes()

    for player, esp in pairs(playerESP) do
        local isVisible = false
        if getgenv().ESPEnabled then
            if not getgenv().TeamCheck or player.Team ~= LocalPlayer.Team then
                local char = player.Character
                if char and char.FindFirstChild(char, "HumanoidRootPart") and char.FindFirstChild(char, "Humanoid") then
                    local hrp = char.HumanoidRootPart
                    local hum = char.Humanoid
                    if hum.Health > 0 then
                        local hrpPos, onScreen = Camera.WorldToViewportPoint(Camera, hrp.Position)
                        
                        if onScreen then
                            isVisible = true
                            local distance = (Camera.CFrame.Position - hrp.Position).Magnitude
                            
                            local head = char.FindFirstChild(char, "Head")
                            local headPos = head and Camera.WorldToViewportPoint(Camera, head.Position + Vector3.new(0, 1.5, 0)) or hrpPos
                            local legPos = Camera.WorldToViewportPoint(Camera, hrp.Position - Vector3.new(0, 3, 0))
                            
                            local boxHeight = math.abs(headPos.Y - legPos.Y)
                            local boxWidth = boxHeight * 0.6
                            
                            if getgenv().ESP_Boxes then
                                esp.box.Size = Vector2.new(boxWidth, boxHeight)
                                esp.box.Position = Vector2.new(hrpPos.X - boxWidth / 2, headPos.Y)
                                esp.box.Color = getgenv().ESP_Color
                                esp.box.Visible = true
                            else
                                esp.box.Visible = false
                            end
                            
                            if getgenv().ESP_Tracers then
                                esp.tracer.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
                                esp.tracer.To = Vector2.new(hrpPos.X, hrpPos.Y)
                                esp.tracer.Color = getgenv().ESP_Color
                                esp.tracer.Visible = true
                            else
                                esp.tracer.Visible = false
                            end
                            
                            if getgenv().ESP_Names then
                                esp.name.Text = player.Name
                                esp.name.Position = Vector2.new(hrpPos.X, headPos.Y - 15)
                                esp.name.Visible = true
                            else
                                esp.name.Visible = false
                            end
                            
                            if getgenv().ESP_Distances then
                                esp.distance.Text = string.format("[%d studs]", math.floor(distance))
                                esp.distance.Position = Vector2.new(hrpPos.X, legPos.Y + 5)
                                esp.distance.Visible = true
                            else
                                esp.distance.Visible = false
                            end
                        end
                    end
                end
            end
        end
        
        if not isVisible then
            esp.box.Visible = false
            esp.tracer.Visible = false
            esp.name.Visible = false
            esp.distance.Visible = false
        end
    end
end)

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    
    if not checkcaller() and typeof(self) == "Instance" and method == "Play" and self.ClassName == "AnimationTrack" then
        local animName = self.Name:lower()
        if getgenv().FastReloadEnabled and (animName:find("reload") or animName:find("bolt")) then
            local args = {...}
            args[3] = getgenv().ReloadSpeedMultiplier or 5
            return oldNamecall(self, table.unpack(args))
        end
    end
    
    return oldNamecall(self, ...)
end)

for _, v in pairs(getgc(true)) do
    if typeof(v) == "table" then
        if rawget(v, "TraceRay") and type(v.TraceRay) == "function" then
            local oldTrace = v.TraceRay
            v.TraceRay = function(self, startPos, endPos, params, ...)
                if getgenv().SilentAimEnabled and getgenv().SilentAimTarget then
                    local targetPos = getgenv().SilentAimTarget.Position
                    local direction = (targetPos - startPos).Unit * (endPos - startPos).Magnitude
                    endPos = startPos + direction
                    
                    if getgenv().WallbangEnabled then
                        if params == nil then
                            params = RaycastParams.new()
                            params.IgnoreWater = true
                            params.CollisionGroup = "RaycastFilter"
                        end
                        params.FilterType = Enum.RaycastFilterType.Include
                        params.FilterDescendantsInstances = { getgenv().SilentAimTarget.Parent }
                    end
                end
                return oldTrace(self, startPos, endPos, params, ...)
            end
        end

        if rawget(v, "PickRecoilForce") then
            local oldPick = v.PickRecoilForce
            v.PickRecoilForce = function(self, ...)
                local recoil = oldPick(self, ...)
                if getgenv().NoRecoilEnabled and typeof(recoil) == "table" then
                    recoil.Force = Vector3.new(0, 0, 0)
                    recoil.Torque = Vector3.new(0, 0, 0)
                    recoil.Impact = Vector3.new(0, 0, 0)
                    if recoil.CameraBlowScale then
                        recoil.CameraBlowScale.Tilt = 0
                        recoil.CameraBlowScale.Blow = 0
                    end
                end
                return recoil
            end
        end
        
        if rawget(v, "GetSwayScale") then
            local oldSway = v.GetSwayScale
            v.GetSwayScale = function(self, ...)
                if getgenv().NoSpreadEnabled then
                    return 0, 0
                end
                return oldSway(self, ...)
            end
        end
        
        if rawget(v, "DepleteStamina") and rawget(v, "GetModifiers") then
            local oldDeplete = v.DepleteStamina
            v.DepleteStamina = function(self, ...)
                if getgenv().InfiniteStaminaEnabled then
                    return
                end
                return oldDeplete(self, ...)
            end
            
            local oldGetModifiers = v.GetModifiers
            v.GetModifiers = function(self, ...)
                local mods = oldGetModifiers(self, ...)
                if getgenv().InfiniteStaminaEnabled and typeof(mods) == "table" then
                    mods.Stamina = 1
                end
                return mods
            end
        end
    end
end

print("[RaveHub] LinoriaLib Enhancement Suite Loaded Successfully!")
