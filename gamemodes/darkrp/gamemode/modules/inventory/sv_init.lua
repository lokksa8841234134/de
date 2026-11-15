--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Инвентарь (McINV): серверная часть

	ply.inv       - карманы персонажа: {weapon = {}, entity = {}, ammo = {}, food = {}, junk = {}}
	ply.bank_inc  - хранилище (склад) аккаунта: общее для 3 персонажей, таблица darkrp_bank
	ent.inv       - содержимое контейнера (коробка, ящик, сейф, пакет, портфель, NPC)
	                чужие карманы открываются как контейнер только при обыске (police/sv_search.lua)

	Предмет - копия записи каталога (DarkRP.Weapons/Entities/Stations/Ammo/Food/Junk)
	с полями class, dt (сетевые переменные энтити), weight, name и т.д.
	В инвентарь попадают только очищенные копии: без функций, энтити и бесконечных чисел.

	Карманы живут в памяти: после выхода без боя ждут игрока KEEP_TIME секунд,
	при смерти и выходе в бою выпадают пакетом. При смене персонажа карманы
	(и оружие из рук) ждут этого персонажа, пока игрок в сети, после выхода - KEEP_TIME.
	Хранилище переживает смерть и рестарт.
---------------------------------------------------------------------------]]
util.AddNetworkString("McINV.Set")
util.AddNetworkString("McINV.StorageLookup")
util.AddNetworkString("McINV.UpdateStorage")
util.AddNetworkString("McINV.OpenBank")
util.AddNetworkString("McINV.Store")
util.AddNetworkString("McINV.Take")
util.AddNetworkString("McINV.Drop")
util.AddNetworkString("McINV.UpgradeBank")
util.AddNetworkString("McINV.RequestINV")
util.AddNetworkString("McINV.RequestINVOffline")
util.AddNetworkString("McINV.DeleteItem")
util.AddNetworkString("McINV.DeleteItemOffline")

local DEFAULT_SPACE = 7			-- карманы, кг
local MULE_SPACE = 3			-- тату "Мул" (b6), не работает в костюме
local BANK_SPACE = 15			-- базовый план хранилища (McINV.BankPlanes)
local MAX_ITEMS = 500			-- предметов одного типа в одном инвентаре
local MAX_ITEM_KEYS = 96		-- полей у одного предмета
local MAX_STACK = 20			-- "выбросить стопку" за один раз
local MAX_DROPS = 60			-- выброшенных игроком предметов на карте
local BANK_RANGE = 150 * 150	-- от точки, где открыли хранилище
local PICKUP_RANGE = 120 * 120
local PUT_RANGE = 40 * 40		-- ключи ищут контейнер в 30 юнитах от предмета
local PACK_RANGE = 26000		-- как в контекстном меню (client/vgui.lua)
local NPC_RANGE = 300 * 300
local KEEP_TIME = 600			-- карманы после выхода без боя
local DEATH_BAG_TIME = 600		-- пакет с вещами после смерти
local COMBAT_TIME = 60			-- как в модуле персонажей
local SAVE_DELAY = 2
local MAX_NET = 60000			-- сжатые данные в одном сообщении
local MAX_DECOMPRESS = 2 ^ 20
local MAX_STR = 2048
local MAX_DEPTH = 6
local MAX_KEYS = 64
local EPS = 0.0001
local BANK_NPC = "bank"			-- работник складов (mc_simple_npcs)
local DEALER_NPC = "dezz"		-- скупщик (McINV.SellStuff)
local DEFAULT_MODEL = "models/props_junk/cardboard_box004a.mdl"
local DEFAULT_WMODEL = "models/weapons/w_pistol.mdl"
local AMMO_MODEL = "models/props_lab/box01a.mdl"
local SHIPMENT_MODEL = "models/props_junk/cardboard_box002a.mdl"

local luaType = type
local pmeta = FindMetaTable("Player")
local emeta = FindMetaTable("Entity")

local TYPES = {INV_WEAPON, INV_ENTITY, INV_AMMO, INV_FOOD, INV_JUNK}

-- тип предмета -> класс энтити на земле
local GROUND_CLASS = {}

for class, type in pairs(McINV.pickups) do
	GROUND_CLASS[type] = class
end

McINV.Cache = McINV.Cache or {}
McINV.DropHandlers = McINV.DropHandlers or {}

-- лимит установленных станций (оружие deployment): deploy_limit[SteamID][класс] = количество
deploy_limit = deploy_limit or {}

function McINV.NewInventory()
	return {
		[INV_WEAPON] = {},
		[INV_ENTITY] = {},
		[INV_AMMO] = {},
		[INV_FOOD] = {},
		[INV_JUNK] = {},
	}
end

--[[---------------------------------------------------------------------------
	Очистка: всё, что попадает в инвентарь, копируется и проверяется
---------------------------------------------------------------------------]]
local function finite(v)
	return isnumber(v) and v == v and v ~= math.huge and v ~= -math.huge
end

local function cleanValue(v, depth)
	if isnumber(v) then return finite(v) and v or nil end
	if isstring(v) then return #v <= MAX_STR and v or nil end
	if isbool(v) then return v end
	if isvector(v) then return Vector(v.x, v.y, v.z) end
	if isangle(v) then return Angle(v.p, v.y, v.r) end
	if IsColor(v) then return Color(v.r, v.g, v.b, v.a) end
	if not istable(v) or depth > MAX_DEPTH then return nil end

	-- цвет после JSON (база, админ-меню) приходит обычной таблицей
	if finite(v.r) and finite(v.g) and finite(v.b) and table.Count(v) <= 4 then
		return Color(math.Clamp(v.r, 0, 255), math.Clamp(v.g, 0, 255), math.Clamp(v.b, 0, 255), finite(v.a) and math.Clamp(v.a, 0, 255) or 255)
	end

	local out, count = {}, 0

	for key, val in pairs(v) do
		if not (isstring(key) and #key <= 64) and not finite(key) then continue end

		count = count + 1
		if count > MAX_KEYS then break end

		local c = cleanValue(val, depth + 1)
		if c ~= nil then out[key] = c end
	end

	return out
end

local cleanInv

local function cleanItem(item, nested)
	if not istable(item) or not isstring(item.class) or item.class == "" or #item.class > 64 then return nil end

	local out, count = {}, 0

	for key, val in pairs(item) do
		if not isstring(key) or #key > 64 or key == "invS" then continue end

		count = count + 1
		if count > MAX_ITEM_KEYS then break end

		local c = cleanValue(val, 1)
		if c ~= nil then out[key] = c end
	end

	out.class = item.class

	if out.weight ~= nil then
		out.weight = isnumber(out.weight) and math.max(out.weight, 0) or nil
	end

	if out.dt ~= nil and not istable(out.dt) then out.dt = nil end

	-- содержимое пакета: только один уровень вложенности
	if not nested and istable(item.invS) then
		out.invS = cleanInv(item.invS, true)
	end

	return out
end

-- список предметов: номера по порядку, без дыр (JSON и админ-меню могут прислать дыры и строковые ключи)
local function cleanList(list, nested)
	local out = {}
	if not istable(list) then return out end

	local keys, seen = {}, {}

	for key in pairs(list) do
		local n = tonumber(key)

		if n and n >= 1 and n <= 1000000 and n == math.floor(n) and not seen[n] then
			seen[n] = true
			keys[#keys + 1] = n
		end

		if #keys >= MAX_ITEMS * 4 then break end
	end

	table.sort(keys)

	for _, n in ipairs(keys) do
		if #out >= MAX_ITEMS then break end

		local item = cleanItem(list[n] or list[tostring(n)], nested)
		if item then out[#out + 1] = item end
	end

	return out
end

function cleanInv(inv, nested)
	local out = McINV.NewInventory()
	if not istable(inv) then return out end

	for _, type in ipairs(TYPES) do
		out[type] = cleanList(inv[type], nested)
	end

	return out
end

--[[---------------------------------------------------------------------------
	Вспомогательное
---------------------------------------------------------------------------]]
local function ensureInv(ent)
	if not istable(ent.inv) then ent.inv = McINV.NewInventory() end

	for _, type in ipairs(TYPES) do
		if not istable(ent.inv[type]) then ent.inv[type] = {} end
	end

	return ent.inv
end

-- удалить по номеру (у списков NPC возможны дыры)
local function removeAt(list, id)
	if not istable(list) or not isnumber(id) or list[id] == nil then return nil end

	if id > #list then
		local item = list[id]
		list[id] = nil
		return item
	end

	return table.remove(list, id)
end

-- контракты RDM (sv_contracts.lua)
McINV.RemoveAt = removeAt

-- добавить в список; id - вернуть на прежнее место (номера в открытом меню не сдвигаются)
local function pushItem(list, item, id)
	if #list >= MAX_ITEMS then return false end

	if id and id >= 1 and id <= #list then
		table.insert(list, id, item)
	else
		list[#list + 1] = item
	end

	return true
end

local function ownerOf(ent)
	if ent.CPPIGetOwner then
		local owner = ent:CPPIGetOwner()
		if IsValid(owner) then return owner end
	end

	if ent.Getowning_ent then
		local owner = ent:Getowning_ent()
		if IsValid(owner) then return owner end
	end

	return nil
end

-- владелец энтити (кассы - sv_registers.lua)
McINV.OwnerOf = ownerOf

local function validModel(model)
	if not isstring(model) or model == "" or #model > 255 then return nil end

	return util.IsValidModel(model) and model or nil
end

local function itemWeight(type, item)
	return tonumber(McINV.GetWeight(item, type, item.class)) or 0
end

-- вместимость контейнера (как в меню хранилища на клиенте)
local function containerSpace(ent)
	if ent.GetSpace then return tonumber(ent:GetSpace()) or 0 end

	return ent:GetDefaultSpace() or 0
end

-- оружие, которое нельзя выбросить на землю (служебное, ключи и т.п.)
local function noDropWeapon(class)
	local single = DarkRP.SingleWep and DarkRP.SingleWep.DisallowDrop

	return (GAMEMODE.Config.DisallowDrop and GAMEMODE.Config.DisallowDrop[class]) or (single and single[class]) or false
end

local function canUse(ply)
	return IsValid(ply) and ply:IsPlayer() and ply:IsUnrestrained() and ply:getDarkRPVar("character") ~= nil and istable(ply.inv)
end

-- рядом NPC с этим UID; если такого NPC на карте нет - решает strict
local function nearNPC(ply, uid, strict)
	local found = false

	for _, npc in ipairs(ents.FindByClass("mcs_npc")) do
		if not npc.GetUID or npc:GetUID() ~= uid then continue end

		found = true

		if npc:GetPos():DistToSqr(ply:GetPos()) <= NPC_RANGE then return true end
	end

	return not found and not strict
end

local function cacheKey(ply)
	return tostring(ply:SteamID64()) .. ":" .. tostring(DarkRP.CharacterID(ply))
end

local function ammoWeight(item)
	local data = DarkRP.Ammo[item.class]
	if not data or not data.bul or not istable(item.dt) then return end

	item.weight = (data.weight or 0) + math.Round(math.max(tonumber(item.dt.Ammo) or 0, 0) * data.bul, 2)
end

local function currency()
	return GAMEMODE.Config.currency or "$"
end

--[[---------------------------------------------------------------------------
	Открытые контейнеры: ply.McINVLoot - что смотрит игрок, ent.McINVViewers - кто смотрит
---------------------------------------------------------------------------]]
local function closeLoot(ply)
	local ent = ply.McINVLoot

	if IsValid(ent) and ent.McINVViewers then
		ent.McINVViewers[ply] = nil
	end

	ply.McINVLoot = nil
	ply.McINVLootForce = nil
end

local function openLoot(ply, ent, force)
	closeLoot(ply)

	ply.McINVLoot = ent
	ply.McINVLootForce = force and true or nil

	ent.McINVViewers = ent.McINVViewers or {}
	ent.McINVViewers[ply] = true
end

local function closeSessions(ply)
	closeLoot(ply)
	ply.McINVBank = nil
end

local function sendStorage(ent, targets)
	local data, len = DarkRP.TableCompress(ent.inv)
	if len > MAX_NET then return false end

	net.Start("McINV.UpdateStorage")
		net.WriteEntity(ent)
		net.WriteString("none")
		net.WriteUInt(len, 32)
		net.WriteData(data, len)
	net.Send(targets)

	return true
end

-- содержимое изменилось: вес пакета, пустой пакет с вещами убитого, обновление у смотрящих
local function containerChanged(ent)
	if not IsValid(ent) then return end

	if ent.invCanStore and istable(ent.inv) then
		local data = DarkRP.Entities[ent:GetClass()]
		ent.weight = ((data and data.weight) or 0) + McINV.GetSpace(ent.inv)
	end

	if ent.McINVTemp and McINV.IsEmpty(ent.inv) then
		ent:Remove()
		return
	end

	if ent.McINVSync then return end
	ent.McINVSync = true

	timer.Simple(0, function()
		if not IsValid(ent) then return end
		ent.McINVSync = nil

		local viewers = {}

		for ply in pairs(ent.McINVViewers or {}) do
			if IsValid(ply) and ply.McINVLoot == ent and McINV.CanAccess(ply, ent) then
				viewers[#viewers + 1] = ply
			else
				ent.McINVViewers[ply] = nil
			end
		end

		if #viewers > 0 then
			sendStorage(ent, viewers)
		end

		-- касса: новый список товаров у покупателей (sv_registers.lua)
		if ent.OnInventoryChanged then ent:OnInventoryChanged() end
	end)
end

--[[---------------------------------------------------------------------------
	База данных: darkrp_bank(uid = SteamID64, space = план, data = JSON хранилища)
---------------------------------------------------------------------------]]
local function dbError(err, query)
	MsgC(Color(255, 90, 0), "[McINV] SQL: " .. tostring(err) .. "\n    " .. tostring(query) .. "\n")
end

local function validSpace(space)
	space = tonumber(space)

	return (space and McINV.BankPlanes[space]) and space or BANK_SPACE
end

hook.Add("DatabaseInitialized", "McINV", function()
	MySQLite.query([[CREATE TABLE IF NOT EXISTS darkrp_bank(
		uid BIGINT NOT NULL PRIMARY KEY,
		space INTEGER NOT NULL DEFAULT 15,
		data MEDIUMTEXT
	)]], nil, dbError)
end)

local function saveBankNow(ply)
	if not IsValid(ply) or not ply.McINVBankLoaded then return end

	local uid = DarkRP.GetPlayerUID(ply)
	if not uid or not DarkRP.DBReady then return end

	timer.Remove("McINV.Save." .. uid)

	MySQLite.query(string.format("REPLACE INTO darkrp_bank(uid, space, data) VALUES(%s, %d, %s)",
		uid, validSpace(ply.McINVBankSpace), MySQLite.SQLStr(util.TableToJSON(ply.bank_inc or {}))
	), nil, dbError)
end

-- частые изменения (перекладывание) пишутся не чаще раза в SAVE_DELAY секунд
local function saveBank(ply)
	if not ply.McINVBankLoaded then return end

	local uid = DarkRP.GetPlayerUID(ply)
	if not uid then return end

	local name = "McINV.Save." .. uid
	if timer.Exists(name) then return end

	timer.Create(name, SAVE_DELAY, 1, function()
		if IsValid(ply) then saveBankNow(ply) end
	end)
end

--[[---------------------------------------------------------------------------
	Отправка клиенту (McINV.Set: UInt32 + Data карманов, Bool, [UInt32 + Data хранилища])
---------------------------------------------------------------------------]]
local function sendInventory(ply, withBank)
	if not IsValid(ply) or not ply.DarkRPClientReady or not istable(ply.inv) then return end

	local data, len = DarkRP.TableCompress(ply.inv)

	if len > MAX_NET then
		MsgC(Color(255, 90, 0), "[McINV] Инвентарь " .. ply:SteamID() .. " слишком большой для отправки (" .. len .. " байт)\n")
		return
	end

	local bdata, blen

	if withBank and ply.McINVBankLoaded then
		bdata, blen = DarkRP.TableCompress(ply.bank_inc)

		if len + blen > MAX_NET then
			MsgC(Color(255, 90, 0), "[McINV] Хранилище " .. ply:SteamID() .. " слишком большое для отправки (" .. blen .. " байт)\n")
			bdata = nil
		end
	end

	net.Start("McINV.Set")
		net.WriteUInt(len, 32)
		net.WriteData(data, len)
		net.WriteBool(bdata ~= nil)

		if bdata then
			net.WriteUInt(blen, 32)
			net.WriteData(bdata, blen)
		end
	net.Send(ply)
end

-- отправка откладывается до конца кадра: десяток изменений подряд - одно сообщение
function pmeta:UpdateInventory(withBank)
	if withBank then self.McINVSendBank = true end
	if self.McINVSendQueued then return end

	self.McINVSendQueued = true

	timer.Simple(0, function()
		if not IsValid(self) then return end

		local bank = self.McINVSendBank
		self.McINVSendQueued = nil
		self.McINVSendBank = nil

		sendInventory(self, bank)
		hook.Call("UpdateInventory", nil, self, bank)

		-- карманы открыты при обыске (police/sv_search.lua): обновить у обыскивающих
		if self.McINVViewers and next(self.McINVViewers) ~= nil then
			containerChanged(self)
		end
	end)
end

--[[---------------------------------------------------------------------------
	Место (кг)
---------------------------------------------------------------------------]]
function pmeta:HaveSpace(weight)
	if not istable(self.inv) then return false end

	return self:GetInvSpace() + (tonumber(weight) or 0) <= (self:GetDefaultSpace() or 0) + EPS
end

-- пока хранилище не загружено из базы, места в нём нет
function pmeta:HaveBankSpace(weight)
	if not self.McINVBankLoaded or not istable(self.bank_inc) then return false end

	return McINV.GetSpace(self.bank_inc) + (tonumber(weight) or 0) <= validSpace(self.McINVBankSpace) + EPS
end

--[[---------------------------------------------------------------------------
	Добавить и забрать предмет
	Вместимость здесь не проверяется - это делает вызывающий код (HaveSpace и т.п.)
---------------------------------------------------------------------------]]
-- bank = true - в хранилище игрока; вернёт сохранённую копию или false
function emeta:AddItem(type, item, bank)
	if not McINV.ttypes[type] then return false end

	item = cleanItem(item)
	if not item then return false end

	if not self:IsPlayer() then
		if not pushItem(ensureInv(self)[type], item) then return false end

		containerChanged(self)

		return item
	end

	-- метки улик и личных вещей имеют смысл только в контейнерах
	item.putby = nil
	item.putname = nil
	item.personal = nil

	if bank then
		-- хранилище ещё загружается: предмет добавится сразу после загрузки
		if not self.McINVBankLoaded then
			self.McINVBankQueue = self.McINVBankQueue or {}
			if #self.McINVBankQueue >= MAX_ITEMS then return false end

			self.McINVBankQueue[#self.McINVBankQueue + 1] = {type, item}

			return item
		end

		if not pushItem(self.bank_inc[type], item) then return false end

		saveBank(self)
		self:UpdateInventory(true)

		return item
	end

	if self:getDarkRPVar("character") == nil or not istable(self.inv) then return false end
	if not pushItem(self.inv[type], item) then return false end

	self:UpdateInventory()

	return item
end

-- вернёт забранный предмет или nil
function emeta:RemoveItem(type, id, bank)
	id = tonumber(id)
	if not McINV.ttypes[type] or not id then return nil end

	if not self:IsPlayer() then
		if not istable(self.inv) then return nil end

		local item = removeAt(self.inv[type], id)
		if item == nil then return nil end

		containerChanged(self)

		return item
	end

	if bank and not self.McINVBankLoaded then return nil end

	local inv = bank and self.bank_inc or self.inv
	if not istable(inv) then return nil end

	local item = removeAt(inv[type], id)
	if item == nil then return nil end

	if bank then saveBank(self) end
	self:UpdateInventory(bank)

	return item
end

-- предмет из каталога по классу (наручники дубинки и отмычки, обвесы)
function emeta:AddItemByClass(type, class, bank)
	local data = McINV.GetItem(type, class)
	if not data then return false end

	return McINV.AddCustomItem(self, type, class, data, bank)
end

function emeta:RemoveItemByClass(type, class, bank)
	local inv = (bank and self:IsPlayer()) and self.bank_inc or self.inv
	local list = istable(inv) and inv[type]
	if not istable(list) then return nil end

	for id = table.maxn(list), 1, -1 do
		if list[id] and list[id].class == class then
			return self:RemoveItem(type, id, bank)
		end
	end

	return nil
end

function emeta:AddBankItem(type, item)
	return self:AddItem(type, item, true)
end

--[[---------------------------------------------------------------------------
	Магазины и патроны (перезарядка mg_base)
---------------------------------------------------------------------------]]
-- магазин из оружия обратно в карманы; места не требует - его только что достали
function pmeta:AddMag(class, ammo, nodrop)
	local data = isstring(class) and DarkRP.Ammo[class]
	if not data then return false end

	local item = McINV.AddCustomItem(nil, INV_AMMO, class, data)
	if not item then return false end

	ammo = math.max(math.floor(tonumber(ammo) or 0), 0)
	item.dt.Ammo = data.ammo and math.min(ammo, data.ammo) or ammo
	item.nodrop = nodrop and true or nil
	ammoWeight(item)

	return self:AddItem(INV_AMMO, item)
end

-- самый полный подходящий магазин: патроны, класс, nodrop
function pmeta:RemoveAnyMag(types)
	if not istable(types) or not istable(self.inv) then return nil end

	local best, ammo = nil, 0

	for id, item in ipairs(self.inv[INV_AMMO]) do
		local count = istable(item.dt) and tonumber(item.dt.Ammo) or 0

		if types[item.class] and count > ammo then
			best, ammo = id, count
		end
	end

	if not best then return nil end

	local item = self:RemoveItem(INV_AMMO, best)
	if not item then return nil end

	return math.floor(ammo), item.class, item.nodrop
end

-- патроны поштучно (дробовики, револьверы) по порядку, как HasBullets; пустые пачки выбрасываются
-- вернёт класс последней пачки и nodrop
function pmeta:RemoveAnyBullet(types, count)
	if not istable(types) or not istable(self.inv) then return nil end

	count = math.max(math.floor(tonumber(count) or 1), 0)

	local list = self.inv[INV_AMMO]
	local class, nodrop
	local id = 1

	while count > 0 and id <= #list do
		local item = list[id]
		local ammo = istable(item.dt) and tonumber(item.dt.Ammo) or 0

		if types[item.class] and ammo > 0 then
			local take = math.min(ammo, count)

			item.dt.Ammo = ammo - take
			count = count - take
			class = item.class
			nodrop = nodrop or item.nodrop

			if item.dt.Ammo <= 0 then
				table.remove(list, id)
			else
				ammoWeight(item)
				id = id + 1
			end
		else
			id = id + 1
		end
	end

	if class then self:UpdateInventory() end

	return class, nodrop
end

--[[---------------------------------------------------------------------------
	Предмет из каталога (тот же расчёт, что и McINV.AddCustomItem на клиенте)
	e = nil - только собрать предмет, иначе положить его в карманы/хранилище/контейнер e
---------------------------------------------------------------------------]]
function McINV.AddCustomItem(e, type, class, data, bank)
	if McINV.DarkRPTypes[type] then type = McINV.DarkRPTypes[type] end
	if not isstring(class) or not istable(data) then return false end

	local item = table.Copy(data)

	item.class = class
	item.dt = {
		eclass = class
	}

	-- станция (ящик, сейф, верстак) лежит в инвентаре запакованной
	if type == "Stations" then
		type = INV_ENTITY
		item.class = "spawned_shipment"
		item.dt.ename = data.name
		item.dt.DeployModel = data.model
		item.model = SHIPMENT_MODEL
	end

	if data.uses then
		item.dt.uses = data.uses
		item.weight = data.uses * (data.weight or 0) + (data.conwht or 0)
	end

	if data.btime then
		item.mt = os.time() + data.btime
	end

	if type == INV_AMMO then
		item.model = AMMO_MODEL
		item.material = "cityrp/labs"
		item.dt.Ammo = data.sell_empty and 0 or data.ammo
		item.dt.ename = data.name
		item.dt.mmodel = data.model or ""

		if data.bul and data.ammo and not data.sell_empty then
			item.weight = (data.weight or 0) + math.Round(data.ammo * data.bul, 2)
		end
	end

	if e == nil then
		return cleanItem(item) or false
	end

	if not IsValid(e) then return false end

	return e:AddItem(type, item, bank) or false
end

--[[---------------------------------------------------------------------------
	Предмет на землю: энтити собирается обратно из сохранённой копии
---------------------------------------------------------------------------]]
-- модель оружия: своя у предмета, из каталога или WorldModel; модели без физики - через wmfix (как DropDRPWeapon)
local function weaponModel(item)
	local data = DarkRP.Weapons[item.class]
	local stored = weapons.GetStored(item.class)
	local model = validModel(item.model) or validModel(data and data.model) or validModel(stored and stored.WorldModel)

	if not model then return DEFAULT_WMODEL end

	local fix = GAMEMODE.Config.wmfix and GAMEMODE.Config.wmfix[model]

	if fix and util.IsValidModel(fix) then
		return fix, model
	end

	return model
end

-- сетевые переменные из предмета: только те, что есть у энтити, и того же типа
local function applyDT(ent, dt)
	if not istable(dt) or not ent.GetNetworkVars then return end

	local vars = ent:GetNetworkVars()

	for key, val in pairs(dt) do
		if key == "owning_ent" or vars[key] == nil or luaType(vars[key]) ~= luaType(val) then continue end

		local set = ent["Set" .. key]
		if isfunction(set) then set(ent, val) end
	end
end

function McINV.SpawnItem(type, item, pos, ang, owner)
	if not McINV.ttypes[type] or not istable(item) or not isstring(item.class) or not isvector(pos) then return nil end

	local class = GROUND_CLASS[type] or item.class
	local ent = ents.Create(class)
	if not IsValid(ent) then return nil end

	local data = McINV.GetItem(type, item.class) or {}
	local model, remodel

	if type == INV_WEAPON then
		model, remodel = weaponModel(item)
	elseif type == INV_AMMO then
		-- в инвентаре у патронов общая иконка, на земле - модель из каталога
		model = validModel(istable(item.dt) and item.dt.mmodel) or validModel(data.model) or validModel(item.model) or AMMO_MODEL
	else
		model = validModel(item.model) or validModel(data.model) or (class == "spawned_shipment" and SHIPMENT_MODEL) or DEFAULT_MODEL
	end

	ent:SetPos(pos)
	ent:SetAngles(ang or angle_zero)
	ent:SetModel(model)

	-- поля, которые энтити хранит у себя: вес, имя, срок годности, данные телефона и документов
	for key in pairs(McINV.CopyData) do
		if item[key] ~= nil then
			ent[key] = istable(item[key]) and table.Copy(item[key]) or item[key]
		end
	end

	if type == INV_WEAPON then
		ent.clip1 = item.clip1
		ent.clip2 = item.clip2
		ent.att_saved = istable(item.att_saved) and table.Copy(item.att_saved) or nil
		ent.gunstate = item.gunstate
		ent.remodel = remodel
	end

	ent:Spawn()
	ent:Activate()

	-- Initialize некоторых энтити ставит свою модель
	if ent:GetModel() ~= model then
		ent:SetModel(model)
		ent:PhysicsInit(SOLID_VPHYSICS)
		ent:SetMoveType(MOVETYPE_VPHYSICS)
		ent:SetSolid(SOLID_VPHYSICS)
	end

	local material = item.material

	if type == INV_AMMO and model ~= item.model then
		material = data.material
	end

	if isstring(material) and material ~= "" and #material <= 255 then
		ent:SetMaterial(material)
	end

	-- сабматериалы и бодигруппы каталога (как у хлама из спавн-меню)
	if model == data.model then
		for k, v in pairs(istable(data.submat) and data.submat or {}) do
			ent:SetSubMaterial(k, v)
		end

		for k, v in pairs(istable(data.bgr) and data.bgr or {}) do
			ent:SetBodygroup(k, v)
		end
	end

	local color = item.color

	if istable(color) and finite(color.r) and finite(color.g) and finite(color.b) then
		ent:SetColor(Color(color.r, color.g, color.b, finite(color.a) and color.a or 255))
	end

	applyDT(ent, item.dt)

	if GROUND_CLASS[type] and ent.Seteclass then
		ent:Seteclass(item.class)
	end

	if type == INV_WEAPON then
		DarkRP.CopyGunDate(item, ent)
	end

	if ent.invCanStore then
		ent.inv = cleanInv(item.invS, true)
		containerChanged(ent)
	end

	if IsValid(owner) then
		if ent.CPPISetOwner then ent:CPPISetOwner(owner) end
		if ent.Setowning_ent then ent:Setowning_ent(owner) end

		owner.McINVDrops = owner.McINVDrops or {}
		owner.McINVDrops[ent] = class
		ent.McINVDropper = owner
	end

	-- копия предмета: при подборе вернутся поля, которых нет у энтити (цена, доставка, данные каталога)
	local saved = table.Copy(item)
	saved.invS = nil
	ent.McINVItem = saved

	local phys = ent:GetPhysicsObject()
	if IsValid(phys) then phys:Wake() end

	return ent
end

-- точка перед игроком; i - номер предмета в стопке (раскладываются сеткой)
local function dropPos(ply, i)
	local aim = ply:GetAimVector()

	local tr = util.TraceLine({
		start = ply:EyePos(),
		endpos = ply:EyePos() + aim * 40,
		filter = ply
	})

	local pos = tr.HitPos - aim * 10

	-- выше ног: ключи берут в руки только то, что выше игрока
	pos.z = math.max(pos.z, ply:GetPos().z + 8)

	if i and i > 1 then
		local n = i - 1
		pos = pos + Vector((n % 3 - 1) * 8, (math.floor(n / 3) % 3 - 1) * 8, math.floor(n / 9) * 8)
	end

	if not util.IsInWorld(pos) then
		pos = ply:GetPos() + Vector(0, 0, 16)
	end

	return pos, Angle(0, ply:EyeAngles().y, 0)
end

-- лимит выброшенных предметов: всего и по каталогу (коробок - не больше max)
local function canDrop(ply, class)
	local drops = ply.McINVDrops or {}
	local total, same = 0, 0

	for ent, c in pairs(drops) do
		if not IsValid(ent) then
			drops[ent] = nil
		else
			total = total + 1
			if c == class then same = same + 1 end
		end
	end

	if total >= MAX_DROPS then
		return false, "Вы выбросили слишком много предметов"
	end

	local data = DarkRP.Entities[class]

	if data and data.max and same >= data.max then
		return false, "Нельзя выбросить больше " .. data.max .. " шт.: " .. (data.name or class)
	end

	return true
end

--[[---------------------------------------------------------------------------
	Предмет с земли
---------------------------------------------------------------------------]]
-- тип и класс предмета; nil - энтити нельзя положить в инвентарь (как SWEP:InvCheck у ключей)
local function entityItemType(ent)
	local class = ent:GetClass()
	local type = McINV.pickups[class]

	if type then
		local eclass = ent.Geteclass and ent:Geteclass()
		if not isstring(eclass) or eclass == "" then return nil end

		return type, eclass
	end

	if DarkRP.Entities[class] then
		return INV_ENTITY, class
	end

	return nil
end

-- вернёт текст отказа или nil
local function groundCheck(ent)
	if ent.Draged then return "Объект окупирован" end
	if ent.NonPickeble then return "Предмет поврежден" end
	if ent:IsOnFire() then return "Предмет горит" end
	if ent.McINVTemp then return "Разберите вещи по одной" end
	if ent.InUse == true or (isentity(ent.InUse) and IsValid(ent.InUse)) then return "Предмет используется" end
	if IsValid(ent:GetParent()) then return "Предмет закреплён" end

	if istable(ent.inv) and not ent.invCanStore and not McINV.IsEmpty(ent.inv) then
		return "Сначала освободите хранилище"
	end

	return nil
end

-- сохранённая копия (если предмет выбросили из инвентаря) + текущее состояние энтити
local function itemFromEntity(ent, type, class)
	local item

	if istable(ent.McINVItem) then
		item = table.Copy(ent.McINVItem)
	else
		local data = McINV.GetItem(type, class)
		item = data and McINV.AddCustomItem(nil, type, class, data) or {class = class}
	end

	if not item then return nil end

	local dt = istable(item.dt) and item.dt or {}

	for key, val in pairs(McINV.GetItemTable(ent, type, class)) do
		if key == "dt" then
			for k, v in pairs(istable(val) and val or {}) do
				dt[k] = v
			end
		elseif key ~= "invS" and not (type == INV_AMMO and (key == "model" or key == "material")) then
			item[key] = val
		end
	end

	item.class = class
	item.dt = dt
	dt.eclass = dt.eclass or class

	-- физика от замены (wmfix): в инвентаре хранится настоящая модель
	if type == INV_WEAPON and isstring(ent.remodel) then
		item.model = ent.remodel
	end

	if ent.invCanStore then
		local data = DarkRP.Entities[ent:GetClass()]

		item.invS = cleanInv(ent.inv, true)
		item.weight = ((data and data.weight) or 0) + McINV.GetSpace(item.invS)
	end

	item.putby = nil
	item.putname = nil
	item.personal = nil

	McINV.ModifyItem(item)

	return cleanItem(item)
end

-- подобрать в карманы (ключи); тип и класс считаются здесь, аргументы ключей не нужны
function pmeta:Pickup(ent)
	if not IsValid(ent) or ent.McINVTaken or not canUse(self) or self:InVehicle() then return false end
	if self:EyePos():DistToSqr(ent:NearestPoint(self:EyePos())) > PICKUP_RANGE then return false end

	local type, class = entityItemType(ent)
	if not type then return false end

	local reason = groundCheck(ent)

	if reason then
		return false
	end

	local item = itemFromEntity(ent, type, class)
	if not item then return false end

	if not self:HaveSpace(itemWeight(type, item)) then
		return false
	end

	if not self:AddItem(type, item) then return false end

	ent.McINVTaken = true
	ent:Remove()

	if type == INV_WEAPON then
		DarkRP.log("other", self, nil, "подобрал оружие" .. McINV.prt(item))
	end

	return true
end

--[[---------------------------------------------------------------------------
	Контейнеры
---------------------------------------------------------------------------]]
-- доступ к содержимому: портфель - владельцу, ENT:CanLoot (почтовый ящик), сейф и касса - только владельцу
-- (сейф и оружейный шкаф, открытые ключами владельца или отмычкой, IsUnLocked - любому),
-- карманы игрока - только при обыске (McINV.CanSearch задаёт police/sv_search.lua),
-- склад улик - полиции, склад RDM - оружейному мастеру (у NPC это условия ответов, их видит только клиент)
function McINV.CanAccess(ply, ent)
	if not IsValid(ply) or not IsValid(ent) then return false end

	if ent:IsPlayer() then
		return ent ~= ply and isfunction(McINV.CanSearch) and McINV.CanSearch(ply, ent) == true
	end

	if ent:IsWeapon() then
		return ent:GetOwner() == ply
	end

	if ent.policeEvidnce and not ply:isCP() then return false end
	if ent.RDMContract and ply:Team() ~= TEAM_GUN then return false end

	if isfunction(ent.CanLoot) and not ent:CanLoot(ply) then return false end

	if ent.McINVOwnerOnly and ownerOf(ent) ~= ply and not ent.IsUnLocked then return false end

	return true
end

-- контейнер, который игрок открыл и всё ещё может трогать
-- (McINVBusy - на станции идёт крафт, содержимое закрыто)
local function lootTarget(ply, ent)
	if not IsValid(ent) or ply.McINVLoot ~= ent or not istable(ent.inv) or ent:IsOnFire() or ent.McINVBusy then return nil end
	if not McINV.CanAccess(ply, ent) then return nil end

	-- force: дистанцию при открытии проверил вызвавший код (NPC - 200 юнитов)
	if ply.McINVLootForce then
		if ent:GetPos():DistToSqr(ply:GetPos()) > NPC_RANGE then return nil end
	elseif not McINV.CanLoot(ply, ent) then
		return nil
	end

	return ent
end

-- открытый игроком контейнер, если его ещё можно трогать (для других модулей: склад улик)
function McINV.GetLootTarget(ply)
	return lootTarget(ply, ply.McINVLoot)
end

-- содержимое поменяли напрямую (оформление улик): вес и обновление у смотрящих
McINV.ContainerChanged = containerChanged

-- закрыть контейнер у всех, кто его смотрит (энтити удалена, обыск закончился)
function McINV.CloseViewers(ent)
	if not ent.McINVViewers then return end

	local viewers = {}

	for ply in pairs(ent.McINVViewers) do
		if IsValid(ply) and ply.McINVLoot == ent then
			ply.McINVLoot = nil
			ply.McINVLootForce = nil
			viewers[#viewers + 1] = ply
		end
	end

	ent.McINVViewers = nil

	if #viewers > 0 then
		net.Start("McINV.UpdateStorage")
			net.WriteEntity(ent)
			net.WriteString("remove")
		net.Send(viewers)
	end
end

-- открыть контейнер (McINV.StorageLookup); craft - меню верстака, msg - текст над содержимым (иначе ent.LootMessage)
function McINV.Loot(ent, ply, craft, force, msg)
	if not IsValid(ent) or not canUse(ply) then return false end
	if not istable(ent.inv) or not McINV.CanAccess(ply, ent) then return false end
	if not force and not McINV.CanLoot(ply, ent) then return false end

	ensureInv(ent)

	local data, len = DarkRP.TableCompress(ent.inv)
	if len > MAX_NET then return false end

	openLoot(ply, ent, force)

	net.Start("McINV.StorageLookup")
		net.WriteEntity(ent)
		net.WriteInt(len, 32)
		net.WriteData(data, len)
		net.WriteBool(craft and true or false)

		if not craft then
			msg = isstring(msg) and msg or ent.LootMessage
			net.WriteString(isstring(msg) and msg or "")
		end
	net.Send(ply)

	return true
end

-- вернёт текст отказа или nil
local function canStoreIn(ent, type, item)
	local data = McINV.GetItem(type, item.class)

	if data and data.canstore == false then return "Это нельзя положить в хранилище" end
	if item.nodrop then return "Этот предмет нельзя никому передать" end

	if istable(item.invS) and not McINV.IsEmpty(item.invS) then
		return "Сначала разберите " .. (item.name or "содержимое")
	end

	if McINV.GetSpace(ent.inv) + itemWeight(type, item) > containerSpace(ent) + EPS then
		return "Недостаточно места"
	end

	return nil
end

-- улики и контракты: кто положил (NYPD Npc возвращает личные вещи по putby)
local function markPut(ent, item, ply)
	if not ent.policeEvidnce and not ent.RDMContract then return end

	item.putby = ply:SteamID64()

	if ent.policeEvidnce then
		item.putname = ply:FullName()
	end
end

-- чужое в уликах и контрактах трогать нельзя
local function putLocked(ply, item)
	return item.putby ~= nil and item.putby ~= ply:SteamID64()
end

-- обыск: в журнал полиции, задержанному - что забрали
local function searchTaken(ply, target, type, item, what)
	DarkRP.log("police", ply, target, what .. " " .. McINV.prt(item, type))
end

-- предмет с земли сразу в контейнер рядом (ключи с зажатым бегом)
function McINV.PutInEntity(ply, target, ent)
	if not IsValid(target) or not IsValid(ent) or target == ent or ent.McINVTaken or not canUse(ply) then return false end
	if target:IsPlayer() or not istable(target.inv) then return false end

	if target.McINVTemp or target.McINVBusy then
		return false
	end

	if not McINV.CanAccess(ply, target) or not McINV.CanLoot(ply, target) then return false end
	if ply:EyePos():DistToSqr(ent:NearestPoint(ply:EyePos())) > PICKUP_RANGE then return false end
	if ent:NearestPoint(target:GetPos()):DistToSqr(target:NearestPoint(ent:GetPos())) > PUT_RANGE then return false end

	local type, class = entityItemType(ent)
	if not type then return false end

	local reason = groundCheck(ent)

	if reason then
		return false
	end

	local item = itemFromEntity(ent, type, class)
	if not item then return false end

	reason = canStoreIn(target, type, item)

	if reason then
		return false
	end

	markPut(target, item, ply)

	if not target:AddItem(type, item) then return false end

	ent.McINVTaken = true
	ent:Remove()

	return true
end

--[[---------------------------------------------------------------------------
	Хранилище: открывается у складской ячейки и почтового ящика
	ply.McINVBank = {noput = почта (только забрать доставку), ent, pos}
---------------------------------------------------------------------------]]
local function bankSession(ply)
	local s = ply.McINVBank
	if not s then return nil end

	if (s.ent ~= nil and not IsValid(s.ent)) or ply:GetPos():DistToSqr(s.pos) > BANK_RANGE then
		ply.McINVBank = nil
		return nil
	end

	return s
end

function McINV.OpenBank(ply, noput, ent, pos)
	if not IsValid(ply) or not ply:IsFreeman() or ply:getDarkRPVar("character") == nil then return false end

	if not ply.McINVBankLoaded then
		return false
	end

	pos = isvector(pos) and pos or (IsValid(ent) and ent:GetPos()) or ply:GetPos()
	if ply:GetPos():DistToSqr(pos) > BANK_RANGE then return false end

	closeLoot(ply)

	ply.McINVBank = {
		noput = noput and true or false,
		ent = IsValid(ent) and ent or nil,
		pos = pos,
	}

	sendInventory(ply, true)

	net.Start("McINV.OpenBank")
		net.WriteBool(noput and true or false)
	net.Send(ply)

	return true
end

local function finishBank(ply, space, data)
	ply.bank_inc = cleanInv(data)
	ply.McINVBankSpace = validSpace(space)
	ply.McINVBankLoaded = true
	ply:SetSelfDarkRPVar("bankspace", ply.McINVBankSpace)

	-- пришло до загрузки: доставка, возврат имущества
	local queue = ply.McINVBankQueue
	ply.McINVBankQueue = nil

	if queue then
		for _, v in ipairs(queue) do
			pushItem(ply.bank_inc[v[1]], v[2])
		end

		saveBankNow(ply)
	end

	ply:UpdateInventory(true)
end

local function loadBank(ply)
	if not IsValid(ply) or ply.McINVBankLoaded or ply.McINVBankLoading then return end

	local uid = DarkRP.GetPlayerUID(ply)

	-- у ботов хранилище только в памяти
	if not uid then
		finishBank(ply, BANK_SPACE, {})
		return
	end

	if not DarkRP.DBReady then return end

	ply.McINVBankLoading = true

	MySQLite.query("SELECT space, data FROM darkrp_bank WHERE uid = " .. uid, function(rows)
		if not IsValid(ply) then return end
		ply.McINVBankLoading = nil

		local row = istable(rows) and rows[1]
		local data = row and isstring(row.data) and util.JSONToTable(row.data)

		finishBank(ply, row and row.space, data or {})
	end, function(err, query)
		dbError(err, query)
		if not IsValid(ply) then return end
		ply.McINVBankLoading = nil

		-- без загрузки хранилище нельзя ни открыть, ни сохранить
		timer.Simple(15, function() loadBank(ply) end)
	end)
end

--[[---------------------------------------------------------------------------
	Размер карманов: 7 кг, тату "Мул" +3 (не в костюме), форма может задать свой (мэр - 4)
---------------------------------------------------------------------------]]
local function inSuit(ply)
	return ply.insuit or string.find(string.lower(ply:GetModel() or ""), "/pm/suit/", 1, true) ~= nil
end

local function updateSpace(ply)
	local space = ply.McINVFixed

	if not space then
		space = DEFAULT_SPACE

		if MCR.HasTatoo(ply, "b6") and not inSuit(ply) then
			space = space + MULE_SPACE
		end
	end

	if ply:getDarkRPVar("invspace") ~= space then
		ply:SetDarkRPVar("invspace", space)
	end

	ply:UpdateInventory()
end

-- size - размер от формы (до следующей смены модели), без size - обычный
function McINV.InventorySize(ply, size)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	size = tonumber(size)
	ply.McINVFixed = size and math.Clamp(math.floor(size), 0, 1000) or nil

	updateSpace(ply)
end

--[[---------------------------------------------------------------------------
	Вещи на землю пакетом: смерть, выход в бою, портфель
---------------------------------------------------------------------------]]
local function spawnBag(contents, pos, name)
	if McINV.NoDrops or McINV.IsEmpty(contents) then return nil end

	local bag = ents.Create("spawned_bag")
	if not IsValid(bag) then return nil end

	bag:SetPos(pos)
	bag:Spawn()
	bag:Activate()

	bag.inv = contents
	bag.McINVTemp = true
	bag:SetSpace(math.max(2, math.ceil(McINV.GetSpace(contents))))
	bag:SetStorageName(name or "Вещи")
	containerChanged(bag)

	timer.Simple(DEATH_BAG_TIME, function()
		if IsValid(bag) then bag:Remove() end
	end)

	return bag
end

function McINV.DropContents(inv, pos, name)
	if not istable(inv) or not isvector(pos) then return nil end

	return spawnBag(cleanInv(inv), pos, name)
end

-- содержимое портфелей в руках - в карманы, иначе пропадёт вместе с оружием
local function collectCarried(ply, into)
	for _, wep in ipairs(ply:GetWeapons()) do
		if not istable(wep.inv) or McINV.IsEmpty(wep.inv) then continue end

		for _, type in ipairs(TYPES) do
			for _, item in ipairs(istable(wep.inv[type]) and wep.inv[type] or {}) do
				local clean = cleanItem(item)
				if clean then pushItem(into[type], clean) end
			end
		end

		wep.inv = McINV.NewInventory()
	end
end

-- карманы на землю; служебное (nodrop) пропадает, keepPhone - первый телефон остаётся
function McINV.DropPockets(ply, pos, name, keepPhone)
	if not IsValid(ply) or not istable(ply.inv) then return nil end

	collectCarried(ply, ply.inv)

	local drop = McINV.NewInventory()
	local keep = McINV.NewInventory()
	local phone = false

	for _, type in ipairs(TYPES) do
		for _, item in ipairs(ply.inv[type]) do
			if keepPhone and not phone and item.phone_type then
				phone = true
				keep[type][#keep[type] + 1] = item
			elseif not item.nodrop then
				drop[type][#drop[type] + 1] = item
			end
		end
	end

	ply.inv = keep
	ply:UpdateInventory()

	return spawnBag(drop, pos, name)
end

--[[---------------------------------------------------------------------------
	Скупщик (NPC dezz): Formater_SV диалога 7 и ответ "DezzSell"
---------------------------------------------------------------------------]]
function McINV.SellStuff(ply, sell)
	if not IsValid(ply) or not istable(ply.inv) then return end

	if not sell then
		local price = McINV.SellPrice(ply)

		if price <= 0 then
			return "Тебе нечего мне предложить.", "", {{"...", "close"}}
		end

		return "За всё, что у тебя есть, дам " .. price .. currency() .. ". Идёт?", "", {
			{"Сойдет", "DezzSell"},
			{"...", "close"},
		}
	end

	if not canUse(ply) or DarkRP.NetDelay(ply, 2) then return 0 end
	if not nearNPC(ply, DEALER_NPC, true) then return 0 end

	-- тот же расчёт, что в McINV.SellPrice: каждый проданный товар снижает цену следующего
	local keep, total, count = {}, 0, 0

	for _, item in ipairs(ply.inv[INV_JUNK]) do
		local v = DarkRP.Junk[item.class]

		if v and v.sell and v.price then
			local price = v.w_price and v.price * (tonumber(item.weight) or 0) or v.price

			total = total + (price - McINV.PriceCut(price, item.class))
			McINV.drugStock[item.class] = (McINV.drugStock[item.class] or 0) + 1
			count = count + 1
		else
			keep[#keep + 1] = item
		end
	end

	if count == 0 then return 0 end

	total = math.Round(total)

	ply.inv[INV_JUNK] = keep

	if total > 0 then
		ply:addMoney(total)
	end

	ply:UpdateInventory()

	DarkRP.log("money", ply, nil, "продал скупщику " .. count .. " шт.", nil, total)

	return total
end

--[[---------------------------------------------------------------------------
	Заказы Дилера Дезза: сдача наркотиков в мусорку с крысой (ваши ответы к 11.3: «Чтоб сдавать
	наркотики. нужно скинуть вес в мусорку где нарисованна мышка» и к шагу 12: «Наркотики сразу
	не пропадают. И тебе еще вроде дезз должен писать что ему надо и только тогда ты сможешь ему
	сдавать, или ему позвонить и на личной встречи ему можешь сдать. придут деньги через минут 15-20.»)
	Мусорки с крысой - 8 моделей models/noirpropper/trash01.mdl у клиента
	(a_config_gmodla/lua/clprops/day_preset1.lua), под каждой - точка GM.Config.DumpCO.
	Персонажу банды (TEAM_GANG: у него номер Дезза, McPhone.ExtraNumbers["9523877"]) с телефоном
	и сигналом Дезз раз в ORDER_EVERY пишет SMS: сколько килограммов какого товара скупщика
	(продаётся на вес) нужно и в какую мусорку - точка GPS в сообщении. На сдачу - ORDER_TIME.
	В зачёт идёт только то, что выбросил сам игрок (владелец предмета). Набран вес - товар лежит
	в мусорке ещё ORDER_PICKUP, потом пропадает, а деньги по цене скупщика (со скидкой спроса,
	McINV.PriceCut) приходят персонажу заказа; его нет на сервере - при выборе этого персонажа.
	Товар унесли раньше - заказ снова ждёт. Личная встреча - звонок Деззу: «Нужно встретиться»,
	скупщик Дезз (mc_simple_npcs, McINV.SellStuff).
---------------------------------------------------------------------------]]
local DEZZ_NAME = "Дилер Дезз"			-- как у автора (McPhone.ExtraNumbers["9523877"], SMS cl_ep1_init.lua)
local ORDER_SMS = "Йоу. Нужно %d кг: «%s». Скинь в мусорку с крысой, точка в сообщении. Жду %d минут."
local ORDER_CHECK = 1					-- проверка, секунд
local ORDER_EVERY = {600, 1200}			-- следующий заказ через, секунд
local ORDER_TIME = 1800					-- на сдачу, секунд
local ORDER_KG = {1, 1}					-- килограммов в заказе (ваш ответ к 13.1: «он просил по 1кг»)
local ORDER_PICKUP = {900, 1200}		-- товар забирают через, секунд (ваш ответ: «через минут 15-20»)
local DUMP_UP = Vector(0, 0, 24)		-- центр проверки над точкой (точка - на земле под мусоркой)
local DUMP_RADIUS = 48					-- юнитов

McINV.DezzOrders = McINV.DezzOrders or {}	-- [SteamID64:персонаж] = заказ
McINV.DezzPending = McINV.DezzPending or {}	-- [SteamID64:персонаж] = деньги, пока персонажа нет

-- товар скупщика на вес: листья, сухие листья, «Беспримесный морфин», «Героин», «Брикет кокаина»,
-- «Пакет метамфетамина», сгущённые листья коки, сфингозин
local function orderGoods()
	local list = {}

	for class, data in pairs(DarkRP.Junk) do
		if data.sell and data.w_price and data.price then list[#list + 1] = class end
	end

	table.sort(list)

	return list
end

-- SteamID64 того, кто выбросил предмет (владелец; вышел с сервера - SteamID у FPP)
local function dropperID(ent)
	if not ent.CPPIGetOwner then return nil end

	local owner, sid = ent:CPPIGetOwner()
	if IsValid(owner) and owner:IsPlayer() then return owner:SteamID64() end
	if isstring(sid) and sid ~= "" then return util.SteamIDTo64(sid) end

	return nil
end

-- товар заказа в его мусорке, выброшенный хозяином заказа, и его вес
local function orderItems(order)
	local found, weight = {}, 0

	for _, ent in ipairs(ents.FindInSphere(order.pos + DUMP_UP, DUMP_RADIUS)) do
		if ent.McINVTaken then continue end

		local type, class = entityItemType(ent)
		if type ~= INV_JUNK or class ~= order.class or groundCheck(ent) then continue end
		if dropperID(ent) ~= order.sid then continue end

		local item = itemFromEntity(ent, type, class)
		if not item then continue end

		local w = math.max(tonumber(item.weight) or 0, 0)
		found[#found + 1] = {ent = ent, weight = w}
		weight = weight + w
	end

	return found, weight
end

-- персонаж заказа на сервере - деньги сразу, иначе при выборе персонажа
local function payOrder(key, total)
	for _, ply in ipairs(player.GetAll()) do
		if ply:getDarkRPVar("character") ~= nil and cacheKey(ply) == key then
			if total > 0 then ply:addMoney(total) end

			return ply
		end
	end

	if total > 0 then
		McINV.DezzPending[key] = (McINV.DezzPending[key] or 0) + total
	end
end

-- Дезз забирает из мусорки заказанный вес по цене скупщика
local function takeOrder(key, order, found)
	local price = DarkRP.Junk[order.class] and DarkRP.Junk[order.class].price or 0
	local total, weight, count = 0, 0, 0

	for _, v in ipairs(found) do
		if weight + EPS >= order.kg then break end

		local cost = price * v.weight
		local cut = McINV.PriceCut(cost, order.class)
		if cut ~= cut then cut = 0 end -- на сервере никого: McINV.PriceCut делит 0 на 0

		total = total + (cost - cut)
		McINV.drugStock[order.class] = (McINV.drugStock[order.class] or 0) + 1
		weight = weight + v.weight
		count = count + 1

		v.ent.McINVTaken = true
		v.ent:Remove()
	end

	total = math.Round(total)

	local ply = payOrder(key, total)

	DarkRP.log("money", ply, nil, "Дезз забрал из мусорки заказ " .. order.name .. ": " .. count .. " шт. [" .. order.class .. "]" .. (IsValid(ply) and "" or ", деньги ждут персонажа"), nil, total)
end

local function newOrder(ply, now)
	local goods = orderGoods()
	local points = GAMEMODE.Config.DumpCO
	if #goods == 0 or not istable(points) or #points == 0 then return end

	local class = goods[math.random(#goods)]
	local pos = points[math.random(#points)]
	if not isvector(pos) then return end

	local kg = math.random(ORDER_KG[1], ORDER_KG[2])

	McINV.DezzOrders[cacheKey(ply)] = {
		sid = ply:SteamID64(),
		name = ply:Name(),
		class = class,
		kg = kg,
		pos = pos,
		expire = now + ORDER_TIME,
	}

	McPhone.SendSMS(DEZZ_NAME, string.format(ORDER_SMS, kg, DarkRP.Junk[class].name, math.floor(ORDER_TIME / 60)), pos, ply)

	DarkRP.log("crime", ply, nil, "получил заказ Дезза: " .. kg .. " кг [" .. class .. "]")
end

-- кому Дезз пишет: персонаж банды с телефоном в карманах
local function orderTarget(ply)
	return ply:Team() == TEAM_GANG and ply:getDarkRPVar("character") ~= nil and McPhone ~= nil and McPhone.SendSMS ~= nil and McINV.GetPhone(ply) ~= nil
end

timer.Create("McINV.DezzOrders", ORDER_CHECK, 0, function()
	local now = CurTime()

	for _, ply in ipairs(player.GetAll()) do
		if not orderTarget(ply) then
			ply.McINVOrderAt = nil
		elseif not McINV.DezzOrders[cacheKey(ply)] then
			if not ply.McINVOrderAt then
				ply.McINVOrderAt = now + math.random(ORDER_EVERY[1], ORDER_EVERY[2])
			elseif now >= ply.McINVOrderAt and ply:Alive() and (tonumber(ply.McPhoneSignal) or 0) >= 1 then
				ply.McINVOrderAt = nil
				newOrder(ply, now)
			end
		end
	end

	for key, order in pairs(McINV.DezzOrders) do
		local found, weight = orderItems(order)

		if weight + EPS < order.kg then
			order.pickup = nil

			if now >= order.expire then McINV.DezzOrders[key] = nil end
		else
			order.pickup = order.pickup or now + math.random(ORDER_PICKUP[1], ORDER_PICKUP[2])

			if now >= order.pickup then
				McINV.DezzOrders[key] = nil
				takeOrder(key, order, found)
			end
		end
	end
end)

-- деньги за заказ, забранный без персонажа; новый персонаж ждёт заказ заново
hook.Add("MCR.CharacterSelected", "McINV.Dezz", function(ply)
	ply.McINVOrderAt = nil

	local key = cacheKey(ply)
	local money = McINV.DezzPending[key]
	if not money then return end

	McINV.DezzPending[key] = nil
	ply:addMoney(money)

	DarkRP.log("money", ply, nil, "получил деньги Дезза за заказ", nil, money)
end)

--[[---------------------------------------------------------------------------
	Перекладывание (клиент: Bool bank, String type, UInt16 id, [Entity контейнера])
---------------------------------------------------------------------------]]
local function readMove()
	local bank = net.ReadBool()
	local type = net.ReadString()
	local id = net.ReadUInt(16)
	local ent = nil

	if not bank then
		ent = net.ReadEntity()
	end

	if not McINV.ttypes[type] then return nil end

	return bank, type, id, ent
end

-- вернёт текст отказа или nil
local function bankStoreCheck(ply, type, item)
	if McINV.BankBlackList[item.class] then return "Это нельзя положить в хранилище" end
	if item.nodrop then return "Этот предмет нельзя положить в хранилище" end

	local fireArms = DarkRP.SingleWep and DarkRP.SingleWep.FireArms or {}

	-- справка F1: чужой огнестрел склад не принимает. Оружие без номера - без ограничения
	-- (ваш ответ к шагу 12: «без ограничения»).
	-- Тяжёлое, Beretta 93R, Glock 18C и АПС (их не зарегистрировать, sv_registers.lua) - только
	-- без номера, свой тоже не годится (ваши слова: «разрешается тяж, но при условии что серийника нет»)
	if type == INV_WEAPON and fireArms[item.class] and istable(item.register) then
		if tostring(item.register.passid) ~= tostring(DarkRP.CharacterID(ply)) then
			return "Это оружие зарегистрировано не на вас"
		end

		if not McINV.CanRegisterGun(item) then
			return "Это оружие склад принимает только без серийного номера"
		end
	end

	if not ply:HaveBankSpace(itemWeight(type, item)) then return "В хранилище нет места" end

	return nil
end

-- из карманов в хранилище или контейнер
net.Receive("McINV.Store", function(_, ply)
	if DarkRP.NetDelay(ply, 0.15) or not canUse(ply) then return end

	local bank, type, id, ent = readMove()
	if bank == nil then return end

	local item = ply.inv[type][id]
	if not item then return end

	if bank then
		local s = bankSession(ply)
		if not s or s.noput or not ply.McINVBankLoaded then return end

		local reason = bankStoreCheck(ply, type, item)

		if reason then
			return
		end

		local copy = table.Copy(item)
		copy.dltime = nil

		if ply:AddItem(type, copy, true) then
			ply:RemoveItem(type, id)
		end

		return
	end

	ent = lootTarget(ply, ent)
	if not ent then return end

	-- карманы задержанного (обыск): забрать можно, подложить нельзя
	if ent:IsPlayer() then
		return
	end

	local reason = canStoreIn(ent, type, item)

	if reason then
		return
	end

	local copy = table.Copy(item)
	markPut(ent, copy, ply)

	if ent:AddItem(type, copy) then
		ply:RemoveItem(type, id)
	end
end)

-- из хранилища или контейнера в карманы
net.Receive("McINV.Take", function(_, ply)
	if DarkRP.NetDelay(ply, 0.15) or not canUse(ply) then return end

	local bank, type, id, ent = readMove()
	if bank == nil then return end

	if bank then
		local s = bankSession(ply)
		if not s or not ply.McINVBankLoaded then return end

		local item = ply.bank_inc[type][id]
		if not item then return end

		-- почтовый ящик: только недавняя доставка, без оружия, патронов и того, что нельзя пересылать
		if s.noput and (type == INV_WEAPON or type == INV_AMMO or McINV.LimitedMailItems[item.class] or not isnumber(item.dltime) or item.dltime < os.time()) then return end

		if not ply:HaveSpace(itemWeight(type, item)) then
			return
		end

		local copy = table.Copy(item)
		copy.dltime = nil

		if ply:AddItem(type, copy) then
			ply:RemoveItem(type, id, true)
		end

		return
	end

	ent = lootTarget(ply, ent)
	if not ent then return end

	local item = istable(ent.inv[type]) and ent.inv[type][id]
	if not item then return end

	if putLocked(ply, item) then
		return
	end

	-- обыск: служебное (nodrop) не изымается
	if ent:IsPlayer() and item.nodrop then
		return
	end

	if not ply:HaveSpace(itemWeight(type, item)) then
		return
	end

	if ply:AddItem(type, item) then
		ent:RemoveItem(type, id)

		if ent:IsPlayer() then
			searchTaken(ply, ent, type, item, "изъял при обыске")
		end
	end
end)

-- из контейнера на землю (из хранилища нельзя - у клиента нет такой кнопки)
net.Receive("McINV.Drop", function(_, ply)
	if DarkRP.NetDelay(ply, 0.15) or not canUse(ply) or ply:InVehicle() then return end

	local bank, type, id, ent = readMove()
	if bank ~= false then return end

	ent = lootTarget(ply, ent)
	if not ent then return end

	local item = istable(ent.inv[type]) and ent.inv[type][id]
	if not item then return end

	if putLocked(ply, item) then
		return
	end

	if item.nodrop or (type == INV_WEAPON and noDropWeapon(item.class)) then
		return
	end

	local ok = canDrop(ply, GROUND_CLASS[type] or item.class)

	if not ok then
		return
	end

	local pos, ang = dropPos(ply)
	if not IsValid(McINV.SpawnItem(type, item, pos, ang, ply)) then return end

	ent:RemoveItem(type, id)

	if ent:IsPlayer() then
		searchTaken(ply, ent, type, item, "выложил на землю при обыске")
	end
end)

--[[---------------------------------------------------------------------------
	Расширение хранилища (меню работника складов, McINV.StorageUpgrade)
---------------------------------------------------------------------------]]
net.Receive("McINV.UpgradeBank", function(_, ply)
	if DarkRP.NetDelay(ply, 1) then return end

	local k = net.ReadUInt(8)
	local plan = McINV.BankPlanes[k]
	if not plan or not ply.McINVBankLoaded or not ply:IsFreeman() then return end

	local cur = validSpace(ply.McINVBankSpace)
	if k <= cur then return end

	if plan.need and cur < plan.need then
		return
	end

	if not nearNPC(ply, BANK_NPC, false) then return end

	local price = math.max(tonumber(plan.price) or 0, 0)
	local credits = plan.donate and math.max(math.floor(tonumber(plan.donate) or 0), 0)

	-- донат-план: за кредиты (¤), которые выдаёт администратор
	if credits then
		if not ply.TakeCredits or not ply:TakeCredits(credits) then
			return
		end

		price = 0
	end

	if price > 0 then
		if not ply:canAfford(price) then
			return
		end

		ply:addMoney(-price)
	end

	ply.McINVBankSpace = k
	ply:SetSelfDarkRPVar("bankspace", k)
	saveBankNow(ply)
	ply:UpdateInventory(true)

	DarkRP.log("money", ply, nil, "расширил хранилище до " .. k .. " кг", nil, credits and (credits .. " ¤") or price)
end)

--[[---------------------------------------------------------------------------
	Админ-меню (msd_ui/madadminmenu.lua): смотреть - право menu, удалять и править - additem
---------------------------------------------------------------------------]]
local function adminCan(ply, perm)
	return IsValid(ply) and sAdmin ~= nil and isfunction(sAdmin.hasPermission) and sAdmin.hasPermission(ply, perm) and true or false
end

local function sendAdminInv(ply, name, who, bank, inv)
	inv = inv or McINV.NewInventory()

	-- net.WriteTable не проверяет размер: оценка по JSON с запасом
	local json = util.TableToJSON(inv) or ""

	if #json > MAX_NET * 0.8 then
		return
	end

	net.Start(name)
		if isentity(who) then
			net.WriteEntity(who)
		else
			net.WriteString(who)
		end

		net.WriteBool(bank)
		net.WriteTable(inv)
	net.Send(ply)
end

net.Receive("McINV.RequestINV", function(_, ply)
	if DarkRP.NetDelay(ply, 0.5) or not adminCan(ply, "menu") then return end

	local target = net.ReadEntity()
	local bank = net.ReadBool()
	if not IsValid(target) or not target:IsPlayer() then return end

	if bank and not target.McINVBankLoaded then
		return
	end

	sendAdminInv(ply, "McINV.RequestINV", target, bank, bank and target.bank_inc or target.inv)
end)

net.Receive("McINV.DeleteItem", function(_, ply)
	if DarkRP.NetDelay(ply, 0.2) or not adminCan(ply, "additem") then return end

	local target = net.ReadEntity()
	local bank = net.ReadBool()
	local type = net.ReadString()
	local id = net.ReadUInt(32)

	if not IsValid(target) or not target:IsPlayer() or not McINV.ttypes[type] then return end

	local item = target:RemoveItem(type, id, bank)
	if not item then return end

	DarkRP.log("admin", ply, target, "удалил предмет " .. McINV.prt(item, type) .. (bank and " из хранилища" or " из карманов"))

	-- номера сдвинулись: меню получает список заново
	sendAdminInv(ply, "McINV.RequestINV", target, bank, bank and target.bank_inc or target.inv)
end)

-- SteamID, SteamID64, [U:1:N] или AccountID (как подсказывает меню) -> SteamID64
local function steam64(str)
	str = string.Trim(tostring(str or ""))
	if str == "" or #str > 64 then return nil end

	if string.match(str, "^STEAM_%d:%d:%d+$") then
		local sid = util.SteamIDTo64(str)
		return sid ~= "0" and sid or nil
	end

	if string.match(str, "^7656119%d%d%d%d%d%d%d%d%d%d$") then return str end

	local acc = tonumber(string.match(str, "^%[U:1:(%d+)%]$") or string.match(str, "^(%d+)$"))
	if not acc or acc <= 0 or acc >= 2 ^ 32 then return nil end

	local sid = util.SteamIDTo64("STEAM_0:" .. (acc % 2) .. ":" .. math.floor(acc / 2))

	return sid ~= "0" and sid or nil
end

-- карманы офлайн-игрока есть только в кэше (KEEP_TIME после выхода); берётся последний персонаж
-- (time - когда карманы ушли в кэш: при выходе или при смене персонажа)
local function cachedPockets(sid64)
	local best

	for key, v in pairs(McINV.Cache) do
		if string.StartWith(key, sid64 .. ":") and v.expire > CurTime() and (not best or (v.time or 0) > (best.time or 0)) then
			best = v
		end
	end

	return best
end

net.Receive("McINV.RequestINVOffline", function(_, ply)
	if DarkRP.NetDelay(ply, 1) or not adminCan(ply, "menu") then return end

	local sid64 = steam64(net.ReadString())
	local bank = net.ReadBool()

	if not sid64 then
		return
	end

	local online = player.GetBySteamID64(sid64)

	if IsValid(online) then
		if bank and not online.McINVBankLoaded then return end

		sendAdminInv(ply, "McINV.RequestINV", online, bank, bank and online.bank_inc or online.inv)
		return
	end

	if not bank then
		local cached = cachedPockets(sid64)

		if not cached then
			return
		end

		sendAdminInv(ply, "McINV.RequestINVOffline", sid64, false, cached.inv)
		return
	end

	if not DarkRP.DBReady then return end

	MySQLite.query("SELECT data FROM darkrp_bank WHERE uid = " .. sid64, function(rows)
		if not IsValid(ply) then return end

		local row = istable(rows) and rows[1]
		local data = row and isstring(row.data) and util.JSONToTable(row.data)

		sendAdminInv(ply, "McINV.RequestINVOffline", sid64, true, cleanInv(data))
	end, dbError)
end)

-- меню присылает весь инвентарь целиком (с правками администратора)
net.Receive("McINV.DeleteItemOffline", function(_, ply)
	if DarkRP.NetDelay(ply, 1) or not adminCan(ply, "additem") then return end

	local sid64 = steam64(net.ReadString())
	local bank = net.ReadBool()
	local len = net.ReadInt(32)

	if not sid64 or len <= 0 or len > MAX_NET then return end

	local raw = util.Decompress(net.ReadData(len), MAX_DECOMPRESS)
	local data = raw and util.JSONToTable(raw)
	if not istable(data) then return end

	local inv = cleanInv(data)
	local online = player.GetBySteamID64(sid64)

	if IsValid(online) then
		if bank then
			if not online.McINVBankLoaded then return end

			online.bank_inc = inv
			saveBankNow(online)
		else
			online.inv = inv
		end

		online:UpdateInventory(bank)
	elseif bank then
		if not DarkRP.DBReady then return end

		MySQLite.query("SELECT space FROM darkrp_bank WHERE uid = " .. sid64, function(rows)
			local row = istable(rows) and rows[1]

			MySQLite.query(string.format("REPLACE INTO darkrp_bank(uid, space, data) VALUES(%s, %d, %s)",
				sid64, validSpace(row and row.space), MySQLite.SQLStr(util.TableToJSON(inv))
			), nil, dbError)
		end, dbError)
	else
		local cached = cachedPockets(sid64)
		if not cached then return end

		cached.inv = inv
	end

	DarkRP.log("admin", ply, IsValid(online) and online or nil, "изменил " .. (bank and "хранилище" or "карманы") .. " игрока " .. sid64)
end)

--[[---------------------------------------------------------------------------
	Карманы (F4): Inventory.Drop тип номер - на землю, "1" - в руки, " " 1 - стопкой
---------------------------------------------------------------------------]]
-- вернёт энтити; второй результат - дальше выбрасывать нельзя (лимит)
local function dropOne(ply, type, id, i)
	local item = ply.inv[type][id]
	if not item then return nil end

	if type == INV_WEAPON and noDropWeapon(item.class) then
		return nil
	end

	local ok = canDrop(ply, GROUND_CLASS[type] or item.class)

	if not ok then
		return nil, true
	end

	local pos, ang = dropPos(ply, i)
	local ent = McINV.SpawnItem(type, item, pos, ang, ply)
	if not IsValid(ent) then return nil end

	ply:RemoveItem(type, id)

	if type == INV_WEAPON then
		DarkRP.log("other", ply, nil, "выбросил оружие" .. McINV.prt(item), nil, nil, ent)
	end

	return ent
end

-- оружие из карманов в руки
local function equipWeapon(ply, id)
	local item = ply.inv[INV_WEAPON][id]
	if not item then return end

	local class = item.class

	if ply:HasWeapon(class) then
		return
	end

	if not weapons.GetStored(class) then
		return
	end

	local wep = ply:Give(class, true)

	if not IsValid(wep) or wep:GetOwner() ~= ply then
		if IsValid(wep) and not IsValid(wep:GetOwner()) then wep:Remove() end

		return
	end

	ply:RemoveItem(INV_WEAPON, id)

	if isnumber(item.clip1) then
		wep:SetClip1(math.max(math.floor(item.clip1), 0))
	else
		-- новый из магазина (clip1 ещё не сохранён): заряды вместо патронов (отмычка) -
		-- полные явно. После Give(class, true) ("без патронов") обойма не гарантирована,
		-- а отмычка с 0 зарядов ломается при первом нажатии
		local primary = wep.Primary
		local size = istable(primary) and tonumber(primary.ClipSize) or -1

		if size > 0 and (primary.Ammo == "" or primary.Ammo == "none") then
			wep:SetClip1(math.Clamp(math.floor(tonumber(primary.DefaultClip) or size), 0, size))
		end
	end

	if isnumber(item.clip2) then wep:SetClip2(math.max(math.floor(item.clip2), 0)) end

	wep.att_saved = istable(item.att_saved) and table.Copy(item.att_saved) or nil
	wep.gunstate = item.gunstate
	DarkRP.CopyGunDate(item, wep)

	ply:SelectWeapon(class)
	DarkRP.log("other", ply, nil, "взял в руки оружие" .. McINV.prt(item))
end

-- остальное в руки: на землю перед игроком и сразу в ключи (перенос)
local function carryItem(ply, type, id)
	local keys = ply:GetWeapon("keys")
	if not IsValid(keys) or not isfunction(keys.AllowPickup) then return end

	local ent = dropOne(ply, type, id)
	if not IsValid(ent) then return end

	ply:SelectWeapon("keys")

	timer.Simple(0.1, function()
		if not IsValid(ply) or not IsValid(ent) or not IsValid(keys) or ply:GetActiveWeapon() ~= keys then return end
		if IsValid(keys.EntHolding) or not keys:AllowPickup(ent) then return end

		keys:Pickup(ent)
	end)
end

-- стопка: все предметы с тем же названием, как их группирует F4
local function dropStack(ply, type, id)
	local list = ply.inv[type]
	local first = list[id]

	if type == INV_WEAPON or not istable(first.dt) or not first.name then
		dropOne(ply, type, id)
		return
	end

	local ids = {}

	-- с конца: номера оставшихся не сдвигаются
	for i = #list, 1, -1 do
		local v = list[i]

		if v.name == first.name and istable(v.dt) and not v.nodrop then
			ids[#ids + 1] = i
			if #ids >= MAX_STACK then break end
		end
	end

	for n, i in ipairs(ids) do
		local _, stop = dropOne(ply, type, i, n)
		if stop then break end
	end
end

concommand.Add("Inventory.Drop", function(ply, _, args)
	if not IsValid(ply) then return end

	local type = args[1]

	-- действия других модулей (полиция: Inventory.Drop nypd <userid>)
	if isstring(type) and not McINV.ttypes[type] then
		local handler = McINV.DropHandlers[type]

		if isfunction(handler) and not DarkRP.NetDelay(ply, 0.5) then
			handler(ply, args[2] or "")
		end

		return
	end

	if DarkRP.NetDelay(ply, 0.2) or not canUse(ply) or ply:InVehicle() then return end
	if not McINV.ttypes[type] then return end

	local id = tonumber(args[2])
	if not id then return end

	id = math.floor(id)

	local item = ply.inv[type][id]
	if not item then return end

	if args[3] == "1" then
		if type == INV_WEAPON then
			equipWeapon(ply, id)
		elseif type ~= INV_AMMO then
			if item.nodrop then
				return
			end

			carryItem(ply, type, id)
		end

		return
	end

	if item.nodrop then
		return
	end

	if args[4] == "1" then
		dropStack(ply, type, id)
	else
		dropOne(ply, type, id)
	end
end)

-- дозарядить магазин: сначала из коробок патронов (ammo_box), потом из других магазинов того же класса
concommand.Add("Inventory.SwapMag", function(ply, _, args)
	if not IsValid(ply) or DarkRP.NetDelay(ply, 0.5) or not canUse(ply) then return end

	local class, id = args[1], tonumber(args[2])
	local list = ply.inv[INV_AMMO]
	local mag = id and list[math.floor(id)]
	local data = isstring(class) and DarkRP.Ammo[class]

	if not mag or mag.class ~= class or not data or not data.ammo or not istable(mag.dt) then return end

	mag.dt.Ammo = math.max(tonumber(mag.dt.Ammo) or 0, 0)

	local need = data.ammo - mag.dt.Ammo
	if need <= 0 then return end

	local changed = false

	local function drain(match, removeEmpty)
		for i = #list, 1, -1 do
			if need <= 0 then return end

			local v = list[i]
			local ammo = v ~= mag and match(v) and (not v.nodrop or mag.nodrop) and istable(v.dt) and tonumber(v.dt.Ammo) or 0

			if ammo > 0 then
				local take = math.min(ammo, need)

				v.dt.Ammo = ammo - take
				mag.dt.Ammo = mag.dt.Ammo + take
				need = need - take
				changed = true

				if removeEmpty and v.dt.Ammo <= 0 then
					table.remove(list, i)
				else
					ammoWeight(v)
				end
			end
		end
	end

	if data.ammo_box then
		drain(function(v) return v.class == data.ammo_box end, true)
	end

	drain(function(v) return v.class == class end, false)

	if not changed then return end

	ammoWeight(mag)
	ply:UpdateInventory()
end)

-- упаковать свою станцию (ящик, сейф) обратно в инвентарь (контекстное меню)
concommand.Add("Inventory.Pack", function(ply)
	if not IsValid(ply) or DarkRP.NetDelay(ply, 1) or not canUse(ply) or ply:InVehicle() then return end

	local ent = ply:GetEyeTrace().Entity
	if not IsValid(ent) or not ent.CanPack or ent.McINVTaken or ent.McINVBusy then return end
	if ent:GetPos():DistToSqr(ply:GetPos()) >= PACK_RANGE then return end

	local class = ent:GetClass()
	local station = DarkRP.Stations[class]
	if not station then return end

	if ownerOf(ent) ~= ply then
		return
	end

	if istable(ent.inv) and not McINV.IsEmpty(ent.inv) then
		return
	end

	if not ply:HaveSpace(station.weight or 1) then
		return
	end

	if not McINV.AddCustomItem(ply, "Stations", class, station) then return end

	ent.McINVTaken = true
	ent:Remove()

	DarkRP.log("property", ply, nil, "запаковал " .. (station.name or class))
end)

--[[---------------------------------------------------------------------------
	Жизненный цикл
---------------------------------------------------------------------------]]
local function givePhone(ply)
	if McINV.GetPhone(ply) then return end
	if not McPhone or not McPhone.Exp or not istable(McPhone.Exp.Themes) or next(McPhone.Exp.Themes) == nil then return end

	McINV.AddPhone(ply)
end

hook.Add("PlayerInitialSpawn", "McINV", function(ply)
	ply.inv = McINV.NewInventory()
	ply.bank_inc = McINV.NewInventory()
	ply.McINVBankSpace = BANK_SPACE

	-- InvChecker (UpdateInventory) сравнивает вес с invspace
	ply:SetDarkRPVar("invspace", DEFAULT_SPACE)
	ply:SetSelfDarkRPVar("bankspace", BANK_SPACE)
end)

hook.Add("DarkRPPlayerDataLoaded", "McINV", loadBank)

-- клиент готов принимать данные
hook.Add("DarkRP.PlayerLoaded", "McINV", function(ply)
	ply:UpdateInventory(true)
end)

-- выбран персонаж: карманы из кэша (вышел меньше KEEP_TIME назад) или пустые с телефоном
hook.Add("MCR.CharacterSelected", "McINV", function(ply)
	closeSessions(ply)

	local key = cacheKey(ply)
	local cached = McINV.Cache[key]
	McINV.Cache[key] = nil

	if cached and cached.expire > CurTime() then
		ply.inv = cleanInv(cached.inv)
	else
		ply.inv = McINV.NewInventory()
		givePhone(ply)
	end

	ply:UpdateInventory(true)
end)

-- смена персонажа: предметы не исчезают (ваш ответ к 11.3: «При смени персонажа никакие предметы
-- не исчезают»). Вещи на карте остаются у игрока, карманы с оружием из рук ждут этого персонажа
-- (MCR.CharacterSelected), пока игрок в сети, после выхода - KEEP_TIME. Служебное (nodrop)
-- пропадает, как при смерти
hook.Add("MCR.CharacterReset", "McINV", function(ply)
	closeSessions(ply)

	if istable(ply.inv) and not ply:IsBot() then
		-- содержимое портфелей - в карманы: портфели снимаются вместе с оружием
		collectCarried(ply, ply.inv)

		-- оружие в руках - в карманы даже сверх веса: StripWeapons при смене снял бы его насовсем
		for _, wep in ipairs(ply:GetWeapons()) do
			local class = wep:GetClass()

			if DarkRP.Weapons[class] and not wep.GivenByTeam and not wep.MQS_weapon and not noDropWeapon(class) then
				if McINV.AddCustomItem(ply, "Weapons", class, DarkRP.WeaponItemData(wep)) then
					wep.Droping = true
					ply:StripWeapon(class)
				end
			end
		end

		for _, type in ipairs(TYPES) do
			local keep = {}

			for _, item in ipairs(ply.inv[type]) do
				if not item.nodrop then keep[#keep + 1] = item end
			end

			ply.inv[type] = keep
		end

		McINV.Cache[cacheKey(ply)] = {inv = ply.inv, expire = math.huge, time = CurTime()}
	end

	ply.inv = McINV.NewInventory()
	ply.McINVFixed = nil

	ply:UpdateInventory()
end)

hook.Add("PlayerDeath", "McINV", function(ply)
	closeSessions(ply)

	if ply:getDarkRPVar("character") == nil then return end

	McINV.DropPockets(ply, ply:GetPos() + Vector(0, 0, 16), "Вещи", true)
end)

hook.Add("PlayerSilentDeath", "McINV", closeSessions)

hook.Add("PlayerDisconnected", "McINV", function(ply)
	saveBankNow(ply)
	closeSessions(ply)

	-- карманы других персонажей (смена персонажа) теперь тоже ждут KEEP_TIME
	local prefix = tostring(ply:SteamID64()) .. ":"

	for key, v in pairs(McINV.Cache) do
		if v.expire == math.huge and string.StartWith(key, prefix) then
			v.expire = CurTime() + KEEP_TIME
		end
	end

	if ply:IsBot() or ply:getDarkRPVar("character") == nil or not istable(ply.inv) then return end

	-- выход в бою или в наручниках: вещи остаются на месте
	if (ply.LastDamage and ply.LastDamage + COMBAT_TIME > CurTime()) or ply:getDarkRPVar("HandCuffed") then
		McINV.DropPockets(ply, ply:GetPos() + Vector(0, 0, 16), "Вещи", false)
		return
	end

	collectCarried(ply, ply.inv)

	-- оружие в руках - в карманы, как "Убрать оружие" (если хватает места)
	for _, wep in ipairs(ply:GetWeapons()) do
		local class = wep:GetClass()

		if DarkRP.Weapons[class] and not wep.GivenByTeam and not wep.MQS_weapon and not noDropWeapon(class) then
			DarkRP.DropHeldWeapon(ply, wep)
		end
	end

	McINV.Cache[cacheKey(ply)] = {inv = ply.inv, expire = CurTime() + KEEP_TIME, time = CurTime()}
end)

hook.Add("ShutDown", "McINV", function()
	McINV.NoDrops = true

	for _, ply in ipairs(player.GetHumans()) do
		saveBankNow(ply)
	end
end)

-- очистка карты: удаляемые портфели не должны рассыпаться пакетами
hook.Add("PreCleanupMap", "McINV", function()
	McINV.NoDrops = true
end)

hook.Add("PostCleanupMap", "McINV", function()
	McINV.NoDrops = nil
end)

hook.Add("EntityRemoved", "McINV", function(ent)
	McINV.CloseViewers(ent)

	-- лимит станций (оружие deployment) освобождается
	if ent.dsid and deploy_limit[ent.dsid] then
		local class = ent:GetClass()
		local count = deploy_limit[ent.dsid][class]

		if count then
			deploy_limit[ent.dsid][class] = count > 1 and count - 1 or nil
		end
	end

	local owner = ent.McINVDropper

	if IsValid(owner) and owner.McINVDrops then
		owner.McINVDrops[ent] = nil
	end
end)

hook.Add("DarkRPVarChanged", "McINV", function(ply, var)
	if var == "tatoo" and IsValid(ply) and ply:IsPlayer() then
		updateSpace(ply)
	end
end)

timer.Create("McINV.Cache", 60, 0, function()
	local now = CurTime()

	for key, v in pairs(McINV.Cache) do
		if v.expire <= now then McINV.Cache[key] = nil end
	end
end)

-- спрос у скупщика восстанавливается: -1 к каждому товару раз в 5 минут
timer.Create("McINV.DrugStock", 300, 0, function()
	for class, count in pairs(McINV.drugStock) do
		McINV.drugStock[class] = count > 1 and count - 1 or nil
	end
end)
