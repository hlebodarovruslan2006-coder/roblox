-- MechanicConfig (ModuleScript, ReplicatedStorage)
-- Все цены, детали, инструменты, неисправности и работники настраиваются здесь.

local Config = {}

Config.StartCash = 30            -- мало специально: в обучении первую машину чиним на кредит из банка
Config.DeliveryTime = 8          -- секунд до доставки заказа (администратор = мгновенно)
Config.CarCompleteBonus = 0.25   -- бонус за полностью отремонтированную машину
Config.BrokenBoltFee = 50        -- штраф за сорванный болт без экстрактора
Config.ComebackChance = 0.5      -- шанс, что клиент вернётся после капиталки, собранной без динамометрического ключа
Config.BoltBreakChance = 0.15    -- шанс сорвать ржавый болт обычным ключом (15%)
Config.ClientTipMin = 150        -- минимальный бонус от клиента за полностью готовую машину
Config.PitBay = 1                -- номер поста со смотровой ямой
Config.ParkingSpots = 4          -- мест на клиентской парковке за мастерской
Config.MaxWaitingCars = 4        -- сколько машин может одновременно ждать на парковке
Config.CarSpawnInterval = 18     -- раз в N секунд (днём) на парковку приезжает новый клиент

-- ДЕНЬ И НОЧЬ, ПОГОДА
Config.DayLength = 720           -- секунд на полные игровые сутки (12 минут)
Config.NightStart = 21           -- с 21:00 ...
Config.NightEnd = 6              -- ... до 06:00 клиенты не приезжают
Config.WeatherChangeMin = 120    -- погода меняется раз в 2-5 минут
Config.WeatherChangeMax = 300

-- ЗАЩИТА ОТ БАНКРОТСТВА
Config.DailyGift = 100           -- подарок каждое игровое утро
Config.PoorGift = 300            -- подарок утром, если денег меньше PoorThreshold
Config.PoorThreshold = 250
Config.Loans = { 150, 300, 750, 1500 } -- мини-кредиты в банке, без процентов
Config.LoanMax = 1500            -- максимальный общий долг

-- ЗВУКИ И МУЗЫКА
-- Встроенные звуки Roblox (rbxasset://) работают всегда. Можно заменить на свои "rbxassetid://ID" из Creator Store.
Config.Sounds = {
	wrench   = { id = "rbxasset://sounds/clickfast.wav", volume = 0.8, pitch = 0.7 },  -- откручивание ключом
	impact   = { id = "rbxasset://sounds/clickfast.wav", volume = 1.0, pitch = 1.6, loops = 3 }, -- гайковёрт
	hammer   = { id = "rbxasset://sounds/hit.wav", volume = 1.0, pitch = 0.8 },
	break_   = { id = "rbxasset://sounds/snap.mp3", volume = 1.0, pitch = 0.9 },
	drill    = { id = "rbxasset://sounds/clickfast.wav", volume = 0.9, pitch = 2.2, loops = 6 },
	spray    = { id = "rbxasset://sounds/swoosh.wav", volume = 0.7, pitch = 0.6 },
	action   = { id = "rbxasset://sounds/button.wav", volume = 0.6, pitch = 0.9 },
	done     = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.7, pitch = 1.0 },
	cash     = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, pitch = 1.4 },
	engine   = { id = "rbxasset://sounds/action_swim.mp3", volume = 0.5, pitch = 0.4 },
}
-- Фоновая музыка: вставьте ID нейтральных треков из Creator Store (Audio -> Music, бесплатные лицензионные треки Roblox).
-- Например: Config.Music = { "rbxassetid://1234567890", "rbxassetid://..." }
Config.Music = {}
Config.MusicVolume = 0.25
Config.RainSound = ""            -- ID звука дождя (по желанию)

-- Аватары персонала: NPC выглядит как аватар реального игрока Roblox.
-- Число = UserId, его видно в адресе профиля игрока: roblox.com/users/ЧИСЛО/profile
-- Ключи: mechanic, electrician, admin. Пусто или 0 = обычная униформа.
Config.NpcAvatars = {
	mechanic = 2724080668,
}

-- Донат: вставьте ID своих Game Pass.
-- Как получить ID: опубликуйте игру → create.roblox.com → Creations → ваша игра → Monetization → Passes →
-- Create a Pass (картинка + название) → включите "Item for Sale" и цену в Robux → скопируйте Pass ID (число).
-- Пока id = 0: в игре кнопка показывает «Скоро», в Studio бонус выдаётся бесплатно для теста.
Config.GamePasses = {
	vip        = { id = 0, name = "VIP-пасс", desc = "+25% ко всем доходам, ежедневная награда x2, значок VIP над головой и золотая табличка владельца" },
	extra_lift = { id = 0, name = "+1 подъёмник", desc = "Открывает 4-й пост со своим подъёмником: ещё одна машина в работе одновременно" },
	x2cash     = { id = 0, name = "x2 денег", desc = "Все доходы удваиваются" },
	x2speed    = { id = 0, name = "x2 бег", desc = "Скорость бега в 2 раза выше" },
}
Config.DonateOrder = { "vip", "extra_lift", "x2cash", "x2speed" } -- порядок карточек во вкладке «Донат»
Config.VipIncomeBonus = 0.25      -- VIP: +25% к доходам
Config.VipDailyMultiplier = 2     -- VIP: ежедневная награда x2

-- Разовые покупки (Developer Products): Monetization → Developer Products → Create → скопируйте Product ID.
-- Пока id = 0: в Studio выдаётся бесплатно для теста.
Config.DevProducts = {
	boost30 = { id = 0, name = "Буст x2 на 30 мин", desc = "Все доходы x2 на 30 минут игры (время идёт, только пока вы в игре). Покупки складываются.", minutes = 30 },
}

-- 4-й пост открывается донатом «+1 подъёмник» (посты 1-3 доступны всем)
Config.BaseBays = 3

-- ЕЖЕДНЕВНАЯ НАГРАДА (реальные сутки, серия входов подряд; после 7-го дня — снова с 1-го)
Config.DailyRewards = { 150, 250, 350, 500, 650, 800, 1200 }

-- ЗАДАНИЯ НА ДЕНЬ (каждые реальные сутки выбираются новые)
-- kind: fix = устранить неисправность, cars = отдать готовую машину, earn = заработать $, fault = конкретный ремонт, stars5 = отзыв на 5★
Config.QuestsPerDay = 3
Config.DailyQuests = {
	{ id = "fix5",     kind = "fix",    goal = 5,    reward = 300, text = "Устраните 5 неисправностей" },
	{ id = "fix12",    kind = "fix",    goal = 12,   reward = 700, text = "Устраните 12 неисправностей" },
	{ id = "cars3",    kind = "cars",   goal = 3,    reward = 400, text = "Полностью отремонтируйте 3 машины" },
	{ id = "cars6",    kind = "cars",   goal = 6,    reward = 800, text = "Полностью отремонтируйте 6 машин" },
	{ id = "earn1500", kind = "earn",   goal = 1500, reward = 400, text = "Заработайте $1500 на ремонтах" },
	{ id = "earn4000", kind = "earn",   goal = 4000, reward = 900, text = "Заработайте $4000 на ремонтах" },
	{ id = "oil2",     kind = "fault",  fault = "oil",    goal = 2, reward = 250, text = "Замените масло 2 раза" },
	{ id = "brakes2",  kind = "fault",  fault = "brakes", goal = 2, reward = 350, text = "Поменяйте тормозные колодки 2 раза" },
	{ id = "tire2",    kind = "fault",  fault = "tire",   goal = 2, reward = 300, text = "Сделайте шиномонтаж 2 раза" },
	{ id = "stars3",   kind = "stars5", goal = 3,    reward = 500, text = "Получите 3 отзыва на 5★" },
}
Config.QuestById = {}
for _, q in ipairs(Config.DailyQuests) do
	Config.QuestById[q.id] = q
end

-- РАНГ МАСТЕРСКОЙ (по числу ремонтов; бонус к доходу от ремонтов)
Config.Ranks = {
	{ repairs = 0,   name = "Гаражная",    bonus = 0 },
	{ repairs = 15,  name = "Районная",    bonus = 0.05 },
	{ repairs = 40,  name = "Городская",   bonus = 0.10 },
	{ repairs = 90,  name = "Известная",   bonus = 0.15 },
	{ repairs = 180, name = "Элитная",     bonus = 0.20 },
	{ repairs = 350, name = "Легендарная", bonus = 0.25 },
}

-- РЕЙТИНГ В ЗВЁЗДАХ: каждый клиент оставляет отзыв 1-5★
-- -1★ если ждал дольше StarSlowTime с приезда, ещё -1★ если вдвое дольше, -1★ за сорванный болт, -1★ за капиталку без динамометрического ключа
Config.StarSlowTime = 240
Config.RatingWindow = 20          -- рейтинг = среднее последних N отзывов
Config.StarTipBonus = 0.2         -- рейтинг 4.5★+ : чаевые клиента +20%
Config.StarSpawnEffect = 0.15     -- каждая звезда выше/ниже 3★ ускоряет/замедляет поток клиентов на 15%

-- ТАБЛИЦА ЛИДЕРОВ (глобальная, по числу ремонтов)
Config.LeaderboardStore = "MechanicTop_v1"
Config.LeaderboardSize = 10
Config.LeaderboardRefresh = 90    -- секунд между обновлениями

-- category: part = запчасть, fluid = тех. жидкость/расходник (заказываются и лежат на складе)
-- tool = инструмент, equip = оборудование (покупаются навсегда)
Config.Items = {
	-- ЗАПЧАСТИ
	{ id = "oil_filter",   cat = "part", name = "Масляный фильтр",          price = 15,   desc = "Меняется вместе с маслом" },
	{ id = "brake_pads",   cat = "part", name = "Тормозные колодки",       price = 60,   desc = "Ремонт скрипящих тормозов" },
	{ id = "tire",         cat = "part", name = "Шина",                    price = 80,   desc = "Шиномонтаж: замена пробитой или стёртой шины" },
	{ id = "battery",      cat = "part", name = "Аккумулятор",            price = 120,  desc = "Когда машина не заводится" },
	{ id = "lambda",       cat = "part", name = "Лямбда-зонд",              price = 90,   desc = "Ошибка P0130" },
	{ id = "spark_plugs",  cat = "part", name = "Свечи зажигания (компл.)",  price = 50,   desc = "Ошибка P0300 — пропуски зажигания" },
	{ id = "injector",     cat = "part", name = "Форсунка",                price = 110,  desc = "Ошибка P0201" },
	{ id = "gasket_head",  cat = "part", name = "Прокладка ГБЦ",           price = 70,   desc = "Ошибка P0217 — перегрев" },
	{ id = "gasket_set",   cat = "part", name = "Комплект прокладок двигателя", price = 120, desc = "Для капитального ремонта" },
	{ id = "valves",       cat = "part", name = "Клапаны (компл.)",        price = 180,  desc = "Капиталка: газораспределительный механизм" },
	{ id = "pistons",      cat = "part", name = "Поршни с кольцами (компл.)", price = 300, desc = "Капиталка: цилиндро-поршневая группа" },
	{ id = "rods",         cat = "part", name = "Шатуны и вкладыши (компл.)", price = 200, desc = "Капиталка: кривошипно-шатунный механизм" },
	{ id = "engine_new",   cat = "part", name = "Новый двигатель",         price = 2500, desc = "Быстрая, но дорогая альтернатива капиталке" },
	{ id = "wipers",       cat = "part", name = "Щётки стеклоочистителя (пара)", price = 25, desc = "Скрипят и мажут дворники" },
	{ id = "shock",        cat = "part", name = "Амортизатор",             price = 110,  desc = "Стук в подвеске, машину раскачивает" },
	{ id = "rim",          cat = "part", name = "Колёсный диск",           price = 90,   desc = "Замена погнутого диска (шиномонтаж)" },
	{ id = "air_filter",   cat = "part", name = "Воздушный фильтр",        price = 20,   desc = "Двигатель «душится», расход вырос" },
	{ id = "bulb",         cat = "part", name = "Лампа фары H4",           price = 15,   desc = "Не горит фара" },

	-- ТЕХ. ЖИДКОСТИ И РАСХОДНИКИ
	{ id = "oil",           cat = "fluid", name = "Моторное масло 4л",     price = 40, desc = "Замена масла и заправка после ремонта двигателя" },
	{ id = "wd40",          cat = "fluid", name = "WD-40",                  price = 10, desc = "Растворяет ржавчину: прикипший болт точно открутится без срыва" },
	{ id = "gasoline",      cat = "fluid", name = "Бензин (канистра)",     price = 15, desc = "Отмывка деталей и болтов в мойке перед сборкой" },
	{ id = "copper_grease", cat = "fluid", name = "Медная смазка",         price = 20, desc = "На резьбу лямбды, суппорты и ступицы: защита от закисания, +15% к оплате" },
	{ id = "assembly_lube", cat = "fluid", name = "Монтажная смазка",       price = 20, desc = "Сборка двигателя: поршни, вкладыши" },
	{ id = "sealant",       cat = "fluid", name = "Герметик",               price = 15, desc = "Наносится при установке прокладок" },
	{ id = "coolant",       cat = "fluid", name = "Антифриз",               price = 25, desc = "Заливается после ремонта ГБЦ и замены двигателя" },
	{ id = "weights",       cat = "fluid", name = "Балансировочные грузики", price = 5, desc = "Балансировка колеса на станке" },

	-- ИНСТРУМЕНТЫ (навсегда)
	{ id = "impact",          cat = "tool", name = "Гайковёрт",               price = 400, desc = "Откручивает болты в 3 раза быстрее обычного ключа" },
	{ id = "torque",          cat = "tool", name = "Динамометрический ключ", price = 350, desc = "Нужен только в капиталке: сборка двигателя с моментом. Без него клиент может вернуться и потребовать половину денег" },
	{ id = "jack",            cat = "tool", name = "Домкрат",                 price = 150, desc = "Поднимает машину для колёс и тормозов" },
	{ id = "stands",          cat = "tool", name = "Страховочные стойки",    price = 100, desc = "Обязательны с домкратом: без них под машину лезть нельзя" },
	{ id = "hammer",          cat = "tool", name = "Молоток",                price = 50,  desc = "Сбивает прикипшие болты (70% шанс), бесплатно и многоразово" },
	{ id = "scanner",         cat = "tool", name = "Автосканер OBD-II",       price = 300, desc = "Читает ошибки Check Engine и сбрасывает их после ремонта" },
	{ id = "multimeter",      cat = "tool", name = "Мультиметр",              price = 80,  desc = "Проверка аккумулятора и проводки" },
	{ id = "extractor",       cat = "tool", name = "Экстрактор болтов",       price = 120, desc = "Выкручивает сорванный болт без штрафа" },
	{ id = "valve_tool",      cat = "tool", name = "Рассухариватель клапанов", price = 150, desc = "Сжимает пружины — нужен для замены клапанов" },
	{ id = "ring_compressor", cat = "tool", name = "Оправка для поршневых колец", price = 100, desc = "Нужна, чтобы вставить поршни в цилиндры" },
	{ id = "vip_impact",    cat = "tool", vip = true, name = "⭐ VIP-гайковёрт", price = 0, desc = "Только с VIP-пассом: откручивает все болты шага разом (и все 4 колеса при переобувке), даже ржавые" },

	-- СЕЗОННЫЕ ШИНЫ (зимой клиенты едут переобуваться на зимнюю, после таяния снега — на летнюю)
	{ id = "winter_tire",   cat = "part", name = "Зимняя шина (шипованная)", price = 90, desc = "Переобувка на зиму: нужно 4 шт. на машину" },
	{ id = "summer_tire",   cat = "part", name = "Летняя шина",             price = 80, desc = "Переобувка на лето: нужно 4 шт. на машину" },

	-- КОРОБКИ ПЕРЕДАЧ (вкладка «⚙ КПП»)
	{ id = "gear_oil",      cat = "fluid", group = "trans", name = "Трансмиссионное масло 75W-90 (МКПП)", price = 35, desc = "Только для механической коробки" },
	{ id = "mt_filter",     cat = "part",  group = "trans", name = "Фильтр-сетка МКПП",            price = 20,  desc = "Меняется вместе с маслом МКПП" },
	{ id = "clutch_kit",    cat = "part",  group = "trans", name = "Комплект сцепления (МКПП)",    price = 220, desc = "Диск, корзина, выжимной подшипник — буксует сцепление" },
	{ id = "mt_synchro",    cat = "part",  group = "trans", name = "Синхронизаторы МКПП (компл.)", price = 160, desc = "Хрустят передачи при включении" },
	{ id = "mt_bearing",    cat = "part",  group = "trans", name = "Подшипник первичного вала МКПП", price = 70, desc = "Гул в коробке" },
	{ id = "atf",           cat = "fluid", group = "trans", name = "Жидкость ATF (АКПП)",          price = 45,  desc = "Только для автомата" },
	{ id = "at_filter",     cat = "part",  group = "trans", name = "Фильтр АКПП",                  price = 35,  desc = "Меняется вместе с ATF" },
	{ id = "at_solenoid",   cat = "part",  group = "trans", name = "Блок соленоидов АКПП",         price = 190, desc = "Ошибка P0750 — коробка пинается" },
	{ id = "at_clutches",   cat = "part",  group = "trans", name = "Фрикционы АКПП (компл.)",      price = 260, desc = "Переборка: коробка буксует" },
	{ id = "at_torque",     cat = "part",  group = "trans", name = "Гидротрансформатор АКПП",      price = 380, desc = "Переборка АКПП" },
	{ id = "cvt_fluid",     cat = "fluid", group = "trans", name = "Жидкость CVT (вариатор)",      price = 55,  desc = "Только для вариатора" },
	{ id = "cvt_filter",    cat = "part",  group = "trans", name = "Фильтр вариатора",             price = 40,  desc = "Меняется вместе с жидкостью CVT" },
	{ id = "cvt_belt",      cat = "part",  group = "trans", name = "Ремень вариатора",             price = 300, desc = "Вариатор гудит и дёргается" },
	{ id = "cvt_pulley",    cat = "part",  group = "trans", name = "Шкив вариатора",               price = 240, desc = "Задиры на шкивах — гул" },
	{ id = "cvt_valve",     cat = "part",  group = "trans", name = "Клапан давления вариатора",    price = 150, desc = "Ошибка P0868 — падает давление" },

	-- ОБОРУДОВАНИЕ (навсегда)
	{ id = "lift",          cat = "equip", name = "Подъёмник",               price = 1500, desc = "Работы снизу: лямбда, двигатель. Заменяет домкрат со стойками (на посту с ямой лямбду можно менять и без него)" },
	{ id = "tire_changer",  cat = "equip", name = "Шиномонтажный станок",   price = 800,  desc = "Разбортировка и монтаж шин" },
	{ id = "balancer",      cat = "equip", name = "Балансировочный станок", price = 600, desc = "Балансировка колёс после шиномонтажа" },
	{ id = "hoist",         cat = "equip", name = "Гидравлический кран",   price = 900,  desc = "Снять и поставить двигатель" },
	{ id = "engine_stand",  cat = "equip", name = "Стенд для двигателя",   price = 700,  desc = "Капитальный ремонт: клапаны, поршни, шатуны, прокладки" },
	{ id = "parts_washer",  cat = "equip", name = "Мойка деталей",          price = 400,  desc = "Отмывка деталей и болтов бензином" },
}

Config.ItemById = {}
for _, it in ipairs(Config.Items) do
	Config.ItemById[it.id] = it
end

-- Работники
Config.Workers = {
	{ id = "admin",       name = "Администратор", hire = 1000,
	  desc = "Детали выдаёт мгновенно и на 10% дешевле. У машины появляется кнопка «Купить всё нужное» одним нажатием" },
	{ id = "mechanic",    name = "Автомеханик",   hire = 1500,
	  desc = "Сам чинит масло, тормоза, шины, свечи, дворники, амортизаторы (берёт детали со склада, 60% оплаты)" },
	{ id = "electrician", name = "Автоэлектрик",   hire = 1500,
	  desc = "Сам сканирует Check Engine и чинит электрику: АКБ, лямбда, форсунки (60% оплаты)" },
}
Config.WorkerById = {}
for _, w in ipairs(Config.Workers) do
	Config.WorkerById[w.id] = w
end
Config.WorkerJobTime = 20     -- секунд на один ремонт работником
Config.WorkerPayShare = 0.6
-- Зарплаты у персонала нет: платите только за найм.

-- Шаги ремонта:
--  bolts  = открутить N болтов (rust = шанс что болт ржавый)
--  action = действие (нужны items со склада / tools / станция at)
--  torque = затяжка с моментом (ТОЛЬКО в капиталке: динамометрический ключ или обычный ключ с риском)
--  grease = по желанию нанести медную смазку (+15%)
-- at = "car" (у машины) или id станции (tire_changer, balancer, engine_stand, parts_washer)
-- lift: nil = не нужно, "jack" = домкрат+стойки или подъёмник, "lift" = подъёмник (или пост с ямой, если pit = true)
local function B(n, rust, label, at) return { type = "bolts", count = n, rust = rust, label = label, at = at } end
local function A(label, time, items, tools, at) return { type = "action", label = label, time = time, items = items, tools = tools, at = at } end
local function T(label, at) return { type = "torque", label = label, at = at } end
local function G(label) return { type = "grease", label = label } end
-- ожидание (до 5 мин): шаг запускается кнопкой и идёт сам — можно заниматься другой машиной
local function W(label, time, at) return { type = "action", label = label, time = math.min(time, 300), wait = true, at = at } end

Config.Faults = {
	{ id = "oil", name = "Пора менять масло", worker = "mechanic", reward = 130,
	  steps = {
		B(1, 0.3, "Открутить сливную пробку"),
		A("Слить старое масло", 3),
		W("Дать старому маслу стечь", 30),
		A("Заменить масляный фильтр", 2, { oil_filter = 1 }),
		A("Закрутить сливную пробку ключом", 1.5),
		A("Залить новое масло", 3, { oil = 1 }),
	  } },
	{ id = "brakes", name = "Скрипят тормоза", worker = "mechanic", reward = 230, lift = "jack",
	  steps = {
		B(4, 0.25, "Открутить колёсные болты"),
		B(2, 0.5, "Открутить суппорт"),
		A("Заменить колодки", 4, { brake_pads = 1 }),
		G("Медная смазка на направляющие суппорта"),
		A("Затянуть суппорт и колесо ключом", 2),
	  } },
	{ id = "tire", name = "Прокол колеса (шиномонтаж)", worker = "mechanic", reward = 170, lift = "jack",
	  steps = {
		B(4, 0.2, "Снять колесо"),
		A("Разбортировать и поставить новую шину", 4, { tire = 1 }, nil, "tire_changer"),
		A("Отбалансировать колесо", 3, { weights = 2 }, nil, "balancer"),
		G("Медная смазка на ступицу"),
		A("Поставить колесо и затянуть болты", 2),
	  } },
	{ id = "battery", name = "Машина не заводится", worker = "electrician", reward = 170,
	  steps = {
		A("Проверить АКБ мультиметром", 2, nil, { "multimeter" }),
		B(2, 0.4, "Открутить клеммы"),
		A("Установить новый аккумулятор", 3, { battery = 1 }),
	  } },
	{ id = "wipers", name = "Скрипят и мажут дворники", worker = "mechanic", reward = 90,
	  steps = {
		A("Снять старые щётки", 2),
		A("Установить новые щётки", 2, { wipers = 1 }),
	  } },
	{ id = "shock", name = "Стук в подвеске — амортизатор", worker = "mechanic", reward = 260,
	  steps = {
		B(2, 0.3, "Открутить верхнее крепление стойки"),
		B(2, 0.35, "Открутить нижнее крепление"),
		A("Поставить новый амортизатор", 4, { shock = 1 }),
		A("Затянуть крепления ключом", 2),
	  } },
	{ id = "rim", name = "Погнут колёсный диск", worker = "mechanic", reward = 240, lift = "jack",
	  steps = {
		B(4, 0.2, "Снять колесо"),
		A("Перебортировать шину на новый диск", 4, { rim = 1 }, nil, "tire_changer"),
		A("Отбалансировать колесо", 3, { weights = 2 }, nil, "balancer"),
		A("Поставить колесо и затянуть болты", 2),
	  } },
	{ id = "air_filter", name = "Двигатель «душится» — воздушный фильтр", worker = "mechanic", reward = 80,
	  steps = {
		A("Открыть корпус фильтра", 1.5),
		A("Поставить новый фильтр", 2, { air_filter = 1 }),
	  } },
	{ id = "bulb", name = "Не горит фара", worker = "electrician", reward = 70,
	  steps = {
		A("Снять разъём и пыльник", 1.5),
		A("Заменить лампу", 2, { bulb = 1 }),
	  } },
	-- СКРЫТЫЕ: нужен сканер (Check Engine)
	{ id = "lambda", hidden = true, code = "P0130", name = "Неисправен лямбда-зонд", worker = "electrician", reward = 280, lift = "lift", pit = true,
	  steps = {
		B(1, 0.85, "Выкрутить старый датчик (выхлоп — всё в ржавчине)"),
		G("Медная смазка на резьбу нового датчика"),
		A("Вкрутить новый лямбда-зонд", 3, { lambda = 1 }),
		A("Сбросить ошибки сканером", 2, nil, { "scanner" }),
	  } },
	{ id = "plugs", hidden = true, code = "P0300", name = "Пропуски зажигания — свечи", worker = "mechanic", reward = 210,
	  steps = {
		A("Снять катушки зажигания", 2),
		B(4, 0.15, "Выкрутить свечи"),
		A("Установить новые свечи", 3, { spark_plugs = 1 }),
		A("Закрутить свечи и поставить катушки", 2),
	  } },
	{ id = "injector", hidden = true, code = "P0201", name = "Неисправна форсунка", worker = "electrician", reward = 320,
	  steps = {
		A("Снять топливную рампу", 3),
		A("Отмыть рампу бензином", 3, { gasoline = 1 }, nil, "parts_washer"),
		A("Заменить форсунку", 4, { injector = 1 }),
		A("Проверить и сбросить ошибку", 2, nil, { "scanner" }),
	  } },
	{ id = "head_gasket", hidden = true, code = "P0217", name = "Перегрев — пробило прокладку ГБЦ", reward = 520,
	  steps = {
		B(6, 0.3, "Открутить болты ГБЦ"),
		A("Отмыть ГБЦ и болты бензином", 4, { gasoline = 1 }, nil, "parts_washer"),
		A("Поставить новую прокладку на герметик", 3, { gasket_head = 1, sealant = 1 }),
		W("Герметик схватывается", 120),
		A("Затянуть болты ГБЦ по схеме", 3),
		A("Залить антифриз", 2, { coolant = 1 }),
	  } },
	-- СЕЗОННАЯ СМЕНА РЕЗИНЫ (приезжают только зимой / сразу после таяния снега). VIP-гайковёрт снимает все 4 колеса разом
	{ id = "winter_tires", season = "winter", name = "Переобуть на зимнюю резину", worker = "mechanic", reward = 380, lift = "jack",
	  steps = {
		B(16, 0.15, "Снять 4 колеса (16 болтов)"),
		A("Перебортировать 4 шины на зимние", 8, { winter_tire = 4 }, nil, "tire_changer"),
		A("Отбалансировать 4 колеса", 6, { weights = 4 }, nil, "balancer"),
		A("Поставить 4 колеса и затянуть болты", 4),
	  } },
	{ id = "summer_tires", season = "summer", name = "Переобуть на летнюю резину", worker = "mechanic", reward = 380, lift = "jack",
	  steps = {
		B(16, 0.2, "Снять 4 колеса (16 болтов)"),
		A("Перебортировать 4 шины на летние", 8, { summer_tire = 4 }, nil, "tire_changer"),
		A("Отбалансировать 4 колеса", 6, { weights = 4 }, nil, "balancer"),
		A("Поставить 4 колеса и затянуть болты", 4),
	  } },

	-- КОРОБКИ ПЕРЕДАЧ: неисправность выпадает только машине с подходящей коробкой (gearbox = mt / at / cvt)
	{ id = "mt_service", gearbox = "mt", name = "МКПП: замена трансмиссионного масла", worker = "mechanic", reward = 210, lift = "jack", pit = true,
	  steps = {
		B(1, 0.4, "Открутить сливную пробку КПП"),
		A("Слить старое масло МКПП", 3),
		W("Дать маслу стечь", 60),
		A("Промыть и заменить фильтр-сетку", 2, { mt_filter = 1 }),
		A("Залить трансмиссионное масло", 3, { gear_oil = 1 }),
	  } },
	{ id = "mt_clutch", gearbox = "mt", name = "Буксует сцепление (МКПП)", reward = 520, lift = "lift",
	  steps = {
		B(6, 0.3, "Открутить МКПП от двигателя"),
		A("Снять коробку передач", 5),
		A("Заменить комплект сцепления", 5, { clutch_kit = 1 }),
		A("Поставить коробку и затянуть болты", 4),
		A("Долить трансмиссионное масло", 2, { gear_oil = 1 }),
	  } },
	{ id = "mt_repair", gearbox = "mt", name = "Хрустят передачи, гул в МКПП", reward = 640, lift = "lift",
	  steps = {
		B(6, 0.3, "Открутить МКПП от двигателя"),
		B(8, 0.25, "Разобрать картер коробки"),
		A("Заменить синхронизаторы", 5, { mt_synchro = 1 }),
		A("Заменить подшипник первичного вала", 4, { mt_bearing = 1 }),
		A("Собрать картер на герметик", 3, { sealant = 1 }),
		W("Герметик картера схватывается", 150),
		A("Поставить коробку и залить масло", 4, { gear_oil = 1, mt_filter = 1 }),
	  } },
	{ id = "at_service", gearbox = "at", name = "АКПП: замена ATF и фильтра", worker = "mechanic", reward = 260, lift = "jack", pit = true,
	  steps = {
		B(1, 0.3, "Открутить сливную пробку АКПП"),
		A("Слить старую ATF", 3),
		B(4, 0.2, "Открутить поддон АКПП"),
		A("Заменить фильтр АКПП", 3, { at_filter = 1 }),
		A("Поставить поддон и залить ATF", 4, { atf = 2 }),
		W("Прогреть коробку и проверить уровень", 90),
	  } },
	{ id = "at_solenoid", gearbox = "at", hidden = true, code = "P0750", name = "АКПП пинается — неисправны соленоиды", reward = 450, lift = "jack", pit = true,
	  steps = {
		B(4, 0.2, "Открутить поддон АКПП"),
		A("Снять гидроблок", 4),
		A("Заменить блок соленоидов", 4, { at_solenoid = 1 }),
		A("Собрать и долить ATF", 3, { atf = 1 }),
		A("Адаптация АКПП сканером", 3, nil, { "scanner" }),
	  } },
	{ id = "at_overhaul", gearbox = "at", name = "АКПП буксует — переборка", reward = 820, lift = "lift",
	  steps = {
		B(8, 0.3, "Открутить АКПП от двигателя"),
		A("Снять АКПП", 5),
		A("Заменить фрикционы", 6, { at_clutches = 1 }),
		A("Заменить гидротрансформатор", 5, { at_torque = 1 }),
		A("Поставить АКПП, новый фильтр и ATF", 5, { at_filter = 1, atf = 3 }),
		W("Адаптация и прогрев АКПП", 240),
	  } },
	{ id = "cvt_service", gearbox = "cvt", name = "Вариатор: замена жидкости CVT и фильтра", worker = "mechanic", reward = 280, lift = "jack", pit = true,
	  steps = {
		B(1, 0.3, "Открутить сливную пробку вариатора"),
		A("Слить старую жидкость CVT", 3),
		W("Дать жидкости стечь", 60),
		A("Заменить фильтр вариатора", 3, { cvt_filter = 1 }),
		A("Залить жидкость CVT", 3, { cvt_fluid = 2 }),
	  } },
	{ id = "cvt_valve", gearbox = "cvt", hidden = true, code = "P0868", name = "Вариатор: падает давление", reward = 420, lift = "jack", pit = true,
	  steps = {
		B(4, 0.2, "Открутить поддон вариатора"),
		A("Заменить клапан давления", 4, { cvt_valve = 1 }),
		A("Долить жидкость CVT", 2, { cvt_fluid = 1 }),
		A("Сбросить ошибку сканером", 2, nil, { "scanner" }),
	  } },
	{ id = "cvt_repair", gearbox = "cvt", name = "Вариатор гудит и дёргается", reward = 760, lift = "lift",
	  steps = {
		B(8, 0.3, "Открутить вариатор от двигателя"),
		A("Снять вариатор", 5),
		A("Заменить ремень вариатора", 5, { cvt_belt = 1 }),
		A("Заменить шкив", 5, { cvt_pulley = 1 }),
		A("Поставить вариатор, фильтр и жидкость", 5, { cvt_filter = 1, cvt_fluid = 3 }),
		W("Адаптация вариатора", 180),
	  } },

	-- ДВИГАТЕЛЬ: два варианта ремонта
	{ id = "engine", name = "Стук в двигателе", lift = "lift", rare = true,
	  variants = {
		{ id = "new", name = "Поставить новый двигатель", reward = 3300,
		  steps = {
			B(6, 0.35, "Открутить подушки и навесное"),
			A("Вынуть старый двигатель краном", 5, nil, { "hoist" }),
			A("Поставить новый двигатель", 6, { engine_new = 1 }, { "hoist" }),
			A("Затянуть подушки двигателя", 2),
			A("Залить масло и антифриз", 3, { oil = 1, coolant = 1 }),
		  } },
		{ id = "overhaul", name = "Капиталка на стенде", reward = 2700,
		  steps = {
			B(6, 0.35, "Открутить подушки и навесное"),
			A("Вынуть двигатель краном", 5, nil, { "hoist" }),
			A("Закрепить двигатель на стенде", 3, nil, nil, "engine_stand"),
			B(8, 0.3, "Разобрать: ГБЦ, поддон, крышки шатунов", "engine_stand"),
			A("Отмыть детали и болты бензином", 5, { gasoline = 2 }, nil, "parts_washer"),
			A("Заменить клапаны", 5, { valves = 1 }, { "valve_tool" }, "engine_stand"),
			A("Заменить поршни и кольца", 5, { pistons = 1, assembly_lube = 1 }, { "ring_compressor" }, "engine_stand"),
			A("Заменить шатуны и вкладыши", 4, { rods = 1, assembly_lube = 1 }, nil, "engine_stand"),
			A("Поставить все прокладки на герметик", 4, { gasket_set = 1, sealant = 1 }, nil, "engine_stand"),
			W("Герметик прокладок схватывается", 300, "engine_stand"),
			T("Собрать двигатель с моментом затяжки", "engine_stand"),
			A("Вернуть двигатель в машину краном", 5, nil, { "hoist" }),
			A("Залить масло и антифриз", 3, { oil = 1, coolant = 1 }),
		  } },
	  } },
}
Config.FaultById = {}
for _, f in ipairs(Config.Faults) do
	Config.FaultById[f.id] = f
end

Config.Stations = {
	tire_changer = "Шиномонтажный станок",
	balancer = "Балансировочный станок",
	engine_stand = "Стенд для двигателя",
	parts_washer = "Мойка деталей",
}

-- Модели машин: body = тип кузова (sedan, hatch, wagon, suv, pickup, van, coupe, classic)
-- СВОИ МОДЕЛИ МАШИН ИЗ TOOLBOX
-- 1. Вставьте машину из Toolbox и перетащите её в ServerStorage → CarModels.
-- 2. Всё: она сама попадёт в игру под именем модели (или атрибута DisplayName).
-- Можно привязать модель к машине из списка ниже: { name = "Лада 2107", body = "classic", model = "Lada2107" }
-- Доп. поля (или атрибуты на самой модели в скобках):
--   model  — точное имя модели в папке CarModels
--   turn   (Turn)   — поворот в градусах: 180, если машина заезжает задом; 90 / -90, если боком
--   length (Length) — длина в стадах (по умолчанию как у кузова body: седан 14, фургон 16)
--   scale  (Scale)  — точный множитель размера вместо length (1 = как в Toolbox)
--   paint  (Paint)  — часть имени деталей кузова для случайного цвета (например "Body"), иначе цвет оригинала
--   body   (Body)   — тип кузова для размера: sedan, hatch, wagon, suv, pickup, van, coupe, classic
Config.OnlyCustomCars = false      -- true: если есть свои модели, приезжают только они (без блочных)
Config.CustomCarsInTraffic = true  -- false: на улице ездят простые блочные машины (меньше лагов)

Config.CarModels = {
	{ name = "Лада 2107", body = "classic" },
	{ name = "Нива 4x4", body = "suv" },
	{ name = "Тойота Камри", body = "sedan" },
	{ name = "БМВ E39", body = "sedan" },
	{ name = "Фольксваген Гольф", body = "hatch" },
	{ name = "Хёндай Солярис", body = "sedan" },
	{ name = "Мерседес W124 универсал", body = "wagon" },
	{ name = "Форд Транзит", body = "van" },
	{ name = "Тойота Хайлюкс", body = "pickup" },
	{ name = "Ниссан 350Z", body = "coupe" },
	{ name = "Шкода Октавия универсал", body = "wagon" },
	{ name = "Лэнд Крузер", body = "suv" },
}
-- КОРОБКИ ПЕРЕДАЧ у машин клиентов (weight = как часто встречается)
Config.Gearboxes = {
	{ id = "mt",  name = "МКПП",     weight = 4 },
	{ id = "at",  name = "АКПП",     weight = 4 },
	{ id = "cvt", name = "Вариатор", weight = 2 },
}
Config.GearboxFaultChance = 0.35   -- шанс, что у машины будет неисправность коробки

-- СЕЗОНЫ: лето и долгая снежная зима (в игровых сутках; сутки = DayLength сек)
Config.SummerDays = 3
Config.WinterDays = 3              -- 3 игровых суток = 36 минут снега
Config.TireSwapChance = 0.55       -- зимой: шанс, что клиент едет переобуваться на зимнюю
Config.SummerSwapDays = 1          -- сколько игровых суток после таяния клиенты едут на летнюю резину

-- VIP-КЛИЕНТЫ (только у владельцев VIP-пасса)
-- Свои модели: создайте в ServerStorage папку VipCarModels и положите туда модели машин (как в CarModels).
-- Они добавятся сами. Если папка пуста — приезжают блочные машины из списка ниже в «премиальных» цветах.
Config.VipCarChance = 0.3          -- доля VIP-клиентов
Config.VipRewardMult = 1.5         -- VIP-клиент платит в 1.5 раза больше (и ремонт, и чаевые)
Config.VipCarModels = {
	{ name = "Мерседес S-класс", body = "sedan" },
	{ name = "Порше 911", body = "coupe" },
	{ name = "Рендж Ровер", body = "suv" },
}
Config.VipCarColors = {
	Color3.fromRGB(15, 15, 18), Color3.fromRGB(212, 175, 55), Color3.fromRGB(235, 235, 240), Color3.fromRGB(110, 20, 30),
}

Config.CarColors = {
	Color3.fromRGB(200, 40, 40), Color3.fromRGB(40, 90, 200), Color3.fromRGB(240, 240, 240),
	Color3.fromRGB(30, 30, 30), Color3.fromRGB(60, 150, 70), Color3.fromRGB(230, 180, 40),
	Color3.fromRGB(120, 120, 130), Color3.fromRGB(90, 30, 40), Color3.fromRGB(20, 50, 90),
	Color3.fromRGB(230, 110, 30), Color3.fromRGB(170, 200, 220), Color3.fromRGB(70, 60, 50),
}

-- Сервер: максимум 4 игрока, у каждого свой бокс
Config.MaxPlots = 4
Config.DefaultShopName = "Старая мастерская"
Config.ShopNameMax = 24

-- Сюжет и обучение
Config.MentorName = "Дед Михалыч"
Config.IntroLines = {
	"Ты долго копил деньги, работая подмастерьем в чужих сервисах...",
	"И вот наконец решился: выкупил старую заброшенную автомастерскую на окраине города.",
	"Крыша течёт, вывеска упала, инструментов почти нет. Зато она — твоя.",
	"Бывший хозяин, дед Михалыч, обещал показать, с чего начать.",
}
Config.Tutorial = {
	{ id = "talk1",   text = "Поговорите с дедом Михалычем у входа" },
	{ id = "bank",    text = "Денег на запчасти не хватает! Выйдите на улицу, найдите 🏦 БАНК и возьмите кредит без процентов $150" },
	{ id = "buy",     text = "Компьютер на стойке администратора: закажите Моторное масло (вкладка «Тех. жидкости») и Масляный фильтр (вкладка «Запчасти»)" },
	{ id = "wait",    text = "Ждите доставку деталей на склад" },
	{ id = "car",     text = "Первый клиент на парковке за мастерской! Подойдите к машине, нажмите E «Сесть за руль» и отгоните её на пост 1 (с ямой)" },
	{ id = "repair",  text = "Нажмите E «Осмотреть» у машины, начните «Пора менять масло» и выполните шаги (спуститесь в яму). Ржавый болт 🟤 лучше обработать WD-40. Шаг ⏳ идёт сам — просто подождите" },
	{ id = "talk2",   text = "Отлично! Поговорите с Михалычем ещё раз" },
	{ id = "name",    text = "Придумайте название своей мастерской" },
}

return Config
