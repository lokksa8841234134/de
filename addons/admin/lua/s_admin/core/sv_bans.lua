--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	sAdmin: баны, предупреждения, журнал наказаний (SQL через slib.db)

	Таблицы:
		sadmin_bans        - sid64, expiration, reason, admin_sid64, date_given
		sadmin_warns       - id, sid64, admin_sid64, reason, date_given, active
		sadmin_punishments - id, sid64, active_warns, action (1 - кик, 2 - бан), date_given

	Бан до 90 дней - "мягкий": игрок заходит на сервер, видит экран блокировки
	(переменная BANNED) и может снять бан токеном. Дольше 90 дней или навсегда - вход закрыт.

	sAdmin.isBanned(sid64)                                - true/false, данные бана
	sAdmin.addBan(sid64, time, reason, admin)             - time в секундах, 0 - навсегда
	sAdmin.banPly(ply, time, reason, admin)
	sAdmin.unban(sid64)
	sAdmin.banMessage(ban)                                - текст при отключении
	sAdmin.addWarn(target, admin, reason, callback)       - callback(активные предупреждения)
	sAdmin.addInfoWarn(target, admin, reason)             - пометка, не считается предупреждением
	sAdmin.deleteWarn(id, callback, ply)                  - callback(успех, предупреждение)
	sAdmin.setWarnInactive(id, callback)                  - callback(успех)
	sAdmin.addPunishmentLog(target, activeWarns, action)
	sAdmin.sendWarnsData(ply), sAdmin.sendWarnPage(ply, type, page, search)
---------------------------------------------------------------------------]]
sAdmin = sAdmin or {}
sAdmin.bans = sAdmin.bans or {}

local SOFT_BAN_LIMIT = 7776000 -- 90 дней
local PAGE_SIZE = 20
local MAX_INT = 2 ^ 53
local NOT_NOTE = " reason NOT LIKE '[NOTE]%'"

local esc = slib.dbEscape

local function int(value)
	local n = tonumber(value) or 0
	if n ~= n then n = 0 end

	return string.format("%.0f", math.floor(math.Clamp(n, -MAX_INT, MAX_INT)))
end

local function isSID64(sid64)
	return isstring(sid64) and #sid64 == 17 and string.match(sid64, "^7656119%d+$") ~= nil
end

local function lower(str)
	return (utf8 and utf8.lower or string.lower)(str)
end

-- текст для базы: валидный UTF-8 без 4-байтовых символов, не длиннее max символов
local function cleanText(str, max)
	str = utf8.force(tostring(str or ""))
	str = string.gsub(str, "[\240-\247][\128-\191][\128-\191][\128-\191]", "")

	return utf8.sub(str, 1, max or 255)
end

local function targetSID(target)
	if isentity(target) then
		return IsValid(target) and target:IsPlayer() and target:SteamID64() or nil
	end

	target = tostring(target or "")

	return isSID64(target) and target or nil
end

local function adminSID(admin)
	return IsValid(admin) and admin:IsPlayer() and admin:SteamID64() or "0"
end

local function log(ply, text, value)
	if DarkRP and DarkRP.log then
		DarkRP.log("admin", IsValid(ply) and ply or nil, nil, text, nil, value)
	end
end

--[[---------------------------------------------------------------------------
	ЧС мультиаккаунтов (data/allwaysban.json, пополняется командой alwaysban)
---------------------------------------------------------------------------]]
local function readAlwaysBan()
	local tbl = util.JSONToTable(file.Read("allwaysban.json", "DATA") or "")

	return istable(tbl) and tbl or {}
end

sAdmin.AlwaysBan = sAdmin.AlwaysBan or readAlwaysBan()

local function inAlwaysBan(steamid)
	if not isstring(steamid) or not string.match(steamid, "^STEAM_%d:%d:%d+$") then return false end

	local sid0 = string.gsub(steamid, "^STEAM_%d", "STEAM_0")
	local sid1 = string.gsub(steamid, "^STEAM_%d", "STEAM_1")

	return tobool(sAdmin.AlwaysBan[sid0] or sAdmin.AlwaysBan[sid1])
end

--[[---------------------------------------------------------------------------
	Баны
---------------------------------------------------------------------------]]
local function isHardBan(ban)
	local exp = tonumber(ban.expiration) or 0

	return exp == 0 or exp - os.time() > SOFT_BAN_LIMIT
end

-- активный бан или nil (истёкший удаляется)
local function activeBan(sid64)
	local ban = sAdmin.bans[sid64]
	if not ban then return nil end

	local exp = tonumber(ban.expiration) or 0

	if exp ~= 0 and exp <= os.time() then
		sAdmin.bans[sid64] = nil
		slib.dbQuery("DELETE FROM sadmin_bans WHERE sid64 = " .. esc(sid64) .. " AND expiration = " .. int(exp))

		return nil
	end

	return ban
end

sAdmin.banMessage = function(ban)
	local exp = tonumber(ban and ban.expiration) or 0
	local left = exp == 0 and "навсегда" or sAdmin.formatTime(math.max(exp - os.time(), 1))

	return string.format(sAdmin.config["ban_message"], utf8.sub(tostring(ban and ban.reason or ""), 1, 200), left)
end

sAdmin.isBanned = function(sid64)
	local ban = activeBan(tostring(sid64 or ""))

	return ban ~= nil, ban
end

sAdmin.addBan = function(sid64, time, reason, admin)
	sid64 = tostring(sid64 or "")
	if not isSID64(sid64) or sAdmin.config["super_users"][sid64] then return end

	time = math.max(0, math.floor(tonumber(time) or 0))

	local ban = {
		sid64 = sid64,
		expiration = time == 0 and 0 or os.time() + time,
		reason = cleanText(reason, 255),
		admin_sid64 = adminSID(admin),
		date_given = os.time()
	}

	sAdmin.bans[sid64] = ban

	slib.dbQuery("REPLACE INTO sadmin_bans (sid64, expiration, reason, admin_sid64, date_given) VALUES (" .. table.concat({
		esc(sid64),
		int(ban.expiration),
		esc(ban.reason),
		esc(ban.admin_sid64),
		int(ban.date_given)
	}, ", ") .. ")")

	hook.Run("sA:Banned", sid64, ban, admin)

	-- мягкий бан тоже отключает: при повторном входе игрок попадёт на экран блокировки
	local ply = player.GetBySteamID64(sid64)

	if IsValid(ply) then
		ply:Kick(sAdmin.banMessage(ban))
	end

	return ban
end

sAdmin.banPly = function(ply, time, reason, admin)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	if ply:IsBot() then
		ply:Kick(sAdmin.config["prefix"] .. tostring(reason or ""))
		return
	end

	return sAdmin.addBan(ply:SteamID64(), time, reason, admin)
end

sAdmin.unban = function(sid64)
	sid64 = tostring(sid64 or "")
	if not isSID64(sid64) then return end

	sAdmin.bans[sid64] = nil
	slib.dbQuery("DELETE FROM sadmin_bans WHERE sid64 = " .. esc(sid64))

	local ply = player.GetBySteamID64(sid64)

	if IsValid(ply) and ply:getDarkRPVar("BANNED") then
		ply:SetSelfDarkRPVar("BANNED", nil)
	end

	hook.Run("sA:Unbanned", sid64)
end

local function applyBanState(ply)
	if not IsValid(ply) or ply:IsBot() then return end

	local sid64 = ply:SteamID64()
	local ban = not sAdmin.config["super_users"][sid64] and activeBan(sid64) or nil

	if not ban then
		if ply:getDarkRPVar("BANNED") then
			ply:SetSelfDarkRPVar("BANNED", nil)
		end

		return
	end

	if isHardBan(ban) then
		ply:Kick(sAdmin.banMessage(ban))
		return
	end

	ply:SetSelfDarkRPVar("BANNED", tonumber(ban.expiration))
end

hook.Add("CheckPassword", "sA:CheckBans", function(sid64)
	if sAdmin.config["super_users"][sid64] then return end

	if inAlwaysBan(util.SteamIDFrom64(sid64)) then
		return false, sAdmin.config["prefix"] .. "Вы в ЧС мультиаккаунтов."
	end

	local ban = activeBan(sid64)

	if ban and isHardBan(ban) then
		return false, sAdmin.banMessage(ban)
	end

	local visible = GetConVar("sv_visiblemaxplayers")
	local limit = visible and visible:GetInt() or 0

	if limit > 0 and player.GetCount() >= limit and not (sAdmin.hasReservedSlot and sAdmin.hasReservedSlot(sid64)) then
		return false, sAdmin.config["prefix"] .. "Сервер заполнен, свободны только резервные слоты."
	end
end)

hook.Add("PlayerInitialSpawn", "sA:ApplyBan", applyBanState)

hook.Add("slib.FullLoaded", "sA:BanInfo", function(ply)
	if not ply:getDarkRPVar("BANNED") then return end

	local ban = activeBan(ply:SteamID64())

	if ban then
		DarkRP.UIEffect(ply, "ban_info", {reason = ban.reason})
	end
end)

timer.Create("sA:BanExpiry", 30, 0, function()
	local now = os.time()

	for sid64, ban in pairs(sAdmin.bans) do
		local exp = tonumber(ban.expiration) or 0

		if exp ~= 0 and exp <= now then
			activeBan(sid64)
		end
	end

	for _, ply in ipairs(player.GetHumans()) do
		if ply:getDarkRPVar("BANNED") and not activeBan(ply:SteamID64()) then
			ply:SetSelfDarkRPVar("BANNED", nil)
			sAdmin.msg(ply, "Срок блокировки истёк. Перезайдите на сервер.")
		end
	end
end)

-- аккаунты, с которых заходили с этого ПК (модуль персонажей)
hook.Add("MCR.AltsDetected", "sA:CheckAlts", function(ply, alts)
	if not IsValid(ply) or not istable(alts) then return end
	if sAdmin.config["super_users"][ply:SteamID64()] then return end

	for _, sid in ipairs(alts) do
		if inAlwaysBan(sid) then
			sAdmin.msg(sAdmin.logPerm(), "%s зашёл с ПК аккаунта %s из ЧС мультиаккаунтов и отключён.", ply, sid)
			log(ply, "отключён: ПК аккаунта из ЧС мультиаккаунтов", sid)
			ply:Kick(sAdmin.config["prefix"] .. "Вы в ЧС мультиаккаунтов.")

			return
		end
	end

	for _, sid in ipairs(alts) do
		local sid64 = util.SteamIDTo64(sid)
		local ban = isSID64(sid64) and activeBan(sid64) or nil

		if ban then
			sAdmin.msg(sAdmin.logPerm(), "%s заходил с этого ПК под заблокированным аккаунтом %s. Причина бана: %s", ply, sid, ban.reason)
			log(ply, "заходил с ПК заблокированного аккаунта", sid)
		end
	end
end)

--[[---------------------------------------------------------------------------
	Предупреждения
---------------------------------------------------------------------------]]
local function activeTime()
	return sAdmin.getTime(sAdmin.config["warns"]["active_time"])
end

local function insertWarn(target, admin, reason, active, callback)
	local sid64 = targetSID(target)
	if not sid64 then return end

	local now = os.time()

	slib.dbQuery("INSERT INTO sadmin_warns (sid64, admin_sid64, reason, date_given, active) VALUES (" .. table.concat({
		esc(sid64),
		esc(adminSID(admin)),
		esc(cleanText(reason, 500)),
		int(now),
		active and "1" or "0"
	}, ", ") .. ")", function()
		if callback then callback(sid64, now) end
	end)
end

sAdmin.addWarn = function(target, admin, reason, callback)
	insertWarn(target, admin, reason, true, function(sid64, now)
		slib.dbQuery("SELECT COUNT(*) AS amount FROM sadmin_warns WHERE sid64 = " .. esc(sid64) .. " AND active = 1 AND date_given > " .. int(now - activeTime()) .. " AND" .. NOT_NOTE, function(rows)
			if callback then
				callback(tonumber(rows[1] and rows[1].amount) or 0)
			end
		end)
	end)
end

sAdmin.addInfoWarn = function(target, admin, reason)
	insertWarn(target, admin, reason, false)
end

local function warnID(id)
	id = tonumber(id)
	if not id or id < 1 or id ~= math.floor(id) or id > MAX_INT then return nil end

	return id
end

sAdmin.deleteWarn = function(id, callback, ply)
	local empty = {sid64 = "N/A"}

	local function done(ok, warn)
		if callback then callback(ok, warn or empty) end
	end

	id = warnID(id)
	if not id then return done(false) end

	slib.dbQuery("SELECT id, sid64, admin_sid64, reason, date_given, active FROM sadmin_warns WHERE id = " .. int(id), function(rows)
		local warn = rows[1]
		if not warn then return done(false) end

		slib.dbQuery("DELETE FROM sadmin_warns WHERE id = " .. int(id), function()
			log(ply, "удалил предупреждение №" .. id .. " игрока " .. tostring(warn.sid64), warn.reason)
			done(true, warn)
		end, function()
			done(false, warn)
		end)
	end, function()
		done(false)
	end)
end

sAdmin.setWarnInactive = function(id, callback)
	local function done(ok)
		if callback then callback(ok) end
	end

	id = warnID(id)
	if not id then return done(false) end

	slib.dbQuery("SELECT id FROM sadmin_warns WHERE id = " .. int(id), function(rows)
		if not rows[1] then return done(false) end

		slib.dbQuery("UPDATE sadmin_warns SET active = 0 WHERE id = " .. int(id), function()
			done(true)
		end, function()
			done(false)
		end)
	end, function()
		done(false)
	end)
end

sAdmin.addPunishmentLog = function(target, amount, action)
	local sid64 = targetSID(target)
	if not sid64 then return end

	slib.dbQuery("INSERT INTO sadmin_punishments (sid64, active_warns, action, date_given) VALUES (" .. table.concat({
		esc(sid64),
		int(amount),
		int(action),
		int(os.time())
	}, ", ") .. ")")
end

--[[---------------------------------------------------------------------------
	Данные для меню: статистика и страницы списков
	1 - журнал наказаний, 2 - все игроки с предупреждениями, 3 - игроки онлайн,
	4 - предупреждения игрока (search - SteamID64)
---------------------------------------------------------------------------]]
sAdmin.sendWarnsData = function(ply)
	local week = int(os.time() - 604800)
	local recent = "SUM(CASE WHEN date_given > " .. week .. " THEN 1 ELSE 0 END) AS recent"

	slib.dbQuery("SELECT COUNT(*) AS total, " .. recent .. " FROM sadmin_warns WHERE" .. NOT_NOTE, function(warns)
		slib.dbQuery("SELECT COUNT(*) AS total, " .. recent .. " FROM sadmin_punishments", function(punishments)
			if not IsValid(ply) then return end

			local w, p = warns[1] or {}, punishments[1] or {}

			sAdmin.networkData(ply, {"warnsData"}, {
				warnsThisWeek = tonumber(w.recent) or 0,
				totalWarns = tonumber(w.total) or 0,
				punishmentsThisWeek = tonumber(p.recent) or 0,
				totalPunishments = tonumber(p.total) or 0
			})
		end)
	end)
end

local function paging(total, page)
	local pages = math.max(1, math.ceil(total / PAGE_SIZE))
	page = math.Clamp(page, 1, pages)

	return pages, page, " LIMIT " .. PAGE_SIZE .. " OFFSET " .. int((page - 1) * PAGE_SIZE)
end

local function sendPunishments(ply, page, search)
	local where = search ~= "" and (" WHERE sid64 LIKE " .. esc("%" .. search .. "%")) or ""

	slib.dbQuery("SELECT COUNT(*) AS total FROM sadmin_punishments" .. where, function(rows)
		if not IsValid(ply) then return end

		local pages, cur, limit = paging(tonumber(rows[1] and rows[1].total) or 0, page)

		slib.dbQuery("SELECT sid64, active_warns, action, date_given FROM sadmin_punishments" .. where .. " ORDER BY date_given DESC" .. limit, function(list)
			if not IsValid(ply) then return end

			local result = {total_pages = pages, cur_page = cur}

			for _, row in ipairs(list) do
				result[#result + 1] = {
					sid64 = row.sid64,
					active_warns = tonumber(row.active_warns) or 0,
					action = tonumber(row.action) or 0,
					date_given = tonumber(row.date_given) or 0
				}
			end

			sAdmin.networkData(ply, {"punishmentLogs"}, result)
		end)
	end)
end

local function sendOfflineWarns(ply, page, search)
	local from = " FROM sadmin_warns w LEFT JOIN sadmin_players p ON p.sid64 = w.sid64"
	local where = ""

	if search ~= "" then
		local like = esc("%" .. search .. "%")
		where = " WHERE w.sid64 LIKE " .. like .. " OR p.name LIKE " .. like
	end

	slib.dbQuery("SELECT COUNT(*) AS total FROM (SELECT w.sid64" .. from .. where .. " GROUP BY w.sid64) t", function(rows)
		if not IsValid(ply) then return end

		local pages, cur, limit = paging(tonumber(rows[1] and rows[1].total) or 0, page)
		local total = "SUM(CASE WHEN w.reason NOT LIKE '[NOTE]%' THEN 1 ELSE 0 END) AS total_warns"

		slib.dbQuery("SELECT w.sid64 AS sid64, MAX(p.name) AS name, " .. total .. ", MAX(w.date_given) AS last_warn" .. from .. where .. " GROUP BY w.sid64 ORDER BY last_warn DESC" .. limit, function(list)
			if not IsValid(ply) then return end

			local result = {total_pages = pages, cur_page = cur}

			for _, row in ipairs(list) do
				result[#result + 1] = {
					sid64 = row.sid64,
					name = row.name ~= "" and row.name or nil,
					total_warns = tonumber(row.total_warns) or 0
				}
			end

			sAdmin.networkData(ply, {"offlineWarns"}, result)
		end)
	end)
end

local function sendOnlineWarns(ply, page, search)
	local needle = lower(search)
	local list = {}

	for _, v in ipairs(player.GetHumans()) do
		local sid64 = v:SteamID64()
		local name = v:SteamName() or ""

		if needle == "" or string.find(lower(name), needle, 1, true) or string.find(lower(v:Nick() or ""), needle, 1, true) or string.find(sid64, needle, 1, true) then
			list[#list + 1] = {sid64 = sid64, name = name}
		end
	end

	local pages, cur = paging(#list, page)
	local result, ids = {total_pages = pages, cur_page = cur}, {}

	for i = (cur - 1) * PAGE_SIZE + 1, math.min(#list, cur * PAGE_SIZE) do
		result[#result + 1] = {sid64 = list[i].sid64, name = list[i].name, total_warns = 0}
		ids[#ids + 1] = esc(list[i].sid64)
	end

	if #ids == 0 then
		sAdmin.networkData(ply, {"onlineWarns"}, result)
		return
	end

	slib.dbQuery("SELECT sid64, COUNT(*) AS total FROM sadmin_warns WHERE sid64 IN (" .. table.concat(ids, ", ") .. ") AND" .. NOT_NOTE .. " GROUP BY sid64", function(rows)
		if not IsValid(ply) then return end

		local counts = {}

		for _, row in ipairs(rows) do
			counts[row.sid64] = tonumber(row.total) or 0
		end

		for _, entry in ipairs(result) do
			entry.total_warns = counts[entry.sid64] or 0
		end

		sAdmin.networkData(ply, {"onlineWarns"}, result)
	end)
end

local function sendPlayerWarns(ply, sid64)
	if not isSID64(sid64) then return end

	slib.dbQuery("SELECT id, sid64, admin_sid64, reason, date_given, active FROM sadmin_warns WHERE sid64 = " .. esc(sid64) .. " ORDER BY date_given DESC LIMIT 100", function(rows)
		slib.dbQuery("SELECT name FROM sadmin_players WHERE sid64 = " .. esc(sid64), function(names)
			if not IsValid(ply) then return end

			local online = player.GetBySteamID64(sid64)
			local stored = names[1] and names[1].name
			local result = {name = IsValid(online) and online:SteamName() or (stored ~= "" and stored or nil)}

			for i, row in ipairs(rows) do
				result[i] = {
					id = tonumber(row.id),
					sid64 = row.sid64,
					admin_sid64 = row.admin_sid64,
					reason = row.reason,
					date_given = tonumber(row.date_given) or 0,
					active = tonumber(row.active) or 0
				}
			end

			sAdmin.networkData(ply, {"playerWarns"}, result)
		end)
	end)
end

sAdmin.sendWarnPage = function(ply, kind, page, search)
	if not IsValid(ply) then return end

	search = string.Trim(tostring(search or ""))

	if kind == 4 then
		sendPlayerWarns(ply, search)
		return
	end

	search = string.gsub(search, "[%%_]", "")

	if kind == 1 then
		sendPunishments(ply, page, search)
	elseif kind == 2 then
		sendOfflineWarns(ply, page, search)
	elseif kind == 3 then
		sendOnlineWarns(ply, page, search)
	end
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

slib.onDBReady("sAdmin:bans", function()
	local ai = slib.dbAutoIncrement()

	runQueries({
		"CREATE TABLE IF NOT EXISTS sadmin_bans (sid64 VARCHAR(20) NOT NULL PRIMARY KEY, expiration BIGINT NOT NULL DEFAULT 0, reason TEXT, admin_sid64 VARCHAR(20), date_given BIGINT NOT NULL DEFAULT 0)",
		"CREATE TABLE IF NOT EXISTS sadmin_warns (id " .. ai .. ", sid64 VARCHAR(20) NOT NULL, admin_sid64 VARCHAR(20), reason TEXT, date_given BIGINT NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1)",
		"CREATE TABLE IF NOT EXISTS sadmin_punishments (id " .. ai .. ", sid64 VARCHAR(20) NOT NULL, active_warns INTEGER NOT NULL DEFAULT 0, action INTEGER NOT NULL DEFAULT 0, date_given BIGINT NOT NULL DEFAULT 0)",
		"DELETE FROM sadmin_bans WHERE expiration <> 0 AND expiration <= " .. int(os.time())
	}, function()
		slib.dbQuery("SELECT sid64, expiration, reason, admin_sid64, date_given FROM sadmin_bans", function(rows)
			local bans = {}

			for _, row in ipairs(rows) do
				bans[row.sid64] = {
					sid64 = row.sid64,
					expiration = tonumber(row.expiration) or 0,
					reason = row.reason or "",
					admin_sid64 = row.admin_sid64 or "0",
					date_given = tonumber(row.date_given) or 0
				}
			end

			-- баны, выданные до готовности базы, новее загруженных
			for sid64, ban in pairs(sAdmin.bans) do
				bans[sid64] = ban
			end

			sAdmin.bans = bans

			for _, ply in ipairs(player.GetHumans()) do
				applyBanState(ply)
			end
		end)
	end)
end)
