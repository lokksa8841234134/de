--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Компьютер участка, вкладка "Оружие" - сервер (клиент - cl.lua рядом)

	GetGunLic {gunid} - владелец оружия по серийному номеру в реестре
	N.L.R. (DarkRP.GunLookup, police/sv_gunreg.lua). Ответ - GetGunLic
	{searching, seardelay} - полоса поиска; если номер действует, а тот, на
	кого он записан, на сервере, ещё {gunid, name, sname, plypassid,
	gun = {name}}. Спиленный номер, номер разобранного ствола и номер
	игрока не на сервере не находятся: клиент пишет "Данные не найдены
	или устарели".
	Пользоваться может полицейский у компьютера (slawer_mayor_computer,
	Slawer.Mayor:PoliceAtComputer - server/sv_computers.lua)
---------------------------------------------------------------------------]]

local SEARCH_DELAY = 5				-- полоса поиска у клиента, с.
local MAX_ID = 32

local function canUse(ply)
	return DarkRP and DarkRP.GunLookup ~= nil and Slawer.Mayor:PoliceAtComputer(ply)
end

Slawer.Mayor:NetReceive("GetGunLic", function(ply, data)
	if not istable(data) or not canUse(ply) then return end

	local reply = {searching = CurTime(), seardelay = SEARCH_DELAY}
	local id = (isstring(data.gunid) or isnumber(data.gunid)) and string.Trim(string.sub(tostring(data.gunid), 1, MAX_ID)) or ""
	local rec = DarkRP.GunLookup(id)
	local owner = rec and rec.state == DarkRP.GUN_ACTIVE and DarkRP.findBYCharacterID(rec.passid)

	if IsValid(owner) and owner:getDarkRPVar("character") ~= nil then
		local parts = string.Explode(" ", owner:FullName())
		local wep = DarkRP.Weapons[rec.class]

		reply.gunid = id
		reply.name = parts[1]
		reply.sname = table.concat(parts, " ", 2)
		reply.plypassid = tostring(DarkRP.PassId(owner))
		reply.gun = {name = istable(wep) and wep.name or rec.class}
	end

	Slawer.Mayor:NetStart("GetGunLic", reply, ply)
end)
