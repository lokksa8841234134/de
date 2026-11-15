--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Сигареты, таблетки и наркотики - сервер

	Как еда (sv_food.lua): [E] по предмету на земле (spawned_junk, ENT:Use)
	или [E] с ним в руках (ключи; из F4 - кнопка "в руки"). Что
	употребляется и как - таблица DRUGS по классу предмета (каталог
	spawnlist/junk.lua), остальной хлам [E] не трогает. Числа и эффекты
	сервера автора не сохранились - DRUGS додуман по рецептам станции
	фармацевта (workstation_pharm), справке F1, подсказкам предметов и
	эффектам клиента.

	Способ (how): pill - внутрь (таблетки, сироп); smoke - закурить
	(сигарета, сигара, самокрутка, трубка); snort - вдохнуть порошок;
	inject - укол; bandage - повязка; bong - бонг; hookah - кальян (сам
	кальян остаётся). Занимает TIME секунд: полоса прогресса
	(DrawProgressBar), звук SOUNDS, модель предмета в правой руке у всех
	("ShowModelR", у кальяна - нет). Отошёл дальше USE_RANGE, предмет
	унесли, потерял сознание, сел в машину, надели наручники, умер - не
	засчитано (RemovePropgressBar). Пока употребляют, предмет не взять
	(InUse); есть и употреблять одновременно нельзя. Между приёмами -
	USE_GAP секунд (ply.eatdelay, общий с едой). Через рот (MOUTH) - не с
	сигаретой во рту и не в закрытой маске (ply:CanConsume автора и его
	уведомление); укол и повязка - можно. Закурить и бонг - нужна
	зажигалка в карманах (lighter), курить трубкой - и трубка (pipe).
	Чего-то не хватает - [E] ничего не делает.

	Курение: предмет во рту (переменная "mouth", модели
	MCR.Attachments.smoking: cigar, sigar, joint, pipe) и значок курения
	("smoke") на smoke секунд, дым изо рта сразу и раз в PUFF_EVERY секунд
	(UI-эффект "smoke" игрокам в PUFF_RANGE, у курящего - эффект на
	экране). Потерял сознание, умер, сменил персонажа - докурить не
	получится. Пачка сигарет - uses сигарет: последняя - пачка исчезает,
	иначе uses и вес убавляются (как порции еды); бонг так же.
	Бонг и кальян - дым ("hookah2": у игрока, у кальяна - и из кальяна) и
	эффект на экране ("hookah"); не чаще раза в HOOKAH_GAP секунд.

	Эффекты (поля DRUGS): stats - временные состояния на time секунд
	(ply:AddTempStat, sv_stats.lua): relax ("Под воздействием"), morph,
	heroin, coca, meth, nark, focus ("Концентрация"), stamina; cure -
	снять состояние (тошнота, кашель, шок, кровотечение); alcohol, toxity -
	опьянение и отравление (минус - снять); karma - рассудок; addict -
	зависимость вида kind (ply:AddAddiction, sv_medic.lua).
	Таблетки LS4 (lsd) - эффект ЛСД у клиента ("lsd", LSD_TIME секунд).
	Клиент рисует его хуком HUDPaint "NLR" и этим гасит предупреждение
	N.L.R., поэтому ply.LSDUntil: MES.ShowNLR (sv_forensic.lua) покажет
	N.L.R. снова, когда ЛСД кончится.

	Передозировка. Справка F1: "Чем препарат сильнее - тем он опаснее ...
	передоз штука страшная". Сильные препараты (dose) копятся в дозе
	игрока, она убывает на DOSE_DECAY в секунду; набралось DOSE_OD -
	передозировка. Подсказки пакетиков: "Если перепутать дорожку с
	героином (дозу с кокаином), то будет очень 'весело'" - героин (heroin)
	под кокаином или метамфетамином и стимулятор (stimulant) под героином -
	передозировка сразу. Под налоксоном ("narcan") опиаты (opioid) не
	действуют: ни состояний, ни зависимости, ни дозы.
	Передозировка ("overdose"): эффект на экране, хрип, через OD_FALL
	секунд - без сознания, через OD_DEATH секунд от начала - смерть
	("Передозировка наркотическими веществами" в деле судмедэкспертизы).
	Таймер смерти - UserID.."overdose", его снимают налоксон и адреналин
	автора (sh_config.lua) и полное лечение. Состояния препаратов (OD_KEEP)
	держатся до конца передозировки: по ним медик выбирает лекарство -
	налоксон от морфина и героина, адреналин от кокаина и метамфетамина.
	Сняли - через OD_WAKE секунд игрок приходит в себя. Очнулся раньше
	(администратор) - передозировка проходит. Налоксон автора снимает
	таймер всегда: при передозировке стимуляторами смерти уже не будет,
	игрок очнётся, когда кончится время без сознания.

	API (сервер):
	DarkRP.UseJunk(ply, ent[, сразу]) - употребить; true - начал или
	употребил.
	DarkRP.StopUsingJunk(ply) - прервать.
	DarkRP.IsUsingJunk(ply) - употребляет ли сейчас.
	hook "DarkRP.PlayerUsedDrug"(ply, класс, поля DRUGS, ent) - засчитано
	(ent уже может быть удалён).
---------------------------------------------------------------------------]]

local USE_RANGE = 100 -- от глаз до центра предмета, как у еды
local USE_GAP = 0.5 -- секунд между приёмами (ply.eatdelay)
local USE_CHECK = 0.1 -- секунд: проверка, что игрок может продолжать
local SOUND_LEVEL = 60

-- секунд на приём
local TIME = {
	pill = 1,
	smoke = 2,
	snort = 3,
	inject = 2,
	bandage = 4, -- как бинты в меню медика
	bong = 3,
	hookah = 3,
}

local SOUNDS = {
	pill = "gb_sfx/craft/pills.wav",
	inject = "player/use/syringe.wav",
	bandage = "player/heal.mp3",
}

-- через рот: ply:CanConsume
local MOUTH = {pill = true, smoke = true, snort = true, bong = true, hookah = true}

local PUFF_EVERY = 10 -- секунд между затяжками (эффект на экране у клиента - 10 секунд)
local PUFF_RANGE = 1500 -- кто видит дым
local HOOKAH_GAP = 60 -- секунд между бонгом и кальяном (ply.DrugHookah)

local DOSE_DECAY = 0.2 -- дозы в секунду
local DOSE_OD = 100
local OD_FALL = 10 -- секунд до потери сознания
local OD_DEATH = 240 -- секунд от начала до смерти
local OD_WAKE = 10 -- секунд: сняли передозировку - очнуться
local OD_SOUND = "metromod/breath_1.wav"
local OD_KEEP = {"relax", "morph", "heroin", "coca", "meth"}

local TICK = 1
local LSD_TIME = 185 -- клиент убирает эффект через 180 + 3 секунды, 2 - запас на пинг

local CIGARETTE = {how = "smoke", mouth = "cigar", smoke = 60, karma = 5, lighter = true}

local DRUGS = {
	-- таблетки: рецепты станции фармацевта
	pills0 = {how = "pill"}, -- "Плацебо"
	pills1 = {how = "pill", alcohol = -50, cure = {"nausea"}}, -- "Средство от похмелья"
	pills2 = {how = "pill", karma = 15}, -- "Антидепрессанты"
	pills3 = {how = "pill", stats = {"focus"}, time = 120}, -- "Таблетки C1"
	pills4 = {how = "pill", stats = {"morph", "relax"}, time = 90, addict = 2, kind = "morph", dose = 10, opioid = true}, -- "Обезболивающее"
	pills5 = {how = "pill", toxity = -30, cure = {"nausea"}}, -- "Активированный уголь"
	pills6 = {how = "pill", stats = {"stamina"}, time = 120}, -- "Кофеиновые таблетки"
	pills7 = {how = "pill", cure = {"cough"}}, -- "Сироп от кашля"
	pills8 = {how = "pill", stats = {"nark", "relax"}, time = 180, lsd = true}, -- "Таблетки LS4"
	headcure = {how = "pill", cure = {"shock"}}, -- "Средство от головы"
	bandage = {how = "bandage", cure = {"bleeding"}},

	-- табак
	pack_paddolo = CIGARETTE,
	pack_jamal = CIGARETTE,
	pack_whisher = CIGARETTE,
	pack_bigc = CIGARETTE,
	pack_noir = CIGARETTE,
	sigar = {how = "smoke", mouth = "sigar", smoke = 120, karma = 10, lighter = true},
	dry_tabacco_small = {how = "smoke", mouth = "pipe", smoke = 90, karma = 5, lighter = true, pipe = true},
	hookah = {how = "hookah", karma = 5, keep = true},

	-- наркотики
	joint = {how = "smoke", mouth = "joint", smoke = 90, stats = {"relax"}, time = 120, karma = 5, addict = 2, kind = "weed", lighter = true},
	dry_weed_small = {how = "smoke", mouth = "pipe", smoke = 90, stats = {"relax"}, time = 120, karma = 5, addict = 2, kind = "weed", lighter = true, pipe = true},
	bong = {how = "bong", stats = {"relax"}, time = 120, karma = 5, addict = 2, kind = "weed", lighter = true},
	craft_coca_small = {how = "smoke", mouth = "pipe", smoke = 30, stats = {"coca", "relax"}, time = 150, addict = 8, kind = "coca", dose = 35, stimulant = true, lighter = true, pipe = true}, -- крэк
	done_coca_small = {how = "snort", stats = {"coca", "relax"}, time = 180, addict = 6, kind = "coca", dose = 35, stimulant = true},
	done_meth_small = {how = "snort", stats = {"meth", "relax"}, time = 180, addict = 10, kind = "meth", dose = 40, stimulant = true},
	done_heroin_small = {how = "snort", stats = {"heroin", "relax"}, time = 180, addict = 12, kind = "heroin", dose = 40, opioid = true, heroin = true},
	done_heroin_syr = {how = "inject", stats = {"heroin", "relax"}, time = 180, addict = 10, kind = "heroin", dose = 45, opioid = true, heroin = true},
	dry_opium_small = {how = "inject", stats = {"morph", "relax"}, time = 60, addict = 10, kind = "morph", dose = 30, opioid = true}, -- "Морфин"
	fentanyl = {how = "inject", stats = {"heroin", "morph", "relax"}, time = 240, addict = 20, kind = "heroin", dose = 60, opioid = true, heroin = true},
}

-- [ply] = {ent, drug, class, finish, sound, model, material}
local using = {}
-- [ply] = {mouth, finish, puff}
local smoking = {}
-- [ply] = доза
local doses = {}
-- [ply] = {fall, fallen, cured, wake}
local overdosed = {}

local function nearby(pos)
	local list = {}
	local range = PUFF_RANGE * PUFF_RANGE

	for _, ply in ipairs(player.GetAll()) do
		if ply:GetPos():DistToSqr(pos) <= range then
			list[#list + 1] = ply
		end
	end

	return list
end

local function has(ply, class)
	return istable(ply.inv) and (ply:HaveItem(INV_JUNK, class) or 0) > 0
end

local function hasTools(ply, drug)
	if drug.lighter and not has(ply, "lighter") then return false end
	if drug.pipe and not has(ply, "pipe") then return false end

	return true
end

local function blocked(ply, ent)
	if not ply:Alive() or ply:getDarkRPVar("unconscious") or ply:getDarkRPVar("HandCuffed") or ply:InVehicle() then return true end
	if IsValid(ply.pk_pill_ent) or ent.McINVTaken then return true end
	if ply:EyePos():DistToSqr(ent:WorldSpaceCenter()) > USE_RANGE * USE_RANGE then return true end

	local user = ent.InUse
	if user == true or (isentity(user) and IsValid(user) and user ~= ply) then return true end

	local keys = ent.Draged
	if keys == true then return true end
	if isentity(keys) and IsValid(keys) and keys:GetOwner() ~= ply then return true end

	return false
end

local function stop(ply, finished)
	local u = using[ply]
	if not u then return end

	using[ply] = nil

	if IsValid(u.ent) and u.ent.InUse == ply then u.ent.InUse = nil end
	if not IsValid(ply) then return end

	if u.sound then ply:StopSound(u.sound) end
	if finished then return end

	net.SendSingleMessage("RemovePropgressBar", ply)

	if u.model then
		DarkRP.UIEffect(nil, "ShowModelR", {ply:UserID(), 0, u.model, u.material})
	end
end

--[[---------------------------------------------------------------------------
	Курение
---------------------------------------------------------------------------]]
local function puff(ply)
	DarkRP.UIEffect(nearby(ply:GetPos()), "smoke", {idx = ply:EntIndex()})
end

local function stopSmoking(ply)
	local s = smoking[ply]
	if not s then return end

	smoking[ply] = nil

	if not IsValid(ply) then return end

	if ply:getDarkRPVar("mouth") == s.mouth then
		ply:SetDarkRPVar("mouth", nil)
	end

	ply:SetSelfDarkRPVar("smoke", nil)
end

local function startSmoking(ply, drug, CT)
	smoking[ply] = {mouth = drug.mouth, finish = CT + drug.smoke, puff = CT + PUFF_EVERY}

	ply:SetDarkRPVar("mouth", drug.mouth)
	ply:AddTempStat("smoke", drug.smoke)

	puff(ply)
end

--[[---------------------------------------------------------------------------
	Передозировка
---------------------------------------------------------------------------]]
local function clearOverdose(ply)
	if not overdosed[ply] then return end

	-- сначала из списка: DarkRPVarChanged ниже не примет это за лечение
	overdosed[ply] = nil

	if not IsValid(ply) then return end

	timer.Remove(ply:UserID() .. "overdose")

	if ply:getDarkRPVar("overdose") then
		ply:SetSelfDarkRPVar("overdose", nil)
	end
end

local function overdose(ply)
	if overdosed[ply] or not ply:Alive() then return end

	overdosed[ply] = {fall = CurTime() + OD_FALL}

	for _, var in ipairs(OD_KEEP) do
		if ply:getDarkRPVar(var) then
			ply:AddTempStat(var, OD_DEATH + TICK)
		end
	end

	ply:SetSelfDarkRPVar("overdose", true)

	DarkRP.UIEffect(ply, "overdose")
	ply:EmitSound(OD_SOUND, SOUND_LEVEL)

	timer.Create(ply:UserID() .. "overdose", OD_DEATH, 1, function()
		if IsValid(ply) and ply:Alive() and ply:getDarkRPVar("overdose") then
			ply:Kill()
		end
	end)
end

-- передозировку сняли (налоксон, адреналин, полное лечение)
hook.Add("DarkRPVarChanged", "DarkRP.Drugs", function(ply, var, _, new)
	if var ~= "overdose" or new ~= nil then return end

	local st = overdosed[ply]
	if not st or st.cured then return end

	timer.Remove(ply:UserID() .. "overdose")
	doses[ply] = nil

	if st.fallen then
		st.cured = true
		st.wake = CurTime() + OD_WAKE
	else
		overdosed[ply] = nil
	end
end)

--[[---------------------------------------------------------------------------
	Приём
---------------------------------------------------------------------------]]
local function consume(ent, class, drug)
	if drug.keep or not IsValid(ent) then return end

	local uses = ent.Getuses and tonumber(ent:Getuses()) or 0

	if uses > 1 then
		local data = DarkRP.Junk[class] or {}

		ent:Setuses(uses - 1)
		ent.weight = (uses - 1) * (tonumber(data.weight) or 0) + (tonumber(data.conwht) or 0)
	else
		ent.McINVTaken = true
		ent:Remove()
	end
end

local function apply(ply, ent, class, drug)
	if not hasTools(ply, drug) then return end

	local CT = CurTime()
	local narcan = drug.opioid and ply:getDarkRPVar("narcan")
	local mixed = not narcan and ((drug.heroin and (ply:getDarkRPVar("coca") or ply:getDarkRPVar("meth"))) or (drug.stimulant and ply:getDarkRPVar("heroin")))

	if drug.mouth then
		startSmoking(ply, drug, CT)
	end

	if not narcan then
		for _, stat in ipairs(drug.stats or {}) do
			ply:AddTempStat(stat, drug.time)
		end

		if drug.addict then
			ply:AddAddiction(drug.addict, drug.kind)
		end
	end

	for _, stat in ipairs(drug.cure or {}) do
		if ply:getDarkRPVar(stat) then
			ply:SetSelfDarkRPVar(stat, nil)
		end
	end

	if drug.alcohol then ply:AddAlcohol(drug.alcohol) end
	if drug.toxity then ply:AddToxity(drug.toxity) end
	if drug.karma then ply:addKarma(drug.karma) end

	if drug.how == "bong" or drug.how == "hookah" then
		local list = nearby(ply:GetPos())

		DarkRP.UIEffect(list, "hookah2", {idx = ply:EntIndex()})

		if drug.how == "hookah" and IsValid(ent) then
			DarkRP.UIEffect(list, "hookah2", {idx = ent:EntIndex()})
		end

		DarkRP.UIEffect(ply, "hookah")
		ply.DrugHookah = CT + HOOKAH_GAP
	end

	if drug.lsd then
		ply.LSDUntil = CT + LSD_TIME
		DarkRP.UIEffect(ply, "lsd")

		if MES and MES.ShowNLR then MES.ShowNLR(ply) end
	end

	ply.eatdelay = CT + USE_GAP

	consume(ent, class, drug)

	if drug.dose and not narcan then
		local dose = (doses[ply] or 0) + drug.dose
		doses[ply] = dose

		if dose >= DOSE_OD then overdose(ply) end
	end

	if mixed then overdose(ply) end

	hook.Run("DarkRP.PlayerUsedDrug", ply, class, drug, ent)
end

function DarkRP.UseJunk(ply, ent, instant)
	if not IsValid(ply) or not ply:IsPlayer() or not IsValid(ent) or ent:GetClass() ~= "spawned_junk" then return false end
	if using[ply] or (DarkRP.IsEating and DarkRP.IsEating(ply)) then return false end

	local class = ent.Geteclass and ent:Geteclass()
	local drug = isstring(class) and DRUGS[class]
	if not drug or blocked(ply, ent) then return false end

	local CT = CurTime()

	if MOUTH[drug.how] then
		if not ply:CanConsume() then return false end
	elseif ply.eatdelay and ply.eatdelay > CT then
		return false
	end

	if (drug.how == "bong" or drug.how == "hookah") and (ply.DrugHookah or 0) > CT then return false end
	if not hasTools(ply, drug) then return false end

	local delay = TIME[drug.how] or 0

	if instant or delay <= 0 then
		apply(ply, ent, class, drug)
		return true
	end

	local model, material
	local snd = SOUNDS[drug.how]

	if drug.how ~= "hookah" then
		model, material = ent:GetModel(), ent:GetMaterial()
	end

	using[ply] = {ent = ent, drug = drug, class = class, finish = CT + delay, sound = snd, model = model, material = material}
	ent.InUse = ply

	net.Start("DrawProgressBar")
		net.WriteFloat(delay)
	net.Send(ply)

	if snd then ply:EmitSound(snd, SOUND_LEVEL) end

	if model then
		DarkRP.UIEffect(nil, "ShowModelR", {ply:UserID(), delay, model, material})
	end

	return true
end

function DarkRP.StopUsingJunk(ply)
	stop(ply)
end

function DarkRP.IsUsingJunk(ply)
	return using[ply] ~= nil
end

timer.Create("DarkRP.UsingJunk", USE_CHECK, 0, function()
	local CT = CurTime()

	for ply, u in pairs(using) do
		if not IsValid(ply) then
			stop(ply)
		elseif not IsValid(u.ent) or blocked(ply, u.ent) then
			stop(ply)
		elseif u.finish <= CT then
			stop(ply, true)
			apply(ply, u.ent, u.class, u.drug)
		end
	end
end)

timer.Create("DarkRP.Drugs", TICK, 0, function()
	local CT = CurTime()

	for ply, dose in pairs(doses) do
		dose = dose - DOSE_DECAY * TICK
		doses[ply] = (IsValid(ply) and dose > 0) and dose or nil
	end

	for ply, st in pairs(overdosed) do
		if not IsValid(ply) then
			overdosed[ply] = nil
		elseif st.cured then
			if st.wake <= CT then
				overdosed[ply] = nil

				if ply:Alive() and ply:IsUncon() then
					ply:UnRagdollize()
				end
			end
		elseif not st.fallen then
			if st.fall <= CT then
				st.fallen = true
				ply:Ragdollize(OD_DEATH, true)
			end
		elseif not ply:IsUncon() then
			-- очнулся раньше (администратор): передозировка прошла
			clearOverdose(ply)
		end
	end

	for ply, s in pairs(smoking) do
		if not IsValid(ply) or not ply:Alive() or ply:IsUncon() or ply:getDarkRPVar("mouth") ~= s.mouth or s.finish <= CT then
			stopSmoking(ply)
		elseif s.puff <= CT then
			s.puff = CT + PUFF_EVERY
			puff(ply)
		end
	end
end)

-- [E] с предметом в руках: смотрит в сторону, а не на него
hook.Add("KeyPress", "DarkRP.Drugs", function(ply, key)
	if key ~= IN_USE or using[ply] then return end

	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) or wep:GetClass() ~= "keys" then return end

	local held = wep.EntHolding
	if not IsValid(held) or held:GetClass() ~= "spawned_junk" then return end

	-- смотрит на дверь, NPC, игрока - [E] для них
	local tr = ply:GetEyeTrace()
	local target = tr.Entity

	if IsValid(target) and target ~= held and tr.HitPos:DistToSqr(ply:EyePos()) < USE_RANGE * USE_RANGE then return end

	DarkRP.UseJunk(ply, held)
end)

local function reset(ply)
	stop(ply)
	stopSmoking(ply)
	clearOverdose(ply)
	doses[ply] = nil
end

hook.Add("PlayerDeath", "DarkRP.Drugs", reset)
hook.Add("PlayerSilentDeath", "DarkRP.Drugs", reset)
hook.Add("PlayerSpawn", "DarkRP.Drugs", reset)
hook.Add("PlayerDisconnected", "DarkRP.Drugs", reset)
hook.Add("MCR.CharacterReset", "DarkRP.Drugs", reset)
