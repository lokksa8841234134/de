--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
CURRENT_TERRITORY = nil

timer.Create("terrtitoryThink", 1, 0, function()

	if not (IsValid(LocalPlayer()) and LocalPlayer():Alive()) then return end

	if CURRENT_TERRITORY then
		if not CURRENT_TERRITORY:IsInside(LocalPlayer()) then
			net.SendSingleMessage("territoryExit")
			if CURRENT_TERRITORY.onExitCL then
				CURRENT_TERRITORY.onExitCL(CURRENT_TERRITORY)
			end
			CURRENT_TERRITORY = nil
		end
	else
		for _, territory in pairs(Territories.list) do
			if territory:IsInside(LocalPlayer()) then
				CURRENT_TERRITORY = territory
				net.Start("territoryEnter")
				net.WriteString(territory.name)
				net.SendToServer()
				if territory.onEnterCL then
					territory.onEnterCL(territory)
				end
				break
			end
		end
	end
end)