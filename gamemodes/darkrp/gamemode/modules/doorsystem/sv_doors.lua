--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Двери и машины: серверная часть (шаг 9)
	Общие проверки - sh_doors.lua, приём на клиенте - cl_doors.lua, команды F2 - sv_doorcommands.lua

	Данные: ent.DoorData = {owner = UserID, extraOwners = {[UserID] = true}, allowedToOwn = {[UserID] = true},
		teamOwn = {[команда] = true}, groupOwn = "NYPD", nonOwnable = true, title = "..."}
	false и пустые таблицы не хранятся (nil) - так их видит и клиент
	Замок: ent.IsUnLocked = true - открыто (по нему ключи выбирают «открыть» или «закрыть»), nil - заперто;
		следит за входами lock/unlock двери (ключи, таран, отмычка, логика карты)

	Настройка дверей карты - при старте и после очистки карты (DarkRP.setupDoors):
		1. RemoveProps из конфига карты удаляются
		2. все двери карты по умолчанию нельзя купить (nonOwnable)
		3. хук DarkRP.SetupDoors: территории (modules/territory/sv_init.lua) раздают свои двери
		4. настройки администраторов из базы (darkrp_doorsettings, меню F2 «Управление») - поверх
		5. клиентам уходит полный список
	Конфиг карты: AutoClose - открытая дверь закрывается сама; ExtraDoors - кому можно ключами (canKeysLock)
---------------------------------------------------------------------------]]
local meta = FindMetaTable("Entity")
local pmeta = FindMetaTable("Player")

util.AddNetworkString("DarkRP_AllDoorData")
util.AddNetworkString("DarkRP_UpdateDoorData")
util.AddNetworkString("DarkRP_RemoveDoorVar")
util.AddNetworkString("DarkRP_RemoveDoorData")
util.AddNetworkString("DarkRP_ResetDoorData")

-- двери карты (то же, что isKeysOwnable без машин)
DarkRP.DoorClasses = {
	func_door = true,
	func_door_rotating = true,
	prop_door_rotating = true,
	func_movelinear = true,
}

local DOOR_CLASSES = DarkRP.DoorClasses

local AUTOCLOSE_STEP = 2 -- проверка дверей AutoClose, секунд
local AUTOCLOSE_DELAY = 15 -- дверь AutoClose закрывается, простояв открытой столько секунд
local SETUP_DELAY = 1 -- после InitPostEntity: логика карты успевает запереть свои двери

local SETTING_VARS = {title = true, nonOwnable = true, group = true, jobs = true}

local registry = setmetatable({}, {__mode = "k"}) -- сущности с данными двери
local batch = 0 -- > 0: изменения не рассылаются по одному, в конце уходит полный список
local cleaning = false -- очистка карты: удаление дверей не рассылается

local function readyPlayers()
	local list = {}

	for _, ply in ipairs(player.GetHumans()) do
		if ply.DarkRPClientReady then list[#list + 1] = ply end
	end

	return list
end

--[[---------------------------------------------------------------------------
	Данные
---------------------------------------------------------------------------]]
function meta:getDoorData()
	-- не дверь и не машина: пустая таблица, никуда не сохраняется
	if not IsValid(self) or not self:isKeysOwnable() then return {} end

	local data = self.DoorData

	if not data then
		data = {}
		self.DoorData = data
		registry[self] = true
	end

	return data
end

--[[---------------------------------------------------------------------------
	Сеть
	DarkRP_UpdateDoorData: UInt32 EntIndex, переменная (DarkRP.writeNetDoorVar)
	DarkRP_RemoveDoorVar: UInt16 EntIndex, UInt8 id переменной (0 - дальше String имя)
	DarkRP_AllDoorData: UInt16 число дверей; по каждой UInt16 EntIndex, UInt8 число переменных, переменные
	DarkRP_RemoveDoorData: UInt32 EntIndex
	DarkRP_ResetDoorData: без данных - клиент забывает все двери (перед полным списком после очистки карты)
---------------------------------------------------------------------------]]
function DarkRP.updateDoorData(door, member, target)
	if not IsValid(door) or not registry[door] or not isstring(member) then return end
	if batch > 0 and not target then return end

	local recipients = target or readyPlayers()
	if istable(recipients) and #recipients == 0 then return end

	local value = door.DoorData[member]

	if value == nil then
		local var = DarkRP.getDoorVarsByName()[member]

		net.Start("DarkRP_RemoveDoorVar")
			net.WriteUInt(door:EntIndex(), 16)
			net.WriteUInt(var and var.id or 0, 8)
			if not var then net.WriteString(member) end
		net.Send(recipients)

		return
	end

	net.Start("DarkRP_UpdateDoorData")
		net.WriteUInt(door:EntIndex(), 32)
		DarkRP.writeNetDoorVar(member, value)
	net.Send(recipients)
end

function DarkRP.sendAllDoorData(target, reset)
	target = target or readyPlayers()
	if istable(target) and #target == 0 then return end

	if reset then
		net.Start("DarkRP_ResetDoorData")
		net.Send(target)
	end

	local list = {}

	for door in pairs(registry) do
		if IsValid(door) and door.DoorData and next(door.DoorData) ~= nil then
			list[#list + 1] = door
		end
	end

	net.Start("DarkRP_AllDoorData")
		net.WriteUInt(#list, 16)

		for _, door in ipairs(list) do
			local names = {}
			for name in pairs(door.DoorData) do names[#names + 1] = name end

			net.WriteUInt(door:EntIndex(), 16)
			net.WriteUInt(#names, 8)

			for _, name in ipairs(names) do
				DarkRP.writeNetDoorVar(name, door.DoorData[name])
			end
		end
	net.Send(target)
end

-- много изменений сразу (настройка карты): одна рассылка полным списком в конце
local function runBatch(fn, ...)
	batch = batch + 1
	local ok, err = xpcall(fn, debug.traceback, ...)
	batch = batch - 1

	if not ok then
		ErrorNoHalt("[DarkRP] Двери: " .. tostring(err) .. "\n")
	end

	DarkRP.sendAllDoorData(nil, true)
end

hook.Add("DarkRP.PlayerLoaded", "DarkRP.Doors", function(ply)
	DarkRP.sendAllDoorData(ply)
end)

-- запрос клиента (запасной, cl_init его не шлёт)
concommand.Add("_sendAllDoorData", function(ply)
	if not IsValid(ply) or DarkRP.NetDelay(ply, 5) then return end
	DarkRP.sendAllDoorData(ply)
end)

hook.Add("EntityRemoved", "DarkRP.Doors", function(ent)
	if not registry[ent] then return end
	registry[ent] = nil

	local owner = ent.DoorData and ent.DoorData.owner and Player(ent.DoorData.owner)

	if IsValid(owner) and owner.Ownedz and owner.Ownedz[ent:EntIndex()] then
		owner.Ownedz[ent:EntIndex()] = nil
		owner.OwnedNumz = math.max((owner.OwnedNumz or 1) - 1, 0)
	end

	if cleaning or batch > 0 then return end

	local recipients = readyPlayers()
	if #recipients == 0 then return end

	net.Start("DarkRP_RemoveDoorData")
		net.WriteUInt(ent:EntIndex(), 32)
	net.Send(recipients)
end)

--[[---------------------------------------------------------------------------
	Замки
---------------------------------------------------------------------------]]
function meta:keysLock()
	if not IsValid(self) then return end

	self:Fire("lock", "", 0)
	if isfunction(self.Lock) then self:Lock(true) end -- машины со своим замком
	self.IsUnLocked = nil

	hook.Run("onKeysLocked", self)
end

function meta:keysUnLock()
	if not IsValid(self) then return end

	self:Fire("unlock", "", 0)
	if isfunction(self.UnLock) then self:UnLock(true) end
	self.IsUnLocked = true

	hook.Run("onKeysUnlocked", self)
end

-- двери карты: начальное состояние замка (m_bLocked есть у func_door и prop_door_rotating)
local function initLockState(ent)
	local locked = ent:GetInternalVariable("m_bLocked")
	ent.IsUnLocked = not locked or nil
end

-- входы lock/unlock от кого угодно (таран, логика карты, территории) - замок ключей не врёт
hook.Add("AcceptInput", "DarkRP.DoorLockState", function(ent, input)
	if not IsValid(ent) or not isstring(input) then return end
	if not DOOR_CLASSES[ent:GetClass()] and not ent:IsVehicle() then return end

	input = string.lower(input)

	if input == "lock" then
		ent.IsUnLocked = nil
	elseif input == "unlock" then
		ent.IsUnLocked = true
	end
end)

--[[---------------------------------------------------------------------------
	Владение
---------------------------------------------------------------------------]]
local function setFlag(door, field, key, on)
	if key == nil then return end

	local data = door:getDoorData()
	local tbl = data[field]

	if on then
		if tbl and tbl[key] then return end

		tbl = tbl or {}
		tbl[key] = true
		data[field] = tbl
	else
		if not tbl or not tbl[key] then return end

		tbl[key] = nil
		if next(tbl) == nil then data[field] = nil end
	end

	DarkRP.updateDoorData(door, field)
end

local function clearFlags(door, field)
	local data = door:getDoorData()
	if data[field] == nil then return end

	data[field] = nil
	DarkRP.updateDoorData(door, field)
end

local function addOwned(ply, door)
	ply.Ownedz = ply.Ownedz or {}
	if ply.Ownedz[door:EntIndex()] then return end

	ply.Ownedz[door:EntIndex()] = door
	ply.OwnedNumz = (ply.OwnedNumz or 0) + 1
end

local function removeOwned(ply, door)
	if not IsValid(ply) or not ply.Ownedz or not ply.Ownedz[door:EntIndex()] then return end

	ply.Ownedz[door:EntIndex()] = nil
	ply.OwnedNumz = math.max((ply.OwnedNumz or 1) - 1, 0)
end

-- приглашённый (allowedToOwn) к чужой двери получает ключи совладельца; к свободной - становится хозяином
function meta:keysOwn(ply)
	if not IsValid(self) or not IsValid(ply) or not ply:IsPlayer() then return end

	if self:isKeysOwned() then
		if not self:isKeysOwnedBy(ply) then self:addKeysDoorOwner(ply) end
		return
	end

	local data = self:getDoorData()

	data.owner = ply:UserID()
	DarkRP.updateDoorData(self, "owner")
	self:removeKeysAllowedToOwn(ply)

	if self:IsVehicle() and isfunction(self.CPPISetOwner) then
		self:CPPISetOwner(ply)
	end

	addOwned(ply, self)
end

-- без игрока или хозяин: дверь освобождается целиком (совладельцы, приглашения, название); иначе уходит совладелец
function meta:keysUnOwn(ply)
	if not IsValid(self) then return end

	local data = self:getDoorData()
	local owner = self:getDoorOwner()

	if ply ~= nil and ply ~= owner then
		self:removeKeysDoorOwner(ply)
		return
	end

	self:removeAllKeysExtraOwners()
	self:removeAllKeysAllowedToOwn()

	if data.owner ~= nil then
		data.owner = nil
		DarkRP.updateDoorData(self, "owner")
	end

	self:setKeysTitle(nil)
	self.DoorBoughtFor = nil

	removeOwned(owner, self)
end

function meta:setKeysNonOwnable(value)
	local data = self:getDoorData()
	value = value and true or nil

	if data.nonOwnable == value then return end

	data.nonOwnable = value
	DarkRP.updateDoorData(self, "nonOwnable")
end

-- пустое название у свободной двери - название администратора (DoorBaseTitle), если оно есть
function meta:setKeysTitle(title)
	local data = self:getDoorData()

	if title ~= nil then title = tostring(title) end
	if title == "" then title = nil end
	if title == nil and not self:isKeysOwned() then title = self.DoorBaseTitle end

	if data.title == title then return end

	data.title = title
	DarkRP.updateDoorData(self, "title")
end

function meta:setDoorGroup(group)
	local data = self:getDoorData()

	if group ~= nil and not (RPExtraTeamDoors[group] and RPExtraTeamDoorIDs[group]) then group = nil end
	if data.groupOwn == group then return end

	data.groupOwn = group
	DarkRP.updateDoorData(self, "groupOwn")
end

function meta:addKeysDoorTeam(t)
	setFlag(self, "teamOwn", tonumber(t), true)
end

function meta:removeKeysDoorTeam(t)
	setFlag(self, "teamOwn", tonumber(t), false)
end

function meta:removeAllKeysDoorTeams()
	clearFlags(self, "teamOwn")
end

function meta:addKeysAllowedToOwn(ply)
	if not IsValid(ply) then return end
	setFlag(self, "allowedToOwn", ply:UserID(), true)
end

function meta:removeKeysAllowedToOwn(ply)
	if not IsValid(ply) then return end
	setFlag(self, "allowedToOwn", ply:UserID(), false)
end

function meta:removeAllKeysAllowedToOwn()
	clearFlags(self, "allowedToOwn")
end

function meta:addKeysDoorOwner(ply)
	if not IsValid(ply) then return end

	setFlag(self, "extraOwners", ply:UserID(), true)
	self:removeKeysAllowedToOwn(ply)
end

function meta:removeKeysDoorOwner(ply)
	if not IsValid(ply) then return end
	setFlag(self, "extraOwners", ply:UserID(), false)
end

function meta:removeAllKeysExtraOwners()
	clearFlags(self, "extraOwners")
end

function meta:removeDoorData()
	if not registry[self] then return end

	registry[self] = nil
	self.DoorData = nil

	local recipients = readyPlayers()
	if #recipients == 0 then return end

	net.Start("DarkRP_RemoveDoorData")
		net.WriteUInt(self:EntIndex(), 32)
	net.Send(recipients)
end

-- отдельные двери и машины игрока (двери помещений освобождает территория), его ключи и приглашения у чужих дверей
function pmeta:keysUnOwnAll()
	for _, door in pairs(self.Ownedz or {}) do
		if IsValid(door) and not door.DoorTerritory and door:isMasterOwner(self) then
			door:keysUnOwn(self)
			door:keysUnLock()
		end
	end

	local id = self:UserID()

	for door in pairs(registry) do
		local data = IsValid(door) and door.DoorData

		if data then
			if data.extraOwners and data.extraOwners[id] then door:removeKeysDoorOwner(self) end
			if data.allowedToOwn and data.allowedToOwn[id] then door:removeKeysAllowedToOwn(self) end
		end
	end

	local kept = {}

	for idx, door in pairs(self.Ownedz or {}) do
		if IsValid(door) and door:isMasterOwner(self) then kept[idx] = door end
	end

	self.Ownedz = kept
	self.OwnedNumz = table.Count(kept)
end

-- смена персонажа ключи не забирает: двери на аккаунте (ваш ответ к 11.3)
hook.Add("PlayerDisconnected", "DarkRP.Doors", function(ply)
	ply:keysUnOwnAll()
end)

--[[---------------------------------------------------------------------------
	Настройки администраторов (меню F2 «Управление»), таблица darkrp_doorsettings
	Ключ - карта и MapCreationID двери; var: title - название; nonOwnable - '1'/'0';
	group - группа дверей ('' - без группы); jobs - команды работ через запятую ('' - нет)
	nonOwnable/group/jobs - дверь настроена вручную: она выходит из помещения (территории)
---------------------------------------------------------------------------]]
local MAP = string.lower(game.GetMap())
local settings = {}
local settingsLoaded = false
local setupDone = false

local function dbError(err, q)
	ErrorNoHalt("[DarkRP] Двери: ошибка базы данных: " .. tostring(err) .. (q and (" (" .. tostring(q) .. ")") or "") .. "\n")
end

local function saveVar(id, var, value)
	if value == nil then
		MySQLite.query(string.format("DELETE FROM darkrp_doorsettings WHERE map = %s AND idx = %d AND var = %s",
			MySQLite.SQLStr(MAP), id, MySQLite.SQLStr(var)), nil, dbError)
		return
	end

	MySQLite.query(string.format("REPLACE INTO darkrp_doorsettings(map, idx, var, value) VALUES(%s, %d, %s, %s)",
		MySQLite.SQLStr(MAP), id, MySQLite.SQLStr(var), MySQLite.SQLStr(value)), nil, dbError)
end

local function hasOverride(s)
	return s ~= nil and (s.nonOwnable ~= nil or s.group ~= nil or s.jobs ~= nil)
end

function DarkRP.isDoorOverridden(door)
	return IsValid(door) and hasOverride(settings[door:MapCreationID()]) or false
end

function DarkRP.getDoorSettings(door)
	return IsValid(door) and settings[door:MapCreationID()] or nil
end

function DarkRP.doorSettingsReady()
	return settingsLoaded
end

-- titleOnly: изменилось только название - хозяин и ключи остаются (иначе дверь настраивается заново)
local function applySetting(door, s, titleOnly)
	if not IsValid(door) or not s then return end

	door.DoorBaseTitle = s.title

	if not titleOnly and hasOverride(s) then
		if door.DoorTerritory then hook.Run("DarkRP.DoorOverridden", door, door.DoorTerritory) end
		door.DoorTerritory = nil

		door:keysUnOwn()
		door:removeAllKeysDoorTeams()

		local group = s.group ~= "" and s.group or nil
		local teams = {}

		for cmd in string.gmatch(s.jobs or "", "[^,]+") do
			local _, idx = DarkRP.getJobByCommand(cmd)
			if idx then teams[#teams + 1] = idx end
		end

		door:setDoorGroup(group)
		door:setKeysNonOwnable(s.nonOwnable == "1" and not group and #teams == 0)

		for _, idx in ipairs(teams) do
			door:addKeysDoorTeam(idx)
		end
	end

	if not door:isKeysOwned() then door:setKeysTitle(nil) end
end

-- values: {var = значение или nil}; сохраняется и сразу применяется
function DarkRP.setDoorSettings(door, values)
	local id = door:MapCreationID()
	if id < 0 then return end

	local s = settings[id] or {}
	settings[id] = s

	local titleOnly = true

	for var, value in pairs(values) do
		if SETTING_VARS[var] then
			if value == false then value = nil end
			if var ~= "title" then titleOnly = false end
			s[var] = value
			saveVar(id, var, value)
		end
	end

	if next(s) == nil then settings[id] = nil end

	applySetting(door, s, titleOnly)
end

-- «Убрать все»: ручные настройки (кроме названия) снимаются, дверь возвращается к обычной (помещение или закрыта)
function DarkRP.resetDoorSettings(door)
	local id = door:MapCreationID()
	local s = settings[id]

	if s then
		for _, var in ipairs({"nonOwnable", "group", "jobs"}) do
			if s[var] ~= nil then
				s[var] = nil
				saveVar(id, var, nil)
			end
		end

		if next(s) == nil then settings[id] = nil end
	end

	if door.DoorTerritory then hook.Run("DarkRP.DoorOverridden", door, door.DoorTerritory) end
	door.DoorTerritory = nil

	door:keysUnOwn()
	door:removeAllKeysDoorTeams()
	door:setDoorGroup(nil)
	door:setKeysNonOwnable(true)

	return hook.Run("DarkRP.DoorReset", door)
end

local function applyAllSettings()
	for id, s in pairs(settings) do
		applySetting(ents.GetMapCreatedEntity(id), s)
	end
end

local function onSettingsLoaded()
	if settingsLoaded then return end
	settingsLoaded = true

	-- MySQL ответила после настройки дверей
	if setupDone then runBatch(applyAllSettings) end
end

hook.Add("DatabaseInitialized", "DarkRP.Doors", function()
	MySQLite.query([[CREATE TABLE IF NOT EXISTS darkrp_doorsettings(
		map VARCHAR(45) NOT NULL,
		idx INTEGER NOT NULL,
		var VARCHAR(16) NOT NULL,
		value TEXT NOT NULL,
		PRIMARY KEY(map, idx, var)
	)]], function()
		MySQLite.query("SELECT idx, var, value FROM darkrp_doorsettings WHERE map = " .. MySQLite.SQLStr(MAP), function(rows)
			settings = {}

			for _, row in ipairs(rows or {}) do
				local id = tonumber(row.idx)

				if id and SETTING_VARS[row.var] and row.value ~= nil then
					settings[id] = settings[id] or {}
					settings[id][row.var] = tostring(row.value)
				end
			end

			onSettingsLoaded()
		end, function(err, q)
			dbError(err, q)
			onSettingsLoaded()
		end)
	end, function(err, q)
		dbError(err, q)
		onSettingsLoaded()
	end)
end)

--[[---------------------------------------------------------------------------
	Настройка дверей карты
---------------------------------------------------------------------------]]
local function removeProps()
	for id in pairs(GAMEMODE.Config.RemoveProps or {}) do
		local ent = ents.GetMapCreatedEntity(id)
		if IsValid(ent) then ent:Remove() end
	end
end

local function setupDoors()
	removeProps()

	for _, ent in ipairs(ents.GetAll()) do
		if IsValid(ent) and DOOR_CLASSES[ent:GetClass()] and ent:MapCreationID() >= 0 then
			initLockState(ent)
			ent.DoorTerritory = nil
			ent:setKeysNonOwnable(true)
		end
	end

	hook.Run("DarkRP.SetupDoors")

	if settingsLoaded then applyAllSettings() end

	setupDone = true
end

function DarkRP.setupDoors()
	runBatch(setupDoors)
end

hook.Add("InitPostEntity", "DarkRP.Doors", function()
	timer.Simple(SETUP_DELAY, DarkRP.setupDoors)
end)

hook.Add("PreCleanupMap", "DarkRP.Doors", function()
	cleaning = true
end)

-- двери карты - новые сущности: отдельные двери игроков теряются, помещения территории выдают заново
hook.Add("PostCleanupMap", "DarkRP.Doors", function()
	cleaning = false

	for _, ply in ipairs(player.GetAll()) do
		ply.Ownedz = {}
		ply.OwnedNumz = 0
	end

	DarkRP.setupDoors()
end)

--[[---------------------------------------------------------------------------
	AutoClose: m_toggle_state у func_door/func_movelinear (0 - открыта, 2 - открывается),
	m_eDoorState у prop_door_rotating (1 - открывается, 2 - открыта, 4 - приоткрыта)
---------------------------------------------------------------------------]]
local function isDoorOpen(door)
	if door:GetClass() == "prop_door_rotating" then
		local state = door:GetInternalVariable("m_eDoorState")
		return state == 1 or state == 2 or state == 4
	end

	local state = door:GetInternalVariable("m_toggle_state")
	return state == 0 or state == 2
end

timer.Create("DarkRP.DoorAutoClose", AUTOCLOSE_STEP, 0, function()
	local list = GAMEMODE and GAMEMODE.Config.AutoClose
	if not list then return end

	local CT = CurTime()

	for id in pairs(list) do
		local door = ents.GetMapCreatedEntity(id)

		if not IsValid(door) or door.ramed or not isDoorOpen(door) then
			if IsValid(door) then door.AutoCloseAt = nil end
			continue
		end

		door.AutoCloseAt = door.AutoCloseAt or CT + AUTOCLOSE_DELAY

		if CT >= door.AutoCloseAt then
			door.AutoCloseAt = nil
			door:Fire("Close", "", 0)
		end
	end
end)

--[[---------------------------------------------------------------------------
	ExtraDoors: функция конфига решает, кому можно открывать и закрывать дверь ключами
---------------------------------------------------------------------------]]
local function extraDoorAccess(ply, ent)
	local list = GAMEMODE.Config.ExtraDoors
	if not list or not IsValid(ent) then return end

	local check = list[ent:MapCreationID()]
	if not isfunction(check) then return end

	local ok, allowed = pcall(check, ply, ent)
	if ok and allowed then return true end
end

hook.Add("canKeysLock", "DarkRP.ExtraDoors", extraDoorAccess)
hook.Add("canKeysUnlock", "DarkRP.ExtraDoors", extraDoorAccess)

--[[---------------------------------------------------------------------------
	darkrp_doorinfo - суперадмину в консоль: дверь под прицелом и помещение, где он стоит
---------------------------------------------------------------------------]]
local function listKeys(tbl)
	local keys = {}
	for k in SortedPairs(tbl or {}) do keys[#keys + 1] = tostring(k) end
	return #keys > 0 and table.concat(keys, ", ") or "-"
end

concommand.Add("darkrp_doorinfo", function(ply)
	if not IsValid(ply) or not ply:IsSuperAdmin() then return end

	local lines = {}
	local ent = ply:GetEyeTrace().Entity

	if IsValid(ent) and ent:isKeysOwnable() then
		local data = ent:getDoorData()
		local t = ent.DoorTerritory
		local s = DarkRP.getDoorSettings(ent)
		local owner = ent:getDoorOwner()
		local teams = {}

		for k in SortedPairs(data.teamOwn or {}) do
			teams[#teams + 1] = DarkRP.Teams[k] and DarkRP.Teams[k].name or tostring(k)
		end

		lines[#lines + 1] = string.format("Дверь %s, EntIndex %d, MapCreationID %d", ent:GetClass(), ent:EntIndex(), ent:MapCreationID())
		lines[#lines + 1] = "  помещение: " .. (t and (t.name .. " (" .. tostring(t.printName) .. ")") or "-")
		lines[#lines + 1] = "  владелец: " .. (IsValid(owner) and owner:FullName() or "-") .. "; совладельцы (UserID): " .. listKeys(data.extraOwners) .. "; приглашены: " .. listKeys(data.allowedToOwn)
		lines[#lines + 1] = "  нельзя купить: " .. (data.nonOwnable and "да" or "нет") .. "; группа: " .. (data.groupOwn or "-") .. "; работы: " .. (#teams > 0 and table.concat(teams, ", ") or "-")
		lines[#lines + 1] = "  замок: " .. (ent.IsUnLocked and "открыто" or "заперто") .. "; название: " .. (data.title or "-")
		lines[#lines + 1] = "  ручные настройки: " .. (s and listKeys(s) or "-")
	else
		lines[#lines + 1] = "Посмотрите на дверь или машину"
	end

	local cur = ply.currentTerritory
	lines[#lines + 1] = "Вы в помещении: " .. (cur and (cur.name .. " (" .. tostring(cur.printName) .. "), дверей: " .. #(cur.doors or {})) or "-")

	for _, line in ipairs(lines) do
		ply:PrintMessage(HUD_PRINTCONSOLE, line)
	end
end)
