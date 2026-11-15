--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
Slawer.Elections.MenuOpenRegister = function()
	if IsValid(Slawer.Elections.RegistrationMenu) then
		Slawer.Elections.RegistrationMenu:Remove()
	end

	Slawer.Elections.RegistrationMenu = vgui.Create("Slawer.Elections:Registration")
end