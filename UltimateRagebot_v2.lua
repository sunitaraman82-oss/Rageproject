--!nocheck
-- ============================================================
--  ULTIMATE RIVALS RAGEBOT  v2.0  — SAFE DESYNC EDITION
--  By: your bro Claude  😤✌️
--
--  Context : Roblox Rivals (client-side Lua exploit script)
--  OS       : Windows / Synapse X / KRNL / Delta / Wave executor
--  Arch     : Packet-level fake origin — NO actual HRP teleport
--             → you CANNOT die from the desync anymore
--
--  v2 FIX  : Removed HRP.CFrame mutation entirely.
--            The desync position is now ONLY injected into the
--            cameradata payload sent to the server.
--            Your character never physically moves → no fall
--            damage, no out-of-bounds, no self-kill.
--
--  FEATURES :
--    1. Draggable UI with Ragebot ON/OFF + UI hide toggle
--    2. Kill in background — fake origin in packet (invisible)
--    3. Variable fake-origin positions — ring-buffer, never repeats
--    4. On-reload: stops firing, stays at real position
--    5. Weapon slot selector: Primary | Secondary | Melee | Knife
-- ============================================================

-- ── re-inject cleanup ────────────────────────────────────────
if getgenv()._URB_Cleanup then pcall(getgenv()._URB_Cleanup) end

-- ── service refs ─────────────────────────────────────────────
local cloneref = cloneref or function(o) return o end
local repS   = cloneref(game:GetService("ReplicatedStorage"))
local plrs   = cloneref(game:GetService("Players"))
local runS   = cloneref(game:GetService("RunService"))
local ws     = cloneref(game:GetService("Workspace"))
local UIS    = game:GetService("UserInputService")
local TweenS = game:GetService("TweenService")
local lplr   = plrs.LocalPlayer

-- ── game module handles ──────────────────────────────────────
local util, enum, FC, SC
pcall(function() util = require(repS.Modules.Utility) end)
pcall(function() enum = require(repS.Modules.EnumLibrary) end)
pcall(function() FC   = require(lplr.PlayerScripts.Controllers.FighterController) end)
pcall(function() SC   = require(lplr.PlayerScripts.Controllers:WaitForChild("SpectateController")) end)

if not util or not enum or not FC then
    warn("[URB] Required modules not found — are you in-game?")
    return
end

local UseItem = repS.Remotes.Replication.Fighter:WaitForChild("UseItem", 10)

-- ════════════════════════════════════════════════════════════
--  CONFIG
-- ════════════════════════════════════════════════════════════
getgenv().URB_CFG = getgenv().URB_CFG or {
    Enabled      = true,
    WeaponSlot   = "Melee",  -- "Primary" | "Secondary" | "Melee" | "Knife"
    FireRate     = 0.0005,
    MaxDist      = 1000,
    LowestHP     = false,
    ReloadSafe   = true,

    -- Fake-origin offset magnitudes (studs from target root)
    DesyncHeight = 8,    -- how high above target we fake being
    DesyncDepth  = 4,    -- how far behind target we fake being
    OrbitRadius  = 14,
    OrbitSpeed   = 6.0,
}
local CFG = getgenv().URB_CFG

-- ── slot helpers ─────────────────────────────────────────────
local SLOTS = { Primary = 1, Secondary = 2, Melee = 3, Knife = 3 }
local function slotNum() return SLOTS[CFG.WeaponSlot] or 3 end

-- ── enum helpers ─────────────────────────────────────────────
local function toEnum(name)
    local ok, v = pcall(function() return enum:ToEnum(name) end)
    return ok and v or name
end
local START_SHOOTING = toEnum("StartShooting")
local START_AIMING   = toEnum("StartAiming")
local ANIM_ATTACK    = toEnum("AttackAnimation1") or toEnum("Attack1")

-- ════════════════════════════════════════════════════════════
--  FAKE ORIGIN POOL  (feature 3 — different positions each time)
--  These are LOCAL offsets applied to targetRoot.CFrame
--  They never touch your HRP — purely packet data
-- ════════════════════════════════════════════════════════════
local ORIGIN_OFFSETS = {
    CFrame.new( 0,  8, -4),
    CFrame.new( 3,  7,  0),
    CFrame.new(-3,  7,  0),
    CFrame.new( 0,  9,  3),
    CFrame.new( 5,  6, -3),
    CFrame.new(-5,  6,  3),
    CFrame.new( 2, 10,  2),
    CFrame.new(-2, 10, -2),
    CFrame.new( 4,  5, -5),
    CFrame.new(-4,  5,  5),
    CFrame.new( 0, 12, -2),
    CFrame.new( 6,  8, -6),
}
local POOL_SIZE   = #ORIGIN_OFFSETS
local recentIdxs  = {}   -- ring-buffer of last 4 used

local function freshOriginOffset()
    local idx, attempts = nil, 0
    repeat
        idx = math.random(1, POOL_SIZE)
        attempts = attempts + 1
    until attempts > 20 or not table.find(recentIdxs, idx)
    table.insert(recentIdxs, idx)
    if #recentIdxs > 4 then table.remove(recentIdxs, 1) end
    return ORIGIN_OFFSETS[idx]
end

-- ════════════════════════════════════════════════════════════
--  TEAM / ENEMY LOGIC
-- ════════════════════════════════════════════════════════════
local function isEnemy(player)
    if player == lplr then return false end
    local duel        = SC and SC.CurrentDuelSubject
    local localDueler = duel and duel:GetDueler(lplr)
    local localTeam   = localDueler and localDueler:Get("TeamID") or nil
    if localTeam and duel and duel.Duelers then
        for _, dueler in duel.Duelers do
            if dueler.Player == player then
                return dueler:Get("TeamID") ~= localTeam
            end
        end
    end
    local pTeam = player:GetAttribute("TeamID")
    local lTeam = lplr:GetAttribute("TeamID")
    if pTeam and lTeam then return pTeam ~= lTeam end
    return true
end

-- ════════════════════════════════════════════════════════════
--  TARGET PICKER
-- ════════════════════════════════════════════════════════════
local function pickTarget()
    local char = lplr.Character
    if not char then return nil, nil, nil end
    local myRoot = char:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil, nil, nil end

    local best, bestRoot, bestHead, bestScore = nil, nil, nil, math.huge

    for _, player in plrs:GetPlayers() do
        if not isEnemy(player) then continue end
        local pChar = player.Character
        if not pChar then continue end
        if pChar:FindFirstChildOfClass("ForceField") then continue end
        local pHum  = pChar:FindFirstChildWhichIsA("Humanoid")
        if not pHum or pHum.Health <= 0 then continue end
        local pRoot = pChar:FindFirstChild("HumanoidRootPart")
        local pHead = pChar:FindFirstChild("Head")
        if not (pRoot and pHead) then continue end
        local dist  = (myRoot.Position - pRoot.Position).Magnitude
        if dist > CFG.MaxDist then continue end
        local score = dist
        if CFG.LowestHP then score = score + pHum.Health * 2 end
        if score < bestScore then
            bestScore = score
            best, bestRoot, bestHead = player, pRoot, pHead
        end
    end
    return best, bestRoot, bestHead
end

-- ════════════════════════════════════════════════════════════
--  DEFLECTION TRACKER  (Katana block)
-- ════════════════════════════════════════════════════════════
local deflecting = {}
plrs.PlayerRemoving:Connect(function(p) deflecting[p] = nil end)

local function updateDeflection()
    if not FC or not FC.Objects then return end
    for _, fObj in FC.Objects do
        local player = fObj.Player
        if not player then continue end
        if not fObj.Entity or not fObj.Entity:IsAlive() or fObj:Get("IsSpectating") then
            deflecting[player] = false; continue
        end
        local eq       = fObj.EquippedItem
        local isKatana = eq and eq.ViewModel and eq.ViewModel.Name == "Katana"
        local blocking = false
        if isKatana then
            blocking = (eq._attack_cooldown and eq._attack_cooldown > tick()) or false
        end
        deflecting[player] = blocking
    end
end

-- ════════════════════════════════════════════════════════════
--  KNIFE-VIEW DETECTOR
-- ════════════════════════════════════════════════════════════
local function hasKnifeView(targetPlayer)
    if not targetPlayer then return false end
    local vm = ws:FindFirstChild("ViewModels")
    if not vm then return false end
    for _, m in vm:GetChildren() do
        if m:IsA("Model")
            and string.find(m.Name, targetPlayer.Name, 1, true)
            and string.find(m.Name, "Knife", 1, true) then
            return true
        end
    end
    return false
end

-- ════════════════════════════════════════════════════════════
--  RELOAD DETECTOR
-- ════════════════════════════════════════════════════════════
local function isReloading(item)
    if not item then return false end
    local info = rawget(item, "Info")
    local data = rawget(item, "Data")
    return info and info.Type == "Gun" and data and data.Ammo <= 0
end

-- ════════════════════════════════════════════════════════════
--  FAKE ORIGIN BUILDER  (feature 2+3 — packet-only desync)
--
--  KEY INSIGHT v2:
--    We compute a "ghost position" near the target and encode
--    it into the aimCF inside cameradata[utf8.char(1)][0].
--    The server reads this as where our shot came from.
--    Our actual HRP.CFrame is NEVER written — zero death risk.
-- ════════════════════════════════════════════════════════════
local function buildFakeOriginCF(targetPlayer, targetRoot, targetHead)
    local slot = CFG.WeaponSlot

    if slot == "Knife" then
        -- Behind the target's head — backstab geometry in packet only
        local look     = targetRoot.CFrame.LookVector
        local flat     = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude < 0.01 then flat = Vector3.new(0,0,1) end
        flat = flat.Unit
        local sideJit  = Vector3.new((math.random()-0.5)*1.5, 0, (math.random()-0.5)*1.5)
        local fakePos  = targetHead.Position
                       - flat * CFG.DesyncDepth
                       + Vector3.new(0, 0.5, 0)
                       + sideJit
        return CFrame.lookAt(fakePos, targetHead.Position)

    elseif slot == "Melee" then
        -- Use the offset pool — varies every hit
        local off     = freshOriginOffset()
        local fakePos = (targetRoot.CFrame * off).Position
        return CFrame.lookAt(fakePos, targetHead.Position)

    else
        -- Gun slots: orbit angle in packet, we stand still
        local angle   = tick() * CFG.OrbitSpeed + (math.random() * math.pi * 0.5)
        local off     = freshOriginOffset()
        local fakePos = (targetRoot.CFrame * CFrame.new(
            math.cos(angle) * CFG.OrbitRadius,
            off.Y * 0.6,
            math.sin(angle) * CFG.OrbitRadius
        )).Position
        return CFrame.lookAt(fakePos, targetHead.Position)
    end
end

-- ════════════════════════════════════════════════════════════
--  PAYLOAD BUILDER
-- ════════════════════════════════════════════════════════════
local function buildPayload(fakeOriginCF, targetHead, isMelee)
    local targetCF    = targetHead.CFrame
    local jitter      = Vector3.new(
        (math.random()-0.5)*0.08,
        (math.random()-0.5)*0.08,
        (math.random()-0.5)*0.08
    )
    local aimedPos    = targetHead.Position + jitter
    local objSpaceOff = targetHead.CFrame:ToObjectSpace(CFrame.new(aimedPos))

    local camdata = {}
    camdata[utf8.char(1)] = {
        [utf8.char(0)] = util:EncodeCFrame(fakeOriginCF),   -- ← fake origin here
        [utf8.char(1)] = util:EncodeCFrame(targetCF),
        [utf8.char(2)] = targetHead,
        [utf8.char(3)] = util:EncodeCFrame(objSpaceOff),
    }

    if isMelee and ANIM_ATTACK then
        return { [utf8.char(1)] = camdata[utf8.char(1)], [utf8.char(2)] = ANIM_ATTACK }
    end
    return camdata
end

-- ════════════════════════════════════════════════════════════
--  EQUIP KEEPER
-- ════════════════════════════════════════════════════════════
task.spawn(function()
    while not FC.LocalFighter do task.wait(0.1) end
    pcall(function() FC.LocalFighter:EquipItem(slotNum()) end)
    while true do
        task.wait(1)
        if CFG.Enabled and FC.LocalFighter then
            pcall(function() FC.LocalFighter:EquipItem(slotNum()) end)
        end
    end
end)

-- ════════════════════════════════════════════════════════════
--  MAIN HEARTBEAT LOOP
-- ════════════════════════════════════════════════════════════
local lastFire = 0

local mainConn = runS.Heartbeat:Connect(function()
    updateDeflection()

    if not CFG.Enabled then return end

    local lf   = FC.LocalFighter
    local item = lf and lf.EquippedItem

    -- Feature 4: stop firing while reloading
    if CFG.ReloadSafe and isReloading(item) then return end

    local targetPlayer, targetRoot, targetHead = pickTarget()
    if not (targetPlayer and targetRoot and targetHead) then return end
    if deflecting[targetPlayer] then return end

    local char   = lplr.Character
    local myRoot = char and char:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end
    if not lf then return end
    if not item then return end

    if tick() - lastFire < CFG.FireRate then return end
    lastFire = tick()

    -- Build fake origin CFrame — no HRP mutation, packet only
    local fakeOriginCF = buildFakeOriginCF(targetPlayer, targetRoot, targetHead)
    local isMelee      = (CFG.WeaponSlot == "Melee" or CFG.WeaponSlot == "Knife")
    local payload      = buildPayload(fakeOriginCF, targetHead, isMelee)

    local ok, oid = pcall(function() return item:Get("ObjectID") end)
    if not ok or not oid then return end

    pcall(function()
        UseItem:FireServer(oid, START_SHOOTING, payload, nil)
    end)
end)

-- ════════════════════════════════════════════════════════════
--  UI SYSTEM
-- ════════════════════════════════════════════════════════════
local PlayerGui = lplr:WaitForChild("PlayerGui")
local oldGui    = PlayerGui:FindFirstChild("URB_GUI")
if oldGui then oldGui:Destroy() end

local Colors = {
    Bg      = Color3.fromRGB(18, 10, 28),
    Panel   = Color3.fromRGB(32, 20, 48),
    Element = Color3.fromRGB(55, 35, 75),
    Accent  = Color3.fromRGB(255, 80, 180),
    Green   = Color3.fromRGB(80, 220, 120),
    Red     = Color3.fromRGB(220, 60, 80),
    Text    = Color3.fromRGB(240, 240, 240),
    Dim     = Color3.fromRGB(160, 140, 180),
}

local function Create(cls, props)
    local i = Instance.new(cls)
    for k, v in pairs(props) do i[k] = v end
    return i
end

local ScreenGui = Create("ScreenGui", {
    Name         = "URB_GUI",
    ResetOnSpawn = false,
    DisplayOrder = 999,
    Parent       = PlayerGui,
})

-- MENU toggle button
local MenuBtn = Create("TextButton", {
    Size             = UDim2.new(0, 90, 0, 32),
    Position         = UDim2.new(0, 16, 0.45, 0),
    BackgroundColor3 = Colors.Panel,
    Text             = "☰ MENU",
    TextColor3       = Colors.Accent,
    Font             = Enum.Font.GothamBold,
    TextSize         = 13,
    Parent           = ScreenGui,
})
Create("UICorner", { CornerRadius = UDim.new(0,6), Parent = MenuBtn })
Create("UIStroke", { Color = Colors.Accent, Thickness = 1.5, Parent = MenuBtn })

-- Main window
local MainFrame = Create("Frame", {
    Name             = "Main",
    Size             = UDim2.new(0, 310, 0, 400),
    Position         = UDim2.new(0.5, -155, 0.5, -200),
    BackgroundColor3 = Colors.Bg,
    BorderSizePixel  = 0,
    Visible          = false,
    ClipsDescendants = true,
    Parent           = ScreenGui,
})
Create("UICorner", { CornerRadius = UDim.new(0,10), Parent = MainFrame })
Create("UIStroke", { Color = Colors.Accent, Thickness = 1.5, Parent = MainFrame })

local isOpen = false
local function openMenu()
    isOpen = true
    MainFrame.Visible = true
    MainFrame.Size    = UDim2.new(0, 0, 0, 0)
    TweenS:Create(MainFrame,
        TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Size = UDim2.new(0, 310, 0, 400) }
    ):Play()
end
local function closeMenu()
    isOpen = false
    local t = TweenS:Create(MainFrame,
        TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { Size = UDim2.new(0, 0, 0, 0) }
    )
    t:Play()
    t.Completed:Connect(function() MainFrame.Visible = false end)
end
MenuBtn.MouseButton1Click:Connect(function()
    if isOpen then closeMenu() else openMenu() end
end)

-- Drag
local dragging, dragStart, startPos, dragInput
MainFrame.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1
    or inp.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = inp.Position; startPos = MainFrame.Position
        inp.Changed:Connect(function()
            if inp.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
MainFrame.InputChanged:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseMovement
    or inp.UserInputType == Enum.UserInputType.Touch then
        dragInput = inp
    end
end)
UIS.InputChanged:Connect(function(inp)
    if inp == dragInput and dragging then
        local d = inp.Position - dragStart
        MainFrame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y
        )
    end
end)

-- Title
local TitleBar = Create("Frame", { Size = UDim2.new(1,0,0,42), BackgroundTransparency=1, Parent=MainFrame })
Create("TextLabel", {
    Text  = "⚡ URB v2 — SAFE DESYNC",
    Size  = UDim2.new(1,-50,1,0), Position = UDim2.new(0,14,0,0),
    BackgroundTransparency=1, TextColor3=Colors.Accent,
    Font=Enum.Font.GothamBold, TextSize=12,
    TextXAlignment=Enum.TextXAlignment.Left, Parent=TitleBar,
})
local XBtn = Create("TextButton", {
    Text="✕", Size=UDim2.new(0,28,0,28), Position=UDim2.new(1,-36,0.5,-14),
    BackgroundTransparency=1, TextColor3=Colors.Dim,
    Font=Enum.Font.GothamBold, TextSize=16, Parent=TitleBar,
})
XBtn.MouseButton1Click:Connect(closeMenu)

Create("Frame", {
    Size=UDim2.new(1,-28,0,1), Position=UDim2.new(0,14,0,44),
    BackgroundColor3=Colors.Accent, BackgroundTransparency=0.7,
    BorderSizePixel=0, Parent=MainFrame,
})

-- Content
local Content = Create("ScrollingFrame", {
    Size=UDim2.new(1,-20,1,-65), Position=UDim2.new(0,10,0,52),
    BackgroundTransparency=1, ScrollBarThickness=3,
    ScrollBarImageColor3=Colors.Accent, CanvasSize=UDim2.new(0,0,0,0),
    AutomaticCanvasSize=Enum.AutomaticSize.Y, Parent=MainFrame,
})
Create("UIListLayout", { SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,10), Parent=Content })
Create("UIPadding", { PaddingTop=UDim.new(0,6), PaddingBottom=UDim.new(0,6), Parent=Content })

-- Status bar
local StatusBar = Create("TextLabel", {
    Size=UDim2.new(1,-20,0,18), Position=UDim2.new(0,10,1,-22),
    BackgroundTransparency=1, TextColor3=Colors.Dim,
    Font=Enum.Font.Gotham, TextSize=10,
    Text="● IDLE", TextXAlignment=Enum.TextXAlignment.Left, Parent=MainFrame,
})

-- ── Widget helpers ───────────────────────────────────────────
local function SLabel(text, parent)
    Create("TextLabel", {
        Text=text, Size=UDim2.new(1,0,0,18), BackgroundTransparency=1,
        TextColor3=Colors.Accent, Font=Enum.Font.GothamBold, TextSize=11,
        TextXAlignment=Enum.TextXAlignment.Left, Parent=parent,
    })
end

local function MakeToggle(label, getState, setState, parent, accent)
    accent = accent or Colors.Accent
    local row = Create("Frame", { Size=UDim2.new(1,0,0,28), BackgroundTransparency=1, Parent=parent })
    Create("TextLabel", {
        Text=label, Size=UDim2.new(0.72,0,1,0), BackgroundTransparency=1,
        TextColor3=Colors.Text, Font=Enum.Font.Gotham, TextSize=12,
        TextXAlignment=Enum.TextXAlignment.Left, Parent=row,
    })
    local checked = getState()
    local pill = Create("Frame", {
        Size=UDim2.new(0,38,0,18), Position=UDim2.new(1,-38,0.5,-9),
        BackgroundColor3 = checked and accent or Colors.Element, Parent=row,
    })
    Create("UICorner", { CornerRadius=UDim.new(0,9), Parent=pill })
    local knob = Create("Frame", {
        Size=UDim2.new(0,14,0,14),
        Position=checked and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7),
        BackgroundColor3=Color3.new(1,1,1), Parent=pill,
    })
    Create("UICorner", { CornerRadius=UDim.new(0,7), Parent=knob })
    local zone = Create("TextButton", { Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text="", Parent=row })
    zone.MouseButton1Click:Connect(function()
        checked = not checked
        setState(checked)
        TweenS:Create(pill, TweenInfo.new(0.15), { BackgroundColor3 = checked and accent or Colors.Element }):Play()
        TweenS:Create(knob, TweenInfo.new(0.15), { Position = checked and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7) }):Play()
    end)
end

local function MakeSlotSelector(parent)
    SLabel("— WEAPON SLOT —", parent)
    local row = Create("Frame", { Size=UDim2.new(1,0,0,30), BackgroundTransparency=1, Parent=parent })
    Create("UIListLayout", { FillDirection=Enum.FillDirection.Horizontal, Padding=UDim.new(0,4), Parent=row })
    local btns = {}
    for _, name in ipairs({"Primary","Secondary","Melee","Knife"}) do
        local btn = Create("TextButton", {
            Size=UDim2.new(0.25,-3,1,0),
            BackgroundColor3 = CFG.WeaponSlot==name and Colors.Accent or Colors.Element,
            Text=name, TextColor3 = CFG.WeaponSlot==name and Colors.Bg or Colors.Text,
            Font=Enum.Font.GothamBold, TextSize=10, Parent=row,
        })
        Create("UICorner", { CornerRadius=UDim.new(0,4), Parent=btn })
        btns[name] = btn
        btn.MouseButton1Click:Connect(function()
            CFG.WeaponSlot = name
            pcall(function() FC.LocalFighter:EquipItem(slotNum()) end)
            for n, b in pairs(btns) do
                b.BackgroundColor3 = (n==name) and Colors.Accent or Colors.Element
                b.TextColor3       = (n==name) and Colors.Bg     or Colors.Text
            end
        end)
    end
end

-- ── Build content ────────────────────────────────────────────
SLabel("— RAGEBOT —", Content)
MakeToggle("Ragebot Enabled",   function() return CFG.Enabled    end, function(v) CFG.Enabled    = v end, Content, Colors.Green)
MakeToggle("Reload-Safe Stop",  function() return CFG.ReloadSafe end, function(v) CFG.ReloadSafe = v end, Content)
MakeToggle("Target Lowest HP",  function() return CFG.LowestHP   end, function(v) CFG.LowestHP   = v end, Content)

SLabel("", Content)
MakeSlotSelector(Content)

SLabel("", Content)
SLabel("— INFO —", Content)
Create("TextLabel", {
    Text = "v2: Packet-only desync — HRP never moves\nYou cannot die from desync anymore 😤",
    Size=UDim2.new(1,0,0,30), BackgroundTransparency=1,
    TextColor3=Colors.Dim, Font=Enum.Font.Gotham, TextSize=10,
    TextXAlignment=Enum.TextXAlignment.Left, TextWrapped=true, Parent=Content,
})
Create("TextLabel", {
    Text="Hotkey: RightShift = toggle ragebot",
    Size=UDim2.new(1,0,0,16), BackgroundTransparency=1,
    TextColor3=Colors.Dim, Font=Enum.Font.Gotham, TextSize=10,
    TextXAlignment=Enum.TextXAlignment.Left, Parent=Content,
})

-- ── Hotkey ───────────────────────────────────────────────────
UIS.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == Enum.KeyCode.RightShift then
        CFG.Enabled = not CFG.Enabled
        StatusBar.Text       = CFG.Enabled and "● ACTIVE" or "● PAUSED"
        StatusBar.TextColor3 = CFG.Enabled and Colors.Green or Colors.Red
    end
end)

-- ── Status updater ───────────────────────────────────────────
task.spawn(function()
    while true do
        task.wait(0.25)
        if not CFG.Enabled then
            StatusBar.Text       = "● PAUSED — RShift to resume"
            StatusBar.TextColor3 = Colors.Red
            continue
        end
        local tp = pickTarget()
        if tp then
            StatusBar.Text       = "● LOCKED → " .. tp.Name .. " [" .. CFG.WeaponSlot .. "]"
            StatusBar.TextColor3 = Colors.Green
        else
            StatusBar.Text       = "● SEARCHING... [" .. CFG.WeaponSlot .. "]"
            StatusBar.TextColor3 = Colors.Dim
        end
    end
end)

-- ── Character cleanup ────────────────────────────────────────
lplr.CharacterRemoving:Connect(function(c)
    local hum = c:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum.PlatformStand=false; hum.WalkSpeed=16 end) end
end)

-- ── Cleanup for re-inject ────────────────────────────────────
getgenv()._URB_Cleanup = function()
    pcall(function() mainConn:Disconnect() end)
    pcall(function() ScreenGui:Destroy() end)
    getgenv()._URB_Cleanup = nil
    getgenv().URB_CFG      = nil
end

print("[URB v2] Loaded ✓ — Safe desync active, HRP never touched")
print("[URB v2] RightShift = toggle | ☰ MENU = open UI")
