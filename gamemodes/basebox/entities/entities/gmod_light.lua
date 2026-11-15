--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()
DEFINE_BASECLASS( "base_gmodentity" )

ENT.PrintName = "Light"
ENT.Editable = true

local MODEL = Model( "models/maxofs2d/light_tubular.mdl" )

function ENT:SetupDataTables()
	self:NetworkVar( "Bool", 0, "On", { KeyName = "on", Edit = { type = "Boolean", order = 1, title = "#entedit.enabled" } } )
	self:NetworkVar( "Bool", 1, "Toggle", { KeyName = "tg", Edit = { type = "Boolean", order = 2, title = "#tool.light.toggle" } } )
	self:NetworkVar( "Float", 1, "LightSize", { KeyName = "sz", Edit = { type = "Float", order = 3, min = 0, max = 1024, title = "#tool.light.size" } } )
	self:NetworkVar( "Float", 2, "Brightness" , { KeyName = "br", Edit = { type = "Int", order = 4, min = 0, max = 6, title = "#tool.light.brightness" } } )

	self:NetworkVar( "Bool", 2, "LightWorld" , { KeyName = "world", Edit = { type = "Boolean", order = 5, title = "#tool.light.noworld", category = "#entedit.advanced" } } )
	self:NetworkVar( "Bool", 3, "LightModels" , { KeyName = "models", Edit = { type = "Boolean", order = 6, title = "#tool.light.nomodels", category = "#entedit.advanced" } } )
end

function ENT:Initialize()

	if ( CLIENT ) then

		self.PixVis = util.GetPixelVisibleHandle()

	end

	if ( SERVER ) then --lights are rolling around even though the model isn't round!!

		self:SetModel( MODEL )
		self:PhysicsInit( SOLID_VPHYSICS )
		self:SetMoveType( MOVETYPE_VPHYSICS )
		self:SetSolid( SOLID_VPHYSICS )
		self:DrawShadow( false )

		local phys = self:GetPhysicsObject()

		if ( IsValid( phys ) ) then
			phys:Wake()
		end

	end

end

function ENT:Toggle()
	self:SetOn( !self:GetOn() )
end

function ENT:Think()

	self.BaseClass.Think( self )

	if ( CLIENT ) then

		if ( !self:GetOn() ) then return end

		local noworld = self:GetLightWorld()
		local dlight = DynamicLight( self:EntIndex(), noworld )

		if ( dlight ) then

			local c = self:GetColor()

			local size = self:GetLightSize()
			local brght = self:GetBrightness()
			-- Clamp for multiplayer
			if ( !game.SinglePlayer() ) then
				size = math.Clamp( size, 0, 1024 )
				brght = math.Clamp( brght, 0, 6 )
			end

			dlight.Pos = self:GetPos()
			dlight.r = c.r
			dlight.g = c.g
			dlight.b = c.b
			dlight.Brightness = brght
			dlight.Decay = size * 5
			dlight.Size = size
			dlight.DieTime = CurTime() + 1

			dlight.noworld = noworld
			dlight.nomodel = self:GetLightModels()

		end

	end

end