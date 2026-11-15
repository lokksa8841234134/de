--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Хранение данных игроков (MySQLite: SQLite по умолчанию, MySQL через config/mysql.lua)

	darkrp_player     - кошелёк (uid = SteamID64)
	darkrp_jobban     - баны работ: data = JSON {[team] = время разбана (os.time) | 0 навсегда}
	darkrp_playerdata - прочие данные: karma, jobxp (JSON), payday
---------------------------------------------------------------------------]]
local pmeta = FindMetaTable("Player")

DarkRP.DBReady = DarkRP.DBReady or false

local function dbError(err, query)
	MsgC(Color(255, 90, 0), "[DarkRP] SQL: " .. tostring(err) .. "\n    " .. tostring(query) .. "\n")
end

-- uid для запросов: только цифры SteamID64, у ботов данных нет
function DarkRP.GetPlayerUID(ply)
	if not IsValid(ply) or ply:IsBot() then return nil end

	local sid = ply:SteamID64()
	if not isstring(sid) or not string.match(sid, "^%d+$") then return nil end

	return sid
end

local tables = {
	[[CREATE TABLE IF NOT EXISTS darkrp_player(
		uid BIGINT NOT NULL PRIMARY KEY,
		rpname VARCHAR(45),
		salary INTEGER NOT NULL DEFAULT 0,
		wallet BIGINT NOT NULL
	)]],
	[[CREATE TABLE IF NOT EXISTS darkrp_jobban(
		uid BIGINT NOT NULL PRIMARY KEY,
		data TEXT NOT NULL
	)]],
	[[CREATE TABLE IF NOT EXISTS darkrp_playerdata(
		uid BIGINT NOT NULL,
		var VARCHAR(32) NOT NULL,
		value TEXT,
		PRIMARY KEY(uid, var)
	)]],
}

function GM:DatabaseInitialized()
	local pending = #tables

	local function done()
		pending = pending - 1
		if pending > 0 then return end

		DarkRP.DBReady = true
		MsgC(Color(120, 230, 120), "[DarkRP] База данных готова (" .. (MySQLite.isMySQL() and "MySQL" or "SQLite") .. ")\n")

		for _, ply in ipairs(player.GetAll()) do
			if ply.DarkRPUnInitialized and not ply.DarkRPDataLoading then
				DarkRP.LoadPlayerData(ply)
			end
		end
	end

	for _, query in ipairs(tables) do
		MySQLite.query(query, done, function(err, q)
			dbError(err, q)
			done()
		end)
	end
end

--[[---------------------------------------------------------------------------
	Произвольные данные игрока
---------------------------------------------------------------------------]]
function DarkRP.SavePlayerData(ply, var, value)
	local uid = DarkRP.GetPlayerUID(ply)
	if not uid or not DarkRP.DBReady or ply.DarkRPUnInitialized then return end

	if value == nil then
		MySQLite.query(string.format("DELETE FROM darkrp_playerdata WHERE uid = %s AND var = %s", uid, MySQLite.SQLStr(var)), nil, dbError)
		return
	end

	if istable(value) then
		value = util.TableToJSON(value)
	end

	MySQLite.query(string.format("REPLACE INTO darkrp_playerdata(uid, var, value) VALUES(%s, %s, %s)", uid, MySQLite.SQLStr(var), MySQLite.SQLStr(tostring(value))), nil, dbError)
end

--[[---------------------------------------------------------------------------
	Загрузка при входе
---------------------------------------------------------------------------]]
local function applyPlayerData(ply, rows)
	local data = {}

	for _, row in ipairs(rows or {}) do
		if row.var then data[row.var] = row.value end
	end

	ply.jobxp = data.jobxp and util.JSONToTable(data.jobxp) or {}
	ply:SetDarkRPVar("karma", math.Clamp(math.floor(tonumber(data.karma) or 100), 0, 200))

	local payday = math.max(math.floor(tonumber(data.payday) or 0), 0)
	if payday > 0 then
		ply:SetSelfDarkRPVar("payday", payday)
	end
end

local function finishLoading(ply)
	ply.DarkRPDataLoading = nil
	ply.DarkRPUnInitialized = nil

	-- клиент готов принимать net только после DarkRP.PlayerLoaded
	if ply.DarkRPClientReady then
		DarkRP.SendPlayerData(ply, "jobxp", ply.jobxp or {})
	end

	hook.Run("DarkRPPlayerDataLoaded", ply)
end

function DarkRP.LoadPlayerData(ply)
	if not IsValid(ply) then return end

	local uid = DarkRP.GetPlayerUID(ply)
	local startmoney = GAMEMODE.Config.startingmoney or 0

	if not uid then
		ply:SetDarkRPVar("money", startmoney)
		ply:SetDarkRPVar("karma", 100)
		ply.jobxp = ply.jobxp or {}
		ply.jobbans = ply.jobbans or {}
		finishLoading(ply)
		return
	end

	if not DarkRP.DBReady then return end

	ply.DarkRPDataLoading = true

	MySQLite.query("SELECT wallet FROM darkrp_player WHERE uid = " .. uid, function(result)
		if not IsValid(ply) then return end

		local wallet = result and result[1] and tonumber(result[1].wallet)

		if not wallet then
			wallet = startmoney
			MySQLite.query(string.format("INSERT INTO darkrp_player(uid, rpname, salary, wallet) VALUES(%s, NULL, 0, %s)", uid, string.format("%d", wallet)), nil, dbError)
		end

		ply:SetDarkRPVar("money", wallet)

		MySQLite.query("SELECT var, value FROM darkrp_playerdata WHERE uid = " .. uid, function(rows)
			if not IsValid(ply) then return end
			applyPlayerData(ply, rows)

			MySQLite.query("SELECT data FROM darkrp_jobban WHERE uid = " .. uid, function(bans)
				if not IsValid(ply) then return end
				DarkRP.ApplyJobBans(ply, bans and bans[1] and bans[1].data)
				finishLoading(ply)
			end, function(err, q)
				dbError(err, q)
				if IsValid(ply) then finishLoading(ply) end
			end)
		end, function(err, q)
			dbError(err, q)
			if IsValid(ply) then
				applyPlayerData(ply, {})
				finishLoading(ply)
			end
		end)
	end, function(err, q)
		dbError(err, q)
		ply.DarkRPDataLoading = nil
	end)
end

-- Сохранение кошелька при любом изменении денег
hook.Add("DarkRPVarChanged", "DarkRP.SaveWallet", function(ply, var, old, new)
	if var ~= "money" or not isnumber(new) or ply.DarkRPUnInitialized then return end

	local uid = DarkRP.GetPlayerUID(ply)
	if not uid or not DarkRP.DBReady then return end

	MySQLite.query(string.format("UPDATE darkrp_player SET wallet = %s WHERE uid = %s", string.format("%d", math.floor(new)), uid), nil, dbError)
end)

--[[---------------------------------------------------------------------------
	Опыт работ: ply.jobxp[code] = {xp = n, unlocks = {[item] = true}}
	С татуировкой a5 "Острый ум" начисление в XP_A5 раза больше (медицина
	FDNY, огнетушитель, шланг, ремонт машин). exact - число уже посчитано
	с a5 (станции крафта) или его задал администратор (addcraftpoints).
	Трата опыта (отрицательное число) не меняется.
---------------------------------------------------------------------------]]
local XP_A5 = 1.5

function pmeta:JobXPAdd(code, amount, exact)
	amount = math.floor(tonumber(amount) or 0)
	if not isstring(code) or code == "" or amount == 0 then return end

	if amount > 0 and not exact and MCR and isfunction(MCR.HasTatoo) and MCR.HasTatoo(self, "a5") then
		amount = math.floor(amount * XP_A5 + 0.5)
	end

	self.jobxp = self.jobxp or {}
	self.jobxp[code] = self.jobxp[code] or {}
	self.jobxp[code].xp = math.max((self.jobxp[code].xp or 0) + amount, 0)

	DarkRP.SavePlayerData(self, "jobxp", self.jobxp)
	DarkRP.SendPlayerData(self, "jobxp", self.jobxp)
end

function pmeta:JobXPUnlock(code, item)
	if not isstring(code) or code == "" or item == nil then return end

	self.jobxp = self.jobxp or {}
	self.jobxp[code] = self.jobxp[code] or {}
	self.jobxp[code].unlocks = self.jobxp[code].unlocks or {}

	if self.jobxp[code].unlocks[item] then return end
	self.jobxp[code].unlocks[item] = true

	DarkRP.SavePlayerData(self, "jobxp", self.jobxp)
	DarkRP.SendPlayerData(self, "jobxp", self.jobxp)
end

--[[---------------------------------------------------------------------------
	Рассудок (карма): 0..200, по умолчанию 100
---------------------------------------------------------------------------]]
function pmeta:SetKarma(amount)
	amount = math.Clamp(math.floor(tonumber(amount) or 100), 0, 200)
	self:SetDarkRPVar("karma", amount)
	DarkRP.SavePlayerData(self, "karma", amount)
end

function pmeta:addKarma(amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount == 0 then return end

	self:SetKarma((self:getDarkRPVar("karma") or 100) + amount)
end

-- Восстановление рассудка: +1 в минуту до 100
timer.Create("DarkRP.KarmaRegen", 60, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		if ply.DarkRPUnInitialized or not ply:Alive() then continue end

		local karma = ply:getDarkRPVar("karma")
		if karma and karma < 100 then
			ply:SetKarma(karma + 1)
		end
	end
end)
