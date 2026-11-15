--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Розыск и ордера на обыск - сервер

	Розыск - переменные DarkRP wanted и wantedReason. По ним компьютер
	участка (slawer_mayor, вкладка "Розыск") показывает список, таран
	(weapon_ram) вскрывает двери разыскиваемого, NPC MCS его пугаются,
	телефон и квесты MQS отказывают, персонажа не сменить.
	Объявляют: полицейский за компьютером (drp_wanted,
	slawer_mayor/modules/wanted/sv.lua), квесты MQS ("DarkRP Wanted") и
	NPC MCS ("licensenomoney" - попытка дачи взятки) без полицейского.
	Снимают: супервайзер за компьютером (drp_unwanted), sAdmin
	(unwanted), задержание или арест (хук playerArrested), конец срока
	розыска (Config.wantedtime).

	Ордер на обыск недвижимости: полицейский за компьютером указывает адрес
	(drp_warrant, slawer_mayor/modules/warrants/sv.lua). Решает районный
	администратор (вопрос на 40 с), если его нет в городе - ордер выдаётся
	сразу, как в DarkRP. Ордер получает владелец недвижимости:
	ply.warranted = true, по нему таран вскрывает его двери.
	Действует Config.searchtime (нет в конфиге - 30 минут).

	Права проверяют хуки автора (sh_init.lua): canWanted, canUnwant,
	canRequestWarrant, canUnwarrant. Розыскиваемому и владельцу приходят
	письма на телефон (фразы wanted_test и warrant_test).
	Вышедший из игры в розыске снова в розыске, когда выберет этого
	персонажа: остаток хранится в памяти до перезапуска сервера.
---------------------------------------------------------------------------]]

local plyMeta = FindMetaTable("Player")

local MAX_WANTED_TIME = 24 * 3600
local DEFAULT_SEARCH_TIME = 30 * 60 -- ордер, если в конфиге нет searchtime
local QUESTION_TIME = 40 -- районному администратору на ответ, как в DarkRP
local REQUEST_COOLDOWN = 60 -- запросы ордера одного полицейского
local CHECK_INTERVAL = 1
local MAX_QUERY = 64 -- длина поиска по ID паспорта или имени
local DEFAULT_REASON = "Не указана"
local MAIL_FROM = "Окружная Полиция"

-- остаток розыска вышедших: DarkRP.CharacterID -> {left, reason}
local suspended = {}

-- запросы ордера у районного администратора: владелец -> запрос
local pending = {}

local function validPlayer(ply, except)
	return IsValid(ply) and ply:IsPlayer() and ply ~= except
end

local function inCity(ply)
	return ply:getDarkRPVar("character") ~= nil
end

-- до ближайшей минуты, как в sv_arrest.lua
local function niceTime(sec)
	sec = math.max(math.floor((tonumber(sec) or 0) + 0.5), 0)

	local h = math.floor(sec / 3600)
	local m = math.floor((sec - h * 3600) / 60 + 0.5)

	if m >= 60 then h, m = h + 1, m - 60 end
	if h > 0 then return m > 0 and (h .. " ч. " .. m .. " мин.") or (h .. " ч.") end

	return math.max(m, 1) .. " мин."
end

-- utf8.lower - a_config_gmodla (city_extentions/sh_utf8.lua), знает
-- кириллицу, но на неверном UTF-8 падает с ошибкой
local function lower(s)
	if utf8.lower and utf8.len(s) then
		local ok, res = pcall(utf8.lower, s)
		if ok then return res end
	end

	return string.lower(s)
end

-- причина в одну строку: её показывают список компьютера и письма
local function cleanText(s)
	if not isstring(s) then return "" end

	return string.Trim((string.gsub(s, "[\r\n\t]+", " ")))
end

local function searchTime()
	local t = tonumber(GAMEMODE.Config.searchtime)

	return t and t > 0 and t or DEFAULT_SEARCH_TIME
end

-- полиция в городе, кроме указанных
local function notifyPolice(msg, ...)
	local except = {...}

	for _, v in ipairs(player.GetAll()) do
		if not v:isCP() or not inCity(v) then continue end

		local skip = false

		for i = 1, select("#", ...) do
			if except[i] == v then skip = true break end
		end

		if not skip then DarkRP.notify(v, 0, 6, msg) end
	end
end

local function mail(ply, text)
	if McPhone and McPhone.NewMail and validPlayer(ply) then
		McPhone.NewMail(MAIL_FROM, text, ply)
	end
end

-- "Офицер Имя Фамилия": звание MRS, если есть
local function officerName(ply)
	if MRS and MRS.GetActiveRankData then
		local _, rank = MRS.GetActiveRankData(ply)
		if istable(rank) and isstring(rank.name) and rank.name ~= "" then return rank.name .. " " .. ply:FullName() end
	end

	return ply:FullName()
end

-- адрес как в поиске клиента: "North street 11, Квартира 4"
local function addressOf(ter)
	local name = isstring(ter.printName) and ter.printName or tostring(ter.name or "")

	if isstring(ter.printStr) and ter.printStr ~= "" then return ter.printStr .. ", " .. name end

	return name
end

--[[---------------------------------------------------------------------------
	DarkRP.findCitizen(query) - житель по ID паспорта (DarkRP.PassId) или
	имени персонажа: полное совпадение, иначе единственное частичное.
	nil и текст для полицейского, если не нашёлся или подходят несколько
---------------------------------------------------------------------------]]
function DarkRP.findCitizen(query)
	query = cleanText(query)

	if query == "" then return nil, "Укажите ID паспорта или имя" end
	if #query > MAX_QUERY or not utf8.len(query) then return nil, "Человек не найден" end

	local byPass = DarkRP.findBYPassID(query)
	if validPlayer(byPass) and inCity(byPass) then return byPass end

	local needle = lower(query)
	local citizens = {}

	for _, v in ipairs(player.GetAll()) do
		if not inCity(v) then continue end

		local name = lower(v:FullName())
		if name == needle then return v end

		citizens[#citizens + 1] = {ply = v, name = name}
	end

	local found

	for _, v in ipairs(citizens) do
		if string.find(v.name, needle, 1, true) then
			if found then return nil, "Под это имя подходят несколько человек: укажите ID паспорта" end
			found = v.ply
		end
	end

	if found then return found end

	return nil, "Человек не найден"
end

--[[---------------------------------------------------------------------------
	Розыск
---------------------------------------------------------------------------]]
-- сначала wanted, потом wantedReason: клиент компьютера добавляет запись в
-- список по wantedReason и убирает по wanted (modules/wanted/cl.lua)
local function setWanted(ply, reason, untilTime)
	ply.WantedUntil = untilTime
	ply:SetDarkRPVar("wanted", true)
	ply:SetDarkRPVar("wantedReason", reason)
end

local function clearWanted(ply)
	ply.WantedUntil = nil
	ply:SetDarkRPVar("wanted", nil)
	ply:SetDarkRPVar("wantedReason", nil)
end

--[[---------------------------------------------------------------------------
	ply:wanted(actor, reason, time) - объявить в розыск на time секунд
	(nil или 0 - Config.wantedtime). actor - полицейский или nil (квесты,
	NPC). Уже разыскиваемому - новая причина, срок - больший из оставшегося
	и нового. Персонаж не выбран - false.
	Хук playerWanted(ply, actor, reason)
---------------------------------------------------------------------------]]
function plyMeta:wanted(actor, reason, time)
	if not inCity(self) then return false end
	if not validPlayer(actor, self) then actor = nil end

	reason = cleanText(reason)
	if reason == "" then reason = DEFAULT_REASON end

	time = tonumber(time)
	if not time or time <= 0 then time = tonumber(GAMEMODE.Config.wantedtime) or 0 end
	if time <= 0 then time = MAX_WANTED_TIME end
	time = math.Clamp(math.ceil(time), 1, MAX_WANTED_TIME)

	local CT = CurTime()
	local again = self:isWanted() and self.WantedUntil ~= nil
	local untilTime = math.max(math.ceil(CT + time), again and self.WantedUntil or 0)

	setWanted(self, reason, untilTime)

	local name = self:FullName()

	DarkRP.notify(self, 1, 8, DarkRP.getPhrase("wanted"))
	mail(self, DarkRP.getPhrase("wanted_test", name, reason))

	if actor then
		DarkRP.log("police", actor, self, again and "продлил розыск" or "объявил в розыск", nil, reason)
	else
		DarkRP.log("police", self, nil, again and "розыск продлён" or "объявлен в розыск", nil, reason)
	end

	hook.Run("playerWanted", self, actor, reason)

	return true
end

-- why: nil - снял полицейский, "forced" - sAdmin, "expired" - срок вышел,
-- "arrested" - задержан или арестован
local function endWanted(ply, actor, why)
	if not ply:isWanted() then return false end
	if not validPlayer(actor, ply) then actor = nil end

	local reason = ply:getDarkRPVar("wantedReason")
	local name = ply:FullName()

	clearWanted(ply)

	if why == "arrested" then
		DarkRP.log("police", ply, nil, "розыск снят: задержан", nil, reason)
	elseif why == "expired" then
		notifyPolice(DarkRP.getPhrase("wanted_expired", name), ply)
		DarkRP.log("police", ply, nil, "розыск закончился", nil, reason)
	elseif actor then
		notifyPolice(DarkRP.getPhrase("wanted_expired", name), actor, ply)
		DarkRP.log("police", actor, ply, "снял розыск", nil, reason)
	else
		notifyPolice(DarkRP.getPhrase("wanted_expired", name), ply)
		DarkRP.log("police", ply, nil, why == "forced" and "розыск снят администратором" or "розыск снят", nil, reason)
	end

	hook.Run("playerUnWanted", ply, actor)

	return true
end

--[[---------------------------------------------------------------------------
	ply:unWanted(actor) - снять розыск. actor - полицейский или строка
	(sAdmin передаёт "force command"). false, если не в розыске.
	Хук playerUnWanted(ply, actor)
---------------------------------------------------------------------------]]
function plyMeta:unWanted(actor)
	return endWanted(self, actor, isstring(actor) and "forced" or nil)
end

-- задержан по протоколу или посажен в камеру: розыск больше не нужен
hook.Add("playerArrested", "DarkRP.Wanted", function(ply, time, arrester)
	endWanted(ply, arrester, "arrested")
end)

--[[---------------------------------------------------------------------------
	Ордер на обыск
---------------------------------------------------------------------------]]
-- info: {address, territory}; approver - районный администратор или nil
local function issueWarrant(owner, warranter, reason, info, approver)
	if owner.warranted then return false end
	if not validPlayer(warranter, owner) then warranter = nil end

	local time = searchTime()
	local address = info.address or "имущество"
	local name = owner:FullName()

	owner.warranted = true
	owner.WarrantInfo = {
		by = warranter,
		reason = reason,
		address = address,
		territory = info.territory,
		expires = math.ceil(CurTime() + time),
	}

	if warranter then
		DarkRP.notify(warranter, 0, 8, DarkRP.getPhrase("warrant_approved2"))
	end

	mail(owner, DarkRP.getPhrase("warrant_test", name, reason))

	local detail = address .. ": " .. reason

	if validPlayer(approver) then
		if warranter then detail = detail .. ", запросил " .. warranter:FullName() end
		DarkRP.log("police", approver, owner, "выдал ордер на обыск", nil, detail)
	elseif warranter then
		DarkRP.log("police", warranter, owner, "получил ордер на обыск без районного администратора", nil, detail)
	else
		DarkRP.log("police", owner, nil, "получен ордер на обыск", nil, detail)
	end

	hook.Run("playerWarranted", owner, warranter, reason)

	return true
end

-- why: nil - отменил полицейский, "expired" - срок вышел, "left" - владелец ушёл
local function endWarrant(ply, actor, why)
	if not ply.warranted then return false end
	if not validPlayer(actor, ply) then actor = nil end

	local info = ply.WarrantInfo or {}
	local address = info.address or "имущество"
	local by = validPlayer(info.by, ply) and info.by or nil

	ply.warranted = nil
	ply.WarrantInfo = nil

	if why == "expired" then
		DarkRP.log("police", ply, nil, "ордер на обыск закончился", nil, address)
	elseif why == "left" then
		DarkRP.log("police", ply, nil, "ордер на обыск снят: владелец ушёл", nil, address)
	else
		if by and by ~= actor then DarkRP.notify(by, 1, 6, DarkRP.getPhrase("warrant_expired")) end
		DarkRP.log("police", actor or ply, actor and ply or nil, actor and "отменил ордер на обыск" or "ордер на обыск отменён", nil, address)
	end

	hook.Run("playerUnWarranted", ply, actor)

	return true
end

--[[---------------------------------------------------------------------------
	ply:warrant(warranter, reason, territory) - ордер на обыск имущества
	игрока сразу, без районного администратора. territory - имя территории
	из Territories.list для адреса, необязательно. false, если ордер уже есть.
	Хук playerWarranted(ply, warranter, reason)
---------------------------------------------------------------------------]]
function plyMeta:warrant(warranter, reason, territory)
	local ter = isstring(territory) and Territories and Territories.list and Territories.list[territory]

	reason = cleanText(reason)
	if reason == "" then reason = DEFAULT_REASON end

	return issueWarrant(self, warranter, reason, {address = istable(ter) and addressOf(ter) or nil, territory = istable(ter) and territory or nil})
end

--[[---------------------------------------------------------------------------
	ply:unWarrant(unwarranter) - отменить ордер (права - хук canUnwarrant
	проверяет вызывающий). false, если ордера нет.
	Хук playerUnWarranted(ply, unwarranter)
---------------------------------------------------------------------------]]
function plyMeta:unWarrant(unwarranter)
	return endWarrant(self, unwarranter)
end

-- районный администратор в городе (не бот: боту вопрос не задать)
local function mayorFor(actor)
	local list = {}

	for _, v in ipairs(player.GetAll()) do
		if v ~= actor and not v:IsBot() and v:isMayor() and inCity(v) then list[#list + 1] = v end
	end

	if #list == 0 then return nil end

	return list[math.random(#list)]
end

local function finishRequest(answer, mayor, req)
	if pending[req.owner] == req then pending[req.owner] = nil end
	if req.cancelled then return end

	local actor, owner = req.actor, req.owner

	if not answer then
		DarkRP.log("police", validPlayer(mayor) and mayor or actor, owner, "отказал в ордере на обыск", nil, req.address)
		return
	end

	-- пока решали, недвижимость могли продать
	if not validPlayer(owner) or req.ter.masterOwner ~= owner then return end

	issueWarrant(owner, actor, req.reason, {address = req.address, territory = req.territory}, mayor)
end

local function questionText(req)
	return "Полиция запрашивает ордер на обыск недвижимости\n" ..
		"Адрес: " .. req.address .. "\n" ..
		"Владелец: " .. req.owner:FullName() .. "\n" ..
		"Запросил: " .. officerName(req.actor) .. "\n" ..
		"Причина: " .. req.reason .. "\n\nВыдать ордер?"
end

--[[---------------------------------------------------------------------------
	DarkRP.requestWarrant(actor, territory, reason) - запрос ордера на обыск
	недвижимости (имя территории из Territories.list). Ордер получает её
	владелец (masterOwner). Возвращает ok и причину отказа (не показывается:
	уведомлением приходит только отказ хука автора canRequestWarrant)
---------------------------------------------------------------------------]]
function DarkRP.requestWarrant(actor, territory, reason)
	if not validPlayer(actor) then return false end

	local ter = isstring(territory) and Territories and Territories.list and Territories.list[territory]
	if not istable(ter) or not ter.buyable then return false, "Адрес не найден" end

	local owner = ter.masterOwner

	if not validPlayer(owner) or not inCity(owner) then
		if isfunction(ter.Owned) and ter:Owned() then return false, "Владельца этой недвижимости сейчас нет в городе" end

		return false, "Эта недвижимость никому не принадлежит"
	end

	if owner == actor then return false, "Это ваша недвижимость" end

	reason = cleanText(reason)
	if not utf8.len(reason) then return false, "Неверная причина" end

	local ok, msg = hook.Call("canRequestWarrant", DarkRP.hooks, owner, actor, reason)

	if not ok then
		if msg then DarkRP.notify(actor, 1, 4, msg) end
		return false, msg
	end

	if pending[owner] then return false, "Запрос ордера на обыск у этого владельца уже рассматривается" end

	local CT = CurTime()

	if actor.WarrantRequestAt and actor.WarrantRequestAt > CT then
		return false, "Новый запрос ордера - через " .. math.ceil(actor.WarrantRequestAt - CT) .. " с."
	end

	actor.WarrantRequestAt = CT + REQUEST_COOLDOWN

	local req = {
		actor = actor,
		owner = owner,
		ter = ter,
		territory = territory,
		reason = reason,
		address = addressOf(ter),
	}

	local mayor = mayorFor(actor)

	if not mayor then
		issueWarrant(owner, actor, reason, {address = req.address, territory = territory})
		return true
	end

	req.mayor = mayor
	pending[owner] = req

	DarkRP.log("police", actor, owner, "запросил ордер на обыск", nil, req.address .. ": " .. reason)
	DarkRP.createQuestion(questionText(req), mayor, finishRequest, QUESTION_TIME, req)

	return true
end

--[[---------------------------------------------------------------------------
	Раз в секунду: конец срока розыска и ордеров
---------------------------------------------------------------------------]]
timer.Create("DarkRP.Wanted", CHECK_INTERVAL, 0, function()
	local CT = CurTime()

	for _, ply in ipairs(player.GetAll()) do
		if ply.WantedUntil and ply.WantedUntil <= CT then
			if ply:isWanted() then endWanted(ply, nil, "expired") else ply.WantedUntil = nil end
		end

		local info = ply.WarrantInfo
		if ply.warranted and info and info.expires <= CT then endWarrant(ply, nil, "expired") end
	end
end)

--[[---------------------------------------------------------------------------
	Выход из игры и смена персонажа: остаток розыска - до следующего выбора
	этого персонажа (MCR.CharacterSelected), ордер и запросы снимаются
---------------------------------------------------------------------------]]
local function leave(ply)
	for owner, req in pairs(pending) do
		if owner == ply or req.actor == ply then
			req.cancelled = true
			pending[owner] = nil
		end
	end

	endWarrant(ply, nil, "left")

	if not ply:isWanted() then
		ply.WantedUntil = nil
		return
	end

	if inCity(ply) then
		local CT = CurTime()
		local left = math.max(math.ceil((ply.WantedUntil or (CT + MAX_WANTED_TIME)) - CT), 1)

		suspended[DarkRP.CharacterID(ply)] = {left = left, reason = ply:getDarkRPVar("wantedReason")}
		DarkRP.log("police", ply, nil, "ушёл в розыске", nil, niceTime(left))
	end

	clearWanted(ply)
end

hook.Add("PlayerDisconnected", "DarkRP.Wanted", leave)
hook.Add("MCR.CharacterReset", "DarkRP.Wanted", leave)

hook.Add("MCR.CharacterSelected", "DarkRP.Wanted", function(ply)
	local key = DarkRP.CharacterID(ply)
	local saved = suspended[key]
	if not saved then return end

	suspended[key] = nil

	local reason = isstring(saved.reason) and saved.reason ~= "" and saved.reason or DEFAULT_REASON

	setWanted(ply, reason, math.ceil(CurTime() + saved.left))

	DarkRP.log("police", ply, nil, "вернулся в розыске", nil, niceTime(saved.left))
end)
