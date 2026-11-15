--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
require("pk_pills")

AddCSLuaFile()

if SERVER then
    include("ppp_include/drivemodes.lua")
end

pk_pills.packStart("Half-Life 2","base","games/16/hl2.png")

include("ppp_include/pill_headcrabs.lua")
include("ppp_include/pill_birds.lua")
