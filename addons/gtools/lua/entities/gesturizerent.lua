--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()

ENT.Base 			= "base_gmodentity"
ENT.PrintName			= "Gesturizer Entity"
ENT.Author			= ""

ENT.Spawnable			= false
ENT.AdminSpawnable		= false
ENT.RenderGroup			= RENDERGROUP_NONE




function ENT:SetupDataTables()

	self:NetworkVar( "Entity", 0, "TargetEnt" );
	self:NetworkVar( "String", 0, "AnimName" );
	self:NetworkVar( "Float", 1, "RepeatRate" );

end




function ENT:Initialize()

	local target = self:GetTargetEnt()

	self:SetNoDraw(true)

	if self:GetRepeatRate() > 0 then
		self.NextRepeat = 0
	else
		//someone was dumb and set it to never repeat, so let's play the gesture once and then delete ourselves
		self:PlayGesture(true)
	end
end




function ENT:Think()

	//if SERVER then return end

	if self:GetRepeatRate() > 0 then
		if !( self.NextRepeat > CurTime() ) then
			self:PlayGesture(false)
			self.NextRepeat = CurTime() + self:GetRepeatRate()
		end
	end
	
	self:NextThink(CurTime())
	return true

end




function ENT:PlayGesture(shouldweremoveourselves)

	if CLIENT then return end

	local target = self:GetTargetEnt()
	local animname	= self:GetAnimName()
	if animname == nil or !target:IsValid() then self:Remove() return end

	local gesturesequence = target:LookupSequence(animname)
	local gesture = target:GetSequenceActivity(gesturesequence)
	target:RestartGesture(gesture)

	//if shouldweremoveourselves == true then
	//	remove ourselves, remove the entity modifier from our target
	//end

end

//prevents the entity from being duplicated
duplicator.RegisterEntityClass( "gesturizerent", function( ply, data )
    //PrintTable( data )
    //duplicator.GenericDuplicatorFunction( ply, data )
end, "Data" )