--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Штрафы - сервер: вкладка "Штрафы" компьютера участка (клиент - cl.lua
	рядом) и банкомат (entities/spawned_atm)

	Slawer.Mayor.Tickets[персонаж] = {{name = статья, fee = сумма,
	cp = кто выписал, time = когда (os.time)}, ...}; персонаж -
	DarkRP.CharacterID. Штраф висит на персонаже, пока его не оплатят:
	хранится в базе (darkrp_tickets: charid, data - JSON списка) и
	переживает выход с сервера и рестарт. Сколько штрафов у персонажа -
	не ограничено.

	Сообщения Slawer.Mayor (shared/networking.lua):
	SendTicket {passid, ticket, fee} - полицейский у компьютера выписывает
	  штраф по статье ticket из DarkRP.Police.TicketTypes игроку с
	  паспортом passid (игрок на сервере, не сам полицейский). fee - от
	  четверти до полной суммы статьи, 0 и мусор - полная. Не чаще раза в
	  TICKET_DELAY с. Ответа нет: клиент сам рисует поиск и "Запрос
	  обработан";
	GetTickets {passid} - полицейский у компьютера: штрафы по паспорту;
	  {self = true} - игрок у банкомата: свои штрафы;
	PayTicket {ticket} - игрок у банкомата оплачивает штраф номер ticket
	  своего списка, деньги - в казну района (Slawer.Mayor:AddFunds).
	Ответ на GetTickets и PayTicket - GetTickets {name, sname, passid,
	tickets}; полицейскому ещё {searching, seardelay} - полоса поиска
	(без данных, если паспорт не найден). В tickets - первые штрафы списка,
	сколько влезает в одно сообщение (MAX_SEND байт JSON); оплаченный
	уходит из списка, и становятся видны следующие.
	Полицейский у компьютера - Slawer.Mayor:PoliceAtComputer
	(server/sv_computers.lua).

	Slawer.Mayor.GetTickets(ply) - сколько штрафов у игрока (больше 4 -
	карта заблокирована: заказ с доставкой, shared/makethings.lua)
---------------------------------------------------------------------------]]

local TICKET_DELAY = 5				-- с. между штрафами одного полицейского (клиент столько рисует поиск)
local SEARCH_DELAY = 5				-- полоса поиска у клиента, с.
local ATM_RANGE = 150 * 150
local MAX_ID = 32
local MAX_TEXT = 128
local MAX_SEND = 60000				-- байт JSON штрафов в ответе (сообщение net - до 64 КБ)

-- Tickets заводит и warrants/sh.lua (Slawer.Mayor.Tickets or {})
Slawer.Mayor.Tickets = Slawer.Mayor.Tickets or {}
Slawer.Mayor.TicketsDirty = Slawer.Mayor.TicketsDirty or {}

local function dbError(err, query)
	MsgC(Color(255, 90, 0), "[Slawer.Mayor] SQL: " .. tostring(err) .. "\n    " .. tostring(query) .. "\n")
end

local function finite(v)
	return isnumber(v) and v == v and v ~= math.huge and v ~= -math.huge
end

-- персонаж игрока - ключ штрафов; персонаж не выбран - nil
local function characterOf(ply)
	if not IsValid(ply) or ply:getDarkRPVar("character") == nil then return nil end

	return string.sub(tostring(DarkRP.CharacterID(ply)), 1, MAX_ID)
end

-- список из базы: только штрафы с суммой
local function cleanList(list)
	local out = {}

	for _, t in ipairs(istable(list) and list or {}) do
		local fee = istable(t) and tonumber(t.fee)
		local time = istable(t) and tonumber(t.time)

		if finite(fee) and fee > 0 then
			out[#out + 1] = {
				name = string.sub(tostring(t.name or ""), 1, MAX_TEXT),
				fee = math.Round(fee),
				cp = string.sub(tostring(t.cp or ""), 1, MAX_TEXT),
				time = finite(time) and math.floor(time) or 0,
			}
		end
	end

	return out
end

local function save(id)
	-- база ещё не загружена: запишется после загрузки
	if not Slawer.Mayor.TicketsLoaded then
		Slawer.Mayor.TicketsDirty[id] = true
		return
	end

	local list = Slawer.Mayor.Tickets[id]

	if not list or #list == 0 then
		Slawer.Mayor.Tickets[id] = nil
		MySQLite.query("DELETE FROM darkrp_tickets WHERE charid = " .. MySQLite.SQLStr(id), nil, dbError)
		return
	end

	MySQLite.query(string.format("REPLACE INTO darkrp_tickets(charid, data) VALUES(%s, %s)",
		MySQLite.SQLStr(id), MySQLite.SQLStr(util.TableToJSON(list))
	), nil, dbError)
end

-- data - MEDIUMTEXT: штрафов сколько угодно, а TEXT в MySQL - до 64 КБ.
-- Таблицу из 11.2 (data TEXT) переделывает ALTER; SQLite размер не ограничивает
hook.Add("DatabaseInitialized", "Slawer.Mayor.Tickets", function()
	if Slawer.Mayor.TicketsLoaded then return end

	local function load()
		MySQLite.query("SELECT charid, data FROM darkrp_tickets", function(rows)
			if Slawer.Mayor.TicketsLoaded then return end

			local tickets = Slawer.Mayor.Tickets

			for _, row in ipairs(istable(rows) and rows or {}) do
				local id = string.sub(tostring(row.charid or ""), 1, MAX_ID)
				local list = cleanList(util.JSONToTable(tostring(row.data or "")))

				-- выписанные до загрузки - после записанных в базе
				for _, t in ipairs(tickets[id] or {}) do
					list[#list + 1] = t
				end

				if id ~= "" and #list > 0 then tickets[id] = list end
			end

			Slawer.Mayor.TicketsLoaded = true

			for id in pairs(Slawer.Mayor.TicketsDirty) do
				save(id)
			end

			Slawer.Mayor.TicketsDirty = {}
		end, dbError)
	end

	MySQLite.query([[CREATE TABLE IF NOT EXISTS darkrp_tickets(
		charid VARCHAR(32) NOT NULL PRIMARY KEY,
		data MEDIUMTEXT NOT NULL
	)]], function()
		if not MySQLite.isMySQL() then
			load()
			return
		end

		MySQLite.query("ALTER TABLE darkrp_tickets MODIFY data MEDIUMTEXT NOT NULL", load, function(err, query)
			dbError(err, query)
			load()

			return true
		end)
	end, dbError)
end)

function Slawer.Mayor.GetTickets(ply)
	local id = characterOf(ply)
	local list = id and Slawer.Mayor.Tickets[id]

	return list and #list or 0
end

-- данные паспорта и штрафы для клиента (имя - как в деле задержанного, police/sv_arrest.lua)
local function identity(target, data)
	local parts = string.Explode(" ", target:FullName())

	data.name = parts[1]
	data.sname = table.concat(parts, " ", 2)
	data.passid = tostring(DarkRP.PassId(target))
	data.tickets = {}

	-- номера те же, что в списке на сервере (по ним PayTicket)
	local size = 0

	for k, t in ipairs(Slawer.Mayor.Tickets[characterOf(target) or ""] or {}) do
		local entry = {name = t.name, fee = t.fee, cp = t.cp}

		size = size + #util.TableToJSON(entry) + 1
		if size > MAX_SEND then break end

		data.tickets[k] = entry
	end

	return data
end

-- игрок на сервере с выбранным персонажем по номеру паспорта
local function findCitizen(passid)
	if not isstring(passid) and not isnumber(passid) then return nil end

	local target = DarkRP.findBYPassID(string.Trim(string.sub(tostring(passid), 1, MAX_ID)))
	if IsValid(target) and target:getDarkRPVar("character") ~= nil then return target end
end

local function canUse(ply)
	return DarkRP and DarkRP.Police and DarkRP.Police.TicketTypes ~= nil and Slawer.Mayor:PoliceAtComputer(ply)
end

local function nearATM(ply)
	if not IsValid(ply) or not ply:IsFreeman() or ply:getDarkRPVar("character") == nil then return false end

	local pos = ply:GetPos()

	for _, atm in ipairs(ents.FindByClass("spawned_atm")) do
		if atm:GetPos():DistToSqr(pos) <= ATM_RANGE then return true end
	end

	return false
end

Slawer.Mayor:NetReceive("SendTicket", function(ply, data)
	if not istable(data) or not canUse(ply) then return end
	if ply.SlawerTicketNext and ply.SlawerTicketNext > CurTime() then return end

	local article = DarkRP.Police.TicketTypes[math.floor(tonumber(data.ticket) or 0)]
	if not istable(article) then return end

	local full = math.Round(tonumber(article[2]) or 0)
	if full <= 0 then return end

	local target = findCitizen(data.passid)
	if not target or target == ply then return end

	local id = characterOf(target)
	local list = Slawer.Mayor.Tickets[id] or {}

	local fee = tonumber(data.fee)
	fee = (finite(fee) and fee > 0) and math.Round(math.Clamp(fee, full / 4, full)) or full

	list[#list + 1] = {
		name = string.sub(tostring(article[1]), 1, MAX_TEXT),
		fee = fee,
		cp = string.sub(ply:FullName(), 1, MAX_TEXT),
		time = os.time(),
	}

	Slawer.Mayor.Tickets[id] = list
	ply.SlawerTicketNext = CurTime() + TICKET_DELAY

	save(id)

	DarkRP.log("police", ply, target, "выписал штраф $" .. fee, nil, article[1])
end)

Slawer.Mayor:NetReceive("GetTickets", function(ply, data)
	if not istable(data) then return end

	-- банкомат: свои штрафы
	if data.self then
		if nearATM(ply) then Slawer.Mayor:NetStart("GetTickets", identity(ply, {}), ply) end
		return
	end

	if not canUse(ply) then return end

	local reply = {searching = CurTime(), seardelay = SEARCH_DELAY}
	local target = findCitizen(data.passid)

	if target then identity(target, reply) end

	Slawer.Mayor:NetStart("GetTickets", reply, ply)
end)

Slawer.Mayor:NetReceive("PayTicket", function(ply, data)
	local id = characterOf(ply)
	if not istable(data) or not id then return end

	local list = Slawer.Mayor.Tickets[id]
	local k = math.floor(tonumber(data.ticket) or 0)
	local ticket = list and list[k]

	if ticket and nearATM(ply) and ply:canAfford(ticket.fee) then
		ply:addMoney(-ticket.fee)
		Slawer.Mayor:AddFunds(ticket.fee)

		table.remove(list, k)
		save(id)

		DarkRP.log("money", ply, nil, "оплатил штраф: " .. ticket.name, nil, ticket.fee)
	end

	-- меню банкомата прозрачно до ответа
	Slawer.Mayor:NetStart("GetTickets", identity(ply, {}), ply)
end)
