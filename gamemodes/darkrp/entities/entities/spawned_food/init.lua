--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- модель и поля предмета ставит McINV.SpawnItem до Spawn
function ENT:Initialize()
	local model = self:GetModel()

	if not model or model == "" then
		self:SetModel("models/props_junk/cardboard_box004a.mdl")
	end

	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
	self:SetUseType(SIMPLE_USE)

	local phys = self:GetPhysicsObject()

	if IsValid(phys) then
		phys:Wake()
	end
end

-- [E] - одна порция (hungermod/sv_food.lua); пилюля ppp кусает сразу
function ENT:Use(activator, caller)
	if not IsValid(activator) or not activator:IsPlayer() or not DarkRP.EatFood then return end

	DarkRP.EatFood(activator, self, IsValid(activator.pk_pill_ent))
end

function ENT:OnTakeDamage(dmg)
	self:TakePhysicsDamage(dmg)
end
