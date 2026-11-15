--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

--[[---------------------------------------------------------------------------
	Торговый автомат: E по кнопке (её подсвечивает клиент, ENT:GetNearestButton) -
	напиток или снек кнопки (DarkRP.Vendors[тип].buttons) за её цену с налогом
	магазинов (McINV.Tax, налог - в казну района). Покупка выпадает в лоток
	(pos, ang типа) и принадлежит покупателю. Кнопка BUSY с. горит зелёным
	(куплено) или красным (не хватило денег). Тип - VendorType: office,
	union, snack; не задан - по модели, иначе office.
	Ставит администратор (в спавн-меню автомата нет, docs/step11_2_shops.md)
---------------------------------------------------------------------------]]
local BUSY = 1.5

function ENT:Initialize()
	local vtype = self:GetVendorType()

	if not DarkRP.Vendors[vtype] then
		vtype = "office"

		for k, v in pairs(DarkRP.Vendors) do
			if v.model == self:GetModel() then
				vtype = k
				break
			end
		end

		self:SetVendorType(vtype)
	end

	local data = DarkRP.Vendors[vtype]
	local model = self:GetModel()

	if not model or model == "" then
		model = data.model
		self:SetModel(model)
	end

	if model == data.model and data.material and self:GetMaterial() == "" then
		self:SetMaterial(data.material)
	end

	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetUseType(SIMPLE_USE)

	local phys = self:GetPhysicsObject()

	if IsValid(phys) then
		phys:EnableMotion(false)
	end
end

function ENT:Use(ply)
	if not IsValid(ply) or not ply:IsPlayer() or not ply:IsFreeman() then return end
	if self.BusyUntil and self.BusyUntil > CurTime() then return end

	local vtype = DarkRP.Vendors[self:GetVendorType()]
	local k = vtype and self:GetNearestButton(ply)
	local button = k and vtype.buttons[k]
	local food = button and DarkRP.Food[button.food]
	if not food then return end

	local price, tax = McINV.Tax(tonumber(button.price) or 0)
	price = math.Round(price)

	self.BusyUntil = CurTime() + BUSY
	self:SetButton(k)

	local item = price > 0 and ply:canAfford(price) and McINV.AddCustomItem(nil, INV_FOOD, button.food, food)
	if item and button.material then item.material = button.material end

	local ent = item and McINV.SpawnItem(INV_FOOD, item, self:LocalToWorld(vtype.pos), self:LocalToWorldAngles(vtype.ang), ply)

	if IsValid(ent) then
		ply:addMoney(-price)
		Slawer.Mayor:AddFunds(tax)
		self:SetStocked(true)

		DarkRP.log("money", ply, nil, "купил в автомате " .. (food.name or button.food) .. " за $" .. price, nil, tax, self)
	else
		self:SetStocked(false)
	end

	local token = {}
	self.BusyToken = token

	timer.Simple(BUSY, function()
		if IsValid(self) and self.BusyToken == token then self:SetButton(0) end
	end)
end
