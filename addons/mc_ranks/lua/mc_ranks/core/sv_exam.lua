--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	MRS - экзамены, серверная часть (шаг 15.2)

	Вопросы и описания - в sh_exam.lua (общий файл, есть у клиентов). Ключа
	ответов у автора не было: он составлен по тексту вопросов и механикам
	сборки и лежит только здесь (KEY). Клиент видит правильные ответы лишь
	в отчёте и только по вопросам из этого отчёта.

	Кто запускает:
	  - NPC комиссар (mc_simple_npcs/sh_addonsup.lua) -
	    MRS.Exam.StartTest(ply, exam): PDcop, GUN1, PDkit, PDcar;
	  - экзаменатор через меню на игроке (client/vgui.lua), net "MRS.Exam":
	    тип 1 - экзамены NYPD (ранг 6+), тип 4 - FDNY (ранг 7+). Оба в одной
	    службе MRS, экзаменатор старше по званию и стоит рядом.

	Ход: все вопросы по одному в случайном порядке (тип 1 клиенту - экзамен
	и номер вопроса), ответ - тип 2 от клиента (номер варианта как в
	sh_exam.lua). Ошибок больше Info.fail или вышло Info.time - не сдан,
	пересдача не раньше Info.cooldown после провала. Смена профессии или
	персонажа и выход с сервера во время экзамена - тоже провал.
	/exam - снова открыть текущий вопрос, если окно закрыли.

	Отчёты - таблица mrs_exams, 30 последних на персонажа; окно отчётов -
	тип 2 клиенту ({отчёты, ответы}). Видят: экзаменатор - сразу после
	экзамена; сдающий - если у экзамена show_res; по кнопке "Открыть данные
	экзамена" (тип 3) - админ, экзаменаторы и руководство службы (экзамены
	своей службы) и сам игрок (только экзамены с show_res).
---------------------------------------------------------------------------]]

local EXAM_DIST = 250 -- экзаменатор не дальше, юнитов
local START_DELAY = 2 -- запуск экзамена - не чаще, секунд
local RECORDS_DELAY = 2 -- запрос отчётов - не чаще
local MAX_RECORDS = 30 -- отчётов на персонажа в базе
local SEND_RECORDS = 20 -- отчётов в одном окне
local MAX_NET_DATA = 60000

--[[ Правила экзаменов
	group - служба MRS, в которой сейчас игрок; rank - звание, в котором
	сдают (ровно); min - ранг не ниже; npc - сдают у NPC, без экзаменатора;
	promote - звание после сдачи (только вверх); flag - метка персонажа
	после сдачи (пока она есть, экзамен снова не сдают); gun - уровень
	оружейной exam_gun (police/sv_loadout.lua, не понижается): 1 -
	снаряжение, спецсредства и магазины, 2 - пистолет и тяжёлое оружие. ]]
local RULES = {
	PDcop = {group = "NYPD", npc = true, rank = 1, promote = 2},
	GUN1 = {group = "NYPD", npc = true, min = 2, flag = "exam_gun1", gun = 1},
	PDkit = {group = "NYPD", npc = true, min = 4, flag = "exam_pdkit"},
	PDcar = {group = "NYPD", npc = true, min = 4, flag = "exam_pdcar"},
	PDcop2 = {group = "NYPD", rank = 1, promote = 2},
	PDofficer = {group = "NYPD", rank = 2, promote = 3},
	PDprobation = {group = "NYPD"}, -- испытательный срок офицера ППО: только отчёт, решает экзаменатор
	PDtaser = {group = "NYPD", min = 2, flag = "exam_taser", gun = 1},
	GUN2 = {group = "NYPD", min = 2, flag = "exam_gun2", gun = 2},
	FD = {group = "FDNY", rank = 1, promote = 2},
	FDmed = {group = "FDNY", rank = 2, promote = 3},
}

-- что открылось - в уведомлении о сдаче (о повышении сообщает SetPlayerRank)
local GAINS = {
	GUN1 = "снаряжение, спецсредства и магазины в оружейной",
	PDtaser = "снаряжение, спецсредства и магазины в оружейной",
	GUN2 = "пистолет и тяжёлое оружие в оружейной",
	PDkit = "полицейская аптечка в оружейной",
	PDcar = "служебные машины участка",
	FDmed = "адреналин, физраствор и морфин в меню медика",
}

-- экзаменаторы, как в меню на игроке (client/vgui.lua): тип net -> служба,
-- ранг экзаменатора не ниже rank, какие экзамены
local EXAMINERS = {
	[1] = {group = "NYPD", rank = 6, exams = {PDcop2 = true, PDofficer = true, PDtaser = true, GUN2 = true, PDprobation = true}},
	[4] = {group = "FDNY", rank = 7, exams = {FD = true, FDmed = true}},
}

-- Правильные ответы: номер варианта из sh_exam.lua для вопросов по порядку.
-- Поменяли вопросы или порядок вариантов - поправьте и здесь: ключ другой
-- длины или с несуществующим вариантом отключает экзамен (см. examData).
local KEY = {
	PDcop = {3, 3, 3, 2, 3, 1, 2, 2, 2, 1, 1, 1, 1, 3, 2, 3, 1, 1, 2, 1, 3, 2, 3, 1, 1, 2},
	GUN1 = {3, 1, 4, 2, 2, 4, 3},
	PDkit = {2, 3, 3, 4, 2, 1, 2, 2, 4, 4, 3, 1, 3, 2},
	PDcar = {3, 3, 4, 2, 4, 2, 1, 3, 2, 2, 4, 3, 4, 3, 4, 3, 3, 1, 2},
	PDcop2 = {2, 2, 3, 4, 3, 3, 1, 1, 1, 1, 3, 1, 2, 3, 2, 3, 2, 3, 2, 2, 3, 2, 3, 1, 1, 2, 2, 2, 2, 2, 1, 1},
	PDprobation = {3, 1, 4, 2, 1, 2, 3, 3, 2, 1},
	PDtaser = {3, 1, 3, 2, 3, 1, 4, 3, 4, 3, 4, 2},
	GUN2 = {4, 1, 2, 3, 2, 3, 4, 1, 2, 2, 2, 2, 3, 4, 3, 2, 2, 1, 2, 3, 3, 3, 3, 3, 4, 3, 4, 1, 4, 1, 4, 4},
	FD = {2, 3, 3, 2, 1, 2, 1, 2, 4, 3, 1, 3, 2, 2, 1, 2, 2, 2, 4, 3, 4, 2, 2, 1, 1, 1, 2},
	FDmed = {3, 2, 4, 2, 3, 2, 3, 2, 3, 3, 4, 2, 1, 2, 3, 1, 3, 2, 2, 2, 4, 4, 3, 2, 3, 2, 1, 2, 1, 1, 1, 2, 1},
}
KEY.PDofficer = KEY.PDcop2 -- в sh_exam.lua PDofficer - копия PDcop2

--[[---------------------------------------------------------------------------
	Помощники
---------------------------------------------------------------------------]]

local function isAdmin(ply)
	return not IsValid(ply) or MRS.IsAdministrator(ply) and true or false
end

local function say(ply, text, kind)
	if IsValid(ply) then
		MRS.SmallNotify(text, ply, kind or 0)
	else
		print("[MRS] " .. text)
	end
end

-- не чаще раза в delay секунд (свои ключи, отдельно от sv_ranks.lua)
local function spam(ply, key, delay)
	ply.MRSExamCD = ply.MRSExamCD or {}

	local t = CurTime()
	if (ply.MRSExamCD[key] or 0) > t then return true end

	ply.MRSExamCD[key] = t + delay
	return false
end

local function sqlStr(s)
	return MySQLite.SQLStr(tostring(s))
end

local function query(sql, callback, onError)
	MySQLite.query(sql, callback, function(err)
		print("[MRS] Ошибка базы (экзамены): " .. tostring(err))
		if onError then onError() end
		return true
	end)
end

local function minutes(sec)
	return math.max(1, math.ceil(sec / 60)) .. " мин."
end

local function rankName(grp, rank)
	local g = MRS.Ranks[grp]
	local r = g and g.ranks and g.ranks[rank]
	return r and r.name or tostring(rank)
end

-- сколько ошибок можно сделать и всё равно сдать
local function allowed(info)
	return math.max(0, math.floor(tonumber(info.fail) or 0))
end

local checked = {}

-- вопросы, описание и ключ экзамена; nil - экзамена нет или ключ не сходится
-- с вопросами sh_exam.lua (тогда экзамен отключён, причина - в консоли)
local function examData(exam)
	local test = MRS.Exam.Test and MRS.Exam.Test[exam]
	local info = MRS.Exam.Info and MRS.Exam.Info[exam]
	local key = KEY[exam]
	if not RULES[exam] or not istable(test) or not istable(info) or not key then return end

	if checked[exam] == nil then
		local ok = #test > 0 and #key == #test

		for i = 1, #test do
			local q = test[i]
			if not ok or not istable(q) or not istable(q.a) or q.a[key[i]] == nil then
				ok = false
				break
			end
		end

		checked[exam] = ok
		if not ok then print("[MRS] Экзамен " .. exam .. ": ключ не совпадает с вопросами sh_exam.lua, экзамен отключён") end
	end

	if checked[exam] then return test, info, key end
end

local function examinerRule(exam)
	for _, rule in pairs(EXAMINERS) do
		if rule.exams[exam] then return rule end
	end
end

-- почему игрок не может сдать экзамен сейчас; nil - может
local function denied(ply, exam)
	local rule = RULES[exam]
	if not rule or not examData(exam) then return "Такого экзамена нет" end
	if not ply.MRSLoaded or not ply.MRSuid then return "Данные персонажа ещё не загружены" end
	if ply.MRSExam then return "Экзамен уже идёт" end
	if MRS.GetNWdata(ply, "Group") ~= rule.group then return "Экзамен только для службы " .. rule.group end

	local rank = MRS.GetPlyRank(ply, rule.group)
	if rule.rank and rank > rule.rank then return "Звание уже выше - экзамен не нужен" end
	if rule.rank and rank < rule.rank then return "Экзамен сдают в звании «" .. rankName(rule.group, rule.rank) .. "»" end
	if rule.min and rank < rule.min then return "Экзамен сдают со звания «" .. rankName(rule.group, rule.min) .. "»" end
	if rule.flag and MRS.GetSData(ply, rule.flag) then return "Экзамен уже сдан" end
end

-- почему ex не может принять экзамен у target; nil - может
local function examinerDenied(ex, target, exam)
	local rule = examinerRule(exam)
	if not rule then return "Этот экзамен сдают у NPC" end
	if not IsValid(target) or not target:IsPlayer() or target == ex then return "Игрок не найден" end
	if ex:GetPos():DistToSqr(target:GetPos()) > EXAM_DIST * EXAM_DIST then return "Подойдите ближе к игроку" end
	if isAdmin(ex) then return end

	local grp = rule.group
	if MRS.GetNWdata(ex, "Group") ~= grp or MRS.GetNWdata(target, "Group") ~= grp then
		return "Экзамен принимают только в своей службе: " .. grp
	end

	local rank = tonumber(MRS.GetNWdata(ex, "Rank")) or 1
	if rank < rule.rank then return "Экзамены принимают со звания «" .. rankName(grp, rule.rank) .. "»" end
	if rank <= (tonumber(MRS.GetNWdata(target, "Rank")) or 1) then return "Экзамен принимает только старший по званию" end
end

--[[---------------------------------------------------------------------------
	Отчёты
---------------------------------------------------------------------------]]

-- окно MRS.OpenExamstats (ui/rank_panel.lua) получает {отчёты, ответы}:
-- отчёт {exam, stamp, fails, status, passed[вопрос] = ответ}, старые первыми
-- (окно выводит новые сверху); ответы[экзамен][вопрос] - правильные, только
-- на вопросы из этих отчётов
local function sendRecords(ply, records)
	local list, answers = {}, {}

	for _, r in ipairs(records) do
		local test, _, key = examData(r.exam)

		if test and istable(r.passed) then
			local passed = {}
			answers[r.exam] = answers[r.exam] or {}

			for qid, k in pairs(r.passed) do
				local q, a = tonumber(qid), tonumber(k)

				if q and a and test[q] and test[q].a[a] ~= nil then
					passed[q] = a
					answers[r.exam][q] = key[q]
				end
			end

			list[#list + 1] = {
				exam = r.exam, stamp = tonumber(r.stamp) or 0, fails = tonumber(r.fails) or 0,
				status = tonumber(r.status) == 1 and 1 or 0, passed = passed,
			}
		end
	end

	if #list == 0 then return false end

	table.sort(list, function(a, b) return a.stamp < b.stamp end)

	local data, len = DarkRP.TableCompress({list, answers})
	if not data or not len or len > MAX_NET_DATA then return false end

	net.Start("MRS.Exam")
	net.WriteUInt(2, 3)
	net.WriteUInt(len, 32)
	net.WriteData(data, len)
	net.Send(ply)

	return true
end

local function saveRecord(st, record)
	if st.nosave then return end

	local uid = sqlStr(st.uid)
	local values = {
		uid, sqlStr(st.sid), sqlStr(record.exam), record.stamp, record.fails, record.status,
		st.examinerSid and sqlStr(st.examinerSid) or "NULL", sqlStr(util.TableToJSON(record.passed) or "[]"),
	}

	query("REPLACE INTO mrs_exams (uid, steamid, exam, stamp, fails, status, examiner, passed) VALUES (" .. table.concat(values, ", ") .. ")", function()
		-- в базе - только MAX_RECORDS последних отчётов персонажа
		query("SELECT stamp FROM mrs_exams WHERE uid = " .. uid .. " ORDER BY stamp DESC LIMIT 1 OFFSET " .. (MAX_RECORDS - 1), function(rows)
			local old = istable(rows) and rows[1] and tonumber(rows[1].stamp)
			if old then query("DELETE FROM mrs_exams WHERE uid = " .. uid .. " AND stamp < " .. old) end
		end)
	end)
end

--[[---------------------------------------------------------------------------
	Экзамен
---------------------------------------------------------------------------]]

local failedAt = {} -- "персонаж#экзамен" -> время провала (после рестарта - из базы)

local function sendQuestion(ply)
	local st = ply.MRSExam
	if not st or st.pending or not st.qid then return end

	net.Start("MRS.Exam")
	net.WriteUInt(1, 3)
	net.WriteString(st.exam)
	net.WriteUInt(st.qid, 32)
	net.Send(ply)
end

-- звание: экзамен у NPC-комиссара (npc = true) повышает сам; экзамены из меню C (сержант)
-- звание не выдают - повышает экзаменатор вручную в меню званий. Возвращает это звание
local function reward(ply, exam)
	local rule = RULES[exam]
	local manual

	if rule.promote and MRS.GetPlyRank(ply, rule.group) < rule.promote then
		if rule.npc then
			MRS.SetPlayerRank(ply, rule.group, rule.promote)
		else
			manual = rankName(rule.group, rule.promote)
		end
	end

	if rule.flag then MRS.SetNWStoredData(ply, rule.flag, 1) end

	if rule.gun and (tonumber(MRS.GetSData(ply, "exam_gun", 0)) or 0) < rule.gun then
		MRS.SetNWStoredData(ply, "exam_gun", rule.gun)
	end

	return manual
end

-- конец экзамена: done - ответил на все вопросы; reason - почему прервали;
-- quiet - сдающему ничего не отправлять (вышел с сервера)
local function finish(ply, done, reason, quiet)
	local st = ply.MRSExam
	if not st or st.pending then return end

	ply.MRSExam = nil
	timer.Remove("MRS.Exam." .. st.userid)

	local _, info = examData(st.exam)
	info = info or {}

	local max = allowed(info)
	local ok = done and st.fails <= max or false
	local name = tostring(info.name or st.exam)
	local record = {exam = st.exam, stamp = os.time(), fails = st.fails, status = ok and 1 or 0, passed = st.passed}

	saveRecord(st, record)

	local manual

	if ok then
		manual = reward(ply, st.exam)

		local gain = not manual and GAINS[st.exam]
		say(ply, "Экзамен сдан: " .. name .. ". Ошибок: " .. st.fails .. (gain and (". Теперь доступно: " .. gain) or "") .. (manual and (". Звание «" .. manual .. "» выдаст экзаменатор") or ""), 0)
	else
		failedAt[st.uid .. "#" .. st.exam] = record.stamp

		if not quiet then
			local cd = tonumber(info.cooldown) or 0
			say(ply, "Экзамен не сдан (" .. (reason or ("ошибок больше " .. max)) .. ")" .. (cd > 0 and (". Пересдача через " .. minutes(cd)) or ""), 1)
		end
	end

	if info.show_res and not quiet then sendRecords(ply, {record}) end

	local ex = st.examiner
	if IsValid(ex) and ex ~= ply then
		say(ex, st.nick .. ": " .. name .. (ok and " - сдан" or " - не сдан") .. ", ошибок " .. st.fails .. (manual and (". Повысьте до «" .. manual .. "» в меню званий") or ""), ok and 0 or 1)
		sendRecords(ex, {record})
	end

	hook.Run("MRS.ExamFinished", ply, st.exam, ok, st.fails, ex)
end

local function answer(ply, k)
	local st = ply.MRSExam
	if not st or st.pending or not st.qid then return end

	local test, info, key = examData(st.exam)
	if not test then return finish(ply, false, "экзамен отключён") end

	-- чужой номер варианта - показать вопрос ещё раз (окно уже закрылось)
	if not k or test[st.qid].a[k] == nil then return sendQuestion(ply) end

	st.passed[st.qid] = k
	if k ~= key[st.qid] then st.fails = st.fails + 1 end

	if st.fails > allowed(info) then return finish(ply, false) end

	st.i = st.i + 1
	st.qid = st.order[st.i]

	if not st.qid then return finish(ply, true) end

	sendQuestion(ply)
end

local function begin(ply, exam, examiner)
	local test, info = examData(exam)

	local order = {}
	for i = 1, #test do order[i] = i end

	for i = #order, 2, -1 do
		local j = math.random(i)
		order[i], order[j] = order[j], order[i]
	end

	local st = {
		exam = exam, order = order, i = 1, qid = order[1], fails = 0, passed = {},
		uid = ply.MRSuid, sid = ply:SteamID64() or "", nick = ply:Nick(), userid = ply:UserID(),
		nosave = ply.MRSNoSave and true or nil,
		examiner = examiner, examinerSid = examiner and examiner:SteamID64() or nil,
	}
	ply.MRSExam = st

	local time = math.max(30, tonumber(info.time) or 600)

	timer.Create("MRS.Exam." .. st.userid, time, 1, function()
		if IsValid(ply) and ply.MRSExam == st then finish(ply, false, "время вышло") end
	end)

	say(ply, "Экзамен начат: " .. tostring(info.name) .. ". Время - " .. minutes(time) .. ", допустимо ошибок: " .. allowed(info), 0)
	if examiner then say(examiner, "Экзамен начат: " .. st.nick .. ", " .. tostring(info.name), 0) end

	sendQuestion(ply)
	hook.Run("MRS.ExamStarted", ply, exam, examiner)
end

-- Запуск экзамена. NPC: MRS.Exam.StartTest(ply, exam); экзаменатор передаёт
-- себя третьим аргументом (его права - examinerDenied). Пересдача - по
-- последнему провалу в базе или в памяти. true - проверки пройдены, ждём базу.
function MRS.Exam.StartTest(ply, exam, examiner)
	if not IsValid(ply) or not ply:IsPlayer() or not isstring(exam) or not RULES[exam] then return false end

	examiner = IsValid(examiner) and examiner or nil

	-- отказ - тому, кто запускал экзамен
	local function deny(text)
		if IsValid(examiner) then
			say(examiner, ply:Nick() .. ": " .. text, 1)
		else
			say(ply, text, 1)
		end

		return false
	end

	if not examiner and not RULES[exam].npc then return deny("Этот экзамен принимает экзаменатор") end

	local why = denied(ply, exam)
	if why then return deny(why) end

	if spam(ply, "start", START_DELAY) then return false end

	local uid = ply.MRSuid
	local wait = {pending = true}
	ply.MRSExam = wait

	local function go(last)
		if not IsValid(ply) or ply.MRSExam ~= wait then return end
		ply.MRSExam = nil
		if ply.MRSuid ~= uid then return end

		local _, info = examData(exam)
		local left = math.max(last or 0, failedAt[uid .. "#" .. exam] or 0) + (tonumber(info and info.cooldown) or 0) - os.time()
		if left > 0 then return deny("Пересдача через " .. minutes(left)) end

		-- пока шёл запрос к базе, всё могло измениться
		why = denied(ply, exam)

		if not why and examiner then
			if IsValid(examiner) then
				why = examinerDenied(examiner, ply, exam)
			else
				why = "Экзаменатор вышел"
			end
		end

		if why then return deny(why) end

		begin(ply, exam, examiner)
	end

	query("SELECT stamp FROM mrs_exams WHERE uid = " .. sqlStr(uid) .. " AND exam = " .. sqlStr(exam) .. " AND status = 0 ORDER BY stamp DESC LIMIT 1", function(rows)
		go(istable(rows) and rows[1] and tonumber(rows[1].stamp) or 0)
	end, function()
		go(0)
	end)

	return true
end

--[[---------------------------------------------------------------------------
	Просмотр отчётов (кнопка "Открыть данные экзамена")
---------------------------------------------------------------------------]]

-- какие отчёты игрока sid видит ply: all - все; group - экзамены своей службы
-- (экзаменатор или руководство); self - свои экзамены с show_res; nil - никакие
local function viewScope(ply, sid)
	if isAdmin(ply) then return {all = true} end

	local scope = {self = ply:SteamID64() == sid}
	local grp = MRS.GetNWdata(ply, "Group")
	local rank = tonumber(MRS.GetNWdata(ply, "Rank")) or 1
	local promote, demote = MRS.RankPermissions(ply)

	for _, rule in pairs(EXAMINERS) do
		if rule.group == grp and (rank >= rule.rank or promote or demote) then scope.group = grp end
	end

	if scope.self or scope.group then return scope end
end

local function visible(scope, r)
	local rule = RULES[r.exam]
	if not rule then return false end
	if scope.all or scope.group == rule.group then return true end

	local _, info = examData(r.exam)
	return scope.self and info ~= nil and info.show_res and true or false
end

local function requestRecords(ply, sid)
	if not isstring(sid) or #sid > 20 or not string.match(sid, "^%d+$") then return end

	local scope = viewScope(ply, sid)
	if not scope then return say(ply, "Нет доступа к отчётам об экзаменах", 1) end

	-- игрок на сервере - отчёты текущего персонажа, иначе - всех его персонажей
	local target = player.GetBySteamID64(sid)
	local where = IsValid(target) and target.MRSuid and ("uid = " .. sqlStr(target.MRSuid)) or ("steamid = " .. sqlStr(sid))

	query("SELECT exam, stamp, fails, status, passed FROM mrs_exams WHERE " .. where .. " ORDER BY stamp DESC LIMIT " .. (MAX_RECORDS * 2), function(rows)
		if not IsValid(ply) then return end

		local list = {}

		for _, row in ipairs(istable(rows) and rows or {}) do
			if #list >= SEND_RECORDS then break end

			row.passed = util.JSONToTable(tostring(row.passed or "")) or {}
			if visible(scope, row) then list[#list + 1] = row end
		end

		if not sendRecords(ply, list) then say(ply, "Отчётов об экзаменах нет", 0) end
	end)
end

--[[---------------------------------------------------------------------------
	Net, команда, хуки, база
---------------------------------------------------------------------------]]

local function abort(ply, reason, quiet)
	local st = ply.MRSExam
	if not st then return end

	if st.pending then
		ply.MRSExam = nil
		return
	end

	finish(ply, false, reason, quiet)
end

-- "MRS.Exam" регистрирует autorun/mc_ranks.lua (до загрузки core)

net.Receive("MRS.Exam", function(_, ply)
	if not IsValid(ply) then return end

	local tp = net.ReadUInt(3)

	if tp == 2 then
		answer(ply, net.ReadUInt(3))
	elseif tp == 1 or tp == 4 then
		local exam = net.ReadString()
		local target = Player(net.ReadUInt(32))

		if spam(ply, "examine", START_DELAY) or not EXAMINERS[tp].exams[exam] then return end

		local why = examinerDenied(ply, target, exam)
		if why then return say(ply, why, 1) end

		MRS.Exam.StartTest(target, exam, ply)
	elseif tp == 3 then
		local sid = net.ReadString()

		if spam(ply, "records", RECORDS_DELAY) then return end

		requestRecords(ply, sid)
	end
end)

local function registerCommand()
	if not DarkRP or not DarkRP.defineChatCommand then return end

	-- окно вопроса закрыли - открыть снова
	DarkRP.defineChatCommand("exam", function(ply)
		local st = ply.MRSExam

		if st and not st.pending and st.qid then
			sendQuestion(ply)
		else
			say(ply, "Сейчас вы не сдаёте экзамен", 1)
		end

		return ""
	end)
end

registerCommand()
hook.Add("MRS.Hook.PostConfigLoad", "MRS.ExamCommand", registerCommand)

hook.Add("OnPlayerChangedTeam", "MRS.Exam", function(ply) abort(ply, "смена профессии") end)
hook.Add("MCR.CharacterSelected", "MRS.Exam", function(ply) abort(ply, "смена персонажа") end)
hook.Add("MCR.CharacterReset", "MRS.Exam", function(ply) abort(ply, "смена персонажа") end)
hook.Add("PlayerDisconnected", "MRS.Exam", function(ply) abort(ply, "выход с сервера", true) end)

local function startDB()
	if MRS.ExamDBStarted then return end
	MRS.ExamDBStarted = true

	query([[CREATE TABLE IF NOT EXISTS mrs_exams(
		uid VARCHAR(64) NOT NULL,
		steamid VARCHAR(32) NOT NULL,
		exam VARCHAR(32) NOT NULL,
		stamp BIGINT NOT NULL,
		fails INTEGER NOT NULL,
		status INTEGER NOT NULL,
		examiner VARCHAR(32),
		passed TEXT NOT NULL,
		PRIMARY KEY(uid, exam, stamp)
	)]])
end

hook.Add("DatabaseInitialized", "MRS.Exam", startDB)
