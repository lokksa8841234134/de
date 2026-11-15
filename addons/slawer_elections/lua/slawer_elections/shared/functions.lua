--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
function Slawer.Elections:Compress(tTable)
	local sJson = util.TableToJSON(tTable or {})

	return sJson, sJson:len()
end

function Slawer.Elections:Decompress(dData)
	local tTable = util.JSONToTable(dData or "")

	return tTable
end

function Slawer.Elections:FromPlayerToID(tTable)
	local tOut = {}

	for k, v in pairs(tTable) do
		if not IsValid(k) then continue end
		tOut[k:UserID()] = v
	end

	return tOut
end

function Slawer.Elections:FromIDToPlayer(tTable)
	local tOut = {}

	for k, v in pairs(tTable) do
		if not IsValid(Player(k)) then continue end
		tOut[Player(k)] = v
	end

	return tOut
end