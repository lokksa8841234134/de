--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
GM.Version = "3.0.0"
GM.Name = "DarkRP"
GM.Author = "By - Mactavish"
DeriveGamemode("basebox")

local pmeta = FindMetaTable("Player")
pmeta.SteamName = pmeta.SteamName or pmeta.Name

function pmeta:Name()
	return self.DarkRPVars and self:getDarkRPVar("dsname") or self:SteamName()
end

pmeta.Nick = pmeta.Name

function pmeta:FullName()
	return self.DarkRPVars and self:getDarkRPVar("rpname") or self:SteamName()
end

local gfol = GM.FolderName .. "/gamemode/"

--[[---------------------------------------------------------------------------
	Клиентские файлы (порядок подключения - в cl_init.lua)
---------------------------------------------------------------------------]]
AddCSLuaFile(gfol .. "cl_init.lua")
AddCSLuaFile(gfol .. "sh_interfaceloader.lua")
AddCSLuaFile(gfol .. "config.lua")
AddCSLuaFile(gfol .. "playervars/sh_init.lua")
AddCSLuaFile(gfol .. "playervars/cl_init.lua")
AddCSLuaFile(gfol .. "shared/player_class.lua")
AddCSLuaFile(gfol .. "shared/animations.lua")
AddCSLuaFile(gfol .. "shared/commands.lua")
AddCSLuaFile(gfol .. "shared/entity.lua")
AddCSLuaFile(gfol .. "shared/makethings.lua")
AddCSLuaFile(gfol .. "shared/workarounds.lua")
AddCSLuaFile(gfol .. "shared.lua")

for _, File in ipairs(file.Find(gfol .. "spawnlist/*.lua", "LUA")) do
	AddCSLuaFile(gfol .. "spawnlist/" .. File)
end

for _, File in ipairs(file.Find(gfol .. "client/*.lua", "LUA")) do
	AddCSLuaFile(gfol .. "client/" .. File)
end

--[[---------------------------------------------------------------------------
	Модули: sh_* - обе стороны, sv_* - сервер, cl_* - клиент
	Порядок как в cl_init.lua; *_interface.lua грузит sh_interfaceloader.lua
---------------------------------------------------------------------------]]
local function LoadModules()
	local root = gfol .. "modules/"
	local _, folders = file.Find(root .. "*", "LUA")

	for _, folder in SortedPairs(folders, true) do
		if GM.Config.DisabledModules[folder] then continue end

		for _, File in SortedPairs(file.Find(root .. folder .. "/sh_*.lua", "LUA"), true) do
			if File == "sh_interface.lua" then continue end
			AddCSLuaFile(root .. folder .. "/" .. File)
			include(root .. folder .. "/" .. File)
		end

		for _, File in SortedPairs(file.Find(root .. folder .. "/sv_*.lua", "LUA"), true) do
			if File == "sv_interface.lua" then continue end
			include(root .. folder .. "/" .. File)
		end

		for _, File in SortedPairs(file.Find(root .. folder .. "/cl_*.lua", "LUA"), true) do
			if File == "cl_interface.lua" then continue end
			AddCSLuaFile(root .. folder .. "/" .. File)
		end
	end
end

--[[---------------------------------------------------------------------------
	Загрузка
---------------------------------------------------------------------------]]
GM.Config = {}
include("sh_interfaceloader.lua")

-- база данных: SQLite по умолчанию, MySQL через config/mysql.lua
include("config/mysql.lua")

if RP_MySQLConfig.EnableMySQL and not util.IsBinaryModuleInstalled("mysqloo") and not util.IsBinaryModuleInstalled("tmysql4") then
	MsgC(Color(255, 90, 0), "[DarkRP] EnableMySQL включён, но модуль mysqloo/tmysql4 не установлен - данные будут храниться в SQLite\n")
	RP_MySQLConfig.EnableMySQL = false
end

if not MySQLite then
	include("libraries/mysqlite/mysqlite.lua")
end

include("config.lua")
include("config/discord.lua")
include("playervars/sh_init.lua")
include("playervars/sv_init.lua")
include("shared/player_class.lua")
include("shared/animations.lua")
include("shared/commands.lua")
include("shared/entity.lua")
include("shared/makethings.lua")
include("shared/workarounds.lua")
include("shared.lua")

for _, File in ipairs(file.Find(gfol .. "spawnlist/*.lua", "LUA")) do
	include(gfol .. "spawnlist/" .. File)
end

include("server/sv_util.lua")
include("server/sv_data.lua")
include("server/sv_chat.lua")
include("server/sv_money.lua")
include("server/sv_jobs.lua")
include("server/sv_votes.lua")
include("server/sv_entities.lua")
include("server/sv_gamemode_functions.lua")
include("server/sv_skillcheck.lua")

LoadModules()
DarkRP.finish()

MySQLite.initialize(RP_MySQLConfig)
