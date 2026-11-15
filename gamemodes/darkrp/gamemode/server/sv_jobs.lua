--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Профессии: смена работы (rp_job), ограничения, баны профессий

	Поля профессий (jobs.lua):
	char      - персонаж: 1 гражданский, 2 госслужба, 3 нелегал; 0/nil - только администрация
	npc       - работодатель: nil - стандартный, "ems", "ramon"; "" - особый способ получения
	max       - мест на профессии (0 - без ограничения)
	online    - минимум игроков на сервере
	mintime   - минимум наигранного времени (сек.)
	rank      - {группа, ранг} минимальный ранг MRS, rank_max - максимальный
	nlrank    - {группа, ранг} ранг, с которого не действуют max и online
	customCheck(ply) / customCheckFailMsg

	Баны: ply.jobbans = {[команда] = время разбана (os.time) | 0 навсегда}
---------------------------------------------------------------------------]]
local pmeta = FindMetaTable("Player")

util.AddNetworkString("OnChangedTeam")

local NPC_RANGE = 300 * 300
local BAN_SHOW_FOREVER = 315360000

local function dbError(err, query)
	MsgC(Color(255, 90, 0), "[DarkRP] SQL: " .. tostring(err) .. "\n    " .. tostring(query) .. "\n")
end

local function niceTime(sec)
	sec = math.max(math.floor(tonumber(sec) or 0), 0)

	local d = math.floor(sec / 86400)
	local h = math.floor(sec % 86400 / 3600)
	local m = math.floor(sec % 3600 / 60)

	if d > 0 then return d .. " дн. " .. h .. " ч." end
	if h > 0 then return h .. " ч. " .. m .. " мин." end

	return math.max(m, 1) .. " мин."
end

local function playTime(ply)
	if sAdmin and sAdmin.mcTime then return sAdmin.mcTime(ply) end

	local t1 = ply:getDarkRPVar("playtime")
	if not t1 then return 0 end

	local t2 = ply:getDarkRPVar("synctime") or CurTime()

	return math.max(0, math.Round(t1 + (CurTime() - t2)))
end

local function plyRank(ply, grp)
	if not MRS or not MRS.GetPlyRank then return 1 end

	return tonumber((MRS.GetPlyRank(ply, grp))) or 1
end

local function defaultTeam(ply)
	return MCR and MCR.DefTeams and MCR.DefTeams[ply:getDarkRPVar("character")]
end

--[[---------------------------------------------------------------------------
	Работодатели (mcs_npc по UID). Если их нет на карте - дистанция не проверяется.
---------------------------------------------------------------------------]]
local function employers(job, t)
	if t == TEAM_LAWYER then return {mayor = true} end
	if job.npc == "ems" then return {clark = true} end
	if job.npc == "ramon" then return {junkyard_temp = true} end
	if job.npc ~= nil then return nil end

	if job.char == 1 then return {jobs_civ = true} end
	if job.char == 2 then return {police_arsenal = true, police_arsenal_night = true} end
end

local function nearEmployer(ply, uids)
	if not uids then return true end

	local pos = ply:GetPos()
	local onMap = false

	for _, ent in ipairs(ents.FindByClass("mcs_npc")) do
		if not ent.GetUID or not uids[ent:GetUID()] then continue end

		onMap = true
		if ent:GetPos():DistToSqr(pos) <= NPC_RANGE then return true end
	end

	return not onMap
end

--[[---------------------------------------------------------------------------
	Проверка возможности занять профессию
---------------------------------------------------------------------------]]
local function canJoin(ply, t, job)
	local char = ply:getDarkRPVar("character")
	local def = defaultTeam(ply)

	if t == ply:Team() then return false end

	-- вернуться к базовой роли персонажа можно всегда
	if def and t == def then return true end

	if not job.char or job.char == 0 then return false, "Эта профессия назначается администрацией" end
	if job.char ~= char then return false, "Эта профессия недоступна вашему персонажу" end
	if ply:Team() ~= def then return false, "Сначала уйдите с текущей работы" end
	if job.npc == "" and t ~= TEAM_LAWYER then return false, "Эту профессию нельзя взять самостоятельно" end
	if not ply:IsFreeman() then return false, "Сейчас вы не можете сменить профессию" end
	if MQS and MQS.HasQuest and MQS.HasQuest(ply) then return false, "Сначала завершите активное задание" end

	local banned, left = ply:isTeamBanned(t)

	if banned then
		return false, left > 0 and ("Вам запрещена эта профессия ещё " .. niceTime(left)) or "Вам навсегда запрещена эта профессия"
	end

	local exempt = job.nlrank and plyRank(ply, job.nlrank[1]) >= job.nlrank[2]

	if not exempt then
		if job.max and job.max > 0 and #team.GetPlayers(t) >= job.max then
			return false, "Все места на этой профессии заняты"
		end

		if job.online and player.GetCount() < job.online then
			return false, "Профессия доступна, когда на сервере от " .. job.online .. " игроков"
		end
	end

	if job.mintime then
		local played = playTime(ply)
		if played < job.mintime then return false, "Нужно наиграть ещё " .. niceTime(job.mintime - played) end
	end

	if job.rank and plyRank(ply, job.rank[1]) < job.rank[2] then
		return false, "Недостаточный ранг для этой профессии"
	end

	if job.rank_max and plyRank(ply, job.rank_max[1]) > job.rank_max[2] then
		return false, "Ваш ранг слишком высок для этой профессии"
	end

	if job.customCheck and not job.customCheck(ply) then
		return false, job.customCheckFailMsg or "Вы не можете занять эту профессию"
	end

	if not nearEmployer(ply, employers(job, t)) then
		return false, "Подойдите к работодателю"
	end

	local allowed, reason = hook.Call("playerCanChangeTeam", nil, ply, t, false)
	if allowed == false then return false, reason or "Вы не можете занять эту профессию" end

	return true
end

--[[---------------------------------------------------------------------------
	Смена профессии
---------------------------------------------------------------------------]]
function pmeta:ChangeTeam(t, force)
	t = tonumber(t)
	local job = t and DarkRP.Teams[t]
	if not job then return false end

	if not force then
		local ok = canJoin(self, t, job)

		if not ok then
			return false
		end
	end

	local old = self:Team()

	self:SetMaterial("")
	self.esuteam = nil
	self:SetDarkRPVar("hidename", nil)
	self:SetDarkRPVar("scba", nil)
	self:SetDarkRPVar("rc", nil)

	self:SetTeam(t)
	self:SetDarkRPVar("job", job.name)
	self:SetSelfDarkRPVar("salary", job.salary or 0)

	for _, wep in ipairs(self:GetWeapons()) do
		if wep.GivenByTeam then self:StripWeapon(wep:GetClass()) end
	end

	if self:Alive() then
		for _, class in ipairs(job.weapons or {}) do
			local wep = self:Give(class)
			if IsValid(wep) then wep.GivenByTeam = true end
		end

		self:SetWalkSpeed(GAMEMODE.Config.walkspeed)
		self:SetRunSpeed(self:isCP() and GAMEMODE.Config.runspeedcp or GAMEMODE.Config.runspeed)
		GAMEMODE:PlayerSetModel(self, job, t)
	end

	if job.PlayerChangeTeam then
		job.PlayerChangeTeam(self)
	end

	net.Start("OnChangedTeam")
		net.WriteInt(old, 12)
		net.WriteInt(t, 12)
	net.Send(self)

	hook.Call("OnPlayerChangedTeam", GAMEMODE, self, old, t)
	DarkRP.log("other", self, nil, "сменил профессию: " .. team.GetName(old) .. " -> " .. job.name)

	return true
end

function pmeta:updateJob(name)
	self:SetDarkRPVar("job", name)
end

-- уведомления о смене профессии делает сам режим
function GM:OnPlayerChangedTeam(ply, oldTeam, newTeam)
end

-- стандартная смена команды (changeteam) отключена, только rp_job
function GM:PlayerRequestTeam(ply, teamid)
end

concommand.Add("rp_job", function(ply, _, args)
	if not IsValid(ply) or ply.DarkRPUnInitialized then return end
	if DarkRP.NetDelay(ply, 1) then return end

	local t = tonumber(args[1])
	if not t or not DarkRP.Teams[t] then return end

	ply:ChangeTeam(t)
end)

--[[---------------------------------------------------------------------------
	Баны профессий
	gosban (TEAM_OFFDUTY) / ganban (TEAM_GANG) - время разбана для меню персонажей
---------------------------------------------------------------------------]]
local function saveJobBans(ply)
	local uid = DarkRP.GetPlayerUID(ply)
	if not uid or not DarkRP.DBReady then return end

	if table.IsEmpty(ply.jobbans or {}) then
		MySQLite.query("DELETE FROM darkrp_jobban WHERE uid = " .. uid, nil, dbError)
		return
	end

	MySQLite.query(string.format("REPLACE INTO darkrp_jobban(uid, data) VALUES(%s, %s)", uid, MySQLite.SQLStr(util.TableToJSON(ply.jobbans))), nil, dbError)
end

local function banVar(ply, t)
	local unban = t and ply.jobbans and ply.jobbans[t]
	if not unban then return nil end

	return unban == 0 and os.time() + BAN_SHOW_FOREVER or unban
end

local function applyBanVars(ply)
	ply:SetSelfDarkRPVar("gosban", banVar(ply, TEAM_OFFDUTY))
	ply:SetSelfDarkRPVar("ganban", banVar(ply, TEAM_GANG))
end

-- JSON из базы -> таблица банов без истёкших записей
local function parseBans(json)
	local bans, changed = {}, false
	local now = os.time()

	for t, unban in pairs(isstring(json) and util.JSONToTable(json) or {}) do
		t, unban = tonumber(t), tonumber(unban)

		if not t or not unban or (unban ~= 0 and unban <= now) then
			changed = true
			continue
		end

		bans[t] = unban
	end

	return bans, changed
end

function DarkRP.ApplyJobBans(ply, json)
	if not IsValid(ply) then return end

	local bans, changed = parseBans(json)

	ply.jobbans = bans
	applyBanVars(ply)

	if changed then saveJobBans(ply) end
end

-- true, оставшиеся секунды (0 - навсегда) | false
function pmeta:isTeamBanned(t)
	t = tonumber(t)
	local unban = t and self.jobbans and self.jobbans[t]
	if not unban then return false end

	if unban == 0 then return true, 0 end

	local left = unban - os.time()
	if left > 0 then return true, left end

	self.jobbans[t] = nil
	saveJobBans(self)
	applyBanVars(self)

	return false
end

-- time в секундах, 0 - навсегда; force - сразу снять с профессии
function pmeta:TeamBan(t, time, force)
	t = tonumber(t)
	if not t or not DarkRP.Teams[t] then return false end

	time = math.max(math.floor(tonumber(time) or 0), 0)

	self.jobbans = self.jobbans or {}
	self.jobbans[t] = time > 0 and os.time() + time or 0

	saveJobBans(self)
	applyBanVars(self)

	local char = self:getDarkRPVar("character") or 1
	local def = MCR and MCR.DefTeams and MCR.DefTeams[char]
	local current = self:Team()

	if force and def then
		local currentJob = DarkRP.Teams[current]

		if current == t and t ~= def then
			self:ChangeTeam(def, true)
		elseif t == def and current ~= def and currentJob and currentJob.char == char then
			self:ChangeTeam(def, true)
		end
	end

	DarkRP.log("other", self, nil, "бан профессии " .. team.GetName(t), nil, time > 0 and niceTime(time) or "навсегда")

	return true
end

function pmeta:TeamUnBan(t)
	t = tonumber(t)
	if not t or not self.jobbans or not self.jobbans[t] then return false end

	self.jobbans[t] = nil
	saveJobBans(self)
	applyBanVars(self)

	DarkRP.log("other", self, nil, "разбан профессии " .. team.GetName(t))

	return true
end

timer.Create("DarkRP.JobBanExpire", 60, 0, function()
	local now = os.time()

	for _, ply in ipairs(player.GetHumans()) do
		if not ply.jobbans or ply.DarkRPUnInitialized then continue end

		local changed = false

		for t, unban in pairs(ply.jobbans) do
			if unban ~= 0 and unban <= now then
				ply.jobbans[t] = nil
				changed = true
			end
		end

		if changed then
			saveJobBans(ply)
			applyBanVars(ply)
		end
	end
end)

--[[---------------------------------------------------------------------------
	Бан/разбан по SteamID64 или STEAM_X:Y:Z (в том числе офлайн)
	DarkRP.TeamBanId(id, job, time) - time nil = разбан
---------------------------------------------------------------------------]]
local function toSteamID64(id)
	id = string.Trim(tostring(id or ""))

	if string.match(id, "^7656%d+$") then return id end

	if string.match(id, "^STEAM_%d:%d:%d+$") then
		local sid64 = util.SteamIDTo64(id)
		if sid64 and sid64 ~= "0" then return sid64 end
	end
end

function DarkRP.TeamBanId(id, job, time)
	local uid = toSteamID64(id)
	job = tonumber(job)
	if not uid or not job or not DarkRP.Teams[job] then return false end

	local ply = player.GetBySteamID64(uid)

	if IsValid(ply) then
		if time == nil then
			return ply:TeamUnBan(job)
		end

		return ply:TeamBan(job, time, true)
	end

	if not DarkRP.DBReady then return false end

	MySQLite.query("SELECT data FROM darkrp_jobban WHERE uid = " .. uid, function(result)
		local bans = parseBans(result and result[1] and result[1].data)

		if time == nil then
			bans[job] = nil
		else
			local seconds = math.max(math.floor(tonumber(time) or 0), 0)
			bans[job] = seconds > 0 and os.time() + seconds or 0
		end

		if table.IsEmpty(bans) then
			MySQLite.query("DELETE FROM darkrp_jobban WHERE uid = " .. uid, nil, dbError)
		else
			MySQLite.query(string.format("REPLACE INTO darkrp_jobban(uid, data) VALUES(%s, %s)", uid, MySQLite.SQLStr(util.TableToJSON(bans))), nil, dbError)
		end

		DarkRP.log("other", nil, nil, (time == nil and "разбан" or "бан") .. " профессии " .. team.GetName(job) .. " для " .. uid)
	end, dbError)

	return true
end