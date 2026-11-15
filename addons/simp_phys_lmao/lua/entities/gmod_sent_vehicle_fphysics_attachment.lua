--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()

ENT.Type            = "anim"

ENT.Spawnable       = false
ENT.AdminSpawnable  = false

ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:Think()
	return false
end

if SERVER then
	function ENT:Initialize()
		self:PhysicsInit( SOLID_VPHYSICS )
		self:SetMoveType( MOVETYPE_VPHYSICS )
		self:SetSolid( SOLID_VPHYSICS )
		self:SetRenderMode( RENDERMODE_TRANSALPHA )
		self:SetNotSolid( true )
		self.DoNotDuplicate = true
	end
end

if CLIENT then
	function ENT:Draw()
		self:DrawModel()
	end

	function ENT:DrawTranslucent()
	end
end