--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Судмедэкспертиза - сервер: травмы, причина смерти, упаковка тела,
	дела судмедэкспертизы, NLR

	Травмы. Урон живому игроку (и без сознания: урон рэгдолла получает
	игрок, sv_ragdoll.lua) записывается в ply.MESWounds: [вид] = сколько
	раз. Вид - класс оружия из MES.gunz или MES.melee (core/sh_init.lua,
	их названия рисует клиент компьютера участка) или общий вид урона из
	KINDS ниже: пуля другого оружия, взрыв, ожоги, падение, транспорт,
	холодное оружие, удары, электрошок, утопление, отравление.
	Полное лечение (ply:MedHeal, sv_medic.lua) и новая жизнь травмы
	стирают, подъём на месте после СЛР - нет.

	Смерть (DoPlayerDeath) - запись о погибшем: время и место, имя, пол и
	дата рождения, причина: ply.MESCause на время ply:Kill (истощение и
	отравление, hungermod/sv_init.lua), иначе по смертельному удару (без
	удара - переохлаждение от обморожения в воде, sv_medic.lua,
	кровопотеря, передозировка или "не установлена"), травмы до смерти и
	признаки (сильная потеря крови, переломы, наркотики, алкоголь,
	обморожение, истощение, обезвоживание, отравление).
	Урон по трупу в первые PERI секунд - ещё травмы до смерти, позже -
	повреждения после смерти ("Прочие увечья" у клиента). Слабые (меньше
	CRUSH_MIN) удары предметов и удары о мир не считаются. Смертельный удар
	по рэгдоллу без сознания (его получает игрок) - одна травма, не две.

	Упаковка тела - консольная команда bag_ragdoll ("Упаковать тело" в
	меню по телу, client/vgui.lua): сотрудник с рацией
	(GAMEMODE.RadioTeams) смотрит на труп или на носилки с телом не дальше
	REACH. Тело убирается, вернуть игрока к жизни уже нельзя, возрождается
	он как обычно. Заводится дело #номер: номера по порядку, дела в памяти
	сервера до перезапуска, хранятся MAX_CASES последних.

	Дела читают компьютер участка (slawer_mayor, modules/policemen/
	sv_jail.lua: вкладка "Дела судмедэкспертизы") и протокол задержания
	(police/sv_arrest.lua: "Прикрепить дело").
	MES.GetDeathLog() - дела для клиента, новые первыми: {время смерти
	(os.time), текст заключения, номер, повреждения после смерти, травмы
	до смерти}. Травмы - только по оружию из MES.gunz и MES.melee:
	[класс] = {сколько} до смерти, [класс] = сколько после, нет таких -
	false. Остальные виды - в тексте заключения.
	MES.GetDeathCase(номер) - дело или nil.

	NLR. Возродившемуся как обычно (не после СЛР) - DarkRP.UIEffect "NLR"
	{место смерти, CurTime()}: клиент (client/util.lua) 1300 секунд
	предупреждает его у места смерти, и уведомление "nlr" из языка.
	ply.nlr - то же для сервера, его снимает sAdmin stopnlr.
	Эффект ЛСД у клиента рисуется тем же хуком HUDPaint "NLR": пока он
	идёт (ply.LSDUntil, hungermod/sv_drugs.lua), предупреждение ждёт и
	появляется после него. MES.ShowNLR(ply) - показать предупреждение
	снова (после таблеток ЛСД).
---------------------------------------------------------------------------]]

local REACH = 200 -- до тела от глаз
local MAX_CASES = 50
local PERI = 0.5 -- секунд после смерти: урон по телу - ещё травма до смерти
local BLOOD_LOW = 30 -- как в осмотре медика (MES.List)
local COLD_SIGN = 8
local CRUSH_MIN = 10
local BAG_DELAY = 1
local ME_COLOR = Color(245, 190, 110)
local DATE = "%d.%m %H:%M" -- без года: в игре свой год
local NLR_TIME = 1300 -- секунд, как у клиента (UI-эффект "NLR")

local BLED = "Обильная кровопотеря"
local OVERDOSE = "Передозировка наркотическими веществами"
local FROZEN = "Переохлаждение" -- умер от обморожения (ply.MESFrozen, sv_medic.lua)
-- голод и отравление (ply.MESCause, hungermod/sv_init.lua)
local STARVED = "Истощение"
local POISONED = "Отравление"
local TOX_SIGN = 30 -- отравление уже с тошнотой
local DRUGS = {"relax", "morph", "meth", "heroin", "coca"}

-- травматический снаряд (police_beanbag) - DMG_PARALYZE
local SHOTS = bit.bor(DMG_BULLET, DMG_BUCKSHOT, DMG_PARALYZE)
local ENV = bit.bor(DMG_BURN, DMG_SLOWBURN, DMG_FALL, DMG_BLAST, DMG_DROWN, DMG_CRUSH, DMG_VEHICLE, DMG_SHOCK, DMG_POISON, DMG_NERVEGAS, DMG_ACID, DMG_RADIATION)
local HITS = bit.bor(DMG_SLASH, DMG_CLUB)

-- {типы урона, вид, причина смерти, в тексте заключения}
local KINDS = {
	{SHOTS, "bullet", "Огнестрельное ранение", "огнестрельные ранения - %s"},
	{DMG_BLAST, "blast", "Взрывная травма", "травмы от взрыва - %s"},
	{bit.bor(DMG_BURN, DMG_SLOWBURN), "burn", "Ожоги", "ожоги"},
	{DMG_FALL, "fall", "Травмы от падения с высоты", "травмы от падения - %s"},
	{DMG_VEHICLE, "vehicle", "Травмы от наезда транспорта", "травмы от наезда транспорта - %s"},
	{DMG_SLASH, "slash", "Резаная рана", "резаные раны - %s"},
	{DMG_CLUB, "club", "Удар тупым предметом", "ушибы, ссадины - %s"},
	{DMG_CRUSH, "crush", "Удар тяжёлым предметом", "ушибы от тяжёлых предметов - %s"},
	{DMG_SHOCK, "shock", "Электротравма", "электротравмы - %s"},
	{DMG_DROWN, "drown", "Утопление", "признаки утопления"},
	{bit.bor(DMG_POISON, DMG_NERVEGAS, DMG_ACID, DMG_RADIATION), "poison", "Отравление", "признаки отравления"},
}

-- оружие ближнего боя не из MES.melee: урон без типа
local MELEE = {0, "melee", "Травма от холодного оружия", "травмы от холодного оружия - %s"}

-- все виды в порядке текста заключения
local ALL, kindOf = {}, {}

for _, kind in ipairs(KINDS) do ALL[#ALL + 1] = kind end
ALL[#ALL + 1] = MELEE

for _, kind in ipairs(ALL) do kindOf[kind[2]] = kind end

-- [ply] = запись о последней смерти, до возрождения
local deaths = {}
-- [номер] = дело; order - номера по порядку
local cases, order = {}, {}
local lastCase = 0

local function add(list, key)
	list[key] = (list[key] or 0) + 1
end

--[[---------------------------------------------------------------------------
	Травмы
---------------------------------------------------------------------------]]
-- вид травмы по урону: класс оружия из таблиц MES или вид из KINDS
local function woundOf(victim, dmg)
	local kind = dmg:GetDamageType()
	local shot = bit.band(kind, SHOTS) ~= 0
	local weapon = dmg:GetInflictor()

	-- у пули источник - стрелок, оружие у него в руках
	if shot and IsValid(weapon) and weapon ~= victim and (weapon:IsPlayer() or weapon:IsNPC()) then
		weapon = weapon:GetActiveWeapon()
	end

	if IsValid(weapon) and weapon:IsWeapon() and bit.band(kind, ENV) == 0 then
		local class = weapon:GetClass()

		if MES.melee[class] then return class end
		-- не выстрел из огнестрельного - удар прикладом
		if MES.gunz[class] then return shot and class or "club" end
		if not shot and bit.band(kind, HITS) == 0 then return MELEE[2] end
	end

	for _, k in ipairs(KINDS) do
		if bit.band(kind, k[1]) ~= 0 then return k[2] end
	end
end

hook.Add("PostEntityTakeDamage", "MES.Forensic", function(ent, dmg, took)
	if not took or not ent:IsPlayer() or not ent:Alive() or dmg:GetDamage() <= 0 then return end

	local key = woundOf(ent, dmg)
	if not key then return end

	local list = ent.MESWounds or {}
	ent.MESWounds = list
	add(list, key)
end)

--[[---------------------------------------------------------------------------
	Смерть: запись о погибшем, урон по телу
---------------------------------------------------------------------------]]
local function causeOf(ply, key)
	if isstring(ply.MESCause) then return ply.MESCause end

	local gun = key and MES.gunz[key]
	if gun then return "Огнестрельное ранение " .. gun[1], gun[2] end

	local melee = key and MES.melee[key]
	if melee then return melee[1] end

	local kind = key and kindOf[key]
	if kind then return kind[3] end

	if ply.MESFrozen then return FROZEN end
	if ply:BloodLevel() <= 0 then return BLED end
	if ply:getDarkRPVar("overdose") then return OVERDOSE end

	return "Не установлена"
end

local function signsOf(ply, cause)
	local signs = {}

	if ply:BloodLevel() < BLOOD_LOW and cause ~= BLED then signs[#signs + 1] = "сильная потеря крови" end
	if ply:getDarkRPVar("fracture") then signs[#signs + 1] = "перелом ноги" end
	if ply:getDarkRPVar("fracturearm") then signs[#signs + 1] = "перелом руки" end

	if ply:getDarkRPVar("overdose") then
		if cause ~= OVERDOSE then signs[#signs + 1] = "передозировка наркотическими веществами" end
	else
		for _, var in ipairs(DRUGS) do
			if ply:getDarkRPVar(var) then
				signs[#signs + 1] = "следы наркотических веществ"
				break
			end
		end
	end

	if (tonumber(ply:getDarkRPVar("alcohol")) or 0) > 0 then signs[#signs + 1] = "следы алкоголя" end
	if (tonumber(ply:getDarkRPVar("cold")) or 0) > COLD_SIGN and cause ~= FROZEN then signs[#signs + 1] = "обморожение" end

	-- голод и жажда (hungermod): переменных нет - не считаются
	if (tonumber(ply:getDarkRPVar("energy")) or 1) <= 0 and cause ~= STARVED then signs[#signs + 1] = "истощение" end
	if (tonumber(ply:getDarkRPVar("thirst")) or 1) <= 0 then signs[#signs + 1] = "обезвоживание" end
	if (tonumber(ply:getDarkRPVar("toxity")) or 0) >= TOX_SIGN and cause ~= POISONED then signs[#signs + 1] = "отравление" end

	return signs
end

-- key - вид смертельного удара
local function newRecord(ply, key)
	local wounds = ply.MESWounds or {}
	ply.MESWounds = nil

	if key then add(wounds, key) end

	local cause, weapon = causeOf(ply, key)
	local born = tostring(ply:getDarkRPVar("age") or "")

	return {
		time = os.time(),
		ct = CurTime(),
		pos = ply:GetPos(),
		name = ply:FullName(),
		gen = ply:getDarkRPVar("gender") == "female" and "ЖЕН." or "МУЖ.",
		born = born ~= "" and born or "не установлена",
		cause = cause,
		weapon = weapon,
		signs = signsOf(ply, cause),
		wounds = wounds,
		post = {},
	}
end

-- урон без нападавшего рэгдолл передаёт игроку от мира (sv_ragdoll.lua)
local function attackerOf(dmg)
	local attacker = dmg:GetAttacker()

	return IsValid(attacker) and attacker or game.GetWorld()
end

hook.Add("DoPlayerDeath", "MES.Forensic", function(ply, _, dmg)
	-- смерть от голода или отравления (ply:Kill) - не удар
	local rec = newRecord(ply, dmg and not ply.MESCause and woundOf(ply, dmg) or nil)

	-- без сознания удар по рэгдоллу получает игрок: после смерти тот же
	-- удар доходит и до рэгдолла, уже трупа (порядок хуков не задан)
	if dmg then rec.hit = {dmg:GetDamageType(), attackerOf(dmg)} end

	deaths[ply] = rec
end)

-- урон по трупу или манекену на носилках (рэгдолл без сознания - урон игроку)
hook.Add("EntityTakeDamage", "MES.Forensic", function(ent, dmg)
	if ent:IsPlayer() or ent.ragdollize then return end

	local ply = ent.player
	if not IsValid(ply) or not ply:IsPlayer() or ply:Alive() or ply.DeathRagdoll ~= ent then return end

	local rec = deaths[ply]
	if not rec or dmg:GetDamage() <= 0 then return end

	-- смертельный удар уже в записи (DoPlayerDeath выше)
	local hit = rec.hit
	rec.hit = nil

	if hit and rec.ct == CurTime() and hit[1] == dmg:GetDamageType() and hit[2] == attackerOf(dmg) then return end

	local attacker = dmg:GetAttacker()

	if dmg:IsDamageType(DMG_CRUSH) and (dmg:GetDamage() < CRUSH_MIN or not IsValid(attacker) or attacker == ent or attacker == ply or attacker:IsWorld()) then
		return
	end

	local key = woundOf(ply, dmg)
	if not key then return end

	add(CurTime() - rec.ct <= PERI and rec.wounds or rec.post, key)
end)

--[[---------------------------------------------------------------------------
	Дела
---------------------------------------------------------------------------]]
-- травмы для клиента: только оружие, которое он знает (MES.gunz, MES.melee)
local function clientTable(list, nested)
	local out

	for key, n in pairs(list) do
		if MES.gunz[key] or MES.melee[key] then
			out = out or {}
			out[key] = nested and {n} or n
		end
	end

	return out or false
end

-- остальные виды - текстом
local function kindsText(list)
	local parts = {}

	for _, kind in ipairs(ALL) do
		local n = list[kind[2]]

		if n then
			parts[#parts + 1] = string.find(kind[4], "%s", 1, true) and string.format(kind[4], n) or kind[4]
		end
	end

	return table.concat(parts, ", ")
end

-- вторая строка - в списке дел у клиента
local function caseText(rec, packer)
	local lines = {
		"Заключение судебно-медицинской экспертизы",
		"Погибший: " .. rec.name .. ". Причина смерти: " .. rec.cause,
		"Дата рождения: " .. rec.born .. "   Пол: " .. rec.gen,
		"Время смерти: " .. os.date(DATE, rec.time),
	}

	if rec.weapon then lines[#lines + 1] = "Предполагаемое оружие: " .. rec.weapon end
	if #rec.signs > 0 then lines[#lines + 1] = "Также обнаружено: " .. table.concat(rec.signs, ", ") end

	local before, after = kindsText(rec.wounds), kindsText(rec.post)

	if before ~= "" then lines[#lines + 1] = "Травмы до смерти: " .. before end
	if after ~= "" then lines[#lines + 1] = "Повреждения после смерти: " .. after end

	lines[#lines + 1] = "Тело упаковал: " .. packer:FullName() .. " (" .. team.GetName(packer:Team()) .. "), " .. os.date(DATE)

	return table.concat(lines, "\n")
end

local function newCase(rec, packer)
	lastCase = lastCase + 1

	local case = {
		num = lastCase,
		time = rec.time,
		name = rec.name,
		text = caseText(rec, packer),
		post = clientTable(rec.post),
		wounds = clientTable(rec.wounds, true),
	}

	cases[case.num] = case
	order[#order + 1] = case.num

	while #order > MAX_CASES do
		cases[table.remove(order, 1)] = nil
	end

	return case
end

function MES.GetDeathCase(num)
	return cases[tonumber(num)]
end

function MES.GetDeathLog()
	local list = {}

	for i = #order, 1, -1 do
		local case = cases[order[i]]
		list[#list + 1] = {case.time, case.text, case.num, case.post, case.wounds}
	end

	return list
end

--[[---------------------------------------------------------------------------
	Упаковка тела
---------------------------------------------------------------------------]]
-- сотрудник с рацией: жив, в сознании, без наручников, не в машине
local function canBag(ply)
	return ply:Alive() and not ply:getDarkRPVar("unconscious") and not ply:getDarkRPVar("HandCuffed") and not ply:InVehicle() and GAMEMODE.RadioTeams[ply:Team()] == true
end

-- тело под прицелом и чьё оно. Носилки: тело на них или лежащий в сиденье
local function aimBody(ply)
	local start = ply:EyePos()
	local ent = util.TraceLine({start = start, endpos = start + ply:GetAimVector() * REACH, filter = ply}).Entity
	if not IsValid(ent) then return end

	if ent:GetClass() == "ent_stretcher" then
		if not IsValid(ent.MESBody) then
			local seat = ent.Stretcher
			local driver = IsValid(seat) and seat:GetDriver()

			return nil, IsValid(driver) and driver or nil
		end

		ent = ent.MESBody
	end

	local victim = ent.player

	if IsValid(victim) and victim:IsPlayer() and victim.DeathRagdoll == ent then return ent, victim end
end

local function meRadius(ply)
	local dist = GAMEMODE.Config.VoiceDist or {}

	return math.max(DarkRP.ChatRadius(ply), dist[2] or 500)
end

concommand.Add("bag_ragdoll", function(ply)
	if not IsValid(ply) or DarkRP.NetDelay(ply, BAG_DELAY) then return end
	if not canBag(ply) then return end

	local body, victim = aimBody(ply)

	if not victim then
		return
	end

	if not body or victim:Alive() or body.ragdollize then
		return
	end

	local rec = deaths[victim] or newRecord(victim)
	deaths[victim] = rec

	local case = newCase(rec, ply)

	-- тело несли ключами
	local keys = body.Draged

	if IsValid(keys) and keys.Reset then
		keys:Reset()
	end

	body:Remove()
	victim.DeathRagdoll = nil

	DarkRP.talkToRange(ply, "* " .. ply:Nick() .. " упаковывает тело в пластиковый пакет", "", meRadius(ply), ME_COLOR, color_white, true)
	DarkRP.log("police", ply, victim, "упаковал тело", nil, "дело #" .. case.num, ply)
end)

--[[---------------------------------------------------------------------------
	Возрождение, выход
---------------------------------------------------------------------------]]
local function merged(a, b)
	local out = table.Copy(a)

	for key, n in pairs(b) do
		out[key] = (out[key] or 0) + n
	end

	return next(out) ~= nil and out or nil
end

-- предупреждение N.L.R.; идёт эффект ЛСД (тот же хук HUDPaint у клиента) - после него
function MES.ShowNLR(ply)
	local rec = ply.nlr
	if not istable(rec) or not isvector(rec.pos) or not isnumber(rec.time) then return end

	local CT = CurTime()
	if rec.time + NLR_TIME <= CT then return end

	local name = "MES.NLR." .. ply:EntIndex()
	local lsd = tonumber(ply.LSDUntil) or 0

	if lsd > CT then
		timer.Create(name, lsd - CT, 1, function()
			if IsValid(ply) and ply.nlr == rec then
				MES.ShowNLR(ply)
			end
		end)

		return
	end

	timer.Remove(name)
	DarkRP.UIEffect(ply, "NLR", {rec.pos, rec.time})
end

hook.Add("PlayerSpawn", "MES.Forensic", function(ply)
	local rec = deaths[ply]
	deaths[ply] = nil

	-- подняли на месте после СЛР: та же жизнь, травмы остаются
	if ply.emsspawned then
		if rec then ply.MESWounds = merged(rec.wounds, rec.post) end
		return
	end

	ply.MESWounds = nil

	-- персонаж не выбран (смена персонажа): не его смерть
	if not rec or ply:getDarkRPVar("character") == nil then return end

	local CT = CurTime()

	ply.nlr = {pos = rec.pos, time = CT}
	MES.ShowNLR(ply)
	DarkRP.notify(ply, 0, 8, DarkRP.getPhrase("nlr"))
end)

hook.Add("PlayerDisconnected", "MES.Forensic", function(ply)
	deaths[ply] = nil
	timer.Remove("MES.NLR." .. ply:EntIndex())
end)
