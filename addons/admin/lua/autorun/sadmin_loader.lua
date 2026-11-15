--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
if slib and slib.loadFolder then
	slib.loadFolder("s_admin/", true, {
		{"s_admin/", "sh_sadmin_config.lua"},
		{"s_admin/core/", "sh_utils.lua"}
	}, {
		{"s_admin/integrations/", "sh_cami.lua"},
		{"s_admin/", "cl_quickaccess.lua"},
		{"s_admin/integrations/", "sv_logging.lua"}
	})
end

hook.Add("slib:loadedUtils", "sA:Init_sAdmin", function()
	slib.loadFolder("s_admin/", true, {
		{"s_admin/", "sh_sadmin_config.lua"},
		{"s_admin/core/", "sh_utils.lua"}
	}, {
		{"s_admin/integrations/", "sh_cami.lua"},
		{"s_admin/", "cl_quickaccess.lua"},
		{"s_admin/integrations/", "sv_logging.lua"}
	})
end)