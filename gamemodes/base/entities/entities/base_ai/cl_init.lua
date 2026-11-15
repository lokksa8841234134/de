--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
include( "shared.lua" )

--[[---------------------------------------------------------
	Name: Draw
	Desc: Draw it!
-----------------------------------------------------------]]
function ENT:Draw( flags )
	self:DrawModel( flags )
end

--[[---------------------------------------------------------
	Name: DrawTranslucent
	Desc: Draw translucent
-----------------------------------------------------------]]
function ENT:DrawTranslucent( flags )

	-- This is here just to make it backwards compatible.
	-- You shouldn't really be drawing your model here unless it's translucent

	self:Draw( flags )

end
