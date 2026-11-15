--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Территории: серверная часть (шаг 9)
	Описание помещений и их методы (OnBuy, OnSell, AddOwner...) - sh_init.lua и data/<карта>.lua,
	здесь - то, что их вызывает:
		- двери карты раздаются помещениям (хук DarkRP.SetupDoors из doorsystem/sv_doors.lua)
		- кто в каком помещении: сервер проверяет сам раз в секунду, сообщения клиента лишь ускоряют проверку
		- SkyLine в телефоне: список, аренда, сдача, совладельцы (net)
		- почтовые ящики помещений, предметы buySpawn после очистки карты
		- выход: аренда прекращается, 10 минут помещение можно вернуть без оплаты (как у автора);
		  смена персонажа аренду и совладение не трогает (ваш ответ к 11.3)
		- пропы - только в своём помещении
	Двери: свободное помещение - двери нельзя купить (заперты); арендованное - ключи у арендатора и совладельцев;
		общественные - нельзя купить, кроме участка (группа NYPD) и пожарной части (FDNY)
---------------------------------------------------------------------------]]
util.AddNetworkString("territoryEnter")
util.AddNetworkString("territoryExit")
util.AddNetworkString("territorySendInfo")
util.AddNetworkString("territoryBuy")
util.AddNetworkString("territorySell")
util.AddNetworkString("territoryAddOwner")
util.AddNetworkString("territoryRemoveOwner")
util.AddNetworkString("TerritoryOnSellAdd")

local POLL = 1 -- проверка, кто в каком помещении, секунд
local HINT_DELAY = 0.25 -- сообщения клиента о входе и выходе - не чаще
local RESERVE_TIME = 600 -- бронь прежнего арендатора (ter_list_dics в sh_init.lua)
local DOOR_PROBE = 24 -- точки по обе стороны двери, юнитов
local DOOR_PROBE_UP = 0.35 -- и выше и ниже центра: доля высоты двери
local BUYABLE_BONUS = 10 -- дверь на границе - арендуемому помещению

-- общественные помещения, двери которых открывают группы (shared.lua, AddDoorGroup)
local DOOR_GROUPS = {
	police = "NYPD",
	firestation = "FDNY",
}

local reserved = {} -- [имя] = {до CurTime, SteamID} - копия брони автора, чтобы скрыть помещение из каталога

local function safeCall(fn, ...)
	local ok, err = xpcall(fn, debug.traceback, ...)

	if not ok then
		ErrorNoHalt("[DarkRP] Территории: " .. tostring(err) .. "\n")
	end

	return ok
end

--[[---------------------------------------------------------------------------
	Границы и порядок поиска: сначала арендуемые, внутри - от меньших к большим
---------------------------------------------------------------------------]]
local ordered = {}

local function prepare()
	ordered = {}

	for name, t in pairs(Territories.list) do
		local coords = t.coords or {}
		if #coords < 3 then continue end

		local minx, miny, minz = math.huge, math.huge, math.huge
		local maxx, maxy = -math.huge, -math.huge
		local area = 0

		for i, v in ipairs(coords) do
			minx, maxx = math.min(minx, v.x), math.max(maxx, v.x)
			miny, maxy = math.min(miny, v.y), math.max(maxy, v.y)
			minz = math.min(minz, v.z)

			local n = coords[i % #coords + 1]
			area = area + v.x * n.y - n.x * v.y
		end

		t.name = t.name or name
		t.doors = t.doors or {}
		t.visitors = t.visitors or {}
		if t.buyable then t.extraOwners = t.extraOwners or {} end

		t.BoundsMin = Vector(minx, miny, minz)
		t.BoundsMax = Vector(maxx, maxy, minz + (t.height or 0))
		t.Area = math.abs(area) / 2

		ordered[#ordered + 1] = t
	end

	table.sort(ordered, function(a, b)
		if (a.buyable and true or false) ~= (b.buyable and true or false) then return a.buyable and true or false end
		if a.Area ~= b.Area then return a.Area < b.Area end
		return a.name < b.name
	end)
end

prepare()

local function inside(t, pos)
	local a, b = t.BoundsMin, t.BoundsMax
	if pos.x < a.x or pos.x > b.x or pos.y < a.y or pos.y > b.y or pos.z < a.z or pos.z > b.z then return false end

	return t:IsInsideV(pos)
end

function Territories.Find(pos)
	for _, t in ipairs(ordered) do
		if inside(t, pos) then return t end
	end
end

--[[---------------------------------------------------------------------------
	Список для SkyLine: свободные (без брони чужого) - пустая таблица;
	свои - {masterOwner, propetytype}; чужие с вывеской (кафе) - тоже, для карты
---------------------------------------------------------------------------]]
local function infoFor(ply)
	local list = {}
	local sid64 = ply:SteamID64()
	local sid = ply:SteamID()
	local CT = CurTime()

	for name, t in pairs(Territories.list) do
		if not t.buyable then continue end

		if t.masterOwner == ply then
			list[name] = {masterOwner = ply, propetytype = t.propetytype}
		elseif t:Owned() then
			if t.propetytype then list[name] = {masterOwner = t.masterOwner, propetytype = t.propetytype} end
		elseif not t.restrict or t.restrict[sid64] then
			local r = reserved[name]
			if not r or r[1] <= CT or r[2] == sid then list[name] = {} end
		end
	end

	return list
end

local function sendInfo(ply)
	net.Start("territorySendInfo")
		net.WriteTable(infoFor(ply))
	net.Send(ply)
end

-- вызывают sh_init.lua, deployment и др.: без игрока - всем
function TerritoriesInfoUpdate(ply)
	if IsValid(ply) then
		if ply:IsPlayer() and not ply:IsBot() then sendInfo(ply) end
		return
	end

	for _, v in ipairs(player.GetHumans()) do
		if v.DarkRPClientReady then sendInfo(v) end
	end
end

net.Receive("territorySendInfo", function(_, ply)
	if DarkRP.NetDelay(ply, 1) then return end
	sendInfo(ply)
end)

hook.Add("DarkRP.PlayerLoaded", "DarkRP.Territories", function(ply)
	sendInfo(ply)
end)

--[[---------------------------------------------------------------------------
	Кто где: вход и выход - методы автора (OnInitialEnter/OnInitialExit), физган и тулган
	выдаются и снимаются и тогда, когда право строить меняется без выхода (аренда, совладелец, смена работы)
---------------------------------------------------------------------------]]
local function exitTerritory(ply)
	local t = ply.currentTerritory
	if not t then return end

	safeCall(t.OnInitialExit, t, ply)
	ply.currentTerritory = nil

	if t.visitors then t.visitors[ply:UserID()] = nil end
	if ply.TerritoryPropAllowed then safeCall(t.StripWeapons, t, ply) end

	ply.TerritoryPropAllowed = nil
end

local function enterTerritory(ply, t)
	safeCall(t.OnInitialEnter, t, ply)
	ply.currentTerritory = t
	ply.TerritoryPropAllowed = t:AllowedPropSpawn(ply) and true or false
end

local function updatePlayer(ply)
	if not IsValid(ply) then return end

	if not ply:Alive() or ply:Team() == 0 then
		exitTerritory(ply)
		return
	end

	local cur = ply.currentTerritory
	local new = Territories.Find(ply:GetPos())

	if new ~= cur then
		exitTerritory(ply)
		if new then enterTerritory(ply, new) end
		return
	end

	if not cur then return end

	local allowed = cur:AllowedPropSpawn(ply) and true or false
	if allowed == ply.TerritoryPropAllowed then return end

	ply.TerritoryPropAllowed = allowed

	if allowed then
		safeCall(cur.GiveWeapons, cur, ply)
	else
		safeCall(cur.StripWeapons, cur, ply)
	end
end

Territories.UpdatePlayer = updatePlayer

timer.Create("DarkRP.Territories", POLL, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		safeCall(updatePlayer, ply)
	end
end)

net.Receive("territoryEnter", function(_, ply)
	if DarkRP.NetDelay(ply, HINT_DELAY) then return end
	safeCall(updatePlayer, ply)
end)

net.Receive("territoryExit", function(_, ply)
	if DarkRP.NetDelay(ply, HINT_DELAY) then return end
	safeCall(updatePlayer, ply)
end)

-- возрождение снимает оружие: помещение засчитывается заново на следующей проверке
hook.Add("PlayerSpawn", "DarkRP.Territories", function(ply)
	exitTerritory(ply)
end)

--[[---------------------------------------------------------------------------
	Пропы - только в своём помещении (там, где выдаётся физган), и туда, куда смотрит игрок
---------------------------------------------------------------------------]]
hook.Add("PlayerSpawnProp", "DarkRP.Territories", function(ply)
	if not IsValid(ply) or checkRights(ply) then return end

	local t = ply.currentTerritory

	if t and t:AllowedPropSpawn(ply) then
		local eye = ply:EyePos()
		local tr = util.TraceLine({start = eye, endpos = eye + ply:GetAimVector() * 2048, filter = ply})

		if t:IsInsideV(tr.HitPos) then return end
	end

	return false
end)

--[[---------------------------------------------------------------------------
	Совладельцы
---------------------------------------------------------------------------]]

-- тихо: выход, отказ от ключей (письмо автора RemoveOwner - когда убирает арендатор)
local function dropCoOwner(t, ply)
	local id = ply:AccountID()
	if not id or not t.extraOwners or not t.extraOwners[id] then return false end

	t.extraOwners[id] = nil

	for _, door in ipairs(t.doors) do
		if IsValid(door) then door:removeKeysDoorOwner(ply) end
	end

	return true
end

local function addCoOwner(ply, t, target)
	if not IsValid(target) or not target:IsPlayer() or target == ply then return end

	if target:Team() == 0 then
		return
	end

	local id = target:AccountID()
	if not id then return end

	if t.extraOwners[id] then
		return
	end

	if not safeCall(t.AddOwner, t, target) then return end

	DarkRP.log("property", ply, target, "добавил совладельца [" .. t.name .. "] " .. tostring(t.printName))
end

local function removeCoOwner(ply, t, target)
	if not IsValid(target) or not target:IsPlayer() or target == ply then return end

	local id = target:AccountID()

	if not id or not t.extraOwners[id] then
		return
	end

	if not safeCall(t.RemoveOwner, t, target) then return end

	DarkRP.log("property", ply, target, "убрал совладельца [" .. t.name .. "] " .. tostring(t.printName))
end

--[[---------------------------------------------------------------------------
	SkyLine (телефон, web_properly.lua) и аренда юнитов звонком (mc_phone/sh_init.lua)
---------------------------------------------------------------------------]]
local function buyable(name)
	local t = isstring(name) and Territories:Get(name)
	return t and t.buyable and t or nil
end

net.Receive("territoryBuy", function(_, ply)
	local t = buyable(net.ReadString())
	if DarkRP.NetDelay(ply, 1) or not t or ply:Team() == 0 then return end

	if t.restrict and not t.restrict[ply:SteamID64()] then
		return
	end

	if t.masterOwner == ply then
		return
	end

	if t:Owned() then
		TerritoriesInfoUpdate(ply)
		return
	end

	local r = reserved[t.name]

	if r and r[1] > CurTime() and r[2] ~= ply:SteamID() then
		return
	end

	-- сообщения о деньгах и лимите - в OnBuy автора
	safeCall(t.OnBuy, t, ply)

	if t.masterOwner == ply then
		reserved[t.name] = nil
		TerritoriesInfoUpdate()
	end
end)

net.Receive("territorySell", function(_, ply)
	local t = buyable(net.ReadString())
	if DarkRP.NetDelay(ply, 1) or not t or not ply:IsTerritoryMasterOwner(t) then return end

	safeCall(t.OnSell, t, ply)
end)

net.Receive("territoryAddOwner", function(_, ply)
	local t = buyable(net.ReadString())
	local target = net.ReadEntity()
	if DarkRP.NetDelay(ply, 1) or not t or not ply:IsTerritoryMasterOwner(t) then return end

	addCoOwner(ply, t, target)
end)

net.Receive("territoryRemoveOwner", function(_, ply)
	local t = buyable(net.ReadString())
	local target = net.ReadEntity()
	if DarkRP.NetDelay(ply, 1) or not t or not ply:IsTerritoryMasterOwner(t) then return end

	removeCoOwner(ply, t, target)
end)

--[[---------------------------------------------------------------------------
	Двери помещений в меню F2 (команды из doorsystem/sv_doorcommands.lua)
---------------------------------------------------------------------------]]
function Territories.DoorToggleOwn(ply, door)
	local t = door.DoorTerritory

	-- арендатор сдаёт помещение в SkyLine в телефоне, совладелец отказывается от ключей
	if not ply:IsTerritoryMasterOwner(t) then
		dropCoOwner(t, ply)
	end
end

function Territories.DoorAddOwner(ply, door, target)
	local t = door.DoorTerritory

	if not ply:IsTerritoryMasterOwner(t) then
		return
	end

	addCoOwner(ply, t, target)
end

function Territories.DoorRemoveOwner(ply, door, target)
	local t = door.DoorTerritory

	if not ply:IsTerritoryMasterOwner(t) then
		return
	end

	removeCoOwner(ply, t, target)
end

--[[---------------------------------------------------------------------------
	Выход: аренда прекращается (бронь на 10 минут), совладение снимается
---------------------------------------------------------------------------]]
local function release(ply)
	exitTerritory(ply)

	for name, t in pairs(Territories.list) do
		if not t.buyable then continue end

		if t.masterOwner == ply then
			reserved[name] = {CurTime() + RESERVE_TIME, ply:SteamID()}
			safeCall(t.keysUnOwn, t, true)
		else
			dropCoOwner(t, ply)
		end
	end
end

-- бронь кончилась - помещение снова видно всем
timer.Create("DarkRP.TerritoryReserve", 10, 0, function()
	local CT = CurTime()
	local changed = false

	for name, r in pairs(reserved) do
		if r[1] <= CT then
			reserved[name] = nil
			changed = true
		end
	end

	if changed then TerritoriesInfoUpdate() end
end)

hook.Add("PlayerDisconnected", "DarkRP.Territories", release)

-- смена персонажа: аренда и совладение остаются (ваш ответ к 11.3: «При смени персонажа
-- никакие предметы не исчезают, когда выходит все исчезает, тоесть если у него было здание больше нет»)
hook.Add("MCR.CharacterReset", "DarkRP.Territories", exitTerritory)

--[[---------------------------------------------------------------------------
	Двери, почтовые ящики, предметы помещений (при старте и после очистки карты)
---------------------------------------------------------------------------]]
-- точки: центр двери, по обе стороны от неё, выше и ниже; центр весит вдвое больше
local function territoryOfDoor(door)
	local center = door:WorldSpaceCenter()
	local size = door:OBBMaxs() - door:OBBMins()
	local side = size.x <= size.y and door:GetForward() or door:GetRight()

	side = Vector(side.x, side.y, 0)
	if side:LengthSqr() < 0.01 then side = Vector(1, 0, 0) end
	side:Normalize()
	side = side * DOOR_PROBE

	local up = Vector(0, 0, size.z * DOOR_PROBE_UP)
	local scores = {}

	for _, h in ipairs({0, 1, -1}) do
		for _, s in ipairs({0, 1, -1}) do
			local pos = center + up * h + side * s
			local weight = s == 0 and 2 or 1

			for _, t in ipairs(ordered) do
				if inside(t, pos) then scores[t] = (scores[t] or 0) + weight end
			end
		end
	end

	local best, bestScore

	for t, score in pairs(scores) do
		if t.buyable then score = score + BUYABLE_BONUS end

		if not best or score > bestScore or (score == bestScore and (t.Area < best.Area or (t.Area == best.Area and t.name < best.name))) then
			best, bestScore = t, score
		end
	end

	return best
end

Territories.DoorTerritory = territoryOfDoor

-- состояние двери по помещению (после очистки карты арендатор и совладельцы получают ключи заново)
local function applyDoor(t, door)
	if t.buyable then
		if IsValid(t.masterOwner) then
			door:setKeysNonOwnable(false)
			door:keysOwn(t.masterOwner)
			door:setKeysTitle(nil) -- как SetOwner автора: у арендованной двери нет названия администратора

			for _, ply in ipairs(player.GetAll()) do
				local id = ply:AccountID()
				if id and t.extraOwners[id] and ply ~= t.masterOwner then door:addKeysDoorOwner(ply) end
			end
		else
			door:setKeysNonOwnable(true)
		end
	elseif DOOR_GROUPS[t.name] then
		door:setKeysNonOwnable(false)
		door:setDoorGroup(DOOR_GROUPS[t.name])
	else
		door:setKeysNonOwnable(true)
	end

	safeCall(t.DoorAction, t, door)
end

local function spawnMailbox(t)
	if IsValid(t.MailboxEnt) then t.MailboxEnt:Remove() end
	t.MailboxEnt = nil

	local data = t.mailbox
	if not istable(data) or not isvector(data[1]) then return end

	local ent = ents.Create("mailbox")
	if not IsValid(ent) then return end

	ent:SetPos(data[1])
	ent:SetAngles(data[2] or Angle(0, 0, 0))
	ent.territory = t.name
	ent:Spawn()
	ent:Activate()

	t.MailboxEnt = ent
end

-- как в OnBuy автора: оборудование помещения (плита кафе)
local function spawnBuyEnts(t)
	for _, ent in ipairs(t.EntTable or {}) do
		if IsValid(ent) then ent:Remove() end
	end

	t.EntTable = {}

	for _, v in ipairs(t.buySpawn or {}) do
		local ent = ents.Create(v.e)
		if not IsValid(ent) then continue end

		ent:SetPos(v.p)
		ent:SetAngles(v.a)
		ent:Spawn()
		ent:DrawShadow(false)

		if v.m then
			ent:SetModel(v.m)
			ent:PhysicsInit(SOLID_VPHYSICS)
		end

		local phys = ent:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end

		t.EntTable[#t.EntTable + 1] = ent

		if v.sf then safeCall(v.sf, ent, t) end
	end
end

local function setupTerritory(t)
	if t.buyable and t.masterOwner ~= nil and not IsValid(t.masterOwner) then
		t.masterOwner = nil
		t.extraOwners = {}
		t.propetytype = nil
	end

	for _, door in ipairs(t.doors) do
		applyDoor(t, door)
	end

	safeCall(t.Init, t)
	spawnMailbox(t)

	if t.buyable and IsValid(t.masterOwner) then spawnBuyEnts(t) end
end

hook.Add("DarkRP.SetupDoors", "DarkRP.Territories", function()
	for _, t in pairs(Territories.list) do
		t.doors = {}
	end

	for _, door in ipairs(ents.GetAll()) do
		if IsValid(door) and DarkRP.DoorClasses[door:GetClass()] and door:MapCreationID() >= 0 and not DarkRP.isDoorOverridden(door) then
			local t = territoryOfDoor(door)

			if t then
				t.doors[#t.doors + 1] = door
				door.DoorTerritory = t
			end
		end
	end

	for _, t in ipairs(ordered) do
		safeCall(setupTerritory, t)
	end

	TerritoriesInfoUpdate()
end)

-- администратор настроил дверь вручную - она больше не часть помещения
hook.Add("DarkRP.DoorOverridden", "DarkRP.Territories", function(door, t)
	if not t or not t.doors then return end

	table.RemoveByValue(t.doors, door)
	door.DoorTerritory = nil
end)

-- «Убрать все»: дверь возвращается в своё помещение
hook.Add("DarkRP.DoorReset", "DarkRP.Territories", function(door)
	local t = territoryOfDoor(door)
	if not t then return end

	if not table.HasValue(t.doors, door) then t.doors[#t.doors + 1] = door end
	door.DoorTerritory = t

	applyDoor(t, door)

	if t.lockDoors == TERRITORY_DOOR_ACTION_LOCK then
		door:Fire("lock", "", 0)
	elseif t.lockDoors == TERRITORY_DOOR_ACTION_UNLOCK then
		door:Fire("unlock", "", 0)
	end

	return t
end)
