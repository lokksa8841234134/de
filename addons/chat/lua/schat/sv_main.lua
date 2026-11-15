--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Окно чата sChat - сервер

	Подключает autorun/sh_schat.lua (SERVER). Клиент - автора
	(schat/cl_interface.lua, cl_theme.lua), сообщения:
	  schat.say        C->S: UInt(4) канал (0 - чат, 1 - LOOC), String текст
	                   S->C: UInt(4) канал, String текст, Entity игрок -
	                   только если хук PlayerSay вернул непустой текст
	  schat.istyping   C->S: Bool - окно чата открыто / закрыто
	  schat.set_theme  C->S: String - тема сервера (JSON автора, Theme:ToJSON),
	                   пустая строка - убрать; только SChat:CanSetServerTheme
	                   S->C: String - тема сервера (клиент предлагает её кнопкой)
	  schat.set_emojis S->C: эмодзи сервера - не отправляется: у клиента автора
	                   нет Settings:ClearCustomEmojis и Settings:AddOnlineEmoji
	                   (cl_settings.lua), приём сообщения дал бы ошибку Lua

	Сообщение из окна идёт тем же путём, что консольные say и say_team:
	hook.Run("PlayerSay") - хуки (команды sAdmin, MCR.Hide) и GM:PlayerSay
	(server/sv_chat.lua: радиус, LOOC, /команды, без сознания - молчит).
	GM:PlayerSay отвечает пустой строкой и сам рассылает строки чата
	(GLA.OnPlayerChat); если какой-то хук вернул свой текст - он уходит
	по schat.say тем, кого пускает PlayerCanSeePlayersChat, как у движка.

	IsTyping (NW-переменная, PLY:IsTyping клиента автора) - не чаще
	TYPING_TICK: последнее состояние применяется по таймеру.
	Тема сервера хранится в data/schat/server_theme.txt, уходит клиенту
	после загрузки (DarkRP.PlayerLoaded) и всем при смене.
---------------------------------------------------------------------------]]

util.AddNetworkString("schat.say")
util.AddNetworkString("schat.istyping")
util.AddNetworkString("schat.set_theme")
util.AddNetworkString("schat.set_emojis")

local SAY_DELAY = 0.25			-- между сообщениями из окна, с
local SAY_MAX_BYTES = 2048		-- длиннее - не читаем
local TYPING_TICK = 0.2			-- IsTyping обновляется не чаще, с
local THEME_DELAY = 2			-- между сменами темы, с
local THEME_MAX = 1024			-- байт JSON темы
local THEME_DIR = "schat"
local THEME_FILE = THEME_DIR .. "/server_theme.txt"

SChat.serverTheme = SChat.serverTheme or ""

--[[---------------------------------------------------------------------------
	Сообщения
---------------------------------------------------------------------------]]
local function cleanText(text)
	if SChat.CleanupString and utf8.force then
		text = SChat.CleanupString(text)
	else
		text = string.Trim(tostring(text or ""))
	end

	local max = SChat.MAX_MESSAGE_LEN or 250

	if (utf8.len(text) or #text) > max then
		text = utf8.sub(text, 1, max)
	end

	return text
end

local function deliver(ply, text, channel, teamonly)
	local recipients = {}

	for _, listener in ipairs(player.GetHumans()) do
		if hook.Run("PlayerCanSeePlayersChat", text, teamonly, listener, ply) ~= false then
			recipients[#recipients + 1] = listener
		end
	end

	if #recipients == 0 then return end

	net.Start("schat.say")
		net.WriteUInt(channel, 4)
		net.WriteString(text)
		net.WriteEntity(ply)
	net.Send(recipients)
end

net.Receive("schat.say", function(len, ply)
	if not IsValid(ply) or len > (SAY_MAX_BYTES + 8) * 8 then return end

	local CT = CurTime()
	if (ply.SChatNextSay or 0) > CT then return end
	ply.SChatNextSay = CT + SAY_DELAY

	local channel = net.ReadUInt(4)
	if channel > 2 then return end

	local text = cleanText(net.ReadString())
	if text == "" then return end

	-- канал 2 (OOC) окно автора не выбирает (SChat:ChangeMOD), подсказка у него - LOOC
	local teamonly = channel ~= 0

	ServerLog(string.format("\"%s<%d><%s><>\" %s \"%s\"\n", ply:Nick(), ply:UserID(), ply:SteamID(), teamonly and "say_team" or "say", text))

	local result = hook.Run("PlayerSay", ply, text, teamonly)

	if isstring(result) and result ~= "" then
		deliver(ply, result, channel, teamonly)
	end
end)

--[[---------------------------------------------------------------------------
	Окно открыто (над головой и в HUD - PLY:IsTyping)
---------------------------------------------------------------------------]]
net.Receive("schat.istyping", function(_, ply)
	if not IsValid(ply) then return end

	ply.SChatTyping = net.ReadBool()
end)

timer.Create("SChat.Typing", TYPING_TICK, 0, function()
	for _, ply in ipairs(player.GetHumans()) do
		local typing = ply.SChatTyping == true and ply:Alive()

		if ply:GetNWBool("IsTyping", false) ~= typing then
			ply:SetNWBool("IsTyping", typing)
		end
	end
end)

hook.Add("PlayerDeath", "SChat.Typing", function(ply)
	ply.SChatTyping = nil
end)

--[[---------------------------------------------------------------------------
	Тема сервера: поля темы автора (Theme:ToJSON / Theme:Import в cl_theme.lua)
---------------------------------------------------------------------------]]
local function int(value, min, max)
	value = tonumber(value)
	if not value or value ~= value then return nil end

	return math.Round(math.Clamp(value, min, max))
end

local function color(value)
	if not istable(value) then return nil end

	local r, g, b = int(value.r, 0, 255), int(value.g, 0, 255), int(value.b, 0, 255)
	if not r or not g or not b then return nil end

	return {r = r, g = g, b = b, a = int(value.a, 0, 255) or 255}
end

-- тема из JSON клиента: только известные поля с проверенными значениями
local function sanitizeTheme(data)
	if not isstring(data) then return nil end

	data = string.Trim(data)
	if data == "" then return "" end
	if #data > THEME_MAX then return nil end

	local tbl = util.JSONToTable(data)
	if not istable(tbl) then return nil end

	local out = {
		pad = int(tbl.pad, 0, 64),
		corner = int(tbl.corner, 0, 32),
		input = color(tbl.input),
		input_bg = color(tbl.input_bg),
		highlight = color(tbl.highlight),
		background = color(tbl.background),
	}

	if table.IsEmpty(out) then return nil end

	return util.TableToJSON(out, false)
end

local function sendTheme(target)
	net.Start("schat.set_theme")
		net.WriteString(SChat.serverTheme)

	if target then
		net.Send(target)
	else
		net.Broadcast()
	end
end

local function loadTheme()
	if not file.Exists(THEME_FILE, "DATA") then return end

	SChat.serverTheme = sanitizeTheme(file.Read(THEME_FILE, "DATA") or "") or ""
end

local function saveTheme()
	if SChat.serverTheme == "" then
		if file.Exists(THEME_FILE, "DATA") then file.Delete(THEME_FILE) end
		return
	end

	if not file.Exists(THEME_DIR, "DATA") then file.CreateDir(THEME_DIR) end

	file.Write(THEME_FILE, SChat.serverTheme)
end

net.Receive("schat.set_theme", function(_, ply)
	if not IsValid(ply) or not SChat:CanSetServerTheme(ply) then return end

	local CT = CurTime()
	if (ply.SChatNextTheme or 0) > CT then return end
	ply.SChatNextTheme = CT + THEME_DELAY

	local theme = sanitizeTheme(net.ReadString())
	if not theme or theme == SChat.serverTheme then return end

	SChat.serverTheme = theme
	saveTheme()
	sendTheme()

	if DarkRP and DarkRP.log then
		DarkRP.log("admin", ply, nil, theme == "" and "убрал тему чата сервера" or "поставил тему чата сервера")
	end
end)

hook.Add("DarkRP.PlayerLoaded", "SChat.Theme", function(ply)
	if SChat.serverTheme ~= "" then sendTheme(ply) end
end)

loadTheme()
