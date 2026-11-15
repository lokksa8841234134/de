--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Блокировка управления машиной - сервер (клиент: client/seatcontrols.lua)

	Клиент шлёт net simfphys_blockcontrols (Bool), когда открывает и
	закрывает меню Q, меню C и чат: пока они открыты, клавиши не должны
	управлять машиной. Сервер запоминает ply.blockcontrols, его читает
	управление машинами simfphys (их серверная часть - шаг 15).

	Без этого сообщения у клиента ошибка Lua "Calling net.Start with
	unregistered message" при каждом нажатии Q и C и открытии чата, и меню
	Q и C не открываются: ошибка обрывает хук OnSpawnMenuOpen раньше
	GM:OnSpawnMenuOpen.
---------------------------------------------------------------------------]]
util.AddNetworkString("simfphys_blockcontrols")

net.Receive("simfphys_blockcontrols", function(_, ply)
	if not IsValid(ply) then return end

	ply.blockcontrols = net.ReadBool() or nil
end)
