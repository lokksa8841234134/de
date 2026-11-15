--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()

ENT.Type = "anim"
ENT.PrintName = "World Anchor"

if ( CLIENT ) then return end

function ENT:Initialize()


	self:SetModel( "models/Combine_Helicopter/helicopter_bomb01.mdl" )
	self:PhysicsInit( SOLID_VPHYSICS )

	self:SetNotSolid( true )
	self:SetNoDraw( true )
	self:DrawShadow( false )

	local phys = self:GetPhysicsObject()
	if ( IsValid( phys ) ) then

		phys:EnableMotion( false )
		phys:EnableCollisions( false )

	end

	self:SetUnFreezable( true )

end
