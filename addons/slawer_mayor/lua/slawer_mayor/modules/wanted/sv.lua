--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Компьютер участка, вкладка "Розыск" - сервер (клиент - cl.lua рядом)

	Команды клиента:
	drp_wanted <ID паспорта или имя> <причина> - "Подать в розыск";
	drp_unwanted <UserID> - кнопка у записи в списке.
	Список клиент строит сам по переменным DarkRP wanted и wantedReason.
	Розыск ведёт police/sv_wanted.lua (DarkRP.findCitizen, ply:wanted,
	ply:unWanted), права - хуки автора canWanted (любой полицейский) и
	canUnwant (только супервайзер) в police/sh_init.lua.
	Пользоваться может полицейский у компьютера (slawer_mayor_computer)
---------------------------------------------------------------------------]]

local function canUse(ply)
	return DarkRP and DarkRP.findCitizen ~= nil and Slawer.Mayor:PoliceAtComputer(ply)
end

-- отказ хука автора (canWanted, canUnwant) - его текстом
local function refuse(ply, msg)
	if msg then DarkRP.notify(ply, 1, 5, msg) end
end

concommand.Add("drp_wanted", function(ply, _, args)
	if not canUse(ply) or DarkRP.NetDelay(ply, 1) then return end

	local target = DarkRP.findCitizen(tostring(args[1] or ""))
	if not target or target == ply then return end

	-- причина с пробелами может прийти несколькими аргументами
	local reason = string.Trim((string.gsub(table.concat(args, " ", 2), "[\r\n\t]+", " ")))
	if not utf8.len(reason) then return end

	local ok, msg = hook.Call("canWanted", DarkRP.hooks, target, ply, reason)
	if not ok then return refuse(ply, msg) end

	target:wanted(ply, reason)
end)

concommand.Add("drp_unwanted", function(ply, _, args)
	if not canUse(ply) or DarkRP.NetDelay(ply, 1) then return end

	local target = Player(math.floor(tonumber(args[1]) or 0))
	if not IsValid(target) or target == ply then return end

	local ok, msg = hook.Call("canUnwant", DarkRP.hooks, target, ply)
	if not ok then return refuse(ply, msg) end

	target:unWanted(ply)
end)
