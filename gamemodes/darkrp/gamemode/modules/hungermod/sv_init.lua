--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Голод и жажда, одышка, опьянение и отравление - сервер

	Переменные игрока - только свои (SetSelfDarkRPVar): полосы HUD, F4 и
	эффекты на экране рисует клиент автора.

	"energy" - калории. Новая жизнь - ENERGY_FULL (полоса HUD рассчитана
	на 250). Раз в HUNGER_EVERY секунд минус GM.Config.hungerspeed, пока
	нет сытости ("hunger"). Еда поднимает калории до своего maxenergy, еда
	без него - до ENERGY_MAX; больше 250 - бонус в мини-игре навыка.
	"thirst" - вода, она же выносливость (HasStamina в sh_init.lua): новая
	жизнь - THIRST_FULL, раз в HUNGER_EVERY минус GM.Config.thirstspeed,
	бег - минус GM.Config.thirst в секунду, удары и толчки - TakeStamina.
	Как в справке F1 ("Еда и вода"): одно из двух на нуле - меньше сил
	(HasStamina не пускает бить и толкать, одышка вдвое быстрее), оба на
	нуле - минус GM.Config.starverate здоровья раз в HUNGER_EVERY (в режиме
	бога и в заключении - нет, под адреналином здоровье не ниже ADREN_HP).
	Здоровье кончилось - смерть, в деле судмедэкспертизы "Истощение"
	(ply.MESCause на время ply:Kill, sv_forensic.lua).

	Сытость ("hunger": хорошая еда, квест больницы) - калории не убывают,
	здоровье растёт на SATED_HP раз в HUNGER_EVERY, рассудок - на
	SATED_KARMA раз в KARMA_EVERY сверх обычного, до KARMA_MAX (справка
	F1: "от высокой сытости ... регенерация здоровья, восстановление
	рассудка").

	"deoxygen" - одышка 0..100, всегда число (задержка дыхания в прицеле
	mg_base ждёт переменную). Бег, удары и толчки, голова под водой и
	кашель её набирают, без них она проходит: на ходу BREATH_WALK в
	секунду, стоя и без сознания - BREATH_STILL, на отдыхе (/rest) -
	BREATH_REST. Клиент автора с 30 - дыхание, дрожь прицела и пункт
	"Отдохнуть" в меню C, с 50 - замедление (shared/commands.lua).
	Тату b8 "Глубокие лёгкие" - одышка набирается медленнее (B8), в
	противогазе - быстрее (GASMASK), без воды или калорий - вдвое быстрее.
	Энергичность ("stamina": кофе, энергетики, адреналин) - бег и удары
	одышки не дают, проходит она вдвое быстрее.

	"alcohol" - опьянение, "toxity" - отравление; на нуле переменной нет
	(F4 и осмотр медика показывают опьянение по самой переменной). Раз в
	HUNGER_EVERY проходят на ALC_DECAY и TOX_DECAY. Тату g4 "Сомелье" -
	опьянение от выпитого слабее (ALC_G4). С ALC_NAUSEA опьянения или
	TOX_NAUSEA отравления тошнит ("nausea"), с ALC_POISON опьянение
	отравляет, с TOX_HURT отравление отнимает здоровье, смерть -
	"Отравление". Отравление и одышку снимает полное лечение (FullHeal).

	Лечение "meds1"-"meds3" (временные состояния; квест больницы ставит
	"meds3") - здоровье растёт до максимума, MEDS - единиц в секунду.

	Точные значения дробные, в переменной - целое вверх. Переменную
	поменяли со стороны (квест больницы, FullHeal, команды) - счёт идёт от
	неё. Подъём на месте после СЛР - голод, жажда, опьянение и отравление
	те же. Смена персонажа и выход из игры - калории, вода, опьянение и
	отравление ждут следующего выбора этого персонажа (в памяти сервера до
	перезапуска). В меню персонажей и в noclip ничего не идёт.

	/rest ("Отдохнуть" в меню C): одышка больше REST_MIN, не в противогазе,
	без кашля, свободен - REST_TIME секунд на месте, одышка проходит
	быстрее.

	API (сервер):
	ply:TakeStamina(сколько[, одышка]) - удар, толчок: вода минус сколько,
	калории - вдвое меньше (в противогазе всё вдвое больше), одышка плюс
	второй аргумент (без него - BREATH_STAMINA на единицу).
	ply:TakeThirst(n), ply:TakeEnergy(n) - минус вода и калории.
	ply:AddThirst(n[, до]), ply:AddEnergy(n[, до]) - плюс, не больше "до"
	(без него - THIRST_FULL и ENERGY_FULL); уже больше - не меняется.
	ply:AddAlcohol(n), ply:AddToxity(n), ply:AddBreath(n) - опьянение,
	отравление, одышка (минус - снять).
	Еда - sv_food.lua.
---------------------------------------------------------------------------]]

local plyMeta = FindMetaTable("Player")

local TICK = 1 -- секунд: одышка, бег, лечение
local HUNGER_EVERY = 10 -- секунд: голод, жажда, опьянение, отравление

local ENERGY_FULL = 250
local ENERGY_MAX = 500 -- квест больницы ставит до 500
local THIRST_FULL = 350 -- полоса HUD: thirst / 350
local BREATH_MAX = 100

-- одышка, в секунду
local RUN_SPEED = 140 -- быстрее с Shift по земле - бег (ключи: Length2DSqr > 20000)
local STILL_SPEED = 10 -- медленнее - стоит
local BREATH_RUN = 1.5
local BREATH_WATER = 4 -- голова под водой
local BREATH_COUGH = 1 -- кашель (газ, дым пожара)
local BREATH_WALK = 2
local BREATH_STILL = 4
local BREATH_REST = 10
local BREATH_STAMINA = 0.25 -- TakeStamina без второго аргумента: одышки на единицу
local ENERGETIC = 2 -- энергичность: одышка проходит во столько раз быстрее

-- одышка набирается
local B8 = 0.6 -- тату b8 "Глубокие лёгкие"
local GASMASK = 1.5 -- в противогазе
local EXHAUSTED = 2 -- вода или калории на нуле

local GASMASK_COST = 2 -- TakeStamina в противогазе: HasStamina требует вдвое больше
local STAMINA_FOOD = 0.5 -- калорий на единицу воды (HasStamina: калорий нужно вдвое меньше)
local ADREN_HP = 10 -- как в sv_medic.lua

-- сытость
local SATED_HP = 1 -- здоровья за HUNGER_EVERY
local SATED_KARMA = 1 -- рассудка за KARMA_EVERY
local KARMA_EVERY = 60 -- секунд, как обычное восстановление (sv_data.lua)
local KARMA_MAX = 100

local ALC_MAX = 200
local ALC_DECAY = 1
local ALC_G4 = 0.6 -- тату g4 "Сомелье"
local ALC_NAUSEA = 80
local ALC_POISON = 150
local ALC_TOX = 3 -- отравления за HUNGER_EVERY с ALC_POISON (проходит TOX_DECAY)

local TOX_MAX = 100
local TOX_DECAY = 1
local TOX_NAUSEA = 30
local TOX_HURT = 50
local TOX_HP = 1 -- здоровья за HUNGER_EVERY с TOX_HURT
local NAUSEA_TIME = 30 -- секунд тошноты, продлевается, пока держится уровень

-- лечение: здоровья в секунду, сильнее - первым
local MEDS = {{"meds3", 0.5}, {"meds2", 0.2}, {"meds1", 0.1}}

local REST_MIN = 30 -- как у пункта меню (client/vgui.lua)
local REST_TIME = 5
local REST_ANIM = "pose_ducking_01"

-- причины смерти в деле судмедэкспертизы (sv_forensic.lua)
local STARVED = "Истощение"
local POISONED = "Отравление"

local DEATH_LOG = {
	[STARVED] = "умер от истощения",
	[POISONED] = "умер от отравления",
}

local MAXES = {energy = ENERGY_MAX, thirst = THIRST_FULL, deoxygen = BREATH_MAX, alcohol = ALC_MAX, toxity = TOX_MAX}
-- на нуле переменной нет
local OPTIONAL = {alcohol = true, toxity = true}
-- ждут следующего выбора персонажа
local SAVE = {"energy", "thirst", "alcohol", "toxity"}

-- [ply] = {[переменная] = точное значение, heal = дробь здоровья}
local states = {}
-- DarkRP.CharacterID -> {[переменная] = значение}
local saved = {}
-- [ply] = до какого CurTime отдыхает
local resting = {}

local function cfg(key, default)
	local config = GAMEMODE and GAMEMODE.Config
	return tonumber(config and config[key]) or default
end

local function number(n)
	n = tonumber(n)
	if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
	return n
end

local function whole(v)
	return math.max(math.ceil(v - 0.0001), 0)
end

local function stateOf(ply)
	local st = states[ply]

	if not st then
		st = {}
		states[ply] = st
	end

	return st
end

-- точное значение; переменную поменяли со стороны - берём её
local function get(ply, var)
	local st = stateOf(ply)
	local cur = tonumber(ply:getDarkRPVar(var)) or 0
	local v = st[var]

	if v == nil or whole(v) ~= cur then
		v = cur
		st[var] = v
	end

	return v
end

local function set(ply, var, v)
	v = math.Clamp(v, 0, MAXES[var])
	stateOf(ply)[var] = v

	local int = whole(v)
	local new = (int > 0 or not OPTIONAL[var]) and int or nil

	if ply:getDarkRPVar(var) ~= new then
		ply:SetSelfDarkRPVar(var, new)
	end

	return v
end

local function fresh(ply)
	states[ply] = {}
	set(ply, "energy", ENERGY_FULL)
	set(ply, "thirst", THIRST_FULL)
	set(ply, "deoxygen", 0)
	set(ply, "alcohol", 0)
	set(ply, "toxity", 0)
end

local function jailed(ply)
	return ply:getDarkRPVar("Arrested") or ply:getDarkRPVar("jailed")
end

-- здоровье от голода, жажды, отравления; кончилось - смерть с причиной в деле
local function hurt(ply, amount, cause)
	if amount <= 0 or ply:HasGodMode() then return end

	local floor = ply:getDarkRPVar("adren") and math.min(ADREN_HP, ply:GetMaxHealth()) or 0
	local hp = ply:Health()

	if hp - amount > floor then
		ply:SetHealth(hp - amount)
	elseif floor > 0 then
		if hp > floor then ply:SetHealth(floor) end
	else
		ply.MESCause = cause
		ply:Kill()
		ply.MESCause = nil

		DarkRP.log("damage", ply, nil, DEATH_LOG[cause], nil, nil, ply)
	end
end

--[[---------------------------------------------------------------------------
	Одышка и выносливость
---------------------------------------------------------------------------]]
local function breathMul(ply)
	if ply:getDarkRPVar("stamina") then return 0 end

	local mul = 1

	if MCR.HasTatoo(ply, "b8") then mul = mul * B8 end
	if DarkRP.GasMask(ply, true) then mul = mul * GASMASK end

	if (tonumber(ply:getDarkRPVar("thirst")) or 0) <= 0 or (tonumber(ply:getDarkRPVar("energy")) or 0) <= 0 then
		mul = mul * EXHAUSTED
	end

	return mul
end

local function spend(ply, water)
	set(ply, "thirst", get(ply, "thirst") - water)
	set(ply, "energy", get(ply, "energy") - water * STAMINA_FOOD)
end

local function running(ply)
	if not ply:KeyDown(IN_SPEED) or not ply:IsOnGround() or ply:WaterLevel() > 1 then return false end

	return ply:GetVelocity():Length2DSqr() > RUN_SPEED * RUN_SPEED
end

local function breathTick(ply, CT)
	local d = get(ply, "deoxygen")
	local gain = 0
	local uncon = ply:getDarkRPVar("unconscious")

	if not uncon and not ply:InVehicle() and not IsValid(ply.pk_pill_ent) then
		if running(ply) then
			gain = BREATH_RUN * breathMul(ply)
			spend(ply, cfg("thirst", 0.3) * TICK)
		end

		if ply:WaterLevel() >= 3 then gain = gain + BREATH_WATER end
		if ply:getDarkRPVar("cough") then gain = gain + BREATH_COUGH end
	end

	if gain > 0 then
		d = d + gain * TICK
	elseif d > 0 then
		local rate = BREATH_WALK

		if resting[ply] and resting[ply] > CT then
			rate = BREATH_REST
		elseif uncon or ply:GetVelocity():Length2DSqr() < STILL_SPEED * STILL_SPEED then
			rate = BREATH_STILL
		end

		if ply:getDarkRPVar("stamina") then rate = rate * ENERGETIC end

		d = d - rate * TICK
	else
		return
	end

	set(ply, "deoxygen", d)
end

--[[---------------------------------------------------------------------------
	Лечение meds1-meds3
---------------------------------------------------------------------------]]
local function healTick(ply)
	local st = stateOf(ply)
	local rate

	for _, med in ipairs(MEDS) do
		if ply:getDarkRPVar(med[1]) then
			rate = med[2]
			break
		end
	end

	local hp, max = ply:Health(), ply:GetMaxHealth()

	if not rate or hp >= max then
		st.heal = nil
		return
	end

	local heal = (st.heal or 0) + rate * TICK
	local add = math.floor(heal)
	st.heal = heal - add

	if add > 0 then
		ply:SetHealth(math.min(hp + add, max))
	end
end

--[[---------------------------------------------------------------------------
	Голод, жажда, опьянение, отравление
---------------------------------------------------------------------------]]
local function hungerTick(ply)
	local energy = get(ply, "energy")

	if not ply:getDarkRPVar("hunger") then
		energy = set(ply, "energy", energy - cfg("hungerspeed", 1))
	end

	local thirst = set(ply, "thirst", get(ply, "thirst") - cfg("thirstspeed", 0.3))
	local alc = get(ply, "alcohol")
	local tox = get(ply, "toxity")

	if alc > 0 then
		if alc >= ALC_POISON then tox = tox + ALC_TOX end
		set(ply, "alcohol", alc - ALC_DECAY)
	end

	if tox > 0 then
		set(ply, "toxity", tox - TOX_DECAY)
	end

	if alc >= ALC_NAUSEA or tox >= TOX_NAUSEA then
		ply:AddTempStat("nausea", NAUSEA_TIME)
	end

	if energy <= 0 and thirst <= 0 and not jailed(ply) then
		hurt(ply, cfg("starverate", 2), STARVED)
	end

	if tox >= TOX_HURT and ply:Alive() then
		hurt(ply, TOX_HP, POISONED)
	end

	-- сытость: здоровье
	if ply:getDarkRPVar("hunger") and ply:Alive() then
		local hp, max = ply:Health(), ply:GetMaxHealth()

		if hp < max then ply:SetHealth(math.min(hp + SATED_HP, max)) end
	end
end

-- сытость: рассудок
local function karmaTick(ply)
	if not ply:getDarkRPVar("hunger") or not ply.addKarma then return end

	local karma = tonumber(ply:getDarkRPVar("karma"))

	if karma and karma < KARMA_MAX then
		ply:addKarma(math.min(SATED_KARMA, KARMA_MAX - karma))
	end
end

local ticks = 0

timer.Create("DarkRP.Hunger", TICK, 0, function()
	ticks = ticks + 1

	local hungry = ticks % (HUNGER_EVERY / TICK) == 0
	local karma = ticks % (KARMA_EVERY / TICK) == 0
	local CT = CurTime()

	for _, ply in ipairs(player.GetAll()) do
		if not ply:Alive() or ply.MCRHidden or ply:GetMoveType() == MOVETYPE_NOCLIP then continue end

		-- переменных нет (модуль перезагрузили): как новая жизнь
		if ply:getDarkRPVar("energy") == nil then fresh(ply) end

		breathTick(ply, CT)
		healTick(ply)

		if hungry and ply:Alive() then hungerTick(ply) end
		if karma and ply:Alive() then karmaTick(ply) end
	end
end)

--[[---------------------------------------------------------------------------
	API
---------------------------------------------------------------------------]]
function plyMeta:AddBreath(n)
	n = number(n)
	if not n or n == 0 or not self:Alive() then return end

	if n > 0 then n = n * breathMul(self) end

	set(self, "deoxygen", get(self, "deoxygen") + n)
end

function plyMeta:TakeStamina(amount, breath)
	amount = number(amount) or 0
	if not self:Alive() then return end

	if amount < 0 then amount = 0 end

	breath = number(breath) or amount * BREATH_STAMINA

	if DarkRP.GasMask(self, true) then amount = amount * GASMASK_COST end
	if amount > 0 then spend(self, amount) end

	self:AddBreath(breath)
end

function plyMeta:TakeThirst(n)
	n = number(n)
	if not n or n <= 0 or not self:Alive() then return end

	set(self, "thirst", get(self, "thirst") - n)
end

function plyMeta:TakeEnergy(n)
	n = number(n)
	if not n or n <= 0 or not self:Alive() then return end

	set(self, "energy", get(self, "energy") - n)
end

local function add(ply, var, n, cap, default)
	n = number(n)
	if not n or n == 0 or not ply:Alive() then return end

	local cur = get(ply, var)

	if n > 0 then
		cap = math.min(number(cap) or default, MAXES[var])
		if cur >= cap then return end

		cur = math.min(cur + n, cap)
	else
		cur = cur + n
	end

	set(ply, var, cur)
end

function plyMeta:AddThirst(n, cap)
	add(self, "thirst", n, cap, THIRST_FULL)
end

function plyMeta:AddEnergy(n, cap)
	add(self, "energy", n, cap, ENERGY_FULL)
end

function plyMeta:AddAlcohol(n)
	n = number(n)
	if not n or n == 0 or not self:Alive() then return end

	if n > 0 and MCR.HasTatoo(self, "g4") then n = n * ALC_G4 end

	set(self, "alcohol", get(self, "alcohol") + n)
end

function plyMeta:AddToxity(n)
	n = number(n)
	if not n or n == 0 or not self:Alive() then return end

	set(self, "toxity", get(self, "toxity") + n)
end

DarkRP.Hunger = {
	ENERGY_FULL = ENERGY_FULL,
	ENERGY_MAX = ENERGY_MAX,
	THIRST_FULL = THIRST_FULL,
	STARVED = STARVED,
	POISONED = POISONED,
}

--[[---------------------------------------------------------------------------
	Отдых (/rest)
---------------------------------------------------------------------------]]
DarkRP.defineChatCommand("rest", function(ply)
	if not ply:IsFreeman() or ply:InVehicle() then return end

	if DarkRP.GasMask(ply, true) then
		return
	end

	if ply:getDarkRPVar("cough") then
		return
	end

	if (tonumber(ply:getDarkRPVar("deoxygen")) or 0) <= REST_MIN then
		return
	end

	local CT = CurTime()
	if resting[ply] and resting[ply] > CT then return end

	resting[ply] = CT + REST_TIME
	DarkRP.ForceAnimation(ply, REST_ANIM, REST_TIME)
end)

--[[---------------------------------------------------------------------------
	Новая жизнь, смена персонажа, выход
---------------------------------------------------------------------------]]
hook.Add("PlayerSpawn", "DarkRP.Hunger", function(ply)
	resting[ply] = nil

	-- подняли на месте после СЛР: тело то же
	if ply.emsspawned then
		stateOf(ply).heal = nil
		set(ply, "deoxygen", 0)
		return
	end

	fresh(ply)
end)

local function onDeath(ply)
	resting[ply] = nil
end

hook.Add("PlayerDeath", "DarkRP.Hunger", onDeath)
hook.Add("PlayerSilentDeath", "DarkRP.Hunger", onDeath)

local function save(ply)
	if not ply:getDarkRPVar("character") or ply.MCRHidden then return end

	local key = DarkRP.CharacterID(ply)

	-- умер - новая жизнь и так начнётся заново
	if not ply:Alive() then
		saved[key] = nil
		return
	end

	local data = {}

	for _, var in ipairs(SAVE) do
		data[var] = get(ply, var)
	end

	saved[key] = data
end

hook.Add("MCR.CharacterReset", "DarkRP.Hunger", function(ply)
	save(ply)
	states[ply] = nil
	resting[ply] = nil
end)

hook.Add("MCR.CharacterSelected", "DarkRP.Hunger", function(ply)
	local key = DarkRP.CharacterID(ply)
	local data = saved[key]
	if not data then return end

	saved[key] = nil

	for _, var in ipairs(SAVE) do
		if data[var] then set(ply, var, data[var]) end
	end
end)

hook.Add("PlayerDisconnected", "DarkRP.Hunger", function(ply)
	save(ply)
	states[ply] = nil
	resting[ply] = nil
end)
