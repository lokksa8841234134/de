--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	DarkRPVars: серверная часть

	SetDarkRPVar      - публичная переменная (видят все игроки)
	SetSelfDarkRPVar  - приватная переменная (видит только владелец)
	SetProDarkRPVar   - сохраняет текущую приватность переменной
	nil в качестве значения удаляет переменную
---------------------------------------------------------------------------]]
local pmeta = FindMetaTable("Player")

util.AddNetworkString("DarkRP_InitializeVars")
util.AddNetworkString("DarkRP_PlayerVar")
util.AddNetworkString("DarkRP_PlayerVarRemoval")

function pmeta:getDarkRPVar(var)
	local vars = self.DarkRPVars

	return vars and vars[var] or nil
end

function pmeta:checkDarkRPVar(var, arg)
	local vars = self.DarkRPVars

	return (vars and vars[var] and vars[var] == arg) or nil
end

local function sendVar(ply, var, value, target)
	if value == nil then
		net.Start("DarkRP_PlayerVarRemoval")
			net.WriteUInt(ply:UserID(), 16)
			DarkRP.writeNetDarkRPVarRemoval(var)
	else
		net.Start("DarkRP_PlayerVar")
			net.WriteUInt(ply:UserID(), 16)
			DarkRP.writeNetDarkRPVar(var, value)
	end

	if target then
		net.Send(target)
	else
		net.Broadcast()
	end
end

local function othersOf(ply)
	local others = {}

	for _, v in ipairs(player.GetHumans()) do
		if v ~= ply then others[#others + 1] = v end
	end

	return others
end

local function setVar(ply, var, value, private, target)
	if not IsValid(ply) or not isstring(var) then return end

	ply.DarkRPVars = ply.DarkRPVars or {}
	ply.privateDRPVars = ply.privateDRPVars or {}

	local old = ply.DarkRPVars[var]
	local wasPrivate = ply.privateDRPVars[var] or false

	-- без изменений: повторно не отправляем (таблицы всегда отправляются)
	if target == nil and old == value and wasPrivate == private and not istable(value) then return end

	ply.DarkRPVars[var] = value
	ply.privateDRPVars[var] = private or nil

	if private then
		-- переменная стала приватной: убрать её у остальных
		if not wasPrivate and old ~= nil then
			local others = othersOf(ply)
			if #others > 0 then sendVar(ply, var, nil, others) end
		end

		if not ply:IsBot() then
			sendVar(ply, var, value, ply)
		end
	else
		sendVar(ply, var, value, target)
	end

	if old ~= value then
		hook.Call("DarkRPVarChanged", nil, ply, var, old, value)
	end
end

function pmeta:SetDarkRPVar(var, value, target)
	setVar(self, var, value, false, target)
end

function pmeta:SetSelfDarkRPVar(var, value)
	setVar(self, var, value, true)
end

function pmeta:SetProDarkRPVar(var, value)
	setVar(self, var, value, self.privateDRPVars and self.privateDRPVars[var] or false)
end

--[[---------------------------------------------------------------------------
	Полная синхронизация по запросу клиента (InitPostEntity и проверка раз в 15 с)
---------------------------------------------------------------------------]]
local function sendAllVars(ply)
	local plys = player.GetAll()
	local count = math.min(#plys, 255)

	net.Start("DarkRP_InitializeVars")
		net.WriteUInt(count, 8)

		for i = 1, count do
			local target = plys[i]
			local vars = {}

			for var, value in pairs(target.DarkRPVars or {}) do
				if target ~= ply and target.privateDRPVars and target.privateDRPVars[var] then continue end
				vars[#vars + 1] = var
			end

			local maxVars = 2 ^ (DarkRP.DARKRP_ID_BITS + 2) - 1
			local varCount = math.min(#vars, maxVars)

			net.WriteUInt(target:UserID(), 16)
			net.WriteUInt(varCount, DarkRP.DARKRP_ID_BITS + 2)

			for j = 1, varCount do
				DarkRP.writeNetDarkRPVar(vars[j], target.DarkRPVars[vars[j]])
			end
		end
	net.Send(ply)
end

concommand.Add("_sendDarkRPvars", function(ply)
	if not IsValid(ply) then return end
	if ply.DarkRPVarsSent and ply.DarkRPVarsSent > CurTime() then return end

	ply.DarkRPVarsSent = CurTime() + 3
	sendAllVars(ply)
end)