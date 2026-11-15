--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()

local col = "[8]magic_1"
ENT.pfxname = col

PrecacheParticleSystem(col)

ENT.Author = "Who"
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Base"
ENT.Category = "Particle Effects"
ENT.Spawnable = false
ENT.AdminOnly = false


if SERVER then
	function ENT:Initialize()
		self:SetModel("models/cityrp/small/box5.mdl")
		self:SetNoDraw(true)
		self:SetSkin(1)
		self:DrawShadow(false)
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		ParticleEffectAttach(self.pfxname, 1, self, 1)
	end
end