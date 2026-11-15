--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	MRS - серверная часть (шаг 15.1)

	В сборке была только общая и клиентская часть: ранги нигде не хранились,
	у всех ранг 0, редактор и меню рангов ничего не сохраняли. Здесь:
	- группы рангов (MRS.Ranks) - в базе DarkRP (MySQLite), таблица
	  mrs_groups; при первом запуске создаются группы по умолчанию (ниже),
	  дальше их меняют в редакторе (/mrs у администратора);
	- ранги и метки игрока (Stored: [группа] = {rank, time}, exam_gun и др.) -
	  на персонажа (MRS.PlayerID), таблица mrs_players; загрузка при выборе
	  персонажа, запись сразу при каждом изменении;
	- активная группа и ранг - по профессии (group.job[название профессии]),
	  бонусы ранга - MRS.PlayerStats (например «Salary bonus»);
	- повышение и понижение: редактор, меню рангов (/mrs), /promote и
	  /demote, консоль mrs_setrank, ранги персонажей не в сети;
	- MRS.SetPlayerRank и MRS.SetNWStoredData для других модулей (награды
	  квестов MQS, команда sAdmin set_mrs_info).
	Экзамены (MRS.Exam) - шаг 15.2.

	Сервер не доверяет клиенту: права проверяются здесь, данные из сети -
	по размеру, формату и частоте.
	ChangePlayerName (ранг в имени) не применяется: имя персонажа входит в
	DarkRP.CharacterID, его смена отвязала бы персонажа от его данных.
---------------------------------------------------------------------------]]

MRS.Ranks = MRS.Ranks or {}

for _, name in ipairs({
	"MRS.GetBigData", "MRS.SetPData", "MRS.RanksUpdate", "MRS.RanksRemove",
	"MRS.RanksSubmit", "MRS.DataShare", "MRS.GetPData", "MRS.GetPlayersRanks",
	"MRS.SavePlayerRankList", "MRS.RequestStoredData", "MRS.OpenEditor", "MRS.Notify"
}) do
	util.AddNetworkString(name)
end

local MAX_NET_DATA = 60000	-- байт сжатых данных в одном сообщении
local MAX_RANKS = 64
local MAX_JOBS = 128
local MAX_TEXT = 256
local LOOK_DIST = 200		-- /promote и /demote без имени - игрок перед тобой

--[[---------------------------------------------------------------------------
	Вспомогательное
---------------------------------------------------------------------------]]
local function spam(ply, key, delay)
	if not IsValid(ply) then return false end

	ply.MRSNetCD = ply.MRSNetCD or {}

	local t = CurTime()
	if (ply.MRSNetCD[key] or 0) > t then return true end

	ply.MRSNetCD[key] = t + delay
	return false
end

-- консоль сервера - тоже администратор
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

local function text(v, max)
	return isstring(v) and #v <= max and v or nil
end

local function encode(t)
	return util.TableToJSON(t or {}) or "{}"
end

local function decode(s)
	local t = isstring(s) and s ~= "" and util.JSONToTable(s)
	return istable(t) and t or {}
end

local function sqlStr(s)
	return MySQLite.SQLStr(tostring(s))
end

-- MySQLite без обработчика ошибки останавливает скрипт - пишем в консоль
local function query(sql, callback, onError)
	MySQLite.query(sql, callback, function(err)
		print("[MRS] Ошибка базы: " .. tostring(err))

		if onError then onError(err) end

		return true
	end)
end

local function stored(ply)
	ply.MRSdata = ply.MRSdata or {}
	ply.MRSdata.Stored = ply.MRSdata.Stored or {}

	return ply.MRSdata.Stored
end

local function groupRanks(grp)
	local g = MRS.Ranks[grp]
	return g and istable(g.ranks) and g.ranks or nil
end

local function rankData(grp, rank)
	local ranks = groupRanks(grp)
	return ranks and ranks[rank] or nil
end

-- ранг в пределах группы; nil - группы нет или в ней нет рангов
local function clampRank(grp, rank)
	local ranks = groupRanks(grp)
	if not ranks or #ranks < 1 then return nil end

	return math.Clamp(math.floor(tonumber(rank) or 1), 1, #ranks)
end

local function storedRank(ply, grp)
	local v = stored(ply)[grp]
	return istable(v) and tonumber(v.rank) or nil
end

--[[---------------------------------------------------------------------------
	Сеть: данные игроков (форматы - как у клиента в sh_player.lua)
---------------------------------------------------------------------------]]
local function writePData(id, value, ent)
	net.Start("MRS.SetPData")
	net.WriteString(id)
	net.WriteString((value == nil or value == false) and "" or tostring(value))
	net.WriteEntity(ent or NULL)
end

function MRS.SetNWdata(ply, id, value)
	ply.MRSdata = ply.MRSdata or {}
	ply.MRSdata[id] = value

	writePData(id, value, ply)
	net.Broadcast()
end

function MRS.SetSelfNWdata(ply, id, value)
	ply.MRSdata_self = ply.MRSdata_self or {}
	ply.MRSdata_self[id] = value

	writePData(id, value, NULL)
	net.Send(ply)
end

function MRS.SendDataToClient(data, ply)
	local cd, bn = MRS.TableCompress(data)

	if not cd or not bn or bn > MAX_NET_DATA then
		print("[MRS] Данные не отправлены: слишком большой объём")
		return
	end

	net.Start("MRS.GetBigData")
	net.WriteUInt(bn, 32)
	net.WriteData(cd, bn)

	if ply then
		net.Send(ply)
	else
		net.Broadcast()
	end
end

-- все данные игрока - только ему самому
local function sendOwn(ply)
	MRS.SendDataToClient({
		isplayerdata = ply:UserID(),
		index = "none",
		data = ply.MRSdata or {}
	}, ply)
end

local function sendStored(ply, key)
	MRS.SendDataToClient({
		isplayerdata = ply:UserID(),
		index = key,
		data = stored(ply)[key]
	}, ply)
end

--[[---------------------------------------------------------------------------
	Бонусы ранга и группа по профессии
---------------------------------------------------------------------------]]
local function revokeStats(ply)
	local applied = ply.MRSStats
	ply.MRSStats = nil

	if not applied then return end

	for id in pairs(applied) do
		local stat = MRS.PlayerStats[id]
		if stat and stat.revoke then stat.revoke(ply) end
	end
end

local function applyStats(ply, grp, rank)
	local data = rankData(grp, rank)
	if not data or not istable(data.stats) then return end

	local applied = {}

	for _, st in ipairs(data.stats) do
		local stat = istable(st) and isstring(st.id) and MRS.PlayerStats[st.id]

		-- check() == true - бонус недоступен (как в sh_init.lua)
		if stat and stat.apply and not applied[st.id] and not (stat.check and stat.check()) then
			stat.apply(ply, istable(st.data) and st.data or {})
			applied[st.id] = true
		end
	end

	if next(applied) then ply.MRSStats = applied end
end

-- MRS.Config.ChangeJobName: ранг в названии профессии (формат - MRS.NameFormats)
local function updateJobName(ply, grp, rank)
	if not MRS.Config.ChangeJobName then return end

	local job = team.GetName(ply:Team())
	local data = grp and rankData(grp, rank)

	if data then
		if MRS.Config.SetAsPrefix then
			local sn = data.srt_name
			local label = (MRS.Ranks[grp].show_sn and isstring(sn) and sn ~= "") and sn or data.name
			local fmt = MRS.NameFormats[MRS.Config.PlayerNameFormat] or "{0} {1}"

			job = (MRS.StringFormat(fmt, label, job))
		else
			job = data.name
		end
	end

	ply:updateJob(job)
end

local function refresh(ply, teamChanged)
	if not IsValid(ply) or not ply.MRSLoaded then return end

	local grp = MRS.GetPlayerGroup(ply:Team())
	local rank = grp and clampRank(grp, storedRank(ply, grp) or 1)
	if not rank then grp = nil end

	-- новая профессия: DarkRP уже поставил её зарплату, старая база бонуса не нужна
	if teamChanged and ply.MRSStats and ply.MRSStats["Salary bonus"] then
		MRS.SetSelfNWdata(ply, "SalaryBonus", ply:getDarkRPVar("salary"))
	end

	revokeStats(ply)

	if MRS.GetNWdata(ply, "Group") ~= (grp or false) then
		MRS.SetNWdata(ply, "Group", grp)
	end

	if MRS.GetNWdata(ply, "Rank") ~= (rank or false) then
		MRS.SetNWdata(ply, "Rank", rank)
	end

	if grp then applyStats(ply, grp, rank) end

	updateJobName(ply, grp, rank)
end

local function refreshAll()
	for _, ply in ipairs(player.GetAll()) do
		refresh(ply)
	end
end

--[[---------------------------------------------------------------------------
	Данные персонажа
---------------------------------------------------------------------------]]
local function savePlayer(ply)
	if not ply.MRSLoaded or ply.MRSNoSave or not ply.MRSuid then return end

	query("REPLACE INTO mrs_players (uid, steamid, slot, name, data, updated) VALUES (" ..
		sqlStr(ply.MRSuid) .. ", " .. sqlStr(ply:SteamID()) .. ", " ..
		math.floor(tonumber(ply.MRSSlot) or 0) .. ", " .. sqlStr(ply.MRSName or "") .. ", " ..
		sqlStr(encode(stored(ply))) .. ", " .. os.time() .. ")")
end

local function loadPlayer(ply)
	local token = {}

	ply.MRSLoadToken = token
	ply.MRSLoaded = false
	ply.MRSuid = MRS.PlayerID(ply)
	ply.MRSSlot = ply:getDarkRPVar("character")
	ply.MRSName = ply.FullName and ply:FullName() or ply:Nick()
	ply.MRSNoSave = ply:IsBot()

	local function done(data, failed)
		if not IsValid(ply) or ply.MRSLoadToken ~= token then return end

		ply.MRSdata = {Stored = data}
		ply.MRSLoaded = true

		-- ошибка чтения: не затирать сохранённое пустыми данными
		if failed then ply.MRSNoSave = true end

		refresh(ply, true)
		sendOwn(ply)
	end

	if ply.MRSNoSave then
		done({})
		return
	end

	query("SELECT data FROM mrs_players WHERE uid = " .. sqlStr(ply.MRSuid), function(rows)
		done(istable(rows) and rows[1] and decode(rows[1].data) or {})
	end, function()
		done({}, true)
	end)
end

local function unloadPlayer(ply)
	revokeStats(ply)

	ply.MRSLoadToken = nil
	ply.MRSLoaded = false
	ply.MRSuid = nil

	if MRS.GetNWdata(ply, "Group") then MRS.SetNWdata(ply, "Group", nil) end
	if MRS.GetNWdata(ply, "Rank") then MRS.SetNWdata(ply, "Rank", nil) end

	ply.MRSdata = {Stored = {}}
	sendOwn(ply)
end

hook.Add("MCR.CharacterSelected", "MRS.LoadPlayer", function(ply)
	loadPlayer(ply)
end)

hook.Add("MCR.CharacterReset", "MRS.ResetPlayer", function(ply)
	unloadPlayer(ply)
end)

-- после смены профессии DarkRP уже выставил зарплату и прочее - через тик
hook.Add("OnPlayerChangedTeam", "MRS.Job", function(ply)
	if not ply.MRSLoaded then return end

	timer.Simple(0, function()
		refresh(ply, true)
	end)
end)

-- боты персонажа не выбирают: ранги на время сессии, без записи в базу
hook.Add("PlayerInitialSpawn", "MRS.Bots", function(ply)
	if not ply:IsBot() then return end

	timer.Simple(1, function()
		if IsValid(ply) and not ply.MRSLoaded then loadPlayer(ply) end
	end)
end)

hook.Add("PlayerDisconnected", "MRS.Clean", function(ply)
	ply.MRSLoadToken = nil
end)

--[[---------------------------------------------------------------------------
	Ранги игроков
---------------------------------------------------------------------------]]
function MRS.SetPlayerRank(ply, grp, rank, silent)
	if not IsValid(ply) or not ply:IsPlayer() or not ply.MRSLoaded or not isstring(grp) then return false end

	rank = clampRank(grp, rank)
	if not rank then return false end

	local old = storedRank(ply, grp)
	if old == rank then return true end

	stored(ply)[grp] = {rank = rank, time = os.time()}
	savePlayer(ply)
	sendStored(ply, grp)
	refresh(ply)

	old = old or 1

	if not silent and rank ~= old then
		say(ply, (rank > old and "Вы повышены: " or "Вы понижены: ") .. rankData(grp, rank).name .. " (" .. grp .. ")", rank > old and 0 or 1)
	end

	hook.Run("MRS.PlayerRankChanged", ply, grp, rank, old)

	return true
end

-- метки персонажа (экзамены и др.); название группы - это ранг в ней
function MRS.SetNWStoredData(ply, key, value)
	if not IsValid(ply) or not ply.MRSLoaded or not isstring(key) or key == "" then return false end

	if MRS.Ranks[key] then
		return MRS.SetPlayerRank(ply, key, tonumber(value) or 1)
	end

	if isstring(value) then
		if value == "" then
			value = nil
		elseif tonumber(value) then
			value = tonumber(value)
		end
	end

	stored(ply)[key] = value
	savePlayer(ply)
	sendStored(ply, key)

	return true
end

-- администратор - любой ранг; иначе только своей группе, ниже своего ранга,
-- повышать - can_promote, понижать - can_demote
local function canSet(ply, target, grp, rank)
	if isAdmin(ply) then return true end
	if ply == target then return false end
	if MRS.GetNWdata(ply, "Group") ~= grp then return false end

	local my = tonumber(MRS.GetNWdata(ply, "Rank")) or 0
	local data = rankData(grp, my)
	if not data then return false end

	local cur = MRS.GetPlyRank(target, grp)
	if cur >= my or rank >= my then return false end

	if rank > cur then return data.can_promote == true end
	if rank < cur then return data.can_demote == true end

	return false
end

local function setRankBy(ply, target, grp, rank)
	if not target.MRSLoaded then
		say(ply, "Игрок ещё не выбрал персонажа", 1)
		return
	end

	if MRS.GetPlyRank(target, grp) == rank then
		say(ply, "Ранг не изменился", 1)
		return
	end

	if not canSet(ply, target, grp, rank) then
		say(ply, "Отказ в доступе", 1)
		return
	end

	if MRS.SetPlayerRank(target, grp, rank) then
		say(ply, target:Nick() .. ": " .. rankData(grp, rank).name .. " (" .. grp .. ")", 0)
	end
end

-- mrs_setrank <UserID> <группа> <ранг> - меню рангов и редактор; группа может быть с пробелами
concommand.Add("mrs_setrank", function(ply, _, args)
	if spam(ply, "setrank", 0.3) or not istable(args) or #args < 3 then return end

	local target = Player(tonumber(args[1]) or -1)
	local grp = table.concat(args, " ", 2, #args - 1)

	if not IsValid(target) or not MRS.Ranks[grp] then return end

	local rank = clampRank(grp, tonumber(args[#args]))
	if not rank then return end

	setRankBy(ply, target, grp, rank)
end)

local function findTarget(ply, arg)
	if istable(arg) then arg = table.concat(arg, " ") end
	arg = string.Trim(tostring(arg or ""))

	if arg ~= "" then return MRS.FindPlayer(arg) end

	local ent = ply:GetEyeTrace().Entity
	if IsValid(ent) and ent:IsPlayer() and ent:GetPos():DistToSqr(ply:GetPos()) <= LOOK_DIST * LOOK_DIST then
		return ent
	end
end

local function stepRank(ply, arg, dir)
	local target = findTarget(ply, arg)

	if not IsValid(target) then
		say(ply, "Игрок не найден", 1)
		return ""
	end

	-- администратор - в группе игрока, остальные - в своей
	local grp = isAdmin(ply) and MRS.GetNWdata(target, "Group") or MRS.GetNWdata(ply, "Group")

	if not grp or not MRS.Ranks[grp] then
		say(ply, "Нет группы рангов", 1)
		return ""
	end

	local rank = clampRank(grp, MRS.GetPlyRank(target, grp) + dir)
	if rank then setRankBy(ply, target, grp, rank) end

	return ""
end

local function openMenu(ply)
	local promote, demote = MRS.RankPermissions(ply)

	if not promote and not demote then
		say(ply, "Отказ в доступе", 1)
		return ""
	end

	net.Start("MRS.OpenEditor")
	net.Send(ply)

	return ""
end

-- команды из MRS.Config (CommanOpen, CommanPromote, CommanDemote)
local commands = {}

local function commandName(name)
	name = string.lower((string.gsub(tostring(name or ""), "^[/!]", "")))
	return name ~= "" and name or nil
end

local function registerCommands()
	local list = DarkRP.chatCommands or {}

	for name, fn in pairs(commands) do
		if list[name] and list[name].callback == fn then list[name] = nil end
	end

	commands = {}

	local function add(name, fn)
		name = commandName(name)
		if not name then return end

		commands[name] = fn
		DarkRP.defineChatCommand(name, fn, 1)
	end

	add(MRS.Config.CommanOpen or "/mrs", function(ply)
		return openMenu(ply)
	end)

	add(MRS.Config.CommanPromote or "/promote", function(ply, arg)
		return stepRank(ply, arg, 1)
	end)

	add(MRS.Config.CommanDemote or "/demote", function(ply, arg)
		return stepRank(ply, arg, -1)
	end)
end

registerCommands()
hook.Add("MRS.Hook.PostConfigLoad", "MRS.Commands", registerCommands)

--[[---------------------------------------------------------------------------
	Группы рангов
---------------------------------------------------------------------------]]
local function cleanRank(r)
	if not istable(r) then return nil end

	local name = text(r.name, 64)
	if not name or string.Trim(name) == "" then return nil end

	local stats = {}

	if istable(r.stats) then
		for _, st in ipairs(r.stats) do
			if istable(st) and isstring(st.id) and MRS.PlayerStats[st.id] then
				stats[#stats + 1] = {id = st.id, data = istable(st.data) and st.data or {}}
			end
		end
	end

	r.name = name
	r.srt_name = text(r.srt_name, 32) or ""
	r.icon = text(r.icon, MAX_TEXT) or ""
	r.hidden = tobool(r.hidden)
	r.can_promote = tobool(r.can_promote)
	r.can_demote = tobool(r.can_demote)
	r.stats = stats

	return r
end

local function cleanGroup(g)
	if not istable(g) then return nil end

	local id = text(g.id, 64)
	if not id or string.Trim(id) == "" or not MRS.CheckID(id) then return nil end

	local jobs, count = {}, 0

	if istable(g.job) then
		for name, on in pairs(g.job) do
			if isstring(name) and on and count < MAX_JOBS then
				jobs[name] = true
				count = count + 1
			end
		end
	end

	local ranks = {}

	if istable(g.ranks) then
		for i = 1, math.min(#g.ranks, MAX_RANKS) do
			local r = cleanRank(g.ranks[i])
			if r then ranks[#ranks + 1] = r end
		end
	end

	g.id = id
	g.oldid = nil
	g.job = jobs
	g.ranks = ranks
	g.icon = text(g.icon, MAX_TEXT)
	g.urlicon = tobool(g.urlicon)
	g.cansee = tobool(g.cansee)
	g.show_sn = tobool(g.show_sn)

	return g
end

local function saveGroup(id)
	query("REPLACE INTO mrs_groups (id, data) VALUES (" .. sqlStr(id) .. ", " .. sqlStr(encode(MRS.Ranks[id])) .. ")")
end

local function sendGroup(id)
	net.Start("MRS.RanksUpdate")
	net.WriteString(id)
	net.WriteTable(MRS.Ranks[id])
	net.Broadcast()
end

-- ранги игроков в этой группе остаются в их данных: группа с тем же названием их вернёт
local function removeGroup(id)
	MRS.Ranks[id] = nil
	query("DELETE FROM mrs_groups WHERE id = " .. sqlStr(id))

	net.Start("MRS.RanksRemove")
	net.WriteString(id)
	net.Broadcast()
end

-- переименование в редакторе (oldid): ранги игроков в сети переходят на новое название
local function renameGroup(oldid, id)
	for _, ply in ipairs(player.GetAll()) do
		local st = ply.MRSLoaded and stored(ply)

		if st and st[oldid] ~= nil and st[id] == nil then
			st[id] = st[oldid]
			st[oldid] = nil
			savePlayer(ply)
			sendOwn(ply)
		end
	end

	removeGroup(oldid)
end

net.Receive("MRS.RanksSubmit", function(_, ply)
	if not isAdmin(ply) or spam(ply, "submit", 0.5) then return end

	local bn = net.ReadUInt(32)
	if bn < 1 or bn > MAX_NET_DATA then return end

	local ok, g = pcall(MRS.TableDecompress, net.ReadData(bn))
	local oldid = ok and istable(g) and text(g.oldid, 64) or nil

	g = ok and cleanGroup(g) or nil

	if not g then
		say(ply, "Группа не сохранена: неверные данные", 1)
		return
	end

	local id = g.id

	if oldid and oldid ~= id and MRS.Ranks[oldid] then
		if MRS.Ranks[id] then
			say(ply, "Группа «" .. id .. "» уже есть", 1)
			return
		end

		renameGroup(oldid, id)
	end

	MRS.Ranks[id] = g
	saveGroup(id)
	sendGroup(id)
	refreshAll()

	say(ply, "Группа «" .. id .. "» сохранена", 0)
end)

net.Receive("MRS.RanksRemove", function(_, ply)
	if not isAdmin(ply) or spam(ply, "remove", 0.5) then return end

	local id = net.ReadString()
	if not MRS.Ranks[id] then return end

	removeGroup(id)
	refreshAll()

	say(ply, "Группа «" .. id .. "» удалена", 0)
end)

--[[---------------------------------------------------------------------------
	Запросы клиента при загрузке
---------------------------------------------------------------------------]]
net.Receive("MRS.DataShare", function(_, ply)
	if spam(ply, "share", 3) then return end

	-- группы ещё не загружены - придут всем после загрузки
	if MRS.RanksLoaded then MRS.DataShare(ply) end
end)

net.Receive("MRS.GetPData", function(_, ply)
	if spam(ply, "pdata", 3) then return end

	for _, p in ipairs(player.GetAll()) do
		local d = p ~= ply and p.MRSdata

		if d then
			if d.Group then
				writePData("Group", d.Group, p)
				net.Send(ply)
			end

			if d.Rank then
				writePData("Rank", d.Rank, p)
				net.Send(ply)
			end
		end
	end

	if ply.MRSLoaded then sendOwn(ply) end

	for id, value in pairs(ply.MRSdata_self or {}) do
		writePData(id, value, NULL)
		net.Send(ply)
	end
end)

--[[---------------------------------------------------------------------------
	Редактор: ранги персонажей (в сети и нет)
	Ключ - SteamID (STEAM_0:1:123 или SteamID64): последний персонаж игрока;
	STEAM_0:1:123#2 - персонаж в слоте 2.
---------------------------------------------------------------------------]]
local function parseKey(key)
	key = string.Trim(tostring(key or ""))

	local sid, slot = string.match(key, "^(STEAM_%d:%d:%d+)#?(%d*)$")

	if not sid and string.match(key, "^7656%d+$") then
		sid, slot = util.SteamIDFrom64(key), ""
	end

	if not sid or sid == "STEAM_0:0:0" then return nil end

	return "STEAM_0" .. string.sub(sid, 8), tonumber(slot)
end

-- callback(игрок в сети на этом персонаже) или callback(nil, uid, данные) или callback()
local function findCharacter(key, callback)
	local sid, slot = parseKey(key)
	if not sid then return callback() end

	local ply = player.GetBySteamID(sid)

	if IsValid(ply) and ply.MRSLoaded and (not slot or slot == tonumber(ply.MRSSlot)) then
		return callback(ply)
	end

	query("SELECT uid, data FROM mrs_players WHERE steamid = " .. sqlStr(sid) ..
		(slot and (" AND slot = " .. slot) or "") .. " ORDER BY updated DESC LIMIT 1", function(rows)
		local row = istable(rows) and rows[1]

		if row then
			callback(nil, row.uid, decode(row.data))
		else
			callback()
		end
	end, function()
		callback()
	end)
end

-- UInt32 количество, затем (String группа, UInt32 ранг, UInt32 время)
local function writeRanks(st)
	local list = {}

	for grp, v in pairs(st) do
		if MRS.Ranks[grp] and istable(v) then list[#list + 1] = {grp, v} end
	end

	net.WriteUInt(#list, 32)

	for _, e in ipairs(list) do
		net.WriteString(e[1])
		net.WriteUInt(math.max(1, math.floor(tonumber(e[2].rank) or 1)), 32)
		net.WriteUInt(math.max(0, math.floor(tonumber(e[2].time) or 0)), 32)
	end
end

net.Receive("MRS.GetPlayersRanks", function(_, ply)
	if not isAdmin(ply) or spam(ply, "offline", 1) then return end

	local key = string.Trim(net.ReadString())
	if key == "" or #key > 64 then return end

	findCharacter(key, function(online, _, data)
		if not IsValid(ply) then return end

		local st = IsValid(online) and stored(online) or data

		if not st then
			say(ply, "Персонаж не найден: " .. key, 1)
			return
		end

		net.Start("MRS.GetPlayersRanks")
		net.WriteString(key)
		writeRanks(st)
		net.Send(ply)
	end)
end)

net.Receive("MRS.SavePlayerRankList", function(_, ply)
	if not isAdmin(ply) or spam(ply, "offsave", 0.3) then return end

	local key, grp, rank = net.ReadString(), net.ReadString(), net.ReadUInt(32)

	rank = MRS.Ranks[grp] and clampRank(grp, rank)
	if not rank or #key > 64 then return end

	findCharacter(key, function(online, uid, data)
		if IsValid(online) then
			MRS.SetPlayerRank(online, grp, rank)
		elseif uid then
			data[grp] = {rank = rank, time = os.time()}
			query("UPDATE mrs_players SET data = " .. sqlStr(encode(data)) .. " WHERE uid = " .. sqlStr(uid))
		else
			say(ply, "Персонаж не найден: " .. key, 1)
			return
		end

		say(ply, key .. ": " .. rankData(grp, rank).name .. " (" .. grp .. ")", 0)
	end)
end)

net.Receive("MRS.RequestStoredData", function(_, ply)
	if not isAdmin(ply) or spam(ply, "stored", 0.3) then return end

	local target = Player(net.ReadUInt(32))
	if not IsValid(target) then return end

	net.Start("MRS.RequestStoredData")
	net.WriteEntity(target)
	writeRanks(stored(target))
	net.Send(ply)
end)

--[[---------------------------------------------------------------------------
	Группы по умолчанию - создаются один раз, если в базе групп ещё нет.
	Ранги подобраны под проверки сборки: NYPD - патруль 3-4, «В штатском» 5+,
	«Cупервайзер» 6+, рация COM 6+, китель 8+, фуражки 6-10 и 11+; FDNY -
	1 EMT, препараты 3+, «Инспектор» 4+, без лимитов профессий 7+; в группах
	NYPD ESU, NYPD Traffic, FBI, NYC LD профессия - с ранга 2. Названия,
	состав и права (can_promote/can_demote) меняются в редакторе.
---------------------------------------------------------------------------]]
local function jobsOf(list)
	local jobs = {}

	for _, var in ipairs(list) do
		local t = _G[var]
		local name = isnumber(t) and team.GetName(t)

		if isstring(name) and name ~= "" then jobs[name] = true end
	end

	return jobs
end

local function ranksOf(list, manage)
	local ranks = {}

	for i, r in ipairs(list) do
		ranks[i] = {
			name = r[1],
			srt_name = r[2],
			icon = "",
			hidden = false,
			can_promote = i >= manage,
			can_demote = i >= manage,
			stats = {}
		}
	end

	return ranks
end

local function newGroup(id, jobs, ranks, manage)
	return {
		id = id,
		job = jobsOf(jobs),
		icon = "",
		urlicon = true,
		cansee = true,
		show_sn = false,
		ranks = ranksOf(ranks, manage)
	}
end

local function defaultGroups()
	return {
		["NYPD"] = newGroup("NYPD", {"TEAM_WARDEN", "TEAM_POLICE", "TEAM_DETECTIVE", "TEAM_POLICESV"}, {
			{"Кадет", "CDT"}, {"Стажёр", "PPO"}, {"Офицер полиции", "PO"}, {"Старший офицер", "SPO"},
			{"Детектив", "DET"}, {"Сержант", "SGT"}, {"Лейтенант", "LT"}, {"Капитан", "CPT"},
			{"Заместитель инспектора", "DI"}, {"Инспектор", "INSP"}, {"Заместитель шефа", "DC"},
			{"Шеф департамента", "COD"}, {"Комиссар", "PC"}
		}, 7),
		["NYPD ESU"] = newGroup("NYPD ESU", {"TEAM_SWAT", "TEAM_FBISWAT"}, {
			{"Кандидат", "CND"}, {"Оперативник", "OPR"}, {"Старший оперативник", "SOP"}, {"Командир ESU", "CMD"}
		}, 4),
		["NYPD Traffic"] = newGroup("NYPD Traffic", {"TEAM_TRAFFIC"}, {
			{"Кандидат", "CND"}, {"Сотрудник дорожной службы", "TEA"}, {"Старший смены", "SUP"}
		}, 3),
		["FBI"] = newGroup("FBI", {"TEAM_FBI"}, {
			{"Кандидат", "CND"}, {"Агент", "SA"}, {"Старший агент", "SSA"}, {"Руководитель отделения", "SAC"}
		}, 4),
		["FDNY"] = newGroup("FDNY", {"TEAM_REF", "TEAM_FIREFIGHTER", "TEAM_INS"}, {
			{"EMT", "EMT"}, {"Пожарный", "FF"}, {"Парамедик", "PM"}, {"Инспектор", "INS"},
			{"Лейтенант", "LT"}, {"Капитан", "CPT"}, {"Командир батальона", "BC"}, {"Шеф департамента", "COD"}
		}, 7),
		["NYC LD"] = newGroup("NYC LD", {"TEAM_LAWYER"}, {
			{"Стажёр", "INT"}, {"Юрист", "ATT"}, {"Старший юрист", "SA"}
		}, 3)
	}
end

--[[---------------------------------------------------------------------------
	База
---------------------------------------------------------------------------]]
local function applyGroups(groups)
	for id in pairs(MRS.Ranks) do
		MRS.Ranks[id] = nil
	end

	for id, g in pairs(groups) do
		MRS.Ranks[id] = g
	end

	MRS.RanksLoaded = true
	MRS.SendDataToClient({index = "Ranks", data = MRS.Ranks})
	refreshAll()

	hook.Run("MRS.RanksLoaded")
end

local function seedGroups()
	query("SELECT name FROM mrs_meta WHERE name = 'seeded'", function(rows)
		-- группы уже создавались и администратор удалил все - не возвращать
		if istable(rows) and rows[1] then
			applyGroups({})
			return
		end

		local groups = defaultGroups()
		applyGroups(groups)

		for id in pairs(groups) do
			saveGroup(id)
		end

		query("REPLACE INTO mrs_meta (name) VALUES ('seeded')")
		print("[MRS] Созданы группы рангов по умолчанию")
	end, function()
		applyGroups(defaultGroups())
	end)
end

local function loadGroups()
	query("SELECT id, data FROM mrs_groups", function(rows)
		local groups = {}

		for _, row in ipairs(istable(rows) and rows or {}) do
			local g = decode(row.data)
			g.id = row.id
			g = cleanGroup(g)

			if g then groups[g.id] = g end
		end

		if not next(groups) then
			seedGroups()
			return
		end

		query("REPLACE INTO mrs_meta (name) VALUES ('seeded')")
		applyGroups(groups)
	end, function()
		-- база не читается: группы по умолчанию только в памяти, без записи
		applyGroups(defaultGroups())
	end)
end

local function startDB()
	if MRS.DBStarted then return end
	MRS.DBStarted = true

	local list = {
		[[CREATE TABLE IF NOT EXISTS mrs_groups(
			id VARCHAR(64) NOT NULL PRIMARY KEY,
			data TEXT NOT NULL
		)]],
		[[CREATE TABLE IF NOT EXISTS mrs_players(
			uid VARCHAR(64) NOT NULL PRIMARY KEY,
			steamid VARCHAR(32) NOT NULL,
			slot INTEGER NOT NULL,
			name VARCHAR(128),
			data TEXT NOT NULL,
			updated BIGINT NOT NULL
		)]],
		[[CREATE TABLE IF NOT EXISTS mrs_meta(
			name VARCHAR(64) NOT NULL PRIMARY KEY
		)]]
	}

	local i = 0

	local function step()
		i = i + 1

		if list[i] then
			query(list[i], step, step)
		else
			loadGroups()
		end
	end

	step()
end

hook.Add("DatabaseInitialized", "MRS.Ranks", startDB)
