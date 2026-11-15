--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
if DarkRPLoaded then return end

local DarkRPVars = {}

local pmeta = FindMetaTable("Player")

function pmeta:getDarkRPVar(var)
	local vars = DarkRPVars[self:UserID()]

	return vars and vars[var] or nil
end

function pmeta:checkDarkRPVar(var, arg)
	local vars = DarkRPVars[self:UserID()]

	return (vars and vars[var] and vars[var] == arg) or nil
end

local function RetrievePlayerVar(userID, var, value)
	local ply = Player(userID)
	DarkRPVars[userID] = DarkRPVars[userID] or {}
	DarkRPVars[userID][var] = value

	if IsValid(ply) then
		ply.DarkRPVars = DarkRPVars[userID]
	end
end

local function doRetrieve()
	local userID = net.ReadUInt(16)
	local var, value = DarkRP.readNetDarkRPVar()
	RetrievePlayerVar(userID, var, value)
end

net.Receive("DarkRP_PlayerVar", doRetrieve)

local function doRetrieveRemoval()
	local userID = net.ReadUInt(16)
	local vars = DarkRPVars[userID] or {}
	local var = DarkRP.readNetDarkRPVarRemoval()
	vars[var] = nil
end

net.Receive("DarkRP_PlayerVarRemoval", doRetrieveRemoval)

local function InitializeDarkRPVars(len)
	local plyCount = net.ReadUInt(8)

	for i = 1, plyCount do
		local userID = net.ReadUInt(16)
		local varCount = net.ReadUInt(DarkRP.DARKRP_ID_BITS + 2)

		for j = 1, varCount do
			local var, value = DarkRP.readNetDarkRPVar()
			RetrievePlayerVar(userID, var, value)
		end
	end
end

net.Receive("DarkRP_InitializeVars", InitializeDarkRPVars)