--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Арест - общая часть (сервер в sv_arrest.lua)

	У арестованного в руках только ключи и предметы заданий MQS: достать
	оружие или инструмент в камере нельзя, но ничего не отбирается - после
	освобождения всё на месте. Хук общий, чтобы предсказание клиента
	совпадало с сервером. Бить и стрелять арестованному не дают сами SWEP
	(ключи, mlw_base), стрельбу в участке - хук MW19FireBullet в sh_init.lua
---------------------------------------------------------------------------]]

local JAIL_ALLOWED = {
	keys = true,
	event_item = true, -- предмет задания MQS ("Give quest item")
}

-- можно ли держать это в руках под арестом (MQS_weapon ставят задания MQS, только на сервере)
function DarkRP.AllowedInJail(wep)
	return JAIL_ALLOWED[wep:GetClass()] == true or wep.MQS_weapon == true
end

hook.Add("PlayerSwitchWeapon", "DarkRP.Arrested", function(ply, oldWep, newWep)
	if not IsValid(newWep) or DarkRP.AllowedInJail(newWep) then return end
	if ply:getDarkRPVar("Arrested") then return true end
end)
