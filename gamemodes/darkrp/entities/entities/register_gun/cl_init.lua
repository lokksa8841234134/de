--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
include("shared.lua")

ENT.colors = {
	Color(19,119,233),
	Color(20,102,196),
	Color(0,62,121),
	Color(55,127,235),
}

function ENT:Think()
	self:NextThink(CurTime())

	return true
end