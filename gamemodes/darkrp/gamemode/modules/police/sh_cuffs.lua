--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Наручники - общая часть (сервер в sv_cuffs.lua)

	Закованный игрок не бьёт, не стреляет, не перезаряжается и держит только
	ключи (руки). Хуки общие, чтобы предсказание клиента совпадало с сервером.

	Клиент копирует ведущего из NW2 "DarkRP.DraggedBy" в ply.DraggedBy:
	по нему SetupMove "DarkRP.Cuffs" (sh_init.lua) тянет игрока и на клиенте.
---------------------------------------------------------------------------]]

hook.Add("StartCommand", "DarkRP.Cuffs", function(ply, cmd)
	if CLIENT then
		local dragger = ply:GetNW2Entity("DarkRP.DraggedBy")
		ply.DraggedBy = IsValid(dragger) and dragger or nil
	end

	if not ply:getDarkRPVar("HandCuffed") or not ply:Alive() then return end

	cmd:RemoveKey(IN_ATTACK)
	cmd:RemoveKey(IN_ATTACK2)
	cmd:RemoveKey(IN_RELOAD)
end)

hook.Add("PlayerSwitchWeapon", "DarkRP.Cuffs", function(ply, oldWep, newWep)
	if IsValid(newWep) and newWep:GetClass() ~= "keys" and ply:getDarkRPVar("HandCuffed") then return true end
end)
