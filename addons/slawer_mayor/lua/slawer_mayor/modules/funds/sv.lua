--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Казна района (бюджет ратуши) - сервер; читают её GetFunds и GetMaxFunds
	(sh.lua рядом), показывает компьютер мэра (cl.lua)

	Slawer.Mayor:SetFunds(n), Slawer.Mayor:AddFunds(n) - деньги казны,
	  от 0 до максимума: сверх максимума не копится;
	Slawer.Mayor:SetMaxFunds(n) - максимум (улучшение "Локализация бюджета"
	  в configuration.lua), казна сверх нового максимума срезается.
	Значения - глобальные переменные "Slawer.Mayor:Funds" и
	"Slawer.Mayor:MaxFunds". При старте сервера - CFG.DefaultFunds и
	CFG.DefaultMaxFunds (500 и 5000), между рестартами казна не хранится:
	так задано в настройках автора ("City funds when the server starts").

	В казну идут налоги с покупок в F4 и у NPC (shared/makethings.lua),
	в кассах и торговых автоматах, пошлина за регистрацию оружия, запчасти
	механика (inventory/sv_registers.lua, spawned_vendor) и оплаченные
	штрафы (policemen/sv_tickets.lua)
---------------------------------------------------------------------------]]

local MAX_INT = 2147483647 -- GlobalInt: 32 бита со знаком

local function amount(n)
	n = tonumber(n)
	if not n or n ~= n or n == math.huge or n == -math.huge then return nil end

	return math.Round(n)
end

function Slawer.Mayor:SetMaxFunds(n)
	n = amount(n)
	if not n then return end

	SetGlobalInt("Slawer.Mayor:MaxFunds", math.Clamp(n, 0, MAX_INT))

	self:SetFunds(self:GetFunds())
end

function Slawer.Mayor:SetFunds(n)
	n = amount(n)
	if not n then return end

	SetGlobalInt("Slawer.Mayor:Funds", math.Clamp(n, 0, self:GetMaxFunds()))
end

function Slawer.Mayor:AddFunds(n)
	n = amount(n)
	if not n or n == 0 then return end

	self:SetFunds(self:GetFunds() + n)
end

hook.Add("InitPostEntity", "Slawer.Mayor.Funds", function()
	if Slawer.Mayor.FundsLoaded then return end
	Slawer.Mayor.FundsLoaded = true

	Slawer.Mayor:SetMaxFunds(Slawer.Mayor.CFG.DefaultMaxFunds or 0)
	Slawer.Mayor:SetFunds(Slawer.Mayor.CFG.DefaultFunds or 0)
end)
