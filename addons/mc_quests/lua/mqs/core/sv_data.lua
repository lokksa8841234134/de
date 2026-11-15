--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	MQS (квесты) - сервер, часть 1: данные игроков, файлы квестов, редактор

	ply.MQSdata.Stored - данные по аккаунту (SteamID вида STEAM_0:1:2345):
	  QuestList (выполненные квесты: id -> сколько раз), CoolDown (личные
	  задержки: id -> os.time) и метки других модулей (police, dezz,
	  эпизоды, наборы). Таблица mqs_players через MySQLite (sv.db или MySQL).
	ply.MQSdata: active_quest, active_questid, quest_objective, do_time,
	  loops - текущий квест, их видят все игроки (MQS.SetNWdata).
	ply.MQSdata_self - счётчики задачи, их видит только сам игрок
	  (MQS.SetSelfNWdata): quest_wait, quest_ent, quest_colected, targets.

	Квесты - JSON в data/<MQS.ServerID>/quests/<карта>/<id>.txt, у каждой
	карты свои. Сохраняет и удаляет их редактор (/mqs, MQS.Config.Editors),
	выполненные квесты игроков правят MQS.Config.Administrators. Квест с
	консольной командой (событие или награда "Run Console Command")
	сохраняет только администратор MQS: иначе редактор получил бы консоль.

	Ход квеста - sv_tasks.lua.
---------------------------------------------------------------------------]]

util.AddNetworkString("MQS.OpenNPCMenu")

local MAX_NET = 60000					-- байт в одном сообщении (предел net - 64 КБ)
local MAX_JSON = 4 * 1024 * 1024		-- байт JSON после распаковки данных от клиента
local SAVE_DELAY = 2					-- запись игрока в базу после изменения, с
local STATS_DELAY = 60					-- запись статистики квестов, с
local QUEST_ROOT = MQS.ServerID .. "/quests"
local STATS_FILE = MQS.ServerID .. "/mqs_stats.txt"
local CONSOLE = "Run Console Command"
local MAX_OBJECTS = 500					-- задач в одном квесте

-- служебные поля редактора: в файл не идут
local EDITOR_ONLY = {"new", "oldid", "edited", "temp_data", "notloaded", "id"}

-- порядок важен: клиент рисует квест, когда пришёл active_quest, - остальное раньше
local PUBLIC_KEYS = {"active_questid", "quest_objective", "do_time", "loops", "active_quest"}

MQS.DB = MQS.DB or {}

local DB = MQS.DB

--[[---------------------------------------------------------------------------
	Мелочи
---------------------------------------------------------------------------]]
local function spam(ply, key, delay)
	ply.MQSNetCD = ply.MQSNetCD or {}

	local t = ply.MQSNetCD[key]
	if t and t > CurTime() then return true end

	ply.MQSNetCD[key] = CurTime() + delay

	return false
end

MQS.NetSpam = spam

local function say(ply, text, kind)
	if IsValid(ply) then
		MQS.SmallNotify(text, ply, kind or 0)
	else
		print("[MQS] " .. text)
	end
end

local function isEditor(ply)
	return IsValid(ply) and ply:IsPlayer() and MQS.IsEditor(ply) and true or false
end

local function isAdmin(ply)
	return IsValid(ply) and ply:IsPlayer() and MQS.IsAdministrator(ply) and true or false
end

local function encode(t)
	return util.TableToJSON(t, false) or "{}"
end

local function decode(s)
	local t = isstring(s) and s ~= "" and util.JSONToTable(s)

	return istable(t) and t or {}
end

local function validSid(sid)
	return isstring(sid) and string.match(sid, "^STEAM_%d:%d:%d+$") ~= nil
end

local function validID(id)
	return isstring(id) and #id > 0 and #id <= 64 and MQS.CheckID(id) and true or false
end

MQS.ValidQuestID = validID

-- таблица от клиента: Int32 длина + сжатый JSON
local function readTable(limit)
	local bn = net.ReadInt(32)
	if not bn or bn <= 0 or bn > (limit or MAX_NET) then return end

	local cd = net.ReadData(bn)
	local json = cd and util.Decompress(cd, MAX_JSON)
	if not json or json == "" then return end

	local t = util.JSONToTable(json)

	return istable(t) and t or nil
end

MQS.ReadNetTable = readTable

-- MySQLite без обработчика ошибки останавливает скрипт - пишем в консоль
local function query(sql, callback, onError)
	MySQLite.query(sql, callback, function(err)
		print("[MQS] Ошибка базы: " .. tostring(err))

		if onError then onError(err) end

		return true
	end)
end

--[[---------------------------------------------------------------------------
	Отправка клиентам
	MQS.SendDataToClien(таблица[, игрок]) - net MQS.GetBigData (без игрока - всем)
---------------------------------------------------------------------------]]
function MQS.SendDataToClien(data, ply)
	if isentity(ply) and not IsValid(ply) then return false end

	local cd, bn = MQS.TableCompress(data)
	if not cd then return false end

	if bn > MAX_NET then
		print("[MQS] Не помещается в одно сообщение (" .. bn .. " байт): " .. tostring(data.index))

		return false
	end

	net.Start("MQS.GetBigData")
	net.WriteInt(bn, 32)
	net.WriteData(cd, bn)

	if ply ~= nil then
		net.Send(ply)
	else
		net.Broadcast()
	end

	return true
end

local function pdataValue(v)
	if v == nil or v == false then return "" end

	return tostring(v)
end

-- без игрока в сообщении клиент кладёт значение в свои MQSdata_self
local function sendSelf(ply, id, value)
	net.Start("MQS.SetPData")
	net.WriteString(id)
	net.WriteString(pdataValue(value))
	net.WriteEntity(NULL)
	net.Send(ply)
end

--[[---------------------------------------------------------------------------
	Данные игрока
---------------------------------------------------------------------------]]
function MQS.InitPlayer(ply)
	ply.MQSdata = ply.MQSdata or {}
	ply.MQSdata.Stored = ply.MQSdata.Stored or {}
	ply.MQSdata_self = ply.MQSdata_self or {}
	ply.EventData = ply.EventData or {}
end

local function stored(ply)
	MQS.InitPlayer(ply)

	return ply.MQSdata.Stored
end

-- MQS.SetNWdata(игрок, ключ, значение) - текущий квест, видят все
function MQS.SetNWdata(ply, id, value)
	if not IsValid(ply) or not isstring(id) then return end

	MQS.InitPlayer(ply)

	if value == false then value = nil end
	ply.MQSdata[id] = value

	net.Start("MQS.SetPData")
	net.WriteString(id)
	net.WriteString(pdataValue(value))
	net.WriteEntity(ply)
	net.Broadcast()
end

-- MQS.SetSelfNWdata(игрок, ключ, значение) - счётчики задачи, видит сам игрок
function MQS.SetSelfNWdata(ply, id, value)
	if not IsValid(ply) or not isstring(id) then return end

	MQS.InitPlayer(ply)

	if value == false then value = nil end
	ply.MQSdata_self[id] = value

	sendSelf(ply, id, value)
end

function DB.Write(sid, data)
	if not DB.Ready or not validSid(sid) or not istable(data) then return false end

	query("REPLACE INTO mqs_players(steamid, data, updated) VALUES(" .. MySQLite.SQLStr(sid) .. ", " .. MySQLite.SQLStr(encode(data)) .. ", " .. os.time() .. ")")

	return true
end

local function saveNow(ply)
	if not IsValid(ply) or not ply.MQS_Loaded then return end

	ply.MQS_Dirty = nil
	timer.Remove("MQS.Save." .. ply:UserID())
	DB.Write(ply:SteamID(), stored(ply))
end

local function scheduleSave(ply)
	ply.MQS_Dirty = true
	if not ply.MQS_Loaded then return end

	local name = "MQS.Save." .. ply:UserID()
	if timer.Exists(name) then return end

	timer.Create(name, SAVE_DELAY, 1, function()
		if IsValid(ply) and ply.MQS_Dirty then saveNow(ply) end
	end)
end

-- записать сейчас, если есть что (выход игрока, выключение сервера)
function MQS.FlushPlayer(ply)
	if IsValid(ply) and ply.MQS_Dirty then saveNow(ply) end
end

-- MQS.SetNWStoredData(игрок, ключ, значение) - сохраняемые данные (nil - удалить)
function MQS.SetNWStoredData(ply, id, value)
	if not IsValid(ply) or not ply:IsPlayer() or id == nil then return end

	stored(ply)[id] = value

	-- поменяли до загрузки из базы: при загрузке это значение важнее
	if not ply.MQS_Loaded then
		ply.MQS_Pending = ply.MQS_Pending or {}
		ply.MQS_Pending[id] = true
	end

	scheduleSave(ply)

	-- до первого пакета клиенту слать нечего: в нём будет всё
	if ply.MQS_DataSent then
		MQS.SendDataToClien({isplayerdata = ply:UserID(), index = id, data = value}, ply)
	end
end

local function publicData(ply, own)
	local d = ply.MQSdata or {}
	local t = {Stored = own and d.Stored or {}}

	for _, k in ipairs(PUBLIC_KEYS) do
		t[k] = d[k]
	end

	return t
end

-- всё о квестах игроку: свои данные целиком, у других - только текущий квест
function MQS.SendPlayerData(ply)
	if not IsValid(ply) then return end

	MQS.InitPlayer(ply)
	ply.MQS_DataSent = true

	MQS.SendDataToClien({isplayerdata = ply:UserID(), index = "none", data = publicData(ply, true)}, ply)

	for id, v in pairs(ply.MQSdata_self) do
		sendSelf(ply, id, v)
	end

	for _, pl in ipairs(player.GetAll()) do
		if pl ~= ply and pl.MQSdata and pl.MQSdata.active_quest then
			MQS.SendDataToClien({isplayerdata = pl:UserID(), index = "none", data = publicData(pl)}, ply)
		end
	end
end

local function loaded(ply, data)
	MQS.InitPlayer(ply)

	-- что поменяли до загрузки, важнее базы
	local pending = ply.MQS_Pending
	local cur = ply.MQSdata.Stored

	if pending then
		for k in pairs(pending) do
			data[k] = cur[k]
		end
	end

	-- без списка выполненных MQS.CanPlayIntro не пустит новичка на вступление
	if not istable(data.QuestList) then data.QuestList = {} end

	ply.MQSdata.Stored = data
	ply.MQS_Pending = nil
	ply.MQS_Loaded = true

	if pending then scheduleSave(ply) end

	if ply.MQS_WantData then
		ply.MQS_WantData = nil
		MQS.SendPlayerData(ply)
	end

	hook.Run("MQS.PlayerDataLoaded", ply)
end

function MQS.LoadPlayer(ply)
	if not IsValid(ply) or ply.MQS_Loaded then return end

	MQS.InitPlayer(ply)

	local sid = ply:SteamID()

	-- боты и игроки без SteamID: в базу не пишем
	if not validSid(sid) then
		loaded(ply, {})

		return
	end

	if not DB.Ready or ply.MQS_Loading then return end

	ply.MQS_Loading = true

	query("SELECT data FROM mqs_players WHERE steamid = " .. MySQLite.SQLStr(sid), function(rows)
		if not IsValid(ply) then return end

		ply.MQS_Loading = nil
		if ply.MQS_Loaded then return end

		loaded(ply, decode(istable(rows) and rows[1] and rows[1].data))
	end, function()
		if IsValid(ply) then ply.MQS_Loading = nil end
	end)
end

--[[---------------------------------------------------------------------------
	MQS.DB.GetPlayerData(steamid[, callback]) - Stored игрока, в сети он или нет.
	Возвращает таблицу сразу, если она уже есть (игрок в сети, SQLite); у
	MySQL ответ приходит позже - только в callback. Пустая таблица - записи нет.
---------------------------------------------------------------------------]]
function DB.GetPlayerData(sid, callback)
	if not validSid(sid) then
		if callback then callback(nil) end

		return
	end

	local pl = player.GetBySteamID(sid)

	if IsValid(pl) and pl.MQS_Loaded then
		local data = table.Copy(stored(pl))

		if callback then callback(data) end

		return data
	end

	if not DB.Ready then
		if callback then callback(nil) end

		return
	end

	local result

	query("SELECT data FROM mqs_players WHERE steamid = " .. MySQLite.SQLStr(sid), function(rows)
		result = decode(istable(rows) and rows[1] and rows[1].data)

		if callback then callback(result) end
	end, function()
		if callback then callback(nil) end
	end)

	return result
end

-- MQS.SavePlayerData(steamid, Stored) - заменить Stored целиком (sAdmin set_mqs_info)
function MQS.SavePlayerData(sid, data)
	if not validSid(sid) or not istable(data) then return end

	local pl = player.GetBySteamID(sid)

	if IsValid(pl) and pl.MQS_Loaded then
		pl.MQSdata.Stored = data
		saveNow(pl)

		if pl.MQS_DataSent then MQS.SendPlayerData(pl) end

		return
	end

	DB.Write(sid, data)
end

function DB.Start()
	if DB.Ready or DB.Starting then return end

	DB.Starting = true

	query([[CREATE TABLE IF NOT EXISTS mqs_players(
		steamid VARCHAR(32) NOT NULL PRIMARY KEY,
		data MEDIUMTEXT NOT NULL,
		updated BIGINT NOT NULL
	)]], function()
		DB.Starting = nil
		DB.Ready = true

		for _, pl in ipairs(player.GetAll()) do
			MQS.LoadPlayer(pl)
		end
	end, function()
		DB.Starting = nil
	end)
end

hook.Add("DatabaseInitialized", "MQS.Data", DB.Start)

hook.Add("PlayerInitialSpawn", "MQS.Data", function(ply)
	MQS.InitPlayer(ply)
	MQS.LoadPlayer(ply)
end)

--[[---------------------------------------------------------------------------
	Файлы квестов
---------------------------------------------------------------------------]]
-- team_whitelist в файле квеста можно писать константой (TEAM_POLICE) или названием
-- профессии («Патрульный»): MQS.CanStartTask сверяет номер команды (ply:Team())
local function teamsOf(q)
	local wl = q.team_whitelist
	if not istable(wl) then return end

	local byName = {}
	for i, tm in pairs(isfunction(team.GetAllTeams) and team.GetAllTeams() or {}) do
		if istable(tm) and isstring(tm.Name) then byName[tm.Name] = i end
	end

	local out, miss = {}, {}
	for k, v in pairs(wl) do
		local n = tonumber(k)
		if not n and isstring(k) then
			local g = rawget(_G, k)
			n = isnumber(g) and g or byName[k]
		end

		if v and n then
			out[n] = true
		elseif v then
			out[k] = true -- профессий ещё нет (загрузка до режима) - разберём при следующей загрузке
			miss[#miss + 1] = tostring(k)
		end
	end

	q.team_whitelist = out

	if #miss > 0 and istable(RPExtraTeams) and #RPExtraTeams > 0 then
		print("[MQS] " .. tostring(q.id) .. ": нет профессий " .. table.concat(miss, ", "))
	end
end

local function mapName(map)
	map = string.lower(isstring(map) and map or game.GetMap())

	return string.match(map, "^[%w_%-%.]+$") and map or nil
end

local function questDir(map)
	return QUEST_ROOT .. "/" .. map
end

-- имя файла строчными: так же его запишет и найдёт GMod на любой системе
local function questFile(map, id)
	return questDir(map) .. "/" .. string.lower(id) .. ".txt"
end

-- MQS.LoadQuestFiles([карта]) - квесты карты (по умолчанию текущей): id -> квест
function MQS.LoadQuestFiles(map)
	local list = {}

	map = mapName(map)
	if not map then return list end

	local dir = questDir(map)

	for _, name in ipairs(file.Find(dir .. "/*.txt", "DATA") or {}) do
		local q = util.JSONToTable(file.Read(dir .. "/" .. name, "DATA") or "")
		local id = istable(q) and (validID(q.id) and q.id or string.StripExtension(name))

		if istable(q) and validID(id) and istable(q.objects) then
			for _, k in ipairs(EDITOR_ONLY) do
				q[k] = nil
			end

			teamsOf(q)
			list[id] = q
		else
			print("[MQS] Не удалось прочитать квест " .. dir .. "/" .. name)
		end
	end

	return list
end

local function writeQuest(id, quest)
	local map = mapName()
	if not map then return false end

	file.CreateDir(MQS.ServerID)
	file.CreateDir(QUEST_ROOT)
	file.CreateDir(questDir(map))

	local data = table.Copy(quest)
	data.id = id

	file.Write(questFile(map, id), util.TableToJSON(data, true))

	return file.Exists(questFile(map, id), "DATA")
end

local function deleteQuest(id)
	local map = mapName()

	if map then file.Delete(questFile(map, id)) end
end

MQS.Quests = MQS.LoadQuestFiles()

--[[---------------------------------------------------------------------------
	Статистика для редактора (mqs_prodata): квест -> t (сколько раз начинали),
	u (сколько разных игроков выполнили)
---------------------------------------------------------------------------]]
MQS.Stats = MQS.Stats or decode(file.Read(STATS_FILE, "DATA"))

local function saveStats()
	file.CreateDir(MQS.ServerID)
	file.Write(STATS_FILE, encode(MQS.Stats))
end

function MQS.AddStat(tk, field)
	if not isstring(tk) then return end

	local s = MQS.Stats[tk] or {}

	s[field] = (tonumber(s[field]) or 0) + 1
	MQS.Stats[tk] = s

	if not timer.Exists("MQS.SaveStats") then
		timer.Create("MQS.SaveStats", STATS_DELAY, 1, saveStats)
	end
end

concommand.Add("mqs_prodata", function(ply)
	if not isEditor(ply) or spam(ply, "prodata", 3) then return end

	local out = {}

	for k, s in pairs(MQS.Stats) do
		out[k] = {tonumber(s.t) or 0, tonumber(s.u) or 0}
	end

	MQS.SendDataToClien({index = "ProData", data = out}, ply)
end)

hook.Add("PlayerDisconnected", "MQS.Data", function(ply)
	-- квест вышедшего - провал (sv_tasks.lua), потом запись
	if MQS.EndPlayerTask then MQS.EndPlayerTask(ply) end

	MQS.FlushPlayer(ply)
	timer.Remove("MQS.Save." .. ply:UserID())
end)

hook.Add("ShutDown", "MQS.Data", function()
	for _, pl in ipairs(player.GetAll()) do
		MQS.FlushPlayer(pl)
	end

	saveStats()
end)

--[[---------------------------------------------------------------------------
	Клиент просит данные
---------------------------------------------------------------------------]]
local function sendScenes(ply)
	if not next(MQS.Scenes.Cache) then return end

	local cd, bn = MQS.TableCompress(MQS.Scenes.Cache)
	if not cd or bn > MAX_NET then return end

	net.Start("MQS.SceneManage")
	net.WriteString("")
	net.WriteUInt(2, 2)
	net.WriteUInt(bn, 32)
	net.WriteData(cd, bn)
	net.Send(ply)
end

-- свои данные (MQSdata); пока база не ответила - сразу после загрузки
net.Receive("MQS.GetPData", function(_, ply)
	if spam(ply, "pdata", 2) then return end

	if not ply.MQS_SceneSent then
		ply.MQS_SceneSent = true
		sendScenes(ply)
	end

	if ply.MQS_Loaded then
		MQS.SendPlayerData(ply)
	else
		ply.MQS_WantData = true
		MQS.LoadPlayer(ply)
	end
end)

-- квесты (без задач), идущие квесты, задержки; первый раз - со списком квестов
net.Receive("MQS.DataShare", function(_, ply)
	if spam(ply, "share", 1) then return end

	local first = not ply.MQS_Shared
	ply.MQS_Shared = true

	MQS.DataShare(ply, first)
end)

-- квест целиком (с задачами)
net.Receive("MQS.ReQuest", function(_, ply)
	if spam(ply, "request", 0.1) then return end

	local id = net.ReadString()

	if validID(id) and MQS.Quests[id] then MQS.ReQuest(id, ply) end
end)

--[[---------------------------------------------------------------------------
	Редактор
---------------------------------------------------------------------------]]
local function hasConsole(quest)
	local function inRewards(r)
		return istable(r) and r[CONSOLE] ~= nil
	end

	if inRewards(quest.reward) then return true end

	for _, obj in pairs(istable(quest.objects) and quest.objects or {}) do
		if istable(obj) then
			if inRewards(obj.reward) then return true end

			for _, ev in pairs(istable(obj.events) and obj.events or {}) do
				if istable(ev) and ev[1] == CONSOLE then return true end
			end
		end
	end

	return false
end

-- задачи - список таблиц с типом
local function validObjects(quest)
	local objs = quest.objects
	if not istable(objs) or not istable(objs[1]) then return false end

	local n = 0

	for k, obj in pairs(objs) do
		n = n + 1

		if not isnumber(k) or not istable(obj) or not isstring(obj.type) then return false end
	end

	return n == #objs and n <= MAX_OBJECTS
end

net.Receive("MQS.QuestSubmit", function(_, ply)
	if not isEditor(ply) or spam(ply, "submit", 1) then return end

	local quest = readTable()
	if not quest then return say(ply, "Квест не дошёл до сервера: он слишком большой или повреждён", 1) end

	local id, oldid = quest.id, quest.oldid

	if not validID(id) then return say(ply, "ID квеста: латиница, цифры и _, не одни цифры, до 64 знаков", 1) end
	if not validObjects(quest) then return say(ply, "В квесте нет задач или они повреждены", 1) end

	-- какой квест заменяет этот (тот же или переименованный)
	local replacing

	if not quest.new then
		if isstring(oldid) and MQS.Quests[oldid] then
			replacing = oldid
		elseif MQS.Quests[id] then
			replacing = id
		end
	end

	-- имя файла без учёта регистра: "Quest" и "quest" - один файл
	for qid in pairs(MQS.Quests) do
		if qid ~= replacing and string.lower(qid) == string.lower(id) then
			return say(ply, "Квест с таким ID уже есть: " .. qid, 1)
		end
	end

	if not isAdmin(ply) then
		if hasConsole(quest) then
			return say(ply, "Квест с консольной командой сохраняет только администратор MQS", 1)
		end

		-- включать и выключать квест может только администратор (как в редакторе)
		local old = replacing and MQS.Quests[replacing]
		quest.active = old and old.active or nil
	end

	for _, k in ipairs(EDITOR_ONLY) do
		quest[k] = nil
	end

	if not writeQuest(id, quest) then return say(ply, "Не удалось записать файл квеста", 1) end

	-- переименовали: старого квеста больше нет
	if replacing and replacing ~= id then
		MQS.StopQuestTasks(replacing)
		MQS.Quests[replacing] = nil

		if string.lower(replacing) ~= string.lower(id) then deleteQuest(replacing) end

		net.Start("MQS.QuestRemove")
		net.WriteString(replacing)
		net.Broadcast()
	end

	-- задачи могли поменяться - текущие прохождения не доиграть
	MQS.StopQuestTasks(id)
	MQS.Quests[id] = quest
	MQS.ReQuest(id)

	say(ply, "Квест сохранён: " .. id, 0)
	print("[MQS] " .. ply:Nick() .. " (" .. ply:SteamID() .. ") сохранил квест " .. id)
	hook.Run("MQS.QuestSaved", id, ply)
end)

net.Receive("MQS.QuestRemove", function(_, ply)
	if not isEditor(ply) or spam(ply, "remove", 1) then return end

	local id = net.ReadString()
	if not MQS.Quests[id] then return end

	MQS.StopQuestTasks(id)
	MQS.Quests[id] = nil
	deleteQuest(id)

	net.Start("MQS.QuestRemove")
	net.WriteString(id)
	net.Broadcast()

	say(ply, "Квест удалён: " .. id, 0)
	print("[MQS] " .. ply:Nick() .. " (" .. ply:SteamID() .. ") удалил квест " .. id)
end)

-- квесты другой карты - скопировать в эту
net.Receive("MQS.GetOtherQuests", function(_, ply)
	if not isEditor(ply) or spam(ply, "other", 2) then return end

	local map = mapName(net.ReadString())
	if not map then return end

	local list = MQS.LoadQuestFiles(map)
	local data = {isaltdata = true, index = "Quests", data = list}

	-- не помещается в одно сообщение - без самых больших квестов
	local cd, bn = MQS.TableCompress(data)
	local dropped = 0

	while cd and bn > MAX_NET and next(list) do
		local big, size = nil, -1

		for k, q in pairs(list) do
			local s = #encode(q)

			if s > size then big, size = k, s end
		end

		list[big] = nil
		dropped = dropped + 1
		cd, bn = MQS.TableCompress(data)
	end

	if dropped > 0 then say(ply, "Не поместились в сообщение квестов: " .. dropped, 1) end

	MQS.SendDataToClien(data, ply)
end)

--[[---------------------------------------------------------------------------
	Выполненные квесты игрока (вкладка игроков в редакторе), игрок в сети или нет
---------------------------------------------------------------------------]]
local function sendQuestList(ply, sid, list)
	local cd, bn = MQS.TableCompress({QuestList = list or {}})
	if not cd or bn > MAX_NET then return end

	net.Start("MQS.GetPlayersQuests")
	net.WriteString(sid)
	net.WriteInt(bn, 32)
	net.WriteData(cd, bn)
	net.Send(ply)
end

-- id -> сколько раз выполнен; нули и мусор - убрать
local function cleanQuestList(t)
	local out = {}

	for k, v in pairs(istable(t) and t or {}) do
		local n = tonumber(v)

		if isstring(k) and #k <= 64 and n and n > 0 then out[k] = math.floor(n) end
	end

	return out
end

net.Receive("MQS.GetPlayersQuests", function(_, ply)
	if not isAdmin(ply) or spam(ply, "plyquests", 1) then return end

	local sid = net.ReadString()
	if not validSid(sid) then return say(ply, "Неверный SteamID: нужен вид STEAM_0:1:2345", 1) end

	DB.GetPlayerData(sid, function(data)
		if not IsValid(ply) then return end
		if not data then return say(ply, "База недоступна", 1) end

		sendQuestList(ply, sid, cleanQuestList(data.QuestList))
	end)
end)

net.Receive("MQS.SavePlayerQuestList", function(_, ply)
	if not isAdmin(ply) or spam(ply, "savelist", 1) then return end

	local sid = net.ReadString()
	local t = readTable()
	if not validSid(sid) or not t then return end

	local list = cleanQuestList(istable(t.QuestList) and t.QuestList or t)
	local pl = player.GetBySteamID(sid)

	print("[MQS] " .. ply:Nick() .. " (" .. ply:SteamID() .. ") изменил выполненные квесты " .. sid)

	if IsValid(pl) and pl.MQS_Loaded then
		MQS.SetNWStoredData(pl, "QuestList", list)

		return say(ply, "Выполненные квесты игрока сохранены", 0)
	end

	DB.GetPlayerData(sid, function(data)
		if not data then
			if IsValid(ply) then say(ply, "База недоступна", 1) end

			return
		end

		data.QuestList = list
		DB.Write(sid, data)

		if IsValid(ply) then say(ply, "Выполненные квесты игрока сохранены", 0) end
	end)
end)

--[[---------------------------------------------------------------------------
	Кинокамера квеста: место камеры сервер прогружает игроку (PVS),
	иначе дальний кадр выйдет пустым
---------------------------------------------------------------------------]]
net.Receive("MQS.UIEffect", function(_, ply)
	if spam(ply, "uieffect", 0.5) then return end

	local data = readTable(4096)
	if not data or data.name ~= "Cinematic camera" or not isvector(data.pos) then return end
	if not MQS.HasQuest(ply) then return end

	ply.MQS_CamPos = data.pos
	ply.MQS_CamEnd = CurTime() + math.Clamp(tonumber(data.time) or 10, 1, 60) + 2
end)

hook.Add("SetupPlayerVisibility", "MQS.Camera", function(ply)
	local pos = ply.MQS_CamPos
	if not pos then return end

	if (ply.MQS_CamEnd or 0) < CurTime() then
		ply.MQS_CamPos, ply.MQS_CamEnd = nil, nil

		return
	end

	AddOriginToPVS(pos)
end)

--[[---------------------------------------------------------------------------
	/mqs - редактор квестов (mqs_editor в консоли - команда клиента)
---------------------------------------------------------------------------]]
local function openEditor(ply)
	if not isEditor(ply) then return say(ply, MSD.GetPhrase("need_admin"), 1) end

	net.Start("MQS.OpenEditor")
	net.Send(ply)
end

local function registerCommand()
	if not DarkRP or not DarkRP.defineChatCommand then return end

	DarkRP.defineChatCommand("mqs", function(ply)
		openEditor(ply)

		return ""
	end, 1)
end

registerCommand()
hook.Add("DarkRPFinishedLoading", "MQS.EditorCommand", registerCommand)
hook.Add("MQS.Hook.PostConfigLoad", "MQS.EditorCommand", registerCommand)

-- файл перезагрузили на ходу
for _, pl in ipairs(player.GetAll()) do
	MQS.InitPlayer(pl)
	MQS.LoadPlayer(pl)
end
