--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Телефон McPhone - сервер: звонки, таксофоны, служебные номера, сигнал
	вышек связи и глушилки, телефон в руке, настройки телефона

	Подключает autorun/mc_phone_init.lua после sh_config, sh_language и
	sh_init. Клиент - автора (cl_init.lua, cl_util.lua, modules/payphone.lua,
	extentions/cl_ep1_init.lua), сообщения:
	  McPhone.CallStart       C->S: номер, есть ли номер службы, [номер службы]
	                          S->C: "Connecting" звонящему / "Incoming" тому,
	                          кому звонят; игрок; тип (2 бита): 1 - звонящий у
	                          таксофона, 2 - входящий с таксофона, 3 - входящий
	                          от службы (+ её номер)
	  McPhone.Accept          C->S: ответить
	  McPhone.CallAccept      S->C: разговор начался (с таксофона ли)
	  McPhone.CallDeny        C->S: положить трубку
	  McPhone.End             S->C: разговор окончен
	  McPhone.CallBuisy       S->C: занято
	  McPhone.CallNotAv       S->C: абонент недоступен (с таксофона ли)
	  McPhone.NoSignal        S->C: нет сети
	  McPhone.CallExtraNumber S->C: служебный номер (номер, таксофон, гудки, с)
	                          C->S: 0 - разговор со служебным номером окончен
	  McPhone.PhoneStatus     C->S: телефон открыт (больше 0) / закрыт (0)
	  McPhone.GetUserData     C->S: настройки (сон, модель, мелодия, обои, цвет)
	  McPhone.SignalChange    S->C: сила сигнала 0-3
	  McPhone.Notify          S->C: уведомление (McPhone.Notify)
	  McPhone.ToggleGPS       S->C: метка GPS (McPhone.ToggleGPS)
	  McPhone.SaveTowers, SpawnTower, RemoveTowers - кнопки суперадмина в
	    настройках (cl_config_manager.lua)
	Здесь же регистрируются сообщения кода автора: GetData и SaveConfig
	(sh_config.lua), Comtact (McPhone.AddContacts), PayPhone (таксофон,
	entities/mc_payphone.lua).

	Звонок игроку - по номеру McPhone.NumberChar (sh_init.lua). Нельзя
	дозвониться: нет такого номера, телефона, сети, игрок мёртв, без сознания,
	в наручниках, говорит с NPC, телефон в режиме сна - "недоступен"; уже
	говорит, звонит или стоит у таксофона - "занято". Сбросил входящий -
	у звонящего "занято". Без ответа звонок кончается через 30 с (экран
	входящего у клиента закрывается сам через 15 с). Разговор обрывается,
	если кто-то из двоих больше не может говорить, ушёл от таксофона или
	потерял сеть. Голос собеседника слышен на любом расстоянии
	(McPhone.InCall, server/sv_chat.lua).

	Таксофон: игрок подходит и жмёт E (mc_payphone.lua, ply.McPayPhone);
	звонок с него - без сети и без телефона, в 70 юнитах от таксофона, как
	у клиента. Перезвонить на таксофон нельзя.

	Служебные номера (McPhone.ExtraNumbers, sh_init.lua): гудки 2-5 с, потом
	запись (delay номера); проверка номера (delay_func) может ответить
	"занято". У номеров с меню (func: 911, механик, Дезз, Self Storage)
	клиент по концу записи сообщает об этом и открывает меню; кнопки меню
	проверяют, что игрок только что дозвонился (McPhone.TakeExtraCall: 911 -
	services, Дезз - mc_simple_npcs, механик - здесь). Дезз и участок
	(9523877, 5553232) - "занято", пока у игрока нет данных квестов MQS
	(шаг 15): проверки автора и меню клиента читают их.
	Номера службы при звонке: "Связаться с механиком" (меню 5553867) -
	звонок механику (TEAM_CAR) с номером сервиса: тому, кого выбрал клиент,
	или любому свободному; "Связаться с заявителем" (вызовы 911) - звонок с
	номером 911, только полиции и пожарным/медикам.

	Сигнал (McPhone.EP1, sh_ep1_init.lua): включённая глушилка ближе
	JammerRange - 0; иначе по ближайшей целой вышке: до трети TowerMaxRange -
	3, до двух третей - 2, до TowerMaxRange - 1, дальше - 0. Вышек на карте
	нет или TowerRangebasedNet выключен - 3. Вышки чинятся сами через
	TowerRepairTime (разрушенная и повреждённая, которую больше не трогали),
	глушилка ломается через JammerLiveTime. Вышки карты сохраняет суперадмин
	(TowersDLC в mcphone_config.txt) - они ставятся при старте и после
	очистки карты.

	Телефон в руке (McPhone.Active): 1 - открыт, 2 - разговор, 3 - трубка
	таксофона; модель (McPhone.Type) и цвет (NW2 McPhone.Color) - по
	телефону в карманах. Настройки телефона хранятся в предмете (item.ud):
	мелодия, обои и цвет - только из списков модели (phones/*.lua).
---------------------------------------------------------------------------]]

local PAYPHONE_RANGE = 5005 -- квадрат расстояния до таксофона, как у клиента (modules/payphone.lua)
local RING_TIME = 30 -- входящий без ответа, с
local RING_DELAY = {2, 5} -- гудки до ответа служебного номера, с
local EXTRA_KEEP = 120 -- меню служебного номера действует после разговора, с
local EXTRA_STALE = 60 -- служебный номер с меню: ждём сообщения клиента о конце разговора, с
local STATUS_DELAY = 0.2 -- PhoneStatus пересчитывается не чаще
local TICK = 1 -- сигнал, разговоры, вышки, глушилки, телефон в руке, с

-- проверки номеров автора, которым нужны данные квестов (MQS, шаг 15)
local QUEST_CHECKS = {dealer = true, police = true}

for _, name in ipairs({"Accept", "CallAccept", "CallBuisy", "CallDeny", "CallExtraNumber", "CallNotAv", "CallStart", "Comtact", "End", "GetData", "GetUserData", "NoSignal", "Notify", "PayPhone", "PhoneStatus", "RemoveTowers", "SaveConfig", "SaveTowers", "SignalChange", "SpawnTower", "ToggleGPS"}) do
	util.AddNetworkString("McPhone." .. name)
end

-- [игрок] = звонок {caller, callee, payphone, callerid, start, accepted}, у обоих один
McPhone.Calls = {}

McPhone.EP1 = McPhone.EP1 or {}
McPhone.EP1.Towers = {}
McPhone.EP1.Jammers = {}

-- перезагрузка Lua: вышки и глушилки уже на карте (при запуске их ещё нет)
if GAMEMODE then
	McPhone.EP1.Towers = ents.FindByClass("mc_antenna")
	McPhone.EP1.Jammers = ents.FindByClass("mc_jammer")
end

local function log(ply, target, text)
	if McPhone.Config.DarkRPLog then
		DarkRP.log("other", ply, target, text)
	end
end

local function signalOf(ply)
	return tonumber(ply.McPhoneSignal) or 0
end

local function hasPhone(ply)
	return McPhone.HasPhone(ply) ~= nil
end

--[[---------------------------------------------------------------------------
	Для других модулей
---------------------------------------------------------------------------]]
-- уведомление на телефоне; ply - игрок или список игроков
function McPhone.Notify(ply, title, text, snd)
	if not istable(ply) and not IsValid(ply) then return end

	net.Start("McPhone.Notify")
		net.WriteString(tostring(title or ""))
		net.WriteString(tostring(text or ""))
		net.WriteBool(snd == true)
	net.Send(ply)
end

-- метка GPS (у клиента это переключатель: если метка уже стоит, она снимается)
function McPhone.ToggleGPS(ply, name, pos)
	if not IsValid(ply) or not isvector(pos) then return end

	net.Start("McPhone.ToggleGPS")
		net.WriteString(tostring(name or ""))
		net.WriteVector(pos)
	net.Send(ply)
end

-- телефон в руке у других игроков (cl_hooks.lua): 0 - нет, 1 - открыт, 2 - разговор, 3 - таксофон
function McPhone.SetCallStatus(ply, status)
	local value = (tonumber(status) or 0) > 0 and status or nil

	if ply:getDarkRPVar("McPhone.Active") ~= value then
		ply:SetDarkRPVar("McPhone.Active", value)
	end
end

function McPhone.RefreshStatus(ply)
	if not IsValid(ply) then return end

	local status = 0

	if IsValid(ply.McPayPhone) then
		status = 3
	elseif hasPhone(ply) then
		local call = McPhone.Calls[ply]

		if ply.McPhoneExtra or (call and (call.caller == ply or call.accepted)) then
			status = 2
		elseif ply.McPhoneOpen then
			status = 1
		end
	end

	McPhone.SetCallStatus(ply, status)
end

-- идёт ли разговор между ними (голос по телефону, server/sv_chat.lua)
function McPhone.InCall(a, b)
	local call = McPhone.Calls[a]

	return a ~= b and call ~= nil and call.accepted ~= nil and McPhone.Calls[b] == call
end

-- игрок только что дозвонился до служебного номера с меню (911, механик, Дезз):
-- {num, payphone, time}, отдаётся один раз
function McPhone.TakeExtraCall(ply, num)
	local done = IsValid(ply) and ply.McPhoneExtraDone

	if not done or done.num ~= num or CurTime() - done.time > EXTRA_KEEP then return nil end

	ply.McPhoneExtraDone = nil

	return done
end

--[[---------------------------------------------------------------------------
	Телефон в карманах: модель, цвет, режим сна
---------------------------------------------------------------------------]]
local function syncLook(ply)
	local _, item = McINV.GetPhone(ply)
	local ud = item and istable(item.ud) and item.ud or nil

	-- режим сна (McPhone.CanUsePhone, sh_init.lua)
	ply.McPhoneData = ud

	local kind = item and tonumber(item.phone_type) or nil

	if ply:getDarkRPVar("McPhone.Type") ~= kind then
		ply:SetDarkRPVar("McPhone.Type", kind)
	end

	local color = ud and ud.PhoneColor or item and item.color

	if istable(color) and color.r and color.g and color.b then
		-- клиент читает Color(x, z, y)
		local vec = Vector(color.r, color.b, color.g)

		if ply:GetNW2Vector("McPhone.Color") ~= vec then
			ply:SetNW2Vector("McPhone.Color", vec)
		end
	end
end

local function themeColor(theme, r, g, b)
	for _, th in pairs(theme.Themes) do
		local c = th.phone

		if istable(c) and c.r == r and c.g == g and c.b == b then
			return Color(r, g, b)
		end
	end

	return nil
end

net.Receive("McPhone.GetUserData", function(_, ply)
	if DarkRP.NetDelay(ply, 0.1) then return end

	local _, item = McINV.GetPhone(ply)
	local ud = item and item.ud
	local theme = istable(ud) and McPhone[ud.PhoneType]

	if not istable(theme) or not istable(theme.Themes) then return end

	local sleep = net.ReadBool()
	local kind = net.ReadString()
	local ringtone = net.ReadString()
	local wallpaper = net.ReadString()
	local r, g, b = net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8)

	-- модель - сам предмет, настройками она не меняется
	if kind ~= ud.PhoneType then return end

	ud.Sleep = sleep

	if istable(theme.Ringtone) and table.HasValue(theme.Ringtone, ringtone) then
		ud.Ringtone = ringtone
	end

	if istable(theme.WallPapers) and table.HasValue(theme.WallPapers, wallpaper) then
		ud.WallPaper = wallpaper
	end

	local color = themeColor(theme, r, g, b)

	if color then
		ud.PhoneColor = color
		item.color = Color(r, g, b)
	end

	syncLook(ply)
end)

net.Receive("McPhone.PhoneStatus", function(_, ply)
	ply.McPhoneOpen = net.ReadUInt(3) > 0 and hasPhone(ply)

	if DarkRP.NetDelay(ply, STATUS_DELAY) then return end

	McPhone.RefreshStatus(ply)
end)

--[[---------------------------------------------------------------------------
	Звонки
---------------------------------------------------------------------------]]
local function busy(ply)
	return McPhone.Calls[ply] ~= nil or ply.McPhoneExtra ~= nil
end

local function sendBusy(ply)
	net.Start("McPhone.CallBuisy")
	net.Send(ply)
end

local function sendNotAv(ply, payphone)
	net.Start("McPhone.CallNotAv")
		net.WriteBool(payphone ~= nil)
	net.Send(ply)
end

-- можно ли дозвониться: nil - да, "busy" - занято, "na" - недоступен
local function reachable(ply)
	if busy(ply) or IsValid(ply.McPayPhone) then return "busy" end
	if not McPhone.CanUsePhone(ply, false, true) or signalOf(ply) < 1 then return "na" end

	return nil
end

-- by - кто положил трубку (ему не сообщаем)
local function endCall(call, by)
	local caller, callee = call.caller, call.callee

	if McPhone.Calls[caller] == call then McPhone.Calls[caller] = nil end
	if McPhone.Calls[callee] == call then McPhone.Calls[callee] = nil end

	for _, ply in ipairs({caller, callee}) do
		if IsValid(ply) and ply ~= by then
			-- сбросили входящий - у звонящего "занято"
			net.Start((not call.accepted and by == callee) and "McPhone.CallBuisy" or "McPhone.End")
			net.Send(ply)
		end

		McPhone.RefreshStatus(ply)
	end
end

local function startCall(ply, target, payphone, callerid)
	local call = {caller = ply, callee = target, payphone = payphone, callerid = callerid, start = CurTime()}

	McPhone.Calls[ply] = call
	McPhone.Calls[target] = call

	net.Start("McPhone.CallStart")
		net.WriteString("Connecting")
		net.WriteEntity(target)
		net.WriteUInt(payphone and 1 or 0, 2)
	net.Send(ply)

	net.Start("McPhone.CallStart")
		net.WriteString("Incoming")
		net.WriteEntity(ply)

		if callerid then
			net.WriteUInt(3, 2)
			net.WriteString(callerid)
		else
			net.WriteUInt(payphone and 2 or 0, 2)
		end
	net.Send(target)

	McPhone.RefreshStatus(ply)
	log(ply, target, "позвонил" .. (payphone and " с таксофона" or "") .. (callerid and " с номера " .. callerid or ""))
end

local function endExtra(ply, finished)
	local extra = ply.McPhoneExtra
	if not extra then return end

	ply.McPhoneExtra = nil

	if finished and extra.func then
		ply.McPhoneExtraDone = {num = extra.num, payphone = extra.payphone, time = CurTime()}
	end

	McPhone.RefreshStatus(ply)
end

local function startExtra(ply, number, extra, payphone)
	local check = extra.delay_func and McPhone.ExtraNumbersFunc[extra.delay_func]

	if check then
		local quests = istable(ply.MQSdata) and istable(ply.MQSdata.Stored)

		if (QUEST_CHECKS[extra.delay_func] and not quests) or check(ply, payphone ~= nil) then
			sendBusy(ply)
			return
		end
	end

	local delay = math.Rand(RING_DELAY[1], RING_DELAY[2])

	ply.McPhoneExtra = {
		num = number,
		payphone = payphone ~= nil,
		func = extra.func ~= nil,
		-- клиент закончит разговор через гудки и запись
		ready = CurTime() + delay + (tonumber(extra.delay) or 0),
	}

	net.Start("McPhone.CallExtraNumber")
		net.WriteString(number)
		net.WriteBool(payphone ~= nil)
		net.WriteFloat(delay)
	net.Send(ply)

	McPhone.RefreshStatus(ply)
	log(ply, nil, "позвонил на номер " .. number .. (payphone and " с таксофона" or ""))
end

-- "Связаться с механиком": клиент шлёт звонок каждому механику, проходит первый
local function mechanic(ply, number)
	local named = McPhone.GetByCharNumber(number)

	if IsValid(named) and named ~= ply and named:Team() == TEAM_CAR and not reachable(named) then return named end

	for _, p in ipairs(team.GetPlayers(TEAM_CAR)) do
		if p ~= ply and not reachable(p) then return p end
	end

	return nil
end

net.Receive("McPhone.CallStart", function(_, ply)
	if DarkRP.NetDelay(ply, 1) then return end

	local number = net.ReadString()
	local callerid = net.ReadBool() and net.ReadString() or nil

	if busy(ply) or ply:getDarkRPVar("character") == nil then return end

	local payphone = IsValid(ply.McPayPhone) and ply.McPayPhone or nil

	if payphone then
		if payphone:GetPos():DistToSqr(ply:GetPos()) > PAYPHONE_RANGE or not McPhone.CanUsePhone(ply, true) then return end
	elseif not McPhone.CanUsePhone(ply) then
		return
	elseif signalOf(ply) < 1 then
		net.Start("McPhone.NoSignal")
		net.Send(ply)
		return
	end

	local extra = not callerid and McPhone.ExtraNumbers[number]

	if extra then
		startExtra(ply, number, extra, payphone)
		return
	end

	local target

	if callerid == "5553867" then
		if not McPhone.TakeExtraCall(ply, "5553867") then return end

		target = mechanic(ply, number)

		if not target then
			sendBusy(ply)
			return
		end
	elseif callerid == "911" then
		if not ply:isCP() and not ply:isEMS() then return end
	elseif callerid then
		return
	end

	target = target or McPhone.GetByCharNumber(number)

	if not IsValid(target) or target == ply then
		sendNotAv(ply, payphone)
		return
	end

	local fail = reachable(target)

	if fail == "busy" then
		sendBusy(ply)
	elseif fail then
		sendNotAv(ply, payphone)
	else
		startCall(ply, target, payphone, callerid)
	end
end)

net.Receive("McPhone.Accept", function(_, ply)
	local call = McPhone.Calls[ply]

	if not call or call.callee ~= ply or call.accepted or not McPhone.CanUsePhone(ply, false, true) then return end

	call.accepted = CurTime()

	net.Start("McPhone.CallAccept")
		net.WriteBool(call.payphone ~= nil)
	net.Send(call.caller)

	net.Start("McPhone.CallAccept")
		net.WriteBool(false)
	net.Send(ply)

	McPhone.RefreshStatus(ply)
end)

net.Receive("McPhone.CallDeny", function(_, ply)
	endExtra(ply, false)

	local call = McPhone.Calls[ply]

	if call then
		endCall(call, ply)
	end
end)

-- 0 - разговор со служебным номером окончен (McPhone.StopCall);
-- 1 шлёт страница busted.html форума overloaded (modules/web_gov.lua) - не обрабатывается
net.Receive("McPhone.CallExtraNumber", function(_, ply)
	if net.ReadUInt(2) ~= 0 then return end

	local extra = ply.McPhoneExtra

	-- дослушал до конца - откроется меню номера (полсекунды - на таймеры клиента)
	endExtra(ply, extra ~= nil and CurTime() >= extra.ready - 0.5)
end)

local function hangUp(ply)
	endExtra(ply, false)
	ply.McPhoneExtraDone = nil

	local call = McPhone.Calls[ply]

	if call then
		endCall(call)
	end

	ply.McPhoneOpen = nil

	if IsValid(ply.McPayPhone) then
		ply.McPayPhone:SetStatIdle(true)
	end

	ply.McPayPhone = nil

	McPhone.RefreshStatus(ply)
end

hook.Add("PlayerDeath", "McPhone.Calls", hangUp)
hook.Add("PlayerDisconnected", "McPhone.Calls", hangUp)
hook.Add("MCR.CharacterReset", "McPhone.Calls", hangUp)

--[[---------------------------------------------------------------------------
	Сигнал, вышки, глушилки
---------------------------------------------------------------------------]]
local function signalAt(ply)
	local cfg = McPhone.Config
	local pos = ply:GetPos()
	local jam = (tonumber(cfg.JammerRange) or 0) ^ 2

	for _, jammer in ipairs(McPhone.EP1.Jammers) do
		if IsValid(jammer) and jammer:GetActive() and pos:DistToSqr(jammer:GetPos()) <= jam then return 0 end
	end

	if not cfg.TowerRangebasedNet then return 3 end

	local towers, nearest = 0, nil

	for _, tower in ipairs(McPhone.EP1.Towers) do
		if IsValid(tower) then
			towers = towers + 1

			if not tower:GetDestroyed() then
				local dist = pos:DistToSqr(tower:GetPos())

				if not nearest or dist < nearest then nearest = dist end
			end
		end
	end

	if towers == 0 then return 3 end
	if not nearest then return 0 end

	local range = tonumber(cfg.TowerMaxRange) or 0
	local dist = math.sqrt(nearest)

	if dist <= range / 3 then return 3 end
	if dist <= range * 2 / 3 then return 2 end
	if dist <= range then return 1 end

	return 0
end

local function callBroken(call, now)
	local caller, callee = call.caller, call.callee

	if not IsValid(caller) or not IsValid(callee) then return true end

	local pay = call.payphone

	if pay then
		if not IsValid(pay) or caller.McPayPhone ~= pay or pay:GetPos():DistToSqr(caller:GetPos()) > PAYPHONE_RANGE or not McPhone.CanUsePhone(caller, true) then return true end
	elseif not McPhone.CanUsePhone(caller) or signalOf(caller) < 1 then
		return true
	end

	if not McPhone.CanUsePhone(callee, false, true) or signalOf(callee) < 1 then return true end

	return not call.accepted and now - call.start > RING_TIME
end

local function tick()
	local now = CurTime()

	for _, tower in ipairs(McPhone.EP1.Towers) do
		if IsValid(tower) then
			-- разрушенная - DestroyTime, повреждённая, которую больше не трогали, - DamageTime
			local due = tower:GetDestroyed() and tower.DestroyTime or tower.DamageTime

			if (due or 0) > 0 and due <= now then
				tower:Repair()
				tower.DamageTime = 0
			end
		end
	end

	for _, jammer in ipairs(McPhone.EP1.Jammers) do
		if IsValid(jammer) and jammer:GetActive() and jammer.LiveTime and jammer.LiveTime <= now then
			jammer:BreakJammer()
		end
	end

	local players = player.GetAll()

	for _, ply in ipairs(players) do
		local signal = signalAt(ply)

		ply.McPhoneSignal = signal

		if ply.DarkRPClientReady and ply.McPhoneSignalSent ~= signal then
			ply.McPhoneSignalSent = signal

			net.Start("McPhone.SignalChange")
				net.WriteInt(signal, 3)
			net.Send(ply)
		end

		-- номер без меню клиент заканчивает сам ("занято" после записи), с меню - сообщает
		local extra = ply.McPhoneExtra

		if extra and now >= extra.ready + (extra.func and EXTRA_STALE or 0) then
			endExtra(ply, false)
		end
	end

	local calls = {}

	for _, call in pairs(McPhone.Calls) do
		calls[call] = true
	end

	for call in pairs(calls) do
		if callBroken(call, now) then
			endCall(call)
		end
	end

	for _, ply in ipairs(players) do
		syncLook(ply)
		McPhone.RefreshStatus(ply)
	end
end

timer.Create("McPhone.Tick", TICK, 0, tick)

hook.Add("PlayerInitialSpawn", "McPhone.Signal", function(ply)
	ply.McPhoneSignal = signalAt(ply)
end)

-- клиент готов: сила сигнала уйдёт со следующей проверкой
hook.Add("DarkRP.PlayerLoaded", "McPhone.Signal", function(ply)
	ply.McPhoneSignalSent = nil
end)

local function spawnTower(pos, ang)
	local tower = ents.Create("mc_antenna")
	if not IsValid(tower) then return nil end

	tower:SetPos(pos)
	tower:SetAngles(ang)
	tower:Spawn()

	local phys = tower:GetPhysicsObject()

	if IsValid(phys) then
		phys:EnableMotion(false)
	end

	return tower
end

-- сохранённые вышки карты: {pos, ang}
local function spawnSaved()
	local saved = istable(McPhone.Config.TowersDLC) and McPhone.Config.TowersDLC[game.GetMap()]
	if not istable(saved) then return end

	for _, v in ipairs(saved) do
		if istable(v) and isvector(v.pos) then
			spawnTower(v.pos, isangle(v.ang) and v.ang or Angle(0, 0, 0))
		end
	end
end

hook.Add("InitPostEntity", "McPhone.Towers", spawnSaved)
hook.Add("PostCleanupMap", "McPhone.Towers", spawnSaved)

net.Receive("McPhone.SaveTowers", function(_, ply)
	if not ply:IsSuperAdmin() or McPhone.LockedConfig or DarkRP.NetDelay(ply, 1) then return end

	local list = {}

	for _, tower in ipairs(ents.FindByClass("mc_antenna")) do
		list[#list + 1] = {pos = tower:GetPos(), ang = tower:GetAngles()}
	end

	if not istable(McPhone.Config.TowersDLC) then
		McPhone.Config.TowersDLC = {}
	end

	McPhone.Config.TowersDLC[game.GetMap()] = list
	file.Write(McPhone.ServerID .. "/mcphone_config.txt", util.TableToJSON(McPhone.Config, true))

	McPhone.Notify(ply, McPhone.GetPhrase("SaveTower"), tostring(#list), true)
	DarkRP.log("other", ply, nil, "сохранил вышки связи на карте: " .. #list)
end)

net.Receive("McPhone.SpawnTower", function(_, ply)
	if not ply:IsSuperAdmin() or DarkRP.NetDelay(ply, 1) then return end

	local tower = spawnTower(ply:GetEyeTrace().HitPos, Angle(0, ply:EyeAngles().y, 0))

	if IsValid(tower) then
		DarkRP.log("other", ply, nil, "поставил вышку связи", nil, nil, tower)
	end
end)

net.Receive("McPhone.RemoveTowers", function(_, ply)
	if not ply:IsSuperAdmin() or DarkRP.NetDelay(ply, 1) then return end

	local count = 0

	for _, tower in ipairs(ents.FindByClass("mc_antenna")) do
		tower:Remove()
		count = count + 1
	end

	DarkRP.log("other", ply, nil, "убрал вышки связи с карты: " .. count)
end)
