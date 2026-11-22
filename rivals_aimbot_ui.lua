--[[
    Rivals Cheat Suite  ×  ObsidianLib UI
    ───────────────────────────────────────
    Tabs:
      Combat  → [Aimbot] subtab  |  [Silent Aim] subtab
      Visuals → ESP
      Misc    → Skin Changer
      Settings
]]

-- ── ObsidianLib ───────────────────────────────────────────────────────────────
local Library = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/visnoukkk/ObsidianLib/refs/heads/main/Library.lua"
))()

local Window = Library:CreateWindow({
    Title  = "Rivals Suite",
    Footer = "by brody",
})

-- ── Top-level tabs ────────────────────────────────────────────────────────────
local CombatTab   = Window:AddTab("Combat",   "sword")
local VisualTab   = Window:AddTab("Visuals",  "eye")
local MiscTab     = Window:AddTab("Misc",     "star")
local SettingsTab = Window:AddTab("Settings", "settings")

-- ── Combat sub-tabs ───────────────────────────────────────────────────────────
local AimbotTab    = CombatTab:AddSubTab("Aimbot")
local SilentAimTab = CombatTab:AddSubTab("Silent Aim")

-- ── Services ──────────────────────────────────────────────────────────────────
local cloneref   = cloneref   or function(x) return x end
local Players    = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UIS        = cloneref(game:GetService("UserInputService"))
local Workspace  = cloneref(game:GetService("Workspace"))

local LP     = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = Workspace.CurrentCamera
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  SHARED CONFIG
--  FOVSize is ONE value used by both Aimbot and Silent Aim.
--  Changing either slider writes to CFG.FOVSize.
-- ═══════════════════════════════════════════════════════════════════════════════
local CFG = {
    -- ── shared / aimbot ──────────────────────────────
    AimEnabled   = false,
    AimMode      = "Spring",       -- "Lock" | "Spring" | "Linear"
    Smoothness   = 0.15,
    FOVSize      = 500,            -- SHARED with Silent Aim
    HitPart      = "Head",         -- shared with SA as default
    ShowFOV      = true,
    TeamCheck    = true,
    WallCheck    = true,
    MaxDistance  = 2000,
    FOVColor     = Color3.fromRGB(255, 255, 255),

    -- ── silent aim ───────────────────────────────────
    SAEnabled      = false,
    SAHitChance    = 100,
    SAHitPart      = "Head",
    SATeamCheck    = true,
    SAWallCheck    = true,
    SAJitterDeg    = 1.5,
    SAPredictLead  = true,
    SALeadCap      = 15,
    SAMultipoint   = false,
    SAMultipointN  = 5,
    SATorsoFallback= true,

    -- ── esp ──────────────────────────────────────────
    ESPEnabled    = false,
    ESPBox        = true,
    ESPName       = true,
    ESPHealthBar  = true,
    ESPTracer     = false,
    ESPTeamCheck  = true,
    ESPMaxDist    = 2000,
    ESPEnemyColor = Color3.fromRGB(235, 64, 80),
    ESPTeamColor  = Color3.fromRGB(50, 200, 100),
    ESPTracerOrigin = "Bottom",
}

-- ═══════════════════════════════════════════════════════════════════════════════
--  DRAWING HELPERS
-- ═══════════════════════════════════════════════════════════════════════════════
local drawOK = pcall(function() local d=Drawing.new("Line") d:Remove() end)
local function newDraw(t, props)
    if not drawOK then return setmetatable({},{__index=function() return function()end end}) end
    local ok, d = pcall(Drawing.new, t)
    if not ok then return setmetatable({},{__index=function() return function()end end}) end
    for k,v in pairs(props) do pcall(function() d[k]=v end) end
    return d
end

-- ── FOV Circle ────────────────────────────────────────────────────────────────
local FOVCircle = newDraw("Circle",{
    Thickness=1.5, Color=CFG.FOVColor, Filled=false, Visible=false, NumSides=64
})

-- ═══════════════════════════════════════════════════════════════════════════════
--  ESP POOL
-- ═══════════════════════════════════════════════════════════════════════════════
local ESPPool = {}
local function newLine(c) return newDraw("Line",{Color=c,Thickness=1.2,Visible=false}) end

local function newESPFor(plr)
    if ESPPool[plr] then return end
    local c = CFG.ESPEnemyColor
    ESPPool[plr] = {
        box = { top=newLine(c), bottom=newLine(c), left=newLine(c), right=newLine(c) },
        name   = newDraw("Text",{Color=Color3.new(1,1,1),Size=13,Font=2,
                    Outline=true,OutlineColor=Color3.new(0,0,0),
                    Visible=false,Text=plr.Name,Center=true}),
        hbarBg = newLine(Color3.fromRGB(0,0,0)),
        hbarFg = newLine(Color3.fromRGB(50,230,80)),
        tracer = newLine(c),
    }
    ESPPool[plr].hbarBg.Thickness = 3
    ESPPool[plr].hbarFg.Thickness = 2
end
local function removeESPFor(plr)
    local e = ESPPool[plr]; if not e then return end
    for _,ln in pairs(e.box) do pcall(function() ln:Remove() end) end
    pcall(function() e.name:Remove() end)
    pcall(function() e.hbarBg:Remove() end)
    pcall(function() e.hbarFg:Remove() end)
    pcall(function() e.tracer:Remove() end)
    ESPPool[plr] = nil
end
local function hideESP(e)
    for _,ln in pairs(e.box) do ln.Visible=false end
    e.name.Visible=false e.hbarBg.Visible=false e.hbarFg.Visible=false e.tracer.Visible=false
end
for _,p in ipairs(Players:GetPlayers()) do if p~=LP then newESPFor(p) end end
Players.PlayerAdded:Connect(function(p) if p~=LP then newESPFor(p) end end)
Players.PlayerRemoving:Connect(removeESPFor)

-- ═══════════════════════════════════════════════════════════════════════════════
--  SHARED CHARACTER HELPERS
-- ═══════════════════════════════════════════════════════════════════════════════
local HEAD_PARTS  = {"HitboxHead","HitboxHeadSmall","Head"}
local TORSO_PARTS = {"HitboxBody","UpperTorso","HumanoidRootPart","LowerTorso"}
local CLOSE_PARTS = {
    "HitboxHead","Head","UpperTorso","LowerTorso","HumanoidRootPart",
    "LeftHand","RightHand","LeftFoot","RightFoot",
    "LeftUpperArm","RightUpperArm","LeftUpperLeg","RightUpperLeg",
}
local BOUND_PARTS = {
    "Head","HumanoidRootPart","UpperTorso","LowerTorso",
    "LeftUpperArm","RightUpperArm","LeftUpperLeg","RightUpperLeg",
    "HitboxHead","HitboxBody",
}

local function getPart(char, hitPartCfg)
    local hp = hitPartCfg or CFG.HitPart
    if hp == "Closest" then
        local center = Vector2.new(Camera.ViewportSize.X*.5, Camera.ViewportSize.Y*.5)
        local best, bestD = nil, math.huge
        for _,name in ipairs(CLOSE_PARTS) do
            local p = char:FindFirstChild(name)
            if p and p:IsA("BasePart") then
                local sp,on = Camera:WorldToViewportPoint(p.Position)
                if on and sp.Z>0 then
                    local d=(Vector2.new(sp.X,sp.Y)-center).Magnitude
                    if d<bestD then best,bestD=p,d end
                end
            end
        end
        if best then return best end
    end
    local list = hp=="Body" and TORSO_PARTS or HEAD_PARTS
    for _,name in ipairs(list) do
        local p=char:FindFirstChild(name)
        if p and p:IsA("BasePart") then return p end
    end
    return char:FindFirstChild("HumanoidRootPart")
end

local function isTeammate(plr)
    if plr==LP then return true end
    local a=LP:GetAttribute("TeamID"); local b=plr:GetAttribute("TeamID")
    if a~=nil and b~=nil then return a==b end
    if LP.Team and plr.Team then return LP.Team==plr.Team end
    return false
end

local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
local _wallChar = nil
local function canSee(pos)
    local myChar=LP.Character
    if myChar~=_wallChar then wallParams.FilterDescendantsInstances={myChar} _wallChar=myChar end
    local origin=Camera.CFrame.Position
    local result=Workspace:Raycast(origin, pos-origin, wallParams)
    if not result then return true end
    local model=result.Instance and result.Instance:FindFirstAncestorOfClass("Model")
    return model~=nil and Players:GetPlayerFromCharacter(model)~=nil
end

local function getScreenBounds(char)
    local minX,minY,maxX,maxY = math.huge,math.huge,-math.huge,-math.huge
    local any=false
    for _,name in ipairs(BOUND_PARTS) do
        local p=char:FindFirstChild(name)
        if p and p:IsA("BasePart") then
            local sp,on=Camera:WorldToViewportPoint(p.Position)
            if on and sp.Z>0 then
                any=true
                if sp.X<minX then minX=sp.X end if sp.Y<minY then minY=sp.Y end
                if sp.X>maxX then maxX=sp.X end if sp.Y>maxY then maxY=sp.Y end
            end
        end
    end
    if not any then return nil end
    return minX-4, minY-4, maxX+4, maxY+4
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  AIMBOT LOGIC
-- ═══════════════════════════════════════════════════════════════════════════════
local function getAimTarget()
    local center=Vector2.new(Camera.ViewportSize.X*.5, Camera.ViewportSize.Y*.5)
    local best,bestPart,bestDist=nil,nil,math.huge
    local myChar=LP.Character
    local myRoot=myChar and myChar:FindFirstChild("HumanoidRootPart")
    for _,plr in ipairs(Players:GetPlayers()) do
        if plr==LP then continue end
        if CFG.TeamCheck and isTeammate(plr) then continue end
        local char=plr.Character
        local hum=char and char:FindFirstChildOfClass("Humanoid")
        local hrp=char and char:FindFirstChild("HumanoidRootPart")
        if not(char and hum and hrp and hum.Health>0) then continue end
        if myRoot and (hrp.Position-myRoot.Position).Magnitude>CFG.MaxDistance then continue end
        local part=getPart(char, CFG.HitPart)
        if not part then continue end
        local sp,on=Camera:WorldToViewportPoint(part.Position)
        if not on or sp.Z<=0 then continue end
        local d2=(Vector2.new(sp.X,sp.Y)-center).Magnitude
        if CFG.FOVSize>0 and d2>CFG.FOVSize then continue end
        if CFG.WallCheck and not canSee(part.Position) then continue end
        if d2<bestDist then bestDist=d2 best=plr bestPart=part end
    end
    return best, bestPart
end

local spring={pos=Vector3.zero, init=false}
local function aimSpring(tp, dt)
    if not spring.init then spring.pos=Camera.CFrame.LookVector+Camera.CFrame.Position spring.init=true end
    local alpha=1-math.exp(-(1+(1-CFG.Smoothness)*20)*dt)
    spring.pos=spring.pos:Lerp(tp, alpha)
    return CFrame.new(Camera.CFrame.Position, spring.pos)
end
local function aimLinear(tp, dt)
    local goal=CFrame.new(Camera.CFrame.Position, tp)
    local alpha=1-math.exp(-(1+(1-CFG.Smoothness)*25)*dt)
    return Camera.CFrame:Lerp(goal, math.clamp(alpha,0,1))
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  SILENT AIM LOGIC
-- ═══════════════════════════════════════════════════════════════════════════════
local c0,c1,c2,c3,c4,c5=utf8.char(0),utf8.char(1),utf8.char(2),utf8.char(3),utf8.char(4),utf8.char(5)
local function encodeCFrame(cf)
    local rx,ry,rz=cf:ToOrientation()
    return {[c0]=cf.X,[c1]=cf.Y,[c2]=cf.Z,[c3]=rx,[c4]=ry,[c5]=rz}
end

local visParams=RaycastParams.new()
visParams.FilterType=Enum.RaycastFilterType.Exclude
local _visChar=nil
local function isVisible(worldPos)
    local origin=Camera.CFrame.Position
    local myChar=LP.Character
    if myChar~=_visChar then visParams.FilterDescendantsInstances={myChar} _visChar=myChar end
    local result=Workspace:Raycast(origin, worldPos-origin, visParams)
    if not result then return true end
    local hitModel=result.Instance and result.Instance:FindFirstAncestorOfClass("Model")
    if hitModel and Players:GetPlayerFromCharacter(hitModel) then return true end
    return (result.Position-worldPos).Magnitude<3
end

local function isPartVisible(part)
    if not part or not part:IsA("BasePart") then return false end
    if not CFG.SAMultipoint then return isVisible(part.Position) end
    if isVisible(part.Position) then return true end
    local n=math.max(1, CFG.SAMultipointN)
    local r=math.min(part.Size.X, part.Size.Y, part.Size.Z)*0.4
    for i=1,n do
        local a=(i/n)*math.pi*2
        local off=Vector3.new(math.cos(a)*r,((i%2==0) and 0.5 or -0.5)*r, math.sin(a)*r)
        if isVisible(part.Position+off) then return true end
    end
    return false
end

local function findBestPartSA(char)
    local primary=getPart(char, CFG.SAHitPart)
    if isPartVisible(primary) then return primary end
    if CFG.SAHitPart~="Body" then
        for _,name in ipairs(HEAD_PARTS) do
            local p=char:FindFirstChild(name)
            if p and p~=primary and isPartVisible(p) then return p end
        end
    end
    if CFG.SATorsoFallback then
        for _,name in ipairs(TORSO_PARTS) do
            local p=char:FindFirstChild(name)
            if p and isPartVisible(p) then return p end
        end
    end
    return primary
end

-- velocity tracker for lead
local _velMap,_velPos,_velTime,_velAccum={},{},{},0
RunService.Heartbeat:Connect(function(dt)
    _velAccum+=dt
    if _velAccum<1/30 then return end _velAccum=0
    local now=tick()
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LP and p.Character then
            local hrp=p.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local pos=hrp.Position; local lt=_velTime[p]
                if _velPos[p] and lt then
                    local d=now-lt
                    if d>0 then
                        local v=(pos-_velPos[p])/d
                        if v.Magnitude<500 then _velMap[p]=v end
                    end
                end
                _velPos[p]=pos _velTime[p]=now
            end
        end
    end
end)

local function getVelocityLead(targetChar, fromPos)
    if not CFG.SAPredictLead or not targetChar then return Vector3.zero end
    local hrp=targetChar:FindFirstChild("HumanoidRootPart")
    if not hrp then return Vector3.zero end
    local plr=Players:GetPlayerFromCharacter(targetChar)
    local lat=(LP:GetNetworkPing() or 0.05)+0.03
    local tv=hrp.AssemblyLinearVelocity
    local cv=plr and _velMap[plr]
    if cv then if(tv-cv).Magnitude>25 then tv=cv end
    else if tv.Magnitude>100 then return Vector3.zero end end
    if tv.Magnitude>120 then return Vector3.zero end
    local lead=Vector3.new(tv.X,0,tv.Z)*lat+Vector3.new(0,tv.Y*lat,0)
    if lead.Magnitude>CFG.SALeadCap then lead=lead.Unit*CFG.SALeadCap end
    return lead
end

local function lookCF(from, to)
    local dir=to-from
    if dir.Magnitude<1e-4 then dir=Vector3.new(0,-1,0) end
    local up=Vector3.new(0,1,0)
    if math.abs(dir.Unit.Y)>0.999 then up=Vector3.new(0,0,1) end
    return CFrame.lookAt(from, from+dir, up)
end

local SA_lastTarget=nil
local function saSelectTarget()
    local center=Vector2.new(Camera.ViewportSize.X*.5, Camera.ViewportSize.Y*.5)
    local best,bestPart,bestScore=nil,nil,math.huge
    local myChar=LP.Character
    local myRoot=myChar and myChar:FindFirstChild("HumanoidRootPart")
    for _,plr in ipairs(Players:GetPlayers()) do
        if plr==LP then continue end
        if CFG.SATeamCheck and isTeammate(plr) then continue end
        local char=plr.Character
        local hum=char and char:FindFirstChildOfClass("Humanoid")
        local hrp=char and char:FindFirstChild("HumanoidRootPart")
        if not(char and hum and hrp and hum.Health>0) then continue end
        if myRoot and (hrp.Position-myRoot.Position).Magnitude>2000 then continue end
        local part=getPart(char, CFG.SAHitPart)
        if not part then continue end
        local sp,on=Camera:WorldToViewportPoint(part.Position)
        if not on or sp.Z<=0 then continue end
        local d=(Vector2.new(sp.X,sp.Y)-center).Magnitude
        if CFG.FOVSize>0 and d>CFG.FOVSize then continue end   -- SHARED FOV
        local score=d
        if plr==SA_lastTarget then score*=0.95 end
        if score<bestScore then bestScore=score best=plr bestPart=part end
    end
    return best, bestPart
end

local function redirectCameraData(cameraData, targetChar, hitPart)
    if not(cameraData and hitPart and hitPart:IsA("BasePart")) then return false end
    local camPos=Camera.CFrame.Position
    local lead=getVelocityLead(targetChar, camPos)
    local jit=Vector3.zero
    if CFG.SAJitterDeg>0 then
        local ok,dir=pcall(function() return Vector3.new(math.random()-.5,math.random()-.5,math.random()-.5) end)
        if ok and dir.Magnitude>1e-4 then
            local dist=(hitPart.Position-camPos).Magnitude
            local off=math.min(math.tan(math.rad(CFG.SAJitterDeg))*dist,3)*(math.random()*.5)
            jit=dir.Unit*off
        end
    end
    local aimPos=hitPart.Position+lead+jit
    local objSpace=hitPart.CFrame:PointToObjectSpace(aimPos)
    local hs=hitPart.Size*0.45
    objSpace=Vector3.new(
        math.clamp(objSpace.X,-hs.X,hs.X),
        math.clamp(objSpace.Y,-hs.Y,hs.Y),
        math.clamp(objSpace.Z,-hs.Z,hs.Z)
    )
    local hitWorld=hitPart.CFrame:PointToWorldSpace(objSpace)
    local objSpaceCF=hitPart.CFrame:ToObjectSpace(CFrame.new(hitWorld))
    local eyeCF=lookCF(camPos, hitWorld)
    local muzzlePos=camPos+eyeCF.RightVector*0.2+Vector3.new(0,-0.07,0)
    local muzzleCF=lookCF(muzzlePos, hitWorld)
    cameraData[c0]=encodeCFrame(eyeCF)
    cameraData[c1]=encodeCFrame(muzzleCF)
    cameraData[c2]=hitPart
    cameraData[c3]=encodeCFrame(objSpaceCF)
    return true
end

-- ── Gun hook ──────────────────────────────────────────────────────────────────
local _hookLive=false
local _origStartShooting=nil
local function installHook()
    if _hookLive then return end
    local ok,GunModule=pcall(function() return require(LP.PlayerScripts.Modules.ItemTypes.Gun) end)
    if not ok or type(GunModule)~="table" then warn("[SA] Gun module not ready, retrying…") return false end
    local orig=GunModule.StartShooting
    if type(orig)~="function" then warn("[SA] StartShooting not found") return false end
    _origStartShooting=orig
    local hooked=function(self,...)
        local results={orig(self,...)}
        pcall(function()
            if not CFG.SAEnabled then return end
            if results[1]~=true then return end
            if not(self.ClientFighter and self.ClientFighter.IsLocalPlayer) then return end
            local cameraData=results[3]
            if type(cameraData)~="table" then return end
            if math.random(1,100)>CFG.SAHitChance then return end
            local tgt,primaryPart=saSelectTarget()
            if not(tgt and primaryPart) then return end
            SA_lastTarget=tgt
            local char=tgt.Character; if not char then return end
            if CFG.SAWallCheck then
                redirectCameraData(cameraData, char, findBestPartSA(char))
            else
                redirectCameraData(cameraData, char, primaryPart)
            end
        end)
        return table.unpack(results)
    end
    if setfenv then pcall(setfenv, hooked, getfenv(orig)) end
    if setreadonly then pcall(setreadonly, GunModule, false) end
    GunModule.StartShooting=hooked
    _hookLive=true
    print("[SA] Hook installed ✓")
    return true
end
task.spawn(function() for _=1,60 do if installHook() then break end task.wait(0.5) end end)
LP.CharacterAdded:Connect(function() task.wait(0.5) installHook() end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  ESP UPDATER
-- ═══════════════════════════════════════════════════════════════════════════════
local function updateESP()
    if not CFG.ESPEnabled then for _,e in pairs(ESPPool) do hideESP(e) end return end
    local myChar=LP.Character
    local myRoot=myChar and myChar:FindFirstChild("HumanoidRootPart")
    local vp=Camera.ViewportSize
    local tracerY = CFG.ESPTracerOrigin=="Top" and 0
                 or CFG.ESPTracerOrigin=="Center" and vp.Y*.5
                 or vp.Y
    local tracerFrom=Vector2.new(vp.X*.5, tracerY)
    for _,plr in ipairs(Players:GetPlayers()) do
        if plr==LP then continue end
        local e=ESPPool[plr]; if not e then continue end
        local char=plr.Character
        local hum=char and char:FindFirstChildOfClass("Humanoid")
        local hrp=char and char:FindFirstChild("HumanoidRootPart")
        if not(char and hum and hrp and hum.Health>0) then hideESP(e) continue end
        if myRoot and (hrp.Position-myRoot.Position).Magnitude>CFG.ESPMaxDist then hideESP(e) continue end
        local mate=isTeammate(plr)
        if CFG.ESPTeamCheck and mate then hideESP(e) continue end
        local minX,minY,maxX,maxY=getScreenBounds(char)
        if not minX then hideESP(e) continue end
        local color=mate and CFG.ESPTeamColor or CFG.ESPEnemyColor
        -- box
        local tl,tr=Vector2.new(minX,minY),Vector2.new(maxX,minY)
        local bl,br=Vector2.new(minX,maxY),Vector2.new(maxX,maxY)
        e.box.top.From=tl; e.box.top.To=tr
        e.box.bottom.From=bl; e.box.bottom.To=br
        e.box.left.From=tl; e.box.left.To=bl
        e.box.right.From=tr; e.box.right.To=br
        for _,ln in pairs(e.box) do ln.Color=color ln.Visible=CFG.ESPBox end
        -- name
        e.name.Position=Vector2.new((minX+maxX)*.5, minY-15)
        e.name.Visible=CFG.ESPName
        -- health bar
        local hp=hum.Health; local maxHp=hum.MaxHealth>0 and hum.MaxHealth or 100
        local ratio=math.clamp(hp/maxHp,0,1)
        local barH=maxY-minY; local barX=minX-5
        e.hbarBg.From=Vector2.new(barX,minY); e.hbarBg.To=Vector2.new(barX,maxY)
        e.hbarBg.Visible=CFG.ESPHealthBar
        local r=math.clamp(2*(1-ratio),0,1); local g=math.clamp(2*ratio,0,1)
        e.hbarFg.Color=Color3.new(r,g,0)
        e.hbarFg.From=Vector2.new(barX,maxY); e.hbarFg.To=Vector2.new(barX,maxY-barH*ratio)
        e.hbarFg.Visible=CFG.ESPHealthBar
        -- tracer
        e.tracer.From=tracerFrom; e.tracer.To=Vector2.new((minX+maxX)*.5, maxY)
        e.tracer.Color=color; e.tracer.Visible=CFG.ESPTracer
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  RENDER LOOP
-- ═══════════════════════════════════════════════════════════════════════════════
local lastT=tick(); local prevTarget=nil
RunService:BindToRenderStep("RivalsCheat", Enum.RenderPriority.Camera.Value+1, function()
    local now=tick(); local dt=math.clamp(now-lastT,0,0.1); lastT=now
    -- FOV
    if FOVCircle.Visible~=nil then
        FOVCircle.Position=Vector2.new(Camera.ViewportSize.X*.5, Camera.ViewportSize.Y*.5)
        FOVCircle.Radius=CFG.FOVSize>0 and CFG.FOVSize or 0
        FOVCircle.Color=CFG.FOVColor
        FOVCircle.Visible=CFG.ShowFOV and CFG.FOVSize>0 and (CFG.AimEnabled or CFG.SAEnabled)
    end
    -- ESP
    updateESP()
    -- Aimbot
    if not CFG.AimEnabled then spring.init=false prevTarget=nil return end
    local tgt,part=getAimTarget()
    if tgt~=prevTarget then spring.init=false prevTarget=tgt end
    if not(tgt and part) then spring.init=false return end
    if CFG.AimMode=="Lock" then Camera.CFrame=CFrame.new(Camera.CFrame.Position,part.Position)
    elseif CFG.AimMode=="Spring" then Camera.CFrame=aimSpring(part.Position,dt)
    elseif CFG.AimMode=="Linear" then Camera.CFrame=aimLinear(part.Position,dt)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  UI  —  COMBAT → [Aimbot] subtab
-- ═══════════════════════════════════════════════════════════════════════════════
local AimCore   = AimbotTab:AddLeftGroupbox("Core")
local AimFilter = AimbotTab:AddRightGroupbox("Filters")
local AimFOV    = AimbotTab:AddLeftGroupbox("FOV")

AimCore:AddToggle("AimEnabled",{
    Text="Enable Aimbot", Default=CFG.AimEnabled,
    Callback=function(v) CFG.AimEnabled=v if not v then spring.init=false end end,
})
AimCore:AddDropdown("AimMode",{
    Text="Mode", Values={"Lock","Spring","Linear"}, Default=CFG.AimMode,
    Callback=function(v) CFG.AimMode=v spring.init=false end,
})
AimCore:AddDropdown("AimHitPart",{
    Text="Hit Part", Values={"Head","Body","Closest"}, Default=CFG.HitPart,
    Callback=function(v) CFG.HitPart=v end,
})
AimCore:AddSlider("AimSmooth",{
    Text="Smoothness", Default=math.floor(CFG.Smoothness*100),
    Min=1, Max=100, Rounding=0, Suffix="%",
    Callback=function(v) CFG.Smoothness=v/100 spring.init=false end,
})
AimCore:AddSlider("AimMaxDist",{
    Text="Max Distance (studs)", Default=CFG.MaxDistance,
    Min=50, Max=5000, Rounding=0,
    Callback=function(v) CFG.MaxDistance=v end,
})

-- shared FOV slider (aimbot side)
AimFOV:AddToggle("AimShowFOV",{
    Text="Show FOV Circle", Default=CFG.ShowFOV,
    Callback=function(v) CFG.ShowFOV=v end,
})
AimFOV:AddSlider("SharedFOV",{
    Text="FOV Radius (px) [shared]", Default=CFG.FOVSize,
    Min=0, Max=1000, Rounding=0,
    Callback=function(v)
        CFG.FOVSize=v
        -- sync SA slider if it exists
        if Library.Options.SAFOVSync then Library.Options.SAFOVSync:SetValue(v) end
    end,
})
if AimFOV.AddColorPicker then
    AimFOV:AddColorPicker("AimFOVColor",{
        Text="FOV Color", Default=CFG.FOVColor,
        Callback=function(v) CFG.FOVColor=v if FOVCircle.Color~=nil then FOVCircle.Color=v end end,
    })
end

AimFilter:AddToggle("AimTeamCheck",{Text="Team Check",Default=CFG.TeamCheck,Callback=function(v) CFG.TeamCheck=v end})
AimFilter:AddToggle("AimWallCheck",{Text="Wall Check",Default=CFG.WallCheck,Callback=function(v) CFG.WallCheck=v end})

-- ═══════════════════════════════════════════════════════════════════════════════
--  UI  —  COMBAT → [Silent Aim] subtab
-- ═══════════════════════════════════════════════════════════════════════════════
local SACore    = SilentAimTab:AddLeftGroupbox("Core")
local SAAdv     = SilentAimTab:AddRightGroupbox("Advanced")
local SAFOVGrp  = SilentAimTab:AddLeftGroupbox("FOV (shared)")

SACore:AddToggle("SAEnabled",{
    Text="Enable Silent Aim", Default=CFG.SAEnabled,
    Callback=function(v) CFG.SAEnabled=v end,
})
SACore:AddSlider("SAHitChance",{
    Text="Hit Chance", Default=CFG.SAHitChance,
    Min=1, Max=100, Rounding=0, Suffix="%",
    Callback=function(v) CFG.SAHitChance=v end,
})
SACore:AddDropdown("SAHitPart",{
    Text="Hit Part", Values={"Head","Body","Closest"}, Default=CFG.SAHitPart,
    Callback=function(v) CFG.SAHitPart=v end,
})
SACore:AddToggle("SATeamCheck",{Text="Team Check",Default=CFG.SATeamCheck,Callback=function(v) CFG.SATeamCheck=v end})
SACore:AddToggle("SAWallCheck",{Text="Wall Check",Default=CFG.SAWallCheck,Callback=function(v) CFG.SAWallCheck=v end})
SACore:AddToggle("SATorsoFallback",{Text="Torso Fallback",Default=CFG.SATorsoFallback,Callback=function(v) CFG.SATorsoFallback=v end})

SAAdv:AddSlider("SAJitter",{
    Text="Jitter (°)", Default=math.floor(CFG.SAJitterDeg*10)/10,
    Min=0, Max=10, Rounding=1,
    Callback=function(v) CFG.SAJitterDeg=v end,
})
SAAdv:AddToggle("SAPredictLead",{Text="Predictive Lead",Default=CFG.SAPredictLead,Callback=function(v) CFG.SAPredictLead=v end})
SAAdv:AddSlider("SALeadCap",{
    Text="Lead Cap (studs)", Default=CFG.SALeadCap,
    Min=1, Max=50, Rounding=0,
    Callback=function(v) CFG.SALeadCap=v end,
})
SAAdv:AddToggle("SAMultipoint",{Text="Multipoint Check",Default=CFG.SAMultipoint,Callback=function(v) CFG.SAMultipoint=v end})
SAAdv:AddSlider("SAMultipointN",{
    Text="Multipoint Count", Default=CFG.SAMultipointN,
    Min=2, Max=12, Rounding=0,
    Callback=function(v) CFG.SAMultipointN=v end,
})

-- shared FOV display (read-only label + mirrored slider)
SAFOVGrp:AddLabel("FOV is shared with Aimbot tab")
SAFOVGrp:AddSlider("SAFOVSync",{
    Text="FOV Radius (px) [shared]", Default=CFG.FOVSize,
    Min=0, Max=1000, Rounding=0,
    Callback=function(v)
        CFG.FOVSize=v
        if Library.Options.SharedFOV then Library.Options.SharedFOV:SetValue(v) end
    end,
})

-- ═══════════════════════════════════════════════════════════════════════════════
--  UI  —  VISUALS TAB
-- ═══════════════════════════════════════════════════════════════════════════════
local ESPGrp  = VisualTab:AddLeftGroupbox("ESP")
local ESPCol  = VisualTab:AddRightGroupbox("Colors")

ESPGrp:AddToggle("ESPEnabled",{Text="Enable ESP",Default=CFG.ESPEnabled,
    Callback=function(v) CFG.ESPEnabled=v if not v then for _,e in pairs(ESPPool) do hideESP(e) end end end})
ESPGrp:AddToggle("ESPBox",{Text="Box",Default=CFG.ESPBox,Callback=function(v) CFG.ESPBox=v end})
ESPGrp:AddToggle("ESPName",{Text="Name",Default=CFG.ESPName,Callback=function(v) CFG.ESPName=v end})
ESPGrp:AddToggle("ESPHealthBar",{Text="Health Bar",Default=CFG.ESPHealthBar,Callback=function(v) CFG.ESPHealthBar=v end})
ESPGrp:AddToggle("ESPTracer",{Text="Tracer",Default=CFG.ESPTracer,Callback=function(v) CFG.ESPTracer=v end})
ESPGrp:AddToggle("ESPTeamCheck",{Text="Hide Teammates",Default=CFG.ESPTeamCheck,Callback=function(v) CFG.ESPTeamCheck=v end})
ESPGrp:AddSlider("ESPMaxDist",{Text="Max Distance",Default=CFG.ESPMaxDist,Min=50,Max=5000,Rounding=0,Callback=function(v) CFG.ESPMaxDist=v end})
ESPGrp:AddDropdown("ESPTracerOrigin",{Text="Tracer Origin",Values={"Bottom","Center","Top"},Default=CFG.ESPTracerOrigin,Callback=function(v) CFG.ESPTracerOrigin=v end})

if ESPCol.AddColorPicker then
    ESPCol:AddColorPicker("ESPEnemyColor",{Text="Enemy",Default=CFG.ESPEnemyColor,Callback=function(v) CFG.ESPEnemyColor=v end})
    ESPCol:AddColorPicker("ESPTeamColor",{Text="Team",Default=CFG.ESPTeamColor,Callback=function(v) CFG.ESPTeamColor=v end})
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  UI  —  MISC TAB  →  Skin Changer
-- ═══════════════════════════════════════════════════════════════════════════════
local SkinGrp = MiscTab:AddLeftGroupbox("Skin Changer")
local SkinInfoGrp = MiscTab:AddRightGroupbox("Info")

-- Skin changer state
local skinActive = false
local skinWeapon = ""
local skinName   = ""

SkinInfoGrp:AddLabel("Applies cosmetics client-side only.")
SkinInfoGrp:AddLabel("Equip target weapon first.")
SkinInfoGrp:AddLabel("Saves to: Cryptic Hub/Rivals Cosmetics.json")

SkinGrp:AddToggle("SkinEnabled",{
    Text="Enable Skin Changer", Default=false,
    Callback=function(v)
        skinActive = v
        if v then
            -- lazy-load skin changer modules when first toggled on
            task.spawn(function()
                if getgenv().RivalsCosmeticsCleanup then
                    pcall(getgenv().RivalsCosmeticsCleanup)
                end
                if not game:IsLoaded() then game.Loaded:Wait() end
                local rs   = game:GetService("ReplicatedStorage")
                local http = game:GetService("HttpService")
                local plr  = Players.LocalPlayer

                local function waitFor(getter)
                    local deadline=os.clock()+90
                    while os.clock()<deadline do
                        local ok,value=pcall(getter)
                        if ok and value then return value end
                        task.wait(0.5)
                    end
                end

                local scripts     = plr:WaitForChild("PlayerScripts")
                local lib2        = waitFor(function() return require(rs.Modules.CosmeticLibrary) end)
                local replicated  = waitFor(function() return require(rs.Modules.ReplicatedClass) end)
                local vmClass     = waitFor(function() return require(scripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem.ClientViewModel) end)
                local pdc         = waitFor(function() return require(scripts.Controllers.PlayerDataController) end)
                local viewModels  = waitFor(function() return scripts.Assets.ViewModels end)
                local classes     = waitFor(function() return scripts.Modules.ViewModels end)
                local equipRemote = waitFor(function() return rs.Remotes.Data.EquipCosmetic end)

                if not(lib2 and replicated and vmClass and pdc and viewModels and classes and equipRemote) then
                    warn("[SkinChanger] game modules not ready"); return
                end

                local folder="Cryptic Hub"; local file=folder.."/Rivals Cosmetics.json"
                local slots={Skin=true,Wrap=true,Charm=true,Finisher=true}
                local added,saved,alive,swaps,swapping,moduleCache,modelCache={},{},true,{},nil,{},{}
                local oldGet=replicated.Get; local oldVmGet=rawget(vmClass,"Get")

                local function get(key)
                    local ok,val=pcall(pdc.CurrentData.Get, pdc.CurrentData, key)
                    return ok and val or nil
                end
                waitFor(function() return get("CosmeticInventory") and get("WeaponInventory") end)
                local function flush()
                    pcall(function()
                        if not isfolder(folder) then makefolder(folder) end
                        writefile(file, http:JSONEncode(saved))
                    end)
                end
                local function find2(weapon)
                    local list=get("WeaponInventory"); if not list then return end
                    for _,w in pairs(list) do if w.Name==weapon then return w end end
                end
                local inv=get("CosmeticInventory")
                for name in pairs(lib2.Cosmetics) do
                    if inv and inv[name]==nil then inv[name]=true added[name]=true end
                end
                pcall(function()
                    if isfile(file) then saved=http:JSONDecode(readfile(file)) end
                end)
                for weapon,picks in pairs(saved) do
                    local w=find2(weapon)
                    if w then
                        for slot,entry in pairs(picks) do
                            if slots[slot] and lib2.Cosmetics[entry.Name] then w[slot]=entry end
                        end
                    end
                end
                local function baseOf(name)
                    local c=lib2.Cosmetics[name]
                    if c and c.Type=="Skin" and c.ItemName then return c.ItemName end
                    return name
                end
                local function moduleOf(name)
                    local cached=moduleCache[name]
                    if cached==nil then
                        local found=classes:FindFirstChild(name,true)
                        cached=found and found:IsA("ModuleScript") and found or false
                        moduleCache[name]=cached
                    end
                    return cached or nil
                end
                local function hasModel(name)
                    local cached=modelCache[name]
                    if cached==nil then cached=viewModels:FindFirstChild(name,true)~=nil modelCache[name]=cached end
                    return cached
                end
                local function installSwap(weapon)
                    if swaps[weapon] then return end
                    local defaultModule=moduleOf(weapon); if not defaultModule then return end
                    local ok2,class=pcall(require, defaultModule)
                    if not ok2 or type(class)~="table" or type(rawget(class,"new"))~="function" then return end
                    local origNew=class.new; swaps[weapon]={class=class,origNew=origNew}
                    class.new=function(...)
                        local picks=alive and saved[weapon]; local skin=picks and picks.Skin
                        local skinModule=skin and moduleOf(skin.Name)
                        if skinModule and not swapping and hasModel(skin.Name)
                            and(skinModule.Parent==defaultModule.Parent or skinModule.Parent==defaultModule) then
                            local loaded,skinClass=pcall(require, skinModule)
                            if loaded and type(skinClass)=="table" and type(skinClass.new)=="function" then
                                swapping={weapon=weapon,skin=skin.Name}
                                local built,object=pcall(skinClass.new,...)
                                swapping=nil
                                if built then return object end
                            end
                        end
                        return origNew(...)
                    end
                end
                for weapon,picks in pairs(saved) do if picks.Skin then installSwap(weapon) end end

                replicated.Get=function(self,key)
                    if alive and slots[key] then
                        local data=rawget(self,"Data")
                        local picks=data and saved[baseOf(data.Name)]
                        local entry=picks and picks[key]
                        if entry~=nil then return entry end
                    end
                    return oldGet(self,key)
                end
                vmClass.Get=function(self,key)
                    if alive and key=="Name" then
                        local data=rawget(self,"Data")
                        if data then
                            local weapon=baseOf(data.Name)
                            if swapping and swapping.weapon==weapon then return swapping.skin end
                            local picks=saved[weapon]; local skin=picks and picks.Skin
                            if skin and not moduleOf(skin.Name) and hasModel(skin.Name)
                                and(data.Name==weapon or not moduleOf(data.Name)) then
                                return skin.Name
                            end
                        end
                    end
                    return(oldVmGet or replicated.Get)(self,key)
                end

                local function refreshHeld(weapon,slot)
                    if slot~="Wrap" and slot~="Charm" then return end
                    for _,obj in ipairs(getgc(true)) do
                        if type(obj)=="table" and type(rawget(obj,"Data"))=="table" and rawget(obj,"ClientItem") and rawget(obj,"Model") and baseOf(obj.Data.Name)==weapon then
                            local entry=saved[weapon] and saved[weapon][slot]
                            obj.Data[slot]=entry
                            local signal=obj._value_changed_events and obj._value_changed_events[slot]
                            if signal then pcall(signal.Fire, signal, entry) end
                            if slot=="Wrap" and obj._UpdateWrap then pcall(obj._UpdateWrap, obj) end
                        end
                    end
                end

                local function equip(weapon,slot,name2,extra)
                    local w=find2(weapon); if not w then return false end
                    local entry
                    if name2 then entry={Name=name2,Inverted=slot=="Wrap" and extra and extra.IsInverted or nil} end
                    w[slot]=entry; saved[weapon]=saved[weapon] or {}; saved[weapon][slot]=entry
                    if slot=="Skin" and entry then installSwap(weapon) end
                    flush(); refreshHeld(weapon,slot); return true
                end

                getgenv().RivalsEquipHandler=function(self,...)
                    if not alive or self~=equipRemote then return false end
                    local weapon,slot,name2,extra=...
                    return slots[slot] and(name2==nil or lib2.Cosmetics[name2]) and equip(weapon,slot,name2,extra) or false
                end

                if not getgenv().RivalsNamecallOriginal then
                    getgenv().RivalsNamecallOriginal=hookmetamethod(game,"__namecall",newcclosure(function(self,...)
                        local handler=getgenv().RivalsEquipHandler
                        if handler and not checkcaller() and getnamecallmethod()=="FireServer" and handler(self,...) then return end
                        return getgenv().RivalsNamecallOriginal(self,...)
                    end))
                end

                getgenv().RivalsCosmeticsCleanup=function()
                    alive=false; getgenv().RivalsEquipHandler=nil
                    replicated.Get=oldGet; vmClass.Get=oldVmGet
                    for _,swap in pairs(swaps) do swap.class.new=swap.origNew end
                    local cur=get("CosmeticInventory")
                    if cur then for name in pairs(added) do cur[name]=nil end end
                    getgenv().RivalsCosmeticsCleanup=nil
                end

                print("[SkinChanger] Loaded ✓")
            end)
        else
            if getgenv().RivalsCosmeticsCleanup then
                pcall(getgenv().RivalsCosmeticsCleanup)
                print("[SkinChanger] Unloaded")
            end
        end
    end,
})

SkinGrp:AddLabel("Equip via in-game UI while toggle is ON.")
SkinGrp:AddLabel("Skins persist across respawns.")
SkinGrp:AddButton({
    Text="Unload Skin Changer",
    Func=function()
        if getgenv().RivalsCosmeticsCleanup then
            pcall(getgenv().RivalsCosmeticsCleanup)
            if Library.Options.SkinEnabled then Library.Options.SkinEnabled:SetValue(false) end
            print("[SkinChanger] Force-unloaded")
        end
    end,
})

-- ═══════════════════════════════════════════════════════════════════════════════
--  UI  —  SETTINGS TAB
-- ═══════════════════════════════════════════════════════════════════════════════
local MenuGrp=SettingsTab:AddLeftGroupbox("Menu")
MenuGrp:AddLabel("Menu Keybind"):AddKeyPicker("MenuKey",{
    Default="RightShift", NoUI=true, Text="Toggle menu",
})
Library.ToggleKeybind=Library.Options.MenuKey
MenuGrp:AddButton({
    Text="Unload All",
    Func=function()
        RunService:UnbindFromRenderStep("RivalsCheat")
        pcall(function() FOVCircle:Remove() end)
        for _,p in ipairs(Players:GetPlayers()) do removeESPFor(p) end
        if _origStartShooting then
            pcall(function()
                local GM=require(LP.PlayerScripts.Modules.ItemTypes.Gun)
                if setreadonly then pcall(setreadonly,GM,false) end
                GM.StartShooting=_origStartShooting
            end)
        end
        if getgenv().RivalsCosmeticsCleanup then pcall(getgenv().RivalsCosmeticsCleanup) end
        Library:Unload()
        _G["RivalsCheat"]=nil
    end,
})

-- ═══════════════════════════════════════════════════════════════════════════════
--  _G API
-- ═══════════════════════════════════════════════════════════════════════════════
_G["RivalsCheat"]={
    Config    = CFG,
    ToggleAim = function()
        CFG.AimEnabled=not CFG.AimEnabled
        if Library.Options.AimEnabled then Library.Options.AimEnabled:SetValue(CFG.AimEnabled) end
    end,
    ToggleSA  = function()
        CFG.SAEnabled=not CFG.SAEnabled
        if Library.Options.SAEnabled then Library.Options.SAEnabled:SetValue(CFG.SAEnabled) end
    end,
    ToggleESP = function()
        CFG.ESPEnabled=not CFG.ESPEnabled
        if Library.Options.ESPEnabled then Library.Options.ESPEnabled:SetValue(CFG.ESPEnabled) end
    end,
    SetFOV    = function(v)
        CFG.FOVSize=v
        if Library.Options.SharedFOV  then Library.Options.SharedFOV:SetValue(v) end
        if Library.Options.SAFOVSync  then Library.Options.SAFOVSync:SetValue(v) end
    end,
}

print("[RivalsCheat] Loaded — RightShift → menu | _G.RivalsCheat.Config to tweak")
