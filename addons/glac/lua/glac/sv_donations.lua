--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Пожертвования с сайта - не используются (ваш ответ к шагу 14): платежей
	нет, кредиты выдаёт администратор. Остались вызовы автора:
	Glac.Donations.Claim (команда sAdmin claim_donation) - всегда «нет платежа»;
	CheckDonations (зелёная кнопка у баланса) - только обновляет баланс.
---------------------------------------------------------------------------]]
Glac.Donations = Glac.Donations or {}

function Glac.Donations.Claim(paymentId, callback)
	if isfunction(callback) then callback({success = false}) end
end

Glac.NetReceive("CheckDonations", function(ply)
	if not IsValid(ply) or DarkRP.NetDelay(ply, 2) then return end

	Glac.SendCredits(ply)
end)
