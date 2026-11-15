--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
include("shared.lua")

ENT.colors = {
	Color(233,158,19),
	Color(216,89,4),
	Color(231,128,9),
	Color(235,151,55),
}

function ENT:Think()
	self:NextThink(CurTime())

	return true
end