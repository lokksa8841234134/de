--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()
DEFINE_BASECLASS( "base_gmodentity" )

ENT.Type = "anim"
ENT.PrintName = "Tool Ghost"

function ENT:Initialize()

	if ( SERVER ) then
		self:PhysicsInitBox( Vector( -4, -4, -4 ), Vector( 4, 4, 4 ) )
	end

end

function ENT:SetNetworkedBonePosition( i, Pos, Angle )

	self:SetNWVector( "Vector" .. i, Pos )
	self:SetNWAngle( "Angle" .. i, Angle )

end

function ENT:Draw( flags )

	-- Don't draw it if we're a ragdoll and haven't
	-- received all of the bone positions yet.
	if ( self:GetModelPhysBoneCount() > 1 and !self:GetNWVector( "Vector0", false ) ) then
		return
	end

	BaseClass.Draw( self, flags )

end
