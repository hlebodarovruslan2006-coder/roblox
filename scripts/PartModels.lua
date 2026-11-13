-- PartModels (ModuleScript, ReplicatedStorage)
-- 3D-модели всех деталей, жидкостей, инструментов и оборудования.
-- Используются: в компьютере и на складе (превью), на стеллажах, на стене инструментов,
-- у машины во время ремонта и как настоящее оборудование в боксе.

local M = {}

local MAT = Enum.Material
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local C = {
	steel = rgb(170, 175, 180), dark = rgb(45, 45, 50), black = rgb(20, 20, 22), red = rgb(200, 35, 35),
	blue = rgb(30, 80, 200), yellow = rgb(240, 190, 30), orange = rgb(235, 120, 30), white = rgb(235, 235, 235),
	green = rgb(50, 160, 70), copper = rgb(190, 110, 60), brown = rgb(110, 75, 50), chrome = rgb(210, 215, 220),
	rust = rgb(130, 70, 40), rubber = rgb(30, 30, 30), pink = rgb(230, 90, 160),
}
M.Colors = C

-- shape: "B" блок, "C" цилиндр (ось X), "V" вертикальный цилиндр, "S" шар, "W" клин
local function add(m, shape, size, pos, color, mat, rot)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = mat or MAT.SmoothPlastic
	p.Color = color or C.steel
	local cf = CFrame.new(pos)
	if shape == "C" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = size
	elseif shape == "V" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(size.Y, size.X, size.Z)
		cf = cf * CFrame.Angles(0, 0, math.rad(90))
	elseif shape == "S" then
		p.Shape = Enum.PartType.Ball
		p.Size = size
	elseif shape == "W" then
		p:Destroy()
		p = Instance.new("WedgePart")
		p.Anchored = true
		p.CanCollide = false
		p.Material = mat or MAT.SmoothPlastic
		p.Color = color or C.steel
		p.Size = size
	else
		p.Size = size
	end
	if rot then
		cf = cf * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
	end
	p.CFrame = cf
	p.Parent = m
	if not m.PrimaryPart then
		m.PrimaryPart = p
	end
	return p
end
M.add = add

local V = Vector3.new
local B = {}

---------------------------------------------------------------- ЗАПЧАСТИ
B.oil = function(m)
	add(m, "B", V(1.4, 2, 0.8), V(0, 1, 0), C.yellow)
	add(m, "B", V(1.0, 0.8, 0.82), V(0, 0.9, 0), C.black)
	add(m, "B", V(0.3, 0.5, 0.5), V(0.4, 2.25, 0), C.yellow)
	add(m, "V", V(0.4, 0.35, 0.4), V(-0.4, 2.15, 0), C.black)
end
B.oil_filter = function(m)
	add(m, "V", V(1.2, 1.5, 1.2), V(0, 0.75, 0), C.blue)
	add(m, "V", V(1.0, 0.15, 1.0), V(0, 1.55, 0), C.steel, MAT.Metal)
	add(m, "V", V(0.4, 0.05, 0.4), V(0, 1.65, 0), C.dark)
end
B.brake_pads = function(m)
	for i = 0, 1 do
		add(m, "B", V(1.8, 0.25, 0.9), V(0, 0.15 + i * 0.6, 0), C.dark, MAT.Metal)
		add(m, "B", V(1.6, 0.2, 0.75), V(0, 0.37 + i * 0.6, 0), C.brown, MAT.Sand)
	end
end
B.tire = function(m)
	-- шина с протектором и боковинами (без диска)
	add(m, "C", V(0.9, 2.6, 2.6), V(0, 1.3, 0), C.rubber, MAT.Fabric)
	add(m, "C", V(0.92, 1.7, 1.7), V(0, 1.3, 0), rgb(55, 55, 58), MAT.Fabric)
	add(m, "C", V(0.95, 1.45, 1.45), V(0, 1.3, 0), rgb(12, 12, 12))
	for i = 0, 11 do
		local a = math.rad(i * 30)
		add(m, "B", V(0.95, 0.18, 0.35), V(0, 1.3 + math.cos(a) * 1.26, math.sin(a) * 1.26), rgb(18, 18, 18), MAT.Fabric, V(-i * 30, 0, 0))
	end
end
-- колёсный диск (литой, 5 спиц)
B.rim = function(m)
	add(m, "C", V(0.8, 1.9, 1.9), V(0, 1.0, 0), C.chrome, MAT.Metal)
	add(m, "C", V(0.82, 1.6, 1.6), V(0, 1.0, 0), C.dark, MAT.Metal)
	for i = 0, 4 do
		local a = math.rad(i * 72)
		add(m, "B", V(0.3, 0.22, 0.75), V(0.3, 1.0 + math.cos(a) * 0.42, math.sin(a) * 0.42), C.chrome, MAT.Metal, V(-i * 72, 0, 0))
	end
	add(m, "C", V(0.9, 0.45, 0.45), V(0, 1.0, 0), C.steel, MAT.Metal)
	for i = 0, 3 do
		local a = math.rad(i * 90 + 45)
		add(m, "C", V(0.95, 0.1, 0.1), V(0, 1.0 + math.cos(a) * 0.13, math.sin(a) * 0.13), C.black)
	end
end
-- щётки стеклоочистителя (пара)
B.wipers = function(m)
	for _, z in ipairs({ -0.35, 0.35 }) do
		add(m, "B", V(3.2, 0.12, 0.12), V(0, 0.35, z), C.black, MAT.Metal)
		add(m, "B", V(3.0, 0.14, 0.05), V(0, 0.22, z), C.rubber, MAT.Fabric)
		add(m, "B", V(0.3, 0.2, 0.2), V(0, 0.42, z), C.dark, MAT.Metal)
		for _, x in ipairs({ -1.0, 1.0 }) do
			add(m, "B", V(0.12, 0.18, 0.1), V(x, 0.28, z), C.dark, MAT.Metal)
		end
	end
	add(m, "B", V(1.2, 0.05, 0.9), V(0, 0.08, 0), rgb(200, 40, 40)) -- упаковка
end
-- амортизатор с пружиной
B.shock = function(m)
	add(m, "V", V(0.55, 1.8, 0.55), V(0, 1.0, 0), C.yellow, MAT.Metal)
	add(m, "V", V(0.25, 1.4, 0.25), V(0, 2.5, 0), C.chrome, MAT.Metal)
	add(m, "V", V(1.0, 0.15, 1.0), V(0, 3.2, 0), C.dark, MAT.Metal)
	add(m, "V", V(0.9, 0.12, 0.9), V(0, 1.4, 0), C.dark, MAT.Metal)
	for i = 0, 6 do
		add(m, "V", V(0.95, 0.09, 0.95), V(0, 1.55 + i * 0.24, 0), C.red, MAT.Metal)
	end
	add(m, "C", V(0.5, 0.5, 0.5), V(0, 0.15, 0), C.dark, MAT.Metal)
	add(m, "V", V(0.15, 0.4, 0.15), V(0, 3.45, 0), C.steel, MAT.Metal)
end
-- воздушный фильтр (панельный)
B.air_filter = function(m)
	add(m, "B", V(2.2, 0.5, 1.6), V(0, 0.25, 0), C.orange)
	for i = -4, 4 do
		add(m, "B", V(0.08, 0.42, 1.45), V(i * 0.22, 0.3, 0), C.white, MAT.Fabric)
	end
	add(m, "B", V(2.3, 0.08, 1.7), V(0, 0.04, 0), C.black)
end
-- лампа фары H4
B.bulb = function(m)
	add(m, "V", V(0.7, 0.25, 0.7), V(0, 0.15, 0), C.dark, MAT.Metal)
	add(m, "V", V(0.5, 0.3, 0.5), V(0, 0.42, 0), C.chrome, MAT.Metal)
	local g = add(m, "S", V(0.55, 0.8, 0.55), V(0, 0.9, 0), rgb(240, 240, 255), MAT.Glass)
	g.Transparency = 0.3
	add(m, "V", V(0.25, 0.1, 0.25), V(0, 1.32, 0), C.black)
	for _, x in ipairs({ -0.15, 0, 0.15 }) do
		add(m, "V", V(0.06, 0.25, 0.06), V(x, -0.08 + 0.1, 0), C.copper, MAT.Metal)
	end
end
B.battery = function(m)
	add(m, "B", V(1.8, 1.3, 1.0), V(0, 0.65, 0), C.black)
	add(m, "B", V(1.8, 0.15, 1.0), V(0, 1.37, 0), C.dark)
	add(m, "B", V(0.8, 0.5, 1.02), V(0, 0.7, 0), C.green)
	add(m, "V", V(0.3, 0.3, 0.3), V(-0.6, 1.55, 0), C.red)
	add(m, "V", V(0.3, 0.3, 0.3), V(0.6, 1.55, 0), C.dark)
end
B.lambda = function(m)
	add(m, "C", V(1.0, 0.35, 0.35), V(0.3, 0.3, 0), C.chrome, MAT.Metal)
	add(m, "B", V(0.3, 0.55, 0.55), V(-0.1, 0.3, 0), C.steel, MAT.Metal)
	add(m, "C", V(1.6, 0.12, 0.12), V(-1.05, 0.3, 0), C.black)
	add(m, "B", V(0.3, 0.3, 0.4), V(-1.95, 0.3, 0), C.dark)
end
B.spark_plugs = function(m)
	for i = 0, 3 do
		local x = -0.9 + i * 0.6
		add(m, "V", V(0.25, 0.7, 0.25), V(x, 1.15, 0), C.white)
		add(m, "V", V(0.4, 0.25, 0.4), V(x, 0.7, 0), C.steel, MAT.Metal)
		add(m, "V", V(0.25, 0.5, 0.25), V(x, 0.35, 0), C.chrome, MAT.Metal)
	end
end
B.injector = function(m)
	add(m, "V", V(0.4, 1.4, 0.4), V(0, 0.9, 0), C.dark)
	add(m, "V", V(0.25, 0.4, 0.25), V(0, 0.1, 0), C.steel, MAT.Metal)
	add(m, "V", V(0.45, 0.12, 0.45), V(0, 1.2, 0), C.orange)
	add(m, "B", V(0.5, 0.3, 0.3), V(0.35, 1.3, 0), C.black)
end
B.gasket_head = function(m)
	add(m, "B", V(3.2, 0.08, 1.4), V(0, 0.04, 0), C.steel, MAT.Metal)
	for i = 0, 3 do
		add(m, "V", V(0.6, 0.1, 0.6), V(-1.2 + i * 0.8, 0.06, 0), C.dark)
	end
end
B.gasket_set = function(m)
	add(m, "B", V(2.4, 0.4, 1.6), V(0, 0.2, 0), C.white)
	add(m, "B", V(2.0, 0.42, 0.6), V(0, 0.2, 0), C.red)
	add(m, "B", V(2.2, 0.06, 1.2), V(0, 0.45, 0), C.steel, MAT.Metal)
end
B.valves = function(m)
	for i = 0, 3 do
		local x = -0.9 + i * 0.6
		add(m, "V", V(0.12, 1.6, 0.12), V(x, 0.9, 0), C.chrome, MAT.Metal)
		add(m, "V", V(0.45, 0.08, 0.45), V(x, 0.1, 0), C.chrome, MAT.Metal)
	end
end
B.pistons = function(m)
	for i = 0, 1 do
		local x = -0.6 + i * 1.2
		add(m, "V", V(1.0, 0.9, 1.0), V(x, 1.4, 0), C.chrome, MAT.Metal)
		add(m, "V", V(1.02, 0.06, 1.02), V(x, 1.65, 0), C.dark)
		add(m, "V", V(1.02, 0.06, 1.02), V(x, 1.5, 0), C.dark)
		add(m, "B", V(0.25, 1.0, 0.3), V(x, 0.6, 0), C.steel, MAT.Metal)
	end
end
B.rods = function(m)
	for i = 0, 1 do
		local x = -0.6 + i * 1.2
		add(m, "B", V(0.25, 1.8, 0.3), V(x, 1.1, 0), C.steel, MAT.Metal)
		add(m, "C", V(0.3, 0.7, 0.7), V(x, 0.3, 0), C.steel, MAT.Metal, V(0, 90, 0))
		add(m, "C", V(0.3, 0.45, 0.45), V(x, 2.0, 0), C.steel, MAT.Metal, V(0, 90, 0))
	end
end
B.engine_new = function(m)
	add(m, "B", V(3, 2.2, 2), V(0, 1.4, 0), C.dark, MAT.Metal)
	add(m, "B", V(3.1, 0.8, 1.6), V(0, 2.9, 0), C.red, MAT.Metal)
	add(m, "B", V(2.6, 0.6, 1.4), V(0, 0.3, 0), C.black, MAT.Metal)
	add(m, "C", V(0.4, 1.4, 1.4), V(-1.7, 1.3, 0), C.steel, MAT.Metal)
	for i = 0, 3 do
		add(m, "V", V(0.25, 0.4, 0.25), V(-1.05 + i * 0.7, 3.4, 0), C.black)
	end
	add(m, "C", V(2.4, 0.3, 0.3), V(0, 2.2, 1.15), C.chrome, MAT.Metal)
end

---------------------------------------------------------------- ЖИДКОСТИ
local function can(m, body, cap, h)
	add(m, "V", V(0.6, h, 0.6), V(0, h / 2, 0), body)
	add(m, "V", V(0.62, h * 0.4, 0.62), V(0, h * 0.45, 0), C.white)
	add(m, "V", V(0.3, 0.3, 0.3), V(0, h + 0.15, 0), cap)
end
B.wd40 = function(m)
	can(m, C.blue, C.red, 1.6)
	add(m, "V", V(0.62, 0.25, 0.62), V(0, 0.7, 0), C.yellow)
end
B.gasoline = function(m)
	add(m, "B", V(1.6, 2, 0.8), V(0, 1, 0), C.red, MAT.Metal)
	add(m, "B", V(1.0, 0.25, 0.3), V(0, 2.1, 0), C.red, MAT.Metal)
	add(m, "V", V(0.3, 0.4, 0.3), V(0.6, 2.2, 0), C.yellow)
	add(m, "B", V(1.0, 0.1, 0.82), V(0, 1.2, 0), C.dark)
end
B.copper_grease = function(m)
	can(m, C.copper, C.black, 1.2)
end
B.assembly_lube = function(m)
	add(m, "B", V(0.9, 1.4, 0.4), V(0, 0.7, 0), C.green)
	add(m, "V", V(0.2, 0.4, 0.2), V(0, 1.6, 0), C.white)
end
B.sealant = function(m)
	add(m, "C", V(1.6, 0.4, 0.4), V(0, 0.25, 0), C.black)
	add(m, "C", V(0.5, 0.15, 0.15), V(1.05, 0.25, 0), C.red)
	add(m, "C", V(0.8, 0.42, 0.42), V(-0.2, 0.25, 0), C.orange)
end
B.coolant = function(m)
	add(m, "B", V(1.1, 1.8, 0.6), V(0, 0.9, 0), rgb(220, 60, 140), MAT.Glass)
	add(m, "V", V(0.35, 0.3, 0.35), V(-0.3, 1.95, 0), C.white)
	add(m, "B", V(0.8, 0.6, 0.62), V(0, 0.9, 0), C.white)
end
B.weights = function(m)
	for i = 0, 3 do
		add(m, "B", V(0.5, 0.25, 0.25), V(-0.8 + i * 0.55, 0.13, 0), C.steel, MAT.Metal)
	end
	add(m, "B", V(2.4, 0.05, 0.4), V(0, 0.02, 0), C.dark)
end

---------------------------------------------------------------- СЕЗОННЫЕ ШИНЫ
local function seasonTire(m, studs, stripe)
	add(m, "C", V(0.9, 2.6, 2.6), V(0, 1.3, 0), C.rubber, MAT.Fabric)
	add(m, "C", V(0.92, 1.7, 1.7), V(0, 1.3, 0), rgb(55, 55, 58), MAT.Fabric)
	add(m, "C", V(0.95, 1.45, 1.45), V(0, 1.3, 0), rgb(12, 12, 12))
	-- цветная полоса на боковине: синяя = зима, жёлтая = лето
	add(m, "C", V(0.94, 2.0, 2.0), V(0, 1.3, 0), stripe, MAT.SmoothPlastic)
	add(m, "C", V(0.96, 1.85, 1.85), V(0, 1.3, 0), rgb(55, 55, 58), MAT.Fabric)
	for i = 0, 15 do
		local a = math.rad(i * 22.5)
		add(m, "B", V(0.95, 0.16, 0.28), V(0, 1.3 + math.cos(a) * 1.27, math.sin(a) * 1.27), rgb(18, 18, 18), MAT.Fabric, V(-i * 22.5, 0, 0))
		if studs then
			add(m, "S", V(0.12, 0.12, 0.12), V(0.3, 1.3 + math.cos(a) * 1.32, math.sin(a) * 1.32), C.chrome, MAT.Metal)
			add(m, "S", V(0.12, 0.12, 0.12), V(-0.3, 1.3 + math.cos(a + 0.2) * 1.32, math.sin(a + 0.2) * 1.32), C.chrome, MAT.Metal)
		end
	end
end
B.winter_tire = function(m)
	seasonTire(m, true, rgb(80, 160, 240))
	add(m, "B", V(0.1, 0.5, 0.08), V(0.5, 1.3, 0), C.white) -- снежинка
	add(m, "B", V(0.1, 0.08, 0.5), V(0.5, 1.3, 0), C.white)
end
B.summer_tire = function(m)
	seasonTire(m, false, C.yellow)
	add(m, "V", V(0.35, 0.1, 0.35), V(0.5, 1.3, 0), C.yellow, nil, V(0, 0, 90)) -- солнце
end

---------------------------------------------------------------- КОРОБКИ ПЕРЕДАЧ
local function canister(m, body, label, h)
	add(m, "B", V(1.2, h, 0.7), V(0, h / 2, 0), body)
	add(m, "B", V(0.9, h * 0.45, 0.72), V(0, h * 0.5, 0), label)
	add(m, "V", V(0.35, 0.3, 0.35), V(-0.3, h + 0.15, 0), C.black)
	add(m, "B", V(0.3, 0.45, 0.4), V(0.35, h + 0.1, 0), body)
end
B.gear_oil = function(m)
	canister(m, rgb(40, 90, 50), C.white, 1.9)
	add(m, "B", V(0.5, 0.12, 0.74), V(0, 0.95, 0), rgb(40, 90, 50)) -- «МКПП»
end
B.atf = function(m)
	canister(m, C.red, C.white, 1.9)
	add(m, "B", V(0.6, 0.12, 0.74), V(0, 0.95, 0), C.red)
end
B.cvt_fluid = function(m)
	canister(m, rgb(120, 60, 170), C.white, 1.9)
	add(m, "B", V(0.6, 0.12, 0.74), V(0, 0.95, 0), rgb(120, 60, 170))
end
-- фильтры: сетка МКПП, плоский фильтр АКПП, цилиндрический фильтр вариатора
B.mt_filter = function(m)
	add(m, "B", V(1.6, 0.15, 1.1), V(0, 0.1, 0), C.steel, MAT.Metal)
	for i = -3, 3 do
		add(m, "B", V(0.04, 0.17, 1.0), V(i * 0.2, 0.12, 0), C.dark, MAT.Metal)
	end
	add(m, "V", V(0.3, 0.4, 0.3), V(0.6, 0.35, 0), C.steel, MAT.Metal)
end
B.at_filter = function(m)
	add(m, "B", V(1.8, 0.35, 1.2), V(0, 0.2, 0), C.black)
	add(m, "B", V(1.5, 0.37, 0.9), V(0, 0.2, 0), C.red)
	add(m, "V", V(0.35, 0.5, 0.35), V(0.6, 0.55, 0), C.black)
end
B.cvt_filter = function(m)
	add(m, "V", V(0.9, 1.3, 0.9), V(0, 0.65, 0), rgb(120, 60, 170))
	add(m, "V", V(0.75, 0.12, 0.75), V(0, 1.35, 0), C.steel, MAT.Metal)
	add(m, "V", V(0.3, 0.05, 0.3), V(0, 1.43, 0), C.dark)
end
-- МКПП
B.clutch_kit = function(m)
	add(m, "C", V(0.3, 2.2, 2.2), V(0, 1.1, 0), C.steel, MAT.Metal, V(0, 90, 0))
	add(m, "C", V(0.32, 1.7, 1.7), V(0, 1.1, 0), C.dark, MAT.Metal, V(0, 90, 0))
	add(m, "C", V(0.25, 1.9, 1.9), V(0, 1.1, -0.35), C.brown, MAT.Sand, V(0, 90, 0))
	add(m, "C", V(0.5, 0.5, 0.5), V(0, 1.1, 0.1), C.chrome, MAT.Metal, V(0, 90, 0))
end
B.mt_synchro = function(m)
	for i = 0, 2 do
		add(m, "C", V(0.25, 1.3, 1.3), V(0, 0.15 + i * 0.3, 0), C.copper, MAT.Metal, V(0, 0, 90))
		add(m, "C", V(0.27, 0.9, 0.9), V(0, 0.15 + i * 0.3, 0), C.dark, nil, V(0, 0, 90))
	end
end
B.mt_bearing = function(m)
	add(m, "C", V(0.5, 1.4, 1.4), V(0, 0.7, 0), C.chrome, MAT.Metal, V(0, 90, 0))
	add(m, "C", V(0.52, 1.1, 1.1), V(0, 0.7, 0), C.dark, MAT.Metal, V(0, 90, 0))
	add(m, "C", V(0.54, 0.6, 0.6), V(0, 0.7, 0), C.chrome, MAT.Metal, V(0, 90, 0))
	for i = 0, 7 do
		local a = math.rad(i * 45)
		add(m, "S", V(0.18, 0.18, 0.18), V(math.cos(a) * 0.43, 0.7 + math.sin(a) * 0.43, 0.27), C.steel, MAT.Metal)
	end
end
-- АКПП
B.at_solenoid = function(m)
	add(m, "B", V(1.8, 0.3, 1.0), V(0, 0.15, 0), C.steel, MAT.Metal)
	for i = 0, 3 do
		add(m, "V", V(0.3, 0.6, 0.3), V(-0.65 + i * 0.43, 0.6, 0), C.black)
		add(m, "B", V(0.18, 0.15, 0.25), V(-0.65 + i * 0.43, 0.97, 0), C.yellow)
	end
end
B.at_clutches = function(m)
	for i = 0, 4 do
		add(m, "C", V(0.08, 1.6, 1.6), V(0, 0.05 + i * 0.12, 0), (i % 2 == 0) and C.brown or C.steel, (i % 2 == 0) and MAT.Sand or MAT.Metal, V(0, 0, 90))
	end
	add(m, "C", V(0.7, 0.6, 0.6), V(0, 0.3, 0), C.dark, nil, V(0, 0, 90))
end
B.at_torque = function(m)
	add(m, "C", V(0.9, 2.2, 2.2), V(0, 1.1, 0), C.steel, MAT.Metal, V(0, 90, 0))
	add(m, "C", V(0.6, 2.3, 2.3), V(0, 1.1, -0.1), C.chrome, MAT.Metal, V(0, 90, 0))
	add(m, "C", V(0.5, 0.45, 0.45), V(0, 1.1, 0.55), C.dark, MAT.Metal, V(0, 90, 0))
	for i = 0, 5 do
		local a = math.rad(i * 60)
		add(m, "C", V(0.2, 0.18, 0.18), V(math.cos(a) * 0.9, 1.1 + math.sin(a) * 0.9, -0.45), C.dark, MAT.Metal, V(0, 90, 0))
	end
end
-- вариатор
B.cvt_belt = function(m)
	for i = 0, 15 do
		local a = math.rad(i * 22.5)
		local x, y = math.cos(a) * 1.0, math.sin(a) * 0.55
		add(m, "B", V(0.22, 0.12, 0.35), V(x, 0.7 + y, 0), C.chrome, MAT.Metal, V(0, 0, -i * 22.5 + 90))
	end
end
B.cvt_pulley = function(m)
	add(m, "C", V(0.15, 0.4, 0.4), V(0, 0.9, 0), C.dark, MAT.Metal, V(0, 90, 0))
	add(m, "C", V(0.25, 1.8, 1.8), V(0, 0.9, -0.3), C.chrome, MAT.Metal, V(0, 90, 0))
	add(m, "C", V(0.25, 1.8, 1.8), V(0, 0.9, 0.3), C.chrome, MAT.Metal, V(0, 90, 0))
	add(m, "C", V(1.4, 0.35, 0.35), V(0, 0.9, 0), C.steel, MAT.Metal, V(0, 90, 0))
end
B.cvt_valve = function(m)
	add(m, "C", V(1.6, 0.35, 0.35), V(0, 0.3, 0), C.chrome, MAT.Metal)
	add(m, "C", V(0.4, 0.5, 0.5), V(-0.5, 0.3, 0), rgb(120, 60, 170))
	add(m, "B", V(0.3, 0.3, 0.3), V(-0.5, 0.65, 0), C.black)
	add(m, "C", V(0.3, 0.42, 0.42), V(0.6, 0.3, 0), C.steel, MAT.Metal)
end

---------------------------------------------------------------- ИНСТРУМЕНТЫ
B.vip_impact = function(m)
	add(m, "C", V(1.6, 0.6, 0.6), V(0, 1.4, 0), rgb(212, 175, 55), MAT.Metal)
	add(m, "C", V(0.4, 0.4, 0.4), V(1.0, 1.4, 0), C.black)
	add(m, "C", V(0.4, 0.25, 0.25), V(1.4, 1.4, 0), C.chrome, MAT.Metal)
	add(m, "B", V(0.45, 1.2, 0.45), V(-0.4, 0.6, 0), C.black, nil, V(0, 0, -10))
	add(m, "B", V(0.7, 0.5, 0.7), V(-0.5, 0.05, 0), rgb(212, 175, 55), MAT.Metal)
	add(m, "S", V(0.35, 0.35, 0.35), V(-0.1, 1.85, 0), rgb(255, 215, 90), MAT.Neon) -- звезда VIP
end
B.impact = function(m)
	add(m, "C", V(1.6, 0.6, 0.6), V(0, 1.4, 0), C.yellow)
	add(m, "C", V(0.4, 0.4, 0.4), V(1.0, 1.4, 0), C.black)
	add(m, "C", V(0.4, 0.25, 0.25), V(1.4, 1.4, 0), C.chrome, MAT.Metal)
	add(m, "B", V(0.45, 1.2, 0.45), V(-0.4, 0.6, 0), C.black, nil, V(0, 0, -10))
	add(m, "B", V(0.7, 0.5, 0.7), V(-0.5, 0.05, 0), C.yellow)
end
B.torque = function(m)
	add(m, "C", V(3.2, 0.25, 0.25), V(0, 0.3, 0), C.chrome, MAT.Metal)
	add(m, "C", V(1.0, 0.35, 0.35), V(-1.2, 0.3, 0), C.black)
	add(m, "V", V(0.5, 0.25, 0.5), V(1.6, 0.3, 0), C.chrome, MAT.Metal)
	add(m, "B", V(0.5, 0.12, 0.3), V(0.2, 0.45, 0), C.red)
end
B.jack = function(m)
	add(m, "B", V(1.2, 0.5, 3), V(0, 0.4, 0), C.red, MAT.Metal)
	add(m, "C", V(0.25, 0.6, 0.6), V(-0.7, 0.3, -1.2), C.black)
	add(m, "C", V(0.25, 0.6, 0.6), V(0.7, 0.3, -1.2), C.black)
	add(m, "B", V(0.4, 0.4, 1.6), V(0, 0.9, 0.6), C.red, MAT.Metal, V(-25, 0, 0))
	add(m, "V", V(0.9, 0.15, 0.9), V(0, 1.3, 1.3), C.dark, MAT.Metal)
	add(m, "B", V(0.15, 0.15, 2.6), V(0, 1.0, -2.2), C.chrome, MAT.Metal, V(-30, 0, 0))
end
B.stands = function(m)
	for _, x in ipairs({ -0.9, 0.9 }) do
		add(m, "B", V(1.2, 0.15, 1.2), V(x, 0.07, 0), C.red, MAT.Metal)
		add(m, "V", V(0.35, 1.6, 0.35), V(x, 0.9, 0), C.red, MAT.Metal)
		add(m, "V", V(0.25, 0.6, 0.25), V(x, 1.9, 0), C.chrome, MAT.Metal)
		add(m, "B", V(0.5, 0.15, 0.3), V(x, 2.25, 0), C.dark, MAT.Metal)
	end
end
B.hammer = function(m)
	add(m, "B", V(0.25, 2, 0.25), V(0, 1, 0), C.brown, MAT.Wood)
	add(m, "B", V(1.1, 0.4, 0.4), V(0, 2.1, 0), C.dark, MAT.Metal)
end
B.scanner = function(m)
	add(m, "B", V(1.3, 2, 0.35), V(0, 1, 0), C.orange)
	add(m, "B", V(1.0, 0.8, 0.05), V(0, 1.45, -0.18), rgb(60, 200, 255), MAT.Neon)
	for i = 0, 2 do
		add(m, "B", V(0.22, 0.15, 0.05), V(-0.35 + i * 0.35, 0.6, -0.18), C.black)
	end
	add(m, "C", V(1.4, 0.12, 0.12), V(-1.3, 0.1, 0), C.black)
	add(m, "B", V(0.4, 0.3, 0.3), V(-2.1, 0.1, 0), C.dark)
end
B.multimeter = function(m)
	add(m, "B", V(1.0, 1.7, 0.35), V(0, 0.85, 0), C.yellow)
	add(m, "B", V(0.8, 0.45, 0.05), V(0, 1.3, -0.18), rgb(170, 210, 150), MAT.Neon)
	add(m, "V", V(0.45, 0.06, 0.45), V(0, 0.65, -0.2), C.dark, nil, V(90, 0, 0))
	add(m, "C", V(1.4, 0.08, 0.08), V(1.2, 0.1, 0.1), C.red)
	add(m, "C", V(1.4, 0.08, 0.08), V(1.2, 0.1, -0.1), C.black)
end
B.extractor = function(m)
	for i = 0, 2 do
		add(m, "V", V(0.15 + i * 0.08, 1.2, 0.15 + i * 0.08), V(-0.5 + i * 0.5, 0.6, 0), C.dark, MAT.Metal)
	end
	add(m, "B", V(2, 0.1, 0.8), V(0, 0.02, 0), C.red)
end
B.valve_tool = function(m)
	add(m, "B", V(0.2, 0.2, 2.4), V(0, 1.6, 0), C.blue, MAT.Metal)
	add(m, "B", V(0.2, 1.6, 0.2), V(0, 0.8, 1.1), C.blue, MAT.Metal)
	add(m, "V", V(0.5, 0.3, 0.5), V(0, 1.4, -1.0), C.chrome, MAT.Metal)
	add(m, "B", V(0.25, 0.25, 1.0), V(0, 0.1, 1.1), C.black)
end
B.ring_compressor = function(m)
	add(m, "V", V(1.3, 0.8, 1.3), V(0, 0.4, 0), C.chrome, MAT.DiamondPlate)
	add(m, "V", V(1.0, 0.82, 1.0), V(0, 0.4, 0), C.dark)
	add(m, "B", V(0.2, 0.2, 1.2), V(0.75, 0.4, 0), C.red)
end

---------------------------------------------------------------- ОБОРУДОВАНИЕ (в масштабе мира)
B.lift = function(m)
	for _, x in ipairs({ -6.5, 6.5 }) do
		add(m, "B", V(2, 0.3, 2), V(x, 0.15, 0), C.dark, MAT.Metal)
		add(m, "B", V(1.2, 11, 1.2), V(x, 5.6, 0), C.red, MAT.Metal)
		add(m, "B", V(0.3, 10, 0.4), V(x + (x > 0 and -0.7 or 0.7), 5.6, 0), C.chrome, MAT.Metal)
		add(m, "B", V(3, 0.3, 0.6), V(x + (x > 0 and -1.8 or 1.8), 1.2, 2.5), C.yellow, MAT.Metal, V(0, x > 0 and 20 or -20, 0))
		add(m, "B", V(3, 0.3, 0.6), V(x + (x > 0 and -1.8 or 1.8), 1.2, -2.5), C.yellow, MAT.Metal, V(0, x > 0 and -20 or 20, 0))
	end
	add(m, "B", V(14, 0.6, 0.8), V(0, 11.3, 0), C.red, MAT.Metal)
	add(m, "B", V(0.8, 1.2, 0.6), V(-7.4, 4, 0.5), C.blue)
end
B.tire_changer = function(m)
	add(m, "B", V(3, 2.6, 2.4), V(0, 1.3, 0), C.red, MAT.Metal)
	add(m, "V", V(2.8, 0.25, 2.8), V(0, 2.75, 0), C.chrome, MAT.DiamondPlate)
	add(m, "B", V(0.5, 3.4, 0.5), V(0, 4.3, 1.4), C.dark, MAT.Metal)
	add(m, "B", V(0.4, 0.4, 1.6), V(0, 5.8, 0.6), C.dark, MAT.Metal)
	add(m, "V", V(0.25, 1.4, 0.25), V(0, 5, -0.2), C.chrome, MAT.Metal)
	add(m, "B", V(1.6, 0.15, 0.4), V(0, 0.08, -1.4), C.black)
	add(m, "C", V(0.9, 2.6, 2.6), V(-2.4, 1.3, 0), C.rubber, MAT.Fabric)
end
B.balancer = function(m)
	add(m, "B", V(2.4, 2.6, 2), V(0, 1.3, 0), C.blue, MAT.Metal)
	add(m, "B", V(2.2, 1.0, 0.2), V(0, 3.3, 0.6), C.black)
	add(m, "B", V(1.8, 0.7, 0.05), V(0, 3.3, 0.48), rgb(80, 255, 120), MAT.Neon)
	add(m, "C", V(1.6, 0.4, 0.4), V(-1.9, 1.8, 0), C.chrome, MAT.Metal)
	add(m, "C", V(0.9, 2.4, 2.4), V(-2.4, 1.8, 0), C.rubber, MAT.Fabric)
	add(m, "B", V(0.3, 1.6, 2.6), V(-2.4, 3.2, 0), C.dark, MAT.Metal, V(0, 0, 15))
end
B.hoist = function(m)
	add(m, "B", V(0.6, 0.4, 6), V(-1.6, 0.4, 0), C.orange, MAT.Metal)
	add(m, "B", V(0.6, 0.4, 6), V(1.6, 0.4, 0), C.orange, MAT.Metal)
	add(m, "B", V(3.8, 0.6, 0.8), V(0, 0.5, 2.6), C.orange, MAT.Metal)
	add(m, "B", V(0.9, 7, 0.9), V(0, 4, 2.6), C.orange, MAT.Metal)
	add(m, "B", V(0.7, 0.7, 6), V(0, 7.3, 0), C.orange, MAT.Metal, V(-12, 0, 0))
	add(m, "V", V(0.5, 3.4, 0.5), V(0, 3.4, 1.6), C.chrome, MAT.Metal, V(15, 0, 0))
	add(m, "B", V(0.1, 2.2, 0.1), V(0, 5.5, -2.8), C.dark, MAT.Metal)
	add(m, "B", V(0.8, 0.5, 0.2), V(0, 4.3, -2.8), C.dark, MAT.Metal)
	for _, x in ipairs({ -1.6, 1.6 }) do
		for _, z in ipairs({ -2.8, 2.8 }) do
			add(m, "C", V(0.3, 0.6, 0.6), V(x, 0.3, z), C.black)
		end
	end
end
B.engine_stand = function(m)
	-- Т-образное основание на колёсиках
	add(m, "B", V(0.5, 0.4, 4), V(-1.2, 0.3, 0), C.red, MAT.Metal)
	add(m, "B", V(0.5, 0.4, 4), V(1.2, 0.3, 0), C.red, MAT.Metal)
	add(m, "B", V(3, 0.4, 0.5), V(0, 0.3, 1.8), C.red, MAT.Metal)
	for _, x in ipairs({ -1.2, 1.2 }) do
		for _, z in ipairs({ -1.8, 1.8 }) do
			add(m, "C", V(0.25, 0.35, 0.35), V(x, 0.18, z), C.black)
		end
	end
	-- вертикальная колонна с усилением
	add(m, "B", V(0.7, 4, 0.7), V(0, 2.4, 1.8), C.red, MAT.Metal)
	add(m, "W", V(0.4, 1.2, 1.2), V(0, 1.1, 1.0), C.red, MAT.Metal, V(0, 180, 0))
	-- горизонтальная стрела (вынос), на которой висит двигатель
	add(m, "B", V(0.6, 0.6, 1.9), V(0, 4.1, 0.95), C.red, MAT.Metal)
	add(m, "V", V(0.75, 0.75, 0.75), V(0, 4.1, 1.8), C.dark, MAT.Metal)
	-- поворотная планшайба и четыре лапы крепления блока
	add(m, "C", V(0.3, 1.4, 1.4), V(0, 4.1, -0.05), C.chrome, MAT.Metal, V(0, 90, 0))
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		add(m, "B", V(0.22, 0.22, 0.5), V(math.cos(a) * 0.95, 4.1 + math.sin(a) * 0.95, -0.35), C.dark, MAT.Metal)
		add(m, "B", V(1.1, 0.22, 0.2), V(math.cos(a) * 0.5, 4.1 + math.sin(a) * 0.5, -0.15), C.dark, MAT.Metal, V(0, 0, 45 + i * 90))
	end
	-- рукоятка поворота
	add(m, "C", V(1.2, 0.3, 0.3), V(0.9, 4.1, 1.8), C.dark, MAT.Metal)
	add(m, "S", V(0.4, 0.4, 0.4), V(1.55, 4.1, 1.8), C.black)
end
B.parts_washer = function(m)
	add(m, "B", V(4, 2.4, 2.4), V(0, 1.2, 0), C.green, MAT.Metal)
	add(m, "B", V(3.6, 0.2, 2.0), V(0, 2.35, 0), rgb(120, 160, 200), MAT.Glass).Transparency = 0.3
	add(m, "B", V(4, 2.4, 0.2), V(0, 3.6, 1.2), C.green, MAT.Metal, V(-20, 0, 0))
	add(m, "V", V(0.15, 1.6, 0.15), V(1.2, 3.1, 0), C.dark, MAT.Metal)
	add(m, "V", V(0.4, 0.4, 0.4), V(1.6, 0.2, -1.3), C.red, MAT.Metal)
end

---------------------------------------------------------------- API
function M.has(id)
	return B[id] ~= nil
end

-- Возвращает Model, собранную вокруг (0,0,0), низ модели на y=0
function M.build(id)
	local m = Instance.new("Model")
	m.Name = "Model_" .. tostring(id)
	local f = B[id]
	if f then
		f(m)
	else
		add(m, "B", V(1, 1, 1), V(0, 0.5, 0), C.steel)
	end
	return m
end

-- Готовая модель в заданной позиции/повороте и (по желанию) в масштабе
function M.place(id, cf, scale, parent)
	local m = M.build(id)
	if scale and scale ~= 1 then
		pcall(function()
			m:ScaleTo(scale)
		end)
	end
	local origin = CFrame.new()
	local pivotOffset = m.PrimaryPart.CFrame:ToObjectSpace(origin)
	m.PrimaryPart.PivotOffset = pivotOffset
	m:PivotTo(cf)
	m.Parent = parent
	return m
end

-- Превью в ViewportFrame (для интерфейса)
function M.viewport(id, parent, size, rotate)
	local vf = Instance.new("ViewportFrame")
	vf.Size = size or UDim2.new(0, 64, 0, 64)
	vf.BackgroundColor3 = Color3.fromRGB(32, 34, 42)
	vf.BorderSizePixel = 0
	vf.Ambient = Color3.fromRGB(170, 170, 180)
	vf.LightColor = Color3.fromRGB(255, 250, 240)
	vf.LightDirection = Vector3.new(-1, -1.5, -1)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = vf
	local m = M.build(id)
	m.Parent = vf
	local cf, sz = m:GetBoundingBox()
	local r = math.max(sz.X, sz.Y, sz.Z)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vf
	vf.CurrentCamera = cam
	local center = cf.Position
	local dist = r * 1.6 + 1
	local function aim(a)
		local off = Vector3.new(math.sin(a) * dist, r * 0.55, math.cos(a) * dist)
		cam.CFrame = CFrame.lookAt(center + off, center)
	end
	aim(math.rad(35))
	vf.Parent = parent
	if rotate then
		local a = 0
		task.spawn(function()
			while vf.Parent do
				a = a + 0.03
				aim(a)
				task.wait(0.03)
			end
		end)
	end
	return vf
end

return M
