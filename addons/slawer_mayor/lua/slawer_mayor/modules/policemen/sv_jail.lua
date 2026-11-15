--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Компьютер участка, вкладки "Задержанные" и "Дела судмедэкспертизы" -
	сервер (клиент - cl.lua рядом)

	Сообщения Slawer.Mayor (shared/networking.lua), дела ведёт
	police/sv_arrest.lua (DarkRP.JailList, JailIdentify, JailSearchNLR,
	JailAccuse, JailAttachCase, JailDetachCase, JailSendToCourt):
	GetJail - список дел;
	UnJail {cp} - "Освободить";
	JailInfoUpdate {user, passid} - личность по ID паспорта,
	  {user} - "Запросить поиск в базе данных N.L.R.",
	  {user, add_accusation} - "Добавить обвинение",
	  {user, add_kill} - "Прикрепить дело" судмедэкспертизы по номеру,
	  {user, remove_kill} - "Удалить" прикреплённое дело;
	SendToPrison {user} - "Передать дело в суд".
	Ответ - всегда GetJail; openuser в деле - клиент сразу открывает его.
	GetDeathLOG - дела судмедэкспертизы (MES.GetDeathLog,
	health/core/sv_forensic.lua), ответ - GetDeathLOG со списком. Клиент
	предлагает "Прикрепить дело" из списка, полученного этой вкладкой.
	Пользоваться может полицейский у компьютера (slawer_mayor_computer,
	Slawer.Mayor:PoliceAtComputer - server/sv_computers.lua)
---------------------------------------------------------------------------]]

local function canUse(ply)
	return DarkRP and DarkRP.JailList ~= nil and Slawer.Mayor:PoliceAtComputer(ply)
end

-- список дел; openFor - UserID дела, которое открыть сразу
local function sendJail(ply, openFor)
	Slawer.Mayor:NetStart("GetJail", DarkRP.JailList(openFor), ply)
end

-- игрок по UserID из сообщения, если на него есть дело; иначе список у полицейского устарел
local function caseTarget(ply, id)
	local target = Player(math.floor(tonumber(id) or 0))
	if IsValid(target) and DarkRP.JailRecords[target:UserID()] then return target end

	sendJail(ply)
end

Slawer.Mayor:NetReceive("GetJail", function(ply)
	if canUse(ply) then sendJail(ply) end
end)

Slawer.Mayor:NetReceive("UnJail", function(ply, data)
	if not istable(data) or not canUse(ply) then return end

	local target = caseTarget(ply, data.cp)
	if not target then return end

	target:unArrest(ply)
	sendJail(ply)
end)

Slawer.Mayor:NetReceive("JailInfoUpdate", function(ply, data)
	if not istable(data) or not canUse(ply) then return end

	local target = caseTarget(ply, data.user)
	if not target then return end

	if data.add_kill ~= nil then
		DarkRP.JailAttachCase(ply, target, data.add_kill)
	elseif data.remove_kill ~= nil then
		DarkRP.JailDetachCase(ply, target, data.remove_kill)
	elseif data.add_accusation ~= nil then
		DarkRP.JailAccuse(ply, target, data.add_accusation)
	elseif data.passid ~= nil then
		DarkRP.JailIdentify(ply, target, data.passid)
	else
		DarkRP.JailSearchNLR(ply, target)
	end

	sendJail(ply, target:UserID())
end)

-- клиент сам переходит к списку, получив его: только в ответ на запрос
Slawer.Mayor:NetReceive("GetDeathLOG", function(ply)
	if canUse(ply) and MES and MES.GetDeathLog then
		Slawer.Mayor:NetStart("GetDeathLOG", MES.GetDeathLog(), ply)
	end
end)

-- клиент сразу уходит на главную страницу: при отказе дело откроется снова
Slawer.Mayor:NetReceive("SendToPrison", function(ply, data)
	if not istable(data) or not canUse(ply) then return end

	local target = caseTarget(ply, data.user)
	if not target then return end

	local ok = DarkRP.JailSendToCourt(ply, target)

	sendJail(ply, not ok and target:UserID() or nil)
end)

-- база N.L.R. ответила: открыть дело у запросившего
hook.Add("playerJailIdentified", "Slawer.Mayor.Jail", function(ply, record, searcher)
	if IsValid(searcher) and searcher:isCP() then sendJail(searcher, ply:UserID()) end
end)

-- задержанный вышел: клиент рисует время по Player(userid), список у
-- полицейских за компьютерами обновляется без него
hook.Add("playerJailSuspended", "Slawer.Mayor.Jail", function(ply)
	for _, cop in ipairs(player.GetAll()) do
		if cop ~= ply and canUse(cop) then sendJail(cop) end
	end
end)
