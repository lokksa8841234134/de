--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	sAdmin: серверное ядро

	"sA:Networking", клиент -> сервер (UInt(3) - действие):
		0 - право ранга, 1 - создание/удаление ранга, 3 - запрос данных,
		5 - страница списка, 6 - время игры игрока (обработчики в sv_data.lua)
		2 - меню открыто/закрыто (Bool)
	Сервер -> клиент: 0 - сообщение в чат, 1 - данные sAdmin[args...] = data, 2 - открыть меню

	sAdmin.msg(targets, var, ...)                 - сообщение: ключ языка или шаблон с %s/%t
	                                                targets: игрок, таблица игроков, nil/NULL - консоль
	sAdmin.networkData(target, args, data)        - данные клиенту (target nil - всем)
	sAdmin.queueNetworking(target, fn)            - fn(ply) сразу при открытом меню, иначе при открытии
	sAdmin.getTargets(cmd, ply, str, max, ignore) - цели команды: ^ * @ #userid SteamID64 SteamID имя
	sAdmin.throttle(ply, key, delay)              - true, если действие ещё на кулдауне
	sAdmin.splitArgs(str)                         - разбор аргументов с учётом кавычек
---------------------------------------------------------------------------]]
sAdmin = sAdmin or {}
sAdmin.playerData = sAdmin.playerData or {}
sAdmin.netHandlers = sAdmin.netHandlers or {}

util.AddNetworkString("sA:Networking")

local MAX_QUEUE = 16
local COMPRESS_FROM = 4096

-- DarkRP-команды, которые пишут текст в чат: недоступны при муте
local MUTED_DARKRP = {
	["me"] = true,
	["do"] = true,
	["it"] = true,
	["look"] = true,
	["roll"] = true
}

local menuOpen, netQueue = {}, {}

local function lang(id, ...)
	return slib.getLang("sadmin", sAdmin.config["language"], id, ...)
end

local function lower(str)
	return (utf8 and utf8.lower or string.lower)(str)
end

--[[---------------------------------------------------------------------------
	Кулдауны и приём сетевых сообщений
---------------------------------------------------------------------------]]
sAdmin.throttle = function(ply, key, delay)
	if not IsValid(ply) then return false end

	local now = CurTime()
	ply.sA_Throttle = ply.sA_Throttle or {}

	if (ply.sA_Throttle[key] or 0) > now then return true end
	ply.sA_Throttle[key] = now + (tonumber(delay) or 1)

	return false
end

net.Receive("sA:Networking", function(len, ply)
	if not IsValid(ply) then return end

	local handler = sAdmin.netHandlers[net.ReadUInt(3)]
	if not handler then return end

	xpcall(handler, ErrorNoHaltWithStack, ply, len)
end)

--[[---------------------------------------------------------------------------
	Сообщения в чат
---------------------------------------------------------------------------]]
local function playerEntry(ply)
	if IsValid(ply) and ply:IsPlayer() then
		return {index = ply:EntIndex(), nick = ply:SteamName()}
	end

	return {index = 0, nick = lang("console")}
end

-- аргумент -> формат niceDisplayText; второй результат true - сообщение не отправляется
local function convertArg(v)
	if v == nil then return lang("n/a") end
	if isentity(v) then return {hasPlayer = true, playerEntry(v)} end
	if not istable(v) then return tostring(v) end
	if table.IsEmpty(v) then return nil, true end

	local list, plain = {hasPlayer = true}, false

	for _, p in ipairs(v) do
		if not isentity(p) then
			plain = true
			break
		end

		if IsValid(p) and p:IsPlayer() then
			list[#list + 1] = playerEntry(p)
		end
	end

	if plain then
		local parts = {}

		for _, p in ipairs(v) do
			parts[#parts + 1] = tostring(p)
		end

		return table.concat(parts, ", ")
	end

	if #list == 0 then return nil, true end

	return list
end

local function recipients(targets)
	if isentity(targets) then
		if IsValid(targets) and targets:IsPlayer() then return {targets}, false end

		return {}, true
	end

	if istable(targets) then
		local list = {}

		for _, p in ipairs(targets) do
			if isentity(p) and IsValid(p) and p:IsPlayer() then
				list[#list + 1] = p
			end
		end

		return list, sAdmin.config["console_prints"]["fine_print"] == true
	end

	return {}, true
end

sAdmin.msg = function(targets, var, ...)
	if not isstring(var) then return end

	local raw, info = {...}, {}

	for i = 1, select("#", ...) do
		local value, abort = convertArg(raw[i])
		if abort then return end

		info[i] = value
	end

	local list, toConsole = recipients(targets)

	if #list > 0 then
		net.Start("sA:Networking")
			net.WriteUInt(0, 3)
			net.WriteString(var)
			net.WriteString(util.TableToJSON(info) or "[]")
		net.Send(list)
	end

	local final = sAdmin.niceDisplayText(var, info)

	if toConsole then
		MsgC(sAdmin.config["chat_prefix"][1], sAdmin.config["chat_prefix"][2], unpack(final))
		MsgN()
	end

	return final
end

--[[---------------------------------------------------------------------------
	Данные для клиента
---------------------------------------------------------------------------]]
local function validPlayers(tbl)
	local list = {}

	for _, p in ipairs(tbl) do
		if isentity(p) and IsValid(p) and p:IsPlayer() then
			list[#list + 1] = p
		end
	end

	return list
end

sAdmin.networkData = function(target, args, data)
	if not istable(args) then return end

	if isentity(target) then
		if not IsValid(target) or not target:IsPlayer() then return end
	elseif istable(target) then
		target = validPlayers(target)
		if #target == 0 then return end
	elseif target ~= nil or player.GetCount() == 0 then
		return
	end

	local json = util.TableToJSON({args = args, data = data})
	if not json then return end

	net.Start("sA:Networking")
		net.WriteUInt(1, 3)

		if #json > COMPRESS_FROM then
			local compressed = util.Compress(json)
			net.WriteBool(true)
			net.WriteUInt(#compressed, 32)
			net.WriteData(compressed, #compressed)
		else
			net.WriteBool(false)
			net.WriteString(json)
		end

	if target == nil then
		net.Broadcast()
	else
		net.Send(target)
	end
end

--[[---------------------------------------------------------------------------
	Состояние меню и отложенная отправка
---------------------------------------------------------------------------]]
local function flushQueue(ply)
	local queue = netQueue[ply]
	netQueue[ply] = nil

	if not queue then return end

	for _, fn in ipairs(queue) do
		xpcall(fn, ErrorNoHaltWithStack, ply)
	end
end

sAdmin.netHandlers[2] = function(ply)
	local state = net.ReadBool()

	if state and not sAdmin.hasPermission(ply, "menu") then
		menuOpen[ply] = nil
		return
	end

	menuOpen[ply] = state or nil

	if state then
		flushQueue(ply)
	end
end

sAdmin.isMenuOpen = function(ply)
	return menuOpen[ply] == true
end

sAdmin.queueNetworking = function(target, fn)
	if not isfunction(fn) then return end

	if target == nil then
		for _, p in ipairs(player.GetHumans()) do
			if sAdmin.hasPermission(p, "menu") then
				sAdmin.queueNetworking(p, fn)
			end
		end

		return
	end

	if not IsValid(target) then return end

	if menuOpen[target] then
		xpcall(fn, ErrorNoHaltWithStack, target)
		return
	end

	local queue = netQueue[target] or {}
	netQueue[target] = queue

	if #queue >= MAX_QUEUE then
		table.remove(queue, 1)
	end

	queue[#queue + 1] = fn
end

hook.Add("PlayerDisconnected", "sA:ClearMenuState", function(ply)
	menuOpen[ply] = nil
	netQueue[ply] = nil
end)

--[[---------------------------------------------------------------------------
	Поиск целей
---------------------------------------------------------------------------]]
local function findPlayers(ply, str)
	local console = not IsValid(ply)

	if str == "" or str == "^" then
		return console and {} or {ply}
	end

	if str == "*" then return player.GetAll() end

	if str == "@" then
		if console then return {} end
		local ent = ply:GetEyeTrace().Entity

		return (IsValid(ent) and ent:IsPlayer()) and {ent} or {}
	end

	local userid = string.match(str, "^#(%d+)$")

	if userid then
		local target = Player(tonumber(userid))

		return IsValid(target) and {target} or {}
	end

	if string.match(str, "^7656119%d+$") then
		local target = player.GetBySteamID64(str)

		return IsValid(target) and {target} or {}
	end

	local upper = string.upper(str)

	if string.match(upper, "^STEAM_%d:%d:%d+$") then
		local target = player.GetBySteamID(upper) or player.GetBySteamID((string.gsub(upper, "^STEAM_1", "STEAM_0")))

		return IsValid(target) and {target} or {}
	end

	local needle = lower(str)
	local exact, partial = {}, {}

	for _, v in ipairs(player.GetAll()) do
		local steam, nick = lower(v:SteamName() or ""), lower(v:Nick() or "")

		if steam == needle or nick == needle then
			exact[#exact + 1] = v
		elseif string.find(steam, needle, 1, true) or string.find(nick, needle, 1, true) then
			partial[#partial + 1] = v
		end
	end

	return #exact > 0 and exact or partial
end

sAdmin.getTargets = function(cmd, ply, str, max, ignore_immunity)
	str = string.Trim(str ~= nil and tostring(str) or "")

	local found = findPlayers(ply, str)

	if #found == 0 then
		sAdmin.msg(ply, "no_targets")
		return {}
	end

	if IsValid(ply) and not ignore_immunity and not sAdmin.config["ignore_immunity_cmds"][cmd] then
		local allowed, blocked = {}, {}

		for _, v in ipairs(found) do
			if v == ply or sAdmin.canTarget(ply, v) then
				allowed[#allowed + 1] = v
			else
				blocked[#blocked + 1] = v
			end
		end

		if #blocked > 0 then
			sAdmin.msg(ply, "unavailable_plys", blocked)
		end

		found = allowed
		if #found == 0 then return {} end
	end

	if max and #found > max then
		sAdmin.msg(ply, "too_many_targets")
		return {}
	end

	return found
end

--[[---------------------------------------------------------------------------
	Команды из чата: !команда, /команда, $команда (тихо), сокращения вроде @
---------------------------------------------------------------------------]]
sAdmin.splitArgs = function(str)
	local args, buf, quoted = {}, {}, false

	local function push()
		args[#args + 1] = table.concat(buf)
		buf = {}
	end

	for i = 1, #str do
		local c = string.sub(str, i, i)

		if c == "\"" then
			if quoted or #buf > 0 then push() end
			quoted = not quoted
		elseif not quoted and (c == " " or c == "\t") then
			if #buf > 0 then push() end
		else
			buf[#buf + 1] = c
		end
	end

	if #buf > 0 then push() end

	return args
end

local function resolveCommand(word)
	if not word then return end
	word = string.lower(word)

	if sAdmin.commands[word] then return word end

	local name = sAdmin.abbreviations[word]
	if name and sAdmin.commands[name] then return name end
end

-- хвост аргументов сливается в последний параметр, если он текстовый (причина, сообщение)
local function chatArgs(name, rest)
	local args = sAdmin.splitArgs(rest)
	local inputs = sAdmin.commands[name].inputs
	local count = istable(inputs) and #inputs or 0

	if count > 0 and #args > count and inputs[count][1] == "text" then
		local tail = table.concat(args, " ", count)

		for i = #args, count + 1, -1 do
			args[i] = nil
		end

		args[count] = tail
	end

	return args
end

local function runChatCommand(ply, name, rest, silent)
	if sAdmin.throttle(ply, "chat_command", 0.5) then
		sAdmin.msg(ply, "request_rate_limit")
		return
	end

	local args = chatArgs(name, rest)
	table.insert(args, 1, name)

	concommand.Run(ply, silent and "sa_silent" or "sa", args, table.concat(args, " "))
end

local function directAbbreviation(text)
	for abbr, name in pairs(sAdmin.abbreviations) do
		if string.match(abbr, "^%p+$") and string.sub(text, 1, #abbr) == abbr and sAdmin.commands[name] then
			return name, string.sub(text, #abbr + 1)
		end
	end
end

hook.Add("PlayerSay", "sA:ChatCommands", function(ply, text)
	if not IsValid(ply) or not isstring(text) then return end

	local trimmed = string.Trim(text)
	if trimmed == "" then return end

	if sAdmin.config["chat_command"][string.lower(trimmed)] then
		if sAdmin.hasPermission(ply, "menu") then
			net.Start("sA:Networking")
				net.WriteUInt(2, 3)
			net.Send(ply)
		else
			sAdmin.msg(ply, "no_permission", "menu")
		end

		return ""
	end

	local prefix = string.sub(trimmed, 1, 1)
	local silent = sAdmin.config["silent_chat_command_prefix"][prefix] == true

	if silent or sAdmin.config["chat_command_prefix"][prefix] then
		local word, rest = string.match(string.sub(trimmed, 2), "^(%S+)%s*(.*)$")
		local name = resolveCommand(word)

		if name then
			runChatCommand(ply, name, rest or "", silent)
			return ""
		end
	end

	local name, rest = directAbbreviation(trimmed)

	if name and sAdmin.hasPermission(ply, name) then
		runChatCommand(ply, name, string.Trim(rest), false)
		return ""
	end

	if sAdmin.muted and sAdmin.muted[ply:SteamID64()] then
		local cmd = string.match(trimmed, "^/(%S+)")

		if not cmd or MUTED_DARKRP[string.lower(cmd)] then
			sAdmin.msg(ply, "Ваш чат заблокирован администрацией.")
			return ""
		end
	end
end)
