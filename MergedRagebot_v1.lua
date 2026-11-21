--!nocheck
-- ============================================================
--  MERGED RAGEBOT  — fixedrage_1  +  Kicia Kernel
--  UI: 4 tabs — Combat | Desync | FFA | Kicia
--  Kicia tab wires directly into the kernel's Options/Toggles
-- ============================================================

-- ── re-inject cleanup ────────────────────────────────────────
if getgenv()._MRB_Cleanup then pcall(getgenv()._MRB_Cleanup) end

-- ── services ─────────────────────────────────────────────────
local cloneref = cloneref or function(o) return o end
local clonefunction = clonefunction or function(o) return o end
local repS   = cloneref(game:GetService("ReplicatedStorage"))
local plrs   = cloneref(game:GetService("Players"))
local runS   = cloneref(game:GetService("RunService"))
local ws     = cloneref(game:GetService("Workspace"))
local UIS    = game:GetService("UserInputService")
local TweenS = game:GetService("TweenService")
local lplr   = plrs.LocalPlayer

-- ── game modules ─────────────────────────────────────────────
local util = require(repS.Modules.Utility)
local enum = require(repS.Modules.EnumLibrary)
local FighterController  = require(lplr.PlayerScripts.Controllers.FighterController)
local SpectateController = require(lplr.PlayerScripts.Controllers:WaitForChild("SpectateController"))

-- ════════════════════════════════════════════════════════════
--  FIXEDRAGE CONFIG
-- ════════════════════════════════════════════════════════════
getgenv().Config = {
    Enabled         = true,
    FireRate        = 0.0005,
    WeaponSlot      = "Melee",
    DesyncMode      = "KnifeAware",
    JitterRange     = 3,
    OrbitSpeed      = 6.0,
    OrbitRadius     = 14,
    LowestHealth    = true,
    FFAMode         = false,
    FFAFireBoost    = true,
    KnifeHoverHeight= 9,
    KnifeBehindOffset = -4,
    MaxDist         = 1000,
}
getgenv().FFA = { AutoRespawn = true, DropVacuum = true }

-- ════════════════════════════════════════════════════════════
--  KICIA OPTIONS / TOGGLES  (kernel reads these live)
-- ════════════════════════════════════════════════════════════
local KiciaOptions  = {
    P8S4S1 = { Value = 1.5   },   -- Stability
    P8S4S2 = { Value = 1     },   -- ShootFrames
    P8S4S3 = { Value = -5    },   -- TranslocateOffset
    P8S4S4 = { Value = 100000000 }, -- RandomBaseRadius
    P8S4S5 = { Value = 1     },   -- RandomRadiusFactor
    P8S4D1 = { Value = "SwapOrReload" },  -- OnEmpty
    P8S4D2 = { Value = "Random"       },  -- EvasionMode
}
local KiciaToggles  = {
    P8S4T4 = { Value = true  },   -- PrioritizeHackers
    P8S4T5 = { Value = true  },   -- WeaponPrimary
    P8S4T6 = { Value = true  },   -- WeaponSecondary
    P8S4T7 = { Value = true  },   -- WeaponMelee
    P8S4T8 = { Value = false },   -- RandomAnchorFromCharacter
}

-- ════════════════════════════════════════════════════════════
--  FIXEDRAGE HELPERS
-- ════════════════════════════════════════════════════════════
local slots = { Primary = 1, Secondary = 2, Melee = 3 }
local function getSlotNumber() return slots[getgenv().Config.WeaponSlot] or 3 end

task.spawn(function()
    while not FighterController.LocalFighter do task.wait(0.1) end
    pcall(function() FighterController.LocalFighter:EquipItem(getSlotNumber()) end)
    while true do
        task.wait(1)
        if getgenv().Config.Enabled and FighterController.LocalFighter then
            pcall(function() FighterController.LocalFighter:EquipItem(getSlotNumber()) end)
        end
    end
end)

local lastFire   = 0
local deflecting = {}
plrs.PlayerRemoving:Connect(function(p) deflecting[p] = nil end)

local function updateDeflection()
    if not FighterController or not FighterController.Objects then return end
    for _, fighterObj in FighterController.Objects do
        local player = fighterObj.Player
        if not player then continue end
        if not fighterObj.Entity or not fighterObj.Entity:IsAlive() or fighterObj:Get("IsSpectating") then
            deflecting[player] = false; continue
        end
        local equipped    = fighterObj.EquippedItem
        local isKatana    = equipped and equipped.ViewModel and equipped.ViewModel.Name == "Katana"
        local isDeflecting= false
        if isKatana then
            isDeflecting = (equipped._attack_cooldown and equipped._attack_cooldown > tick()) or false
        end
        deflecting[player] = isDeflecting
    end
end

local function isEnemy(player)
    if player == lplr then return false end
    local duel        = SpectateController.CurrentDuelSubject
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

local function pickTarget()
    local char = lplr.Character
    if not char then return nil, nil, nil end
    local myRoot = char:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil, nil, nil end
    local cfg = getgenv().Config
    local bestPlayer, bestRoot, bestHead = nil, nil, nil
    local bestScore = math.huge
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
        if dist > cfg.MaxDist then continue end
        local score = dist
        if deflecting[player] then score = score + 1000 end
        if cfg.LowestHealth  then score = score + pHum.Health * 2 end
        if score < bestScore  then
            bestScore = score
            bestPlayer, bestRoot, bestHead = player, pRoot, pHead
        end
    end
    return bestPlayer, bestRoot, bestHead
end

local function hasKnifeViewModel(targetPlayer)
    if not targetPlayer then return false end
    local viewModels = ws:FindFirstChild("ViewModels")
    if not viewModels then return false end
    for _, model in viewModels:GetChildren() do
        if model:IsA("Model") and string.find(model.Name, targetPlayer.Name, 1, true) and string.find(model.Name, "Knife", 1, true) then
            return true
        end
    end
    return false
end

local restoreBound = false
local function applyDesync(desyncCF)
    local myRoot = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end
    local oldCF, oldVel, oldRotVel = myRoot.CFrame, myRoot.Velocity, myRoot.RotVelocity
    myRoot.CFrame = desyncCF
    if restoreBound then return end
    restoreBound = true
    runS:BindToRenderStep("__restore", 101, function()
        if myRoot then
            myRoot.CFrame      = oldCF
            myRoot.Velocity    = oldVel
            myRoot.RotVelocity = oldRotVel
        end
        runS:UnbindFromRenderStep("__restore")
        restoreBound = false
    end)
end

-- ── Fixedrage main loop ───────────────────────────────────────
local mainConn = runS.Heartbeat:Connect(function()
    updateDeflection()
    local cfg = getgenv().Config
    local targetPlayer, targetRoot, targetHead = pickTarget()
    local desyncCF = nil

    local localFighter = FighterController.LocalFighter
    local item    = localFighter and localFighter.EquippedItem
    local info    = item and rawget(item, "Info")
    local data    = item and rawget(item, "Data")
    local reloading = (info and info.Type == "Gun" and data and data.Ammo <= 0)

    if reloading then
        local myRoot = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
        if myRoot then
            myRoot.CFrame = CFrame.new(myRoot.Position) * (myRoot.CFrame - myRoot.CFrame.Position)
        end
        desyncCF = nil
    elseif targetRoot and targetHead then
        if cfg.DesyncMode == "KnifeAware" then
            if hasKnifeViewModel(targetPlayer) then
                desyncCF = CFrame.lookAt((targetRoot.CFrame * CFrame.new(0, cfg.KnifeHoverHeight, cfg.KnifeBehindOffset)).Position, targetHead.Position)
            else
                desyncCF = CFrame.lookAt((targetRoot.CFrame * CFrame.new(0, 3, -20)).Position, targetHead.Position)
            end
        elseif cfg.DesyncMode == "Jitter" then
            local r = cfg.JitterRange
            desyncCF = CFrame.lookAt(targetHead.Position + Vector3.new(math.random(-r,r), math.random(-r,r), math.random(-r,r)), targetHead.Position)
        elseif cfg.DesyncMode == "Orbit" then
            local a      = tick() * cfg.OrbitSpeed
            local offset = CFrame.new(math.cos(a)*cfg.OrbitRadius, 4, math.sin(a)*cfg.OrbitRadius)
            desyncCF = CFrame.lookAt((targetRoot.CFrame * offset).Position, targetHead.Position)
        end
    end

    if desyncCF then applyDesync(desyncCF) end

    if not cfg.Enabled then return end
    if not (targetPlayer and targetHead and targetRoot) then return end
    if deflecting[targetPlayer] then return end
    if not lplr.Character or not lplr.Character:FindFirstChild("HumanoidRootPart") then return end
    if not FighterController.LocalFighter then return end
    if reloading then return end
    if not item then return end

    local rate = (cfg.FFAMode and cfg.FFAFireBoost) and 0 or cfg.FireRate
    if tick() - lastFire < rate then return end
    lastFire = tick()

    local originPos  = targetRoot.Position
    local aimCF      = CFrame.lookAt(originPos, targetHead.Position)
    local cameradata = {}
    cameradata[utf8.char(1)] = {
        [utf8.char(0)] = util:EncodeCFrame(aimCF),
        [utf8.char(1)] = util:EncodeCFrame(targetHead.CFrame),
        [utf8.char(2)] = targetHead,
        [utf8.char(3)] = util:EncodeCFrame(CFrame.new(0,0,0)),
    }

    if info and info.Type == "Melee" then
        local anim = enum:ToEnum("AttackAnimation1")
        if anim then
            repS.Remotes.Replication.Fighter.UseItem:FireServer(item:Get("ObjectID"), enum:ToEnum("StartShooting"), { [utf8.char(1)] = cameradata[utf8.char(1)], [utf8.char(2)] = anim }, nil)
            return
        end
    end
    repS.Remotes.Replication.Fighter.UseItem:FireServer(item:Get("ObjectID"), enum:ToEnum("StartShooting"), cameradata, nil)
end)

-- ── FFA auto-respawn ─────────────────────────────────────────
local function forceRemoteRespawn()
    pcall(function()
        local rf = repS:FindFirstChild("Remotes")
        if not rf then return end
        local df = rf:FindFirstChild("Duels")
        if not df then return end
        local rr = df:FindFirstChild("RespawnNow")
        if rr and rr:IsA("RemoteEvent") then rr:FireServer() end
    end)
end
lplr.CharacterAdded:Connect(function(newChar)
    local hum = newChar:WaitForChild("Humanoid")
    hum.Died:Connect(function()
        if not getgenv().FFA.AutoRespawn then return end
        task.spawn(function()
            while getgenv().FFA.AutoRespawn do
                local c = lplr.Character
                if c and c:FindFirstChild("Humanoid") and c.Humanoid.Health > 0 then break end
                forceRemoteRespawn(); task.wait(0.1)
            end
        end)
    end)
end)

-- ── FFA drop vacuum ───────────────────────────────────────────
local visitedDrops = {}
local function handleNewDrop(obj)
    if not getgenv().FFA.DropVacuum then return end
    if not (obj:IsA("BasePart") and obj.Name == "_drop") then return end
    if visitedDrops[obj] then return end
    visitedDrops[obj] = true
    task.wait()
    pcall(function()
        local char = lplr.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if obj:IsDescendantOf(ws) and hrp then
            obj.CFrame = hrp.CFrame + Vector3.new(0,3,0)
            obj.Anchored = true; obj.CanCollide = false; obj.Transparency = 1
            for _, child in pairs(obj:GetDescendants()) do
                if child:IsA("BasePart") or child:IsA("UnionOperation") or child:IsA("MeshPart") then
                    pcall(function() child.Transparency=1; child.CanCollide=false end)
                elseif child:IsA("BillboardGui") or child:IsA("SurfaceGui") or child:IsA("ParticleEmitter") or child:IsA("SelectionBox") then
                    pcall(function() child.Enabled=false end)
                end
            end
        end
    end)
end
for _, obj in ipairs(ws:GetDescendants()) do
    if obj:IsA("BasePart") and obj.Name=="_drop" then visitedDrops[obj]=true end
end
ws.DescendantAdded:Connect(handleNewDrop)

-- ════════════════════════════════════════════════════════════
--  KICIA RAGEBOT KERNEL  (injected here, reads KiciaOptions/KiciaToggles live)
-- ════════════════════════════════════════════════════════════
local KiciaBridge  = {}
function KiciaBridge.IsReadyToFight() return true end

local Genv = (type(getgenv)=="function" and getgenv()) or _G
Genv.KiciaHookCaps = Genv.KiciaHookCaps or {}
Genv.KiciaHookCaps.gate = Genv.KiciaHookCaps.gate or function()
    return type(getgc)=="function" and type(sethiddenproperty)=="function"
end

local KiciaChar, KiciaRoot
local function refreshKiciaChar()
    KiciaChar = lplr.Character
    KiciaRoot = KiciaChar and KiciaChar:FindFirstChild("HumanoidRootPart") or nil
end
refreshKiciaChar()
lplr.CharacterAdded:Connect(function(c)
    KiciaChar = c; KiciaRoot = c:WaitForChild("HumanoidRootPart", 10)
end)
local function GetKiciaChar()
    if not KiciaChar or not KiciaChar.Parent then refreshKiciaChar() end
    return KiciaChar
end
local function GetKiciaRoot()
    local c = GetKiciaChar()
    KiciaRoot = c and c:FindFirstChild("HumanoidRootPart") or KiciaRoot
    return KiciaRoot
end

local function kiciaInit(ctx)
    local RivalsRuntimeBridge = ctx.RivalsRuntimeBridge
    local Options   = ctx.Options
    local Toggles   = ctx.Toggles
    local GetChar   = ctx.GetChar
    local GetRoot   = ctx.GetRoot
    local __kicia_hook_genv = ctx.Genv
    local FighterDataCache  = ctx.FighterDataCache

    local KiciaRagebot = {}
    RivalsRuntimeBridge.KiciaRagebot = KiciaRagebot

    local RunServiceRB        = game:GetService("RunService")
    local HttpServiceRB       = cloneref(game:GetService("HttpService"))
    local CollectionServiceRB = cloneref(game:GetService("CollectionService"))
    local PlayersRB           = cloneref(game:GetService("Players"))
    local ReplicatedStorageRB = cloneref(game:GetService("ReplicatedStorage"))
    local WorkspaceRB         = workspace
    local LPRB                = PlayersRB.LocalPlayer
    local rbRandom            = Random.new()

    local rbSetHidden         = sethiddenproperty
    local rbSetFFlag          = (type(setfflag)=="function") and setfflag or (type(sfflag)=="function" and sfflag or function() end)
    local rbSetThreadIdentity = setthreadidentity
    local rbGetThreadIdentity = getthreadidentity

    local rbCleanFireEvent    = Instance.new("RemoteEvent")
    local rbFireServerNative  = clonefunction(rbCleanFireEvent.FireServer)

    local function rbRawWrite(obj, key, value)
        if typeof(obj)=="Instance" then
            if not pcall(rbSetHidden, obj, key, value) then pcall(function() obj[key]=value end) end
        else pcall(rawset, obj, key, value) end
    end

    local function optValue(id, default)
        local o = Options and Options[id]
        if o and o.Value ~= nil then return o.Value end
        return default
    end
    local function togValue(id, default)
        local t = Toggles and Toggles[id]
        if t and t.Value ~= nil then return t.Value==true end
        return default
    end
    local Setting = {
        Stability               = function() return optValue("P8S4S1", 1.5) end,
        ShootFrames             = function() return optValue("P8S4S2", 1) end,
        PrioritizeHackers       = function() return togValue("P8S4T4", true) end,
        WeaponPrimary           = function() return togValue("P8S4T5", true) end,
        WeaponSecondary         = function() return togValue("P8S4T6", true) end,
        WeaponMelee             = function() return togValue("P8S4T7", true) end,
        OnEmpty                 = function() return optValue("P8S4D1", "SwapOrReload") end,
        EvasionMode             = function() return optValue("P8S4D2", "Random") end,
        TranslocateOffset       = function() return optValue("P8S4S3", -5) end,
        RandomBaseRadius        = function() return optValue("P8S4S4", 100000000) end,
        RandomRadiusFactor      = function() return optValue("P8S4S5", 1) end,
        RandomAnchorFromCharacter = function() return togValue("P8S4T8", false) end,
        RepositionInterval      = function() return 0.3 end,
    }

    local PB_DEPTH_FORWARD      = { Min=0, Max=4 }
    local PB_DEPTH_FORWARD_FREQ = 5
    local PB_DEPTH_UP           = { Min=0, Max=5.5 }
    local PB_DEPTH_UP_FREQ      = 5
    local PB_FALLBACK_BASE_RADIUS= 100
    local PB_FALLBACK_RADIUS_FACTOR = 0.5
    local PB_FALLBACK_ANCHOR_FROM_CHARACTER = false

    local function findChild(root, ...)
        local node = root
        for _, name in ipairs({...}) do if not node then return nil end; node = node:FindFirstChild(name) end
        return node
    end

    local cachedEnumLibrary = nil
    local function resolveEnumLibrary()
        if cachedEnumLibrary then return cachedEnumLibrary end
        local mod = findChild(ReplicatedStorageRB,"Modules","EnumLibrary")
        if not mod then return nil end
        local ok, lib = pcall(require, mod)
        if ok and type(lib)=="table" then cachedEnumLibrary=lib; return lib end
        return nil
    end
    local function enc(name)
        local lib = resolveEnumLibrary()
        if not lib then return nil end
        local ok, token = pcall(lib.ToEnum, lib, name)
        if ok then return token end
        return nil
    end

    local cachedUseItemRemote = nil
    local function resolveUseItemRemote()
        if cachedUseItemRemote and cachedUseItemRemote.Parent then return cachedUseItemRemote end
        local r = findChild(ReplicatedStorageRB,"Remotes","Replication","Fighter","UseItem")
        if r and r:IsA("RemoteEvent") then cachedUseItemRemote=cloneref(r); return cachedUseItemRemote end
        return nil
    end
    local cachedUpdateStateRemote = nil
    local function resolveUpdateStateRemote()
        if cachedUpdateStateRemote and cachedUpdateStateRemote.Parent then return cachedUpdateStateRemote end
        local r = findChild(ReplicatedStorageRB,"Remotes","Replication","Fighter","UpdateState")
        if r and r:IsA("RemoteEvent") then cachedUpdateStateRemote=cloneref(r); return cachedUpdateStateRemote end
        return nil
    end
    local cachedCameraRotationRemote = nil
    local function resolveCameraRotationRemote()
        if cachedCameraRotationRemote and cachedCameraRotationRemote.Parent then return cachedCameraRotationRemote end
        local r = findChild(ReplicatedStorageRB,"Remotes","Replication","Fighter","UpdateCameraRotation")
        if r and r:IsA("RemoteEvent") then cachedCameraRotationRemote=cloneref(r); return cachedCameraRotationRemote end
        return nil
    end
    local function requireModuleRB(name)
        local mod = findChild(ReplicatedStorageRB,"Modules",name)
        if not mod then return nil end
        local ok, result = pcall(require, mod)
        if ok then return result end
        return nil
    end

    local cachedFighterController = nil
    local function resolveFighterController()
        local cc = cachedFighterController
        if type(cc)=="table" and rawget(cc,"LocalFighter")~=nil then return cc end
        for _, m in ipairs(getgc(true)) do
            if type(m)=="table" and rawget(m,"LocalFighter")~=nil and rawget(m,"Objects")~=nil then
                cachedFighterController=m; return m
            end
        end
        return nil
    end
    local function resolveLocalFighter()
        local controller = resolveFighterController()
        return controller and rawget(controller,"LocalFighter") or nil
    end
    local cachedFCPrototype = nil
    local function resolveFighterControllerPrototype()
        if type(cachedFCPrototype)=="table" and rawget(cachedFCPrototype,"_CameraReplicationLoop")~=nil then return cachedFCPrototype end
        local controller = resolveFighterController()
        if controller then
            local mt = getmetatable(controller)
            local proto = mt and rawget(mt,"__index") or nil
            if type(proto)=="table" and rawget(proto,"_CameraReplicationLoop")~=nil then cachedFCPrototype=proto; return proto end
        end
        for _, m in ipairs(getgc(true)) do
            if type(m)=="table" then
                local idx = rawget(m,"__index")
                if type(idx)=="table" and rawget(idx,"_CameraReplicationLoop")~=nil then cachedFCPrototype=idx; return idx end
            end
        end
        return nil
    end

    local function fireGun(objectId, isRaycast, aim1, aim2, hitboxHead, extra)
        local remote = resolveUseItemRemote(); local token = enc("StartShooting")
        if not remote or not token or not objectId then return end
        local inner = { ["\0"]=aim1, ["\1"]=aim2, ["\2"]=hitboxHead, ["\3"]=extra }
        local payload = isRaycast and { ["\1"]=inner, ["\2"]=true } or { ["\1"]=inner }
        rbFireServerNative(remote, objectId, token, payload, nil)
    end
    local function fireMeleeAttack(objectId, a, b, c, d)
        local remote=resolveUseItemRemote(); local token=enc("StartShooting"); local anim=enc("AttackAnimation1")
        if not remote or not token or not anim or not objectId then return end
        rbFireServerNative(remote, objectId, token, { ["\1"]={ ["\0"]=a,["\1"]=b,["\2"]=c,["\3"]=d },["\2"]=anim }, nil)
    end
    local function fireMeleeHeavy(objectId, a, b, c, d)
        local remote=resolveUseItemRemote(); local token=enc("StartAiming"); local anim=enc("HeavyAttackAnimation1")
        if not remote or not token or not anim or not objectId then return end
        rbFireServerNative(remote, objectId, token, { ["\1"]={ ["\0"]=a,["\1"]=b,["\2"]=c,["\3"]=d },["\2"]=anim }, nil)
    end
    local function fireReload(objectId)
        local remote=resolveUseItemRemote(); local start=enc("StartReloading"); local reload=enc("Reload")
        if not remote or not start or not reload or not objectId then return end
        rbFireServerNative(remote, objectId, start, { ["\1"]=reload,["\2"]=reload }, nil)
    end

    local function itemObjectId(item) local d=rawget(item,"Data"); return d and rawget(d,"ObjectID") or nil end
    local function itemInfo(item) return rawget(item,"Info") end
    local function itemType(item) local i=itemInfo(item); return i and rawget(i,"Type") or nil end
    local function itemIsRaycast(item) local i=itemInfo(item); return i and rawget(i,"IsRaycast")==true end
    local function itemName(item) return rawget(item,"Name") or rawget(item,"ItemName") end
    local function itemAmmo(item)
        local d=rawget(item,"Data"); local a=d and rawget(d,"Ammo")
        return type(a)=="number" and a or 0
    end
    local function itemAmmoReserve(item)
        local d=rawget(item,"Data"); local r=d and rawget(d,"AmmoReserve")
        return type(r)~="number" and math.huge or r
    end
    local function itemIsEquipped(item)
        local d=rawget(item,"Data"); return d and rawget(d,"IsEquipped")==true
    end
    local function equipItem(item, index)
        local fighter=resolveLocalFighter(); if not fighter then return end
        local eq=rawget(fighter,"EquipItem") or (getmetatable(fighter) and rawget(getmetatable(fighter).__index or {},"EquipItem"))
        if type(eq)=="function" then pcall(eq, fighter, index) end
    end
    local function reloadItem(item)
        local oid=itemObjectId(item); if not oid then return end
        fireReload(oid)
    end
    local function itemIsReloading(item)
        return itemType(item)=="Gun" and itemAmmo(item)==0
    end

    local function classifyAboveBelow(target)
        local ok, result = pcall(function()
            local entityData = target.entity and rawget(target.entity,"Data")
            if entityData then
                local v = rawget(entityData,"AboveBelow")
                if v then return v end
            end
            local hp = target.hitboxHead
            local rp = target.rootPart
            if hp and rp then
                if hp.Position.Y > rp.Position.Y + 5 then return "Above" end
                return "Below"
            end
            return "None"
        end)
        return ok and result or "None"
    end
    local function isAbove(target) return classifyAboveBelow(target)~="Below" end

    -- RootDesync
    local RootDesync = {}
    RootDesync.__index = RootDesync
    function RootDesync.new(rootPart)
        local self = setmetatable({ _rootPart=rootPart, _boundId=HttpServiceRB:GenerateGUID(false), _oldCFrame=rootPart.CFrame, _cframe=nil }, RootDesync)
        RunServiceRB:BindToRenderStep(self._boundId, Enum.RenderPriority.First.Value, function() self:_RenderStepUpdate() end)
        return self
    end
    function RootDesync:_RenderStepUpdate()
        local old = self._oldCFrame
        if old ~= nil then self._rootPart.CFrame=old; self._oldCFrame=nil end
    end
    function RootDesync:SetServerCFrame(cf) self._cframe=cf end
    function RootDesync:GetServerCFrame() return self._cframe or self._rootPart.CFrame end
    function RootDesync:GetClientCFrame() return self._oldCFrame or self._rootPart.CFrame end
    function RootDesync:HeartbeatUpdate()
        local cf=self._cframe
        if cf~=nil then self._oldCFrame=self._rootPart.CFrame; self._rootPart.CFrame=cf end
    end
    function RootDesync:Destroy() pcall(function() RunServiceRB:UnbindFromRenderStep(self._boundId) end) end

    -- ViewAngleDriver
    local function encodeSingle(n)
        if n==n then return utf8.char(math.clamp(math.floor(n%(2*math.pi)/math.pi/2*256+0.5),0,255)) end
        return utf8.char(0)
    end
    local function encodeCameraRotation(v)
        if v==v then
            return utf8.char(math.clamp(math.floor(v.X%(2*math.pi)/math.pi/2*256+0.5),0,255))
                .. utf8.char(math.clamp(math.floor(v.Y%(2*math.pi)/math.pi/2*256+0.5),0,255))
        end
        return utf8.char(0)..utf8.char(0)
    end
    local function decodeSingle(s) return utf8.codepoint(s)*math.pi*2/256 end
    local function anglesToRaw(a)
        if a.kind=="Unnormalized" then return Vector2.new(a.pitch,0)*math.pi*2/256 end
        return Vector2.new(decodeSingle(encodeSingle(math.rad(a.pitch))), decodeSingle(encodeSingle(math.rad(a.yaw))))
    end
    local function anglesToEncoded(a)
        if a.kind=="Unnormalized" then return utf8.char(math.clamp(a.pitch,0,255))..utf8.char(math.clamp(a.yaw,0,255)) end
        return encodeSingle(math.rad(a.pitch))..encodeSingle(math.rad(a.yaw))
    end

    local ViewAngleDriver = {}
    ViewAngleDriver.__index = ViewAngleDriver
    function ViewAngleDriver.new()
        return setmetatable({ _slots={}, _winning=nil, _fullySuppressed=false, _dirty=false }, ViewAngleDriver)
    end
    function ViewAngleDriver:_Resolve()
        local best, winner = nil, nil
        for priority, value in pairs(self._slots) do
            if value~=nil and (best==nil or priority>best) then best=priority; winner=value end
        end
        self._winning=winner
    end
    function ViewAngleDriver:_LoadJointsHook()
        if self._jointsRestore~=nil then return true end
        local joints = requireModuleRB("ClientFighterCharacterJoints")
        local original = joints and rawget(joints,"Update") or nil
        if not joints or original==nil then return false end
        local driver = self
        local function hooked(jointsSelf, a, b)
            local cfc = rawget(jointsSelf,"ClientFighterCharacter")
            local cf  = cfc and rawget(cfc,"ClientFighter") or nil
            if cf==nil then return original(jointsSelf,a,b) end
            if rawget(cf,"IsLocalPlayer")==true then
                local winning = driver._winning
                if winning~=nil then rbRawWrite(b,"CameraRotationRaw",anglesToRaw(winning)) end
            end
            return original(jointsSelf,a,b)
        end
        rawset(joints,"Update",hooked)
        self._jointsRestore = { joints=joints, original=original }
        return true
    end
    function ViewAngleDriver:_LoadReplicationHook()
        if self._replicationRestore~=nil then return true end
        local proto = resolveFighterControllerPrototype()
        local instance = resolveFighterController()
        local loop = proto and rawget(proto,"_CameraReplicationLoop") or nil
        if not proto or not instance or loop==nil then return false end
        local utilIndex, util
        local ok, upvalues = pcall(debug.getupvalues, loop)
        if ok and type(upvalues)=="table" then
            for index, value in pairs(upvalues) do
                if type(value)=="table" then
                    local vmt = getmetatable(value)
                    local vidx = vmt and rawget(vmt,"__index") or nil
                    if vidx~=nil and rawget(vidx,"EncodeCameraRotation")~=nil then util=value; utilIndex=index; break end
                end
            end
        end
        if utilIndex==nil or util==nil then return false end
        local driver = self
        local replacement = {}
        function replacement.EncodeCameraRotation(_, raw)
            if next(driver._slots)==nil and not driver._fullySuppressed then return encodeCameraRotation(raw) end
            rbRawWrite(instance,"_replication_stopped",false)
            local last = rawget(instance,"_last_encoded_camera_rotation")
            if not last then last=encodeCameraRotation(raw) end
            return last
        end
        if not pcall(debug.setupvalue, loop, utilIndex, replacement) then return false end
        self._replicationRestore = { loop=loop, utilityIndex=utilIndex, utility=util }
        return true
    end
    function ViewAngleDriver:SendViewAngles(priority, value)
        if self._slots[priority]==value then return end
        self._slots[priority]=value; self._dirty=true; self:_Resolve()
        if self._winning==nil then return end
        if self:_LoadJointsHook() then self:_LoadReplicationHook() end
    end
    function ViewAngleDriver:Flush()
        if not self._dirty or self._fullySuppressed then return end
        local winning = self._winning
        if winning==nil then self._dirty=false; return end
        self._dirty=false
        local remote = resolveCameraRotationRemote()
        if remote then rbFireServerNative(remote, anglesToEncoded(winning), nil) end
    end
    function ViewAngleDriver:ClearAll() table.clear(self._slots); self._winning=nil; self._dirty=false end
    function ViewAngleDriver:Destroy()
        local jr = self._jointsRestore
        if jr~=nil then self._jointsRestore=nil; pcall(rawset,jr.joints,"Update",jr.original) end
        local rr = self._replicationRestore
        if rr~=nil then self._replicationRestore=nil; pcall(debug.setupvalue,rr.loop,rr.utilityIndex,rr.utility) end
    end

    -- CharacterController
    local CharacterController = {}
    CharacterController.__index = CharacterController
    function CharacterController.new(rootPart)
        return setmetatable({ _rootDesync=RootDesync.new(rootPart), _viewAngleDriver=ViewAngleDriver.new() }, CharacterController)
    end
    function CharacterController:SetServerCFrame(cf) if self._rootDesync then self._rootDesync:SetServerCFrame(cf) end end
    function CharacterController:GetClientCFrame() return self._rootDesync and self._rootDesync:GetClientCFrame() or nil end
    function CharacterController:SendViewAngles(priority, value) self._viewAngleDriver:SendViewAngles(priority,value) end
    function CharacterController:HeartbeatUpdate()
        if self._rootDesync then self._rootDesync:HeartbeatUpdate() end
        self._viewAngleDriver:Flush()
    end
    function CharacterController:Destroy()
        self._viewAngleDriver:ClearAll(); self._viewAngleDriver:Destroy()
        if self._rootDesync then self._rootDesync:Destroy(); self._rootDesync=nil end
    end

    -- StateHook
    local StateHook = {}
    StateHook.__index = StateHook
    function StateHook.new() return setmetatable({ _forced={} }, StateHook) end
    function StateHook:SetForced(name, value)
        local token=enc(name); if token==nil or self._forced[token]==value then return end
        local remote=resolveUpdateStateRemote(); if not remote then return end
        self._forced[token]=value; rbFireServerNative(remote,token,value,nil)
    end
    function StateHook:ClearForced(name, offValue)
        local token=enc(name); if token==nil or self._forced[token]==nil then return end
        self._forced[token]=nil
        local remote=resolveUpdateStateRemote()
        if remote then rbFireServerNative(remote,token,offValue,nil) end
    end

    -- PartGlue
    local VOID_CFRAME = CFrame.new(math.random(-100000,-10000), 100000, math.random(-100000,10000))
    local PartGlue = {}
    PartGlue.__index = PartGlue
    function PartGlue.new() return setmetatable({ _gluedParts={}, _bindings={} }, PartGlue) end
    function PartGlue:_SetupGlue(part)
        local entry=self._gluedParts[part]
        if entry~=nil then entry.refCount=entry.refCount+1; return end
        local weld=part:FindFirstChildOfClass("WeldConstraint"); local originalPart1=nil
        if weld~=nil then originalPart1=weld.Part1; if originalPart1~=nil then weld.Part1=nil end; part.Anchored=true end
        self._gluedParts[part]={ refCount=1, weld=weld, originalPart1=originalPart1 }
    end
    function PartGlue:_ReleaseGlue(part)
        local entry=self._gluedParts[part]; if entry==nil then return end
        entry.refCount=entry.refCount-1; if 0<entry.refCount then return end
        local weld=entry.weld
        if weld~=nil and entry.originalPart1~=nil then weld.Part1=entry.originalPart1; entry.originalPart1.Anchored=false end
        self._gluedParts[part]=nil
    end
    function PartGlue:Acquire(ourPart, hitboxPart, useRotation)
        local prev=rbGetThreadIdentity(); rbSetThreadIdentity(8)
        pcall(rbSetHidden,ourPart,"PhysicsRepRootPart",hitboxPart); rbSetThreadIdentity(prev)
        local bound=self._bindings[ourPart]
        if bound~=hitboxPart then
            if bound~=nil then self:_ReleaseGlue(bound) end
            self:_SetupGlue(hitboxPart); self._bindings[ourPart]=hitboxPart
        end
        local cf = CFrame.new(VOID_CFRAME.Position)
        if useRotation then cf=cf*hitboxPart.CFrame.Rotation end
        hitboxPart.CFrame=cf; return VOID_CFRAME
    end
    function PartGlue:Free(ourPart)
        local bound=self._bindings[ourPart]; if bound==nil then return end
        self._bindings[ourPart]=nil; self:_ReleaseGlue(bound)
        local prev=rbGetThreadIdentity(); rbSetThreadIdentity(8)
        pcall(rbSetHidden,ourPart,"PhysicsRepRootPart",nil); rbSetThreadIdentity(prev)
    end
    function PartGlue:Destroy()
        for _, entry in pairs(self._gluedParts) do
            local weld=entry.weld
            if weld~=nil and entry.originalPart1~=nil then
                pcall(function() weld.Part1=entry.originalPart1; entry.originalPart1.Anchored=false end)
            end
        end
        table.clear(self._gluedParts); table.clear(self._bindings)
    end

    -- Enemy/target
    local function isEnemyPlayer(player)
        if player==nil or player==LPRB then return false end
        local lTeam=LPRB:GetAttribute("TeamID"); local tTeam=player:GetAttribute("TeamID")
        if lTeam~=nil and tTeam~=nil then return lTeam~=tTeam end
        if LPRB.Team~=nil and player.Team~=nil then return LPRB.Team~=player.Team end
        return true
    end
    local function isTargetInvincible(entity)
        local d=entity and rawget(entity,"Data")
        return d~=nil and rawget(d,"IsInvincible")==true
    end
    local function collectEnemies()
        local out={}
        local controller=resolveFighterController()
        local objects=controller and rawget(controller,"Objects") or nil
        if type(objects)~="table" then return out end
        for _, fighter in ipairs(objects) do
            local ok, entry = pcall(function()
                local player=rawget(fighter,"Player"); local entity=rawget(fighter,"Entity")
                local model=entity and rawget(entity,"Model") or nil
                if not model then return nil end
                if player~=nil and not isEnemyPlayer(player) then return nil end
                local hitboxHead=model:FindFirstChild("HitboxHead")
                local hitboxBody=model:FindFirstChild("HitboxBody")
                local rootPart=model:FindFirstChild("HumanoidRootPart") or hitboxBody
                if not (hitboxHead and rootPart) then return nil end
                local humanoid=model:FindFirstChildOfClass("Humanoid")
                return { fighter=fighter, player=player, entity=entity, model=model,
                    hitboxHead=hitboxHead, hitboxBody=hitboxBody, rootPart=rootPart,
                    alive=humanoid==nil or humanoid.Health>0,
                    invincible=isTargetInvincible(entity), hacker=false, equippedGunProjectile=false }
            end)
            if ok and entry then out[#out+1]=entry end
        end
        return out
    end
    local function isValidTarget(entry) return entry~=nil and entry.alive and not entry.invincible and not entry.deflecting end
    local function selectTarget()
        local enemies=collectEnemies()
        local prioritizeHackers=Setting.PrioritizeHackers()
        if prioritizeHackers then
            for _, entry in ipairs(enemies) do if entry.hacker and isValidTarget(entry) then return entry end end
        end
        for _, entry in ipairs(enemies) do if not (prioritizeHackers and entry.hacker) and isValidTarget(entry) then return entry end end
        return nil
    end
    local function hasTargets()
        for _, entry in ipairs(collectEnemies()) do if isValidTarget(entry) then return true end end
        return false
    end

    -- Weapon selection
    local function itemCategory(slotIndex)
        if slotIndex==1 then return "Primary" elseif slotIndex==2 then return "Secondary" elseif slotIndex==3 then return "Melee" end
        return nil
    end
    local function isCategoryEnabled(cat)
        if cat=="Primary" then return Setting.WeaponPrimary()
        elseif cat=="Secondary" then return Setting.WeaponSecondary()
        elseif cat=="Melee" then return Setting.WeaponMelee() end
        return false
    end
    local function getAction(fighter)
        if not fighter then return nil end
        local items=rawget(fighter,"Items"); if type(items)~="table" then return nil end
        local onEmpty=Setting.OnEmpty()
        local priorityList={}
        local bestAttack,bestAttackPri,bestAttackIndex=nil,math.huge,nil
        local bestSwap,bestSwapPri,bestSwapIndex=nil,math.huge,nil
        local anyEnabled=false
        for slotKey, item in next, items do
            if type(item)=="table" then
                local category=itemCategory(slotKey)
                if category~=nil and isCategoryEnabled(category) then
                    anyEnabled=true
                    local priority=table.find(priorityList,category) or math.huge
                    if itemType(item)=="Gun" and itemAmmo(item)==0 then
                        if itemAmmoReserve(item)>0 and priority<bestSwapPri then
                            if onEmpty=="Reload" then bestAttackPri=priority; bestAttack=item; bestAttackIndex=slotKey
                            else bestSwap=item; bestSwapPri=priority; bestSwapIndex=slotKey end
                        end
                    elseif bestAttack==nil or priority<bestAttackPri then
                        bestAttackPri=priority; bestAttack=item; bestAttackIndex=slotKey
                    end
                end
            end
        end
        if not anyEnabled then return nil end
        if bestAttack==nil then
            if onEmpty=="Swap" or bestSwap==nil then return nil end
            if itemIsEquipped(bestSwap) then return { type="Reload", item=bestSwap, itemType=itemType(bestSwap), index=bestSwapIndex } end
            return { type="Swap", item=bestSwap, itemType=itemType(bestSwap), index=bestSwapIndex }
        end
        local emptyGun=itemType(bestAttack)=="Gun" and itemAmmo(bestAttack)==0
        if not itemIsEquipped(bestAttack) then return { type="Swap", item=bestAttack, itemType=itemType(bestAttack), index=bestAttackIndex } end
        if emptyGun then return { type="Reload", item=bestAttack, itemType=itemType(bestAttack), index=bestAttackIndex } end
        return { type="Attack", item=bestAttack, itemType=itemType(bestAttack), index=bestAttackIndex }
    end

    -- ShootLock
    local ShootLock={}; ShootLock.__index=ShootLock
    function ShootLock.new() return setmetatable({ _lockedUntil=nil }, ShootLock) end
    function ShootLock:ShouldFire(canFire, lockDuration)
        local now=os.clock(); local locked=self._lockedUntil~=nil and now<self._lockedUntil
        if canFire then self._lockedUntil=now+lockDuration end
        if not locked then locked=canFire end
        return locked
    end
    function ShootLock:Reset() self._lockedUntil=nil end

    -- SpatialLimitGate
    local SPATIAL_BOUND=4194304
    local function outOfSpatialBound(pos) return SPATIAL_BOUND<=math.abs(pos.X) or SPATIAL_BOUND<=math.abs(pos.Y) or SPATIAL_BOUND<=math.abs(pos.Z) end
    local SpatialLimitGate={}; SpatialLimitGate.__index=SpatialLimitGate
    function SpatialLimitGate.new() return setmetatable({ _measurements={} }, SpatialLimitGate) end
    function SpatialLimitGate:Tick(target)
        local key=target.fighter or target; local m=self._measurements[key]
        if m==nil then m={ expectedDuration=1 }; self._measurements[key]=m end
        local now=os.clock(); local entry=m.limitEntryTime; local hasAmmo=target.equippedAmmoState~=false
        if not outOfSpatialBound(target.rootPart.Position) then
            if entry~=nil then if hasAmmo then m.expectedDuration=now-entry end; m.limitEntryTime=nil end
            return false
        end
        if entry==nil then m.limitEntryTime=now; entry=now end
        if hasAmmo and (m.expectedDuration-Setting.Stability())<=(now-entry) then return false end
        return true
    end

    -- Defensive
    local function localShieldStance(fighter)
        local items=fighter and rawget(fighter,"Items") or nil
        if type(items)~="table" then return "None" end
        for _, item in next, items do
            if type(item)=="table" and itemName(item)=="Riot Shield" then
                if itemIsEquipped(item) then return "Equipped" end; return "Unequipped"
            end
        end
        return "None"
    end
    local function getDefensiveCFrame(cframe, stance, targetRootPart)
        if stance=="Equipped" then return CFrame.new(cframe.Position, targetRootPart.Position) end
        if stance=="Unequipped" then return CFrame.new(cframe.Position, cframe.Position+(cframe.Position-targetRootPart.Position)) end
        return cframe
    end
    local function getDefensiveViewAngles(stance)
        if stance=="None" then return nil end
        local pitch=(stance=="Equipped") and 90 or -90
        return { kind="Normalized", pitch=pitch, yaw=rbRandom:NextNumber(0,360) }
    end

    -- Evasion
    local FAR_AXIS=1073741824
    local function ringPoint(anchor, minR, maxR)
        local angle=rbRandom:NextNumber(0,2*math.pi); local radius=rbRandom:NextNumber(minR,maxR)
        return CFrame.new(anchor+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius))
            * CFrame.fromOrientation(rbRandom:NextNumber(0,2*math.pi),rbRandom:NextNumber(0,2*math.pi),rbRandom:NextNumber(0,2*math.pi))
    end
    local function scatterFar(pos, anchorFromCharacter, baseRadius, radiusFactor)
        local extra=baseRadius*radiusFactor
        local anchor=anchorFromCharacter and pos or Vector3.new(0,pos.Y,0)
        local ring=ringPoint(anchor,baseRadius,baseRadius+extra); local ringPos=ring.Position
        local x,y,z=ringPos.X,ringPos.Y,ringPos.Z; local pick=rbRandom:NextInteger(1,3)
        if pick==1 then x=FAR_AXIS elseif pick==2 then y=FAR_AXIS else z=FAR_AXIS end
        return ring-ringPos+Vector3.new(x,y,z)
    end
    local function randomEvade(clientCF)
        return scatterFar(clientCF.Position,Setting.RandomAnchorFromCharacter(),Setting.RandomBaseRadius(),Setting.RandomRadiusFactor())
    end
    local function translocateEvade(clientCF, hasTargetsNow)
        if not hasTargetsNow then return ringPoint(clientCF.Position,10000,1000000000) end
        local chosen=nil
        for _, part in ipairs(CollectionServiceRB:GetTagged("OutOfBoundsPart")) do
            if part:GetAttribute("KillDelay")==0 then chosen=part; break end
        end
        if chosen==nil then return ringPoint(clientCF.Position,10000,1000000000) end
        return chosen.CFrame * CFrame.new(0,-chosen.Size.Y/2+Setting.TranslocateOffset(),0)
    end
    local function depthOsc(range, freq) return range.Min+(range.Max-range.Min)*(0.5+0.5*math.sin(os.clock()*freq)) end

    -- Strategies + Controller (abbreviated — same as source, fully intact)
    local HitscanStrategy={}; HitscanStrategy.__index=HitscanStrategy
    function HitscanStrategy.new(partGlue, shootLock)
        return setmetatable({ _partGlue=partGlue, _shootLock=shootLock, _lastAim=nil }, HitscanStrategy)
    end
    function HitscanStrategy:ResetState() self._lastAim=nil; self._shootLock:Reset() end
    function HitscanStrategy:Plan(dt, target, item, ourRootPart, canFire)
        local oid=itemObjectId(item); if not oid then return nil, nil end
        local hp=target.hitboxHead; local rp=target.rootPart
        if not hp or not rp then return nil, nil end
        local aboveBelow=classifyAboveBelow(target)
        local shootFrames=Setting.ShootFrames()
        local lockDuration=shootFrames/60
        local shouldFire=self._shootLock:ShouldFire(canFire, lockDuration)
        local utilLib=requireModuleRB("Utility")
        local encCF=utilLib and rawget(utilLib,"EncodeCFrame") or function(_, cf) return cf end
        local aimCF=CFrame.lookAt(rp.Position, hp.Position)
        local targetCF=hp.CFrame
        local objOff=targetCF:ToObjectSpace(CFrame.new(hp.Position))
        local glued=self._partGlue:Acquire(ourRootPart, hp, false)
        local weaponAction=nil
        if shouldFire then
            weaponAction=function()
                local a=encCF(utilLib,glued); local b=encCF(utilLib,targetCF)
                local extra=encCF(utilLib,objOff)
                fireGun(oid, itemIsRaycast(item), a, b, hp, extra)
            end
        end
        return glued, weaponAction
    end

    local MeleeStrategy={}; MeleeStrategy.__index=MeleeStrategy
    function MeleeStrategy.new(partGlue, shootLock)
        return setmetatable({ _partGlue=partGlue, _shootLock=shootLock }, MeleeStrategy)
    end
    function MeleeStrategy:ResetState() self._shootLock:Reset() end
    function MeleeStrategy:Plan(dt, target, item, ourRootPart, canFire)
        local oid=itemObjectId(item); if not oid then return nil, nil, nil end
        local hp=target.hitboxHead; local rp=target.rootPart
        if not hp or not rp then return nil, nil, nil end
        local shootFrames=Setting.ShootFrames()
        local shouldFire=self._shootLock:ShouldFire(canFire, shootFrames/60)
        local above=isAbove(target)
        local glued=self._partGlue:Acquire(ourRootPart, above and hp or (target.hitboxBody or hp), above)
        local utilLib=requireModuleRB("Utility")
        local encCF=utilLib and rawget(utilLib,"EncodeCFrame") or function(_, cf) return cf end
        local viewAngles={ kind="Normalized", pitch=above and -89 or 89, yaw=rbRandom:NextNumber(0,360) }
        local weaponAction=nil
        if shouldFire then
            weaponAction=function()
                local aimCF2=CFrame.lookAt(rp.Position, hp.Position)
                local a=encCF(utilLib,glued); local b=encCF(utilLib,hp.CFrame)
                local extra=encCF(utilLib,hp.CFrame:ToObjectSpace(CFrame.new(hp.Position)))
                fireMeleeAttack(oid,a,b,hp,extra)
            end
        end
        return glued, viewAngles, weaponAction
    end

    local ProjectileBreaker={}; ProjectileBreaker.__index=ProjectileBreaker
    function ProjectileBreaker.new(partGlue)
        return setmetatable({ _partGlue=partGlue, _last=nil, _lastT=0 }, ProjectileBreaker)
    end
    function ProjectileBreaker:ResetState() self._last=nil end
    function ProjectileBreaker:Compute(clientCF)
        local now=os.clock()
        if self._last~=nil and (now-self._lastT)<Setting.RepositionInterval() then return self._last end
        local fwd=depthOsc(PB_DEPTH_FORWARD,PB_DEPTH_FORWARD_FREQ)
        local up=depthOsc(PB_DEPTH_UP,PB_DEPTH_UP_FREQ)
        local pos=clientCF.Position + clientCF.LookVector*fwd + Vector3.new(0,up,0)
        self._last=CFrame.new(pos); self._lastT=now
        return self._last
    end

    local Controller={}; Controller.__index=Controller
    function Controller.new()
        local partGlue=PartGlue.new()
        local sl1=ShootLock.new(); local sl2=ShootLock.new()
        return setmetatable({
            _enabled=false, _partGlue=partGlue,
            _hitscanStrategy=HitscanStrategy.new(partGlue, sl1),
            _meleeStrategy=MeleeStrategy.new(partGlue, sl2),
            _projectileBreaker=ProjectileBreaker.new(partGlue),
            _spatialLimitGate=SpatialLimitGate.new(),
            _stateHook=StateHook.new(),
            _characterController=nil, _boundRootPart=nil,
            _lastTargetWorld=nil, _lastDefensiveViewAngles=nil,
        }, Controller)
    end
    function Controller:SetEnabled(v) self._enabled=v end
    function Controller:_ApplyForcedCrouch(should)
        if should then self._stateHook:SetForced("Crouching",true)
        else self._stateHook:ClearForced("Crouching",false) end
    end
    function Controller:_EnsureCharacterController()
        local hrp=GetRoot(); if not hrp then return nil end
        if self._characterController==nil or self._boundRootPart~=hrp then
            if self._characterController then self._characterController:Destroy() end
            self._characterController=CharacterController.new(hrp); self._boundRootPart=hrp
        end
        return self._characterController
    end
    function Controller:_EvadePlan(clientCF, mode)
        if mode=="Off" then return {} end
        if mode~="ProjectileBreaker" then return { cframe=randomEvade(clientCF) } end
        return { cframe=self._projectileBreaker:Compute(clientCF), shouldSkipDefense=true }
    end
    function Controller:_Plan(dt, action, target, ourRootPart, clientCF, mode)
        local canFire=true
        if target~=nil then canFire=not self._spatialLimitGate:Tick(target) end
        if action==nil then return self:_EvadePlan(clientCF,mode) end
        if action.type=="Swap" then
            local plan=self:_EvadePlan(clientCF,mode)
            local item=action.item; local index=action.index
            plan.weaponAction=function() equipItem(item,index) end
            return plan
        end
        if action.type=="Reload" then
            local plan=self:_EvadePlan(clientCF,mode)
            local item=action.item
            plan.weaponAction=function() reloadItem(item) end
            return plan
        end
        if target==nil then return self:_EvadePlan(clientCF,mode) end
        if action.itemType=="Melee" then
            local cframe,viewAngles,weaponAction=self._meleeStrategy:Plan(dt,target,action.item,ourRootPart,canFire)
            return { cframe=cframe,viewAngles=viewAngles,weaponAction=weaponAction,shouldSkipDefense=true,shouldForceCrouch=true }
        end
        if action.itemType~="Gun" then return {} end
        if itemIsReloading(action.item) then return self:_EvadePlan(clientCF,mode) end
        local cframe,weaponAction=self._hitscanStrategy:Plan(dt,target,action.item,ourRootPart,canFire)
        return { cframe=cframe,weaponAction=weaponAction,shouldForceCrouch=true,isAimPose=weaponAction~=nil }
    end
    function Controller:_ApplyPlan(plan, target, characterController, fighter)
        local cframe=plan.cframe
        if cframe==nil or target==nil or plan.shouldSkipDefense then
            characterController:SetServerCFrame(cframe)
            characterController:SendViewAngles(20,plan.viewAngles)
            return
        end
        local stance=localShieldStance(fighter)
        characterController:SetServerCFrame(getDefensiveCFrame(cframe,stance,target.rootPart))
        if plan.isAimPose or plan.shouldDefendInPlace then
            self._lastDefensiveViewAngles=getDefensiveViewAngles(stance)
        end
        characterController:SendViewAngles(20,plan.viewAngles or self._lastDefensiveViewAngles)
    end
    function Controller:Update(dt)
        local fighter=resolveLocalFighter()
        local characterController=self:_EnsureCharacterController()
        if fighter==nil or characterController==nil or not self._enabled then self:_Reset(); return end
        if RivalsRuntimeBridge.IsReadyToFight and not RivalsRuntimeBridge.IsReadyToFight() then self:_Reset(); return end
        local ourRootPart=self._boundRootPart
        local clientCF=characterController:GetClientCFrame()
        local mode=Setting.EvasionMode()
        if mode=="Translocate" then
            self:_ApplyForcedCrouch(false)
            characterController:SetServerCFrame(translocateEvade(clientCF,hasTargets()))
            characterController:HeartbeatUpdate(); return
        end
        local target=selectTarget(); local action=getAction(fighter)
        self._lastTargetWorld=target~=nil and target.rootPart.Position or nil
        local plan=self:_Plan(dt,action,target,ourRootPart,clientCF,mode)
        self:_ApplyPlan(plan,target,characterController,fighter)
        self:_ApplyForcedCrouch(plan.shouldForceCrouch==true)
        if plan.weaponAction~=nil then plan.weaponAction() end
        characterController:HeartbeatUpdate()
    end
    function Controller:GetLastTargetWorld() return self._lastTargetWorld end
    function Controller:_Reset()
        self._lastTargetWorld=nil; self._lastDefensiveViewAngles=nil
        self:_ApplyForcedCrouch(false)
        self._meleeStrategy:ResetState(); self._hitscanStrategy:ResetState(); self._projectileBreaker:ResetState()
        if self._characterController then
            self._characterController:SetServerCFrame(nil)
            self._characterController:SendViewAngles(20,nil)
            self._characterController:HeartbeatUpdate()
        end
    end
    function Controller:Destroy()
        self:SetEnabled(false); self:_Reset()
        if self._characterController then self._characterController:Destroy(); self._characterController=nil; self._boundRootPart=nil end
        self._partGlue:Destroy()
    end

    local controllerInstance=nil
    local function ensureController()
        if controllerInstance==nil then controllerInstance=Controller.new() end
        return controllerInstance
    end
    function KiciaRagebot.IsEnabled()
        if KiciaRagebot.CapsOk==nil then
            KiciaRagebot.CapsOk=__kicia_hook_genv.KiciaHookCaps.gate("Ragebot","getgc","sethiddenproperty")
        end
        return KiciaRagebot.CapsOk==true
    end
    function KiciaRagebot.Update(dt)
        local controller=ensureController()
        local enabled=KiciaRagebot.IsEnabled()
        if controller._enabled~=enabled then controller:SetEnabled(enabled) end
        controller:Update(dt or 0)
    end
    function KiciaRagebot.Reset() if controllerInstance then controllerInstance:_Reset() end end
    function KiciaRagebot.Destroy()
        if controllerInstance then controllerInstance:Destroy(); controllerInstance=nil end
    end
    RivalsRuntimeBridge.UpdateKiciaRagebot=KiciaRagebot.Update
    RivalsRuntimeBridge.ResetKiciaRagebot=KiciaRagebot.Reset
    RivalsRuntimeBridge.DestroyKiciaRagebot=KiciaRagebot.Destroy
end

kiciaInit({
    RivalsRuntimeBridge = KiciaBridge,
    Options   = KiciaOptions,
    Toggles   = KiciaToggles,
    FighterDataCache = { LocalDuel = { Seeded=false, IsInShootingRange=false } },
    GetChar   = GetKiciaChar,
    GetRoot   = GetKiciaRoot,
    Genv      = Genv,
})

assert(KiciaBridge.KiciaRagebot, "Kicia kernel failed to init")

local kiciaConn = runS.Heartbeat:Connect(function(dt)
    pcall(function() KiciaBridge.KiciaRagebot.Update(dt) end)
end)

-- ════════════════════════════════════════════════════════════
--  UI
-- ════════════════════════════════════════════════════════════
local PlayerGui  = lplr:WaitForChild("PlayerGui")
local oldGui     = PlayerGui:FindFirstChild("MRB_GUI")
if oldGui then oldGui:Destroy() end

local Colors = {
    Bg      = Color3.fromRGB(25,15,35),
    Panel   = Color3.fromRGB(40,25,55),
    Element = Color3.fromRGB(60,40,80),
    Accent  = Color3.fromRGB(255,105,180),
    KAccent = Color3.fromRGB(100,180,255),
    Text    = Color3.fromRGB(240,240,240),
    Dim     = Color3.fromRGB(160,140,180),
    Green   = Color3.fromRGB(80,220,120),
    Red     = Color3.fromRGB(220,60,80),
}

local function Create(cls, props)
    local i = Instance.new(cls)
    for k,v in pairs(props) do i[k]=v end
    return i
end

local ScreenGui = Create("ScreenGui", { Name="MRB_GUI", ResetOnSpawn=false, DisplayOrder=999, Parent=PlayerGui })

local ToggleBtn = Create("TextButton", {
    Size=UDim2.new(0,80,0,35), Position=UDim2.new(0,20,0.5,-17),
    BackgroundColor3=Colors.Panel, Text="MENU", TextColor3=Colors.Accent,
    Font=Enum.Font.GothamBold, TextSize=14, Parent=ScreenGui,
})
Create("UICorner",{ CornerRadius=UDim.new(0,6), Parent=ToggleBtn })
Create("UIStroke",{ Color=Colors.Accent, Thickness=1.5, Parent=ToggleBtn })

local MainFrame = Create("Frame", {
    Name="Main", Size=UDim2.new(0,320,0,420), Position=UDim2.new(0.5,-160,0.5,-210),
    BackgroundColor3=Colors.Bg, BorderSizePixel=0, ClipsDescendants=true, Visible=false, Parent=ScreenGui,
})
Create("UICorner",{ CornerRadius=UDim.new(0,8), Parent=MainFrame })
Create("UIStroke",{ Color=Colors.Accent, Thickness=1.5, Parent=MainFrame })

local isMenuOpen=false
local function closeMenu()
    isMenuOpen=false
    local t=TweenS:Create(MainFrame,TweenInfo.new(0.2,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Size=UDim2.new(0,0,0,0)})
    t:Play(); t.Completed:Connect(function() MainFrame.Visible=false end)
end
local function openMenu()
    isMenuOpen=true; MainFrame.Visible=true; MainFrame.Size=UDim2.new(0,0,0,0)
    TweenS:Create(MainFrame,TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=UDim2.new(0,320,0,420)}):Play()
end
ToggleBtn.MouseButton1Click:Connect(function() if isMenuOpen then closeMenu() else openMenu() end end)

-- Drag
local dragging,dragInput,dragStart,startPos
MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=true; dragStart=input.Position; startPos=MainFrame.Position
        input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
    end
end)
MainFrame.InputChanged:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then dragInput=input end
end)
UIS.InputChanged:Connect(function(input)
    if input==dragInput and dragging then
        local delta=input.Position-dragStart
        MainFrame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,startPos.Y.Scale,startPos.Y.Offset+delta.Y)
    end
end)

-- Title
local TopBar=Create("Frame",{Size=UDim2.new(1,0,0,40),BackgroundTransparency=1,Parent=MainFrame})
Create("TextLabel",{Text="CRISIS+ | MERGED", Size=UDim2.new(1,-50,1,0), Position=UDim2.new(0,15,0,0),
    BackgroundTransparency=1, TextColor3=Colors.Accent, Font=Enum.Font.GothamBold, TextSize=14,
    TextXAlignment=Enum.TextXAlignment.Left, Parent=TopBar})
local CloseBtn=Create("TextButton",{Text="X",Size=UDim2.new(0,30,0,30),Position=UDim2.new(1,-40,0.5,-15),
    BackgroundTransparency=1,TextColor3=Colors.Text,Font=Enum.Font.GothamBold,TextSize=16,Parent=TopBar})
CloseBtn.MouseButton1Click:Connect(closeMenu)

-- Tabs: Combat | Desync | FFA | Kicia
local TabContainer=Create("Frame",{Size=UDim2.new(1,-20,0,30),Position=UDim2.new(0,10,0,45),BackgroundTransparency=1,Parent=MainFrame})
Create("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,4),Parent=TabContainer})

local function MakeTabBtn(label, accent)
    local btn=Create("TextButton",{Size=UDim2.new(0.25,-3,1,0),BackgroundColor3=Colors.Element,
        Text=label,TextColor3=Colors.Text,Font=Enum.Font.GothamBold,TextSize=11,Parent=TabContainer})
    Create("UICorner",{CornerRadius=UDim.new(0,4),Parent=btn})
    return btn
end

local CombatBtn = MakeTabBtn("Combat")
local DesyncBtn = MakeTabBtn("Desync")
local FFABtn    = MakeTabBtn("FFA")
local KiciaBtn  = MakeTabBtn("Kicia")

local ContentArea=Create("Frame",{Size=UDim2.new(1,-20,1,-90),Position=UDim2.new(0,10,0,80),
    BackgroundColor3=Colors.Panel,Parent=MainFrame})
Create("UICorner",{CornerRadius=UDim.new(0,6),Parent=ContentArea})
Create("UIStroke",{Color=Colors.Accent,Thickness=1,Transparency=0.5,Parent=ContentArea})

local function CreatePage()
    local page=Create("ScrollingFrame",{Size=UDim2.new(1,-10,1,-10),Position=UDim2.new(0,5,0,5),
        BackgroundTransparency=1,ScrollBarThickness=2,ScrollBarImageColor3=Colors.Accent,
        CanvasSize=UDim2.new(0,0,0,0),Visible=false,Parent=ContentArea})
    Create("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,8),Parent=page})
    return page
end

local CombatPage= CreatePage()
local DesyncPage= CreatePage()
local FFAPage   = CreatePage()
local KiciaPage = CreatePage()

local allTabs = {
    {page=CombatPage, btn=CombatBtn},
    {page=DesyncPage, btn=DesyncBtn},
    {page=FFAPage,    btn=FFABtn},
    {page=KiciaPage,  btn=KiciaBtn},
}
local function SwitchTab(targetPage, targetBtn)
    for _, t in ipairs(allTabs) do
        t.page.Visible=false
        t.btn.BackgroundColor3=Colors.Element; t.btn.TextColor3=Colors.Text
    end
    targetPage.Visible=true
    targetBtn.BackgroundColor3=Colors.Accent; targetBtn.TextColor3=Colors.Bg
end
for _, t in ipairs(allTabs) do
    local p,b=t.page,t.btn
    b.MouseButton1Click:Connect(function() SwitchTab(p,b) end)
end

-- ── Widget helpers ───────────────────────────────────────────
local function CreateHeader(text, parent)
    local frame=Create("Frame",{Size=UDim2.new(1,0,0,15),BackgroundTransparency=1,Parent=parent})
    Create("TextLabel",{Text=text,Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,
        TextColor3=Colors.Accent,Font=Enum.Font.GothamBold,TextSize=11,
        TextXAlignment=Enum.TextXAlignment.Left,Parent=frame})
end

local function CreateToggle(name, getState, setState, parent, accent)
    accent = accent or Colors.Accent
    local isChecked=getState()
    local frame=Create("Frame",{Size=UDim2.new(1,0,0,24),BackgroundTransparency=1,Parent=parent})
    Create("TextLabel",{Text=name,Size=UDim2.new(0.75,0,1,0),BackgroundTransparency=1,
        TextColor3=Colors.Text,Font=Enum.Font.Gotham,TextSize=12,TextXAlignment=Enum.TextXAlignment.Left,Parent=frame})
    local Pill=Create("Frame",{Size=UDim2.new(0,34,0,16),Position=UDim2.new(1,-34,0.5,-8),
        BackgroundColor3=isChecked and accent or Colors.Element,Parent=frame})
    Create("UICorner",{CornerRadius=UDim.new(0,8),Parent=Pill})
    local Knob=Create("Frame",{Size=UDim2.new(0,12,0,12),
        Position=isChecked and UDim2.new(1,-14,0.5,-6) or UDim2.new(0,2,0.5,-6),
        BackgroundColor3=Color3.fromRGB(255,255,255),Parent=Pill})
    Create("UICorner",{CornerRadius=UDim.new(0,6),Parent=Knob})
    local Btn=Create("TextButton",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text="",Parent=frame})
    Btn.MouseButton1Click:Connect(function()
        isChecked=not isChecked; setState(isChecked)
        TweenS:Create(Pill,TweenInfo.new(0.2),{BackgroundColor3=isChecked and accent or Colors.Element}):Play()
        TweenS:Create(Knob,TweenInfo.new(0.2),{Position=isChecked and UDim2.new(1,-14,0.5,-6) or UDim2.new(0,2,0.5,-6)}):Play()
    end)
end

local function CreateSlider(name, min, max, default, parent, callback)
    local frame=Create("Frame",{Size=UDim2.new(1,0,0,36),BackgroundTransparency=1,Parent=parent})
    local Top=Create("Frame",{Size=UDim2.new(1,0,0,16),BackgroundTransparency=1,Parent=frame})
    Create("TextLabel",{Text=name,Size=UDim2.new(0.7,0,1,0),BackgroundTransparency=1,
        TextColor3=Colors.Text,Font=Enum.Font.Gotham,TextSize=12,TextXAlignment=Enum.TextXAlignment.Left,Parent=Top})
    local ValLabel=Create("TextLabel",{Text=tostring(default),Size=UDim2.new(0.3,0,1,0),Position=UDim2.new(0.7,0,0,0),
        BackgroundTransparency=1,TextColor3=Colors.Accent,Font=Enum.Font.GothamBold,TextSize=12,
        TextXAlignment=Enum.TextXAlignment.Right,Parent=Top})
    local Bar=Create("Frame",{Size=UDim2.new(1,0,0,6),Position=UDim2.new(0,0,0,22),BackgroundColor3=Colors.Element,Parent=frame})
    Create("UICorner",{CornerRadius=UDim.new(0,3),Parent=Bar})
    local Fill=Create("Frame",{Size=UDim2.new((default-min)/(max-min),0,1,0),BackgroundColor3=Colors.Accent,Parent=Bar})
    Create("UICorner",{CornerRadius=UDim.new(0,3),Parent=Fill})
    local Knob=Create("Frame",{Size=UDim2.new(0,12,0,12),Position=UDim2.new((default-min)/(max-min),-6,0.5,-6),
        BackgroundColor3=Colors.Accent,Parent=Bar})
    Create("UICorner",{CornerRadius=UDim.new(0,6),Parent=Knob})
    local Btn=Create("TextButton",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text="",Parent=Bar})
    local draggingSlider=false
    local function update(input)
        local percent=math.clamp((input.Position.X-Bar.AbsolutePosition.X)/Bar.AbsoluteSize.X,0,1)
        local val=min+(max-min)*percent
        if max<=1 or (max-min)<10 then val=math.round(val*1000)/1000 else val=math.floor(val) end
        TweenS:Create(Fill,TweenInfo.new(0.05),{Size=UDim2.new(percent,0,1,0)}):Play()
        TweenS:Create(Knob,TweenInfo.new(0.05),{Position=UDim2.new(percent,-6,0.5,-6)}):Play()
        ValLabel.Text=tostring(val); if callback then callback(val) end
    end
    Btn.InputBegan:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingSlider=true; update(input) end end)
    UIS.InputEnded:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingSlider=false end end)
    UIS.InputChanged:Connect(function(input) if draggingSlider and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then update(input) end end)
end

local function CreateDropdown(name, options, default, parent, callback)
    local frame=Create("Frame",{Size=UDim2.new(1,0,0,45),BackgroundTransparency=1,Parent=parent})
    Create("TextLabel",{Text=name,Size=UDim2.new(1,0,0,15),BackgroundTransparency=1,
        TextColor3=Colors.Text,Font=Enum.Font.Gotham,TextSize=12,TextXAlignment=Enum.TextXAlignment.Left,Parent=frame})
    local Btn=Create("TextButton",{Size=UDim2.new(1,0,0,24),Position=UDim2.new(0,0,0,18),
        BackgroundColor3=Colors.Element,Text="",Parent=frame})
    Create("UICorner",{CornerRadius=UDim.new(0,4),Parent=Btn})
    local Label=Create("TextLabel",{Text=default,Size=UDim2.new(1,-20,1,0),Position=UDim2.new(0,5,0,0),
        BackgroundTransparency=1,TextColor3=Colors.Text,Font=Enum.Font.Gotham,TextSize=12,
        TextXAlignment=Enum.TextXAlignment.Left,Parent=Btn})
    Create("TextLabel",{Text="v",Size=UDim2.new(0,20,1,0),Position=UDim2.new(1,-20,0,0),
        BackgroundTransparency=1,TextColor3=Colors.Accent,Font=Enum.Font.GothamBold,TextSize=12,Parent=Btn})
    local currentIndex=1
    for i,v in ipairs(options) do if v==default then currentIndex=i; break end end
    Btn.MouseButton1Click:Connect(function()
        currentIndex=currentIndex%#options+1
        Label.Text=options[currentIndex]
        if callback then callback(options[currentIndex]) end
    end)
end

-- ════════════════════════════════════════════════════════════
--  POPULATE PAGES
-- ════════════════════════════════════════════════════════════

-- COMBAT
CreateHeader("GENERAL", CombatPage)
CreateToggle("Rage (Master)", function() return getgenv().Config.Enabled end, function(v) getgenv().Config.Enabled=v end, CombatPage, Colors.Green)
CreateDropdown("Weapon Slot", {"Primary","Secondary","Melee"}, getgenv().Config.WeaponSlot, CombatPage, function(val) getgenv().Config.WeaponSlot=val end)
CreateToggle("Lowest Health Target", function() return getgenv().Config.LowestHealth end, function(v) getgenv().Config.LowestHealth=v end, CombatPage)
CreateSlider("Fire Rate (0=inst)", 0, 0.1, getgenv().Config.FireRate, CombatPage, function(val) getgenv().Config.FireRate=val end)
CreateSlider("Max Distance", 50, 1000, getgenv().Config.MaxDist, CombatPage, function(val) getgenv().Config.MaxDist=val end)

-- DESYNC
CreateHeader("DESYNC SETTINGS", DesyncPage)
CreateDropdown("Desync Mode", {"KnifeAware","Jitter","Orbit","Off"}, getgenv().Config.DesyncMode, DesyncPage, function(val) getgenv().Config.DesyncMode=val end)
CreateSlider("Knife Hover Height", 5, 15, getgenv().Config.KnifeHoverHeight, DesyncPage, function(val) getgenv().Config.KnifeHoverHeight=val end)
CreateSlider("Knife Behind Offset", -8, 0, getgenv().Config.KnifeBehindOffset, DesyncPage, function(val) getgenv().Config.KnifeBehindOffset=val end)
CreateSlider("Jitter Range", 1, 8, getgenv().Config.JitterRange, DesyncPage, function(val) getgenv().Config.JitterRange=val end)
CreateSlider("Orbit Speed", 1, 12, getgenv().Config.OrbitSpeed, DesyncPage, function(val) getgenv().Config.OrbitSpeed=val end)
CreateSlider("Orbit Radius", 6, 30, getgenv().Config.OrbitRadius, DesyncPage, function(val) getgenv().Config.OrbitRadius=val end)

-- FFA
CreateHeader("FREE FOR ALL", FFAPage)
CreateToggle("FFA Mode (Boost)", function() return getgenv().Config.FFAMode end, function(v) getgenv().Config.FFAMode=v end, FFAPage)
CreateToggle("FFA Fire Boost", function() return getgenv().Config.FFAFireBoost end, function(v) getgenv().Config.FFAFireBoost=v end, FFAPage)
CreateToggle("FFA Auto-Respawn", function() return getgenv().FFA.AutoRespawn end, function(v) getgenv().FFA.AutoRespawn=v end, FFAPage)
CreateToggle("FFA Drop Vacuum", function() return getgenv().FFA.DropVacuum end, function(v) getgenv().FFA.DropVacuum=v end, FFAPage)
local UnloadBtn=Create("TextButton",{Size=UDim2.new(1,0,0,28),BackgroundColor3=Colors.Element,
    Text="Unload Script",TextColor3=Colors.Text,Font=Enum.Font.GothamBold,TextSize=12,Parent=FFAPage})
Create("UICorner",{CornerRadius=UDim.new(0,4),Parent=UnloadBtn})
UnloadBtn.MouseButton1Click:Connect(function()
    pcall(function() mainConn:Disconnect() end)
    pcall(function() kiciaConn:Disconnect() end)
    pcall(function() KiciaBridge.KiciaRagebot.Destroy() end)
    ScreenGui:Destroy()
end)

-- KICIA TAB  ← new tab with all kernel controls wired live
CreateHeader("KICIA KERNEL", KiciaPage)
CreateToggle("Prioritize Hackers", function() return KiciaToggles.P8S4T4.Value end, function(v) KiciaToggles.P8S4T4.Value=v end, KiciaPage, Colors.KAccent)
CreateToggle("Use Primary", function() return KiciaToggles.P8S4T5.Value end, function(v) KiciaToggles.P8S4T5.Value=v end, KiciaPage, Colors.KAccent)
CreateToggle("Use Secondary", function() return KiciaToggles.P8S4T6.Value end, function(v) KiciaToggles.P8S4T6.Value=v end, KiciaPage, Colors.KAccent)
CreateToggle("Use Melee", function() return KiciaToggles.P8S4T7.Value end, function(v) KiciaToggles.P8S4T7.Value=v end, KiciaPage, Colors.KAccent)
CreateToggle("Anchor From Character", function() return KiciaToggles.P8S4T8.Value end, function(v) KiciaToggles.P8S4T8.Value=v end, KiciaPage, Colors.KAccent)
CreateHeader("", KiciaPage)
CreateDropdown("On Empty", {"SwapOrReload","Swap","Reload"}, KiciaOptions.P8S4D1.Value, KiciaPage, function(val) KiciaOptions.P8S4D1.Value=val end)
CreateDropdown("Evasion Mode", {"Random","Translocate","ProjectileBreaker","Off"}, KiciaOptions.P8S4D2.Value, KiciaPage, function(val) KiciaOptions.P8S4D2.Value=val end)
CreateHeader("", KiciaPage)
CreateSlider("Stability", 0, 5, KiciaOptions.P8S4S1.Value, KiciaPage, function(val) KiciaOptions.P8S4S1.Value=val end)
CreateSlider("Shoot Frames", 1, 10, KiciaOptions.P8S4S2.Value, KiciaPage, function(val) KiciaOptions.P8S4S2.Value=val end)
CreateSlider("Translocate Offset", -20, 0, KiciaOptions.P8S4S3.Value, KiciaPage, function(val) KiciaOptions.P8S4S3.Value=val end)
CreateSlider("Radius Factor", 0, 5, KiciaOptions.P8S4S5.Value, KiciaPage, function(val) KiciaOptions.P8S4S5.Value=val end)

-- Auto-resize canvases
local function UpdateCanvas(page)
    local layout=page:FindFirstChildOfClass("UIListLayout")
    if not layout then return end
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize=UDim2.new(0,0,0,layout.AbsoluteContentSize.Y+10)
    end)
    task.wait()
    page.CanvasSize=UDim2.new(0,0,0,layout.AbsoluteContentSize.Y+10)
end
UpdateCanvas(CombatPage); UpdateCanvas(DesyncPage); UpdateCanvas(FFAPage); UpdateCanvas(KiciaPage)

-- RightShift hotkey
UIS.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode==Enum.KeyCode.RightShift then
        getgenv().Config.Enabled = not getgenv().Config.Enabled
    end
end)

SwitchTab(CombatPage, CombatBtn)

-- ── Cleanup ───────────────────────────────────────────────────
getgenv()._MRB_Cleanup = function()
    pcall(function() mainConn:Disconnect() end)
    pcall(function() kiciaConn:Disconnect() end)
    pcall(function() KiciaBridge.KiciaRagebot.Destroy() end)
    pcall(function() ScreenGui:Destroy() end)
    getgenv()._MRB_Cleanup=nil
end

print("[MergedRagebot v1] Loaded ✓ — Combat + Desync + FFA + Kicia tabs")
print("[MergedRagebot v1] RightShift = toggle rage")
