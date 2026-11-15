--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Арест - сервер (общая часть в sh_arrest.lua)

	Переменная Arrested - момент освобождения по CurTime(): по ней HUD
	показывает время задержанному и полиции, награда MQS "Arrest Time"
	уменьшает срок, меняя её напрямую.

	Как сажают (памятка PoliceTip, slawer_mayor/languages/ru.lua):
	1. Протокол задержания: меню F2 -> "Задержать игрока" у стойки
	   дежурного (JailNPC) - client/popups.lua, Police.Arrest UInt(1, 2) +
	   таблица {reason, passid}. Задержанный остаётся на месте в наручниках,
	   в камеру его ведут сами полицейские. На допрос и оформление дела -
	   30 минут (Arrested = конец задержания).
	2. Компьютер участка, вкладка "Задержанные" (slawer_mayor,
	   modules/policemen/sv_jail.lua): личность - по ID паспорта или поиском
	   в базе N.L.R. (30 секунд), обвинения - статьи DarkRP.Police.TicketTypes.
	   Статьи об убийстве (пометка "deathlog") - только с прикреплённым
	   делом судмедэкспертизы ("Прикрепить дело", health/core/sv_forensic.lua).
	3. "Передать дело в суд" - только когда задержанный в камере: срок -
	   сумма статей обвинения (не больше 2 ч.), наручники снимаются.
	   Не передали за 30 минут - задержанного отпускают у выхода.
	Сразу в камеру, без протокола, сажают DarkRP.AutoArrest (стрельба
	в участке - sh_init.lua, NPC MCS "JailPlayer" и "Auto Arrest") и sAdmin
	(arrest <игрок> <время>, unarrest <игрок>).
	Терапевт в больнице (MCS civilian_med) по просьбе полицейского лечит
	задержанного: Police.Arrest UInt(0, 2).

	Протоколы - DarkRP.JailRecords[UserID], поля как у Slawer.JailTable
	клиента компьютера. Арестованный после смерти появляется в камере
	(GM:PlayerSpawn), на свободу выходит у Config.Positions.UnJail.
	Вышедший из игры досиживает срок или задержание, когда снова выберет
	этого персонажа (хранится в памяти до перезапуска сервера).
---------------------------------------------------------------------------]]

util.AddNetworkString("Police.Arrest")

local plyMeta = FindMetaTable("Player")

local MAX_TIME = 7 * 24 * 3600
local DETENTION_TIME = 30 * 60 -- от протокола до передачи дела в суд
local NLR_DELAY = 30 -- поиск личности в базе N.L.R., с. (клиент рисует полосу по seardelay)
local MIN_SENTENCE = 60
local MAX_SENTENCE = 120 * 60 -- сумма статей - не больше самой тяжёлой (Терроризм)
local MAX_ACCUSATIONS = 10
local MAX_KILLS = 10 -- дел судмедэкспертизы в протоколе
local CELL_RANGE = 600 -- "в камере": не дальше от Positions.Jail
local JAIL_SPREAD = 100 -- радиус поиска свободного места в камере: дальше - уже за стеной
local NET_DELAY = 1
local CHECK_INTERVAL = 1
local AUTO_COOLDOWN = 2 -- каждая пуля очереди вызывает AutoArrest/CubKick
local AUTO_REASON = "Нарушение закона"

local BOOK_RANGE = 600 -- до стойки дежурного (клиент показывает пункт меню в 500)
local HOSPITAL_RANGE = 300
local HEAL_COOLDOWN = 300

-- поля протокола, которые получает клиент компьютера (остальные - только для сервера)
local CLIENT_FIELDS = {"userid", "name", "sname", "gen", "date", "passid", "type", "aresster", "rank", "reason", "accusations", "closed", "searching", "seardelay", "kills"}

DarkRP.JailRecords = DarkRP.JailRecords or {}

-- сроки вышедших: DarkRP.CharacterID -> {left, reason, record}
local suspended = {}

-- до ближайшей минуты: CurTime() дробный, срок 5 мин. - это 300.7 с до Arrested
local function niceTime(sec)
	sec = math.max(math.floor((tonumber(sec) or 0) + 0.5), 0)

	local h = math.floor(sec / 3600)
	local m = math.floor((sec - h * 3600) / 60 + 0.5)

	if m >= 60 then h, m = h + 1, m - 60 end
	if h > 0 then return m > 0 and (h .. " ч. " .. m .. " мин.") or (h .. " ч.") end

	return math.max(m, 1) .. " мин."
end

local function validPlayer(ply, except)
	return IsValid(ply) and ply:IsPlayer() and ply ~= except
end

-- позиция NPC MCS на текущей карте
local function npcPos(id, fallback)
	local spawn = MCS and MCS.Spawns and MCS.Spawns[id]
	local pos = spawn and spawn.pos and spawn.pos[game.GetMap()]

	return pos and pos[1] or fallback
end

-- выход из машины ставит игрока у двери уже после SetPos: повтор в следующем тике
local function teleport(ply, pos, arrested)
	local inVehicle = ply:InVehicle()
	if inVehicle then ply:ExitVehicle() end

	ply:SetPos(pos)

	if not inVehicle then return end

	timer.Simple(0, function()
		if IsValid(ply) and ply:Alive() and (ply:getDarkRPVar("Arrested") ~= nil) == arrested then
			ply:SetPos(pos)
		end
	end)
end

-- снять наручники; предмет "cuffs" получает первый живой игрок из списка
-- (кто надел, кто снимает, кто оформил протокол)
local function removeCuffs(ply, ...)
	if not ply.HandCuffed then return end

	local owners = {...}

	ply:CuffHands()

	for i = 1, select("#", ...) do
		if validPlayer(owners[i], ply) then
			owners[i]:AddItemByClass(INV_JUNK, "cuffs")
			return
		end
	end
end

-- незакрытое дело: протокол есть, в суд ещё не передано (задержание)
local function openRecord(ply)
	local rec = DarkRP.JailRecords[ply:UserID()]
	if rec and not rec.closed then return rec end
end

-- данные паспорта в протокол (как их показывает клиент компьютера)
local function fillIdentity(target, rec)
	local parts = string.Explode(" ", target:FullName())

	rec.name = parts[1] ~= "" and parts[1] or rec.name
	rec.sname = table.concat(parts, " ", 2)
	rec.date = tostring(target:getDarkRPVar("age") or "")
	rec.passid = tostring(DarkRP.PassId(target))
	rec.type = string.sub(tostring(target:AccountID()), 3, 4)
end

local function stopSearch(rec)
	rec.searching, rec.seardelay, rec.searcher = nil, nil, nil
end

-- обвинения одной строкой (причина ареста): три первые статьи и сколько ещё
local function accusationText(list)
	local names = {}

	for i = 1, math.min(#list, 3) do
		local article = DarkRP.Police.TicketTypes[list[i]]
		names[#names + 1] = article and article[1] or tostring(list[i])
	end

	local text = table.concat(names, ", ")
	if #list > 3 then text = text .. " и ещё " .. (#list - 3) end

	return text
end

--[[---------------------------------------------------------------------------
	DarkRP.retrieveJailPos(ply) - свободное место в камере
---------------------------------------------------------------------------]]
function DarkRP.retrieveJailPos(ply)
	local pos = GAMEMODE.Config.Positions and GAMEMODE.Config.Positions.Jail
	if not pos then return ply:GetPos() end

	return DarkRP.findEmptyPos(pos, {ply}, JAIL_SPREAD, 25, Vector(0, 0, 70))
end

--[[---------------------------------------------------------------------------
	Посадить сразу в камеру / освободить
---------------------------------------------------------------------------]]
local function jail(ply, time, arrester, reason, resumed)
	if ply:getDarkRPVar("character") == nil then return false end

	time = tonumber(time)
	if not time or time <= 0 then time = GAMEMODE.Config.jailtimer or 300 end
	time = math.Clamp(math.ceil(time), 1, MAX_TIME)

	if not validPlayer(arrester, ply) then arrester = nil end
	if not isstring(reason) or reason == "" then reason = nil end

	local CT = CurTime()
	local current = ply:getDarkRPVar("Arrested")

	-- срок вместо задержания: протокол без суда больше не нужен
	if not resumed and openRecord(ply) then
		DarkRP.JailRecords[ply:UserID()] = nil
		current = nil
	end

	local releaseAt = math.max(math.ceil(CT + time), current or 0)

	ply:ReleaseDrag()
	removeCuffs(ply, ply.restainBy, arrester)

	ply:SetDarkRPVar("Arrested", releaseAt)
	ply.ArrestReason = reason or (current and ply.ArrestReason) or nil

	if ply:Alive() then
		teleport(ply, DarkRP.retrieveJailPos(ply), true)
		DarkRP.ForceKeys(ply)
	end

	local left = niceTime(releaseAt - CT)
	local why = ply.ArrestReason and (": " .. ply.ArrestReason) or ""
	local detail = left .. (ply.ArrestReason and (", " .. ply.ArrestReason) or "")

	if resumed then
		DarkRP.log("police", ply, nil, "вернулся досиживать срок", nil, detail)
		return true
	end

	if arrester then
		DarkRP.log("police", arrester, ply, current and "продлил арест" or "арестовал", nil, detail)
	else
		DarkRP.log("police", ply, nil, current and "арест продлён" or "арестован", nil, detail)
	end

	hook.Run("playerArrested", ply, time, arrester, ply.ArrestReason)

	return true
end

-- why: "detention" - не передали дело в суд за 30 минут, "expired" - срок вышел
local function release(ply, unarrester, teleportOverride, why)
	if not ply:getDarkRPVar("Arrested") then return false end
	if not validPlayer(unarrester, ply) then unarrester = nil end

	local id = ply:UserID()
	local rec = DarkRP.JailRecords[id]

	ply:SetDarkRPVar("Arrested", nil)
	ply.ArrestReason = nil
	DarkRP.JailRecords[id] = nil

	-- задержанного отпускают из наручников: их возвращают надевшему
	ply:ReleaseDrag()
	removeCuffs(ply, ply.restainBy, unarrester, rec and rec.officerPly)

	local pos = GAMEMODE.Config.Positions and GAMEMODE.Config.Positions.UnJail

	if not teleportOverride and pos and ply:Alive() then
		teleport(ply, DarkRP.findEmptyPos(pos, {ply}, 300, 30, Vector(0, 0, 70)), false)
	end

	if unarrester then
		DarkRP.log("police", unarrester, ply, "освободил из-под ареста")
	elseif why == "detention" then
		DarkRP.log("police", ply, nil, "отпущен: дело не передано в суд")
	elseif why == "expired" then
		DarkRP.log("police", ply, nil, "отсидел срок")
	else
		DarkRP.log("police", ply, nil, "освобождён из-под ареста")
	end

	hook.Run("playerUnArrested", ply, unarrester, teleportOverride)

	return true
end

--[[---------------------------------------------------------------------------
	ply:arrest(time, arrester, reason) - сразу в камеру на time секунд (нет
	или 0 - Config.jailtimer). Уже арестованного - обратно в камеру, срок -
	больший из оставшегося и нового; незакрытое задержание срок заменяет.
	Персонаж не выбран - false.
	Хук playerArrested(ply, time, arrester, reason)
---------------------------------------------------------------------------]]
function plyMeta:arrest(time, arrester, reason)
	return jail(self, time, arrester, reason)
end

--[[---------------------------------------------------------------------------
	ply:unArrest(unarrester, teleportOverride) - освободить (и задержанного,
	наручники снимаются). Живой выходит у Config.Positions.UnJail,
	teleportOverride = true - остаётся на месте.
	Хук playerUnArrested(ply, unarrester, teleportOverride)
---------------------------------------------------------------------------]]
function plyMeta:unArrest(unarrester, teleportOverride)
	return release(self, unarrester, teleportOverride)
end

--[[---------------------------------------------------------------------------
	DarkRP.AutoArrest(ply, time, reason) - арест без полицейского
	(по умолчанию Config.jailtimer, "Нарушение закона")
---------------------------------------------------------------------------]]
function DarkRP.AutoArrest(ply, time, reason)
	if not validPlayer(ply) or not ply:Alive() then return false end

	local CT = CurTime()
	if ply.NextAutoArrest and ply.NextAutoArrest > CT then return false end

	ply.NextAutoArrest = CT + AUTO_COOLDOWN

	return ply:arrest(time, nil, isstring(reason) and reason ~= "" and reason or AUTO_REASON)
end

--[[---------------------------------------------------------------------------
	DarkRP.CubKick(ply) - стрельба в клубе (территория с club_zone): охрана
	заставляет убрать оружие. Территорий клуба в конфиге сейчас нет
---------------------------------------------------------------------------]]
function DarkRP.CubKick(ply)
	if not validPlayer(ply) or not ply:Alive() then return end

	DarkRP.ForceKeys(ply)

	local CT = CurTime()
	if ply.NextClubKick and ply.NextClubKick > CT then return end

	ply.NextClubKick = CT + AUTO_COOLDOWN

	DarkRP.log("police", ply, nil, "стрелял в клубе")
end

--[[---------------------------------------------------------------------------
	Police.Arrest: протокол задержания и больница.
	Задержанный - тот, кого полицейский ведёт (ply.Dragging, sv_cuffs.lua)
---------------------------------------------------------------------------]]
local function escortedSuspect(ply)
	if not ply:isCP() then
		return nil
	end

	if not ply:IsFreeman() or ply:InVehicle() then return nil end

	local target = ply.Dragging

	if not validPlayer(target, ply) or target.DraggedBy ~= ply or not target.HandCuffed or not target:Alive() then
		return nil
	end

	return target
end

-- протокол как у Slawer.JailTable. Данные паспорта - только при верном ID паспорта
local function makeRecord(target, officer, reason, passid)
	local rankName = ""

	if MRS and MRS.GetActiveRankData then
		local _, rank = MRS.GetActiveRankData(officer)
		if istable(rank) and isstring(rank.name) then rankName = rank.name end
	end

	local record = {
		userid = target:UserID(),
		name = target:Name(),
		sname = "",
		gen = target:getDarkRPVar("gender") == "female" and "ЖЕН." or "МУЖ.",
		date = "",
		passid = "",
		type = "",
		aresster = officer:FullName(),
		rank = rankName,
		reason = reason,
		-- только для сервера
		steamid = target:SteamID64(),
		officer = officer:SteamID64(),
		officerPly = officer,
		time = os.time(),
	}

	if passid ~= "" and passid == tostring(DarkRP.PassId(target)) then
		fillIdentity(target, record)
	end

	return record
end

-- задержанный остаётся там, где стоит, в наручниках
local function detain(target, officer, record, reason)
	local deadline = math.ceil(CurTime() + DETENTION_TIME)

	record.deadline = deadline
	DarkRP.JailRecords[target:UserID()] = record

	target:SetDarkRPVar("Arrested", deadline)
	target.ArrestReason = reason

	if target:Alive() then DarkRP.ForceKeys(target) end

	local left = niceTime(DETENTION_TIME)

	DarkRP.log("police", officer, target, "оформил протокол задержания", nil, reason)

	hook.Run("playerArrested", target, DETENTION_TIME, officer, reason)
end

local function bookSuspect(ply, data)
	local target = escortedSuspect(ply)
	if not target then return end

	local desk = GAMEMODE.Config.Positions.JailNPC

	if not DarkRP.InRangeVector(ply:GetPos(), desk, BOOK_RANGE) or not DarkRP.InRangeVector(target:GetPos(), desk, BOOK_RANGE) then
		return
	end

	if target:getDarkRPVar("Arrested") then
		return
	end

	if target:getDarkRPVar("character") == nil then return end

	local reason = tonumber(data.reason)
	local article = reason and DarkRP.Police.TicketTypes[reason]

	if not article then
		return
	end

	local passid = (isstring(data.passid) or isnumber(data.passid)) and string.Trim(string.sub(tostring(data.passid), 1, 32)) or ""
	local record = makeRecord(target, ply, reason, passid)

	detain(target, ply, record, article[1])
end

local function healSuspect(ply)
	local target = escortedSuspect(ply)
	if not target then return end

	if not DarkRP.InRangeVector(ply:GetPos(), npcPos("civilian_med", GAMEMODE.Config.Positions.Hospital), HOSPITAL_RANGE) then return end

	local CT = CurTime()

	if target.NextPoliceHeal and target.NextPoliceHeal > CT then
		return
	end

	target.NextPoliceHeal = CT + HEAL_COOLDOWN

	-- полное лечение (переломы, кровотечение) - модуль health, шаг 8
	if target.FullHeal then
		target:FullHeal()
	else
		target:SetHealth(math.max(target:Health(), target:GetMaxHealth()))
	end

	DarkRP.log("police", ply, target, "отвёл задержанного к врачу")
end

-- больница - 2 бита режима (байт), протокол - режим и таблица. Срок от
-- дежурного (MCS police_cadet, UInt 12 бит) не принимается: арест
-- подтверждают в компьютере участка
net.Receive("Police.Arrest", function(len, ply)
	if DarkRP.NetDelay(ply, NET_DELAY) then return end

	local mode = net.ReadUInt(2)

	if mode == 0 and len <= 8 then
		healSuspect(ply)
	elseif mode == 1 and len > 16 then
		local ok, data = pcall(net.ReadTable)
		if ok and istable(data) then bookSuspect(ply, data) end
	end
end)

--[[---------------------------------------------------------------------------
	Дело в компьютере участка (slawer_mayor, modules/policemen/sv_jail.lua).
	Функции возвращают ok и текст для полицейского
---------------------------------------------------------------------------]]
local function caseOf(target)
	local rec = IsValid(target) and DarkRP.JailRecords[target:UserID()]

	if not rec then return nil, "Дело не найдено" end
	if rec.closed then return nil, "Дело уже передано в суд" end

	return rec
end

-- DarkRP.JailList(openFor) - дела для клиента (Slawer.JailTable) по UserID.
-- Только игроки на сервере: клиент берёт время из Player(userid).
-- openFor - UserID дела, которое компьютер откроет сразу (openuser)
function DarkRP.JailList(openFor)
	local list = {}

	for id, rec in pairs(DarkRP.JailRecords) do
		local ply = Player(id)
		if not IsValid(ply) or not ply:getDarkRPVar("Arrested") then continue end

		local row = {}

		for _, k in ipairs(CLIENT_FIELDS) do
			row[k] = rec[k]
		end

		if id == openFor then row.openuser = true end

		list[id] = row
	end

	return list
end

-- DarkRP.JailIdentify(officer, target, passid) - личность по ID паспорта
function DarkRP.JailIdentify(officer, target, passid)
	local rec, err = caseOf(target)
	if not rec then return false, err end
	if rec.passid ~= "" then return false, "Личность уже установлена" end

	passid = (isstring(passid) or isnumber(passid)) and string.Trim(string.sub(tostring(passid), 1, 32)) or ""

	if passid == "" then return false, "Введите ID паспорта" end
	if passid ~= tostring(DarkRP.PassId(target)) then return false, "ID паспорта не совпадает с задержанным" end

	fillIdentity(target, rec)
	stopSearch(rec)

	DarkRP.log("police", officer, target, "установил личность задержанного", nil, rec.passid)

	return true, "Личность установлена: " .. target:FullName()
end

-- DarkRP.JailSearchNLR(officer, target) - поиск личности в базе N.L.R. (NLR_DELAY)
function DarkRP.JailSearchNLR(officer, target)
	local rec, err = caseOf(target)
	if not rec then return false, err end
	if rec.passid ~= "" then return false, "Личность уже установлена" end
	if rec.searching then return false, "Поиск в базе N.L.R. уже идёт" end

	rec.searching = CurTime()
	rec.seardelay = NLR_DELAY
	rec.searcher = officer

	DarkRP.log("police", officer, target, "запросил поиск личности в базе N.L.R.")

	return true, "Запрос в базу N.L.R. отправлен. Ответ - через " .. (NLR_DELAY < 60 and NLR_DELAY .. " с." or niceTime(NLR_DELAY))
end

-- DarkRP.JailAccuse(officer, target, article) - предъявить обвинение (номер статьи)
function DarkRP.JailAccuse(officer, target, article)
	local rec, err = caseOf(target)
	if not rec then return false, err end
	if rec.passid == "" then return false, "Сначала установите личность задержанного" end

	local idx = tonumber(article)
	local ticket = idx and DarkRP.Police.TicketTypes[idx]
	if not ticket then return false, "Такой статьи нет" end
	if ticket[4] == "deathlog" and not rec.kills then return false, "Сначала прикрепите дело судмедэкспертизы" end

	rec.accusations = rec.accusations or {}

	for _, v in ipairs(rec.accusations) do
		if v == idx then return false, "Это обвинение уже предъявлено" end
	end

	if #rec.accusations >= MAX_ACCUSATIONS then return false, "В деле не больше " .. MAX_ACCUSATIONS .. " обвинений" end

	rec.accusations[#rec.accusations + 1] = idx

	DarkRP.log("police", officer, target, "предъявил обвинение", nil, ticket[1])

	return true, "Обвинение предъявлено: " .. ticket[1]
end

-- DarkRP.JailAttachCase(officer, target, num) - прикрепить дело судмедэкспертизы
-- (rec.kills = {[номер] = true}, клиент показывает "Прикреплено дело об убийстве")
function DarkRP.JailAttachCase(officer, target, num)
	local rec, err = caseOf(target)
	if not rec then return false, err end
	if rec.passid == "" then return false, "Сначала установите личность задержанного" end

	num = tonumber(num)
	if not num or not MES or not MES.GetDeathCase or not MES.GetDeathCase(num) then return false, "Такого дела судмедэкспертизы нет" end
	if rec.kills and rec.kills[num] then return false, "Дело #" .. num .. " уже прикреплено" end
	if rec.kills and table.Count(rec.kills) >= MAX_KILLS then return false, "В протоколе не больше " .. MAX_KILLS .. " дел судмедэкспертизы" end

	rec.kills = rec.kills or {}
	rec.kills[num] = true

	DarkRP.log("police", officer, target, "прикрепил дело судмедэкспертизы", nil, "#" .. num)

	return true, "Дело #" .. num .. " прикреплено"
end

-- DarkRP.JailDetachCase(officer, target, num) - открепить дело
function DarkRP.JailDetachCase(officer, target, num)
	local rec, err = caseOf(target)
	if not rec then return false, err end

	num = tonumber(num)
	if not num or not rec.kills or not rec.kills[num] then return false, "Это дело не прикреплено" end

	rec.kills[num] = nil
	if next(rec.kills) == nil then rec.kills = nil end

	DarkRP.log("police", officer, target, "открепил дело судмедэкспертизы", nil, "#" .. num)

	return true, "Дело #" .. num .. " откреплено"
end

-- DarkRP.JailSendToCourt(officer, target) - передать дело в суд: срок по статьям обвинения
function DarkRP.JailSendToCourt(officer, target)
	local rec, err = caseOf(target)
	if not rec then return false, err end
	if rec.passid == "" then return false, "Сначала установите личность задержанного" end
	if not rec.accusations or #rec.accusations == 0 then return false, "Предъявите обвинения: без них дело в суд не передать" end

	-- дело открепили после обвинения
	for _, idx in ipairs(rec.accusations) do
		local ticket = DarkRP.Police.TicketTypes[idx]

		if ticket and ticket[4] == "deathlog" and not rec.kills then
			return false, "Обвинение «" .. ticket[1] .. "» - без дела судмедэкспертизы. Прикрепите дело"
		end
	end

	local cell = GAMEMODE.Config.Positions and GAMEMODE.Config.Positions.Jail

	if cell and not DarkRP.InRangeVector(target:GetPos(), cell, CELL_RANGE) then
		return false, "Сначала отведите задержанного в камеру"
	end

	local minutes = 0

	for _, idx in ipairs(rec.accusations) do
		local ticket = DarkRP.Police.TicketTypes[idx]
		minutes = minutes + (ticket and tonumber(ticket[3]) or 0)
	end

	local term = math.Clamp(minutes * 60, MIN_SENTENCE, MAX_SENTENCE)
	local charges = accusationText(rec.accusations)

	rec.closed = true
	rec.sentence = term
	stopSearch(rec)

	target:ReleaseDrag()
	removeCuffs(target, target.restainBy, officer, rec.officerPly)

	target:SetDarkRPVar("Arrested", math.ceil(CurTime() + term))
	target.ArrestReason = charges

	if target:Alive() then DarkRP.ForceKeys(target) end

	local left = niceTime(term)

	local value = left .. ", " .. charges

	if rec.kills then
		local nums = table.GetKeys(rec.kills)
		table.sort(nums)
		value = value .. ", дела судмедэкспертизы #" .. table.concat(nums, ", #")
	end

	DarkRP.log("police", officer, target, "передал дело в суд", nil, value)

	return true, "Дело передано в суд: " .. target:FullName() .. ". Срок: " .. left
end

-- ответ базы N.L.R.: хук открывает дело у запросившего (sv_jail.lua)
local function identifiedByNLR(ply, rec)
	local searcher = rec.searcher
	if not validPlayer(searcher, ply) then searcher = nil end

	stopSearch(rec)
	fillIdentity(ply, rec)

	DarkRP.log("police", ply, nil, "личность установлена по базе N.L.R.", nil, rec.passid)

	hook.Run("playerJailIdentified", ply, rec, searcher)
end

--[[---------------------------------------------------------------------------
	Раз в секунду: конец задержания и срока, ответ базы N.L.R.,
	в руках - только разрешённое (DarkRP.AllowedInJail, sh_arrest.lua)
---------------------------------------------------------------------------]]
timer.Create("DarkRP.Arrest", CHECK_INTERVAL, 0, function()
	local CT = CurTime()

	for _, ply in ipairs(player.GetAll()) do
		local releaseAt = ply:getDarkRPVar("Arrested")
		if not releaseAt then continue end

		local rec = openRecord(ply)

		if rec then
			-- задержание не сокращается (награда MQS "Arrest Time" - для срока по суду)
			if releaseAt ~= rec.deadline then
				releaseAt = rec.deadline
				ply:SetDarkRPVar("Arrested", releaseAt)
			end

			if rec.searching and CT >= rec.searching + rec.seardelay then
				identifiedByNLR(ply, rec)
			end
		end

		if releaseAt <= CT then
			release(ply, nil, false, rec and "detention" or "expired")
			continue
		end

		if ply:Alive() and not ply:InVehicle() then
			local wep = ply:GetActiveWeapon()

			if IsValid(wep) and not DarkRP.AllowedInJail(wep) then
				DarkRP.ForceKeys(ply)
			end
		end
	end
end)

--[[---------------------------------------------------------------------------
	Выход из игры и смена персонажа: срок или задержание откладываются до
	следующего выбора этого персонажа (MCR.CharacterSelected).
	Хук playerJailSuspended(ply, record) - дело ушло вместе с игроком
---------------------------------------------------------------------------]]
local function suspend(ply)
	local id = ply:UserID()
	local rec = DarkRP.JailRecords[id]
	local releaseAt = ply:getDarkRPVar("Arrested")

	DarkRP.JailRecords[id] = nil

	if not releaseAt then return end

	local open = rec and not rec.closed
	local left = math.max(math.ceil((open and rec.deadline or releaseAt) - CurTime()), 1)

	-- поиск в базе N.L.R. не ждёт ушедшего: запросят снова
	if open then stopSearch(rec) end

	if ply:getDarkRPVar("character") ~= nil then
		suspended[DarkRP.CharacterID(ply)] = {left = left, reason = ply.ArrestReason, record = rec}
		DarkRP.log("police", ply, nil, open and "ушёл во время задержания" or "ушёл, не досидев срок", nil, niceTime(left))
	end

	ply:SetDarkRPVar("Arrested", nil)
	ply.ArrestReason = nil

	if rec then hook.Run("playerJailSuspended", ply, rec) end
end

hook.Add("PlayerDisconnected", "DarkRP.Arrest", suspend)
hook.Add("MCR.CharacterReset", "DarkRP.Arrest", suspend)

-- вернувшийся задержанный ждёт решения по делу в камере
local function resumeDetention(ply, rec, left, reason)
	rec.deadline = math.ceil(CurTime() + left)

	ply:SetDarkRPVar("Arrested", rec.deadline)
	ply.ArrestReason = reason

	if ply:Alive() then
		teleport(ply, DarkRP.retrieveJailPos(ply), true)
		DarkRP.ForceKeys(ply)
	end

	DarkRP.log("police", ply, nil, "вернулся под задержание", nil, niceTime(left))
end

hook.Add("MCR.CharacterSelected", "DarkRP.Arrest", function(ply)
	local key = DarkRP.CharacterID(ply)
	local saved = suspended[key]
	if not saved then return end

	suspended[key] = nil

	local rec = saved.record

	if rec then
		rec.userid = ply:UserID()
		DarkRP.JailRecords[rec.userid] = rec
	end

	if rec and not rec.closed then
		resumeDetention(ply, rec, saved.left, saved.reason)
	else
		jail(ply, saved.left, nil, saved.reason, true)
	end
end)

-- в камере нельзя строить из пропов спавн-меню
hook.Add("PlayerSpawnObject", "DarkRP.Arrested", function(ply)
	if ply:getDarkRPVar("Arrested") then return false end
end)
