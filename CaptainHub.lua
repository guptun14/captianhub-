--[[
    Captain Hub🧢 v5
    7 หมวด: Player / Attack / Movement / Visual / World / Outfit / Misc
    + อนิเมชั่นเปิด/ปิดเมนู | Outfit รองรับ R6 + R15
]]

local bootOK, bootErr = pcall(function()

-- ═════════════ CONFIG ═════════════
local CONFIG = {
    Title        = "Captain Hub🧢",
    ToggleKey    = Enum.KeyCode.RightShift,
    Speed        = 50,
    Jump         = 100,
    FlySpeed     = 60,
    FOV          = 90,
    Gravity      = 196,
    ClockTime    = 14,
    TeamCheck    = false,
    ESPInterval  = 0.2,

    -- Animation
    OpenTime     = 0.35,
    CloseTime    = 0.2,

    -- Attack
    TargetPlayers   = true,
    TargetBots      = true,
    AtkTeamCheck    = false,
    AimPart         = "Head",
    WallCheck       = true,
    ShowFOV         = true,
    AimFOV          = 150,
    AimSmooth       = 12,
    AuraRange       = 15,
    AuraDelayMs     = 100,
    AuraMaxTargets  = 3,
    AutoEquip       = true,
    HitboxSize      = 12,
    HitboxInterval  = 0.5,

    AccentColor  = Color3.fromRGB(255, 170, 0),
    BgColor      = Color3.fromRGB(24, 24, 30),
    PanelColor   = Color3.fromRGB(34, 34, 42),
}

-- ═════════════ SERVICES ═════════════
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")
local Workspace        = game:GetService("Workspace")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")
local StarterGui       = game:GetService("StarterGui")
local CoreGui          = game:GetService("CoreGui")
local VirtualUser      = game:GetService("VirtualUser")
local TweenService     = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait()
    LocalPlayer = Players.LocalPlayer
end

-- ═════════════ STATE ═════════════
local State = {
    Speed = false, Jump = false, InfJump = false, AntiAFK = false,
    Fly = false, Noclip = false,
    ESP = false, Fullbright = false, FOV = false,
    Gravity = false, Time = false, NoFog = false,
    Aimbot = false, KillAura = false, AutoClick = false, Hitbox = false,
}
local connections = {}
local flyBV, flyBG
local espFolder
local espObjects = {}
local origLighting = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
    GlobalShadows = Lighting.GlobalShadows,
    Ambient = Lighting.Ambient,
}
local origGravity = Workspace.Gravity
local origFOV = (Workspace.CurrentCamera and Workspace.CurrentCamera.FieldOfView) or 70
local gui, main, fovCircle
local unloaded = false
local layoutCounter = 0
local botSet = {}
local hitboxOrig = {}
local auraTimer = 0
local hitboxTimer = 0
local fti = firetouchinterest
local menuOpen = false
local setMenu

-- ═════════════ UTILITAIRES ═════════════
local function track(conn)
    connections[#connections + 1] = conn
    return conn
end

local function getChar() return LocalPlayer.Character end

local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function notify(text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = CONFIG.Title, Text = tostring(text), Duration = 4,
        })
    end)
end

local function make(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props) do
        pcall(function() inst[k] = v end)
    end
    if parent then inst.Parent = parent end
    return inst
end

local function nextOrder()
    layoutCounter = layoutCounter + 1
    return layoutCounter
end

local function isInputPointer(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local function isInputMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
end

local function tryParent(getter)
    local ok, container = pcall(getter)
    if not ok or not container then return nil end
    local ok2, test = pcall(function()
        local t = Instance.new("ScreenGui")
        t.Name = "__captain_test"
        t.Parent = container
        local good = (t.Parent == container)
        t:Destroy()
        return good
    end)
    if ok2 and test then return container end
    return nil
end

local function getGuiParent()
    return tryParent(function() return CoreGui end)
        or tryParent(function() return gethui and gethui() end)
        or LocalPlayer:WaitForChild("PlayerGui")
end

local function removeOld(container)
    pcall(function()
        for _, c in ipairs(container:GetChildren()) do
            if c.Name == "CaptainHub" then c:Destroy() end
        end
    end)
end

-- ═════════════ LOGIQUE ═════════════
local function resetSpeed()
    local hum = getHum()
    if hum then hum.WalkSpeed = 16 end
end

local function resetJump()
    local hum = getHum()
    if hum then
        hum.UseJumpPower = true
        hum.JumpPower = 50
    end
end

track(UserInputService.JumpRequest:Connect(function()
    if State.InfJump then
        local hum = getHum()
        if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end) end
    end
end))

track(LocalPlayer.Idled:Connect(function()
    if State.AntiAFK then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end))

-- Fly
local function cleanupFly()
    if flyBV then flyBV:Destroy() flyBV = nil end
    if flyBG then flyBG:Destroy() flyBG = nil end
    local hum = getHum()
    if hum then hum.PlatformStand = false end
end

local function flyStep(dt)
    local root, hum = getRoot(), getHum()
    local cam = Workspace.CurrentCamera
    if not (root and hum and cam) then return end

    if not flyBV or flyBV.Parent ~= root then
        if flyBV then flyBV:Destroy() end
        if flyBG then flyBG:Destroy() end
        flyBV = make("BodyVelocity", {
            MaxForce = Vector3.new(1e9, 1e9, 1e9),
            Velocity = Vector3.new(0, 0, 0),
        }, root)
        flyBG = make("BodyGyro", {
            MaxTorque = Vector3.new(1e9, 1e9, 1e9),
            P = 1e4,
        }, root)
    end

    hum.PlatformStand = true
    local look = cam.CFrame.LookVector
    local flatLook = Vector3.new(look.X, 0, look.Z)
    if flatLook.Magnitude < 0.001 then flatLook = Vector3.new(0, 0, -1) end
    flatLook = flatLook.Unit

    local move = hum.MoveDirection
    local vel = Vector3.new(0, 0, 0)
    if move.Magnitude > 0 then
        local fwd = move:Dot(flatLook)
        vel = move.Unit * CONFIG.FlySpeed + Vector3.new(0, look.Y * fwd * CONFIG.FlySpeed, 0)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        vel = vel + Vector3.new(0, CONFIG.FlySpeed, 0)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
        vel = vel - Vector3.new(0, CONFIG.FlySpeed, 0)
    end

    local alpha = 1 - math.exp(-12 * dt)
    flyBV.Velocity = flyBV.Velocity:Lerp(vel, alpha)
    flyBG.CFrame = CFrame.lookAt(root.Position, root.Position + flatLook)
end

local function setFly(on)
    State.Fly = on
    if not on then cleanupFly() end
end

-- Noclip
track(RunService.Stepped:Connect(function()
    if not State.Noclip then return end
    local char = getChar()
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            part.CanCollide = false
        end
    end
end))

-- TP
local function tpNearest()
    local root = getRoot()
    if not root then return notify("ไม่พบตัวละคร") end
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local r = plr.Character:FindFirstChild("HumanoidRootPart")
            if r then
                list[#list + 1] = { root = r, mag = (r.Position - root.Position).Magnitude }
            end
        end
    end
    table.sort(list, function(a, b) return a.mag < b.mag end)
    if list[1] then
        root.CFrame = list[1].root.CFrame * CFrame.new(0, 0, 3)
    else
        notify("ไม่มีผู้เล่นอื่น")
    end
end

-- ESP
local function clearESP(plr)
    local obj = espObjects[plr]
    if obj then
        if obj.hl then obj.hl:Destroy() end
        if obj.bb then obj.bb:Destroy() end
        espObjects[plr] = nil
    end
end

local function buildESP(plr)
    clearESP(plr)
    if plr == LocalPlayer or not State.ESP then return end
    if CONFIG.TeamCheck and LocalPlayer.Team ~= nil and LocalPlayer.Team == plr.Team then return end
    local char = plr.Character
    if not char then return end

    local color = (plr.Team and plr.TeamColor.Color) or Color3.fromRGB(255, 70, 70)
    local hl = make("Highlight", {
        Adornee = char,
        FillColor = color,
        FillTransparency = 0.6,
        OutlineColor = Color3.new(1, 1, 1),
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
    }, espFolder)

    local bb, label
    local head = char:FindFirstChild("Head")
    if head then
        bb = make("BillboardGui", {
            Adornee = head,
            Size = UDim2.fromOffset(180, 30),
            StudsOffset = Vector3.new(0, 2.5, 0),
            AlwaysOnTop = true,
        }, espFolder)
        label = make("TextLabel", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = plr.DisplayName,
            TextColor3 = color,
            TextStrokeTransparency = 0,
            TextScaled = true,
            Font = Enum.Font.GothamBold,
        }, bb)
    end
    espObjects[plr] = { hl = hl, bb = bb, label = label }
end

local function refreshESP()
    for _, plr in ipairs(Players:GetPlayers()) do
        if State.ESP then buildESP(plr) else clearESP(plr) end
    end
end

local function hookPlayerESP(plr)
    track(plr.CharacterAdded:Connect(function()
        task.wait(0.5)
        if State.ESP then buildESP(plr) end
    end))
end

for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer then hookPlayerESP(plr) end
end
track(Players.PlayerAdded:Connect(hookPlayerESP))
track(Players.PlayerRemoving:Connect(clearESP))

-- Fullbright / World
local function applyFullbright(on)
    State.Fullbright = on
    if on then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(200, 200, 200)
    else
        Lighting.Brightness = origLighting.Brightness
        Lighting.ClockTime = origLighting.ClockTime
        Lighting.GlobalShadows = origLighting.GlobalShadows
        Lighting.Ambient = origLighting.Ambient
    end
end

local function applyNoFog(on)
    State.NoFog = on
    if on then
        Lighting.FogEnd = 1e6
        Lighting.FogStart = 1e6
    else
        Lighting.FogEnd = origLighting.FogEnd
        Lighting.FogStart = origLighting.FogStart
    end
end

local function fpsBoost()
    pcall(function()
        for _, v in ipairs(Workspace:GetDescendants()) do
            if v:IsA("BasePart") then
                v.Material = Enum.Material.SmoothPlastic
                v.CastShadow = false
            elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke")
                or v:IsA("Fire") or v:IsA("Sparkles") then
                v.Enabled = false
            end
        end
        for _, v in ipairs(Lighting:GetChildren()) do
            if v:IsA("PostEffect") or v:IsA("BlurEffect") or v:IsA("SunRaysEffect") then
                v.Enabled = false
            end
        end
        Lighting.GlobalShadows = false
    end)
    notify("FPS Boost เปิดแล้ว")
end

-- Misc
local function rejoin()
    pcall(function()
        if #Players:GetPlayers() <= 1 then
            LocalPlayer:Kick("\nกำลัง Rejoin...")
            task.wait()
        end
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)
end

local function serverHop()
    local ok, res = pcall(function()
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId
            .. "/servers/Public?sortOrder=Asc&limit=100"
        return HttpService:JSONDecode(game:HttpGet(url))
    end)
    if not ok or not res or not res.data then
        return notify("Server Hop ล้มเหลว")
    end
    for _, s in ipairs(res.data) do
        if s.id ~= game.JobId and s.playing < s.maxPlayers then
            pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer)
            end)
            return
        end
    end
    notify("ไม่พบเซิร์ฟเวอร์ที่ว่าง")
end

local function resetChar()
    local hum = getHum()
    if hum then hum.Health = 0 end
end

local function copyPlaceId()
    local ok = pcall(function() setclipboard(tostring(game.PlaceId)) end)
    notify(ok and ("คัดลอก PlaceId: " .. game.PlaceId) or "executor ไม่รองรับ setclipboard")
end

-- ───────── Attack : ระบบหาเป้าหมาย (ผู้เล่น + บอท) ─────────
pcall(function()
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("Humanoid") then botSet[d] = true end
    end
end)
track(Workspace.DescendantAdded:Connect(function(d)
    if d:IsA("Humanoid") then botSet[d] = true end
end))
track(Workspace.DescendantRemoving:Connect(function(d)
    botSet[d] = nil
end))

local function findRoot(char, hum)
    return char:FindFirstChild("HumanoidRootPart")
        or hum.RootPart
        or char.PrimaryPart
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
end

local function getTargets(origin)
    local list = {}
    local myChar = getChar()

    if CONFIG.TargetPlayers then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local teamOK = true
                if CONFIG.AtkTeamCheck and LocalPlayer.Team ~= nil and LocalPlayer.Team == plr.Team then
                    teamOK = false
                end
                if teamOK then
                    local char = plr.Character
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    local root = hum and findRoot(char, hum)
                    if hum and root and hum.Health > 0 then
                        list[#list + 1] = {
                            char = char, hum = hum, root = root,
                            isPlayer = true,
                            mag = (root.Position - origin).Magnitude,
                        }
                    end
                end
            end
        end
    end

    if CONFIG.TargetBots then
        for hum in pairs(botSet) do
            local char = hum.Parent
            if char and char:IsA("Model") and char ~= myChar
                and not (myChar and char:IsDescendantOf(myChar))
                and not Players:GetPlayerFromCharacter(char)
                and hum.Health > 0 then
                local root = findRoot(char, hum)
                if root then
                    list[#list + 1] = {
                        char = char, hum = hum, root = root,
                        isPlayer = false,
                        mag = (root.Position - origin).Magnitude,
                    }
                end
            end
        end
    end

    return list
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function isVisible(cam, part, char)
    local myChar = getChar()
    rayParams.FilterDescendantsInstances = { myChar or Workspace }
    local origin = cam.CFrame.Position
    local result = Workspace:Raycast(origin, part.Position - origin, rayParams)
    return result == nil or result.Instance:IsDescendantOf(char)
end

-- Aimbot
local function getAimTarget()
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    local vpSize = cam.ViewportSize
    local center = Vector2.new(vpSize.X / 2, vpSize.Y / 2)
    local candidates = {}

    for _, t in ipairs(getTargets(cam.CFrame.Position)) do
        local part = t.char:FindFirstChild(CONFIG.AimPart) or t.root
        local pos, onScreen = cam:WorldToViewportPoint(part.Position)
        if onScreen and pos.Z > 0 then
            local screenMag = (Vector2.new(pos.X, pos.Y) - center).Magnitude
            if screenMag <= CONFIG.AimFOV then
                t.part = part
                t.mag = screenMag
                candidates[#candidates + 1] = t
            end
        end
    end

    table.sort(candidates, function(a, b) return a.mag < b.mag end)

    for _, t in ipairs(candidates) do
        if not CONFIG.WallCheck or isVisible(cam, t.part, t.char) then
            return t
        end
    end
    return nil
end

local function aimStep(dt)
    if not State.Aimbot then return end
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local t = getAimTarget()
    if not t then return end

    local camPos = cam.CFrame.Position
    local direction = t.part.Position - camPos
    if direction.Magnitude <= 0.015 then return end
    local diff = (direction.Unit - cam.CFrame.LookVector).Magnitude
    if diff <= 0.015 then return end

    local alpha = 1 - math.exp(-CONFIG.AimSmooth * dt)
    cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(camPos, t.part.Position), alpha)
end

local function updateFOVCircle()
    if not fovCircle then return end
    fovCircle.Visible = State.Aimbot and CONFIG.ShowFOV
    fovCircle.Size = UDim2.fromOffset(CONFIG.AimFOV * 2, CONFIG.AimFOV * 2)
end

-- Kill Aura / Auto Click
local function auraStep(dt)
    auraTimer = auraTimer + dt
    if auraTimer < CONFIG.AuraDelayMs / 1000 then return end
    auraTimer = 0

    local char, hum, root = getChar(), getHum(), getRoot()
    if not (char and hum and root) or hum.Health <= 0 then return end

    local tool = char:FindFirstChildOfClass("Tool")
    if not tool and CONFIG.AutoEquip then
        local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
        local bt = bp and bp:FindFirstChildOfClass("Tool")
        if bt then
            pcall(function() hum:EquipTool(bt) end)
        end
        return
    end
    if not tool then return end

    if State.AutoClick and not State.KillAura then
        pcall(function() tool:Activate() end)
        return
    end

    local inRange = {}
    for _, t in ipairs(getTargets(root.Position)) do
        if t.mag <= CONFIG.AuraRange then inRange[#inRange + 1] = t end
    end
    if #inRange == 0 then return end
    table.sort(inRange, function(a, b) return a.mag < b.mag end)

    pcall(function() tool:Activate() end)

    local handle = tool:FindFirstChild("Handle")
    if handle and fti then
        for i = 1, math.min(#inRange, CONFIG.AuraMaxTargets) do
            local target = inRange[i]
            pcall(fti, handle, target.root, 0)
            pcall(fti, handle, target.root, 1)
        end
    end
end

-- Hitbox Expander
local function restoreHitboxes()
    for part, o in pairs(hitboxOrig) do
        if part and part.Parent then
            pcall(function()
                part.Size = o.Size
                part.Transparency = o.Transparency
                part.CanCollide = o.CanCollide
            end)
        end
    end
    hitboxOrig = {}
end

local function hitboxStep()
    local s = CONFIG.HitboxSize
    for _, t in ipairs(getTargets(Vector3.new(0, 0, 0))) do
        local part = t.root
        if not hitboxOrig[part] then
            hitboxOrig[part] = {
                Size = part.Size,
                Transparency = part.Transparency,
                CanCollide = part.CanCollide,
            }
        end
        pcall(function()
            part.Size = Vector3.new(s, s, s)
            part.Transparency = 0.7
            part.CanCollide = false
        end)
    end
end

-- TP หลังเป้าหมายที่ใกล้ที่สุด
local function tpBehindNearest()
    local root = getRoot()
    if not root then return notify("ไม่พบตัวละคร") end
    local list = getTargets(root.Position)
    table.sort(list, function(a, b) return a.mag < b.mag end)
    local t = list[1]
    if not t then return notify("ไม่พบเป้าหมาย") end
    local behind = (t.root.CFrame * CFrame.new(0, 0, 3)).Position
    root.CFrame = CFrame.lookAt(behind, t.root.Position)
end

-- ───────── Outfit (R6 + R15) ─────────
local origDesc, outfitDesc
local keepOutfit = false
local wornIds = {}

local function saveOriginal()
    if origDesc then return end
    local hum = getHum()
    if not hum then return end
    local ok, d = pcall(function() return hum:GetAppliedDescription() end)
    if ok then origDesc = d end
end

local function applyDescription(hum, desc)
    local ok = pcall(function() hum:ApplyDescriptionReset(desc) end)
    if not ok then
        ok = pcall(function() hum:ApplyDescription(desc) end)
    end
    return ok
end

local function wearAsset(id)
    local char, hum = getChar(), getHum()
    if not (char and hum) then return false end
    local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. id) end)
    if not ok or type(objs) ~= "table" or #objs == 0 then return false end

    local worn = false
    local function handle(inst)
        if inst:IsA("Accessory") then
            hum:AddAccessory(inst)
            worn = true
        elseif inst:IsA("Shirt") or inst:IsA("Pants") or inst:IsA("ShirtGraphic") then
            local old = char:FindFirstChildOfClass(inst.ClassName)
            if old then old:Destroy() end
            inst.Parent = char
            worn = true
        elseif inst:IsA("Decal") then
            local head = char:FindFirstChild("Head")
            if head then
                local old = head:FindFirstChildOfClass("Decal")
                if old then old:Destroy() end
                inst.Name = "face"
                inst.Parent = head
                worn = true
            end
        end
    end

    for _, obj in ipairs(objs) do
        handle(obj)
        if not worn then
            for _, child in ipairs(obj:GetChildren()) do handle(child) end
        end
    end
    return worn
end

local function wearIds(text)
    saveOriginal()
    local okN, failN = 0, 0
    for idStr in text:gmatch("%d+") do
        if wearAsset(idStr) then
            okN = okN + 1
            wornIds[#wornIds + 1] = idStr
        else
            failN = failN + 1
        end
    end
    notify(("ใส่สำเร็จ %d | ล้มเหลว %d"):format(okN, failN))
end

local function copyOutfit(input)
    local hum = getHum()
    if not hum then return notify("ไม่พบตัวละคร") end
    saveOriginal()

    local q = input:match("^%s*(.-)%s*$")
    local lq = q:lower()
    local uid

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Name:lower() == lq or plr.DisplayName:lower() == lq
            or plr.Name:lower():sub(1, #lq) == lq then
            uid = plr.UserId
            break
        end
    end
    if not uid then uid = tonumber(q) end
    if not uid then
        local ok, res = pcall(function() return Players:GetUserIdFromNameAsync(q) end)
        if ok then uid = res end
    end
    if not uid then return notify("ไม่พบผู้เล่นชื่อนี้") end

    local ok, desc = pcall(function() return Players:GetHumanoidDescriptionFromUserId(uid) end)
    if not ok or not desc then return notify("ดึงชุดไม่สำเร็จ") end

    if applyDescription(hum, desc) then
        outfitDesc = desc
        wornIds = {}
        notify("ก๊อปชุดสำเร็จ")
    else
        notify("ใส่ชุดไม่สำเร็จ")
    end
end

local function resetOutfit()
    local hum = getHum()
    if not (hum and origDesc) then return notify("ยังไม่มีชุดเดิมให้คืน") end
    if applyDescription(hum, origDesc) then
        outfitDesc = nil
        wornIds = {}
        notify("คืนชุดเดิมแล้ว")
    end
end

local function removeAccessories()
    local char = getChar()
    if not char then return end
    saveOriginal()
    for _, v in ipairs(char:GetChildren()) do
        if v:IsA("Accessory") then v:Destroy() end
    end
end

local function removeClothes()
    local char = getChar()
    if not char then return end
    saveOriginal()
    for _, v in ipairs(char:GetChildren()) do
        if v:IsA("Shirt") or v:IsA("Pants") or v:IsA("ShirtGraphic") then v:Destroy() end
    end
end

local function removeFace()
    local char = getChar()
    local head = char and char:FindFirstChild("Head")
    if not head then return end
    saveOriginal()
    for _, v in ipairs(head:GetChildren()) do
        if v:IsA("Decal") then v:Destroy() end
    end
end

local skinColors = {
    { "เลือกสี", nil },
    { "แดง",    Color3.fromRGB(255, 60, 60) },
    { "น้ำเงิน", Color3.fromRGB(60, 120, 255) },
    { "เขียว",   Color3.fromRGB(60, 200, 90) },
    { "ดำ",     Color3.fromRGB(25, 25, 25) },
    { "ขาว",    Color3.fromRGB(245, 245, 245) },
    { "ทอง",    Color3.fromRGB(255, 200, 40) },
    { "ชมพู",   Color3.fromRGB(255, 130, 190) },
    { "เทา",    Color3.fromRGB(130, 130, 140) },
}
local skinNames = {}
for i, v in ipairs(skinColors) do skinNames[i] = v[1] end

local function setSkin(name)
    local idx = table.find(skinNames, name)
    local color = idx and skinColors[idx][2]
    local char = getChar()
    if not (color and char) then return end
    saveOriginal()
    local bc = char:FindFirstChildOfClass("BodyColors") or make("BodyColors", {}, char)
    bc.HeadColor3 = color
    bc.TorsoColor3 = color
    bc.LeftArmColor3 = color
    bc.RightArmColor3 = color
    bc.LeftLegColor3 = color
    bc.RightLegColor3 = color
end

local scaleNames = {
    Height = "BodyHeightScale", Width = "BodyWidthScale",
    Depth = "BodyDepthScale", Head = "HeadScale",
}
local function setScale(kind, percent)
    local hum = getHum()
    if not hum or hum.RigType ~= Enum.HumanoidRigType.R15 then return end
    local val = hum:FindFirstChild(scaleNames[kind])
    if val then val.Value = percent / 100 end
end

track(LocalPlayer.CharacterAdded:Connect(function(char)
    if not keepOutfit then return end
    local hum = char:WaitForChild("Humanoid", 10)
    if not hum then return end
    task.wait(1)
    if outfitDesc then applyDescription(hum, outfitDesc) end
    for _, id in ipairs(wornIds) do pcall(wearAsset, id) end
end))

-- ═════════════ GUI ═════════════
local function makeDraggable(handle, target)
    local dragging, dragStart, startPos, moved = false, nil, nil, false
    track(handle.InputBegan:Connect(function(input)
        if isInputPointer(input) then
            dragging = true
            moved = false
            dragStart = input.Position
            startPos = target.Position
            local c
            c = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if c then c:Disconnect() end
                end
            end)
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and isInputMove(input) then
            local d = input.Position - dragStart
            if d.Magnitude > 6 then moved = true end
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end))
    return function() return moved end
end

local guiParent = getGuiParent()
removeOld(guiParent)
removeOld(LocalPlayer:FindFirstChildOfClass("PlayerGui") or guiParent)

gui = make("ScreenGui", {
    Name = "CaptainHub",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 999,
}, guiParent)
pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)

espFolder = make("Folder", { Name = "ESP" }, gui)

fovCircle = make("Frame", {
    Name = "AimFOV",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(CONFIG.AimFOV * 2, CONFIG.AimFOV * 2),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, fovCircle)
make("UIStroke", { Color = CONFIG.AccentColor, Thickness = 1.5, Transparency = 0.2 }, fovCircle)

local cam = Workspace.CurrentCamera
local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
local W = math.clamp(vp.X - 24, 300, 460)
local H = math.clamp(vp.Y - 70, 230, 320)

main = make("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(W, H),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    BackgroundColor3 = CONFIG.BgColor,
    BorderSizePixel = 0,
    Active = true,
    Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, main)
make("UIStroke", { Color = CONFIG.AccentColor, Thickness = 1.5 }, main)

local mainScale = make("UIScale", { Scale = 0 }, main)

setMenu = function(open)
    menuOpen = open
    if open then
        main.Visible = true
        TweenService:Create(mainScale,
            TweenInfo.new(CONFIG.OpenTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = 1 }):Play()
    else
        local tw = TweenService:Create(mainScale,
            TweenInfo.new(CONFIG.CloseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Scale = 0 })
        tw:Play()
        tw.Completed:Connect(function()
            if not menuOpen then main.Visible = false end
        end)
    end
end

local topBar = make("Frame", {
    Size = UDim2.new(1, 0, 0, 36),
    BackgroundColor3 = CONFIG.PanelColor,
    BorderSizePixel = 0,
}, main)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, topBar)
make("TextLabel", {
    Size = UDim2.new(1, -80, 1, 0),
    Position = UDim2.fromOffset(12, 0),
    BackgroundTransparency = 1,
    Text = CONFIG.Title,
    TextColor3 = CONFIG.AccentColor,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Enum.Font.GothamBold,
    TextSize = 16,
}, topBar)

local closeBtn = make("TextButton", {
    Size = UDim2.fromOffset(28, 24),
    Position = UDim2.new(1, -34, 0, 6),
    BackgroundColor3 = Color3.fromRGB(200, 60, 60),
    Text = "X",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 14,
}, topBar)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, closeBtn)
track(closeBtn.MouseButton1Click:Connect(function() setMenu(false) end))

makeDraggable(topBar, main)

local tabBar = make("ScrollingFrame", {
    Size = UDim2.new(0, 100, 1, -44),
    Position = UDim2.fromOffset(6, 40),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 0,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y,
}, main)
make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, tabBar)

local pageHolder = make("Frame", {
    Size = UDim2.new(1, -116, 1, -44),
    Position = UDim2.fromOffset(110, 40),
    BackgroundTransparency = 1,
}, main)

local pages, tabButtons = {}, {}

local function selectTab(name)
    for n, page in pairs(pages) do
        page.Visible = (n == name)
        tabButtons[n].BackgroundColor3 = (n == name) and CONFIG.AccentColor or CONFIG.PanelColor
        tabButtons[n].TextColor3 = (n == name) and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
    end
end

local function createTab(name, title)
    local btn = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = CONFIG.PanelColor,
        Text = title,
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        LayoutOrder = nextOrder(),
    }, tabBar)
    make("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)

    local page = make("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Visible = false,
    }, pageHolder)
    make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, page)
    make("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, page)

    pages[name], tabButtons[name] = page, btn
    track(btn.MouseButton1Click:Connect(function() selectTab(name) end))
    return page
end

local function addLabel(page, text)
    make("TextLabel", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Text = "— " .. text .. " —",
        TextColor3 = CONFIG.AccentColor,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        LayoutOrder = nextOrder(),
    }, page)
end

local function addToggle(page, text, default, callback)
    local on = default
    local btn = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = CONFIG.PanelColor,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = nextOrder(),
    }, page)
    make("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)
    make("TextLabel", {
        Size = UDim2.new(1, -70, 1, 0),
        Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = Color3.new(1, 1, 1),
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, btn)
    local pill = make("TextLabel", {
        Size = UDim2.fromOffset(46, 22),
        Position = UDim2.new(1, -54, 0.5, -11),
        Text = "",
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = Color3.new(1, 1, 1),
    }, btn)
    make("UICorner", { CornerRadius = UDim.new(0, 11) }, pill)

    local function refresh()
        pill.Text = on and "ON" or "OFF"
        TweenService:Create(pill, TweenInfo.new(0.15), {
            BackgroundColor3 = on and Color3.fromRGB(50, 180, 90) or Color3.fromRGB(110, 110, 120),
        }):Play()
    end
    pill.BackgroundColor3 = on and Color3.fromRGB(50, 180, 90) or Color3.fromRGB(110, 110, 120)
    pill.Text = on and "ON" or "OFF"
    track(btn.MouseButton1Click:Connect(function()
        on = not on
        refresh()
        local ok, err = pcall(callback, on)
        if not ok then notify("Error: " .. tostring(err)) end
    end))
end

local function addButton(page, text, callback)
    local btn = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = CONFIG.PanelColor,
        Text = text,
        TextColor3 = CONFIG.AccentColor,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        LayoutOrder = nextOrder(),
    }, page)
    make("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)
    track(btn.MouseButton1Click:Connect(function()
        local ok, err = pcall(callback)
        if not ok then notify("Error: " .. tostring(err)) end
    end))
end

local function addCycle(page, text, options, default, callback)
    local idx = table.find(options, default) or 1
    local btn = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = CONFIG.PanelColor,
        Text = text .. ": " .. options[idx],
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.Gotham,
        TextSize = 12,
        LayoutOrder = nextOrder(),
    }, page)
    make("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)
    track(btn.MouseButton1Click:Connect(function()
        idx = idx % #options + 1
        btn.Text = text .. ": " .. options[idx]
        pcall(callback, options[idx])
    end))
end

local function addSlider(page, text, min, max, default, step, callback)
    local frame = make("Frame", {
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundColor3 = CONFIG.PanelColor,
        LayoutOrder = nextOrder(),
    }, page)
    make("UICorner", { CornerRadius = UDim.new(0, 6) }, frame)
    local label = make("TextLabel", {
        Size = UDim2.new(1, -20, 0, 22),
        Position = UDim2.fromOffset(10, 3),
        BackgroundTransparency = 1,
        Text = text .. ": " .. tostring(default),
        TextColor3 = Color3.new(1, 1, 1),
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.Gotham,
        TextSize = 12,
    }, frame)
    local hit = make("TextButton", {
        Size = UDim2.new(1, -20, 0, 24),
        Position = UDim2.fromOffset(10, 24),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    }, frame)
    local bar = make("Frame", {
        Size = UDim2.new(1, 0, 0, 6),
        Position = UDim2.new(0, 0, 0.5, -3),
        BackgroundColor3 = Color3.fromRGB(60, 60, 70),
        BorderSizePixel = 0,
    }, hit)
    make("UICorner", { CornerRadius = UDim.new(1, 0) }, bar)
    local fill = make("Frame", {
        Size = UDim2.fromScale((default - min) / (max - min), 1),
        BackgroundColor3 = CONFIG.AccentColor,
        BorderSizePixel = 0,
    }, bar)
    make("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)

    local dragging = false
    local function setFromX(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        local val = min + (max - min) * rel
        val = math.clamp(math.floor(val / step + 0.5) * step, min, max)
        fill.Size = UDim2.fromScale((val - min) / (max - min), 1)
        label.Text = text .. ": " .. tostring(val)
        pcall(callback, val)
    end
    track(hit.InputBegan:Connect(function(input)
        if isInputPointer(input) then
            dragging = true
            page.ScrollingEnabled = false
            setFromX(input.Position.X)
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and isInputMove(input) then setFromX(input.Position.X) end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if isInputPointer(input) and dragging then
            dragging = false
            page.ScrollingEnabled = true
        end
    end))
end

local function addInput(page, placeholder, buttonText, callback)
    local frame = make("Frame", {
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = CONFIG.PanelColor,
        LayoutOrder = nextOrder(),
    }, page)
    make("UICorner", { CornerRadius = UDim.new(0, 6) }, frame)
    local box = make("TextBox", {
        Size = UDim2.new(1, -80, 1, -10),
        Position = UDim2.fromOffset(8, 5),
        BackgroundColor3 = CONFIG.BgColor,
        Text = "",
        PlaceholderText = placeholder,
        PlaceholderColor3 = Color3.fromRGB(140, 140, 150),
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.Gotham,
        TextSize = 11,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)
    make("UICorner", { CornerRadius = UDim.new(0, 5) }, box)
    make("UIPadding", { PaddingLeft = UDim.new(0, 6) }, box)
    local btn = make("TextButton", {
        Size = UDim2.fromOffset(58, 26),
        Position = UDim2.new(1, -66, 0.5, -13),
        BackgroundColor3 = CONFIG.AccentColor,
        Text = buttonText,
        TextColor3 = Color3.new(0, 0, 0),
        Font = Enum.Font.GothamBold,
        TextSize = 12,
    }, frame)
    make("UICorner", { CornerRadius = UDim.new(0, 5) }, btn)
    track(btn.MouseButton1Click:Connect(function()
        if box.Text == "" then return notify("ยังไม่ได้กรอก") end
        local ok, err = pcall(callback, box.Text)
        if not ok then notify("Error: " .. tostring(err)) end
    end))
end

-- Tab 1 : Player
local pPlayer = createTab("Player", "Player")
addToggle(pPlayer, "Speed Hack", false, function(v)
    State.Speed = v
    if not v then resetSpeed() end
end)
addSlider(pPlayer, "Speed", 16, 200, CONFIG.Speed, 1, function(v) CONFIG.Speed = v end)
addToggle(pPlayer, "High Jump", false, function(v)
    State.Jump = v
    if not v then resetJump() end
end)
addSlider(pPlayer, "Jump Power", 50, 300, CONFIG.Jump, 5, function(v) CONFIG.Jump = v end)
addToggle(pPlayer, "Infinite Jump", false, function(v) State.InfJump = v end)

-- Tab 2 : Attack
local pAttack = createTab("Attack", "Attack")
addLabel(pAttack, "เป้าหมาย")
addToggle(pAttack, "โจมตีผู้เล่น", CONFIG.TargetPlayers, function(v)
    CONFIG.TargetPlayers = v
end)
addToggle(pAttack, "โจมตีบอท / NPC", CONFIG.TargetBots, function(v)
    CONFIG.TargetBots = v
end)
addToggle(pAttack, "Team Check (ข้ามทีมเดียวกัน)", CONFIG.AtkTeamCheck, function(v)
    CONFIG.AtkTeamCheck = v
end)

addLabel(pAttack, "Aimbot")
addToggle(pAttack, "Aimbot (ล็อกกล้อง)", false, function(v)
    State.Aimbot = v
    updateFOVCircle()
end)
addCycle(pAttack, "จุดเล็ง", { "Head", "HumanoidRootPart" }, CONFIG.AimPart, function(v)
    CONFIG.AimPart = v
end)
addToggle(pAttack, "Wall Check (ไม่ล็อกทะลุกำแพง)", CONFIG.WallCheck, function(v)
    CONFIG.WallCheck = v
end)
addToggle(pAttack, "แสดงวง FOV", CONFIG.ShowFOV, function(v)
    CONFIG.ShowFOV = v
    updateFOVCircle()
end)
addSlider(pAttack, "Aim FOV", 30, 500, CONFIG.AimFOV, 5, function(v)
    CONFIG.AimFOV = v
    updateFOVCircle()
end)
addSlider(pAttack, "Aim Speed", 1, 40, CONFIG.AimSmooth, 1, function(v)
    CONFIG.AimSmooth = v
end)

addLabel(pAttack, "Kill Aura")
addToggle(pAttack, "Kill Aura", false, function(v)
    State.KillAura = v
    auraTimer = 0
end)
addToggle(pAttack, "Auto Click (ตีรัว)", false, function(v)
    State.AutoClick = v
    auraTimer = 0
end)
addToggle(pAttack, "Auto Equip อาวุธ", CONFIG.AutoEquip, function(v)
    CONFIG.AutoEquip = v
end)
addSlider(pAttack, "Aura Range", 5, 60, CONFIG.AuraRange, 1, function(v)
    CONFIG.AuraRange = v
end)
addSlider(pAttack, "Aura Delay (ms)", 50, 1000, CONFIG.AuraDelayMs, 50, function(v)
    CONFIG.AuraDelayMs = v
end)

addLabel(pAttack, "Hitbox")
addToggle(pAttack, "Hitbox Expander", false, function(v)
    State.Hitbox = v
    hitboxTimer = CONFIG.HitboxInterval
    if not v then restoreHitboxes() end
end)
addSlider(pAttack, "Hitbox Size", 2, 40, CONFIG.HitboxSize, 1, function(v)
    CONFIG.HitboxSize = v
end)
addButton(pAttack, "TP หลังเป้าหมายที่ใกล้ที่สุด", tpBehindNearest)

-- Tab 3 : Movement
local pMove = createTab("Movement", "Movement")
addToggle(pMove, "Fly (Space/Ctrl)", false, setFly)
addSlider(pMove, "Fly Speed", 10, 200, CONFIG.FlySpeed, 5, function(v) CONFIG.FlySpeed = v end)
addToggle(pMove, "Noclip", false, function(v) State.Noclip = v end)
addButton(pMove, "TP ไปผู้เล่นที่ใกล้ที่สุด", tpNearest)

-- Tab 4 : Visual
local pVisual = createTab("Visual", "Visual")
addToggle(pVisual, "ESP ผู้เล่น", false, function(v)
    State.ESP = v
    refreshESP()
end)
addToggle(pVisual, "Team Check", CONFIG.TeamCheck, function(v)
    CONFIG.TeamCheck = v
    refreshESP()
end)
addToggle(pVisual, "Fullbright", false, applyFullbright)
addToggle(pVisual, "Custom FOV", false, function(v)
    State.FOV = v
    if not v and Workspace.CurrentCamera then
        Workspace.CurrentCamera.FieldOfView = origFOV
    end
end)
addSlider(pVisual, "FOV", 40, 120, CONFIG.FOV, 1, function(v) CONFIG.FOV = v end)

-- Tab 5 : World
local pWorld = createTab("World", "World")
addToggle(pWorld, "Custom Gravity", false, function(v)
    State.Gravity = v
    if not v then Workspace.Gravity = origGravity end
end)
addSlider(pWorld, "Gravity", 0, 400, CONFIG.Gravity, 5, function(v) CONFIG.Gravity = v end)
addToggle(pWorld, "Custom Time", false, function(v)
    State.Time = v
    if not v then Lighting.ClockTime = origLighting.ClockTime end
end)
addSlider(pWorld, "Clock Time", 0, 24, CONFIG.ClockTime, 1, function(v) CONFIG.ClockTime = v end)
addToggle(pWorld, "No Fog", false, applyNoFog)
addButton(pWorld, "FPS Boost", fpsBoost)

-- Tab 6 : Outfit
local pOutfit = createTab("Outfit", "Outfit")
addLabel(pOutfit, "ก๊อปชุดผู้เล่น")
addInput(pOutfit, "ชื่อ / UserId", "ก๊อป", copyOutfit)
addLabel(pOutfit, "ใส่ไอเทมด้วย ID")
addInput(pOutfit, "ID เสื้อ/กางเกง/หมวก/หน้า (คั่นด้วย ,)", "ใส่", wearIds)
addLabel(pOutfit, "สีตัวละคร")
addCycle(pOutfit, "สีผิว", skinNames, "เลือกสี", setSkin)
addLabel(pOutfit, "สเกล % (เฉพาะ R15)")
addSlider(pOutfit, "ความสูง", 50, 200, 100, 5, function(v) setScale("Height", v) end)
addSlider(pOutfit, "ความกว้าง", 50, 200, 100, 5, function(v) setScale("Width", v) end)
addSlider(pOutfit, "ความหนา", 50, 200, 100, 5, function(v) setScale("Depth", v) end)
addSlider(pOutfit, "ขนาดหัว", 50, 250, 100, 5, function(v) setScale("Head", v) end)
addLabel(pOutfit, "ถอด / คืนค่า")
addButton(pOutfit, "ถอดอุปกรณ์ทั้งหมด (หมวก/ผม)", removeAccessories)
addButton(pOutfit, "ถอดเสื้อผ้า", removeClothes)
addButton(pOutfit, "ถอดหน้า", removeFace)
addButton(pOutfit, "คืนชุดเดิม", resetOutfit)
addToggle(pOutfit, "คงชุดไว้ตอนเกิดใหม่", false, function(v) keepOutfit = v end)

-- Tab 7 : Misc
local pMisc = createTab("Misc", "Misc")
addToggle(pMisc, "Anti-AFK", false, function(v) State.AntiAFK = v end)
addButton(pMisc, "Rejoin", rejoin)
addButton(pMisc, "Server Hop", serverHop)
addButton(pMisc, "Reset Character", resetChar)
addButton(pMisc, "Copy PlaceId", copyPlaceId)

local function unload()
    if unloaded then return end
    unloaded = true
    keepOutfit = false
    State.Aimbot, State.KillAura, State.AutoClick, State.Hitbox = false, false, false, false
    pcall(function() RunService:UnbindFromRenderStep("CaptainAim") end)
    restoreHitboxes()
    cleanupFly()
    resetSpeed()
    resetJump()
    applyFullbright(false)
    applyNoFog(false)
    Workspace.Gravity = origGravity
    if Workspace.CurrentCamera then Workspace.CurrentCamera.FieldOfView = origFOV end
    for plr in pairs(espObjects) do clearESP(plr) end
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    if gui then gui:Destroy() end
    notify("ปิด Captain Hub แล้ว")
end
addButton(pMisc, "Unload Hub", unload)

-- ปุ่มลอย
local floatBtn = make("TextButton", {
    Name = "Float",
    Size = UDim2.fromOffset(46, 46),
    Position = UDim2.new(0, 12, 0.5, -23),
    BackgroundColor3 = CONFIG.BgColor,
    Text = "🧢",
    TextSize = 22,
    ZIndex = 10,
}, gui)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, floatBtn)
make("UIStroke", { Color = CONFIG.AccentColor, Thickness = 2 }, floatBtn)
local floatScale = make("UIScale", { Scale = 1 }, floatBtn)
local floatMoved = makeDraggable(floatBtn, floatBtn)
track(floatBtn.MouseButton1Click:Connect(function()
    if floatMoved() then return end
    floatScale.Scale = 0.75
    TweenService:Create(floatScale,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Scale = 1 }):Play()
    setMenu(not menuOpen)
end))

track(UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == CONFIG.ToggleKey then setMenu(not menuOpen) end
end))

-- ═════════════ BOUCLE ═════════════
local espTimer = 0

track(RunService.Heartbeat:Connect(function(dt)
    local hum = getHum()
    if hum then
        if State.Speed then hum.WalkSpeed = CONFIG.Speed end
        if State.Jump then
            hum.UseJumpPower = true
            hum.JumpPower = CONFIG.Jump
        end
    end

    if State.Fly then pcall(flyStep, dt) end
    if State.Gravity then Workspace.Gravity = CONFIG.Gravity end
    if State.Time then Lighting.ClockTime = CONFIG.ClockTime end

    if State.KillAura or State.AutoClick then pcall(auraStep, dt) end

    if State.Hitbox then
        hitboxTimer = hitboxTimer + dt
        if hitboxTimer >= CONFIG.HitboxInterval then
            hitboxTimer = 0
            pcall(hitboxStep)
        end
    end

    if State.ESP then
        espTimer = espTimer + dt
        if espTimer >= CONFIG.ESPInterval then
            espTimer = 0
            local root = getRoot()
            for plr, obj in pairs(espObjects) do
                local c = plr.Character
                local r = c and c:FindFirstChild("HumanoidRootPart")
                if obj.label and r and root then
                    local d = math.floor((r.Position - root.Position).Magnitude)
                    obj.label.Text = plr.DisplayName .. " [" .. d .. "m]"
                end
                if not c or obj.hl.Adornee ~= c then buildESP(plr) end
            end
        end
    end
end))

track(RunService.RenderStepped:Connect(function()
    if State.FOV and Workspace.CurrentCamera then
        Workspace.CurrentCamera.FieldOfView = CONFIG.FOV
    end
end))

track(LocalPlayer.CharacterAdded:Connect(function()
    flyBV, flyBG = nil, nil
end))

-- ═════════════ INIT ═════════════
pcall(function() RunService:UnbindFromRenderStep("CaptainAim") end)
RunService:BindToRenderStep("CaptainAim", Enum.RenderPriority.Camera.Value + 1, function(dt)
    pcall(aimStep, dt)
end)

selectTab("Player")
pcall(saveOriginal)
setMenu(true)
notify("โหลด Captain Hub🧢 สำเร็จ")
print(("[Captain Hub🧢 v5] โหลดสำเร็จ | Players=%s Bots=%s AimFOV=%d AuraRange=%d Hitbox=%d | Toggle: %s / ปุ่ม 🧢")
    :format(tostring(CONFIG.TargetPlayers), tostring(CONFIG.TargetBots),
        CONFIG.AimFOV, CONFIG.AuraRange, CONFIG.HitboxSize, CONFIG.ToggleKey.Name))

end)

if not bootOK then
    warn("[Captain Hub🧢] ERROR: " .. tostring(bootErr))
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Captain Hub🧢 Error",
            Text = tostring(bootErr):sub(1, 150),
            Duration = 10,
        })
    end)
end
