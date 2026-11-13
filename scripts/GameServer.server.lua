-- GameServer (Script, ServerScriptService)
-- v4: парковка и выбор машины, смотровая яма, день/ночь и погода, банк и кредиты,
-- подарки, звуки, новые детали, несколько ремонтов одновременно, новый город.
-- v3.1: свои модели машин из Toolbox (ServerStorage → CarModels).
-- Симулятор автомеханика v3: сюжет и обучение, боксы на 4 игроков, своё название мастерской.
-- v2: Check Engine и сканер, болты (ржавые / WD-40 / молоток),
-- капиталка на стенде, шиномонтаж, компьютер с заказом деталей, работники, донат.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("MechanicConfig"))

local CASH = "Деньги"
local REPAIRS = "Ремонты"

-- модули (ServerScriptService → Modules)
local Modules = script.Parent:WaitForChild("Modules")
local DataSave = require(Modules:WaitForChild("DataSave"))
local NpcRig = require(Modules:WaitForChild("NpcRig"))
-- тот же ключ, что и раньше: старый прогресс игроков сохраняется
DataSave.init("AutoMechanicSim_v2")
NpcRig.preload()
for _, uid in pairs(Config.NpcAvatars or {}) do
	NpcRig.preloadAvatar(uid)
end

---------------------------------------------------------------- УДАЛЁННЫЕ СОБЫТИЯ
local remotes = Instance.new("Folder")
remotes.Name = "MechanicRemotes"
local function remote(cls, name)
	local r = Instance.new(cls)
	r.Name = name
	r.Parent = remotes
	return r
end
local NotifyEvent = remote("RemoteEvent", "Notify")
local OpenUIEvent = remote("RemoteEvent", "OpenUI")
local JobUpdateEvent = remote("RemoteEvent", "JobUpdate")
local JobActionEvent = remote("RemoteEvent", "JobAction")
local ShopFunction = remote("RemoteFunction", "ShopAction")
local StoryEvent = remote("RemoteEvent", "Story")
local ParkingEvent = remote("RemoteEvent", "Parking")
remotes.Parent = ReplicatedStorage

local PD = {}          -- player -> служебные данные
local viewing = {}     -- player -> номер поста, который открыт в панели
local activeFault = {} -- player -> текущий ремонт
local NPCs = {}        -- player -> { workerId -> { model, label } }
local Bays = {}

local function notify(p, text, kind)
	NotifyEvent:FireClient(p, text, kind or "info")
end

---------------------------------------------------------------- ПРОГРЕСС: РАНГ, ЗВЁЗДЫ, ЗАДАНИЯ, ЕЖЕДНЕВНАЯ НАГРАДА, БУСТ
local HttpService = game:GetService("HttpService")
local STARS = "Рейтинг"
local Hooks = {} -- refreshSigns(p) задаётся ниже, когда появятся участки

local function today()
	return math.floor(os.time() / 86400)
end

local function repairsOf(p)
	local ls = p:FindFirstChild("leaderstats")
	local r = ls and ls:FindFirstChild(REPAIRS)
	return r and r.Value or 0
end

local function rankOf(repairs)
	local idx = 1
	for i, r in ipairs(Config.Ranks) do
		if repairs >= r.repairs then
			idx = i
		end
	end
	return idx, Config.Ranks[idx]
end

local function ratingOf(d)
	local list = d and d.reviews
	if not list or #list == 0 then
		return nil
	end
	local s = 0
	for _, v in ipairs(list) do
		s = s + v
	end
	return s / #list
end

local function boostActive(p)
	return (p:GetAttribute("BoostUntil") or 0) > os.time()
end

local function syncProgress(p)
	local d = PD[p]
	if not d then
		return
	end
	local idx, rk = rankOf(repairsOf(p))
	if d.rank and idx > d.rank then
		notify(p, "🏅 Новый ранг мастерской: «" .. rk.name .. "»! Бонус к доходу: +" .. math.floor(rk.bonus * 100 + 0.5) .. "%", "good")
	end
	d.rank = idx
	p:SetAttribute("Rank", idx)
	local rating = ratingOf(d)
	p:SetAttribute("Rating", rating and math.floor(rating * 10 + 0.5) / 10 or 0)
	p:SetAttribute("RatingCount", d.reviewsTotal or 0)
	local ls = p:FindFirstChild("leaderstats")
	local st = ls and ls:FindFirstChild(STARS)
	if st then
		st.Value = rating and string.format("★%.1f", rating) or "—"
	end
	if Hooks.refreshSigns then
		Hooks.refreshSigns(p)
	end
end

local function questsSync(p)
	local d = PD[p]
	if d and d.quests then
		p:SetAttribute("Quests", HttpService:JSONEncode(d.quests.list))
	end
end

-- новые сутки: новые задания и проверка ежедневной награды
local function ensureDaily(p)
	local d = PD[p]
	if not d then
		return
	end
	local t = today()
	if not d.quests or d.quests.day ~= t then
		local pool = table.clone(Config.DailyQuests)
		local list, used = {}, {}
		while #list < (Config.QuestsPerDay or 3) and #pool > 0 do
			local q = table.remove(pool, math.random(1, #pool))
			local key = q.kind .. (q.fault or "")
			if not used[key] then
				used[key] = true
				table.insert(list, { id = q.id, n = 0, claimed = false })
			end
		end
		local fresh = d.quests ~= nil
		d.quests = { day = t, list = list }
		questsSync(p)
		if fresh and d.tut then
			notify(p, "📋 Новые задания на день! Кнопка «📋 Мастерская»", "info")
		end
	end
	d.daily = d.daily or { day = -1, streak = 0 }
	local ready = d.daily.day ~= t
	local streak = d.daily.streak or 0
	if ready then
		streak = (d.daily.day == t - 1) and (streak % #Config.DailyRewards) + 1 or 1
	end
	if ready and not p:GetAttribute("DailyReady") and d.tut then
		notify(p, "🎁 Ежедневная награда ждёт! Кнопка «📋 Мастерская»", "good")
	end
	p:SetAttribute("DailyReady", ready)
	p:SetAttribute("DailyStreak", streak)
end

local function questAdd(p, kind, amount, faultId)
	local d = PD[p]
	if not d or not d.quests or not d.tut then
		return
	end
	local changed = false
	for _, q in ipairs(d.quests.list) do
		local def = Config.QuestById[q.id]
		if def and def.kind == kind and (not def.fault or def.fault == faultId) and q.n < def.goal then
			q.n = math.min(def.goal, q.n + amount)
			changed = true
			if q.n >= def.goal then
				notify(p, "📋 Задание выполнено: «" .. def.text .. "». Заберите награду в «📋 Мастерская»", "good")
			end
		end
	end
	if changed then
		questsSync(p)
	end
end

local function addReview(p, stars, why)
	local d = PD[p]
	if not d then
		return
	end
	d.reviews = d.reviews or {}
	table.insert(d.reviews, stars)
	while #d.reviews > (Config.RatingWindow or 20) do
		table.remove(d.reviews, 1)
	end
	d.reviewsTotal = (d.reviewsTotal or 0) + 1
	local txt = "Отзыв клиента: " .. string.rep("★", stars) .. string.rep("☆", 5 - stars)
	if why ~= "" then
		txt = txt .. " (" .. why .. ")"
	end
	notify(p, txt, stars >= 4 and "good" or "bad")
	if stars == 5 then
		questAdd(p, "stars5", 1)
	end
	syncProgress(p)
end

---------------------------------------------------------------- ДЕНЬГИ И СКЛАД
local function cashObj(p)
	local ls = p:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild(CASH)
end

local function getCash(p)
	local c = cashObj(p)
	return c and c.Value or 0
end

-- множитель доходов: x2 денег, буст, VIP, ранг мастерской
local function incomeMult(p)
	local m = 1
	if p:GetAttribute("Pass_x2cash") then
		m = m * 2
	end
	if boostActive(p) then
		m = m * 2
	end
	if p:GetAttribute("Pass_vip") then
		m = m * (1 + (Config.VipIncomeBonus or 0.25))
	end
	local _, rk = rankOf(repairsOf(p))
	return m * (1 + (rk.bonus or 0))
end

local function addCash(p, amount, isIncome)
	local c = cashObj(p)
	if not c then
		return 0
	end
	if isIncome then
		amount = amount * incomeMult(p)
	end
	amount = math.floor(amount + 0.5)
	c.Value = c.Value + amount
	if isIncome and amount > 0 then
		questAdd(p, "earn", amount)
	end
	return amount
end

local function spend(p, amount)
	local c = cashObj(p)
	if not c or c.Value < amount then
		return false
	end
	c.Value = c.Value - amount
	return true
end

local function addRepair(p)
	local ls = p:FindFirstChild("leaderstats")
	local r = ls and ls:FindFirstChild(REPAIRS)
	if r then
		r.Value = r.Value + 1
	end
end

local function invGet(p, id)
	return p:GetAttribute("Inv_" .. id) or 0
end

local function invAdd(p, id, n)
	p:SetAttribute("Inv_" .. id, math.max(0, invGet(p, id) + n))
end

local function owns(p, id)
	return p:GetAttribute("Own_" .. id) == true
end

local function hired(p, id)
	return p:GetAttribute("Hire_" .. id) == true
end

local function itemName(id)
	local it = Config.ItemById[id]
	return it and it.name or id
end

---------------------------------------------------------------- ПОСТРОЕНИЕ МИРА
local world = Instance.new("Folder")
world.Name = "Garage"
world.Parent = workspace

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape
	end
	for k, v in pairs(props) do
		if k ~= "Parent" and k ~= "Shape" then
			p[k] = v
		end
	end
	p.Parent = props.Parent or world
	return p
end

local function label3d(adornee, text, offsetY, color, w, h)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, w or 240, 0, h or 56)
	bb.StudsOffset = Vector3.new(0, offsetY or 3, 0)
	bb.MaxDistance = 80
	bb.Adornee = adornee
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, 0, 1, 0)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBold
	tl.TextColor3 = color or Color3.new(1, 1, 1)
	tl.TextStrokeTransparency = 0.3
	tl.Parent = bb
	bb.Parent = adornee
	return tl
end

local function prompt(parentPart, action, object, cb)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object or ""
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp.Parent = parentPart
	pp.Triggered:Connect(cb)
	return pp
end

local openJob
local openActive

-- звуковой эффект в точке мира (ключи — Config.Sounds)
local Debris = game:GetService("Debris")
local function sfx(pos, key)
	local s = Config.Sounds and Config.Sounds[key]
	if not s or not s.id or s.id == "" or not pos then
		return
	end
	pcall(function()
		local a = Instance.new("Part")
		a.Name = "Sfx"
		a.Anchored = true
		a.CanCollide = false
		a.CanQuery = false
		a.Transparency = 1
		a.Size = Vector3.new(0.5, 0.5, 0.5)
		a.Position = pos + Vector3.new(0, 3, 0)
		a.Parent = workspace
		local snd = Instance.new("Sound")
		snd.SoundId = s.id
		snd.Volume = s.volume or 0.7
		snd.PlaybackSpeed = s.pitch or 1
		snd.RollOffMaxDistance = 90
		snd.RollOffMinDistance = 8
		snd.Parent = a
		local loops = s.loops or 1
		task.spawn(function()
			for _ = 1, loops do
				if not a.Parent then
					return
				end
				snd:Play()
				local len = snd.TimeLength
				task.wait((len > 0 and len / snd.PlaybackSpeed or 0.3) * 0.9)
			end
		end)
		Debris:AddItem(a, 2 + loops * 1.2)
	end)
end

---------------------------------------------------------------- ГРАФИКА И ОСВЕЩЕНИЕ
local Lighting = game:GetService("Lighting")
local TextService = game:GetService("TextService")
local PartModels = require(ReplicatedStorage:WaitForChild("PartModels"))

pcall(function()
	Lighting.ClockTime = 15.5
	Lighting.Brightness = 2.6
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 120, 130)
	Lighting.Ambient = Color3.fromRGB(40, 40, 50)
	Lighting.ShadowSoftness = 0.25
	local function ensure(cls)
		local o = Lighting:FindFirstChildOfClass(cls)
		if not o then
			o = Instance.new(cls)
			o.Parent = Lighting
		end
		return o
	end
	ensure("Sky")
	local atm = ensure("Atmosphere")
	atm.Density = 0.28
	atm.Haze = 1.2
	atm.Color = Color3.fromRGB(200, 210, 225)
	atm.Decay = Color3.fromRGB(110, 120, 140)
	local bloom = ensure("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 30
	bloom.Threshold = 1.4
	local cc = ensure("ColorCorrectionEffect")
	cc.Contrast = 0.08
	cc.Saturation = 0.12
	cc.TintColor = Color3.fromRGB(255, 248, 238)
	local rays = ensure("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.6
end)

-- ДЕНЬ / НОЧЬ / ПОГОДА (состояние; цикл запускается внизу, в блоке СТАРТ)
local World = { night = false, clock = 8, weather = "clear", day = 1, season = "summer", seasonLeft = 0, summerSwapLeft = 0 }
local NightLights = {}  -- { light = PointLight, part = неоновая лампа }
local NightWindows = {} -- окна домов, которые светятся ночью
local function applyNight(night)
	for _, l in ipairs(NightLights) do
		if l.light then
			l.light.Enabled = night
		end
		if l.part then
			l.part.Material = night and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
	end
	for _, w in ipairs(NightWindows) do
		w.Material = night and Enum.Material.Neon or Enum.Material.Glass
		w.Color = night and Color3.fromRGB(255, 225, 150) or Color3.fromRGB(70, 95, 120)
		w.Transparency = night and 0.15 or 0.1
	end
end

---------------------------------------------------------------- БОКСЫ (до 4 игроков, у каждого свой)
local PLOT_SPACING = 190
local BAY_LX = { -48, -16, 16, 48 } -- 4-й пост открывается донатом «+1 подъёмник»
local BAY_LZ = -15
-- смотровая яма (пост Config.PitBay): ширина, начало/конец по Z, глубина
local PIT_W, PIT_Z1, PIT_Z2, PIT_D = 4.4, BAY_LZ - 9, BAY_LZ + 13, 6
-- клиентская парковка за мастерской
local PARK_LX = { -64, -32, 32, 64 } -- между путями выезда с постов
local PARK_LZ = -78
local LANE_Z = -66
local Plots = {}
local onMentorTalk -- объявлена в блоке обучения
local Tut = {} -- хуки обучения (open, carDone, carLeft)
local BankDoors = {} -- позиции дверей банков (цель обучения «возьмите кредит»)

local function plotOf(p)
	for _, pl in ipairs(Plots) do
		if pl.owner == p then
			return pl
		end
	end
	return nil
end

Hooks.refreshSigns = function(p)
	local pl = plotOf(p)
	if pl then
		for _, f in ipairs(pl.nameHooks) do
			pcall(f)
		end
	end
end

-- 4-й пост закрыт, пока у владельца нет доната «+1 подъёмник»
local function bayLocked(bay)
	if not bay.bonus then
		return false
	end
	local o = bay.plot.owner
	return not (o and o:GetAttribute("Pass_extra_lift"))
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- текст на поверхности детали (вывески, таблички, надписи на форме)
local function surfaceText(adornee, face, text, color, font, bg)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	sg.Brightness = 1.5
	sg.Parent = adornee
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, 0, 1, 0)
	t.BackgroundTransparency = bg and 0 or 1
	if bg then
		t.BackgroundColor3 = bg
	end
	t.TextScaled = true
	t.Font = font or Enum.Font.GothamBlack
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.Text = text
	t.Parent = sg
	return t
end

local function pointLight(parentPart, color, range, brightness, surface)
	local l
	if surface then
		l = Instance.new("SurfaceLight")
		l.Face = Enum.NormalId.Bottom
		l.Angle = 120
	else
		l = Instance.new("PointLight")
	end
	l.Color = color or rgb(255, 244, 220)
	l.Range = range or 20
	l.Brightness = brightness or 1.5
	l.Shadows = true
	l.Parent = parentPart
	return l
end

---------------------------------------------------------------- ЛЮДИ (скины NPC)
-- вид одежды
local Outfits = {
	mechanic = { shirt = rgb(25, 50, 120), pants = rgb(25, 50, 120), shoes = rgb(20, 20, 20), hat = "cap", hatColor = rgb(220, 90, 20), stripes = rgb(220, 230, 60), title = "МЕХАНИК" },
	electrician = { shirt = rgb(90, 150, 90), pants = rgb(60, 80, 130), shoes = rgb(90, 60, 40), hair = rgb(70, 45, 25), belt = rgb(60, 40, 20), title = "ЭЛЕКТРИК" },
	admin = { shirt = rgb(25, 25, 30), pants = rgb(25, 25, 30), shoes = rgb(10, 10, 10), hair = rgb(30, 25, 20), suit = true, tie = rgb(150, 20, 30), title = "АДМИНИСТРАТОР" },
	mentor = { shirt = rgb(110, 90, 60), pants = rgb(70, 70, 75), shoes = rgb(60, 40, 30), hair = rgb(200, 200, 200), vest = rgb(60, 80, 50), beard = rgb(215, 215, 215) },
}
local ClientShirts = { rgb(200, 60, 60), rgb(60, 120, 200), rgb(240, 240, 240), rgb(240, 190, 40), rgb(120, 60, 160), rgb(40, 140, 120), rgb(230, 130, 170), rgb(90, 90, 90) }
local ClientPants = { rgb(40, 50, 90), rgb(30, 30, 30), rgb(120, 100, 70), rgb(70, 70, 80) }
local Skins = { rgb(255, 214, 170), rgb(235, 190, 150), rgb(200, 150, 110), rgb(150, 105, 75) }
local HairCols = { rgb(30, 25, 20), rgb(90, 60, 30), rgb(200, 160, 80), rgb(140, 50, 30), rgb(60, 60, 60) }

local function randomClientOutfit()
	return {
		skin = Skins[math.random(1, #Skins)], -- один цвет кожи на всё время визита
		shirt = ClientShirts[math.random(1, #ClientShirts)],
		pants = ClientPants[math.random(1, #ClientPants)],
		shoes = rgb(math.random(20, 200), math.random(20, 200), math.random(20, 200)),
		hair = HairCols[math.random(1, #HairCols)],
		hat = (math.random() < 0.25) and "cap" or nil,
		hatColor = ClientShirts[math.random(1, #ClientShirts)],
		jacket = (math.random() < 0.3) and rgb(60, 45, 35) or nil,
	}
end

-- Блочный персонаж (запасной вариант, если R15 недоступен). Пивот = центр торса (y = 3 стоя, y = 2.4 сидя).
local function makeBlockyRig(o, name, sitting, parent)
	local m = Instance.new("Model")
	m.Name = name or "NPC"
	local skin = o.skin or Skins[math.random(1, #Skins)]
	local function bp(n, size, cf, color, mat)
		return part({ Name = n, Size = size, CFrame = cf, Color = color, Material = mat or Enum.Material.SmoothPlastic, CanCollide = false, Parent = m })
	end
	local torso = bp("Torso", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), o.suit and rgb(25, 25, 30) or o.shirt, o.mechanic and Enum.Material.Fabric or Enum.Material.SmoothPlastic)
	m.PrimaryPart = torso
	if sitting then
		for _, x in ipairs({ -0.5, 0.5 }) do
			bp("Thigh", Vector3.new(1, 1, 2), CFrame.new(x, 1.5, -1), o.pants)
			bp("Shin", Vector3.new(1, 1.4, 1), CFrame.new(x, 0.7, -1.5), o.pants)
			bp("Shoe", Vector3.new(1, 0.3, 1.2), CFrame.new(x, 0.15, -1.6), o.shoes)
		end
	else
		for _, x in ipairs({ -0.5, 0.5 }) do
			bp("Leg", Vector3.new(1, 1.8, 1), CFrame.new(x, 1.1, 0), o.pants)
			bp("Shoe", Vector3.new(1, 0.3, 1.2), CFrame.new(x, 0.15, -0.1), o.shoes)
		end
	end
	for _, x in ipairs({ -1.5, 1.5 }) do
		bp("Arm", Vector3.new(1, 2, 1), CFrame.new(x, 3, 0), (o.suit and rgb(25, 25, 30)) or o.jacket or o.shirt)
		bp("Hand", Vector3.new(0.9, 0.5, 0.9), CFrame.new(x, 1.8, 0), skin)
	end
	local head = bp("Head", Vector3.new(1.3, 1.3, 1.3), CFrame.new(0, 4.65, 0), skin)
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	if o.hat == "cap" then
		bp("Cap", Vector3.new(1.4, 0.45, 1.4), CFrame.new(0, 5.45, 0), o.hatColor or rgb(200, 80, 20))
		bp("Visor", Vector3.new(1.3, 0.12, 0.7), CFrame.new(0, 5.25, -0.95), o.hatColor or rgb(200, 80, 20))
	elseif o.hair then
		bp("Hair", Vector3.new(1.4, 0.4, 1.4), CFrame.new(0, 5.4, 0.05), o.hair)
		bp("HairBack", Vector3.new(1.4, 0.9, 0.3), CFrame.new(0, 4.95, 0.6), o.hair)
	end
	if o.beard then
		bp("Beard", Vector3.new(1.2, 0.6, 0.3), CFrame.new(0, 4.2, -0.6), o.beard)
	end
	-- костюм: белая рубашка + галстук
	if o.suit then
		bp("Shirt", Vector3.new(0.7, 1.9, 0.05), CFrame.new(0, 3.02, -0.52), rgb(245, 245, 245))
		bp("Tie", Vector3.new(0.25, 1.4, 0.06), CFrame.new(0, 3.15, -0.56), o.tie)
	end
	-- комбинезон механика со светоотражающими полосами
	if o.stripes then
		bp("Stripe", Vector3.new(2.02, 0.2, 1.02), CFrame.new(0, 2.4, 0), o.stripes, Enum.Material.Neon)
		for _, x in ipairs({ -0.5, 0.5 }) do
			bp("LegStripe", Vector3.new(1.02, 0.2, 1.02), CFrame.new(x, 0.9, 0), o.stripes, Enum.Material.Neon)
		end
		bp("Pocket", Vector3.new(0.6, 0.5, 0.05), CFrame.new(0.5, 3.4, -0.52), rgb(15, 35, 90))
	end
	if o.belt then
		bp("ToolBelt", Vector3.new(2.1, 0.35, 1.1), CFrame.new(0, 2.15, 0), o.belt)
		bp("Pouch", Vector3.new(0.5, 0.6, 0.4), CFrame.new(0.8, 1.9, -0.5), o.belt)
	end
	if o.vest then
		bp("Vest", Vector3.new(2.06, 1.7, 1.06), CFrame.new(0, 3.1, 0), o.vest, Enum.Material.Fabric)
	end
	if sitting then
		m:PivotTo(CFrame.new(0, 2.4, 0))
	end
	m.Parent = parent or world
	return m, torso
end

-- R15-персонаж с анимациями (модуль NpcRig). Стоячий; чтобы посадить — NpcRig.sit.
local function makeRig(o, name, sitting, parent, avatarId)
	local skin = o.skin or Skins[math.random(1, #Skins)]
	if not sitting then
		if avatarId then
			local am, atorso = NpcRig.buildAvatar(avatarId, name, parent or world)
			if am then
				return am, atorso, true
			end
		end
		local m, torso = NpcRig.build(o, name, parent or world, skin)
		if m then
			return m, torso
		end
	end
	return makeBlockyRig(o, name, sitting, parent)
end

-- надпись названия мастерской на спине униформы
local function uniformLabel(torso, plot, title)
	local t = surfaceText(torso, Enum.NormalId.Back, "", rgb(255, 255, 255), Enum.Font.GothamBold)
	local function refresh()
		t.Text = (title or "") .. "\n" .. (plot.shopName or Config.DefaultShopName)
	end
	refresh()
	table.insert(plot.nameHooks, refresh)
	return t
end


---------------------------------------------------------------- МАШИНЫ (разные кузова)
-- L длина, W ширина, H высота кузова, ride клиренс, hood/trunk длина капота/багажника, cabH высота салона
local BodyTypes = {
	sedan = { L = 14, W = 7, H = 1.9, ride = 1.0, hood = 4.2, trunk = 3.2, cabH = 2.2, wheel = 2.6 },
	hatch = { L = 12, W = 6.8, H = 1.9, ride = 1.0, hood = 3.6, trunk = 0.6, cabH = 2.4, wheel = 2.5 },
	wagon = { L = 15, W = 7, H = 1.9, ride = 1.0, hood = 4.2, trunk = 0.6, cabH = 2.3, wheel = 2.6 },
	suv = { L = 14.5, W = 7.6, H = 2.6, ride = 1.6, hood = 3.8, trunk = 0.5, cabH = 2.6, wheel = 3.3 },
	pickup = { L = 16, W = 7.4, H = 2.4, ride = 1.6, hood = 4.2, trunk = 6.5, cabH = 2.6, wheel = 3.2, bed = true },
	van = { L = 16, W = 7.6, H = 2.2, ride = 1.2, hood = 2.4, trunk = 0.3, cabH = 4.6, wheel = 2.8 },
	coupe = { L = 13.5, W = 7, H = 1.5, ride = 0.7, hood = 5.2, trunk = 2.6, cabH = 1.7, wheel = 2.6, spoiler = true },
	classic = { L = 13.5, W = 6.6, H = 2.0, ride = 1.1, hood = 3.8, trunk = 3.2, cabH = 2.4, wheel = 2.4, chrome = true, round = true },
}

local function makeCar(color, bodyName)
	local b = BodyTypes[bodyName] or BodyTypes.sedan
	local m = Instance.new("Model")
	m.Name = "CustomerCar"
	local L, W, H = b.L, b.W, b.H
	local baseY = b.ride + H / 2 + 0.3
	local function cp(n, size, cf, col, mat, extra)
		local props = { Name = n, Size = size, CFrame = cf, Color = col, Material = mat or Enum.Material.SmoothPlastic, Parent = m, CanCollide = false }
		if extra then
			for k, v in pairs(extra) do
				props[k] = v
			end
		end
		return part(props)
	end
	local paint = Enum.Material.SmoothPlastic
	local body = cp("Body", Vector3.new(W, H, L), CFrame.new(0, baseY, 0), color, paint, { Reflectance = 0.08, CanCollide = true })
	m.PrimaryPart = body
	body.PivotOffset = CFrame.new(0, -baseY, 0)
	local front = L / 2
	-- салон со стёклами
	local cabLen = L - b.hood - b.trunk
	local cabZ = front - b.hood - cabLen / 2
	local topY = baseY + H / 2
	if b.bed then
		cabLen = 5
		cabZ = front - b.hood - cabLen / 2
	end
	local glass = rgb(25, 35, 45)
	cp("Cabin", Vector3.new(W - 0.6, b.cabH, cabLen - 0.8), CFrame.new(0, topY + b.cabH / 2, cabZ), glass, Enum.Material.Glass, { Transparency = 0.35, Reflectance = 0.2 })
	cp("Roof", Vector3.new(W - 0.5, 0.25, cabLen - 1.6), CFrame.new(0, topY + b.cabH + 0.1, cabZ - 0.1), color, paint, { Reflectance = 0.08 })
	for _, x in ipairs({ -(W / 2 - 0.45), W / 2 - 0.45 }) do
		cp("Pillar", Vector3.new(0.3, b.cabH, 0.35), CFrame.new(x, topY + b.cabH / 2, cabZ + cabLen / 2 - 0.5), color, paint)
		cp("Pillar", Vector3.new(0.3, b.cabH, 0.35), CFrame.new(x, topY + b.cabH / 2, cabZ - cabLen / 2 + 0.5), color, paint)
		cp("Mirror", Vector3.new(0.6, 0.45, 0.25), CFrame.new(x + (x > 0 and 0.4 or -0.4), topY + 0.4, cabZ + cabLen / 2 - 0.6), color, paint)
		cp("Handle", Vector3.new(0.08, 0.15, 0.6), CFrame.new(x + (x > 0 and 0.32 or -0.32), topY - 0.3, cabZ), rgb(30, 30, 30))
	end
	-- капот чуть выше, решётка и фары
	cp("Hood", Vector3.new(W - 0.4, 0.2, b.hood - 0.3), CFrame.new(0, topY + 0.1, front - b.hood / 2), color, paint, { Reflectance = 0.1 })
	cp("Grille", Vector3.new(W * 0.5, H * 0.45, 0.15), CFrame.new(0, baseY + 0.1, front + 0.05), rgb(25, 25, 28), Enum.Material.DiamondPlate)
	local bumperCol = b.chrome and rgb(210, 215, 220) or rgb(35, 35, 38)
	local bumperMat = b.chrome and Enum.Material.Metal or Enum.Material.SmoothPlastic
	cp("BumperF", Vector3.new(W + 0.2, 0.6, 0.6), CFrame.new(0, baseY - H / 2 + 0.3, front + 0.2), bumperCol, bumperMat)
	cp("BumperR", Vector3.new(W + 0.2, 0.6, 0.6), CFrame.new(0, baseY - H / 2 + 0.3, -front - 0.2), bumperCol, bumperMat)
	for _, x in ipairs({ -(W / 2 - 0.9), W / 2 - 0.9 }) do
		if b.round then
			cp("Headlight", Vector3.new(0.2, 0.8, 0.8), CFrame.new(x, baseY + 0.2, front + 0.05) * CFrame.Angles(0, math.rad(90), 0), rgb(255, 250, 220), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder })
		else
			cp("Headlight", Vector3.new(1.3, 0.45, 0.15), CFrame.new(x, baseY + 0.35, front + 0.05), rgb(255, 250, 220), Enum.Material.Neon)
		end
		cp("Taillight", Vector3.new(1.2, 0.45, 0.15), CFrame.new(x, baseY + 0.35, -front - 0.05), rgb(200, 20, 20), Enum.Material.Neon)
	end
	local plateF = cp("Plate", Vector3.new(1.8, 0.45, 0.08), CFrame.new(0, baseY - H / 2 + 0.3, front + 0.52), rgb(240, 240, 240))
	surfaceText(plateF, Enum.NormalId.Back, string.format("А%03dВС 38", math.random(1, 999)), rgb(10, 10, 10), Enum.Font.GothamBold)
	local plateR = cp("Plate", Vector3.new(1.8, 0.45, 0.08), CFrame.new(0, baseY - H / 2 + 0.3, -front - 0.52), rgb(240, 240, 240))
	surfaceText(plateR, Enum.NormalId.Front, string.format("К%03dМО 38", math.random(1, 999)), rgb(10, 10, 10), Enum.Font.GothamBold)
	-- кузов пикапа
	if b.bed then
		local bedLen = L - b.hood - cabLen
		local bedZ = -front + bedLen / 2
		for _, x in ipairs({ -(W / 2 - 0.15), W / 2 - 0.15 }) do
			cp("BedWall", Vector3.new(0.3, 1.0, bedLen), CFrame.new(x, topY + 0.5, bedZ), color, paint)
		end
		cp("Tailgate", Vector3.new(W, 1.0, 0.3), CFrame.new(0, topY + 0.5, -front + 0.15), color, paint)
		cp("BedFloor", Vector3.new(W - 0.6, 0.1, bedLen - 0.4), CFrame.new(0, topY + 0.05, bedZ), rgb(40, 40, 40), Enum.Material.DiamondPlate)
	end
	if b.spoiler then
		cp("Spoiler", Vector3.new(W - 0.6, 0.15, 1.0), CFrame.new(0, topY + 0.9, -front + 0.6), rgb(20, 20, 20))
		for _, x in ipairs({ -2, 2 }) do
			cp("SpoilerLeg", Vector3.new(0.2, 0.8, 0.3), CFrame.new(x, topY + 0.4, -front + 0.6), rgb(20, 20, 20))
		end
	end
	if bodyName == "suv" then
		for _, x in ipairs({ -(W / 2 - 0.6), W / 2 - 0.6 }) do
			cp("RoofRail", Vector3.new(0.2, 0.25, cabLen - 2), CFrame.new(x, topY + b.cabH + 0.35, cabZ), rgb(30, 30, 30))
		end
		cp("Spare", Vector3.new(0.8, 2.4, 2.4), CFrame.new(0, baseY + 0.5, -front - 0.7) * CFrame.Angles(0, math.rad(90), 0), rgb(25, 25, 25), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	end
	-- колёса с дисками и арками
	local wr = b.wheel
	local wz = L / 2 - math.max(2.2, wr * 0.85)
	-- разные диски: 1 литьё 5 спиц, 2 штамповка, 3 многоспицевые, 4 хром «глубокая полка»
	local rimStyle = math.random(1, 4)
	local rimCols = { rgb(185, 190, 198), rgb(40, 40, 45), rgb(210, 175, 90), rgb(225, 228, 232), rgb(120, 125, 135) }
	local rimCol = (rimStyle == 2) and rgb(70, 72, 78) or rimCols[math.random(1, #rimCols)]
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local x = sx * (W / 2 - 0.35)
			local pos = Vector3.new(x, wr / 2, sz * wz)
			cp("Wheel", Vector3.new(1.1, wr, wr), CFrame.new(pos), rgb(22, 22, 22), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
			local rc = (b.chrome and rimStyle == 4) and rgb(225, 228, 232) or rimCol
			local ox = sx * 0.6
			if rimStyle == 1 or rimStyle == 3 then
				cp("Rim", Vector3.new(1.15, wr * 0.62, wr * 0.62), CFrame.new(pos), rgb(30, 30, 32), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
				cp("RimLip", Vector3.new(1.17, wr * 0.64, wr * 0.64), CFrame.new(pos + Vector3.new(sx * 0.01, 0, 0)), rc, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Transparency = 0 })
				cp("RimBack", Vector3.new(1.19, wr * 0.55, wr * 0.55), CFrame.new(pos), rgb(30, 30, 32), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
				local n = rimStyle == 1 and 5 or 10
				for k = 0, n - 1 do
					local a = math.rad(k * 360 / n)
					cp("Spoke", Vector3.new(0.1, wr * 0.26, rimStyle == 1 and wr * 0.1 or wr * 0.05), CFrame.new(pos + Vector3.new(ox, 0, 0)) * CFrame.Angles(a, 0, 0) * CFrame.new(0, wr * 0.14, 0), rc, Enum.Material.Metal)
				end
			elseif rimStyle == 2 then
				cp("Rim", Vector3.new(1.15, wr * 0.6, wr * 0.6), CFrame.new(pos), rc, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
				for k = 0, 5 do
					local a = math.rad(k * 60)
					cp("RimHole", Vector3.new(1.18, wr * 0.09, wr * 0.09), CFrame.new(pos + Vector3.new(0, math.cos(a) * wr * 0.2, math.sin(a) * wr * 0.2)), rgb(15, 15, 15), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
				end
			else
				cp("Rim", Vector3.new(1.15, wr * 0.64, wr * 0.64), CFrame.new(pos), rc, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.25 })
				cp("RimDish", Vector3.new(1.17, wr * 0.42, wr * 0.42), CFrame.new(pos), rgb(150, 155, 160), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
				for k = 0, 7 do
					local a = math.rad(k * 45)
					cp("Spoke", Vector3.new(0.08, wr * 0.2, wr * 0.04), CFrame.new(pos + Vector3.new(ox, 0, 0)) * CFrame.Angles(a, 0, 0) * CFrame.new(0, wr * 0.1, 0), rc, Enum.Material.Metal)
				end
			end
			cp("Hub", Vector3.new(1.24, wr * 0.16, wr * 0.16), CFrame.new(pos), rgb(60, 60, 65), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
			cp("Arch", Vector3.new(0.4, 0.4, wr + 0.6), CFrame.new(x + sx * 0.05, wr + 0.05, sz * wz), rgb(20, 20, 20))
		end
	end
	return m
end


---------------------------------------------------------------- СВОИ МОДЕЛИ МАШИН (ServerStorage → CarModels)
-- Перетащите модели машин из Toolbox в папку ServerStorage → CarModels.
-- При загрузке: скрипты внутри модели удаляются (защита от вирусов и чужих шасси),
-- детали закрепляются, машина масштабируется под пост и разворачивается капотом вперёд.
-- Если модель не найдена или сломана — используется встроенная блочная машина.
local ServerStorage = game:GetService("ServerStorage")
local carFolder = ServerStorage:FindFirstChild("CarModels")
if not carFolder then
	carFolder = Instance.new("Folder")
	carFolder.Name = "CarModels"
	carFolder.Parent = ServerStorage
end
-- VIP-машины: ServerStorage → VipCarModels (приезжают только к владельцам VIP-пасса)
local vipFolder = ServerStorage:FindFirstChild("VipCarModels")
if not vipFolder then
	vipFolder = Instance.new("Folder")
	vipFolder.Name = "VipCarModels"
	vipFolder.Parent = ServerStorage
end
local function folderOf(cm)
	return cm.vip and vipFolder or carFolder
end
local carTemplates = {}

local CAR_REMOVE = {
	"BaseScript", "ModuleScript", "Humanoid", "ProximityPrompt", "ClickDetector", "DragDetector",
	"BodyMover", "Constraint", "JointInstance", "WeldConstraint", "NoCollisionConstraint", "Sound",
}

local function carOpt(cm, src, key, attr)
	if cm[key] ~= nil then
		return cm[key]
	end
	return src:GetAttribute(attr)
end

local function prepareCarTemplate(src, cm)
	local m
	if src:IsA("Model") then
		m = src:Clone()
	else
		m = Instance.new("Model")
		for _, ch in ipairs(src:GetChildren()) do
			ch:Clone().Parent = m
		end
	end
	local seat = m:FindFirstChildWhichIsA("VehicleSeat", true)
	local partCount = 0
	for _, d in ipairs(m:GetDescendants()) do
		local kill = false
		for _, cls in ipairs(CAR_REMOVE) do
			if d:IsA(cls) then
				kill = true
				break
			end
		end
		if kill then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			if d:IsA("Seat") or d:IsA("VehicleSeat") then
				d.Disabled = true
			end
			partCount = partCount + 1
		end
	end
	if partCount == 0 then
		m:Destroy()
		return nil
	end
	-- коробка, выровненная по осям мира
	m.PrimaryPart = nil
	m.WorldPivot = CFrame.new(m:GetBoundingBox().Position)
	local bbCF, size = m:GetBoundingBox()
	-- где перед машины: по сиденью водителя, иначе по длинной стороне
	local fwd
	if seat and seat.Parent then
		local lv = seat.CFrame.LookVector
		fwd = Vector3.new(lv.X, 0, lv.Z)
	end
	if not fwd or fwd.Magnitude < 0.1 then
		fwd = size.X > size.Z and Vector3.new(1, 0, 0) or Vector3.new(0, 0, 1)
	end
	if math.abs(fwd.X) > math.abs(fwd.Z) then
		fwd = Vector3.new(math.sign(fwd.X), 0, 0)
	else
		fwd = Vector3.new(0, 0, math.sign(fwd.Z))
	end
	local turn = tonumber(carOpt(cm, src, "turn", "Turn")) or 0
	local yaw = math.atan2(fwd.X, fwd.Z) + math.rad(turn)
	-- масштаб под длину кузова (седан = 14 стадов)
	local len = math.abs(fwd.X) > 0.5 and size.X or size.Z
	if math.abs(turn) % 180 == 90 then
		len = math.abs(fwd.X) > 0.5 and size.Z or size.X
	end
	local base = BodyTypes[cm.body or "sedan"] or BodyTypes.sedan
	local target = tonumber(carOpt(cm, src, "length", "Length")) or base.L
	local factor = tonumber(carOpt(cm, src, "scale", "Scale")) or (target / math.max(len, 0.1))
	if math.abs(factor - 1) > 0.02 then
		local ok, err = pcall(function()
			m:ScaleTo(m:GetScale() * factor)
		end)
		if not ok then
			warn("[CarModels] не удалось изменить размер «" .. src.Name .. "»: " .. tostring(err))
		end
		bbCF, size = m:GetBoundingBox()
	end
	-- невидимый корень: подсказка «Осмотреть», табличка и точка опоры на полу
	local root = Instance.new("Part")
	root.Name = "CarRoot"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CFrame = CFrame.new(bbCF.Position) * CFrame.Angles(0, yaw, 0)
	root.Parent = m
	m.PrimaryPart = root
	root.PivotOffset = CFrame.new(0, -size.Y / 2, 0)
	m.Name = "CustomerCar"
	m:PivotTo(CFrame.new())
	return m
end

local function getCarTemplate(cm)
	if not cm.model then
		return nil
	end
	local key = (cm.vip and "vip:" or "") .. cm.model
	if carTemplates[key] == nil then
		local src = folderOf(cm):FindFirstChild(cm.model)
		local tpl = nil
		if not src then
			warn("[CarModels] в ServerStorage → " .. folderOf(cm).Name .. " нет модели «" .. cm.model .. "», будет блочная машина")
		else
			local ok, res = pcall(prepareCarTemplate, src, cm)
			if ok then
				tpl = res
			else
				warn("[CarModels] ошибка в модели «" .. cm.model .. "»: " .. tostring(res))
			end
		end
		carTemplates[key] = tpl or false
	end
	return carTemplates[key] or nil
end

-- перекраска: только детали, в имени которых есть слово из paint (например "Body")
local function paintCar(m, cm, color)
	local src = folderOf(cm):FindFirstChild(cm.model)
	local key = src and carOpt(cm, src, "paint", "Paint") or cm.paint
	if type(key) ~= "string" or key == "" then
		return
	end
	key = string.lower(key)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), key, 1, true) then
			d.Color = color
		end
	end
end

-- машины из папки, не прописанные в MechanicConfig, добавляются сами
do
	local used = {}
	for _, cm in ipairs(Config.CarModels) do
		if cm.model then
			used[cm.model] = true
		end
	end
	for _, ch in ipairs(carFolder:GetChildren()) do
		if not used[ch.Name] and (ch:IsA("Model") or ch:IsA("Folder")) then
			table.insert(Config.CarModels, {
				name = ch:GetAttribute("DisplayName") or ch.Name,
				model = ch.Name,
				body = ch:GetAttribute("Body") or "sedan",
			})
		end
	end
	if Config.OnlyCustomCars then
		local custom = {}
		for _, cm in ipairs(Config.CarModels) do
			if cm.model and carFolder:FindFirstChild(cm.model) then
				table.insert(custom, cm)
			end
		end
		if #custom > 0 then
			Config.CarModels = custom
		end
	end
	local n = 0
	for _, cm in ipairs(Config.CarModels) do
		if cm.model and getCarTemplate(cm) then
			n = n + 1
		end
	end
	print("[CarModels] загружено своих моделей машин: " .. n)

	-- VIP: модели из папки VipCarModels заменяют блочные VIP-машины из конфига
	local vipList = {}
	for _, ch in ipairs(vipFolder:GetChildren()) do
		if ch:IsA("Model") or ch:IsA("Folder") then
			local cm = { name = ch:GetAttribute("DisplayName") or ch.Name, model = ch.Name, body = ch:GetAttribute("Body") or "sedan", vip = true }
			if getCarTemplate(cm) then
				table.insert(vipList, cm)
			end
		end
	end
	if #vipList > 0 then
		Config.VipCarModels = vipList
	end
	for _, cm in ipairs(Config.VipCarModels or {}) do
		cm.vip = true
	end
	print("[CarModels] VIP-моделей из VipCarModels: " .. #vipList)
end

-- машина для клиента или улицы: своя модель, если есть, иначе блочная
local function buildCar(cm, forTraffic, color)
	color = color or Config.CarColors[math.random(1, #Config.CarColors)]
	if not (forTraffic and Config.CustomCarsInTraffic == false) then
		local tpl = getCarTemplate(cm)
		if tpl then
			local m = tpl:Clone()
			paintCar(m, cm, color)
			return m
		end
	end
	return makeCar(color, cm.body)
end


---------------------------------------------------------------- ПОСТРОЙКА БОКСА
-- Локальные координаты: улица спереди (+Z), холл с клиентами z 30..52,
-- стеклянная стена z = 30, бокс z -50..30, ворота в задней стене, сервисная дорога сзади.
local STATION_L = {
	tire_changer = Vector3.new(-55, 0, 2),
	balancer = Vector3.new(-55, 0, 16),
	engine_stand = Vector3.new(55, 0, 2),
	parts_washer = Vector3.new(55, 0, 16),
}
local TOOL_SLOTS = { "impact", "torque", "hammer", "scanner", "multimeter", "extractor", "valve_tool", "ring_compressor", "vip_impact" }

-- плита с прямоугольными вырезами (для смотровых ям): mk(sizeX, sizeZ, centerX, centerZ)
-- holes = { {x1, x2, z1, z2}, ... } — вырезы не должны перекрываться по X
local function slabHoles(mk, cx, cz, sx, sz, holes)
	table.sort(holes, function(a, b)
		return a[1] < b[1]
	end)
	local x0, x1 = cx - sx / 2, cx + sx / 2
	local z0, z1 = cz - sz / 2, cz + sz / 2
	local x = x0
	for _, h in ipairs(holes) do
		local hx1, hx2 = math.max(h[1], x), math.min(h[2], x1)
		if hx2 > hx1 then
			if hx1 - x > 0.01 then
				mk(hx1 - x, z1 - z0, (x + hx1) / 2, cz)
			end
			local hz1, hz2 = math.max(h[3], z0), math.min(h[4], z1)
			if hz1 - z0 > 0.01 then
				mk(hx2 - hx1, hz1 - z0, (hx1 + hx2) / 2, (z0 + hz1) / 2)
			end
			if z1 - hz2 > 0.01 then
				mk(hx2 - hx1, z1 - hz2, (hx1 + hx2) / 2, (hz2 + z1) / 2)
			end
			x = hx2
		end
	end
	if x1 - x > 0.01 then
		mk(x1 - x, z1 - z0, (x + x1) / 2, cz)
	end
end

local function setShopName(plot, name)
	plot.shopName = name
	for _, f in ipairs(plot.nameHooks) do
		pcall(f)
	end
end

local function buildPlot(k)
	local O = Vector3.new((k - (Config.MaxPlots + 1) / 2) * PLOT_SPACING, 0, 0)
	local folder = Instance.new("Folder")
	folder.Name = "Plot" .. k
	folder.Parent = world
	local plot = { index = k, origin = O, owner = nil, bays = {}, stations = {}, stationParts = {}, seats = {}, nameHooks = {}, folder = folder, shopName = nil }
	local function P(props)
		props.Parent = props.Parent or folder
		if props.Position then
			props.Position = O + props.Position
		end
		if props.CFrame then
			props.CFrame = CFrame.new(O) * props.CFrame
		end
		return part(props)
	end
	local V = Vector3.new
	local brick = rgb(150, 85, 65)
	local plaster = rgb(225, 220, 210)

	-- полы
	do
		local holes = {}
		local pbx = BAY_LX[Config.PitBay or 1]
		if pbx then
			table.insert(holes, { pbx - PIT_W / 2, pbx + PIT_W / 2, PIT_Z1, PIT_Z2 })
		end
		slabHoles(function(sx, sz, cx, cz)
			P({ Name = "ShopFloor", Size = V(sx, 1, sz), Position = V(cx, -0.45, cz), Color = rgb(120, 122, 126), Material = Enum.Material.Concrete })
		end, 0, -10, 130, 80, holes)
	end
	P({ Name = "LobbyFloor", Size = V(130, 1, 22), Position = V(0, -0.4, 41), Color = rgb(230, 225, 215), Material = Enum.Material.Marble })
	P({ Name = "Apron", Size = V(130, 1, 12), Position = V(0, -0.5, -56), Color = rgb(90, 90, 95), Material = Enum.Material.Concrete })
	-- стены
	local function wallX(x1, x2, z, h, col, mat)
		if x2 - x1 > 0.1 then
			P({ Name = "Wall", Size = V(x2 - x1, h or 20, 2), Position = V((x1 + x2) / 2, (h or 20) / 2, z), Color = col or brick, Material = mat or Enum.Material.Brick })
		end
	end
	P({ Name = "Wall", Size = V(2, 20, 104), Position = V(-65, 10, 1), Color = brick, Material = Enum.Material.Brick })
	P({ Name = "Wall", Size = V(2, 20, 104), Position = V(65, 10, 1), Color = brick, Material = Enum.Material.Brick })
	P({ Name = "InnerPaint", Size = V(0.2, 8, 80), Position = V(-63.9, 4, -10), Color = rgb(60, 90, 140), Material = Enum.Material.SmoothPlastic })
	P({ Name = "InnerPaint", Size = V(0.2, 8, 80), Position = V(63.9, 4, -10), Color = rgb(60, 90, 140), Material = Enum.Material.SmoothPlastic })
	-- задняя стена с воротами
	local x = -65
	for _, bx in ipairs(BAY_LX) do
		wallX(x, bx - 8, -50)
		P({ Name = "Lintel", Size = V(16, 6, 2), Position = V(bx, 17, -50), Color = brick, Material = Enum.Material.Brick })
		P({ Name = "Shutter", Size = V(16, 1.5, 2.4), Position = V(bx, 13.6, -50), Color = rgb(160, 165, 170), Material = Enum.Material.CorrodedMetal })
		for i = 0, 7 do
			P({ Name = "Hazard", Size = V(0.4, 14, 0.4), Position = V(bx + (i < 4 and -8.2 or 8.2), 7, -49 + (i % 4) * 0.01), Color = (i % 2 == 0) and rgb(240, 200, 30) or rgb(20, 20, 20), CanCollide = false })
		end
		x = bx + 8
	end
	wallX(x, 65, -50)
	-- фасад с входом и витринами
	wallX(-65, -52, 52, 20, plaster, Enum.Material.Plaster)
	wallX(-28, -6, 52, 20, plaster, Enum.Material.Plaster)
	wallX(6, 28, 52, 20, plaster, Enum.Material.Plaster)
	wallX(52, 65, 52, 20, plaster, Enum.Material.Plaster)
	for _, wx in ipairs({ -40, 40 }) do
		P({ Name = "WinLow", Size = V(24, 3, 2), Position = V(wx, 1.5, 52), Color = plaster, Material = Enum.Material.Plaster })
		P({ Name = "WinHigh", Size = V(24, 7, 2), Position = V(wx, 16.5, 52), Color = plaster, Material = Enum.Material.Plaster })
		P({ Name = "Window", Size = V(24, 10, 0.4), Position = V(wx, 8, 52), Color = rgb(160, 200, 230), Material = Enum.Material.Glass, Transparency = 0.6, Reflectance = 0.15 })
	end
	P({ Name = "DoorTop", Size = V(12, 9, 2), Position = V(0, 15.5, 52), Color = plaster, Material = Enum.Material.Plaster })
	P({ Name = "Canopy", Size = V(18, 0.6, 6), Position = V(0, 11.2, 55), Color = rgb(30, 30, 35), Material = Enum.Material.Metal })
	P({ Name = "Step", Size = V(14, 0.4, 4), Position = V(0, 0.2, 54), Color = rgb(160, 160, 160), Material = Enum.Material.Concrete })
	-- крыша и светильники
	P({ Name = "Roof", Size = V(132, 1.5, 106), Position = V(0, 20.7, 1), Color = rgb(70, 70, 75), Material = Enum.Material.Metal })
	P({ Name = "Cornice", Size = V(134, 1.2, 1.5), Position = V(0, 21.2, 53.5), Color = rgb(40, 40, 45), Material = Enum.Material.Metal })
	for _, lx in ipairs({ -45, -15, 15, 45 }) do
		for _, lz in ipairs({ -35, -12, 12 }) do
			local lamp = P({ Name = "Lamp", Size = V(10, 0.3, 1.2), Position = V(lx, 19.7, lz), Color = rgb(255, 250, 235), Material = Enum.Material.Neon, CanCollide = false })
			pointLight(lamp, rgb(255, 245, 225), 30, 1.6, true)
		end
		local ll = P({ Name = "LobbyLamp", Size = V(3, 0.3, 3), Position = V(lx, 19.7, 41), Color = rgb(255, 230, 190), Material = Enum.Material.Neon, CanCollide = false })
		pointLight(ll, rgb(255, 220, 170), 24, 1.2, true)
	end

	-- стеклянная стена между холлом и боксом (с дверным проёмом)
	for _, seg in ipairs({ { -64, -5 }, { 5, 64 } }) do
		local cx = (seg[1] + seg[2]) / 2
		local w = seg[2] - seg[1]
		P({ Name = "GlassWall", Size = V(w, 14, 0.4), Position = V(cx, 8, 30), Color = rgb(190, 225, 240), Material = Enum.Material.Glass, Transparency = 0.7, Reflectance = 0.1 })
		P({ Name = "GlassBase", Size = V(w, 1, 0.8), Position = V(cx, 0.5, 30), Color = rgb(50, 50, 55), Material = Enum.Material.Metal })
		P({ Name = "GlassTop", Size = V(w, 5, 0.8), Position = V(cx, 17.5, 30), Color = rgb(225, 220, 210), Material = Enum.Material.Plaster })
		for fx = seg[1], seg[2], 10 do
			P({ Name = "Frame", Size = V(0.4, 14, 0.6), Position = V(fx, 8, 30), Color = rgb(50, 50, 55), Material = Enum.Material.Metal })
		end
	end
	P({ Name = "DoorLintel", Size = V(10, 5, 0.8), Position = V(0, 17.5, 30), Color = rgb(225, 220, 210), Material = Enum.Material.Plaster })
	local staffSign = P({ Name = "StaffSign", Size = V(6, 1.2, 0.2), Position = V(0, 13.6, 30.5), Color = rgb(30, 30, 35) })
	surfaceText(staffSign, Enum.NormalId.Back, "🔧 РЕМОНТНАЯ ЗОНА", rgb(255, 210, 60))

	-- стойка администратора с компьютером
	local deskPos = V(-36, 0, 38)
	P({ Name = "Desk", Size = V(16, 3.6, 3), Position = deskPos + V(0, 1.8, 0), Color = rgb(90, 60, 40), Material = Enum.Material.Wood })
	P({ Name = "DeskTop", Size = V(16.4, 0.3, 3.4), Position = deskPos + V(0, 3.75, 0), Color = rgb(240, 240, 240), Material = Enum.Material.Marble })
	local deskFront = P({ Name = "DeskFront", Size = V(12, 2, 0.2), Position = deskPos + V(0, 2, 1.55), Color = rgb(25, 50, 110) })
	local deskText = surfaceText(deskFront, Enum.NormalId.Back, "", rgb(255, 220, 90))
	local monitor = P({ Name = "Computer", Size = V(3, 2.2, 0.3), Position = deskPos + V(-3, 5.2, -0.5), Color = rgb(20, 20, 25) })
	P({ Name = "Screen", Size = V(2.7, 1.9, 0.05), Position = deskPos + V(-3, 5.2, -0.33), Color = rgb(60, 160, 255), Material = Enum.Material.Neon, CanCollide = false })
	P({ Name = "MonStand", Size = V(0.4, 1, 0.4), Position = deskPos + V(-3, 4.3, -0.5), Color = rgb(20, 20, 25) })
	P({ Name = "Keyboard", Size = V(2.2, 0.15, 0.8), Position = deskPos + V(-3, 3.95, 0.6), Color = rgb(30, 30, 35) })
	P({ Name = "Bell", Shape = Enum.PartType.Ball, Size = V(0.6, 0.6, 0.6), Position = deskPos + V(4, 4.1, 0.8), Color = rgb(220, 180, 60), Material = Enum.Material.Metal })
	P({ Name = "Printer", Size = V(1.8, 1, 1.4), Position = deskPos + V(3, 4.4, -0.6), Color = rgb(230, 230, 230) })
	label3d(monitor, "🖥 КОМПЬЮТЕР", 2.2, Color3.fromRGB(150, 220, 255), 200, 40)
	prompt(monitor, "Открыть", "Компьютер", function(p)
		if plot.owner ~= p then
			notify(p, "Это чужая мастерская. Ваш бокс отмечен стрелкой.", "bad")
			return
		end
		OpenUIEvent:FireClient(p, "computer")
	end)
	plot.computerPos = O + deskPos
	-- вывеска на стене за стойкой
	local lobbySign = P({ Name = "LobbySign", Size = V(22, 3, 0.4), Position = V(-36, 13, 30.6), Color = rgb(20, 40, 90) })
	local lobbyText = surfaceText(lobbySign, Enum.NormalId.Back, "", rgb(255, 220, 90))

	-- зона ожидания
	for i = 0, 7 do
		local sx = 12 + i * 6
		local seatPos = V(sx, 0, 47.5)
		P({ Name = "Chair", Size = V(4, 1.6, 3.4), Position = seatPos + V(0, 0.8, 0), Color = rgb(40, 60, 100), Material = Enum.Material.Fabric })
		P({ Name = "ChairBack", Size = V(4, 3.4, 0.6), Position = seatPos + V(0, 3.2, 1.6), Color = rgb(40, 60, 100), Material = Enum.Material.Fabric })
		P({ Name = "ChairArm", Size = V(0.4, 1, 3.4), Position = seatPos + V(-2.1, 2, 0), Color = rgb(30, 30, 35), Material = Enum.Material.Metal })
		table.insert(plot.seats, { pos = O + seatPos + V(0, 0, -0.3), used = false })
	end
	P({ Name = "CoffeeTable", Size = V(10, 1.6, 4), Position = V(31, 0.8, 41), Color = rgb(110, 75, 50), Material = Enum.Material.Wood })
	for i = 0, 2 do
		P({ Name = "Magazine", Size = V(1.4, 0.08, 1.8), Position = V(28 + i * 2.2, 1.65, 41), Color = ClientShirts[i + 1], CanCollide = false })
	end
	P({ Name = "Cooler", Size = V(2, 4, 2), Position = V(60, 2, 46), Color = rgb(240, 240, 240) })
	P({ Name = "Bottle", Shape = Enum.PartType.Cylinder, Size = V(2, 1.6, 1.6), CFrame = CFrame.new(60, 5, 46) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(120, 180, 240), Material = Enum.Material.Glass, Transparency = 0.3 })
	for _, px in ipairs({ -60, 8 }) do
		P({ Name = "Pot", Shape = Enum.PartType.Cylinder, Size = V(2.4, 2.4, 2.4), CFrame = CFrame.new(px, 1.2, 48) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(150, 90, 60), Material = Enum.Material.Slate })
		P({ Name = "Plant", Shape = Enum.PartType.Ball, Size = V(4, 4, 4), Position = V(px, 4.2, 48), Color = rgb(50, 130, 60), Material = Enum.Material.Grass })
	end
	local tv = P({ Name = "TV", Size = V(9, 5, 0.3), Position = V(36, 11, 30.5), Color = rgb(15, 15, 18) })
	local tvText = surfaceText(tv, Enum.NormalId.Back, "", rgb(255, 255, 255), Enum.Font.GothamBold, rgb(20, 40, 80))
	table.insert(plot.nameHooks, function()
		tvText.Text = "📺 Добро пожаловать в\n«" .. (plot.shopName or Config.DefaultShopName) .. "»\nРемонт быстро и честно!"
	end)

	-- вывеска на фасаде и стела у дороги
	local facade = P({ Name = "FacadeSign", Size = V(46, 6, 1), Position = V(0, 25, 53.5), Color = rgb(20, 40, 90) })
	local facadeText = surfaceText(facade, Enum.NormalId.Back, "", rgb(255, 220, 90))
	local facadeGlow = P({ Name = "SignGlow", Size = V(46.4, 0.4, 1.2), Position = V(0, 21.9, 53.6), Color = rgb(255, 200, 60), Material = Enum.Material.Neon, CanCollide = false })
	local glowLight = pointLight(facadeGlow, rgb(255, 210, 120), 26, 2)
	P({ Name = "PylonPole", Size = V(1.2, 16, 1.2), Position = V(52, 8, 62), Color = rgb(50, 50, 55), Material = Enum.Material.Metal })
	local pylon = P({ Name = "Pylon", Size = V(12, 7, 1.2), Position = V(52, 18, 62), Color = rgb(20, 40, 90) })
	local pylonF = surfaceText(pylon, Enum.NormalId.Front, "", rgb(255, 220, 90))
	local pylonB = surfaceText(pylon, Enum.NormalId.Back, "", rgb(255, 220, 90))
	local boards = {}
	for _, wx in ipairs({ -40, 40 }) do
		for i = 0, 1 do
			local bd = P({ Name = "Board", Size = V(26, 1.2, 0.4), CFrame = CFrame.new(wx, 6 + i * 4, 52.6) * CFrame.Angles(0, 0, math.rad(i == 0 and 12 or -10)), Color = rgb(130, 95, 60), Material = Enum.Material.WoodPlanks, CanCollide = false })
			table.insert(boards, bd)
		end
	end
	local forSale = P({ Name = "ForSale", Size = V(10, 4, 0.3), Position = V(-16, 9, 53.4), Color = rgb(200, 30, 30) })
	surfaceText(forSale, Enum.NormalId.Back, "ПРОДАЁТСЯ", rgb(255, 255, 255))
	local ownerTag = P({ Name = "OwnerTag", Size = V(1, 1, 1), Position = V(0, 31, 53), Transparency = 1, CanCollide = false })
	local ownerLabel = label3d(ownerTag, "", 0, rgb(180, 255, 180), 360, 64)
	plot.ownerLabel = ownerLabel
	table.insert(plot.nameHooks, function()
		local named = plot.shopName ~= nil
		local title = plot.shopName or Config.DefaultShopName
		local txt = "🔧 " .. string.upper(title)
		facadeText.Text = txt
		facadeText.TextColor3 = named and rgb(255, 220, 90) or rgb(150, 150, 150)
		facadeGlow.Color = named and rgb(255, 200, 60) or rgb(90, 90, 90)
		facadeGlow.Material = named and Enum.Material.Neon or Enum.Material.SmoothPlastic
		glowLight.Enabled = named
		pylonF.Text = txt .. "\nАВТОСЕРВИС"
		pylonB.Text = pylonF.Text
		lobbyText.Text = txt
		deskText.Text = "РЕСЕПШН · " .. title
		for _, bd in ipairs(boards) do
			bd.Transparency = named and 1 or 0
		end
		forSale.Transparency = plot.owner and 1 or 0
		for _, d in ipairs(forSale:GetDescendants()) do
			if d:IsA("SurfaceGui") then
				d.Enabled = plot.owner == nil
			end
		end
		local o = plot.owner
		if o then
			local _, rk = rankOf(repairsOf(o))
			local rt = o:GetAttribute("Rating") or 0
			local vip = o:GetAttribute("Pass_vip") == true
			ownerLabel.Text = (vip and "⭐ VIP · " or "") .. "Владелец: " .. o.DisplayName .. "\n🏅 " .. rk.name .. " · " .. (rt > 0 and string.format("★%.1f", rt) or "нет отзывов")
			ownerLabel.TextColor3 = vip and rgb(255, 215, 90) or rgb(180, 255, 180)
		else
			ownerLabel.Text = "Свободный бокс"
			ownerLabel.TextColor3 = rgb(180, 255, 180)
		end
	end)

	-- таблица лидеров у дороги (зеркально стеле)
	P({ Name = "LeaderPole", Size = V(1.2, 9, 1.2), Position = V(-52, 4.5, 62), Color = rgb(50, 50, 55), Material = Enum.Material.Metal })
	local lboard = P({ Name = "LeaderBoard", Size = V(14, 12, 0.8), Position = V(-52, 15, 62), Color = rgb(25, 25, 32) })
	plot.leaderLabels = {
		surfaceText(lboard, Enum.NormalId.Front, "🏆 ТОП МЕХАНИКОВ", rgb(255, 215, 90), Enum.Font.GothamBold),
		surfaceText(lboard, Enum.NormalId.Back, "🏆 ТОП МЕХАНИКОВ", rgb(255, 215, 90), Enum.Font.GothamBold),
	}
	for _, l in ipairs(plot.leaderLabels) do
		l.TextXAlignment = Enum.TextXAlignment.Left
	end


	-- посты (подъёмники ставятся при покупке)
	for i, bx in ipairs(BAY_LX) do
		local lp = V(bx, 0, BAY_LZ)
		local isPit = (i == (Config.PitBay or 1))
		if isPit then
			-- полноценная смотровая яма: игрок спускается по ступеням и стоит в полный рост
			local cz = (PIT_Z1 + PIT_Z2) / 2
			local len = PIT_Z2 - PIT_Z1
			local wc = rgb(150, 150, 152)
			P({ Name = "PitFloor", Size = V(PIT_W + 2, 1, len + 2), Position = V(bx, -PIT_D - 0.5, cz), Color = rgb(95, 95, 98), Material = Enum.Material.Concrete })
			for _, sx in ipairs({ -1, 1 }) do
				P({ Name = "PitWall", Size = V(1, PIT_D, len + 2), Position = V(bx + sx * (PIT_W / 2 + 0.5), -PIT_D / 2, cz), Color = wc, Material = Enum.Material.Concrete })
				P({ Name = "PitEdge", Size = V(0.5, 0.12, len), Position = V(bx + sx * (PIT_W / 2 + 0.25), 0.1, cz), Color = rgb(240, 200, 30), CanCollide = false })
				local pl = P({ Name = "PitLamp", Size = V(0.3, 0.6, 3), Position = V(bx + sx * (PIT_W / 2 - 0.15), -2.2, cz - 4), Color = rgb(255, 250, 235), Material = Enum.Material.Neon, CanCollide = false })
				pointLight(pl, rgb(255, 245, 225), 14, 1.4)
			end
			for _, ez in ipairs({ PIT_Z1 - 0.5, PIT_Z2 + 0.5 }) do
				P({ Name = "PitWall", Size = V(PIT_W, PIT_D, 1), Position = V(bx, -PIT_D / 2, ez), Color = wc, Material = Enum.Material.Concrete })
			end
			P({ Name = "PitEdge", Size = V(PIT_W + 1, 0.12, 0.5), Position = V(bx, 0.1, PIT_Z1 - 0.25), Color = rgb(240, 200, 30), CanCollide = false })
			-- ступени со стороны ворот в лобби
			for st = 1, PIT_D - 1 do
				local top = -st
				local hgt = PIT_D - st
				P({ Name = "PitStep", Size = V(PIT_W, hgt, 1.2), Position = V(bx, -PIT_D + hgt / 2, PIT_Z2 - (st - 0.5) * 1.2), Color = rgb(130, 130, 134), Material = Enum.Material.DiamondPlate })
				local _ = top
			end
		else
			P({ Name = "BayMark", Size = V(15, 0.06, 24), Position = lp + V(0, 0.03, 0), Color = rgb(70, 72, 76), Material = Enum.Material.Concrete, CanCollide = false })
		end
		for _, sx in ipairs({ -7.5, 7.5 }) do
			P({ Name = "BayLine", Size = V(0.4, 0.08, 24), Position = lp + V(sx, 0.06, 0), Color = rgb(240, 200, 30), CanCollide = false })
		end
		if not isPit then
			P({ Name = "Drain", Size = V(3, 0.08, 1), Position = lp + V(0, 0.07, 0), Color = rgb(30, 30, 30), Material = Enum.Material.DiamondPlate, CanCollide = false })
		end
		local bonus = i > (Config.BaseBays or 3)
		local tagText = isPit and ("ПОСТ " .. i .. " · ЯМА") or (bonus and ("⭐ ПОСТ " .. i) or ("ПОСТ " .. i))
		local tag = P({ Name = "BayLabel", Size = V((isPit or bonus) and 8 or 4, 1.6, 0.3), Position = lp + V(0, 16, -33.6), Color = bonus and rgb(255, 215, 90) or rgb(240, 200, 30) })
		surfaceText(tag, Enum.NormalId.Back, tagText, rgb(20, 20, 20))
		local bay = { index = #Bays + 1, localIdx = i, plot = plot, pos = O + lp, job = nil, bonus = bonus or nil }
		Bays[bay.index] = bay
		plot.bays[i] = bay
	end

	-- парковка клиентов (за мастерской, на служебной дороге)
	plot.parking = {}
	for i, sx in ipairs(PARK_LX) do
		if i > (Config.ParkingSpots or 4) then
			break
		end
		local lp = V(sx, 0, PARK_LZ)
		for _, dx in ipairs({ -5, 5 }) do
			P({ Name = "ParkLine", Size = V(0.4, 0.06, 13), Position = lp + V(dx, -0.07, 0), Color = rgb(240, 240, 240), CanCollide = false })
		end
		local num = P({ Name = "ParkNum", Size = V(4, 0.06, 4), Position = lp + V(0, -0.07, -8.5), Transparency = 1, CanCollide = false })
		surfaceText(num, Enum.NormalId.Top, "P" .. i, rgb(240, 240, 240))
		table.insert(plot.parking, { index = i, pos = O + lp, job = nil })
	end
	local psign = P({ Name = "ParkingSign", Size = V(14, 3, 0.3), Position = V(0, 11, -51.3), Color = rgb(30, 70, 160) })
	surfaceText(psign, Enum.NormalId.Front, "🅿 ПАРКОВКА КЛИЕНТОВ", rgb(255, 255, 255))

	-- станции (точки взаимодействия существуют всегда, модель — после покупки)
	for id, lp in pairs(STATION_L) do
		local hit = P({ Name = id .. "_Hit", Size = V(6, 5, 6), Position = lp + V(0, 2.5, 0), Transparency = 1, CanCollide = false })
		plot.stations[id] = O + lp
		plot.stationParts[id] = hit
		label3d(hit, Config.Stations[id], 4.5, rgb(255, 230, 150), 200, 36)
		prompt(hit, "Продолжить ремонт", Config.Stations[id], function(p)
			if plot.owner ~= p then
				notify(p, "Это не ваш бокс", "bad")
				return
			end
			openActive(p)
		end)
	end
	-- верстаки, стеллажи, инструментальная стена
	local function shelf(cx, cz, name)
		P({ Name = name, Size = V(3, 0.3, 16), Position = V(cx, 1, cz), Color = rgb(60, 70, 90), Material = Enum.Material.Metal })
		P({ Name = name, Size = V(3, 0.3, 16), Position = V(cx, 4, cz), Color = rgb(60, 70, 90), Material = Enum.Material.Metal })
		P({ Name = name, Size = V(3, 0.3, 16), Position = V(cx, 7, cz), Color = rgb(60, 70, 90), Material = Enum.Material.Metal })
		for _, dz in ipairs({ -7.8, 7.8 }) do
			P({ Name = name .. "Post", Size = V(3, 8, 0.3), Position = V(cx, 4, cz + dz), Color = rgb(230, 120, 30), Material = Enum.Material.Metal })
		end
	end
	shelf(-62.5, -38, "PartsShelf")
	shelf(62.5, -38, "FluidShelf")
	local ps = P({ Name = "PSLabel", Size = V(0.2, 1.2, 8), Position = V(-63.8, 9, -38), Color = rgb(20, 20, 25) })
	surfaceText(ps, Enum.NormalId.Right, "ЗАПЧАСТИ", rgb(255, 210, 60))
	local fs = P({ Name = "FSLabel", Size = V(0.2, 1.2, 8), Position = V(63.8, 9, -38), Color = rgb(20, 20, 25) })
	surfaceText(fs, Enum.NormalId.Left, "ЖИДКОСТИ И ХИМИЯ", rgb(255, 210, 60))
	P({ Name = "Pegboard", Size = V(0.3, 7, 18), Position = V(-63.7, 7, -14), Color = rgb(200, 170, 120), Material = Enum.Material.Wood })
	P({ Name = "Workbench", Size = V(4, 3.4, 18), Position = V(-61.5, 1.7, -14), Color = rgb(150, 40, 40), Material = Enum.Material.Metal })
	P({ Name = "BenchTop", Size = V(4.2, 0.3, 18.2), Position = V(-61.5, 3.55, -14), Color = rgb(120, 90, 60), Material = Enum.Material.Wood })
	P({ Name = "Vise", Size = V(1.2, 1, 1.6), Position = V(-61, 4.2, -20), Color = rgb(40, 70, 140), Material = Enum.Material.Metal })
	P({ Name = "Compressor", Shape = Enum.PartType.Cylinder, Size = V(5, 2.6, 2.6), CFrame = CFrame.new(61.5, 1.6, -22), Color = rgb(200, 40, 40), Material = Enum.Material.Metal })
	P({ Name = "OilDrum", Shape = Enum.PartType.Cylinder, Size = V(4, 2.6, 2.6), CFrame = CFrame.new(60, 2, -28) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(30, 70, 150), Material = Enum.Material.Metal })
	P({ Name = "OilStain", Size = V(6, 0.05, 4), Position = V(-8, 0.06, 5), Color = rgb(35, 35, 35), Transparency = 0.4, CanCollide = false })
	P({ Name = "TireStack", Shape = Enum.PartType.Cylinder, Size = V(5, 3, 3), CFrame = CFrame.new(-58, 2.5, 25) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(25, 25, 25), Material = Enum.Material.Fabric })

	plot.equipFolder = Instance.new("Folder")
	plot.equipFolder.Name = "Equipment"
	plot.equipFolder.Parent = folder
	plot.L = function(lx, ly, lz)
		return O + V(lx, ly, lz)
	end
	Plots[k] = plot
	for _, f in ipairs(plot.nameHooks) do
		pcall(f)
	end
	return plot
end

-- перестроить купленное оборудование, инструменты и полки
local function refreshEquipment(plot)
	if not plot.equipFolder then
		return
	end
	plot.equipFolder:ClearAllChildren()
	local p = plot.owner
	local ef = plot.equipFolder
	local function ghost(pos, size, text)
		local g = part({ Name = "Ghost", Size = size, Position = pos + Vector3.new(0, size.Y / 2, 0), Color = rgb(120, 200, 255), Material = Enum.Material.ForceField, Transparency = 0.3, CanCollide = false, Parent = ef })
		label3d(g, text, size.Y / 2 + 1, rgb(160, 210, 255), 200, 34)
	end
	local function safePlace(id, cf, scale)
		pcall(function()
			PartModels.place(id, cf, scale or 1, ef)
		end)
	end
	local lift = p and owns(p, "lift")
	for _, bay in ipairs(plot.bays) do
		if bay.bonus then
			-- пост из доната «+1 подъёмник» всегда со своим подъёмником
			if p and p:GetAttribute("Pass_extra_lift") then
				safePlace("lift", CFrame.new(bay.pos), 1)
			elseif p then
				ghost(bay.pos + Vector3.new(0, 0, 9), Vector3.new(14, 0.3, 1), "⭐ Пост " .. bay.localIdx .. " + подъёмник: Донат")
			end
		elseif lift then
			safePlace("lift", CFrame.new(bay.pos), 1)
		elseif p then
			ghost(bay.pos + Vector3.new(0, 0, 9), Vector3.new(14, 0.3, 1), "Подъёмник: $" .. Config.ItemById.lift.price)
		end
	end
	for id, pos in pairs(plot.stations) do
		if p and owns(p, id) then
			safePlace(id, CFrame.new(pos) * CFrame.Angles(0, math.rad(pos.X > plot.origin.X and -90 or 90), 0), 1)
		else
			ghost(pos, Vector3.new(5, 4, 5), "Не куплено: $" .. Config.ItemById[id].price)
		end
	end
	local hoistPos = plot.L(58, 0, -40)
	if p and owns(p, "hoist") then
		safePlace("hoist", CFrame.new(hoistPos), 1)
	else
		ghost(hoistPos, Vector3.new(4, 8, 4), "Кран: $" .. Config.ItemById.hoist.price)
	end
	if not p then
		return
	end
	-- домкрат и подставки на полу
	if owns(p, "jack") then
		safePlace("jack", CFrame.new(plot.L(-50, 0, 24)) * CFrame.Angles(0, math.rad(90), 0), 1.6)
	end
	if owns(p, "stands") then
		safePlace("stands", CFrame.new(plot.L(-45, 0, 24)), 1.6)
	end
	-- инструменты на стене
	for i, id in ipairs(TOOL_SLOTS) do
		if owns(p, id) then
			local z = -21.5 + (i - 1) * 2.1
			safePlace(id, CFrame.new(plot.L(-61.5, 3.7, z)) * CFrame.Angles(0, math.rad(90), 0), 1.4)
		end
	end
	-- запчасти и жидкости на полках (по тому, что лежит на складе)
	local slotsL, slotsR = 0, 0
	for _, it in ipairs(Config.Items) do
		local n = invGet(p, it.id)
		if n > 0 and (it.cat == "part" or it.cat == "fluid") and it.id ~= "engine_new" then
			local left = it.cat == "part"
			local s = left and slotsL or slotsR
			if s < 18 then
				local row = math.floor(s / 6)
				local col = s % 6
				local lx = left and -62.5 or 62.5
				local pos = plot.L(lx, 1.15 + row * 3, -44.5 + col * 2.6)
				safePlace(it.id, CFrame.new(pos), 1.3)
				if left then
					slotsL = slotsL + 1
				else
					slotsR = slotsR + 1
				end
			end
		end
	end
	if invGet(p, "engine_new") > 0 then
		safePlace("engine_new", CFrame.new(plot.L(45, 0, 22)), 1)
	end
end


---------------------------------------------------------------- ГОРОД ВОКРУГ
local function buildCity()
	local V = Vector3.new
	local half = (Config.MaxPlots * PLOT_SPACING) / 2 + 60
	local W = half * 2
	do
		local holes = {}
		local pbx = BAY_LX[Config.PitBay or 1]
		if pbx then
			for k = 1, Config.MaxPlots do
				local ox = (k - (Config.MaxPlots + 1) / 2) * PLOT_SPACING
				table.insert(holes, { ox + pbx - PIT_W / 2, ox + pbx + PIT_W / 2, PIT_Z1, PIT_Z2 })
			end
		end
		slabHoles(function(sx, sz, cx, cz)
			part({ Name = "Ground", Size = V(sx, 1, sz), Position = V(cx, -1, cz), Color = rgb(85, 135, 70), Material = Enum.Material.Grass })
		end, 0, 0, W + 200, 520, holes)
	end
	-- главная улица
	part({ Name = "Street", Size = V(W, 1, 35), Position = V(0, -0.6, 77.5), Color = rgb(45, 45, 48), Material = Enum.Material.Asphalt })
	for x = -half, half, 14 do
		part({ Name = "Dash", Size = V(7, 0.05, 0.6), Position = V(x, -0.08, 77.5), Color = rgb(240, 240, 240), CanCollide = false })
	end
	for _, z in ipairs({ 56.5, 98.5 }) do
		part({ Name = "Sidewalk", Size = V(W, 1, 7), Position = V(0, -0.4, z), Color = rgb(175, 175, 170), Material = Enum.Material.Pavement })
		part({ Name = "Curb", Size = V(W, 1.1, 0.5), Position = V(0, -0.35, z + (z < 70 and 3.5 or -3.5)), Color = rgb(210, 210, 205), Material = Enum.Material.Concrete })
	end
	-- служебная дорога сзади (по ней приезжают клиенты)
	part({ Name = "ServiceRoad", Size = V(W, 1, 50), Position = V(0, -0.6, -87), Color = rgb(55, 55, 58), Material = Enum.Material.Asphalt })
	-- фонари
	for x = -half, half, 40 do
		for _, z in ipairs({ 59, 96 }) do
			part({ Name = "LampPole", Size = V(0.6, 14, 0.6), Position = V(x, 7, z), Color = rgb(40, 40, 45), Material = Enum.Material.Metal })
			local arm = part({ Name = "LampHead", Size = V(1.4, 0.5, 3), Position = V(x, 14, z + (z < 70 and 1.5 or -1.5)), Color = rgb(255, 240, 200), Material = Enum.Material.Neon, CanCollide = false })
			local sl = pointLight(arm, rgb(255, 225, 170), 32, 1.6, true)
			table.insert(NightLights, { light = sl, part = arm })
		end
	end
	-- деревья и заборы между боксами
	local function tree(pos, s)
		part({ Name = "Trunk", Size = V(1.4 * s, 7 * s, 1.4 * s), Position = pos + V(0, 3.5 * s, 0), Color = rgb(100, 70, 45), Material = Enum.Material.Wood })
		part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = V(8, 8, 8) * s, Position = pos + V(0, 9 * s, 0), Color = rgb(55 + math.random(0, 30), 120 + math.random(0, 40), 55), Material = Enum.Material.Grass })
		part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = V(6, 6, 6) * s, Position = pos + V(2 * s, 11 * s, 1 * s), Color = rgb(60, 140, 60), Material = Enum.Material.Grass })
	end
	for k = 0, Config.MaxPlots do
		local gx = (k - Config.MaxPlots / 2) * PLOT_SPACING
		for _, z in ipairs({ -30, 0, 30 }) do
			tree(V(gx + math.random(-8, 8), 0, z), 0.8 + math.random() * 0.5)
		end
		part({ Name = "Fence", Size = V(0.4, 5, 110), Position = V(gx, 2.5, -5), Color = rgb(140, 110, 80), Material = Enum.Material.WoodPlanks })
		part({ Name = "Bush", Shape = Enum.PartType.Ball, Size = V(5, 4, 5), Position = V(gx + 10, 1.5, 49), Color = rgb(50, 120, 50), Material = Enum.Material.Grass })
	end
	-- дома на другой стороне улицы (v4: 5 разных типов зданий, без АЗС, есть банк)
	local shops = { "ПРОДУКТЫ", "АПТЕКА", "КАФЕ", "ПЕКАРНЯ", "КНИГИ", "ЦВЕТЫ", "ОДЕЖДА", "ПОЧТА", "СТОЛОВАЯ", "ЭЛЕКТРОНИКА" }
	local facadeCols = { rgb(200, 170, 140), rgb(160, 90, 70), rgb(220, 210, 180), rgb(120, 140, 160), rgb(190, 120, 90), rgb(230, 230, 230) }
	local shopIdx = 0
	local function nextShop()
		shopIdx = shopIdx + 1
		return shops[(shopIdx - 1) % #shops + 1]
	end
	local function windows(x1, x2, y1, y2, stepX, stepY, ww, wh)
		for fy = y1, y2, stepY do
			for fx = x1, x2, stepX do
				local win = part({ Name = "Win", Size = V(ww, wh, 0.2), Position = V(fx, fy, 103.9), Color = rgb(70, 95, 120), Material = Enum.Material.Glass, Transparency = 0.1, CanCollide = false })
				if math.random() < 0.45 then
					table.insert(NightWindows, win)
				end
			end
		end
	end
	local function shopSign(cx, w, text, col, y)
		local sign = part({ Name = "ShopSign", Size = V(math.min(w - 6, 20), 2.4, 0.4), Position = V(cx, y or 5.5, 103.7), Color = col })
		surfaceText(sign, Enum.NormalId.Front, text, rgb(30, 30, 30))
	end
	local function door(cx, col)
		part({ Name = "Door", Size = V(4, 7, 0.3), Position = V(cx, 3.5, 103.8), Color = col or rgb(80, 55, 40), Material = Enum.Material.Wood })
	end
	local function building(kind, x, w, i)
		local cx = x + w / 2
		local col = facadeCols[math.random(1, #facadeCols)]
		if kind == "apart" then
			local h = math.random(30, 46)
			part({ Name = "Apartments", Size = V(w - 2, h, 32), Position = V(cx, h / 2, 120), Color = col, Material = Enum.Material.Brick })
			windows(x + 5, x + w - 6, 10, h - 4, 6, 7, 3, 3.6)
			for fy = 14, h - 6, 7 do
				part({ Name = "Balcony", Size = V(5, 0.4, 2), Position = V(x + 8, fy - 2.2, 103), Color = rgb(200, 200, 200), Material = Enum.Material.Concrete })
			end
			door(cx)
		elseif kind == "shop" then
			local h = math.random(12, 16)
			part({ Name = "Shop", Size = V(w - 2, h, 32), Position = V(cx, h / 2, 120), Color = col, Material = Enum.Material.Plaster })
			part({ Name = "ShopWindow", Size = V(w - 12, 5, 0.2), Position = V(cx, 3.5, 103.9), Color = rgb(150, 190, 210), Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false })
			part({ Name = "Awning", Size = V(w - 4, 0.4, 3), Position = V(cx, 7.4, 102.4), Color = facadeCols[(i % #facadeCols) + 1], Material = Enum.Material.Fabric, CanCollide = false })
			shopSign(cx, w, nextShop(), rgb(255, 245, 210), 10)
			windows(x + 5, x + w - 6, 10, h - 3, 7, 6, 3, 2.5)
			door(cx + w / 2 - 5, rgb(60, 60, 65))
		elseif kind == "office" then
			local h = math.random(44, 62)
			part({ Name = "Office", Size = V(w - 2, h, 32), Position = V(cx, h / 2, 120), Color = rgb(90, 120, 150), Material = Enum.Material.Glass, Transparency = 0.05 })
			for fy = 6, h, 6 do
				part({ Name = "Floor", Size = V(w - 1.6, 0.6, 0.3), Position = V(cx, fy, 103.9), Color = rgb(200, 205, 210), Material = Enum.Material.Metal, CanCollide = false })
			end
			windows(x + 4, x + w - 5, 9, h - 3, 4, 6, 2.6, 3)
			shopSign(cx, w, "БИЗНЕС-ЦЕНТР", rgb(235, 235, 240), 8)
			door(cx, rgb(40, 40, 45))
		elseif kind == "house" then
			local h = math.random(13, 17)
			part({ Name = "House", Size = V(w - 2, h, 30), Position = V(cx, h / 2, 120), Color = col, Material = Enum.Material.WoodPlanks })
			part({ Name = "Roof", Size = V(w, 2, 32), Position = V(cx, h + 1, 120), Color = rgb(120, 50, 40), Material = Enum.Material.Slate })
			part({ Name = "Roof", Size = V(w - 8, 2, 24), Position = V(cx, h + 3, 120), Color = rgb(120, 50, 40), Material = Enum.Material.Slate })
			part({ Name = "Roof", Size = V(w - 16, 2, 16), Position = V(cx, h + 5, 120), Color = rgb(120, 50, 40), Material = Enum.Material.Slate })
			windows(x + 5, x + w - 6, 5, h - 3, 8, 6, 3.4, 3)
			door(cx)
		else -- warehouse
			local h = 14
			part({ Name = "Warehouse", Size = V(w - 2, h, 34), Position = V(cx, h / 2, 121), Color = rgb(150, 155, 160), Material = Enum.Material.CorrodedMetal })
			part({ Name = "Gate", Size = V(math.min(12, w - 8), 9, 0.3), Position = V(cx, 4.5, 103.8), Color = rgb(110, 115, 120), Material = Enum.Material.DiamondPlate })
			shopSign(cx, w, "СКЛАД", rgb(250, 200, 60), 11)
		end
	end
	local function bank(cx)
		local w, h = 40, 22
		part({ Name = "Bank", Size = V(w - 2, h, 32), Position = V(cx, h / 2, 120), Color = rgb(225, 220, 205), Material = Enum.Material.Marble })
		for k = -2, 2 do
			part({ Name = "Column", Size = V(1.6, 14, 1.6), Position = V(cx + k * 7, 7, 102.5), Color = rgb(240, 238, 230), Material = Enum.Material.Marble })
		end
		part({ Name = "Pediment", Size = V(w - 4, 2, 5), Position = V(cx, 15, 103), Color = rgb(240, 238, 230), Material = Enum.Material.Marble })
		part({ Name = "Steps", Size = V(16, 0.6, 4), Position = V(cx, 0.1, 101.5), Color = rgb(200, 200, 195), Material = Enum.Material.Marble })
		local sign = part({ Name = "BankSign", Size = V(20, 2.6, 0.4), Position = V(cx, 17.5, 100.3), Color = rgb(30, 60, 110) })
		surfaceText(sign, Enum.NormalId.Front, "🏦 БАНК · КРЕДИТЫ", rgb(255, 255, 255))
		windows(cx - 15, cx + 15, 19, 19, 6, 6, 3, 2.4)
		local d = part({ Name = "BankDoor", Size = V(6, 8, 0.4), Position = V(cx, 4, 103.8), Color = rgb(60, 45, 30), Material = Enum.Material.Wood })
		table.insert(BankDoors, d.Position)
		local pr = prompt(d, "Кредит без процентов", "Банк", function(p)
			OpenUIEvent:FireClient(p, "bank")
		end)
		pr.MaxActivationDistance = 12
	end
	local kinds = { "apart", "shop", "office", "house", "warehouse" }
	local banks = { -PLOT_SPACING, PLOT_SPACING }
	local placed = {}
	local prevKind
	local x = -half + 10
	local i = 0
	while x < half - 10 do
		local gap, nb = math.huge, nil
		for bi, bx in ipairs(banks) do
			if not placed[bi] and bx - 20 - x < gap then
				gap, nb = bx - 20 - x, bi
			end
		end
		if nb and gap < 26 then
			if gap > 6 then
				tree(V(x + gap / 2, 0, 112), 1)
			end
			placed[nb] = true
			bank(banks[nb])
			x = banks[nb] + 20
		else
			local w = math.random(26, 44)
			if gap < 52 then
				w = gap
			end
			w = math.min(w, half - x)
			i = i + 1
			local kind
			repeat
				kind = kinds[math.random(1, #kinds)]
			until kind ~= prevKind
			prevKind = kind
			building(kind, x, w, i)
			x = x + w
		end
	end
	-- фонтан на площади у тротуара
	part({ Name = "FountainBase", Shape = Enum.PartType.Cylinder, Size = V(1.2, 9, 9), CFrame = CFrame.new(0, 0.2, 99) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(190, 190, 185), Material = Enum.Material.Concrete })
	part({ Name = "FountainWater", Shape = Enum.PartType.Cylinder, Size = V(0.2, 8, 8), CFrame = CFrame.new(0, 0.85, 99) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(90, 160, 210), Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false })
	-- припаркованные машины
	local deco = Instance.new("Folder")
	deco.Name = "Traffic"
	deco.Parent = world
	for px = -half + 30, half - 30, 55 do
		local cm = Config.CarModels[math.random(1, #Config.CarModels)]
		local car = buildCar(cm, true)
		car.Parent = deco
		car:PivotTo(CFrame.new(px + math.random(-6, 6), 0, 91) * CFrame.Angles(0, math.rad(90), 0))
	end
	-- движущиеся машины по улице
	for lane = 1, 2 do
		task.spawn(function()
			while true do
				local cm = Config.CarModels[math.random(1, #Config.CarModels)]
				local car = buildCar(cm, true)
				car.Parent = deco
				local z = lane == 1 and 70 or 85
				local dir = lane == 1 and 1 or -1
				local startX = -half * dir
				local rot = CFrame.Angles(0, math.rad(dir > 0 and 90 or -90), 0)
				local speed = 35 + math.random(0, 15)
				local t = 0
				local dist = half * 2
				while t * speed < dist do
					local dt = task.wait(0.05)
					t = t + dt
					if car.Parent == nil then
						break
					end
					car:PivotTo(CFrame.new(startX + dir * t * speed, 0, z) * rot)
				end
				car:Destroy()
				task.wait(math.random(3, 9))
			end
		end)
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = V(10, 1, 10)
	spawn.Position = V(0, -0.4, 77)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = world
end

---------------------------------------------------------------- КЛИЕНТЫ В ЗОНЕ ОЖИДАНИЯ
local function moveModel(m, fromCF, toCF, duration)
	local t = 0
	while t < duration do
		local dt = RunService.Heartbeat:Wait()
		t = t + dt
		local a = math.min(t / duration, 1)
		a = a * a * (3 - 2 * a)
		if not m.Parent then
			return
		end
		m:PivotTo(fromCF:Lerp(toCF, a))
	end
	if m.Parent then
		m:PivotTo(toCF)
	end
end

-- клиент заходит через дверь и садится только на СВОБОДНОЕ место (никто не садится друг на друга)
local function walkRig(rig, pts, speed)
	speed = speed or 7
	NpcRig.play(rig, "walk", speed / 12)
	for _, pt in ipairs(pts) do
		if not rig.Parent then
			return
		end
		local from = rig:GetPivot().Position
		local to = Vector3.new(pt.X, from.Y, pt.Z)
		local d = to - from
		if d.Magnitude > 0.05 then
			moveModel(rig, CFrame.lookAt(from, to), CFrame.lookAt(to, to + d.Unit), d.Magnitude / speed)
		end
	end
	NpcRig.play(rig, "idle")
end

local function seatClient(plot)
	for _, s in ipairs(plot.seats) do
		if not s.used then
			s.used = true
			local c = { seat = s, plot = plot, outfit = randomClientOutfit() }
			task.spawn(function()
				local y = plot.L(0, 3, 0).Y
				local w = makeRig(c.outfit, "Client", false, plot.folder)
				w:PivotTo(CFrame.new(plot.L(4, 3, 66)))
				c.walker = w
				walkRig(w, { plot.L(4, 3, 58), plot.L(4, 3, 44.6), Vector3.new(s.pos.X, y, plot.L(0, 0, 44.6).Z) }, 7)
				if w.Parent then
					w:Destroy()
				end
				c.walker = nil
				if c.gone then
					s.used = false
					return
				end
				local rig = makeRig(c.outfit, "Client", false, plot.folder)
				-- R15 садится на невидимое сиденье (верх подушки y = 1.6) лицом от спинки, в сторону зала
				if not NpcRig.sit(rig, CFrame.new(s.pos + Vector3.new(0, 1.6, 0))) then
					rig:Destroy()
					rig = makeBlockyRig(c.outfit, "Client", true, plot.folder)
					rig:PivotTo(CFrame.new(s.pos + Vector3.new(0, 2.4, 0)))
				end
				if c.gone then
					rig:Destroy()
					s.used = false
					return
				end
				c.rig = rig
			end)
			return c
		end
	end
	return nil
end

local function releaseClient(c)
	if not c or c.gone then
		return
	end
	c.gone = true
	if c.walker then
		if c.walker.Parent then
			c.walker:Destroy()
		end
		return
	end
	local rig = c.rig
	c.rig = nil
	if not rig then
		c.seat.used = false
		return
	end
	local plot, s = c.plot, c.seat
	task.spawn(function()
		if rig.Parent then
			rig:Destroy()
		end
		local w = makeRig(c.outfit, "Client", false, plot.folder)
		w:PivotTo(CFrame.new(Vector3.new(s.pos.X, plot.L(0, 3, 0).Y, plot.L(0, 0, 44.6).Z)))
		walkRig(w, { plot.L(4, 3, 44.6), plot.L(4, 3, 58), plot.L(4, 3, 72) }, 7)
		if w.Parent then
			w:Destroy()
		end
		s.used = false
	end)
end

local function carFace(pos, dir)
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 1e-3 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, pos - dir.Unit)
end

local function driveCar(car, points, speed)
	speed = speed or 12
	for _, pt in ipairs(points) do
		if not car.Parent then
			return
		end
		local cf = car:GetPivot()
		local from = cf.Position
		local to = Vector3.new(pt.X, from.Y, pt.Z)
		local d = to - from
		if d.Magnitude > 0.1 then
			local face = carFace(from, d)
			if cf.LookVector:Dot(face.LookVector) < 0.999 then
				moveModel(car, cf, face, 0.8)
			end
			moveModel(car, face, carFace(to, d), d.Magnitude / speed)
		end
	end
end

local function rollFaults(plot, gearbox)
	local recent = (plot and plot.recentFaults) or {}
	local isRecent = {}
	for _, id in ipairs(recent) do
		isRecent[id] = true
	end
	local pool, backup, boxPool = {}, {}, {}
	for _, f in ipairs(Config.Faults) do
		if f.gearbox then
			-- коробка: только неисправности своей КПП
			if f.gearbox == gearbox then
				table.insert(boxPool, f)
			end
		elseif not f.rare and not f.season then
			if isRecent[f.id] then
				table.insert(backup, f)
			else
				table.insert(pool, f)
			end
		end
	end
	local list = {}
	local maxN = 3
	if not isRecent.engine and math.random() < 0.15 then
		table.insert(list, Config.FaultById.engine)
		maxN = 1
	elseif #boxPool > 0 and math.random() < (Config.GearboxFaultChance or 0.35) then
		table.insert(list, boxPool[math.random(1, #boxPool)])
		maxN = 2
	end
	local n = math.random(1, maxN)
	for _ = 1, n do
		local src = (#pool > 0) and pool or backup
		if #src == 0 then
			break
		end
		table.insert(list, table.remove(src, math.random(1, #src)))
	end
	if plot then
		plot.recentFaults = plot.recentFaults or {}
		for _, f in ipairs(list) do
			table.insert(plot.recentFaults, 1, f.id)
		end
		while #plot.recentFaults > 6 do
			table.remove(plot.recentFaults)
		end
	end
	return list
end

local function stepsOf(fs)
	if fs.variant then
		return fs.variant.steps
	end
	return fs.def.steps or {}
end

local function rewardOf(fs)
	if fs.variant then
		return fs.variant.reward
	end
	return fs.def.reward or 0
end

local function liftText(lift, def)
	local pit = def and def.pit
	local pb = tostring(Config.PitBay or 1)
	if lift == "lift" then
		return pit and ("нужен подъёмник или смотровая яма (пост " .. pb .. ")") or "нужен подъёмник"
	elseif lift == "jack" then
		return pit and ("нужен домкрат + стойки, подъёмник или яма (пост " .. pb .. ")") or "нужен домкрат + стойки или подъёмник"
	end
	if pit then
		return "удобнее из ямы (пост " .. pb .. ")"
	end
	return nil
end

local function updateCarLabel(bay)
	local job = bay.job
	if not job or not job.label then
		return
	end
	local lines = { job.name }
	local hiddenLeft = false
	for _, fs in ipairs(job.faults) do
		if fs.revealed then
			local mark = "❌ "
			if fs.done then
				mark = "✅ "
			elseif fs.lockedBy then
				mark = "🔧 "
			end
			table.insert(lines, mark .. fs.def.name)
		elseif not fs.done then
			hiddenLeft = true
		end
	end
	if hiddenLeft then
		table.insert(lines, "⚠ CHECK ENGINE — неизвестная ошибка!")
	end
	job.label.Text = table.concat(lines, "\n")
end

local function missingForJob(p, job)
	if not job then
		return {}, 0
	end
	local need = {}
	for _, fs in ipairs(job.faults) do
		if fs.revealed and not fs.done then
			local steps = (fs.variant and fs.variant.steps) or ((not fs.def.variants) and fs.def.steps) or {}
			for si = math.max(1, fs.stepIdx or 0), #steps do
				local st = steps[si]
				if st and st.items then
					for id, n in pairs(st.items) do
						need[id] = (need[id] or 0) + n
					end
				end
			end
		end
	end
	local list, cost = {}, 0
	for id, n in pairs(need) do
		local miss = n - invGet(p, id)
		if miss > 0 then
			local it = Config.ItemById[id]
			table.insert(list, { id = id, name = itemName(id), n = miss })
			cost = cost + (it and it.price or 0) * miss
		end
	end
	if hired(p, "admin") then
		cost = math.floor(cost * 0.9)
	end
	return list, cost
end

---------------------------------------------------------------- СНИМОК ДЛЯ ПАНЕЛИ РЕМОНТА
local function snapshot(p, bayIndex)
	local bay = Bays[bayIndex]
	local job = bay and bay.job
	local snap = { near = bay and bay.pos or nil, bay = bayIndex, bayLocal = bay and bay.localIdx or bayIndex, shopName = bay and bay.plot.shopName or nil, hasJob = (job ~= nil and job.ready == true) }
	if not snap.hasJob then
		return snap
	end
	snap.car = job.name
	snap.missing, snap.missingCost = missingForJob(p, job)
	snap.hasAdmin = hired(p, "admin")
	snap.scanRemaining = math.max(0, (job.scanUntil or 0) - os.clock())
	snap.scanTotal = job.scanTotal or 3
	snap.hasHidden = false
	snap.faults = {}
	for i, fs in ipairs(job.faults) do
		local f = { idx = i, done = fs.done, revealed = fs.revealed }
		if not fs.revealed then
			if not fs.done then
				snap.hasHidden = true
			end
			f.name = "❓ Неизвестная ошибка"
		else
			f.name = fs.def.name
			f.code = fs.def.code
			f.reward = rewardOf(fs)
			f.liftText = liftText(fs.def.lift, fs.def)
			if fs.lockedBy == p then
				f.mine = true
			elseif fs.lockedBy then
				f.lockedName = fs.lockedName or "кто-то"
			end
			if fs.def.variants and not fs.variant then
				f.variants = {}
				for _, v in ipairs(fs.def.variants) do
					table.insert(f.variants, { id = v.id, name = v.name, reward = v.reward })
				end
			end
			if fs.variant then
				f.variantName = fs.variant.name
			end
			f.busyRemaining = math.max(0, (fs.busyUntil or 0) - os.clock())
			f.busyTotal = fs.busyTotal or 1
			f.busyLabel = fs.busyLabel
			if fs.stepIdx > 0 and not fs.done then
				local steps = stepsOf(fs)
				local st = steps[fs.stepIdx]
				f.stepIdx = fs.stepIdx
				f.stepCount = #steps
				if st then
					local s = { type = st.type, label = st.label, time = st.time, wait = st.wait }
					s.atName = "у машины (пост " .. bay.localIdx .. ")"
					if st.at then
						s.atName = Config.Stations[st.at]
					end
					s.items = {}
					if st.items then
						for id, n in pairs(st.items) do
							table.insert(s.items, { id = id, name = itemName(id), need = n })
						end
					end
					s.tools = {}
					if st.tools then
						for _, id in ipairs(st.tools) do
							table.insert(s.tools, { id = id, name = itemName(id) })
						end
					end
					if st.at then
						table.insert(s.tools, { id = st.at, name = Config.Stations[st.at] })
					end
					f.step = s
					f.bolts = fs.bolts
				end
			end
		end
		table.insert(snap.faults, f)
	end
	return snap
end

local function pushJob(bayIndex)
	local bay = Bays[bayIndex]
	if bay then
		updateCarLabel(bay)
	end
	for p, b in pairs(viewing) do
		if b == bayIndex and p.Parent then
			JobUpdateEvent:FireClient(p, snapshot(p, bayIndex))
		end
	end
end

openJob = function(p, bayIndex)
	viewing[p] = bayIndex
	if Tut.open then
		Tut.open(p, bayIndex)
	end
	OpenUIEvent:FireClient(p, "job")
	JobUpdateEvent:FireClient(p, snapshot(p, bayIndex))
end

openActive = function(p)
	local fs = activeFault[p]
	if fs and not fs.done and not fs.cancelled then
		openJob(p, fs.bayIndex)
	else
		notify(p, "Сначала начните ремонт у машины (подойдите и нажмите E)", "bad")
	end
end

---------------------------------------------------------------- ЖИЗНЕННЫЙ ЦИКЛ МАШИНЫ
local spawnCar

local function carLeave(bay)
	local job = bay.job
	if not job or job.leaving then
		return
	end
	job.leaving = true
	job.ready = false
	for p, fs in pairs(activeFault) do
		if fs.bayIndex == bay.index then
			activeFault[p] = nil
		end
	end
	for _, fs in ipairs(job.faults) do
		fs.cancelled = true
	end
	pushJob(bay.index)
	task.spawn(function()
		task.wait(1.5)
		local car = job.model
		if car and car.Parent then
			sfx(car:GetPivot().Position, "engine")
			driveCar(car, { Vector3.new(bay.pos.X, 0, bay.plot.L(0, 0, -122).Z) }, 14)
		end
		if car then
			car:Destroy()
		end
		releaseClient(job.client)
		job.client = nil
		if bay.job == job then
			bay.job = nil
		end
		pushJob(bay.index)
		if job.tutorial then
			bay.plot.tutJob = nil
			task.wait(3)
			Tut.carLeft(bay, job)
		end
	end)
end

local function checkCarDone(bay)
	local job = bay.job
	if not job or job.leaving then
		return
	end
	for _, fs in ipairs(job.faults) do
		if not fs.done then
			return
		end
	end
	-- отзыв клиента владельцу мастерской
	local owner = job.plot and job.plot.owner
	if owner and owner.Parent and not job.tutorial then
		local stars, why = 5, {}
		local waited = os.clock() - (job.arrivedAt or os.clock())
		local slow = Config.StarSlowTime or 240
		if waited > slow then
			stars = stars - (waited > slow * 2 and 2 or 1)
			table.insert(why, "долго ждал")
		end
		if job.boltBroken then
			stars = stars - 1
			table.insert(why, "сорванный болт")
		end
		for _, fs in ipairs(job.faults) do
			if fs.sloppy then
				stars = stars - 1
				table.insert(why, "капиталка без динамометрического ключа")
				break
			end
		end
		addReview(owner, math.max(1, stars), table.concat(why, ", "))
	end
	for p, earned in pairs(job.earnings) do
		if p.Parent then
			local tip = math.max(Config.ClientTipMin or 150, math.floor(earned * Config.CarCompleteBonus))
			local rt = ratingOf(PD[p])
			if rt and rt >= 4.5 then
				tip = tip * (1 + (Config.StarTipBonus or 0.2))
			end
			if job.vip then
				tip = tip * (Config.VipRewardMult or 1.5)
			end
			local bonus = addCash(p, tip, true)
			sfx(bay.pos, "cash")
			notify(p, "🚗 " .. job.name .. " готова! Бонус от клиента: +$" .. bonus, "good")
			questAdd(p, "cars", 1)
		end
	end
	if job.tutorial and Tut.carDone then
		Tut.carDone(bay)
	end
	carLeave(bay)
end

local function completeFault(bay, fs, p, share)
	fs.done = true
	fs.lockedBy = nil
	fs.lockedName = nil
	fs.busyUntil = 0
	if activeFault[p] == fs then
		activeFault[p] = nil
	end
	local base = rewardOf(fs) * share
	if fs.greased then
		base = base * 1.15
	end
	if bay.job and bay.job.vip then
		base = base * (Config.VipRewardMult or 1.5)
	end
	base = math.floor(base)
	if p.Parent and bay.job then
		local got = addCash(p, base, true)
		addRepair(p)
		questAdd(p, "fix", 1)
		questAdd(p, "fault", 1, fs.def.id)
		syncProgress(p)
		sfx(bay.pos, "done")
		notify(p, "✅ " .. fs.def.name .. ": +$" .. got, "good")
		bay.job.earnings[p] = (bay.job.earnings[p] or 0) + base
		if fs.sloppy and math.random() < Config.ComebackChance then
			local refund = math.floor(base * 0.5)
			task.delay(25, function()
				if p.Parent then
					local c = cashObj(p)
					if c then
						c.Value = math.max(0, c.Value - refund)
					end
					notify(p, "😠 Клиент вернулся: после капремонта болты затянуты обычным ключом «на глаз»! Требует вернуть половину стоимости ремонта: -$" .. refund .. ". Для капиталки нужен динамометрический ключ.", "bad")
				end
			end)
		end
	end
	pushJob(bay.index)
	checkCarDone(bay)
end

local function labelParked(job)
	if not job.label then
		return
	end
	local lines = { "🅿 " .. job.name }
	local hidden = false
	for _, fs in ipairs(job.faults) do
		if fs.revealed then
			table.insert(lines, "❌ " .. fs.def.name)
		else
			hidden = true
		end
	end
	if hidden then
		table.insert(lines, "⚠ CHECK ENGINE")
	end
	table.insert(lines, "Сядьте за руль → отгоните на пост")
	job.label.Text = table.concat(lines, "\n")
end

local function driverSeat(car)
	local seat = Instance.new("Seat")
	seat.Name = "DriverSeatMS"
	seat.Size = Vector3.new(1.6, 0.4, 1.6)
	seat.Transparency = 1
	seat.Anchored = true
	seat.CanCollide = false
	seat.Disabled = true
	seat.CFrame = car:GetPivot() * CFrame.new(-1.2, 1.3, 0.6) * CFrame.Angles(0, math.pi, 0)
	seat.Parent = car
	return seat
end

local function attachToBay(bay, job, p)
	bay.reserved = nil
	if job.spot and job.spot.job == job then
		job.spot.job = nil
	end
	job.spot = nil
	job.bay = bay
	job.driving = false
	for _, fs in ipairs(job.faults) do
		fs.bayIndex = bay.index
	end
	bay.job = job
	if job.prompt then
		job.prompt.ActionText = "Осмотреть"
	end
	job.ready = true
	updateCarLabel(bay)
	pushJob(bay.index)
	if job.tutorial and Tut.open and p then
		Tut.open(p, bay.index)
	end
end

-- клиент приезжает на ПАРКОВКУ; игрок сам выбирает, какую машину и на какой пост ехать
spawnCar = function(plot, opts)
	if not plot or not plot.owner or not plot.parking then
		return
	end
	local spot
	if opts and opts.spot then
		spot = plot.parking[opts.spot]
		if spot and spot.job then
			spot = nil
		end
	end
	if not spot then
		for _, sp in ipairs(plot.parking) do
			if not sp.job then
				spot = sp
				break
			end
		end
	end
	if not spot then
		if opts and opts.tutorial then
			plot.tutJob = nil
		end
		return
	end
	local owner = plot.owner
	local vip = not (opts and opts.tutorial) and owner and owner:GetAttribute("Pass_vip") and #(Config.VipCarModels or {}) > 0 and math.random() < (Config.VipCarChance or 0.3)
	local cm, car
	if vip then
		cm = Config.VipCarModels[math.random(1, #Config.VipCarModels)]
		car = buildCar(cm, false, Config.VipCarColors[math.random(1, #Config.VipCarColors)])
	else
		cm = Config.CarModels[math.random(1, #Config.CarModels)]
		car = buildCar(cm)
	end
	-- коробка передач (взвешенный случайный выбор)
	local gearbox = Config.Gearboxes[1]
	do
		local total = 0
		for _, g in ipairs(Config.Gearboxes) do
			total = total + (g.weight or 1)
		end
		local r = math.random() * total
		for _, g in ipairs(Config.Gearboxes) do
			r = r - (g.weight or 1)
			if r <= 0 then
				gearbox = g
				break
			end
		end
	end
	local title = (vip and "⭐ VIP · " or "") .. cm.name .. " · " .. gearbox.name
	local job = { name = title, model = car, faults = {}, earnings = {}, ready = false, tutorial = opts and opts.tutorial or nil, spot = spot, plot = plot, vip = vip or nil, gearbox = gearbox.id }
	spot.job = job
	if job.tutorial then
		plot.tutJob = job
	end
	local list = job.tutorial and { Config.FaultById.oil } or rollFaults(plot, gearbox.id)
	-- сезонная переобувка
	if not job.tutorial then
		local swap = nil
		if World.season == "winter" then
			swap = Config.FaultById.winter_tires
		elseif (World.summerSwapLeft or 0) > 0 then
			swap = Config.FaultById.summer_tires
		end
		if swap and math.random() < (Config.TireSwapChance or 0.55) then
			table.insert(list, 1, swap)
			while #list > 3 do
				table.remove(list)
			end
		end
	end
	for _, def in ipairs(list) do
		table.insert(job.faults, { def = def, revealed = not def.hidden, done = false, stepIdx = 0, busyUntil = 0, bayIndex = 0, forceRust = opts and opts.forceRust or nil })
	end
	job.label = label3d(car.PrimaryPart, "", 6, Color3.new(1, 1, 1), 330, 150)
	labelParked(job)
	local pp = prompt(car.PrimaryPart, "Сесть за руль", job.name, function(p)
		if plot.owner ~= p then
			notify(p, "Это не ваш автосервис", "bad")
			return
		end
		if job.bay then
			openJob(p, job.bay.index)
			return
		end
		if not job.arrived or job.driving or job.leaving then
			return
		end
		local bays = {}
		for _, b in ipairs(plot.bays) do
			table.insert(bays, { idx = b.localIdx, free = (b.job == nil and not b.reserved), pit = (b.localIdx == (Config.PitBay or 1)), lift = owns(p, "lift") or b.bonus == true, locked = bayLocked(b), bonus = b.bonus == true })
		end
		local faults = {}
		for _, fs in ipairs(job.faults) do
			table.insert(faults, fs.revealed and fs.def.name or "❓ Неизвестная ошибка")
		end
		OpenUIEvent:FireClient(p, "parking", { spot = spot.index, car = job.name, bays = bays, faults = faults, tutorial = job.tutorial and true or false, pitBay = Config.PitBay or 1 })
	end)
	pp.MaxActivationDistance = 14
	job.prompt = pp
	local startCF = CFrame.new(spot.pos.X, 0, plot.L(0, 0, -122).Z)
	car:PivotTo(startCF)
	job.seat = driverSeat(car)
	car.Parent = plot.folder
	sfx(spot.pos, "engine")
	moveModel(car, startCF, CFrame.new(spot.pos.X, 0, spot.pos.Z), 4)
	if spot.job ~= job or job.leaving then
		return
	end
	job.arrived = true
	job.arrivedAt = os.clock()
	job.client = seatClient(plot)
	if plot.owner and not job.tutorial then
		notify(plot.owner, "🚗 Новый клиент: " .. job.name .. " на парковке (место P" .. spot.index .. ")", "info")
	end
end

ParkingEvent.OnServerEvent:Connect(function(p, action, spotIdx, bayLocal)
	if action ~= "drive" then
		return
	end
	local plot = plotOf(p)
	if not plot or plot.owner ~= p or not plot.parking then
		return
	end
	local spot = plot.parking[tonumber(spotIdx) or 0]
	local bay = plot.bays[tonumber(bayLocal) or 0]
	if not spot or not bay then
		return
	end
	local job = spot.job
	if not job or not job.arrived or job.driving or job.leaving then
		notify(p, "Машина ещё не готова", "bad")
		return
	end
	if bayLocked(bay) then
		notify(p, "⭐ Пост " .. bay.localIdx .. " открывается донатом «+1 подъёмник» (Компьютер → Донат)", "bad")
		return
	end
	if bay.job or bay.reserved then
		notify(p, "Пост " .. bay.localIdx .. " занят", "bad")
		return
	end
	if job.tutorial and bay.localIdx ~= (Config.PitBay or 1) then
		notify(p, "Михалыч: «Масло меняем из ямы — гони на пост " .. (Config.PitBay or 1) .. "!»", "info")
		return
	end
	bay.reserved = true
	job.driving = true
	local car = job.model
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = job.seat
	if hum and seat and seat.Parent then
		seat.Disabled = false
		seat:Sit(hum)
	end
	sfx(car:GetPivot().Position, "engine")
	driveCar(car, { Vector3.new(spot.pos.X, 0, LANE_Z), Vector3.new(bay.pos.X, 0, LANE_Z), Vector3.new(bay.pos.X, 0, bay.pos.Z) }, 14)
	if seat and seat.Parent then
		if hum and hum.SeatPart == seat then
			hum.Sit = false
		end
		local sw = seat:FindFirstChild("SeatWeld")
		if sw then
			sw:Destroy()
		end
		seat.Disabled = true
	end
	if not car.Parent or job.leaving or plot.owner ~= p then
		bay.reserved = nil
		return
	end
	attachToBay(bay, job, p)
	task.wait(0.2)
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = CFrame.new(bay.pos + Vector3.new(7, 3.5, 2))
	end
	notify(p, "🔧 " .. job.name .. " на посту " .. bay.localIdx .. ". Подойдите к машине и нажмите E", "good")
end)

---------------------------------------------------------------- ШАГИ РЕМОНТА
local function busy(fs, seconds, label, fn)
	fs.busyUntil = os.clock() + seconds
	fs.busyTotal = seconds
	fs.busyLabel = label
	pushJob(fs.bayIndex)
	-- 3D-модель детали/инструмента рядом с машиной, пока идёт шаг
	local prop = nil
	local st = stepsOf(fs)[fs.stepIdx]
	local pbay = Bays[fs.bayIndex]
	if st and pbay then
		local pid = nil
		if type(st.items) == "table" then
			pid = next(st.items)
		end
		if not pid and type(st.tools) == "table" then
			pid = st.tools[1]
		end
		if pid and PartModels.has(pid) then
			local pos = (st.at and pbay.plot.stations[st.at]) or pbay.pos
			pcall(function()
				prop = PartModels.place(pid, CFrame.new(pos + Vector3.new(4.5, 0, 6)), 1.6, pbay.plot.folder)
			end)
		end
	end
	task.delay(seconds, function()
		if prop then
			prop:Destroy()
		end
		if fs.cancelled then
			return
		end
		fs.busyUntil = 0
		fn()
		pushJob(fs.bayIndex)
	end)
end

local function enterStep(fs)
	fs.bolts = nil
	local st = stepsOf(fs)[fs.stepIdx]
	if st and st.type == "bolts" then
		fs.bolts = {}
		for i = 1, st.count do
			if math.random() < st.rust then
				fs.bolts[i] = "rusty"
			else
				fs.bolts[i] = "ok"
			end
		end
		if fs.forceRust then
			fs.bolts[1] = "rusty"
		end
	end
end

local function advance(fs, p)
	fs.stepIdx = fs.stepIdx + 1
	if fs.stepIdx > #stepsOf(fs) then
		completeFault(Bays[fs.bayIndex], fs, p, 1)
	else
		enterStep(fs)
	end
end

local function nearTarget(p, bayIndex, at)
	local char = p.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local target = Bays[bayIndex].pos
	local radius = 20
	if at then
		target = Bays[bayIndex].plot.stations[at]
		if not target then
			return false
		end
		radius = 14
	end
	local dx = root.Position.X - target.X
	local dz = root.Position.Z - target.Z
	return math.sqrt(dx * dx + dz * dz) <= radius
end

local function liftCheck(p, lift, bay, def)
	local pb = Config.PitBay or 1
	if bay and bay.bonus then
		return true -- донатный пост со своим подъёмником
	end
	if def and def.pit and bay and bay.localIdx == pb then
		return true -- работаем из смотровой ямы
	end
	if lift == "lift" then
		if owns(p, "lift") then
			return true
		end
		if def and def.pit then
			return false, "Нужен подъёмник — или перегоните машину на пост " .. pb .. " со смотровой ямой"
		end
		return false, "Нужен подъёмник (Компьютер → Оборудование)"
	elseif lift == "jack" then
		if owns(p, "lift") then
			return true
		end
		if not owns(p, "jack") then
			return false, "Нужен домкрат или подъёмник (Компьютер)"
		end
		if not owns(p, "stands") then
			return false, "⛔ Без страховочных стоек под машину на домкрате лезть нельзя!"
		end
		return true
	end
	return true
end

local function bpos(fs)
	local b = Bays[fs.bayIndex]
	return b and (b.pos + Vector3.new(0, 1, 0)) or nil
end

local function allBoltsDone(fs)
	for _, s in ipairs(fs.bolts) do
		if s ~= "done" then
			return false
		end
	end
	return true
end

local function handleBolt(p, fs, arg)
	if type(arg) ~= "table" or not fs.bolts then
		return
	end
	local k = tonumber(arg.bolt)
	local state = k and fs.bolts[k]
	if not state or state == "done" then
		return
	end
	local method = arg.method
	local hasImpact = owns(p, "impact")
	local boltTime = 1.5
	if hasImpact then
		boltTime = 0.5
	end
	local function after()
		if allBoltsDone(fs) then
			advance(fs, p)
		end
	end

	-- VIP-гайковёрт: все болты шага разом (кроме сорванных — их выкручивают экстрактором)
	if method == "vip" then
		if not owns(p, "vip_impact") then
			notify(p, "⭐ VIP-гайковёрт есть только у владельцев VIP-пасса (Компьютер → Донат)", "bad")
			return
		end
		local n = 0
		for _, s in pairs(fs.bolts) do
			if s ~= "done" and s ~= "broken" then
				n = n + 1
			end
		end
		if n == 0 then
			notify(p, "Остались только сорванные болты 💥 — выкрутите их по одному", "info")
			return
		end
		sfx(bpos(fs), "impact")
		busy(fs, 1.5, "⭐ VIP-гайковёрт: откручиваем все болты разом (" .. n .. " шт.)...", function()
			for i, s in pairs(fs.bolts) do
				if s ~= "broken" then
					fs.bolts[i] = "done"
				end
			end
			after()
		end)
		return
	end

	if method == "wd40" then
		if state ~= "rusty" then
			notify(p, "WD-40 нужен только для ржавых болтов 🟤", "info")
			return
		end
		if invGet(p, "wd40") < 1 then
			notify(p, "Нет WD-40 на складе (Компьютер → Тех. жидкости)", "bad")
			return
		end
		invAdd(p, "wd40", -1)
		busy(fs, 2, "WD-40 пропитывает резьбу...", function()
			fs.bolts[k] = "soaked"
		end)
	elseif method == "hammer" then
		if state ~= "rusty" then
			notify(p, "Молоток нужен только для прикипших болтов 🟤", "info")
			return
		end
		if not owns(p, "hammer") then
			notify(p, "Нет молотка (Компьютер → Инструменты)", "bad")
			return
		end
		busy(fs, 1, "Простукиваем болт молотком...", function()
			if math.random() < 0.7 then
				sfx(bpos(fs), "hammer")
				fs.bolts[k] = "soaked"
				notify(p, "🔨 Болт сдвинулся!", "good")
			else
				notify(p, "🔨 Не поддался. Ещё раз или WD-40", "info")
			end
		end)
	else
		if state == "broken" then
			if owns(p, "extractor") then
				busy(fs, 3, "Выкручиваем экстрактором...", function()
					fs.bolts[k] = "done"
					after()
				end)
			else
				local paid = spend(p, Config.BrokenBoltFee)
				sfx(bpos(fs), "drill")
				local dl = paid and ("Высверливаем сорванный болт (-$" .. Config.BrokenBoltFee .. ")...") or "Денег нет — высверливаем вручную (дольше, но бесплатно)..."
				busy(fs, paid and 5 or 9, dl, function()
					fs.bolts[k] = "done"
					after()
				end)
			end
		elseif state == "rusty" then
			busy(fs, boltTime * 1.5, "Пытаемся открутить ржавый болт...", function()
				if math.random() < (Config.BoltBreakChance or 0.15) then
					fs.bolts[k] = "broken"
					local bb = Bays[fs.bayIndex]
					if bb and bb.job then
						bb.job.boltBroken = true
					end
					sfx(bpos(fs), "break_")
					notify(p, "💥 Болт сорвало! Нажмите на него, чтобы выкрутить. В следующий раз — WD-40 или молоток.", "bad")
				else
					fs.bolts[k] = "done"
					after()
				end
			end)
		else
			local txt = "Откручиваем ключом..."
			sfx(bpos(fs), owns(p, "impact") and "impact" or "wrench")
			if hasImpact then
				txt = "Гайковёрт: дрррр!"
			end
			busy(fs, boltTime, txt, function()
				fs.bolts[k] = "done"
				after()
			end)
		end
	end
end

local function handleStep(p, fs, st, arg)
	if st.type == "action" then
		if st.tools then
			for _, id in ipairs(st.tools) do
				if not owns(p, id) then
					notify(p, "Нужен инструмент: " .. itemName(id) .. " (Компьютер)", "bad")
					return
				end
			end
		end
		if st.items then
			for id, n in pairs(st.items) do
				if invGet(p, id) < n then
					notify(p, "Не хватает на складе: " .. itemName(id) .. " (" .. invGet(p, id) .. "/" .. n .. "). Закажите в компьютере", "bad")
					return
				end
			end
			for id, n in pairs(st.items) do
				invAdd(p, id, -n)
			end
		end
		sfx(bpos(fs), st.sound or (st.tighten and "wrench") or "action")
		local lbl = st.wait and ("⏳ " .. st.label .. " — можно пока заняться другой машиной") or (st.label .. "...")
		busy(fs, st.time or 2, lbl, function()
			if st.wait and p.Parent then
				notify(p, "⏳ Готово: «" .. st.label .. "» (пост " .. (Bays[fs.bayIndex] and Bays[fs.bayIndex].localIdx or "?") .. ")", "info")
			end
			advance(fs, p)
		end)
	elseif st.type == "torque" then
		if arg == "eye" then
			sfx(bpos(fs), "wrench")
			busy(fs, 1.5, "Затягиваем обычным ключом на глаз (риск возврата половины суммы)...", function()
				fs.sloppy = true
				advance(fs, p)
			end)
		else
			if not owns(p, "torque") then
				notify(p, "Нет динамометрического ключа (Компьютер → Инструменты)", "bad")
				return
			end
			busy(fs, 2, "Затягиваем с моментом... щёлк!", function()
				advance(fs, p)
			end)
		end
	elseif st.type == "grease" then
		if arg == "apply" then
			if invGet(p, "copper_grease") < 1 then
				notify(p, "Нет медной смазки на складе", "bad")
				return
			end
			invAdd(p, "copper_grease", -1)
			busy(fs, 1.5, "Наносим медную смазку...", function()
				fs.greased = true
				advance(fs, p)
			end)
		else
			advance(fs, p)
			pushJob(fs.bayIndex)
		end
	end
end

---------------------------------------------------------------- ДЕЙСТВИЯ ИГРОКА В ПАНЕЛИ РЕМОНТА
JobActionEvent.OnServerEvent:Connect(function(p, action, bayIndex, faultIdx, arg)
	if action == "close" then
		viewing[p] = nil
		return
	end
	if type(bayIndex) ~= "number" then
		return
	end
	local bay = Bays[bayIndex]
	if not bay or bay.plot.owner ~= p then
		notify(p, "Это не ваш бокс", "bad")
		return
	end
	local job = bay.job
	if not job or not job.ready then
		return
	end

	if action == "scan" then
		if not owns(p, "scanner") then
			notify(p, "Нужен автосканер OBD-II (Компьютер → Инструменты)", "bad")
			return
		end
		if (job.scanUntil or 0) > os.clock() then
			return
		end
		if not nearTarget(p, bayIndex, nil) then
			notify(p, "Подойдите к машине", "bad")
			return
		end
		job.scanUntil = os.clock() + 3
		job.scanTotal = 3
		pushJob(bayIndex)
		task.delay(3, function()
			if job.leaving then
				return
			end
			local codes = {}
			for _, fs in ipairs(job.faults) do
				if not fs.revealed then
					fs.revealed = true
					table.insert(codes, fs.def.code .. " — " .. fs.def.name)
				end
			end
			if #codes > 0 then
				notify(p, "🔍 Сканер: " .. table.concat(codes, "; "), "info")
			else
				notify(p, "🔍 Ошибок не найдено", "info")
			end
			pushJob(bayIndex)
		end)
		return
	end

	if action == "refuse" then
		for _, fs in ipairs(job.faults) do
			if fs.lockedBy and fs.lockedBy ~= p then
				notify(p, "Над машиной уже работают", "bad")
				return
			end
		end
		notify(p, "Вы отказали клиенту. Скоро приедет следующий.", "info")
		carLeave(bay)
		return
	end

	local fs = job.faults[tonumber(faultIdx) or 0]
	if not fs or fs.done or not fs.revealed then
		return
	end
	if fs.busyUntil > os.clock() then
		return
	end

	if action == "start" then
		if fs.lockedBy and fs.lockedBy ~= p then
			notify(p, "Этим уже занимается " .. (fs.lockedName or "кто-то"), "bad")
			return
		end
		local ok, msg = liftCheck(p, fs.def.lift, Bays[fs.bayIndex], fs.def)
		if not ok then
			notify(p, msg, "bad")
			return
		end
		if fs.def.variants and not fs.variant then
			for _, v in ipairs(fs.def.variants) do
				if v.id == arg then
					fs.variant = v
				end
			end
			if not fs.variant then
				return
			end
		end
		fs.lockedBy = p
		fs.lockedName = p.DisplayName
		activeFault[p] = fs
		if fs.stepIdx == 0 then
			fs.stepIdx = 1
			enterStep(fs)
		end
		pushJob(bayIndex)
		return
	end

	if fs.lockedBy ~= p then
		return
	end

	if action == "abandon" then
		fs.lockedBy = nil
		fs.lockedName = nil
		activeFault[p] = nil
		pushJob(bayIndex)
		return
	end

	local st = stepsOf(fs)[fs.stepIdx]
	if not st then
		return
	end
	if not nearTarget(p, bayIndex, st.at) then
		if st.at then
			notify(p, "📍 Подойдите к станции: " .. Config.Stations[st.at], "bad")
		else
			notify(p, "📍 Подойдите к машине на посту " .. bayIndex, "bad")
		end
		return
	end
	if st.at and not owns(p, st.at) then
		notify(p, "Нужно оборудование: " .. Config.Stations[st.at] .. " (Компьютер → Оборудование)", "bad")
		return
	end

	if action == "bolt" and st.type == "bolts" then
		handleBolt(p, fs, arg)
	elseif action == "do" and st.type ~= "bolts" then
		handleStep(p, fs, st, arg)
	end
end)

---------------------------------------------------------------- РАБОТНИКИ (NPC)
local npcHomeL = {
	admin = Vector3.new(-36, 0, 35),
	mechanic = Vector3.new(-18, 0, 10),
	electrician = Vector3.new(18, 0, 10),
}
local npcColor = {
	admin = Color3.fromRGB(150, 190, 255),
	mechanic = Color3.fromRGB(255, 160, 70),
	electrician = Color3.fromRGB(255, 225, 80),
}

local function makeNPC(p, wid)
	local def = Config.WorkerById[wid]
	local plot = plotOf(p)
	if not def or not plot then
		return nil
	end
	local hl = npcHomeL[wid] or npcHomeL.mechanic
	local home = plot.L(hl.X, 0, hl.Z)
	if wid ~= "admin" then
		home = home + Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
	end
	local outfit = Outfits[wid] or Outfits.mechanic
	local avatarId = Config.NpcAvatars and Config.NpcAvatars[wid]
	local m, torso, isAvatar = makeRig(outfit, def.name .. " (" .. p.DisplayName .. ")", false, plot.folder, avatarId)
	local rot = (wid == "admin") and CFrame.Angles(0, math.rad(180), 0) or CFrame.new()
	m:PivotTo(CFrame.new(home + Vector3.new(0, 3, 0)) * rot)
	if not isAvatar then
		uniformLabel(torso, plot, outfit.title)
	end
	local lbl = label3d(torso, def.name .. "\nсвободен", 3.8, npcColor[wid] or Color3.new(1, 1, 1), 220, 50)
	return { model = m, label = lbl, home = home, busy = false, name = def.name }
end

local function npcStatus(npc, text)
	if npc and npc.label then
		npc.label.Text = npc.name .. "\n" .. text
	end
end

local function spawnWorker(p, wid)
	NPCs[p] = NPCs[p] or {}
	if NPCs[p][wid] then
		return
	end
	NPCs[p][wid] = makeNPC(p, wid)
end

local function removeWorker(p, wid)
	local list = NPCs[p]
	if list and list[wid] then
		list[wid].model:Destroy()
		list[wid] = nil
	end
end

local function itemsNeeded(steps)
	local need = {}
	for _, st in ipairs(steps) do
		if st.items then
			for id, n in pairs(st.items) do
				need[id] = (need[id] or 0) + n
			end
		end
	end
	return need
end

local function moveNPC(npc, target)
	if npc.model.Parent then
		local from = npc.model:GetPivot()
		local to = Vector3.new(target.X, 3, target.Z)
		local flat = Vector3.new(to.X - from.Position.X, 0, to.Z - from.Position.Z)
		local toCF = CFrame.new(to)
		if flat.Magnitude > 0.1 then
			-- разворачивается по ходу движения и идёт с анимацией
			from = CFrame.lookAt(from.Position, from.Position + flat.Unit)
			toCF = CFrame.lookAt(to, to + flat.Unit)
			NpcRig.play(npc.model, "walk", flat.Magnitude / 2 / 12)
		end
		moveModel(npc.model, from, toCF, 2)
		NpcRig.play(npc.model, "idle")
	end
end

local function tryWorker(p, wid, npc)
	if npc.busy then
		return
	end
	-- автоэлектрик сначала сканирует Check Engine
	if wid == "electrician" and owns(p, "scanner") then
		for _, bay in ipairs(Bays) do
			local job = (bay.plot.owner == p) and bay.job or nil
			if job and job.ready and not job.leaving and not job.npcScan then
				local hidden = false
				for _, fs in ipairs(job.faults) do
					if not fs.revealed then
						hidden = true
					end
				end
				if hidden then
					job.npcScan = true
					npc.busy = true
					npcStatus(npc, "🔍 сканирует пост " .. bay.localIdx)
					task.spawn(function()
						moveNPC(npc, bay.pos + Vector3.new(6, 0, 8))
						task.wait(6)
						if not job.leaving then
							for _, fs in ipairs(job.faults) do
								fs.revealed = true
							end
							if p.Parent then
								notify(p, "🔍 Автоэлектрик просканировал пост " .. bay.localIdx, "info")
							end
							pushJob(bay.index)
						end
						npc.busy = false
						npcStatus(npc, "свободен")
					end)
					return
				end
			end
		end
	end

	local missing = nil
	for _, bay in ipairs(Bays) do
		local job = (bay.plot.owner == p) and bay.job or nil
		if job and job.ready and not job.leaving then
			for _, fs in ipairs(job.faults) do
				if fs.revealed and not fs.done and not fs.lockedBy and fs.stepIdx == 0 and fs.def.worker == wid then
					local need = itemsNeeded(stepsOf(fs))
					local ok = true
					for id, n in pairs(need) do
						if invGet(p, id) < n then
							ok = false
							missing = itemName(id)
						end
					end
					if ok then
						for id, n in pairs(need) do
							invAdd(p, id, -n)
						end
						fs.lockedBy = npc
						fs.lockedName = npc.name
						fs.busyUntil = os.clock() + Config.WorkerJobTime
						fs.busyTotal = Config.WorkerJobTime
						fs.busyLabel = npc.name .. " работает..."
						npc.busy = true
						npcStatus(npc, "🔧 " .. fs.def.name .. " (пост " .. bay.localIdx .. ")")
						pushJob(bay.index)
						task.spawn(function()
							moveNPC(npc, bay.pos + Vector3.new(-6, 0, 8))
							task.wait(Config.WorkerJobTime - 2)
							npc.busy = false
							npcStatus(npc, "свободен")
							if fs.cancelled then
								return
							end
							if p.Parent then
								completeFault(bay, fs, p, Config.WorkerPayShare)
							else
								fs.lockedBy = nil
								fs.lockedName = nil
							end
							moveNPC(npc, npc.home)
						end)
						return
					end
				end
			end
		end
	end
	if missing then
		local d = PD[p]
		local key = "hint_" .. wid
		if d and (d[key] or 0) < os.clock() then
			d[key] = os.clock() + 30
			notify(p, npc.name .. ": нет деталей на складе (" .. missing .. "). Закажите в компьютере!", "info")
		end
	end
end

task.spawn(function()
	while true do
		task.wait(3)
		for p, list in pairs(NPCs) do
			if p.Parent then
				for wid, npc in pairs(list) do
					if wid ~= "admin" then
						tryWorker(p, wid, npc)
					end
				end
			end
		end
	end
end)


---------------------------------------------------------------- ДОНАТ
local function applySpeed(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		if p:GetAttribute("Pass_x2speed") then
			hum.WalkSpeed = 32
		else
			hum.WalkSpeed = 16
		end
	end
end

-- значок VIP над головой
local function applyVipTag(p)
	local head = p.Character and p.Character:FindFirstChild("Head")
	if not head or head:FindFirstChild("VipTag") then
		return
	end
	if not p:GetAttribute("Pass_vip") then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "VipTag"
	bb.Size = UDim2.new(0, 90, 0, 26)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.MaxDistance = 60
	bb.AlwaysOnTop = true
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, 0, 1, 0)
	tl.BackgroundColor3 = Color3.fromRGB(70, 55, 20)
	tl.BackgroundTransparency = 0.2
	tl.Text = "⭐ VIP"
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBlack
	tl.TextColor3 = Color3.fromRGB(255, 215, 90)
	tl.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = tl
	bb.Parent = head
end

local function grantPass(p, key)
	p:SetAttribute("Pass_" .. key, true)
	if key == "x2speed" then
		applySpeed(p)
	elseif key == "vip" then
		applyVipTag(p)
		Hooks.refreshSigns(p)
		p:SetAttribute("Own_vip_impact", true)
	elseif key == "extra_lift" then
		local pl = plotOf(p)
		if pl then
			refreshEquipment(pl)
		end
	end
	notify(p, "⭐ Активировано: " .. Config.GamePasses[key].name, "good")
end

local function grantProduct(p, key)
	local dp = Config.DevProducts[key]
	if key == "boost30" then
		local now = os.time()
		local untilT = math.max(now, p:GetAttribute("BoostUntil") or 0) + (dp.minutes or 30) * 60
		p:SetAttribute("BoostUntil", untilT)
		notify(p, "⚡ " .. dp.name .. " активирован! Осталось " .. math.floor((untilT - now) / 60) .. " мин.", "good")
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(p, passId, purchased)
	if not purchased then
		return
	end
	for key, gp in pairs(Config.GamePasses) do
		if gp.id == passId and gp.id > 0 then
			grantPass(p, key)
		end
	end
end)

---------------------------------------------------------------- КОМПЬЮТЕР: МАГАЗИН / ПЕРСОНАЛ / ДОНАТ
ShopFunction.OnServerInvoke = function(p, action, id, qty)
	local d = PD[p]
	if not d or type(id) ~= "string" then
		return false, "Ошибка"
	end

	if action == "buyNeeded" then
		local bay = Bays[tonumber(id) or 0]
		if not bay or bay.plot.owner ~= p or not bay.job then
			return false, "Нет машины на посту"
		end
		if not hired(p, "admin") then
			return false, "Наймите администратора (Компьютер → Персонал)"
		end
		local list, cost = missingForJob(p, bay.job)
		if #list == 0 then
			return false, "Все нужные запчасти уже на складе"
		end
		if not spend(p, cost) then
			return false, "Не хватает денег ($" .. cost .. ")"
		end
		local names = {}
		for _, m in ipairs(list) do
			invAdd(p, m.id, m.n)
			table.insert(names, m.name .. " x" .. m.n)
		end
		sfx(bay.pos, "cash")
		pushJob(bay.index)
		return true, "Администратор принёс: " .. table.concat(names, ", ") .. " (-$" .. cost .. ")"
	elseif action == "loan" then
		local amount = tonumber(id) or 0
		local valid = false
		for _, v in ipairs(Config.Loans or {}) do
			if v == amount then
				valid = true
			end
		end
		if not valid then
			return false, "Нет такого кредита"
		end
		local cur = d.loan or 0
		local maxL = Config.LoanMax or 1500
		if cur + amount > maxL then
			return false, "Лимит долга $" .. maxL .. ". Сейчас вы должны $" .. cur
		end
		d.loan = cur + amount
		addCash(p, amount, false)
		p:SetAttribute("Loan", d.loan)
		return true, "🏦 Кредит $" .. amount .. " выдан. Без процентов — верните, когда сможете. Долг: $" .. d.loan
	elseif action == "repay" then
		local cur = d.loan or 0
		if cur <= 0 then
			return false, "У вас нет долгов"
		end
		local amount = math.min(cur, math.floor(tonumber(id) or cur), math.floor(getCash(p)))
		if amount <= 0 or not spend(p, amount) then
			return false, "Не хватает денег на погашение"
		end
		d.loan = cur - amount
		p:SetAttribute("Loan", d.loan)
		return true, "🏦 Погашено $" .. amount .. ". Остаток долга: $" .. d.loan
	end

	if action == "buy" then
		local it = Config.ItemById[id]
		if not it then
			return false, "Нет такого товара"
		end
		if it.cat == "part" or it.cat == "fluid" then
			local n = math.clamp(math.floor(tonumber(qty) or 1), 1, 10)
			local price = it.price * n
			if hired(p, "admin") then
				price = math.floor(price * 0.9)
			end
			if not spend(p, price) then
				return false, "Не хватает денег ($" .. price .. ")"
			end
			if hired(p, "admin") then
				invAdd(p, id, n)
				return true, "Администратор заказал: " .. it.name .. " x" .. n .. " — уже на складе (-$" .. price .. ")"
			end
			local order = { id = id, n = n }
			table.insert(d.pending, order)
			task.delay(Config.DeliveryTime, function()
				local dd = PD[p]
				if not dd or not p.Parent then
					return
				end
				for i, o in ipairs(dd.pending) do
					if o == order then
						table.remove(dd.pending, i)
						invAdd(p, o.id, o.n)
						notify(p, "📦 Доставка: " .. it.name .. " x" .. o.n, "good")
						break
					end
				end
			end)
			return true, "Заказ оформлен: " .. it.name .. " x" .. n .. ". Доставка через " .. Config.DeliveryTime .. " сек."
		else
			if it.vip then
				return false, "⭐ Выдаётся вместе с VIP-пассом (вкладка «Донат»)"
			end
			if owns(p, id) then
				return false, "Уже куплено"
			end
			if not spend(p, it.price) then
				return false, "Не хватает денег ($" .. it.price .. ")"
			end
			p:SetAttribute("Own_" .. id, true)
			return true, "Куплено: " .. it.name
		end

	elseif action == "hire" then
		local w = Config.WorkerById[id]
		if not w then
			return false, "Ошибка"
		end
		if hired(p, id) then
			return false, "Уже нанят"
		end
		if not spend(p, w.hire) then
			return false, "Не хватает денег ($" .. w.hire .. ")"
		end
		p:SetAttribute("Hire_" .. id, true)
		spawnWorker(p, id)
		return true, "Нанят: " .. w.name .. " (без зарплаты)"

	elseif action == "fire" then
		local w = Config.WorkerById[id]
		if not w or not hired(p, id) then
			return false, "Ошибка"
		end
		p:SetAttribute("Hire_" .. id, false)
		removeWorker(p, id)
		return true, "Уволен: " .. w.name

	elseif action == "pass" then
		local gp = Config.GamePasses[id]
		if not gp then
			return false, "Ошибка"
		end
		if p:GetAttribute("Pass_" .. id) then
			return false, "Уже есть"
		end
		if gp.id > 0 then
			MarketplaceService:PromptGamePassPurchase(p, gp.id)
			return true, "Окно покупки открыто"
		elseif RunService:IsStudio() then
			grantPass(p, id)
			return true, "(Studio) Выдано бесплатно для теста"
		end
		return false, "Game Pass ещё не настроен (вставьте ID в MechanicConfig)"

	elseif action == "product" then
		local dp = Config.DevProducts[id]
		if not dp then
			return false, "Ошибка"
		end
		if dp.id > 0 then
			MarketplaceService:PromptProductPurchase(p, dp.id)
			return true, "Окно покупки открыто"
		elseif RunService:IsStudio() then
			grantProduct(p, id)
			return true, "(Studio) Выдано бесплатно для теста"
		end
		return false, "Товар ещё не настроен (вставьте Product ID в MechanicConfig)"

	elseif action == "daily" then
		if not d.loaded or not d.tut then
			return false, "Сначала пройдите обучение"
		end
		ensureDaily(p)
		if not p:GetAttribute("DailyReady") then
			return false, "Награда уже получена — приходите завтра!"
		end
		local streak = p:GetAttribute("DailyStreak") or 1
		local amount = (Config.DailyRewards[streak] or Config.DailyRewards[1])
		if p:GetAttribute("Pass_vip") then
			amount = amount * (Config.VipDailyMultiplier or 2)
		end
		d.daily = { day = today(), streak = streak }
		addCash(p, amount, false)
		ensureDaily(p)
		return true, "🎁 Ежедневная награда (день " .. streak .. "): +$" .. amount

	elseif action == "quest" then
		ensureDaily(p)
		local def = Config.QuestById[id]
		if not def or not d.quests then
			return false, "Ошибка"
		end
		for _, q in ipairs(d.quests.list) do
			if q.id == id then
				if q.claimed then
					return false, "Награда уже получена"
				end
				if q.n < def.goal then
					return false, "Задание ещё не выполнено"
				end
				q.claimed = true
				addCash(p, def.reward, false)
				questsSync(p)
				return true, "📋 Награда за задание: +$" .. def.reward
			end
		end
		return false, "Это задание уже сменилось"
	end
	return false, "Неизвестное действие"
end

---------------------------------------------------------------- СОХРАНЕНИЕ
local function save(p)
	local d = PD[p]
	if not DataSave.available() or not d or not d.loaded then
		return
	end
	local data = { cash = getCash(p), repairs = 0, inv = {}, own = {}, hire = {}, tut = d.tut, shopName = d.shopName, loan = d.loan or 0 }
	local ls = p:FindFirstChild("leaderstats")
	local r = ls and ls:FindFirstChild(REPAIRS)
	if r then
		data.repairs = r.Value
	end
	for _, it in ipairs(Config.Items) do
		if it.cat == "part" or it.cat == "fluid" then
			local n = invGet(p, it.id)
			if n > 0 then
				data.inv[it.id] = n
			end
		elseif owns(p, it.id) and not it.vip then
			data.own[it.id] = true
		end
	end
	for _, o in ipairs(d.pending) do
		data.inv[o.id] = (data.inv[o.id] or 0) + o.n
	end
	for _, w in ipairs(Config.Workers) do
		if hired(p, w.id) then
			data.hire[w.id] = true
		end
	end
	data.daily = d.daily
	data.quests = d.quests
	data.reviews = d.reviews
	data.reviewsTotal = d.reviewsTotal
	data.receipts = d.receipts
	data.boostLeft = math.max(0, (p:GetAttribute("BoostUntil") or 0) - os.time())
	data.savedAt = os.time()
	task.spawn(function()
		-- глобальная таблица лидеров
		pcall(function()
			DataStoreService:GetOrderedDataStore(Config.LeaderboardStore):SetAsync("u_" .. p.UserId, data.repairs)
		end)
	end)
	return DataSave.save("p_" .. p.UserId, data)
end

-- разовые покупки (буст). Повторно одну покупку не выдаём: id чеков хранятся в сохранении
MarketplaceService.ProcessReceipt = function(info)
	local p = Players:GetPlayerByUserId(info.PlayerId)
	local d = p and PD[p]
	if not d or not d.loaded then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	d.receipts = d.receipts or {}
	if table.find(d.receipts, info.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local key
	for k, dp in pairs(Config.DevProducts) do
		if dp.id > 0 and dp.id == info.ProductId then
			key = k
		end
	end
	if not key then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	grantProduct(p, key)
	table.insert(d.receipts, info.PurchaseId)
	while #d.receipts > 50 do
		table.remove(d.receipts, 1)
	end
	if DataSave.available() and not save(p) then
		-- выдано в этой сессии; Roblox повторит чек позже, а повтор отсечётся по receipts
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

---------------------------------------------------------------- БОКСЫ ИГРОКОВ
local function claimPlot(p)
	for _, pl in ipairs(Plots) do
		if not pl.owner then
			pl.owner = p
			pl.ready = false
			p:SetAttribute("PlotOrigin", pl.origin)
			p:SetAttribute("PlotIndex", pl.index)
			p:SetAttribute("ComputerPos", pl.computerPos)
			return pl
		end
	end
	return nil
end

local function removeMentor(plot)
	if plot.mentor then
		plot.mentor:Destroy()
		plot.mentor = nil
	end
end

local function releasePlot(p)
	local pl = plotOf(p)
	if not pl then
		return
	end
	for _, bay in ipairs(pl.bays) do
		local job = bay.job
		if job then
			job.leaving = true
			for _, fs in ipairs(job.faults) do
				fs.cancelled = true
			end
			if job.model then
				job.model:Destroy()
			end
			releaseClient(job.client)
			job.client = nil
			bay.job = nil
		end
	end
	for _, spot in ipairs(pl.parking or {}) do
		local job = spot.job
		if job then
			job.leaving = true
			if job.model then
				job.model:Destroy()
			end
			releaseClient(job.client)
			job.client = nil
			spot.job = nil
		end
	end
	for _, bay in ipairs(pl.bays) do
		bay.reserved = nil
	end
	pl.tutJob = nil
	pl.nextSpawn = nil
	removeMentor(pl)
	pl.owner = nil
	pl.ready = false
	setShopName(pl, nil)
	refreshEquipment(pl)
end

local function sendHome(p)
	local pl = plotOf(p)
	local char = p.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if pl and root then
		root.CFrame = CFrame.new(pl.L(0, 4, 64))
	end
end

local function startCars(plot, firstDelay)
	plot.ready = true
	plot.nextSpawn = os.clock() + (firstDelay or 2)
end

---------------------------------------------------------------- ОБУЧЕНИЕ И СЮЖЕТ
local TutIndex = {}
for i, s in ipairs(Config.Tutorial) do
	TutIndex[s.id] = i
end
local TUT_CAR = { tutorial = true, forceRust = true, spot = 1 }

-- сколько стоят запчасти на первый ремонт (масло + фильтр)
local function tutPartsCost()
	local sum = 0
	for _, st in ipairs(Config.FaultById.oil.steps) do
		for id, n in pairs(st.items or {}) do
			sum = sum + (Config.ItemById[id] and Config.ItemById[id].price or 0) * n
		end
	end
	return sum
end

local Dialog1 = {
	"Ну здравствуй, новый хозяин! Сорок лет я тут гайки крутил...",
	"Мастерская старая, да крепкая. За стеклом — бокс на четыре поста, тут — холл для клиентов.",
	"Инструмент я весь распродал, уж не серчай. Зато компьютер на стойке работает.",
	"Закажи моторное масло (вкладка «Тех. жидкости») и масляный фильтр. Первый клиент уже звонил — ему масло поменять. Менять будем из ямы на первом посту — домкрат не нужен.",
	"Только вот денег у тебя — кот наплакал, на запчасти не хватит. Не беда: выйди на улицу, найди 🏦 БАНК и возьми кредит $150. Процентов там нет — отдашь, когда клиенты заплатят.",
}
local Dialog2 = {
	"Вот это я понимаю! Руки из нужного места растут.",
	"Дальше сам: клиенты ставят машины на парковку за боксом — садись за руль и загоняй на свободный пост. Сканер, подъёмник, шиномонтаж, персонал — через компьютер. А если деньги кончатся — в банке через дорогу дают кредит без процентов.",
	"А старая вывеска совсем рассыпалась. Придумай-ка мастерской своё имя!",
}

local function tutTarget(plot, id)
	if id == "talk1" or id == "talk2" or id == "name" then
		return plot.L(0, 5, 44)
	elseif id == "buy" or id == "wait" then
		return plot.computerPos + Vector3.new(-3, 6, 0)
	elseif id == "bank" then
		local best
		for _, pos in ipairs(BankDoors) do
			if not best or (pos - plot.origin).Magnitude < (best - plot.origin).Magnitude then
				best = pos
			end
		end
		return best and (best + Vector3.new(0, 6, 2)) or nil
	elseif id == "car" then
		return plot.parking[1].pos + Vector3.new(0, 6, 0)
	elseif id == "repair" then
		return plot.bays[Config.PitBay or 1].pos + Vector3.new(0, 6, 0)
	end
	return nil
end

local function setTut(p, id)
	local d = PD[p]
	local plot = plotOf(p)
	if not d or not plot then
		return
	end
	d.tutStage = id
	if id == nil then
		p:SetAttribute("TutStep", nil)
		p:SetAttribute("TutStepNum", nil)
		p:SetAttribute("TutTarget", nil)
		return
	end
	local s = Config.Tutorial[TutIndex[id]]
	p:SetAttribute("TutStep", s and s.text or "")
	p:SetAttribute("TutStepNum", TutIndex[id])
	p:SetAttribute("TutTarget", tutTarget(plot, id))
end

local function spawnMentor(plot)
	if plot.mentor then
		return
	end
	local rig, torso = makeRig(Outfits.mentor, Config.MentorName, false, plot.folder)
	rig:PivotTo(CFrame.new(plot.L(0, 3, 44)) * CFrame.Angles(0, math.rad(180), 0))
	label3d(torso, "👴 " .. Config.MentorName, 3.6, rgb(255, 230, 150), 220, 40)
	local pp = prompt(torso, "Поговорить", Config.MentorName, function(p)
		if plot.owner ~= p then
			notify(p, "Михалыч: «Иди к себе в мастерскую, сынок»", "info")
			return
		end
		onMentorTalk(p)
	end)
	pp.MaxActivationDistance = 10
	plot.mentor = rig
end

onMentorTalk = function(p)
	local d = PD[p]
	if not d or d.tut then
		return
	end
	if d.tutStage == "talk1" then
		StoryEvent:FireClient(p, "dialog", { speaker = Config.MentorName, lines = Dialog1 })
		setTut(p, getCash(p) < tutPartsCost() and "bank" or "buy")
	elseif d.tutStage == "talk2" or d.tutStage == "name" then
		StoryEvent:FireClient(p, "dialog", { speaker = Config.MentorName, lines = Dialog2, after = "name" })
		setTut(p, "name")
	else
		local s = Config.Tutorial[TutIndex[d.tutStage or "talk1"] or 1]
		StoryEvent:FireClient(p, "dialog", { speaker = Config.MentorName, lines = { "Давай-давай, не стой! " .. (s and s.text or "") } })
	end
end

Tut.open = function(p, bayIndex)
	local d = PD[p]
	local bay = Bays[bayIndex]
	if d and not d.tut and d.tutStage == "car" and bay and bay.job and bay.job.tutorial then
		setTut(p, "repair")
	end
end

Tut.carDone = function(bay)
	local p = bay.plot.owner
	local d = p and PD[p]
	if d and not d.tut then
		setTut(p, "talk2")
		notify(p, "🎉 Первый ремонт сделан! Вернитесь к Михалычу в холл.", "good")
	end
end

Tut.carLeft = function(bay, job)
	local plot = bay.plot
	local p = plot.owner
	local d = p and PD[p]
	if d and not d.tut and (d.tutStage == "car" or d.tutStage == "repair") and not plot.tutJob then
		setTut(p, "car")
		plot.tutJob = true
		task.spawn(spawnCar, plot, TUT_CAR)
	end
end

-- проверка шагов «купить» и «дождаться доставки»
task.spawn(function()
	local need = itemsNeeded(Config.FaultById.oil.steps)
	while true do
		task.wait(1)
		for p, d in pairs(PD) do
			local plot = plotOf(p)
			if plot and d.loaded and not d.tut and d.tutStage == "bank" and getCash(p) >= tutPartsCost() then
				setTut(p, "buy")
				notify(p, "🏦 Деньги есть! Теперь к компьютеру на стойке — закажите масло и фильтр.", "good")
			end
			if plot and d.loaded and not d.tut and (d.tutStage == "buy" or d.tutStage == "wait") then
				local hasTools = true -- замена масла идёт из ямы, домкрат и стойки не нужны
				local hasParts = true
				local ordered = true
				for id, n in pairs(need) do
					if invGet(p, id) < n then
						hasParts = false
						local coming = 0
						for _, o in ipairs(d.pending) do
							if o.id == id then
								coming = coming + o.n
							end
						end
						if invGet(p, id) + coming < n then
							ordered = false
						end
					end
				end
				if hasTools and hasParts then
					setTut(p, "car")
					notify(p, "🚗 Приехал первый клиент! Машина на парковке за боксом (P1): сядьте за руль и загоните её на пост " .. (Config.PitBay or 1) .. " (яма).", "good")
					if not plot.tutJob then
						plot.tutJob = true
						task.spawn(spawnCar, plot, TUT_CAR)
					end
				elseif hasTools and ordered and d.tutStage == "buy" then
					setTut(p, "wait")
				end
			end
		end
	end
end)

-- название мастерской
StoryEvent.OnServerEvent:Connect(function(p, action, arg)
	local d = PD[p]
	local plot = plotOf(p)
	if not d or not plot then
		return
	end
	if action == "talk" then
		onMentorTalk(p)
		return
	end
	if action ~= "setName" then
		return
	end
	if not d.tut and d.tutStage ~= "name" then
		notify(p, "Сначала закончите обучение", "bad")
		return
	end
	if type(arg) ~= "string" then
		return
	end
	local name = string.gsub(arg, "^%s+", "")
	name = string.gsub(name, "%s+$", "")
	name = string.gsub(name, "[%c]", "")
	local len = utf8.len(name) or #name
	if len < 1 or len > Config.ShopNameMax then
		notify(p, "Название: от 1 до " .. Config.ShopNameMax .. " символов", "bad")
		return
	end
	if (d.lastRename or 0) > os.clock() - 3 then
		return
	end
	d.lastRename = os.clock()
	local okF, filtered = pcall(function()
		local res = TextService:FilterStringAsync(name, p.UserId)
		return res:GetNonChatStringForBroadcastAsync()
	end)
	if not okF then
		if RunService:IsStudio() then
			filtered = name
		else
			notify(p, "Фильтр текста недоступен, попробуйте позже", "bad")
			return
		end
	end
	local first = not d.tut
	d.shopName = filtered
	d.tut = true
	setShopName(plot, filtered)
	p:SetAttribute("ShopName", filtered)
	setTut(p, nil)
	removeMentor(plot)
	if first then
		StoryEvent:FireClient(p, "named", { name = filtered, origin = plot.origin })
		addCash(p, 500, false)
		notify(p, "🎉 Добро пожаловать в «" .. filtered .. "»! Михалыч оставил вам $500 на развитие.", "good")
		startCars(plot, 8)
	else
		notify(p, "✏ Вывески обновлены: «" .. filtered .. "»", "good")
	end
	save(p)
end)

local function onPlayerAdded(p)
	local d = { pending = {}, loaded = false }
	PD[p] = d
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = CASH
	cash.Parent = ls
	local reps = Instance.new("IntValue")
	reps.Name = REPAIRS
	reps.Parent = ls
	local starsVal = Instance.new("StringValue")
	starsVal.Name = STARS
	starsVal.Value = "—"
	starsVal.Parent = ls

	local ok, data = DataSave.load("p_" .. p.UserId)
	if not p.Parent then
		-- игрок вышел, пока грузилось сохранение — не занимаем бокс
		PD[p] = nil
		return
	end
	if not ok then
		task.delay(4, function()
			if p.Parent then
				notify(p, "⚠ Не удалось загрузить сохранение. Чтобы не затереть прогресс, эта сессия НЕ сохраняется — перезайдите позже.", "bad")
			end
		end)
	end
	cash.Value = (data and data.cash) or Config.StartCash
	reps.Value = (data and data.repairs) or 0
	if data then
		for id, n in pairs(data.inv or {}) do
			p:SetAttribute("Inv_" .. id, n)
		end
		for id in pairs(data.own or {}) do
			p:SetAttribute("Own_" .. id, true)
		end
		for id in pairs(data.hire or {}) do
			if Config.WorkerById[id] then
				p:SetAttribute("Hire_" .. id, true)
			end
		end
	else
		p:SetAttribute("Inv_wd40", 3)
	end
	ls.Parent = p
	d.loaded = ok
	d.tut = (data and data.tut) and true or false
	d.shopName = data and data.shopName or nil
	d.loan = data and data.loan or 0
	p:SetAttribute("Loan", d.loan)
	d.daily = data and data.daily or nil
	d.quests = data and data.quests or nil
	d.reviews = data and data.reviews or {}
	d.reviewsTotal = data and data.reviewsTotal or 0
	d.receipts = data and data.receipts or {}
	if data and (data.boostLeft or 0) > 0 then
		p:SetAttribute("BoostUntil", os.time() + data.boostLeft)
	end
	ensureDaily(p)
	questsSync(p)
	syncProgress(p)

	local plot = claimPlot(p)
	if plot then
		setShopName(plot, d.tut and d.shopName or nil)
		if d.shopName then
			p:SetAttribute("ShopName", d.shopName)
		end
		refreshEquipment(plot)
		local refreshQueued = false
		p.AttributeChanged:Connect(function(attr)
			local pre = string.sub(attr, 1, 4)
			if (pre == "Own_" or pre == "Inv_" or attr == "Pass_extra_lift") and not refreshQueued then
				refreshQueued = true
				task.delay(0.5, function()
					refreshQueued = false
					local pl = plotOf(p)
					if pl then
						refreshEquipment(pl)
					end
				end)
			end
		end)
	end

	for _, w in ipairs(Config.Workers) do
		if hired(p, w.id) then
			spawnWorker(p, w.id)
		end
	end

	for key, gp in pairs(Config.GamePasses) do
		if gp.id > 0 then
			local okp, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(p.UserId, gp.id)
			end)
			if okp and has then
				p:SetAttribute("Pass_" .. key, true)
			end
		end
	end
	if p:GetAttribute("Pass_vip") then
		p:SetAttribute("Own_vip_impact", true)
	end
	Hooks.refreshSigns(p)

	p.CharacterAdded:Connect(function(char)
		char:WaitForChild("Humanoid")
		char:WaitForChild("HumanoidRootPart")
		applySpeed(p)
		char:WaitForChild("Head", 5)
		applyVipTag(p)
		task.wait(0.1)
		sendHome(p)
	end)
	if p.Character then
		applySpeed(p)
		applyVipTag(p)
		sendHome(p)
	end

	if not plot then
		notify(p, "Все 4 бокса заняты — вы в режиме зрителя", "bad")
	elseif d.tut then
		notify(p, "👋 С возвращением в «" .. (d.shopName or Config.DefaultShopName) .. "»!", "info")
		startCars(plot, 3)
	else
		spawnMentor(plot)
		setTut(p, "talk1")
		task.delay(1.5, function()
			if p.Parent then
				StoryEvent:FireClient(p, "intro", { lines = Config.IntroLines, origin = plot.origin })
			end
		end)
	end
end

---------------------------------------------------------------- СТАРТ
buildCity()
for k = 1, Config.MaxPlots do
	refreshEquipment(buildPlot(k))
end

-- СЕЗОНЫ: зимой земля под снегом, идёт снег, клиенты едут на зимнюю резину; после таяния — на летнюю
local groundLook = {}
for _, d in ipairs(world:GetDescendants()) do
	if d:IsA("BasePart") and d.Name == "Ground" then
		groundLook[d] = { d.Color, d.Material }
	end
end
local function setSeason(season)
	local first = World.seasonLeft == 0 and season == "summer"
	World.season = season
	World.seasonLeft = season == "winter" and (Config.WinterDays or 3) or (Config.SummerDays or 3)
	workspace:SetAttribute("Season", season)
	for part, look in pairs(groundLook) do
		if season == "winter" then
			part.Color = Color3.fromRGB(235, 240, 245)
			part.Material = Enum.Material.Snow
		else
			part.Color = look[1]
			part.Material = look[2]
		end
	end
	if first then
		return
	end
	local msg
	if season == "winter" then
		World.weather = "snow"
		msg = "❄ Пришла зима! Выпал снег — клиенты поедут переобуваться на ЗИМНЮЮ резину. Закажите зимние шины (Компьютер → Запчасти)."
	else
		World.weather = "clear"
		World.summerSwapLeft = Config.SummerSwapDays or 1
		msg = "🌱 Снег растаял! Клиенты поедут переобуваться обратно на ЛЕТНЮЮ резину. Закажите летние шины."
	end
	workspace:SetAttribute("Weather", World.weather)
	for _, p in ipairs(Players:GetPlayers()) do
		notify(p, msg, "info")
	end
end
setSeason("summer")

-- время суток, погода и подарки дня (игрок не может обанкротиться)
task.spawn(function()
	local dayLen = Config.DayLength or 720
	local function nextW()
		return os.clock() + math.random(Config.WeatherChangeMin or 120, Config.WeatherChangeMax or 300)
	end
	local nextWeather = nextW()
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	local baseDensity = atm and atm.Density or 0.3
	local baseHaze = atm and atm.Haze or 0
	local giftDay = {}
	local last = os.clock()
	World.clock = 8
	World.night = false
	applyNight(false)
	workspace:SetAttribute("Weather", World.weather)
	while true do
		task.wait(0.5)
		local now = os.clock()
		local dt = now - last
		last = now
		local prev = World.clock
		World.clock = (World.clock + dt * 24 / dayLen) % 24
		if World.clock < prev then
			World.day = World.day + 1
			World.summerSwapLeft = math.max(0, (World.summerSwapLeft or 0) - 1)
			World.seasonLeft = World.seasonLeft - 1
			if World.seasonLeft <= 0 then
				setSeason(World.season == "winter" and "summer" or "winter")
			end
		end
		Lighting.ClockTime = World.clock
		local isNight = World.clock >= (Config.NightStart or 21) or World.clock < (Config.NightEnd or 6)
		if isNight ~= World.night then
			World.night = isNight
			applyNight(isNight)
			for _, p in ipairs(Players:GetPlayers()) do
				notify(p, isNight and "🌙 Наступила ночь — новые клиенты не приезжают до утра. Можно доделать текущие машины." or "☀ Утро! Клиенты снова едут в автосервис.", "info")
			end
		end
		if now >= nextWeather then
			nextWeather = nextW()
			local r = math.random()
			if World.season == "winter" then
				World.weather = (r < 0.65 and "snow") or (r < 0.85 and "cloudy") or "clear"
			else
				World.weather = (r < 0.5 and "clear") or (r < 0.75 and "cloudy") or "rain"
			end
			workspace:SetAttribute("Weather", World.weather)
			if atm then
				local add = (World.weather == "rain" and 0.2) or (World.weather == "cloudy" and 0.1) or 0
				atm.Density = baseDensity + add
				atm.Haze = baseHaze + add * 8
			end
		end
		Lighting.Brightness = isNight and 1 or ((World.weather == "rain" and 1.7) or ((World.weather == "cloudy" or World.weather == "snow") and 2.1) or 2.6)
		workspace:SetAttribute("Clock", World.clock)
		workspace:SetAttribute("Day", World.day)
		workspace:SetAttribute("Night", isNight)
		if not isNight then
			for _, p in ipairs(Players:GetPlayers()) do
				local d = PD[p]
				if d and d.loaded and d.tut and giftDay[p.UserId] ~= World.day then
					giftDay[p.UserId] = World.day
					if getCash(p) < (Config.PoorThreshold or 250) then
						addCash(p, Config.PoorGift or 300, false)
						notify(p, "🎁 Подарок дня: +$" .. (Config.PoorGift or 300) .. " — Михалыч подкинул на запчасти, чтобы не прогореть!", "good")
					else
						addCash(p, Config.DailyGift or 100, false)
						notify(p, "🎁 Подарок дня: +$" .. (Config.DailyGift or 100), "good")
					end
				end
			end
		end
	end
end)

-- поток клиентов на парковку (ночью никто не приезжает)
task.spawn(function()
	while true do
		task.wait(1)
		if not World.night then
			for _, plot in ipairs(Plots) do
				if plot.owner and plot.ready and plot.parking and plot.nextSpawn and os.clock() >= plot.nextSpawn then
					local waiting, inWork, open = 0, 0, 0
					for _, sp in ipairs(plot.parking) do
						if sp.job then
							waiting = waiting + 1
						end
					end
					for _, b in ipairs(plot.bays) do
						if b.job then
							inWork = inWork + 1
						end
						if not bayLocked(b) then
							open = open + 1
						end
					end
					if waiting < math.min(Config.MaxWaitingCars or 4, #plot.parking) then
						local k = (waiting + inWork >= open) and 2 or 1
						-- хороший рейтинг = клиенты едут чаще, плохой = реже
						local rt = ratingOf(PD[plot.owner])
						if rt then
							k = k * math.clamp(1 - (rt - 3) * (Config.StarSpawnEffect or 0.15), 0.5, 1.6)
						end
						plot.nextSpawn = os.clock() + (Config.CarSpawnInterval or 18) * k
						task.spawn(spawnCar, plot)
					else
						plot.nextSpawn = os.clock() + 5
					end
				end
			end
		end
	end
end)

-- новые сутки (задания, ежедневная награда) и таблица лидеров
task.spawn(function()
	while true do
		for _, p in ipairs(Players:GetPlayers()) do
			if PD[p] then
				ensureDaily(p)
			end
		end
		task.wait(30)
	end
end)

local nameCache = {}
local function userName(uid)
	if nameCache[uid] then
		return nameCache[uid]
	end
	local pl = Players:GetPlayerByUserId(uid)
	local ok, n = pcall(function()
		return pl and pl.DisplayName or Players:GetNameFromUserIdAsync(uid)
	end)
	nameCache[uid] = ok and n or ("#" .. uid)
	return nameCache[uid]
end

task.spawn(function()
	task.wait(5)
	local store
	pcall(function()
		store = DataStoreService:GetOrderedDataStore(Config.LeaderboardStore)
	end)
	while true do
		local rows
		if store then
			local ok, pages = pcall(function()
				return store:GetSortedAsync(false, Config.LeaderboardSize or 10)
			end)
			if ok and pages then
				rows = {}
				for _, e in ipairs(pages:GetCurrentPage()) do
					local uid = tonumber(string.sub(e.key, 3))
					if uid then
						table.insert(rows, { name = userName(uid), value = e.value })
					end
				end
			end
		end
		local live = {}
		for _, p in ipairs(Players:GetPlayers()) do
			live[p.DisplayName] = repairsOf(p)
		end
		if not rows then
			-- нет доступа к DataStore (Studio без API) — показываем игроков на сервере
			rows = {}
			for n, v in pairs(live) do
				table.insert(rows, { name = n, value = v })
			end
		else
			for _, r in ipairs(rows) do
				if live[r.name] and live[r.name] > r.value then
					r.value = live[r.name]
				end
			end
		end
		table.sort(rows, function(a, b)
			return a.value > b.value
		end)
		local lines = { "🏆 ТОП МЕХАНИКОВ (ремонты)" }
		for i, r in ipairs(rows) do
			if i > (Config.LeaderboardSize or 10) then
				break
			end
			table.insert(lines, i .. ". " .. r.name .. " — " .. r.value)
		end
		if #rows == 0 then
			table.insert(lines, "пока пусто")
		end
		local txt = table.concat(lines, "\n")
		for _, pl in ipairs(Plots) do
			for _, l in ipairs(pl.leaderLabels or {}) do
				l.Text = txt
			end
		end
		workspace:SetAttribute("Leaderboard", HttpService:JSONEncode(rows))
		task.wait(Config.LeaderboardRefresh or 90)
	end
end)

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(p)
	save(p)
	releasePlot(p)
	for _, bay in ipairs(Bays) do
		if bay.job then
			for _, fs in ipairs(bay.job.faults) do
				if fs.lockedBy == p then
					fs.lockedBy = nil
					fs.lockedName = nil
				end
			end
			bay.job.earnings[p] = nil
			pushJob(bay.index)
		end
	end
	if NPCs[p] then
		for wid in pairs(NPCs[p]) do
			removeWorker(p, wid)
		end
	end
	NPCs[p] = nil
	PD[p] = nil
	viewing[p] = nil
	activeFault[p] = nil
end)

game:BindToClose(function()
	-- сохраняем всех параллельно и ждём, пока записи дойдут (до 25 сек)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(save, p)
	end
	task.wait(0.2)
	DataSave.waitAll(25)
end)

task.spawn(function()
	while true do
		task.wait(120)
		for _, p in ipairs(Players:GetPlayers()) do
			save(p)
		end
	end
end)

