--[[
    ╔══════════════════════════════════════════════════════╗
    ║         VOID SPAM + RAGEBOT  v1.0                   ║
    ║  Platform  : Roblox Executor (Synapse X / KRNL etc) ║
    ║  Arch      : LocalScript injection, client-side     ║
    ║  Game      : FighterController-based shooter        ║
    ║  Sections  :                                        ║
    ║    [1] Core services + controller pointers          ║
    ║    [2] Void Spam (teleport enemies under map)       ║
    ║    [3] Ragebot  (silent aim, FOV, bone select)      ║
    ║    [4] UI                                           ║
    ╚══════════════════════════════════════════════════════╝
]]

-- ─────────────────────────────────────────────
-- [1]  CORE SERVICES & POINTERS
-- ─────────────────────────────────────────────
local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService   = game:GetService("TweenService")
local Camera         = workspace.CurrentCamera

local LP             = Players.LocalPlayer
local PlayerGui      = LP:WaitForChild("PlayerGui")

-- Grab the already-initialised controllers from the require cache.
-- The game loads them all into LocalPlayer.PlayerScripts; we grab them
-- via the same require path the game itself uses.  If getgenv / getrenv
-- gethiddenproperty is not available we fall back to a simple module scan.
local function safeRequire(path)
    local ok, result = pcall(require, path)
    return ok and result or nil
end

local PlayerScripts  = LP:WaitForChild("PlayerScripts")
local RepStorage     = game:GetService("ReplicatedStorage")

local FighterController = safeRequire(PlayerScripts.Controllers.FighterController)
local MechController    = safeRequire(PlayerScripts.Controllers.MechanicsController)
local EnemyController   = safeRequire(PlayerScripts.Controllers.EnemyController)

-- ─────────────────────────────────────────────
-- [2]  CONFIG  (all toggleable from UI)
-- ─────────────────────────────────────────────
local CFG = {
    -- Void Spam
    VoidEnabled      = false,
    VoidY            = -500,          -- Y position to send targets to
    VoidInterval     = 0.15,          -- seconds between teleport pulses
    VoidTargetMode   = "Nearest",     -- "Nearest" | "All"

    -- Ragebot
    RagebotEnabled   = false,
    RagebotBone      = "Head",        -- "Head" | "HumanoidRootPart" | "Torso"
    RagebotFOV       = 180,           -- degrees; 180 = no FOV limit
    RagebotSilent    = true,          -- silent-aim (move camera vector, not CFrame)
    RagebotAutoFire  = true,          -- trigger EquippedItemInput automatically
    RagebotWallCheck = false,         -- skip targets behind walls
    RagebotTeamCheck = true,          -- skip teammates
}

-- ─────────────────────────────────────────────
-- [3]  HELPER UTILITIES
-- ─────────────────────────────────────────────

-- Returns all alive enemy fighters (excludes LocalPlayer's fighter)
local function getTargets()
    local targets = {}
    if not FighterController then return targets end
    for _, fighter in pairs(FighterController.Objects) do
        -- skip self
        if fighter.IsLocalPlayer then continue end
        -- skip dead
        if not fighter.IsAlive or not fighter:IsAlive() then continue end
        -- skip no entity
        if not fighter.Entity then continue end
        local model = fighter.Entity.Model
        if not model then continue end
        -- team check
        if CFG.RagebotTeamCheck then
            local plr = Players:GetPlayerFromCharacter(model)
            if plr and plr.Team == LP.Team then continue end
        end
        table.insert(targets, fighter)
    end
    return targets
end

-- Distance from camera to world position
local function distFromCam(pos)
    return (Camera.CFrame.Position - pos).Magnitude
end

-- Angle in degrees between camera look and direction to point
local function fovAngle(pos)
    local dir     = (pos - Camera.CFrame.Position).Unit
    local look    = Camera.CFrame.LookVector
    local dot     = math.clamp(look:Dot(dir), -1, 1)
    return math.deg(math.acos(dot))
end

-- Get the bone CFrame of a fighter (falls back gracefully)
local function getBoneCF(fighter)
    local model = fighter.Entity and fighter.Entity.Model
    if not model then return nil end
    local part = model:FindFirstChild(CFG.RagebotBone)
        or model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("Torso")
    if not part then return nil end
    return part.CFrame
end

-- Nearest alive fighter within FOV
local function getNearestTarget()
    local best, bestAngle = nil, math.huge
    for _, fighter in pairs(getTargets()) do
        local cf = getBoneCF(fighter)
        if not cf then continue end
        local angle = fovAngle(cf.Position)
        if angle < CFG.RagebotFOV / 2 and angle < bestAngle then
            bestAngle = angle
            best      = fighter
        end
    end
    return best
end

-- Simple raycast wall check
local function wallCheck(origin, target)
    local dir     = (target - origin)
    local dist    = dir.Magnitude
    local params  = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    -- exclude character models
    local excl = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character then table.insert(excl, plr.Character) end
    end
    params.FilterDescendantsInstances = excl
    local result = workspace:Raycast(origin, dir.Unit * dist, params)
    return result ~= nil  -- true = wall in the way
end

-- ─────────────────────────────────────────────
-- [4]  VOID SPAM
-- ─────────────────────────────────────────────
-- Strategy: on each pulse, grab target(s) RootPart and CFrame-move them
-- to Y = VoidY.  This is client-side, but in many games the server
-- accepts CFrame replication from the owner if anti-cheat is weak.
-- For fighter-controller games the entity RootPart position is what the
-- server reads for physics authority.

local lastVoidTick = 0

local function runVoidSpam()
    if not CFG.VoidEnabled then return end
    if tick() - lastVoidTick < CFG.VoidInterval then return end
    lastVoidTick = tick()

    local targets
    if CFG.VoidTargetMode == "All" then
        targets = getTargets()
    else
        local t = getNearestTarget()
        targets = t and { t } or {}
    end

    for _, fighter in ipairs(targets) do
        local model = fighter.Entity and fighter.Entity.Model
        if not model then continue end
        local root = model:FindFirstChild("HumanoidRootPart")
        if not root then continue end
        -- teleport the root below the map
        local cf = root.CFrame
        local voidCF = CFrame.new(cf.X, CFG.VoidY, cf.Z)
        -- Use the game's own physics owner to push position
        pcall(function()
            root.CFrame = voidCF
        end)
        -- Also fire the character through Animate velocity hack:
        -- set Velocity to straight down to skip fall detection
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.new(0, -400, 0)
        end)
    end
end

-- ─────────────────────────────────────────────
-- [5]  RAGEBOT
-- ─────────────────────────────────────────────
-- Silent aim: on each RenderStepped we intercept the camera LookVector
-- by wrapping workspace.CurrentCamera.CFrame so that the game's own
-- raycast (see MechanicsController._CanAutoShoot) hits our target.
-- Then we optionally auto-fire via EquippedItemInput.

local origCF       = nil   -- saved real camera CFrame each frame
local ragebotLock  = nil   -- current locked fighter

local function getSilentCF(targetPos)
    -- Build a camera CFrame pointing at the target from real position
    local realPos = Camera.CFrame.Position
    return CFrame.lookAt(realPos, targetPos)
end

local function ragebotTick()
    if not CFG.RagebotEnabled then
        ragebotLock = nil
        return
    end
    if not FighterController then return end

    local lf = FighterController.LocalFighter
    if not lf or not lf.IsAlive or not lf:IsAlive() then return end
    if not lf.EquippedItem then return end   -- need a weapon

    local target = getNearestTarget()
    if not target then
        ragebotLock = nil
        return
    end

    local boneCF = getBoneCF(target)
    if not boneCF then return end
    local bonePos = boneCF.Position

    -- Optional wall check
    if CFG.RagebotWallCheck then
        if wallCheck(Camera.CFrame.Position, bonePos) then
            ragebotLock = nil
            return
        end
    end

    ragebotLock = target

    -- Silent aim: deflect camera temporarily
    if CFG.RagebotSilent then
        local silentCF = getSilentCF(bonePos)
        -- Temporarily overwrite camera CFrame for this frame only
        -- (restore happens at end of frame via RenderStepped priority)
        Camera.CFrame = silentCF
    end

    -- Auto fire
    if CFG.RagebotAutoFire then
        pcall(function()
            if lf.EquippedItem then
                -- Use the same path the game uses internally
                MechController:EquippedItemInput("StartShooting")
                task.defer(function()
                    pcall(function()
                        MechController:EquippedItemInput("FinishShooting")
                    end)
                end)
            end
        end)
    end
end

-- Restore real camera after silent aim each frame
local ragebotConn, restoreConn

local function startRagebotLoop()
    if ragebotConn then ragebotConn:Disconnect() end
    if restoreConn then restoreConn:Disconnect() end

    -- High-priority: deflect aim
    ragebotConn = RunService:BindToRenderStep(
        "RagebotAim",
        Enum.RenderPriority.Camera.Value + 1,
        function()
            origCF = Camera.CFrame  -- save real CF
            ragebotTick()
        end
    )

    -- Low-priority: restore so the player's view isn't stuck
    restoreConn = RunService:BindToRenderStep(
        "RagebotRestore",
        Enum.RenderPriority.Last.Value,
        function()
            if origCF and not CFG.RagebotEnabled then
                Camera.CFrame = origCF
            end
        end
    )
end

startRagebotLoop()

-- Void spam on Heartbeat
local voidConn = RunService.Heartbeat:Connect(runVoidSpam)

-- ─────────────────────────────────────────────
-- [6]  UI
-- ─────────────────────────────────────────────

-- Destroy any old instance
if PlayerGui:FindFirstChild("CheatUI") then
    PlayerGui.CheatUI:Destroy()
end

local ScreenGui    = Instance.new("ScreenGui")
ScreenGui.Name     = "CheatUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent   = PlayerGui

-- ── Colour palette ────────────────────────────
local COL = {
    bg       = Color3.fromRGB(15, 15, 20),
    header   = Color3.fromRGB(25, 25, 35),
    accent   = Color3.fromRGB(100, 60, 220),   -- purple
    accent2  = Color3.fromRGB(220, 60, 100),   -- red-pink
    textMain = Color3.fromRGB(230, 230, 240),
    textDim  = Color3.fromRGB(130, 130, 150),
    on       = Color3.fromRGB(80, 220, 120),
    off      = Color3.fromRGB(220, 80, 80),
    slider   = Color3.fromRGB(60, 60, 80),
    sliderFg = Color3.fromRGB(100, 60, 220),
    sep      = Color3.fromRGB(40, 40, 55),
}

-- ── Main frame ────────────────────────────────
local Main = Instance.new("Frame")
Main.Name  = "Main"
Main.Size  = UDim2.new(0, 310, 0, 0)   -- height auto via layout
Main.Position = UDim2.new(0, 24, 0.5, -200)
Main.BackgroundColor3 = COL.bg
Main.BorderSizePixel  = 0
Main.ClipsDescendants = true
Main.Parent = ScreenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = Main

local stroke = Instance.new("UIStroke")
stroke.Color     = COL.accent
stroke.Thickness = 1.5
stroke.Transparency = 0.4
stroke.Parent = Main

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.SortOrder     = Enum.SortOrder.LayoutOrder
layout.Padding       = UDim.new(0, 0)
layout.Parent        = Main

-- Auto-size Main height to content
layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    Main.Size = UDim2.new(0, 310, 0, layout.AbsoluteContentSize.Y)
end)

-- ── Drag logic ────────────────────────────────
do
    local dragging, dragStart, startPos
    Main.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging  = true
            dragStart = inp.Position
            startPos  = Main.Position
        end
    end)
    Main.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = inp.Position - dragStart
            Main.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

-- ── UI helper builders ─────────────────────────

local function makeHeader(text, layoutOrder)
    local f = Instance.new("Frame")
    f.Size  = UDim2.new(1, 0, 0, 36)
    f.BackgroundColor3 = COL.header
    f.BorderSizePixel  = 0
    f.LayoutOrder      = layoutOrder
    f.Parent           = Main

    local lbl = Instance.new("TextLabel")
    lbl.Size  = UDim2.new(1, -12, 1, 0)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text  = text
    lbl.Font  = Enum.Font.GothamBold
    lbl.TextSize = 13
    lbl.TextColor3 = COL.accent
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = f
    return f
end

local function makeSeparator(layoutOrder)
    local f = Instance.new("Frame")
    f.Size  = UDim2.new(1, 0, 0, 1)
    f.BackgroundColor3 = COL.sep
    f.BorderSizePixel  = 0
    f.LayoutOrder      = layoutOrder
    f.Parent           = Main
end

-- Toggle row  →  returns label, toggleBtn, getBool, setBool
local function makeToggle(label, default, layoutOrder, onChange)
    local row = Instance.new("Frame")
    row.Size  = UDim2.new(1, 0, 0, 38)
    row.BackgroundTransparency = 1
    row.LayoutOrder = layoutOrder
    row.Parent = Main

    local lbl = Instance.new("TextLabel")
    lbl.Size  = UDim2.new(0.65, 0, 1, 0)
    lbl.Position = UDim2.new(0, 14, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text  = label
    lbl.Font  = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextColor3 = COL.textMain
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local pill = Instance.new("Frame")
    pill.Size  = UDim2.new(0, 44, 0, 22)
    pill.Position = UDim2.new(1, -58, 0.5, -11)
    pill.BackgroundColor3 = default and COL.on or COL.off
    pill.BorderSizePixel  = 0
    pill.Parent = row

    local pillCorner = Instance.new("UICorner")
    pillCorner.CornerRadius = UDim.new(1, 0)
    pillCorner.Parent = pill

    local knob = Instance.new("Frame")
    knob.Size  = UDim2.new(0, 16, 0, 16)
    knob.Position = default and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel  = 0
    knob.Parent = pill

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local state = default
    local function setState(val)
        state = val
        local info = TweenInfo.new(0.15, Enum.EasingStyle.Quad)
        TweenService:Create(pill, info, {BackgroundColor3 = val and COL.on or COL.off}):Play()
        TweenService:Create(knob, info, {Position = val
            and UDim2.new(1, -19, 0.5, -8)
            or  UDim2.new(0, 3,   0.5, -8)}):Play()
        if onChange then onChange(val) end
    end

    pill.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            setState(not state)
        end
    end)

    return { getState = function() return state end, setState = setState }
end

-- Dropdown row
local function makeDropdown(label, options, default, layoutOrder, onChange)
    local row = Instance.new("Frame")
    row.Size  = UDim2.new(1, 0, 0, 38)
    row.BackgroundTransparency = 1
    row.LayoutOrder = layoutOrder
    row.ClipsDescendants = false
    row.Parent = Main

    local lbl = Instance.new("TextLabel")
    lbl.Size  = UDim2.new(0.5, 0, 1, 0)
    lbl.Position = UDim2.new(0, 14, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text  = label
    lbl.Font  = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextColor3 = COL.textMain
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size  = UDim2.new(0, 110, 0, 24)
    btn.Position = UDim2.new(1, -122, 0.5, -12)
    btn.BackgroundColor3 = COL.slider
    btn.BorderSizePixel  = 0
    btn.Text  = default
    btn.Font  = Enum.Font.Gotham
    btn.TextSize = 11
    btn.TextColor3 = COL.textMain
    btn.Parent = row

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = btn

    local current = default

    -- Dropdown list (spawns under button, destroyed on select)
    btn.MouseButton1Click:Connect(function()
        -- remove any old list
        local old = row:FindFirstChild("DropList")
        if old then old:Destroy(); return end

        local list = Instance.new("Frame")
        list.Name = "DropList"
        list.Size = UDim2.new(0, 110, 0, #options * 26 + 4)
        list.Position = UDim2.new(1, -122, 1, 2)
        list.BackgroundColor3 = COL.header
        list.BorderSizePixel  = 0
        list.ZIndex = 10
        list.Parent = row

        local lc = Instance.new("UICorner")
        lc.CornerRadius = UDim.new(0, 6)
        lc.Parent = list

        local ll = Instance.new("UIListLayout")
        ll.Padding = UDim.new(0, 2)
        ll.Parent  = list

        local lpad = Instance.new("UIPadding")
        lpad.PaddingTop  = UDim.new(0, 2)
        lpad.PaddingLeft = UDim.new(0, 4)
        lpad.Parent = list

        for _, opt in ipairs(options) do
            local ob = Instance.new("TextButton")
            ob.Size  = UDim2.new(1, -8, 0, 22)
            ob.BackgroundColor3 = opt == current and COL.accent or COL.slider
            ob.BorderSizePixel  = 0
            ob.Text  = opt
            ob.Font  = Enum.Font.Gotham
            ob.TextSize = 11
            ob.TextColor3 = COL.textMain
            ob.ZIndex = 11
            ob.Parent = list

            local oc = Instance.new("UICorner")
            oc.CornerRadius = UDim.new(0, 4)
            oc.Parent = ob

            ob.MouseButton1Click:Connect(function()
                current = opt
                btn.Text = opt
                list:Destroy()
                if onChange then onChange(opt) end
            end)
        end
    end)

    return { getCurrent = function() return current end }
end

-- Slider row  →  min,max,step,default,onChange
local function makeSlider(label, min, max, step, default, layoutOrder, onChange)
    local row = Instance.new("Frame")
    row.Size  = UDim2.new(1, 0, 0, 44)
    row.BackgroundTransparency = 1
    row.LayoutOrder = layoutOrder
    row.Parent = Main

    local lbl = Instance.new("TextLabel")
    lbl.Size  = UDim2.new(1, -14, 0, 20)
    lbl.Position = UDim2.new(0, 14, 0, 2)
    lbl.BackgroundTransparency = 1
    lbl.Font  = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextColor3 = COL.textMain
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local valLbl = Instance.new("TextLabel")
    valLbl.Size  = UDim2.new(0, 50, 0, 20)
    valLbl.Position = UDim2.new(1, -64, 0, 2)
    valLbl.BackgroundTransparency = 1
    valLbl.Font  = Enum.Font.GothamBold
    valLbl.TextSize = 12
    valLbl.TextColor3 = COL.accent
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.Parent = row

    local track = Instance.new("Frame")
    track.Size  = UDim2.new(1, -28, 0, 6)
    track.Position = UDim2.new(0, 14, 0, 28)
    track.BackgroundColor3 = COL.slider
    track.BorderSizePixel  = 0
    track.Parent = row

    local tc = Instance.new("UICorner")
    tc.CornerRadius = UDim.new(1, 0)
    tc.Parent = track

    local fill = Instance.new("Frame")
    fill.Size  = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = COL.sliderFg
    fill.BorderSizePixel  = 0
    fill.Parent = track

    local fc = Instance.new("UICorner")
    fc.CornerRadius = UDim.new(1, 0)
    fc.Parent = fill

    local value = default
    local function setValue(v)
        v = math.clamp(math.round(v / step) * step, min, max)
        value = v
        local pct = (v - min) / (max - min)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        lbl.Text  = label
        valLbl.Text = tostring(v)
        if onChange then onChange(v) end
    end
    setValue(default)

    local dragging = false
    track.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
        end
    end)
    track.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local relX = math.clamp(
                inp.Position.X - track.AbsolutePosition.X,
                0,
                track.AbsoluteSize.X
            )
            local pct = relX / track.AbsoluteSize.X
            setValue(min + pct * (max - min))
        end
    end)

    return { getValue = function() return value end, setValue = setValue }
end

-- ── Build the UI sections ─────────────────────

-- Title header
do
    local h = Instance.new("Frame")
    h.Size  = UDim2.new(1, 0, 0, 44)
    h.BackgroundColor3 = COL.header
    h.BorderSizePixel  = 0
    h.LayoutOrder       = 0
    h.Parent = Main

    local title = Instance.new("TextLabel")
    title.Size  = UDim2.new(1, 0, 1, 0)
    title.BackgroundTransparency = 1
    title.Text  = "⚡  VOID + RAGE"
    title.Font  = Enum.Font.GothamBold
    title.TextSize = 15
    title.TextColor3 = COL.textMain
    title.Parent = h

    -- small subtitle
    local sub = Instance.new("TextLabel")
    sub.Size  = UDim2.new(1, 0, 0, 14)
    sub.Position = UDim2.new(0, 0, 1, -14)
    sub.BackgroundTransparency = 1
    sub.Text  = "drag to move  •  v1.0"
    sub.Font  = Enum.Font.Gotham
    sub.TextSize = 10
    sub.TextColor3 = COL.textDim
    sub.Parent = h
end

-- ── VOID SPAM section ─────────────────────────
makeHeader("  VOID SPAM", 1)
makeSeparator(2)

local voidToggle = makeToggle("Enable Void Spam", CFG.VoidEnabled, 3, function(v)
    CFG.VoidEnabled = v
end)

makeDropdown("Target Mode", {"Nearest", "All"}, CFG.VoidTargetMode, 4, function(v)
    CFG.VoidTargetMode = v
end)

makeSlider("Void Y (depth)", -2000, -50, 50, CFG.VoidY, 5, function(v)
    CFG.VoidY = v
end)

makeSlider("Interval (s × 100)", 1, 100, 1, math.round(CFG.VoidInterval * 100), 6, function(v)
    CFG.VoidInterval = v / 100
end)

makeSeparator(7)

-- ── RAGEBOT section ───────────────────────────
makeHeader("  RAGEBOT", 8)
makeSeparator(9)

local rageToggle = makeToggle("Enable Ragebot", CFG.RagebotEnabled, 10, function(v)
    CFG.RagebotEnabled = v
end)

makeToggle("Silent Aim", CFG.RagebotSilent, 11, function(v)
    CFG.RagebotSilent = v
end)

makeToggle("Auto Fire", CFG.RagebotAutoFire, 12, function(v)
    CFG.RagebotAutoFire = v
end)

makeToggle("Wall Check", CFG.RagebotWallCheck, 13, function(v)
    CFG.RagebotWallCheck = v
end)

makeToggle("Team Check", CFG.RagebotTeamCheck, 14, function(v)
    CFG.RagebotTeamCheck = v
end)

makeDropdown("Bone Target", {"Head", "Torso", "HumanoidRootPart"}, CFG.RagebotBone, 15, function(v)
    CFG.RagebotBone = v
end)

makeSlider("FOV (°)", 10, 180, 5, CFG.RagebotFOV, 16, function(v)
    CFG.RagebotFOV = v
end)

makeSeparator(17)

-- ── FOV circle visualiser ─────────────────────
do
    local fovRow = Instance.new("Frame")
    fovRow.Size  = UDim2.new(1, 0, 0, 30)
    fovRow.BackgroundTransparency = 1
    fovRow.LayoutOrder = 18
    fovRow.Parent = Main

    local fovLbl = Instance.new("TextLabel")
    fovLbl.Size  = UDim2.new(1, -14, 1, 0)
    fovLbl.Position = UDim2.new(0, 14, 0, 0)
    fovLbl.BackgroundTransparency = 1
    fovLbl.Text  = "FOV Circle on screen"
    fovLbl.Font  = Enum.Font.Gotham
    fovLbl.TextSize = 12
    fovLbl.TextColor3 = COL.textMain
    fovLbl.TextXAlignment = Enum.TextXAlignment.Left
    fovLbl.Parent = fovRow

    local fovToggle = makeToggle("Show FOV Circle", false, 19, function(v)
        CFG.ShowFOVCircle = v
    end)
    CFG.ShowFOVCircle = false
end

makeSeparator(20)

-- ── Status bar ────────────────────────────────
do
    local statusRow = Instance.new("Frame")
    statusRow.Size  = UDim2.new(1, 0, 0, 30)
    statusRow.BackgroundTransparency = 1
    statusRow.LayoutOrder = 21
    statusRow.Parent = Main

    local statusLbl = Instance.new("TextLabel")
    statusLbl.Name  = "StatusLabel"
    statusLbl.Size  = UDim2.new(1, -14, 1, 0)
    statusLbl.Position = UDim2.new(0, 14, 0, 0)
    statusLbl.BackgroundTransparency = 1
    statusLbl.Text  = "Status: idle"
    statusLbl.Font  = Enum.Font.Gotham
    statusLbl.TextSize = 11
    statusLbl.TextColor3 = COL.textDim
    statusLbl.TextXAlignment = Enum.TextXAlignment.Left
    statusLbl.Parent = statusRow

    -- Update status every 0.5s
    RunService.Heartbeat:Connect(function()
        local parts = {}
        if CFG.VoidEnabled   then table.insert(parts, "🕳 VOID") end
        if CFG.RagebotEnabled then
            local t = getNearestTarget()
            if t then
                local plr = Players:GetPlayerFromCharacter(t.Entity.Model)
                local name = plr and plr.Name or "NPC"
                table.insert(parts, "🎯 LOCKED: " .. name)
            else
                table.insert(parts, "🎯 RAGE (no target)")
            end
        end
        statusLbl.Text = #parts > 0 and table.concat(parts, "  ") or "Status: idle"
    end)
end

-- ── FOV Circle drawing ────────────────────────
do
    -- Draw an ellipse on the screen representing the FOV cone
    local fovCircle = Instance.new("Frame")
    fovCircle.Name  = "FOVCircle"
    fovCircle.BackgroundTransparency = 1
    fovCircle.BorderSizePixel = 0
    fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
    fovCircle.Size = UDim2.new(0, 200, 0, 200)
    fovCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
    fovCircle.ZIndex   = 5
    fovCircle.Parent   = ScreenGui

    local fovStroke = Instance.new("UIStroke")
    fovStroke.Color       = Color3.fromRGB(100, 60, 220)
    fovStroke.Thickness   = 1.5
    fovStroke.Transparency = 0.3
    fovStroke.Parent = fovCircle

    local fovC = Instance.new("UICorner")
    fovC.CornerRadius = UDim.new(1, 0)
    fovC.Parent = fovCircle

    RunService.RenderStepped:Connect(function()
        fovCircle.Visible = CFG.ShowFOVCircle
        if not CFG.ShowFOVCircle then return end
        -- Approximate pixel radius from FOV angle
        local vp   = Camera.ViewportSize
        local half = CFG.RagebotFOV / 2
        -- project: at distance 1, spread = tan(half_rad)
        local spread = math.tan(math.rad(half))
        -- focal length in pixels (heuristic)
        local fl = vp.Y / (2 * math.tan(math.rad(Camera.FieldOfView / 2)))
        local px = math.clamp(spread * fl, 10, math.min(vp.X, vp.Y) / 2)
        fovCircle.Size = UDim2.new(0, px * 2, 0, px * 2)
    end)
end

-- ── Keybind: RightAlt toggles void, F4 toggles ragebot ──
UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == Enum.KeyCode.RightAlt then
        CFG.VoidEnabled = not CFG.VoidEnabled
        voidToggle.setState(CFG.VoidEnabled)
    elseif inp.KeyCode == Enum.KeyCode.F4 then
        CFG.RagebotEnabled = not CFG.RagebotEnabled
        rageToggle.setState(CFG.RagebotEnabled)
    end
end)

print("[CheatUI] Loaded — RightAlt = void | F4 = ragebot")

--[[
    ═══════════════════════════════════════════════════
    ENHANCEMENTS UPON REQUEST
    ═══════════════════════════════════════════════════
    • Prediction lead  — shoot ahead of moving targets
      by factoring RootPart AssemblyLinearVelocity into
      the aim vector (needs bullet travel time constant)
    • ESP / Chams      — Highlight instances per fighter
      using the game's own PlayHurtEffect hook or a
      custom SelectionBox layer
    • Anti-aim resolver — detect fighter's real spine
      angle via Entity RootPart orientation deltas
    • Void trajectory  — apply a horizontal push vector
      to send targets off specific map edges rather than
      straight down
    • Whitelist        — per-player name exclusion list
      (friends you don't want to void)
    • Hotkey rebinding — click a row to capture next key
    ═══════════════════════════════════════════════════
]]
