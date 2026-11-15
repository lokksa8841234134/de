--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	sAdmin: джайл, ноуклип и невидимость, наблюдение (FSpectate), скринграб,
	отложенные команды, обращения к администрации, возвраты имущества

	Таблицы:
		sadmin_storedcmds - sid (SteamID), data (JSON: команда и кто её сохранил)
		sadmin_restore    - id, sid (SteamID), data (JSON заявки на возврат)

	sAdmin.jailPly(ply, time)            - джайл на месте на time секунд (0 - до разджайла)
	sAdmin.unjailPly(ply)
	sAdmin.startSpectate(ply, target)    - наблюдение за игроком (target nil - свободная камера)
	sAdmin.Grab(target, context, auto)   - скриншот экрана игрока: ссылка в Discord (admin_e) и журнал
	sAdmin.StoreCmd(sid, args, admin)    - команда от имени консоли при следующем входе игрока
	sAdmin.RemoveCmd(sid)
	sAdmin.SendTickets(target)           - обращения игроку (target nil - всей администрации)
	sAdmin.ApproveRestoreTicket(ply, id) - одобрить заявку на возврат и выдать, если игрок на сервере

	Ключ сервиса загрузки скриншотов: sadmin_grab_key (server.cfg).
---------------------------------------------------------------------------]]
sAdmin = sAdmin or {}
sAdmin.jailData = sAdmin.jailData or {}
sAdmin.requests = sAdmin.requests or {}
sAdmin.RestoreTickets = sAdmin.RestoreTickets or {tickets = {}}
sAdmin.RestoreTickets.tickets = sAdmin.RestoreTickets.tickets or {}
sAdmin.godded = sAdmin.godded or {}
sAdmin.cloakedPeople = sAdmin.cloakedPeople or {}
sAdmin.muted = sAdmin.muted or {}
sAdmin.gagged = sAdmin.gagged or {}

util.AddNetworkString("S2C_Union_Spawn")
util.AddNetworkString("FSpectate")
util.AddNetworkString("FSpectateTarget")
util.AddNetworkString("SincoMoni")
util.AddNetworkString("sA:GetAdminData")
util.AddNetworkString("sA:ApplyToAdmin")
util.AddNetworkString("sA:CloseRequest")
util.AddNetworkString("sA:RestoreSync")
util.AddNetworkString("sA:RestoreAction")
util.AddNetworkString("sA:RestoreCreate")

local MAX_INT = 2 ^ 53
local MAX_NET = 60000 -- предел сжатых данных в одном сообщении, байт

local JAIL_RADIUS = 96

local GRAB_TIMEOUT = 120
local AUTO_GRAB_DELAY = 60

local TICKET_MIN, TICKET_MAX = 10, 1000
local TICKET_DELAY = 30
local TICKET_KEEP_CLOSED = 10800 -- закрытые обращения хранятся 3 часа
local TICKET_KEEP_OPEN = 86400 -- открытые - сутки

local RESTORE_MAX_ITEMS = 50
local RESTORE_MAX_JSON = 16384
local RESTORE_KEEP = 2592000 -- выданные заявки хранятся 30 дней

-- команды, которые нельзя отложить через runcmd
local BLOCKED_STORED = {
	["runcmd"] = true,
	["removecmd"] = true
}

-- категории DarkRP для возврата, если инвентарь не задал свои
local DEFAULT_RESTORE_CATS = {
	["Weapons"] = true,
	["Entities"] = true,
	["Ammo"] = true,
	["Food"] = true,
	["Junk"] = true
}

local grabKey = CreateConVar("sadmin_grab_key", "", {FCVAR_ARCHIVE, FCVAR_PROTECTED}, "Ключ сервиса загрузки скриншотов для скринграба sAdmin")

local esc = slib.dbEscape

local function int(value)
	local n = tonumber(value) or 0
	if n ~= n then n = 0 end

	return string.format("%.0f", math.floor(math.Clamp(n, -MAX_INT, MAX_INT)))
end

local function consoleName()
	return slib.getLang("sadmin", sAdmin.config["language"], "console")
end

-- текст: валидный UTF-8 без 4-байтовых символов, без пробелов по краям, не длиннее max символов
local function cleanText(str, max)
	str = utf8.force(tostring(str or ""))
	str = string.gsub(str, "[\240-\247][\128-\191][\128-\191][\128-\191]", "")

	return string.Trim(utf8.sub(string.Trim(str), 1, max or 255))
end

local function describe(ply)
	if not IsValid(ply) then return consoleName() end

	return string.format("%s (%s, %s)", ply:Nick(), ply:SteamName(), ply:SteamID())
end

local function adminSID(admin)
	return IsValid(admin) and admin:IsPlayer() and admin:SteamID64() or "0"
end

local function immunity(ply)
	return tonumber(sAdmin.hasPermission(ply, "immunity")) or 0
end

local function log(ply, text, target, value, category)
	if DarkRP and DarkRP.log then
		DarkRP.log(category or "admin", IsValid(ply) and ply or nil, IsValid(target) and target or nil, text, nil, value)
	end
end

local function discord(channel, content)
	if Discord and isfunction(Discord.Log) then
		Discord.Log(channel, {content = content, allowed_mentions = {parse = {}}})
	end
end

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

-- SteamID или SteamID64 -> "STEAM_0:X:Y", иначе nil
local function normalizeSID(sid)
	sid = string.upper(string.Trim(tostring(sid or "")))

	if #sid == 17 and string.match(sid, "^7656119%d+$") then
		sid = util.SteamIDFrom64(sid) or ""
	end

	sid = string.gsub(sid, "^STEAM_1:", "STEAM_0:")

	return string.match(sid, "^STEAM_0:[01]:%d+$") and sid or nil
end

--[[---------------------------------------------------------------------------
	Джайл: игрок удерживается там, где его заджайлили. Без атаки, пропов,
	транспорта, ноуклипа и самоубийства. Оставшийся срок хранится в PData
	и продолжается при следующем входе.
---------------------------------------------------------------------------]]
-- снять невидимость, включённую клавишей ноуклипа
local function dropNoclipCloak(ply)
	if not ply.sA_noclipCloak then return end
	ply.sA_noclipCloak = nil

	if sAdmin.cloakedPeople[ply:SteamID64()] and sAdmin.cloakHandle then
		sAdmin.cloakHandle(ply)
	end
end

local function leaveNoclip(ply)
	if ply:GetMoveType() == MOVETYPE_NOCLIP then
		ply:SetMoveType(MOVETYPE_WALK)
	end

	dropNoclipCloak(ply)
end

-- точка на полу под игроком: заджайленный в воздухе не падает бесконечно
local function groundPos(ply)
	local pos = ply:GetPos()

	local tr = util.TraceLine({
		start = pos + Vector(0, 0, 8),
		endpos = pos - Vector(0, 0, 8192),
		filter = ply,
		mask = MASK_PLAYERSOLID
	})

	return (tr.Hit and not tr.StartSolid) and tr.HitPos or pos
end

local function clearJail(ply)
	sAdmin.jailData[ply:SteamID64()] = nil
	ply.sA_Jailed = nil
	ply.sA_PendingJail = nil
	ply:RemovePData("sA:jail")
end

sAdmin.jailPly = function(ply, time)
	if not IsValid(ply) or not ply:IsPlayer() then return false end

	time = tonumber(time) or 0
	if time ~= time then time = 0 end
	time = math.Clamp(math.floor(time), 0, MAX_INT)

	if ply:InVehicle() then ply:ExitVehicle() end
	leaveNoclip(ply)

	sAdmin.jailData[ply:SteamID64()] = {
		pos = groundPos(ply),
		release = time > 0 and CurTime() + time or 0
	}

	ply.sA_Jailed = true
	ply.sA_PendingJail = nil
	ply:SetPData("sA:jail", time)

	if time > 0 then
		sAdmin.msg(ply, "Вы помещены в джайл на %t.", time)
	else
		sAdmin.msg(ply, "Вы помещены в джайл до решения администрации.")
	end

	return true
end

sAdmin.unjailPly = function(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return false end

	local jailed = sAdmin.jailData[ply:SteamID64()] ~= nil or ply.sA_PendingJail ~= nil
	clearJail(ply)

	if jailed then
		sAdmin.msg(ply, "Вы освобождены из джайла.")
	end

	return jailed
end

timer.Create("sA:Jail", 1, 0, function()
	local now = CurTime()

	for _, ply in ipairs(player.GetAll()) do
		if not ply.sA_Jailed then continue end

		local data = sAdmin.jailData[ply:SteamID64()]

		if not data then
			ply.sA_Jailed = nil
			continue
		end

		if data.release > 0 and data.release <= now then
			clearJail(ply)
			sAdmin.msg(ply, "Срок джайла истёк, вы свободны.")
			continue
		end

		if ply.MCRHidden or not ply:Alive() then continue end

		if ply:InVehicle() then ply:ExitVehicle() end
		leaveNoclip(ply)

		if ply:GetPos():DistToSqr(data.pos) > JAIL_RADIUS * JAIL_RADIUS then
			ply:SetPos(data.pos)
			ply:SetLocalVelocity(vector_origin)
		end
	end
end)

hook.Add("StartCommand", "sA:Jail", function(ply, cmd)
	if not ply.sA_Jailed then return end

	cmd:RemoveKey(IN_ATTACK)
	cmd:RemoveKey(IN_ATTACK2)
end)

local function blockJailed(ply)
	if ply.sA_Jailed then return false end
end

for _, name in ipairs({
	"CanPlayerSuicide", "CanPlayerEnterVehicle", "PlayerGiveSWEP",
	"PlayerSpawnObject", "PlayerSpawnSENT", "PlayerSpawnSWEP", "PlayerSpawnVehicle",
	"PlayerSpawnNPC", "PlayerSpawnProp", "PlayerSpawnEffect", "PlayerSpawnRagdoll"
}) do
	hook.Add(name, "sA:Jail", blockJailed)
end

hook.Add("PlayerDisconnected", "sA:Jail", function(ply)
	local sid64 = ply:SteamID64()
	local data = sid64 and sAdmin.jailData[sid64]
	if not data then return end

	sAdmin.jailData[sid64] = nil

	-- бессрочный джайл уже записан в PData как 0
	if data.release <= 0 then return end

	local left = math.ceil(data.release - CurTime())

	if left > 0 then
		ply:SetPData("sA:jail", left)
	else
		ply:RemovePData("sA:jail")
	end
end)

hook.Add("PlayerInitialSpawn", "sA:Jail", function(ply)
	local time = tonumber(ply:GetPData("sA:jail"))

	if time and time == time and time >= 0 then
		ply.sA_PendingJail = math.floor(time)
	end
end)

-- после возрождения: бессмертие, джайл (не в меню выбора персонажа)
hook.Add("PlayerSpawn", "sA:SpawnState", function(ply)
	timer.Simple(0, function()
		if not IsValid(ply) then return end

		local sid64 = ply:SteamID64()

		if sAdmin.godded[sid64] then
			ply:GodEnable()
		end

		if ply:GetMoveType() ~= MOVETYPE_NOCLIP then
			dropNoclipCloak(ply)
		end

		if ply.MCRHidden then return end

		if ply.sA_PendingJail then
			sAdmin.jailPly(ply, ply.sA_PendingJail)
		elseif ply.sA_Jailed and sAdmin.jailData[sid64] then
			ply:SetPos(sAdmin.jailData[sid64].pos)
		end
	end)
end)

--[[---------------------------------------------------------------------------
	Ноуклип по клавише: право noclip, не в джайле, не в транспорте, не в пилюле
	и не без сознания (рэгдолл лежит, а невидимый игрок улетел бы).
	При auto_cloak_on_noclip включается невидимость, при выходе она снимается.
---------------------------------------------------------------------------]]
hook.Add("PlayerNoClip", "sA:NoClip", function(ply, desired)
	if not desired then
		dropNoclipCloak(ply)
		return true
	end

	if ply.sA_Jailed or ply.MCRHidden or not ply:Alive() or ply:InVehicle() or ply:getDarkRPVar("unconscious") then return false end
	if not sAdmin.hasPermission(ply, "noclip") then return false end
	if pk_pills and isfunction(pk_pills.getMappedEnt) and IsValid(pk_pills.getMappedEnt(ply)) then return false end

	if sAdmin.config["auto_cloak_on_noclip"] and sAdmin.cloakHandle and not sAdmin.cloakedPeople[ply:SteamID64()] then
		sAdmin.cloakHandle(ply, true)
		ply.sA_noclipCloak = true
	end

	return true
end)

--[[---------------------------------------------------------------------------
	Невидимость: скрыть невидимых от вошедших позже игроков и новое оружие,
	состояния (невидимость, мут, гег) для загрузившегося клиента
---------------------------------------------------------------------------]]
local function setWeaponHidden(wep, owner, hide)
	for _, viewer in ipairs(player.GetAll()) do
		if viewer ~= owner then
			wep:SetPreventTransmit(viewer, hide)
		end
	end

	wep.sA_Hidden = hide or nil
end

hook.Add("PlayerInitialSpawn", "sA:Cloak", function(viewer)
	timer.Simple(0, function()
		if not IsValid(viewer) then return end

		for sid64, state in pairs(sAdmin.cloakedPeople) do
			local target = state and player.GetBySteamID64(sid64)
			if not IsValid(target) or target == viewer then continue end

			target:SetPreventTransmit(viewer, true)

			for _, wep in ipairs(target:GetWeapons()) do
				wep:SetPreventTransmit(viewer, true)
			end
		end
	end)
end)

hook.Add("WeaponEquip", "sA:Cloak", function(wep, owner)
	timer.Simple(0, function()
		if not IsValid(wep) or not IsValid(owner) or not sAdmin.cloakedPeople[owner:SteamID64()] then return end

		setWeaponHidden(wep, owner, true)
	end)
end)

-- выброшенное невидимым оружие снова видно всем
hook.Add("PlayerDroppedWeapon", "sA:Cloak", function(owner, wep)
	if not IsValid(wep) then return end

	if wep.sA_Hidden or (IsValid(owner) and sAdmin.cloakedPeople[owner:SteamID64()]) then
		setWeaponHidden(wep, owner, false)
	end
end)

hook.Add("PlayerDisconnected", "sA:Cloak", function(ply)
	local sid64 = ply:SteamID64()
	if not sid64 or not sAdmin.cloakedPeople[sid64] then return end

	sAdmin.cloakedPeople[sid64] = nil
	sAdmin.networkData(nil, {"cloakedPeople", sid64}, nil)
end)

hook.Add("slib.FullLoaded", "sA:SendStates", function(ply)
	for _, key in ipairs({"cloakedPeople", "muted", "gagged"}) do
		for sid64, state in pairs(sAdmin[key]) do
			if state then
				sAdmin.networkData(ply, {key, sid64}, true)
			end
		end
	end
end)

--[[---------------------------------------------------------------------------
	Наблюдение (FSpectate)
	"FSpectate" сервер -> клиент: Bool свободная камера, Entity цель (NULL - нет)
	"FSpectateTarget" клиент -> сервер: Entity новая цель
	Консоль: rp_spec <UserID>, _specupd x y z (позиция камеры), end_spect
---------------------------------------------------------------------------]]
local function canSpectate(ply)
	return IsValid(ply) and (sAdmin.hasPermission(ply, "FSpectate") or sAdmin.hasPermission(ply, "spectate"))
end

local function sendSpectate(ply, roaming, target)
	net.Start("FSpectate")
		net.WriteBool(roaming)
		net.WriteEntity(IsValid(target) and target or NULL)
	net.Send(ply)
end

sAdmin.startSpectate = function(ply, target)
	if not IsValid(ply) or not ply:IsPlayer() then return false end

	if IsValid(target) and target:IsPlayer() and not sAdmin.canTarget(ply, target) then
		sAdmin.msg(ply, "unavailable_plys", target)
		return false
	end

	ply.FSpectating = true
	ply.FSpectatingEnt = IsValid(target) and target or nil
	ply.FSpectatePos = nil

	if ply:InVehicle() then ply:ExitVehicle() end

	sendSpectate(ply, not IsValid(target), target)
	log(ply, IsValid(target) and "начал наблюдение за игроком" or "начал наблюдение (свободная камера)", target)

	return true
end

concommand.Add("rp_spec", function(ply, cmd, args)
	if not IsValid(ply) then return end

	if not canSpectate(ply) then
		sAdmin.msg(ply, "no_permission", "FSpectate")
		return
	end

	if sAdmin.throttle(ply, "spectate", 0.5) then return end

	local target

	if args[1] then
		target = Player(math.floor(tonumber(args[1]) or -1))

		if not IsValid(target) then
			sAdmin.msg(ply, "no_targets")
			return
		end

		if target == ply then
			sAdmin.msg(ply, "cant_target_self")
			return
		end
	end

	sAdmin.startSpectate(ply, target)
end)

-- позиция свободной камеры от клиента (раз в 0.5 секунды)
concommand.Add("_specupd", function(ply, cmd, args)
	if not IsValid(ply) or not ply.FSpectating or not canSpectate(ply) then return end

	local x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
	if not x or not y or not z or x ~= x or y ~= y or z ~= z then return end

	ply.FSpectatePos = Vector(math.Clamp(x, -32768, 32768), math.Clamp(y, -32768, 32768), math.Clamp(z, -32768, 32768))
	ply.FSpectatingEnt = nil
end)

concommand.Add("end_spect", function(ply)
	if not IsValid(ply) then return end

	ply.FSpectating = nil
	ply.FSpectatingEnt = nil
	ply.FSpectatePos = nil
end)

net.Receive("FSpectateTarget", function(len, ply)
	if not IsValid(ply) or not ply.FSpectating or not canSpectate(ply) then return end

	local target = net.ReadEntity()
	if not IsValid(target) or target == ply then return end

	-- клиент уже переключил камеру: вернуть его в свободный режим
	if target:IsPlayer() and not sAdmin.canTarget(ply, target) then
		if not sAdmin.throttle(ply, "spectate_denied", 1) then
			sAdmin.msg(ply, "unavailable_plys", target)
		end

		sendSpectate(ply, true, NULL)
		return
	end

	ply.FSpectatingEnt = target
	ply.FSpectatePos = nil
end)

hook.Add("SetupPlayerVisibility", "sA:Spectate", function(ply)
	if not ply.FSpectating then return end

	local ent = ply.FSpectatingEnt

	if IsValid(ent) then
		AddOriginToPVS(ent:IsPlayer() and ent:GetShootPos() or ent:GetPos())
	elseif ply.FSpectatePos then
		AddOriginToPVS(ply.FSpectatePos)
	end
end)

-- наблюдающий слышит голос рядом с целью или камерой (не позиционно);
-- без сознания игрок молчит (server/sv_chat.lua)
hook.Add("PlayerCanHearPlayersVoice", "sA:Spectate", function(listener, talker)
	if not listener.FSpectating or listener == talker then return end
	if not IsValid(talker) or not talker:Alive() or talker.MCRHidden or sAdmin.gagged[talker:SteamID64()] then return end
	if talker.getDarkRPVar and talker:getDarkRPVar("unconscious") then return end

	local ent = listener.FSpectatingEnt
	local origin = IsValid(ent) and ent:GetPos() or listener.FSpectatePos
	if not origin then return end

	local radius = DarkRP and DarkRP.ChatRadius and DarkRP.ChatRadius(talker) or 500

	if origin:DistToSqr(talker:GetPos()) <= radius * radius then
		return true, false
	end
end)

--[[---------------------------------------------------------------------------
	Скринграб
	"SincoMoni" сервер -> клиент: String id, String ключ сервиса загрузки
	клиент -> сервер: String id, String ссылка или String "er;" .. id, String ошибка
---------------------------------------------------------------------------]]
local grabs = {} -- sid64 -> ожидаемый скриншот
local autoGrabs = {} -- sid64 -> CurTime, раньше которого автоскриншот не делается

sAdmin.Grab = function(target, context, auto)
	if not IsValid(target) or not target:IsPlayer() or target:IsBot() then return false end

	local key = grabKey:GetString()

	if key == "" then
		if not auto then
			sAdmin.msg(sAdmin.logPerm(), "Скринграб недоступен: на сервере не задан sadmin_grab_key.")
		end

		return false
	end

	local sid64, now = target:SteamID64(), CurTime()

	if auto then
		if (autoGrabs[sid64] or 0) > now then return false end
		autoGrabs[sid64] = now + AUTO_GRAB_DELAY
	end

	-- один ожидаемый скриншот на игрока
	if grabs[sid64] and grabs[sid64].time + GRAB_TIMEOUT > now then return false end

	local id = string.format("%08x%08x", math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))

	grabs[sid64] = {
		id = id,
		time = now,
		auto = auto == true,
		context = (IsValid(context) and context:IsPlayer()) and describe(context) or nil
	}

	net.Start("SincoMoni")
		net.WriteString(id)
		net.WriteString(key)
	net.Send(target)

	return true
end

net.Receive("SincoMoni", function(len, ply)
	if not IsValid(ply) then return end

	local sid64 = ply:SteamID64()
	local grab = grabs[sid64]
	if not grab then return end

	local id, data = net.ReadString(), net.ReadString()
	local failed = string.sub(id, 1, 3) == "er;"

	if failed then
		id = string.sub(id, 4)
	end

	if id ~= grab.id then return end
	grabs[sid64] = nil

	local title = (grab.auto and "Автоскриншот " or "Скриншот ") .. describe(ply) .. (grab.context and " (удар по " .. grab.context .. ")" or "")

	if failed then
		local err = cleanText(data, 200)

		log(ply, "скринграб не удался", nil, err)

		if not grab.auto then
			sAdmin.msg(sAdmin.logPerm(), "Скриншот %s не получен: %s", ply, err)
		end

		return
	end

	if #data > 512 or not string.match(data, "^https?://%S+$") then
		log(ply, "скринграб: клиент прислал неверную ссылку")
		return
	end

	discord("admin_e", title .. ": " .. data)
	log(ply, grab.auto and "автоскриншот" or "скриншот", nil, data)

	if not grab.auto then
		sAdmin.msg(sAdmin.logPerm(), "Скриншот %s: %s", ply, data)
	end
end)

timer.Create("sA:Grabs", 60, 0, function()
	local now = CurTime()

	for sid64, grab in pairs(grabs) do
		if grab.time + GRAB_TIMEOUT <= now then
			grabs[sid64] = nil
		end
	end

	for sid64, time in pairs(autoGrabs) do
		if time <= now then
			autoGrabs[sid64] = nil
		end
	end
end)

hook.Add("PlayerDisconnected", "sA:Grabs", function(ply)
	local sid64 = ply:SteamID64()

	if sid64 then
		grabs[sid64] = nil
	end
end)

--[[---------------------------------------------------------------------------
	Отложенные команды (runcmd): одна команда на SteamID, выполняется от имени
	консоли при следующем входе игрока (сразу, если он на сервере).
	"^" в аргументах заменяется на этого игрока. Сохранить можно только команду,
	на которую у администратора есть право; цель с иммунитетом выше, чем
	у сохранившего, команду не получит.
---------------------------------------------------------------------------]]
local function resolveCommand(word)
	if not isstring(word) then return end
	word = string.lower(word)

	if sAdmin.commands[word] then return word end

	local name = sAdmin.abbreviations[word]
	if name and sAdmin.commands[name] then return name end
end

local function quoteArg(arg)
	arg = string.gsub(tostring(arg), "\"", "")

	return string.find(arg, "%s") and "\"" .. arg .. "\"" or arg
end

-- строка команды -> имя, аргументы (хвост сливается в последний текстовый параметр)
local function parseStored(line)
	local args = sAdmin.splitArgs(line)
	local name = resolveCommand(table.remove(args, 1))
	if not name then return end

	local inputs = sAdmin.commands[name].inputs
	local count = istable(inputs) and #inputs or 0

	if count > 0 and #args > count and inputs[count][1] == "text" then
		local tail = table.concat(args, " ", count)

		for i = #args, count + 1, -1 do
			args[i] = nil
		end

		args[count] = tail
	end

	return name, args
end

local function runStored(ply, data)
	if not IsValid(ply) or not istable(data) or not isstring(data.cmd) then return end

	local name, args = parseStored(data.cmd)
	if not name or BLOCKED_STORED[name] then return end

	local limit = tonumber(data.immunity)

	if limit and immunity(ply) > limit then
		log(nil, "отложенная команда не выполнена (иммунитет цели выше): " .. data.cmd, ply, data.admin)
		return
	end

	local sid64 = ply:SteamID64()

	for i, v in ipairs(args) do
		if v == "^" then
			args[i] = sid64
		end
	end

	log(nil, "выполнена отложенная команда: " .. data.cmd, ply, data.admin)

	table.insert(args, 1, name)
	concommand.Run(NULL, "sa", args, table.concat(args, " "))
end

sAdmin.StoreCmd = function(sid, args, admin)
	sid = normalizeSID(sid)
	if not sid or not istable(args) or args[2] == nil then return false end

	local line

	-- из чата команда приходит одной строкой, из консоли - отдельными аргументами
	if #args == 2 then
		line = tostring(args[2])
	else
		local parts = {}

		for i = 2, #args do
			parts[#parts + 1] = quoteArg(args[i])
		end

		line = table.concat(parts, " ")
	end

	line = cleanText(line, 1000)

	local name = line ~= "" and parseStored(line)
	if not name or BLOCKED_STORED[name] then return false end

	if IsValid(admin) and not sAdmin.hasPermission(admin, name) then return false end

	local data = {
		cmd = line,
		admin = adminSID(admin),
		time = os.time()
	}

	-- консоль и super_users без ограничения иммунитета
	if IsValid(admin) and not sAdmin.config["super_users"][admin:SteamID64()] then
		data.immunity = immunity(admin)
	end

	local target = player.GetBySteamID(sid)

	if IsValid(target) then
		xpcall(runStored, ErrorNoHaltWithStack, target, data)
		return true
	end

	slib.dbQuery("REPLACE INTO sadmin_storedcmds (sid, data) VALUES (" .. esc(sid) .. ", " .. esc(util.TableToJSON(data)) .. ")")
	log(admin, "сохранил отложенную команду для " .. sid .. ": " .. line)

	return true
end

sAdmin.RemoveCmd = function(sid)
	sid = normalizeSID(sid)
	if not sid then return false end

	slib.dbQuery("DELETE FROM sadmin_storedcmds WHERE sid = " .. esc(sid))

	return true
end

hook.Add("slib.FullLoaded", "sA:StoredCmds", function(ply)
	if ply:IsBot() then return end

	-- после загрузки ранга и данных игрока
	timer.Simple(3, function()
		if not IsValid(ply) then return end

		local sid = ply:SteamID()

		slib.dbQuery("SELECT data FROM sadmin_storedcmds WHERE sid = " .. esc(sid), function(rows)
			if not rows[1] or not IsValid(ply) then return end

			slib.dbQuery("DELETE FROM sadmin_storedcmds WHERE sid = " .. esc(sid))
			xpcall(runStored, ErrorNoHaltWithStack, ply, util.JSONToTable(rows[1].data or "") or {})
		end)
	end)
end)

--[[---------------------------------------------------------------------------
	Обращения к администрации (F4 -> вызов администратора), до смены карты.
	Игрок получает только свои обращения; переписка (/dm) и принявший
	администратор видны только администрации.
	"sA:GetAdminData" сервер -> клиент: UInt(32) длина, сжатая таблица обращений
---------------------------------------------------------------------------]]
local lastTicketId = table.maxn(sAdmin.requests)

local function isStaff(ply)
	return IsValid(ply) and sAdmin.hasPermission(ply, "is_staff") and true or false
end

local function ticketReason(kind)
	local reasons = MSD and istable(MSD.AdminReasons) and MSD.AdminReasons

	if reasons then return reasons[kind] end

	return (kind >= 1 and kind <= 5) and tostring(kind) or nil
end

local function ticketCopy(req, staff)
	local copy = {
		type = req.type,
		text = req.text,
		sid64 = req.sid64,
		steamname = req.steamname,
		name = req.name,
		time = req.time,
		accepted = req.accepted,
		bad = req.bad,
		closed_time = req.closed_time,
		chat = req.chat and true or nil
	}

	if staff then
		copy.chatlog = req.chatlog
		copy.admin = req.admin
		copy.admin_name = req.admin_name
		copy.mainadmin = req.mainadmin
	end

	return copy
end

local function ticketData(ply, staff, openOnly)
	local list, sid64 = {}, ply:SteamID64()

	for id, req in pairs(sAdmin.requests) do
		if not staff and req.sid64 ~= sid64 then continue end
		if openOnly and req.accepted then continue end

		list[id] = ticketCopy(req, staff)
	end

	return DarkRP.TableCompress(list)
end

local function sendTicketsTo(ply)
	local staff = isStaff(ply)
	local data, size = ticketData(ply, staff)

	-- слишком много данных: только открытые обращения
	if size > MAX_NET then
		data, size = ticketData(ply, staff, true)
		if size > MAX_NET then return end
	end

	net.Start("sA:GetAdminData")
		net.WriteUInt(size, 32)
		net.WriteData(data, size)
	net.Send(ply)
end

sAdmin.SendTickets = function(target)
	if target ~= nil then
		if IsValid(target) and target:IsPlayer() and not target:IsBot() then
			sendTicketsTo(target)
		end

		return
	end

	for _, v in ipairs(player.GetHumans()) do
		if isStaff(v) then
			sendTicketsTo(v)
		end
	end
end

--[[---------------------------------------------------------------------------
	Новое обращение: окно «Связь с администрацией» (sA:ApplyToAdmin) и
	жалоба на массовое убийство из меню F1 (sa_rdm). Одно открытое обращение
	на игрока, не чаще TICKET_DELAY
---------------------------------------------------------------------------]]
function sAdmin.CreateRequest(ply, kind, text)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	local reason = ticketReason(kind)
	if not reason then return end

	text = cleanText(text, TICKET_MAX)

	if (utf8.len(text) or 0) < TICKET_MIN then
		sAdmin.msg(ply, "Опишите обращение подробнее: не меньше %s символов.", TICKET_MIN)
		return
	end

	local sid64 = ply:SteamID64()

	for id, req in pairs(sAdmin.requests) do
		if req.sid64 == sid64 and not req.accepted then
			sAdmin.msg(ply, "У вас уже есть открытое обращение №%s, дождитесь ответа.", id)
			return
		end
	end

	if sAdmin.throttle(ply, "ticket", TICKET_DELAY) then
		sAdmin.msg(ply, "request_rate_limit")
		return
	end

	lastTicketId = math.max(lastTicketId, table.maxn(sAdmin.requests)) + 1
	local id = lastTicketId

	sAdmin.requests[id] = {
		type = kind,
		text = text,
		sid64 = sid64,
		steamname = ply:SteamName(),
		name = ply:Nick(),
		time = os.time(),
		accepted = false
	}

	sAdmin.msg(ply, "Обращение №%s отправлено администрации.", id)

	for _, v in ipairs(player.GetHumans()) do
		if v ~= ply and isStaff(v) then
			sAdmin.msg(v, "Новое обращение №%s от %s: %s", id, ply, reason)
		end
	end

	discord("request", string.format("Обращение №%d (%s) от %s:\n%s", id, reason, describe(ply), text))
	log(ply, "создал обращение №" .. id, nil, reason)

	sAdmin.SendTickets()

	return id
end

net.Receive("sA:ApplyToAdmin", function(len, ply)
	if not IsValid(ply) then return end

	local kind = net.ReadUInt(3)
	local text = net.ReadString()

	sAdmin.CreateRequest(ply, kind, text)
end)

--[[---------------------------------------------------------------------------
	sa_rdm - «Массовое убийство без причины» в меню F1 (msd/ui/msdhelpmenu.lua,
	кнопка только у мёртвого): обращение «Серьёзное нарушение правил игры»
	(MSD.AdminReasons[5]) о том, кто убил игрока. Убийца запоминается при
	смерти (PlayerDeath) до возрождения. Убит не игроком - обращения нет
---------------------------------------------------------------------------]]
local RDM_KIND = 5

hook.Add("PlayerDeath", "sA:RDMReport", function(victim, inflictor, attacker)
	if not IsValid(victim) then return end

	if IsValid(attacker) and attacker:IsVehicle() and IsValid(attacker:GetDriver()) then
		attacker = attacker:GetDriver()
	end

	if not IsValid(attacker) or not attacker:IsPlayer() or attacker == victim then
		victim.sA_LastKiller = nil
		return
	end

	local weapon = IsValid(inflictor) and inflictor ~= attacker and inflictor:GetClass() or nil

	if not weapon then
		local wep = attacker:GetActiveWeapon()
		weapon = IsValid(wep) and wep:GetClass() or nil
	end

	victim.sA_LastKiller = {
		text = describe(attacker),
		weapon = weapon,
		time = os.time()
	}
end)

hook.Add("PlayerSpawn", "sA:RDMReport", function(ply)
	ply.sA_LastKiller = nil
end)

concommand.Add("sa_rdm", function(ply)
	if not IsValid(ply) or ply:Alive() then return end

	local kill = ply.sA_LastKiller
	if not kill then return end

	local text = string.format("Массовое убийство без причины. Убийца: %s%s, %s.",
		kill.text, kill.weapon and (", оружие " .. kill.weapon) or "", os.date("%H:%M:%S", kill.time))

	sAdmin.CreateRequest(ply, RDM_KIND, text)
end)

net.Receive("sA:CloseRequest", function(len, ply)
	if not isStaff(ply) or sAdmin.throttle(ply, "ticket_close", 0.5) then return end

	local id, bad = net.ReadUInt(32), net.ReadBool()
	local req = sAdmin.requests[id]
	if not req or req.accepted then return end

	req.accepted = true
	req.bad = bad or nil
	req.admin = ply:SteamID64()
	req.admin_name = ply:SteamName()
	req.closed_time = os.time()

	local requester = player.GetBySteamID64(req.sid64)

	if IsValid(requester) and requester ~= ply then
		sAdmin.msg(requester, bad and "Обращение №%s отклонено администрацией." or "Обращение №%s принято администрацией.", id)
	end

	for _, v in ipairs(player.GetHumans()) do
		if isStaff(v) then
			sAdmin.msg(v, bad and "%s отклонил обращение №%s." or "%s принял обращение №%s.", ply, id)
		end
	end

	discord("request", string.format("Обращение №%d %s: %s", id, bad and "отклонено" or "принято", describe(ply)))
	log(ply, (bad and "отклонил" or "принял") .. " обращение №" .. id, requester)

	sAdmin.SendTickets()

	if IsValid(requester) and not isStaff(requester) then
		sAdmin.SendTickets(requester)
	end
end)

net.Receive("sA:GetAdminData", function(len, ply)
	if not isStaff(ply) or sAdmin.throttle(ply, "tickets", 1) then return end

	sAdmin.SendTickets(ply)
end)

timer.Create("sA:Tickets", 60, 0, function()
	local now, changed = os.time(), false

	for id, req in pairs(sAdmin.requests) do
		local expired

		if req.accepted then
			expired = (req.closed_time or req.time or 0) + TICKET_KEEP_CLOSED < now
		else
			expired = (req.time or 0) + TICKET_KEEP_OPEN < now
		end

		if expired then
			sAdmin.requests[id] = nil
			changed = true
		end
	end

	if changed then
		sAdmin.SendTickets()
	end
end)

--[[---------------------------------------------------------------------------
	Возвраты имущества: заявку создаёт restore_create, одобряет restore_approve.
	Одобренная заявка выдаётся, когда игрок на сервере и выбрал персонажа
	(предметы - только при серверном инвентаре McINV.AddCustomItem).
	"sA:RestoreSync" сервер -> клиент: UInt(2) 0 - UInt(32) длина, сжатые заявки;
		1 - String JSON {id, ticket} (ticket nil - заявка удалена)
---------------------------------------------------------------------------]]
local function canViewRestore(ply)
	return IsValid(ply) and (sAdmin.hasPermission(ply, "restore_create") or sAdmin.hasPermission(ply, "restore_approve")) and true or false
end

local function restoreViewers()
	local list = {}

	for _, v in ipairs(player.GetHumans()) do
		if canViewRestore(v) then
			list[#list + 1] = v
		end
	end

	return list
end

local function broadcastRestore(id)
	local list = restoreViewers()
	if #list == 0 then return end

	net.Start("sA:RestoreSync")
		net.WriteUInt(1, 2)
		net.WriteString(util.TableToJSON({id = id, ticket = sAdmin.RestoreTickets.tickets[id]}) or "{}")
	net.Send(list)
end

local function saveRestore(id)
	local ticket = sAdmin.RestoreTickets.tickets[id]
	if not ticket then return end

	slib.dbQuery("UPDATE sadmin_restore SET data = " .. esc(util.TableToJSON(ticket)) .. " WHERE id = " .. int(id))
end

local function validCategory(cat)
	local cats = (McINV and istable(McINV.DarkRPTypes)) and McINV.DarkRPTypes or DEFAULT_RESTORE_CATS

	return isstring(cat) and cats[cat] ~= nil and DarkRP and istable(DarkRP[cat])
end

-- только существующие предметы DarkRP, не больше RESTORE_MAX_ITEMS
local function cleanItems(items)
	local result, count = {}, 0
	if not istable(items) then return result, count end

	for cat, list in pairs(items) do
		if not validCategory(cat) or not istable(list) then continue end

		for _, class in ipairs(list) do
			if count >= RESTORE_MAX_ITEMS then break end

			if isstring(class) and DarkRP[cat][class] then
				result[cat] = result[cat] or {}
				table.insert(result[cat], class)
				count = count + 1
			end
		end
	end

	return result, count
end

local function tryDeliver(id)
	local ticket = sAdmin.RestoreTickets.tickets[id]
	if not ticket or not ticket.approved or ticket.delivered then return false end

	local ply = player.GetBySteamID(ticket.sid)
	if not IsValid(ply) or ply.DarkRPUnInitialized or ply.MCRHidden then return false end

	local hasItems = istable(ticket.items) and next(ticket.items) ~= nil
	if hasItems and not (McINV and isfunction(McINV.AddCustomItem)) then return false end

	-- сначала отметка о выдаче: ошибка ниже не приведёт к повторной выдаче
	ticket.delivered = true
	ticket.delivered_time = os.time()
	saveRestore(id)
	broadcastRestore(id)

	local money, failed = tonumber(ticket.money) or 0, 0

	if money > 0 and not pcall(ply.addMoney, ply, money) then
		failed = failed + 1
	end

	if hasItems then
		for cat, list in pairs(ticket.items) do
			local items = DarkRP[cat]

			for _, class in ipairs(istable(list) and list or {}) do
				local data = istable(items) and items[class]
				local ok, added = false, false

				-- как в DarkRP.DropHeldWeapon: ложный результат - предмет не добавлен
				if data then
					ok, added = pcall(McINV.AddCustomItem, ply, cat, class, table.Copy(data), true)
				end

				if not ok or not added then
					failed = failed + 1
				end
			end
		end
	end

	sAdmin.msg(ply, "Вам выдан возврат имущества по заявке №%s.", id)
	log(ply, "получил возврат по заявке №" .. id .. (failed > 0 and " (не выдано позиций: " .. failed .. ")" or ""), nil, money, "money")

	return true
end

local function deliverFor(ply)
	if not IsValid(ply) or ply:IsBot() then return end

	local sid = ply:SteamID()

	for id, ticket in pairs(sAdmin.RestoreTickets.tickets) do
		if ticket.sid == sid and ticket.approved and not ticket.delivered then
			tryDeliver(id)
		end
	end
end

sAdmin.ApproveRestoreTicket = function(ply, id)
	id = tonumber(id)

	local ticket = id and sAdmin.RestoreTickets.tickets[id]
	if not ticket or ticket.approved then return false end

	ticket.approved = true
	ticket.approver_name = IsValid(ply) and ply:SteamName() or consoleName()
	ticket.approver_sid64 = adminSID(ply)
	ticket.approved_time = os.time()

	saveRestore(id)
	broadcastRestore(id)
	log(ply, "одобрил заявку на возврат №" .. id, nil, ticket.sid)

	tryDeliver(id)

	return true
end

local function restoreData(pendingOnly)
	local list = sAdmin.RestoreTickets.tickets

	if pendingOnly then
		list = {}

		for id, ticket in pairs(sAdmin.RestoreTickets.tickets) do
			if not ticket.delivered then
				list[id] = ticket
			end
		end
	end

	return DarkRP.TableCompress(list)
end

net.Receive("sA:RestoreSync", function(len, ply)
	if not canViewRestore(ply) or sAdmin.throttle(ply, "restore_sync", 1) then return end

	local data, size = restoreData()

	-- слишком много данных: без уже выданных заявок
	if size > MAX_NET then
		data, size = restoreData(true)
		if size > MAX_NET then return end
	end

	net.Start("sA:RestoreSync")
		net.WriteUInt(0, 2)
		net.WriteUInt(size, 32)
		net.WriteData(data, size)
	net.Send(ply)
end)

net.Receive("sA:RestoreCreate", function(len, ply)
	if not IsValid(ply) or not sAdmin.hasPermission(ply, "restore_create") then return end

	if sAdmin.throttle(ply, "restore_create", 3) then
		sAdmin.msg(ply, "request_rate_limit")
		return
	end

	local sid = normalizeSID(net.ReadString())
	local money = net.ReadUInt(32)
	local json = net.ReadString()
	local reason = cleanText(net.ReadString(), 500)

	if not sid then
		sAdmin.msg(ply, "Неверный SteamID в заявке на возврат.")
		return
	end

	if #json > RESTORE_MAX_JSON then return end

	local items, count = cleanItems(util.JSONToTable(json))

	if money <= 0 and count == 0 then
		sAdmin.msg(ply, "Заявка на возврат не может быть пустой.")
		return
	end

	if reason == "" then
		sAdmin.msg(ply, "Укажите причину возврата.")
		return
	end

	local ticket = {
		sid = sid,
		money = money,
		items = items,
		reason = reason,
		creator_name = ply:SteamName(),
		creator_sid64 = ply:SteamID64(),
		created_time = os.time(),
		approved = false,
		delivered = false
	}

	local function created(id)
		id = tonumber(id)
		if not id then return end

		sAdmin.RestoreTickets.tickets[id] = ticket
		broadcastRestore(id)

		if IsValid(ply) then
			sAdmin.msg(ply, "Заявка на возврат №%s создана.", id)
		end

		sAdmin.msg(sAdmin.FindByPerm("restore_approve"), "Новая заявка на возврат №%s для %s ожидает одобрения.", id, sid)
		log(ply, "создал заявку на возврат №" .. id .. " для " .. sid, nil, money)
	end

	slib.dbQuery("INSERT INTO sadmin_restore (sid, data) VALUES (" .. esc(sid) .. ", " .. esc(util.TableToJSON(ticket)) .. ")", function(rows, lastInsert)
		if tonumber(lastInsert) and tonumber(lastInsert) > 0 then
			created(lastInsert)
			return
		end

		slib.dbQuery("SELECT MAX(id) AS id FROM sadmin_restore WHERE sid = " .. esc(sid), function(found)
			created(found[1] and found[1].id)
		end)
	end)
end)

net.Receive("sA:RestoreAction", function(len, ply)
	if not IsValid(ply) or not sAdmin.hasPermission(ply, "restore_approve") then return end
	if sAdmin.throttle(ply, "restore_action", 0.5) then return end

	local mode, id = net.ReadUInt(2), net.ReadUInt(32)
	local ticket = sAdmin.RestoreTickets.tickets[id]
	if not ticket then return end

	if mode == 0 then
		if sAdmin.ApproveRestoreTicket(ply, id) then
			sAdmin.msg(sAdmin.logPerm(), "%s одобрил заявку на возврат №%s", ply, id)
		end
	elseif mode == 1 then
		if ticket.delivered then return end

		sAdmin.RestoreTickets.tickets[id] = nil
		slib.dbQuery("DELETE FROM sadmin_restore WHERE id = " .. int(id))
		broadcastRestore(id)

		sAdmin.msg(sAdmin.logPerm(), "%s удалил заявку на возврат №%s", ply, id)
		log(ply, "удалил заявку на возврат №" .. id, nil, ticket.sid)
	end
end)

hook.Add("DarkRPPlayerDataLoaded", "sA:Restore", function(ply)
	timer.Simple(5, function()
		deliverFor(ply)
	end)
end)

hook.Add("PlayerSpawn", "sA:Restore", function(ply)
	timer.Simple(1, function()
		deliverFor(ply)
	end)
end)

timer.Create("sA:Restore", 60, 0, function()
	for id, ticket in pairs(sAdmin.RestoreTickets.tickets) do
		if ticket.approved and not ticket.delivered then
			tryDeliver(id)
		end
	end
end)

--[[---------------------------------------------------------------------------
	База данных
---------------------------------------------------------------------------]]
local function loadRestore()
	slib.dbQuery("SELECT id, sid, data FROM sadmin_restore", function(rows)
		local tickets, old, now = {}, {}, os.time()

		for _, row in ipairs(rows) do
			local id = tonumber(row.id)
			local ticket = util.JSONToTable(row.data or "")
			if not id or not istable(ticket) then continue end

			if ticket.delivered and (tonumber(ticket.delivered_time) or 0) + RESTORE_KEEP < now then
				old[#old + 1] = int(id)
				continue
			end

			ticket.sid = ticket.sid or row.sid
			tickets[id] = ticket
		end

		-- заявки, созданные до загрузки
		for id, ticket in pairs(sAdmin.RestoreTickets.tickets) do
			if not tickets[id] then
				tickets[id] = ticket
			end
		end

		sAdmin.RestoreTickets.tickets = tickets

		if #old > 0 then
			slib.dbQuery("DELETE FROM sadmin_restore WHERE id IN (" .. table.concat(old, ", ") .. ")")
		end
	end)
end

slib.onDBReady("sAdmin:tools", function()
	runQueries({
		"CREATE TABLE IF NOT EXISTS sadmin_storedcmds (sid VARCHAR(32) NOT NULL PRIMARY KEY, data TEXT)",
		"CREATE TABLE IF NOT EXISTS sadmin_restore (id " .. slib.dbAutoIncrement() .. ", sid VARCHAR(32) NOT NULL, data TEXT)"
	}, loadRestore)
end)
