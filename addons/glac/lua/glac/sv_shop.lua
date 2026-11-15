--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Покупка за кредиты и кейсы

	Buy: String ключ предмета, Int(10) оттенок меню (клиент: Glac.Buy).
	Ответ: Result - UInt(2) RESULT_ITEM, String предмет, Int(10) оттенок;
	неудача - RESULT_FAIL («недостаточно кредитов» в меню).
	Кейс: сначала CaseOpen (оттенок), затем Result с выпавшим предметом.

	Сервер проверяет сам: предмет есть и не NoBuy, его check(ply), цена
	(Glac.GetPrice), баланс. Кредиты списываются до выдачи, при ошибке выдачи
	возвращаются. Бесплатных покупок нет: Price 0 покупается, только если
	баланс не нужен и check разрешает (компенсация «Восстановление покупок»).
	Машины (McCD.AddCar) выдаются в личный гараж автосалона (шаг 15.4.3);
	если гараж игрока ещё грузится, машина ждёт и добавляется после загрузки.
	Ошибка выдачи (класса нет в sh_cars.lua) отменяет покупку и возвращает кредиты.
---------------------------------------------------------------------------]]
function Glac.SendFail(ply)
	Glac.NetStart("Result")
		net.WriteUInt(Glac.RESULT_FAIL, 2)
	net.Send(ply)
end

local function sendItem(ply, key, hue)
	Glac.NetStart("Result")
		net.WriteUInt(Glac.RESULT_ITEM, 2)
		net.WriteString(key)
		net.WriteInt(hue, 10)
	net.Send(ply)
end

local function canBuy(ply, item)
	if not item or item.NoBuy or not (item.is_case or isfunction(item.OnPurFunction)) then return false end
	if item.check then
		local ok, res = pcall(item.check, ply)
		if not ok or not res then return false end
	end

	return true
end

local function give(ply, item)
	local ok, err = pcall(item.OnPurFunction, ply, item)

	if not ok then
		ErrorNoHalt("[Glac] выдача '" .. tostring(item.key) .. "': " .. tostring(err) .. "\n")
	end

	return ok
end

-- выпавший предмет кейса по шансам
local function roll(caseId)
	local drops, total = Glac.Cases[caseId] or {}, 0

	for _, d in ipairs(drops) do total = total + math.max(d.chance, 0) end
	if total <= 0 then return nil end

	local r = math.random() * total

	for _, d in ipairs(drops) do
		r = r - math.max(d.chance, 0)
		if r <= 0 then return d.item end
	end

	return drops[#drops].item
end

Glac.NetReceive("Buy", function(ply)
	if not IsValid(ply) or ply.DarkRPUnInitialized or DarkRP.SpamBlock(ply, 1) then return end

	local key = net.ReadString()
	local hue = math.Clamp(net.ReadInt(10), -512, 511)
	local item = Glac.Items[key]

	if not canBuy(ply, item) then
		Glac.SendFail(ply)
		return
	end

	local price = math.max(math.floor(tonumber(Glac.GetPrice(item, ply)) or 0), 0)

	if not ply:TakeCredits(price) then
		Glac.SendFail(ply)
		return
	end

	local drop

	if item.is_case then
		local dropKey = roll(item.is_case)
		drop = dropKey and Glac.Items[dropKey]
		if not drop or not isfunction(drop.OnPurFunction) then
			ply:AddCredits(price)
			Glac.SendFail(ply)
			return
		end
	end

	if not give(ply, drop or item) then
		ply:AddCredits(price)
		Glac.SendFail(ply)
		return
	end

	DarkRP.log("money", ply, nil, "купил за кредиты: " .. tostring(key) .. (drop and (" -> " .. tostring(drop.key)) or ""), nil, price)

	if drop then
		Glac.NetStart("CaseOpen")
			net.WriteInt(hue, 10)
		net.Send(ply)

		sendItem(ply, drop.key, hue)
	else
		sendItem(ply, key, hue)
	end
end)
