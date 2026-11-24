
local env = (getgenv and getgenv()) or _G
if type(env._NWB_SPLIX_UNLOAD) == "function" then
    pcall(env._NWB_SPLIX_UNLOAD)
end


local cloneref = cloneref or function(o) return o end
local checkcaller = checkcaller or function() return false end
local newcclosure = newcclosure or function(f) return f end
local hookfunction = hookfunction or replaceclosure
local restorefunction = restorefunction
local isfunctionhooked = isfunctionhooked
local setrenderproperty = setrenderproperty

local Players = cloneref(game:GetService("Players"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local Workspace = cloneref(game:GetService("Workspace"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local Lighting = cloneref(game:GetService("Lighting"))
local HttpService = cloneref(game:GetService("HttpService"))

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local math_sqrt = math.sqrt
local math_floor = math.floor
local math_ceil = math.ceil
local math_clamp = math.clamp
local math_min = math.min
local math_max = math.max
local math_abs = math.abs
local math_random = math.random
local math_tan = math.tan
local math_rad = math.rad
local string_format = string.format
local string_sub = string.sub
local string_find = string.find
local string_match = string.match
local string_lower = string.lower
local string_byte = string.byte
local string_char = string.char
local table_insert = table.insert
local table_remove = table.remove
local table_clear = table.clear
local table_concat = table.concat
local table_create = table.create
local os_clock = os.clock
local os_date = os.date
local Vector2_new = Vector2.new
local Vector3_new = Vector3.new
local Vector3_zero = Vector3.zero
local CFrame_new = CFrame.new
local CFrame_Angles = CFrame.Angles
local CFrame_lookAt = CFrame.lookAt
local Color3_fromRGB = Color3.fromRGB
local Color3_new = Color3.new
local buffer_len = buffer and buffer.len
local buffer_readu8 = buffer and buffer.readu8
local buffer_readu16 = buffer and buffer.readu16

local COLOR_GOLD = Color3_fromRGB(255, 225, 80)
local COLOR_BLACK = Color3_new(0, 0, 0)
local COLOR_HP_BG = Color3_fromRGB(15, 15, 15)
local COLOR_WHITE = Color3_new(1, 1, 1)
local COLOR_LIGHT_GRAY = Color3_fromRGB(215, 215, 215)
local COMPANY_STRINGS = { [0] = "C0", [1] = "C1", [2] = "C2", [3] = "C3", [4] = "C4", [5] = "C5", [6] = "C6" }

-- Precomputed 33-step HP Bar Color LUT (eliminates per-frame Color3.fromRGB allocations)
local HP_COLOR_LUT = table_create(33)
for i = 0, 32 do
    local frac = i / 32
    HP_COLOR_LUT[i] = Color3_fromRGB(math_floor(255 * (1 - frac)), math_floor(235 * frac), 55)
end

--==============================================================================
-- 1. STATE CONTAINER & UNLOAD CLEANUP INFRASTRUCTURE
--==============================================================================
local State = {
    Unloaded = false,
    Connections = {},
    BlinkUnsubs = {},
    Drawings = {},
    Hooks = {},
    DisabledConns = {},
    DisabledZoomConns = {},
    LightingSnapshot = nil,
    FXSnapshot = {},
    SmokeSnapshot = {},
    SmokeEmitters = {},
    SmokeScanned = false,
    OriginalMaxZoom = LocalPlayer.CameraMaxZoomDistance,
    OriginalWalkSpeed = 50,
    OriginalCameraType = nil,
    OriginalFieldOfView = nil,
    OwnedCompanyIdx = 1,
    MyCompanyAliveCount = 0,
    LastOwnedScan = 0,
    LastNpcFolder = nil,
    NpcModels = {},
    NpcFolderConns = {},
    NpcSnapshotTick = 0,
    NpcRecordCache = {},
    NpcSnapshots = table_create(256),
    NpcSnapshotCount = 0,
    CompanyClusters = {},
    DroppedFlags = {},
    CharParts = {},
    LastChar = nil,
    WalkHookHum = nil,
    LastWalkHookScan = 0,
    LastZoomHookScan = 0,
    ArcCache = { Key = "", WorldPoints = table_create(28), Count = 0 },
    ArtyState = nil,
    ArtyLastEventAt = 0,
    ArtyLastEventKind = "NONE",
    SilentAimTarget = nil,
    SpyLogs = {},
    SpyMaxLogs = 14,
    Timers = {
        FocusFire = 0, Formation = 0, Chant = 0, ArtyFire = 0, ArtyDrill = 0,
        ArtyTarget = 0, Missions = 0, Vote = 0, WalkSpeed = 0, ConfigPoll = 0, DeployFix = 0,
    },
    PrevStates = {
        AttackHeld = false, MeleeActive = false, FocusActive = false, FlyActive = false,
        RTSActive = false, FreecamActive = false, SmokeHidden = false, FpsBoost = false,
        Fullbright = false, PacketSpy = false, KeybindsVisible = nil,
    },
    FlyBodyVel = nil,
    FlyBodyGyro = nil,
    FreecamCF = nil,
    RTSCenter = nil,
    SavedFolder = "splix/configs",
}

local function addConn(conn)
    if conn then table_insert(State.Connections, conn) end
    return conn
end

local function newDrawing(kind, props)
    local ok, obj = pcall(Drawing.new, kind)
    if not ok or not obj then return nil end
    if props then
        for k, v in pairs(props) do
            if setrenderproperty then
                pcall(setrenderproperty, obj, k, v)
            else
                pcall(function() obj[k] = v end)
            end
        end
    end
    table_insert(State.Drawings, obj)
    return obj
end

--==============================================================================
-- 2. GAME MODULE & REMOTE RESOLUTION (DEFENSIVE)
--==============================================================================
local function findModule(name)
    local inst = ReplicatedStorage:FindFirstChild(name, true)
    if inst and inst:IsA("ModuleScript") then
        local ok, mod = pcall(require, inst)
        if ok and mod ~= nil then return mod, inst end
    end
    return nil, inst
end

local MusketUtils = findModule("MusketUtils")
local GameSettings = findModule("GameSettings") or {}
local ArtilleryConfig = findModule("ArtilleryConfig") or {}
local NpcMovementSync = findModule("NpcMovementSync")
local BlinkClient = nil
do
    local blinkFolder = ReplicatedStorage:FindFirstChild("Blink")
    local clientMod = blinkFolder and blinkFolder:FindFirstChild("Client")
    if clientMod and clientMod:IsA("ModuleScript") then
        local ok, mod = pcall(require, clientMod)
        if ok then BlinkClient = mod end
    end
end

local RojoFolder = ReplicatedStorage:FindFirstChild("NapoleonicWarsRojo")
local ArtyFolder = ReplicatedStorage:FindFirstChild("NWBArtilleryRemotes")
local BlinkReliableRemote = ReplicatedStorage:FindFirstChild("BLINK_RELIABLE_REMOTE", true)
local BlinkUnreliableRemote = ReplicatedStorage:FindFirstChild("BLINK_UNRELIABLE_REMOTE", true)

local Remotes = {
    MeleeCommand = RojoFolder and RojoFolder:FindFirstChild("MeleeCommand"),
    NpcMoveIntent = RojoFolder and RojoFolder:FindFirstChild("NpcMoveIntent"),
    SetFlagGuardMode = RojoFolder and RojoFolder:FindFirstChild("SetFlagGuardMode"),
    ChantContextRequest = RojoFolder and RojoFolder:FindFirstChild("ChantContextRequest"),
    NWBCommandRequest = RojoFolder and RojoFolder:FindFirstChild("NWBCommandRequest"),
    NWBGameModeVote = RojoFolder and RojoFolder:FindFirstChild("NWBGameModeVote"),
    MissionQuery = RojoFolder and RojoFolder:FindFirstChild("MissionQuery"),
    MissionClaim = RojoFolder and RojoFolder:FindFirstChild("MissionClaim"),
    SafeDeploymentReady = RojoFolder and RojoFolder:FindFirstChild("SafeDeploymentReady"),
    SafeDeploymentRequest = RojoFolder and RojoFolder:FindFirstChild("SafeDeploymentRequest"),
    ArtyCommand = ArtyFolder and ArtyFolder:FindFirstChild("Command"),
    ArtyState = ArtyFolder and ArtyFolder:FindFirstChild("State"),
}

local Consts = {
    BulletSpeed = tonumber(GameSettings.BULLET_SPEED) or 1000,
    BulletGravity = tonumber(GameSettings.BULLET_GRAVITY) or 10,
    CombatRange = tonumber(GameSettings.COMBAT_RANGE) or 500,
    ChantCooldown = tonumber(GameSettings.CHANT_COOLDOWN) or 10,
    ArtyCloseRadius = tonumber(GameSettings.ARTILLERY_CLOSE_FIRE_RADIUS) or 85,
    DefaultMaxZoom = tonumber(GameSettings.CAMERA_MAX_ZOOM) or 500,
    DefaultWalkSpeed = tonumber(GameSettings.PLAYER_WALK_SPEED_DEFAULT) or 50,
    ArtyMuzzleSpeed = (ArtilleryConfig and (tonumber(ArtilleryConfig.MuzzleSpeed) or tonumber(ArtilleryConfig.ShellSpeed))) or 250,
    ArtyGravityScale = (ArtilleryConfig and tonumber(ArtilleryConfig.GravityScale)) or 0.16,
}

--==============================================================================
-- 3. PURE-LUAU PNG SYNTHESIS (IMGUR 429 BYPASS FOR SPLIX ASSETS)
--==============================================================================
local PNGBuilder = {}
do
    local band, bor, bxor, rshift, lshift = bit32.band, bit32.bor, bit32.bxor, bit32.rshift, bit32.lshift

    local crcTable = table_create(256)
    for i = 0, 255 do
        local c = i
        for _ = 1, 8 do
            c = (band(c, 1) ~= 0) and bxor(rshift(c, 1), 0xEDB88320) or rshift(c, 1)
        end
        crcTable[i] = c
    end

    local function crc32(bytes)
        local c = 0xFFFFFFFF
        for i = 1, #bytes do
            c = bxor(crcTable[band(bxor(c, string_byte(bytes, i)), 0xFF)], rshift(c, 8))
        end
        return bxor(c, 0xFFFFFFFF)
    end

    local function adler32(bytes)
        local s1, s2 = 1, 0
        for i = 1, #bytes do
            s1 = (s1 + string_byte(bytes, i)) % 65521
            s2 = (s2 + s1) % 65521
        end
        return bor(lshift(s2, 16), s1)
    end

    local function u32be(n)
        n = band(n, 0xFFFFFFFF)
        return string_char(band(rshift(n, 24), 0xFF), band(rshift(n, 16), 0xFF), band(rshift(n, 8), 0xFF), band(n, 0xFF))
    end

    local function u16le(n)
        return string_char(band(n, 0xFF), band(rshift(n, 8), 0xFF))
    end

    local function chunk(ctype, data)
        local body = ctype .. data
        return u32be(#data) .. body .. u32be(crc32(body))
    end

    local function hsvToRgb(h, s, v)
        local i = math_floor(h * 6)
        local f = h * 6 - i
        local p = v * (1 - s)
        local q = v * (1 - f * s)
        local t = v * (1 - (1 - f) * s)
        local m = i % 6
        local r, g, b = v, t, p
        if m == 1 then r, g, b = q, v, p
        elseif m == 2 then r, g, b = p, v, t
        elseif m == 3 then r, g, b = p, q, v
        elseif m == 4 then r, g, b = t, p, v
        elseif m == 5 then r, g, b = v, p, q end
        return math_floor(r * 255 + 0.5), math_floor(g * 255 + 0.5), math_floor(b * 255 + 0.5)
    end

    function PNGBuilder.EncodeRGBA(width, height, pixelFn)
        local rows = table_create(height)
        for y = 0, height - 1 do
            local row = table_create(width + 1)
            row[1] = "\0"
            for x = 0, width - 1 do
                local r, g, b, a = pixelFn(x, y, width, height)
                row[x + 2] = string_char(
                    math_clamp(math_floor(r), 0, 255),
                    math_clamp(math_floor(g), 0, 255),
                    math_clamp(math_floor(b), 0, 255),
                    math_clamp(math_floor(a), 0, 255)
                )
            end
            rows[y + 1] = table_concat(row)
        end
        local raw = table_concat(rows)

        local zlibParts = { string_char(0x78, 0x01) }
        local len = #raw
        local pos = 1
        while pos <= len do
            local blockEnd = math_min(pos + 65534, len)
            local block = string_sub(raw, pos, blockEnd)
            local bLen = #block
            zlibParts[#zlibParts + 1] = string_char((blockEnd >= len) and 1 or 0)
            zlibParts[#zlibParts + 1] = u16le(bLen)
            zlibParts[#zlibParts + 1] = u16le(bxor(bLen, 0xFFFF))
            zlibParts[#zlibParts + 1] = block
            pos = blockEnd + 1
        end
        zlibParts[#zlibParts + 1] = u32be(adler32(raw))

        local ihdr = u32be(width) .. u32be(height) .. string_char(8, 6, 0, 0, 0)
        return "\137PNG\r\n\026\n" .. chunk("IHDR", ihdr) .. chunk("IDAT", table_concat(zlibParts)) .. chunk("IEND", "")
    end

    function PNGBuilder.BuildSplixAssets()
        local assets = {}
        assets.gradient = PNGBuilder.EncodeRGBA(2, 64, function(_, y, _, h)
            local t = y / (h - 1)
            if t < 0.5 then return 255, 255, 255, (1 - t * 2) * 32 end
            return 0, 0, 0, ((t - 0.5) * 2) * 76
        end)
        assets.hue = PNGBuilder.EncodeRGBA(2, 128, function(_, y, _, h)
            local r, g, b = hsvToRgb(1 - (y / (h - 1)), 1, 1)
            return r, g, b, 255
        end)
        assets.valsat = PNGBuilder.EncodeRGBA(48, 48, function(x, y, w, h)
            local sx = 1 - (x / (w - 1))
            local vy = y / (h - 1)
            local alpha = 1 - (1 - sx) * (1 - vy)
            if alpha <= 0.001 then return 0, 0, 0, 0 end
            local gray = ((sx * (1 - vy)) / alpha) * 255
            return gray, gray, gray, alpha * 255
        end)
        assets.valsat_cursor = PNGBuilder.EncodeRGBA(7, 7, function(x, y)
            local d = math_max(math_abs(x - 3), math_abs(y - 3))
            if d == 3 then return 0, 0, 0, 255 elseif d == 2 then return 255, 255, 255, 255 end
            return 0, 0, 0, 0
        end)
        assets.transp = PNGBuilder.EncodeRGBA(16, 16, function(x, y)
            local c = (((math_floor(x / 4) + math_floor(y / 4)) % 2) == 0) and 165 or 230
            return c, c, c, 255
        end)
        assets.cptransp = assets.transp
        assets.arrow_down = PNGBuilder.EncodeRGBA(9, 5, function(x, y)
            return (math_abs(x - 4) == (4 - y)) and 235 or 0, 235, 235, (math_abs(x - 4) == (4 - y)) and 255 or 0
        end)
        assets.arrow_up = PNGBuilder.EncodeRGBA(9, 5, function(x, y)
            return (math_abs(x - 4) == y) and 235 or 0, 235, 235, (math_abs(x - 4) == y) and 255 or 0
        end)
        return assets
    end
end

--==============================================================================
-- 4. LOAD SPLIX LIBRARY & PATCH ASSET LOADER + WATERMARK BEFORE INIT
--==============================================================================
local SPLIX_URL = "https://raw.githubusercontent.com/matas3535/SplixPrivateDrawingLibrary/main/Library.lua"
local rawSplix = game:HttpGet(SPLIX_URL)
local splixChunk, loadErr = loadstring(rawSplix)
assert(splixChunk, "[NWB Suite] Failed to compile Splix library: " .. tostring(loadErr))

local Library, Utility, Pointers, Theme = splixChunk()

local SynthesizedPNGs = PNGBuilder.BuildSplixAssets()
if isfolder and makefolder then
    if not isfolder("splix") then pcall(makefolder, "splix") end
    if not isfolder("splix/assets") then pcall(makefolder, "splix/assets") end
    if not isfolder("splix/configs") then pcall(makefolder, "splix/configs") end
end

if writefile and isfile then
    for name, bytes in pairs(SynthesizedPNGs) do
        local path = "splix/assets/" .. name .. ".png"
        if not isfile(path) then
            pcall(writefile, path, bytes)
        else
            local okRead, cur = pcall(readfile, path)
            if not okRead or type(cur) ~= "string" or string_sub(cur, 1, 4) ~= "\137PNG" then
                pcall(writefile, path, bytes)
            end
        end
    end
end

if Utility and type(Utility.LoadImage) == "function" then
    local origLoadImage = Utility.LoadImage
    Utility.LoadImage = function(self, instance, imageName, imageLink)
        if State.Unloaded or not instance then return end
        local key = tostring(imageName or "")
        local bytes = SynthesizedPNGs[key]
        if not bytes and isfile and readfile then
            local path = "splix/assets/" .. key .. ".png"
            if isfile(path) then
                local okRead, content = pcall(readfile, path)
                if okRead and type(content) == "string" and string_sub(content, 1, 4) == "\137PNG" then
                    bytes = content
                end
            end
        end
        if not bytes and type(imageLink) == "string" and #imageLink > 0 then
            local okHttp, fetched = pcall(game.HttpGet, game, imageLink)
            if okHttp and type(fetched) == "string" and string_sub(fetched, 1, 4) == "\137PNG" then
                bytes = fetched
                if writefile then pcall(writefile, "splix/assets/" .. key .. ".png", bytes) end
            end
        end
        if bytes then
            pcall(function() instance.Data = bytes end)
            return
        end
        pcall(origLoadImage, self, instance, imageName, imageLink)
    end
end

--==============================================================================
-- 5. LOCK-FREE POINTER HELPERS & UI BUILD (7 ENGLISH PAGES)
--==============================================================================
-- Zero-pcall fast pointer reader (eliminates ~10,000 pcalls/sec from hot loops)
local function getVal(ptr, default)
    local obj = Pointers and Pointers[ptr]
    if not obj then return default end
    local val = obj.current
    if val == nil then
        if type(obj.Get) == "function" then
            val = obj:Get()
        end
        if val == nil then return default end
    end
    local kb = obj.keybind
    if val == true and type(kb) == "table" and kb.mode ~= "Always" then
        if kb.active ~= nil then return kb.active == true end
        if type(kb.Active) == "function" then return kb:Active() == true end
    end
    return val
end

local function getColor(ptr, defaultColor, defaultAlpha)
    local val = getVal(ptr, nil)
    if type(val) == "table" and typeof(val.Color) == "Color3" then
        return val.Color, val.Transparency or (defaultAlpha or 0)
    elseif typeof(val) == "Color3" then
        return val, defaultAlpha or 0
    end
    return defaultColor, defaultAlpha or 0
end

local Cfg = {
    sa_enabled = true, sa_filter = "Enemy Only", sa_priority = "Closest to Crosshair",
    sa_part = "Head", sa_wallcheck = false, sa_players = true, sa_range = 550, sa_snap = true,
    fov_show = true, fov_filled = false, fov_radius = 180, fov_sides = 64,
    esp_enabled = true, esp_enemy_only = true, esp_friendly = false, esp_box = true,
    esp_hp = true, esp_tags = true, esp_morale = true, esp_weapon = true, esp_dist = true,
    esp_maxdist = 1100, esp_cap = 120, esp_flags = true, esp_threats = true, esp_warn_dist = 75,
    arty_hud = true, arty_arc = true, arty_warn = true, arty_minrange = 85, arty_speed = 250, arty_grav = 16,
    comp_hud = true, comp_autofocus = false,
    spy_enabled = false, spy_hud = true, spy_out = true, spy_in = true, spy_noisy = false, spy_console = false,
    qol_autodeployfix = true,
    mv_ws_on = false, mv_ws_val = 70, mv_fly_on = false, mv_fly_val = 90, mv_noclip = false,
    cam_zoom_on = true, cam_zoom_val = 1500, cam_freecam = false, cam_free_spd = 95, cam_rts = false, cam_rts_alt = 135,
    fov_color = Color3_fromRGB(235, 85, 65),
    sa_snap_color = Color3_fromRGB(255, 215, 70),
    esp_enemy_color = Color3_fromRGB(255, 75, 75),
    esp_ally_color = Color3_fromRGB(80, 185, 255),
    esp_flag_color = Color3_fromRGB(255, 220, 60),
    arty_arc_color = Color3_fromRGB(255, 145, 50),
}

local function refreshHotConfig()
    Cfg.sa_enabled = getVal("sa_enabled", true)
    Cfg.sa_filter = getVal("sa_filter", "Enemy Only")
    Cfg.sa_priority = getVal("sa_priority", "Closest to Crosshair")
    Cfg.sa_part = getVal("sa_part", "Head")
    Cfg.sa_wallcheck = getVal("sa_wallcheck", false)
    Cfg.sa_players = getVal("sa_players", true)
    Cfg.sa_range = getVal("sa_range", 550)
    Cfg.sa_snap = getVal("sa_snap", true)
    Cfg.fov_show = getVal("fov_show", true)
    Cfg.fov_filled = getVal("fov_filled", false)
    Cfg.fov_radius = getVal("fov_radius", 180)
    Cfg.fov_sides = getVal("fov_sides", 64)
    Cfg.esp_enabled = getVal("esp_enabled", true)
    Cfg.esp_enemy_only = getVal("esp_enemy_only", true)
    Cfg.esp_friendly = getVal("esp_friendly", false)
    Cfg.esp_box = getVal("esp_box", true)
    Cfg.esp_hp = getVal("esp_hp", true)
    Cfg.esp_tags = getVal("esp_tags", true)
    Cfg.esp_morale = getVal("esp_morale", true)
    Cfg.esp_weapon = getVal("esp_weapon", true)
    Cfg.esp_dist = getVal("esp_dist", true)
    Cfg.esp_maxdist = getVal("esp_maxdist", 1100)
    Cfg.esp_cap = math_floor(getVal("esp_cap", 120) or 120)
    Cfg.esp_flags = getVal("esp_flags", true)
    Cfg.esp_threats = getVal("esp_threats", true)
    Cfg.esp_warn_dist = getVal("esp_warn_dist", 75)
    Cfg.arty_hud = getVal("arty_hud", true)
    Cfg.arty_arc = getVal("arty_arc", true)
    Cfg.arty_warn = getVal("arty_warn", true)
    Cfg.arty_minrange = getVal("arty_minrange", Consts.ArtyCloseRadius)
    Cfg.arty_speed = getVal("arty_speed", Consts.ArtyMuzzleSpeed)
    Cfg.arty_grav = getVal("arty_grav", math_floor(Consts.ArtyGravityScale * 100 + 0.5))
    Cfg.comp_hud = getVal("comp_hud", true)
    Cfg.comp_autofocus = getVal("comp_autofocus", false)
    Cfg.spy_enabled = getVal("spy_enabled", false)
    Cfg.spy_hud = getVal("spy_hud", true)
    Cfg.spy_out = getVal("spy_out", true)
    Cfg.spy_in = getVal("spy_in", true)
    Cfg.spy_noisy = getVal("spy_noisy", false)
    Cfg.spy_console = getVal("spy_console", false)
    Cfg.qol_autodeployfix = getVal("qol_autodeployfix", true)
    Cfg.mv_ws_on = getVal("mv_ws_on", false)
    Cfg.mv_ws_val = getVal("mv_ws_val", 70)
    Cfg.mv_fly_on = getVal("mv_fly_on", false)
    Cfg.mv_fly_val = getVal("mv_fly_val", 90)
    Cfg.mv_noclip = getVal("mv_noclip", false)
    Cfg.cam_zoom_on = getVal("cam_zoom_on", true)
    Cfg.cam_zoom_val = getVal("cam_zoom_val", 1500)
    Cfg.cam_freecam = getVal("cam_freecam", false)
    Cfg.cam_free_spd = getVal("cam_free_spd", 95)
    Cfg.cam_rts = getVal("cam_rts", false)
    Cfg.cam_rts_alt = getVal("cam_rts_alt", 135)
    Cfg.fov_color = getColor("fov_color", Cfg.fov_color)
    Cfg.sa_snap_color = getColor("sa_snap_color", Cfg.sa_snap_color)
    Cfg.esp_enemy_color = getColor("esp_enemy_color", Cfg.esp_enemy_color)
    Cfg.esp_ally_color = getColor("esp_ally_color", Cfg.esp_ally_color)
    Cfg.esp_flag_color = getColor("esp_flag_color", Cfg.esp_flag_color)
    Cfg.arty_arc_color = getColor("arty_arc_color", Cfg.arty_arc_color)
end

local Window = Library:New({
    Name = "rave.hook | NWB ",
    Size = Vector2_new(660, 560),
    Accent = Color3_fromRGB(220, 75, 55),
})
Window.uibind = Enum.KeyCode.RightShift

local WatermarkDrawings = {}
Window.Watermark = function(self)
    local wmBg = newDrawing("Square", { Visible = true, Filled = true, Color = Color3_fromRGB(20, 20, 20), Size = Vector2_new(250, 22), Position = Vector2_new(12, 12), ZIndex = 200 })
    local wmBorder = newDrawing("Square", { Visible = true, Filled = false, Thickness = 1, Color = Color3_fromRGB(48, 48, 48), Size = Vector2_new(250, 22), Position = Vector2_new(12, 12), ZIndex = 201 })
    local wmAccent = newDrawing("Square", { Visible = true, Filled = true, Color = Theme and Theme.accent or Color3_fromRGB(220, 75, 55), Size = Vector2_new(250, 2), Position = Vector2_new(12, 12), ZIndex = 202 })
    local wmText = newDrawing("Text", { Visible = true, Size = 13, Font = Drawing.Fonts and Drawing.Fonts.Plex or 2, Outline = true, Color = Color3_fromRGB(235, 235, 235), Position = Vector2_new(18, 15), Text = "NWB Suite | Initializing...", ZIndex = 203 })
    WatermarkDrawings = { wmBg, wmBorder, wmAccent, wmText }

    task.spawn(function()
        local lastShow, lastText, lastAccent
        while not State.Unloaded do
            local show = getVal("ui_watermark", true)
            local txt = string_format("NWB Tactical | %s | Units: %d | Comp #%d", LocalPlayer.Name, State.NpcSnapshotCount, State.OwnedCompanyIdx or 0)
            local accentCol = (Theme and Theme.accent) or wmAccent.Color
            if txt ~= lastText or show ~= lastShow or accentCol ~= lastAccent then
                lastText, lastShow, lastAccent = txt, show, accentCol
                pcall(function()
                    wmText.Text = txt
                    local width = math_max(180, wmText.TextBounds.X + 14)
                    local sz = Vector2_new(width, 22)
                    wmBg.Size = sz
                    wmBorder.Size = sz
                    wmAccent.Size = Vector2_new(width, 2)
                    wmAccent.Color = accentCol
                    local vis = show and not State.Unloaded
                    for _, d in ipairs(WatermarkDrawings) do d.Visible = vis end
                end)
            end
            task.wait(0.25)
        end
    end)

    return { Update = function() end }
end

local Actions = {
    ToggleAttackHold = function(...) end, OrderFormationAtAim = function(...) end,
    ApplyFireDoctrine = function(...) end, ApplyBearerMode = function(...) end,
    ApplyGuardMode = function(...) end, TriggerChant = function(...) end,
    ArtySend = function(...) end, ArtyTargetBest = function(...) end,
    ArtyApplyStyle = function(...) end, ToggleBuiltInFreecam = function(...) end,
    DumpSpyToConsole = function(...) end, ClaimMissions = function(...) end,
    PrintMissions = function(...) end, VoteMode = function(...) end,
    VoteMapAndTime = function(...) end, SaveConfigSlot = function(...) end,
    LoadConfigSlot = function(...) end, DeleteConfigSlot = function(...) end,
    CopyConfigJson = function(...) end, ScanOwnedCompany = function(...) end,
    FixDeploymentScreen = function(...) end,
}

-- Page 1: Combat
local PageCombat = Window:Page({ Name = "Combat" })
do
    local SecAim = PageCombat:Section({ Name = "Silent Aim", Side = "Left" })
    local tSa = SecAim:Toggle({ Name = "Enable Silent Aim", Default = true, Pointer = "sa_enabled" })
    tSa:Keybind({ Default = Enum.KeyCode.Q, Mode = "Always", KeybindName = "Silent Aim", Pointer = "sa_key" })
    SecAim:Dropdown({ Name = "Target Filter", Options = { "Enemy Only", "All Teams" }, Default = "Enemy Only", Pointer = "sa_filter" })
    SecAim:Dropdown({ Name = "Target Priority", Options = { "Closest to Crosshair", "Closest Distance", "Lowest HP", "Flag Bearers First" }, Default = "Closest to Crosshair", Pointer = "sa_priority" })
    SecAim:Dropdown({ Name = "Aim Part", Options = { "Head", "HumanoidRootPart", "UpperTorso", "Random" }, Default = "Head", Pointer = "sa_part" })
    SecAim:Slider({ Name = "Hit Chance", Min = 0, Max = 100, Default = 100, Suffix = "%", Pointer = "sa_hitchance" })
    SecAim:Slider({ Name = "Max Aim Range", Min = 50, Max = 1200, Default = 550, Suffix = " st", Pointer = "sa_range" })
    SecAim:Toggle({ Name = "Ballistic Drop & Lead", Default = true, Pointer = "sa_predict" })
    SecAim:Toggle({ Name = "Visibility Wall Check", Default = false, Pointer = "sa_wallcheck" })
    SecAim:Toggle({ Name = "Target Players Too", Default = true, Pointer = "sa_players" })

    local SecFov = PageCombat:Section({ Name = "FOV & Ballistics", Side = "Right" })
    local tFov = SecFov:Toggle({ Name = "Show FOV Circle", Default = true, Pointer = "fov_show" })
    tFov:Colorpicker({ Default = Color3_fromRGB(235, 85, 65), Transparency = 0, Pointer = "fov_color" })
    SecFov:Toggle({ Name = "Filled FOV", Default = false, Pointer = "fov_filled" })
    SecFov:Slider({ Name = "FOV Radius", Min = 30, Max = 600, Default = 180, Suffix = " px", Pointer = "fov_radius" })
    SecFov:Slider({ Name = "FOV Sides", Min = 16, Max = 90, Default = 64, Pointer = "fov_sides" })
    local tSnap = SecFov:Toggle({ Name = "Target Snap Line", Default = true, Pointer = "sa_snap" })
    tSnap:Colorpicker({ Default = Color3_fromRGB(255, 215, 70), Transparency = 0, Pointer = "sa_snap_color" })
    SecFov:Toggle({ Name = "Override Speed / Gravity", Default = false, Pointer = "sa_override_ballistics" })
    SecFov:Slider({ Name = "Custom Bullet Speed", Min = 400, Max = 2500, Default = math_floor(Consts.BulletSpeed), Pointer = "sa_speed" })
    SecFov:Slider({ Name = "Custom Gravity", Min = 0, Max = 30, Default = math_floor(Consts.BulletGravity), Pointer = "sa_gravity" })

    local SecMod = PageCombat:Section({ Name = "Weapon & Hit Assist", Side = "Right" })
    SecMod:Toggle({ Name = "No Spread Override", Default = true, Pointer = "sa_nospread" })
    SecMod:Toggle({ Name = "Log Outgoing Hit Reports", Default = false, Pointer = "sa_log_hits" })
    SecMod:Toggle({ Name = "Experimental Direct Hit Sync", Default = false, Pointer = "sa_direct_hit" })
    SecMod:Button({ Name = "Clear Locked Target", Callback = function() State.SilentAimTarget = nil end })
end

-- Page 2: Company
local PageCompany = Window:Page({ Name = "Company" })
do
    local SecAuto = PageCompany:Section({ Name = "Company Automation", Side = "Left" })
    SecAuto:Slider({ Name = "Company Index (0 = Auto)", Min = 0, Max = 6, Default = 0, Pointer = "comp_index" })
    local tFocus = SecAuto:Toggle({ Name = "Auto Focus Fire Nearest", Default = false, Pointer = "comp_autofocus" })
    tFocus:Keybind({ Default = Enum.KeyCode.F, Mode = "Always", KeybindName = "Auto Focus", Pointer = "comp_focus_key" })
    SecAuto:Dropdown({ Name = "Focus Target Scope", Options = { "Enemy Only", "Any Alive" }, Default = "Enemy Only", Pointer = "comp_focus_scope" })
    SecAuto:Toggle({ Name = "Auto Melee Assist", Default = false, Pointer = "comp_automelee" })
    SecAuto:Slider({ Name = "Melee Engage Radius", Min = 10, Max = 120, Default = 40, Suffix = " st", Pointer = "comp_melee_rad" })
    SecAuto:Toggle({ Name = "Smart Auto Face Enemy", Default = false, Pointer = "comp_autoface" })
    SecAuto:Slider({ Name = "Order Interval (x0.1s)", Min = 2, Max = 20, Default = 4, Pointer = "comp_interval" })
    SecAuto:Toggle({ Name = "Auto Chant (10s Cooldown)", Default = false, Pointer = "comp_autochant" })

    local SecForm = PageCompany:Section({ Name = "Formation & Hold", Side = "Left" })
    SecForm:Toggle({ Name = "Auto Orbit / Keep Distance", Default = false, Pointer = "comp_orbit" })
    SecForm:Slider({ Name = "Preferred Combat Dist", Min = 25, Max = 260, Default = 85, Suffix = " st", Pointer = "comp_hold_dist" })
    SecForm:ButtonHolder({ Buttons = {
        { "Toggle Attack Hold", function() Actions.ToggleAttackHold() end },
        { "Form Line at Aim", function() Actions.OrderFormationAtAim() end },
    } })

    local SecDoc = PageCompany:Section({ Name = "Doctrine & Guard", Side = "Right" })
    SecDoc:Dropdown({ Name = "Fire Doctrine", Options = { "FireAtWill", "Volley", "Ripple", "HoldFire" }, Default = "FireAtWill", Pointer = "comp_doctrine" })
    SecDoc:Button({ Name = "Apply Fire Doctrine", Callback = function() Actions.ApplyFireDoctrine() end })
    SecDoc:Dropdown({ Name = "Bearer Mode", Options = { "0 - CENTER", "1 - LEFT", "2 - RIGHT", "3 - PACING" }, Default = "0 - CENTER", Pointer = "comp_bearer" })
    SecDoc:Button({ Name = "Apply Bearer Mode", Callback = function() Actions.ApplyBearerMode() end })
    SecDoc:Dropdown({ Name = "Flag Guard Mode", Options = { "FLAG", "LINE" }, Default = "FLAG", Pointer = "comp_guard" })
    SecDoc:Button({ Name = "Apply Flag Guard Mode", Callback = function() Actions.ApplyGuardMode() end })
    SecDoc:Toggle({ Name = "Show Company Status HUD", Default = true, Pointer = "comp_hud" })
    SecDoc:Button({ Name = "Trigger Chant Now", Callback = function() Actions.TriggerChant(true) end })
end

-- Page 3: Artillery
local PageArty = Window:Page({ Name = "Artillery" })
do
    local SecArtyAuto = PageArty:Section({ Name = "Battery Automation", Side = "Left" })
    local tArtyFire = SecArtyAuto:Toggle({ Name = "Auto Fire When Ready", Default = false, Pointer = "arty_autofire" })
    tArtyFire:Keybind({ Default = Enum.KeyCode.G, Mode = "Always", KeybindName = "Arty AutoFire", Pointer = "arty_fire_key" })
    SecArtyAuto:Toggle({ Name = "Auto Drill Advance", Default = false, Pointer = "arty_autodrill" })
    SecArtyAuto:Toggle({ Name = "Auto Target Best Company", Default = false, Pointer = "arty_autotarget" })
    SecArtyAuto:Dropdown({ Name = "Target Priority", Options = { "Densest Company", "Closest Safe", "Lowest Avg HP" }, Default = "Densest Company", Pointer = "arty_priority" })
    SecArtyAuto:Slider({ Name = "Safe Min Range", Min = 50, Max = 300, Default = math_floor(Consts.ArtyCloseRadius), Suffix = " st", Pointer = "arty_minrange" })
    SecArtyAuto:Dropdown({ Name = "Preferred Shot Style", Options = { "OVERHEAD", "STRAIGHT" }, Default = "OVERHEAD", Pointer = "arty_style" })

    local SecArtyManual = PageArty:Section({ Name = "Manual Battery Commands", Side = "Left" })
    SecArtyManual:ButtonHolder({ Buttons = {
        { "Fire Battery", function() Actions.ArtySend("FIRE") end },
        { "Cycle Ammo", function() Actions.ArtySend("CYCLE") end },
    } })
    SecArtyManual:ButtonHolder({ Buttons = {
        { "Drill Advance", function() Actions.ArtySend("DRILL_ADVANCE") end },
        { "Target Best", function() Actions.ArtyTargetBest() end },
    } })
    SecArtyManual:Button({ Name = "Apply Shot Style", Callback = function() Actions.ArtyApplyStyle() end })

    local SecArtyVis = PageArty:Section({ Name = "Artillery HUD & Arc", Side = "Right" })
    SecArtyVis:Toggle({ Name = "Show Reload & Crew HUD", Default = true, Pointer = "arty_hud" })
    local tArc = SecArtyVis:Toggle({ Name = "3D Ballistic Trajectory Arc", Default = true, Pointer = "arty_arc" })
    tArc:Colorpicker({ Default = Color3_fromRGB(255, 145, 50), Transparency = 0, Pointer = "arty_arc_color" })
    SecArtyVis:Slider({ Name = "Arc Gravity Scale (%)", Min = 10, Max = 45, Default = math_floor(Consts.ArtyGravityScale * 100 + 0.5), Suffix = "%", Pointer = "arty_grav" })
    SecArtyVis:Slider({ Name = "Arc Muzzle Speed", Min = 150, Max = 500, Default = math_floor(Consts.ArtyMuzzleSpeed), Pointer = "arty_speed" })
    SecArtyVis:Toggle({ Name = "Close Threat Alert (<= 85st)", Default = true, Pointer = "arty_warn" })
end

-- Page 4: Visuals
local PageVisuals = Window:Page({ Name = "Visuals" })
do
    local SecEsp = PageVisuals:Section({ Name = "Tactical Unit ESP", Side = "Left" })
    local tEsp = SecEsp:Toggle({ Name = "Enable ESP", Default = true, Pointer = "esp_enabled" })
    tEsp:Keybind({ Default = Enum.KeyCode.V, Mode = "Always", KeybindName = "Unit ESP", Pointer = "esp_key" })
    SecEsp:Toggle({ Name = "Enemy Only", Default = true, Pointer = "esp_enemy_only" })
    local tBox = SecEsp:Toggle({ Name = "2D Bounding Box", Default = true, Pointer = "esp_box" })
    tBox:Colorpicker({ Default = Color3_fromRGB(255, 75, 75), Transparency = 0, Pointer = "esp_enemy_color" })
    local tTeamCol = SecEsp:Toggle({ Name = "Show Friendly Units", Default = false, Pointer = "esp_friendly" })
    tTeamCol:Colorpicker({ Default = Color3_fromRGB(80, 185, 255), Transparency = 0, Pointer = "esp_ally_color" })
    SecEsp:Toggle({ Name = "Health Bar", Default = true, Pointer = "esp_hp" })
    SecEsp:Toggle({ Name = "Role / Company / Owner", Default = true, Pointer = "esp_tags" })
    SecEsp:Toggle({ Name = "Morale & Suppression", Default = true, Pointer = "esp_morale" })
    SecEsp:Toggle({ Name = "Weapon State", Default = true, Pointer = "esp_weapon" })
    SecEsp:Toggle({ Name = "Distance Label", Default = true, Pointer = "esp_dist" })
    SecEsp:Slider({ Name = "Max ESP Distance", Min = 100, Max = 2500, Default = 1100, Suffix = " st", Pointer = "esp_maxdist" })

    local SecObj = PageVisuals:Section({ Name = "Objectives & Warnings", Side = "Right" })
    local tFlag = SecObj:Toggle({ Name = "Dropped Flag Tracker", Default = true, Pointer = "esp_flags" })
    tFlag:Colorpicker({ Default = Color3_fromRGB(255, 220, 60), Transparency = 0, Pointer = "esp_flag_color" })
    SecObj:Toggle({ Name = "Threat Warning HUD", Default = true, Pointer = "esp_threats" })
    SecObj:Slider({ Name = "Charge Warn Distance", Min = 25, Max = 200, Default = 75, Suffix = " st", Pointer = "esp_warn_dist" })
    SecObj:Slider({ Name = "Max Rendered ESP Units", Min = 20, Max = 250, Default = 120, Pointer = "esp_cap" })

    local SecWorld = PageVisuals:Section({ Name = "World & Performance", Side = "Right" })
    SecWorld:Toggle({ Name = "Hide Musket Smoke", Default = false, Pointer = "vis_nosmoke" })
    SecWorld:Toggle({ Name = "FPS Boost (Shadows & FX)", Default = false, Pointer = "vis_fps" })
    SecWorld:Toggle({ Name = "Fullbright Lighting", Default = false, Pointer = "vis_fullbright" })
end

-- Page 5: Move
local PageMove = Window:Page({ Name = "Move" })
do
    local SecChar = PageMove:Section({ Name = "Character Movement", Side = "Left" })
    local tWs = SecChar:Toggle({ Name = "WalkSpeed Bypass", Default = false, Pointer = "mv_ws_on" })
    tWs:Keybind({ Default = Enum.KeyCode.X, Mode = "Always", KeybindName = "WalkSpeed", Pointer = "mv_ws_key" })
    SecChar:Slider({ Name = "WalkSpeed Value", Min = 16, Max = 180, Default = 70, Pointer = "mv_ws_val" })
    local tFly = SecChar:Toggle({ Name = "Local Fly", Default = false, Pointer = "mv_fly_on" })
    tFly:Keybind({ Default = Enum.KeyCode.H, Mode = "Always", KeybindName = "Local Fly", Pointer = "mv_fly_key" })
    SecChar:Slider({ Name = "Fly Speed", Min = 20, Max = 300, Default = 90, Pointer = "mv_fly_val" })
    local tNc = SecChar:Toggle({ Name = "Noclip", Default = false, Pointer = "mv_noclip" })
    tNc:Keybind({ Default = Enum.KeyCode.N, Mode = "Always", KeybindName = "Noclip", Pointer = "mv_noclip_key" })
    SecChar:Toggle({ Name = "Infinite Jump", Default = false, Pointer = "mv_infjump" })

    local SecCam = PageMove:Section({ Name = "Camera & Tactical View", Side = "Right" })
    SecCam:Toggle({ Name = "Unlock Camera MaxZoom", Default = true, Pointer = "cam_zoom_on" })
    SecCam:Slider({ Name = "Max Zoom Distance", Min = 128, Max = 3000, Default = 1500, Suffix = " st", Pointer = "cam_zoom_val" })
    local tFree = SecCam:Toggle({ Name = "Custom Freecam", Default = false, Pointer = "cam_freecam" })
    tFree:Keybind({ Default = Enum.KeyCode.C, Mode = "Always", KeybindName = "Freecam", Pointer = "cam_free_key" })
    SecCam:Slider({ Name = "Freecam Speed", Min = 20, Max = 300, Default = 95, Pointer = "cam_free_spd" })
    local tRts = SecCam:Toggle({ Name = "RTS Top-Down Camera", Default = false, Pointer = "cam_rts" })
    tRts:Keybind({ Default = Enum.KeyCode.T, Mode = "Always", KeybindName = "RTS View", Pointer = "cam_rts_key" })
    SecCam:Slider({ Name = "RTS Altitude", Min = 40, Max = 400, Default = 135, Suffix = " st", Pointer = "cam_rts_alt" })
    SecCam:Button({ Name = "Toggle Native Freecam GUI", Callback = function() Actions.ToggleBuiltInFreecam() end })
end

-- Page 6: Spy
local PageSpy = Window:Page({ Name = "Spy" })
do
    local SecSpy = PageSpy:Section({ Name = "Blink Binary Packet Spy", Side = "Left" })
    SecSpy:Toggle({ Name = "Enable Blink Packet Spy", Default = false, Pointer = "spy_enabled" })
    SecSpy:Toggle({ Name = "Show On-Screen Feed", Default = true, Pointer = "spy_hud" })
    SecSpy:Toggle({ Name = "Log Outgoing Packets", Default = true, Pointer = "spy_out" })
    SecSpy:Toggle({ Name = "Log Incoming Events", Default = true, Pointer = "spy_in" })
    SecSpy:Toggle({ Name = "Include NpcBatch / Ping", Default = false, Pointer = "spy_noisy" })
    SecSpy:Toggle({ Name = "Mirror Logs to Console", Default = false, Pointer = "spy_console" })
    SecSpy:ButtonHolder({ Buttons = {
        { "Clear Feed", function() table_clear(State.SpyLogs) end },
        { "Dump Last 20", function() Actions.DumpSpyToConsole() end },
    } })

    local SecQol = PageSpy:Section({ Name = "Missions & Match QoL", Side = "Right" })
    local tDeploy = SecQol:Toggle({ Name = "Auto Fix Stuck Deployment", Default = true, Pointer = "qol_autodeployfix" })
    tDeploy:Keybind({ Default = Enum.KeyCode.F4, Mode = "Always", KeybindName = "Fix Deploy", Pointer = "qol_deploy_key" })
    SecQol:Button({ Name = "Fix Deployment Screen Now", Callback = function() Actions.FixDeploymentScreen(true) end })
    SecQol:Toggle({ Name = "Auto Claim Ready Missions", Default = false, Pointer = "qol_autoclaim" })
    SecQol:Button({ Name = "Claim Ready Missions Now", Callback = function() Actions.ClaimMissions(true) end })
    SecQol:Button({ Name = "Print Missions Status", Callback = function() Actions.PrintMissions() end })
    SecQol:Toggle({ Name = "Auto Vote Preferred Mode/Map", Default = false, Pointer = "qol_autovote" })
    SecQol:Dropdown({ Name = "Preferred Game Mode", Options = { "TeamDeathmatch", "KingOfTheHill" }, Default = "TeamDeathmatch", Pointer = "qol_mode" })
    SecQol:Slider({ Name = "Map / Time Vote Option", Min = 1, Max = 4, Default = 1, Pointer = "qol_vote_opt" })
    SecQol:ButtonHolder({ Buttons = {
        { "Vote Mode", function() Actions.VoteMode() end },
        { "Vote Map & Time", function() Actions.VoteMapAndTime() end },
    } })
end

-- Page 7: Config
local PageCfg = Window:Page({ Name = "Config" })
do
    local SecCfg = PageCfg:Section({ Name = "Configuration Slots", Side = "Left" })
    SecCfg:ConfigBox({ Pointer = "cfg_slot" })
    SecCfg:ButtonHolder({ Buttons = {
        { "Save Slot", function() Actions.SaveConfigSlot() end },
        { "Load Slot", function() Actions.LoadConfigSlot() end },
    } })
    SecCfg:ButtonHolder({ Buttons = {
        { "Delete Slot", function() Actions.DeleteConfigSlot() end },
        { "Copy JSON", function() Actions.CopyConfigJson() end },
    } })

    local SecSys = PageCfg:Section({ Name = "Suite Controls", Side = "Right" })
    SecSys:Keybind({ Name = "Menu Keybind", Default = Enum.KeyCode.RightShift, KeybindName = "Menu", Pointer = "ui_menubind" })
    SecSys:Toggle({ Name = "Show Watermark", Default = true, Pointer = "ui_watermark" })
    SecSys:Toggle({ Name = "Show Keybinds List", Default = true, Pointer = "ui_keybinds" })
    SecSys:Button({ Name = "Re-Scan Game Modules", Callback = function() Actions.ScanOwnedCompany(true) end })
    SecSys:Button({ Name = "Unload Suite Safely", Callback = function()
        if type(env._NWB_SPLIX_UNLOAD) == "function" then
            task.defer(env._NWB_SPLIX_UNLOAD)
        end
    end })
end

Window:Initialize()

--==============================================================================
-- 6. WORLD / ENTITY / TEAM HELPERS & EVENT-DRIVEN SNAPSHOT CACHE
--==============================================================================
local function getLocalTeamName()
    local char = LocalPlayer.Character
    if char then
        local attr = char:GetAttribute("TeamName")
        if attr then return tostring(attr) end
    end
    local tm = LocalPlayer.Team
    if tm and tm.Name then return tm.Name end
    return tostring(LocalPlayer:GetAttribute("TeamName") or "")
end

local function isSameTeamWith(myTeam, unitTeamName, playerTeamObj)
    if unitTeamName and unitTeamName ~= "" and myTeam ~= "" then
        return tostring(unitTeamName) == myTeam
    end
    if playerTeamObj and LocalPlayer.Team then
        return playerTeamObj == LocalPlayer.Team
    end
    return false
end

local function resolveCharacterParts(model)
    if not model then return nil, nil, nil end
    local head = model:FindFirstChild("Head")
    local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
    local upper = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or hrp
    return head, hrp, upper
end

local function chooseAimPart(unit, mode)
    if mode == "Random" then
        local h, r, u = unit.Head, unit.HRP, unit.Upper
        local n = (h and 1 or 0) + (r and 1 or 0) + (u and 1 or 0)
        if n > 0 then
            local pick = math_random(1, n)
            if h then if pick == 1 then return h end pick -= 1 end
            if r then if pick == 1 then return r end pick -= 1 end
            return u
        end
    elseif mode == "HumanoidRootPart" then
        return unit.HRP or unit.Head or unit.Upper
    elseif mode == "UpperTorso" then
        return unit.Upper or unit.HRP or unit.Head
    end
    return unit.Head or unit.HRP or unit.Upper
end

local function rebuildUnitTopLabel(rec)
    local p1
    if rec.IsBearer then p1 = "[BEARER]"
    elseif rec.IsGuard then p1 = "[GUARD]"
    elseif rec.Role ~= "" and rec.Role ~= "LineInfantry" then p1 = "[" .. rec.Role .. "]" end
    local p2 = rec.CompanyIndex and (COMPANY_STRINGS[rec.CompanyIndex] or ("C" .. tostring(rec.CompanyIndex))) or rec.Name
    rec.TopTag = p1 and (p1 .. " " .. p2) or p2
end

local function rebuildUnitBotLabels(rec)
    rec.MoraleInt = math_floor(rec.Suppression)
    if rec.Morale ~= "" or rec.Suppression > 0 then
        local m = rec.Morale ~= "" and rec.Morale or "Steady"
        rec.BotMorale = (rec.Suppression > 0) and string_format("%s S:%d", m, rec.MoraleInt) or m
    else
        rec.BotMorale = ""
    end
    if rec.WeaponState ~= "" and rec.BotMorale ~= "" then
        rec.BotBoth = rec.WeaponState .. " | " .. rec.BotMorale
    elseif rec.WeaponState ~= "" then
        rec.BotBoth = rec.WeaponState
    else
        rec.BotBoth = rec.BotMorale
    end
end

local function trackWorkspaceFlag(obj, add)
    if not obj or string_sub(obj.Name, 1, 12) ~= "DroppedFlag_" then return end
    if add then
        local part = obj:IsA("BasePart") and obj or (obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")))
        State.DroppedFlags[obj] = part or obj
    else
        State.DroppedFlags[obj] = nil
    end
end

for _, obj in ipairs(Workspace:GetChildren()) do trackWorkspaceFlag(obj, true) end
addConn(Workspace.ChildAdded:Connect(function(obj) if not State.Unloaded then trackWorkspaceFlag(obj, true) end end))
addConn(Workspace.ChildRemoved:Connect(function(obj) State.DroppedFlags[obj] = nil end))

-- Event-driven Npc_Registry model list (eliminates 20Hz GetChildren() table allocations)
local function bindNpcFolder(folder)
    for _, c in ipairs(State.NpcFolderConns) do pcall(function() c:Disconnect() end) end
    table_clear(State.NpcFolderConns)
    table_clear(State.NpcModels)
    table_clear(State.NpcRecordCache)
    State.LastNpcFolder = folder
    if not folder then return end

    local models = State.NpcModels
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Model") then models[#models + 1] = child end
    end
    local cAdd = folder.ChildAdded:Connect(function(child)
        if not State.Unloaded and child:IsA("Model") then
            models[#models + 1] = child
        end
    end)
    local cRem = folder.ChildRemoved:Connect(function(child)
        State.NpcRecordCache[child] = nil
        for i = #models, 1, -1 do
            if models[i] == child then
                table_remove(models, i)
                break
            end
        end
    end)
    State.NpcFolderConns[1] = cAdd
    State.NpcFolderConns[2] = cRem
    addConn(cAdd)
    addConn(cRem)
end

local PlayerRecordCache = {}
local OwnedVotesScratch = {}

addConn(Players.PlayerRemoving:Connect(function(plr) PlayerRecordCache[plr] = nil end))

local function refreshSnapshots()
    local snapshots = State.NpcSnapshots
    local clusters = State.CompanyClusters
    local npcCache = State.NpcRecordCache
    local tickId = State.NpcSnapshotTick + 1
    State.NpcSnapshotTick = tickId
    -- Poll heavy dynamic attributes every 4th tick (5Hz) while Position/Health update at full 20Hz
    local pollDynamicAttrs = (tickId % 4 == 1)

    local writeIdx = 0
    local myTeam = getLocalTeamName()
    local myUserId = LocalPlayer.UserId

    for idx in pairs(OwnedVotesScratch) do OwnedVotesScratch[idx] = 0 end
    for _, c in pairs(clusters) do
        c.Count = 0
        c.SumPos = Vector3_zero
        c.SumHp = 0
        c.SumMaxHp = 0
    end

    local npcClientFolder = Workspace:FindFirstChild("Npc_Registry")
    local npcServerFolder = Workspace:FindFirstChild("Npc_Registry_Server")
    if npcClientFolder ~= State.LastNpcFolder then
        bindNpcFolder(npcClientFolder)
    end

    if npcClientFolder then
        local models = State.NpcModels
        for i = 1, #models do
            local model = models[i]
            if model and model.Parent then
                local rec = npcCache[model]
                if not rec then
                    rec = {
                        IsNPC = true,
                        Model = model,
                        Name = model.Name,
                        NpcId = tonumber(string_match(model.Name, "^NPC_(%d+)$")),
                        TopTag = model.Name,
                        BotMorale = "",
                        BotBoth = "",
                        WeaponState = "",
                        Morale = "",
                        Suppression = 0,
                        MoraleInt = 0,
                        Role = "",
                        TeamName = "",
                        IsBearer = false,
                        IsGuard = false,
                    }
                    npcCache[model] = rec
                end

                if not rec.HRP or not rec.HRP.Parent or not rec.Head then
                    rec.Head, rec.HRP, rec.Upper = resolveCharacterParts(model)
                end

                local head, hrp = rec.Head, rec.HRP
                if hrp or head then
                    if not rec.ServerModel or not rec.ServerModel.Parent then
                        rec.ServerModel = npcServerFolder and npcServerFolder:FindFirstChild(model.Name) or nil
                        rec.Humanoid = nil
                    end
                    local serverModel = rec.ServerModel
                    if not rec.Humanoid or not rec.Humanoid.Parent then
                        rec.Humanoid = (serverModel and serverModel:FindFirstChildOfClass("Humanoid"))
                            or model:FindFirstChildOfClass("Humanoid")
                    end

                    local hum = rec.Humanoid
                    local hp = hum and hum.Health or 100
                    local maxHp = hum and hum.MaxHealth or 100

                    if hp > 0 and maxHp > 0 then
                        -- Static/semi-static identity attributes: read once or until populated
                        local ownerId = rec.OwnerUserId
                        if not ownerId then
                            ownerId = tonumber(model:GetAttribute("OwnerUserId"))
                            rec.OwnerUserId = ownerId
                        end
                        local compIdx = rec.CompanyIndex
                        if not compIdx then
                            compIdx = tonumber(model:GetAttribute("CompanyIndex"))
                            rec.CompanyIndex = compIdx
                        end
                        local teamName = rec.TeamName
                        if teamName == "" then
                            teamName = tostring(model:GetAttribute("TeamName") or (serverModel and serverModel:GetAttribute("TeamName")) or "")
                            rec.TeamName = teamName
                        end
                        local role = rec.Role
                        if role == "" then
                            role = tostring(model:GetAttribute("NWBRole") or model:GetAttribute("ClassKey") or "")
                            rec.Role = role
                        end

                        -- Dynamic combat state attributes: polled at 5Hz or on first init
                        if pollDynamicAttrs or not rec._tagsInit then
                            local isBearer = model:GetAttribute("IsFlagBearer") == true
                            local isGuard = (serverModel and serverModel:GetAttribute("IsFlagGuard") == true)
                                or (model:GetAttribute("IsFlagGuard") == true)
                            local weaponState = tostring(
                                model:GetAttribute("NWB_PendingWeaponState")
                                or (serverModel and serverModel:GetAttribute("NWB_WeaponState"))
                                or ""
                            )
                            local morale = tostring((serverModel and serverModel:GetAttribute("MoraleState")) or "")
                            local suppression = (serverModel and tonumber(serverModel:GetAttribute("Suppression"))) or 0

                            local topChanged = (rec.IsBearer ~= isBearer) or (rec.IsGuard ~= isGuard) or not rec._tagsInit
                            local botChanged = (rec.WeaponState ~= weaponState)
                                or (rec.Morale ~= morale)
                                or (rec.MoraleInt ~= math_floor(suppression))
                                or not rec._tagsInit

                            rec.IsBearer = isBearer
                            rec.IsGuard = isGuard
                            rec.WeaponState = weaponState
                            rec.Morale = morale
                            rec.Suppression = suppression

                            if topChanged then rebuildUnitTopLabel(rec) end
                            if botChanged then rebuildUnitBotLabels(rec) end
                            rec._tagsInit = true
                        end

                        local friendly = isSameTeamWith(myTeam, teamName, nil)
                        local pos = (hrp and hrp.Position) or head.Position

                        if ownerId == myUserId and compIdx then
                            OwnedVotesScratch[compIdx] = (OwnedVotesScratch[compIdx] or 0) + 1
                        end

                        rec.Position = pos
                        rec.Health = hp
                        rec.MaxHealth = maxHp
                        rec.Friendly = friendly

                        writeIdx += 1
                        snapshots[writeIdx] = rec

                        if ownerId and compIdx then
                            local key = rec._clusterKey
                            if not key then
                                key = teamName .. "|" .. tostring(ownerId) .. "|" .. tostring(compIdx)
                                rec._clusterKey = key
                            end
                            local c = clusters[key]
                            if not c then
                                c = {
                                    Key = key, TeamName = teamName, Friendly = friendly,
                                    OwnerUserId = ownerId, CompanyIndex = compIdx,
                                    Count = 0, SumPos = Vector3_zero, SumHp = 0, SumMaxHp = 0,
                                    Centroid = Vector3_zero, AvgHp = 100,
                                }
                                clusters[key] = c
                            end
                            c.Friendly = friendly
                            c.Count += 1
                            c.SumPos += pos
                            c.SumHp += hp
                            c.SumMaxHp += maxHp
                        end
                    end
                end
            end
        end
    end

    if Cfg.sa_players or Cfg.esp_enabled then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local char = plr.Character
                local prec = PlayerRecordCache[plr]
                if not prec then
                    prec = {
                        IsNPC = false, Player = plr, Name = plr.Name, Role = "Player",
                        CompanyIndex = nil, OwnerUserId = plr.UserId, IsGuard = false,
                        Morale = "", Suppression = 0, MoraleInt = 0, BotMorale = "",
                        BotBoth = "", WeaponState = "", IsBearer = false,
                    }
                    PlayerRecordCache[plr] = prec
                end
                if prec.Model ~= char or not prec.HRP or not prec.HRP.Parent then
                    prec.Model = char
                    prec.Head, prec.HRP, prec.Upper = resolveCharacterParts(char)
                    prec.Humanoid = char:FindFirstChildOfClass("Humanoid")
                    prec._tagsInit = false
                end
                local hum = prec.Humanoid
                local head, hrp = prec.Head, prec.HRP
                if hum and hum.Health > 0 and (hrp or head) then
                    local teamName = tostring(char:GetAttribute("TeamName") or (plr.Team and plr.Team.Name) or "")
                    local friendly = isSameTeamWith(myTeam, teamName, plr.Team)
                    if pollDynamicAttrs or not prec._tagsInit then
                        local isBearer = char:GetAttribute("IsFlagBearer") == true
                        local weaponState = tostring(char:GetAttribute("NWB_PendingWeaponState") or "")
                        local topChanged = (prec.IsBearer ~= isBearer) or not prec._tagsInit
                        local botChanged = (prec.WeaponState ~= weaponState) or not prec._tagsInit
                        prec.IsBearer = isBearer
                        prec.WeaponState = weaponState
                        if topChanged then rebuildUnitTopLabel(prec) end
                        if botChanged then rebuildUnitBotLabels(prec) end
                        prec._tagsInit = true
                    end

                    prec.Position = (hrp and hrp.Position) or head.Position
                    prec.Health = hum.Health
                    prec.MaxHealth = math_max(1, hum.MaxHealth)
                    prec.TeamName = teamName
                    prec.Friendly = friendly

                    writeIdx += 1
                    snapshots[writeIdx] = prec
                end
            end
        end
    end

    for i = writeIdx + 1, State.NpcSnapshotCount do snapshots[i] = nil end
    State.NpcSnapshotCount = writeIdx

    for _, c in pairs(clusters) do
        if c.Count > 0 then
            c.Centroid = c.SumPos / c.Count
            c.AvgHp = c.SumHp / c.Count
        end
    end

    local forcedIdx = math_floor(getVal("comp_index", 0) or 0)
    if forcedIdx > 0 then
        State.OwnedCompanyIdx = forcedIdx
    else
        local bestIdx, bestVotes = State.OwnedCompanyIdx, 0
        for idx, count in pairs(OwnedVotesScratch) do
            if count > bestVotes then
                bestVotes = count
                bestIdx = idx
            end
        end
        if bestVotes > 0 then State.OwnedCompanyIdx = bestIdx end
    end
    State.MyCompanyAliveCount = OwnedVotesScratch[State.OwnedCompanyIdx] or 0
end

local SharedLosParams = RaycastParams.new()
SharedLosParams.FilterType = Enum.RaycastFilterType.Exclude
local SharedLosIgnore = {}

local function isLineOfSightClear(origin, part, model)
    SharedLosIgnore[1] = LocalPlayer.Character or model
    SharedLosIgnore[2] = LocalPlayer.Character and model or nil
    SharedLosParams.FilterDescendantsInstances = SharedLosIgnore
    local result = Workspace:Raycast(origin, part.Position - origin, SharedLosParams)
    if not result then return true end
    return result.Instance and result.Instance:IsDescendantOf(model)
end

--==============================================================================
-- 7. COMBAT: SILENT AIM, BALLISTICS & MUSKETUTILS HOOK
--==============================================================================
local function computeAimPoint(origin, targetPart, speed, gravity, predict)
    local tPos = targetPart.Position
    if not predict then return tPos end
    local vel = targetPart.AssemblyLinearVelocity or Vector3_zero
    if vel.X ~= vel.X or vel.Magnitude > 500 then vel = Vector3_zero end
    local invSpeed = 1 / math_max(50, speed)
    local flightTime = (tPos - origin).Magnitude * invSpeed
    local predicted = tPos + vel * flightTime
    flightTime = (predicted - origin).Magnitude * invSpeed
    predicted = tPos + vel * flightTime
    local drop = 0.5 * gravity * flightTime * flightTime
    return predicted + Vector3_new(0, drop, 0)
end

local function findSilentAimTarget()
    if not Cfg.sa_enabled or not Camera then return nil end
    local fovRadius = Cfg.fov_radius
    local maxRange = Cfg.sa_range
    local maxRangeSq = maxRange * maxRange
    local fovRadiusSq = fovRadius * fovRadius
    local filterAll = (Cfg.sa_filter == "All Teams")
    local prioMode = Cfg.sa_priority
    local partMode = Cfg.sa_part
    local wallCheck = Cfg.sa_wallcheck
    local allowPlayers = Cfg.sa_players

    local vp = Camera.ViewportSize
    local cx, cy = vp.X * 0.5, vp.Y * 0.5
    local cCF = Camera.CFrame
    local cPos = cCF.Position
    local cLook = cCF.LookVector
    local clX, clY, clZ = cLook.X, cLook.Y, cLook.Z
    local cpX, cpY, cpZ = cPos.X, cPos.Y, cPos.Z

    local char = LocalPlayer.Character
    local head = char and char:FindFirstChild("Head")
    local origin = (head and head.Position) or cPos
    local ox, oy, oz = origin.X, origin.Y, origin.Z

    local bestCandidate = nil
    local bestScore = math.huge
    local snapshots = State.NpcSnapshots

    for i = 1, State.NpcSnapshotCount do
        local unit = snapshots[i]
        if (unit.IsNPC or allowPlayers) and (filterAll or not unit.Friendly) then
            local part = chooseAimPart(unit, partMode)
            if part then
                local pPos = part.Position
                local dx, dy, dz = pPos.X - ox, pPos.Y - oy, pPos.Z - oz
                local distSq = dx * dx + dy * dy + dz * dz
                if distSq <= maxRangeSq then
                    local cdx, cdy, cdz = pPos.X - cpX, pPos.Y - cpY, pPos.Z - cpZ
                    if (cdx * clX + cdy * clY + cdz * clZ) > 0 then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(pPos)
                        if onScreen and screenPos.Z > 0 then
                            local fx, fy = screenPos.X - cx, screenPos.Y - cy
                            local fovSq = fx * fx + fy * fy
                            if fovSq <= fovRadiusSq then
                                if (not wallCheck) or isLineOfSightClear(origin, part, unit.Model) then
                                    local fovDist = math_sqrt(fovSq)
                                    local worldDist = math_sqrt(distSq)
                                    local score = fovDist
                                    if prioMode == "Closest Distance" then score = worldDist
                                    elseif prioMode == "Lowest HP" then score = unit.Health + fovDist * 0.05
                                    elseif prioMode == "Flag Bearers First" then score = (unit.IsBearer and 0 or 5000) + fovDist end
                                    if score < bestScore then
                                        bestScore = score
                                        bestCandidate = {
                                            Unit = unit, Part = part,
                                            ScreenPos = Vector2_new(screenPos.X, screenPos.Y),
                                            WorldDist = worldDist, FovDist = fovDist,
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return bestCandidate
end

local function installCombatHook()
    if not MusketUtils or type(MusketUtils._spawnOwnerBullet) ~= "function" then return false end
    local origSpawn = MusketUtils._spawnOwnerBullet
    State.Hooks.OrigSpawnOwnerBullet = origSpawn

    MusketUtils._spawnOwnerBullet = function(self, originVec, unitDirVec, shotId, ...)
        if State.Unloaded then
            return origSpawn(self, originVec, unitDirVec, shotId, ...)
        end

        local finalOrigin = originVec
        local finalDir = unitDirVec
        local targetHitInfo = nil

        local saOn = Cfg.sa_enabled
        local hitChance = getVal("sa_hitchance", 100)
        local noSpread = getVal("sa_nospread", true)

        if saOn and math_random(1, 100) <= hitChance then
            local target = State.SilentAimTarget or findSilentAimTarget()
            if target and target.Part and target.Part.Parent then
                local useCustom = getVal("sa_override_ballistics", false)
                local spd = useCustom and getVal("sa_speed", Consts.BulletSpeed) or Consts.BulletSpeed
                local grav = useCustom and getVal("sa_gravity", Consts.BulletGravity) or Consts.BulletGravity
                local predict = getVal("sa_predict", true)
                local origin = typeof(originVec) == "Vector3" and originVec or Camera.CFrame.Position
                local aimPos = computeAimPoint(origin, target.Part, spd, grav, predict)
                local delta = aimPos - origin
                if delta.Magnitude > 0.01 then
                    finalDir = delta.Unit
                    targetHitInfo = { Target = target, AimPos = aimPos }
                end
            elseif noSpread and Camera then
                finalDir = Camera.CFrame.LookVector
            end
        elseif noSpread and Camera then
            finalDir = Camera.CFrame.LookVector
        end

        if getVal("sa_log_hits", false) and targetHitInfo then
            print(string_format("[NWB Combat] ShotId=%s -> %s (%s) dist=%.1f",
                tostring(shotId), tostring(targetHitInfo.Target.Unit.Name),
                tostring(targetHitInfo.Target.Part.Name), targetHitInfo.Target.WorldDist))
        end

        if getVal("sa_direct_hit", false)
            and targetHitInfo
            and targetHitInfo.Target.Unit.IsNPC
            and targetHitInfo.Target.Unit.NpcId
            and type(shotId) == "number"
            and BlinkClient and BlinkClient.NpcHitReport and BlinkClient.NpcHitReport.Fire
        then
            local npcId = targetHitInfo.Target.Unit.NpcId
            local hitPos = targetHitInfo.Target.Part.Position
            task.defer(function()
                if not State.Unloaded then
                    pcall(BlinkClient.NpcHitReport.Fire, shotId, npcId, hitPos)
                end
            end)
        end

        return origSpawn(self, finalOrigin, finalDir, shotId, ...)
    end
    return true
end
installCombatHook()

--==============================================================================
-- 8. COMPANY AUTOMATION & TACTICAL COMMANDS
--==============================================================================
local function getMyCompanyCentroid()
    local sum, count = Vector3_zero, 0
    local myIdx = State.OwnedCompanyIdx
    local myId = LocalPlayer.UserId
    local snapshots = State.NpcSnapshots
    for i = 1, State.NpcSnapshotCount do
        local u = snapshots[i]
        if u.IsNPC and u.OwnerUserId == myId and u.CompanyIndex == myIdx then
            sum += u.Position
            count += 1
        end
    end
    if count > 0 then return sum / count, count end
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    return (root and root.Position) or Vector3_zero, 0
end

local function findNearestCompanyCluster(fromPos, enemyOnly)
    local bestCluster, bestDistSq = nil, math.huge
    local fx, fy, fz = fromPos.X, fromPos.Y, fromPos.Z
    for _, c in pairs(State.CompanyClusters) do
        if c.Count > 0 and (not enemyOnly or not c.Friendly) then
            local ct = c.Centroid
            local dx, dy, dz = ct.X - fx, ct.Y - fy, ct.Z - fz
            local dSq = dx * dx + dy * dy + dz * dz
            if dSq < bestDistSq then
                bestDistSq = dSq
                bestCluster = c
            end
        end
    end
    return bestCluster, bestCluster and math_sqrt(bestDistSq) or math.huge
end

Actions.ScanOwnedCompany = function(announce)
    refreshSnapshots()
    if announce then
        print("[NWB Suite] Active owned company index resolved to #" .. tostring(State.OwnedCompanyIdx))
    end
end

Actions.ApplyFireDoctrine = function()
    if not Remotes.NWBCommandRequest then return end
    local doctrine = tostring(getVal("comp_doctrine", "FireAtWill"))
    pcall(function()
        Remotes.NWBCommandRequest:FireServer({
            action = "SetFireDoctrine",
            companyIndex = State.OwnedCompanyIdx,
            value = doctrine,
            requestId = HttpService:GenerateGUID(false),
        })
    end)
end

Actions.ApplyBearerMode = function()
    if not (BlinkClient and BlinkClient.BearerModeCommand and BlinkClient.BearerModeCommand.Fire) then return end
    local sel = tostring(getVal("comp_bearer", "0 - CENTER"))
    local modeInt = tonumber(string_match(sel, "^(%d+)")) or 0
    pcall(BlinkClient.BearerModeCommand.Fire, State.OwnedCompanyIdx, modeInt)
end

Actions.ApplyGuardMode = function()
    if not Remotes.SetFlagGuardMode then return end
    local guardMode = tostring(getVal("comp_guard", "FLAG"))
    pcall(function() Remotes.SetFlagGuardMode:FireServer(State.OwnedCompanyIdx, guardMode) end)
end

Actions.ToggleAttackHold = function()
    if not (BlinkClient and BlinkClient.NpcCanAttackToggle and BlinkClient.NpcCanAttackToggle.Fire) then return end
    State.PrevStates.AttackHeld = not State.PrevStates.AttackHeld
    pcall(BlinkClient.NpcCanAttackToggle.Fire, State.OwnedCompanyIdx)
end

Actions.TriggerChant = function(force)
    local now = os_clock()
    if not force and (now - State.Timers.Chant) < (Consts.ChantCooldown + 0.3) then return end
    State.Timers.Chant = now
    if Remotes.ChantContextRequest then
        pcall(function() Remotes.ChantContextRequest:FireServer() end)
    end
    if BlinkClient and BlinkClient.NpcChant and BlinkClient.NpcChant.Fire then
        pcall(BlinkClient.NpcChant.Fire, State.OwnedCompanyIdx)
    end
end

Actions.OrderFormationAtAim = function()
    if not (BlinkClient and BlinkClient.NpcOrderCommand and BlinkClient.NpcOrderCommand.Fire) then return end
    local _, count = getMyCompanyCentroid()
    local ranks = count >= 8 and 2 or 1
    local files = math_max(1, math_ceil(math_max(1, count) / ranks))
    local mouseLoc = UserInputService:GetMouseLocation()
    local ray = Camera:ViewportPointToRay(mouseLoc.X, mouseLoc.Y)
    SharedLosIgnore[1] = LocalPlayer.Character
    SharedLosIgnore[2] = nil
    SharedLosParams.FilterDescendantsInstances = SharedLosIgnore
    local res = Workspace:Raycast(ray.Origin, ray.Direction * 1500, SharedLosParams)
    local anchor = res and res.Position or (ray.Origin + ray.Direction * 100)
    local look = Camera.CFrame.LookVector
    local facing = Vector3_new(look.X, 0, look.Z)
    facing = (facing.Magnitude < 0.01) and Vector3_new(0, 0, -1) or facing.Unit
    pcall(BlinkClient.NpcOrderCommand.Fire, anchor, facing, ranks, files, State.OwnedCompanyIdx)
end

local function stepCompanyAutomation(now)
    local myIdx = State.OwnedCompanyIdx
    local centroid, count = getMyCompanyCentroid()
    local enemyOnly = getVal("comp_focus_scope", "Enemy Only") == "Enemy Only"
    local nearestEnemy, nearestDist = findNearestCompanyCluster(centroid, enemyOnly)

    local focusOn = Cfg.comp_autofocus
    if focusOn and nearestEnemy and (now - State.Timers.FocusFire) >= 0.7 then
        State.Timers.FocusFire = now
        if BlinkClient and BlinkClient.NpcFocusFireTarget and BlinkClient.NpcFocusFireTarget.Fire then
            pcall(BlinkClient.NpcFocusFireTarget.Fire, myIdx, nearestEnemy.OwnerUserId, nearestEnemy.CompanyIndex)
        end
        if not State.PrevStates.FocusActive and BlinkClient and BlinkClient.NpcFocusFireToggle and BlinkClient.NpcFocusFireToggle.Fire then
            State.PrevStates.FocusActive = true
            pcall(BlinkClient.NpcFocusFireToggle.Fire, myIdx, true)
        end
    elseif not focusOn and State.PrevStates.FocusActive then
        State.PrevStates.FocusActive = false
        if BlinkClient and BlinkClient.NpcFocusFireToggle and BlinkClient.NpcFocusFireToggle.Fire then
            pcall(BlinkClient.NpcFocusFireToggle.Fire, myIdx, false)
        end
    end

    local meleeOn = getVal("comp_automelee", false)
    local meleeRadius = getVal("comp_melee_rad", 40)
    if meleeOn and nearestEnemy and nearestDist <= meleeRadius then
        if not State.PrevStates.MeleeActive then
            State.PrevStates.MeleeActive = true
            if Remotes.MeleeCommand then
                pcall(function()
                    Remotes.MeleeCommand:FireServer("TARGET", myIdx, nearestEnemy.OwnerUserId, nearestEnemy.CompanyIndex)
                    Remotes.MeleeCommand:FireServer("MODE", myIdx, true, false)
                end)
            end
            if BlinkClient and BlinkClient.NpcMeleeToggle and BlinkClient.NpcMeleeToggle.Fire then
                pcall(BlinkClient.NpcMeleeToggle.Fire, myIdx, true)
            end
        end
    elseif State.PrevStates.MeleeActive and (not meleeOn or not nearestEnemy or nearestDist > meleeRadius + 15) then
        State.PrevStates.MeleeActive = false
        if Remotes.MeleeCommand then
            pcall(function() Remotes.MeleeCommand:FireServer("MODE", myIdx, false, true) end)
        end
        if BlinkClient and BlinkClient.NpcMeleeToggle and BlinkClient.NpcMeleeToggle.Fire then
            pcall(BlinkClient.NpcMeleeToggle.Fire, myIdx, false)
        end
    end

    local autoFace = getVal("comp_autoface", false)
    local orbitOn = getVal("comp_orbit", false)
    local interval = math_max(0.2, (getVal("comp_interval", 4) or 4) * 0.1)
    local syncOk = true
    if NpcMovementSync and type(NpcMovementSync.IsFlagEnabled) == "function" then
        local okSync, res = pcall(NpcMovementSync.IsFlagEnabled)
        if okSync and res == false then syncOk = false end
    end

    if syncOk and (autoFace or orbitOn) and count > 0 and nearestEnemy and (now - State.Timers.Formation) >= interval then
        State.Timers.Formation = now
        local delta = nearestEnemy.Centroid - centroid
        local flat = Vector3_new(delta.X, 0, delta.Z)
        if flat.Magnitude > 0.5 then
            local facing = flat.Unit
            local goalPos = centroid
            if orbitOn then
                local desired = getVal("comp_hold_dist", 85)
                goalPos = nearestEnemy.Centroid - facing * desired
                goalPos = Vector3_new(goalPos.X, centroid.Y, goalPos.Z)
            end
            local ranks = count >= 8 and 2 or 1
            local files = math_max(1, math_ceil(count / ranks))
            if BlinkClient and BlinkClient.NpcOrderCommand and BlinkClient.NpcOrderCommand.Fire then
                pcall(BlinkClient.NpcOrderCommand.Fire, goalPos, facing, ranks, files, myIdx)
            end
        end
    end

    if getVal("comp_autochant", false) and count > 0 then
        Actions.TriggerChant(false)
    end
end

--==============================================================================
-- 9. ARTILLERY ASSISTANT, STATE LISTENER & 3D TRAJECTORY ARC
--==============================================================================
if Remotes.ArtyState and Remotes.ArtyState:IsA("RemoteEvent") then
    addConn(Remotes.ArtyState.OnClientEvent:Connect(function(kind, stateTbl)
        if State.Unloaded then return end
        State.ArtyLastEventAt = os_clock()
        State.ArtyLastEventKind = tostring(kind or "UPDATE")
        if kind == "RELEASED" then
            State.ArtyState = nil
        elseif type(stateTbl) == "table" then
            State.ArtyState = stateTbl
        end
    end))
end

Actions.ArtySend = function(cmd, payload)
    if not (Remotes.ArtyCommand and Remotes.ArtyCommand:IsA("RemoteEvent")) then return end
    pcall(function()
        if payload ~= nil then Remotes.ArtyCommand:FireServer(cmd, payload)
        else Remotes.ArtyCommand:FireServer(cmd) end
    end)
end

Actions.ArtyApplyStyle = function()
    Actions.ArtySend("STYLE", tostring(getVal("arty_style", "OVERHEAD")))
end

local lastArtyTargetKey = ""
local function pickBestArtyCompany()
    local st = State.ArtyState
    local origin = (st and typeof(st.batteryOrigin) == "Vector3" and st.batteryOrigin)
        or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character.HumanoidRootPart.Position)
        or Camera.CFrame.Position
    local minRange = Cfg.arty_minrange
    local prio = getVal("arty_priority", "Densest Company")

    local best, bestScore = nil, -math.huge
    for _, c in pairs(State.CompanyClusters) do
        if not c.Friendly and c.Count > 0 then
            local dist = (c.Centroid - origin).Magnitude
            if dist >= minRange then
                local score = (prio == "Closest Safe" and -dist)
                    or (prio == "Lowest Avg HP" and (-c.AvgHp + c.Count * 2))
                    or (c.Count * 100 - dist * 0.2)
                if score > bestScore then
                    bestScore = score
                    best = c
                end
            end
        end
    end
    return best
end

local function buildArtyTargetPayload(best)
    return {
        companyIndex = (State.ArtyState and tonumber(State.ArtyState.companyIndex)) or State.OwnedCompanyIdx or 1,
        targetOwnerUserId = best.OwnerUserId,
        targetCompanyIndex = best.CompanyIndex,
        requestId = HttpService:GenerateGUID(false),
    }
end

Actions.ArtyTargetBest = function()
    local best = pickBestArtyCompany()
    if best then
        lastArtyTargetKey = best.Key
        Actions.ArtySend("TARGET_COMPANY", buildArtyTargetPayload(best))
    end
end

local function stepArtilleryAutomation(now)
    local st = State.ArtyState
    if not st or st.destroyed then return end

    if getVal("arty_autofire", false) and st.canFire and (now - State.Timers.ArtyFire) >= 0.35 then
        State.Timers.ArtyFire = now
        Actions.ArtySend("FIRE")
    end
    if getVal("arty_autodrill", false) and st.drillCanAdvance and (now - State.Timers.ArtyDrill) >= 0.25 then
        State.Timers.ArtyDrill = now
        Actions.ArtySend("DRILL_ADVANCE")
    end
    if getVal("arty_autotarget", false) and (now - State.Timers.ArtyTarget) >= 1.2 then
        State.Timers.ArtyTarget = now
        local best = pickBestArtyCompany()
        if best and best.Key ~= lastArtyTargetKey then
            lastArtyTargetKey = best.Key
            Actions.ArtySend("TARGET_COMPANY", buildArtyTargetPayload(best))
        end
    end
end

--==============================================================================
-- 10. BLINK BINARY PACKET INSPECTOR & QOL (MISSIONS / VOTING)
--==============================================================================
local BlinkOutRelNames = {
    [4] = "NpcReady", [17] = "TeamRegimentSelect", [18] = "RequestTeamReset",
    [36] = "MapVoteCast", [39] = "RequestMapVote", [42] = "TimeVoteCast", [45] = "PingRequest",
}

local BlinkOutUnrelNames = {
    [1] = "NpcOrderCommand", [2] = "BearerModeCommand", [3] = "NpcCanAttackToggle",
    [4] = "NpcChant", [5] = "NpcHitReport", [6] = "NpcMeleeToggle",
    [7] = "NpcMeleeTarget", [8] = "NpcFocusFireTarget", [9] = "NpcFocusFireToggle", [45] = "PingRequest",
}

local function pushSpyLog(direction, name, details)
    local line = string_format("[%s][%s] %s%s", os_date("%H:%M:%S"), direction, tostring(name), details and (" | " .. details) or "")
    table_insert(State.SpyLogs, 1, line)
    while #State.SpyLogs > State.SpyMaxLogs do table_remove(State.SpyLogs) end
    if Cfg.spy_console then print(line) end
end

Actions.DumpSpyToConsole = function()
    print("=== Blink Packet Spy Dump (" .. tostring(#State.SpyLogs) .. ") ===")
    for i = #State.SpyLogs, 1, -1 do print(State.SpyLogs[i]) end
end

local function summarizeArgs(...)
    local n = select("#", ...)
    local limit = math_min(n, 4)
    local parts = table_create(limit)
    for i = 1, limit do
        local v = select(i, ...)
        local t = typeof(v)
        if t == "Vector3" then parts[i] = string_format("(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z)
        elseif t == "table" then parts[i] = "{table}"
        else parts[i] = tostring(v) end
    end
    return table_concat(parts, ", ")
end

local function setupBlinkIncomingListeners()
    if not BlinkClient then return end
    local noisyEvents = { NpcBatch = true, PingSync = true }
    for eventName, mod in pairs(BlinkClient) do
        if type(mod) == "table" and type(mod.On) == "function" then
            local okSub, unsub = pcall(mod.On, function(...)
                if State.Unloaded or not Cfg.spy_enabled or not Cfg.spy_in then return end
                if noisyEvents[eventName] and not Cfg.spy_noisy then return end
                pushSpyLog("IN ", eventName, summarizeArgs(...))
            end)
            if okSub and type(unsub) == "function" then
                table_insert(State.BlinkUnsubs, unsub)
            end
        end
    end
end
setupBlinkIncomingListeners()

-- Fast-path Potassium __namecall hook: checks Cfg.spy_enabled & instance pointer BEFORE getnamecallmethod()
local function installBlinkOutgoingHook()
    if not (hookmetamethod and (BlinkReliableRemote or BlinkUnreliableRemote)) then return end
    local oldNamecall
    local function hookFn(self, ...)
        if Cfg.spy_enabled
            and Cfg.spy_out
            and (self == BlinkReliableRemote or self == BlinkUnreliableRemote)
            and not State.Unloaded
        then
            local method = getnamecallmethod and getnamecallmethod() or ""
            if method == "FireServer" or method == "fireServer" then
                local buf = select(1, ...)
                if typeof(buf) == "buffer" and buffer_len then
                    local len = buffer_len(buf)
                    if len >= 1 then
                        local op = buffer_readu8(buf, 0)
                        local isRel = (self == BlinkReliableRemote)
                        local opMap = isRel and BlinkOutRelNames or BlinkOutUnrelNames
                        local name = opMap[op] or ((isRel and "RelOp_" or "UnrelOp_") .. tostring(op))
                        if name ~= "PingRequest" or Cfg.spy_noisy then
                            local extra = string_format("op=%d bytes=%d", op, len)
                            if not isRel and op == 5 and len >= 17 then
                                extra = string_format("shot=%d npc=%d (%dB)", buffer_readu16(buf, 1), buffer_readu16(buf, 3), len)
                            elseif not isRel and op == 1 and len >= 4 then
                                extra = string_format("comp=%d (%dB)", buffer_readu8(buf, len - 1), len)
                            end
                            pushSpyLog("OUT", name, extra)
                        end
                    end
                end
            end
        end
        return oldNamecall(self, ...)
    end
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(hookFn))
    State.Hooks.OldNamecall = oldNamecall
end
installBlinkOutgoingHook()

Actions.ClaimMissions = function(verbose)
    if not (Remotes.MissionQuery and Remotes.MissionClaim) then return end
    task.spawn(function()
        local ok, data = pcall(function() return Remotes.MissionQuery:InvokeServer() end)
        if not ok or type(data) ~= "table" or type(data.missions) ~= "table" then return end
        local claimedAny = 0
        for _, m in ipairs(data.missions) do
            if type(m) == "table" and m.rewardPending == true and not m.claimed and m.id then
                local okClaim = pcall(function() return Remotes.MissionClaim:InvokeServer(m.id) end)
                if okClaim then
                    claimedAny += 1
                    if verbose then print("[NWB QoL] Claimed mission: " .. tostring(m.title or m.id)) end
                end
            end
        end
        if verbose and claimedAny == 0 then print("[NWB QoL] No pending unclaimed missions.") end
    end)
end

Actions.PrintMissions = function()
    if not Remotes.MissionQuery then return end
    task.spawn(function()
        local ok, data = pcall(function() return Remotes.MissionQuery:InvokeServer() end)
        if not ok or type(data) ~= "table" or type(data.missions) ~= "table" then
            print("[NWB QoL] MissionQuery unavailable.")
            return
        end
        print(string_format("=== NWB Missions (Coins: %s) ===", tostring(data.coins or "?")))
        for _, m in ipairs(data.missions) do
            print(string_format(" - [%s] %s (%s/%s) pending=%s claimed=%s",
                tostring(m.cadence or "?"), tostring(m.title or m.id),
                tostring(m.progress), tostring(m.target),
                tostring(m.rewardPending), tostring(m.claimed)))
        end
    end)
end

Actions.VoteMode = function()
    if not Remotes.NWBGameModeVote then return end
    local mode = tostring(getVal("qol_mode", "TeamDeathmatch"))
    pcall(function()
        Remotes.NWBGameModeVote:FireServer({ modeKey = mode, requestId = HttpService:GenerateGUID(false) })
    end)
end

Actions.VoteMapAndTime = function()
    local opt = math_floor(getVal("qol_vote_opt", 1) or 1)
    if BlinkClient then
        if BlinkClient.MapVoteCast and BlinkClient.MapVoteCast.Fire then pcall(BlinkClient.MapVoteCast.Fire, opt) end
        if BlinkClient.TimeVoteCast and BlinkClient.TimeVoteCast.Fire then pcall(BlinkClient.TimeVoteCast.Fire, opt) end
    end
end

local DEPLOY_MENU_NAMES = { "TeamSelectMenu", "MainMenu", "DeploymentGui", "Deployment", "RegimentMenu", "RegimentSelect", "TeamSelect" }
Actions.FixDeploymentScreen = function(verbose)
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local closedAny = false
    if pg then
        for i = 1, #DEPLOY_MENU_NAMES do
            local gui = pg:FindFirstChild(DEPLOY_MENU_NAMES[i])
            if gui and gui:IsA("ScreenGui") and gui.Enabled then
                gui.Enabled = false
                closedAny = true
            end
        end
    end

    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local camFixed = false
    if Camera and hum and not (Cfg.cam_freecam or Cfg.cam_rts) then
        if Camera.CameraType == Enum.CameraType.Scriptable then
            Camera.CameraType = Enum.CameraType.Custom
            Camera.CameraSubject = hum
            camFixed = true
        elseif Camera.CameraSubject ~= hum then
            Camera.CameraSubject = hum
            camFixed = true
        end
    end

    local fxCleaned = 0
    for _, fx in ipairs(Lighting:GetChildren()) do
        if fx:IsA("BlurEffect") or fx:IsA("ColorCorrectionEffect") then
            local fName = fx.Name
            if string_find(fName, "Menu", 1, true) or string_find(fName, "Deploy", 1, true) or string_find(fName, "Select", 1, true) then
                if fx.Enabled then
                    fx.Enabled = false
                    fxCleaned += 1
                end
            end
        end
    end

    if Remotes.SafeDeploymentReady and Remotes.SafeDeploymentReady:IsA("RemoteEvent") then
        pcall(function() Remotes.SafeDeploymentReady:FireServer() end)
    end

    if verbose then
        print(string_format("[NWB QoL] Deployment Screen Unstuck: closedMenu=%s camFixed=%s fxCleaned=%d",
            tostring(closedAny), tostring(camFixed), fxCleaned))
    end
end

--==============================================================================
-- 11. MOVEMENT, CAMERA, WORLD FX & CLEANUP RESTORATION
--==============================================================================
local function setWalkSpeedBypass(enabled, targetSpeed, now)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    if enabled then
        local tNow = now or os_clock()
        local needScan = (State.WalkHookHum ~= hum)
            or (next(State.DisabledConns) == nil and (tNow - State.LastWalkHookScan) >= 1.5)
            or (math_abs(hum.WalkSpeed - targetSpeed) > 1 and (tNow - State.LastWalkHookScan) >= 0.4)
        if needScan and getconnections then
            State.WalkHookHum = hum
            State.LastWalkHookScan = tNow
            local okConns, conns = pcall(getconnections, hum:GetPropertyChangedSignal("WalkSpeed"))
            if okConns and type(conns) == "table" then
                for _, c in ipairs(conns) do
                    if type(c.Disable) == "function" then
                        pcall(c.Disable, c)
                        State.DisabledConns[c] = true
                    elseif type(c.Disconnect) == "function" then
                        pcall(c.Disconnect, c)
                    end
                end
            end
        end
        if hum.WalkSpeed ~= targetSpeed then hum.WalkSpeed = targetSpeed end
    else
        State.WalkHookHum = nil
        for c in pairs(State.DisabledConns) do
            if type(c.Enable) == "function" then pcall(c.Enable, c) end
        end
        table_clear(State.DisabledConns)
        hum.WalkSpeed = Consts.DefaultWalkSpeed
    end
end

local function setZoomBypass(enabled, targetZoom, now)
    if enabled then
        local tNow = now or os_clock()
        local needScan = (next(State.DisabledZoomConns) == nil and (tNow - State.LastZoomHookScan) >= 1.5)
            or (LocalPlayer.CameraMaxZoomDistance ~= targetZoom and (tNow - State.LastZoomHookScan) >= 0.5)
        if needScan and getconnections then
            State.LastZoomHookScan = tNow
            local okConns, conns = pcall(getconnections, LocalPlayer:GetPropertyChangedSignal("CameraMaxZoomDistance"))
            if okConns and type(conns) == "table" then
                for _, c in ipairs(conns) do
                    local okEnv, fenv = pcall(getfenv, c.Function)
                    local scr = okEnv and fenv and fenv.script
                    if scr and scr.Name == "CameraRecovery" then
                        if type(c.Disable) == "function" then
                            pcall(c.Disable, c)
                            State.DisabledZoomConns[c] = true
                        elseif type(c.Disconnect) == "function" then
                            pcall(c.Disconnect, c)
                        end
                    end
                end
            end
        end
        if LocalPlayer.CameraMaxZoomDistance ~= targetZoom then
            LocalPlayer.CameraMaxZoomDistance = targetZoom
        end
    else
        for c in pairs(State.DisabledZoomConns) do
            if type(c.Enable) == "function" then pcall(c.Enable, c) end
        end
        table_clear(State.DisabledZoomConns)
        LocalPlayer.CameraMaxZoomDistance = State.OriginalMaxZoom
    end
end

local function stopFly()
    if State.FlyBodyVel then pcall(function() State.FlyBodyVel:Destroy() end) State.FlyBodyVel = nil end
    if State.FlyBodyGyro then pcall(function() State.FlyBodyGyro:Destroy() end) State.FlyBodyGyro = nil end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = false end
end

local CharDescConn = nil
local function refreshCharParts(char)
    State.LastChar = char
    table_clear(State.CharParts)
    if CharDescConn then pcall(function() CharDescConn:Disconnect() end) CharDescConn = nil end
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then table_insert(State.CharParts, part) end
    end
    CharDescConn = addConn(char.DescendantAdded:Connect(function(inst)
        if not State.Unloaded and inst:IsA("BasePart") then table_insert(State.CharParts, inst) end
    end))
end

local function stepMovementAndCamera(dt)
    local now = os_clock()
    local char = LocalPlayer.Character
    if char ~= State.LastChar then refreshCharParts(char) end
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")

    if Cfg.mv_ws_on then
        local targetWs = Cfg.mv_ws_val
        if (hum and hum.WalkSpeed ~= targetWs) or State.WalkHookHum ~= hum or (now - State.Timers.WalkSpeed) >= 0.5 then
            State.Timers.WalkSpeed = now
            setWalkSpeedBypass(true, targetWs, now)
        end
    elseif next(State.DisabledConns) ~= nil then
        setWalkSpeedBypass(false, Consts.DefaultWalkSpeed, now)
    end

    if Cfg.mv_fly_on and hrp and hum and Camera then
        if not State.FlyBodyVel or State.FlyBodyVel.Parent ~= hrp then
            stopFly()
            local bv = Instance.new("BodyVelocity")
            bv.MaxForce = Vector3_new(9e4, 9e4, 9e4)
            bv.Velocity = Vector3_zero
            bv.Parent = hrp
            State.FlyBodyVel = bv

            local bg = Instance.new("BodyGyro")
            bg.MaxTorque = Vector3_new(9e4, 9e4, 9e4)
            bg.P = 9e4
            bg.CFrame = Camera.CFrame
            bg.Parent = hrp
            State.FlyBodyGyro = bg
        end
        hum.PlatformStand = true
        local move = Vector3_zero
        local camCF = Camera.CFrame
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += camCF.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= camCF.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= camCF.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += camCF.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3_new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3_new(0, 1, 0) end
        State.FlyBodyVel.Velocity = (move.Magnitude > 0.01) and (move.Unit * Cfg.mv_fly_val) or Vector3_zero
        State.FlyBodyGyro.CFrame = camCF
    elseif State.FlyBodyVel then
        stopFly()
    end

    if Cfg.mv_noclip and char then
        local parts = State.CharParts
        for i = #parts, 1, -1 do
            local part = parts[i]
            if not part.Parent then table_remove(parts, i)
            elseif part.CanCollide then part.CanCollide = false end
        end
    end

    if Cfg.cam_zoom_on then
        local desiredZoom = Cfg.cam_zoom_val
        if LocalPlayer.CameraMaxZoomDistance ~= desiredZoom or next(State.DisabledZoomConns) == nil then
            setZoomBypass(true, desiredZoom, now)
        end
    elseif next(State.DisabledZoomConns) ~= nil or LocalPlayer.CameraMaxZoomDistance ~= State.OriginalMaxZoom then
        setZoomBypass(false, State.OriginalMaxZoom, now)
    end

    local freeOn = Cfg.cam_freecam
    local rtsOn = Cfg.cam_rts
    if (freeOn or rtsOn) and Camera then
        if not State.OriginalCameraType then State.OriginalCameraType = Camera.CameraType end
        Camera.CameraType = Enum.CameraType.Scriptable

        if freeOn then
            if not State.FreecamCF then State.FreecamCF = Camera.CFrame end
            local deltaMouse = UserInputService:GetMouseDelta()
            local rotCF = State.FreecamCF
            if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
                local rx, ry = rotCF:ToOrientation()
                local yaw = ry - deltaMouse.X * 0.004
                local pitch = math_clamp(rx - deltaMouse.Y * 0.004, -1.5, 1.5)
                rotCF = CFrame_new(rotCF.Position) * CFrame_Angles(0, yaw, 0) * CFrame_Angles(pitch, 0, 0)
            end
            local move = Vector3_zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += rotCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= rotCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= rotCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += rotCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.E) or UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3_new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.Q) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3_new(0, 1, 0) end
            local spd = Cfg.cam_free_spd * (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 2.2 or 1)
            State.FreecamCF = rotCF + move * spd * dt
            Camera.CFrame = State.FreecamCF
        else
            State.FreecamCF = nil
            if not State.RTSCenter then State.RTSCenter = getMyCompanyCentroid() end
            local pan = Vector3_zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then pan += Vector3_new(0, 0, -1) end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then pan += Vector3_new(0, 0, 1) end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then pan += Vector3_new(-1, 0, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then pan += Vector3_new(1, 0, 0) end
            State.RTSCenter += pan * 120 * dt
            local alt = Cfg.cam_rts_alt
            local camPos = Vector3_new(State.RTSCenter.X, State.RTSCenter.Y + alt, State.RTSCenter.Z + alt * 0.35)
            Camera.CFrame = CFrame_lookAt(camPos, State.RTSCenter)
        end
    else
        State.FreecamCF = nil
        State.RTSCenter = nil
        if State.OriginalCameraType then
            Camera.CameraType = State.OriginalCameraType
            State.OriginalCameraType = nil
        end
    end
end

addConn(UserInputService.JumpRequest:Connect(function()
    if State.Unloaded or not getVal("mv_infjump", false) then return end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end))

Actions.ToggleBuiltInFreecam = function()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local fc = pg and pg:FindFirstChild("Freecam")
    if fc then
        local scr = fc:FindFirstChild("FreecamScript")
        if scr and scr:IsA("LocalScript") then
            scr.Enabled = not scr.Enabled
            print("[NWB Camera] Native Freecam script Enabled = " .. tostring(scr.Enabled))
            return
        end
    end
    print("[NWB Camera] Native Freecam GUI not found; use Custom Freecam toggle.")
end

local function ensureSmokeCache()
    if State.SmokeScanned then return end
    State.SmokeScanned = true
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("ParticleEmitter") and string_find(string_lower(inst.Name), "smoke", 1, true) then
            State.SmokeSnapshot[inst] = inst.Enabled
            table_insert(State.SmokeEmitters, inst)
        end
    end
end

addConn(Workspace.DescendantAdded:Connect(function(inst)
    if State.Unloaded or not State.SmokeScanned then return end
    if inst:IsA("ParticleEmitter") and string_find(string_lower(inst.Name), "smoke", 1, true) then
        State.SmokeSnapshot[inst] = inst.Enabled
        table_insert(State.SmokeEmitters, inst)
        if State.PrevStates.SmokeHidden then inst.Enabled = false end
    end
end))

local function applyWorldVisuals()
    local noSmoke = getVal("vis_nosmoke", false)
    if noSmoke ~= State.PrevStates.SmokeHidden then
        State.PrevStates.SmokeHidden = noSmoke
        ensureSmokeCache()
        local list = State.SmokeEmitters
        for i = #list, 1, -1 do
            local pe = list[i]
            if not pe.Parent then
                State.SmokeSnapshot[pe] = nil
                table_remove(list, i)
            elseif noSmoke then
                pe.Enabled = false
            elseif State.SmokeSnapshot[pe] ~= nil then
                pe.Enabled = State.SmokeSnapshot[pe]
            end
        end
    end

    local fpsBoost = getVal("vis_fps", false)
    local fullbright = getVal("vis_fullbright", false)
    if not State.LightingSnapshot then
        State.LightingSnapshot = {
            GlobalShadows = Lighting.GlobalShadows, Brightness = Lighting.Brightness,
            ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd,
            Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
        }
    end

    if fpsBoost ~= State.PrevStates.FpsBoost then
        State.PrevStates.FpsBoost = fpsBoost
        Lighting.GlobalShadows = not fpsBoost and State.LightingSnapshot.GlobalShadows or false
        for _, fx in ipairs(Lighting:GetChildren()) do
            if fx:IsA("PostEffect") then
                if fpsBoost then
                    if State.FXSnapshot[fx] == nil then State.FXSnapshot[fx] = fx.Enabled end
                    fx.Enabled = false
                elseif State.FXSnapshot[fx] ~= nil then
                    fx.Enabled = State.FXSnapshot[fx]
                end
            end
        end
    end

    if fullbright ~= State.PrevStates.Fullbright then
        State.PrevStates.Fullbright = fullbright
        if fullbright then
            Lighting.Brightness = 2.5
            Lighting.ClockTime = 14
            Lighting.FogEnd = 100000
            Lighting.Ambient = Color3_fromRGB(165, 165, 165)
            Lighting.OutdoorAmbient = Color3_fromRGB(165, 165, 165)
        else
            Lighting.Brightness = State.LightingSnapshot.Brightness
            Lighting.ClockTime = State.LightingSnapshot.ClockTime
            Lighting.FogEnd = State.LightingSnapshot.FogEnd
            Lighting.Ambient = State.LightingSnapshot.Ambient
            Lighting.OutdoorAmbient = State.LightingSnapshot.OutdoorAmbient
        end
    end
end

--==============================================================================
-- 12. DRAWING OBJECT POOLS (ZERO-REDUNDANT-BRIDGE-WRITE ESP, FOV, ARC, HUDS)
--==============================================================================
local FovCircle = newDrawing("Circle", { Visible = false, Thickness = 1.5, Filled = false, NumSides = 64, Radius = 180, Color = Color3_fromRGB(235, 85, 65), ZIndex = 10 })
local SnapLine = newDrawing("Line", { Visible = false, Thickness = 1.5, Color = Color3_fromRGB(255, 215, 70), ZIndex = 11 })

local EspPool = table_create(250)
local function getEspSlot(idx)
    local slot = EspPool[idx]
    if slot then return slot end
    slot = {
        BoxOutline = newDrawing("Square", { Visible = false, Filled = false, Thickness = 3, Color = COLOR_BLACK, ZIndex = 4 }),
        Box = newDrawing("Square", { Visible = false, Filled = false, Thickness = 1.2, Color = Color3_fromRGB(255, 75, 75), ZIndex = 5 }),
        HpBg = newDrawing("Square", { Visible = false, Filled = true, Color = COLOR_HP_BG, ZIndex = 4 }),
        HpBar = newDrawing("Square", { Visible = false, Filled = true, Color = HP_COLOR_LUT[32], ZIndex = 5 }),
        TopText = newDrawing("Text", { Visible = false, Size = 13, Center = true, Outline = true, Font = Drawing.Fonts and Drawing.Fonts.Plex or 2, Color = COLOR_WHITE, ZIndex = 6 }),
        BottomText = newDrawing("Text", { Visible = false, Size = 12, Center = true, Outline = true, Font = Drawing.Fonts and Drawing.Fonts.Plex or 2, Color = COLOR_LIGHT_GRAY, ZIndex = 6 }),
        _visBox = false, _visHp = false, _visTop = false, _visBot = false,
        _topText = "", _botText = "", _lastTopBase = nil, _lastDist = -1,
        _boxCol = nil, _hpBucket = -1,
    }
    EspPool[idx] = slot
    return slot
end

local FlagPool = {}
local function getFlagSlot(idx)
    local slot = FlagPool[idx]
    if slot then return slot end
    slot = {
        Draw = newDrawing("Text", { Visible = false, Size = 14, Center = true, Outline = true, Font = Drawing.Fonts and Drawing.Fonts.Plex or 2, Color = COLOR_GOLD, ZIndex = 12 }),
        _vis = false, _lastDist = -1, _text = "", _col = nil,
    }
    FlagPool[idx] = slot
    return slot
end

local ARC_SEG_COUNT = 26
local ArcSegments = table_create(ARC_SEG_COUNT)
for i = 1, ARC_SEG_COUNT do
    ArcSegments[i] = newDrawing("Line", { Visible = false, Thickness = 2, Color = Color3_fromRGB(255, 145, 50), ZIndex = 9 })
end
local ArcImpactCircle = newDrawing("Circle", { Visible = false, Thickness = 2, Radius = 12, NumSides = 24, Color = Color3_fromRGB(255, 145, 50), ZIndex = 9 })

local HudCompany = newDrawing("Text", { Visible = false, Size = 14, Outline = true, Font = Drawing.Fonts and Drawing.Fonts.Plex or 2, Color = Color3_fromRGB(225, 235, 255), Position = Vector2_new(14, 42), ZIndex = 30 })
local HudArty = newDrawing("Text", { Visible = false, Size = 14, Outline = true, Font = Drawing.Fonts and Drawing.Fonts.Plex or 2, Color = Color3_fromRGB(255, 195, 110), Position = Vector2_new(14, 64), ZIndex = 30 })
local HudThreat = newDrawing("Text", { Visible = false, Size = 16, Center = true, Outline = true, Font = Drawing.Fonts and Drawing.Fonts.Plex or 2, Color = Color3_fromRGB(255, 75, 75), ZIndex = 31 })
local HudSpyLines = table_create(State.SpyMaxLogs)
for i = 1, State.SpyMaxLogs do
    HudSpyLines[i] = {
        Draw = newDrawing("Text", { Visible = false, Size = 13, Outline = true, Font = Drawing.Fonts and Drawing.Fonts.Monospace or 3, Color = Color3_fromRGB(165, 245, 190), ZIndex = 30 }),
        _vis = false, _text = "", _y = -1,
    }
end

local RenderState = {
    PrevEspUsed = 0, PrevFlagsUsed = 0, PrevArcShown = false,
    LastFovVis = false, LastFovFilled = nil, LastFovRadius = -1, LastFovSides = -1, LastFovCol = nil, LastCenter = Vector2_new(0, 0),
    LastSnapVis = false, LastCompVis = false, LastCompText = "",
    LastArtyVis = false, LastArtyText = "", LastThreatVis = false, LastThreatText = "",
    LastFovDeg = 0, HalfFovTan = math_tan(math_rad(35)),
}

local function hideEspSlot(s)
    if s._visBox then s.BoxOutline.Visible = false s.Box.Visible = false s._visBox = false end
    if s._visHp then s.HpBg.Visible = false s.HpBar.Visible = false s._visHp = false end
    if s._visTop then s.TopText.Visible = false s._visTop = false end
    if s._visBot then s.BottomText.Visible = false s._visBot = false end
end

local function renderEspAndVisuals()
    if not Camera then return end
    local vp = Camera.ViewportSize
    local vpX, vpY = vp.X, vp.Y
    local cx, cy = vpX * 0.5, vpY * 0.5
    local center = RenderState.LastCenter
    if center.X ~= cx or center.Y ~= cy then
        center = Vector2_new(cx, cy)
        RenderState.LastCenter = center
    end

    local fovDeg = Camera.FieldOfView
    if fovDeg ~= RenderState.LastFovDeg then
        RenderState.LastFovDeg = fovDeg
        RenderState.HalfFovTan = math_tan(math_rad(fovDeg * 0.5))
    end
    local projScale = vpY / (2 * RenderState.HalfFovTan)
    local camCF = Camera.CFrame
    local camPos = camCF.Position
    local camPx, camPy, camPz = camPos.X, camPos.Y, camPos.Z
    local camLook = camCF.LookVector
    local clX, clY, clZ = camLook.X, camLook.Y, camLook.Z
    local vertFactor = math_clamp(math_abs(camCF.UpVector.Y), 0.35, 1)

    local saOn = Cfg.sa_enabled
    local fovRadius = Cfg.fov_radius
    local fovRadiusSq = fovRadius * fovRadius

    -- FOV Circle (fully dirty-checked to avoid redundant C++ Drawing bridge writes)
    local showFov = Cfg.fov_show and saOn
    if FovCircle then
        if showFov ~= RenderState.LastFovVis then
            RenderState.LastFovVis = showFov
            FovCircle.Visible = showFov
        end
        if showFov then
            local filled = Cfg.fov_filled
            local sides = math_clamp(math_floor(Cfg.fov_sides), 12, 120)
            local col = Cfg.fov_color
            FovCircle.Position = center
            if fovRadius ~= RenderState.LastFovRadius then
                RenderState.LastFovRadius = fovRadius
                FovCircle.Radius = fovRadius
            end
            if sides ~= RenderState.LastFovSides then
                RenderState.LastFovSides = sides
                FovCircle.NumSides = sides
            end
            if col ~= RenderState.LastFovCol then
                RenderState.LastFovCol = col
                FovCircle.Color = col
            end
            if filled ~= RenderState.LastFovFilled then
                RenderState.LastFovFilled = filled
                FovCircle.Filled = filled
                FovCircle.Transparency = filled and 0.25 or 0.9
            end
        end
    end

    -- Unified Single-Pass Projection (Silent Aim + Unit ESP + Threat Proximity)
    local saRange = Cfg.sa_range
    local saRangeSq = saRange * saRange
    local saFilterAll = (Cfg.sa_filter == "All Teams")
    local saPrio = Cfg.sa_priority
    local saPartMode = Cfg.sa_part
    local saWallCheck = Cfg.sa_wallcheck
    local saPlayers = Cfg.sa_players

    local myChar = LocalPlayer.Character
    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local myHead = myChar and myChar:FindFirstChild("Head")
    local saOrigin = (myHead and myHead.Position) or camPos
    local ox, oy, oz = saOrigin.X, saOrigin.Y, saOrigin.Z

    local espOn = Cfg.esp_enabled
    local enemyOnly = Cfg.esp_enemy_only
    local showFriendly = Cfg.esp_friendly
    local showBox = Cfg.esp_box
    local showHp = Cfg.esp_hp
    local showTags = Cfg.esp_tags
    local showMorale = Cfg.esp_morale
    local showWeapon = Cfg.esp_weapon
    local showDist = Cfg.esp_dist
    local maxDist = Cfg.esp_maxdist
    local maxDistSq = maxDist * maxDist
    local cap = Cfg.esp_cap
    local enemyCol = Cfg.esp_enemy_color
    local allyCol = Cfg.esp_ally_color
    local threatsOn = Cfg.esp_threats

    local usedSlots = 0
    local nearestChargeDistSq = math.huge
    local bestCandidate = nil
    local bestScore = math.huge

    local snapshots = State.NpcSnapshots
    local snapCount = State.NpcSnapshotCount

    for i = 1, snapCount do
        local u = snapshots[i]
        local uPos = u.Position
        local dx, dy, dz = uPos.X - camPx, uPos.Y - camPy, uPos.Z - camPz
        local camDistSq = dx * dx + dy * dy + dz * dz

        if threatsOn and not u.Friendly and camDistSq < nearestChargeDistSq then
            nearestChargeDistSq = camDistSq
        end

        -- Frustum dot-product pre-cull: discard units behind camera plane immediately
        local forwardDot = dx * clX + dy * clY + dz * clZ
        if forwardDot < -2 then
            continue
        end

        local espNeed = espOn and usedSlots < cap and camDistSq <= maxDistSq
            and u.HRP ~= nil
            and (not enemyOnly or not u.Friendly or showFriendly)

        local saNeed = false
        if saOn and (u.IsNPC or saPlayers) and (saFilterAll or not u.Friendly) then
            local odx, ody, odz = uPos.X - ox, uPos.Y - oy, uPos.Z - oz
            if (odx * odx + ody * ody + odz * odz) <= (saRangeSq + 64) then
                saNeed = true
            end
        end

        if espNeed or saNeed then
            local cScr, cOnScr = Camera:WorldToViewportPoint(uPos)
            local cz = cScr.Z
            if cz > 0 then
                local scx, scy = cScr.X, cScr.Y

                -- Draw Unit ESP from single projection (shared Vector2 & LUT colors)
                if espNeed and (cOnScr or (scx >= -60 and scx <= vpX + 60 and scy >= -90 and scy <= vpY + 90)) then
                    usedSlots += 1
                    local slot = getEspSlot(usedSlots)
                    local h = math_max(8, (5.8 * vertFactor * projScale) / cz)
                    local w = math_max(5, h * 0.58)
                    local x = scx - w * 0.5
                    local y = scy - h * 0.483
                    local boxCol = u.Friendly and allyCol or enemyCol

                    if showBox then
                        if not slot._visBox then
                            slot.BoxOutline.Visible = true
                            slot.Box.Visible = true
                            slot._visBox = true
                        end
                        local boxPos = Vector2_new(x, y)
                        local boxSize = Vector2_new(w, h)
                        slot.BoxOutline.Position = boxPos
                        slot.BoxOutline.Size = boxSize
                        slot.Box.Position = boxPos
                        slot.Box.Size = boxSize
                        if slot._boxCol ~= boxCol then
                            slot._boxCol = boxCol
                            slot.Box.Color = boxCol
                        end
                    elseif slot._visBox then
                        slot.BoxOutline.Visible = false
                        slot.Box.Visible = false
                        slot._visBox = false
                    end

                    if showHp then
                        if not slot._visHp then
                            slot.HpBg.Visible = true
                            slot.HpBar.Visible = true
                            slot._visHp = true
                        end
                        local frac = math_clamp(u.Health / math_max(1, u.MaxHealth), 0, 1)
                        local barH = math_max(2, h * frac)
                        local hpX = x - 6
                        slot.HpBg.Position = Vector2_new(hpX, y)
                        slot.HpBg.Size = Vector2_new(3, h)
                        slot.HpBar.Position = Vector2_new(hpX, y + (h - barH))
                        slot.HpBar.Size = Vector2_new(3, barH)
                        local bucket = math_floor(frac * 32 + 0.5)
                        if slot._hpBucket ~= bucket then
                            slot._hpBucket = bucket
                            slot.HpBar.Color = HP_COLOR_LUT[bucket] or HP_COLOR_LUT[32]
                        end
                    elseif slot._visHp then
                        slot.HpBg.Visible = false
                        slot.HpBar.Visible = false
                        slot._visHp = false
                    end

                    if showTags or showDist then
                        local topStr
                        if showTags and showDist then
                            local distInt = math_floor(math_sqrt(camDistSq))
                            if slot._lastTopBase ~= u.TopTag or slot._lastDist ~= distInt then
                                slot._lastTopBase = u.TopTag
                                slot._lastDist = distInt
                                slot._topText = string_format("%s %dm", u.TopTag, distInt)
                            end
                            topStr = slot._topText
                        elseif showTags then
                            topStr = u.TopTag
                        else
                            local distInt = math_floor(math_sqrt(camDistSq))
                            if slot._lastTopBase ~= "" or slot._lastDist ~= distInt then
                                slot._lastTopBase = ""
                                slot._lastDist = distInt
                                slot._topText = string_format("%dm", distInt)
                            end
                            topStr = slot._topText
                        end

                        if not slot._visTop then
                            slot.TopText.Visible = true
                            slot._visTop = true
                        end
                        slot.TopText.Position = Vector2_new(scx, y - 15)
                        local topCol = u.IsBearer and COLOR_GOLD or boxCol
                        if slot._topCol ~= topCol then
                            slot._topCol = topCol
                            slot.TopText.Color = topCol
                        end
                        if slot._topAssigned ~= topStr then
                            slot._topAssigned = topStr
                            slot.TopText.Text = topStr
                        end
                    elseif slot._visTop then
                        slot.TopText.Visible = false
                        slot._visTop = false
                    end

                    local botStr = ""
                    if showWeapon and showMorale then
                        botStr = u.BotBoth
                    elseif showWeapon then
                        botStr = u.WeaponState
                    elseif showMorale then
                        botStr = u.BotMorale
                    end

                    if botStr ~= "" then
                        if not slot._visBot then
                            slot.BottomText.Visible = true
                            slot._visBot = true
                        end
                        slot.BottomText.Position = Vector2_new(scx, y + h + 2)
                        if slot._botText ~= botStr then
                            slot._botText = botStr
                            slot.BottomText.Text = botStr
                        end
                    elseif slot._visBot then
                        slot.BottomText.Visible = false
                        slot._visBot = false
                    end
                end

                -- Evaluate Silent Aim candidate using coarse screen cone cull before projecting aimPart
                if saNeed and math_abs(scx - cx) <= fovRadius + 85 and math_abs(scy - cy) <= fovRadius + 95 then
                    local part = chooseAimPart(u, saPartMode)
                    if part then
                        local pPos = part.Position
                        local pdx, pdy, pdz = pPos.X - ox, pPos.Y - oy, pPos.Z - oz
                        local partDistSq = pdx * pdx + pdy * pdy + pdz * pdz
                        if partDistSq <= saRangeSq then
                            local ax, ay, az, aOnScr
                            if part == u.HRP then
                                ax, ay, az, aOnScr = scx, scy, cz, cOnScr
                            else
                                local aScr, aVis = Camera:WorldToViewportPoint(pPos)
                                ax, ay, az, aOnScr = aScr.X, aScr.Y, aScr.Z, aVis
                            end
                            if aOnScr and az > 0 then
                                local fx, fy = ax - cx, ay - cy
                                local fovSq = fx * fx + fy * fy
                                if fovSq <= fovRadiusSq then
                                    if (not saWallCheck) or isLineOfSightClear(saOrigin, part, u.Model) then
                                        local fovDist = math_sqrt(fovSq)
                                        local worldDist = math_sqrt(partDistSq)
                                        local score = fovDist
                                        if saPrio == "Closest Distance" then
                                            score = worldDist
                                        elseif saPrio == "Lowest HP" then
                                            score = u.Health + fovDist * 0.05
                                        elseif saPrio == "Flag Bearers First" then
                                            score = (u.IsBearer and 0 or 5000) + fovDist
                                        end
                                        if score < bestScore then
                                            bestScore = score
                                            bestCandidate = {
                                                Unit = u,
                                                Part = part,
                                                ScreenPos = Vector2_new(ax, ay),
                                                WorldDist = worldDist,
                                                FovDist = fovDist,
                                            }
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    State.SilentAimTarget = bestCandidate

    for i = usedSlots + 1, RenderState.PrevEspUsed do
        local s = EspPool[i]
        if s then hideEspSlot(s) end
    end
    RenderState.PrevEspUsed = usedSlots

    -- Snap Line
    if SnapLine then
        if Cfg.sa_snap and saOn and bestCandidate then
            if not RenderState.LastSnapVis then
                RenderState.LastSnapVis = true
                SnapLine.Visible = true
            end
            SnapLine.From = center
            SnapLine.To = bestCandidate.ScreenPos
            SnapLine.Color = Cfg.sa_snap_color
        elseif RenderState.LastSnapVis then
            RenderState.LastSnapVis = false
            SnapLine.Visible = false
        end
    end

    -- Dropped Flags ESP
    local usedFlags = 0
    if Cfg.esp_flags and next(State.DroppedFlags) ~= nil then
        local flagCol = Cfg.esp_flag_color
        for obj, ref in pairs(State.DroppedFlags) do
            if not obj.Parent then
                State.DroppedFlags[obj] = nil
            else
                local pos = ref:IsA("BasePart") and ref.Position
                    or (obj:IsA("Model") and (obj.PrimaryPart and obj.PrimaryPart.Position))
                if pos then
                    local sp, vis = Camera:WorldToViewportPoint(pos + Vector3_new(0, 3, 0))
                    if vis and sp.Z > 0 then
                        usedFlags += 1
                        local fSlot = getFlagSlot(usedFlags)
                        local d = fSlot.Draw
                        if not fSlot._vis then
                            fSlot._vis = true
                            d.Visible = true
                        end
                        if fSlot._col ~= flagCol then
                            fSlot._col = flagCol
                            d.Color = flagCol
                        end
                        d.Position = Vector2_new(sp.X, sp.Y)
                        local fx, fy, fz = pos.X - camPx, pos.Y - camPy, pos.Z - camPz
                        local distInt = math_floor(math_sqrt(fx * fx + fy * fy + fz * fz))
                        if fSlot._lastDist ~= distInt then
                            fSlot._lastDist = distInt
                            fSlot._text = string_format("[DROPPED FLAG] %dm", distInt)
                            d.Text = fSlot._text
                        end
                    end
                end
            end
        end
    end
    for i = usedFlags + 1, RenderState.PrevFlagsUsed do
        local fSlot = FlagPool[i]
        if fSlot and fSlot._vis then
            fSlot._vis = false
            fSlot.Draw.Visible = false
        end
    end
    RenderState.PrevFlagsUsed = usedFlags

    -- 3D Artillery Trajectory Arc
    local drawArc = false
    local st = State.ArtyState
    if Cfg.arty_arc and st and typeof(st.batteryOrigin) == "Vector3" and typeof(st.batteryForward) == "Vector3" then
        drawArc = true
        local arcCol = Cfg.arty_arc_color
        local spd = Cfg.arty_speed
        local gravPct = Cfg.arty_grav or 16
        local bo = st.batteryOrigin
        local bf = st.batteryForward
        local cacheKey = string_format("%.2f,%.2f,%.2f|%.3f,%.3f,%.3f|%d|%d", bo.X, bo.Y, bo.Z, bf.X, bf.Y, bf.Z, math_floor(spd), math_floor(gravPct))
        local arcCache = State.ArcCache
        if arcCache.Key ~= cacheKey then
            arcCache.Key = cacheKey
            local g = (Workspace.Gravity or 196.2) * (gravPct * 0.01)
            local p0 = bo + Vector3_new(0, 4, 0)
            local dir = bf.Magnitude > 0.01 and bf.Unit or Vector3_new(0, 0.25, -1).Unit
            local v0 = dir * spd
            local tStep = 0.22
            local pts = arcCache.WorldPoints
            for idx = 1, ARC_SEG_COUNT + 1 do
                local t = (idx - 1) * tStep
                pts[idx] = p0 + v0 * t - Vector3_new(0, 0.5 * g * t * t, 0)
            end
            arcCache.Count = ARC_SEG_COUNT + 1
        end

        local pts = arcCache.WorldPoints
        local prevScr, prevVis = nil, false
        for idx = 1, ARC_SEG_COUNT + 1 do
            local scr, vis = Camera:WorldToViewportPoint(pts[idx])
            local curPt = Vector2_new(scr.X, scr.Y)
            if idx > 1 then
                local line = ArcSegments[idx - 1]
                if (prevVis or vis) and scr.Z > 0 then
                    line.Visible = true
                    line.From = prevScr
                    line.To = curPt
                    line.Color = arcCol
                else
                    line.Visible = false
                end
            end
            prevScr, prevVis = curPt, (vis and scr.Z > 0)
        end

        if ArcImpactCircle then
            local impScr, impVis = Camera:WorldToViewportPoint(pts[ARC_SEG_COUNT + 1])
            ArcImpactCircle.Visible = impVis and impScr.Z > 0
            if ArcImpactCircle.Visible then
                ArcImpactCircle.Position = Vector2_new(impScr.X, impScr.Y)
                ArcImpactCircle.Color = arcCol
            end
        end
        RenderState.PrevArcShown = true
    end
    if not drawArc and RenderState.PrevArcShown then
        RenderState.PrevArcShown = false
        for _, l in ipairs(ArcSegments) do l.Visible = false end
        if ArcImpactCircle then ArcImpactCircle.Visible = false end
    end

    -- HUD Overlays
    if HudCompany then
        if Cfg.comp_hud then
            local txt = string_format(
                "Company #%d | Alive: %d | Focus: %s | Melee: %s | Hold: %s",
                State.OwnedCompanyIdx or 0,
                State.MyCompanyAliveCount or 0,
                Cfg.comp_autofocus and "ON" or "OFF",
                State.PrevStates.MeleeActive and "ENGAGED" or "IDLE",
                State.PrevStates.AttackHeld and "HOLD" or "FIRE"
            )
            if not RenderState.LastCompVis then
                RenderState.LastCompVis = true
                HudCompany.Visible = true
            end
            if RenderState.LastCompText ~= txt then
                RenderState.LastCompText = txt
                HudCompany.Text = txt
            end
        elseif RenderState.LastCompVis then
            RenderState.LastCompVis = false
            HudCompany.Visible = false
        end
    end

    if HudArty then
        if Cfg.arty_hud then
            local txt
            if st then
                local rem = tonumber(st.reloadRemaining) or 0
                local dur = tonumber(st.reloadDuration) or 15
                txt = string_format(
                    "Artillery | Ready:%s | Reload:%.1f/%.0fs | Crew:%s/%s | Ammo:%s | Target:%s (%sm) | Drill:%s",
                    tostring(st.readyGuns or (st.canFire and 1 or 0)),
                    rem,
                    dur,
                    tostring(st.crew or "?"),
                    tostring(st.crewRequired or "?"),
                    tostring(st.loadedAmmoType or st.ammoType or "?"),
                    tostring(st.targetName or "None"),
                    tostring(st.targetRange and math_floor(st.targetRange) or "-"),
                    tostring(st.drillPhase or "-")
                )
            else
                txt = "Artillery | No active battery mounted"
            end
            if not RenderState.LastArtyVis then
                RenderState.LastArtyVis = true
                HudArty.Visible = true
            end
            if RenderState.LastArtyText ~= txt then
                RenderState.LastArtyText = txt
                HudArty.Text = txt
            end
        elseif RenderState.LastArtyVis then
            RenderState.LastArtyVis = false
            HudArty.Visible = false
        end
    end

    if HudThreat then
        local proxWarn, artyWarn
        if threatsOn and myHrp and nearestChargeDistSq <= (Cfg.esp_warn_dist * Cfg.esp_warn_dist) then
            proxWarn = string_format("ENEMY PROXIMITY ALERT (%dm)", math_floor(math_sqrt(nearestChargeDistSq)))
        end
        if Cfg.arty_warn and st and st.targetRange and tonumber(st.targetRange) <= Cfg.arty_minrange then
            artyWarn = string_format("ARTILLERY MINIMUM SAFE RANGE WARNING (%dm)", math_floor(tonumber(st.targetRange) or 0))
        end
        local threatTxt = (proxWarn and artyWarn) and (proxWarn .. "  |  " .. artyWarn) or (proxWarn or artyWarn)
        if threatTxt then
            if not RenderState.LastThreatVis then
                RenderState.LastThreatVis = true
                HudThreat.Visible = true
            end
            HudThreat.Position = Vector2_new(cx, 46)
            if RenderState.LastThreatText ~= threatTxt then
                RenderState.LastThreatText = threatTxt
                HudThreat.Text = threatTxt
            end
        elseif RenderState.LastThreatVis then
            RenderState.LastThreatVis = false
            HudThreat.Visible = false
        end
    end

    -- Blink Spy On-Screen Feed
    local showSpyFeed = Cfg.spy_enabled and Cfg.spy_hud and #State.SpyLogs > 0
    for i = 1, State.SpyMaxLogs do
        local slot = HudSpyLines[i]
        if slot then
            local d = slot.Draw
            local txt = showSpyFeed and State.SpyLogs[i] or nil
            if txt then
                if not slot._vis then
                    slot._vis = true
                    d.Visible = true
                end
                local yPos = vpY - 30 - (i * 15)
                if slot._y ~= yPos then
                    slot._y = yPos
                    d.Position = Vector2_new(14, yPos)
                end
                if slot._text ~= txt then
                    slot._text = txt
                    d.Text = txt
                end
            elseif slot._vis then
                slot._vis = false
                d.Visible = false
            end
        end
    end
end

--==============================================================================
-- 13. CONFIG SLOTS MANAGEMENT & POLLING SYNC
--==============================================================================
local function getSelectedConfigSlot()
    local obj = Pointers and Pointers.cfg_slot
    local slot = getVal("cfg_slot", nil) or (obj and obj.current) or 1
    if type(slot) == "number" or tonumber(slot) then
        return "slot_" .. tostring(slot)
    end
    return tostring(slot)
end

Actions.SaveConfigSlot = function()
    local name = getSelectedConfigSlot()
    local path = State.SavedFolder .. "/" .. name .. ".json"
    local ok, json = pcall(Window.GetConfig, Window)
    if ok and type(json) == "string" and writefile then
        pcall(writefile, path, json)
        print("[NWB Config] Saved configuration -> " .. path)
    end
end

Actions.LoadConfigSlot = function()
    local name = getSelectedConfigSlot()
    local path = State.SavedFolder .. "/" .. name .. ".json"
    if isfile and readfile and isfile(path) then
        local okRead, json = pcall(readfile, path)
        if okRead and type(json) == "string" then
            pcall(Window.LoadConfig, Window, json)
            refreshHotConfig()
            print("[NWB Config] Loaded configuration <- " .. path)
        end
    else
        print("[NWB Config] Config file does not exist yet: " .. path)
    end
end

Actions.DeleteConfigSlot = function()
    local name = getSelectedConfigSlot()
    local path = State.SavedFolder .. "/" .. name .. ".json"
    if isfile and delfile and isfile(path) then
        pcall(delfile, path)
        print("[NWB Config] Deleted configuration: " .. path)
    end
end

Actions.CopyConfigJson = function()
    local ok, json = pcall(Window.GetConfig, Window)
    if ok and type(json) == "string" and setclipboard then
        pcall(setclipboard, json)
        print("[NWB Config] Copied config JSON to clipboard.")
    end
end

--==============================================================================
-- 14. MAIN LOOPS (20HZ GAME SNAPSHOT/AUTOMATION + RENDERSTEPPED VISUALS)
--==============================================================================
refreshHotConfig()

task.spawn(function()
    while not State.Unloaded do
        local now = os_clock()
        Camera = Workspace.CurrentCamera
        pcall(refreshHotConfig)
        pcall(refreshSnapshots)
        pcall(stepCompanyAutomation, now)
        pcall(stepArtilleryAutomation, now)
        pcall(applyWorldVisuals)

        if getVal("qol_autoclaim", false) and (now - State.Timers.Missions) >= 8 then
            State.Timers.Missions = now
            Actions.ClaimMissions(false)
        end

        if getVal("qol_autovote", false) and (now - State.Timers.Vote) >= 12 then
            State.Timers.Vote = now
            Actions.VoteMode()
            Actions.VoteMapAndTime()
        end

        if Cfg.qol_autodeployfix and (now - State.Timers.DeployFix) >= 1.2 then
            State.Timers.DeployFix = now
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local pg = LocalPlayer:FindFirstChild("PlayerGui")
                local tMenu = pg and pg:FindFirstChild("TeamSelectMenu")
                local mMenu = pg and pg:FindFirstChild("MainMenu")
                local isStuck = (tMenu and tMenu:IsA("ScreenGui") and tMenu.Enabled)
                    or (mMenu and mMenu:IsA("ScreenGui") and mMenu.Enabled)
                    or (Camera and Camera.CameraType == Enum.CameraType.Scriptable and not (Cfg.cam_freecam or Cfg.cam_rts))
                if isStuck then
                    Actions.FixDeploymentScreen(false)
                end
            end
        end

        local menuBind = getVal("ui_menubind", nil)
        if Window then
            if typeof(menuBind) == "EnumItem" then
                Window.uibind = menuBind
            elseif type(menuBind) == "table" and type(menuBind[1]) == "string" and type(menuBind[2]) == "string" then
                local okEnum, item = pcall(function() return Enum[menuBind[1]][menuBind[2]] end)
                if okEnum and typeof(item) == "EnumItem" then
                    Window.uibind = item
                end
            end
        end
        if Window and Window.keybindslist then
            local showKb = getVal("ui_keybinds", true)
            if State.PrevStates.KeybindsVisible ~= showKb then
                State.PrevStates.KeybindsVisible = showKb
                pcall(function() Window.keybindslist:Visibility(showKb) end)
            end
        end

        task.wait(0.05)
    end
end)

-- RenderStepped no longer runs refreshHotConfig() (saves ~70 pcalls/lookups per frame)
addConn(RunService.RenderStepped:Connect(function(dt)
    if State.Unloaded then return end
    Camera = Workspace.CurrentCamera
    pcall(stepMovementAndCamera, dt)
    pcall(renderEspAndVisuals)
end))

addConn(LocalPlayer.CharacterAdded:Connect(function(newChar)
    if State.Unloaded then return end
    refreshCharParts(newChar)
    task.wait(0.4)
    if getVal("mv_ws_on", false) then
        setWalkSpeedBypass(true, getVal("mv_ws_val", 70), os_clock())
    end
    if Cfg.qol_autodeployfix then
        task.delay(0.8, function()
            if not State.Unloaded and Cfg.qol_autodeployfix then
                local pg = LocalPlayer:FindFirstChild("PlayerGui")
                local tMenu = pg and pg:FindFirstChild("TeamSelectMenu")
                if tMenu and tMenu:IsA("ScreenGui") and tMenu.Enabled then
                    Actions.FixDeploymentScreen(false)
                end
            end
        end)
    end
end))

--==============================================================================
-- 15. FULL SAFE UNLOAD ROUTINE
--==============================================================================
env._NWB_SPLIX_UNLOAD = function()
    if State.Unloaded then return end
    State.Unloaded = true

    if MusketUtils and State.Hooks.OrigSpawnOwnerBullet then
        pcall(function()
            MusketUtils._spawnOwnerBullet = State.Hooks.OrigSpawnOwnerBullet
        end)
    end
    if hookmetamethod and State.Hooks.OldNamecall then
        pcall(hookmetamethod, game, "__namecall", State.Hooks.OldNamecall)
    end

    for _, conn in ipairs(State.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    table_clear(State.Connections)
    table_clear(State.NpcFolderConns)

    for _, unsub in ipairs(State.BlinkUnsubs) do
        pcall(unsub)
    end
    table_clear(State.BlinkUnsubs)

    pcall(setWalkSpeedBypass, false, Consts.DefaultWalkSpeed)
    pcall(setZoomBypass, false, State.OriginalMaxZoom)
    pcall(stopFly)
    pcall(function()
        if Camera and State.OriginalCameraType then
            Camera.CameraType = State.OriginalCameraType
        end
    end)

    if State.LightingSnapshot then
        pcall(function()
            Lighting.GlobalShadows = State.LightingSnapshot.GlobalShadows
            Lighting.Brightness = State.LightingSnapshot.Brightness
            Lighting.ClockTime = State.LightingSnapshot.ClockTime
            Lighting.FogEnd = State.LightingSnapshot.FogEnd
            Lighting.Ambient = State.LightingSnapshot.Ambient
            Lighting.OutdoorAmbient = State.LightingSnapshot.OutdoorAmbient
        end)
    end
    for fx, wasEnabled in pairs(State.FXSnapshot) do
        pcall(function() fx.Enabled = wasEnabled end)
    end
    for pe, wasEnabled in pairs(State.SmokeSnapshot) do
        if pe and pe.Parent then
            pcall(function() pe.Enabled = wasEnabled end)
        end
    end

    for _, d in ipairs(State.Drawings) do
        pcall(function() d:Remove() end)
    end
    table_clear(State.Drawings)
    table_clear(State.NpcModels)
    table_clear(State.NpcRecordCache)
    table_clear(State.NpcSnapshots)
    State.NpcSnapshotCount = 0
    table_clear(State.CompanyClusters)
    table_clear(State.DroppedFlags)
    table_clear(State.CharParts)
    table_clear(State.SmokeEmitters)
    table_clear(PlayerRecordCache)

    if Window and type(Window.Unload) == "function" then
        pcall(Window.Unload, Window)
    end
    if Library then
        Library.drawings = {}
    end

    env._NWB_SPLIX_UNLOAD = nil
    print("[NWB Suite] Unloaded cleanly.")
end

print("[NWB] Loaded successfully (Potassium Optimized). Press " .. tostring(Window.uibind.Name) .. " to toggle menu.")
