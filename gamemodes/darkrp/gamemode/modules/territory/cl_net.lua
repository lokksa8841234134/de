--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Помещение сдано (OnSell в sh_init.lua, шаг 9): оно сразу пропадает из «Управления» SkyLine,
	полный список следом присылает сервер (territorySendInfo)
---------------------------------------------------------------------------]]
net.Receive("TerritoryOnSellAdd", function()
	local name = net.ReadString()
	local data = McPhone and McPhone.ter_list and McPhone.ter_list[name]

	if data and data.masterOwner == LocalPlayer() then
		McPhone.ter_list[name] = nil
	end
end)
