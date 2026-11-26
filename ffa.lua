local Players           = game:GetService("Players")
local RS                = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local lp                = Players.LocalPlayer
local UIS               = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Workspace         = game:GetService("Workspace")

if game.CreatorId ~= 3461453 then lp:Kick("Not Supported game") return end
repeat task.wait() until game:IsLoaded() and lp.Character

local Trove = {}
Trove.__index = Trove
function Trove.new(name) return setmetatable({ _name = name, _items = {}, _cleaning = false }, Trove) end
local function cleanItem(o)
    local t = typeof(o)
    if t == "RBXScriptConnection" then pcall(function() o:Disconnect() end)
    elseif t == "Instance" then pcall(function() o:Destroy() end)
    elseif t == "thread" then pcall(task.cancel, o)
    elseif type(o) == "function" then pcall(o)
    elseif type(o) == "table" then
        local d = o.Destroy or o.Disconnect
        if type(d) == "function" then pcall(d, o) end
    end
end
function Trove:Add(o) table.insert(self._items, o); return o end
function Trove:Connect(sig, fn) return self:Add(sig:Connect(fn)) end
function Trove:Clean()
    if self._cleaning then return end
    self._cleaning = true
    local items = self._items; self._items = {}
    for i = #items, 1, -1 do cleanItem(items[i]) end
    self._cleaning = false
end
Trove.Destroy = Trove.Clean
local MainTrove = Trove.new("Kicia")

pcall(function()
    if setfflag then
        setfflag("DFIntS2PhysicsSenderRate", "240")
        setfflag("DFIntAssemblyHistoryBufferSize", "2147483648")
        setfflag("DFIntAssemblyHistorySkipSize", "0")
    end
end)

local EnumLibrary = require(RS.Modules.EnumLibrary)
local UseItem     = RS.Remotes.Replication.Fighter:WaitForChild("UseItem", 10)
local FC          = require(lp.PlayerScripts.Controllers:WaitForChild("FighterController", 30))
local function localFighter() return FC and FC.LocalFighter end

local Utility
pcall(function() Utility = require(RS.Modules.Utility) end)

local _to_enum = rawget(EnumLibrary, "_to_enum")
local _from_enum = rawget(EnumLibrary, "_from_enum")
local function toEnum(name)
    if _to_enum then return _to_enum[name] end
    local ok, v = pcall(function() return EnumLibrary:ToEnum(name) end)
    if ok and v ~= nil then return v end
    return nil
end
local START_SHOOTING = toEnum("StartShooting")

-- ============================================================
-- CONFIG
-- ============================================================
local AXIS = {
    TP_HEAD_OFFSET     = 5.0,
    TP_WRITES          = 8,
    STICKY_LOCK        = true,
    STICKY_FRAMES      = 4,
    HOVER_MAINTAIN     = true,

    PREDICTION_STRENGTH = 1.0,
    MAX_PING            = 0.3,

    TeamCheck           = true,
    CheckKatanaDeflect  = true,
    CheckRiotShield     = true,
    ProtectionCacheTime = 0.25,
    NEAR_OTHER_MATCH_R  = 1000,

    VOID_MAX           = 1000000,
    VOID_MIN_Y         = 5000,

    AUTO_HEAL          = true,
    AUTO_AMMO          = true,
    AUTO_HEAL_THRESHOLD = 25,

    -- >>> Burst (like asdasd.txt)
    BurstCount         = 4,
    ModNoSpread        = false,   -- payload flag ile yapılıyor, input hook gerekmiyor
    ModAutomatic       = false,   -- client input bypass, animasyon yok

    AimbotEnabled      = true,
    SilentRapidInterval = 0.03,
    TriggerbotEnabled  = true,
    TriggerReaction    = 0,
    IgnoreFOV          = true,
    FOVRadius          = 282,
    HarionFastShoot    = true,
    ModAttackSpeed     = true,
    ModAttackSpeedBoost = 85,
    ModFasterReload    = true,
    ModReloadBoost     = 20,
    ModFasterADS       = true,
    ModADSBoost        = 85,
    ModFasterEquip     = true,
    ModEquipBoost      = 80,
    IgnoreAimbotWeapons = { ["Flare Gun"]=true, ["Freeze Ray"]=true, ["Grenade Launcher"]=true, ["RPG"]=true },
}
local CONFIG = AXIS

local function clampNum(v, lo, hi, def)
    if typeof(v) ~= "number" or v ~= v then v = def end
    return math.clamp(v, lo, hi)
end

-- Respawn spam
local RespawnNow
pcall(function()
    RespawnNow = RS:WaitForChild("Remotes", 15):WaitForChild("Duels", 15):WaitForChild("RespawnNow", 15)
end)
task.spawn(function()
    while true do
        if RespawnNow then pcall(function() RespawnNow:FireServer() end) end
        task.wait(0.1)
    end
end)

pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)
task.spawn(function() while true do task.wait(0.5) pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end) end end)

-- ============================================================
-- FAST CFrame
-- ============================================================
local _ni_cache, _ni_checked = nil, false
local function getHRPNewIndex(hrp)
    if not _ni_checked then
        local mt = getrawmetatable(hrp)
        _ni_cache = mt and rawget(mt, "__newindex")
        _ni_checked = true
    end
    return _ni_cache
end
local V0 = Vector3.zero
local function fastSetCF(hrp, cf)
    local ni = getHRPNewIndex(hrp)
    if ni then
        pcall(ni, hrp, "AssemblyLinearVelocity", V0)
        pcall(ni, hrp, "AssemblyAngularVelocity", V0)
        pcall(ni, hrp, "CFrame", cf)
        pcall(ni, hrp, "AssemblyLinearVelocity", V0)
        pcall(ni, hrp, "AssemblyAngularVelocity", V0)
    else
        pcall(function()
            hrp.AssemblyLinearVelocity = V0
            hrp.AssemblyAngularVelocity = V0
            hrp.CFrame = cf
        end)
    end
    if sethiddenproperty then
        pcall(sethiddenproperty, hrp, "CFrame", cf)
        pcall(sethiddenproperty, hrp, "AssemblyLinearVelocity", V0)
        pcall(sethiddenproperty, hrp, "AssemblyAngularVelocity", V0)
    end
end
local function stickySetCF(hrp, cf)
    for _ = 1, CONFIG.TP_WRITES do fastSetCF(hrp, cf) end
end
local stickyLockUntil, stickyCF = 0, nil
local function beginStickyLock(hrp, cf)
    if not CONFIG.STICKY_LOCK then return end
    stickyCF = cf
    stickyLockUntil = tick() + (CONFIG.STICKY_FRAMES * (1/60))
end

-- ============================================================
-- VIM
-- ============================================================
local VIM = nil
local function getVIM()
    if VIM then return VIM end
    local ok, v = pcall(function() return Instance.new("VirtualInputManager") end)
    if ok and v then VIM = v end
    return VIM
end
local function pressKey(kc)
    task.spawn(function()
        local v = getVIM(); if not v then return end
        pcall(function() v:SendKeyEvent(true, kc, false, game) end)
        task.wait(0.03)
        pcall(function() v:SendKeyEvent(false, kc, false, game) end)
    end)
end
local slotKey = { [1] = Enum.KeyCode.One, [2] = Enum.KeyCode.Two }

-- ============================================================
-- FORWARD DECL
-- ============================================================
local isTeamMate, getCurrentSlot, isEquipping, isReloading, handleAmmo, hasAnyLiveEnemy, itemGet, canAttack

-- ============================================================
-- VOID
-- ============================================================
local voidActive = false
local voidTargetPos = nil
local function randomVoidPos()
    return Vector3.new(math.random(-CONFIG.VOID_MAX, CONFIG.VOID_MAX), math.random(CONFIG.VOID_MIN_Y, CONFIG.VOID_MAX), math.random(-CONFIG.VOID_MAX, CONFIG.VOID_MAX))
end
local function goVoid(hrp)
    if not voidTargetPos then voidTargetPos = randomVoidPos() end
    stickyCF = nil; stickyLockUntil = 0
    hrp.CFrame = CFrame.new(voidTargetPos)
    hrp.AssemblyLinearVelocity = V0
    hrp.AssemblyAngularVelocity = V0
end
local function exitVoid()
    voidTargetPos = nil; stickyCF = nil; stickyLockUntil = 0
end

-- ============================================================
-- ITEM HELPERS
-- ============================================================
itemGet = function(item, key)
    if not item then return nil end
    local ok, v = pcall(function() return item:Get(key) end)
    if ok and v ~= nil then return v end
    return rawget(item, key)
end
local function itemAmmo(item)
    local a = itemGet(item, "Ammo")
    if a == nil and type(item) == "table" then
        local d = rawget(item, "Data")
        a = type(d) == "table" and rawget(d, "Ammo") or nil
    end
    return a
end
local function itemReserve(item)
    local r = itemGet(item, "AmmoReserve")
    if r == nil and type(item) == "table" then
        local d = rawget(item, "Data")
        r = type(d) == "table" and rawget(d, "AmmoReserve") or nil
    end
    return r
end
local function itemIsReloading(item)
    if type(item) ~= "table" then return false end
    local now = tick()
    local c = rawget(item, "_reload_cooldown"); if type(c) == "number" and now < c then return true end
    local n = rawget(item, "_shoot_cooldown_no_ammo"); return type(n) == "number" and now < n
end
local function isGunItem(item)
    if type(item) ~= "table" then return false end
    local info = rawget(item, "Info"); if type(info) ~= "table" then return false end
    return (rawget(info, "Type") or rawget(info, "Class")) == "Gun"
end

-- ============================================================
-- Equip state
-- ============================================================
isEquipping = function()
    local f = localFighter(); if not f then return false end
    local item = f.EquippedItem
    local c = type(item) == "table" and rawget(item, "_equip_cooldown") or nil
    return type(c) == "number" and tick() < c
end
isReloading = function()
    local f = localFighter(); if not f then return false end
    local item = f.EquippedItem; if type(item) ~= "table" then return false end
    local info = rawget(item, "Info")
    local t = type(info) == "table" and (rawget(info, "Type") or rawget(info, "Class")) or nil
    if t ~= "Gun" then return false end
    if f.IsReloading == true or f.Reloading == true then return true end
    return itemIsReloading(item)
end
getCurrentSlot = function()
    local f = localFighter(); if not f then return nil end
    local item = f.EquippedItem; if type(item) ~= "table" then return nil end
    return tonumber(itemGet(item, "Slot")) or 1
end
hasAnyLiveEnemy = function()
    local myEnv = lp:GetAttribute("EnvironmentID")
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and not isTeamMate(plr) then
            local char = plr.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 and plr:GetAttribute("EnvironmentID") == myEnv then return true end
        end
    end
    return false
end

-- ============================================================
-- SLOT / AMMO
-- ============================================================
local lastSlotSwitch = 0
local function ensureGunEquipped()
    local slot = getCurrentSlot()
    if slot == 1 or slot == 2 then return slot end
    if isEquipping() then return nil end
    if tick() - lastSlotSwitch < 0.3 then return nil end
    lastSlotSwitch = tick()
    pressKey(slotKey[1])
    return nil
end
local lastAmmoAction = 0
handleAmmo = function()
    if isReloading() then return true end
    local f = localFighter(); if not f then return false end
    local item = f.EquippedItem; if type(item) ~= "table" then return false end
    if isEquipping() then return true end
    local ammo = itemAmmo(item)
    if type(ammo) ~= "number" or ammo > 0 then return false end
    if tick() - lastAmmoAction < 0.5 then return true end
    lastAmmoAction = tick()
    local slot = tonumber(itemGet(item, "Slot")) or 1
    if slot == 1 then
        pressKey(slotKey[2])
    else
        pressKey(slotKey[1])
        task.delay(0.3, function()
            local f2 = localFighter(); if not f2 then return end
            local it2 = f2.EquippedItem; if type(it2) ~= "table" then return end
            if (tonumber(itemGet(it2, "Slot")) or 1) == 1 and (itemAmmo(it2) or 0) <= 0 then
                pressKey(Enum.KeyCode.R)
            end
        end)
    end
    return true
end

-- ============================================================
-- AUTO PICKUP
-- ============================================================
local Drops = {}
local function dropKind(drop)
    if not drop:IsA("BasePart") or drop.Name ~= "_drop" then return nil end
    if drop:FindFirstChild("Health") then return "Health" end
    if drop:FindFirstChild("AmmoBalanced") or drop:FindFirstChild("Ammo") then return "Ammo" end
    return nil
end
local function watchDrop(c) if c.Name == "_drop" and c:IsA("BasePart") then Drops[c] = true end end
for _, c in ipairs(workspace:GetChildren()) do watchDrop(c) end
MainTrove:Connect(workspace.ChildAdded, watchDrop)
MainTrove:Connect(workspace.ChildRemoved, function(c) Drops[c] = nil end)

local function pickupTouchPart()
    local char = lp.Character
    return char and (char:FindFirstChild("HitboxBody") or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart"))
end
local function nearestDrop(kind, touchPart)
    local best, bestD
    for drop in pairs(Drops) do
        if drop.Parent ~= workspace then Drops[drop] = nil
        elseif dropKind(drop) == kind and drop.CanTouch and drop:FindFirstChildOfClass("TouchTransmitter") then
            local d = (drop.Position - touchPart.Position).Magnitude
            if not bestD or d < bestD then best, bestD = drop, d end
        end
    end
    return best
end
local function touchDrop(drop, touchPart)
    if type(firetouchinterest) ~= "function" then return false end
    pcall(firetouchinterest, touchPart, drop, 0)
    task.defer(function()
        if drop.Parent and touchPart.Parent then pcall(firetouchinterest, touchPart, drop, 1) end
    end)
    return true
end

MainTrove:Add(task.spawn(function()
    while true do
        task.wait(0.05)
        if not (CONFIG.AUTO_HEAL or CONFIG.AUTO_AMMO) then continue end
        local char = lp.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local touchPart = pickupTouchPart()
        if not hum or not touchPart then continue end
        local didAction = false
        if CONFIG.AUTO_HEAL then
            local hp, maxHp = hum.Health, hum.MaxHealth
            if (maxHp - hp) >= CONFIG.AUTO_HEAL_THRESHOLD then
                local drop = nearestDrop("Health", touchPart)
                if drop and touchDrop(drop, touchPart) then didAction = true end
            end
        end
        if not didAction and CONFIG.AUTO_AMMO then
            local f = localFighter()
            local item = f and f.EquippedItem
            local a = itemAmmo(item)
            if type(a) == "number" and a <= 0 then
                local drop = nearestDrop("Ammo", touchPart)
                if drop then touchDrop(drop, touchPart) end
            end
        end
    end
end))

-- ============================================================
-- ENEMY TRACKER + PREDICTION
-- ============================================================
local enemyTrackers    = setmetatable({}, { __mode = "k" })
local enemyTrackerChar = setmetatable({}, { __mode = "k" })
local MAX_TRACK = 8

local function updateEnemyTracker(plr)
    local char = plr.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local t = enemyTrackers[plr]
    if not t or enemyTrackerChar[plr] ~= char then
        t = { positions = {}, cframes = {}, times = {} }
        enemyTrackers[plr] = t; enemyTrackerChar[plr] = char
    end
    local now = workspace:GetServerTimeNow()
    table.insert(t.positions, root.Position)
    table.insert(t.cframes, root.CFrame)
    table.insert(t.times, now)
    while #t.positions > MAX_TRACK do
        table.remove(t.positions, 1); table.remove(t.cframes, 1); table.remove(t.times, 1)
    end
end

local function getPredictedState(plr)
    local char = plr.Character
    local fbPos, fbCF = V0, CFrame.new()
    if char then
        local root = char:FindFirstChild("HumanoidRootPart")
        if root then fbPos, fbCF = root.Position, root.CFrame end
    end
    local t = enemyTrackers[plr]
    if not t or #t.positions < 2 then
        return { Position = fbPos, CFrame = fbCF, Velocity = V0, PredictionTime = 0, RealPosition = fbPos, RealCFrame = fbCF }
    end
    local n = #t.positions
    local totalW, sumVel = 0, V0
    for i = 2, n do
        local dt = t.times[i] - t.times[i-1]
        if dt > 0.001 then
            local v = (t.positions[i] - t.positions[i-1]) / dt
            local w = i - 1
            sumVel = sumVel + v * w; totalW = totalW + w
        end
    end
    local avgVel = totalW > 0 and (sumVel / totalW) or V0
    local lastPos, lastCF, lastT = t.positions[n], t.cframes[n], t.times[n]
    local sampleAge = math.max(0, workspace:GetServerTimeNow() - lastT)
    local rawPing = lp:GetNetworkPing()
    local rtt = rawPing > 1 and (rawPing / 1000) or rawPing
    local predTime = math.clamp((rtt + sampleAge) * CONFIG.PREDICTION_STRENGTH, 0, CONFIG.MAX_PING)
    return {
        Position = lastPos + avgVel * predTime,
        CFrame = lastCF, Velocity = avgVel, PredictionTime = predTime,
        RealPosition = lastPos, RealCFrame = lastCF,
    }
end

-- ============================================================
-- TEAMCHECK (AUTOSHOT)
-- ============================================================
local function getTeamData(plr)
    if not plr or not plr.Character then return nil end
    local hl = plr.Character:FindFirstChildOfClass("Highlight")
    if hl then return { Type = "Highlight", R = hl.FillColor.R, G = hl.FillColor.G, B = hl.FillColor.B } end
    local teamId = plr:GetAttribute("TeamID")
    if teamId and tostring(teamId) ~= "" then return { Type = "Attribute", Value = tostring(teamId) } end
    for _, v in ipairs(plr.Character:GetChildren()) do
        local n = v.Name:lower()
        if (n:find("team") or n:find("faction")) and v:IsA("ValueBase") then
            return { Type = "Value", Value = tostring(v.Value) }
        end
    end
    return nil
end

isTeamMate = function(plr)
    if not plr or plr == lp then return true end
    if not CONFIG.TeamCheck then return false end
    if lp.Team ~= nil and plr.Team ~= nil and lp.Team == plr.Team then return true end
    local myT, theirT = getTeamData(lp), getTeamData(plr)
    if myT and theirT then
        if myT.Type == "Highlight" and theirT.Type == "Highlight" then
            local diff = math.abs(myT.R - theirT.R) + math.abs(myT.G - theirT.G) + math.abs(myT.B - theirT.B)
            if diff < 0.2 then return true end
        elseif myT.Value and theirT.Value and myT.Value == theirT.Value then
            return true
        end
    end
    return false
end

local function hasAllyLabels(plr)
    local char = plr.Character; if not char then return false end
    for _, n in ipairs({"HumanoidRootPart","Head","HitboxHead","HitboxBody"}) do
        local part = char:FindFirstChild(n)
        if part then
            for _, l in ipairs({"AllyLabel","TeammateLabel","TeamLabel","FriendLabel"}) do
                if part:FindFirstChild(l) then return true end
            end
        end
    end
    return false
end

-- ============================================================
-- PROTECTION
-- ============================================================
local SPAWN_TAGS = { "SpawnProtection","SpawnShield","Immune","Invincible","Protected","SpawnImmune","GodMode","SpawnImmunity" }
local CHAR_ATTRS = { "SpawnProtection","Protected","Invincible","IsInvincible","SpawnShield","Immune","SpawnImmune","GodMode","ImmuneUntil" }
local HUM_ATTRS  = { "SpawnProtection","Protected","Invincible","IsInvincible","Immune","Spawning" }
local PLR_ATTRS  = { "SpawnProtection","Protected","Invincible","IsInvincible","Immune","SpawnShield" }

local function computeProtection(char)
    if not char then return true end
    if char:FindFirstChildWhichIsA("ForceField", true) then return true end
    for _, a in ipairs(CHAR_ATTRS) do
        local v = char:GetAttribute(a)
        if v == true or (typeof(v) == "number" and v > tick()) then return true end
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        for _, a in ipairs(HUM_ATTRS) do if hum:GetAttribute(a) == true then return true end end
        local st = hum:GetState()
        if st == Enum.HumanoidStateType.GettingUp or st == Enum.HumanoidStateType.Physics then return true end
    end
    local plr = Players:GetPlayerFromCharacter(char)
    if plr then for _, a in ipairs(PLR_ATTRS) do if plr:GetAttribute(a) == true then return true end end end
    for _, tag in ipairs(SPAWN_TAGS) do
        if CollectionService:HasTag(char, tag) or (hum and CollectionService:HasTag(hum, tag)) then return true end
    end
    for _, c in ipairs(char:GetChildren()) do
        local nm = c.Name:lower()
        if nm:find("immune") or nm:find("invincible")
           or (nm:find("spawn") and (nm:find("shield") or nm:find("protect"))) then return true end
    end
    if plr then
        local ok, fighter = pcall(function() return FC:GetFighter(plr) end)
        if ok and fighter then
            if fighter.Entity then
                local okE, inv = pcall(function() return fighter.Entity:Get("IsInvincible") end)
                if okE and inv == true then return true end
            end
            local d = fighter.Data
            if d and (d.IsInvincible == true or d.SpawnProtection == true) then return true end
        end
    end
    return false
end

local protCache = setmetatable({}, { __mode = "k" })
local function hasProtection(char)
    if not char then return true end
    local now, e = tick(), protCache[char]
    if e and now - e.t < CONFIG.ProtectionCacheTime then return e.v end
    local ok, v = pcall(computeProtection, char)
    v = (not ok) or v
    protCache[char] = { t = now, v = v }
    return v
end

-- ============================================================
-- KATANA DEFLECT / SHIELD
-- ============================================================
local function getFighter(plr)
    local ok, f = pcall(function() return FC:GetFighter(plr) end)
    return ok and f or nil
end
local DEFLECT_BYPASS = { ["Slingshot"]=true,["Bow"]=true,["Exogun"]=true,["Spray"]=true,["Flamethrower"]=true,["Grenade Launcher"]=true,["RPG"]=true,["Crossbow"]=true,["Daggers"]=true }
local SHIELD_PIERCE  = { ["Flamethrower"]=true,["Exogun"]=true,["Spray"]=true,["Chainsaw"]=true,["Grenade Launcher"]=true }

local function isKatanaDeflecting(item)
    if type(item) ~= "table" or item.Name ~= "Katana" then return false end
    local now = tick()
    local ac = rawget(item, "_attack_cooldown"); local dc = rawget(item, "_deflect_cooldown"); local dh = rawget(item, "_deflect_hash")
    return type(ac) == "number" and ac > now and type(dc) == "number" and dc > now and type(dh) == "number" and dh % 2 == 1
end
local function inventoryItemName(item)
    local t = typeof(item)
    if t == "string" then return item ~= "" and item or nil end
    if t == "Instance" then return item.Name end
    if t ~= "table" then return nil end
    if type(item.Name) == "string" and item.Name ~= "" then return item.Name end
    local info = item.Info
    if type(info) == "table" and type(info.Name) == "string" then return info.Name end
    return nil
end
local function fighterLoadoutNames(f)
    local names = {}
    local inv = f and (f.Loadout or f.Slots or f.Items or f.EquippedItems)
    if type(inv) == "table" then for _, it in pairs(inv) do local n = inventoryItemName(it); if n then names[n] = true end end end
    local last = f and f.Data and f.Data.LastPickedWeapons
    if type(last) == "table" then for _, n in ipairs(last) do names[n] = true end end
    return names
end
local function isDeflectBlocked(plr, localItem)
    if not CONFIG.CheckKatanaDeflect then return false end
    if localItem and DEFLECT_BYPASS[localItem.Name] then return false end
    local f = getFighter(plr); return isKatanaDeflecting(f and f.EquippedItem)
end
local function isShieldBlocked(plr, char, localItem, observerPos)
    if not CONFIG.CheckRiotShield then return false end
    if localItem and SHIELD_PIERCE[localItem.Name] then return false end
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local f = getFighter(plr)
    if not root or not f or typeof(observerPos) ~= "Vector3" then return false end
    local equipped = inventoryItemName(f.EquippedItem)
    local hasShield = fighterLoadoutNames(f)["Riot Shield"] == true
    local toLocal = observerPos - root.Position
    toLocal = toLocal.Magnitude > 0.001 and toLocal.Unit or root.CFrame.LookVector
    local dot = root.CFrame.LookVector:Dot(toLocal)
    if equipped == "Riot Shield" and dot >= 0 then return true end
    if hasShield and equipped and equipped ~= "Riot Shield" and dot <= 0 then return true end
    return false
end

-- ============================================================
-- FILTER
-- ============================================================
local function getRoot(char) return char and char:FindFirstChild("HumanoidRootPart") end
local function scanWeapon(plr)
    local vms = workspace:FindFirstChild("ViewModels"); if not vms then return "" end
    for _, model in ipairs(vms:GetChildren()) do
        if model:IsA("Model") then
            local sp = model.Name:find(" - ", 1, true)
            if sp and model.Name:sub(1, sp-1) == plr.Name then return model.Name:sub(sp+3):lower() end
        end
    end
    return ""
end
local function isNearOtherMatch(pos, ignore)
    if typeof(pos) ~= "Vector3" then return false end
    local myEnv = lp:GetAttribute("EnvironmentID")
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and plr ~= ignore and plr:GetAttribute("EnvironmentID") ~= myEnv then
            local r = getRoot(plr.Character)
            if r and (r.Position - pos).Magnitude <= CONFIG.NEAR_OTHER_MATCH_R then return true end
        end
    end
    return false
end
local function isShootingRange()
    for _, obj in ipairs({workspace, lp}) do
        for _, attr in ipairs({"ShootingRange","Mode","Map","MapName"}) do
            local v = obj:GetAttribute(attr)
            if v == true and attr == "ShootingRange" then return true end
            if type(v) == "string" then
                local t = v:lower():gsub("[%s_%-]", "")
                if t:find("shootingrange", 1, true) or t:find("firingrange", 1, true) then return true end
            end
        end
    end
    return false
end

canAttack = function(plr)
    if plr == lp or isTeamMate(plr) then return false end
    local myEnv = lp:GetAttribute("EnvironmentID")
    if not myEnv or plr:GetAttribute("EnvironmentID") ~= myEnv then return false end
    local char = plr.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    if hasProtection(char) then return false end
    if hasAllyLabels(plr) then return false end
    if isDeflectBlocked(plr, nil) then return false end
    local myHrp = getRoot(lp.Character)
    if isShieldBlocked(plr, char, nil, myHrp and myHrp.Position) then return false end
    local r = getRoot(char)
    if r and isNearOtherMatch(r.Position, plr) then return false end
    return true
end

local function findBestTarget(pos)
    local best, bestV = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if canAttack(plr) then
            local root = getRoot(plr.Character)
            if root then
                local v = (root.Position - pos).Magnitude
                if root.Position.Magnitude > 1000000 then v = v - 2000000000 end
                if scanWeapon(plr) ~= "" then v = v - 1000000000 end
                if v < bestV then bestV = v; best = { Player = plr, Root = root, Char = plr.Character } end
            end
        end
    end
    return best
end

-- ============================================================
-- WEAPON MODS (AUTOSHOT - arka plan)
-- ============================================================
local HOOKS = {}
local function playerModule(...)
    local node = lp:FindFirstChild("PlayerScripts")
    for _, n in ipairs({"Modules", ...}) do node = node and node:FindFirstChild(n) end
    if not node then return nil end
    local ok, m = pcall(require, node)
    return (ok and type(m) == "table") and m or nil
end
local function wrapModuleFn(mod, name, makeWrapper)
    if type(mod) ~= "table" then return false end
    HOOKS[mod] = HOOKS[mod] or {}
    local orig = HOOKS[mod][name] or rawget(mod, name)
    if type(orig) ~= "function" then return false end
    HOOKS[mod][name] = orig
    mod[name] = makeWrapper(orig)
    return true
end
local function attackSpeedScale()
    if not CONFIG.ModAttackSpeed then return 1 end
    return 1 / (1 + clampNum(CONFIG.ModAttackSpeedBoost, 0, 85, 85) / 100)
end
local function callWithScaledInfo(info, fields, scale, minValue, fn, ...)
    local saved = {}
    if type(info) == "table" and scale < 0.999 then
        for _, f in ipairs(fields) do
            local v = info[f]
            if type(v) == "number" then saved[f] = v; info[f] = math.max(minValue, v * scale) end
        end
    end
    local res = table.pack(pcall(fn, ...))
    for f, v in pairs(saved) do info[f] = v end
    if not res[1] then return table.pack() end
    return table.pack(table.unpack(res, 2, res.n))
end
local function shootItem(self)
    if type(self) == "table" and type(self.Name) == "string" and self.Name ~= "" then return self end
    local it = localFighter() and localFighter().EquippedItem
    if type(it) == "table" and type(it.Name) == "string" and it.Name ~= "" then return it end
    return nil
end

local function installGunHooks()
    local gun = playerModule("ItemTypes", "Gun")
    if not gun then return false end
    wrapModuleFn(gun, "StartShooting", function(orig)
        return function(self, ...)
            local item = shootItem(self)
            if not item then return nil end
            local r = callWithScaledInfo(item.Info, {"ShootCooldown","ShootBurstCooldown","QuickShotCooldown"}, attackSpeedScale(), 0.001, orig, item, ...)
            return table.unpack(r, 1, r.n)
        end
    end)
    return true
end

-- FAST SHOOT
local fastShootCache = setmetatable({}, { __mode = "k" })
local FAST_KEYS = {"ShootCooldown","QuickShotCooldown","SpinCooldown","DashCooldown","Cooldown","BuildCooldown","AttackCooldown","HeavyAttackCooldown","BurstCooldown"}
local function rememberFS(info, key)
    if info[key] == nil then return nil end
    local c = fastShootCache[info]; if not c then c = {}; fastShootCache[info] = c end
    if c[key] == nil then c[key] = info[key] end
    return c[key]
end
local function applyFS(info, fast)
    local recoil = rememberFS(info, "ShootRecoil"); if recoil ~= nil then info.ShootRecoil = fast and 0 or recoil end
    local spread = rememberFS(info, "ShootSpread"); if spread ~= nil then info.ShootSpread = fast and 0 or spread end
    local speed = rememberFS(info, "ProjectileSpeed"); if speed ~= nil then info.ProjectileSpeed = fast and 99999999 or speed end
    for _, key in ipairs(FAST_KEYS) do
        local orig = rememberFS(info, key)
        if orig ~= nil then info[key] = fast and 0 or orig end
    end
end

local ModsInstalled = { Gun = false }
local function refreshMods()
    if not ModsInstalled.Gun then ModsInstalled.Gun = installGunHooks() end
    if CONFIG.HarionFastShoot then
        local f = localFighter()
        local items = type(f) == "table" and rawget(f, "Items") or nil
        if type(items) == "table" then
            for _, it in pairs(items) do
                local info = type(it) == "table" and it.Info or nil
                if type(info) == "table" then pcall(applyFS, info, true) end
            end
        end
    end
end
MainTrove:Add(task.spawn(function() while true do task.wait(1); pcall(refreshMods) end end))

-- ============================================================
-- PAYLOAD (asdasd.txt format)
-- ============================================================
local MUZZLE_CF = CFrame.new(0.43, 0.25, 0.42)
local function encodeCF(cf)
    if Utility and Utility.EncodeCFrame then
        local ok, r = pcall(function() return Utility:EncodeCFrame(cf) end)
        if ok and r ~= nil then return r end
    end
    return cf
end

-- asdasd.txt birebir format
local function fireAt(shootPos, targetPart)
    local item = localFighter() and localFighter().EquippedItem
    if not item then return end
    local oid = itemGet(item, "ObjectID")
    if not oid then return end
    if not targetPart or not targetPart.Parent then return end

    local aimCF = encodeCF(CFrame.new(shootPos, targetPart.Position))
    local muzzle = encodeCF(MUZZLE_CF)
    local data = {
        [utf8.char(1)] = {
            [utf8.char(0)] = aimCF,
            [utf8.char(1)] = aimCF,
            [utf8.char(2)] = targetPart,
            [utf8.char(3)] = muzzle,
        },
    }
    -- No spread flag (asdasd.txt)
    data[utf8.char(2)] = true

    for _ = 1, math.clamp(CONFIG.BurstCount or 4, 1, 10) do
        pcall(function() UseItem:FireServer(oid, START_SHOOTING, data, nil) end)
    end
end

-- ============================================================
-- TARGET LOCK — ölmeden geçme
-- ============================================================
local lockedTargetPlayer = nil
local lockedTargetChar = nil
local lastGroundPos = nil

local function isTargetStillAlive(plr, char)
    if not plr or not char or not char.Parent then return false end
    if plr.Character ~= char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local myEnv = lp:GetAttribute("EnvironmentID")
    if not myEnv or plr:GetAttribute("EnvironmentID") ~= myEnv then return false end
    return true
end

local cachedEnemy, cachedEnemyAt = nil, 0
local function getLockedOrClosestEnemy()
    -- Lock varsa ve hâlâ canlıysa koru
    if lockedTargetPlayer and lockedTargetChar then
        if isTargetStillAlive(lockedTargetPlayer, lockedTargetChar) then
            local root = lockedTargetChar:FindFirstChild("HumanoidRootPart")
            if root then
                return {
                    Player = lockedTargetPlayer,
                    Root = root,
                    Char = lockedTargetChar,
                }
            end
        end
        -- Hedef öldü / ayrıldı -> unlock
        lockedTargetPlayer = nil
        lockedTargetChar = nil
    end

    -- Yeni hedef bul
    local now = tick()
    if now - cachedEnemyAt < 0.05 then
        if cachedEnemy and canAttack(cachedEnemy.Player) then
            lockedTargetPlayer = cachedEnemy.Player
            lockedTargetChar = cachedEnemy.Char
            return cachedEnemy
        end
        cachedEnemy, cachedEnemyAt = nil, 0
    end
    cachedEnemyAt = now

    local searchFrom = lastGroundPos
    if not searchFrom then
        local lpRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        searchFrom = lpRoot and lpRoot.Position
    end
    if not searchFrom then return nil end

    local enemy = findBestTarget(searchFrom)
    if enemy then
        lockedTargetPlayer = enemy.Player
        lockedTargetChar = enemy.Char
    end
    cachedEnemy = enemy
    return enemy
end

-- ============================================================
-- HOVER
-- ============================================================
local function maintainHover(hrp)
    if not CONFIG.HOVER_MAINTAIN or not hrp then return end
    local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end) end
    hrp.AssemblyLinearVelocity = V0
    hrp.AssemblyAngularVelocity = V0
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
MainTrove:Connect(RunService.Heartbeat, function()
    local now    = tick()
    local lpRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not lpRoot then return end

    maintainHover(lpRoot)

    if isShootingRange() then return end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then updateEnemyTracker(plr) end
    end

    local f = localFighter()
    if not f then return end

    -- VOID: reload OR all-dead (lock sıfırla)
    if isReloading() or not hasAnyLiveEnemy() then
        voidActive = true
        lockedTargetPlayer = nil
        lockedTargetChar = nil
        goVoid(lpRoot)
        return
    end

    if voidActive then
        voidActive = false
        exitVoid()
    end

    -- Sticky lock (önceki TP kalıntısı)
    if CONFIG.STICKY_LOCK and stickyCF and now < stickyLockUntil then
        stickySetCF(lpRoot, stickyCF)
    end

    -- Ensure gun
    local slot = ensureGunEquipped()
    if not slot then return end

    -- Ammo
    if handleAmmo() then return end

    -- Target lock'tan al (öldürmeden başka düşmana geçmez)
    local enemy = getLockedOrClosestEnemy()
    if not enemy then return end

    local item = f.EquippedItem
    if not isGunItem(item) then return end

    -- Full HS: her zaman head
    local targetHead = enemy.Char:FindFirstChild("HitboxHead")
        or enemy.Char:FindFirstChild("Head")
        or enemy.Root
    if not targetHead then return end

    -- >>> Hedef protected olsa bile LOCK KORUNUR, sadece ateş etme
    if hasProtection(enemy.Char) then
        return
    end

    -- Kirli filtreler — hâlâ canlı mı bir kez daha kontrol
    if not enemy.Root.Parent or enemy.Player.Character ~= enemy.Char then return end

    local predState = getPredictedState(enemy.Player)
    if isNearOtherMatch(predState.RealPosition, enemy.Player) then return end

    -- Head + prediction offset
    local posOffset = predState.Position - predState.RealPosition
    local headPos = targetHead.Position + posOffset

    -- TP: head'in tam 5 stud yukarısı (XZ aynı)
    local tpPos = Vector3.new(headPos.X, headPos.Y + CONFIG.TP_HEAD_OFFSET, headPos.Z)
    local tpCF = CFrame.lookAt(tpPos, headPos)

    -- STRONG TP
    stickySetCF(lpRoot, tpCF)
    beginStickyLock(lpRoot, tpCF)
    lastGroundPos = lpRoot.Position

    -- >>> asdasd.txt stili burst fire (no-spread payload içinde, animasyon yok)
    fireAt(tpPos, targetHead)
end)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local CameraController = require(
    player.PlayerScripts.Controllers.CameraController
)

local SPEED = 0
local PITCH = math.rad(-90)

local angle = 0

RunService.RenderStepped:Connect(function(dt)
    angle = (angle + SPEED * dt) % (math.pi * 2)

    CameraController.Rotation = Vector2.new(
        PITCH,
        angle
    )
end)
-- ============================================================
-- AXIS — 7 FEATURE BUILD (Minimal ON/OFF UI)
-- 15 saniyelik gecikme eklendi
-- ============================================================

-- >>> 15 SANİYE BEKLEME <<<
do
    print("[axis] Script 15 saniye sonra başlayacak...")
    for i = 5, 1, -1 do
        print(("[axis] %d saniye kaldı..."):format(i))
        task.wait(1)
    end
    print("[axis] Başlıyor!")
end
local TextChatService = game:GetService("TextChatService")
local RS = game:GetService("ReplicatedStorage")
local MESSAGE = "KEREM.CANN IS GOAT"

if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(3)

pcall(function()
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		TextChatService.TextChannels:WaitForChild("RBXGeneral", 10):SendAsync(MESSAGE)
	else
		RS:WaitForChild("DefaultChatSystemChatEvents", 10).SayMessageRequest:FireServer(MESSAGE, "All")
	end
end)