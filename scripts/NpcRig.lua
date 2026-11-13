-- NpcRig (ModuleScript, ServerScriptService → Modules)
-- R15-персонажи для NPC (персонал, клиенты, Михалыч) со стандартными анимациями Roblox.
-- Пивот модели совпадает со старым блочным: точка на высоте 3 над полом, лицом по -Z.
-- Если R15 создать не удалось, GameServer сам откатывается на старых блочных персонажей.

local Players = game:GetService("Players")

local M = {}

-- стандартные R15-анимации Roblox (доступны в любой игре)
M.Anims = {
	idle = "rbxassetid://507766666",
	walk = "rbxassetid://507777826",
	sit = "rbxassetid://2506281703",
}

local STAND_PIVOT_Y = 3

local base = nil
local loading = false
local failed = false

local function getBase()
	if base or failed then
		return base
	end
	if loading then
		while loading do
			task.wait(0.05)
		end
		return base
	end
	loading = true
	local ok, res = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if ok and res then
		for _, c in ipairs(res:GetDescendants()) do
			if c:IsA("LuaSourceContainer") or c:IsA("BodyColors") or c:IsA("Clothing") or c:IsA("ShirtGraphic") or c:IsA("Accessory") then
				c:Destroy()
			end
		end
		if res:FindFirstChildOfClass("Humanoid") and res:FindFirstChild("HumanoidRootPart") then
			base = res
		end
	else
		warn("[NpcRig] Не удалось создать R15, будут блочные NPC: " .. tostring(res))
	end
	failed = (base == nil)
	loading = false
	return base
end

function M.preload()
	task.spawn(getBase)
end

local TORSO = { "UpperTorso", "LowerTorso" }
local ARMS = { "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm" }
local HANDS = { "LeftHand", "RightHand" }
local LEGS = { "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg" }
local FEET = { "LeftFoot", "RightFoot" }

local function paint(m, names, color, mat)
	if not color then
		return
	end
	for _, n in ipairs(names) do
		local p = m:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			p.Color = color
			if mat then
				p.Material = mat
			end
		end
	end
end

-- маленькая деталь (кепка, галстук и т.п.), приваренная к части тела
local function deco(m, attach, name, size, offset, color, mat)
	if not attach or not color then
		return nil
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.Anchored = false
	p.CFrame = attach.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = attach
	w.Part1 = p
	w.Parent = p
	p.Parent = m
	return p
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- o: таблица одежды из Outfits / randomClientOutfit; skin: цвет кожи
-- возвращает model, torso (UpperTorso) или nil, если R15 недоступен
function M.build(o, name, parent, skin)
	local b = getBase()
	if not b then
		return nil
	end
	local m = b:Clone()
	m.Name = name or "NPC"
	local hum = m:FindFirstChildOfClass("Humanoid")
	local hrp = m:FindFirstChild("HumanoidRootPart")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	if not hum:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = hum
	end

	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanTouch = false
			p.Anchored = false
		end
	end

	-- одежда цветом частей тела
	local top = (o.suit and rgb(25, 25, 30)) or o.shirt
	paint(m, { "Head" }, skin)
	paint(m, HANDS, skin)
	paint(m, TORSO, top, Enum.Material.SmoothPlastic)
	paint(m, { "UpperTorso" }, o.vest, Enum.Material.Fabric)
	paint(m, ARMS, (o.suit and rgb(25, 25, 30)) or o.jacket or o.shirt)
	paint(m, { "LowerTorso" }, o.pants)
	paint(m, LEGS, o.pants)
	paint(m, FEET, o.shoes)

	local head = m:FindFirstChild("Head")
	if head and not head:FindFirstChildOfClass("Decal") then
		local face = Instance.new("Decal")
		face.Name = "face"
		face.Texture = "rbxasset://textures/face.png"
		face.Face = Enum.NormalId.Front
		face.Parent = head
	end
	local ut = m:FindFirstChild("UpperTorso")
	local lt = m:FindFirstChild("LowerTorso")

	if head then
		local hs = head.Size
		if o.hat == "cap" then
			local c = o.hatColor or rgb(200, 80, 20)
			deco(m, head, "Cap", Vector3.new(hs.X + 0.12, 0.4, hs.Z + 0.12), CFrame.new(0, hs.Y / 2 + 0.1, 0), c)
			deco(m, head, "Visor", Vector3.new(hs.X, 0.1, 0.6), CFrame.new(0, hs.Y / 2 - 0.05, -hs.Z / 2 - 0.25), c)
		elseif o.hair then
			deco(m, head, "Hair", Vector3.new(hs.X + 0.08, 0.3, hs.Z + 0.08), CFrame.new(0, hs.Y / 2 + 0.05, 0.03), o.hair)
			deco(m, head, "HairBack", Vector3.new(hs.X + 0.08, hs.Y * 0.6, 0.22), CFrame.new(0, hs.Y * 0.15, hs.Z / 2 + 0.05), o.hair)
		end
		if o.beard then
			deco(m, head, "Beard", Vector3.new(hs.X * 0.85, hs.Y * 0.4, 0.22), CFrame.new(0, -hs.Y * 0.3, -hs.Z / 2 - 0.05), o.beard)
		end
	end
	if ut then
		local us = ut.Size
		if o.suit then
			deco(m, ut, "Shirt", Vector3.new(0.6, us.Y * 0.95, 0.05), CFrame.new(0, 0, -us.Z / 2 - 0.02), rgb(245, 245, 245))
			deco(m, ut, "Tie", Vector3.new(0.22, us.Y * 0.75, 0.06), CFrame.new(0, 0.05, -us.Z / 2 - 0.06), o.tie)
		end
		if o.stripes then
			deco(m, ut, "Pocket", Vector3.new(0.5, 0.45, 0.05), CFrame.new(0.45, 0.2, -us.Z / 2 - 0.02), rgb(15, 35, 90))
		end
	end
	if lt then
		local ls = lt.Size
		if o.stripes then
			deco(m, lt, "Stripe", Vector3.new(ls.X + 0.04, 0.2, ls.Z + 0.04), CFrame.new(0, 0, 0), o.stripes, Enum.Material.Neon)
			for _, n in ipairs({ "LeftLowerLeg", "RightLowerLeg" }) do
				local leg = m:FindFirstChild(n)
				if leg then
					deco(m, leg, "LegStripe", Vector3.new(leg.Size.X + 0.04, 0.2, leg.Size.Z + 0.04), CFrame.new(0, 0, 0), o.stripes, Enum.Material.Neon)
				end
			end
		end
		if o.belt then
			deco(m, lt, "ToolBelt", Vector3.new(ls.X + 0.1, 0.35, ls.Z + 0.1), CFrame.new(0, 0.1, 0), o.belt)
			deco(m, lt, "Pouch", Vector3.new(0.5, 0.6, 0.4), CFrame.new(0.7, -0.2, -ls.Z / 2 - 0.15), o.belt)
		end
	end

	-- пивот как у старого блочного персонажа: y = 3 над полом
	local rootH = hum.HipHeight + hrp.Size.Y / 2
	hrp.PivotOffset = CFrame.new(0, STAND_PIVOT_Y - rootH, 0)
	m.PrimaryPart = hrp
	hrp.Anchored = true
	m:PivotTo(CFrame.new(0, STAND_PIVOT_Y, 0))
	m.Parent = parent
	M.play(m, "idle")
	return m, ut or hrp
end

-- Аватар реального игрока по UserId (Config.NpcAvatars)
local avatarCache = {}
local avatarLoading = {}
local avatarFailAt = {}

local function getAvatarBase(userId)
	if avatarCache[userId] then
		return avatarCache[userId]
	end
	if avatarFailAt[userId] and os.clock() - avatarFailAt[userId] < 60 then
		return nil
	end
	if avatarLoading[userId] then
		while avatarLoading[userId] do
			task.wait(0.05)
		end
		return avatarCache[userId]
	end
	avatarLoading[userId] = true
	local ok, res = pcall(function()
		local desc = Players:GetHumanoidDescriptionFromUserId(userId)
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if ok and res and res:FindFirstChildOfClass("Humanoid") and res:FindFirstChild("HumanoidRootPart") then
		for _, c in ipairs(res:GetDescendants()) do
			if c:IsA("LuaSourceContainer") then
				c:Destroy()
			end
		end
		avatarCache[userId] = res
	else
		avatarFailAt[userId] = os.clock()
		warn("[NpcRig] Не удалось загрузить аватар " .. tostring(userId) .. ": " .. tostring(res))
	end
	avatarLoading[userId] = nil
	return avatarCache[userId]
end

function M.preloadAvatar(userId)
	userId = tonumber(userId)
	if userId and userId > 0 then
		task.spawn(getAvatarBase, userId)
	end
end

-- возвращает model, torso или nil (тогда GameServer берёт обычную униформу)
function M.buildAvatar(userId, name, parent)
	userId = tonumber(userId)
	if not userId or userId <= 0 then
		return nil
	end
	local b = getAvatarBase(userId)
	if not b then
		return nil
	end
	local m = b:Clone()
	m.Name = name or "NPC"
	local hum = m:FindFirstChildOfClass("Humanoid")
	local hrp = m:FindFirstChild("HumanoidRootPart")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	if not hum:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = hum
	end
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanTouch = false
			p.Anchored = false
		end
	end
	local rootH = hum.HipHeight + hrp.Size.Y / 2
	hrp.PivotOffset = CFrame.new(0, STAND_PIVOT_Y - rootH, 0)
	m.PrimaryPart = hrp
	hrp.Anchored = true
	m:PivotTo(CFrame.new(0, STAND_PIVOT_Y, 0))
	m.Parent = parent
	M.play(m, "idle")
	return m, m:FindFirstChild("UpperTorso") or hrp
end

local tracks = setmetatable({}, { __mode = "k" })

-- kind: "idle" | "walk" | "sit". Для блочных персонажей ничего не делает.
function M.play(m, kind, speed)
	local hum = m and m:FindFirstChildOfClass("Humanoid")
	if not hum or not m.Parent then
		return
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local t = tracks[m]
	if not t then
		t = {}
		tracks[m] = t
	end
	local tr = t[kind]
	if not tr then
		local a = Instance.new("Animation")
		a.AnimationId = M.Anims[kind]
		local ok, res = pcall(function()
			return animator:LoadAnimation(a)
		end)
		if not ok or not res then
			return
		end
		tr = res
		tr.Looped = true
		tr.Priority = (kind == "walk") and Enum.AnimationPriority.Movement
			or (kind == "sit") and Enum.AnimationPriority.Action
			or Enum.AnimationPriority.Idle
		t[kind] = tr
	end
	for k, other in pairs(t) do
		if k ~= kind and other.IsPlaying then
			other:Stop(0.2)
		end
	end
	if not tr.IsPlaying then
		tr:Play(0.2)
	end
	if speed then
		tr:AdjustSpeed(math.clamp(speed, 0.4, 1.6))
	end
end

-- Посадить R15 на невидимое сиденье. seatTopCF — верх подушки кресла, LookVector = куда смотрит человек.
-- Возвращает false, если модель не R15 (тогда GameServer использует блочного сидящего).
function M.sit(m, seatTopCF)
	local hum = m and m:FindFirstChildOfClass("Humanoid")
	local hrp = m and m:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then
		return false
	end
	m:PivotTo(seatTopCF * CFrame.new(0, STAND_PIVOT_Y, 0))
	local seat = Instance.new("Seat")
	seat.Name = "NpcSeat"
	seat.Size = Vector3.new(2, 0.2, 2)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false -- игроки не сядут на него случайно
	seat.CanQuery = false
	seat.Anchored = true
	seat.CFrame = seatTopCF * CFrame.new(0, -0.1, 0)
	seat.Parent = m.Parent
	m.Destroying:Connect(function()
		seat:Destroy()
	end)
	hrp.Anchored = false
	local ok = pcall(function()
		seat:Sit(hum)
	end)
	if not ok or not seat:FindFirstChild("SeatWeld") then
		-- запасной вариант: просто ставим в позу сидя
		hrp.Anchored = true
		hrp.CFrame = seatTopCF * CFrame.new(0, hrp.Size.Y / 2 + 0.6, 0)
	end
	M.play(m, "sit")
	return true
end

return M
