--[[
    ╔══════════════════════════════════════════════════════════╗
    ║       VOID SPAM + RAGEBOT  v2.0  — MOBILE PORT         ║
    ║  Platform  : Roblox Executor — Hydrogen / Delta / Fluxus║
    ║              + Synapse X / KRNL on PC                   ║
    ║  Input     : Touch-first, Mouse fallback                ║
    ║  Changes from v1.0:                                     ║
    ║    • Touch drag on UI panel                             ║
    ║    • Touch sliders (TouchMoved)                         ║
    ║    • Touch-aware dropdown (Activated event)             ║
    ║    • On-screen VOID / RAGE quick-tap buttons            ║
    ║    • pcall-guarded BindToRenderStep → Heartbeat fallback║
    ║    • Controller require → getgenv cache scan fallback   ║
    ║    • AssemblyLinearVelocity write pcall-guarded         ║
    ║    • ScrollingFrame wrapper so panel fits small screens ║
    ╚══════════════════════════════════════════════════════════╝
]]

-- ─────────────────────────────────────────────────────────────
-- [1]  SERVICES
-- ─────────────────────────────────────────────────────────────
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Camera           = workspace.CurrentCamera

local LP               = Players.LocalPlayer
local PlayerGui        = LP:WaitForChild("PlayerGui")

-- ── Platform detection ────────────────────────────────────────
-- Touch = mobile executor  |  Mouse/Keyboard = PC executor
local IS_MOBILE = UserInputService.TouchEnabled
    and not UserInputService.KeyboardEnabled

-- ─────────────────────────────────────────────────────────────
-- [2]  CONTROLLER ACQUISITION
--      Primary  : require() via game's own path
--      Fallback : scan getgenv() / _G for already-cached tables
--      This is needed on Hydrogen/Delta where require() on
--      game scripts is sandboxed and returns nil silently.
-- ─────────────────────────────────────────────────────────────
local function safeRequire(path)
    local ok, res = pcall(require, path)
    return ok and type(res) == "table" and res or nil
end

-- Search a global env table for a controller by duck-typing
local function findInEnv(env, keys)
    if type(env) ~= "table" then return nil end
    for _, v in pairs(env) do
        if type(v) == "table" then
            local match = true
            for _, k in ipairs(keys) do
                if v[k] == nil then match = false; break end
            end
            if match then return v end
        end
    end
end

local PlayerScripts = LP:WaitForChild("PlayerScripts")

local FighterController = safeRequire(PlayerScripts.Controllers.FighterController)
local MechController    = safeRequire(PlayerScripts.Controllers.MechanicsController)
local EnemyController   = safeRequire(PlayerScripts.Controllers.EnemyController)

-- Fallback: getgenv scan (Synapse X / Fluxus expose getgenv)
if not FighterController then
    local ok, env = pcall(getgenv)
    if ok and env then
        FighterController = findInEnv(env, {"LocalFighter", "Objects", "GetFighter"})
        MechController    = findInEnv(env, {"LocalFighter", "EquippedItemInput", "IsCrouching"})
    end
end

-- Fallback: _G scan (some executors dump modules into _G)
if not FighterController then
    FighterController = findInEnv(_G, {"LocalFighter", "Objects", "GetFighter"})
    MechController    = MechController or findInEnv(_G, {"LocalFighter", "EquippedItemInput"})
end

-- ─────────────────────────────────────────────────────────────
-- [3]  CONFIG
-- ─────────────────────────────────────────────────────────────
local CFG = {
    -- Void Spam
    VoidEnabled      = false,
    VoidY            = -500,
    VoidInterval     = 0.15,
    VoidTargetMode   = "Nearest",   -- "Nearest" | "All"

    -- Ragebot
    RagebotEnabled   = false,
    RagebotBone      = "Head",      -- "Head" | "Torso" | "HumanoidRootPart"
    RagebotFOV       = 180,
    RagebotSilent    = true,
    RagebotAutoFire  = true,
    RagebotWallCheck = false,
    RagebotTeamCheck = true,
    ShowFOVCircle    = false,
}

-- ─────────────────────────────────────────────────────────────
-- [4]  HELPER UTILITIES
-- ─────────────────────────────────────────────────────────────
local function getTargets()
    local targets = {}
    if not FighterController then return targets end
    local ok, objs = pcall(function() return FighterController.Objects end)
    if not ok or not objs then return targets end
    for _, fighter in pairs(objs) do
        if fighter.IsLocalPlayer then continue end
        local alive = pcall(function()
            if not fighter.IsAlive then error() end
            if not fighter:IsAlive() then error() end
        end)
        if not alive then continue end
        if not fighter.Entity then continue end
        local model = fighter.Entity.Model
        if not model then continue end
        if CFG.RagebotTeamCheck then
            local plr = Players:GetPlayerFromCharacter(model)
            if plr and plr.Team == LP.Team then continue end
        end
        table.insert(targets, fighter)
    end
    return targets
end

local function fovAngle(pos)
    local dir  = (pos - Camera.CFrame.Position).Unit
    local look = Camera.CFrame.LookVector
    local dot  = math.clamp(look:Dot(dir), -1, 1)
    return math.deg(math.acos(dot))
end

local function getBoneCF(fighter)
    local model = fighter.Entity and fighter.Entity.Model
    if not model then return nil end
    local part = model:FindFirstChild(CFG.RagebotBone)
        or model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("Torso")
    if not part then return nil end
    return part.CFrame
end

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

local function wallCheck(origin, target)
    local dir    = target - origin
    local dist   = dir.Magnitude
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local excl = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character then table.insert(excl, plr.Character) end
    end
    params.FilterDescendantsInstances = excl
    local result = workspace:Raycast(origin, dir.Unit * dist, params)
    return result ~= nil
end

-- ─────────────────────────────────────────────────────────────
-- [5]  VOID SPAM
-- ─────────────────────────────────────────────────────────────
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
        targets = t and {t} or {}
    end

    for _, fighter in ipairs(targets) do
        local model = fighter.Entity and fighter.Entity.Model
        if not model then continue end
        local root = model:FindFirstChild("HumanoidRootPart")
        if not root then continue end
        local cf = root.CFrame
        pcall(function()
            root.CFrame = CFrame.new(cf.X, CFG.VoidY, cf.Z)
        end)
        -- velocity push — pcall guarded (fails silently on
        -- restricted mobile executors, CFrame alone still works)
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.new(0, -400, 0)
        end)
    end
end

RunService.Heartbeat:Connect(runVoidSpam)

-- ─────────────────────────────────────────────────────────────
-- [6]  RAGEBOT
-- ─────────────────────────────────────────────────────────────
local origCF      = nil
local ragebotLock = nil

local function ragebotTick()
    if not CFG.RagebotEnabled then ragebotLock = nil; return end
    if not FighterController then return end

    local lf
    pcall(function() lf = FighterController.LocalFighter end)
    if not lf then return end

    local alive = false
    pcall(function() alive = lf.IsAlive and lf:IsAlive() end)
    if not alive then return end

    local hasWeapon = false
    pcall(function() hasWeapon = lf.EquippedItem ~= nil end)
    if not hasWeapon then return end

    local target = getNearestTarget()
    if not target then ragebotLock = nil; return end

    local boneCF = getBoneCF(target)
    if not boneCF then return end
    local bonePos = boneCF.Position

    if CFG.RagebotWallCheck then
        if wallCheck(Camera.CFrame.Position, bonePos) then
            ragebotLock = nil; return
        end
    end

    ragebotLock = target

    if CFG.RagebotSilent then
        pcall(function()
            Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, bonePos)
        end)
    end

    if CFG.RagebotAutoFire and MechController then
        pcall(function()
            MechController:EquippedItemInput("StartShooting")
            task.defer(function()
                pcall(function()
                    MechController:EquippedItemInput("FinishShooting")
                end)
            end)
        end)
    end
end

-- ── BindToRenderStep with Heartbeat fallback ──────────────────
-- On some mobile executors BindToRenderStep throws or is a no-op.
local function bindRenderStep(name, priority, fn)
    local ok = pcall(function()
        RunService:BindToRenderStep(name, priority, fn)
    end)
    if not ok then
        -- fallback: Heartbeat (slightly less precise but works everywhere)
        RunService.Heartbeat:Connect(fn)
    end
end

local function startRagebotLoop()
    pcall(function() RunService:UnbindFromRenderStep("RagebotAim") end)
    pcall(function() RunService:UnbindFromRenderStep("RagebotRestore") end)

    bindRenderStep("RagebotAim",
        Enum.RenderPriority.Camera.Value + 1,
        function()
            origCF = Camera.CFrame
            ragebotTick()
        end
    )
    bindRenderStep("RagebotRestore",
        Enum.RenderPriority.Last.Value,
        function()
            if origCF and not CFG.RagebotEnabled then
                pcall(function() Camera.CFrame = origCF end)
            end
        end
    )
end

startRagebotLoop()

-- ─────────────────────────────────────────────────────────────
-- [7]  UI  — MOBILE-FIRST
-- ─────────────────────────────────────────────────────────────
if PlayerGui:FindFirstChild("CheatUI") then
    PlayerGui.CheatUI:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "CheatUI"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent         = PlayerGui

-- ── Colour palette ────────────────────────────────────────────
local COL = {
    bg       = Color3.fromRGB(13, 13, 18),
    header   = Color3.fromRGB(22, 22, 32),
    accent   = Color3.fromRGB(110, 65, 230),
    textMain = Color3.fromRGB(228, 228, 240),
    textDim  = Color3.fromRGB(120, 120, 145),
    on       = Color3.fromRGB(75, 215, 115),
    off      = Color3.fromRGB(215, 75, 85),
    slider   = Color3.fromRGB(55, 55, 75),
    sliderFg = Color3.fromRGB(110, 65, 230),
    sep      = Color3.fromRGB(38, 38, 52),
    btnVoid  = Color3.fromRGB(230, 65, 65),
    btnRage  = Color3.fromRGB(110, 65, 230),
}

-- Panel width: 300 on PC, 94% viewport on phone
local vp         = Camera.ViewportSize
local PANEL_W    = IS_MOBILE and math.min(300, vp.X * 0.94) or 310
-- Row heights slightly larger on mobile for fat fingers
local ROW_H      = IS_MOBILE and 44 or 38
local SLIDER_H   = IS_MOBILE and 50 or 44
local FONT_SIZE  = IS_MOBILE and 13 or 12
local PILL_W, PILL_H = IS_MOBILE and 50 or 44, IS_MOBILE and 26 or 22

-- ── Outer container with ScrollingFrame ──────────────────────
-- Mobile screens can be short; wrap in a scroll so nothing is clipped.
local maxH       = IS_MOBILE and (vp.Y * 0.80) or 700

local Outer = Instance.new("Frame")
Outer.Name              = "Outer"
Outer.Size              = UDim2.new(0, PANEL_W, 0, 44)   -- resized below
Outer.Position          = IS_MOBILE
    and UDim2.new(0.03, 0, 0.08, 0)
    or  UDim2.new(0, 24, 0.5, -200)
Outer.BackgroundColor3  = COL.bg
Outer.BorderSizePixel   = 0
Outer.ClipsDescendants  = true
Outer.Parent            = ScreenGui

local outerCorner = Instance.new("UICorner")
outerCorner.CornerRadius = UDim.new(0, 10)
outerCorner.Parent = Outer

local outerStroke = Instance.new("UIStroke")
outerStroke.Color       = COL.accent
outerStroke.Thickness   = 1.5
outerStroke.Transparency = 0.35
outerStroke.Parent = Outer

-- Title bar (always visible, used for dragging)
local TitleBar = Instance.new("Frame")
TitleBar.Name             = "TitleBar"
TitleBar.Size             = UDim2.new(1, 0, 0, 44)
TitleBar.Position         = UDim2.new(0, 0, 0, 0)
TitleBar.BackgroundColor3 = COL.header
TitleBar.BorderSizePixel  = 0
TitleBar.ZIndex           = 5
TitleBar.Parent           = Outer

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 10)
titleCorner.Parent = TitleBar

-- fix bottom corners of title bar
local titleFix = Instance.new("Frame")
titleFix.Size             = UDim2.new(1, 0, 0, 10)
titleFix.Position         = UDim2.new(0, 0, 1, -10)
titleFix.BackgroundColor3 = COL.header
titleFix.BorderSizePixel  = 0
titleFix.ZIndex           = 5
titleFix.Parent           = TitleBar

local titleLbl = Instance.new("TextLabel")
titleLbl.Size               = UDim2.new(1, -44, 1, 0)
titleLbl.Position           = UDim2.new(0, 14, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text               = "⚡  VOID + RAGE  v2.0"
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 14
titleLbl.TextColor3         = COL.textMain
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
titleLbl.ZIndex             = 6
titleLbl.Parent             = TitleBar

-- Collapse / expand button
local collapseBtn = Instance.new("TextButton")
collapseBtn.Size              = UDim2.new(0, 32, 0, 32)
collapseBtn.Position          = UDim2.new(1, -38, 0.5, -16)
collapseBtn.BackgroundColor3  = COL.accent
collapseBtn.BorderSizePixel   = 0
collapseBtn.Text              = "−"
collapseBtn.Font              = Enum.Font.GothamBold
collapseBtn.TextSize          = 16
collapseBtn.TextColor3        = Color3.fromRGB(255,255,255)
collapseBtn.ZIndex            = 6
collapseBtn.Parent            = TitleBar

local cc = Instance.new("UICorner")
cc.CornerRadius = UDim.new(0, 6)
cc.Parent = collapseBtn

-- ScrollingFrame for content
local Scroll = Instance.new("ScrollingFrame")
Scroll.Name                   = "Scroll"
Scroll.Size                   = UDim2.new(1, 0, 1, -44)
Scroll.Position               = UDim2.new(0, 0, 0, 44)
Scroll.BackgroundTransparency = 1
Scroll.BorderSizePixel        = 0
Scroll.ScrollBarThickness     = IS_MOBILE and 3 or 4
Scroll.ScrollBarImageColor3   = COL.accent
Scroll.CanvasSize             = UDim2.new(0, 0, 0, 0)  -- updated below
Scroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
Scroll.Parent                 = Outer

local ContentFrame = Instance.new("Frame")
ContentFrame.Name               = "Content"
ContentFrame.Size               = UDim2.new(1, 0, 0, 0)
ContentFrame.AutomaticSize      = Enum.AutomaticSize.Y
ContentFrame.BackgroundTransparency = 1
ContentFrame.Parent             = Scroll

local contentLayout = Instance.new("UIListLayout")
contentLayout.FillDirection = Enum.FillDirection.Vertical
contentLayout.SortOrder     = Enum.SortOrder.LayoutOrder
contentLayout.Padding       = UDim.new(0, 0)
contentLayout.Parent        = ContentFrame

-- Auto-resize Outer height to content (capped at maxH)
local collapsed = false
local expandedH = 44

contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    local contentH = contentLayout.AbsoluteContentSize.Y
    expandedH = math.min(contentH + 44, maxH)
    if not collapsed then
        Outer.Size = UDim2.new(0, PANEL_W, 0, expandedH)
    end
end)

-- Collapse logic
collapseBtn.Activated:Connect(function()
    collapsed = not collapsed
    local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad)
    if collapsed then
        collapseBtn.Text = "+"
        TweenService:Create(Outer, info, {Size = UDim2.new(0, PANEL_W, 0, 44)}):Play()
    else
        collapseBtn.Text = "−"
        TweenService:Create(Outer, info, {Size = UDim2.new(0, PANEL_W, 0, expandedH)}):Play()
    end
end)

-- ── DRAG — works for both Touch and Mouse ─────────────────────
do
    local dragging   = false
    local dragStartP = Vector2.zero   -- screen pos when drag began
    local frameStartP= Vector2.zero   -- Outer offset when drag began

    local function onDragStart(screenPos)
        dragging    = true
        dragStartP  = Vector2.new(screenPos.X, screenPos.Y)
        frameStartP = Vector2.new(Outer.Position.X.Offset, Outer.Position.Y.Offset)
    end
    local function onDragMove(screenPos)
        if not dragging then return end
        local delta = Vector2.new(screenPos.X, screenPos.Y) - dragStartP
        Outer.Position = UDim2.new(
            Outer.Position.X.Scale, frameStartP.X + delta.X,
            Outer.Position.Y.Scale, frameStartP.Y + delta.Y
        )
    end
    local function onDragEnd()
        dragging = false
    end

    -- Mouse drag
    TitleBar.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            onDragStart(inp.Position)
        end
    end)
    TitleBar.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            onDragEnd()
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            onDragMove(inp.Position)
        end
    end)

    -- Touch drag on title bar
    TitleBar.TouchStarted:Connect(function(touch, _)
        onDragStart(touch.Position)
    end)
    TitleBar.TouchEnded:Connect(function(_, _)
        onDragEnd()
    end)
    TitleBar.TouchMoved:Connect(function(touch, _)
        onDragMove(touch.Position)
    end)
end

-- ─────────────────────────────────────────────────────────────
-- [8]  UI COMPONENT BUILDERS
-- ─────────────────────────────────────────────────────────────

local function makeHeader(text, layoutOrder)
    local f = Instance.new("Frame")
    f.Size             = UDim2.new(1, 0, 0, 34)
    f.BackgroundColor3 = COL.header
    f.BorderSizePixel  = 0
    f.LayoutOrder      = layoutOrder
    f.Parent           = ContentFrame

    local lbl = Instance.new("TextLabel")
    lbl.Size               = UDim2.new(1, -12, 1, 0)
    lbl.Position           = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text               = text
    lbl.Font               = Enum.Font.GothamBold
    lbl.TextSize           = FONT_SIZE + 1
    lbl.TextColor3         = COL.accent
    lbl.TextXAlignment     = Enum.TextXAlignment.Left
    lbl.Parent             = f
end

local function makeSep(layoutOrder)
    local f = Instance.new("Frame")
    f.Size             = UDim2.new(1, 0, 0, 1)
    f.BackgroundColor3 = COL.sep
    f.BorderSizePixel  = 0
    f.LayoutOrder      = layoutOrder
    f.Parent           = ContentFrame
end

-- ── Toggle ────────────────────────────────────────────────────
local function makeToggle(label, default, layoutOrder, onChange)
    local row = Instance.new("Frame")
    row.Size               = UDim2.new(1, 0, 0, ROW_H)
    row.BackgroundTransparency = 1
    row.LayoutOrder        = layoutOrder
    row.Parent             = ContentFrame

    local lbl = Instance.new("TextLabel")
    lbl.Size               = UDim2.new(0.62, 0, 1, 0)
    lbl.Position           = UDim2.new(0, 14, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text               = label
    lbl.Font               = Enum.Font.Gotham
    lbl.TextSize           = FONT_SIZE
    lbl.TextColor3         = COL.textMain
    lbl.TextXAlignment     = Enum.TextXAlignment.Left
    lbl.TextWrapped        = true
    lbl.Parent             = row

    local pill = Instance.new("Frame")
    pill.Size              = UDim2.new(0, PILL_W, 0, PILL_H)
    pill.Position          = UDim2.new(1, -(PILL_W + 10), 0.5, -PILL_H/2)
    pill.BackgroundColor3  = default and COL.on or COL.off
    pill.BorderSizePixel   = 0
    pill.Parent            = row

    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size              = UDim2.new(0, PILL_H - 6, 0, PILL_H - 6)
    knob.Position          = default
        and UDim2.new(1, -(PILL_H - 3), 0.5, -(PILL_H-6)/2)
        or  UDim2.new(0, 3, 0.5, -(PILL_H-6)/2)
    knob.BackgroundColor3  = Color3.fromRGB(255,255,255)
    knob.BorderSizePixel   = 0
    knob.Parent            = pill

    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local state = default
    local info  = TweenInfo.new(0.15, Enum.EasingStyle.Quad)

    local function setState(val)
        state = val
        TweenService:Create(pill, info,
            {BackgroundColor3 = val and COL.on or COL.off}):Play()
        TweenService:Create(knob, info, {Position = val
            and UDim2.new(1, -(PILL_H-3), 0.5, -(PILL_H-6)/2)
            or  UDim2.new(0, 3,           0.5, -(PILL_H-6)/2)}):Play()
        if onChange then onChange(val) end
    end

    -- Activated fires for both mouse click AND touch tap
    local pillBtn = Instance.new("TextButton")
    pillBtn.Size               = UDim2.new(1, 0, 1, 0)
    pillBtn.BackgroundTransparency = 1
    pillBtn.Text               = ""
    pillBtn.Parent             = pill
    pillBtn.Activated:Connect(function() setState(not state) end)

    return { getState = function() return state end, setState = setState }
end

-- ── Dropdown ──────────────────────────────────────────────────
local function makeDropdown(label, options, default, layoutOrder, onChange)
    local row = Instance.new("Frame")
    row.Size               = UDim2.new(1, 0, 0, ROW_H)
    row.BackgroundTransparency = 1
    row.LayoutOrder        = layoutOrder
    row.ClipsDescendants   = false
    row.Parent             = ContentFrame

    local lbl = Instance.new("TextLabel")
    lbl.Size               = UDim2.new(0.48, 0, 1, 0)
    lbl.Position           = UDim2.new(0, 14, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text               = label
    lbl.Font               = Enum.Font.Gotham
    lbl.TextSize           = FONT_SIZE
    lbl.TextColor3         = COL.textMain
    lbl.TextXAlignment     = Enum.TextXAlignment.Left
    lbl.TextWrapped        = true
    lbl.Parent             = row

    local BW = 108
    local btn = Instance.new("TextButton")
    btn.Size               = UDim2.new(0, BW, 0, ROW_H - 10)
    btn.Position           = UDim2.new(1, -(BW + 8), 0.5, -(ROW_H-10)/2)
    btn.BackgroundColor3   = COL.slider
    btn.BorderSizePixel    = 0
    btn.Text               = default
    btn.Font               = Enum.Font.Gotham
    btn.TextSize           = FONT_SIZE - 1
    btn.TextColor3         = COL.textMain
    btn.Parent             = row

    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    local current = default

    btn.Activated:Connect(function()
        local old = row:FindFirstChild("DropList")
        if old then old:Destroy(); return end

        local list = Instance.new("Frame")
        list.Name              = "DropList"
        list.Size              = UDim2.new(0, BW, 0, #options * (ROW_H - 8) + 6)
        list.Position          = UDim2.new(1, -(BW + 8), 1, 2)
        list.BackgroundColor3  = COL.header
        list.BorderSizePixel   = 0
        list.ZIndex            = 20
        list.Parent            = row

        Instance.new("UICorner", list).CornerRadius = UDim.new(0, 6)

        local ll = Instance.new("UIListLayout")
        ll.Padding = UDim.new(0, 2)
        ll.Parent  = list

        local lpad = Instance.new("UIPadding")
        lpad.PaddingTop  = UDim.new(0, 3)
        lpad.PaddingLeft = UDim.new(0, 4)
        lpad.Parent      = list

        for _, opt in ipairs(options) do
            local ob = Instance.new("TextButton")
            ob.Size              = UDim2.new(1, -8, 0, ROW_H - 10)
            ob.BackgroundColor3  = opt == current and COL.accent or COL.slider
            ob.BorderSizePixel   = 0
            ob.Text              = opt
            ob.Font              = Enum.Font.Gotham
            ob.TextSize          = FONT_SIZE - 1
            ob.TextColor3        = COL.textMain
            ob.ZIndex            = 21
            ob.Parent            = list

            Instance.new("UICorner", ob).CornerRadius = UDim.new(0, 4)

            ob.Activated:Connect(function()
                current  = opt
                btn.Text = opt
                list:Destroy()
                if onChange then onChange(opt) end
            end)
        end
    end)

    return { getCurrent = function() return current end }
end

-- ── Slider — touch + mouse ────────────────────────────────────
local function makeSlider(label, minV, maxV, step, default, layoutOrder, onChange)
    local row = Instance.new("Frame")
    row.Size               = UDim2.new(1, 0, 0, SLIDER_H)
    row.BackgroundTransparency = 1
    row.LayoutOrder        = layoutOrder
    row.Parent             = ContentFrame

    local lbl = Instance.new("TextLabel")
    lbl.Size               = UDim2.new(0.65, -14, 0, 20)
    lbl.Position           = UDim2.new(0, 14, 0, 4)
    lbl.BackgroundTransparency = 1
    lbl.Text               = label
    lbl.Font               = Enum.Font.Gotham
    lbl.TextSize           = FONT_SIZE
    lbl.TextColor3         = COL.textMain
    lbl.TextXAlignment     = Enum.TextXAlignment.Left
    lbl.Parent             = row

    local valLbl = Instance.new("TextLabel")
    valLbl.Size            = UDim2.new(0.35, -6, 0, 20)
    valLbl.Position        = UDim2.new(0.65, 0, 0, 4)
    valLbl.BackgroundTransparency = 1
    valLbl.Font            = Enum.Font.GothamBold
    valLbl.TextSize        = FONT_SIZE
    valLbl.TextColor3      = COL.accent
    valLbl.TextXAlignment  = Enum.TextXAlignment.Right
    valLbl.Parent          = row

    local trackY   = IS_MOBILE and 32 or 28
    local trackH   = IS_MOBILE and 8 or 6

    local track = Instance.new("Frame")
    track.Size             = UDim2.new(1, -28, 0, trackH)
    track.Position         = UDim2.new(0, 14, 0, trackY)
    track.BackgroundColor3 = COL.slider
    track.BorderSizePixel  = 0
    track.Parent           = row

    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.Size              = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3  = COL.sliderFg
    fill.BorderSizePixel   = 0
    fill.Parent            = track

    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    -- Invisible hit region (taller on mobile for easy touch)
    local hitH = IS_MOBILE and 32 or 16
    local hit = Instance.new("TextButton")
    hit.Size               = UDim2.new(1, 0, 0, hitH)
    hit.Position           = UDim2.new(0, 0, 0, trackY - (hitH - trackH)/2)
    hit.BackgroundTransparency = 1
    hit.Text               = ""
    hit.Parent             = row

    local value = default
    local function setValue(v)
        v     = math.clamp(math.round(v / step) * step, minV, maxV)
        value = v
        local pct = (v - minV) / (maxV - minV)
        fill.Size    = UDim2.new(pct, 0, 1, 0)
        valLbl.Text  = tostring(v)
        if onChange then onChange(v) end
    end
    setValue(default)

    -- Shared position → value calc
    local function posToValue(screenX)
        local abs = track.AbsolutePosition
        local sz  = track.AbsoluteSize
        local relX = math.clamp(screenX - abs.X, 0, sz.X)
        return minV + (relX / sz.X) * (maxV - minV)
    end

    -- Mouse drag
    local mouseDown = false
    hit.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            mouseDown = true
            setValue(posToValue(inp.Position.X))
        end
    end)
    hit.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            mouseDown = false
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if mouseDown and inp.UserInputType == Enum.UserInputType.MouseMovement then
            setValue(posToValue(inp.Position.X))
        end
    end)

    -- Touch drag
    hit.TouchStarted:Connect(function(touch, _)
        setValue(posToValue(touch.Position.X))
    end)
    hit.TouchMoved:Connect(function(touch, _)
        setValue(posToValue(touch.Position.X))
    end)

    return { getValue = function() return value end, setValue = setValue }
end

-- ─────────────────────────────────────────────────────────────
-- [9]  BUILD UI CONTENT
-- ─────────────────────────────────────────────────────────────

-- ── VOID SPAM ─────────────────────────────────────────────────
makeHeader("  VOID SPAM", 1)
makeSep(2)

local voidToggle = makeToggle("Enable Void Spam", CFG.VoidEnabled, 3, function(v)
    CFG.VoidEnabled = v
end)

makeDropdown("Target Mode", {"Nearest","All"}, CFG.VoidTargetMode, 4, function(v)
    CFG.VoidTargetMode = v
end)

makeSlider("Void Depth (Y)", -2000, -50, 50, CFG.VoidY, 5, function(v)
    CFG.VoidY = v
end)

makeSlider("Interval ×100 (s)", 1, 100, 1,
    math.round(CFG.VoidInterval * 100), 6, function(v)
    CFG.VoidInterval = v / 100
end)

makeSep(7)

-- ── RAGEBOT ───────────────────────────────────────────────────
makeHeader("  RAGEBOT", 8)
makeSep(9)

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

makeDropdown("Bone Target",
    {"Head","Torso","HumanoidRootPart"},
    CFG.RagebotBone, 15, function(v)
    CFG.RagebotBone = v
end)

makeSlider("FOV (°)", 10, 180, 5, CFG.RagebotFOV, 16, function(v)
    CFG.RagebotFOV = v
end)

makeToggle("Show FOV Circle", CFG.ShowFOVCircle, 17, function(v)
    CFG.ShowFOVCircle = v
end)

makeSep(18)

-- ── Status row ────────────────────────────────────────────────
local statusRow = Instance.new("Frame")
statusRow.Size               = UDim2.new(1, 0, 0, 30)
statusRow.BackgroundTransparency = 1
statusRow.LayoutOrder        = 19
statusRow.Parent             = ContentFrame

local statusLbl = Instance.new("TextLabel")
statusLbl.Size               = UDim2.new(1, -14, 1, 0)
statusLbl.Position           = UDim2.new(0, 14, 0, 0)
statusLbl.BackgroundTransparency = 1
statusLbl.Text               = "Status: idle"
statusLbl.Font               = Enum.Font.Gotham
statusLbl.TextSize           = FONT_SIZE - 1
statusLbl.TextColor3         = COL.textDim
statusLbl.TextXAlignment     = Enum.TextXAlignment.Left
statusLbl.Parent             = statusRow

RunService.Heartbeat:Connect(function()
    local parts = {}
    if CFG.VoidEnabled then table.insert(parts, "🕳 VOID") end
    if CFG.RagebotEnabled then
        local t = getNearestTarget()
        if t then
            local plr = Players:GetPlayerFromCharacter(t.Entity.Model)
            table.insert(parts, "🎯 " .. (plr and plr.Name or "NPC"))
        else
            table.insert(parts, "🎯 NO TARGET")
        end
    end
    statusLbl.Text = #parts > 0 and table.concat(parts,"  ") or "Status: idle"
end)

-- Bottom padding
local padBot = Instance.new("Frame")
padBot.Size               = UDim2.new(1, 0, 0, 8)
padBot.BackgroundTransparency = 1
padBot.LayoutOrder        = 99
padBot.Parent             = ContentFrame

-- ─────────────────────────────────────────────────────────────
-- [10]  MOBILE QUICK-ACTION BUTTONS
--       Floating on-screen VOID and RAGE tap buttons so you
--       don't need a keyboard.  Hidden on PC where hotkeys work.
-- ─────────────────────────────────────────────────────────────
if IS_MOBILE then
    local function makeQuickBtn(text, col, posX, onTap)
        local btn = Instance.new("TextButton")
        btn.Size              = UDim2.new(0, 72, 0, 72)
        btn.Position          = UDim2.new(posX, 0, 1, -100)
        btn.AnchorPoint       = Vector2.new(0, 1)
        btn.BackgroundColor3  = col
        btn.BorderSizePixel   = 0
        btn.Text              = text
        btn.Font              = Enum.Font.GothamBold
        btn.TextSize          = 11
        btn.TextColor3        = Color3.fromRGB(255,255,255)
        btn.TextWrapped       = true
        btn.ZIndex            = 10
        btn.Parent            = ScreenGui

        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 36)

        local stroke = Instance.new("UIStroke")
        stroke.Color       = Color3.fromRGB(255,255,255)
        stroke.Thickness   = 1.5
        stroke.Transparency = 0.6
        stroke.Parent      = btn

        btn.Activated:Connect(onTap)
        return btn
    end

    local voidBtn = makeQuickBtn("🕳\nVOID\nOFF", COL.btnVoid, 0.04, function()
        CFG.VoidEnabled = not CFG.VoidEnabled
        voidToggle.setState(CFG.VoidEnabled)
        voidBtn.Text = CFG.VoidEnabled and "🕳\nVOID\nON" or "🕳\nVOID\nOFF"
    end)

    local rageBtn = makeQuickBtn("🎯\nRAGE\nOFF", COL.btnRage, 0.19, function()
        CFG.RagebotEnabled = not CFG.RagebotEnabled
        rageToggle.setState(CFG.RagebotEnabled)
        rageBtn.Text = CFG.RagebotEnabled and "🎯\nRAGE\nON" or "🎯\nRAGE\nOFF"
    end)

    -- keep button text in sync with panel toggles
    RunService.Heartbeat:Connect(function()
        voidBtn.Text = CFG.VoidEnabled and "🕳\nVOID\nON" or "🕳\nVOID\nOFF"
        rageBtn.Text = CFG.RagebotEnabled and "🎯\nRAGE\nON" or "🎯\nRAGE\nOFF"
    end)
end

-- ─────────────────────────────────────────────────────────────
-- [11]  PC HOTKEYS  (skipped on mobile to save resources)
-- ─────────────────────────────────────────────────────────────
if not IS_MOBILE then
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
end

-- ─────────────────────────────────────────────────────────────
-- [12]  FOV CIRCLE
-- ─────────────────────────────────────────────────────────────
local fovCircle = Instance.new("Frame")
fovCircle.BackgroundTransparency = 1
fovCircle.BorderSizePixel        = 0
fovCircle.AnchorPoint            = Vector2.new(0.5, 0.5)
fovCircle.Size                   = UDim2.new(0, 200, 0, 200)
fovCircle.Position               = UDim2.new(0.5, 0, 0.5, 0)
fovCircle.ZIndex                 = 5
fovCircle.Parent                 = ScreenGui

local fovStroke = Instance.new("UIStroke")
fovStroke.Color       = COL.accent
fovStroke.Thickness   = 1.5
fovStroke.Transparency = 0.25
fovStroke.Parent      = fovCircle

Instance.new("UICorner", fovCircle).CornerRadius = UDim.new(1, 0)

bindRenderStep("FOVCircleDraw", Enum.RenderPriority.Last.Value, function()
    fovCircle.Visible = CFG.ShowFOVCircle
    if not CFG.ShowFOVCircle then return end
    local vp     = Camera.ViewportSize
    local spread = math.tan(math.rad(CFG.RagebotFOV / 2))
    local fl     = vp.Y / (2 * math.tan(math.rad(Camera.FieldOfView / 2)))
    local px     = math.clamp(spread * fl, 10, math.min(vp.X, vp.Y) / 2)
    fovCircle.Size = UDim2.new(0, px*2, 0, px*2)
end)

-- ─────────────────────────────────────────────────────────────
print(("[CheatUI v2.0] Loaded | Mobile=%s | FighterCtrl=%s | MechCtrl=%s"):format(
    tostring(IS_MOBILE),
    tostring(FighterController ~= nil),
    tostring(MechController ~= nil)
))

--[[
  ═══════════════════════════════════════════════════
  ENHANCEMENTS UPON REQUEST
  ═══════════════════════════════════════════════════
  • Prediction lead   — lead moving targets using
    AssemblyLinearVelocity + configurable travel time
  • ESP / Chams       — per-fighter Highlight overlay
  • Void trajectory   — directional horizontal push
    to send targets off specific map edges
  • Friend whitelist  — per-name exclusion table
  • Gyroscope aim     — mobile gyro → camera delta
    for natural phone-tilt aiming assist
  • Config save/load  — persist CFG to executor
    writefile / readfile between sessions
  ═══════════════════════════════════════════════════
]]
