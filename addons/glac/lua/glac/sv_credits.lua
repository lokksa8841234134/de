--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Кредиты (¤) - баланс игрока в базе

	Кредиты никто не покупает: сайта оплаты нет, кнопка «Пожертвовать проекту»
	только пишет «Убрал Ради Плюмбусса». Кредиты выдаёт администратор:
	sAdmin addcredits / setcredits (v:AddCredits, v:SetCredits).

	Таблица glac_credits(uid = SteamID64, credits). Баланс грузится при заходе;
	пока он не загружен, AddCredits копится и добавляется при загрузке.
	Клиент получает баланс сообщением Credits (Int 32) по запросу Sync и при
	каждом изменении.
---------------------------------------------------------------------------]]
-- Material есть только у клиента: конфиги магазина зовут его без проверки
if not Material then Material = function() return "" end end

local pmeta = FindMetaTable("Player")
local MAX_CREDITS = 2147483647

local function uid(ply)
	return DarkRP and DarkRP.GetPlayerUID and DarkRP.GetPlayerUID(ply) or nil
end

function Glac.SendCredits(ply)
	if not IsValid(ply) or ply:IsBot() then return end

	Glac.NetStart("Credits")
		net.WriteInt(math.Clamp(ply.GlacCredits or 0, 0, MAX_CREDITS), 32)
	net.Send(ply)
end

local function save(ply)
	local id = uid(ply)
	if not id or not Glac.DBReady then return end

	MySQLite.query(string.format("REPLACE INTO glac_credits(uid, credits) VALUES(%s, %d)", id, ply.GlacCredits or 0), nil, function(err)
		ErrorNoHalt("[Glac] кредиты не сохранены: " .. tostring(err) .. "\n")
	end)
end

local function changed(ply)
	save(ply)
	Glac.SendCredits(ply)
end

function pmeta:GetCredits()
	return self.GlacCredits or 0
end

function pmeta:SetCredits(amount)
	amount = tonumber(amount)
	if not amount or amount ~= amount then return end

	self.GlacCredits = math.Clamp(math.floor(amount), 0, MAX_CREDITS)
	self.GlacPending = nil
	self.GlacLoaded = true
	changed(self)
end

function pmeta:AddCredits(amount)
	amount = tonumber(amount)
	if not amount or amount ~= amount then return end

	amount = math.floor(amount)

	if not self.GlacLoaded then
		self.GlacPending = (self.GlacPending or 0) + amount
		return
	end

	self.GlacCredits = math.Clamp((self.GlacCredits or 0) + amount, 0, MAX_CREDITS)
	changed(self)
end

-- true - списано; false - не хватает
function pmeta:TakeCredits(amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount < 0 or not self.GlacLoaded or (self.GlacCredits or 0) < amount then return false end
	if amount == 0 then return true end

	self.GlacCredits = self.GlacCredits - amount
	changed(self)

	return true
end

local function load(ply)
	local id = uid(ply)
	if not id or not Glac.DBReady or ply.GlacLoaded or ply.GlacLoading then return end

	ply.GlacLoading = true

	MySQLite.query("SELECT credits FROM glac_credits WHERE uid = " .. id, function(rows)
		ply.GlacLoading = nil
		if not IsValid(ply) or ply.GlacLoaded then return end

		local value = rows and rows[1] and tonumber(rows[1].credits) or 0
		ply.GlacCredits = math.Clamp(value + (ply.GlacPending or 0), 0, MAX_CREDITS)
		ply.GlacPending = nil
		ply.GlacLoaded = true

		if ply.GlacCredits ~= value then save(ply) end
		Glac.SendCredits(ply)
	end, function(err)
		ply.GlacLoading = nil
		ErrorNoHalt("[Glac] кредиты не загружены: " .. tostring(err) .. "\n")
	end)
end

hook.Add("DatabaseInitialized", "Glac.Credits", function()
	MySQLite.query("CREATE TABLE IF NOT EXISTS glac_credits(uid BIGINT NOT NULL PRIMARY KEY, credits BIGINT NOT NULL)", function()
		Glac.DBReady = true

		for _, ply in ipairs(player.GetHumans()) do load(ply) end
	end, function(err)
		ErrorNoHalt("[Glac] таблица кредитов: " .. tostring(err) .. "\n")
	end)
end)

hook.Add("PlayerInitialSpawn", "Glac.Credits", load)

-- клиент спрашивает баланс после загрузки
Glac.NetReceive("Sync", function(ply)
	if not IsValid(ply) or DarkRP.NetDelay(ply, 2) then return end

	if ply.GlacLoaded then Glac.SendCredits(ply) else load(ply) end
end)
