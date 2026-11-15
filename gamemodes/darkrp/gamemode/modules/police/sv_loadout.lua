--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Оружейная полиции (меню "Разгрузка") - сервер

	Клиент: msd_ui/lua/msd/ui/police_ui.lua (MSD.Loadout.Create). Меню
	открывают NPC арсенала в участке (MCS, шаг 7) и пункт "Разгрузка" у
	полицейской машины (client/vgui.lua, машины из GAMEMODE.Config.PoliceCars).
	Предметы и цены - DarkRP.Police.PrimaryWeps, SecondaryWeps, SidearmWeps,
	Gear1 (police/sh_config.lua).

	net, C->S:
	  LoadoutGive, String таблица, String класс - взять предмет, а если он
	    уже выдан - сдать. В таблице - одна вещь: новая меняется на прежнюю.
	    "cuffs", "" - наручники (предмет INV_JUNK "cuffs").
	  LoadoutArmor, UInt(2): 0 - бронежилет, 2 - пиджак (ранг 8+). Повторное
	    нажатие снимает. 1 - куртка: в клиенте кнопка закомментирована.
	  LoadoutGiveAmmo - магазины к выданному оружию.
	net, S->C: LoadoutCliebt - перерисовать меню (через 0.3 с, когда
	оружие уже дошло до клиента).

	Где что выдают (как в клиенте):
	  тяжёлое оружие, пистолет, магазины - только в оружейной участка
	    (DarkRP.InsideArmory, GAMEMODE.Config.PoliceArmory);
	  снаряжение, бронежилет, наручники, пиджак - в оружейной или у
	    полицейской машины.
	Оружие и магазины - после экзамена exam_gun (MRS): снаряжение и
	магазины с 1, тяжёлое оружие и пистолет со 2, ранг 6+ - без экзамена.
	У предмета проверяются AllowedTeams, AllowedUsers, SHCheck, Level
	(улучшение мэрии ML, по умолчанию 1) и Rank.

	Залог: Price предмета берётся с ранга 1 и возвращается, когда оружие
	сдано - кнопкой, заменой, при смене профессии и персонажа, при выходе.
	При смерти оружие теряется, залог не возвращается.
	Выданное оружие - служебное (GivenByTeam): его не выбросить, не
	изъять, оно снимается при смене профессии (sv_jobs.lua).
	Магазины - служебные (nodrop): до 3 магазинов (или 2 пачек патронов)
	к каждому выданному оружию, пропадают при уходе из полиции.

	Бронежилеты - общий склад участка DarkRP.Police.Vests. Сколько их
	помещается и как часто привозят новый - улучшение мэрии 1
	"Полицейские бронежилеты" (Armor и Time уровня). Целый жилет можно
	сдать обратно, пробитый (броня 0) списывается.
	Наручники: первые за смену бесплатно, следующие - DarkRP.Police.CuffPrice.
---------------------------------------------------------------------------]]

util.AddNetworkString("LoadoutGive")
util.AddNetworkString("LoadoutArmor")
util.AddNetworkString("LoadoutGiveAmmo")
util.AddNetworkString("LoadoutCliebt")

local NET_DELAY = 0.3
local CAR_RANGE = 250 * 250
local CAR_CLASS = "gmod_sent_vehicle_fphysics_base"
local VEST = 2 -- armorVest: 1 - ESU (jobs.lua), 2 - бронежилет оружейной, 3 - костюм пожарного
local VEST_ARMOR = 100
local COAT_RANK = 7 -- пиджак - ранг больше 7, как в клиенте
local FREE_RANK = 5 -- ранг больше 5 - оружие без экзамена
local DEPOSIT_RANK = 2 -- залог берётся с ранга меньше 2
local MAX_MAGS = 3
local MAX_BOXES = 2

-- таблица меню: только в оружейной, нужный уровень exam_gun, название
local CATEGORIES = {
	PrimaryWeps = {armory = true, exam = 2},
	SecondaryWeps = {armory = true, exam = 2},
	SidearmWeps = {exam = 1},
	Gear1 = {exam = 1},
}

local function refresh(ply)
	timer.Simple(0.3, function()
		if not IsValid(ply) then return end

		net.Start("LoadoutCliebt")
		net.Send(ply)
	end)
end

local function rankOf(ply)
	return tonumber(MRS.GetNWdata(ply, "Rank")) or 1
end

local function examGun(ply)
	return tonumber(MRS.GetSData(ply, "exam_gun", 0)) or 0
end

local function money(n)
	return (GAMEMODE.Config.currency or "$") .. string.Comma(n)
end

--[[---------------------------------------------------------------------------
	Где стоит игрок
---------------------------------------------------------------------------]]
local function nearPoliceCar(ply)
	local cars = GAMEMODE.Config.PoliceCars or {}
	local pos = ply:GetPos()

	for _, ent in ipairs(ents.FindByClass(CAR_CLASS)) do
		if ent.GetSpawn_List and cars[ent:GetSpawn_List()] and ent:NearestPoint(pos):DistToSqr(pos) <= CAR_RANGE then
			return true
		end
	end

	return false
end

-- "armory", "car" или nil
local function placeOf(ply)
	if DarkRP.InsideArmory(ply) then return "armory" end
	if nearPoliceCar(ply) then return "car" end
end

-- общая проверка для всех запросов меню
local function canUse(ply)
	if not IsValid(ply) or not ply:isCP() or ply:getDarkRPVar("character") == nil then return end
	if DarkRP.NetDelay(ply, NET_DELAY) then return end

	if not ply:IsFreeman() then
		return
	end

	local place = placeOf(ply)

	if not place then
		return
	end

	return place
end

--[[---------------------------------------------------------------------------
	Оружие
---------------------------------------------------------------------------]]
local function deposits(ply)
	ply.PoliceDeposits = ply.PoliceDeposits or {}

	return ply.PoliceDeposits
end

local function depositFor(ply, item)
	local price = tonumber(item.Price) or 0

	return (price > 0 and rankOf(ply) < DEPOSIT_RANK) and price or 0
end

-- почему предмет не выдаётся (nil - выдаётся)
local function denied(ply, item)
	if item.AllowedTeams and not item.AllowedTeams[ply:Team()] then
		return "Это снаряжение не выдаётся вашей должности"
	end

	if item.AllowedUsers and not item.AllowedUsers[ply:SteamID()] then
		return "Это оружие выдаётся только по личному разрешению"
	end

	if item.SHCheck and not item.SHCheck(ply) then
		return "Это снаряжение выдаётся после экзамена"
	end

	if item.Level then
		local id = item.ML or 1

		if Slawer.Mayor:GetUpgradeLevel(id) < item.Level then
			local upgrade = Slawer.Mayor.CFG.Upgrades and Slawer.Mayor.CFG.Upgrades[id]

			return "Нужно улучшение мэрии «" .. (upgrade and upgrade.Name or tostring(id)) .. "» уровня " .. item.Level
		end
	end

	if item.Rank and rankOf(ply) < item.Rank then
		return "Выдаётся с ранга " .. item.Rank
	end
end

-- выданное оружие этой таблицы меню
local function loadoutWeapon(ply, cat)
	for _, wep in ipairs(ply:GetWeapons()) do
		if wep.PoliceLoadout == cat then return wep end
	end
end

-- сдать оружие: снять и вернуть залог; вернёт сумму залога
local function takeBack(ply, class)
	ply:StripWeapon(class)

	local dep = deposits(ply)[class] or 0
	deposits(ply)[class] = nil

	if dep > 0 then ply:addMoney(dep) end

	return dep
end

local function itemName(cat, class)
	local list = DarkRP.Police[cat]

	return list and list[class] and list[class].Name or class
end

local function giveWeapon(ply, cat, class, item)
	local old = loadoutWeapon(ply, cat)
	local oldClass = IsValid(old) and old:GetClass() or nil
	local dep = depositFor(ply, item)
	local oldDep = oldClass and deposits(ply)[oldClass] or 0

	if dep - oldDep > 0 and not ply:canAfford(dep - oldDep) then
		return
	end

	local wep = ply:Give(class)

	if not IsValid(wep) then
		return
	end

	wep.GivenByTeam = true
	wep.PoliceLoadout = cat

	if oldClass then
		takeBack(ply, oldClass)
	end

	if dep > 0 then
		ply:addMoney(-dep)
		deposits(ply)[class] = dep
	end

	DarkRP.log("police", ply, nil, "взял в оружейной " .. item.Name .. (dep > 0 and " (залог " .. money(dep) .. ")" or ""))
end

local function returnWeapon(ply, cat, class)
	local dep = takeBack(ply, class)
	local name = itemName(cat, class)

	DarkRP.log("police", ply, nil, "сдал в оружейную " .. name)
end

--[[---------------------------------------------------------------------------
	Наручники
---------------------------------------------------------------------------]]
local function giveCuffs(ply)
	if not istable(ply.inv) then return end

	if ply:HaveItem(INV_JUNK, "cuffs") > 0 then
		return
	end

	local data = McINV.GetItem(INV_JUNK, "cuffs")
	if not data then return end

	if not ply:HaveSpace(McINV.GetWeight(data, INV_JUNK, "cuffs")) then
		return
	end

	local sid = ply:SteamID64()
	local given = DarkRP.Police.Cuffs[sid] or 0
	local price = given > 0 and (tonumber(DarkRP.Police.CuffPrice) or 0) or 0

	if price > 0 and not ply:canAfford(price) then
		return
	end

	if not ply:AddItemByClass(INV_JUNK, "cuffs") then return end

	DarkRP.Police.Cuffs[sid] = given + 1

	if price > 0 then
		ply:addMoney(-price)
	end

	DarkRP.log("police", ply, nil, "взял в оружейной наручники" .. (price > 0 and " за " .. money(price) or ""))
end

--[[---------------------------------------------------------------------------
	Бронежилеты: общий склад
---------------------------------------------------------------------------]]
local function vestLevel()
	local upgrade = Slawer.Mayor.CFG.Upgrades and Slawer.Mayor.CFG.Upgrades[1]
	local levels = upgrade and upgrade.Levels or {}
	local data = levels[Slawer.Mayor:GetUpgradeLevel(1)] or levels[0] or {}

	return tonumber(data.Armor) or 5, tonumber(data.Time) or 300
end

-- новые жилеты привозят по одному раз в Time секунд, пока склад не полон
local function restock()
	local P = DarkRP.Police
	local max, period = vestLevel()
	local now = CurTime()

	if P.Vests >= max then
		P.VestsUpdate = 0
		return max, period
	end

	if P.VestsUpdate == 0 or P.VestsUpdate > now + period then
		P.VestsUpdate = now + period
	end

	while P.Vests < max and P.VestsUpdate <= now do
		P.Vests = P.Vests + 1
		P.VestsUpdate = P.VestsUpdate + period
	end

	if P.Vests >= max then P.VestsUpdate = 0 end

	return max, period
end

-- жилет возвращается на склад, если он не пробит
local function stockVest(armor)
	local P = DarkRP.Police
	local max = restock()

	if armor <= 0 then return false end

	P.Vests = math.min(P.Vests + 1, max)
	if P.Vests >= max then P.VestsUpdate = 0 end

	return true
end

-- снять жилет оружейной; вернёт true, если он ушёл на склад.
-- MCR.SetArmor снимает пиджак под жилет и запоминает его в ply.oldset, а
-- при снятии жилета надевает обратно. После этого oldset сбрасывается,
-- иначе пиджак вернулся бы и при следующем жилете. newModel - модель уже
-- сменилась (новая профессия): пиджак не возвращается
local function removeVest(ply, newModel)
	local armor = ply:Armor()

	ply.PoliceVest = nil
	if newModel then ply.oldset = nil end

	if ply:getDarkRPVar("armorVest") == VEST then
		ply:SetDarkRPVar("armorVest", nil)
		ply:SetArmor(0)
		MCR.SetArmor(ply, false)
	end

	ply.oldset = nil

	return stockVest(armor)
end

local function toggleVest(ply)
	local cur = ply:getDarkRPVar("armorVest")

	if cur == VEST then
		local stocked = removeVest(ply)

		DarkRP.log("police", ply, nil, stocked and "сдал бронежилет" or "сдал пробитый бронежилет")
		return
	end

	if cur then
		return
	end

	local P = DarkRP.Police
	local _, period = restock()

	if P.Vests < 1 then
		return
	end

	P.Vests = P.Vests - 1
	if P.VestsUpdate == 0 then P.VestsUpdate = CurTime() + period end

	ply.PoliceVest = true
	ply:SetDarkRPVar("armorVest", VEST)
	ply:SetArmor(VEST_ARMOR)
	MCR.SetArmor(ply, true)

	DarkRP.log("police", ply, nil, "взял бронежилет, на складе " .. P.Vests)
end

-- пиджак: MCR.SetArmor(ply, true, 3) сам надевает и снимает (character/sh_util.lua)
local function toggleCoat(ply)
	if ply:Team() == TEAM_DETECTIVE then
		return
	end

	if not string.find(ply:GetModel() or "", "nypd", 1, true) then
		return
	end

	if rankOf(ply) <= COAT_RANK then
		return
	end

	if ply:getDarkRPVar("armorVest") then
		return
	end

	MCR.SetArmor(ply, true, 3)
end

--[[---------------------------------------------------------------------------
	Магазины к выданному оружию
---------------------------------------------------------------------------]]
-- ёмкость по цепочке базовых классов (police_mk20 -> mwb_mk17):
-- weapons.Get наследует только верхний уровень, Primary берётся целиком
local function baseClip(t)
	while istable(t) do
		local clip = istable(t.Primary) and tonumber(t.Primary.ClipSize)
		if clip and clip > 0 then return clip end

		t = t.BaseClass
	end
end

-- какой магазин (или пачка) подходит оружию и сколько их держать
local function ammoFor(wep)
	local t = weapons.Get(wep:GetClass())
	if not t then return end

	if istable(t.UseMags) then
		-- магазин под штатную ёмкость оружия, иначе самый маленький
		local clip = wep:GetMaxClip1()
		if not clip or clip <= 0 then clip = baseClip(t) end
		local best, bestAmmo

		for class in SortedPairs(t.UseMags) do
			local data = DarkRP.Ammo[class]

			if data and data.ammo then
				if data.ammo == clip then return class, data, MAX_MAGS end

				if not bestAmmo or data.ammo < bestAmmo then
					best, bestAmmo = class, data.ammo
				end
			end
		end

		if best then return best, DarkRP.Ammo[best], MAX_MAGS end
	elseif istable(t.UseINV) then
		for class, on in SortedPairs(t.UseINV) do
			if on == true and DarkRP.Ammo[class] then return class, DarkRP.Ammo[class], MAX_BOXES end
		end
	end
end

-- пустые служебные магазины этих классов выбрасываются
local function dropEmpty(ply, classes)
	local list = ply.inv[INV_AMMO]

	for id = #list, 1, -1 do
		local item = list[id]
		local ammo = istable(item.dt) and tonumber(item.dt.Ammo) or 0

		if item.nodrop and classes[item.class] and ammo <= 0 then
			ply:RemoveItem(INV_AMMO, id)
		end
	end
end

local function countFull(ply, class)
	local n = 0

	for _, item in ipairs(ply.inv[INV_AMMO]) do
		if item.class == class and istable(item.dt) and (tonumber(item.dt.Ammo) or 0) > 0 then
			n = n + 1
		end
	end

	return n
end

local function giveAmmo(ply)
	if not istable(ply.inv) then return end

	local plan, classes = {}, {}

	for _, wep in ipairs(ply:GetWeapons()) do
		if not wep.PoliceLoadout then continue end

		local class, data, max = ammoFor(wep)

		if class and not classes[class] then
			classes[class] = true
			plan[#plan + 1] = {class = class, data = data, max = max, name = itemName(wep.PoliceLoadout, wep:GetClass())}
		end
	end

	if #plan == 0 then
		return
	end

	dropEmpty(ply, classes)

	local given, full = {}, false

	for _, p in ipairs(plan) do
		local weight = (tonumber(p.data.weight) or 0) + (tonumber(p.data.ammo) or 0) * (tonumber(p.data.bul) or 0)
		local n = 0

		for _ = countFull(ply, p.class) + 1, p.max do
			if not ply:HaveSpace(weight) then
				full = true
				break
			end

			if not ply:AddMag(p.class, p.data.ammo, true) then break end

			n = n + 1
		end

		if n > 0 then given[#given + 1] = p.name .. " x" .. n end
	end

	if #given == 0 then
		return
	end

	DarkRP.log("police", ply, nil, "взял магазины: " .. table.concat(given, ", "))
end

-- служебные магазины пропадают у тех, кто ушёл из полиции
local function dropServiceAmmo(ply)
	local list = istable(ply.inv) and ply.inv[INV_AMMO]
	if not istable(list) then return end

	local removed = false

	for id = #list, 1, -1 do
		if list[id].nodrop then
			table.remove(list, id)
			removed = true
		end
	end

	if removed and ply.UpdateInventory then ply:UpdateInventory() end
end

--[[---------------------------------------------------------------------------
	Запросы меню
---------------------------------------------------------------------------]]
net.Receive("LoadoutGive", function(_, ply)
	local cat = net.ReadString()
	local class = net.ReadString()

	local place = canUse(ply)
	if not place then return end

	if cat == "cuffs" then
		giveCuffs(ply)
		refresh(ply)
		return
	end

	local rules = CATEGORIES[cat]
	local item = rules and DarkRP.Police[cat] and DarkRP.Police[cat][class]
	if not item then return end

	if rules.armory and place ~= "armory" then
		return
	end

	local wep = ply:GetWeapon(class)

	if IsValid(wep) then
		if wep.PoliceLoadout then
			returnWeapon(ply, wep.PoliceLoadout, class)
			refresh(ply)
		end

		return
	end

	if examGun(ply) < rules.exam and rankOf(ply) <= FREE_RANK then
		return
	end

	local why = denied(ply, item)

	if why then
		return
	end

	giveWeapon(ply, cat, class, item)
	refresh(ply)
end)

net.Receive("LoadoutArmor", function(_, ply)
	local kind = net.ReadUInt(2)

	if not canUse(ply) then return end

	if kind == 0 then
		toggleVest(ply)
	elseif kind == 2 then
		toggleCoat(ply)
	else
		return
	end

	refresh(ply)
end)

net.Receive("LoadoutGiveAmmo", function(_, ply)
	local place = canUse(ply)
	if not place then return end

	if place ~= "armory" then
		return
	end

	if examGun(ply) < 1 and rankOf(ply) <= FREE_RANK then
		return
	end

	giveAmmo(ply)
	refresh(ply)
end)

--[[---------------------------------------------------------------------------
	Смена профессии и персонажа, выход, смерть
---------------------------------------------------------------------------]]
-- оружие уже снято (GivenByTeam), вернуть залоги и жилет
local function settle(ply, silent)
	local sum = 0

	for _, dep in pairs(ply.PoliceDeposits or {}) do
		sum = sum + dep
	end

	ply.PoliceDeposits = nil

	if sum > 0 then
		ply:addMoney(sum)
	end

	if ply.PoliceVest then
		removeVest(ply, true)
	end
end

hook.Add("OnPlayerChangedTeam", "DarkRP.Police.Loadout", function(ply, _, new)
	settle(ply)

	if not (GAMEMODE.CivilProtection and GAMEMODE.CivilProtection[new]) then
		dropServiceAmmo(ply)
		DarkRP.Police.Cuffs[ply:SteamID64()] = nil
	end
end)

-- при выходе оружие пропадает вместе с игроком: залог возвращается
hook.Add("PlayerDisconnected", "DarkRP.Police.Loadout", function(ply)
	for class in pairs(ply.PoliceDeposits or {}) do
		if ply:HasWeapon(class) then ply:StripWeapon(class) end
	end

	settle(ply, true)
	dropServiceAmmo(ply)
	DarkRP.Police.Cuffs[ply:SteamID64()] = nil
end)

-- смена персонажа: служебное оружие снимает StripWeapons, служебные магазины (nodrop) убирает
-- инвентарь, остальные карманы ждут персонажа
hook.Add("MCR.CharacterReset", "DarkRP.Police.Loadout", function(ply)
	settle(ply, true)
	DarkRP.Police.Cuffs[ply:SteamID64()] = nil
end)

hook.Add("PlayerDeath", "DarkRP.Police.Loadout", function(ply)
	-- залог за служебное оружие при смерти не возвращается
	ply.PoliceDeposits = nil

	-- жилет пропадает вместе с бронёй, модель при возрождении ставится заново
	if ply.PoliceVest then
		ply.PoliceVest = nil
		ply.oldset = nil

		if ply:getDarkRPVar("armorVest") == VEST then
			ply:SetDarkRPVar("armorVest", nil)
		end
	end
end)

-- жилет сняли сами (F4, remove_vest) - он выброшен, на склад не вернётся
hook.Add("DarkRPVarChanged", "DarkRP.Police.Loadout", function(ply, var, old, new)
	if var ~= "armorVest" or old ~= VEST or new == VEST or not ply.PoliceVest then return end

	ply.PoliceVest = nil
	MCR.SetArmor(ply, false)
	ply.oldset = nil
end)
