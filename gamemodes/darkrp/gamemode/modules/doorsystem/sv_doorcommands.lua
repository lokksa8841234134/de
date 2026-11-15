--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Команды дверей и машин из меню F2 (client/vgui.lua): darkrp /команда
	Владельцу: /toggleown - купить или отдать ключи, /ao и /ro <UserID> - пригласить и забрать ключи,
		/title <текст> - название
	Администратору (HasAdminAccess("door")): /toggleownable, /togglegroupownable [группа], /toggleteamownable <работа>,
		/title у чужой или свободной двери - сохраняются в базе (sv_doors.lua)
	Двери помещений (территорий): аренда и совладельцы - через SkyLine, команды передаются территории
---------------------------------------------------------------------------]]
local LOOK_DIST = 200 -- от глаз до точки на двери
local MENU_DIST = 26000 -- квадрат расстояния, на котором F2 показывает дверь (client/vgui.lua)
local SELL_BACK = 0.666 -- доля цены, которая возвращается при продаже купленных ключей
local TITLE_LEN = 48

local function lookDoor(ply)
	local tr = ply:GetEyeTrace()
	local ent = tr.Entity

	if not IsValid(ent) or not ent:isKeysOwnable() then return end
	if tr.HitPos:DistToSqr(ply:EyePos()) > LOOK_DIST * LOOK_DIST and ent:GetPos():DistToSqr(ply:GetPos()) >= MENU_DIST then return end

	return ent
end

local function what(ent)
	return ent:IsVehicle() and "машины" or "двери"
end

local function territoryDoor(ent)
	local t = ent.DoorTerritory
	return t and t.buyable and Territories and t or nil
end

--[[---------------------------------------------------------------------------
	Владельцу
---------------------------------------------------------------------------]]
DarkRP.defineChatCommand("toggleown", function(ply)
	local ent = lookDoor(ply)

	if not ent then
		return
	end

	if ply:isArrested() then
		return
	end

	if territoryDoor(ent) and Territories.DoorToggleOwn then
		Territories.DoorToggleOwn(ply, ent)
		return
	end

	if ent:isKeysOwnedBy(ply) then
		if not ent:isMasterOwner(ply) then
			ent:keysUnOwn(ply)
			return
		end

		local refund = ent.DoorBoughtFor and math.floor(ent.DoorBoughtFor * SELL_BACK + 0.5) or 0

		ent:keysUnOwn(ply)
		ent:keysUnLock()

		if refund > 0 then
			ply:addMoney(refund)
		end

		DarkRP.log("property", ply, nil, "отдал ключи от " .. what(ent) .. (refund > 0 and (" за $" .. refund) or ""))
		return
	end

	if ent:isKeysOwned() then
		if ent:isKeysAllowedToOwn(ply) then
			ent:keysOwn(ply)
		end

		return
	end

	if ent:getKeysNonOwnable() or ent:getKeysDoorGroup() or ent:getKeysDoorTeams() then
		return
	end

	local vehicle = ent:IsVehicle()

	if vehicle then
		local owner = isfunction(ent.CPPIGetOwner) and ent:CPPIGetOwner()

		if IsValid(owner) and owner ~= ply then
			return
		end
	end

	local cost = vehicle and (GAMEMODE.Config.vehiclecost or 30) or (GAMEMODE.Config.doorcost or 300)

	if not ply:canAfford(cost) then
		return
	end

	ply:addMoney(-cost)
	ent:keysOwn(ply)
	ent.DoorBoughtFor = cost

	DarkRP.log("property", ply, nil, "купил ключи от " .. what(ent) .. " за $" .. cost)
end, 0.5)

DarkRP.defineChatCommand("ao", function(ply, args)
	local ent = lookDoor(ply)

	if not ent then
		return
	end

	local target = DarkRP.findPlayer(args)

	if not IsValid(target) then
		return
	end

	if target == ply then return end

	if territoryDoor(ent) and Territories.DoorAddOwner then
		Territories.DoorAddOwner(ply, ent, target)
		return
	end

	if not ent:isKeysOwnedBy(ply) then
		return
	end

	if ent:isKeysOwnedBy(target) or ent:isKeysAllowedToOwn(target) then
		return
	end

	ent:addKeysAllowedToOwn(target)
end, 0.5)

DarkRP.defineChatCommand("ro", function(ply, args)
	local ent = lookDoor(ply)

	if not ent then
		return
	end

	local target = DarkRP.findPlayer(args)

	if not IsValid(target) then
		return
	end

	if territoryDoor(ent) and Territories.DoorRemoveOwner then
		Territories.DoorRemoveOwner(ply, ent, target)
		return
	end

	if not ent:isKeysOwnedBy(ply) then
		return
	end

	if ent:isMasterOwner(target) then
		return
	end

	if ent:isKeysAllowedToOwn(target) then
		ent:removeKeysAllowedToOwn(target)
	elseif ent:isKeysOwnedBy(target) then
		ent:removeKeysDoorOwner(target)
	else
		return
	end
end, 0.5)

DarkRP.defineChatCommand("title", function(ply, args)
	local ent = lookDoor(ply)

	if not ent then
		return
	end

	local title = utf8.sub(string.Trim(args or ""), 1, TITLE_LEN)
	if title == "" then title = nil end

	if ent:isKeysOwnedBy(ply) then
		ent:setKeysTitle(title)
		return
	end

	if not ply:HasAdminAccess("door") then
		return
	end

	-- администратор: постоянное название двери карты, у занятой двери появится, когда она освободится
	if ent:MapCreationID() < 0 or not DarkRP.DoorClasses[ent:GetClass()] then
		return
	end

	if not DarkRP.doorSettingsReady() then
		return
	end

	DarkRP.setDoorSettings(ent, {title = title or false})
end, 0.5)

--[[---------------------------------------------------------------------------
	Администратору: настройки сохраняются (sv_doors.lua), дверь выходит из помещения
---------------------------------------------------------------------------]]
local function adminDoor(ply)
	if not ply:HasAdminAccess("door") then
		return
	end

	local ent = lookDoor(ply)

	if not ent or not DarkRP.DoorClasses[ent:GetClass()] or ent:MapCreationID() < 0 then
		return
	end

	if not DarkRP.doorSettingsReady() then
		return
	end

	return ent
end

local function adminLog(ply, ent, text)
	DarkRP.log("admin", ply, nil, "дверь " .. ent:MapCreationID() .. ": " .. text)
end

DarkRP.defineChatCommand("toggleownable", function(ply)
	local ent = adminDoor(ply)
	if not ent then return end

	local locked = not ent:getKeysNonOwnable()

	DarkRP.setDoorSettings(ent, {nonOwnable = locked and "1" or "0", group = "", jobs = ""})

	adminLog(ply, ent, locked and "нельзя купить" or "можно купить")
end, 0.5)

DarkRP.defineChatCommand("togglegroupownable", function(ply, args)
	local ent = adminDoor(ply)
	if not ent then return end

	local group = string.Trim(args or "")

	-- «Убрать все»: дверь снова обычная - в своём помещении или закрыта для покупки
	if group == "" then
		DarkRP.resetDoorSettings(ent)

		adminLog(ply, ent, "сброс настроек")
		return
	end

	if not RPExtraTeamDoors[group] then
		return
	end

	local on = ent:getKeysDoorGroup() ~= group

	DarkRP.setDoorSettings(ent, {nonOwnable = "0", group = on and group or "", jobs = ""})

	adminLog(ply, ent, on and ("группа " .. group) or "без группы")
end, 0.5)

DarkRP.defineChatCommand("toggleteamownable", function(ply, args)
	local ent = adminDoor(ply)
	if not ent then return end

	local idx = tonumber(args)
	local job = idx and DarkRP.Teams[idx]

	if not job or not job.command then
		return
	end

	local teams = table.Copy(ent:getKeysDoorTeams() or {})
	local on = not teams[idx]

	teams[idx] = on or nil

	local cmds = {}

	for k in SortedPairs(teams) do
		if DarkRP.Teams[k] and DarkRP.Teams[k].command then cmds[#cmds + 1] = DarkRP.Teams[k].command end
	end

	DarkRP.setDoorSettings(ent, {nonOwnable = "0", group = "", jobs = table.concat(cmds, ",")})

	adminLog(ply, ent, (on and "работа + " or "работа - ") .. job.command)
end, 0.5)
