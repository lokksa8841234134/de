--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
include("shared.lua")

local USE_DIST_SQR = 120 * 120

function ENT:Initialize()
	self:SetModel("models/props/cs_assault/money.mdl")
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetUseType(SIMPLE_USE)
	self:SetCollisionGroup(COLLISION_GROUP_WEAPON)

	self.nodupe = true

	local phys = self:GetPhysicsObject()

	if IsValid(phys) then
		phys:Wake()
	end
end

function ENT:Use(activator)
	if self.USED then return end
	if not IsValid(activator) or not activator:IsPlayer() or activator.DarkRPUnInitialized then return end
	if not activator:IsUnrestrained() then return end
	if activator:EyePos():DistToSqr(self:NearestPoint(activator:EyePos())) > USE_DIST_SQR then return end

	self.USED = true

	local amount = math.max(math.floor(tonumber(self:Getamount()) or 0), 0)

	if amount > 0 then
		local currency = GAMEMODE.Config.currency or "$"

		activator:addMoney(amount)
		DarkRP.log("money", activator, nil, "подобрал деньги " .. currency .. amount, nil, nil, self)
	end

	self:Remove()
end

function ENT:OnTakeDamage(dmg)
	self:TakePhysicsDamage(dmg)
end
