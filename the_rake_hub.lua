-- The Rake: REMASTERED | LinoriaLib Cheat Menu
-- Designed and implemented by Antigravity OUTCOME

-- Cleanup existing script instance if loaded
if _G.RakeScriptLoaded and type(_G.RakeScriptUnload) == "function" then
    pcall(_G.RakeScriptUnload)
end

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"))()
local ThemeManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/addons/SaveManager.lua"))()

-- State Variables
_G.ModifyWalkSpeed = false
_G.CustomWalkSpeed = 12
_G.CustomSprintSpeed = 25

_G.ModifyJumpPower = false
_G.CustomJumpPower = 35

_G.InfiniteStamina = false
_G.NoFallDamage = false
_G.InstantInteract = false
_G.AutoCollectScrap = false

_G.ESP_Players = false
_G.ESP_Rake = false
_G.ESP_Supply = false
_G.ESP_Flare = false
_G.ESP_Scrap = false
_G.ESP_Locations = false
_G.ESP_Traps = false

_G.Fullbright = false
_G.NoFog = false
_G.AutoRejoin = false

-- Connections container for clean unloading
local Connections = {}
local DrawingsContainer = {}
local ESPCache = {}

local lp = game:GetService("Players").LocalPlayer
local camera = workspace.CurrentCamera
local Lighting = game:GetService("Lighting")

-- Cache for environment environmental settings
local originalSettings = {}
local originalFogSettings = {}

local function saveOriginalLighting()
    originalSettings.Ambient = Lighting.Ambient
    originalSettings.OutdoorAmbient = Lighting.OutdoorAmbient
    originalSettings.Brightness = Lighting.Brightness
    originalSettings.ClockTime = Lighting.ClockTime
    originalSettings.GlobalShadows = Lighting.GlobalShadows
end

local function restoreOriginalLighting()
    if originalSettings.Ambient then
        Lighting.Ambient = originalSettings.Ambient
        Lighting.OutdoorAmbient = originalSettings.OutdoorAmbient
        Lighting.Brightness = originalSettings.Brightness
        Lighting.ClockTime = originalSettings.ClockTime
        Lighting.GlobalShadows = originalSettings.GlobalShadows
    end
end

local function saveOriginalFog()
    originalFogSettings.FogEnd = Lighting.FogEnd
    originalFogSettings.FogStart = Lighting.FogStart
    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
    if atmosphere then
        originalFogSettings.AtmosphereDensity = atmosphere.Density
    end
end

local function restoreOriginalFog()
    if originalFogSettings.FogEnd then
        Lighting.FogEnd = originalFogSettings.FogEnd
        Lighting.FogStart = originalFogSettings.FogStart
    end
    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
    if atmosphere and originalFogSettings.AtmosphereDensity then
        atmosphere.Density = originalFogSettings.AtmosphereDensity
    end
end

-- Helper to get ClientState from Garbage Collector (throttled GC scanning to prevent FPS drops)
local clientState = nil
local lastScanTime = 0
local function getClientState()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        clientState = nil
        return nil
    end
    
    if clientState and clientState.char == char and not clientState.dead then
        return clientState
    end
    clientState = nil -- Invalidate cache
    
    local now = tick()
    if now - lastScanTime < 3 then
        return nil
    end
    lastScanTime = now
    
    for _, obj in pairs(getgc(true)) do
        if type(obj) == "table" and rawget(obj, "vars") and rawget(obj, "CONFIG") and rawget(obj, "plr") and obj.plr == lp then
            if obj.char == char and not obj.dead then
                clientState = obj
                return clientState
            end
        end
    end
    return nil
end

-- Helper to set values inside the protected CONFIG table safely
local function setConfigValue(cs, key, value)
    if not cs or not cs.CONFIG then return end
    local mt = getrawmetatable(cs.CONFIG)
    if mt and type(mt.__index) == "table" then
        local isRO = false
        pcall(function()
            if isreadonly then isRO = isreadonly(mt.__index) end
        end)
        pcall(function()
            if setreadonly then setreadonly(mt.__index, false) end
        end)
        mt.__index[key] = value
        pcall(function()
            if isRO and setreadonly then setreadonly(mt.__index, true) end
        end)
    end
end

-- (Removed metamethod hooks to prevent Adonis indexinstance/namecall detector kicks)



-- Hook TakeStamina function to implement infinite stamina cleanly
local lastHookedClientState = nil
local oldTakeStamina = nil
local function applyStaminaHook()
    local cs = getClientState()
    if cs and cs ~= lastHookedClientState then
        lastHookedClientState = cs
        local mt = getmetatable(cs)
        if mt then
            local isRO = false
            pcall(function()
                if isreadonly then isRO = isreadonly(mt) end
            end)
            
            pcall(function()
                if setreadonly then
                    setreadonly(mt, false)
                elseif makewriteable then
                    makewriteable(mt)
                end
            end)
            
            oldTakeStamina = mt.TakeStamina
            mt.TakeStamina = function(self, amount)
                if _G.InfiniteStamina then
                    self.vars.stamina = self.CONFIG.MAX_STAMINA or 100
                    return
                end
                if oldTakeStamina then
                    return oldTakeStamina(self, amount)
                end
            end
            
            pcall(function()
                if isRO and setreadonly then
                    setreadonly(mt, true)
                end
            end)
        end
    end
end

-- Disable Fall Damage Connection (includes auto-protection for scrap collection teleports)
local _lastFallDisableState = nil
local function applyNoFallDamage()
    local cs = getClientState()
    if cs and cs.cons and cs.cons.FDF then
        if _G.NoFallDamage or _G.AutoCollectScrap then
            cs.cons.FDF:Disconnect()
        end
    end
end

-- Instant Proximity Prompts (Event-driven setup)
local conn1 = game:GetService("ProximityPromptService").PromptShown:Connect(function(prompt)
    if _G.InstantInteract then
        -- Exclude long-hold server-validated prompts from client-side HoldDuration = 0 to prevent rejection
        if prompt.Parent and (prompt.Parent.Name == "StationGUIPart" or prompt.Parent.Name == "PowerBox") then
            return
        end
        prompt.HoldDuration = 0
    end
end)
table.insert(Connections, conn1)

local conn2 = game:GetService("ProximityPromptService").PromptButtonHoldBegan:Connect(function(prompt)
    if _G.InstantInteract and fireproximityprompt then
        -- Intercept manual holds on server-validated prompts and fire them instantly using executor simulation
        if prompt.Parent and (prompt.Parent.Name == "StationGUIPart" or prompt.Parent.Name == "PowerBox") then
            fireproximityprompt(prompt)
        end
    end
end)
table.insert(Connections, conn2)

-- Auto-Rejoin on Kick (using GuiService to catch connection loss or server kick notifications)
local conn3 = game:GetService("GuiService").ErrorMessageChanged:Connect(function(message)
    if _G.AutoRejoin then
        task.wait(1.5) -- Wait to ensure client is ready for teleport
        local ts = game:GetService("TeleportService")
        local lp = game:GetService("Players").LocalPlayer
        if game.JobId ~= "" then
            ts:TeleportToPlaceInstance(game.PlaceId, game.JobId, lp)
        else
            ts:Teleport(game.PlaceId, lp)
        end
    end
end)
table.insert(Connections, conn3)

-- Helper to find physical position of ProximityPrompt
local function getPromptPosition(prompt)
    local parent = prompt.Parent
    if not parent then return nil end
    if parent:IsA("BasePart") then
        return parent.Position
    elseif parent:IsA("Attachment") then
        return parent.WorldPosition
    end
    return nil
end

-- Helper to get closest visible prompt within activation range
local function getClosestPrompt()
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    local closestPrompt = nil
    local closestDist = math.huge
    
    for _, prompt in ipairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Enabled then
            local pos = getPromptPosition(prompt)
            if pos then
                local dist = (hrp.Position - pos).Magnitude
                if dist <= prompt.MaxActivationDistance then
                    if dist < closestDist then
                        closestDist = dist
                        closestPrompt = prompt
                    end
                end
            end
        end
    end
    
    return closestPrompt
end

-- Intercept interaction keypress to trigger instantly (bypasses custom scripts)
local conn4 = game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
    if processed then return end
    if not _G.InstantInteract then return end
    
    local prompt = getClosestPrompt()
    if prompt and input.KeyCode == prompt.KeyboardKeyCode and fireproximityprompt then
        fireproximityprompt(prompt)
    end
end)
table.insert(Connections, conn4)

-- State container and helpers to temporarily disable client-side movement checkers
local disabledConnections = {}
local function disableAntiCheat()
    table.clear(disabledConnections)
    local function processSignal(signal)
        for _, con in ipairs(getconnections(signal)) do
            local s = con.Script
            if s and (s.Name == "S_C" or s.Name == "R_C" or s.Name == "MB" or s.Name == "PR_C") then
                local success = pcall(function()
                    con:Disable()
                end)
                if success then
                    table.insert(disabledConnections, con)
                end
            end
        end
    end
    pcall(processSignal, game:GetService("RunService").Heartbeat)
    pcall(processSignal, game:GetService("RunService").Stepped)
    pcall(processSignal, game:GetService("RunService").RenderStepped)
end

local function enableAntiCheat()
    for _, con in ipairs(disabledConnections) do
        pcall(function()
            con:Enable()
        end)
    end
    table.clear(disabledConnections)
end

-- Safe Step Teleport helper to bypass server-side distance checks and physics flings
local function stepTeleport(targetCF, skipAntiCheat)
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    -- Temporarily disable client-side anti-cheat detection loops if not skipped
    if not skipAntiCheat then
        disableAntiCheat()
    end
    
    local startPos = hrp.Position
    local targetPos = targetCF.Position
    local diff = targetPos - startPos
    local dist = diff.Magnitude
    
    local success, err = pcall(function()
        if dist <= 40 then
            hrp.CFrame = targetCF
            hrp.Velocity = Vector3.new(0, 0, 0)
            pcall(function()
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            end)
            return
        end
        
        local steps = math.ceil(dist / 35)
        for i = 1, steps do
            local alpha = i / steps
            local nextPos = startPos:Lerp(targetPos, alpha)
            hrp.CFrame = CFrame.new(nextPos) * targetCF.Rotation
            
            -- Reset velocity continuously to prevent fling
            hrp.Velocity = Vector3.new(0, 0, 0)
            pcall(function()
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            end)
            
            task.wait(0.015)
        end
    end)
    
    -- Always re-enable anti-cheat loops once arrived if not skipped
    if not skipAntiCheat then
        enableAntiCheat()
    end
    
    if not success then
        error(err)
    end
end

-- Remote interaction helper with safe step teleport and triggers
local function firePromptRemotely(prompt, customArgs)
    if not prompt or not fireproximityprompt then return end
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local pos = getPromptPosition(prompt)
    if not pos then return end
    
    local originalCF = hrp.CFrame
    local oldAnchored = hrp.Anchored
    
    -- Hold anti-cheat disabled globally for the entire interaction time
    disableAntiCheat()
    
    pcall(function()
        -- Disable client-side LineOfSight check temporarily
        local oldLOS = prompt.RequiresLineOfSight
        prompt.RequiresLineOfSight = false
        
        -- Calculate CFrame looking directly at the lever from 2.5 studs away
        local lookCF = prompt.Parent:IsA("BasePart") and prompt.Parent.CFrame or CFrame.new(pos)
        -- To look at the lever, the target position is (pos + lookVector*2.5), and it looks AT (pos)
        local targetPos = pos + lookCF.LookVector * 2.5
        local targetCF = CFrame.new(targetPos, pos)
        
        -- Step-teleport to the prompt position (skip internal disable since handled globally)
        stepTeleport(targetCF, true)
        
        hrp.Anchored = true
        task.wait(0.25) -- Wait for position replication to server
        
        fireproximityprompt(prompt)
        if firesignal then
            firesignal(prompt.Triggered)
        end
        
        -- Backup Remote Event trigger
        if customArgs and prompt.Parent and prompt.Parent.Parent then
            local remote = prompt.Parent.Parent:FindFirstChild("RemoteEvent")
            if remote then
                remote:FireServer(customArgs)
            end
        end
        
        task.wait(0.25) -- Wait for trigger replication to server
        prompt.RequiresLineOfSight = oldLOS
    end)
    
    hrp.Anchored = false
    stepTeleport(originalCF, true)
    
    -- Re-enable anti-cheat after returning safely
    enableAntiCheat()
    
    hrp.Anchored = oldAnchored
    
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end
end

-- Remote shop helper with GUI tracking and persistent anchor
local function openShopRemotely()
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local prompt = workspace.Map.Shack.ShopPart:FindFirstChildOfClass("ProximityPrompt")
    local shopGui = lp.PlayerGui:FindFirstChild("SHOP")
    local shopFrame = shopGui and shopGui:FindFirstChild("ShopFrame")
    
    if hrp and prompt and shopFrame then
        local originalCF = hrp.CFrame
        local oldAnchored = hrp.Anchored
        
        -- Hold anti-cheat disabled globally for the entire shop opening phase
        disableAntiCheat()
        
        pcall(function()
            prompt.RequiresLineOfSight = false
            
            -- Step-teleport to shop (skip internal disable since handled globally)
            stepTeleport(prompt.Parent.CFrame, true)
            
            hrp.Anchored = true
            task.wait(0.25)
            
            fireproximityprompt(prompt)
            if firesignal then
                firesignal(prompt.Triggered)
            end
            task.wait(0.25)
            
            task.spawn(function()
                -- Wait for shop GUI to open client-side (prevents instant return)
                local opened = false
                for i = 1, 10 do
                    if shopFrame.Visible then
                        opened = true
                        break
                    end
                    task.wait(0.1)
                end
                
                if opened then
                    local timeLimit = 60
                    local elapsed = 0
                    while shopFrame.Visible and elapsed < timeLimit do
                        task.wait(0.25)
                        elapsed = elapsed + 0.25
                        if hrp and hrp.Parent then
                            hrp.CFrame = prompt.Parent.CFrame
                        end
                    end
                end
                
                if hrp and hrp.Parent then
                    hrp.Anchored = false
                    stepTeleport(originalCF, true)
                    
                    -- Re-enable anti-cheat loop once we are back home
                    enableAntiCheat()
                    
                    hrp.Anchored = oldAnchored
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum then
                        hum:ChangeState(Enum.HumanoidStateType.Running)
                    end
                end
            end)
        end)
    end
end

-- Auto-Grab Scrap metal via touch replication + safe short teleport bypass
local collectingScrapActive = false

local function getRakePosition()
    local rake = workspace:FindFirstChild("Rake")
    local hrp = rake and rake:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position
end

local function collectAllScrap()
    if collectingScrapActive then return end
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not hum or hum.Health <= 0 then return end
    
    -- Skip if player is inside the lobby/spectator zone (underground)
    if hrp.Position.Y < -50 then return end
    
    local cs = getClientState()
    if not cs or cs.dead then return end
    
    local spawns = workspace:FindFirstChild("Filter") and workspace.Filter:FindFirstChild("ScrapSpawns")
    if not spawns or not firetouchinterest then return end
    
    local scrapFound = {}
    for _, spawnPoint in ipairs(spawns:GetChildren()) do
        local scrapModel = spawnPoint:FindFirstChildOfClass("Model")
        if scrapModel then
            local scrapPart = scrapModel:FindFirstChild("Scrap")
            if scrapPart and scrapPart:IsDescendantOf(workspace) then
                table.insert(scrapFound, scrapPart)
            end
        end
    end
    
    if #scrapFound > 0 then
        collectingScrapActive = true
        local originalCF = hrp.CFrame
        local rakePos = getRakePosition()
        
        -- Disable anti-cheat connections globally during the entire collection loop
        disableAntiCheat()
        
        -- Safely wrapper ensures coordinates & state always restore
        local success, err = pcall(function()
            for _, scrapPart in ipairs(scrapFound) do
                if scrapPart and scrapPart.Parent and scrapPart:IsDescendantOf(workspace) then
                    -- Safety check: skip if the scrap is too close to the Rake (within 45 studs)
                    if rakePos then
                        local distToRake = (scrapPart.Position - rakePos).Magnitude
                        if distToRake < 45 then
                            continue
                        end
                    end
                    
                    -- Step-teleport to scrap (unanchored, placed slightly above to trigger Touch - skip internal disable)
                    stepTeleport(scrapPart.CFrame * CFrame.new(0, 1.5, 0), true)
                    task.wait(0.2) -- Wait for position replication
                    
                    local ft: any = firetouchinterest
                    pcall(ft, hrp, scrapPart, 0)
                    task.wait(0.08)
                    pcall(ft, hrp, scrapPart, 1)
                    
                    task.wait(0.2) -- Wait for touch replication
                end
            end
        end)
        
        -- Step-teleport back
        stepTeleport(originalCF, true)
        
        -- Re-enable anti-cheat once we are safely returned to original position
        enableAntiCheat()
        
        collectingScrapActive = false
        
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end
        
        if not success then
            warn("Error during scrap collection:", err)
        end
    end
end

-- Auto-Collect Scrap loop
task.spawn(function()
    while true do
        task.wait(4)
        if _G.AutoCollectScrap then
            pcall(collectAllScrap)
        end
    end
end)

-- ESP Drawings pool helper
local function getDrawings(id)
    if not ESPCache[id] then
        ESPCache[id] = {
            Text = Drawing.new("Text"),
            Box = {
                Top = Drawing.new("Line"),
                Bottom = Drawing.new("Line"),
                Left = Drawing.new("Line"),
                Right = Drawing.new("Line")
            }
        }
        
        ESPCache[id].Text.Size = 14
        ESPCache[id].Text.Center = true
        ESPCache[id].Text.Outline = true
        ESPCache[id].Text.Color = Color3.new(1, 1, 1)
        ESPCache[id].Text.Visible = false
        table.insert(DrawingsContainer, ESPCache[id].Text)
        
        for _, line in pairs(ESPCache[id].Box) do
            line.Thickness = 1.5
            line.Color = Color3.new(1, 1, 1)
            line.Visible = false
            table.insert(DrawingsContainer, line)
        end
    end
    return ESPCache[id]
end

-- Draw 2D Box Helper
local function draw2DBox(drawings, pos, distance, color)
    local distanceClamped = math.max(distance, 1)
    local sizeX = 1000 / distanceClamped
    local sizeY = 1500 / distanceClamped
    
    drawings.Box.Top.From = Vector2.new(pos.X - sizeX / 2, pos.Y - sizeY / 2)
    drawings.Box.Top.To = Vector2.new(pos.X + sizeX / 2, pos.Y - sizeY / 2)
    drawings.Box.Top.Color = color
    drawings.Box.Top.Visible = true
    
    drawings.Box.Bottom.From = Vector2.new(pos.X - sizeX / 2, pos.Y + sizeY / 2)
    drawings.Box.Bottom.To = Vector2.new(pos.X + sizeX / 2, pos.Y + sizeY / 2)
    drawings.Box.Bottom.Color = color
    drawings.Box.Bottom.Visible = true
    
    drawings.Box.Left.From = Vector2.new(pos.X - sizeX / 2, pos.Y - sizeY / 2)
    drawings.Box.Left.To = Vector2.new(pos.X - sizeX / 2, pos.Y + sizeY / 2)
    drawings.Box.Left.Color = color
    drawings.Box.Left.Visible = true
    
    drawings.Box.Right.From = Vector2.new(pos.X + sizeX / 2, pos.Y - sizeY / 2)
    drawings.Box.Right.To = Vector2.new(pos.X + sizeX / 2, pos.Y + sizeY / 2)
    drawings.Box.Right.Color = color
    drawings.Box.Right.Visible = true
end

-- Main Update Loop
local activeIds = {}
local renderConn = game:GetService("RunService").RenderStepped:Connect(function()
    camera = workspace.CurrentCamera
    if not camera then return end
    
    -- Sync Hook / Fallback values
    local cs = getClientState()
    if cs then
        pcall(applyStaminaHook)
        pcall(applyNoFallDamage)
        
        if _G.InfiniteStamina then
            cs.vars.stamina = cs.CONFIG.MAX_STAMINA or 100
        end
        
        -- Direct configuration manipulation + Humanoid speed enforcement
        if _G.ModifyWalkSpeed then
            setConfigValue(cs, "WS", _G.CustomWalkSpeed)
            setConfigValue(cs, "RS", _G.CustomSprintSpeed)
            local char = lp.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.WalkSpeed > 0 then
                local isSprinting = cs.vars and cs.vars.sprinting
                hum.WalkSpeed = isSprinting and _G.CustomSprintSpeed or _G.CustomWalkSpeed
            end
        else
            setConfigValue(cs, "WS", 12)
            setConfigValue(cs, "RS", 25)
        end
        
        if _G.ModifyJumpPower then
            setConfigValue(cs, "JumpPower", _G.CustomJumpPower)
            local char = lp.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.JumpPower > 0 then
                hum.JumpPower = _G.CustomJumpPower
            end
        else
            setConfigValue(cs, "JumpPower", 35)
        end
    end
    
    -- Render Lighting overrides
    if _G.Fullbright then
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
        Lighting.Brightness = 2
        Lighting.ClockTime = 12
        Lighting.GlobalShadows = false
    end
    
    if _G.NoFog then
        Lighting.FogStart = 9e9
        Lighting.FogEnd = 9e9
        local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
        if atmosphere then
            atmosphere.Density = 0
        end
    end
    
    -- Players ESP
    if _G.ESP_Players then
        for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
            if plr ~= lp and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") and plr.Character:FindFirstChildOfClass("Humanoid") then
                local char = plr.Character
                local hrp = char.HumanoidRootPart
                local hum = char:FindFirstChildOfClass("Humanoid")
                
                if hum.Health > 0 then
                    local w2s, onScreen = camera:WorldToViewportPoint(hrp.Position)
                    if onScreen then
                        local id = "player_" .. plr.UserId
                        activeIds[id] = true
                        
                        local drawings = getDrawings(id)
                        local dist = (camera.CFrame.Position - hrp.Position).Magnitude
                        
                        drawings.Text.Text = string.format("%s\n[%dm] (%d HP)", plr.Name, math.floor(dist), math.floor(hum.Health))
                        drawings.Text.Position = Vector2.new(w2s.X, w2s.Y + (1600 / math.max(dist, 1)) / 2 + 5)
                        drawings.Text.Color = Color3.fromRGB(0, 255, 100)
                        drawings.Text.Visible = true
                        
                        draw2DBox(drawings, w2s, dist, Color3.fromRGB(0, 255, 100))
                    end
                end
            end
        end
    end
    
    -- The Rake ESP
    if _G.ESP_Rake then
        local rake = workspace:FindFirstChild("Rake")
        if rake and rake:FindFirstChild("HumanoidRootPart") and rake:FindFirstChildOfClass("Humanoid") then
            local hrp = rake.HumanoidRootPart
            local hum = rake:FindFirstChildOfClass("Humanoid")
            
            if hum.Health > 0 then
                local w2s, onScreen = camera:WorldToViewportPoint(hrp.Position)
                if onScreen then
                    local id = "rake"
                    activeIds[id] = true
                    
                    local drawings = getDrawings(id)
                    local dist = (camera.CFrame.Position - hrp.Position).Magnitude
                    
                    local targetStr = "None"
                    local targetVal = rake:FindFirstChild("TargetVal")
                    if targetVal and targetVal.Value then
                        targetStr = targetVal.Value.Name
                    end
                    
                    drawings.Text.Text = string.format("THE RAKE\nChasing: %s\n[%dm] (%d/%d HP)", targetStr, math.floor(dist), math.floor(hum.Health), math.floor(hum.MaxHealth))
                    drawings.Text.Position = Vector2.new(w2s.X, w2s.Y + (1600 / math.max(dist, 1)) / 2 + 5)
                    drawings.Text.Color = Color3.fromRGB(255, 0, 0)
                    drawings.Text.Visible = true
                    
                    draw2DBox(drawings, w2s, dist, Color3.fromRGB(255, 0, 0))
                end
            end
        end
    end
    
    -- Supply Drops ESP
    if _G.ESP_Supply then
        local crates = workspace:FindFirstChild("Debris") and workspace.Debris:FindFirstChild("SupplyCrates")
        if crates then
            for _, crate in ipairs(crates:GetChildren()) do
                local root = crate:IsA("BasePart") and crate or crate:FindFirstChildOfClass("BasePart")
                if root then
                    local w2s, onScreen = camera:WorldToViewportPoint(root.Position)
                    if onScreen then
                        local id = "supply_" .. tostring(crate)
                        activeIds[id] = true
                        
                        local drawings = getDrawings(id)
                        local dist = (camera.CFrame.Position - root.Position).Magnitude
                        
                        drawings.Text.Text = string.format("SUPPLY DROP\n[%dm]", math.floor(dist))
                        drawings.Text.Position = Vector2.new(w2s.X, w2s.Y)
                        drawings.Text.Color = Color3.fromRGB(255, 165, 0)
                        drawings.Text.Visible = true
                        
                        drawings.Box.Top.Visible = false
                        drawings.Box.Bottom.Visible = false
                        drawings.Box.Left.Visible = false
                        drawings.Box.Right.Visible = false
                    end
                end
            end
        end
    end
    
    -- Flare Gun ESP
    if _G.ESP_Flare then
        -- 1. Check world pickup model
        local flarePickUp = workspace:FindFirstChild("FlareGunPickUp")
        if flarePickUp then
            local root = flarePickUp:FindFirstChild("FlareGun") or flarePickUp:FindFirstChildOfClass("BasePart")
            if root then
                local w2s, onScreen = camera:WorldToViewportPoint(root.Position)
                if onScreen then
                    local id = "flare_pickup"
                    activeIds[id] = true
                    
                    local drawings = getDrawings(id)
                    local dist = (camera.CFrame.Position - root.Position).Magnitude
                    
                    drawings.Text.Text = string.format("FLARE GUN (PICKUP)\n[%dm]", math.floor(dist))
                    drawings.Text.Position = Vector2.new(w2s.X, w2s.Y)
                    drawings.Text.Color = Color3.fromRGB(255, 255, 0)
                    drawings.Text.Visible = true
                    
                    drawings.Box.Top.Visible = false
                    drawings.Box.Bottom.Visible = false
                    drawings.Box.Left.Visible = false
                    drawings.Box.Right.Visible = false
                end
            end
        end
        
        -- 2. Check dropped tools in workspace
        for _, child in ipairs(workspace:GetChildren()) do
            if child:IsA("Tool") and child.Name:lower():find("flare") then
                local root = child:FindFirstChild("Handle") or child:FindFirstChildOfClass("BasePart")
                if root then
                    local w2s, onScreen = camera:WorldToViewportPoint(root.Position)
                    if onScreen then
                        local id = "flare_tool_" .. tostring(child)
                        activeIds[id] = true
                        
                        local drawings = getDrawings(id)
                        local dist = (camera.CFrame.Position - root.Position).Magnitude
                        
                        drawings.Text.Text = string.format("FLARE GUN (TOOL)\n[%dm]", math.floor(dist))
                        drawings.Text.Position = Vector2.new(w2s.X, w2s.Y)
                        drawings.Text.Color = Color3.fromRGB(255, 255, 0)
                        drawings.Text.Visible = true
                        
                        drawings.Box.Top.Visible = false
                        drawings.Box.Bottom.Visible = false
                        drawings.Box.Left.Visible = false
                        drawings.Box.Right.Visible = false
                    end
                end
            end
        end
    end
    
    -- Scrap Metal ESP
    if _G.ESP_Scrap then
        local spawns = workspace:FindFirstChild("Filter") and workspace.Filter:FindFirstChild("ScrapSpawns")
        if spawns then
            for _, spawnPoint in ipairs(spawns:GetChildren()) do
                -- Scrap model (ScrapX) inside spawn point
                local scrapModel = spawnPoint:FindFirstChildOfClass("Model")
                if scrapModel then
                    local root = scrapModel:FindFirstChild("Scrap") or scrapModel:FindFirstChildOfClass("BasePart")
                    if root then
                        local w2s, onScreen = camera:WorldToViewportPoint(root.Position)
                        if onScreen then
                            local id = "scrap_" .. tostring(scrapModel)
                            activeIds[id] = true
                            
                            local drawings = getDrawings(id)
                            local dist = (camera.CFrame.Position - root.Position).Magnitude
                            
                            local lvl = scrapModel:FindFirstChild("LevelVal") and scrapModel.LevelVal.Value or "Unknown"
                            local val = scrapModel:FindFirstChild("PointsVal") and scrapModel.PointsVal.Value or "Unknown"
                            
                            drawings.Text.Text = string.format("SCRAP (Lvl: %s, Val: %s)\n[%dm]", tostring(lvl), tostring(val), math.floor(dist))
                            drawings.Text.Position = Vector2.new(w2s.X, w2s.Y)
                            drawings.Text.Color = Color3.fromRGB(0, 191, 255)
                            drawings.Text.Visible = true
                            
                            drawings.Box.Top.Visible = false
                            drawings.Box.Bottom.Visible = false
                            drawings.Box.Left.Visible = false
                            drawings.Box.Right.Visible = false
                        end
                    end
                end
            end
        end
    end
    
    -- Locations ESP
    if _G.ESP_Locations then
        local locPoints = workspace:FindFirstChild("Filter") and workspace.Filter:FindFirstChild("LocationPoints")
        if locPoints then
            for _, loc in ipairs(locPoints:GetChildren()) do
                if loc:IsA("BasePart") then
                    local w2s, onScreen = camera:WorldToViewportPoint(loc.Position)
                    if onScreen then
                        local cleanName = loc.Name:gsub("MSG", "")
                        cleanName = cleanName:gsub("(%l)(%u)", "%1 %2")
                        
                        local id = "loc_" .. loc.Name
                        activeIds[id] = true
                        
                        local drawings = getDrawings(id)
                        local dist = (camera.CFrame.Position - loc.Position).Magnitude
                        
                        drawings.Text.Text = string.format("%s\n[%dm]", cleanName:upper(), math.floor(dist))
                        drawings.Text.Position = Vector2.new(w2s.X, w2s.Y)
                        drawings.Text.Color = Color3.fromRGB(238, 130, 238)
                        drawings.Text.Visible = true
                        
                        drawings.Box.Top.Visible = false
                        drawings.Box.Bottom.Visible = false
                        drawings.Box.Left.Visible = false
                        drawings.Box.Right.Visible = false
                    end
                end
            end
        end
    -- Traps ESP
    if _G.ESP_Traps then
        local traps = workspace:FindFirstChild("Debris") and workspace.Debris:FindFirstChild("Traps")
        if traps then
            for _, trap in ipairs(traps:GetChildren()) do
                local root = trap:IsA("BasePart") and trap or trap:FindFirstChildOfClass("BasePart")
                if root then
                    local w2s, onScreen = camera:WorldToViewportPoint(root.Position)
                    if onScreen then
                        local id = "trap_" .. tostring(trap)
                        activeIds[id] = true
                        
                        local drawings = getDrawings(id)
                        local dist = (camera.CFrame.Position - root.Position).Magnitude
                        
                        local name = trap.Name == "RakeTrapModel" and "RAKE TRAP" or trap.Name:upper()
                        drawings.Text.Text = string.format("%s\n[%dm]", name, math.floor(dist))
                        drawings.Text.Position = Vector2.new(w2s.X, w2s.Y)
                        drawings.Text.Color = Color3.fromRGB(255, 69, 0)
                        drawings.Text.Visible = true
                        
                        drawings.Box.Top.Visible = false
                        drawings.Box.Bottom.Visible = false
                        drawings.Box.Left.Visible = false
                        drawings.Box.Right.Visible = false
                    end
                end
            end
        end
    end
end
    -- Hide inactive drawing elements
    for id, drawings in pairs(ESPCache) do
        if not activeIds[id] then
            drawings.Text.Visible = false
            drawings.Box.Top.Visible = false
            drawings.Box.Bottom.Visible = false
            drawings.Box.Left.Visible = false
            drawings.Box.Right.Visible = false
        end
    end
    table.clear(activeIds)
end)
table.insert(Connections, renderConn)

-- GUI Setup
local Window = Library:CreateWindow({
    Title = 'Rake Remastered RaveHub',
    Center = true,
    AutoShow = true,
    TabWidth = 160,
})

-- Players Tab
local PlayersTab = Window:AddTab('Players')
local WalkSpeedGroup = PlayersTab:AddLeftGroupbox('WalkSpeed Controls')
local JumpGroup = PlayersTab:AddRightGroupbox('Jump & Stamina')

WalkSpeedGroup:AddToggle('WS_Toggle', {
    Text = 'Enable Speed Mod',
    Default = false,
    Tooltip = 'Enables your custom Walk and Run speeds.',
    Callback = function(Value)
        _G.ModifyWalkSpeed = Value
    end
})

WalkSpeedGroup:AddSlider('WS_WalkSlider', {
    Text = 'Walk Speed',
    Default = 12,
    Min = 5,
    Max = 100,
    Rounding = 0,
    Compact = false,
    Callback = function(Value)
        _G.CustomWalkSpeed = Value
    end
})

WalkSpeedGroup:AddSlider('WS_SprintSlider', {
    Text = 'Run (Sprint) Speed',
    Default = 25,
    Min = 5,
    Max = 150,
    Rounding = 0,
    Compact = false,
    Callback = function(Value)
        _G.CustomSprintSpeed = Value
    end
})

JumpGroup:AddToggle('JP_Toggle', {
    Text = 'Enable Jump Mod',
    Default = false,
    Tooltip = 'Enables custom jump power.',
    Callback = function(Value)
        _G.ModifyJumpPower = Value
    end
})

JumpGroup:AddSlider('JP_Slider', {
    Text = 'Jump Power',
    Default = 35,
    Min = 10,
    Max = 150,
    Rounding = 0,
    Compact = false,
    Callback = function(Value)
        _G.CustomJumpPower = Value
    end
})

JumpGroup:AddToggle('Stamina_Toggle', {
    Text = 'Infinite Stamina',
    Default = false,
    Tooltip = 'Keeps your stamina values full completely bypassing Adonis.',
    Callback = function(Value)
        _G.InfiniteStamina = Value
        if not Value then
            -- Reset stamina to base on toggle off
            local cs = getClientState()
            if cs then
                cs.vars.stamina = cs.CONFIG.MAX_STAMINA or 100
            end
        end
    end
})

-- Teleports & Exploits Group inside Players Tab
local ExploitGroup = PlayersTab:AddLeftGroupbox('Gameplay Exploits')

ExploitGroup:AddToggle('NoFall_Toggle', {
    Text = 'No Fall Damage',
    Default = false,
    Tooltip = 'Disconnects the game\'s fall damage detection system.',
    Callback = function(Value)
        _G.NoFallDamage = Value
        if Value then
            pcall(applyNoFallDamage)
        end
    end
})

ExploitGroup:AddToggle('Instant_Toggle', {
    Text = 'Instant Interaction',
    Default = false,
    Tooltip = 'Removes hold duration from all doors and generators.',
    Callback = function(Value)
        _G.InstantInteract = Value
    end
})

ExploitGroup:AddToggle('GrabScrap_Toggle', {
    Text = 'Auto-Collect Scrap',
    Default = false,
    Tooltip = 'Loop-collects all scrap pieces spawning on the map via bypass.',
    Callback = function(Value)
        _G.AutoCollectScrap = Value
    end
})

ExploitGroup:AddButton('Instant Grab All Scrap', function()
    pcall(collectAllScrap)
end)

-- Visuals Tab
local VisualsTab = Window:AddTab('Visuals')
local ESPGroup = VisualsTab:AddLeftGroupbox('ESP Toggles')
local LightGroup = VisualsTab:AddRightGroupbox('Atmosphere & Brightness')

ESPGroup:AddToggle('ESP_Players_Tgl', {
    Text = 'Players ESP',
    Default = false,
    Callback = function(Value)
        _G.ESP_Players = Value
    end
})

ESPGroup:AddToggle('ESP_Rake_Tgl', {
    Text = 'The Rake ESP',
    Default = false,
    Callback = function(Value)
        _G.ESP_Rake = Value
    end
})

ESPGroup:AddToggle('ESP_Supply_Tgl', {
    Text = 'Supply Drop ESP',
    Default = false,
    Callback = function(Value)
        _G.ESP_Supply = Value
    end
})

ESPGroup:AddToggle('ESP_Flare_Tgl', {
    Text = 'Flare Gun ESP',
    Default = false,
    Callback = function(Value)
        _G.ESP_Flare = Value
    end
})

ESPGroup:AddToggle('ESP_Scrap_Tgl', {
    Text = 'Scrap Metal ESP',
    Default = false,
    Callback = function(Value)
        _G.ESP_Scrap = Value
    end
})

ESPGroup:AddToggle('ESP_Loc_Tgl', {
    Text = 'Locations ESP',
    Default = false,
    Callback = function(Value)
        _G.ESP_Locations = Value
    end
})

ESPGroup:AddToggle('ESP_Traps_Tgl', {
    Text = 'Traps ESP',
    Default = false,
    Callback = function(Value)
        _G.ESP_Traps = Value
    end
})

LightGroup:AddToggle('Fullbright_Toggle', {
    Text = 'Fullbright',
    Default = false,
    Tooltip = 'Enforces daylight lighting settings to eliminate darkness.',
    Callback = function(Value)
        _G.Fullbright = Value
        if not Value then
            restoreOriginalLighting()
        else
            saveOriginalLighting()
        end
    end
})

LightGroup:AddToggle('NoFog_Toggle', {
    Text = 'No Fog',
    Default = false,
    Tooltip = 'Disables atmospheric density and fog range limits.',
    Callback = function(Value)
        _G.NoFog = Value
        if not Value then
            restoreOriginalFog()
        else
            saveOriginalFog()
        end
    end
})

-- Trolls & Utilities Tab
local TrollTab = Window:AddTab('Trolls & Utils')
local SafehouseTrollGroup = TrollTab:AddLeftGroupbox('Safehouse Controls (Troll)')
local TowerTrollGroup = TrollTab:AddRightGroupbox('Observation Tower Controls')
local MapTrollGroup = TrollTab:AddLeftGroupbox('Map-wide Remote Actions')

SafehouseTrollGroup:AddButton('Toggle Safehouse Door', function()
    local prompt = workspace.Map.SafeHouse.Door.DoorLever.DoorGUIPart:FindFirstChildOfClass("ProximityPrompt")
    firePromptRemotely(prompt, "Door")
end)

SafehouseTrollGroup:AddButton('Toggle Safehouse Lights', function()
    local prompt = workspace.Map.SafeHouse.Door.LightLever.LightGUIPart:FindFirstChildOfClass("ProximityPrompt")
    firePromptRemotely(prompt, "Light")
end)

SafehouseTrollGroup:AddButton('Sabotage Safehouse Power Box', function()
    local prompt = workspace.Map.SafeHouse.Door.PowerBox.GUIPart:FindFirstChildOfClass("ProximityPrompt")
    firePromptRemotely(prompt)
end)

SafehouseTrollGroup:AddButton('Get Walkie Talkie Remotely', function()
    local prompt = workspace.Map.SafeHouse.Giver.WalkieTalkie.Attachment:FindFirstChildOfClass("ProximityPrompt")
    if prompt then
        firePromptRemotely(prompt)
        local remote = game:GetService("ReplicatedStorage"):FindFirstChild("WalkieEvent")
        if remote then
            remote:FireServer()
        end
    end
end)

TowerTrollGroup:AddButton('Toggle Tower Outer Door', function()
    local prompt = workspace.Map.ObservationTower.Door.DoorLever.DoorGUIPart:FindFirstChildOfClass("ProximityPrompt")
    firePromptRemotely(prompt)
end)

TowerTrollGroup:AddButton('Toggle Tower Inner Door', function()
    local prompt = workspace.Map.ObservationTower.Door.DoorLever2.DoorGUIPart2:FindFirstChildOfClass("ProximityPrompt")
    firePromptRemotely(prompt)
end)

TowerTrollGroup:AddButton('Toggle Tower Lights', function()
    local prompt = workspace.Map.ObservationTower.Lights.LightLever.LightGUIPart:FindFirstChildOfClass("ProximityPrompt")
    firePromptRemotely(prompt)
end)

TowerTrollGroup:AddButton('Toggle Radar Lever', function()
    local prompt = workspace.Map.ObservationTower.Radar.Lever.RadarGUIPart:FindFirstChildOfClass("ProximityPrompt")
    firePromptRemotely(prompt)
end)

MapTrollGroup:AddButton('Toggle Power Grid (Station)', function()
    local prompt = workspace.Map.PowerStation.StationFolder.StationGUIPart:FindFirstChildOfClass("ProximityPrompt")
    firePromptRemotely(prompt)
end)

MapTrollGroup:AddButton('Open Shop Menu Remotely', function()
    openShopRemotely()
end)

MapTrollGroup:AddButton('Return from Shop (Safeguard)', function()
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.Anchored = false
        local shopGui = lp.PlayerGui:FindFirstChild("SHOP")
        local shopFrame = shopGui and shopGui:FindFirstChild("ShopFrame")
        if shopFrame then
            shopFrame.Visible = false
        end
        Library:Notify("Safeguard applied: Character unanchored.", 3)
    end
end)

MapTrollGroup:AddButton('Disarm All Rake Traps', function()
    local traps = workspace:FindFirstChild("Debris") and workspace.Debris:FindFirstChild("Traps")
    if traps and fireproximityprompt then
        for _, trap in ipairs(traps:GetDescendants()) do
            if trap:IsA("ProximityPrompt") then
                firePromptRemotely(trap)
            end
        end
    end
end)

-- Game Info Tab
local InfoTab = Window:AddTab('Game Info')
local GeneralInfoGroup = InfoTab:AddLeftGroupbox('Match Information')
local RakeInfoGroup = InfoTab:AddRightGroupbox('Rake & Scraps')

local StatusLabel = GeneralInfoGroup:AddLabel('Status: N/A')
local ClockLabel = GeneralInfoGroup:AddLabel('Game Time: N/A')
local CountdownLabel = GeneralInfoGroup:AddLabel('Time to Daybreak: N/A')
local PowerStatusLabel = GeneralInfoGroup:AddLabel('Power Grid: N/A')
local PowerEnergyLabel = GeneralInfoGroup:AddLabel('Power Energy: N/A')

local RakeTargetLabel = RakeInfoGroup:AddLabel('Rake Target: N/A')
local ScrapCountLabel = RakeInfoGroup:AddLabel('Active Scraps: N/A')

local gameInfoActive = true
task.spawn(function()
    while gameInfoActive do
        task.wait(1)
        pcall(function()
            -- 1. Time Info
            local clock = game:GetService("Lighting").ClockTime
            local isNight = false
            local timeStr = "Daytime"
            local remainingStr = "N/A"
            
            if clock >= 0 and clock <= 6 then
                isNight = true
                timeStr = string.format("%02d:%02d AM", math.floor(clock == 0 and 12 or clock), math.floor((clock * 60) % 60))
                local remaining = 6 - clock
                remainingStr = string.format("%dm %ds", math.floor(remaining * 60), math.floor((remaining * 3600) % 60))
            elseif clock >= 18 and clock <= 24 then
                isNight = true
                local displayClock = clock >= 24 and clock - 24 or clock
                timeStr = string.format("%02d:%02d PM", math.floor(displayClock > 12 and displayClock - 12 or (displayClock == 0 and 12 or displayClock)), math.floor((clock * 60) % 60))
                local remaining = (24 - clock) + 6
                remainingStr = string.format("%dm %ds", math.floor(remaining * 60), math.floor((remaining * 3600) % 60))
            end
            
            StatusLabel:SetText('Status: ' .. (isNight and 'NIGHTTIME' or 'DAYTIME'))
            ClockLabel:SetText('Game Time: ' .. timeStr)
            CountdownLabel:SetText('Time to Daybreak: ' .. remainingStr)
            
            -- 2. Power Info
            local pb = workspace.Map.SafeHouse.Door:FindFirstChild("PowerBox")
            local light1 = pb and pb:FindFirstChild("Light1")
            local powerOn = light1 and light1.Material == Enum.Material.Neon
            PowerStatusLabel:SetText('Power Grid: ' .. (powerOn and 'ACTIVE' or 'SHUTDOWN'))
            
            local ps = workspace.Map:FindFirstChild("PowerStation")
            local energy = ps and ps.StationFolder:FindFirstChild("Progress") and ps.StationFolder.Progress.Value or 0
            PowerEnergyLabel:SetText('Power Energy: ' .. tostring(math.floor(energy)) .. '%')
            
            -- 3. Rake Info
            local rake = workspace:FindFirstChild("Rake")
            local rakeTarget = "None"
            if rake then
                local targetVal = rake:FindFirstChild("TargetVal")
                if targetVal and targetVal.Value then
                    rakeTarget = targetVal.Value.Name
                end
            end
            RakeTargetLabel:SetText('Rake Target: ' .. rakeTarget)
            
            -- 4. Scraps Info
            local scrapsCount = 0
            local spawns = workspace:FindFirstChild("Filter") and workspace.Filter:FindFirstChild("ScrapSpawns")
            if spawns then
                for _, spawnPoint in ipairs(spawns:GetChildren()) do
                    if spawnPoint:FindFirstChildOfClass("Model") then
                        scrapsCount = scrapsCount + 1
                    end
                end
            end
            ScrapCountLabel:SetText('Active Scraps: ' .. tostring(scrapsCount))
        end)
    end
end)

-- Settings Tab
local SettingsTab = Window:AddTab('Settings')
local SettingsGroup = SettingsTab:AddLeftGroupbox('Menu Settings')

local MenuToggleLabel = SettingsGroup:AddLabel('Menu Keybind')
MenuToggleLabel:AddKeyPicker('MenuToggleKey', {
    Default = 'RightShift',
    NoUI = false,
    Text = 'Toggle Menu',
    Mode = 'Toggle',
    
    ChangedCallback = function(val)
        Library.ToggleKey = val
    end
})

SettingsGroup:AddToggle('AutoRejoin_Toggle', {
    Text = 'Auto-Rejoin on Kick',
    Default = false,
    Tooltip = 'Automatically rejoins the server if you get kicked or disconnected.',
    Callback = function(Value)
        _G.AutoRejoin = Value
    end
})

-- Handle LinoriaLib Minimize keybind linking
Library.ToggleKey = Enum.KeyCode.RightShift

local function UnloadScript()
    -- Disconnect render step and connections
    gameInfoActive = false
    
    for _, con in ipairs(Connections) do
        if con then con:Disconnect() end
    end
    table.clear(Connections)
    
    -- Destroy drawings
    for _, drawing in ipairs(DrawingsContainer) do
        if drawing then drawing:Destroy() end
    end
    table.clear(DrawingsContainer)
    table.clear(ESPCache)
    
    -- Revert stamina hook
    local cs = getClientState()
    if cs and getmetatable(cs) and oldTakeStamina then
        local mt = getmetatable(cs)
        local isRO = false
        pcall(function()
            if isreadonly then isRO = isreadonly(mt) end
        end)
        pcall(function()
            if setreadonly then setreadonly(mt, false) end
        end)
        mt.TakeStamina = oldTakeStamina
        pcall(function()
            if isRO and setreadonly then setreadonly(mt, true) end
        end)
    end
    
    -- Restore original environmental settings
    restoreOriginalLighting()
    restoreOriginalFog()
    
    -- Restore original walkspeed/jump values
    if cs then
        setConfigValue(cs, "WS", 12)
        setConfigValue(cs, "RS", 25)
        setConfigValue(cs, "JumpPower", 35)
    end
    

    
    -- Clear loaded status
    _G.RakeScriptLoaded = false
    _G.RakeScriptUnload = nil
    
    -- Destroy UI
    Library:Unload()
end


SettingsGroup:AddButton('Rejoin Server', function()
    local ts = game:GetService("TeleportService")
    local lp = game:GetService("Players").LocalPlayer
    if game.JobId ~= "" then
        ts:TeleportToPlaceInstance(game.PlaceId, game.JobId, lp)
    else
        ts:Teleport(game.PlaceId, lp)
    end
end)

SettingsGroup:AddButton('Unload Script', UnloadScript)

-- Set unload global function for reloads
_G.RakeScriptLoaded = true
_G.RakeScriptUnload = UnloadScript

-- Save starting light values on execution
saveOriginalLighting()
saveOriginalFog()

Library:Notify("Rake: REMASTERED Script Loaded! Press RightShift to toggle menu.", 5)
