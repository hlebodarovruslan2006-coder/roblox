-- Story.client.lua — катсцены, диалоги, обучение, название мастерской
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local Config = require(ReplicatedStorage:WaitForChild("MechanicConfig"))
local remotes = ReplicatedStorage:WaitForChild("MechanicRemotes")
local StoryEvent = remotes:WaitForChild("Story")

local gui = Instance.new("ScreenGui")
gui.Name = "StoryGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(o, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = o
end
local function stroke(o, col, th)
	local s = Instance.new("UIStroke")
	s.Color = col or Color3.fromRGB(255, 190, 70)
	s.Thickness = th or 2
	s.Parent = o
end
local function make(class, props)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	return o
end
local function tween(o, t, props, style)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), props)
	tw:Play()
	return tw
end

---------------------------------------------------------------- КИНО-ПОЛОСЫ И СУБТИТРЫ
local topBar = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), ZIndex = 50, Parent = gui })
local botBar = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 0), ZIndex = 50, Parent = gui })
local fade = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 60, Parent = gui })
local subtitle = make("TextLabel", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.new(0.8, 0, 0, 70), Font = Enum.Font.GothamMedium, TextSize = 24, TextWrapped = true,
	TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.5, Text = "", ZIndex = 55, Parent = gui,
})
local chapter = make("TextLabel", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22),
	Size = UDim2.new(0.8, 0, 0, 50), Font = Enum.Font.GothamBlack, TextSize = 34, TextColor3 = Color3.fromRGB(255, 200, 90),
	TextStrokeTransparency = 0.4, Text = "", TextTransparency = 1, ZIndex = 55, Parent = gui,
})
local skipBtn = make("TextButton", {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -130), Size = UDim2.new(0, 170, 0, 40),
	BackgroundColor3 = Color3.fromRGB(30, 30, 35), BackgroundTransparency = 0.2, TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold, TextSize = 18, Text = "Пропустить ⏭", Visible = false, ZIndex = 70, Parent = gui,
})
corner(skipBtn, 8)

local inCutscene = false
local skipRequested = false
skipBtn.MouseButton1Click:Connect(function()
	skipRequested = true
end)

local function letterbox(on)
	local h = on and 0.12 or 0
	tween(topBar, 0.6, { Size = UDim2.new(1, 0, h, 0) })
	tween(botBar, 0.6, { Size = UDim2.new(1, 0, h, 0) })
end

local function hideHud(hide)
	local hud = player.PlayerGui:FindFirstChild("MechanicUI")
	if hud and hud:IsA("ScreenGui") then
		hud.Enabled = not hide
	end
end

-- печатающийся текст; возвращает false, если нажали «Пропустить»
local function typeText(label, text, speed, stopFlag)
	label.Text = text
	label.MaxVisibleGraphemes = 0
	local total = utf8.len(text) or #text
	for i = 1, total do
		if stopFlag and stopFlag() then
			label.MaxVisibleGraphemes = -1
			return false
		end
		label.MaxVisibleGraphemes = i
		task.wait(speed or 0.03)
	end
	label.MaxVisibleGraphemes = -1
	return true
end

local function shot(fromCF, toCF, dur)
	camera.CFrame = fromCF
	local cv = Instance.new("CFrameValue")
	cv.Value = fromCF
	local conn = cv.Changed:Connect(function(v)
		camera.CFrame = v
	end)
	local tw = TweenService:Create(cv, TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Value = toCF })
	tw:Play()
	return function()
		tw:Cancel()
		conn:Disconnect()
		cv:Destroy()
	end
end

local function look(pos, target)
	return CFrame.lookAt(pos, target)
end

local function beginCutscene()
	inCutscene = true
	skipRequested = false
	hideHud(true)
	camera.CameraType = Enum.CameraType.Scriptable
	letterbox(true)
	skipBtn.Visible = true
end

local function endCutscene()
	tween(fade, 0.4, { BackgroundTransparency = 0 }).Completed:Wait()
	camera.CameraType = Enum.CameraType.Custom
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		camera.CameraSubject = hum
	end
	subtitle.Text = ""
	chapter.TextTransparency = 1
	skipBtn.Visible = false
	letterbox(false)
	hideHud(false)
	tween(fade, 0.6, { BackgroundTransparency = 1 })
	inCutscene = false
end

local function playIntro(data)
	if inCutscene then
		return
	end
	local O = data.origin or Vector3.new()
	local lines = data.lines or Config.IntroLines
	local shots = {
		{ look(O + Vector3.new(55, 28, 94), O + Vector3.new(0, 6, 30)), look(O + Vector3.new(30, 16, 82), O + Vector3.new(0, 6, 40)) }, -- v4: камера между улицей и фасадом, не сквозь дома
		{ look(O + Vector3.new(-12, 6, 80), O + Vector3.new(0, 12, 52)), look(O + Vector3.new(10, 7, 68), O + Vector3.new(0, 11, 52)) },
		{ look(O + Vector3.new(28, 9, 49), O + Vector3.new(-36, 4, 36)), look(O + Vector3.new(18, 8, 44), O + Vector3.new(-30, 4, 34)) },
		{ look(O + Vector3.new(-20, 12, 36), O + Vector3.new(0, 3, -20)), look(O + Vector3.new(20, 10, 34), O + Vector3.new(0, 3, -25)) },
	}
	beginCutscene()
	fade.BackgroundTransparency = 0
	tween(fade, 1.2, { BackgroundTransparency = 1 })
	chapter.Text = "Глава 1. Старая мастерская"
	tween(chapter, 1, { TextTransparency = 0 })
	for i, line in ipairs(lines) do
		if skipRequested then
			break
		end
		local sh = shots[((i - 1) % #shots) + 1]
		local stop = shot(sh[1], sh[2], 7)
		typeText(subtitle, line, 0.035, function()
			return skipRequested
		end)
		local t0 = os.clock()
		while os.clock() - t0 < 2.6 and not skipRequested do
			task.wait(0.05)
		end
		stop()
		if i == 1 then
			tween(chapter, 1, { TextTransparency = 1 })
		end
	end
	endCutscene()
end

local function playNamed(data)
	local O = data.origin or Vector3.new()
	beginCutscene()
	skipBtn.Visible = false
	local stop = shot(look(O + Vector3.new(-25, 5, 92), O + Vector3.new(0, 12, 52)), look(O + Vector3.new(0, 9, 74), O + Vector3.new(0, 12, 52)), 6)
	chapter.Text = "«" .. tostring(data.name) .. "» — открыта!"
	tween(chapter, 0.8, { TextTransparency = 0 })
	-- конфетти
	local cols = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 210, 60), Color3.fromRGB(80, 200, 255), Color3.fromRGB(120, 255, 120), Color3.fromRGB(230, 120, 255) }
	for _ = 1, 70 do
		local c = make("Frame", {
			BackgroundColor3 = cols[math.random(1, #cols)], BorderSizePixel = 0, Rotation = math.random(0, 360),
			Size = UDim2.new(0, math.random(8, 14), 0, math.random(14, 22)),
			Position = UDim2.new(math.random(), 0, -0.05, 0), ZIndex = 56, Parent = gui,
		})
		local tw = tween(c, math.random(25, 45) / 10, { Position = UDim2.new(c.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1.1, 0), Rotation = c.Rotation + math.random(180, 720) }, Enum.EasingStyle.Linear)
		tw.Completed:Connect(function()
			c:Destroy()
		end)
	end
	typeText(subtitle, "Новая вывеска загорелась. Клиенты уже едут!", 0.03)
	task.wait(3)
	stop()
	endCutscene()
end

---------------------------------------------------------------- ДИАЛОГ
local openNameUI -- объявлена ниже
local dlg = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.new(0, 640, 0, 150),
	BackgroundColor3 = Color3.fromRGB(28, 24, 20), BackgroundTransparency = 0.05, Visible = false, ZIndex = 40, Parent = gui,
})
corner(dlg, 14)
stroke(dlg)
local dlgFace = make("TextLabel", { BackgroundColor3 = Color3.fromRGB(70, 55, 40), Position = UDim2.new(0, 14, 0, 14), Size = UDim2.new(0, 84, 0, 84), Text = "👴", TextSize = 56, Font = Enum.Font.GothamBold, ZIndex = 41, Parent = dlg })
corner(dlgFace, 42)
local dlgName = make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 112, 0, 10), Size = UDim2.new(1, -124, 0, 26), Font = Enum.Font.GothamBlack, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 200, 90), Text = "", ZIndex = 41, Parent = dlg })
local dlgText = make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 112, 0, 38), Size = UDim2.new(1, -124, 0, 70), Font = Enum.Font.Gotham, TextSize = 19, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.new(1, 1, 1), Text = "", ZIndex = 41, Parent = dlg })
local dlgNext = make("TextButton", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -12), Size = UDim2.new(0, 130, 0, 34), BackgroundColor3 = Color3.fromRGB(255, 170, 50), Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Color3.fromRGB(30, 20, 10), Text = "Далее ▶", ZIndex = 41, Parent = dlg })
corner(dlgNext, 8)

local dlgQueue = nil
local dlgIdx = 0
local dlgTyping = false
local dlgSkipType = false

local function showLine()
	local line = dlgQueue.lines[dlgIdx]
	dlgNext.Text = (dlgIdx >= #dlgQueue.lines) and "Понял ✔" or "Далее ▶"
	dlgTyping = true
	dlgSkipType = false
	typeText(dlgText, line, 0.022, function()
		return dlgSkipType
	end)
	dlgTyping = false
end

local function openDialog(data)
	dlgQueue = data
	dlgIdx = 1
	dlgName.Text = data.speaker or ""
	dlg.Visible = true
	dlg.Position = UDim2.new(0.5, 0, 1, 180)
	tween(dlg, 0.35, { Position = UDim2.new(0.5, 0, 1, -24) }, Enum.EasingStyle.Back)
	task.spawn(showLine)
end

dlgNext.MouseButton1Click:Connect(function()
	if not dlgQueue then
		return
	end
	if dlgTyping then
		dlgSkipType = true
		return
	end
	if dlgIdx < #dlgQueue.lines then
		dlgIdx = dlgIdx + 1
		task.spawn(showLine)
	else
		local after = dlgQueue.after
		dlgQueue = nil
		dlg.Visible = false
		if after == "name" then
			openNameUI(true)
		end
	end
end)

---------------------------------------------------------------- НАЗВАНИЕ МАСТЕРСКОЙ
local nameFrame = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 460, 0, 250),
	BackgroundColor3 = Color3.fromRGB(26, 28, 34), Visible = false, ZIndex = 45, Parent = gui,
})
corner(nameFrame, 14)
stroke(nameFrame)
local nameTitle = make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 14), Size = UDim2.new(1, 0, 0, 34), Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = Color3.fromRGB(255, 200, 90), Text = "🪧 Название мастерской", ZIndex = 46, Parent = nameFrame })
make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 20, 0, 50), Size = UDim2.new(1, -40, 0, 40), Font = Enum.Font.Gotham, TextSize = 15, TextWrapped = true, TextColor3 = Color3.fromRGB(200, 200, 210), Text = "Имя появится на вывеске, воротах, стойке, форме работников и в компьютере. До " .. Config.ShopNameMax .. " символов.", ZIndex = 46, Parent = nameFrame })
local nameBox = make("TextBox", { Position = UDim2.new(0, 20, 0, 100), Size = UDim2.new(1, -40, 0, 46), BackgroundColor3 = Color3.fromRGB(45, 48, 58), TextColor3 = Color3.new(1, 1, 1), PlaceholderText = "Например: АвтоДок у Руслана", PlaceholderColor3 = Color3.fromRGB(130, 130, 140), Font = Enum.Font.GothamBold, TextSize = 20, ClearTextOnFocus = false, Text = "", ZIndex = 46, Parent = nameFrame })
corner(nameBox, 8)
local nameCount = make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 20, 0, 148), Size = UDim2.new(1, -40, 0, 20), Font = Enum.Font.Gotham, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(160, 160, 170), Text = "0/" .. Config.ShopNameMax, ZIndex = 46, Parent = nameFrame })
local nameOk = make("TextButton", { Position = UDim2.new(0, 20, 1, -64), Size = UDim2.new(0.5, -26, 0, 46), BackgroundColor3 = Color3.fromRGB(70, 190, 90), Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = Color3.new(1, 1, 1), Text = "✔ Готово", ZIndex = 46, Parent = nameFrame })
corner(nameOk, 8)
local nameCancel = make("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 1, -64), Size = UDim2.new(0.5, -26, 0, 46), BackgroundColor3 = Color3.fromRGB(90, 90, 100), Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = Color3.new(1, 1, 1), Text = "Отмена", ZIndex = 46, Parent = nameFrame })
corner(nameCancel, 8)

nameBox:GetPropertyChangedSignal("Text"):Connect(function()
	local t = nameBox.Text
	if (utf8.len(t) or #t) > Config.ShopNameMax then
		local cut = utf8.offset(t, Config.ShopNameMax + 1)
		if cut then
			nameBox.Text = string.sub(t, 1, cut - 1)
			return
		end
	end
	nameCount.Text = (utf8.len(t) or #t) .. "/" .. Config.ShopNameMax
end)

local nameRequired = false
openNameUI = function(required)
	nameRequired = required and true or false
	nameCancel.Visible = not nameRequired
	nameOk.Size = nameRequired and UDim2.new(1, -40, 0, 46) or UDim2.new(0.5, -26, 0, 46)
	nameTitle.Text = nameRequired and "🪧 Придумайте название!" or "✏ Переименовать мастерскую"
	nameBox.Text = player:GetAttribute("ShopName") or ""
	nameFrame.Visible = true
	nameFrame.Size = UDim2.new(0, 400, 0, 210)
	tween(nameFrame, 0.25, { Size = UDim2.new(0, 460, 0, 250) }, Enum.EasingStyle.Back)
	nameBox:CaptureFocus()
end

nameOk.MouseButton1Click:Connect(function()
	local t = nameBox.Text
	if string.match(t, "%S") == nil then
		nameBox.PlaceholderText = "Введите хотя бы один символ"
		return
	end
	StoryEvent:FireServer("setName", t)
	nameFrame.Visible = false
end)
nameCancel.MouseButton1Click:Connect(function()
	nameFrame.Visible = false
end)

-- кнопка переименования (после обучения)
local renameBtn = make("TextButton", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.new(0, 150, 0, 36), BackgroundColor3 = Color3.fromRGB(40, 42, 50), BackgroundTransparency = 0.15, Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.fromRGB(255, 200, 90), Text = "✏ Название", Visible = false, ZIndex = 30, Parent = gui })
corner(renameBtn, 8)
renameBtn.MouseButton1Click:Connect(function()
	openNameUI(false)
end)

---------------------------------------------------------------- ЗАДАНИЕ ОБУЧЕНИЯ + УКАЗАТЕЛЬ
local objFrame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 58), Size = UDim2.new(0, 520, 0, 74), BackgroundColor3 = Color3.fromRGB(24, 26, 32), BackgroundTransparency = 0.1, Visible = false, ZIndex = 30, Parent = gui })
corner(objFrame, 12)
stroke(objFrame, Color3.fromRGB(90, 170, 255), 2)
local objHead = make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, 6), Size = UDim2.new(1, -28, 0, 20), Font = Enum.Font.GothamBlack, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(120, 190, 255), Text = "", ZIndex = 31, Parent = objFrame })
local objText = make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, 26), Size = UDim2.new(1, -28, 0, 44), Font = Enum.Font.GothamMedium, TextSize = 16, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.new(1, 1, 1), Text = "", ZIndex = 31, Parent = objFrame })
local objBar = make("Frame", { BackgroundColor3 = Color3.fromRGB(90, 170, 255), BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(0, 0, 0, 4), ZIndex = 31, Parent = objFrame })

-- маркер цели в мире
local marker = Instance.new("Part")
marker.Name = "TutorialMarker"
marker.Anchored = true
marker.CanCollide = false
marker.CanQuery = false
marker.CanTouch = false
marker.Transparency = 1
marker.Size = Vector3.new(0.5, 0.5, 0.5)
local markerAtt = Instance.new("Attachment")
markerAtt.Parent = marker
local bb = Instance.new("BillboardGui")
bb.Size = UDim2.new(0, 70, 0, 70)
bb.AlwaysOnTop = true
bb.Parent = marker
local arrow = make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = "⬇", TextSize = 56, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(90, 190, 255), TextStrokeTransparency = 0.3, Parent = bb })
local beam = Instance.new("Beam")
beam.Attachment1 = markerAtt
beam.Width0 = 0.6
beam.Width1 = 0.6
beam.FaceCamera = true
beam.LightEmission = 1
beam.Color = ColorSequence.new(Color3.fromRGB(90, 190, 255))
beam.Transparency = NumberSequence.new(0.35)
beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
beam.TextureMode = Enum.TextureMode.Static
beam.TextureLength = 2
beam.TextureSpeed = 1.5
beam.Parent = marker
local charAtt = nil

local function attachBeam()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		charAtt = root:FindFirstChild("TutorialAtt") or Instance.new("Attachment")
		charAtt.Name = "TutorialAtt"
		charAtt.Parent = root
		beam.Attachment0 = charAtt
	end
end
player.CharacterAdded:Connect(function(char)
	char:WaitForChild("HumanoidRootPart")
	attachBeam()
end)
attachBeam()

local function refreshObjective()
	local text = player:GetAttribute("TutStep")
	local num = player:GetAttribute("TutStepNum")
	local target = player:GetAttribute("TutTarget")
	if text and text ~= "" then
		local total = #Config.Tutorial
		objHead.Text = "📘 ОБУЧЕНИЕ · шаг " .. tostring(num or "?") .. "/" .. total
		objText.Text = text
		if not objFrame.Visible then
			objFrame.Visible = true
		end
		tween(objBar, 0.5, { Size = UDim2.new(((num or 1) - 1) / total, 0, 0, 4) })
	else
		objFrame.Visible = false
	end
	if typeof(target) == "Vector3" then
		marker.Position = target
		marker.Parent = workspace
	else
		marker.Parent = nil
	end
	renameBtn.Visible = player:GetAttribute("ShopName") ~= nil and not (text and text ~= "")
end
for _, a in ipairs({ "TutStep", "TutStepNum", "TutTarget", "ShopName" }) do
	player:GetAttributeChangedSignal(a):Connect(refreshObjective)
end
refreshObjective()

local t = 0
RunService.RenderStepped:Connect(function(dt)
	if marker.Parent then
		t = t + dt
		bb.StudsOffset = Vector3.new(0, 1 + math.sin(t * 4) * 0.6, 0)
		arrow.TextTransparency = 0.1 + (math.sin(t * 6) + 1) * 0.1
	end
end)

---------------------------------------------------------------- СОБЫТИЯ СЕРВЕРА
StoryEvent.OnClientEvent:Connect(function(kind, data)
	data = data or {}
	if kind == "intro" then
		task.spawn(playIntro, data)
	elseif kind == "dialog" then
		openDialog(data)
	elseif kind == "name" then
		openNameUI(true)
	elseif kind == "named" then
		task.spawn(playNamed, data)
	end
end)
