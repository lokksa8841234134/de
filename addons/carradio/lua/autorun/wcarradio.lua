--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
local wyozicr_debug = SERVER and CreateConVar("wyozicr_debug", "0") or CreateClientConVar("wyozicr_debug", "0", FCVAR_ARCHIVE)

wyozicr = wyozicr or {}
function wyozicr.Debug(...)
	if not wyozicr_debug:GetBool() then return end
	print("[WCR-DEBUG] ", ...)
end
function wyozicr.IsDebug()
	return wyozicr_debug:GetBool()
end

local function AddClient(fil)
	if SERVER then AddCSLuaFile(fil) end
	if CLIENT then return include(fil) end
end

local function AddServer(fil)
	if SERVER then return include(fil) end
end

local function AddShared(fil)
	include(fil)
	AddCSLuaFile(fil)
end

-- WCR for 76561198253646334

AddShared("wcarradio/sh_ext.lua")
AddShared("wcarradio/sh_wcr_util.lua")
AddShared("wcarradio/sh_wcr_config.lua")
AddShared("wcarradio/sh_wcr_stations.lua")
wyozicr.tdui = AddClient("wcarradio/cl_lib_tdui.lua")
AddClient("wcarradio/cl_carstereo.lua")
AddClient("wcarradio/cl_carfui.lua")
AddClient("wcarradio/cl_wcr_soundmuffler.lua")
AddServer("wcarradio/sv_carstereo.lua")