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
	Почтовый ящик: выдача заказов из хранилища (McINV.OpenBank, noput - только забрать)
	self.territory - помещение (объект или имя в Territories.list), задаёт тот, кто ставит ящик;
	без него ящик общий
---------------------------------------------------------------------------]]
function ENT:Initialize()
	local model = self:GetModel()

	if not model or model == "" then
		self:SetModel("models/props/cs_militia/mailbox01.mdl")
	end

	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetUseType(SIMPLE_USE)

	local phys = self:GetPhysicsObject()

	if IsValid(phys) then
		phys:EnableMotion(false)
	end
end

-- ящик помещения - только владельцам; по нему же покупка ищет ближайшую почту для GPS (makethings.lua)
function ENT:CanLoot(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return false end
	if self.territory == nil then return true end

	local territory = self.territory

	if isstring(territory) then
		territory = Territories:Get(territory)
	end

	return istable(territory) and ply:IsTerritoryOwner(territory) and true or false
end

function ENT:Use(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if DarkRP.UseDelay(ply, 1) then return end

	if not self:CanLoot(ply) then
		return
	end

	McINV.OpenBank(ply, true, self, self:GetPos())
end
