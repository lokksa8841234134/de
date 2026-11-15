--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Вызовы служб (911) - сервер

	Вызов приходит из меню номера 911 в телефоне (ExtraNumbersFunc["911"],
	mc_phone/sh_init.lua): services_request - служба и причина. Принимается,
	только если игрок только что дозвонился до 911 (McPhone.TakeExtraCall,
	mc_phone/sv_init.lua); причины - как в меню: у полиции список police_call
	(sh_init.lua), у FDNY - скорая и пожар. Звонил с мобильного - в вызове
	его номер, диспетчер может перезвонить ("Связаться с заявителем"), с
	таксофона номера нет. Сигнализация (испуг NPC, mcs_npc/shared.lua)
	вызывает Dispatcher.Call сама.

	Dispatcher.Call(служба, позиция, причина, имя, номер, игрок) - новый
	вызов (номер и игрок для журнала - необязательны): ответственным -
	уведомление на телефон, всем, кто видит вызовы службы, - новый список.

	Меню "Вызовы" (autorun/client/cl_services.lua):
	  services_update  C->S: служба - прислать список
	                   S->C: служба, размер, сжатая таблица вызовов
	                   {[номер] = {name, reason, time, number, pos, status
	                   (1 - открыт, 2 - завершён), responders = {[SteamID] =
	                   {unit, name}}, closedby, closed}}
	  services_respond C->S: служба, номер вызова, действие: 1 - принять,
	                   2 - открепиться, 3 - завершить
	Список видят профессии службы (Teams, sh_services_config.lua) и
	ответственные (Responders: NYPD - полиция, FDNY - пожарные и медики);
	принимать и завершать могут ответственные. Принять - только с позывным
	(DarkRP.Police.Units, police/sv_units.lua): клиент показывает позывные
	прикреплённых. Завершить - только прикреплённый. Хранятся последние 30
	вызовов службы. Сменил профессию, персонажа или вышел - открепляется от
	открытых вызовов.
---------------------------------------------------------------------------]]

AddCSLuaFile("sh_services_config.lua")
include("sh_services_config.lua")

util.AddNetworkString("services_request")
util.AddNetworkString("services_update")
util.AddNetworkString("services_respond")

local MAX_CALLS = 30

-- причины FDNY - кнопки меню 911 (у полиции - police_call)
local FDNY_REASONS = {
	["Запрос скорой медицинской помощи"] = true,
	["Возгорание, пожар"] = true,
}

-- [служба] = {[номер] = вызов}
Dispatcher.Calls = Dispatcher.Calls or {}
Dispatcher.LastID = Dispatcher.LastID or {}

local function validReason(grp, reason)
	if grp == "NYPD" then return istable(police_call) and table.HasValue(police_call, reason) end
	if grp == "FDNY" then return FDNY_REASONS[reason] == true end

	return false
end

local function canView(ply, cfg)
	return cfg.Teams[ply:Team()] or cfg.Responders(ply)
end

local function viewers(grp)
	local cfg = Dispatcher.Config.Grps[grp]
	local list = {}

	for _, ply in ipairs(player.GetAll()) do
		if ply.DarkRPClientReady and canView(ply, cfg) then
			list[#list + 1] = ply
		end
	end

	return list
end

local function send(grp, list)
	if #list == 0 then return end

	local data, len = DarkRP.TableCompress(Dispatcher.Calls[grp] or {})

	net.Start("services_update")
		net.WriteString(grp)
		net.WriteUInt(len, 32)
		net.WriteData(data, len)
	net.Send(list)
end

function Dispatcher.Call(grp, pos, reason, name, number, caller)
	local cfg = Dispatcher.Config.Grps[grp]
	if not cfg or not isvector(pos) then return nil end

	local id = (Dispatcher.LastID[grp] or 0) + 1
	Dispatcher.LastID[grp] = id

	local calls = Dispatcher.Calls[grp] or {}
	Dispatcher.Calls[grp] = calls

	local call = {
		name = tostring(name or ""),
		reason = tostring(reason or ""),
		time = os.time(),
		number = number,
		pos = pos,
		status = 1,
		responders = {},
	}

	calls[id] = call
	calls[id - MAX_CALLS] = nil

	local list = {}

	for _, ply in ipairs(player.GetAll()) do
		if cfg.Responders(ply) then
			list[#list + 1] = ply
		end
	end

	if #list > 0 and McPhone and isfunction(McPhone.Notify) then
		McPhone.Notify(list, McPhone.GetPhrase("char_911"), call.reason, true)
	end

	send(grp, viewers(grp))
	DarkRP.log("police", caller, nil, "вызов " .. grp .. " #" .. id .. ": " .. call.reason .. " (" .. call.name .. ")")

	return id
end

net.Receive("services_request", function(_, ply)
	if DarkRP.NetDelay(ply, 1) then return end

	local grp = net.ReadString()
	local reason = net.ReadString()
	local cfg = Dispatcher.Config.Grps[grp]

	if not cfg or not validReason(grp, reason) or ply:getDarkRPVar("character") == nil or not cfg.CustomCheck(ply) then return end

	local done = McPhone and isfunction(McPhone.TakeExtraCall) and McPhone.TakeExtraCall(ply, "911")
	if not done then return end

	Dispatcher.Call(grp, ply:GetPos(), reason, ply:FullName(), not done.payphone and McPhone.NumberChar(ply) or nil, ply)
end)

net.Receive("services_update", function(_, ply)
	if DarkRP.NetDelay(ply, 1) then return end

	local grp = net.ReadString()
	local cfg = Dispatcher.Config.Grps[grp]

	if not cfg or not canView(ply, cfg) then return end

	send(grp, {ply})
end)

net.Receive("services_respond", function(_, ply)
	if DarkRP.NetDelay(ply, 0.5) then return end

	local grp = net.ReadString()
	local id = net.ReadUInt(32)
	local action = net.ReadUInt(3)
	local cfg = Dispatcher.Config.Grps[grp]
	local call = Dispatcher.Calls[grp] and Dispatcher.Calls[grp][id]

	if not cfg or not call or call.status ~= 1 or not cfg.Responders(ply) or ply:getDarkRPVar("character") == nil then return end

	local sid = ply:SteamID()
	local unit = DarkRP.Police and DarkRP.Police.Units and DarkRP.Police.Units[ply:UserID()]
	local rec = call.responders[sid]

	if action == 1 then
		if rec or not unit then return end

		call.responders[sid] = {unit = unit, name = ply:FullName()}
		DarkRP.log("police", ply, nil, "принял вызов " .. grp .. " #" .. id)
	elseif action == 2 then
		if not rec then return end

		call.responders[sid] = nil
		DarkRP.log("police", ply, nil, "открепился от вызова " .. grp .. " #" .. id)
	elseif action == 3 then
		if not rec then return end

		call.status = 2
		call.closedby = (unit or rec.unit) .. " " .. rec.name
		call.closed = os.time()
		DarkRP.log("police", ply, nil, "завершил вызов " .. grp .. " #" .. id)
	else
		return
	end

	send(grp, viewers(grp))
end)

local function detach(ply)
	local sid = ply:SteamID()

	for grp, calls in pairs(Dispatcher.Calls) do
		local changed = false

		for _, call in pairs(calls) do
			if call.status == 1 and call.responders[sid] then
				call.responders[sid] = nil
				changed = true
			end
		end

		if changed then
			send(grp, viewers(grp))
		end
	end
end

hook.Add("OnPlayerChangedTeam", "Dispatcher.Calls", detach)
hook.Add("PlayerDisconnected", "Dispatcher.Calls", detach)
hook.Add("MCR.CharacterReset", "Dispatcher.Calls", detach)
