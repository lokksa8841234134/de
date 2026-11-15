--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Ограбление (/rob) - кнопка «Ограбить» в меню C (client/vgui.lua)

	Ваши слова к 13.2: игрок в F2 нажимает «Сдаться» (поза со сложенными
	руками, idle_sit 4 + ground_sit); ты с пистолетом подходишь сзади, появляется
	плашка «Ограбить» - просто анимация, и у него снимается немного денег.

	Грабитель: нелегал (TEAM_GANG), живой, в сознании, без наручников, не в
	машине, с огнестрелом в руках (DarkRP.SingleWep.FireArms - условие кнопки
	у клиента). Жертва: игрок, который сдался (поза «Сдаться» на земле), живой,
	не в наручниках, стоит спереди от грабителя на расстоянии до ROB_RANGE и
	грабитель - у неё за спиной. Полицию, лежащих без сознания и закованных не
	грабят. Деньги: 5-10 % наличных, не больше ROB_MAX; на жертве меньше
	ROB_MIN_WALLET - не грабят. Идёт полоса ROB_TIME секунд и жест передачи;
	отошёл, убрал оружие, жертва встала или умерла - прервалось.
	Ваш ответ к 14: одного человека повторно - через ROB_VICTIM_CD (40 минут)
	после удачного ограбления, кто бы ни грабил; другого - сразу, и он тоже
	уходит на 40 минут. Перезарядка считается по SteamID - выход с сервера
	и смена персонажа её не сбрасывают. Прерванное ограбление перезарядку не
	ставит. Сообщений о перезарядке нет: кнопка просто ничего не делает.
	Двое одну жертву одновременно не грабят.
---------------------------------------------------------------------------]]
local ROB_RANGE = 90				-- юнитов
local ROB_TIME = 5					-- секунд
local ROB_VICTIM_CD = 2400			-- один человек, секунд (40 минут)
local ROB_PERCENT = {5, 10}
local ROB_MAX = 3000
local ROB_MIN_WALLET = 100
local SURRENDER_POSE = 4			-- idle_sit 4 в меню F2

local active = {}	-- [грабитель] = {victim, finish}
local robbedUntil = {}	-- [SteamID64 жертвы] = CurTime(), до которого её не грабят

local function robKey(ply)
	return ply:SteamID64() or ("bot" .. ply:UserID())
end

local function cooling(victim, now)
	return (robbedUntil[robKey(victim)] or 0) > now
end

-- эту жертву уже грабит кто-то другой
local function busy(victim, robber)
	for ply, data in pairs(active) do
		if ply ~= robber and IsValid(ply) and data.victim == victim then return true end
	end

	return false
end

local function surrendered(ply)
	return ply:GetNWBool("SitAnyG_", false) and ply:getDarkRPVar("sa") == SURRENDER_POSE
end

local function canRob(ply)
	return IsValid(ply) and ply:Alive() and not ply.DarkRPUnInitialized and not ply:getDarkRPVar("unconscious")
		and ply:IsUnrestrained() and not ply:InVehicle() and ply:Team() == TEAM_GANG
end

local function armed(ply)
	local wep = ply:GetActiveWeapon()

	return IsValid(wep) and DarkRP.SingleWep and DarkRP.SingleWep.FireArms and DarkRP.SingleWep.FireArms[wep:GetClass()] and true or false
end

-- жертва перед грабителем и он у неё за спиной
local function target(ply)
	local tr = util.TraceLine({
		start = ply:EyePos(),
		endpos = ply:EyePos() + ply:GetAimVector() * ROB_RANGE,
		filter = ply
	})

	local victim = tr.Entity

	if not IsValid(victim) or not victim:IsPlayer() or victim == ply or victim.DarkRPUnInitialized then return nil end

	return victim
end

local function behind(ply, victim)
	local to = ply:GetPos() - victim:GetPos()
	to.z = 0

	local face = victim:GetAimVector()
	face.z = 0

	return to:Dot(face) < 0
end

local function victimOK(victim)
	if not victim:Alive() or victim:getDarkRPVar("unconscious") or victim:getDarkRPVar("HandCuffed") then return false end
	if victim:isCP() then return false end

	return surrendered(victim)
end

local function stop(ply)
	if not active[ply] then return end

	active[ply] = nil
	net.SendSingleMessage("RemovePropgressBar", ply)
	timer.Remove("DarkRP.Rob" .. ply:UserID())
end

local function finish(ply, victim)
	active[ply] = nil

	if not IsValid(ply) or not IsValid(victim) then return end
	if not canRob(ply) or not armed(ply) or not victimOK(victim) or not behind(ply, victim) then return end
	if ply:GetPos():DistToSqr(victim:GetPos()) > ROB_RANGE * ROB_RANGE * 1.5 then return end

	local wallet = victim:getDarkRPVar("money") or 0
	local amount = math.min(math.floor(wallet * math.random(ROB_PERCENT[1], ROB_PERCENT[2]) / 100), ROB_MAX, wallet)
	if amount <= 0 then return end

	victim:addMoney(-amount)
	ply:addMoney(amount)

	robbedUntil[robKey(victim)] = CurTime() + ROB_VICTIM_CD

	DarkRP.log("crime", ply, victim, "ограбил игрока", nil, amount)
end

DarkRP.defineChatCommand("rob", function(ply)
	if not canRob(ply) or not armed(ply) or active[ply] then return "" end
	if DarkRP.NetDelay(ply, 1) then return "" end

	local CT = CurTime()

	local victim = target(ply)
	if not victim or not victimOK(victim) or not behind(ply, victim) then return "" end
	if (victim:getDarkRPVar("money") or 0) < ROB_MIN_WALLET then return "" end
	if cooling(victim, CT) or busy(victim, ply) then return "" end

	active[ply] = {victim = victim, finish = CT + ROB_TIME}

	net.Start("DrawProgressBar")
		net.WriteFloat(ROB_TIME)
	net.Send(ply)

	DarkRP.UIEffect(nil, "anim_giveitem", {ply:UserID()})

	-- прервать, если что-то изменилось
	timer.Create("DarkRP.Rob" .. ply:UserID(), 0.25, 0, function()
		local data = active[ply]

		if not IsValid(ply) or not data then timer.Remove("DarkRP.Rob" .. (IsValid(ply) and ply:UserID() or 0)) return end

		local v = data.victim

		if not IsValid(v) or not canRob(ply) or not armed(ply) or not victimOK(v) or not behind(ply, v)
			or ply:GetPos():DistToSqr(v:GetPos()) > ROB_RANGE * ROB_RANGE * 1.5 then
			stop(ply)
			return
		end

		if CurTime() >= data.finish then
			timer.Remove("DarkRP.Rob" .. ply:UserID())
			finish(ply, v)
			net.SendSingleMessage("RemovePropgressBar", ply)
		end
	end)

	return ""
end)

hook.Add("PlayerDisconnected", "DarkRP.Rob", function(ply)
	active[ply] = nil
	timer.Remove("DarkRP.Rob" .. ply:UserID())
end)
