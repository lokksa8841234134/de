--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Проверка навыка (DarkRP.SC) - сервер

	Мини-игра взлома: полоса из 20 отрезков с зоной, стрелка ходит туда и
	обратно, игрок жмёт атаку, когда стрелка в зоне. Клиент -
	addons/health/lua/mc_haes/core/cl_init.lua. Вызывают отмычка
	(entities/weapons/lockpick) и станции крафта (workstation_base):
	  DarkRP.SC.Send(ply, окно, длительность, успех, провал[, звук])
	    окно - секунд на раунд (у отмычки 2, с татуировкой a4 - 3);
	    длительность - время всей проверки;
	    успех(ply) - все раунды пройдены, не раньше конца длительности;
	    провал(ply) - промах или раунд пропущен;
	    звук - на каждое попадание.
	  DarkRP.SC.Fail(ply[, тихо]) - прервать; тихо - без вызова провала
	    (так отмычка прерывает взлом, когда отвернулись или убрали её).
	  Send возвращает проверку, DarkRP.SC.Session(ply) - текущая проверка
	    игрока: станция крафта так узнаёт, что её проверку прервали молча,
	    и не трогает чужую (отмычку).
	Новый Send тихо прерывает прежнюю проверку, смерть и выход - тоже.

	Полоса над отрезками - общий прогресс всей проверки, без перерывов от
	начала до конца. Окно появляется сразу, зона - с первым раундом через
	FIRST секунд, дальше по раунду на каждые ROUND_EVERY секунд (не больше
	MAX_ROUNDS). Раунды разбросаны по времени и кончаются до конца полосы.
	После попадания стрелка стоит в зоне до следующего раунда, нажатия
	между раундами не считаются. Окно убирается в конце или при провале.

	net SC.Noire, S->C UInt(2):
	  0 - окно: UInt(5) первый отрезок зоны, UInt(5) ширина зоны (0 - зоны
	    нет, раунд ещё не начался), UInt(12) длина полосы в секундах,
	    Float начало полосы (CurTime), Bool последний раунд (другой цвет);
	  1 - убрать окно.
	Клиент рисует полосу как (начало + длина - CurTime) / длина и сам
	прячет окно, когда она кончилась. Длина - целые секунды: начало
	сдвинуто так, чтобы полоса кончалась ровно в конце проверки.
	C->S: Float положение стрелки 0..1, Float CurTime клиента при нажатии.
	Положение стрелки зависит только от времени: (1 - cos(4t)) / 2. Сервер
	проверяет, что оно сходится со временем нажатия (с запасом 0.2 полосы),
	и что нажатие пришло во время раунда.
	Энергия больше 250 (голод) расширяет зону на отрезок влево - клиент
	рисует его серым.
---------------------------------------------------------------------------]]

util.AddNetworkString("SC.Noire")

DarkRP.SC = DarkRP.SC or {}

local SEGMENTS = 20
local ZONE = 3
local FIRST = 3 -- первый раунд через 3 секунды
local ROUND_EVERY = 8 -- дальше по раунду на каждые 8 секунд
local MAX_ROUNDS = 8
local BETWEEN = 0.3 -- наименьшая пауза между раундами
local END_GAP = 0.5 -- последний раунд кончается за полсекунды до конца полосы
local GRACE = 0.3 -- запас к окну раунда сверх пинга
local POS_SLACK = 0.2
local PRESS_DELAY = 0.15 -- клиент шлёт нажатие не чаще раза в 0.2 с
local ENERGY_BONUS = 250
local MAX_BAR = 4095 -- UInt(12)

-- [ply] = {window, starts, round, active, sp, ps, roundStart, deadline, barStart, barLen, finish, success, fail, sound}
local sessions = {}

local function arrow(t)
	return (1 - math.cos(t * 4)) / 2
end

-- Float по сети - 32 бита: на больших CurTime (сервер работает неделями)
-- время нажатия приходит округлённым, запас растёт вместе с ним
local function floatStep(x)
	local _, e = math.frexp(math.abs(x))

	return 2 ^ (e - 24)
end

-- окно с общей полосой; зона - только во время раунда
local function send(ply, typ, s)
	net.Start("SC.Noire")
		net.WriteUInt(typ, 2)

		if typ == 0 then
			net.WriteUInt(s.active and s.sp or 0, 5)
			net.WriteUInt(s.active and s.ps or 0, 5)
			net.WriteUInt(s.barLen, 12)
			net.WriteFloat(s.barStart)
			net.WriteBool(s.active and s.round == #s.starts)
		end
	net.Send(ply)
end

-- начала раундов от начала проверки: первый через FIRST секунд, остальные -
-- поровну по оставшемуся времени, внутри доли - случайный сдвиг
local function plan(window, duration)
	local first = math.min(FIRST, math.max(duration - window - END_GAP, 0))
	local from = first + window + BETWEEN -- раньше второй раунд не начнётся
	local last = duration - END_GAP - window -- позже раунд не начнётся
	local step = window + BETWEEN
	local rest = math.Clamp(math.floor((duration - first) / ROUND_EVERY) + 1, 1, MAX_ROUNDS) - 1

	if last < from then
		rest = 0
	else
		rest = math.min(rest, math.floor((last - from) / step) + 1)
	end

	local starts = {first}
	local slot = rest > 0 and (last - from + step) / rest or 0

	for i = 1, rest do
		starts[i + 1] = from + (i - 1) * slot + math.random() * (slot - step)
	end

	return starts
end

function DarkRP.SC.Fail(ply, silent)
	local s = sessions[ply]
	if not s then return end

	sessions[ply] = nil

	if IsValid(ply) then send(ply, 1) end
	if not silent and s.fail then s.fail(ply) end
end

function DarkRP.SC.Send(ply, window, duration, onSuccess, onFail, snd)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	DarkRP.SC.Fail(ply, true)

	window = math.Clamp(math.floor(tonumber(window) or 2), 1, 60)
	duration = math.max(tonumber(duration) or 40, 1)

	local now = CurTime()
	local starts = plan(window, duration)
	local barLen = math.min(math.ceil(duration), MAX_BAR)

	for i, t in ipairs(starts) do
		starts[i] = now + t
	end

	local s = {
		window = window,
		starts = starts,
		round = 0,
		active = false,
		finish = now + duration,
		barLen = barLen,
		barStart = now + duration - barLen,
		success = onSuccess,
		fail = onFail,
		sound = isstring(snd) and snd or nil,
	}

	sessions[ply] = s

	-- окно и полоса сразу, зона - с первым раундом
	send(ply, 0, s)

	return s
end

function DarkRP.SC.Session(ply)
	return sessions[ply]
end

local function startRound(ply, s, now)
	s.round = s.round + 1
	s.active = true
	-- 1..17: слева от зоны остаётся отрезок для бонуса энергии
	s.sp = math.random(1, SEGMENTS - ZONE)
	s.ps = ZONE
	s.roundStart = now
	s.deadline = now + s.window + ply:Ping() / 1000 + GRACE

	send(ply, 0, s)
end

local function succeed(ply, s)
	sessions[ply] = nil

	send(ply, 1)

	if s.success then s.success(ply) end
end

-- действия собираются отдельно: обратные вызовы могут начать новую проверку
hook.Add("Think", "DarkRP.SC", function()
	if next(sessions) == nil then return end

	local now = CurTime()
	local due = {}

	for ply, s in pairs(sessions) do
		if not IsValid(ply) then
			due[#due + 1] = {ply, "drop"}
		elseif s.active then
			if now > s.deadline then due[#due + 1] = {ply, "miss"} end
		elseif s.round < #s.starts then
			if now >= s.starts[s.round + 1] then due[#due + 1] = {ply, "round"} end
		elseif now >= s.finish then
			due[#due + 1] = {ply, "done"}
		end
	end

	for _, d in ipairs(due) do
		local ply, what = d[1], d[2]
		local s = sessions[ply]

		if not s then continue end

		if what == "drop" then
			sessions[ply] = nil
		elseif what == "miss" then
			DarkRP.SC.Fail(ply)
		elseif what == "round" then
			startRound(ply, s, now)
		else
			succeed(ply, s)
		end
	end
end)

net.Receive("SC.Noire", function(_, ply)
	local pos = net.ReadFloat()
	local ctime = net.ReadFloat()

	local s = sessions[ply]
	if not s or not s.active then return end

	local now = CurTime()
	if s.lastPress and now - s.lastPress < PRESS_DELAY then return end
	s.lastPress = now

	local lag = ply:Ping() / 1000
	local step = (ctime == ctime) and floatStep(ctime) or 0
	local hit = pos == pos and ctime == ctime -- не NaN
		and ctime >= s.roundStart - 0.05 - step and ctime <= s.roundStart + s.window + 0.1 + step
		and ctime <= now + 0.5 + step and ctime >= now - 1 - lag - step
		and math.abs(pos - arrow(ctime)) <= POS_SLACK + 2 * step

	if hit then
		local seg = math.Clamp(math.floor(pos * SEGMENTS), 0, SEGMENTS - 1)
		local energy = tonumber(ply:getDarkRPVar("energy")) or 0

		hit = (seg >= s.sp and seg < s.sp + s.ps) or (energy > ENERGY_BONUS and seg == s.sp - 1)
	end

	if not hit then
		DarkRP.SC.Fail(ply)
		return
	end

	-- раунд пройден: окно и полоса остаются, стрелка у клиента стоит до следующего раунда
	s.active = false

	if s.sound then ply:EmitSound(s.sound, 60) end
end)

hook.Add("PlayerDeath", "DarkRP.SC", function(ply)
	DarkRP.SC.Fail(ply, true)
end)

hook.Add("PlayerDisconnected", "DarkRP.SC", function(ply)
	sessions[ply] = nil
end)
