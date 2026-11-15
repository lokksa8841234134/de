--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Обыск задержанного и склад улик - сервер

	Меню "Обыск игрока" (client/vgui.lua) есть у игрока в наручниках:
	"Снять оружие" (Police.RemoveWeapons) - оружие задержанного переходит
	в карманы обыскивающего; что не влезло, остаётся на задержанном.
	"Обыск инвентаря" (Police.CheckInv) - карманы задержанного открываются
	как контейнер (McINV.Loot): вещи можно забрать себе или выложить на землю,
	подложить нельзя. Каждое действие инвентарь проверяет через McINV.CanSearch.
	Обыскивать может любой свободный игрок, не только полиция (решение
	владельца сервера, шаг 6.3), не дальше 150 юнитов; задержанный -
	живой, в наручниках и не в машине. Склад улик - только полиция.

	Склад улик (NPC с policeEvidnce, "Изъятое имущество"): инвентарь помечает,
	кто что положил (putby, putname). Список над содержимым склада
	(police/sh_config.lua) шлёт Inventory.Drop nypd <userid>:
	"Личные вещи #N" - всё, что положил офицер, становится личными вещами
	задержанного (putby = его SteamID64 и personal: их выдаёт NPC по фразе
	"Я хочу забрать свои личные вещи"), "Центральный склад" - удаляется.
	Задержанных для этого списка (Slawer.JailTable) сервер присылает, когда
	полицейский подходит к NPC склада, а не только в компьютере участка.
---------------------------------------------------------------------------]]

util.AddNetworkString("Police.CheckInv")
util.AddNetworkString("Police.RemoveWeapons")

local SEARCH_RANGE = 150 * 150 -- квадрат: как у контейнеров (McINV.CanLoot)
local NET_DELAY = 1
local TYPES = {INV_WEAPON, INV_ENTITY, INV_AMMO, INV_FOOD, INV_JUNK}

--[[---------------------------------------------------------------------------
	Кто кого может обыскать. Вернёт причину отказа или nil
---------------------------------------------------------------------------]]
local function searchDenied(ply, target)
	if not IsValid(ply) or not IsValid(target) or not target:IsPlayer() or ply == target then return "" end
	if not ply:IsFreeman() or ply:InVehicle() then return "" end
	if not target.HandCuffed or not target:Alive() then return "Игрок не в наручниках" end
	if target:InVehicle() then return "Сначала выведите задержанного из машины" end
	if ply:GetPos():DistToSqr(target:GetPos()) > SEARCH_RANGE then return "Подойдите ближе" end

	return nil
end

-- для инвентаря (McINV.CanAccess): можно ли сейчас трогать карманы target
function McINV.CanSearch(ply, target)
	return searchDenied(ply, target) == nil
end

-- цель из сообщения клиента; nil - отказ
local function readTarget(ply)
	local target = net.ReadEntity()
	local reason = searchDenied(ply, target)

	if reason then
		return nil
	end

	return target
end

--[[---------------------------------------------------------------------------
	Обыск инвентаря (клиент: Entity задержанного)
---------------------------------------------------------------------------]]
net.Receive("Police.CheckInv", function(_, ply)
	if DarkRP.NetDelay(ply, NET_DELAY) then return end

	local target = readTarget(ply)
	if not target or target:getDarkRPVar("character") == nil or not istable(target.inv) then return end

	local msg = "Карманы задержанного: " .. target:FullName() .. ". Изъятое сдаётся на склад улик."

	if not McINV.Loot(target, ply, false, false, msg) then
		return
	end

	DarkRP.log("police", ply, target, "обыскал карманы")
end)

--[[---------------------------------------------------------------------------
	Снять оружие (клиент: Entity задержанного)
	Изымается оружие из каталога (DarkRP.Weapons), кроме служебного:
	выданного профессией, квестового и того, что нельзя выбросить (DisallowDrop)
---------------------------------------------------------------------------]]
local function canSeize(wep)
	local class = wep:GetClass()
	if not DarkRP.Weapons[class] or wep.GivenByTeam or wep.MQS_weapon then return false end

	local single = DarkRP.SingleWep and DarkRP.SingleWep.DisallowDrop

	return not (GAMEMODE.Config.DisallowDrop[class] or (single and single[class]))
end

net.Receive("Police.RemoveWeapons", function(_, ply)
	if DarkRP.NetDelay(ply, NET_DELAY) then return end

	local target = readTarget(ply)
	if not target then return end

	for _, wep in ipairs(target:GetWeapons()) do
		if not IsValid(wep) or not canSeize(wep) then continue end

		local class = wep:GetClass()
		local item = McINV.AddCustomItem(nil, "Weapons", class, DarkRP.WeaponItemData(wep))
		if not item then continue end

		-- не влезло в карманы - остаётся на задержанном
		if not ply:HaveSpace(McINV.GetWeight(item, INV_WEAPON, class)) or not ply:AddItem(INV_WEAPON, item) then continue end

		wep.Droping = true
		target:StripWeapon(class)

		DarkRP.log("police", ply, target, "изъял оружие" .. McINV.prt(item))
	end
end)

--[[---------------------------------------------------------------------------
	Склад улик: Inventory.Drop nypd <userid> (меню склада, police/sh_config.lua)
	userid - личные вещи задержанного, пусто - центральный склад
---------------------------------------------------------------------------]]
-- личные вещи оформляются на задержанного (наручники) или арестованного
local function evidenceOwner(ply, arg)
	local target = Player(math.floor(tonumber(arg) or 0))

	if not IsValid(target) or target:getDarkRPVar("character") == nil then
		return nil
	end

	if not target.HandCuffed and not target:isArrested() then
		return nil
	end

	return target
end

McINV.DropHandlers = McINV.DropHandlers or {}

McINV.DropHandlers.nypd = function(ply, arg)
	if not ply:isCP() or not ply:IsFreeman() then return end

	local ent = McINV.GetLootTarget(ply)
	if not ent or not ent.policeEvidnce then return end

	arg = string.Trim(tostring(arg or ""))

	local owner

	if arg ~= "" then
		owner = evidenceOwner(ply, arg)
		if not owner then return end
	end

	local sid = ply:SteamID64()
	local count = 0

	for _, type in ipairs(TYPES) do
		local list = ent.inv[type]
		if not istable(list) then continue end

		-- с конца: удаление не сдвигает ещё не просмотренные номера (у NPC в списке бывают дыры)
		for id = table.maxn(list), 1, -1 do
			local item = list[id]
			if not istable(item) or item.putby ~= sid or item.personal then continue end

			if owner then
				item.putby = owner:SteamID64()
				item.putname = "Личные вещи: " .. owner:FullName()
				item.personal = true
				count = count + 1

				DarkRP.log("police", ply, owner, "оформил личные вещи задержанного " .. McINV.prt(item, type))
			elseif ent:RemoveItem(type, id) then
				count = count + 1

				DarkRP.log("police", ply, nil, "отправил на центральный склад " .. McINV.prt(item, type))
			end
		end
	end

	if count == 0 then
		return
	end

	if owner then
		McINV.ContainerChanged(ent)
	end
end

--[[---------------------------------------------------------------------------
	Наручники сняли (офицер, отмычка, смерть, смена персонажа) - обыск закрывается
---------------------------------------------------------------------------]]
hook.Add("DarkRPVarChanged", "DarkRP.Search", function(ply, var, _, new)
	if var == "HandCuffed" and new == nil and IsValid(ply) then
		McINV.CloseViewers(ply)
	end
end)

--[[---------------------------------------------------------------------------
	Полицейский у NPC склада улик: свежий список задержанных для "Личные вещи #N"
---------------------------------------------------------------------------]]
hook.Add("PlayerUse", "DarkRP.Evidence", function(ply, ent)
	if not IsValid(ent) or not ent.policeEvidnce or not ply:isCP() then return end
	if not DarkRP.JailList or not Slawer or not Slawer.Mayor or DarkRP.NetDelay(ply, 2) then return end

	Slawer.Mayor:NetStart("GetJail", DarkRP.JailList(), ply)
end)
