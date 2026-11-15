--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Временные состояния игрока - сервер

	ply:AddTempStat(состояние, секунды) - включить переменную-флаг игрока
	на время: "shock" (удары, электрошокер, светошумовая граната),
	"bleeding" (холодное оружие), "fracture" и "fracturearm" (кувалда),
	"cough" (газ, дым пожара), "morph", "relax", "adren", "stamina",
	"narcan" (препараты медика), "meds3" и "hunger" (квесты MQS).
	Все они зарегистрированы как биты (playervars/sh_init.lua); переменная
	только своя (SetSelfDarkRPVar): эффекты на экране и замедление считает
	клиент самого игрока, медику состояние пациента сообщает сервер.
	Повторный вызов продлевает до большего из сроков, но не складывает их.
	Снять состояние раньше срока - просто убрать переменную
	(ply:SetSelfDarkRPVar(состояние, nil): бинты, лечение в sv_medic.lua),
	срок и таймер снимаются вместе с ней.
	Смерть и возрождение снимают все временные состояния.
---------------------------------------------------------------------------]]

local plyMeta = FindMetaTable("Player")

local MAX_TIME = 3600

-- [ply] = {[состояние] = конец по CurTime()}
local temps = {}

local function timerName(ply, stat)
	return "MES.TempStat." .. ply:EntIndex() .. "." .. stat
end

function plyMeta:AddTempStat(stat, time)
	time = tonumber(time)
	if not isstring(stat) or stat == "" or not time or time ~= time or time <= 0 then return end
	if not self:Alive() then return end

	time = math.min(time, MAX_TIME)

	local finish = CurTime() + time
	local list = temps[self]

	if list and list[stat] and list[stat] >= finish then
		-- срок и так дольше; переменную могли снять раньше срока (лечение)
		if not self:getDarkRPVar(stat) then
			self:SetSelfDarkRPVar(stat, true)
		end

		return
	end

	if not list then
		list = {}
		temps[self] = list
	end

	list[stat] = finish
	self:SetSelfDarkRPVar(stat, true)

	local ply = self

	timer.Create(timerName(self, stat), time, 1, function()
		if not IsValid(ply) then return end

		local l = temps[ply]
		if not l or l[stat] ~= finish then return end

		l[stat] = nil
		if next(l) == nil then temps[ply] = nil end

		ply:SetSelfDarkRPVar(stat, nil)
	end)
end

local function clearStats(ply)
	local list = temps[ply]
	if not list then return end

	temps[ply] = nil

	for stat in pairs(list) do
		timer.Remove(timerName(ply, stat))
		ply:SetSelfDarkRPVar(stat, nil)
	end
end

hook.Add("PlayerDeath", "MES.TempStats", clearStats)
hook.Add("PlayerSilentDeath", "MES.TempStats", clearStats)
hook.Add("PlayerSpawn", "MES.TempStats", clearStats)

hook.Add("PlayerDisconnected", "MES.TempStats", function(ply)
	local list = temps[ply]
	if not list then return end

	temps[ply] = nil

	for stat in pairs(list) do
		timer.Remove(timerName(ply, stat))
	end
end)

-- переменную сняли раньше срока: срок и таймер больше не нужны
hook.Add("DarkRPVarChanged", "MES.TempStats", function(ply, var, _, new)
	if new then return end

	local list = temps[ply]
	if not list or not list[var] then return end

	list[var] = nil
	if next(list) == nil then temps[ply] = nil end

	timer.Remove(timerName(ply, var))
end)
