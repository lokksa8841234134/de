--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Позывные (подразделения) полиции и пожарных - сервер

	Позывной назначает профессия в PlayerChangeTeam (jobs.lua автора):
	  DarkRP.Police.AddUnit(служба, ply[, тип, режим, префикс])
	  DarkRP.Police.AssignUnit(ply, номер)
	Позывные видят все: DarkRP.Police.Units[UserID] = позывной (sh_config.lua),
	таблица уходит клиентам через DarkRP.SendDataShared. Где они видны:
	панель рации - кто говорит (client/hud.lua), вызовы 911 (services),
	компьютер участка - "Сотрудники" (slawer_mayor/modules/policemen/cl.lua).

	Как строится позывной:
	  AddUnit("NYPD", ply) - патрульный экипаж: 29-Adam, 29-Boy ... - первое
	    свободное слово из DarkRP.Police.PhoneticNum;
	  тип и true - тип и номер с префиксом: "ESU 6-1", "EMS 96-1",
	    "RESCUE 96-2". Номер - наименьший свободный среди позывных с этим
	    префиксом (у пожарных, парамедиков и инспекторов он общий - 96-);
	  тип и строка - строка в конце: "AUX на смене", с префиксом - ещё и
	    номер: "TRAFFIC BN-1 на смене";
	  AssignUnit(ply, n) - общий позывной: 29-6 (в штатском), 29-19
	    (супервайзер).

	Экипажи - кнопки компьютера участка, вкладка "Сотрудники":
	  police_join <userid> <userid2> - первый переходит в экипаж второго и
	    получает его позывной с номером: 29-Adam-2, 29-Adam-3;
	  police_join <userid> - вернуть ему собственный позывной.
	Распределяет руководство (Slawer.Mayor:HasAccess "kick": районный
	администратор, полиция ранга 6+, пожарные ранга 7+) за компьютером
	участка; суперадмин и консоль сервера - откуда угодно.
	Позывной снимается при смене профессии, смене персонажа и выходе.
---------------------------------------------------------------------------]]

local PRECINCT = "29-"
local COMPUTER_RANGE = 250 * 250 -- как у компьютеров участка (sv_computers.lua)

-- [ply] = {name, base, suffix, key, group, team, joined, member, args}
-- key - кто занимает слово или номер: "P:Adam", "N:6-:1", "T:AUX", "A:6";
-- у переведённых в чужой экипаж key того экипажа
local records = {}
local pending = false

local function broadcast()
	if pending then return end
	pending = true

	-- несколько смен за один кадр уходят одним сообщением
	timer.Simple(0, function()
		pending = false
		DarkRP.SendDataShared(nil, "Police", "Units", DarkRP.Police.Units)
	end)
end

local function setRecord(ply, rec)
	records[ply] = rec
	DarkRP.Police.Units[ply:UserID()] = rec and rec.name or nil
	broadcast()
end

local function usedKeys(except)
	local used = {}

	for p, rec in pairs(records) do
		if not IsValid(p) then
			records[p] = nil
		elseif p ~= except then
			used[rec.key] = true
		end
	end

	return used
end

local function freeNumber(prefix, used, from)
	local n = from or 1

	while used["N:" .. prefix .. ":" .. n] do
		n = n + 1
	end

	return n
end

-- патрульный экипаж: первое свободное слово, если заняты все 26 - номер с 30
local function patrolUnit(used)
	for _, word in ipairs(DarkRP.Police.PhoneticNum) do
		if not used["P:" .. word] then
			return PRECINCT .. word, "P:" .. word
		end
	end

	local n = freeNumber(PRECINCT, used, 30)

	return PRECINCT .. n, "N:" .. PRECINCT .. ":" .. n
end

function DarkRP.Police.AddUnit(group, ply, utype, mode, prefix)
	if not IsValid(ply) then return end

	local used = usedKeys(ply)
	local rec = {
		group = group,
		team = ply:Team(),
		suffix = isstring(mode) and mode or "",
		args = {"add", group, utype, mode, prefix},
	}

	if utype == nil then
		rec.base, rec.key = patrolUnit(used)
	elseif mode == true or (isstring(mode) and prefix) then
		prefix = tostring(prefix or "")

		local n = freeNumber(prefix, used)

		rec.base = tostring(utype) .. " " .. prefix .. n
		rec.key = "N:" .. prefix .. ":" .. n
	else
		rec.base = tostring(utype)
		rec.key = "T:" .. rec.base
	end

	rec.name = rec.base .. rec.suffix
	setRecord(ply, rec)

	return rec.name
end

function DarkRP.Police.AssignUnit(ply, num)
	if not IsValid(ply) then return end

	local base = PRECINCT .. tostring(num)

	setRecord(ply, {
		group = "NYPD",
		team = ply:Team(),
		base = base,
		suffix = "",
		name = base,
		key = "A:" .. tostring(num),
		args = {"assign", num},
	})

	return base
end

function DarkRP.Police.RemoveUnit(ply)
	if not records[ply] then return end

	records[ply] = nil
	DarkRP.Police.Units[ply:UserID()] = nil
	broadcast()
end

function DarkRP.Police.GetUnit(ply)
	return records[ply] and records[ply].name or nil
end

-- перевести ply в экипаж target: позывной экипажа с номером 2, 3 ...
function DarkRP.Police.JoinUnit(ply, target)
	local rec, trec = records[ply], records[target]

	if not rec or not trec then return false, "У сотрудника нет позывного" end
	if ply == target then return false, "Выберите другого сотрудника" end
	if rec.group ~= trec.group then return false, "Это сотрудник другой службы" end
	if rec.key == trec.key then return false, "Они уже в одном экипаже" end

	local taken = {}

	for p, r in pairs(records) do
		if p ~= ply and r.joined and r.key == trec.key then
			taken[r.member] = true
		end
	end

	local k = 2

	while taken[k] do
		k = k + 1
	end

	local name = trec.base .. "-" .. k .. trec.suffix

	setRecord(ply, {
		group = rec.group,
		team = rec.team,
		args = rec.args,
		key = trec.key,
		base = trec.base,
		suffix = trec.suffix,
		joined = true,
		member = k,
		name = name,
	})

	return true, name
end

-- вернуть собственный позывной тому, кого переводили в чужой экипаж
function DarkRP.Police.RestoreUnit(ply)
	local rec = records[ply]
	if not rec then return false, "У сотрудника нет позывного" end
	if not rec.joined then return false, "У сотрудника и так свой позывной" end

	local a = rec.args

	if a[1] == "assign" then
		return true, DarkRP.Police.AssignUnit(ply, a[2])
	end

	return true, DarkRP.Police.AddUnit(a[2], ply, a[3], a[4], a[5])
end

--[[---------------------------------------------------------------------------
	police_join - кнопки "Сотрудники" в компьютере участка
---------------------------------------------------------------------------]]
local function nearComputer(ply)
	local pos = ply:GetPos()

	for _, ent in ipairs(ents.FindByClass("slawer_mayor_computer")) do
		if ent:GetPos():DistToSqr(pos) <= COMPUTER_RANGE then return true end
	end

	return false
end

local function canManage(ply)
	-- консоль сервера
	if not IsValid(ply) then return true end
	if ply:IsSuperAdmin() then return true end

	if not Slawer.Mayor:HasAccess(ply, "kick") then
		return false, "Распределять экипажи может только руководство"
	end

	if not ply:IsFreeman() or not nearComputer(ply) then
		return false, "Экипажи распределяют за компьютером участка"
	end

	return true
end

-- своя служба: полиция распределяет полицию, пожарные - пожарных
local function sameService(ply, p)
	if not IsValid(ply) or ply:IsSuperAdmin() or ply:isMayor() then return true end
	if ply:isCP() then return p:isCP() == true end
	if ply:isEMS() then return p:isEMS() == true end

	return false
end

-- ответ консоли сервера (игрокам уведомлений нет)
local function reply(ply, msg)
	if not IsValid(ply) and msg then print("[police_join] " .. msg) end
end

local function findPlayer(arg)
	local p = Player(tonumber(arg) or -1)

	return IsValid(p) and p or nil
end

concommand.Add("police_join", function(ply, _, args)
	if IsValid(ply) and DarkRP.NetDelay(ply, 0.5) then return end

	local ok, why = canManage(ply)

	if not ok then
		reply(ply, why)
		return
	end

	local p = findPlayer(args[1])

	if not p or not records[p] or not sameService(ply, p) then
		reply(ply, "У этого сотрудника нет позывного")
		return
	end

	-- один аргумент - вернуть свой позывной
	if args[2] == nil or args[2] == "" then
		local done, res = DarkRP.Police.RestoreUnit(p)

		if not done then
			reply(ply, res)
			return
		end

		if p ~= ply then reply(ply, p:FullName() .. " - снова " .. res) end
		DarkRP.log("police", IsValid(ply) and ply or nil, p, "вернул позывной " .. res)

		return
	end

	local v = findPlayer(args[2])

	if not v or not records[v] or not sameService(ply, v) then
		reply(ply, "У второго сотрудника нет позывного")
		return
	end

	-- как у компьютера автора: вспомогательную полицию в чужой экипаж не переводят
	if p:Team() == TEAM_WARDEN then
		reply(ply, "Вспомогательную полицию нельзя перевести в другой экипаж")
		return
	end

	local done, res = DarkRP.Police.JoinUnit(p, v)

	if not done then
		reply(ply, res)
		return
	end

	if p ~= ply then reply(ply, p:FullName() .. " - теперь " .. res) end
	DarkRP.log("police", IsValid(ply) and ply or nil, p, "перевёл в экипаж " .. records[v].name .. ": " .. res)
end)

--[[---------------------------------------------------------------------------
	Когда позывной снимается и кто получает таблицу
---------------------------------------------------------------------------]]
-- новая профессия ставит свой позывной до хука (ChangeTeam, sv_jobs.lua);
-- позывной старой профессии снимается
hook.Add("OnPlayerChangedTeam", "DarkRP.Police.Units", function(ply, _, new)
	local rec = records[ply]

	if rec and rec.team ~= new then
		DarkRP.Police.RemoveUnit(ply)
	end
end)

hook.Add("PlayerDisconnected", "DarkRP.Police.Units", DarkRP.Police.RemoveUnit)
hook.Add("MCR.CharacterReset", "DarkRP.Police.Units", DarkRP.Police.RemoveUnit)

hook.Add("DarkRP.PlayerLoaded", "DarkRP.Police.Units", function(ply)
	DarkRP.SendDataShared(ply, "Police", "Units", DarkRP.Police.Units)
end)
