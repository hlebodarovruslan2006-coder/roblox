-- DataSave (ModuleScript, ServerScriptService → Modules)
-- Надёжные сохранения: повторные попытки, UpdateAsync, очередь, ожидание при выключении сервера.

local DataStoreService = game:GetService("DataStoreService")

local M = {}

local RETRIES = 4
local store = nil
local saving = {} -- key -> true, пока идёт запись
local queued = {} -- key -> самые свежие данные, пришедшие во время записи

function M.init(name)
	local ok, res = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)
	if ok then
		store = res
	else
		warn("[DataSave] DataStore недоступен: " .. tostring(res))
	end
	return store ~= nil
end

function M.available()
	return store ~= nil
end

-- ждём, пока у Roblox есть лимит запросов (иначе запрос просто встанет в очередь/упадёт)
local function waitBudget(kind)
	for _ = 1, 20 do
		local ok, b = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(kind)
		end)
		if not ok or b > 0 then
			return
		end
		task.wait(0.5)
	end
end

-- ошибки, при которых повторять бессмысленно (например, в Studio выключен доступ к API)
local function fatal(err)
	local s = tostring(err)
	return string.find(s, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(s, "API access", 1, true) ~= nil
		or string.find(s, "403", 1, true) ~= nil
end

-- возвращает ok, data. ok = false — загрузить не удалось, сохранять такую сессию НЕЛЬЗЯ.
function M.load(key)
	if not store then
		return true, nil
	end
	for i = 1, RETRIES do
		waitBudget(Enum.DataStoreRequestType.GetAsync)
		local ok, res = pcall(function()
			return store:GetAsync(key)
		end)
		if ok then
			return true, res
		end
		warn(("[DataSave] Загрузка %s, попытка %d: %s"):format(key, i, tostring(res)))
		if fatal(res) then
			break
		end
		if i < RETRIES then
			task.wait(i * 1.5)
		end
	end
	return false, nil
end

-- запись с повторами. Если запись уже идёт — новые данные запишутся сразу после неё.
function M.save(key, data)
	if not store then
		return false
	end
	if saving[key] then
		queued[key] = data
		return true
	end
	saving[key] = true
	local success = false
	local current = data
	while current do
		queued[key] = nil
		local payload = current
		success = false
		for i = 1, RETRIES do
			waitBudget(Enum.DataStoreRequestType.UpdateAsync)
			local ok, err = pcall(function()
				store:UpdateAsync(key, function()
					return payload
				end)
			end)
			if ok then
				success = true
				break
			end
			warn(("[DataSave] Сохранение %s, попытка %d: %s"):format(key, i, tostring(err)))
			if fatal(err) then
				break
			end
			if i < RETRIES then
				task.wait(i * 1.5)
			end
		end
		current = queued[key]
	end
	saving[key] = nil
	return success
end

-- ждём окончания всех записей (для BindToClose)
function M.waitAll(timeout)
	local t0 = os.clock()
	while next(saving) and os.clock() - t0 < (timeout or 25) do
		task.wait(0.1)
	end
end

return M
