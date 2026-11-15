--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Рукав"
ENT.Author = "Mactavish"
ENT.Spawnable = true

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/props_c17/lockers001a_single.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:DrawShadow(false)
		local phys = self:GetPhysicsObject()
		phys:Wake()
	end

	function ENT:Use(ply)
	end
end