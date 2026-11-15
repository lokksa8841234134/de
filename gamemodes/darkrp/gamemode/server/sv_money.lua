--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Деньги: кошелёк (money), зарплатный счёт (payday), зарплата каждые 10 минут,
	/dropmoney, /givemoney, пачки денег (spawned_money)
---------------------------------------------------------------------------]]
local pmeta = FindMetaTable("Player")

local PAYDAY_DELAY = 600
local MAX_INT = 2147483647

local function currency()
	return GAMEMODE.Config.currency or "$"
end

local function toAmount(value)
	value = tonumber(value)
	if not value or value ~= value or value == math.huge or value == -math.huge then return nil end

	return math.Round(value)
end

function pmeta:addMoney(amount)
	amount = toAmount(amount)
	if not amount or amount == 0 then return end

	self:SetDarkRPVar("money", (self:getDarkRPVar("money") or 0) + amount)
end

-- Зарплатный счёт: снимается в банкомате
function pmeta:addPaydayMoney(amount)
	amount = toAmount(amount)
	if not amount or amount == 0 then return end

	local payday = math.Clamp((self:getDarkRPVar("payday") or 0) + amount, 0, MAX_INT)

	self:SetSelfDarkRPVar("payday", payday > 0 and payday or nil)
	DarkRP.SavePlayerData(self, "payday", payday > 0 and payday or nil)
end

local function paydayNotice(ply, amount)
	local text = DarkRP.getPhrase("payday_message", currency() .. amount)

	if McPhone and McPhone.NewMail then
		McPhone.NewMail("Bank of Union", text, ply)
	else
		DarkRP.notify(ply, 0, 6, text)
	end
end

-- PayDay(amount) - начислить сумму (награды), PayDay() - обычная зарплата
function pmeta:PayDay(amount)
	if not IsValid(self) or self.DarkRPUnInitialized then return end

	if amount ~= nil then
		amount = toAmount(amount)
		if not amount or amount <= 0 then return end

		self:addPaydayMoney(amount)
		paydayNotice(self, amount)

		return
	end

	local salary = self:getDarkRPVar("salary") or 0
	local suppress, message, hookAmount = hook.Call("playerGetSalary", GAMEMODE, self, salary)
	salary = toAmount(hookAmount) or salary

	if suppress then
		if message then DarkRP.notify(self, 1, 4, message) end
		return
	end

	if self:getDarkRPVar("Arrested") or self:getDarkRPVar("jailed") then
		DarkRP.notify(self, 1, 4, DarkRP.getPhrase("payday_missed"))
		return
	end

	if salary <= 0 then
		DarkRP.notify(self, 3, 4, DarkRP.getPhrase("payday_unemployed"))
		return
	end

	self:addPaydayMoney(salary)
	paydayNotice(self, salary)
end

local function paydayTimer(ply)
	return "DarkRP.Payday." .. ply:UserID()
end

hook.Add("PlayerInitialSpawn", "DarkRP.Payday", function(ply)
	local name = paydayTimer(ply)

	timer.Create(name, PAYDAY_DELAY, 0, function()
		if not IsValid(ply) then
			timer.Remove(name)
			return
		end

		ply:PayDay()
	end)
end)

hook.Add("PlayerDisconnected", "DarkRP.Payday", function(ply)
	timer.Remove(paydayTimer(ply))
end)

--[[---------------------------------------------------------------------------
	Пачки денег
---------------------------------------------------------------------------]]
function DarkRP.createMoneyBag(pos, amount, owner)
	amount = toAmount(amount)
	if not amount or amount <= 0 then return end

	local ent = ents.Create("spawned_money")
	if not IsValid(ent) then return end

	ent:SetPos(pos)
	ent:Setamount(math.min(amount, MAX_INT))
	ent:Spawn()
	ent:Activate()

	if IsValid(owner) and ent.CPPISetOwner then
		ent:CPPISetOwner(owner)
	end

	return ent
end

local function moneyArg(ply, args)
	local amount = toAmount(args)

	if not amount or amount < 1 or amount > MAX_INT then
		return
	end

	return amount
end

DarkRP.defineChatCommand("dropmoney", function(ply, args)
	if not ply:Alive() or not ply:IsUnrestrained() or ply:InVehicle() then return "" end
	if DarkRP.NetDelay(ply, 2) then return "" end

	local amount = moneyArg(ply, args)
	if not amount then return "" end

	if not ply:canAfford(amount) then
		return ""
	end

	local tr = util.TraceLine({
		start = ply:EyePos(),
		endpos = ply:EyePos() + ply:GetAimVector() * 60,
		filter = ply
	})

	ply:addMoney(-amount)

	local bag = DarkRP.createMoneyBag(tr.HitPos + tr.HitNormal * 4, amount, ply)
	if not IsValid(bag) then
		ply:addMoney(amount)
		return ""
	end

	DarkRP.log("money", ply, nil, "выбросил деньги " .. currency() .. amount, nil, nil, bag)

	return ""
end)

DarkRP.defineChatCommand("givemoney", function(ply, args)
	if not ply:Alive() or not ply:IsUnrestrained() or ply:InVehicle() then return "" end
	if DarkRP.NetDelay(ply, 1) then return "" end

	local amount = moneyArg(ply, args)
	if not amount then return "" end

	local tr = util.TraceLine({
		start = ply:EyePos(),
		endpos = ply:EyePos() + ply:GetAimVector() * 100,
		filter = ply
	})

	local target = tr.Entity

	if not IsValid(target) or not target:IsPlayer() or not target:Alive() or target.DarkRPUnInitialized then
		return ""
	end

	if not ply:canAfford(amount) then
		return ""
	end

	ply:addMoney(-amount)
	target:addMoney(amount)

	DarkRP.log("money", ply, target, "передал деньги " .. currency() .. amount)

	return ""
end)
