--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Контракты RDM (Rhode Defence Manufacturer) - сервер

	Сайт RDM в телефоне (mc_phone/modules/web_shop_gun.lua, вкладка
	контрактов - у оружейного мастера) спрашивает активный контракт:
	  DarkRP.ShareDataReq C->S: 0
	                      S->C: 0, есть ли контракт, {name - заказчик,
	                      weapon = {class, ammount - сколько сдать за раз},
	                      price - премия, %}
	Другим профессиям контракта нет.

	Контракт - оружие со стола оружейника (GunNamesGlobal,
	workstation_guns/shared.lua) с ценой в DarkRP.Weapons: партия 2-5 штук,
	премия 10-30%, общая квота - 2-4 партии.
	Сдают Кольту Магнуссону (NPC coltrdm, "Склад RDM",
	mcs_npcs/npcs/utill.lua): оружейный мастер кладёт оружие на склад (вещь
	помечается, кто положил, - putby, sv_init.lua). Каждые 2 с склады
	проверяются: набралась у мастера партия - оружие класса контракта с
	серийным номером (спиленный номер и оружие без номера не принимаются) -
	склад забирает его (не больше остатка квоты) и платит цену оружия с
	премией за штуку на счёт зарплаты (ply:PayDay, письмо банка). Мастер для
	этого должен быть в сети персонажем-оружейником. Остальное лежит на
	складе, забрать может только положивший.
	Квота выполнена - следующий контракт через 30 минут.
---------------------------------------------------------------------------]]

util.AddNetworkString("DarkRP.ShareDataReq")

local ISSUER = "Rhode Defence Manufacturer" -- как в реплике Кольта Магнуссона
local CHECK = 2 -- проверка складов, с
local AMOUNT = {2, 5} -- партия, штук
local PREMIUM = {10, 30} -- премия к цене, %
local QUOTA = {2, 4} -- квота, партий
local PAUSE = 1800 -- новый контракт после выполненного, с

-- McINV.RDMContract = {class, amount, premium, left} или nil; McINV.RDMNext - не раньше
McINV.RDMNext = McINV.RDMNext or 0

-- стол оружейника грузится после модулей: контракт создаётся, когда он нужен
local function contract()
	if McINV.RDMContract then return McINV.RDMContract end
	if CurTime() < McINV.RDMNext or not istable(GunNamesGlobal) then return nil end

	local classes = {}

	for class in pairs(GunNamesGlobal) do
		local wep = DarkRP.Weapons[class]

		if istable(wep) and (tonumber(wep.price) or 0) > 0 then
			classes[#classes + 1] = class
		end
	end

	if #classes == 0 then return nil end

	table.sort(classes)

	local amount = math.random(AMOUNT[1], AMOUNT[2])

	McINV.RDMContract = {
		class = classes[math.random(#classes)],
		amount = amount,
		premium = math.random(PREMIUM[1], PREMIUM[2]),
		left = amount * math.random(QUOTA[1], QUOTA[2]),
	}

	return McINV.RDMContract
end

net.Receive("DarkRP.ShareDataReq", function(_, ply)
	if DarkRP.NetDelay(ply, 1) then return end
	if net.ReadUInt(3) ~= 0 then return end

	local c = ply:Team() == TEAM_GUN and ply:getDarkRPVar("character") ~= nil and contract() or nil

	net.Start("DarkRP.ShareDataReq")
		net.WriteUInt(0, 3)
		net.WriteBool(c ~= nil)

		if c then
			net.WriteTable({
				name = ISSUER,
				weapon = {class = c.class, ammount = math.min(c.amount, c.left)},
				price = c.premium,
			})
		end
	net.Send(ply)
end)

-- одна партия за проверку: номера вещей после неё сдвигаются
local function deliver(npc, c)
	local list = npc.inv[INV_WEAPON]

	-- [SteamID64] = номера подходящих вещей
	local byOwner = {}

	for id, item in pairs(list) do
		if istable(item) and item.class == c.class and istable(item.register) and item.putby then
			byOwner[item.putby] = byOwner[item.putby] or {}
			table.insert(byOwner[item.putby], id)
		end
	end

	local need = math.min(c.amount, c.left)

	for sid, ids in pairs(byOwner) do
		local ply = player.GetBySteamID64(sid)

		if #ids >= need and IsValid(ply) and ply:Team() == TEAM_GUN and ply:getDarkRPVar("character") ~= nil then
			table.sort(ids)

			local count = math.min(#ids, c.left)

			for i = count, 1, -1 do
				McINV.RemoveAt(list, ids[i])
			end

			McINV.ContainerChanged(npc)

			local price = math.Round(DarkRP.Weapons[c.class].price * (1 + c.premium / 100))

			ply:PayDay(price * count)
			c.left = c.left - count

			DarkRP.log("money", ply, nil, "сдал по контракту RDM " .. count .. " x " .. c.class, nil, price * count)

			if c.left <= 0 then
				McINV.RDMContract = nil
				McINV.RDMNext = CurTime() + PAUSE
			end

			return
		end
	end
end

timer.Create("McINV.RDMContract", CHECK, 0, function()
	local c = contract()
	if not c then return end

	for _, npc in ipairs(ents.FindByClass("mcs_npc")) do
		if npc.RDMContract and istable(npc.inv) and istable(npc.inv[INV_WEAPON]) then
			deliver(npc, c)

			if McINV.RDMContract ~= c then return end
		end
	end
end)
