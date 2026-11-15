--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
-- Glac: credit shop, cases and episodes.
--
-- glac/sh_core.lua        Glac table, item registry, config loader
-- glac/sh_net.lua         the single Glac.Net message and its opcodes
-- glac/sh_episodes.lua    episodes, their rewards and premium passes
-- glac/sv_credits.lua     credit balance (SQL)
-- glac/sv_donations.lua   website donations -> credits
-- glac/sv_shop.lua        buying items, opening cases
-- glac/cl_glac.lua        client balance and purchase API
-- glac/config/sh_shop.lua         shop items
-- glac/config/cases/*.lua         one file per case, loaded automatically

Glac = Glac or {}

local function Shared(path)
	if SERVER then AddCSLuaFile(path) end
	include(path)
end

local function Server(path)
	if SERVER then include(path) end
end

local function Client(path)
	if SERVER then
		AddCSLuaFile(path)
	else
		include(path)
	end
end

Shared("glac/sh_core.lua")
Shared("glac/sh_net.lua")

Server("glac/sv_credits.lua")
Server("glac/sv_donations.lua")
Server("glac/sv_shop.lua")
Client("glac/cl_glac.lua")

Shared("glac/sh_episodes.lua")
Shared("glac/config/sh_shop.lua")
Shared("glac/config/sh_anniversary.lua")

for _, f in ipairs(file.Find("glac/config/cases/*.lua", "LUA")) do
	Shared("glac/config/cases/" .. f)
end
