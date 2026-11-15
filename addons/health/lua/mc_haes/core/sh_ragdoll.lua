--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Без сознания - общая часть (сервер в sv_ragdoll.lua)

	Игрок без сознания (переменная "unconscious") не нажимает клавиши и не
	ходит, оружие сменить можно только на ключи (их выдают наручники).
	Хуки общие, чтобы предсказание клиента совпадало с сервером. Взгляд из
	глаз рэгдолла, чёрный экран и блокировку мыши делает клиент автора.
---------------------------------------------------------------------------]]

hook.Add("StartCommand", "MES.Uncon", function(ply, cmd)
	if not ply:getDarkRPVar("unconscious") or not ply:Alive() then return end

	cmd:ClearButtons()
	cmd:ClearMovement()
	cmd:SetImpulse(0)
end)

hook.Add("PlayerSwitchWeapon", "MES.Uncon", function(ply, oldWep, newWep)
	if IsValid(newWep) and newWep:GetClass() ~= "keys" and ply:getDarkRPVar("unconscious") then return true end
end)
