--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Чат и чат-команды

	DarkRP.defineChatCommand(cmd, callback(ply, args), delay)
	Ввод: say / say_team (GM:PlayerSay) и консоль "darkrp /команда аргументы"
	Обычный чат слышно в радиусе голоса (GM.Config.VoiceDist[voicedist]),
	say_team - LOOC в том же радиусе.
	Без сознания (переменная unconscious, health/mc_haes/core/sv_ragdoll.lua)
	игрок молчит: ни чата, ни LOOC, ни команд DarkRP, ни голоса - ни рядом,
	ни по рации. Команды и жалобы sAdmin работают: его хук PlayerSay
	срабатывает раньше GM:PlayerSay.
---------------------------------------------------------------------------]]
util.AddNetworkString("GLA.OnPlayerChat")
util.AddNetworkString("DarkRP.ItCommand")

DarkRP.chatCommands = DarkRP.chatCommands or {}

local MAX_CHAT_LEN = 300
local MAX_IT_LEN = 64

local colLOOC1 = Color(163, 163, 163)
local colLOOC2 = Color(211, 219, 223)
local colMe = Color(245, 190, 110)
local colDo = Color(150, 200, 235)

function DarkRP.defineChatCommand(cmd, callback, delay)
	if not isstring(cmd) or not isfunction(callback) then return end

	DarkRP.chatCommands[string.lower(cmd)] = {
		callback = callback,
		delay = tonumber(delay) or 0
	}
end

--[[---------------------------------------------------------------------------
	Отправка строк чата
	Клиент: String prefix, String text, Color col1, Color col2, Entity ply, Bool notts
	Пустой text - строка выводится одним префиксом (действия, системные сообщения)
---------------------------------------------------------------------------]]
function DarkRP.SendChat(recipients, prefix, text, col1, col2, sender, notts)
	if istable(recipients) and #recipients == 0 then return end

	net.Start("GLA.OnPlayerChat")
		net.WriteString(prefix or "")
		net.WriteString(text or "")
		net.WriteColor(col1 or color_white, false)
		net.WriteColor(col2 or color_white, false)
		net.WriteEntity(IsValid(sender) and sender or NULL)
		net.WriteBool(notts and true or false)
	net.Send(recipients)
end

function DarkRP.ChatRadius(ply)
	local dist = GAMEMODE.Config.VoiceDist or {}

	return dist[ply:getDarkRPVar("voicedist") or 2] or dist[2] or 500
end

function DarkRP.PlayersInRange(ply, radius)
	local recipients = {}
	local pos = ply:GetPos()
	local sqr = radius * radius

	for _, v in ipairs(player.GetHumans()) do
		if v == ply or v:GetPos():DistToSqr(pos) <= sqr then
			recipients[#recipients + 1] = v
		end
	end

	return recipients
end

function DarkRP.talkToRange(ply, prefix, text, radius, col1, col2, notts)
	DarkRP.SendChat(DarkRP.PlayersInRange(ply, radius or DarkRP.ChatRadius(ply)), prefix, text, col1, col2, ply, notts)
end

-- действия видно хотя бы на средней дистанции голоса
local function actionRadius(ply)
	local dist = GAMEMODE.Config.VoiceDist or {}

	return math.max(DarkRP.ChatRadius(ply), dist[2] or 500)
end

local function isFiltered(text)
	local words = GAMEMODE.FilterWords
	if not words then return false end

	local lower = string.lower(text)

	for word in pairs(words) do
		if string.find(lower, string.lower(word), 1, true) then return true end
	end

	return false
end

local function prepareText(text)
	text = string.gsub(tostring(text or ""), "[\r\n\t]", " ")
	text = string.Trim(utf8.force(text))

	if (utf8.len(text) or 0) > MAX_CHAT_LEN then
		text = utf8.sub(text, 1, MAX_CHAT_LEN)
	end

	return text
end

-- без сознания игрок молчит
local function silenced(ply)
	return ply:getDarkRPVar("unconscious") and true or false
end

--[[---------------------------------------------------------------------------
	Диспетчер команд
---------------------------------------------------------------------------]]
local function runCommand(ply, cmd, args)
	if silenced(ply) then return end

	cmd = string.lower(cmd)
	local command = DarkRP.chatCommands[cmd]

	if not command then
		return
	end

	if command.delay > 0 then
		local CT = CurTime()
		ply.DarkRPCommandDelay = ply.DarkRPCommandDelay or {}
		if (ply.DarkRPCommandDelay[cmd] or 0) > CT then return end
		ply.DarkRPCommandDelay[cmd] = CT + command.delay
	end

	local ok, err = xpcall(command.callback, debug.traceback, ply, args or "")

	if not ok then
		ErrorNoHalt("[DarkRP] Ошибка команды /" .. cmd .. ": " .. tostring(err) .. "\n")
	end
end

local function handleCommand(ply, text)
	local cmd, args = string.match(text, "^/(%S+)%s*(.*)$")
	if not cmd then return end

	runCommand(ply, cmd, string.Trim(args or ""))
end

function GM:PlayerSay(ply, text, teamonly)
	if not IsValid(ply) or ply.DarkRPUnInitialized then return "" end

	text = prepareText(text)
	if text == "" then return "" end

	if silenced(ply) then return "" end

	if isFiltered(text) then
		DarkRP.log("chat", ply, nil, "заблокированное сообщение: " .. text)
		return ""
	end

	if string.sub(text, 1, 1) == "/" then
		handleCommand(ply, text)
		return ""
	end

	if DarkRP.NetDelay(ply, 0.5) then return "" end

	if teamonly then
		DarkRP.talkToRange(ply, "[LOOC] " .. ply:Nick(), text, DarkRP.ChatRadius(ply), colLOOC1, colLOOC2, true)
		return ""
	end

	if not ply:Alive() then return "" end

	DarkRP.talkToRange(ply, "", text, DarkRP.ChatRadius(ply), team.GetColor(ply:Team()), color_white, false)

	return ""
end

concommand.Add("darkrp", function(ply, _, args)
	if not IsValid(ply) or ply.DarkRPUnInitialized or not args[1] then return end

	local cmd = tostring(args[1])
	if string.sub(cmd, 1, 1) == "/" then cmd = string.sub(cmd, 2) end
	if cmd == "" or string.find(cmd, "%s") then return end

	local rest = {}
	for i = 2, #args do rest[#rest + 1] = tostring(args[i]) end

	local text = prepareText(table.concat(rest, " "))

	if isFiltered(text) then
		return
	end

	runCommand(ply, cmd, text)
end)

--[[---------------------------------------------------------------------------
	Ролевые команды
---------------------------------------------------------------------------]]
DarkRP.defineChatCommand("me", function(ply, args)
	if not ply:Alive() then return "" end
	if DarkRP.NetDelay(ply, 1) then return "" end

	if args == "" then
		return ""
	end

	DarkRP.talkToRange(ply, "* " .. ply:Nick() .. " " .. args, "", actionRadius(ply), colMe, color_white, true)

	return ""
end)

DarkRP.defineChatCommand("do", function(ply, args)
	if not ply:Alive() then return "" end
	if DarkRP.NetDelay(ply, 1) then return "" end

	if args == "" then
		return ""
	end

	DarkRP.talkToRange(ply, "** " .. args .. " (" .. ply:Nick() .. ")", "", actionRadius(ply), colDo, color_white, true)

	return ""
end)

DarkRP.defineChatCommand("roll", function(ply)
	if not ply:Alive() then return "" end
	if DarkRP.NetDelay(ply, 2) then return "" end

	DarkRP.talkToRange(ply, "* " .. ply:Nick() .. " бросает кубик: " .. math.random(1, 100) .. " (1-100)", "", actionRadius(ply), colMe, color_white, true)

	return ""
end)

--[[---------------------------------------------------------------------------
	/it - описание своего предмета, /look - описания вокруг (по клавише zoom)
---------------------------------------------------------------------------]]
local function entOwner(ent)
	if ent.CPPIGetOwner then
		local owner = ent:CPPIGetOwner()
		if IsValid(owner) then return owner end
	end

	if ent.Getowning_ent then
		local owner = ent:Getowning_ent()
		if IsValid(owner) then return owner end
	end
end

DarkRP.defineChatCommand("it", function(ply, args)
	if not ply:Alive() then return "" end
	if DarkRP.NetDelay(ply, 1) then return "" end

	local tr = util.TraceLine({
		start = ply:EyePos(),
		endpos = ply:EyePos() + ply:GetAimVector() * 150,
		filter = ply
	})

	local ent = tr.Entity

	if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsWorld() or ent:MapCreationID() ~= -1 or (ent.isDoor and ent:isDoor()) then
		return ""
	end

	local owner = entOwner(ent)

	if IsValid(owner) and owner ~= ply and not ply:IsAdmin() then
		return ""
	end

	if args == "" then
		ent.itText = nil
		return ""
	end

	if (utf8.len(args) or 0) > MAX_IT_LEN then
		args = utf8.sub(args, 1, MAX_IT_LEN)
	end

	ent.itText = args
	DarkRP.log("other", ply, nil, "описание предмета: " .. args, nil, nil, ent)

	return ""
end)

DarkRP.defineChatCommand("look", function(ply)
	if DarkRP.NetDelay(ply, 2) then return "" end

	local pos = ply:GetPos()
	local props = {}

	for _, ent in ipairs(ents.FindInSphere(pos, 1200)) do
		if ent.IsSimfphyscar and ent.McCD_UniqueId then
			props[ent:EntIndex()] = tostring(ent.McCD_UniqueId) .. "[n]"
		elseif ent.itText and ent:GetPos():DistToSqr(pos) <= 90000 then
			props[ent:EntIndex()] = ent.itText
		end
	end

	local data = {props = props}

	if ply:isCP() and MW_CASES then
		local cases = {}

		for id, case in pairs(MW_CASES) do
			if case.pos and case.pos:DistToSqr(pos) <= 1000000 then
				cases[id] = case
			end
		end

		data.cases = cases
	end

	local compressed, len = DarkRP.TableCompress(data)

	net.Start("DarkRP.ItCommand")
		net.WriteUInt(0, 2)
		net.WriteUInt(len, 32)
		net.WriteData(compressed, len)
	net.Send(ply)

	return ""
end)

--[[---------------------------------------------------------------------------
	/drop - выбросить оружие из рук
---------------------------------------------------------------------------]]
DarkRP.defineChatCommand("drop", function(ply)
	if not ply:Alive() or not ply:IsUnrestrained() or ply:InVehicle() then return "" end
	if DarkRP.NetDelay(ply, 1) then return "" end

	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) then return "" end

	local class = wep:GetClass()
	local single = DarkRP.SingleWep and DarkRP.SingleWep.DisallowDrop or {}

	if GAMEMODE.Config.DisallowDrop[class] or single[class] or wep.GivenByTeam or wep.MQS_weapon then
		return ""
	end

	wep.Droping = true
	ply:DropDRPWeapon(wep)

	return ""
end)

--[[---------------------------------------------------------------------------
	/gesture <жест> (ключи из контекстного меню msd_ui)
---------------------------------------------------------------------------]]
local gestures = {
	male = {
		point = "g_frustrated_point",
		no = "hg_headshake",
		yes = "hg_puncuate_down",
		thumbsup = "g_thumbsup",
		plead = "g_plead_01",
		what = "g_what",
		palmout = "g_palm_out_r",
		call = "g_lefthandmotion",
		left = "hg_nod_left",
		right = "hg_nod_right",
		fist = "g_fist",
		fist_swing = "g_fist_swing_across",
		noway = "g_noway_small",
		now = "g_noway_big",
		shrug = "g_shrug",
		ease = "g_lhandease",
		urgent = "g_medurgent_mid",
	},
	female = {
		point = "g_pointleft_l",
		no = "hg_headshake",
		yes = "hg_puncuate_down",
		thumbsup = "g_thumbsup",
		plead = "g_plead_01",
		what = "g_pointright_l",
		left = "hg_nod_left",
		right = "hg_nod_right",
		fist_swing = "g_fist_swing_across",
		noway = "g_noway_small",
		now = "g_noway_big",
		ease = "g_lhandease",
		urgent = "g_medurgent_mid",
	}
}

DarkRP.defineChatCommand("gesture", function(ply, args)
	if not ply:Alive() or not ply:IsUnrestrained() or ply:InVehicle() then return "" end
	if ply.DarkRPGestureCD and ply.DarkRPGestureCD > CurTime() then return "" end

	local list = gestures[ply:getDarkRPVar("gender") == "female" and "female" or "male"]
	local seq = list[string.lower(args)]

	if not seq or not Gestures or not Gestures[seq] or ply:LookupSequence(seq) < 0 then return "" end

	ply.DarkRPGestureCD = CurTime() + 1.5
	DarkRP.PlayerGesture(ply, seq)

	return ""
end)

--[[---------------------------------------------------------------------------
	Голосовой чат: слышно в радиусе голоса говорящего. По рации
	(police/sv_radio.lua, проверка автора CanRadio) и по телефону (принятый
	звонок, mc_phone/sv_init.lua) - на любом расстоянии и без объёмного
	звука. Без сознания говорящего не слышно
---------------------------------------------------------------------------]]
function GM:PlayerCanHearPlayersVoice(listener, talker)
	if not IsValid(talker) or not talker:Alive() or talker:getDarkRPVar("unconscious") then return false, false end

	local radius = DarkRP.ChatRadius(talker)

	if listener:GetPos():DistToSqr(talker:GetPos()) <= radius * radius then
		return true, true
	end

	if listener:Alive() and talker.CanRadio and talker:CanRadio(listener) then
		return true, false
	end

	if listener:Alive() and McPhone and McPhone.InCall and McPhone.InCall(talker, listener) then
		return true, false
	end

	return false, false
end

-- voicedist [1-3]: шёпот / разговор / крик (без аргумента - по кругу)

concommand.Add("voicedist", function(ply, _, args)
	if not IsValid(ply) or ply.DarkRPUnInitialized then return end
	if ply.DarkRPVoiceCD and ply.DarkRPVoiceCD > CurTime() then return end
	ply.DarkRPVoiceCD = CurTime() + 1

	local dist = tonumber(args[1])
	dist = dist and math.Clamp(math.floor(dist), 1, 3) or ((ply:getDarkRPVar("voicedist") or 2) % 3 + 1)

	ply:SetDarkRPVar("voicedist", dist)
end)

--[[---------------------------------------------------------------------------
	hide_weapon: спрятать пистолет / достать спрятанное оружие
---------------------------------------------------------------------------]]
concommand.Add("hide_weapon", function(ply)
	if not IsValid(ply) or not ply:Alive() then return end
	if ply.DarkRPHideCD and ply.DarkRPHideCD > CurTime() then return end
	ply.DarkRPHideCD = CurTime() + 1

	local hidden = false

	for _, wep in ipairs(ply:GetWeapons()) do
		if wep:GetNWBool("HiddenWep") then
			wep:SetNWBool("HiddenWep", false)
			hidden = true
		end
	end

	if hidden then
		return
	end

	if not ply:IsUnrestrained() or DarkRP.IsUniformPolice(ply) or MCR.HasTatoo(ply, "a1") then return end

	local wep = ply:GetActiveWeapon()

	if not IsValid(wep) or not DarkRP.CanConcealWeapon(wep) then
		return
	end

	wep:SetNWBool("HiddenWep", true)
	ply:SelectWeapon("keys")
end)