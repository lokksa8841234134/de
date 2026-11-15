--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	sAdmin: ранги, данные игроков, ограничения параметров (SQL через slib.db)

	Таблицы:
		sadmin_usergroups  - name, permissions (JSON)
		sadmin_players     - sid64, name, usergroup, rank_expire, playtime, last_join
		sadmin_paramlimits - usergroup, command, data (JSON)

	sAdmin.setRank(ply, rank, time)                   - ранг игроку (time в секундах, 0 - навсегда)
	sAdmin.updatePlayerRank(sid64, rank, time)        - ранг по SteamID64, в том числе оффлайн
	sAdmin.updatePlayerSessionEnd(ply)                - сохранить игрока и разослать его данные
	sAdmin.mcTime(ply)                                - наигранное время (как на клиенте)
	sAdmin.hasReservedSlot(sid64)                     - доступ к резервным слотам
	sAdmin.saveParameterLimitations(rank, name, data) - ограничения параметров команды для ранга
---------------------------------------------------------------------------]]
sAdmin = sAdmin or {}
sAdmin.usergroups = sAdmin.usergroups or {}
sAdmin.playerData = sAdmin.playerData or {}
sAdmin.ParameterLimitations = sAdmin.ParameterLimitations or {}
sAdmin.netHandlers = sAdmin.netHandlers or {}

-- стандартная выдача групп из settings/users.txt перезаписала бы ранги sAdmin
hook.Remove("PlayerInitialSpawn", "PlayerAuthSpawn")

local PAGE_SIZE = 20
local SAVE_INTERVAL = 300
local MAX_INT = 2 ^ 53

-- ранги, без которых не работают проверки IsAdmin/IsSuperAdmin и CAMI
local PROTECTED_RANKS = {
	["user"] = true,
	["admin"] = true,
	["superadmin"] = true
}

local ADMIN_COMMANDS = {
	"kick", "ban", "banid", "unban", "checkban", "jail", "unjail",
	"mute", "unmute", "unmuteid", "gag", "ungag",
	"warn", "warnid", "notice", "noticeid", "pm", "dm", "asay",
	"goto", "bring", "return", "tp", "teleport", "noclip", "cloak", "uncloak",
	"god", "ungod", "freeze", "unfreeze", "slay", "respawn", "spectate", "unspectate",
	"screengrab", "hp", "armor", "stopsound", "cleardecals",
	"revive", "slr", "ragdoll", "unragdoll", "exitvehicle", "extinguish",
	"stopnlr", "unwanted", "gotobody", "gotocar", "enttp", "entremove",
	"local_remove", "removefood", "removejunk"
}

local rankCache = {}    -- sid64 -> {rank, expire}: ранги выше user, для резервных слотов
local pendingRanks = {} -- sid64 -> {rank, expire}: ранг выдан, пока игрок загружался
local groupsLoaded = false

local esc = slib.dbEscape

local function int(value)
	local n = tonumber(value) or 0
	if n ~= n then n = 0 end

	return string.format("%.0f", math.floor(math.Clamp(n, -MAX_INT, MAX_INT)))
end

local function isSID64(sid64)
	return isstring(sid64) and #sid64 == 17 and string.match(sid64, "^7656119%d+$") ~= nil
end

local function isSuper(ply)
	return not IsValid(ply) or sAdmin.config["super_users"][ply:SteamID64()] == true
end

local function canManage(ply)
	return isSuper(ply) or tobool(sAdmin.hasPermission(ply, "manage_perms"))
end

local function immunityOf(rank)
	local group = sAdmin.usergroups[rank]

	return group and group.permissions and tonumber(group.permissions["immunity"]) or 0
end

local function ownImmunity(ply)
	return tonumber(sAdmin.hasPermission(ply, "immunity")) or 0
end

-- имя для базы: валидный UTF-8 без 4-байтовых символов (utf8 в MySQL их не принимает)
local function cleanName(name)
	name = utf8.force(tostring(name or ""))
	name = string.gsub(name, "[\240-\247][\128-\191][\128-\191][\128-\191]", "")

	return utf8.sub(name, 1, 64)
end

local function log(ply, text, value)
	if DarkRP and DarkRP.log then
		DarkRP.log("admin", IsValid(ply) and ply or nil, nil, text, nil, value)
	end
end

--[[---------------------------------------------------------------------------
	Ранги по умолчанию
---------------------------------------------------------------------------]]
local function defaultRanks()
	local admin = {
		immunity = 50,
		menu = true,
		silent = true,
		is_staff = true,
		rslots = true,
		can_log = true,
		FSpectate = true,
		FSpectateTeleport = true,
		phys_players = true,
		-- права FPP (CAMI) - всем рангам администрации, ваш ответ к 14
		FPP_Settings = true,
		FPP_Cleanup = true,
		FPP_TouchOtherPlayersProps = true
	}

	for _, name in ipairs(ADMIN_COMMANDS) do
		admin[name] = true
	end

	return {
		["user"] = {permissions = {immunity = 0, dm = true}},
		["admin"] = {permissions = admin},
		["superadmin"] = {permissions = {
			immunity = 100,
			all_perms = true,
			manage_perms = true,
			menu = true,
			silent = true,
			is_staff = true,
			rslots = true,
			weapon_upgrade = true,
			phys_players = true,
			propspawn = true,
			can_log = true,
			FSpectate = true,
			FSpectateTeleport = true,
			FPP_Settings = true,
			FPP_Cleanup = true,
			FPP_TouchOtherPlayersProps = true
		}}
	}
end

-- до загрузки из базы работают ранги по умолчанию
if table.IsEmpty(sAdmin.usergroups) then
	for name, data in pairs(defaultRanks()) do
		sAdmin.usergroups[name] = data
	end
end

--[[---------------------------------------------------------------------------
	Сохранение
---------------------------------------------------------------------------]]
local function saveGroup(name)
	local group = sAdmin.usergroups[name]
	if not group then return end

	slib.dbQuery("REPLACE INTO sadmin_usergroups (name, permissions) VALUES (" .. esc(name) .. ", " .. esc(util.TableToJSON(group.permissions or {}) or "{}") .. ")")
end

local function setCache(sid64, rank, expire)
	if rank == "user" then
		rankCache[sid64] = nil
	else
		rankCache[sid64] = {rank = rank, expire = tonumber(expire) or 0}
	end
end

local function expireFor(rank, time)
	time = math.floor(tonumber(time) or 0)
	if rank == "user" or time <= 0 then return 0 end

	return os.time() + time
end

local function applyRank(ply, rank)
	local old = ply:GetUserGroup()
	if old == rank then return end

	ply:SetUserGroup(rank)

	if CAMI and CAMI.SignalUserGroupChanged then
		CAMI.SignalUserGroupChanged(ply, old, rank, "sAdmin")
	end
end

sAdmin.mcTime = function(ply)
	if not IsValid(ply) or not ply.getDarkRPVar then return 0 end

	local t1 = tonumber(ply:getDarkRPVar("playtime")) or 0
	local t2 = tonumber(ply:getDarkRPVar("synctime")) or CurTime()

	return math.max(0, math.Round(t1 + (CurTime() - t2)))
end

local function savePlayerRow(ply)
	if not IsValid(ply) or ply:IsBot() then return end

	local sid64 = ply:SteamID64()
	local data = sid64 and sAdmin.playerData[sid64]

	-- readonly: данные не прочитались из базы, перезаписывать их нельзя
	if not data or not data.loaded or data.readonly then return end

	local values = table.concat({
		esc(sid64),
		esc(cleanName(ply:SteamName())),
		esc(data.rank),
		int(data.rank_expire),
		int(sAdmin.mcTime(ply)),
		int(os.time())
	}, ", ")

	slib.dbQuery("REPLACE INTO sadmin_players (sid64, name, usergroup, rank_expire, playtime, last_join) VALUES (" .. values .. ")")
end

-- данные игрока клиентам: по одной записи, таблицы с ключами SteamID64 целиком не отправляются
local function networkPlayer(ply, target)
	if not IsValid(ply) then return end

	local sid64 = ply:SteamID64()
	local data = sid64 and sAdmin.playerData[sid64]
	if not data then return end

	sAdmin.networkData(target, {"playerData", sid64}, {
		rank = data.rank,
		rank_expire = data.rank_expire,
		playtime = data.playtime,
		synctime = data.synctime
	})
end

sAdmin.updatePlayerSessionEnd = function(ply)
	savePlayerRow(ply)
	networkPlayer(ply)
end

--[[---------------------------------------------------------------------------
	Загрузка игрока
---------------------------------------------------------------------------]]
local function finishLoad(ply, row, readonly)
	local sid64 = ply:SteamID64()
	local rank = row and row.usergroup or "user"
	local expire = row and tonumber(row.rank_expire) or 0
	local playtime = row and tonumber(row.playtime) or 0

	local pending = pendingRanks[sid64]

	if pending then
		rank, expire = pending.rank, pending.expire
		pendingRanks[sid64] = nil
	end

	if not sAdmin.usergroups[rank] or (expire > 0 and expire <= os.time()) then
		rank, expire = "user", 0
	end

	local now = math.floor(CurTime())

	sAdmin.playerData[sid64] = {
		rank = rank,
		rank_expire = expire,
		playtime = playtime,
		synctime = now,
		loaded = true,
		readonly = readonly or nil
	}

	setCache(sid64, rank, expire)
	applyRank(ply, rank)

	ply:SetDarkRPVar("playtime", playtime)
	ply:SetDarkRPVar("synctime", now)

	savePlayerRow(ply)
	networkPlayer(ply)

	hook.Run("sA:PlayerLoaded", ply, rank)
end

local function loadPlayer(ply)
	if not groupsLoaded or not IsValid(ply) or ply.sA_Loading then return end

	local sid64 = ply:SteamID64()
	if not sid64 then return end

	local data = sAdmin.playerData[sid64]
	if data and data.loaded then return end

	if ply:IsBot() then
		finishLoad(ply, nil, true)
		return
	end

	ply.sA_Loading = true

	slib.dbQuery("SELECT usergroup, rank_expire, playtime FROM sadmin_players WHERE sid64 = " .. esc(sid64), function(rows)
		if not IsValid(ply) then return end

		ply.sA_Loading = nil
		finishLoad(ply, rows[1])
	end, function()
		if not IsValid(ply) then return end

		ply.sA_Loading = nil
		finishLoad(ply, nil, true)
	end)
end

hook.Add("PlayerInitialSpawn", "sA:LoadPlayer", function(ply)
	timer.Simple(0, function()
		if IsValid(ply) then loadPlayer(ply) end
	end)
end)

--[[---------------------------------------------------------------------------
	Выдача рангов
---------------------------------------------------------------------------]]
sAdmin.updatePlayerRank = function(sid64, rank, time)
	sid64 = tostring(sid64 or "")
	if not isSID64(sid64) or not sAdmin.usergroups[rank] then return end

	local ply = player.GetBySteamID64(sid64)
	local data = sAdmin.playerData[sid64]

	if IsValid(ply) and data and data.loaded then
		sAdmin.setRank(ply, rank, time)
		return
	end

	local expire = expireFor(rank, time)

	if IsValid(ply) then
		pendingRanks[sid64] = {rank = rank, expire = expire}
	end

	setCache(sid64, rank, expire)

	slib.dbQuery("SELECT sid64 FROM sadmin_players WHERE sid64 = " .. esc(sid64), function(rows)
		if rows[1] then
			slib.dbQuery("UPDATE sadmin_players SET usergroup = " .. esc(rank) .. ", rank_expire = " .. int(expire) .. " WHERE sid64 = " .. esc(sid64))
		else
			slib.dbQuery("INSERT INTO sadmin_players (sid64, name, usergroup, rank_expire, playtime, last_join) VALUES (" .. esc(sid64) .. ", '', " .. esc(rank) .. ", " .. int(expire) .. ", 0, 0)")
		end
	end)
end

sAdmin.setRank = function(ply, rank, time)
	if not IsValid(ply) or not sAdmin.usergroups[rank] then return end

	local sid64 = ply:SteamID64()
	if not sid64 then return end

	local data = sAdmin.playerData[sid64]

	if not data or not data.loaded then
		if not ply:IsBot() then
			sAdmin.updatePlayerRank(sid64, rank, time)
		end

		return
	end

	local expire = expireFor(rank, time)
	data.rank, data.rank_expire = rank, expire

	setCache(sid64, rank, expire)
	applyRank(ply, rank)
	savePlayerRow(ply)
	networkPlayer(ply)

	hook.Run("sA:RankChanged", ply, rank, expire)
end

sAdmin.hasReservedSlot = function(sid64)
	if sAdmin.config["reserve_slots"][sid64] or sAdmin.config["super_users"][sid64] then return true end

	local cached = rankCache[sid64]
	if not cached or (cached.expire > 0 and cached.expire <= os.time()) then return false end

	local group = sAdmin.usergroups[cached.rank]

	return group ~= nil and group.permissions ~= nil and tobool(group.permissions["rslots"])
end

timer.Create("sA:RankExpiry", 30, 0, function()
	local now = os.time()

	for _, ply in ipairs(player.GetHumans()) do
		local data = sAdmin.playerData[ply:SteamID64()]

		if data and data.loaded and data.rank ~= "user" and (tonumber(data.rank_expire) or 0) > 0 and data.rank_expire <= now then
			local old = data.rank

			sAdmin.setRank(ply, "user")
			sAdmin.msg(ply, "Срок действия ранга %s истёк.", old)
		end
	end

	for sid64, cached in pairs(rankCache) do
		if cached.expire > 0 and cached.expire <= now then
			rankCache[sid64] = nil
		end
	end
end)

--[[---------------------------------------------------------------------------
	Ранги: удаление
---------------------------------------------------------------------------]]
local function deleteRank(rank)
	sAdmin.usergroups[rank] = nil

	for _, ranks in pairs(sAdmin.ParameterLimitations) do
		ranks[rank] = nil
	end

	for sid64, cached in pairs(rankCache) do
		if cached.rank == rank then rankCache[sid64] = nil end
	end

	for sid64, pending in pairs(pendingRanks) do
		if pending.rank == rank then pendingRanks[sid64] = nil end
	end

	slib.dbQuery("DELETE FROM sadmin_usergroups WHERE name = " .. esc(rank))
	slib.dbQuery("DELETE FROM sadmin_paramlimits WHERE usergroup = " .. esc(rank))
	slib.dbQuery("UPDATE sadmin_players SET usergroup = 'user', rank_expire = 0 WHERE usergroup = " .. esc(rank))

	for _, v in ipairs(player.GetAll()) do
		local data = sAdmin.playerData[v:SteamID64()]

		if data and data.rank == rank then
			sAdmin.setRank(v, "user")
		end
	end

	if CAMI and CAMI.UnregisterUsergroup then
		CAMI.UnregisterUsergroup(rank, "sAdmin")
	end

	sAdmin.networkData(nil, {"usergroups", rank}, nil)
end

--[[---------------------------------------------------------------------------
	Ограничения параметров команд
---------------------------------------------------------------------------]]
sAdmin.saveParameterLimitations = function(rank, name, data)
	if not isstring(rank) or not isstring(name) or not istable(data) then return end
	if not sAdmin.usergroups[rank] then return end

	local cmd = sAdmin.commands[name]
	if not cmd or not istable(cmd.inputs) then return end

	local clean = {}

	for k, v in pairs(data) do
		local index = tonumber(k)
		if not index or not cmd.inputs[index] or not istable(v) then continue end

		local min = math.max(0, tonumber(v.min) or 0)
		local max = math.max(0, tonumber(v.max) or 0)

		if min == 0 and max == 0 then continue end

		clean[index] = {min = min, max = max}
	end

	sAdmin.ParameterLimitations[name] = sAdmin.ParameterLimitations[name] or {}

	if table.IsEmpty(clean) then
		sAdmin.ParameterLimitations[name][rank] = nil
		slib.dbQuery("DELETE FROM sadmin_paramlimits WHERE usergroup = " .. esc(rank) .. " AND command = " .. esc(name))

		return
	end

	sAdmin.ParameterLimitations[name][rank] = clean
	slib.dbQuery("REPLACE INTO sadmin_paramlimits (usergroup, command, data) VALUES (" .. esc(rank) .. ", " .. esc(name) .. ", " .. esc(util.TableToJSON(clean) or "{}") .. ")")
end

--[[---------------------------------------------------------------------------
	Загрузка из базы
---------------------------------------------------------------------------]]
local function runQueries(queries, done)
	local i = 0

	local function step()
		i = i + 1

		if not queries[i] then
			if done then done() end
			return
		end

		slib.dbQuery(queries[i], step, step)
	end

	step()
end

local function replaceContents(target, source)
	for k in pairs(target) do
		target[k] = nil
	end

	for k, v in pairs(source) do
		target[k] = v
	end
end

local function loadLimits(done)
	slib.dbQuery("SELECT usergroup, command, data FROM sadmin_paramlimits", function(rows)
		local limits = {}

		for _, row in ipairs(rows) do
			local data = util.JSONToTable(row.data or "")

			if istable(data) and sAdmin.usergroups[row.usergroup] then
				limits[row.command] = limits[row.command] or {}
				limits[row.command][row.usergroup] = data
			end
		end

		replaceContents(sAdmin.ParameterLimitations, limits)
		done()
	end, done)
end

local function loadRankCache(done)
	slib.dbQuery("SELECT sid64, usergroup, rank_expire FROM sadmin_players WHERE usergroup <> 'user'", function(rows)
		rankCache = {}

		for _, row in ipairs(rows) do
			if sAdmin.usergroups[row.usergroup] then
				setCache(row.sid64, row.usergroup, row.rank_expire)
			end
		end

		done()
	end, done)
end

-- persist: сохранить недостающие ранги по умолчанию (не при ошибке чтения, чтобы не затереть права)
local function applyGroups(rows, persist)
	local groups, missing = {}, {}

	for _, row in ipairs(rows) do
		local perms = util.JSONToTable(row.permissions or "")

		if isstring(row.name) and row.name ~= "" then
			groups[row.name] = {permissions = istable(perms) and perms or {}}
		end
	end

	local defaults = defaultRanks()

	for name in pairs(PROTECTED_RANKS) do
		if not groups[name] then
			groups[name] = defaults[name]
			missing[#missing + 1] = name
		end
	end

	replaceContents(sAdmin.usergroups, groups)
	groupsLoaded = true

	if persist then
		for _, name in ipairs(missing) do
			saveGroup(name)
		end
	end

	for name in pairs(sAdmin.usergroups) do
		sAdmin.registerCAMIGroup(name)
	end

	sAdmin.networkData(nil, {"usergroups"}, sAdmin.usergroups)
end

--[[---------------------------------------------------------------------------
	Права FPP рангам администрации (ваш ответ к 14: «всем, даже суперадминам»).
	В новой базе они уже в рангах по умолчанию. В базе, созданной раньше, их
	один раз выдают superadmin и каждому рангу с is_staff или all_perms;
	обычным игрокам (user) - нет. Отметка в sadmin_migrations: снятое потом в
	меню рангов после перезапуска не возвращается.
---------------------------------------------------------------------------]]
local FPP_PERMS = {"FPP_Settings", "FPP_Cleanup", "FPP_TouchOtherPlayersProps"}

local function grantFPP(done)
	slib.dbQuery("SELECT name FROM sadmin_migrations WHERE name = 'fpp_rights'", function(rows)
		if rows[1] then done() return end

		for name, group in pairs(sAdmin.usergroups) do
			local perms = group.permissions or {}

			if name == "superadmin" or tobool(perms.is_staff) or tobool(perms.all_perms) then
				for _, perm in ipairs(FPP_PERMS) do
					perms[perm] = true
				end

				group.permissions = perms
				saveGroup(name)
			end
		end

		slib.dbQuery("INSERT INTO sadmin_migrations (name) VALUES ('fpp_rights')")
		sAdmin.networkData(nil, {"usergroups"}, sAdmin.usergroups)
		done()
	end, done)
end

local function loadRest()
	loadLimits(function()
		loadRankCache(function()
			for _, ply in ipairs(player.GetAll()) do
				loadPlayer(ply)
			end

			hook.Run("sA:UsergroupsLoaded")
		end)
	end)
end

slib.onDBReady("sAdmin:data", function()
	runQueries({
		"CREATE TABLE IF NOT EXISTS sadmin_usergroups (name VARCHAR(32) NOT NULL PRIMARY KEY, permissions TEXT)",
		"CREATE TABLE IF NOT EXISTS sadmin_players (sid64 VARCHAR(20) NOT NULL PRIMARY KEY, name VARCHAR(128), usergroup VARCHAR(32) NOT NULL DEFAULT 'user', rank_expire BIGINT NOT NULL DEFAULT 0, playtime BIGINT NOT NULL DEFAULT 0, last_join BIGINT NOT NULL DEFAULT 0)",
		"CREATE TABLE IF NOT EXISTS sadmin_paramlimits (usergroup VARCHAR(32) NOT NULL, command VARCHAR(64) NOT NULL, data TEXT, PRIMARY KEY (usergroup, command))",
		"CREATE TABLE IF NOT EXISTS sadmin_migrations (name VARCHAR(64) NOT NULL PRIMARY KEY)"
	}, function()
		slib.dbQuery("SELECT name, permissions FROM sadmin_usergroups", function(rows)
			applyGroups(rows, true)
			grantFPP(loadRest)
		end, function()
			-- таблица недоступна: ранги по умолчанию только в памяти
			applyGroups({}, false)
			loadRest()
		end)
	end)
end)

--[[---------------------------------------------------------------------------
	Сохранение по таймеру, выход игрока, выключение сервера
---------------------------------------------------------------------------]]
timer.Create("sA:SavePlayers", SAVE_INTERVAL, 0, function()
	for _, ply in ipairs(player.GetHumans()) do
		savePlayerRow(ply)
	end
end)

hook.Add("PlayerDisconnected", "sA:SavePlayer", function(ply)
	local sid64 = ply:SteamID64()
	if not sid64 then return end

	savePlayerRow(ply)

	local had = sAdmin.playerData[sid64] ~= nil
	sAdmin.playerData[sid64] = nil
	pendingRanks[sid64] = nil
	ply.sA_Loading = nil

	if had then
		sAdmin.networkData(nil, {"playerData", sid64}, nil)
	end
end)

hook.Add("ShutDown", "sA:SavePlayers", function()
	for _, ply in ipairs(player.GetHumans()) do
		savePlayerRow(ply)
	end
end)

hook.Add("slib.FullLoaded", "sA:SendPlayerData", function(ply)
	sAdmin.networkData(ply, {"usergroups"}, sAdmin.usergroups)

	for _, v in ipairs(player.GetAll()) do
		networkPlayer(v, ply)
	end
end)

--[[---------------------------------------------------------------------------
	Сеть: 0 - право ранга, 1 - создание/удаление ранга
---------------------------------------------------------------------------]]
sAdmin.netHandlers[0] = function(ply)
	local rank, perm = net.ReadString(), net.ReadString()
	local data = sAdmin.getPermissiondata(perm)
	local isLimit = sAdmin.limits[perm] == true
	local numeric = isLimit or (data and data.type == 0)
	local value

	-- клиент пишет число для лимитов и прав с type 0, иначе Bool
	if numeric then
		value = net.ReadUInt(9)
	else
		value = net.ReadBool()
	end

	if not groupsLoaded then return end

	if not canManage(ply) then
		sAdmin.msg(ply, "no_permission", "manage_perms")
		return
	end

	local group = sAdmin.usergroups[rank]
	if not group or (not data and not isLimit) then return end

	if not isSuper(ply) then
		local own = ownImmunity(ply)

		if immunityOf(rank) >= own or (perm == "immunity" and value >= own) then
			sAdmin.msg(ply, "too_high_rank")
			return
		end

		if value == true and not sAdmin.hasPermission(ply, perm) then
			sAdmin.msg(ply, "no_permission", perm)
			return
		end
	end

	group.permissions = group.permissions or {}

	if numeric then
		group.permissions[perm] = math.Clamp(value, 0, 511)
	else
		group.permissions[perm] = value or nil
	end

	saveGroup(rank)

	if perm == "immunity" then
		sAdmin.registerCAMIGroup(rank)
	end

	sAdmin.networkData(nil, {"usergroups", rank, "permissions", perm}, group.permissions[perm])
	log(ply, "изменил право " .. perm .. " ранга " .. rank, tostring(group.permissions[perm] or false))
end

sAdmin.netHandlers[1] = function(ply)
	local rank = string.lower(string.Trim(net.ReadString()))
	local create = net.ReadBool()

	if not groupsLoaded then return end

	if not canManage(ply) then
		sAdmin.msg(ply, "no_permission", "manage_perms")
		return
	end

	if sAdmin.throttle(ply, "sA:EditRank", 1) then
		sAdmin.msg(ply, "request_rate_limit")
		return
	end

	if create then
		if rank == "" or #rank > 32 or not string.match(rank, "^[%w_%-]+$") or tonumber(rank) or sAdmin.usergroups[rank] then
			sAdmin.msg(ply, "invalid_usergroup")
			return
		end

		sAdmin.usergroups[rank] = {permissions = {immunity = 0}}
		saveGroup(rank)
		sAdmin.registerCAMIGroup(rank)

		sAdmin.networkData(nil, {"usergroups", rank}, sAdmin.usergroups[rank])
		log(ply, "создал ранг " .. rank)

		return
	end

	if not sAdmin.usergroups[rank] or PROTECTED_RANKS[rank] then
		sAdmin.msg(ply, "invalid_usergroup")
		return
	end

	if not isSuper(ply) and immunityOf(rank) >= ownImmunity(ply) then
		sAdmin.msg(ply, "too_high_rank")
		return
	end

	deleteRank(rank)
	log(ply, "удалил ранг " .. rank)
end

--[[---------------------------------------------------------------------------
	Сеть: 3 - данные меню, 5 - страницы списков, 6 - данные игрока
---------------------------------------------------------------------------]]
local function sendStats(ply)
	slib.dbQuery("SELECT COUNT(*) AS total, SUM(playtime) AS playtime FROM sadmin_players", function(rows)
		if not IsValid(ply) then return end

		local totals = rows[1] or {}

		slib.dbQuery("SELECT sid64, name, usergroup, playtime FROM sadmin_players WHERE usergroup <> 'user' ORDER BY playtime DESC LIMIT 10", function(top)
			if not IsValid(ply) then return end

			local board, staff = {}, 0

			for _, row in ipairs(top) do
				board[#board + 1] = {
					sid64 = row.sid64,
					name = row.name ~= "" and row.name or nil,
					rank = row.usergroup,
					playtime = tonumber(row.playtime) or 0
				}
			end

			for _, v in ipairs(player.GetHumans()) do
				if sAdmin.hasPermission(v, "is_staff") then staff = staff + 1 end
			end

			sAdmin.networkData(ply, {"stats"}, {
				totalPlaytime = tonumber(totals.playtime) or 0,
				totalPlayers = tonumber(totals.total) or 0,
				totalStaffOnline = staff,
				staff_playtimeLeaderboard = board
			})
		end)
	end)
end

local function sendPlayersPage(ply, page, search)
	search = string.gsub(string.Trim(search), "[%%_]", "")

	local where = ""

	if search ~= "" then
		local like = esc("%" .. search .. "%")
		where = " WHERE name LIKE " .. like .. " OR sid64 LIKE " .. like
	end

	slib.dbQuery("SELECT COUNT(*) AS total FROM sadmin_players" .. where, function(rows)
		if not IsValid(ply) then return end

		local total = tonumber(rows[1] and rows[1].total) or 0
		local pages = math.max(1, math.ceil(total / PAGE_SIZE))
		page = math.Clamp(page, 1, pages)

		slib.dbQuery("SELECT sid64, name, usergroup, rank_expire, playtime FROM sadmin_players" .. where .. " ORDER BY last_join DESC LIMIT " .. PAGE_SIZE .. " OFFSET " .. int((page - 1) * PAGE_SIZE), function(list)
			if not IsValid(ply) then return end

			local result = {total_pages = pages, cur_page = page}

			for _, row in ipairs(list) do
				result[#result + 1] = {
					sid64 = row.sid64,
					name = row.name ~= "" and row.name or nil,
					rank = row.usergroup,
					rank_expire = tonumber(row.rank_expire) or 0,
					playtime = tonumber(row.playtime) or 0
				}
			end

			sAdmin.networkData(ply, {"offlinePlayers"}, result)
		end)
	end)
end

sAdmin.netHandlers[3] = function(ply)
	local id = net.ReadUInt(2)

	if not sAdmin.hasPermission(ply, "menu") then return end
	if sAdmin.throttle(ply, "sA:MenuData" .. id, 1) then return end

	if id == 0 then
		sendStats(ply)

		for _, v in ipairs(player.GetAll()) do
			networkPlayer(v, ply)
		end
	elseif id == 3 and sAdmin.sendWarnsData then
		sAdmin.sendWarnsData(ply)
	end
end

sAdmin.netHandlers[5] = function(ply)
	local kind = net.ReadUInt(3)
	local page = math.max(1, net.ReadUInt(15))
	local search = string.sub(net.ReadString(), 1, 64)

	if not sAdmin.hasPermission(ply, "menu") then return end
	if kind == 0 and not sAdmin.hasPermission(ply, "is_staff") then return end
	if kind > 4 then return end

	-- поиск при вводе шлёт запрос на каждую букву: выполняется только последний
	timer.Create("sA:Page_" .. ply:UserID() .. "_" .. kind, 0.25, 1, function()
		if not IsValid(ply) then return end

		if kind == 0 then
			sendPlayersPage(ply, page, search)
		elseif sAdmin.sendWarnPage then
			sAdmin.sendWarnPage(ply, kind, page, search)
		end
	end)
end

sAdmin.netHandlers[6] = function(ply)
	local target = net.ReadEntity()
	if not IsValid(target) or not target:IsPlayer() then return end
	if sAdmin.throttle(ply, "sA:PlayerData" .. target:EntIndex(), 1) then return end

	networkPlayer(target, ply)
end
