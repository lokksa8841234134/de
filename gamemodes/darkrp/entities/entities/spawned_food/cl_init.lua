--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
include("shared.lua")

local cutlist = {
	["america"] = { ang = Angle(-180, -90, 0), mat = Material("models/antlion/antlion_innards"), min = -10, max = 20},
	["pizza"] = { ang = Angle(-180, 0, 0), mat = Material("models/antlion/antlion_innards"), min = -10, max = 20},
	["french_pancake"] = { ang = Angle(-180, 90, 0), mat = Material("models/antlion/antlion_innards"), min = -10, max = 20},
	["ribs"] = { ang = Angle(-180, -90, 0), mat = Material("models/antlion/antlion_innards"), min = -10, max = 20},
	["german_chicken"] = { ang = Angle(180, 0, 0), mat = Material("models/antlion/antlion_innards"), min = -7, max = 15},
	["chicken_row"] = { ang = Angle(180, 0, 0), mat = Material("models/antlion/antlion_innards"), min = -7, max = 15},
	["pie"] = { ang = Angle(-180, 0, 0), mat = Material("models/antlion/antlion_innards"), min = -5, max = 15},
	["french_cake"] = { ang = Angle(-180, 0, 0), mat = Material("models/antlion/antlion_innards"), min = -7, max = 15},
	["ananas"] = { ang = Angle(-90, 0, 0), mat = Material("models/antlion/antlion_innards"), min = -10, max = 15},
	["french_baget"] = { ang = Angle(-180, 90, 0), mat = Material("models/antlion/antlion_innards"), min = -20, max = 40},
	["europan_pancake"] = { ang = Angle(-90, 0, 0), mat = Material("models/antlion/antlion_innards"), min = 1, max = 2},
}

function ENT:Draw()
	self:DrawModel()
end