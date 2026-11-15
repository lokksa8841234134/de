--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
-- ╔══╗───╔╗╔══╗───────────╔╗──--
-- ║═╦╩╦╦╗║║║╔╗║╔═╦╦╦═╦╦═╦═╣╚╗─--
-- ║╔╣╬║╔╝║╚╣╠╣║║╬║╔╣╬╠╣╩╣═╣╔╣─--
-- ╚╝╚═╩╝─╚═╩╝╚╝║╔╩╝╚╦╝╠═╩═╩═╝─--
-- ─────────────╚╝───╚═╝───────--
-- ───── By Mactavish ─────────--

McCD = {}
McCD.Cars = {}
McCD.Config = {}

McCD.Version = "0.0.1"

local function McCDLoad()

	MsgC( Color(0, 255, 0), "[McCD] Initialization started\n" )

	if SERVER then

		include("mc_cardealer/sh_config.lua")
		include("mc_cardealer/sh_cars.lua")
		include("mc_cardealer/sv_db.lua")
		include("mc_cardealer/sv_init.lua")
		AddCSLuaFile("mc_cardealer/sh_config.lua")
		AddCSLuaFile("mc_cardealer/sh_cars.lua")
		AddCSLuaFile("mc_cardealer/cl_util.lua")
		AddCSLuaFile("mc_cardealer/cl_init.lua")
	else
		include("mc_cardealer/sh_config.lua")
		include("mc_cardealer/sh_cars.lua")
		include("mc_cardealer/cl_util.lua")
		include("mc_cardealer/cl_init.lua")
	end

	MsgC( Color(0, 255, 0), "[McCD] Initialization done\n" )

end

if SERVER then
	hook.Add("PostGamemodeLoaded", "McCD.LoadSV", function() McCDLoad() end)
else
	hook.Add("InitPostEntity", "McCD.LoadCL", function() McCDLoad() end)
end

if GAMEMODE then
	McCDLoad()
end