--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
Dispatcher = Dispatcher or {}
Dispatcher.Config = {}
Dispatcher.Config.Grps = {}

local function CreateConfig()
	Dispatcher.Config.Grps = {
		["NYPD"] = {
			Teams = table.Copy(GAMEMODE.CivilProtection),
			Responders = function(ply)
				return ply:isCP()
			end,
			CustomCheck = function(ply) return true end,
		},
		["FDNY"] = {
			Teams = {
				[TEAM_REF] = true,
				[TEAM_FIREFIGHTER] = true,
			},
			Responders = function(ply)
				return ply:isEMS()
			end,
			CustomCheck = function(ply) return true end,
		},
	}
end

hook.Add("PostGamemodeLoaded", "CreateServicesConfig", function()
	CreateConfig()
end)

if GAMEMODE then
	CreateConfig()
end