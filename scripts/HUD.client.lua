-- HUD (LocalScript, StarterPlayerScripts)
-- Интерфейс v4 (парковка, банк, часы/погода, музыка, автозакрытие окон). Было: v3 (3D-модели деталей, название мастерской): деньги, уведомления, компьютер (магазин/персонал/донат), склад, панель ремонта.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("MechanicConfig"))
local remotes = ReplicatedStorage:WaitForChild("MechanicRemotes")
local NotifyEvent = remotes:WaitForChild("Notify")
local OpenUIEvent = remotes:WaitForChild("OpenUI")
local JobUpdateEvent = remotes:WaitForChild("JobUpdate")
local JobActionEvent = remotes:WaitForChild("JobAction")
local ShopFunction = remotes:WaitForChild("ShopAction")
local ParkingEvent = remotes:WaitForChild("Parking")
local SoundService = game:GetService("SoundService")
local PartModels = require(ReplicatedStorage:WaitForChild("PartModels"))

local COLORS = {
	bg = Color3.fromRGB(28, 30, 38),
	panel = Color3.fromRGB(40, 43, 54),
	card = Color3.fromRGB(52, 56, 70),
	text = Color3.fromRGB(235, 235, 240),
	dim = Color3.fromRGB(160, 165, 180),
	good = Color3.fromRGB(60, 170, 90),
	bad = Color3.fromRGB(200, 60, 60),
	info = Color3.fromRGB(60, 110, 200),
	warn = Color3.fromRGB(230, 160, 30),
	btn = Color3.fromRGB(70, 110, 210),
	gray = Color3.fromRGB(90, 92, 104),
}

local function new(cls, props, children)
	local o = Instance.new(cls)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			o[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = o
	end
	if props and props.Parent then
		o.Parent = props.Parent
	end
	return o
end

local function corner(o, r)
	new("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = o })
	return o
end

local function pad(o, n)
	new("UIPadding", { PaddingTop = UDim.new(0, n), PaddingBottom = UDim.new(0, n), PaddingLeft = UDim.new(0, n), PaddingRight = UDim.new(0, n), Parent = o })
	return o
end

local function label(parent, text, size, color, h, bold)
	return new("TextLabel", {
		Parent = parent,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, h or 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
		TextSize = size or 14,
		TextColor3 = color or COLORS.text,
	})
end

local function button(parent, text, color, w, h, cb)
	local b = new("TextButton", {
		Parent = parent,
		Size = UDim2.new(0, w or 120, 0, h or 30),
		BackgroundColor3 = color or COLORS.btn,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextWrapped = true,
		AutoButtonColor = true,
	})
	corner(b, 6)
	if cb then
		b.MouseButton1Click:Connect(cb)
	end
	return b
end

local function row(parent, h)
	local f = new("Frame", { Parent = parent, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h or 32) })
	new("UIListLayout", { Parent = f, FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center })
	return f
end

local function clear(f)
	for _, c in ipairs(f:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function window(name, title, size, pos)
	local w = new("Frame", { Name = name, BackgroundColor3 = COLORS.bg, Size = size, Position = pos, Visible = false })
	corner(w, 10)
	local head = new("TextLabel", { Parent = w, BackgroundTransparency = 1, Size = UDim2.new(1, -50, 0, 36), Position = UDim2.new(0, 14, 0, 4), Text = title, Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = COLORS.text, TextXAlignment = Enum.TextXAlignment.Left })
	local close = button(w, "✕", COLORS.bad, 30, 30)
	close.Position = UDim2.new(1, -38, 0, 6)
	local body = new("ScrollingFrame", { Parent = w, BackgroundTransparency = 1, Size = UDim2.new(1, -16, 1, -52), Position = UDim2.new(0, 8, 0, 44), CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, BorderSizePixel = 0 })
	new("UIListLayout", { Parent = body, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })
	return w, body, close, head
end

local function card(parent, color)
	local c = new("Frame", { Parent = parent, BackgroundColor3 = color or COLORS.card, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	corner(c, 8)
	pad(c, 8)
	new("UIListLayout", { Parent = c, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder })
	return c
end

local function iconLine(parent, id, text, px, rotate, textSize)
	local r = row(parent, px)
	pcall(PartModels.viewport, id, r, UDim2.new(0, px, 0, px), rotate)
	local l = label(r, text, textSize or 13, COLORS.text, px)
	l.Size = UDim2.new(1, -(px + 8), 0, px)
	l.AutomaticSize = Enum.AutomaticSize.None
	l.TextYAlignment = Enum.TextYAlignment.Center
	return r
end

---------------------------------------------------------------- ОСНОВА
local gui = new("ScreenGui", { Name = "MechanicUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })

local top = new("Frame", { Parent = gui, BackgroundColor3 = COLORS.bg, Size = UDim2.new(0, 300, 0, 44), Position = UDim2.new(0, 12, 1, -56) })
local shopLbl = new("TextLabel", { Parent = gui, BackgroundTransparency = 1, Size = UDim2.new(0, 400, 0, 24), Position = UDim2.new(0, 14, 1, -84), Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = Color3.fromRGB(255, 200, 90), TextStrokeTransparency = 0.5, TextXAlignment = Enum.TextXAlignment.Left, Text = "" })
corner(top, 10)
local cashLbl = new("TextLabel", { Parent = top, BackgroundTransparency = 1, Size = UDim2.new(0, 160, 1, 0), Position = UDim2.new(0, 12, 0, 0), Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = Color3.fromRGB(120, 230, 120), TextXAlignment = Enum.TextXAlignment.Left, Text = "💰 $0" })
local invBtn = button(top, "📦 Склад", COLORS.btn, 110, 32)
invBtn.Position = UDim2.new(1, -118, 0, 6)

local notifHolder = new("Frame", { Parent = gui, BackgroundTransparency = 1, Size = UDim2.new(0, 520, 0, 300), Position = UDim2.new(0.5, -260, 0, 10), ZIndex = 10 })
new("UIListLayout", { Parent = notifHolder, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center })
local notifCount = 0
NotifyEvent.OnClientEvent:Connect(function(text, kind)
	notifCount = notifCount + 1
	local f = new("TextLabel", {
		Parent = notifHolder, LayoutOrder = notifCount, ZIndex = 10,
		Size = UDim2.new(1, 0, 0, 34), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS[kind] or COLORS.info, BackgroundTransparency = 0.1,
		Text = text, TextWrapped = true, Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.new(1, 1, 1),
	})
	corner(f, 8)
	pad(f, 8)
	local kids = {}
	for _, c in ipairs(notifHolder:GetChildren()) do
		if c:IsA("TextLabel") then
			table.insert(kids, c)
		end
	end
	if #kids > 5 then
		kids[1]:Destroy()
	end
	task.delay(6, function()
		if f.Parent then
			f:Destroy()
		end
	end)
end)

local function cash()
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Деньги")
	return c and c.Value or 0
end

local function inv(id)
	return player:GetAttribute("Inv_" .. id) or 0
end

local function owns(id)
	return player:GetAttribute("Own_" .. id) == true
end

local function toast(text, kind)
	-- локальное уведомление (тот же вид)
	local f = new("TextLabel", {
		Parent = notifHolder, LayoutOrder = notifCount + 1, ZIndex = 10,
		Size = UDim2.new(1, 0, 0, 34), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS[kind] or COLORS.info, BackgroundTransparency = 0.1,
		Text = text, TextWrapped = true, Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.new(1, 1, 1),
	})
	notifCount = notifCount + 1
	corner(f, 8)
	pad(f, 8)
	task.delay(5, function()
		if f.Parent then
			f:Destroy()
		end
	end)
end

local function shop(action, id, qty)
	local ok, msg = ShopFunction:InvokeServer(action, id, qty)
	if msg then
		if ok then
			toast(msg, "good")
		else
			toast(msg, "bad")
		end
	end
end

---------------------------------------------------------------- КОМПЬЮТЕР
local compWin, compBody, compClose, compHead = window("Computer", "🖥 Компьютер автосервиса", UDim2.new(0, 640, 0, 520), UDim2.new(0.5, -320, 0.5, -260))
compWin.Parent = gui
local function refreshShopName()
	local n = player:GetAttribute("ShopName") or Config.DefaultShopName
	compHead.Text = "🖥 Компьютер «" .. n .. "»"
	shopLbl.Text = "🏪 " .. n
end
player:GetAttributeChangedSignal("ShopName"):Connect(refreshShopName)
refreshShopName()
compBody.Size = UDim2.new(1, -16, 1, -96)
compBody.Position = UDim2.new(0, 8, 0, 88)
local tabsRow = row(compWin, 36)
tabsRow.Position = UDim2.new(0, 10, 0, 44)
tabsRow.Size = UDim2.new(1, -20, 0, 36)

local TABS = {
	{ id = "part", name = "Запчасти" },
	{ id = "fluid", name = "Тех. жидкости" },
	{ id = "tool", name = "Инструменты" },
	{ id = "equip", name = "Оборудование" },
	{ id = "staff", name = "Персонал" },
	{ id = "donate", name = "⭐ Донат" },
}
local currentTab = "part"
local tabButtons = {}
local renderComputer

for i, t in ipairs(TABS) do
	local b = button(tabsRow, t.name, COLORS.gray, 96, 32, function()
		currentTab = t.id
		renderComputer()
	end)
	b.LayoutOrder = i
	tabButtons[t.id] = b
end

local function itemRow(it)
	local c = card(compBody)
	local head = row(c, 84)
	pcall(PartModels.viewport, it.id, head, UDim2.new(0, 84, 0, 84), true)
	local info = new("Frame", { Parent = head, BackgroundTransparency = 1, Size = UDim2.new(1, -96, 0, 84) })
	new("UIListLayout", { Parent = info, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
	label(info, it.name .. "  —  $" .. it.price, 15, COLORS.text, 18, true)
	label(info, "Для чего: " .. it.desc, 13, COLORS.dim, 16)
	local r = row(c, 32)
	if it.cat == "part" or it.cat == "fluid" then
		local st = label(r, "На складе: " .. inv(it.id), 13, COLORS.text, 30)
		st.Size = UDim2.new(0, 150, 0, 30)
		st.AutomaticSize = Enum.AutomaticSize.None
		st.TextYAlignment = Enum.TextYAlignment.Center
		button(r, "Заказать x1", COLORS.btn, 120, 30, function()
			shop("buy", it.id, 1)
		end)
		button(r, "x5 ($" .. it.price * 5 .. ")", COLORS.btn, 120, 30, function()
			shop("buy", it.id, 5)
		end)
	else
		if owns(it.id) then
			button(r, "✔ Куплено", COLORS.good, 140, 30)
		else
			button(r, "Купить за $" .. it.price, COLORS.btn, 160, 30, function()
				shop("buy", it.id, 1)
			end)
		end
	end
end

renderComputer = function()
	if not compWin.Visible then
		return
	end
	for id, b in pairs(tabButtons) do
		if id == currentTab then
			b.BackgroundColor3 = COLORS.btn
		else
			b.BackgroundColor3 = COLORS.gray
		end
	end
	local y = compBody.CanvasPosition
	clear(compBody)
	if currentTab == "part" or currentTab == "fluid" then
		local note = "🚚 Доставка заказа: " .. Config.DeliveryTime .. " сек. Администратор заказывает мгновенно и на 10% дешевле."
		if player:GetAttribute("Hire_admin") then
			note = "🧑‍💼 Администратор на месте: доставка мгновенная, скидка 10%."
		end
		label(compBody, note, 13, COLORS.warn, 18, true)
	end
	if currentTab == "staff" then
		label(compBody, "Работники берут детали со склада и чинят сами. Зарплаты нет — платите только за найм.", 13, COLORS.warn, 18, true)
		for _, w in ipairs(Config.Workers) do
			local c = card(compBody)
			label(c, w.name .. "  —  найм $" .. w.hire .. ", без зарплаты", 15, COLORS.text, 18, true)
			label(c, w.desc, 13, COLORS.dim, 16)
			local r = row(c, 32)
			if player:GetAttribute("Hire_" .. w.id) then
				button(r, "Уволить", COLORS.bad, 120, 30, function()
					shop("fire", w.id)
				end)
			else
				button(r, "Нанять за $" .. w.hire, COLORS.good, 160, 30, function()
					shop("hire", w.id)
				end)
			end
		end
	elseif currentTab == "donate" then
		for _, key in ipairs({ "x2cash", "x2speed" }) do
			local gp = Config.GamePasses[key]
			local c = card(compBody, Color3.fromRGB(70, 55, 20))
			label(c, "⭐ " .. gp.name, 16, Color3.fromRGB(255, 215, 90), 20, true)
			label(c, gp.desc, 13, COLORS.text, 16)
			local r = row(c, 32)
			if player:GetAttribute("Pass_" .. key) then
				button(r, "✔ Активно", COLORS.good, 140, 30)
			elseif (gp.id or 0) <= 0 and not game:GetService("RunService"):IsStudio() then
				button(r, "Скоро", Color3.fromRGB(90, 90, 90), 140, 30)
			else
				button(r, "Купить", COLORS.warn, 140, 30, function()
					shop("pass", key)
				end)
			end
		end
	else
		for _, it in ipairs(Config.Items) do
			if it.cat == currentTab then
				itemRow(it)
			end
		end
	end
	compBody.CanvasPosition = y
end

compClose.MouseButton1Click:Connect(function()
	compWin.Visible = false
end)

---------------------------------------------------------------- СКЛАД
local invWin, invBody, invClose = window("Inventory", "📦 Склад и инструменты", UDim2.new(0, 380, 0, 460), UDim2.new(0, 12, 0.5, -260))
invWin.Parent = gui

local function renderInventory()
	if not invWin.Visible then
		return
	end
	clear(invBody)
	label(invBody, "Запчасти и жидкости:", 15, COLORS.warn, 18, true)
	local any = false
	for _, it in ipairs(Config.Items) do
		if (it.cat == "part" or it.cat == "fluid") and inv(it.id) > 0 then
			iconLine(invBody, it.id, it.name .. ": " .. inv(it.id) .. " шт.", 44, false, 14)
			any = true
		end
	end
	if not any then
		label(invBody, "пусто — закажите в компьютере", 14, COLORS.dim)
	end
	label(invBody, "Инструменты и оборудование:", 15, COLORS.warn, 18, true)
	any = false
	for _, it in ipairs(Config.Items) do
		if (it.cat == "tool" or it.cat == "equip") and owns(it.id) then
			iconLine(invBody, it.id, "✔ " .. it.name, 44, false, 14)
			any = true
		end
	end
	if not any then
		label(invBody, "пока только обычный ключ", 14, COLORS.dim)
	end
end

invBtn.MouseButton1Click:Connect(function()
	invWin.Visible = not invWin.Visible
	renderInventory()
end)
invClose.MouseButton1Click:Connect(function()
	invWin.Visible = false
end)

---------------------------------------------------------------- ПАНЕЛЬ РЕМОНТА
local jobWin, jobBody, jobClose, jobHead = window("Job", "🔧 Ремонт", UDim2.new(0, 440, 0, 560), UDim2.new(1, -452, 0.5, -280))
jobWin.Parent = gui
local snap = nil
local renderJob
local boltMode = "unscrew"
local bars = {}

local function act(action, faultIdx, arg)
	if snap then
		JobActionEvent:FireServer(action, snap.bay, faultIdx, arg)
	end
end

local function progressBar(parent, remaining, total, text)
	local holder = new("Frame", { Parent = parent, BackgroundColor3 = COLORS.bg, Size = UDim2.new(1, 0, 0, 24) })
	corner(holder, 6)
	local fill = new("Frame", { Parent = holder, BackgroundColor3 = COLORS.warn, Size = UDim2.new(0, 0, 1, 0) })
	corner(fill, 6)
	new("TextLabel", { Parent = holder, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = text or "", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.new(1, 1, 1), ZIndex = 2 })
	table.insert(bars, { fill = fill, endAt = os.clock() + remaining, total = math.max(total or 1, 0.1) })
end

RunService.Heartbeat:Connect(function()
	for _, b in ipairs(bars) do
		if b.fill.Parent then
			local left = math.max(0, b.endAt - os.clock())
			b.fill.Size = UDim2.new(1 - left / b.total, 0, 1, 0)
		end
	end
end)

local BOLT_ICON = { ok = "🔩", rusty = "🟤", soaked = "💧", broken = "💥", done = "✔" }
local BOLT_COLOR = { ok = COLORS.gray, rusty = Color3.fromRGB(150, 80, 30), soaked = COLORS.info, broken = COLORS.bad, done = COLORS.good }

local function renderStep(c, f)
	local st = f.step
	label(c, "Шаг " .. f.stepIdx .. "/" .. f.stepCount .. ": " .. st.label, 14, COLORS.warn, 18, true)
	label(c, "📍 Где: " .. st.atName, 13, COLORS.dim, 16)
	for _, t in ipairs(st.tools) do
		local mark = "❌ "
		if owns(t.id) then
			mark = "✅ "
		end
		iconLine(c, t.id, mark .. t.name, 36, false)
	end
	for _, it in ipairs(st.items) do
		local have = inv(it.id)
		local mark = "❌ "
		if have >= it.need then
			mark = "✅ "
		end
		iconLine(c, it.id, mark .. it.name .. " (" .. have .. "/" .. it.need .. ")", 36, false)
	end

	if f.busyRemaining and f.busyRemaining > 0 then
		progressBar(c, f.busyRemaining - (os.clock() - snap._recv), f.busyTotal, f.busyLabel)
		return
	end

	if st.type == "bolts" and f.bolts then
		label(c, "Режим (выберите, потом нажмите на болт):", 13, COLORS.dim, 16)
		local modes = row(c, 32)
		local keyName = "🔧 Ключ"
		if owns("impact") then
			keyName = "⚡ Гайковёрт"
		end
		local defs = {
			{ id = "unscrew", name = keyName },
			{ id = "wd40", name = "🧴 WD-40 (" .. inv("wd40") .. ")" },
			{ id = "hammer", name = "🔨 Молоток" },
		}
		for i, m in ipairs(defs) do
			local col = COLORS.gray
			if boltMode == m.id then
				col = COLORS.btn
			end
			local b = button(modes, m.name, col, 128, 30, function()
				boltMode = m.id
				renderJob()
			end)
			b.LayoutOrder = i
		end
		local grid = new("Frame", { Parent = c, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
		new("UIGridLayout", { Parent = grid, CellSize = UDim2.new(0, 46, 0, 46), CellPadding = UDim2.new(0, 6, 0, 6), SortOrder = Enum.SortOrder.LayoutOrder })
		for k, state in ipairs(f.bolts) do
			local b = button(grid, BOLT_ICON[state] or "?", BOLT_COLOR[state] or COLORS.gray, 46, 46, function()
				act("bolt", f.idx, { bolt = k, method = boltMode })
			end)
			b.TextSize = 22
			b.LayoutOrder = k
		end
		label(c, "🔩 обычный  🟤 ржавый (может сорваться, 15%)  💧 обработан  💥 сорван — нужен экстрактор", 12, COLORS.dim, 16)
	elseif st.type == "action" then
		local r = row(c, 34)
		button(r, "▶ " .. st.label, COLORS.good, 300, 32, function()
			act("do", f.idx)
		end)
	elseif st.type == "torque" then
		local r = row(c, 34)
		button(r, "🔧 Динамометрический ключ", COLORS.good, 220, 32, function()
			act("do", f.idx, "wrench")
		end)
		button(r, "👀 На глаз (риск)", COLORS.bad, 170, 32, function()
			act("do", f.idx, "eye")
		end)
	elseif st.type == "grease" then
		label(c, "Медная смазка защищает от закисания: +15% к оплате", 13, COLORS.dim, 16)
		local r = row(c, 34)
		button(r, "🟠 Нанести (" .. inv("copper_grease") .. ")", COLORS.good, 200, 32, function()
			act("do", f.idx, "apply")
		end)
		button(r, "Пропустить", COLORS.gray, 140, 32, function()
			act("do", f.idx, "skip")
		end)
	end
end

renderJob = function()
	bars = {}
	if not jobWin.Visible or not snap then
		return
	end
	local y = jobBody.CanvasPosition
	clear(jobBody)
	if not snap.hasJob then
		jobHead.Text = "🔧 Пост " .. (snap.bayLocal or snap.bay)
		label(jobBody, "Машины нет — ждём следующего клиента...", 15, COLORS.dim)
		return
	end
	jobHead.Text = "🔧 " .. snap.car .. " (пост " .. (snap.bayLocal or snap.bay) .. ")"

	if snap.missing and #snap.missing > 0 then
		local c = card(jobBody, Color3.fromRGB(60, 50, 90))
		local names = {}
		for _, m in ipairs(snap.missing) do
			table.insert(names, m.name .. " x" .. m.n)
		end
		label(c, "📦 Не хватает на складе: " .. table.concat(names, ", "), 13, COLORS.text)
		if snap.hasAdmin then
			local r = row(c, 34)
			button(r, "🧑‍💼 Купить нужные запчасти ($" .. (snap.missingCost or 0) .. ")", COLORS.good, 380, 32, function()
				shop("buyNeeded", tostring(snap.bay))
			end)
		else
			label(c, "Наймите администратора — он докупит всё одной кнопкой прямо у машины и выдаст мгновенно.", 12, COLORS.dim)
		end
	end

	if snap.hasHidden then
		local c = card(jobBody, Color3.fromRGB(90, 60, 15))
		label(c, "⚠ CHECK ENGINE — неизвестная ошибка!", 15, Color3.fromRGB(255, 200, 60), 18, true)
		label(c, "Подключите автосканер OBD-II, чтобы узнать, что чинить.", 13, COLORS.text, 16)
		if snap.scanRemaining > 0 then
			progressBar(c, snap.scanRemaining - (os.clock() - snap._recv), snap.scanTotal, "Читаем ошибки...")
		else
			local r = row(c, 34)
			local txt = "🔍 Сканировать"
			if not owns("scanner") then
				txt = "🔍 Сканировать (нет сканера ❌)"
			end
			button(r, txt, COLORS.warn, 300, 32, function()
				act("scan")
			end)
		end
	end

	for _, f in ipairs(snap.faults) do
		if f.revealed then
			local col = COLORS.card
			if f.done then
				col = Color3.fromRGB(35, 70, 45)
			end
			local c = card(jobBody, col)
			local title = f.name
			if f.code then
				title = "[" .. f.code .. "] " .. title
			end
			if f.done then
				title = "✅ " .. title
			end
			label(c, title, 15, COLORS.text, 18, true)
			if not f.done then
				local info = "Оплата: $" .. (f.reward or 0)
				if f.variantName then
					info = info .. "  •  " .. f.variantName
				end
				if f.liftText then
					info = info .. "  •  " .. f.liftText
				end
				label(c, info, 13, COLORS.dim, 16)
				if f.lockedName and not f.mine then
					label(c, "🔒 Занимается: " .. f.lockedName, 13, COLORS.warn, 16)
					if f.busyRemaining and f.busyRemaining > 0 then
						progressBar(c, f.busyRemaining - (os.clock() - snap._recv), f.busyTotal, f.busyLabel)
					end
				elseif f.mine and f.step then
					renderStep(c, f)
					local r = row(c, 30)
					button(r, "Бросить ремонт", COLORS.gray, 140, 26, function()
						act("abandon", f.idx)
					end)
				elseif f.variants then
					label(c, "Выберите способ ремонта:", 13, COLORS.text, 16)
					for _, v in ipairs(f.variants) do
						local r = row(c, 34)
						button(r, v.name .. " — $" .. v.reward, COLORS.good, 380, 32, function()
							act("start", f.idx, v.id)
						end)
					end
				else
					local r = row(c, 34)
					local txt = "▶ Начать ремонт"
					if f.mine then
						txt = "▶ Продолжить"
					end
					button(r, txt, COLORS.good, 200, 32, function()
						act("start", f.idx)
					end)
				end
			end
		end
	end

	local r = row(jobBody, 34)
	button(r, "🚫 Отказать клиенту", COLORS.bad, 200, 30, function()
		act("refuse")
	end)
	jobBody.CanvasPosition = y
end

JobUpdateEvent.OnClientEvent:Connect(function(s)
	s._recv = os.clock()
	snap = s
	renderJob()
end)

jobClose.MouseButton1Click:Connect(function()
	jobWin.Visible = false
end)
jobWin:GetPropertyChangedSignal("Visible"):Connect(function()
	if not jobWin.Visible then
		JobActionEvent:FireServer("close")
	end
end)

---------------------------------------------------------------- ПАРКОВКА
local parkWin, parkBody, parkClose, parkHead = window("Parking", "🅿 Машина клиента", UDim2.new(0, 420, 0, 430), UDim2.new(0.5, -210, 0.5, -215))
parkWin.Parent = gui
parkClose.MouseButton1Click:Connect(function()
	parkWin.Visible = false
end)
local function renderParking(data)
	clear(parkBody)
	parkHead.Text = "🅿 " .. tostring(data.car or "Машина") .. " (P" .. tostring(data.spot) .. ")"
	local c = card(parkBody, COLORS.card)
	label(c, "Неисправности:", 15, COLORS.text, 18, true)
	for _, n in ipairs(data.faults or {}) do
		label(c, "• " .. n, 13, COLORS.dim, 16)
	end
	if data.tutorial then
		label(parkBody, "👴 Михалыч: «Гони на пост " .. tostring(data.pitBay) .. " — там смотровая яма, масло меняют снизу»", 13, COLORS.warn)
	end
	label(parkBody, "Сесть за руль и отогнать на пост:", 15, COLORS.text, 18, true)
	for _, b in ipairs(data.bays or {}) do
		local r = row(parkBody, 36)
		local txt = "🚗 Пост " .. b.idx .. (b.pit and " · смотровая яма" or "") .. (b.free and "" or " — занят")
		button(r, txt, b.free and COLORS.good or COLORS.gray, 340, 32, function()
			if not b.free then
				toast("Этот пост занят", "bad")
				return
			end
			parkWin.Visible = false
			ParkingEvent:FireServer("drive", data.spot, b.idx)
		end)
	end
end

---------------------------------------------------------------- БАНК
local bankWin, bankBody, bankClose = window("Bank", "🏦 Банк · кредит без процентов", UDim2.new(0, 420, 0, 440), UDim2.new(0.5, -210, 0.5, -220))
bankWin.Parent = gui
bankClose.MouseButton1Click:Connect(function()
	bankWin.Visible = false
end)
local function renderBank()
	if not bankWin.Visible then
		return
	end
	clear(bankBody)
	local debt = player:GetAttribute("Loan") or 0
	label(bankBody, "Ваш долг: $" .. debt .. "   (лимит $" .. (Config.LoanMax or 1500) .. ")", 16, debt > 0 and COLORS.warn or COLORS.good, 22, true)
	label(bankBody, "Процентов нет. Возвращаете сами, когда удобно.", 13, COLORS.dim)
	for _, a in ipairs(Config.Loans or {}) do
		local r = row(bankBody, 36)
		local can = debt + a <= (Config.LoanMax or 1500)
		button(r, "💵 Взять $" .. a, can and COLORS.btn or COLORS.gray, 220, 32, function()
			shop("loan", tostring(a))
		end)
	end
	if debt > 0 then
		local r = row(bankBody, 36)
		button(r, "✅ Погасить весь долг ($" .. debt .. ")", COLORS.good, 300, 32, function()
			shop("repay", tostring(debt))
		end)
		local r2 = row(bankBody, 36)
		button(r2, "Погасить $100", COLORS.good, 220, 32, function()
			shop("repay", "100")
		end)
	end
end

local openedAt = {}
local function rootPos()
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return r and r.Position or nil
end

OpenUIEvent.OnClientEvent:Connect(function(name, data)
	if name == "computer" then
		compWin.Visible = true
		renderComputer()
	elseif name == "job" then
		jobWin.Visible = true
		renderJob()
	elseif name == "bank" then
		openedAt.bank = rootPos()
		bankWin.Visible = true
		renderBank()
	elseif name == "parking" and type(data) == "table" then
		openedAt.park = rootPos()
		parkWin.Visible = true
		renderParking(data)
	end
end)

-- отошли от машины / компьютера / банка — окно закрывается само
task.spawn(function()
	while true do
		task.wait(0.3)
		local pos = rootPos()
		if pos then
			if jobWin.Visible and snap and typeof(snap.near) == "Vector3" and (pos - snap.near).Magnitude > 40 then
				jobWin.Visible = false
			end
			local cp = player:GetAttribute("ComputerPos")
			if compWin.Visible and typeof(cp) == "Vector3" and (pos - cp).Magnitude > 20 then
				compWin.Visible = false
			end
			if bankWin.Visible and openedAt.bank and (pos - openedAt.bank).Magnitude > 20 then
				bankWin.Visible = false
			end
			if parkWin.Visible and openedAt.park and (pos - openedAt.park).Magnitude > 20 then
				parkWin.Visible = false
			end
		end
	end
end)

---------------------------------------------------------------- ЧАСЫ, ПОГОДА, МУЗЫКА
local clockLbl = new("TextLabel", { Parent = gui, BackgroundColor3 = COLORS.bg, BackgroundTransparency = 0.2, Size = UDim2.new(0, 250, 0, 30), Position = UDim2.new(1, -262, 0, 10), Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = COLORS.text, Text = "" })
corner(clockLbl, 8)
local musicBtn = button(gui, "🎵 Музыка: вкл", COLORS.gray, 160, 28)
musicBtn.Position = UDim2.new(1, -172, 0, 46)
local WEATHER = { clear = "☀ Ясно", cloudy = "☁ Облачно", rain = "🌧 Дождь" }

local music = Instance.new("Sound")
music.Name = "BackgroundMusic"
music.Volume = Config.MusicVolume or 0.25
music.Parent = SoundService
local musicOn = true
local tracks = Config.Music or {}
if #tracks == 0 then
	musicBtn.Visible = false
end
task.spawn(function()
	local i = 0
	while #tracks > 0 do
		if musicOn then
			i = i % #tracks + 1
			music.SoundId = tracks[i]
			music:Play()
			local t0 = os.clock()
			repeat
				task.wait(1)
			until not music.IsPlaying and os.clock() - t0 > 3
		else
			task.wait(1)
		end
	end
end)
musicBtn.MouseButton1Click:Connect(function()
	musicOn = not musicOn
	if musicOn then
		music:Resume()
	else
		music:Pause()
	end
	musicBtn.Text = musicOn and "🎵 Музыка: вкл" or "🔇 Музыка: выкл"
end)

-- дождь: частицы над камерой + звук
local rainPart = Instance.new("Part")
rainPart.Name = "RainEmitter"
rainPart.Anchored = true
rainPart.CanCollide = false
rainPart.CanQuery = false
rainPart.CanTouch = false
rainPart.Transparency = 1
rainPart.Size = Vector3.new(140, 1, 140)
rainPart.Parent = workspace
local rain = Instance.new("ParticleEmitter")
rain.Color = ColorSequence.new(Color3.fromRGB(190, 210, 235))
rain.LightEmission = 0.2
rain.Transparency = NumberSequence.new(0.35)
rain.Size = NumberSequence.new(0.12)
rain.Squash = NumberSequence.new(2.5)
rain.Lifetime = NumberRange.new(0.9, 1.2)
rain.Speed = NumberRange.new(70, 80)
rain.EmissionDirection = Enum.NormalId.Bottom
rain.SpreadAngle = Vector2.new(3, 3)
rain.Rate = 0
rain.Parent = rainPart
local rainSnd = Instance.new("Sound")
rainSnd.Looped = true
rainSnd.Volume = 0.35
rainSnd.SoundId = Config.RainSound or ""
rainSnd.Parent = SoundService

local isRaining = false
local rainParams = RaycastParams.new()
rainParams.FilterType = Enum.RaycastFilterType.Exclude
RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if cam then
		local pos = cam.CFrame.Position
		rainPart.CFrame = CFrame.new(pos + Vector3.new(0, 45, 0))
		-- частицы не сталкиваются с деталями, поэтому под крышей дождь выключаем сами
		local ignore = { rainPart }
		if player.Character then
			table.insert(ignore, player.Character)
		end
		rainParams.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(pos, Vector3.new(0, 80, 0), rainParams)
		local underRoof = hit ~= nil and hit.Instance.Transparency < 0.9
		rain.Rate = (isRaining and not underRoof) and 900 or 0
		rainSnd.Volume = underRoof and 0.12 or 0.35
	end
end)

task.spawn(function()
	while true do
		local clk = workspace:GetAttribute("Clock") or 8
		local h = math.floor(clk)
		local m = math.floor((clk - h) * 60)
		local w = workspace:GetAttribute("Weather") or "clear"
		local night = workspace:GetAttribute("Night")
		clockLbl.Text = string.format("%s %02d:%02d · день %d · %s", night and "🌙" or "🕗", h, m, workspace:GetAttribute("Day") or 1, WEATHER[w] or w)
		local raining = (w == "rain")
		isRaining = raining
		if raining and rainSnd.SoundId ~= "" and not rainSnd.IsPlaying then
			rainSnd:Play()
		elseif not raining and rainSnd.IsPlaying then
			rainSnd:Stop()
		end
		task.wait(0.5)
	end
end)

---------------------------------------------------------------- ОБНОВЛЕНИЕ
local pending = false
local function refreshAll()
	if pending then
		return
	end
	pending = true
	task.delay(0.15, function()
		pending = false
		renderComputer()
		renderInventory()
		renderJob()
		renderBank()
	end)
end
player.AttributeChanged:Connect(refreshAll)

task.spawn(function()
	local ls = player:WaitForChild("leaderstats")
	local c = ls:WaitForChild("Деньги")
	local function upd()
		cashLbl.Text = "💰 $" .. c.Value
	end
	upd()
	c.Changed:Connect(function()
		upd()
		refreshAll()
	end)
end)
