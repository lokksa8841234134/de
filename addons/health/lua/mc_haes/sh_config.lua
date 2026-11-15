--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
local function getHP(ply, medic)
	local hp = ply:Health()
	if medic:Team() ~= 13 then
		if hp < 25 then
			return "Плохое"
		end

		if hp > 25 and hp < 60 then
			return "Удовлетворительное"
		end

		return "Нормальное"
	end

	return hp .. "%"
end

MES.List = {
	{"blood", "Общее состояние", function(ply, stat, medic)
		local sta = "Общее здоровье: " .. getHP(ply, medic)

		if ply:getDarkRPVar("unconscious") then
			sta = sta .. " Без сознания."
		end

		if not ply:Alive() then
			sta = "Нет дыхания. Пульс отсутвует или слабый."
		end

		if medic:Team() ~= 13 then return sta end

		if ply:getDarkRPVar("bleeding") then
			sta = sta .. " Внешнее кровотечение, открытая рана"
		end

		if ply:getDarkRPVar("cold") and ply:getDarkRPVar("cold") > 8 then
			sta = sta .. " Обморожение."
		end

		if ply:getDarkRPVar(stat) and ply:getDarkRPVar(stat) < 30 then
			return "Возможна сильная потеря крови. " .. sta
		end

		if ply:getDarkRPVar(stat) and ply:getDarkRPVar(stat) < 60 then
			return "Возможно малокровие. " .. sta
		end

		return sta
	end},
	{"fracture", "Перелом ноги", function(ply, stat)
		if ply:getDarkRPVar(stat) then
			return "Есть заметный перелом ноги"
		end

		return "Нет заметного перелома ног"
	end},
	{"fracturearm", "Перелом руки", function(ply, stat)
		if ply:getDarkRPVar(stat) then
			return "Есть заметный перелом руки"
		end

		return "Нет заметного перелома рук"
	end},
	{"alcohol", "Воздействия", function(ply, stat)
		if ply:getDarkRPVar("overdose") then
			return "Передоз наркотическими веществами"
		end

		if ply:getDarkRPVar("relax") then
			return "Расширенные зрачки" .. (ply:getDarkRPVar(stat) and ". Заметный запах спирта, притупленная реакция" or "")
		end

		if ply:getDarkRPVar(stat) then
			return "Заметный запах спирта, притупленная реакция"
		end

		return "Нет заметных воздействий от веществ"
	end},
}

MES.ListHeal = {
	{"Наложить бинты", 5, function(medic, ply)
		if ply:getDarkRPVar("bleeding") then
			ply:SetSelfDarkRPVar("bleeding", nil)
			if IsValid(medic) and medic:isEMS() then
				medic:JobXPAdd("fdny", math.random(5))
			end
		end
	end, "player/heal.mp3", "накладывает бинты на человека", 4},
	{"Ввести налоксон", 5, function(medic, ply)
		if (ply:getDarkRPVar("morph") or ply:getDarkRPVar("heroin")) and ply:getDarkRPVar("overdose") then
			ply:SetSelfDarkRPVar("overdose", nil)
			if IsValid(medic) and medic:isEMS() then
				medic:JobXPAdd("fdny", 10)
			end
		end

		if timer.Exists(ply:UserID() .. "overdose") then
			timer.Remove(ply:UserID() .. "overdose")
		end

		ply:SetSelfDarkRPVar("relax", nil)
		ply:SetSelfDarkRPVar("morph", nil)
		ply:SetSelfDarkRPVar("heroin", nil)
		ply:AddTempStat("narcan", 110)
	end, "player/use/syringe.wav", "вводит препарат человеку", 2, function(ply)
		return not ply:getDarkRPVar("narcan")
	end},
	{"Ввести адреналин", 15, function(medic, ply)
		-- передозировка стимуляторами: кокаин, метамфетамин
		if (ply:getDarkRPVar("coca") or ply:getDarkRPVar("meth")) and ply:getDarkRPVar("overdose") then
			ply:SetSelfDarkRPVar("overdose", nil)
			timer.Remove(ply:UserID() .. "overdose")
			if IsValid(medic) and medic:isEMS() then
				medic:JobXPAdd("fdny", 10)
			end
		end

		if ply:Alive() then
			ply:SetHealth(math.Clamp(10, ply:Health(), ply:GetMaxHealth()))
		end

		if ply:getDarkRPVar("cold") and ply:getDarkRPVar("cold") > 0 then
			ply:SetSelfDarkRPVar("cold", 0)
			if IsValid(medic) and medic:isEMS() then
				medic:JobXPAdd("fdny", 10)
			end
		end

		ply:AddTempStat("adren", 110)
		ply:AddTempStat("stamina", 30)
	end, "player/use/syringe.wav", "вводит препарат человеку", 2, function(ply)
		return not ply:getDarkRPVar("adren")
	end},
	{"Ввести физраствор", 10, function(medic, ply, rag)
		ply.saline = CurTime() + 300
		if ply:getDarkRPVar("blood") < 15 then
			ply:BloodLevel(15)
			if IsValid(medic) and medic:isEMS() then
				medic:JobXPAdd("fdny", 5)
			end
		end
	end, "player/use/syringe.wav", "вводит препарат человеку", 5, function(ply)
		return not ply.saline or ply.saline < CurTime()
	end},
	{"Начать СЛР", 5, function(medic, ply, rag)
		MES.SLR(medic, ply, rag)
	end, "metromod/breath_1.wav", "приступает к СЛР", 10, function(ply)
		return not ply:Alive()
	end, "СЛР ничем не поможет"},
	{"Ввести морфин", 30, function(medic, ply, rag)
		if ply:getDarkRPVar("overdose") and rag then
			rag.crithit = true
		end

		ply:AddAddiction(10, "morph")
		ply:AddTempStat("morph", 60)
		ply:AddTempStat("relax", 60)
	end, "player/use/syringe.wav", "вводит препарат человеку", 2, function(ply)
		return not ply:getDarkRPVar("morph")
	end},
}

MES.ListHealRest = {
	[3] = true,
	[4] = true,
	[6] = true,
}