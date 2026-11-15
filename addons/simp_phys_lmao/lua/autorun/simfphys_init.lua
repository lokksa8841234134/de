--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
hook.Add("PostGamemodeLoaded", "SimfPhys.Loading", function()
	AddCSLuaFile("simfphys/init.lua")
	include("simfphys/init.lua")
end)