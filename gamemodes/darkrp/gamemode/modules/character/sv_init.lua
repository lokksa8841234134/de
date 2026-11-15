--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Персонажи (MCR): серверная часть меню персонажей, магазина одежды и косметики

	darkrp_character  - 3 слота на аккаунт (uid = SteamID64)
	darkrp_playerdata - mcr_extra (сохранённые персонажи), mcr_outfits (купленная одежда)

	ply.characters[id] = {fname, sname, gender, model, face, eye, suit = {}, data = {}}
	suit - индексы MCR.shop: top, pants, boots, coat, wboots, suit, shirt, spants, insuit
	data - age, tatoo, skillpoint, skilltime (секунды до следующего слота навыков), medals

	Пока персонаж не выбран (переменная character = nil), игрок невидим, заморожен
	и не может ничего брать или создавать - он находится в меню персонажей.
---------------------------------------------------------------------------]]
util.AddNetworkString("MCR.Fetch")
util.AddNetworkString("MCR.Select")
util.AddNetworkString("MCR.Create")
util.AddNetworkString("MCR.Outfit")
util.AddNetworkString("MCR.Camera")
util.AddNetworkString("MCR.AddPVS")
util.AddNetworkString("MCR.OnSelect")
util.AddNetworkString("MCR.Tattoo")

DB = DB or {}

local MAX_PACKET = 4096			-- сжатые данные персонажа от клиента
local MAX_JSON = 8192			-- данные персонажа после распаковки
local MAX_ALTS_JSON = 8192		-- список аккаунтов с этого ПК (MCR.Fetch)
local MAX_ALTS = 50
local MAX_EXTRA = 10			-- сохранённых персонажей на один слот
local MIN_KARMA = 40			-- слоты 2 и 3 (как в меню)
local CHANGE_COOLDOWN = 60		-- смена персонажа через F4
local COMBAT_TIME = 60			-- после ранения сменить персонажа нельзя
local SHOP_NPC = "shop4"		-- продавец одежды (mc_simple_npcs, Urban Outfits)
local SHOP_RANGE = 300 * 300
local GAME_YEAR = 2000			-- Нью-Йорк начала 2000-х, клиент считает возраст как 2000 - год рождения
local SKILL_TIME = 1800			-- каждые 30 минут игры персонажем открывается слот навыков
local SKILL_AUTO_MAX = 6		-- сами открываются 6 слотов (столько рисует тату-салон), больше - командой sAdmin
local SKILL_TICK = 60
local TATTOO_RANGE = 30			-- как в меню тату-салона

local MODELS = {male = 9, female = 6}
local EYES = 5
local INSUIT_MAX = {male = 6, female = 2}

local MONTHS = {"января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"}

local SUIT_PARTS = {"top", "pants", "boots", "coat", "wboots", "suit", "shirt", "spants"}
local OWN_KEYS = {"top", "pants", "boots", "coat", "wboots", "suit"}

-- тип из MCR.Outfit: shop - таблица MCR.shop, own - ключ покупки (детали костюма - общий suit)
-- nobuy - только надеть купленное, insuit - вариация костюма
local OUTFITS = {
	top = {shop = "top", own = "top"},
	pants = {shop = "pants", own = "pants"},
	boots = {shop = "boots", own = "boots"},
	coat = {shop = "coat", own = "coat", female = true},
	wboots = {shop = "wboots", own = "wboots", female = true},
	suit = {shop = "suit", own = "suit", nobuy = true, insuit = true},
	shirt = {shop = "shirt", own = "suit", nobuy = true, insuit = true},
	spants = {shop = "spants", own = "suit", nobuy = true, insuit = true},
	allsuit = {shop = "suit", own = "suit", insuit = true},
}

-- переменные персонажа, которые снимаются при возврате в меню
local CHAR_VARS = {"dsname", "gender", "model", "age", "tatoo", "medals", "skillpoint", "head", "face", "vest", "mouth", "armorVest", "scba", "hidename"}
local COSMETIC_VARS = {"head", "face", "vest", "mouth"}

local function dbError(err, query)
	MsgC(Color(255, 90, 0), "[MCR] SQL: " .. tostring(err) .. "\n    " .. tostring(query) .. "\n")
end

local function niceTime(sec)
	sec = math.max(math.floor(tonumber(sec) or 0), 0)

	local d = math.floor(sec / 86400)
	local h = math.floor(sec % 86400 / 3600)
	local m = math.floor(sec % 3600 / 60)

	if d > 0 then return d .. " дн. " .. h .. " ч." end
	if h > 0 then return h .. " ч. " .. m .. " мин." end

	return math.max(m, 1) .. " мин."
end

local function toInt(value, min, max)
	value = tonumber(value)
	if not value or value ~= value then return nil end

	value = math.floor(value)
	if value < min or value > max then return nil end

	return value
end

local function isSelected(ply)
	return ply:getDarkRPVar("character") ~= nil
end

-- наигранное время, как sAdmin.mcTime на клиенте; без данных sAdmin - 0
local function playTime(ply)
	if sAdmin and sAdmin.mcTime then return sAdmin.mcTime(ply) end

	local t1 = ply:getDarkRPVar("playtime")
	if not t1 then return 0 end

	return math.max(0, math.Round(t1 + (CurTime() - (ply:getDarkRPVar("synctime") or CurTime()))))
end

local function hasPack(ply, pack)
	return MQS and MQS.GetSData and MQS.GetSData(ply, pack) and true or false
end

-- суперадмин - без токена, остальным списывается токен MQS (mcr_change / mcr_save)
local function useToken(ply, token)
	if ply:IsSuperAdmin() then return true end

	local count = MQS and MQS.GetDataStored and tonumber(MQS.GetDataStored(ply, token)) or 0

	if count < 1 or not MQS.SetNWStoredData then
		return false
	end

	MQS.SetNWStoredData(ply, token, count - 1)

	return true
end

--[[---------------------------------------------------------------------------
	Проверка и приведение данных персонажа
---------------------------------------------------------------------------]]
local function readSuit(gender, suit)
	local res = {}
	if not istable(suit) then return res end

	for _, part in ipairs(SUIT_PARTS) do
		local sid = tonumber(suit[part])
		if sid and MCR.shop[part][sid] then res[part] = sid end
	end

	-- в старых данных insuit мог быть true (см. MCR.ApplySkinData)
	res.insuit = suit.insuit == true and 1 or toInt(suit.insuit, 1, INSUIT_MAX[gender])

	return res
end

local function readChar(char)
	if not istable(char) or not MODELS[char.gender] then return nil end

	local gender = char.gender
	local model = toInt(char.model, 1, MODELS[gender])
	if not model then return nil end

	if not isstring(char.fname) or not isstring(char.sname) or char.fname == "" or char.sname == "" then return nil end

	return {
		fname = char.fname,
		sname = char.sname,
		gender = gender,
		model = model,
		face = toInt(char.face, 1, MCR.GetFaceMax(gender .. "_0" .. model)) or 1,
		eye = toInt(char.eye, 1, EYES) or 1,
		suit = readSuit(gender, char.suit),
		data = istable(char.data) and char.data or {},
	}
end

local function readExtra(tbl)
	local res = {}
	if not istable(tbl) then return res end

	for id, list in pairs(tbl) do
		id = toInt(id, 1, 3)
		if not id or not istable(list) then continue end

		for _, char in ipairs(list) do
			char = readChar(char)
			if not char then continue end

			res[id] = res[id] or {}
			if #res[id] >= MAX_EXTRA then break end

			res[id][#res[id] + 1] = char
		end
	end

	return res
end

-- в базе: {тип = {индексы}}, в памяти и у клиента (MCR.OuttitData): {тип = {[индекс] = true}}
local function readOutfits(tbl)
	local res = {}
	if not istable(tbl) then return res end

	for _, key in ipairs(OWN_KEYS) do
		if not istable(tbl[key]) then continue end

		for _, sid in pairs(tbl[key]) do
			sid = tonumber(sid)
			if not sid or not MCR.shop[key][sid] then continue end

			res[key] = res[key] or {}
			res[key][sid] = true
		end
	end

	return res
end

-- возраст по лицу: MCR.AgeCounter[модель][лицо] - десяток лет; день и месяц случайные
local function generateAge(char)
	local faces = MCR.AgeCounter[char.gender .. "_0" .. char.model]
	local decade = faces and tonumber(faces[char.face]) or 2
	local age = decade * 10 + math.random(0, 9)

	return math.random(28) .. " " .. MONTHS[math.random(12)] .. " " .. (GAME_YEAR - age)
end

--[[---------------------------------------------------------------------------
	База данных
---------------------------------------------------------------------------]]
hook.Add("DatabaseInitialized", "MCR.Characters", function()
	MySQLite.query([[CREATE TABLE IF NOT EXISTS darkrp_character(
		uid BIGINT NOT NULL,
		id INTEGER NOT NULL,
		fname VARCHAR(32) NOT NULL,
		sname VARCHAR(32) NOT NULL,
		gender VARCHAR(8) NOT NULL,
		model INTEGER NOT NULL,
		face INTEGER NOT NULL,
		eye INTEGER NOT NULL,
		suit TEXT,
		data TEXT,
		PRIMARY KEY(uid, id)
	)]], nil, dbError)
end)

-- вызывается и из sAdmin (randomname, changename): suit - JSON или таблица
function DB.CreateCharData(ply, id, fname, sname, gender, model, face, eye, suit)
	local uid = DarkRP.GetPlayerUID(ply)
	id = toInt(id, 1, 3)
	if not uid or not id or not DarkRP.DBReady then return end

	local char = ply.characters and ply.characters[id]
	local data = char and istable(char.data) and char.data or {}

	if istable(suit) then suit = util.TableToJSON(suit) end

	MySQLite.query(string.format("REPLACE INTO darkrp_character(uid, id, fname, sname, gender, model, face, eye, suit, data) VALUES(%s, %d, %s, %s, %s, %d, %d, %d, %s, %s)",
		uid, id,
		MySQLite.SQLStr(tostring(fname)), MySQLite.SQLStr(tostring(sname)), MySQLite.SQLStr(tostring(gender)),
		math.floor(tonumber(model) or 1), math.floor(tonumber(face) or 1), math.floor(tonumber(eye) or 1),
		MySQLite.SQLStr(isstring(suit) and suit or "{}"), MySQLite.SQLStr(util.TableToJSON(data))
	), nil, dbError)
end

-- сохраняет ply.characters[id].data
function DB.CreateExtraDataSave(ply, id)
	local uid = DarkRP.GetPlayerUID(ply)
	id = toInt(id, 1, 3)

	local char = id and ply.characters and ply.characters[id]
	if not uid or not char or not DarkRP.DBReady then return end

	MySQLite.query(string.format("UPDATE darkrp_character SET data = %s WHERE uid = %s AND id = %d",
		MySQLite.SQLStr(util.TableToJSON(istable(char.data) and char.data or {})), uid, id
	), nil, dbError)
end

local function saveChar(ply, id)
	local char = ply.characters[id]
	DB.CreateCharData(ply, id, char.fname, char.sname, char.gender, char.model, char.face, char.eye, char.suit)
end

-- ключи слотов строками: JSON не превратит разреженную таблицу в массив
local function saveExtra(ply)
	local tbl = {}

	for id, list in pairs(ply.MCRExtra) do
		if #list > 0 then tbl[tostring(id)] = list end
	end

	DarkRP.SavePlayerData(ply, "mcr_extra", next(tbl) and tbl or nil)
end

local function saveOutfits(ply)
	local tbl = {}

	for key, list in pairs(ply.MCROutfits) do
		local ids = table.GetKeys(list)
		table.sort(ids)
		tbl[key] = ids
	end

	DarkRP.SavePlayerData(ply, "mcr_outfits", tbl)
end

--[[---------------------------------------------------------------------------
	Отправка данных клиенту (MCR.Fetch)
---------------------------------------------------------------------------]]
local function publicChar(char)
	return {
		fname = char.fname,
		sname = char.sname,
		gender = char.gender,
		model = char.model,
		face = char.face,
		eye = char.eye,
		suit = table.Copy(char.suit),
	}
end

function MCR.FetchData(ply)
	if not IsValid(ply) or not ply.characters or not ply.MCRFetched then return end

	local chars = {}

	for id = 1, 3 do
		if ply.characters[id] then chars[id] = publicChar(ply.characters[id]) end
	end

	local extra

	for id, list in pairs(ply.MCRExtra or {}) do
		if #list == 0 then continue end

		local out = {}

		for c_id, char in ipairs(list) do
			out[c_id] = publicChar(char)
		end

		extra = extra or {}
		extra[tostring(id)] = out
	end

	net.Start("MCR.Fetch")
		net.WriteTable(chars)
		net.WriteTable(ply.MCROutfits or {})

		if extra then
			local compressed = util.Compress(util.TableToJSON(extra))
			net.WriteBool(true)
			net.WriteInt(#compressed, 32)
			net.WriteData(compressed, #compressed)
		else
			net.WriteBool(false)
		end
	net.Send(ply)
end

local function sendIfReady(ply)
	if ply.MCRLoaded and ply.MCRFetched then MCR.FetchData(ply) end
end

--[[---------------------------------------------------------------------------
	Загрузка персонажей (после основных данных DarkRP)
---------------------------------------------------------------------------]]
local function finishLoad(ply, chars, vars)
	ply.characters = chars
	ply.MCRExtra = readExtra(vars.mcr_extra)
	ply.MCROutfits = readOutfits(vars.mcr_outfits)
	ply.MCRLoading = nil
	ply.MCRLoaded = true

	sendIfReady(ply)
end

local function loadCharacters(ply)
	if not IsValid(ply) or ply:IsBot() or ply.MCRLoaded or ply.MCRLoading then return end

	local uid = DarkRP.GetPlayerUID(ply)

	-- без SteamID64 сохранять некуда: персонажи живут до выхода
	if not uid then
		finishLoad(ply, {}, {})
		return
	end

	if not DarkRP.DBReady then return end

	ply.MCRLoading = true

	local function fail(err, query)
		dbError(err, query)
		if not IsValid(ply) then return end

		ply.MCRLoading = nil

		timer.Simple(15, function()
			loadCharacters(ply)
		end)
	end

	MySQLite.query("SELECT id, fname, sname, gender, model, face, eye, suit, data FROM darkrp_character WHERE uid = " .. uid, function(rows)
		if not IsValid(ply) then return end

		local chars = {}

		for _, row in ipairs(rows or {}) do
			local id = toInt(row.id, 1, 3)

			local char = id and readChar({
				fname = row.fname,
				sname = row.sname,
				gender = row.gender,
				model = row.model,
				face = row.face,
				eye = row.eye,
				suit = isstring(row.suit) and util.JSONToTable(row.suit) or nil,
				data = isstring(row.data) and util.JSONToTable(row.data) or nil,
			})

			if char then chars[id] = char end
		end

		MySQLite.query("SELECT var, value FROM darkrp_playerdata WHERE uid = " .. uid .. " AND var IN ('mcr_extra', 'mcr_outfits')", function(rows2)
			if not IsValid(ply) then return end

			local vars = {}

			for _, row in ipairs(rows2 or {}) do
				if isstring(row.var) and isstring(row.value) then vars[row.var] = util.JSONToTable(row.value) end
			end

			finishLoad(ply, chars, vars)
		end, fail)
	end, fail)
end

hook.Add("DarkRPPlayerDataLoaded", "MCR.Characters", loadCharacters)

--[[---------------------------------------------------------------------------
	Игрок без выбранного персонажа: невидим, заморожен, без оружия
---------------------------------------------------------------------------]]
local function hidePlayer(ply)
	ply.MCRHidden = true
	ply:StripWeapons()
	ply:SetNoDraw(true)
	ply:SetNotSolid(true)
	ply:DrawShadow(false)
	ply:GodEnable()
	ply:Lock()
end

local function showPlayer(ply)
	if not ply.MCRHidden then return end

	ply.MCRHidden = nil
	ply:UnLock()
	ply:GodDisable()
	ply:SetNoDraw(false)
	ply:SetNotSolid(false)
	ply:DrawShadow(true)
end

hook.Add("PlayerSpawn", "MCR.Hide", function(ply)
	if ply:IsBot() or isSelected(ply) then return end

	hidePlayer(ply)
end)

hook.Add("PlayerLoadout", "MCR.Hide", function(ply)
	if ply.MCRHidden then return true end
end)

local function blockHidden(ply)
	if ply.MCRHidden then return false end
end

hook.Add("PlayerSpawnObject", "MCR.Hide", blockHidden)
hook.Add("PlayerCanPickupWeapon", "MCR.Hide", blockHidden)
hook.Add("PlayerCanPickupItem", "MCR.Hide", blockHidden)
hook.Add("PlayerUse", "MCR.Hide", blockHidden)
hook.Add("CanPlayerEnterVehicle", "MCR.Hide", blockHidden)

-- у игрока в меню нет возраста (age): на клиенте озвучка чата падает с ошибкой
hook.Add("PlayerSay", "MCR.Hide", function(ply)
	if ply.MCRHidden then return "" end
end)

hook.Add("PlayerCanHearPlayersVoice", "MCR.Hide", function(listener, talker)
	if talker.MCRHidden then return false end
end)

--[[---------------------------------------------------------------------------
	Камеры меню: мир вокруг камеры должен передаваться клиенту (PVS)
---------------------------------------------------------------------------]]
local function pvsPoints(v)
	local cfg = MCR.Config

	if v == 1 then return {cfg.MainCam.pos, cfg.CharP[1][1]} end
	if v == 2 or v == 3 then return {cfg.CharC[v][1], cfg.CharP[v][1]} end
	if v == 4 then return {cfg.CharCam.pos, cfg.CharP["main"][1]} end

	return nil
end

hook.Add("SetupPlayerVisibility", "MCR.PVS", function(ply)
	if not ply.MCRPVS then return end

	for _, pos in ipairs(ply.MCRPVS) do
		AddOriginToPVS(pos)
	end
end)

-- 0 - заставка закрыта, 1..#MCR.Config.Cams - текущая камера заставки
net.Receive("MCR.Camera", function(_, ply)
	if not IsValid(ply) then return end

	-- клиент пишет номер камеры в знаковые 3 бита: 4 и 5 приходят отрицательными
	local state = net.ReadInt(3)
	if state < 0 then state = state + 8 end

	local cam = MCR.Config.Cams[state]

	if state == 0 or not cam or isSelected(ply) then
		ply.MCRPVS = nil
		return
	end

	ply.MCRPVS = {cam.st.pos, cam.ed and cam.ed.pos or cam.st.pos}
end)

-- 0 - очистить, 1..3 - персонаж слота, 4 - создание персонажа
net.Receive("MCR.AddPVS", function(_, ply)
	if not IsValid(ply) then return end

	local v = net.ReadUInt(4)

	ply.MCRPVS = not isSelected(ply) and pvsPoints(v) or nil
end)

--[[---------------------------------------------------------------------------
	Запрос данных: клиент присылает аккаунты, с которых заходили с этого ПК
---------------------------------------------------------------------------]]
local function checkAlts(ply, json)
	if #json > MAX_ALTS_JSON then return end

	local tbl = util.JSONToTable(json)
	if not istable(tbl) then return end

	local own = ply:SteamID()
	local alts = {}

	for sid in pairs(tbl) do
		if #alts >= MAX_ALTS then break end

		if isstring(sid) and sid ~= own and string.match(sid, "^STEAM_%d:%d:%d+$") then
			alts[#alts + 1] = sid
		end
	end

	if #alts == 0 then return end

	ply.MCRAlts = alts

	local list = table.concat(alts, ", ")
	DarkRP.log("other", ply, nil, "заходил с этого ПК под другими аккаунтами", nil, list)

	if sAdmin and sAdmin.msg and sAdmin.logPerm then
		sAdmin.msg(sAdmin.logPerm(), "%s заходил с этого ПК под другими аккаунтами: %s", ply, list)
	end

	-- sAdmin проверяет баны найденных аккаунтов (sv_bans.lua)
	hook.Run("MCR.AltsDetected", ply, alts)
end

net.Receive("MCR.Fetch", function(_, ply)
	if not IsValid(ply) or ply.MCRFetched then return end

	ply.MCRFetched = true
	checkAlts(ply, net.ReadString())

	if ply.MCRLoaded then
		MCR.FetchData(ply)
	else
		loadCharacters(ply)
	end
end)

--[[---------------------------------------------------------------------------
	Выбор персонажа
---------------------------------------------------------------------------]]
local function canSelect(ply, id)
	local char = ply.characters[id]
	if not char then return "Персонаж не найден." end
	if ply:getDarkRPVar("BANNED") then return "Ваш аккаунт заблокирован." end
	if id == 1 then return nil end

	if (ply:getDarkRPVar("karma") or 100) < MIN_KARMA then return "Персонаж заблокирован - низкий рассудок." end

	local banned, left = ply:isTeamBanned(MCR.DefTeams[id])

	if banned then
		return left > 0 and ("Персонаж заблокирован ещё " .. niceTime(left) .. ".") or "Персонаж заблокирован навсегда."
	end

	return nil
end

local function applyCharacter(ply, id, char)
	local data = char.data

	if not isstring(data.age) then
		data.age = generateAge(char)
		DB.CreateExtraDataSave(ply, id)
	end

	for _, var in ipairs(COSMETIC_VARS) do
		ply:SetDarkRPVar(var, nil)
	end

	ply:SetDarkRPVar("rpname", char.fname .. " " .. char.sname)
	ply:SetDarkRPVar("dsname", char.fname)
	ply:SetDarkRPVar("gender", char.gender)
	ply:SetDarkRPVar("model", char.model)
	ply:SetDarkRPVar("age", data.age)
	ply:SetDarkRPVar("tatoo", isstring(data.tatoo) and data.tatoo ~= "" and data.tatoo or nil)
	ply:SetDarkRPVar("medals", isstring(data.medals) and data.medals ~= "" and data.medals or nil)
	ply:SetDarkRPVar("skillpoint", toInt(data.skillpoint, 1, 31))
	ply:SetDarkRPVar("character", id)
end

local function selectCharacter(ply, id)
	if isSelected(ply) then return end

	local reason = canSelect(ply, id)

	if reason then
		-- клиент уже закрыл меню и затемнил экран
		if not ply:getDarkRPVar("BANNED") then
			DarkRP.UIEffect(ply, "OpenCharacterCreator")
		end

		return
	end

	local char = ply.characters[id]

	ply.MCRPVS = nil
	applyCharacter(ply, id, char)
	showPlayer(ply)

	ply:ChangeTeam(MCR.DefTeams[id], true)
	ply:Spawn()

	-- карманы персонажа (инвентарь) и другие модули, которым нужен выбранный персонаж
	hook.Run("MCR.CharacterSelected", ply, id)

	net.Start("MCR.OnSelect")
		net.WriteUInt(id, 3)
	net.Send(ply)

	DarkRP.UIEffect(ply, "blackScreen", {false, true})
	DarkRP.log("other", ply, nil, "выбрал персонажа", nil, "#" .. id .. " " .. char.fname .. " " .. char.sname)
end

-- сохранённый персонаж меняется местами с персонажем слота (или занимает пустой слот)
local function loadExtra(ply, id, c_id)
	local list = ply.MCRExtra[id]
	local char = list[c_id]
	local current = ply.characters[id]

	if not current and id > 1 and playTime(ply) < (MCR.Config.TimeNeed[id] or 0) then
		return
	end

	if current then
		list[c_id] = current
	else
		table.remove(list, c_id)
		if #list == 0 then ply.MCRExtra[id] = nil end
	end

	ply.characters[id] = char
	saveChar(ply, id)
	saveExtra(ply)

	DarkRP.log("other", ply, nil, "загрузил сохранённого персонажа", nil, "#" .. id .. " " .. char.fname .. " " .. char.sname)
end

local function removeExtra(ply, id, c_id)
	local list = ply.MCRExtra[id]
	local char = table.remove(list, c_id)

	if #list == 0 then ply.MCRExtra[id] = nil end

	saveExtra(ply)
	DarkRP.log("other", ply, nil, "удалил сохранённого персонажа", nil, "#" .. id .. " " .. char.fname .. " " .. char.sname)
end

net.Receive("MCR.Select", function(_, ply)
	if not IsValid(ply) or not ply.characters then return end

	local mode = net.ReadUInt(3)

	if mode ~= 0 then
		if DarkRP.NetDelay(ply, 0.5) then return end

		selectCharacter(ply, mode)
		return
	end

	local id = net.ReadUInt(3)
	local c_id = net.ReadUInt(16)
	local load = net.ReadBool()

	if DarkRP.NetDelay(ply, 1) or isSelected(ply) then return end

	local list = ply.MCRExtra[id]
	if not list or not list[c_id] then return end

	if load then
		loadExtra(ply, id, c_id)
	else
		removeExtra(ply, id, c_id)
	end

	MCR.FetchData(ply)
end)

--[[---------------------------------------------------------------------------
	Создание, пересоздание и сохранение персонажа
---------------------------------------------------------------------------]]
local function buildCharacter(ply, id, tbl)
	local gender = tbl.gender
	if not MODELS[gender] then return nil end

	local model = toInt(tbl.model, 1, MODELS[gender])
	if not model then return nil end

	local face = toInt(tbl.face, 1, MCR.GetFaceMax(gender .. "_0" .. model))
	local eye = toInt(tbl.eye, 1, EYES)
	if not face or not eye then return nil end

	-- стартовая одежда - только из случайного набора меню
	local suit = istable(tbl.suit) and tbl.suit or {}
	local top, pants = tonumber(suit.top), tonumber(suit.pants)
	if not table.HasValue(MCR.randomtop[gender], top) or not table.HasValue(MCR.randompants[gender], pants) then return nil end

	local fname, sname = tbl.fname, tbl.sname

	if not isstring(fname) or not isstring(sname) or not MCR.CheckName(fname) or not MCR.CheckName(sname) then
		return nil, "Используйте только латинские буквы, не менее 3 и не более 16."
	end

	fname, sname = MCR.NiceName(fname), MCR.NiceName(sname, true)

	if string.lower(fname) == string.lower(sname) then
		return nil, "Имя не может повторять фамилию."
	end

	for slot, other in pairs(ply.characters) do
		if slot ~= id and string.lower(other.fname) == string.lower(fname) and string.lower(other.sname) == string.lower(sname) then
			return nil, "Такой персонаж уже есть на другом слоте."
		end
	end

	return {
		fname = fname,
		sname = sname,
		gender = gender,
		model = model,
		face = face,
		eye = eye,
		suit = {top = top, pants = pants},
		data = {},
	}
end

local function createCharacter(ply, id, compressed)
	local json = util.Decompress(compressed, MAX_JSON)
	if not json or json == "" or #json > MAX_JSON then return end

	local tbl = util.JSONToTable(json)
	if not istable(tbl) then return end

	local char, err = buildCharacter(ply, id, tbl)

	if not char then
		return
	end

	local old = ply.characters[id]

	if old then
		if not useToken(ply, "mcr_change") then return end
	elseif id > 1 and playTime(ply) < (MCR.Config.TimeNeed[id] or 0) then
		return
	end

	char.data.age = generateAge(char)
	ply.characters[id] = char
	saveChar(ply, id)
	MCR.FetchData(ply)

	local name = "#" .. id .. " " .. char.fname .. " " .. char.sname

	if old then
		DarkRP.log("other", ply, nil, "пересоздал персонажа", nil, name .. " (был " .. old.fname .. " " .. old.sname .. ")")
	else
		DarkRP.log("other", ply, nil, "создал персонажа", nil, name)
	end
end

-- копия персонажа слота в сохранённые; данные от клиента не используются
local function saveToExtra(ply, id)
	local char = ply.characters[id]
	if not char then return end

	local list = ply.MCRExtra[id] or {}

	if #list >= MAX_EXTRA then
		return
	end

	if not useToken(ply, "mcr_save") then return end

	list[#list + 1] = table.Copy(char)
	ply.MCRExtra[id] = list
	saveExtra(ply)
	MCR.FetchData(ply)

	DarkRP.log("other", ply, nil, "сохранил персонажа", nil, "#" .. id .. " " .. char.fname .. " " .. char.sname)
end

net.Receive("MCR.Create", function(_, ply)
	if not IsValid(ply) or not ply.characters then return end

	local id = net.ReadUInt(3)
	local bytes = net.ReadUInt(32)
	if bytes < 1 or bytes > MAX_PACKET then return end

	local compressed = net.ReadData(bytes)
	local save = net.ReadBool()

	if DarkRP.NetDelay(ply, 2) then return end
	if isSelected(ply) or not MCR.DefTeams[id] then return end

	if save then
		saveToExtra(ply, id)
	else
		createCharacter(ply, id, compressed)
	end
end)

--[[---------------------------------------------------------------------------
	Возврат к выбору персонажа (F4 - "Сменить персонажа")
---------------------------------------------------------------------------]]
local function resetCharacter(ply)
	-- прогресс слота навыков (skilltime) сохраняется до сброса
	DB.CreateExtraDataSave(ply, ply:getDarkRPVar("character"))

	-- вещи на карте, помещение и ключи остаются на аккаунте, карманы с оружием из рук ждут этого
	-- персонажа (инвентарь, ваш ответ к 11.3); остальное снимает StripWeapons ниже
	hook.Run("MCR.CharacterReset", ply, ply:getDarkRPVar("character"))

	ply:SetDarkRPVar("character", nil)
	ply:SetDarkRPVar("rpname", ply:SteamName())

	for _, var in ipairs(CHAR_VARS) do
		ply:SetDarkRPVar(var, nil)
	end

	ply:SetSelfDarkRPVar("salary", nil)
	ply:SetArmor(0)
	ply:StripWeapons()
	ply:SetTeam(0)
	ply:SetDarkRPVar("job", team.GetName(0))

	-- PlayerSpawn: персонаж не выбран - игрок скрывается
	ply:Spawn()
end

concommand.Add("mcr_change", function(ply)
	if not IsValid(ply) or not ply.characters then return end
	if DarkRP.NetDelay(ply, 2) then return end

	-- меню закрылось без выбора персонажа - открыть заново
	if not isSelected(ply) then
		if not ply:getDarkRPVar("BANNED") then DarkRP.UIEffect(ply, "OpenCharacterCreator") end
		return
	end

	local CT = CurTime()

	if ply.MCRNextChange and ply.MCRNextChange > CT then
		return
	end

	if not ply:IsFreeman() or ply:InVehicle() then
		return
	end

	if ply:getDarkRPVar("wanted") then
		return
	end

	if ply.LastDamage and ply.LastDamage + COMBAT_TIME > CT then
		return
	end

	ply.MCRNextChange = CT + CHANGE_COOLDOWN
	DarkRP.log("other", ply, nil, "вернулся к выбору персонажа")

	resetCharacter(ply)
	MCR.FetchData(ply)
	DarkRP.UIEffect(ply, "OpenCharacterCreator")
end)

--[[---------------------------------------------------------------------------
	Магазин одежды (MCR.OpenShop у продавца shop4)
---------------------------------------------------------------------------]]
local function nearShop(ply)
	local pos = ply:GetPos()
	local onMap = false

	for _, ent in ipairs(ents.FindByClass("mcs_npc")) do
		if not ent.GetUID or ent:GetUID() ~= SHOP_NPC then continue end

		onMap = true
		if ent:GetPos():DistToSqr(pos) <= SHOP_RANGE then return true end
	end

	-- продавца нет на карте - расстояние не проверяется
	return not onMap
end

local function outfitError(ply, char, typ, item, insuit)
	local cfg = OUTFITS[typ]

	if not ply:IsUnrestrained() then return "Сейчас это невозможно." end
	if ply:getDarkRPVar("scba") then return "Сначала снимите снаряжение." end
	if not nearShop(ply) then return "Подойдите к продавцу одежды." end

	if (item.only and item.only ~= char.gender) or (cfg.female and char.gender ~= "female") then
		return "Эта одежда не подходит вашему персонажу."
	end

	if item.pack and not hasPack(ply, item.pack) then return "Эта одежда доступна только с набором." end
	if item.noshow and not item.pack then return "Эта одежда недоступна." end

	if cfg.insuit then
		if insuit > INSUIT_MAX[char.gender] then return "Такой вариации костюма нет." end
		if insuit > 4 and not hasPack(ply, "d_packhotline") then return "Эта вариация костюма доступна только с набором." end
	end

	return nil
end

local function equipOutfit(char, typ, sid, insuit)
	local suit = char.suit
	local cfg = OUTFITS[typ]

	if typ == "allsuit" then
		suit.suit, suit.shirt, suit.spants = sid, sid, sid
	else
		suit[typ] = sid
	end

	-- костюм - модель suit с вариацией, остальное - обычная модель
	suit.insuit = cfg.insuit and insuit or nil

	-- женские модели: костюм, обычные штаны или обувь снимают зауженные штаны (coat) и высокие сапоги (wboots)
	if char.gender == "female" and (cfg.insuit or typ == "pants" or typ == "boots") then
		suit.coat, suit.wboots = nil, nil
	end
end

net.Receive("MCR.Outfit", function(_, ply)
	if not IsValid(ply) or not ply.characters then return end

	local typ = net.ReadString()
	local sid = net.ReadUInt(8)
	local insuit = net.ReadUInt(3)

	if DarkRP.NetDelay(ply, 0.5) then return end

	local cfg = OUTFITS[typ]
	local id = ply:getDarkRPVar("character")
	local char = id and ply.characters[id]
	if not cfg or not char then return end

	local item = MCR.shop[cfg.shop][sid]
	if not item then return end

	if insuit < 1 then insuit = 1 end

	local err = outfitError(ply, char, typ, item, insuit)

	if err then
		return
	end

	local owned = item.pack or (ply.MCROutfits[cfg.own] and ply.MCROutfits[cfg.own][sid])

	if not owned then
		if cfg.nobuy then return end

		-- донат-одежда (¤) покупается за кредиты, остальное - за $
		local price = math.max(math.floor(tonumber(item.price) or 600), 0)

		if item.don then
			if not ply.TakeCredits or not ply:TakeCredits(price) then
				return
			end
		elseif price > 0 then
			if not ply:canAfford(price) then
				return
			end

			ply:addMoney(-price)
		end

		ply.MCROutfits[cfg.own] = ply.MCROutfits[cfg.own] or {}
		ply.MCROutfits[cfg.own][sid] = true
		saveOutfits(ply)

		DarkRP.log("money", ply, nil, "купил одежду", nil, item.name .. (item.don and (" за " .. price .. " ¤") or (" за $" .. price)))
	end

	equipOutfit(char, typ, sid, insuit)
	saveChar(ply, id)
	hook.Call("PlayerSetModel", GAMEMODE, ply)
	MCR.FetchData(ply)
end)

--[[---------------------------------------------------------------------------
	Косметика (F4 - "Внешний вид")
---------------------------------------------------------------------------]]
-- проверки в sh_cosmetics.lua вызывают sAdmin.mcTime, которого на сервере может не быть
local function cosmeticAllowed(ply, item)
	if not isfunction(item.check) then return false end

	local ok, res = pcall(item.check, ply)

	if not ok then
		ErrorNoHalt("[MCR] косметика " .. tostring(item.name) .. ": " .. tostring(res) .. "\n")
		return false
	end

	return res and true or false
end

concommand.Add("mcr_puton", function(ply, _, args)
	if not IsValid(ply) or not isSelected(ply) or not ply:IsUnrestrained() then return end
	if DarkRP.NetDelay(ply, 1) then return end

	local part, key = args[1], args[2]
	local item = isstring(part) and isstring(key) and MCR.Cosmetics[part] and MCR.Cosmetics[part][key]
	if not item then return end

	if not cosmeticAllowed(ply, item) or not MCR.CanEquipCosmetics(ply, part, key) then
		return
	end

	ply:SetDarkRPVar(part, key)
end)

-- 1 - торс (бронежилет или жилет), 2 - голова, 3 - лицо
concommand.Add("remove_vest", function(ply, _, args)
	if not IsValid(ply) or not isSelected(ply) or not ply:IsUnrestrained() then return end
	if DarkRP.NetDelay(ply, 1) then return end

	local slot = tonumber(args[1])

	if slot == 1 then
		local armor = ply:getDarkRPVar("armorVest")

		if armor == 3 then
		elseif armor then
			ply:SetDarkRPVar("armorVest", nil)
			ply:SetArmor(0)
		else
			ply:SetDarkRPVar("vest", nil)
		end
	elseif slot == 2 then
		ply:SetDarkRPVar("head", nil)
	elseif slot == 3 then
		ply:SetDarkRPVar("face", nil)
	end
end)

--[[---------------------------------------------------------------------------
	Навыки, татуировки и медали текущего персонажа (команды sAdmin)
---------------------------------------------------------------------------]]
local function currentChar(ply)
	if not IsValid(ply) or not ply.characters then return nil end

	local id = ply:getDarkRPVar("character")

	return id and ply.characters[id], id
end

-- список ключей через ";" (или "|"), только существующие, без повторов
local function filterList(str, known)
	local list, seen = {}, {}

	for _, k in ipairs(string.Explode(";", string.Replace(tostring(str or ""), "|", ";"))) do
		k = string.Trim(k)

		if known[k] and not seen[k] then
			seen[k] = true
			list[#list + 1] = k
		end
	end

	return #list > 0 and table.concat(list, ";") or nil
end

function MCR.SetSkillPoints(ply, amount, max)
	local char, id = currentChar(ply)
	if not char then return false end

	max = math.Clamp(math.floor(tonumber(max) or 30), 0, 31)
	amount = math.Clamp(math.floor(tonumber(amount) or 0), 0, max)

	char.data.skillpoint = amount > 0 and amount or nil
	ply:SetDarkRPVar("skillpoint", char.data.skillpoint)
	DB.CreateExtraDataSave(ply, id)

	return true
end

-- data = {"a1;b2", очки навыков}
function MCR.RestoreTatoo(ply, data)
	local char = currentChar(ply)
	if not char or not istable(data) then return false end

	char.data.tatoo = filterList(data[1], MCR.Tatoo)
	ply:SetDarkRPVar("tatoo", char.data.tatoo)

	return MCR.SetSkillPoints(ply, data[2], 30)
end

function MCR.RemoveTatoo(ply)
	local char, id = currentChar(ply)
	if not char then return false end

	char.data.tatoo = nil
	ply:SetDarkRPVar("tatoo", nil)
	DB.CreateExtraDataSave(ply, id)

	return true
end

function MCR.SetMedals(ply, str)
	local char, id = currentChar(ply)
	if not char then return false end

	char.data.medals = filterList(str, MCR.Medals)
	ply:SetDarkRPVar("medals", char.data.medals)
	DB.CreateExtraDataSave(ply, id)

	return true
end

--[[---------------------------------------------------------------------------
	Слоты навыков: каждые 30 минут игры персонажем открывается слот (до 6),
	при смерти пропадают все открытые слоты и татуировки
---------------------------------------------------------------------------]]
local function saveCurrent(ply)
	local char, id = currentChar(ply)
	if char then DB.CreateExtraDataSave(ply, id) end
end

timer.Create("MCR.SkillPoints", SKILL_TICK, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		if not ply:Alive() then continue end

		local char, id = currentChar(ply)
		if not char then continue end

		local data = char.data
		local points = toInt(data.skillpoint, 1, 31) or 0

		if points >= SKILL_AUTO_MAX then
			data.skilltime = nil
			continue
		end

		local time = (tonumber(data.skilltime) or 0) + SKILL_TICK

		if time < SKILL_TIME then
			data.skilltime = time
			continue
		end

		data.skilltime = nil
		data.skillpoint = points + 1
		ply:SetDarkRPVar("skillpoint", data.skillpoint)
		DB.CreateExtraDataSave(ply, id)
	end
end)

hook.Add("PlayerDeath", "MCR.SkillPoints", function(ply)
	local char, id = currentChar(ply)
	if not char then return end

	local data = char.data

	data.tatoo, data.skillpoint, data.skilltime = nil, nil, nil
	ply:SetDarkRPVar("tatoo", nil)
	ply:SetDarkRPVar("skillpoint", nil)
	DB.CreateExtraDataSave(ply, id)
end)

hook.Add("PlayerDisconnected", "MCR.SkillPoints", saveCurrent)

hook.Add("ShutDown", "MCR.SkillPoints", function()
	for _, ply in ipairs(player.GetAll()) do
		saveCurrent(ply)
	end
end)

--[[---------------------------------------------------------------------------
	Тату-салон (MSD.OpenTattooMenu): клиент присылает ключ MCR.Tatoo
	MCR.Tatoo[ключ] = {название, очки навыка, цена, описание, несовместимая тату}
---------------------------------------------------------------------------]]
net.Receive("MCR.Tattoo", function(_, ply)
	if not IsValid(ply) then return end

	local key = net.ReadString()
	if DarkRP.NetDelay(ply, 1) then return end

	local char, id = currentChar(ply)
	local tattoo = MCR.Tatoo[key]
	if not char or not tattoo then return end

	-- меню салона закрывается по тем же условиям: игрок не свободен или отошёл от кресла
	if not ply:IsFreeman() or not DarkRP.InRangeVector(GAMEMODE.Config.TattooSalon, ply:GetPos(), TATTOO_RANGE) then return end

	local owned, used = {}, 0

	for _, k in ipairs(string.Explode(";", tostring(char.data.tatoo or ""))) do
		if MCR.Tatoo[k] and not owned[k] then
			owned[k] = true
			used = used + MCR.Tatoo[k][2]
		end
	end

	if owned[key] then return end

	if tattoo[5] and owned[tattoo[5]] then
		return
	end

	if (toInt(char.data.skillpoint, 1, 31) or 0) - used < tattoo[2] then
		return
	end

	local price = math.max(math.floor(tonumber(tattoo[3]) or 0), 0)

	if not ply:canAfford(price) then
		return
	end

	ply:addMoney(-price)

	char.data.tatoo = filterList(tostring(char.data.tatoo or "") .. ";" .. key, MCR.Tatoo)
	ply:SetDarkRPVar("tatoo", char.data.tatoo)
	DB.CreateExtraDataSave(ply, id)

	-- клиент обновляет меню и проигрывает звук
	net.Start("MCR.Tattoo")
	net.Send(ply)

	DarkRP.log("money", ply, nil, "набил тату", nil, tattoo[1] .. " за $" .. price)
end)
