--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
include("shared.lua")

ENT.colors = {
	Color(145,177,59),
	Color(71,112,33),
	Color(155,189,7),
	Color(150,185,84),
}

function ENT:Think()
	self:NextThink(CurTime())

	return true
end