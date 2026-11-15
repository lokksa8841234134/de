--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Компьютер участка, вкладка "Запрос ордера на обыск недвижимости" -
	сервер (клиент - cl.lua рядом)

	Команда клиента: drp_warrant <территория> <причина> - "Запросить ордер".
	Территория - имя из Territories.list, адрес клиент ищет сам.
	Ордер ведёт police/sv_wanted.lua (DarkRP.requestWarrant): решает
	районный администратор, ордер получает владелец недвижимости.
	SyncWarrants и GetOwners сервер не шлёт: список ордеров клиент нигде
	не показывает, а у списка адресов нет update, GetOwners дал бы ошибку.
	Пользоваться может полицейский у компьютера (slawer_mayor_computer)
---------------------------------------------------------------------------]]

concommand.Add("drp_warrant", function(ply, _, args)
	if not DarkRP or not DarkRP.requestWarrant or not Slawer.Mayor:PoliceAtComputer(ply) then return end
	if DarkRP.NetDelay(ply, 1) then return end

	DarkRP.requestWarrant(ply, tostring(args[1] or ""), table.concat(args, " ", 2))
end)
