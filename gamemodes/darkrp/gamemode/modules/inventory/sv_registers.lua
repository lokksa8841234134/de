--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Кассы, экран регистрации оружия и кран механика - сервер

	Кассы - станции, ставятся из посылки, как сейф: register_cook (повар,
	еда), register_misc (еда, хлам, предметы), register_gun (оружейный
	шкаф: оружие и патроны). Что продаётся - ENT.SellTypes кассы.
	Сверху - экран, кассовый аппарат (register_screen, McINV.AttachScreen).
	Владелец (McINV.OwnerOf: CPPI или owning_ent):
	  E по кассе - её содержимое (McINV.Loot): положить и забрать товар;
	  E по экрану - "Управление": название магазина и наценка до 200 %;
	  у оружейного шкафа E по экрану - "Регистрация оружия",
	  Shift+E - "Управление".
	Остальные: E по кассе или экрану - меню покупки (McINV.StoreUIEnt на
	  клиенте). Оружейный шкаф, открытый ключами владельца или отмычкой
	  (IsUnLocked), E по самому шкафу открывает как контейнер - любому.
	Цена - цена каталога с налогом магазинов (McINV.Tax) плюс наценка
	(CustomPrice), округлённая до целого. Налог - в казну района
	(Slawer.Mayor:AddFunds), остальное - владельцу. Владелец должен быть
	на сервере, сам у себя не покупает; noresell в каталоге - не продаётся.

	Регистрация оружия (экран оружейного шкафа, только оружейник): ствол из
	шкафа записывается на персонажа игрока с введённым паспортом (игрок на
	сервере), пошлина McINV.WeaponTax - в казну. Отказ, молча:
	номер записан на другого (перерегистрирует только тот, на кого
	записан номер), номер спилен (register = false), тяжёлое оружие
	(RifleWeps), Beretta 93R и Glock 18C (класс mwb_93r и обвесы, которые
	делают из Beretta M9 - 93R, из Glock 19 - 18C), АПС (пистолет
	Макарова с автоматическим стволом attachment_vm_pi_mike_barauto) -
	их номер навсегда на оружейнике (docs/step12_weapons_plan.md).
	Остальной обвес из GM.Config.FFL (глушители, автоматический УСМ
	Tec-9, ствол ПБ) регистрации не мешает - такое оружие просто
	нелегальное. Ствол без номера получает новый (реестр -
	police/sv_gunreg.lua).

	Кран механика (workstation_car): E по крану или экрану - "Заказ
	автозапчастей" (только механик). Аккумулятор - по цене каталога;
	кузов, двигатель и стёкла - для машины в CarPartScanRange от крана:
	доля цены машины (CarPartMult, McCD.Cars), без цены - по каталогу.
	Запчасть появляется у крана со стороны механика; carclass - для какой
	машины (её ищет ремкомплект, simp_phys_lmao/weapon_simrepair.lua).

	Сеть:
	C->S McINV.BuyFromEnt  - Entity касса, String тип, Int(16) номер товара
	S->C McINV.BuyFromEnt  - Entity касса, Int(32) длина, Data - товары
	C->S McINV.RegisterNer - UInt(2) 1: Entity касса, String название,
							 Float наценка (0.5 - 50 %);
							 UInt(2) 2: Entity шкаф, UInt(10) номер оружия
							 в шкафу, String паспорт
	S->C McINV.RegisterNer - Entity касса или кран, Entity экран, UInt(2):
							 0 управление, 1 регистрация (Int(32) длина,
							 Data - содержимое шкафа), 2 запчасти
	C->S CarParts.Order    - Entity кран, String запчасть, Entity машина
	Товары у покупателей с открытым меню обновляются McINV.UpdateStorage
	"none", после смены наценки меню у них закрывается ("remove").
---------------------------------------------------------------------------]]

util.AddNetworkString("McINV.BuyFromEnt")
util.AddNetworkString("McINV.RegisterNer")
util.AddNetworkString("CarParts.Order")

local RANGE = 300 * 300				-- меню кассы клиент закрывает дальше 300 юнитов
local SCREEN_MODEL = "models/props_c17/cashregister01a.mdl"
local DEFAULT_MODEL = "models/props_wasteland/controlroom_storagecloset001a.mdl"
local DEFAULT_SPACE = 30			-- вместимость кассы, кг
local MAX_MARKUP = 2				-- наценка до 200 %
local MAX_NAME = 20					-- символов в названии магазина, как у клиента
local MAX_NET = 60000				-- сжатые данные в одном сообщении
local MAX_ID = 32
local CAR_SCAN = 1500				-- CarPartScanRange по умолчанию, как у клиента
local CAR_CLASS = "gmod_sent_vehicle_fphysics_base"
local PART_GAP = 25					-- запчасть - на столько дальше края крана

-- запчасти крана; true - цена каталога, машина не нужна
local CAR_PARTS = {
	parts_hull = false,
	parts_engine = false,
	parts_glass = false,
	parts_battery = true,
}

local function finite(v)
	return isnumber(v) and v == v and v ~= math.huge and v ~= -math.huge
end

local function near(ply, ent)
	return ent:GetPos():DistToSqr(ply:GetPos()) <= RANGE
end

local function isRegister(ent)
	return IsValid(ent) and ent.McINVRegister == true and istable(ent.inv)
end

local function markupOf(base)
	local markup = tonumber(base:GetCustomPrice())

	return finite(markup) and math.Clamp(markup, 0, MAX_MARKUP) or 0
end

-- товары для покупателя: содержимое кассы без того, что она не продаёт
local function shopData(base)
	local inv = {}

	for type, list in pairs(base.inv) do
		inv[type] = base.SellTypes and base.SellTypes[type] and list or {}
	end

	return DarkRP.TableCompress(inv)
end

local function canShop(ply, base)
	return IsValid(ply) and ply:IsPlayer() and ply:IsFreeman() and ply:getDarkRPVar("character") ~= nil and istable(ply.inv)
		and isRegister(base) and not base:IsOnFire() and near(ply, base)
end

local function openShop(base, ply)
	if not canShop(ply, base) then return end

	local data, len = shopData(base)
	if len > MAX_NET then return end

	ply.McINVShop = base
	base.McINVBuyers = base.McINVBuyers or {}
	base.McINVBuyers[ply] = true

	net.Start("McINV.BuyFromEnt")
		net.WriteEntity(base)
		net.WriteInt(len, 32)
		net.WriteData(data, len)
	net.Send(ply)
end

-- закрыть меню покупки у всех покупателей кассы
local function closeBuyers(base)
	local targets = {}

	for ply in pairs(base.McINVBuyers or {}) do
		if IsValid(ply) and ply.McINVShop == base then
			ply.McINVShop = nil
			targets[#targets + 1] = ply
		end
	end

	base.McINVBuyers = {}

	if #targets == 0 then return end

	net.Start("McINV.UpdateStorage")
		net.WriteEntity(base)
		net.WriteString("remove")
	net.Send(targets)
end

-- меню экрана: 0 управление, 1 регистрация оружия, 2 запчасти
local function openMenu(base, ply, mode)
	local screen = base:Getscreen()
	local data, len

	if mode == 1 then
		data, len = DarkRP.TableCompress(base.inv)
		if len > MAX_NET then return end
	end

	net.Start("McINV.RegisterNer")
		net.WriteEntity(base)
		net.WriteEntity(IsValid(screen) and screen or base)
		net.WriteUInt(mode, 2)

		if mode == 1 then
			net.WriteInt(len, 32)
			net.WriteData(data, len)
		end
	net.Send(ply)
end

--[[---------------------------------------------------------------------------
	Касса и экран
---------------------------------------------------------------------------]]
-- экран (кассовый аппарат) на переднем верхнем краю кассы или крана
function McINV.AttachScreen(base)
	if IsValid(base:Getscreen()) then return base:Getscreen() end

	local screen = ents.Create("register_screen")
	if not IsValid(screen) then return end

	local maxs = base:OBBMaxs()

	screen:SetModel(SCREEN_MODEL)
	screen:SetPos(base:LocalToWorld(Vector(maxs.x - 8, 0, maxs.z)))
	screen:SetAngles(base:GetAngles())
	screen:Spawn()
	screen:SetParent(base)
	screen:Setbase_ent(base)

	base:Setscreen(screen)

	return screen
end

-- E по кассе или крану (screen = false) и по их экрану (screen = true)
function McINV.UseRegister(base, ply, screen)
	if not IsValid(base) or not IsValid(ply) or not ply:IsFreeman() or not near(ply, base) then return end

	if base:GetClass() == "workstation_car" then
		if ply:Team() == TEAM_CAR then openMenu(base, ply, 2) end
		return
	end

	if not isRegister(base) then return end

	if McINV.OwnerOf(base) == ply then
		if not screen then
			McINV.Loot(base, ply, false)
		elseif base:GetClass() == "register_gun" and not ply:KeyDown(IN_SPEED) then
			openMenu(base, ply, 1)
		else
			openMenu(base, ply, 0)
		end

		return
	end

	if base.IsUnLocked and not screen then
		McINV.Loot(base, ply, false)
		return
	end

	openShop(base, ply)
end

-- общий код касс (register_cook, register_gun, register_misc - их init.lua)
function McINV.SetupRegister(ENT)
	-- содержимое открывает только владелец (McINV.CanAccess), открытый шкаф - любой
	ENT.McINVOwnerOnly = true
	ENT.McINVRegister = true

	function ENT:Initialize()
		local data = DarkRP.Stations[self:GetClass()]
		local model = self:GetModel()

		if not model or model == "" then
			self:SetModel(data and data.model or DEFAULT_MODEL)
		end

		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)

		local phys = self:GetPhysicsObject()

		if IsValid(phys) then
			phys:Wake()
		end

		if self:GetSpace() <= 0 then self:SetSpace(DEFAULT_SPACE) end
		if self:GetStorageName() == "" then self:SetStorageName(data and data.name or self.PrintName or "Касса") end

		self:SetCustomPrice(markupOf(self))

		self.inv = self.inv or McINV.NewInventory()
		self.McINVBuyers = {}

		McINV.AttachScreen(self)
	end

	function ENT:Use(ply)
		if not IsValid(ply) or not ply:IsPlayer() then return end
		if DarkRP.UseDelay(ply, 1) then return end

		McINV.UseRegister(self, ply, false)
	end

	function ENT:OnRemove()
		local screen = self:Getscreen()
		if IsValid(screen) then screen:Remove() end

		closeBuyers(self)
	end

	-- товар поменялся (modules/inventory/sv_init.lua, containerChanged): новый список покупателям
	function ENT:OnInventoryChanged()
		local targets = {}

		for ply in pairs(self.McINVBuyers or {}) do
			if not IsValid(ply) or ply.McINVShop ~= self then
				self.McINVBuyers[ply] = nil
			elseif near(ply, self) then
				targets[#targets + 1] = ply
			end
		end

		if #targets == 0 then return end

		local data, len = shopData(self)
		if len > MAX_NET then return end

		net.Start("McINV.UpdateStorage")
			net.WriteEntity(self)
			net.WriteString("none")
			net.WriteUInt(len, 32)
			net.WriteData(data, len)
		net.Send(targets)
	end
end

--[[---------------------------------------------------------------------------
	Покупка
---------------------------------------------------------------------------]]
net.Receive("McINV.BuyFromEnt", function(_, ply)
	if DarkRP.NetDelay(ply, 0.3) then return end

	local base = net.ReadEntity()
	local type = net.ReadString()
	local id = net.ReadInt(16)

	if not canShop(ply, base) or ply.McINVShop ~= base then return end
	if not base.SellTypes or not base.SellTypes[type] or not istable(base.inv[type]) then return end

	local item = base.inv[type][id]
	if not istable(item) then return end

	local data = McINV.GetItem(type, item.class)
	if not data or data.noresell then return end

	local owner = McINV.OwnerOf(base)
	if not IsValid(owner) or owner == ply then return end

	local price, tax = McINV.Tax(tonumber(data.price) or 0, type, item)
	local total = math.Round(math.max(price + price * markupOf(base), 1))
	tax = math.Clamp(math.Round(tonumber(tax) or 0), 0, total)

	if not ply:HaveSpace(McINV.GetWeight(item, type, item.class)) or not ply:canAfford(total) then return end

	local taken = base:RemoveItem(type, id)
	if not taken then return end

	if not ply:AddItem(type, taken) then
		base:AddItem(type, taken)
		return
	end

	ply:addMoney(-total)
	Slawer.Mayor:AddFunds(tax)
	owner:addMoney(total - tax)

	DarkRP.log("money", ply, owner, "купил в кассе " .. McINV.prt(taken, type) .. " за $" .. total, nil, tax, base)
end)

--[[---------------------------------------------------------------------------
	Экран: управление и регистрация оружия
---------------------------------------------------------------------------]]
-- название магазина: до MAX_NAME символов, без управляющих; пусто - nil
local function cleanName(name)
	if not isstring(name) or not utf8.len(name) then return nil end

	name = string.Trim((string.gsub(name, "%c", "")))
	if name == "" then return nil end

	if utf8.len(name) > MAX_NAME then name = utf8.sub(name, 1, MAX_NAME) end

	return name
end

-- обвесы из GM.Config.FFL, после которых пистолет - Beretta 93R или Glock 18C
-- или АПС (автоматический ствол у пистолета Макарова)
local AUTO_PISTOL_ATT = {
	attachment_vm_pi_mike9_barauto_diamatti = true,
	att_vm_pi_golf18_slide = true,
	attachment_vm_pi_mike_barauto = true,
}

-- можно записать на другого: не тяжёлое, не Beretta 93R, не Glock 18C и не АПС с автоматическим стволом
local function canRegisterGun(item)
	if DarkRP.SingleWep.RifleWeps[item.class] or item.class == "mwb_93r" then return false end

	for _, att in pairs(istable(item.att_saved) and item.att_saved or {}) do
		if istable(att) and att.m_Index ~= nil and AUTO_PISTOL_ATT[att.m_Index] then return false end
	end

	return true
end

-- склад (sv_init.lua, шаг 12): что не зарегистрировать, он принимает только без номера
McINV.CanRegisterGun = canRegisterGun

local function saveRegister(ply, base, name, markup)
	if not isRegister(base) or McINV.OwnerOf(base) ~= ply or not near(ply, base) then return end
	if not finite(markup) then return end

	local station = DarkRP.Stations[base:GetClass()]

	base:SetStorageName(cleanName(name) or (station and station.name) or base.PrintName or "Касса")
	base:SetCustomPrice(math.Round(math.Clamp(markup, 0, MAX_MARKUP), 2))

	-- у покупателей в меню старые цены
	closeBuyers(base)
end

local function registerGun(ply, base, id, passid)
	if not isRegister(base) or base:GetClass() ~= "register_gun" then return end
	if ply:Team() ~= TEAM_GUN or McINV.OwnerOf(base) ~= ply or not near(ply, base) then return end

	local item = istable(base.inv[INV_WEAPON]) and base.inv[INV_WEAPON][id]
	if not istable(item) or not DarkRP.SingleWep.FireArms[item.class] then return end

	-- спиленный номер регистрацией не "отмывается"
	if item.register == false then return end
	if istable(item.register) and tostring(item.register.passid) ~= tostring(DarkRP.CharacterID(ply)) then return end
	if not canRegisterGun(item) then return end

	local target = DarkRP.findBYPassID(string.Trim(string.sub(passid, 1, MAX_ID)))
	if not IsValid(target) or target:getDarkRPVar("character") == nil then return end

	local fee = math.max(math.Round(tonumber(McINV.WeaponTax(item)) or 0), 0)
	if not ply:canAfford(fee) then return end

	local passTo = tostring(DarkRP.CharacterID(target))
	local serial = istable(item.register) and item.register.id

	if serial ~= nil and DarkRP.GunRegister(serial, item.class, passTo) then
		item.register = {id = tostring(serial), passid = passTo}
	else
		item.register = {id = DarkRP.NewGunSerial(item.class, passTo), passid = passTo}
	end

	ply:addMoney(-fee)
	Slawer.Mayor:AddFunds(fee)

	McINV.ContainerChanged(base)

	DarkRP.log("property", ply, target, "зарегистрировал оружие " .. McINV.prt(item, INV_WEAPON), nil, fee, base)
end

net.Receive("McINV.RegisterNer", function(_, ply)
	if DarkRP.NetDelay(ply, 0.5) then return end
	if not IsValid(ply) or not ply:IsFreeman() then return end

	local mode = net.ReadUInt(2)

	if mode == 1 then
		local base = net.ReadEntity()
		local name = net.ReadString()
		local markup = net.ReadFloat()

		saveRegister(ply, base, name, markup)
	elseif mode == 2 then
		local base = net.ReadEntity()
		local id = net.ReadUInt(10)
		local passid = net.ReadString()

		registerGun(ply, base, id, passid)
	end
end)

--[[---------------------------------------------------------------------------
	Кран механика: заказ запчастей
---------------------------------------------------------------------------]]
-- у крана со стороны механика, за краем крана
local function partPos(base, ply)
	local maxs = base:OBBMaxs()
	local dir = ply:GetPos() - base:GetPos()
	dir.z = 0

	if dir:LengthSqr() < 1 then dir = base:GetForward() end
	dir:Normalize()

	return base:GetPos() + dir * (math.max(maxs.x, maxs.y) + PART_GAP) + Vector(0, 0, 16)
end

net.Receive("CarParts.Order", function(_, ply)
	if DarkRP.NetDelay(ply, 1) then return end

	local base = net.ReadEntity()
	local class = net.ReadString()
	local car = net.ReadEntity()

	if not IsValid(ply) or not ply:IsFreeman() or ply:Team() ~= TEAM_CAR then return end
	if not IsValid(base) or base:GetClass() ~= "workstation_car" or not near(ply, base) then return end

	local data = CAR_PARTS[class] ~= nil and DarkRP.Junk[class]
	if not data then return end

	local raw, carclass

	if CAR_PARTS[class] then
		raw = data.price
	else
		local mult = base.CarPartMult and tonumber(base.CarPartMult[class])
		if not mult or not IsValid(car) or car:GetClass() ~= CAR_CLASS then return end

		local scan = tonumber(base.CarPartScanRange) or CAR_SCAN
		if car:GetPos():DistToSqr(base:GetPos()) > scan * scan then return end

		carclass = isfunction(car.GetSpawn_List) and car:GetSpawn_List() or nil
		local cd = carclass and McCD and McCD.Cars and McCD.Cars[carclass]
		if not istable(cd) then return end

		local carprice = tonumber(cd.price)
		if carprice and cd.donate then carprice = carprice * 150 end

		raw = carprice and math.Round(carprice * mult) or data.price
	end

	local price, tax = McINV.Tax(tonumber(raw) or 0)
	price = math.Round(price)
	if price <= 0 or not ply:canAfford(price) then return end

	local ent = DarkRP.CreateJunk(class, partPos(base, ply), base:GetAngles())
	if not IsValid(ent) then return end

	if ent.CPPISetOwner then ent:CPPISetOwner(ply) end
	if ent.Setowning_ent then ent:Setowning_ent(ply) end
	ent.carclass = carclass

	ply:addMoney(-price)
	Slawer.Mayor:AddFunds(tax)

	DarkRP.log("money", ply, nil, "заказал " .. (data.name or class) .. (carclass and (" для " .. carclass) or "") .. " за $" .. price, nil, price, base)
end)
