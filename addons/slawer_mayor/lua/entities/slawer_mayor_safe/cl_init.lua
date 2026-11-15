--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
include( "shared.lua" )

function ENT:Draw()
	self:DrawModel()
end

function ENT:SetAnim( strAnim, intSpeed )
	local strSequence, intDuration = self:LookupSequence( strAnim )
	if intDuration > 0 then
		self:SetCycle( 0 )
		self:ResetSequence( strSequence )
		self:SetPlaybackRate( intSpeed )
		self:SetCycle( 0 )
	end
end

Slawer.Mayor:NetReceive("ToggleSafeAnim", function(tbl)
	if tbl.ent && IsValid(Entity(tbl.ent)) then
		Entity(tbl.ent):SetAnim(tbl.open && "open" || "close", 1)
	end
end)