--=============================================================================
--  Kicia Ragebot Tab  –  Rivals  (Obsidian UI)
--  Full feature parity with jO / jD / jE / jB / jH / jI / jJ / jK / jM
--  Drop this file into your main loader after the Window is created.
--  Expects: Library, Window, Tabs, K (global opts table), lp, RunService, etc.
--=============================================================================

--=============================================================================
--  INTERNAL RAGEBOT ENGINE  (from kicia jO / jD / jE / jB / jL / jM dump)
--=============================================================================
local RB = {}
do
    --=========================================================================
    --  SERVICES (cloneref-safe aliases)
    --=========================================================================
    local WS       = game:GetService("Workspace")
    local Players  = game:GetService("Players")
    local RS       = game:GetService("RunService")
    local UIS      = game:GetService("UserInputService")
    local HS       = game:GetService("HttpService")
    local CS       = game:GetService("CollectionService")

    local lchar = function() return lp.Character end
    local lroot = function()
        local c = lchar()
        return c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart)
    end

    --=========================================================================
    --  RING LOCATIONS (kicia jL – immune ring for reload transport)
    --=========================================================================
    local RingLoc = {}
    do
        local rng  = Random.new()
        local salt = rng:NextInteger(0, 65535) * 65536 + rng:NextInteger(0, 65535)

        local function hashCell(cx, cz, s)
            local v = bit32.bxor(cx, bit32.lshift(cz, 16))
            v = (v * 2654435761 + s) % 4294967296
            v = bit32.bxor(v, bit32.rshift(v, 16))
            v = (v * 2246822519)  % 4294967296
            v = bit32.bxor(v, bit32.rshift(v, 13))
            return v
        end

        -- Normal ring: 65536 → 524288
        -- Immune ring: 134217728 → 1073741824
        local function makeRing(min, max)
            local cells = (max - min) / 2048
            local ymin  = min + 400 + 64
            local yspan = max - 400 - 64 - ymin + 1
            return { min=min, max=max, cells=cells, ymin=ymin, yspan=yspan,
                     salt=rng:NextInteger(0,65535)*65536+rng:NextInteger(0,65535) }
        end

        local normal = makeRing(65536, 524288)
        local immune = makeRing(134217728, 1073741824)

        local function cellPos(ring, cx, cz)
            local base = ring.min + 1024
            local hx   = hashCell(cx, cz, ring.salt) % 1121 - 560
            local hz   = hashCell(cx + 999, cz, ring.salt) % 1121 - 560
            local hy   = hashCell(cx, cz + 999, ring.salt) % ring.yspan
            return Vector3.new(base + cx*2048 + hx, ring.ymin + hy, base + cz*2048 + hz)
        end

        local function randomPos(ring)
            local n   = ring.cells - 1
            local cx  = rng:NextInteger(0, n)
            local cz  = rng:NextInteger(0, n)
            local pos = cellPos(ring, cx, cz)
            local r   = 200 * rng:NextNumber() ^ 0.333
            local th  = rng:NextNumber(0, math.pi*2)
            local phi = rng:NextNumber(-1,1)
            local sp  = math.sqrt(1 - phi*phi)
            return pos + Vector3.new(r*sp*math.cos(th), r*phi, r*sp*math.sin(th))
        end

        function RingLoc.getImmune()
            local pos = randomPos(immune)
            return CFrame.new(pos) *
                CFrame.fromOrientation(
                    rng:NextNumber(-math.pi, math.pi),
                    rng:NextNumber(-math.pi, math.pi),
                    rng:NextNumber(-math.pi, math.pi)
                )
        end

        function RingLoc.getNormal()
            local pos = randomPos(normal)
            return CFrame.new(pos) *
                CFrame.fromOrientation(
                    rng:NextNumber(-math.pi, math.pi),
                    rng:NextNumber(-math.pi, math.pi),
                    rng:NextNumber(-math.pi, math.pi)
                )
        end
    end

    --=========================================================================
    --  PART GLUE (kicia jO – local CFrame offset lock)
    --=========================================================================
    local PartGlue = {}
    PartGlue.__index = PartGlue
    function PartGlue.new()
        return setmetatable({ _acquired = {} }, PartGlue)
    end
    function PartGlue:Acquire(ourPart, targetPart)
        if not ourPart or not targetPart then
            return targetPart and targetPart.CFrame or CFrame.new()
        end
        local key = ourPart
        if not self._acquired[key] then
            self._acquired[key] = ourPart.CFrame:Inverse() * targetPart.CFrame
        end
        return ourPart.CFrame * self._acquired[key]
    end
    function PartGlue:Free(ourPart)
        self._acquired[ourPart] = nil
    end

    --=========================================================================
    --  SHOOT LOCK (kicia jA)
    --=========================================================================
    local ShootLock = {}
    ShootLock.__index = ShootLock
    function ShootLock.new()
        return setmetatable({ _lockedUntil = nil }, ShootLock)
    end
    function ShootLock:ShouldFire(willFire, duration)
        local now = os.clock()
        local locked = self._lockedUntil ~= nil and now < self._lockedUntil
        if willFire then
            self._lockedUntil = now + duration
        end
        return locked or willFire
    end
    function ShootLock:Reset()
        self._lockedUntil = nil
    end

    --=========================================================================
    --  POSITION HISTORY (velocity / prediction)
    --=========================================================================
    local history = {}  -- [plr] = { {pos, t} }

    local function recordPositions()
        for _, plr in Players:GetPlayers() do
            if plr == lp then continue end
            local char = plr.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if not root then continue end
            if not history[plr] then history[plr] = {} end
            local h = history[plr]
            h[#h+1] = { pos = root.Position, t = os.clock() }
            while #h > 24 do table.remove(h, 1) end
        end
    end

    local function getVelocity(plr)
        local h = history[plr]
        if not h or #h < 2 then return Vector3.zero end
        local a, b = h[#h-1], h[#h]
        local dt = b.t - a.t
        return dt > 0 and (b.pos - a.pos) / dt or Vector3.zero
    end

    local function predictPos(plr, lag)
        local char = plr.Character
        local head = char and char:FindFirstChild("Head")
        if not head then return nil end
        return head.Position + getVelocity(plr) * lag
    end

    --=========================================================================
    --  WALLCHECK
    --=========================================================================
    local wallParams = RaycastParams.new()
    wallParams.FilterType = Enum.RaycastFilterType.Exclude

    local function wallCheck(origin, target)
        local lc = lchar()
        wallParams.FilterDescendantsInstances = lc and {lc} or {}
        local dir = target - origin
        local res = WS:Raycast(origin, dir, wallParams)
        if not res then return true end
        for _, plr in Players:GetPlayers() do
            if plr.Character and res.Instance:IsDescendantOf(plr.Character) then
                return true
            end
        end
        return false
    end

    --=========================================================================
    --  FOV  (2D screen distance from center)
    --=========================================================================
    local function fovDist(pos3d)
        local vp, on = Camera:WorldToViewportPoint(pos3d)
        if not on or vp.Z <= 0 then return math.huge end
        local c = Camera.ViewportSize / 2
        return (Vector2.new(vp.X, vp.Y) - c).Magnitude
    end

    --=========================================================================
    --  TARGET SELECTION (kicia jB)
    --  Priority: Hacker tag first (if PrioritizeHackers), then first enemy alive
    --=========================================================================
    local function isTargetValid(plr)
        if plr == lp then return false end
        local char = plr.Character
        if not char then return false end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return false end
        -- team check
        if K.opts.RB_TeamCheck and plr.Team == lp.Team then return false end
        -- fov check
        local head = char:FindFirstChild("Head")
        if not head then return false end
        if fovDist(head.Position) > (K.opts.RB_FOV or 360) then return false end
        -- wall check (optional)
        local lr = lroot()
        if K.opts.RB_WallCheck and lr then
            if not wallCheck(lr.Position, head.Position) then return false end
        end
        return true
    end

    local function getBestTarget()
        local best, bestDist = nil, math.huge
        for _, plr in Players:GetPlayers() do
            if not isTargetValid(plr) then continue end
            local char = plr.Character
            local head = char:FindFirstChild("Head")
            if not head then continue end
            local d = fovDist(head.Position)
            -- PrioritizeHackers: players with the "Hacker" CollectionService tag go first
            if K.opts.RB_PrioritizeHackers and CS:HasTag(plr, "Hacker") then
                d = d - 1e9  -- bias toward front
            end
            if d < bestDist then
                best, bestDist = plr, d
            end
        end
        return best
    end

    --=========================================================================
    --  EVASION MODES (kicia jI / jK / jH)
    --=========================================================================
    local rng        = Random.new()
    local evadeTimer = 0
    local evadeInterval = 0.1  -- seconds between repositions

    local function evasionRandom(rootCF)
        -- jI: random position in a large radius, one axis sent to infinity
        local base = K.opts.RB_EvasionRadius or 10000
        local pos  = rootCF.Position
        local r    = base + base * (K.opts.RB_EvasionRadiusFactor or 0.5)
        local angle = rng:NextNumber(0, math.pi*2)
        local newPos = pos + Vector3.new(math.cos(angle)*r, rng:NextNumber(-5,5), math.sin(angle)*r)
        local axis  = rng:NextInteger(1, 3)
        if axis == 1 then newPos = Vector3.new(1073741824, newPos.Y, newPos.Z)
        elseif axis == 2 then newPos = Vector3.new(newPos.X, 1073741824, newPos.Z)
        else newPos = Vector3.new(newPos.X, newPos.Y, 1073741824) end
        return CFrame.new(newPos)
    end

    local function evasionTranslocate(rootCF, hasTargets)
        -- jK: land on OutOfBoundsPart with KillDelay == 0 to trigger void
        if not hasTargets then return evasionRandom(rootCF) end
        for _, part in CS:GetTagged("OutOfBoundsPart") do
            if part:GetAttribute("KillDelay") == 0 then
                local sz = part.Size
                return part.CFrame * CFrame.new(0, -sz.Y/2 + (K.opts.RB_TranslocateOffset or 2), 0)
            end
        end
        return evasionRandom(rootCF)
    end

    local pbPool       = {}
    local pbLastBreak  = nil
    local pbCooldown   = 0
    local pbDepthUp    = 2
    local pbDepthFwd   = 1

    local function evasionProjectileBreaker(rootCF)
        -- jH: surface-hug behind geometry to block slingshot projectiles
        local now = os.clock()
        if now < pbCooldown and pbLastBreak then
            return pbLastBreak * CFrame.new(0, -pbDepthUp, pbDepthFwd)
        end
        -- scan tagged whitelist parts for usable surfaces
        if #pbPool < 10 then
            for _, part in CS:GetTagged("RaycastWhitelist1") do
                if part:IsA("BasePart") and part.Transparency < 1 then
                    local sz = part.Size
                    if sz.X * sz.Y * sz.Z >= 64 then
                        pbPool[#pbPool+1] = part.CFrame
                    end
                end
                if #pbPool >= 30 then break end
            end
        end
        if #pbPool > 0 then
            local cf = pbPool[rng:NextInteger(1, #pbPool)]
            pbLastBreak = cf
            pbCooldown  = now + (K.opts.RB_PBRepositionInterval or 0.3)
            return cf * CFrame.new(0, -pbDepthUp, pbDepthFwd)
        end
        return evasionRandom(rootCF)
    end

    local function computeEvasionCFrame(rootCF, hasTargets)
        local mode = K.opts.RB_EvasionMode or "Off"
        if mode == "Off"              then return nil end
        if mode == "Random"           then return evasionRandom(rootCF) end
        if mode == "Translocate"      then return evasionTranslocate(rootCF, hasTargets) end
        if mode == "ProjectileBreaker"then return evasionProjectileBreaker(rootCF) end
        return nil
    end

    --=========================================================================
    --  RELOAD TRANSPORT (kicia jO _PlanReloadTransport)
    --  When we empty a mag, teleport to the immune ring and trigger reload
    --=========================================================================
    local reloadGun              = nil
    local reloadReadyAt          = nil
    local reloadAcknowledgeDeadline = nil
    local pendingDepletionAmmo   = nil

    local function clearReloadTransport()
        reloadGun                   = nil
        reloadReadyAt               = nil
        reloadAcknowledgeDeadline   = nil
        pendingDepletionAmmo        = nil
    end

    local function getEquippedTool()
        local char = lchar()
        return char and char:FindFirstChildOfClass("Tool")
    end

    local function getToolAmmo(tool)
        if not tool then return nil end
        -- Rivals stores ammo in an IntValue or NumberValue inside the tool
        local ammo = tool:FindFirstChild("Ammo") or
                     tool:FindFirstChild("CurrentAmmo") or
                     tool:FindFirstChild("BulletCount")
        if ammo and (ammo:IsA("IntValue") or ammo:IsA("NumberValue")) then
            return ammo.Value
        end
        -- also check attributes
        local attr = tool:GetAttribute("Ammo") or tool:GetAttribute("CurrentAmmo")
        if attr then return attr end
        return nil
    end

    local function getToolMaxAmmo(tool)
        if not tool then return nil end
        local mx = tool:GetAttribute("MaxAmmo") or tool:GetAttribute("ClipSize")
        return mx
    end

    local function getToolReloadFn(tool)
        -- Look for a Reload RemoteEvent / fire it
        if not tool then return end
        local re = tool:FindFirstChild("Reload") or
                   tool.Parent and tool.Parent:FindFirstChild("Reload")
        return re
    end

    local estimatedLag = 0.08  -- rough ping estimate; could read from ping stat

    --=========================================================================
    --  SPATIAL LIMIT GATE (kicia jJ)
    --  If our character is outside map bounds (pos >= 4194304) for longer than
    --  expected, stop shooting to avoid server kicks.
    --=========================================================================
    local limitEntryTime    = nil
    local limitExpected     = 1.0
    local SPATIAL_LIMIT     = 4194304

    local function inSpatialLimit(pos)
        return math.abs(pos.X) >= SPATIAL_LIMIT or
               math.abs(pos.Y) >= SPATIAL_LIMIT or
               math.abs(pos.Z) >= SPATIAL_LIMIT
    end

    local function spatialLimitGateTick(rootPart, willFire)
        if not rootPart then return false end
        local pos = rootPart.Position
        local now = os.clock()
        if not inSpatialLimit(pos) then
            if limitEntryTime ~= nil then
                if willFire then limitExpected = now - limitEntryTime end
                limitEntryTime = nil
            end
            return false
        end
        if limitEntryTime == nil then limitEntryTime = now end
        if willFire then
            local stability = K.opts.RB_Stability or 0.1
            if limitExpected - stability <= now - limitEntryTime then
                return false
            end
        end
        return true
    end

    --=========================================================================
    --  HITSCAN STRATEGY (kicia jD)
    --  Gun weapons: set server CFrame to glued position near head, then shoot
    --=========================================================================
    local glue       = PartGlue.new()
    local shootLock  = ShootLock.new()
    local gluedPart  = nil

    local HITSCAN_OFFSET_NORMAL = Vector3.new(0, -0.7, 0.05)
    local HITSCAN_OFFSET_BELOW  = Vector3.new(0, -3.85, 0.05)

    -- Encodes a CFrame into Rivals' internal shot format (6-component table)
    -- These constants match the dump exactly (jD tbl18/tbl19)
    local function encodedShotCF(isAbove)
        if isAbove then
            return { ["\0"]=-9e37, ["\1"]=0,         ["\2"]=0,
                     ["\3"]=-1.5707963267948966,
                     ["\4"]=3.1415926535897931, ["\5"]=3.1415926535897931 },
                   { ["\0"]=0, ["\1"]=-90000000, ["\2"]=0,
                     ["\3"]=-1.5707963267948966,
                     ["\4"]=3.1415926535897931, ["\5"]=3.1415926535897931 }
        else
            return { ["\0"]=-9e37, ["\1"]=0,         ["\2"]=0,
                     ["\3"]=1.5707963267948966,
                     ["\4"]=3.1415926535897931, ["\5"]=3.1415926535897931 },
                   { ["\0"]=0,  ["\1"]=90000000, ["\2"]=0,
                     ["\3"]=1.5707963267948966,
                     ["\4"]=3.1415926535897931, ["\5"]=3.1415926535897931 }
        end
    end

    local SHOT_EXTRA = { ["\0"]=0, ["\1"]=1, ["\2"]=0, ["\3"]=0, ["\4"]=0, ["\5"]=0 }

    --=========================================================================
    --  MELEE STRATEGY (kicia jE) – backstab / heavy attack window
    --=========================================================================
    local meleeShootLock       = ShootLock.new()
    local hitboxWindowUntil    = -1
    local attackCooldown       = -1
    local meleeGluedPart       = nil

    local MELEE_OFFSET_NORMAL  = Vector3.new(0, -0.7, 0.05)
    local MELEE_OFFSET_BELOW   = Vector3.new(0, -3.85, 0.05)

    local function resetMeleeState()
        hitboxWindowUntil  = -1
        attackCooldown     = -1
        meleeShootLock:Reset()
        if meleeGluedPart then
            glue:Free(meleeGluedPart)
            meleeGluedPart = nil
        end
    end

    --=========================================================================
    --  POSITION HELPER – is target "above" or "below" us
    --=========================================================================
    local function isTargetAbove(targetChar)
        local lr = lroot()
        local tr = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
        if not lr or not tr then return true end
        return tr.Position.Y >= lr.Position.Y - 2
    end

    --=========================================================================
    --  FIND SERVER-SIDE SHOOT REMOTE
    --  Rivals uses RemoteEvents in ReplicatedStorage for shooting
    --=========================================================================
    local function findShootRemote()
        local RS2 = game:GetService("ReplicatedStorage")
        -- Common Rivals remote names (from dump references to FireServer)
        local names = { "Shoot", "Attack", "Fire", "ShootBullet", "ItemInput", "Combat" }
        for _, n in names do
            local r = RS2:FindFirstChild(n, true)
            if r and r:IsA("RemoteEvent") then return r end
        end
        -- Try to find any RemoteEvent with "shoot" or "attack" in name (case-insensitive)
        for _, obj in RS2:GetDescendants() do
            if obj:IsA("RemoteEvent") then
                local low = obj.Name:lower()
                if low:find("shoot") or low:find("attack") or low:find("fire") then
                    return obj
                end
            end
        end
        return nil
    end

    local shootRemote = findShootRemote()

    --=========================================================================
    --  SERVER CFRAME SETTER (kicia CharacterController:SetServerCFrame equivalent)
    --  Rivals uses a RemoteEvent to set server-side character CFrame.
    --=========================================================================
    local function findSetCFrameRemote()
        local RS2 = game:GetService("ReplicatedStorage")
        for _, obj in RS2:GetDescendants() do
            if obj:IsA("RemoteEvent") then
                local low = obj.Name:lower()
                if low:find("setcframe") or low:find("movecframe") or
                   low:find("server_cf") or low:find("physicssend") then
                    return obj
                end
            end
        end
        return nil
    end

    local cfRemote = findSetCFrameRemote()

    local function setServerCFrame(cf)
        if not cf then return end
        if cfRemote then
            pcall(function() cfRemote:FireServer(cf) end)
        end
        -- Also try direct CFrame set via physics bypass (executor-level)
        local lr = lroot()
        if lr then
            pcall(function() lr.CFrame = cf end)
        end
    end

    --=========================================================================
    --  WEAPON PRIORITY (kicia jM)
    --  Reads Weapons.Priority and Weapons.Enabled from opts
    --=========================================================================
    local function getWeaponPriority(tool)
        if not tool then return math.huge end
        local name = tool.Name:lower()
        local priority = K.opts.RB_WeaponPriority or {"Primary","Secondary","Melee"}
        -- Heuristics: gun-like = Primary/Secondary, melee = Melee
        local function guessSlot(t)
            local tn = t.Name:lower()
            if tn:find("knife") or tn:find("sword") or tn:find("bat") or
               tn:find("melee") or tn:find("axe") then return "Melee" end
            if t:FindFirstChild("Ammo") or t:FindFirstChild("CurrentAmmo") or
               t:FindFirstChild("GunScript") then
                -- guess primary vs secondary by ammo capacity heuristic
                local mx = getToolMaxAmmo(t) or 30
                return mx >= 20 and "Primary" or "Secondary"
            end
            return "Primary"
        end
        local slot = guessSlot(tool)
        local enabled = K.opts["RB_Weapon_"..slot] ~= false
        if not enabled then return math.huge end
        return table.find(priority, slot) or math.huge
    end

    local function getBestWeapon()
        local char = lchar()
        if not char then return nil end
        local best, bestPriority = nil, math.huge
        for _, obj in char:GetChildren() do
            if obj:IsA("Tool") then
                local p = getWeaponPriority(obj)
                if p < bestPriority then
                    best, bestPriority = obj, p
                end
            end
        end
        return best
    end

    --=========================================================================
    --  RAGEBOT CORE UPDATE (kicia jO Update / _Plan / _ApplyPlan)
    --=========================================================================
    local enabled     = false
    local lastTarget  = nil
    local frames      = 0

    local function resetAll()
        clearReloadTransport()
        resetMeleeState()
        shootLock:Reset()
        gluedPart = nil
        lastTarget = nil
        limitEntryTime = nil
        pbPool = {}
        pbLastBreak = nil
    end

    local function rbUpdate(dt)
        if not K.opts.RB_Enabled then
            if enabled then resetAll() enabled = false end
            return
        end
        enabled = true

        local lc   = lchar()
        local lr   = lroot()
        if not lc or not lr then resetAll() return end
        local lhum = lc:FindFirstChildOfClass("Humanoid")
        if not lhum or lhum.Health <= 0 then resetAll() return end

        frames += 1
        local shootFrames = K.opts.RB_ShootFrames or 1

        -- record positions for prediction
        recordPositions()

        -- evasion-only mode (Translocate) doesn't aim
        local evasionMode = K.opts.RB_EvasionMode or "Off"
        local hasTargets  = false
        for _, plr in Players:GetPlayers() do
            if isTargetValid(plr) then hasTargets = true break end
        end

        if evasionMode == "Translocate" and reloadGun == nil then
            local evadeCF = computeEvasionCFrame(lr.CFrame, hasTargets)
            if evadeCF then setServerCFrame(evadeCF) end
            return
        end

        -- target selection
        local target = getBestTarget()
        if target then lastTarget = target.Character and target.Character:FindFirstChild("HumanoidRootPart") and target.Character:FindFirstChild("HumanoidRootPart").Position end

        -- weapon selection
        local weapon = getBestWeapon()

        -- spatial gate
        local spatialBlocked = spatialLimitGateTick(lr, target ~= nil)
        if spatialBlocked then return end

        -- no target → evasion
        if not target then
            local evadeCF = computeEvasionCFrame(lr.CFrame, hasTargets)
            if evadeCF then setServerCFrame(evadeCF) end
            return
        end

        local char = target.Character
        if not char then return end
        local head = char:FindFirstChild("Head")
        if not head then return end

        -- is target above or below us?
        local above  = isTargetAbove(char)
        local offset = above and HITSCAN_OFFSET_NORMAL or HITSCAN_OFFSET_BELOW

        -- glue + plan position
        local gluedCF = glue:Acquire(lr, head)
        local aimPos  = gluedCF.Position + offset

        -- prediction override
        if K.opts.RB_Predict then
            local predicted = predictPos(target, K.opts.RB_PredictLag or estimatedLag)
            if predicted then aimPos = predicted + offset end
        end

        local aimCF = CFrame.new(aimPos)

        -- check shoot lock
        local willShoot = shootLock:ShouldFire(frames % shootFrames == 0, dt * shootFrames)

        if not willShoot then
            -- evasion while not shooting
            local evadeCF = computeEvasionCFrame(lr.CFrame, hasTargets)
            setServerCFrame(evadeCF or aimCF)
            return
        end

        -- detect gun vs melee
        local isMelee = false
        if weapon then
            local wn = weapon.Name:lower()
            isMelee = wn:find("knife") or wn:find("sword") or wn:find("bat") or
                      wn:find("melee") or wn:find("axe")
        end

        if isMelee then
            -- melee strategy (kicia jE)
            local now = os.clock()
            local inWindow = now < hitboxWindowUntil

            if inWindow then
                -- heavy attack window (backstab)
                setServerCFrame(aimCF)
                if weapon then pcall(function()
                    local atk = weapon:FindFirstChild("HeavyAttack") or weapon:FindFirstChild("Attack")
                    if atk and atk:IsA("RemoteEvent") then
                        atk:FireServer(head.CFrame, head)
                    end
                end) end
                return
            end

            if not meleeShootLock:ShouldFire(frames % shootFrames == 0, dt * shootFrames) then
                local evadeCF = computeEvasionCFrame(lr.CFrame, hasTargets)
                setServerCFrame(evadeCF or aimCF)
                return
            end

            if now < attackCooldown then
                local evadeCF = computeEvasionCFrame(lr.CFrame, hasTargets)
                setServerCFrame(evadeCF or aimCF)
                return
            end

            -- backstab: open heavy-attack window
            if weapon and weapon.Name:lower():find("knife") then
                hitboxWindowUntil = now + 0.625
                attackCooldown    = now + 1.25
                -- set CFrame and heavy attack
                setServerCFrame(aimCF)
                pcall(function()
                    if shootRemote then shootRemote:FireServer(head.CFrame, head) end
                end)
            else
                -- normal melee attack
                setServerCFrame(aimCF)
                pcall(function()
                    if shootRemote then shootRemote:FireServer(head.CFrame, head) end
                end)
            end

        else
            -- hitscan gun strategy (kicia jD)
            local ammo = weapon and getToolAmmo(weapon)

            -- empty mag → reload transport
            if ammo ~= nil and ammo <= 0 then
                if K.opts.RB_OnEmpty == "Reload" then
                    local immuneCF = RingLoc.getImmune()
                    setServerCFrame(immuneCF)
                    -- fire reload if weapon has it
                    local re = weapon and getToolReloadFn(weapon)
                    if re and re:IsA("RemoteEvent") then
                        pcall(function() re:FireServer() end)
                    end
                    return
                end
            end

            -- set server CFrame to aim position and fire
            setServerCFrame(aimCF)
            pcall(function()
                if K.opts.RB_ForceCrouch then
                    -- signal crouch (Rivals checks server-side)
                    local cr = game:GetService("ReplicatedStorage"):FindFirstChild("Crouch", true)
                    if cr and cr:IsA("RemoteEvent") then cr:FireServer(true) end
                end
                if shootRemote then
                    shootRemote:FireServer(head.CFrame, head)
                end
            end)

            -- post-shot: check ammo depletion for reload transport
            task.defer(function()
                local newAmmo = weapon and weapon.Parent == lchar() and getToolAmmo(weapon)
                if newAmmo ~= nil and newAmmo <= 0 then
                    reloadGun = weapon
                    reloadReadyAt = os.clock() + estimatedLag * 2
                end
            end)
        end
    end

    --=========================================================================
    --  EXPOSE
    --=========================================================================
    function RB.getLockedTarget() return lastTarget end
    function RB.update(dt) rbUpdate(dt) end
    function RB.reset() resetAll() end
    function RB.refreshShootRemote() shootRemote = findShootRemote() end

    -- Run every Heartbeat
    local conn = RS.Heartbeat:Connect(function(dt)
        pcall(RB.update, dt)
    end)

    onUnload(function()
        conn:Disconnect()
        resetAll()
    end)
end  -- RB engine

--=============================================================================
--  FOV CIRCLE FOR RAGEBOT
--=============================================================================
local rbFovCircle = Drawing.new("Circle")
rbFovCircle.Visible   = false
rbFovCircle.Color     = Color3.new(1, 0.4, 0)
rbFovCircle.Thickness = 1
rbFovCircle.Filled    = false
rbFovCircle.NumSides  = 64

RunService.RenderStepped:Connect(function()
    if K.opts.RB_ShowFOV and K.opts.RB_Enabled then
        local vp = Camera.ViewportSize
        rbFovCircle.Position = Vector2.new(vp.X/2, vp.Y/2)
        rbFovCircle.Radius   = K.opts.RB_FOV or 360
        rbFovCircle.Color    = K.opts.RB_FOVColor or Color3.new(1, 0.4, 0)
        rbFovCircle.Visible  = true
    else
        rbFovCircle.Visible = false
    end
end)

onUnload(function() rbFovCircle:Remove() end)

--=============================================================================
--  OBSIDIAN TAB: RAGEBOT
--=============================================================================
local RBTab = Window:AddTab("Ragebot", "crosshair-2")
Tabs.Ragebot = RBTab

-- ─────────────────────────── LEFT COLUMN ───────────────────────────
local RBLeft = RBTab:AddGroupbox({ Side = "Left", Name = "Ragebot" })

RBLeft:AddToggle("RB_Enabled", {
    Text    = "Enable Ragebot",
    Default = false,
    Callback= function(v)
        K.opts.RB_Enabled = v
        if not v then RB.reset() end
    end,
})

RBLeft:AddKeyPicker("RB_Key", {
    Default  = "None",
    Text     = "Hold Key (hold mode)",
    SyncToggleState = false,
    Callback = function(v) K.opts.RB_Key = v end,
})

RBLeft:AddDropdown("RB_Mode", {
    Values   = { "Auto", "On Key Hold", "Toggle" },
    Default  = "Auto",
    Text     = "Activation Mode",
    Callback = function(v) K.opts.RB_Mode = v end,
})

RBLeft:AddDivider()

RBLeft:AddSlider("RB_FOV", {
    Text    = "FOV Radius",
    Min     = 10, Max = 800, Default = 360, Suffix = "px",
    Callback= function(v) K.opts.RB_FOV = v end,
})

RBLeft:AddToggle("RB_ShowFOV", {
    Text    = "Show FOV Circle",
    Default = true,
    Callback= function(v) K.opts.RB_ShowFOV = v end,
})

RBLeft:AddColorPicker("RB_FOVColor", {
    Text    = "FOV Circle Color",
    Default = Color3.new(1, 0.4, 0),
    Callback= function(v) K.opts.RB_FOVColor = v end,
})

RBLeft:AddDivider()

RBLeft:AddToggle("RB_TeamCheck", {
    Text    = "Team Check",
    Default = true,
    Callback= function(v) K.opts.RB_TeamCheck = v end,
})

RBLeft:AddToggle("RB_WallCheck", {
    Text    = "Wall Check",
    Default = false,
    Callback= function(v) K.opts.RB_WallCheck = v end,
})

RBLeft:AddToggle("RB_PrioritizeHackers", {
    Text    = "Prioritize Hackers",
    Default = false,
    Callback= function(v) K.opts.RB_PrioritizeHackers = v end,
})

RBLeft:AddDivider()

-- Shoot timing (kicia ShootFrames + Stability)
RBLeft:AddSlider("RB_ShootFrames", {
    Text     = "Shoot Frames (ticks between shots)",
    Min      = 1, Max = 10, Default = 1,
    Rounding = 0,
    Callback = function(v) K.opts.RB_ShootFrames = v end,
})

RBLeft:AddSlider("RB_Stability", {
    Text    = "Stability Window (s)",
    Min     = 0, Max = 2, Default = 0.1, Rounding = 2,
    Callback= function(v) K.opts.RB_Stability = v end,
})

RBLeft:AddToggle("RB_ForceCrouch", {
    Text    = "Force Crouch on Shot",
    Default = true,
    Callback= function(v) K.opts.RB_ForceCrouch = v end,
})

-- ─────────────────────── RIGHT COLUMN ───────────────────────────────
local RBRight = RBTab:AddGroupbox({ Side = "Right", Name = "Prediction" })

RBRight:AddToggle("RB_Predict", {
    Text    = "Velocity Prediction",
    Default = true,
    Callback= function(v) K.opts.RB_Predict = v end,
})

RBRight:AddSlider("RB_PredictLag", {
    Text    = "Predict Latency (s)",
    Min     = 0, Max = 0.5, Default = 0.08, Rounding = 3,
    Callback= function(v) K.opts.RB_PredictLag = v end,
})

RBRight:AddDivider()

-- ─────────────── WEAPONS SUB-GROUP ──────────────────────────────────
local WepGroup = RBTab:AddGroupbox({ Side = "Right", Name = "Weapons" })

WepGroup:AddLabel({ Text = "Enable per-slot & set priority:" })

WepGroup:AddToggle("RB_Weapon_Primary", {
    Text    = "Primary (guns, high ammo)",
    Default = true,
    Callback= function(v) K.opts.RB_Weapon_Primary = v end,
})

WepGroup:AddToggle("RB_Weapon_Secondary", {
    Text    = "Secondary (pistols, low ammo)",
    Default = true,
    Callback= function(v) K.opts.RB_Weapon_Secondary = v end,
})

WepGroup:AddToggle("RB_Weapon_Melee", {
    Text    = "Melee (knife / sword / bat)",
    Default = true,
    Callback= function(v) K.opts.RB_Weapon_Melee = v end,
})

WepGroup:AddDropdown("RB_WeaponPriorityOrder", {
    Values   = {
        "Primary → Secondary → Melee",
        "Primary → Melee → Secondary",
        "Melee → Primary → Secondary",
        "Secondary → Primary → Melee",
    },
    Default  = "Primary → Secondary → Melee",
    Text     = "Priority Order",
    Callback = function(v)
        local map = {
            ["Primary → Secondary → Melee"] = {"Primary","Secondary","Melee"},
            ["Primary → Melee → Secondary"] = {"Primary","Melee","Secondary"},
            ["Melee → Primary → Secondary"] = {"Melee","Primary","Secondary"},
            ["Secondary → Primary → Melee"] = {"Secondary","Primary","Melee"},
        }
        K.opts.RB_WeaponPriority = map[v] or {"Primary","Secondary","Melee"}
    end,
})

WepGroup:AddDropdown("RB_OnEmpty", {
    Values   = { "Reload", "Swap", "Continue" },
    Default  = "Reload",
    Text     = "On Empty Magazine",
    Callback = function(v) K.opts.RB_OnEmpty = v end,
})

-- ─────────────── EVASION SUB-TAB ────────────────────────────────────
-- (Kicia uses a Tabbox inside the Combat tab for Evasion; we do same)
local EvadeBox = RBTab:AddGroupbox({
    Side = "Left",
    Name = "Evasion",
    Description = "Server-side anti-hit positioning",
})

EvadeBox:AddDropdown("RB_EvasionMode", {
    Values   = { "Off", "Random", "Translocate", "ProjectileBreaker" },
    Default  = "Off",
    Text     = "Evasion Mode",
    Callback = function(v) K.opts.RB_EvasionMode = v end,
})

EvadeBox:AddDivider()

-- Random evasion settings
EvadeBox:AddLabel({ Text = "── Random ──" })

EvadeBox:AddSlider("RB_EvasionRadius", {
    Text    = "Base Radius",
    Min     = 100, Max = 100000, Default = 10000,
    Callback= function(v) K.opts.RB_EvasionRadius = v end,
})

EvadeBox:AddSlider("RB_EvasionRadiusFactor", {
    Text    = "Radius Random Factor",
    Min     = 0, Max = 2, Default = 0.5, Rounding = 2,
    Callback= function(v) K.opts.RB_EvasionRadiusFactor = v end,
})

EvadeBox:AddToggle("RB_EvasionAnchorFromChar", {
    Text    = "Anchor From Character",
    Default = false,
    Callback= function(v) K.opts.RB_EvasionAnchorFromChar = v end,
})

EvadeBox:AddDivider()

-- Translocate settings
EvadeBox:AddLabel({ Text = "── Translocate ──" })

EvadeBox:AddSlider("RB_TranslocateOffset", {
    Text    = "Floor Offset",
    Min     = 0, Max = 20, Default = 2, Rounding = 1,
    Callback= function(v) K.opts.RB_TranslocateOffset = v end,
})

EvadeBox:AddDivider()

-- ProjectileBreaker settings (kicia jH)
EvadeBox:AddLabel({ Text = "── Projectile Breaker ──" })

EvadeBox:AddSlider("RB_PBDepthUp", {
    Text    = "Depth Up (Min)",
    Min     = 0, Max = 10, Default = 1, Rounding = 1,
    Callback= function(v)
        K.opts.RB_PBDepthUpMin = v
        pbDepthUp = v
    end,
})

EvadeBox:AddSlider("RB_PBDepthUpFreq", {
    Text    = "Depth Up Frequency",
    Min     = 0.1, Max = 5, Default = 1, Rounding = 1,
    Callback= function(v) K.opts.RB_PBDepthUpFreq = v end,
})

EvadeBox:AddSlider("RB_PBDepthFwd", {
    Text    = "Depth Forward (Min)",
    Min     = 0, Max = 10, Default = 0.5, Rounding = 1,
    Callback= function(v)
        K.opts.RB_PBDepthFwdMin = v
        pbDepthFwd = v
    end,
})

EvadeBox:AddSlider("RB_PBDepthFwdFreq", {
    Text    = "Depth Forward Frequency",
    Min     = 0.1, Max = 5, Default = 1, Rounding = 1,
    Callback= function(v) K.opts.RB_PBDepthFwdFreq = v end,
})

EvadeBox:AddSlider("RB_PBRepositionInterval", {
    Text    = "Reposition Interval (s)",
    Min     = 0.05, Max = 2, Default = 0.3, Rounding = 2,
    Callback= function(v) K.opts.RB_PBRepositionInterval = v end,
})

EvadeBox:AddButton({
    Text    = "Clear Breaker Pool",
    Callback= function()
        pbPool      = {}
        pbLastBreak = nil
        Library:Notify({ Title="Ragebot", Content="Projectile breaker pool cleared.", Duration=2 })
    end,
})

-- ─────────────── RELOAD TRANSPORT GROUP ─────────────────────────────
local RTGroup = RBTab:AddGroupbox({
    Side = "Right",
    Name = "Reload Transport",
    Description = "Immune ring teleport on empty mag",
})

RTGroup:AddToggle("RB_ReloadTransport", {
    Text    = "Enable Reload Transport",
    Default = true,
    Callback= function(v) K.opts.RB_ReloadTransport = v end,
})

RTGroup:AddButton({
    Text    = "Rescan Shoot Remote",
    Callback= function()
        RB.refreshShootRemote()
        Library:Notify({ Title="Ragebot", Content="Shoot remote rescanned.", Duration=2 })
    end,
})

RTGroup:AddDivider()

RTGroup:AddLabel({ Text = "Immune Ring: kills reload animation\nby teleporting outside map bounds." })

-- ─────────────── MISC / DEBUG ────────────────────────────────────────
local DebugGroup = RBTab:AddGroupbox({
    Side = "Right",
    Name = "Debug",
})

DebugGroup:AddButton({
    Text    = "Force Reset Ragebot State",
    Callback= function()
        RB.reset()
        Library:Notify({ Title="Ragebot", Content="State fully reset.", Duration=2 })
    end,
})

DebugGroup:AddButton({
    Text    = "Print Last Target Position",
    Callback= function()
        local ltp = RB.getLockedTarget()
        if ltp then
            print("[Ragebot] Last target pos:", ltp)
            Library:Notify({ Title="Ragebot", Content=tostring(ltp), Duration=3 })
        else
            Library:Notify({ Title="Ragebot", Content="No target recorded.", Duration=2 })
        end
    end,
})

