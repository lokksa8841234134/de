--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Рация - сервер

	Рация есть у профессий из GM.RadioTeams (shared.lua): полиция, ФБР,
	пожарные, парамедики, инспектор. Клиент: меню F2 "Рация" ("Вкл/Выкл",
	"Каналы", client/vgui.lua), клавиша передачи (P, настройка pradio_key,
	mc_phone/cl_hooks.lua), панель справа: канал и кто говорит
	(client/hud.lua).

	net Police.Radio, C->S, UInt(3) - действие:
	  0 - выключить, 1 - включить;
	  2 и UInt(5) - канал: 1-3 PD, 4-6 FD, 10 COM;
	  3 - начать передачу, 4 - закончить (клавиша переключает).
	Переменные DarkRP, видны всем: rc_on - рация включена, rc - канал,
	rc_speek - идёт передача. Канал по умолчанию ставит профессия
	(PlayerChangeTeam в jobs.lua), при смене профессии он сбрасывается
	(sv_jobs.lua).

	Кто кого слышит - plyMeta:CanRadio (sh_init.lua, код автора): у
	говорящего идёт передача, у обоих включена рация и один канал. На COM
	канале говорит только ранг 6+ (MRS), его слышат все, у кого есть рация.
	Голос по рации - GM:PlayerCanHearPlayersVoice (server/sv_chat.lua): на
	любом расстоянии, без объёмного звука.

	Пользоваться рацией может свободный игрок (IsFreeman): живой, не в
	наручниках, не арестован, не без сознания. Передача обрывается, если
	это изменилось, и при смерти, смене профессии или персонажа.
---------------------------------------------------------------------------]]

util.AddNetworkString("Police.Radio")

local ACT_OFF, ACT_ON, ACT_CHANNEL, ACT_TALK, ACT_STOP = 0, 1, 2, 3, 4
local NET_DELAY = 0.25 -- клавиша передачи на клиенте - не чаще раза в секунду
local COM_CHANNEL = 10
local COM_RANK = 5 -- как в CanRadio: на COM канале говорит ранг больше 5

-- названия - как на панели рации (client/hud.lua)
local CHANNELS = {
	[1] = "PD канал #1",
	[2] = "PD канал #2",
	[3] = "PD канал #3",
	[4] = "FD канал #1",
	[5] = "FD канал #2",
	[6] = "FD канал #3",
	[COM_CHANNEL] = "COM канал",
}

-- переменные, при которых передача обрывается: наручники, арест, тюрьма,
-- без сознания (как в IsFreeman)
local RESTRAINTS = {
	HandCuffed = true,
	Arrested = true,
	jailed = true,
	unconscious = true,
}

local function hasRadio(ply)
	return GAMEMODE.RadioTeams[ply:Team()] == true
end

local function stopTalk(ply)
	ply:SetDarkRPVar("rc_speek", nil)
end

local function radioOff(ply)
	ply:SetDarkRPVar("rc_speek", nil)
	ply:SetDarkRPVar("rc_on", nil)
end

-- ранг для COM канала. Серверной части рангов MRS пока нет (шаг 15):
-- MRS.GetNWdata вернёт false, и говорить на COM канале не может никто
local function comSpeaker(ply)
	local rank = tonumber(MRS.GetNWdata(ply, "Rank"))

	return rank ~= nil and rank > COM_RANK
end

local actions = {}

actions[ACT_OFF] = radioOff

actions[ACT_ON] = function(ply)
	if ply:getDarkRPVar("rc_on") then return end

	ply:SetDarkRPVar("rc_on", true)
end

actions[ACT_CHANNEL] = function(ply)
	local ch = net.ReadUInt(5)
	if not CHANNELS[ch] then return end

	ply:SetDarkRPVar("rc", ch)

	if ch == COM_CHANNEL and not comSpeaker(ply) then
		stopTalk(ply)
		return
	end
end

actions[ACT_TALK] = function(ply)
	if not ply:getDarkRPVar("rc_on") then return end

	local ch = ply:getDarkRPVar("rc")

	if not CHANNELS[ch] then
		return
	end

	if ch == COM_CHANNEL and not comSpeaker(ply) then
		return
	end

	ply:SetDarkRPVar("rc_speek", true)
end

actions[ACT_STOP] = stopTalk

net.Receive("Police.Radio", function(_, ply)
	if not IsValid(ply) or not hasRadio(ply) then return end

	local act = net.ReadUInt(3)
	local fn = actions[act]
	if not fn then return end

	-- закончить передачу можно всегда и сразу
	if act ~= ACT_STOP then
		if DarkRP.NetDelay(ply, NET_DELAY) then return end

		if not ply:IsFreeman() then
			return
		end
	end

	fn(ply)
end)

--[[---------------------------------------------------------------------------
	Когда передача обрывается или рация выключается
---------------------------------------------------------------------------]]
hook.Add("DarkRPVarChanged", "DarkRP.Radio", function(ply, var, _, new)
	if new == nil or not RESTRAINTS[var] then return end
	if ply:getDarkRPVar("rc_speek") then stopTalk(ply) end
end)

hook.Add("PlayerDeath", "DarkRP.Radio", function(ply)
	stopTalk(ply)
end)

hook.Add("PlayerSpawn", "DarkRP.Radio", function(ply)
	stopTalk(ply)
end)

-- новая профессия с рацией: рация остаётся включённой, канал - новой
-- профессии; без рации - выключается
hook.Add("OnPlayerChangedTeam", "DarkRP.Radio", function(ply, _, new)
	if GAMEMODE.RadioTeams[new] then
		stopTalk(ply)
	else
		radioOff(ply)
	end
end)

hook.Add("MCR.CharacterReset", "DarkRP.Radio", radioOff)
