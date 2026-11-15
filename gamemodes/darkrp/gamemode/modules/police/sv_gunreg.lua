--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Реестр серийных номеров оружия (база данных N.L.R.)

	darkrp_gunreg: id - номер, class - класс оружия, passid - персонаж, на
	которого записан номер (DarkRP.CharacterID), state - 0 действует, 1 спилен,
	2 ствол разобран; stamp - когда запись менялась (os.time)

	DarkRP.NewGunSerial(class, passid) - новый номер: 8 случайных цифр, первая
	  не ноль (стол оружейника, экран регистрации для ствола без номера).
	  Номер не повторяется никогда: спиленные и разобранные тоже заняты
	DarkRP.GunRegister(id, class, passid) - номер на другого владельца
	  (экран регистрации, inventory/sv_registers.lua)
	DarkRP.GunErase(id, class, passid) - номер спилен (рабочий стол)
	DarkRP.GunDestroy(id, class, passid) - ствол разобран (компонент рецепта)
	  class и passid нужны, только если номера нет в реестре (выдан до него)
	DarkRP.GunLookup(id) - запись {class, passid, state, stamp} или nil

	Владельца по номеру ищет вкладка "Оружие" компьютера участка
	(slawer_mayor/modules/policemen/sv_guns.lua). Записи живут в памяти,
	при старте загружаются из базы; номер, выданный до загрузки, база не
	затирает - он запишется после неё.
---------------------------------------------------------------------------]]
local SERIAL_DIGITS = 8
local MAX_ID = 16

DarkRP.GUN_ACTIVE = 0
DarkRP.GUN_ERASED = 1
DarkRP.GUN_DESTROYED = 2

DarkRP.GunRegistry = DarkRP.GunRegistry or {}

local registry = DarkRP.GunRegistry

local function dbError(err, query)
	MsgC(Color(255, 90, 0), "[N.L.R.] SQL: " .. tostring(err) .. "\n    " .. tostring(query) .. "\n")
end

-- номер: только цифры (у старых стволов их 6-10)
local function validId(id)
	if not isstring(id) and not isnumber(id) then return nil end

	id = tostring(id)

	return #id <= MAX_ID and string.match(id, "^%d+$") and id or nil
end

local function save(id)
	local rec = registry[id]
	if not rec then return end

	-- база ещё не загружена: запишется после загрузки
	if not DarkRP.GunRegistryLoaded then
		rec.unsaved = true
		return
	end

	rec.unsaved = nil

	MySQLite.query(string.format("REPLACE INTO darkrp_gunreg(id, class, passid, state, stamp) VALUES(%s, %s, %s, %d, %d)",
		MySQLite.SQLStr(id), MySQLite.SQLStr(rec.class), MySQLite.SQLStr(rec.passid), rec.state, rec.stamp
	), nil, dbError)
end

-- class, passid = nil - не менять
local function setRecord(id, state, class, passid)
	local rec = registry[id]

	if not rec then
		rec = {class = "", passid = ""}
		registry[id] = rec
	end

	if class ~= nil then rec.class = string.sub(tostring(class), 1, 64) end
	if passid ~= nil then rec.passid = string.sub(tostring(passid), 1, 32) end

	rec.state = state
	rec.stamp = os.time()

	save(id)

	return rec
end

hook.Add("DatabaseInitialized", "DarkRP.GunRegistry", function()
	MySQLite.query([[CREATE TABLE IF NOT EXISTS darkrp_gunreg(
		id VARCHAR(16) NOT NULL PRIMARY KEY,
		class VARCHAR(64) NOT NULL,
		passid VARCHAR(32) NOT NULL,
		state INTEGER NOT NULL DEFAULT 0,
		stamp INTEGER NOT NULL DEFAULT 0
	)]], function()
		MySQLite.query("SELECT id, class, passid, state, stamp FROM darkrp_gunreg", function(rows)
			for _, row in ipairs(istable(rows) and rows or {}) do
				local id = validId(row.id)

				-- выданный до загрузки номер новее записи в базе
				if id and not registry[id] then
					registry[id] = {
						class = tostring(row.class or ""),
						passid = tostring(row.passid or ""),
						state = math.floor(tonumber(row.state) or 0),
						stamp = math.floor(tonumber(row.stamp) or 0),
					}
				end
			end

			DarkRP.GunRegistryLoaded = true

			for id, rec in pairs(registry) do
				if rec.unsaved then save(id) end
			end
		end, dbError)
	end, dbError)
end)

function DarkRP.NewGunSerial(class, passid)
	local id

	repeat
		local digits = {math.random(1, 9)}

		for i = 2, SERIAL_DIGITS do
			digits[i] = math.random(0, 9)
		end

		id = table.concat(digits)
	until not registry[id]

	setRecord(id, DarkRP.GUN_ACTIVE, class or "", passid or "")

	return id
end

function DarkRP.GunRegister(id, class, passid)
	id = validId(id)
	if not id then return false end

	setRecord(id, DarkRP.GUN_ACTIVE, class or "", passid or "")

	return true
end

-- запись в реестре главнее данных предмета
local function closeRecord(id, state, class, passid)
	id = validId(id)
	if not id then return false end

	local known = registry[id] ~= nil

	setRecord(id, state, not known and (class or "") or nil, not known and (passid or "") or nil)

	return true
end

function DarkRP.GunErase(id, class, passid)
	return closeRecord(id, DarkRP.GUN_ERASED, class, passid)
end

function DarkRP.GunDestroy(id, class, passid)
	return closeRecord(id, DarkRP.GUN_DESTROYED, class, passid)
end

function DarkRP.GunLookup(id)
	id = validId(id)

	return id and registry[id] or nil
end
