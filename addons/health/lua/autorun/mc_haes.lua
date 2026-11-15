--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
MES = {}

function MES.Load()
	if SERVER then
		include("mc_haes/sh_config.lua")
		AddCSLuaFile("mc_haes/sh_config.lua")
		local f = file.Find("mc_haes/core/*", "LUA")

		for _, v in ipairs(f) do
			if string.StartWith(v, "sh_") then
				include("mc_haes/core/" .. v)
				AddCSLuaFile("mc_haes/core/" .. v)
			elseif string.StartWith(v, "sv_") then
				include("mc_haes/core/" .. v)
			elseif string.StartWith(v, "cl_") then
				AddCSLuaFile("mc_haes/core/" .. v)
			end
		end

		f = file.Find("mc_haes/ui/*", "LUA")

		for _, v in ipairs(f) do
			AddCSLuaFile("mc_haes/ui/" .. v)
		end
	else
		include("mc_haes/sh_config.lua")
		local f = file.Find("mc_haes/core/*", "LUA")

		for _, v in ipairs(f) do
			if string.StartWith(v, "sh_") then
				include("mc_haes/core/" .. v)
			elseif string.StartWith(v, "cl_") then
				include("mc_haes/core/" .. v)
			end
		end

		f = file.Find("mc_haes/ui/*", "LUA")

		for _, v in ipairs(f) do
			include("mc_haes/ui/" .. v)
		end
	end
end

MES.Load()