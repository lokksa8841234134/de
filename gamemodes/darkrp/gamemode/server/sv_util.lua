--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Серверные утилиты ядра: уведомления, UI-эффекты, передача данных,
	антиспам net/команд, логи, Discord-вебхуки, поиск свободной позиции.
---------------------------------------------------------------------------]]
util.AddNetworkString("GLA.Notify")
util.AddNetworkString("GLA.UIEffects")
util.AddNetworkString("DarkRP.PlayerSendData")
util.AddNetworkString("DarkRP.SendDataShared")

--[[---------------------------------------------------------------------------
	Уведомления (клиент: GLA.Notify -> String msg, UInt4 type, UInt12 len)
---------------------------------------------------------------------------]]
local function writeNotify(msgtype, len, msg)
	net.WriteString(tostring(msg or ""))
	net.WriteUInt(math.Clamp(math.floor(tonumber(msgtype) or 0), 0, 15), 4)
	net.WriteUInt(math.Clamp(math.floor(tonumber(len) or 4), 0, 4095), 12)
end

function DarkRP.notify(ply, msgtype, len, msg)
	if istable(ply) then
		local targets = {}

		for _, v in ipairs(ply) do
			if IsValid(v) and v:IsPlayer() then targets[#targets + 1] = v end
		end

		if #targets == 0 then return end

		net.Start("GLA.Notify")
			writeNotify(msgtype, len, msg)
		net.Send(targets)

		return
	end

	if not IsValid(ply) then
		print("[DarkRP] " .. tostring(msg))
		return
	end

	net.Start("GLA.Notify")
		writeNotify(msgtype, len, msg)
	net.Send(ply)
end

function DarkRP.notifyAll(msgtype, len, msg)
	net.Start("GLA.Notify")
		writeNotify(msgtype, len, msg)
	net.Broadcast()
end

--[[---------------------------------------------------------------------------
	UI-эффекты (клиент: GLA.UIEffects -> String effect, Bool hasData, [Table])
	target: игрок, таблица игроков или nil (всем)
---------------------------------------------------------------------------]]
function DarkRP.UIEffect(target, effect, data)
	if target ~= nil and not istable(target) and not IsValid(target) then return end

	net.Start("GLA.UIEffects")
		net.WriteString(effect)

		if data ~= nil then
			net.WriteBool(true)
			net.WriteTable(data)
		else
			net.WriteBool(false)
		end

	if target == nil then
		net.Broadcast()
	else
		net.Send(target)
	end
end

--[[---------------------------------------------------------------------------
	Передача таблиц клиенту (сжатие DarkRP.TableCompress)
	DarkRP.PlayerSendData: на клиенте LocalPlayer()[info] = data
	DarkRP.SendDataShared: на клиенте DarkRP[p1][p2] = data
---------------------------------------------------------------------------]]
function DarkRP.SendPlayerData(ply, info, data)
	if not IsValid(ply) or not isstring(info) then return end

	local compressed = DarkRP.TableCompress(data or {})

	net.Start("DarkRP.PlayerSendData")
		net.WriteInt(#compressed, 32)
		net.WriteData(compressed, #compressed)
		net.WriteString(info)
	net.Send(ply)
end

function DarkRP.SendDataShared(target, p1, p2, data)
	if not isstring(p1) or not isstring(p2) then return end
	if target ~= nil and not istable(target) and not IsValid(target) then return end

	local compressed = DarkRP.TableCompress(data or {})

	net.Start("DarkRP.SendDataShared")
		net.WriteInt(#compressed, 32)
		net.WriteData(compressed, #compressed)
		net.WriteString(p1)
		net.WriteString(p2)

	if target == nil then
		net.Broadcast()
	else
		net.Send(target)
	end
end

--[[---------------------------------------------------------------------------
	Антиспам
	DarkRP.NetDelay(ply, delay) - true, если вызов из этого места был недавно
	DarkRP.SpamBlock(ply, delay) - общий для игрока кулдаун
---------------------------------------------------------------------------]]
function DarkRP.NetDelay(ply, delay)
	if not IsValid(ply) then return true end

	local info = debug.getinfo(2, "Sl")
	local key = info and (info.short_src .. ":" .. (info.currentline or 0)) or "unknown"
	local CT = CurTime()

	ply.DarkRPNetDelay = ply.DarkRPNetDelay or {}

	if ply.DarkRPNetDelay[key] and ply.DarkRPNetDelay[key] > CT then return true end

	ply.DarkRPNetDelay[key] = CT + (tonumber(delay) or 1)

	return false
end

function DarkRP.SpamBlock(ply, delay)
	if not IsValid(ply) then return true end

	local CT = CurTime()
	if ply.DarkRPSpamBlock and ply.DarkRPSpamBlock > CT then return true end

	ply.DarkRPSpamBlock = CT + (tonumber(delay) or 1)

	return false
end

--[[---------------------------------------------------------------------------
	Логи: файл data/darkrp_logs/ГГГГ-ММ-ДД.txt + консоль админов (AdminLog)
	DarkRP.log(category, ply, target, text, color, value, ent)
---------------------------------------------------------------------------]]
local logColors = {
	money = Color(120, 230, 120),
	police = Color(90, 160, 255),
	crime = Color(255, 90, 90),
	damage = Color(255, 160, 60),
	property = Color(230, 200, 90),
	other = Color(200, 200, 200),
}

local function describe(ent)
	if not IsValid(ent) then return nil end

	if ent:IsPlayer() then
		return string.format("%s [%s | %s]", ent:FullName() or "", ent:SteamName(), ent:SteamID())
	end

	return tostring(ent)
end

file.CreateDir("darkrp_logs")

function DarkRP.log(category, ply, target, text, color, value, ent)
	category = isstring(category) and category or "other"

	local parts = {}
	local actor = describe(ply)
	if actor then parts[#parts + 1] = actor end
	parts[#parts + 1] = tostring(text or "")

	local victim = describe(target)
	if victim then parts[#parts + 1] = "-> " .. victim end
	if value ~= nil then parts[#parts + 1] = "(" .. tostring(value) .. ")" end

	if IsValid(ent) then
		local pos = ent:GetPos()
		parts[#parts + 1] = string.format("@ %d %d %d", pos.x, pos.y, pos.z)
	end

	local msg = table.concat(parts, " ")
	local col = IsColor(color) and color or logColors[category] or logColors.other

	file.Append("darkrp_logs/" .. os.date("%Y-%m-%d") .. ".txt", os.date("[%H:%M:%S] ") .. "[" .. category .. "] " .. msg .. "\n")
	MsgC(col, "[DarkRP:" .. category .. "] ", color_white, msg, "\n")

	local admins = {}

	for _, v in ipairs(player.GetHumans()) do
		if v:IsAdmin() then admins[#admins + 1] = v end
	end

	if #admins > 0 then
		DarkRP.UIEffect(admins, "AdminLog", {prf = category, cl = Color(col.r, col.g, col.b), msg = msg})
	end
end

--[[---------------------------------------------------------------------------
	Discord-вебхуки (адреса в config/discord.lua)
	Discord.Log(channel, {content = "", username = "", embeds = {}})
---------------------------------------------------------------------------]]
Discord = Discord or {}

local chttpLoaded = false

if util.IsBinaryModuleInstalled("chttp") then
	chttpLoaded = pcall(require, "chttp") and isfunction(CHTTP)
end

function Discord.Log(channel, payload)
	local url = DarkRP.DiscordWebhooks and DarkRP.DiscordWebhooks[channel]
	if not isstring(url) or url == "" then return false end

	if isstring(payload) then
		payload = {content = payload}
	end

	if not istable(payload) then return false end

	if isstring(payload.content) then
		local content = utf8.force(payload.content)

		if (utf8.len(content) or 0) > 1990 then
			content = utf8.sub(content, 1, 1990)
		end

		payload.content = content
	end

	local request = {
		url = url,
		method = "POST",
		type = "application/json",
		body = util.TableToJSON(payload),
		failed = function(err)
			MsgC(Color(255, 90, 0), "[DarkRP] Discord webhook (" .. tostring(channel) .. "): " .. tostring(err) .. "\n")
		end
	}

	if chttpLoaded then
		CHTTP(request)
	else
		HTTP(request)
	end

	return true
end

--[[---------------------------------------------------------------------------
	Поиск свободного места для игрока/сущности
	GAMEMODE:FindEmptyPos(pos, ignore, distance, step, area)
---------------------------------------------------------------------------]]
function DarkRP.isEmpty(vector, ignore)
	ignore = ignore or {}

	local point = util.PointContents(vector)
	local a = point ~= CONTENTS_SOLID
		and point ~= CONTENTS_MOVEABLE
		and point ~= CONTENTS_LADDER
		and point ~= CONTENTS_PLAYERCLIP
		and point ~= CONTENTS_MONSTERCLIP

	if not a then return false end

	for _, v in ipairs(ents.FindInSphere(vector, 35)) do
		if (v:IsNPC() or v:IsPlayer() or v:GetClass() == "prop_physics" or v.NotEmptyPos) and not table.HasValue(ignore, v) then
			return false
		end
	end

	return true
end

function DarkRP.findEmptyPos(pos, ignore, distance, step, area)
	area = area or Vector(0, 0, 0)

	if DarkRP.isEmpty(pos, ignore) and DarkRP.isEmpty(pos + area, ignore) then
		return pos
	end

	for j = step, distance, step do
		for i = -1, 1, 2 do
			local k = j * i

			for _, offset in ipairs({Vector(k, 0, 0), Vector(0, k, 0), Vector(0, 0, k)}) do
				local try = pos + offset

				if DarkRP.isEmpty(try, ignore) and DarkRP.isEmpty(try + area, ignore) then
					return try
				end
			end
		end
	end

	return pos
end

function GM:FindEmptyPos(pos, ignore, distance, step, area)
	return DarkRP.findEmptyPos(pos, ignore, distance or 600, step or 30, area)
end

--[[---------------------------------------------------------------------------
	DarkRP.FirePen(ply, dist) - вызывается базой оружия mg_base при каждом
	выстреле на сервере (sh_primaryattack_behaviour.lua, перед self:Bullets()).
	В дампе функции не было, из-за чего серверная часть выстрела падала
	с ошибкой и пули не наносили урон (шаг 8.4.2).
	Что делал оригинал - неизвестно (по названию: "штраф/шум за выстрел"
	на dist юнитов). Здесь: запоминаем время и место выстрела и зовём хук
	DarkRP.PlayerFired(ply, dist) - к нему можно подключить реакцию
	(розыск, NPC, звук), если вспомните, что там было.
---------------------------------------------------------------------------]]
function DarkRP.FirePen(ply, dist)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	ply.LastFireTime = CurTime()
	ply.LastFirePos = ply:GetShootPos()

	hook.Run("DarkRP.PlayerFired", ply, tonumber(dist) or 0)
end
