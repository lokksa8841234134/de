--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Taser Dart"
ENT.Author = "Mac"

if (CLIENT) then return end

function ENT:Initialize()
	self:SetModel("models/hunter/blocks/cube025x025x025.mdl")
	self:SetModelScale(0.05)
	self:SetMaterial("models/debug/debugwhite")
	self:SetColor(Color(100, 100, 100))
	self:SetNoDraw(true)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:PhysicsInit(SOLID_VPHYSICS)
	local phys = self:GetPhysicsObject()

	if (IsValid(phys)) then
		phys:Wake()
	end

	timer.Simple(3, function()
		if (IsValid(self)) then
			self:Remove()
		end
	end)
end

function ENT:Touch(ent)
end