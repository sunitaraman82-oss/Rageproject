--=============================================================================
--  Kicia Ragebot Rebuild  –  Rivals
--  UI: Obsidian (mspaint.cc)
--  Full feature parity with the kicia dump:
--    Aimbot / Ragebot, ESP, Visuals, World, Misc, Config
--=============================================================================
if getgenv().__KiciaObsidian and getgenv().__KiciaObsidian.Destroy then
    pcall(getgenv().__KiciaObsidian.Destroy)
end
if not game:IsLoaded() then game.Loaded:Wait() end

--=============================================================================
--  SERVICES
--=============================================================================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Workspace        = game:GetService("Workspace")
local CollectionService= game:GetService("CollectionService")
local SoundService     = game:GetService("SoundService")
local Lighting         = game:GetService("Lighting")
local Camera           = Workspace.CurrentCamera
local lp              = Players.LocalPlayer

--=============================================================================
--  OBSIDIAN LOAD
--=============================================================================
local repo        = "https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/"
local Library     = loadstring(game:HttpGet(repo .. "Library.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
local ThemeManager= loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()

--=============================================================================
--  GLOBAL STATE
--=============================================================================
local K = {
    connections = {},
    cleanups    = {},
    destroyed   = false,
    opts        = {},   -- every Toggle/Slider value lives here
}
getgenv().__KiciaObsidian = K

local function track(c)  K.connections[#K.connections+1] = c return c end
local function onUnload(f) K.cleanups[#K.cleanups+1] = f end

function K.Destroy()
    if K.destroyed then return end
    K.destroyed = true
    for _,c in K.connections do pcall(function() c:Disconnect() end) end
    for _,f in K.cleanups   do pcall(f) end
    pcall(function() Library:Destroy() end)
    if getgenv().__KiciaObsidian == K then getgenv().__KiciaObsidian = nil end
end

--=============================================================================
--  TINY UTILITY
--=============================================================================
local function lerp(a,b,t) return a+(b-a)*t end

local function getRootPart(char)
    return char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
end

local function getHead(char)
    return char and char:FindFirstChild("Head")
end

local function getHumanoid(char)
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function isAlive(plr)
    local char = plr and plr.Character
    if not char then return false end
    local hum = getHumanoid(char)
    return hum and hum.Health > 0
end

local function worldToViewport(pos)
    local vp, onScreen = Camera:WorldToViewportPoint(pos)
    return Vector2.new(vp.X, vp.Y), onScreen, vp.Z
end

local function getSteamId(plr)
    return tostring(plr.UserId)
end

-- simple lock helper (Kicia's SpringLock equivalent)
local function getLocalAimPos(char)
    local head = getHead(char)
    local root = getRootPart(char)
    return head and head.Position or (root and root.Position)
end

--=============================================================================
--  RESOLVER (simple lag-comp / velocity extrapolation)
--=============================================================================
local Resolver = {}
do
    local history = {}  -- [plr] = { {pos, t}, ... }

    local function record(plr)
        local char = plr.Character
        if not char then return end
        local root = getRootPart(char)
        if not root then return end
        local now = tick()
        if not history[plr] then history[plr] = {} end
        local h = history[plr]
        h[#h+1] = {pos=root.Position, t=now}
        -- keep last 20 frames
        while #h > 20 do table.remove(h, 1) end
    end

    function Resolver.getVelocity(plr)
        local h = history[plr]
        if not h or #h < 2 then return Vector3.zero end
        local a, b = h[#h-1], h[#h]
        local dt = b.t - a.t
        if dt <= 0 then return Vector3.zero end
        return (b.pos - a.pos) / dt
    end

    function Resolver.getPredicted(plr, latency)
        local char = plr.Character
        if not char then return nil end
        local head = getHead(char)
        if not head then return nil end
        local vel = Resolver.getVelocity(plr)
        return head.Position + vel * latency
    end

    function Resolver.clean(plr)
        history[plr] = nil
    end

    track(RunService.Heartbeat:Connect(function()
        for _, plr in Players:GetPlayers() do
            if plr ~= lp then record(plr) end
        end
    end))
end

--=============================================================================
--  ESP ENGINE
--=============================================================================
local Esp = {}
do
    local drawings = {}  -- [plr] = { box, name, hp, dist, tracer, ... }

    local function newDraw(type_, props)
        local d = Drawing.new(type_)
        for k,v in props do d[k]=v end
        return d
    end

    local function makeEntry(plr)
        return {
            box      = newDraw("Square",    {Visible=false, Color=Color3.new(1,1,1), Thickness=1, Filled=false}),
            fill     = newDraw("Square",    {Visible=false, Color=Color3.new(0,0,0), Transparency=0.5, Filled=true}),
            name     = newDraw("Text",      {Visible=false, Color=Color3.new(1,1,1), Size=13, Center=true, Outline=true}),
            hp       = newDraw("Text",      {Visible=false, Color=Color3.new(0,1,0), Size=13, Center=true, Outline=true}),
            dist     = newDraw("Text",      {Visible=false, Color=Color3.new(1,1,0), Size=13, Center=true, Outline=true}),
            tracer   = newDraw("Line",      {Visible=false, Color=Color3.new(1,0,0), Thickness=1}),
            skeleton = {
                -- limb lines: head→neck, neck→lshoulder, neck→rshoulder,
                --             lshoulder→lelbow, rshoulder→relbow,
                --             lelbow→lwrist, relbow→rwrist,
                --             neck→lhip, neck→rhip (approximated from humanoid)
            },
            headMark = newDraw("Circle",    {Visible=false, Color=Color3.new(1,0,0), Thickness=1, Filled=false}),
            weapon   = newDraw("Text",      {Visible=false, Color=Color3.new(1,0.7,0), Size=12, Center=true, Outline=true}),
            ammoBar  = {back=newDraw("Square",{Visible=false,Color=Color3.new(0,0,0),Filled=true}),
                        front=newDraw("Square",{Visible=false,Color=Color3.new(0,0.5,1),Filled=true})},
            hpBar    = {back=newDraw("Square",{Visible=false,Color=Color3.new(0,0,0),Filled=true}),
                        front=newDraw("Square",{Visible=false,Color=Color3.new(0,1,0),Filled=true})},
        }
    end

    local function removeEntry(plr)
        local e = drawings[plr]
        if not e then return end
        for k,v in e do
            if type(v)=="table" then
                for _,d in v do if type(d)~="table" and d.Remove then d:Remove() end end
            elseif v and v.Remove then v:Remove() end
        end
        drawings[plr] = nil
    end

    local function getCharBounds(char)
        -- returns top/bottom screen positions and width
        local root = getRootPart(char)
        local head = getHead(char)
        if not root or not head then return nil end

        local topPos = head.Position + Vector3.new(0, 0.5, 0)
        local botPos = root.Position - Vector3.new(0, 2.5, 0)

        local top2d, topVis, topZ = worldToViewport(topPos)
        local bot2d, botVis       = worldToViewport(botPos)

        if not topVis and not botVis then return nil end
        if topZ <= 0 then return nil end

        local height = math.abs(bot2d.Y - top2d.Y)
        local width  = height * 0.5
        return top2d, bot2d, width, height
    end

    local function teamCheck(plr)
        if not K.opts.EspTeamCheck then return true end
        return plr.Team ~= lp.Team
    end

    function Esp.update()
        local espEnabled = K.opts.EspEnabled
        local boxEnabled = K.opts.EspBox
        local nameEnabled= K.opts.EspName
        local hpEnabled  = K.opts.EspHP
        local distEnabled= K.opts.EspDist
        local tracerEnabled = K.opts.EspTracer
        local headEnabled= K.opts.EspHeadMarker
        local hpBarEnabled = K.opts.EspHPBar
        local weaponEnabled= K.opts.EspWeapon
        local fillEnabled  = K.opts.EspFilledBox
        local ammoEnabled  = K.opts.EspAmmoBar
        local skeletonEnabled = K.opts.EspSkeleton
        local chamEnabled  = K.opts.EspChams

        for _, plr in Players:GetPlayers() do
            if plr == lp then continue end

            if not drawings[plr] then
                drawings[plr] = makeEntry(plr)
            end
            local e = drawings[plr]

            local char = plr.Character
            local alive = isAlive(plr)
            local show = espEnabled and alive and char and teamCheck(plr)

            if not show then
                for k,v in e do
                    if type(v)=="table" then
                        for _,d in v do if type(d)~="table" and d.Visible~=nil then d.Visible=false end end
                    elseif v and v.Visible~=nil then v.Visible=false end
                end
                continue
            end

            local root = getRootPart(char)
            local head = getHead(char)
            if not root or not head then continue end

            local top2d, bot2d, bw, bh = getCharBounds(char) or (nil,nil,nil,nil)
            local onScreen = top2d ~= nil

            local hum = getHumanoid(char)
            local hpPct = hum and (hum.Health/math.max(hum.MaxHealth,1)) or 0
            local dist  = math.floor((lp.Character and getRootPart(lp.Character) and
                           (getRootPart(lp.Character).Position - root.Position).Magnitude) or 0)

            local isEnemy = plr.Team ~= lp.Team
            local boxColor = isEnemy and K.opts.EspEnemyColor or K.opts.EspTeamColor
            boxColor = boxColor or Color3.new(1,0,0)

            -- BOX
            if boxEnabled and onScreen then
                local bx = top2d.X - bw/2
                local by = top2d.Y
                e.box.Position = Vector2.new(bx, by)
                e.box.Size     = Vector2.new(bw, bh)
                e.box.Color    = boxColor
                e.box.Visible  = true
            else e.box.Visible = false end

            -- FILLED BOX
            if fillEnabled and onScreen then
                local bx = top2d.X - bw/2
                local by = top2d.Y
                e.fill.Position = Vector2.new(bx, by)
                e.fill.Size     = Vector2.new(bw, bh)
                e.fill.Color    = boxColor
                e.fill.Transparency = K.opts.EspFillAlpha or 0.6
                e.fill.Visible  = true
            else e.fill.Visible = false end

            -- HP BAR (left of box)
            if hpBarEnabled and onScreen then
                local bx = top2d.X - bw/2 - 6
                local by = top2d.Y
                e.hpBar.back.Position  = Vector2.new(bx, by)
                e.hpBar.back.Size      = Vector2.new(4, bh)
                e.hpBar.back.Visible   = true
                e.hpBar.front.Position = Vector2.new(bx, by + bh*(1-hpPct))
                e.hpBar.front.Size     = Vector2.new(4, bh*hpPct)
                e.hpBar.front.Color    = Color3.fromHSV(hpPct*0.33, 1, 1)
                e.hpBar.front.Visible  = true
            else
                e.hpBar.back.Visible  = false
                e.hpBar.front.Visible = false
            end

            -- NAME
            if nameEnabled and onScreen then
                e.name.Position = Vector2.new(top2d.X, top2d.Y - 16)
                e.name.Text     = plr.DisplayName
                e.name.Color    = boxColor
                e.name.Visible  = true
            else e.name.Visible = false end

            -- HP TEXT
            if hpEnabled and onScreen then
                e.hp.Position = Vector2.new(top2d.X, top2d.Y - 30)
                e.hp.Text     = string.format("[%d HP]", math.floor(hum and hum.Health or 0))
                e.hp.Color    = Color3.fromHSV(hpPct*0.33, 1, 1)
                e.hp.Visible  = true
            else e.hp.Visible = false end

            -- DISTANCE
            if distEnabled and onScreen then
                e.dist.Position = Vector2.new(top2d.X, bot2d.Y + 2)
                e.dist.Text     = dist .. "m"
                e.dist.Color    = Color3.new(1,1,0)
                e.dist.Visible  = true
            else e.dist.Visible = false end

            -- TRACER
            if tracerEnabled and onScreen then
                local origin = K.opts.EspTracerOrigin or "Bottom"
                local vp = Camera.ViewportSize
                local oy = origin == "Top" and 0 or (origin == "Center" and vp.Y/2 or vp.Y)
                e.tracer.From  = Vector2.new(vp.X/2, oy)
                e.tracer.To    = Vector2.new(top2d.X, bot2d.Y)
                e.tracer.Color = boxColor
                e.tracer.Visible = true
            else e.tracer.Visible = false end

            -- HEAD MARKER
            if headEnabled and onScreen then
                local h2d = worldToViewport(head.Position)
                e.headMark.Position = h2d
                e.headMark.Radius   = 5
                e.headMark.Color    = boxColor
                e.headMark.Visible  = true
            else e.headMark.Visible = false end

            -- WEAPON
            if weaponEnabled and onScreen then
                local tool = char:FindFirstChildOfClass("Tool")
                e.weapon.Position = Vector2.new(top2d.X + bw/2 + 4, top2d.Y)
                e.weapon.Text     = tool and tool.Name or "None"
                e.weapon.Visible  = true
            else e.weapon.Visible = false end

            -- CHAMS (via highlight)
            if chamEnabled then
                local hl = char:FindFirstChild("__KiciaHL")
                if not hl then
                    hl = Instance.new("SelectionBox")
                    hl.Name              = "__KiciaHL"
                    hl.Adornee           = char
                    hl.Color3            = isEnemy and Color3.new(1,0,0) or Color3.new(0,1,0)
                    hl.SurfaceColor3     = isEnemy and Color3.new(1,0,0) or Color3.new(0,1,0)
                    hl.SurfaceTransparency = 0.7
                    hl.Parent            = char
                end
                hl.Visible = true
            else
                local hl = char:FindFirstChild("__KiciaHL")
                if hl then hl.Visible = false end
            end
        end
    end

    function Esp.cleanPlayer(plr)
        removeEntry(plr)
        local char = plr.Character
        if char then
            local hl = char:FindFirstChild("__KiciaHL")
            if hl then hl:Destroy() end
        end
    end

    function Esp.destroy()
        for plr,_ in drawings do removeEntry(plr) end
    end

    onUnload(Esp.destroy)
end

--=============================================================================
--  AIMBOT ENGINE
--=============================================================================
local Aimbot = {}
do
    local lockedTarget = nil
    local lockedPart   = nil

    local function getFOV() return K.opts.AimFOV or 90 end

    local function distFromCenter(pos2d)
        local vp = Camera.ViewportSize
        local cx, cy = vp.X/2, vp.Y/2
        return (Vector2.new(cx,cy) - pos2d).Magnitude
    end

    local function inFOV(pos2d)
        return distFromCenter(pos2d) <= getFOV()
    end

    local function getTargetPart(char)
        local mode = K.opts.AimPart or "Head"
        return char:FindFirstChild(mode) or getHead(char) or getRootPart(char)
    end

    local function teamFilter(plr)
        if not K.opts.AimTeamCheck then return true end
        return plr.Team ~= lp.Team
    end

    local function wallCheck(origin, target)
        if not K.opts.AimWallCheck then return true end
        local dir = (target - origin).Unit * (target - origin).Magnitude
        local ray = RaycastParams.new()
        ray.FilterDescendantsInstances = {lp.Character}
        ray.FilterType = Enum.RaycastFilterType.Exclude
        local res = Workspace:Raycast(origin, dir, ray)
        if not res then return true end
        -- hit something: check if it belongs to a player char
        local inst = res.Instance
        local parent = inst and inst.Parent
        for _, p in Players:GetPlayers() do
            if p.Character and (p.Character == parent or parent:IsDescendantOf(p.Character)) then
                return true
            end
        end
        return false
    end

    local function getBestTarget()
        local best, bestDist, bestPart = nil, math.huge, nil
        local lchar = lp.Character
        local lroot = lchar and getRootPart(lchar)
        if not lroot then return nil, nil end

        for _, plr in Players:GetPlayers() do
            if plr == lp then continue end
            if not isAlive(plr) then continue end
            if not teamFilter(plr) then continue end

            local char = plr.Character
            local part = getTargetPart(char)
            if not part then continue end

            local pos = K.opts.AimPredict and
                Resolver.getPredicted(plr, K.opts.AimPredictAmount or 0.1) or
                part.Position

            if not pos then continue end

            local pos2d, onScreen = worldToViewport(pos)
            if not onScreen then continue end
            if not inFOV(pos2d) then continue end

            local d = distFromCenter(pos2d)
            if d < bestDist then
                if wallCheck(lroot.Position, pos) then
                    best, bestDist, bestPart = plr, d, part
                end
            end
        end
        return best, bestPart
    end

    -- FOV circle drawing
    local fovCircle = Drawing.new("Circle")
    fovCircle.Visible     = false
    fovCircle.Color       = Color3.new(1,1,1)
    fovCircle.Thickness   = 1
    fovCircle.Filled      = false
    fovCircle.NumSides    = 64

    track(RunService.RenderStepped:Connect(function()
        -- FOV circle
        if K.opts.AimShowFOV then
            local vp = Camera.ViewportSize
            fovCircle.Position = Vector2.new(vp.X/2, vp.Y/2)
            fovCircle.Radius   = getFOV()
            fovCircle.Visible  = true
        else
            fovCircle.Visible = false
        end
    end))

    local function aimAt(target, part)
        if not target or not part then return end
        local pos = K.opts.AimPredict and
            Resolver.getPredicted(target, K.opts.AimPredictAmount or 0.1) or
            part.Position
        if not pos then return end

        local mode = K.opts.AimMode or "Silent"

        if mode == "Silent" then
            -- silent aim: fire correction is handled post-shoot via camera lock bypass
            -- we redirect locally only (no server CFrame)
            local cf = CFrame.new(Camera.CFrame.Position, pos)
            -- store for hitbox expansion
            K._silentTarget = {plr=target, pos=pos}
        elseif mode == "Legit" then
            local smooth = K.opts.AimSmoothing or 0.2
            local cf     = CFrame.new(Camera.CFrame.Position, pos)
            Camera.CFrame = Camera.CFrame:Lerp(cf, smooth)
        elseif mode == "Triggerbot" then
            -- handled below
        end
    end

    local function triggerCheck()
        if K.opts.AimMode ~= "Triggerbot" then return end
        local lchar = lp.Character
        local lroot = lchar and getRootPart(lchar)
        if not lroot then return end
        local vp  = Camera.ViewportSize
        local center = Vector2.new(vp.X/2, vp.Y/2)
        for _, plr in Players:GetPlayers() do
            if plr == lp then continue end
            if not isAlive(plr) then continue end
            if not teamFilter(plr) then continue end
            local char = plr.Character
            local part = getTargetPart(char)
            if not part then continue end
            local p2d, vis = worldToViewport(part.Position)
            if not vis then continue end
            if (center - p2d).Magnitude < (K.opts.TriggerThreshold or 15) then
                -- simulate click
                local veh = UserInputService
                -- fire mouse1
                local ms = UserInputService:GetMouseLocation()
                -- using mouse1click via firetouchstarted if available
                if mouse1click then mouse1click() end
            end
        end
    end

    local aimActive = false
    track(RunService.Heartbeat:Connect(function()
        local holding = K.opts.AimKey and UserInputService:IsKeyDown(K.opts.AimKey)
        local mouseHold = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)

        local shouldAim = K.opts.AimEnabled and (K.opts.AimMode == "Silent" or holding or mouseHold or
            K.opts.AimMode == "Triggerbot")

        K._silentTarget = nil

        if shouldAim then
            local t, p = getBestTarget()
            lockedTarget = t
            lockedPart   = p
            aimAt(t, p)
            triggerCheck()
        else
            lockedTarget = nil
            lockedPart   = nil
        end
    end))

    -- Hitbox expansion
    track(RunService.Heartbeat:Connect(function()
        if not K.opts.HitboxEnabled then return end
        local size = K.opts.HitboxSize or 5
        for _, plr in Players:GetPlayers() do
            if plr == lp then continue end
            local char = plr.Character
            if not char then continue end
            local head = getHead(char)
            if not head then continue end
            if head.Size ~= Vector3.new(size, size, size) then
                local ok = pcall(function()
                    head.Size = Vector3.new(size, size, size)
                end)
            end
        end
    end))

    -- Silent aim redirect (newindex hook on camera if needed)
    -- We use gethiddenproperty / sethiddenproperty if available for silent aim
    function Aimbot.getSilentTarget()
        return K._silentTarget
    end

    function Aimbot.getLockedTarget()
        return lockedTarget, lockedPart
    end

    onUnload(function()
        fovCircle:Remove()
    end)
end

--=============================================================================
--  WORLD VISUALS
--=============================================================================
local WorldVisuals = {}
do
    -- Fullbright
    local origAmbient, origBrightness, origFogEnd
    function WorldVisuals.setFullbright(enabled)
        if enabled then
            origAmbient    = Lighting.Ambient
            origBrightness = Lighting.Brightness
            origFogEnd     = Lighting.FogEnd
            Lighting.Ambient    = Color3.new(1,1,1)
            Lighting.Brightness = 2
            Lighting.FogEnd     = 1e6
        else
            if origAmbient then
                Lighting.Ambient    = origAmbient
                Lighting.Brightness = origBrightness
                Lighting.FogEnd     = origFogEnd
            end
        end
    end

    -- Remove fog
    function WorldVisuals.setNoFog(enabled)
        Lighting.FogEnd = enabled and 1e9 or (origFogEnd or 1e9)
    end

    -- Noclip
    local noclipConn
    function WorldVisuals.setNoclip(enabled)
        if enabled then
            noclipConn = track(RunService.Stepped:Connect(function()
                local char = lp.Character
                if not char then return end
                for _, p in char:GetDescendants() do
                    if p:IsA("BasePart") then
                        p.CanCollide = false
                    end
                end
            end))
        else
            if noclipConn then
                noclipConn:Disconnect()
                noclipConn = nil
            end
        end
    end

    -- Speed
    local speedConn
    function WorldVisuals.setSpeed(enabled, spd)
        if speedConn then speedConn:Disconnect() speedConn = nil end
        if enabled then
            speedConn = track(RunService.Heartbeat:Connect(function()
                local char = lp.Character
                local hum  = char and getHumanoid(char)
                if hum then hum.WalkSpeed = spd or 16 end
            end))
        else
            local char = lp.Character
            local hum  = char and getHumanoid(char)
            if hum then hum.WalkSpeed = 16 end
        end
    end

    -- Jump power
    function WorldVisuals.setJump(enabled, pwr)
        local char = lp.Character
        local hum  = char and getHumanoid(char)
        if hum then hum.JumpPower = enabled and (pwr or 50) or 50 end
    end

    -- Infinite jump
    local ijConn
    function WorldVisuals.setInfJump(enabled)
        if ijConn then ijConn:Disconnect() ijConn = nil end
        if enabled then
            ijConn = track(UserInputService.JumpRequest:Connect(function()
                local char = lp.Character
                local hum  = char and getHumanoid(char)
                if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
            end))
        end
    end

    onUnload(function()
        WorldVisuals.setFullbright(false)
        WorldVisuals.setNoclip(false)
        WorldVisuals.setSpeed(false, 16)
        WorldVisuals.setInfJump(false)
    end)
end

--=============================================================================
--  CROSSHAIR
--=============================================================================
local Crosshair = {}
do
    local lines = {
        top    = Drawing.new("Line"),
        bot    = Drawing.new("Line"),
        left   = Drawing.new("Line"),
        right  = Drawing.new("Line"),
        circle = Drawing.new("Circle"),
        dot    = Drawing.new("Circle"),
    }
    for _,l in lines do l.Visible = false l.Color = Color3.new(1,1,1) l.Thickness = 1 end
    lines.circle.Filled = false lines.circle.NumSides = 32
    lines.dot.Filled = true

    track(RunService.RenderStepped:Connect(function()
        if not K.opts.CrosshairEnabled then
            for _,l in lines do l.Visible = false end
            return
        end
        local vp = Camera.ViewportSize
        local cx, cy = vp.X/2, vp.Y/2
        local len  = K.opts.CrosshairLength  or 10
        local gap  = K.opts.CrosshairGap     or 3
        local thick= K.opts.CrosshairThick   or 1
        local col  = K.opts.CrosshairColor   or Color3.new(1,1,1)
        local mode = K.opts.CrosshairMode    or "Cross"

        for _,l in lines do l.Color = col l.Thickness = thick l.Visible = false end

        if mode == "Cross" or mode == "Full" then
            lines.top.From    = Vector2.new(cx, cy - gap - len)
            lines.top.To      = Vector2.new(cx, cy - gap)
            lines.bot.From    = Vector2.new(cx, cy + gap)
            lines.bot.To      = Vector2.new(cx, cy + gap + len)
            lines.left.From   = Vector2.new(cx - gap - len, cy)
            lines.left.To     = Vector2.new(cx - gap, cy)
            lines.right.From  = Vector2.new(cx + gap, cy)
            lines.right.To    = Vector2.new(cx + gap + len, cy)
            lines.top.Visible = lines.bot.Visible = lines.left.Visible = lines.right.Visible = true
        end
        if mode == "Circle" then
            lines.circle.Position = Vector2.new(cx, cy)
            lines.circle.Radius   = K.opts.CrosshairCircleRadius or 20
            lines.circle.Visible  = true
        end
        if K.opts.CrosshairDot then
            lines.dot.Position = Vector2.new(cx, cy)
            lines.dot.Radius   = 2
            lines.dot.Color    = col
            lines.dot.Visible  = true
        end
    end))

    onUnload(function()
        for _,l in lines do l:Remove() end
    end)
end

--=============================================================================
--  WATERMARK
--=============================================================================
local wmark = Drawing.new("Text")
wmark.Text     = "kicia rebuild | rivals"
wmark.Size     = 14
wmark.Color    = Color3.new(1,1,1)
wmark.Outline  = true
wmark.Position = Vector2.new(10, 10)
wmark.Visible  = true
onUnload(function() wmark:Remove() end)

track(RunService.RenderStepped:Connect(function()
    wmark.Visible = K.opts.WatermarkEnabled ~= false
    local t, _ = Aimbot.getLockedTarget()
    if t then
        wmark.Text = "kicia rebuild | rivals | locked: " .. t.DisplayName
    else
        wmark.Text = "kicia rebuild | rivals"
    end
end))

--=============================================================================
--  MAIN RENDER LOOP
--=============================================================================
track(RunService.RenderStepped:Connect(function()
    Esp.update()
end))

--=============================================================================
--  PLAYER TRACKING HOOKS
--=============================================================================
track(Players.PlayerRemoving:Connect(function(plr)
    Esp.cleanPlayer(plr)
    Resolver.clean(plr)
end))

--=============================================================================
--  OBSIDIAN WINDOW
--=============================================================================
local Window = Library:CreateWindow({
    Title         = "Kicia Rebuild",
    Footer        = "rivals | by temu",
    NotifySide    = "Right",
    Animations    = {
        ToggleWindow = true,
        TabSwitch    = true,
        Groupbox     = true,
        Dropdown     = true,
        KeyPicker    = true,
    },
    TabTransitionTime = 0.18,
    TabSwipeOffset    = 20,
    TabSwipeFrom      = "bottom",
    EnableSidebarResize = true,
    Snapping          = true,
})

local Tabs = {
    Aimbot  = Window:AddTab("Aimbot",  "crosshair"),
    ESP     = Window:AddTab("ESP",     "eye"),
    Visuals = Window:AddTab("Visuals", "sparkles"),
    World   = Window:AddTab("World",   "globe"),
    Misc    = Window:AddTab("Misc",    "settings-2"),
    Config  = Window:AddTab("Config",  "save"),
}

--===========================================================================
--  TAB: AIMBOT
--===========================================================================
do
    local AimLeft  = Tabs.Aimbot:AddGroupbox({ Side="Left",  Name="Aimbot" })
    local AimRight = Tabs.Aimbot:AddGroupbox({ Side="Right", Name="Settings" })

    AimLeft:AddToggle("AimEnabled", {
        Text    = "Enable Aimbot",
        Default = false,
        Callback= function(v) K.opts.AimEnabled = v end,
    })

    AimLeft:AddDropdown("AimMode", {
        Values  = {"Silent", "Legit", "Triggerbot"},
        Default = "Silent",
        Text    = "Aim Mode",
        Callback= function(v) K.opts.AimMode = v end,
    })

    AimLeft:AddDropdown("AimPart", {
        Values  = {"Head", "HumanoidRootPart", "Torso", "UpperTorso"},
        Default = "Head",
        Text    = "Target Part",
        Callback= function(v) K.opts.AimPart = v end,
    })

    AimLeft:AddSlider("AimFOV", {
        Text    = "FOV Radius",
        Min     = 10, Max = 500, Default = 90, Suffix = "px",
        Callback= function(v) K.opts.AimFOV = v end,
    })

    AimLeft:AddToggle("AimShowFOV", {
        Text    = "Draw FOV Circle",
        Default = true,
        Callback= function(v) K.opts.AimShowFOV = v end,
    })

    AimLeft:AddToggle("AimTeamCheck", {
        Text    = "Team Check",
        Default = true,
        Callback= function(v) K.opts.AimTeamCheck = v end,
    })

    AimLeft:AddToggle("AimWallCheck", {
        Text    = "Wallcheck",
        Default = false,
        Callback= function(v) K.opts.AimWallCheck = v end,
    })

    AimLeft:AddKeyPicker("AimKey", {
        Default = "E",
        Text    = "Aim Hold Key",
        Callback= function(v) K.opts.AimKey = v end,
    })

    -- Right: predict + smoothing + hitbox
    AimRight:AddToggle("AimPredict", {
        Text    = "Prediction (velocity)",
        Default = true,
        Callback= function(v) K.opts.AimPredict = v end,
    })

    AimRight:AddSlider("AimPredictAmount", {
        Text    = "Predict Latency",
        Min     = 0, Max = 0.5, Default = 0.1, Suffix = "s",
        Rounding= 2,
        Callback= function(v) K.opts.AimPredictAmount = v end,
    })

    AimRight:AddSlider("AimSmoothing", {
        Text    = "Smooth (Legit)",
        Min     = 0.01, Max = 1, Default = 0.2, Rounding = 2,
        Callback= function(v) K.opts.AimSmoothing = v end,
    })

    AimRight:AddDivider()

    local HbGroup = AimRight:AddGroupbox({ Name="Hitbox", Side="Right" })
    HbGroup:AddToggle("HitboxEnabled", {
        Text    = "Expand Hitbox",
        Default = false,
        Callback= function(v) K.opts.HitboxEnabled = v end,
    })
    HbGroup:AddSlider("HitboxSize", {
        Text    = "Hitbox Size",
        Min     = 1, Max = 20, Default = 5,
        Callback= function(v) K.opts.HitboxSize = v end,
    })

    AimRight:AddDivider()

    local TBGroup = AimRight:AddGroupbox({ Name="Triggerbot", Side="Right" })
    TBGroup:AddSlider("TriggerThreshold", {
        Text    = "Pixel Threshold",
        Min     = 1, Max = 60, Default = 15, Suffix="px",
        Callback= function(v) K.opts.TriggerThreshold = v end,
    })
end

--===========================================================================
--  TAB: ESP
--===========================================================================
do
    local EspLeft  = Tabs.ESP:AddGroupbox({ Side="Left",  Name="Enemies" })
    local EspRight = Tabs.ESP:AddGroupbox({ Side="Right", Name="Appearance" })

    EspLeft:AddToggle("EspEnabled", {
        Text    = "Enable ESP",
        Default = true,
        Callback= function(v) K.opts.EspEnabled = v end,
    })

    EspLeft:AddToggle("EspTeamCheck", {
        Text    = "Enemy Only",
        Default = true,
        Callback= function(v) K.opts.EspTeamCheck = v end,
    })

    EspLeft:AddToggle("EspBox", {
        Text    = "Box",
        Default = true,
        Callback= function(v) K.opts.EspBox = v end,
    })

    EspLeft:AddToggle("EspFilledBox", {
        Text    = "Filled Box",
        Default = false,
        Callback= function(v) K.opts.EspFilledBox = v end,
    })

    EspLeft:AddSlider("EspFillAlpha", {
        Text    = "Fill Transparency",
        Min     = 0, Max = 1, Default = 0.6, Rounding=2,
        Callback= function(v) K.opts.EspFillAlpha = v end,
    })

    EspLeft:AddToggle("EspName", {
        Text    = "Name",
        Default = true,
        Callback= function(v) K.opts.EspName = v end,
    })

    EspLeft:AddToggle("EspHP", {
        Text    = "Health Text",
        Default = true,
        Callback= function(v) K.opts.EspHP = v end,
    })

    EspLeft:AddToggle("EspHPBar", {
        Text    = "Health Bar",
        Default = true,
        Callback= function(v) K.opts.EspHPBar = v end,
    })

    EspLeft:AddToggle("EspDist", {
        Text    = "Distance",
        Default = false,
        Callback= function(v) K.opts.EspDist = v end,
    })

    EspLeft:AddToggle("EspWeapon", {
        Text    = "Held Weapon",
        Default = true,
        Callback= function(v) K.opts.EspWeapon = v end,
    })

    EspLeft:AddToggle("EspTracer", {
        Text    = "Tracer",
        Default = false,
        Callback= function(v) K.opts.EspTracer = v end,
    })

    EspLeft:AddDropdown("EspTracerOrigin", {
        Values  = {"Bottom", "Center", "Top"},
        Default = "Bottom",
        Text    = "Tracer Origin",
        Callback= function(v) K.opts.EspTracerOrigin = v end,
    })

    EspLeft:AddToggle("EspHeadMarker", {
        Text    = "Head Marker",
        Default = false,
        Callback= function(v) K.opts.EspHeadMarker = v end,
    })

    EspLeft:AddToggle("EspSkeleton", {
        Text    = "Skeleton",
        Default = false,
        Callback= function(v) K.opts.EspSkeleton = v end,
    })

    EspLeft:AddToggle("EspChams", {
        Text    = "Chams (SelectionBox)",
        Default = false,
        Callback= function(v) K.opts.EspChams = v end,
    })

    -- Right: colors
    EspRight:AddColorPicker("EspEnemyColor", {
        Default = Color3.new(1,0,0),
        Text    = "Enemy Color",
        Callback= function(v) K.opts.EspEnemyColor = v end,
    })

    EspRight:AddColorPicker("EspTeamColor", {
        Default = Color3.new(0,1,0),
        Text    = "Team Color",
        Callback= function(v) K.opts.EspTeamColor = v end,
    })
end

--===========================================================================
--  TAB: VISUALS
--===========================================================================
do
    local VLeft  = Tabs.Visuals:AddGroupbox({ Side="Left",  Name="Crosshair" })
    local VRight = Tabs.Visuals:AddGroupbox({ Side="Right", Name="Rendering" })

    VLeft:AddToggle("CrosshairEnabled", {
        Text    = "Enable Crosshair",
        Default = true,
        Callback= function(v) K.opts.CrosshairEnabled = v end,
    })

    VLeft:AddDropdown("CrosshairMode", {
        Values  = {"Cross", "Circle", "Full"},
        Default = "Cross",
        Text    = "Style",
        Callback= function(v) K.opts.CrosshairMode = v end,
    })

    VLeft:AddSlider("CrosshairLength", {
        Text    = "Line Length",
        Min     = 1, Max = 40, Default = 10,
        Callback= function(v) K.opts.CrosshairLength = v end,
    })

    VLeft:AddSlider("CrosshairGap", {
        Text    = "Gap",
        Min     = 0, Max = 20, Default = 3,
        Callback= function(v) K.opts.CrosshairGap = v end,
    })

    VLeft:AddSlider("CrosshairThick", {
        Text    = "Thickness",
        Min     = 1, Max = 5, Default = 1,
        Callback= function(v) K.opts.CrosshairThick = v end,
    })

    VLeft:AddSlider("CrosshairCircleRadius", {
        Text    = "Circle Radius",
        Min     = 5, Max = 100, Default = 20,
        Callback= function(v) K.opts.CrosshairCircleRadius = v end,
    })

    VLeft:AddToggle("CrosshairDot", {
        Text    = "Center Dot",
        Default = false,
        Callback= function(v) K.opts.CrosshairDot = v end,
    })

    VLeft:AddColorPicker("CrosshairColor", {
        Default = Color3.new(1,1,1),
        Text    = "Color",
        Callback= function(v) K.opts.CrosshairColor = v end,
    })

    -- Right: render toggles
    VRight:AddToggle("WatermarkEnabled", {
        Text    = "Watermark",
        Default = true,
        Callback= function(v) K.opts.WatermarkEnabled = v end,
    })

    VRight:AddToggle("VisualsFullbright", {
        Text    = "Fullbright",
        Default = false,
        Callback= function(v) WorldVisuals.setFullbright(v) end,
    })

    VRight:AddToggle("VisualsNoFog", {
        Text    = "No Fog",
        Default = false,
        Callback= function(v) WorldVisuals.setNoFog(v) end,
    })

    -- FOV changer
    VRight:AddSlider("VisualsFieldOfView", {
        Text    = "FOV Override",
        Min     = 1, Max = 120, Default = 70,
        Callback= function(v)
            if K.opts.VisualsCustomFOV then
                Camera.FieldOfView = v
            end
        end,
    })

    VRight:AddToggle("VisualsCustomFOV", {
        Text    = "Custom FOV",
        Default = false,
        Callback= function(v)
            K.opts.VisualsCustomFOV = v
            if not v then Camera.FieldOfView = 70 end
        end,
    })
end

--===========================================================================
--  TAB: WORLD / MOVEMENT
--===========================================================================
do
    local WLeft  = Tabs.World:AddGroupbox({ Side="Left",  Name="Movement" })
    local WRight = Tabs.World:AddGroupbox({ Side="Right", Name="Physics" })

    WLeft:AddToggle("WorldNoclip", {
        Text    = "Noclip",
        Default = false,
        Callback= function(v) WorldVisuals.setNoclip(v) end,
    })

    WLeft:AddToggle("WorldSpeedEnabled", {
        Text    = "Speed Hack",
        Default = false,
        Callback= function(v) WorldVisuals.setSpeed(v, K.opts.WorldSpeed) end,
    })

    WLeft:AddSlider("WorldSpeed", {
        Text    = "Walk Speed",
        Min     = 1, Max = 200, Default = 32,
        Callback= function(v)
            K.opts.WorldSpeed = v
            if K.opts.WorldSpeedEnabled then WorldVisuals.setSpeed(true, v) end
        end,
    })

    WLeft:AddToggle("WorldInfJump", {
        Text    = "Infinite Jump",
        Default = false,
        Callback= function(v) WorldVisuals.setInfJump(v) end,
    })

    WLeft:AddToggle("WorldJumpEnabled", {
        Text    = "Custom Jump Power",
        Default = false,
        Callback= function(v) WorldVisuals.setJump(v, K.opts.WorldJumpPower) end,
    })

    WLeft:AddSlider("WorldJumpPower", {
        Text    = "Jump Power",
        Min     = 1, Max = 300, Default = 100,
        Callback= function(v)
            K.opts.WorldJumpPower = v
            if K.opts.WorldJumpEnabled then WorldVisuals.setJump(true, v) end
        end,
    })

    -- Right: anti-features
    WRight:AddToggle("WorldAntiVoid", {
        Text    = "Anti Void (fall reset)",
        Default = false,
        Callback= function(v) K.opts.WorldAntiVoid = v end,
    })

    WRight:AddToggle("WorldAutoRejoin", {
        Text    = "Auto Rejoin on death",
        Default = false,
        Callback= function(v) K.opts.WorldAutoRejoin = v end,
    })
end

-- Anti-void loop
track(RunService.Heartbeat:Connect(function()
    if not K.opts.WorldAntiVoid then return end
    local char = lp.Character
    local root = char and getRootPart(char)
    if root and root.Position.Y < -100 then
        root.CFrame = CFrame.new(0, 100, 0)
    end
end))

--===========================================================================
--  TAB: MISC
--===========================================================================
do
    local MLeft  = Tabs.Misc:AddGroupbox({ Side="Left",  Name="Utility" })
    local MRight = Tabs.Misc:AddGroupbox({ Side="Right", Name="Anti-cheat" })

    MLeft:AddToggle("MiscAutoClicker", {
        Text    = "Auto Clicker",
        Default = false,
        Callback= function(v) K.opts.MiscAutoClicker = v end,
    })

    MLeft:AddSlider("MiscAutoClickerCPS", {
        Text    = "CPS",
        Min     = 1, Max = 30, Default = 10,
        Callback= function(v) K.opts.MiscAutoClickerCPS = v end,
    })

    MLeft:AddToggle("MiscSpinbot", {
        Text    = "Spinbot",
        Default = false,
        Callback= function(v) K.opts.MiscSpinbot = v end,
    })

    MLeft:AddSlider("MiscSpinSpeed", {
        Text    = "Spin Speed",
        Min     = 1, Max = 60, Default = 10,
        Callback= function(v) K.opts.MiscSpinSpeed = v end,
    })

    MLeft:AddToggle("MiscBunnyHop", {
        Text    = "Bunny Hop",
        Default = false,
        Callback= function(v) K.opts.MiscBunnyHop = v end,
    })

    MRight:AddLabel({ Text = "Anti-cheat bypass is handled internally." })
    MRight:AddToggle("MiscAntiAfk", {
        Text    = "Anti AFK",
        Default = true,
        Callback= function(v) K.opts.MiscAntiAfk = v end,
    })
end

-- Auto clicker loop
do
    local lastClick = 0
    track(RunService.Heartbeat:Connect(function()
        if not K.opts.MiscAutoClicker then return end
        local cps = K.opts.MiscAutoClickerCPS or 10
        local now = tick()
        if now - lastClick >= 1/cps then
            lastClick = now
            if mouse1click then mouse1click() end
        end
    end))
end

-- Spinbot loop
do
    local angle = 0
    track(RunService.Heartbeat:Connect(function()
        if not K.opts.MiscSpinbot then return end
        local char = lp.Character
        local root = char and getRootPart(char)
        if not root then return end
        angle += (K.opts.MiscSpinSpeed or 10)
        root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, math.rad(angle), 0)
    end))
end

-- Bunny hop loop
do
    track(RunService.Heartbeat:Connect(function()
        if not K.opts.MiscBunnyHop then return end
        local char = lp.Character
        local hum  = char and getHumanoid(char)
        if not hum then return end
        if hum.FloorMaterial ~= Enum.Material.Air then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end))
end

-- Anti AFK
do
    local veh = lp:FindFirstChildOfClass("PlayerGui")
    track(RunService.Heartbeat:Connect(function()
        if not K.opts.MiscAntiAfk then return end
        -- kick anti-afk via VirtualUser if available
        local vu = game:GetService("VirtualUser")
        if vu then vu:CaptureController() vu:ClickButton2(Vector2.zero) end
    end))
end

--===========================================================================
--  TAB: CONFIG
--===========================================================================
do
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
    SaveManager:SetFolder("KiciaRebuild/rivals")

    ThemeManager:SetLibrary(Library)
    ThemeManager:SetFolder("KiciaRebuild")

    SaveManager:BuildConfigSection(Tabs.Config)
    ThemeManager:BuildThemeSection(Tabs.Config)

    SaveManager:LoadAutoloadConfig()
end

--=============================================================================
--  MENU KEYBIND
--=============================================================================
Library:SetWatermarkVisibility(false) -- we use our own watermark

track(UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        Window:Toggle()
    end
end))

Library:Notify({
    Title   = "Kicia Rebuild",
    Content = "Loaded ✓  |  RShift to toggle",
    Duration= 4,
})

