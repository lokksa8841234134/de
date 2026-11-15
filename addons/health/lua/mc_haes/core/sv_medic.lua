--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Медицина - сервер: кровь, лечение, зависимость, СЛР, меню медика

	Кровь - переменная "blood" от 0 до 100, только своя (SetSelfDarkRPVar).
	ply:BloodLevel() - уровень крови, ply:BloodLevel(уровень) - поставить.
	Раз в секунду у живого: кровотечение ("bleeding", sv_stats.lua) отнимает
	BLEED в секунду (в режиме бога - нет), физраствор (ply.saline - до
	какого CurTime действует, препарат из MES.ListHeal) прибавляет SALINE в
	секунду, без того и другого кровь восстанавливается на единицу за REGEN
	секунд, но не выше 100. Кровь кончилась - смерть. Возрождение - снова
	100, кроме подъёма на месте после СЛР. Смерть снимает физраствор, чтобы
	телу с большой потерей крови его можно было ввести перед СЛР.

	ply:MedHeal() - здоровье до максимума, кровь до 100, снимает
	кровотечение и переломы (квесты MQS, больница). Вылеченные травмы
	судмедэкспертиза уже не увидит (ply.MESWounds, sv_forensic.lua).
	ply:FullHeal() - то же, и ещё шок, кашель, тошнота, передозировка (с её
	таймером), обморожение, отравление, нехватка кислорода (терапевт,
	sAdmin revive и hp). Опьянение, действие препаратов и зависимость не
	трогает.

	Адреналин (MES.ListHeal[3] в sh_config.lua автора) снимает передозировку
	стимуляторами - кокаином и метамфетамином (от морфина и героина -
	налоксон) - и обморожение, поднимает здоровье до 10 и даёт бодрость
	("stamina") на 30 секунд. Пока действует "adren" (110 секунд), здоровье
	не падает ниже ADREN_HP от падения, огня, взрыва без хозяина, NPC,
	обморожения и прочего. Урон другого игрока - и машиной, за рулём
	которой он сидит, - проходит как обычно: убить можно.

	Обморожение - переменная "cold", только своя. В воде по пояс и глубже
	(без сознания - если в воде рэгдолл) холод растёт на COLD_GAIN в
	секунду до COLD_MAX, на суше проходит на COLD_WARM в секунду. Клиент
	автора рисует иней (ярче с холодом) и снежинку, медик и
	судмедэкспертиза видят обморожение от 9. С COLD_HURT обморожение раз в
	COLD_HURT_EVERY секунд отнимает единицу здоровья (в режиме бога - нет);
	здоровье кончилось - смерть, в деле - "Переохлаждение" (ply.MESFrozen
	на время ply:Kill). Снимают адреналин и FullHeal; новая жизнь - тоже,
	подъём на месте после СЛР - нет. В транспорте и в noclip не мёрзнут.

	ply:AddAddiction(сколько[, вид]) - зависимость (морфин, позже
	наркотики). Переменная "addict" - сумма по видам, не больше 200 (столько
	клиент рисует в полную силу), без зависимости - nil: иначе F4 покажет
	состояние. Раз в ADDICT_TICK секунд каждый вид слабеет на единицу, пока
	не действует "relax" (под препаратом тяга не проходит). Смерть
	зависимость не снимает, выход из игры и смена персонажа - тоже: она ждёт
	следующего выбора этого персонажа (в памяти сервера до перезапуска).

	MES.SLR(медик, игрок, тело) - СЛР (меню медика, тату "Доктор", sAdmin
	slr и revive). Тело - ply.DeathRagdoll: труп или манекен на носилках.
	Без медика (sAdmin) СЛР всегда успешна, а живой без сознания просто
	приходит в себя. Медику СЛР помогает с шансом SLR_CHANCE и не помогает
	вовсе, если тело не откачать (crithit), крови меньше SLR_BLOOD или
	попытка за эту смерть больше SLR_MAX. Успех - игрок возрождается на
	месте тела (ply.emsspawned: гейммод не переносит его на точку
	профессии, sv_ragdoll.lua не убирает тело) с SLR_HP здоровья и лежит
	без сознания SLR_UNCON секунд - в позе трупа или на тех же носилках.
	Возвращает true при успехе.

	Меню медика (cl_init.lua, оружие med_kit и med_pd) - консольные команды
	"mes.check <номер в MES.List>" - осмотр и "mes.apply <номер в
	MES.ListHeal>" - препарат. Пациента клиент не передаёт: сервер находит
	его сам по прицелу (игрок, рэгдолл без сознания, труп, носилки с телом
	или с лежащим). Препарат стоит зарядов аптечки (Clip1), их списывает
	окончание действия. MES.ListHealRest - только парамедику ранга FDNY от
	REST_RANK, условие препарата (вещество ещё действует, СЛР живому) сервер
	проверяет сам. Осмотр приходит в чат. Препарат - звук, /me и
	полоса прогресса (net DrawProgressBar) на время действия; медик отошёл,
	сменил оружие, потерял сознание, пациент умер, ожил или пропал -
	действие прерывается (net RemovePropgressBar).
	Чат-команда /slr_tatoo - СЛР без аптечки с татуировкой b9 "Доктор":
	клиент предлагает её в меню по телу (client/vgui.lua).
---------------------------------------------------------------------------]]

local plyMeta = FindMetaTable("Player")

local BLOOD_MAX = 100
local BLOOD_TICK = 1
local BLEED = 1 -- крови в секунду при кровотечении
local SALINE = 0.5 -- крови в секунду под физраствором
local REGEN = 30 -- секунд на единицу крови без кровотечения
local EPS = 1e-6

local ADDICT_MAX = 200
local ADDICT_TICK = 60
local ADDICT_KIND = "other"

local SLR_CHANCE = 0.3
local SLR_MAX = 8 -- попыток СЛР медика за одну смерть
local SLR_BLOOD = 15
local SLR_HP = 15
local SLR_UNCON = 30
local SLR_XP = 20
local SLR_ITEM = 5 -- "Начать СЛР" в MES.ListHeal
local LIFT = 12 -- рэгдолл другой модели ложится на высоте над полом
local NEAR = 64

local KITS = {med_kit = true, med_pd = true}
local REACH = 200 -- прицел медика от глаз
local KEEP = 250 -- медик отошёл от пациента дальше - действие прерывается
local ACTION_TICK = 0.1
local REST_RANK = 3
local TATOO = "b9"
local ME_COLOR = Color(245, 190, 110)

--[[---------------------------------------------------------------------------
	Кровь
---------------------------------------------------------------------------]]
-- [ply] = накопленная дробная часть
local bloodFrac = {}

function plyMeta:BloodLevel(level)
	if level == nil then
		return tonumber(self:getDarkRPVar("blood")) or BLOOD_MAX
	end

	level = tonumber(level)
	if not level or level ~= level then return end

	bloodFrac[self] = nil
	self:SetSelfDarkRPVar("blood", math.Clamp(math.Round(level), 0, BLOOD_MAX))
end

local function bleedOut(ply)
	bloodFrac[ply] = nil
	ply:SetSelfDarkRPVar("blood", 0)
	ply:Kill()

	DarkRP.log("damage", ply, nil, "умер от потери крови", nil, nil, ply)
end

local function bloodTick(ply, CT)
	local cur = tonumber(ply:getDarkRPVar("blood"))

	-- физраствор сравнивает кровь с числом: у живого она есть всегда
	if not cur then
		ply:SetSelfDarkRPVar("blood", BLOOD_MAX)
		return
	end

	local rate = 0

	if ply:getDarkRPVar("bleeding") and not ply:HasGodMode() then
		rate = -BLEED
	end

	if (ply.saline or 0) > CT then
		rate = rate + SALINE
	elseif rate == 0 then
		rate = 1 / REGEN
	end

	-- восстанавливается только до нормы (sAdmin hp ставит и больше)
	if rate > 0 and cur >= BLOOD_MAX then
		bloodFrac[ply] = nil
		return
	end

	local acc = (bloodFrac[ply] or 0) + rate * BLOOD_TICK
	local whole = acc >= 0 and math.floor(acc + EPS) or -math.floor(EPS - acc)

	bloodFrac[ply] = acc - whole
	if whole == 0 then return end

	local level = cur + whole
	if whole > 0 then level = math.min(level, BLOOD_MAX) end

	if level > 0 then
		ply:SetSelfDarkRPVar("blood", level)
	else
		bleedOut(ply)
	end
end

timer.Create("MES.Blood", BLOOD_TICK, 0, function()
	local CT = CurTime()

	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() then
			bloodTick(ply, CT)
		end
	end
end)

--[[---------------------------------------------------------------------------
	Лечение
---------------------------------------------------------------------------]]
local HEAL = {"bleeding", "fracture", "fracturearm"}
local HEAL_FULL = {"shock", "cough", "nausea", "overdose"}
local HEAL_LEVELS = {"cold", "toxity", "deoxygen"}

local function clearFlags(ply, list)
	for _, var in ipairs(list) do
		if ply:getDarkRPVar(var) ~= nil then
			ply:SetSelfDarkRPVar(var, nil)
		end
	end
end

function plyMeta:MedHeal()
	if self:Alive() and self:Health() < self:GetMaxHealth() then
		self:SetHealth(self:GetMaxHealth())
	end

	if self:BloodLevel() < BLOOD_MAX then
		self:BloodLevel(BLOOD_MAX)
	end

	clearFlags(self, HEAL)
	self.MESWounds = nil
end

function plyMeta:FullHeal()
	self:MedHeal()
	clearFlags(self, HEAL_FULL)
	timer.Remove(self:UserID() .. "overdose")

	for _, var in ipairs(HEAL_LEVELS) do
		local value = tonumber(self:getDarkRPVar(var))

		if value and value > 0 then
			self:SetProDarkRPVar(var, 0)
		end
	end
end

--[[---------------------------------------------------------------------------
	Зависимость
---------------------------------------------------------------------------]]
-- [ply] = {[вид] = сила}
local addictions = {}
-- вышли из игры или сменили персонажа: DarkRP.CharacterID -> {[вид] = сила}
local savedAddictions = {}

local function syncAddiction(ply)
	local sum = 0

	for _, value in pairs(addictions[ply] or {}) do
		sum = sum + value
	end

	sum = math.min(math.floor(sum), ADDICT_MAX)
	ply:SetSelfDarkRPVar("addict", sum > 0 and sum or nil)
end

function plyMeta:AddAddiction(amount, kind)
	amount = tonumber(amount)
	if not amount or amount ~= amount or amount == 0 or not self:Alive() then return end

	kind = isstring(kind) and kind ~= "" and kind or ADDICT_KIND

	local list = addictions[self]

	if not list then
		list = {}
		addictions[self] = list
	end

	local value = math.min((list[kind] or 0) + amount, ADDICT_MAX)
	list[kind] = value > 0 and value or nil

	if next(list) == nil then addictions[self] = nil end

	syncAddiction(self)
end

timer.Create("MES.Addict", ADDICT_TICK, 0, function()
	for ply, list in pairs(addictions) do
		if not IsValid(ply) then
			addictions[ply] = nil
			continue
		end

		if ply:getDarkRPVar("relax") then continue end

		for kind, value in pairs(list) do
			list[kind] = value > 1 and value - 1 or nil
		end

		if next(list) == nil then addictions[ply] = nil end

		syncAddiction(ply)
	end
end)

hook.Add("MCR.CharacterReset", "MES.Addict", function(ply)
	local list = addictions[ply]
	if not list then return end

	addictions[ply] = nil
	savedAddictions[DarkRP.CharacterID(ply)] = list
	ply:SetSelfDarkRPVar("addict", nil)
end)

hook.Add("MCR.CharacterSelected", "MES.Addict", function(ply)
	local key = DarkRP.CharacterID(ply)
	local list = savedAddictions[key]
	if not list then return end

	savedAddictions[key] = nil
	addictions[ply] = list
	syncAddiction(ply)
end)

--[[---------------------------------------------------------------------------
	СЛР и подъём на месте
---------------------------------------------------------------------------]]
-- поза трупа: новый рэгдолл без сознания ляжет так же
local function bodyPose(body)
	if body:GetClass() ~= "prop_ragdoll" then return end

	local pose = {model = body:GetModel(), count = body:GetPhysicsObjectCount()}

	for i = 0, pose.count - 1 do
		local phys = body:GetPhysicsObjectNum(i)

		if IsValid(phys) then
			pose[i] = {phys:GetPos(), phys:GetAngles()}
		end
	end

	return pose
end

local function layBody(rag, pose, pos)
	if not IsValid(rag) then return end

	local count = rag:GetPhysicsObjectCount()
	local same = pose and pose.model == rag:GetModel() and pose.count == count
	local shift

	if not same then
		-- другая модель (сменилась профессия): хотя бы на месте тела
		local root = rag:GetPhysicsObjectNum(0)
		if not IsValid(root) or root:GetPos():DistToSqr(pos) <= NEAR * NEAR then return end

		shift = pos + Vector(0, 0, LIFT) - root:GetPos()
	end

	for i = 0, count - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		if not IsValid(phys) then continue end

		if same then
			local p = pose[i]

			if p then
				phys:SetPos(p[1])
				phys:SetAngles(p[2])
			end
		else
			phys:SetPos(phys:GetPos() + shift)
		end

		phys:SetVelocity(vector_origin)
		phys:Wake()
	end
end

local function floorUnder(body, ply)
	local pos = body:GetPos()
	local tr = util.TraceLine({start = pos + Vector(0, 0, 16), endpos = pos - Vector(0, 0, 64), mask = MASK_PLAYERSOLID, filter = {body, ply}})

	if tr.Hit and not tr.StartSolid then return tr.HitPos end

	return pos
end

local function revive(ply, body, medic)
	local gurney = body.MESStretcher
	if not IsValid(gurney) or gurney.MESBody ~= body or not IsValid(gurney.Stretcher) then gurney = nil end

	local pose = bodyPose(body)
	local pos = gurney and gurney:GetPos() or floorUnder(body, ply)
	local yaw = body:GetAngles().y

	-- тело несли ключами
	local keys = body.Draged

	if IsValid(keys) and keys.Reset then
		keys:Reset()
	end

	body:Remove()
	ply.DeathRagdoll = nil

	ply.emsspawned = true
	ply:Spawn()
	ply.emsspawned = nil

	ply:SetPos(pos)
	ply:SetEyeAngles(Angle(0, yaw, 0))
	ply:SetHealth(math.min(SLR_HP, ply:GetMaxHealth()))

	if ply:BloodLevel() < SLR_BLOOD then
		ply:BloodLevel(SLR_BLOOD)
	end

	if gurney and not IsValid(gurney.Stretcher:GetDriver()) then
		-- в сиденье носилок рэгдолла нет: лежащего рисует клиент
		gurney:Enter(ply)
		ply:Ragdollize(SLR_UNCON, true)
	else
		layBody(ply:Ragdollize(SLR_UNCON, true), pose, pos)
	end

	if IsValid(medic) then
		if medic:isEMS() then
			medic:JobXPAdd("fdny", SLR_XP)
		end

		DarkRP.log("other", medic, ply, "вернул к жизни (СЛР)")
	end

	return true
end

function MES.SLR(medic, ply, body)
	if not IsValid(ply) or not ply:IsPlayer() then return false end

	if ply:Alive() then
		if not IsValid(medic) and ply:IsUncon() then
			return ply:UnRagdollize()
		end

		return false
	end

	if not IsValid(body) or ply.DeathRagdoll ~= body or body.ragdollize then return false end

	if IsValid(medic) then
		ply.MESSLRTries = (ply.MESSLRTries or 0) + 1

		if body.crithit or ply.MESSLRTries > SLR_MAX or ply:BloodLevel() < SLR_BLOOD or math.random() >= SLR_CHANCE then
			return false
		end
	end

	return revive(ply, body, medic)
end

--[[---------------------------------------------------------------------------
	Меню медика: осмотр и препараты
---------------------------------------------------------------------------]]
-- [медик] = {id, target, alive, body, weapon, finish}
local actions = {}

-- медик может помогать: жив, в сознании, без наручников, не в машине
local function canTreat(ply)
	return ply:Alive() and not ply:getDarkRPVar("unconscious") and not ply:getDarkRPVar("HandCuffed") and not ply:InVehicle()
end

local function kitOf(ply)
	local wep = ply:GetActiveWeapon()

	if IsValid(wep) and KITS[wep:GetClass()] then return wep end
end

local function restrictedOk(ply)
	return ply:Team() == TEAM_REF and MRS and MRS.GetPlyRank and (tonumber(MRS.GetPlyRank(ply, "FDNY")) or 0) >= REST_RANK
end

-- пациент по энтити под прицелом: игрок, его тело (ply.DeathRagdoll),
-- носилки с телом или с лежащим в сиденье
local function patientOf(ent)
	if not IsValid(ent) then return end
	if ent:IsPlayer() then return ent end

	if ent:GetClass() == "ent_stretcher" then
		if not IsValid(ent.MESBody) then
			local seat = ent.Stretcher
			local driver = IsValid(seat) and seat:GetDriver()

			return IsValid(driver) and driver or nil
		end

		ent = ent.MESBody
	end

	local ply = ent.player

	if IsValid(ply) and ply:IsPlayer() and ply.DeathRagdoll == ent then return ply end
end

local function aimPatient(ply)
	local start = ply:EyePos()
	local tr = util.TraceLine({start = start, endpos = start + ply:GetAimVector() * REACH, filter = ply})
	local target = patientOf(tr.Entity)

	if target ~= ply then return target end
end

-- где пациент: тело или сам игрок
local function bodyOf(target)
	local body = target.DeathRagdoll
	if IsValid(body) then return body end

	if target:Alive() then return target end
end

local function actionRadius(ply)
	local dist = GAMEMODE.Config.VoiceDist or {}

	return math.max(DarkRP.ChatRadius(ply), dist[2] or 500)
end

local function stopAction(medic)
	if not actions[medic] then return end

	actions[medic] = nil
	if not IsValid(medic) then return end

	net.SendSingleMessage("RemovePropgressBar", medic)
end

-- новое действие тихо заменяет прежнее: полоса у клиента тоже одна
local function startAction(medic, id, target, weapon)
	local item = MES.ListHeal[id]
	local time = math.max(tonumber(item[6]) or 0, 0)
	local alive = target:Alive()

	actions[medic] = {
		id = id,
		target = target,
		alive = alive,
		body = not alive and target.DeathRagdoll or nil,
		weapon = weapon,
		finish = CurTime() + time,
	}

	if isstring(item[4]) and item[4] ~= "" then
		medic:EmitSound(item[4])
	end

	if isstring(item[5]) and item[5] ~= "" then
		DarkRP.talkToRange(medic, "* " .. medic:Nick() .. " " .. item[5], "", actionRadius(medic), ME_COLOR, color_white, true)
	end

	net.Start("DrawProgressBar")
		net.WriteFloat(time)
	net.Send(medic)
end

local function broken(medic, act)
	if not canTreat(medic) then return true end
	if act.weapon and medic:GetActiveWeapon() ~= act.weapon then return true end

	local target = act.target
	if not IsValid(target) or target:Alive() ~= act.alive then return true end

	-- тело убрали, положили на носилки или сняли с них
	if not act.alive and target.DeathRagdoll ~= act.body then return true end

	local body = bodyOf(target)

	return not IsValid(body) or medic:GetPos():DistToSqr(body:GetPos()) > KEEP * KEEP
end

local function finishAction(medic, act)
	local item = MES.ListHeal[act.id]
	local target = act.target

	if item[7] and not item[7](target) then
		if item[8] then DarkRP.notify(medic, 1, 4, item[8]) end
		return
	end

	local weapon = act.weapon

	if weapon then
		if weapon:Clip1() < item[2] then
			return
		end

		weapon:SetClip1(weapon:Clip1() - item[2])
	end

	-- физраствор сравнивает кровь с числом
	if target:getDarkRPVar("blood") == nil then
		target:SetSelfDarkRPVar("blood", BLOOD_MAX)
	end

	DarkRP.log("other", medic, target, "медпомощь: " .. item[1])

	item[3](medic, target, target.DeathRagdoll)
end

timer.Create("MES.Medic", ACTION_TICK, 0, function()
	local CT = CurTime()

	for medic, act in pairs(actions) do
		if not IsValid(medic) then
			actions[medic] = nil
		elseif broken(medic, act) then
			stopAction(medic)
		elseif CT >= act.finish then
			actions[medic] = nil
			finishAction(medic, act)
		end
	end
end)

concommand.Add("mes.check", function(ply, _, args)
	if not IsValid(ply) or DarkRP.NetDelay(ply, 0.5) then return end

	local id = tonumber(args[1] or "")
	local item = id and MES.List[id]
	if not item or not canTreat(ply) or not kitOf(ply) then return end

	local target = aimPatient(ply)

	if not target then
		return
	end

	-- шаг 11: результат осмотра - в чат (эффект автора ChatText), а не уведомлением
	DarkRP.UIEffect(ply, "ChatText", {type = 0, text = item[2] .. ": " .. tostring(item[3](target, item[1], ply))})
end)

concommand.Add("mes.apply", function(ply, _, args)
	if not IsValid(ply) or DarkRP.NetDelay(ply, 0.5) then return end

	local id = tonumber(args[1] or "")
	local item = id and MES.ListHeal[id]
	if not item or not canTreat(ply) then return end

	local weapon = kitOf(ply)
	if not weapon then return end

	if MES.ListHealRest[id] and not restrictedOk(ply) then
		return
	end

	local target = aimPatient(ply)

	if not target then
		return
	end

	if item[7] and not item[7](target) then
		if item[8] then DarkRP.notify(ply, 1, 4, item[8]) end
		return
	end

	if weapon:Clip1() < item[2] then
		return
	end

	startAction(ply, id, target, weapon)
end)

-- СЛР без аптечки: татуировка "Доктор"
local function tatooSLR(ply)
	if not canTreat(ply) then return "" end

	if not MCR.HasTatoo(ply, TATOO) then
		return ""
	end

	local target = aimPatient(ply)

	if not target then
		return ""
	end

	local item = MES.ListHeal[SLR_ITEM]

	if item[7] and not item[7](target) then
		if item[8] then DarkRP.notify(ply, 1, 4, item[8]) end
		return ""
	end

	startAction(ply, SLR_ITEM, target)

	return ""
end

local function setup()
	DarkRP.defineChatCommand("slr_tatoo", tatooSLR, 1)
end

-- аддон грузится до гейммода
hook.Add("PostGamemodeLoaded", "MES.Medic", setup)
if GAMEMODE and DarkRP then setup() end

--[[---------------------------------------------------------------------------
	Адреналин: здоровье не ниже ADREN_HP, кроме урона от других игроков
---------------------------------------------------------------------------]]
local ADREN_HP = 10

-- урон нанёс другой игрок: сам или машиной, за рулём которой сидит
local function byPlayer(dmg, victim)
	local attacker = dmg:GetAttacker()

	if IsValid(attacker) and not attacker:IsPlayer() and attacker.GetDriver then
		attacker = attacker:GetDriver()
	end

	return IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim
end

hook.Add("EntityTakeDamage", "MES.Adrenaline", function(ply, dmg)
	if not ply:IsPlayer() or not ply:Alive() or not ply:getDarkRPVar("adren") then return end
	if byPlayer(dmg, ply) then return end

	local hp = ply:Health()

	-- взрыв мог уже обнулить здоровье (vFireFixExplosion)
	if hp <= 0 then
		hp = math.min(ADREN_HP, ply:GetMaxHealth())
		ply:SetHealth(hp)
	end

	dmg:SetDamage(math.min(dmg:GetDamage(), math.max(hp - ADREN_HP, 0)))
end)

--[[---------------------------------------------------------------------------
	Обморожение: в воде холод растёт, на суше проходит
---------------------------------------------------------------------------]]
local COLD_MAX = 100
local COLD_TICK = 1
local COLD_WATER = 2 -- в воде по пояс и глубже (WaterLevel)
local COLD_GAIN = 1 -- холода в секунду в воде
local COLD_WARM = 0.5 -- холода в секунду проходит на суше
local COLD_HURT = 50 -- с этого холода обморожение отнимает здоровье
local COLD_HURT_EVERY = 3 -- секунд на единицу здоровья
local COLD_CHEST = "ValveBiped.Bip01_Spine2"

-- [ply] = {level, hurt}: точный холод (переменная - целая) и когда снова
-- отнять здоровье
local colds = {}

-- в воде ли игрок; без сознания он спрятан - мёрзнет его рэгдолл
local function inWater(ply)
	if ply:InVehicle() or ply:GetMoveType() == MOVETYPE_NOCLIP then return false end

	local rag = ply:getDarkRPVar("unconscious") and ply.DeathRagdoll

	if IsValid(rag) then
		local bone = rag:LookupBone(COLD_CHEST)
		local pos = bone and rag:GetBonePosition(bone) or rag:WorldSpaceCenter()

		return bit.band(util.PointContents(pos), CONTENTS_WATER) ~= 0
	end

	return ply:WaterLevel() >= COLD_WATER
end

local function freezeOut(ply)
	colds[ply] = nil

	-- причина смерти в деле судмедэкспертизы (sv_forensic.lua)
	ply.MESFrozen = true
	ply:Kill()
	ply.MESFrozen = nil

	DarkRP.log("damage", ply, nil, "умер от обморожения", nil, nil, ply)
end

local function coldHurt(ply, st, CT)
	if st.level < COLD_HURT or ply:HasGodMode() then
		st.hurt = nil
		return
	end

	if not st.hurt then
		st.hurt = CT + COLD_HURT_EVERY
		return
	end

	if st.hurt > CT then return end
	st.hurt = CT + COLD_HURT_EVERY

	-- под адреналином здоровье не ниже ADREN_HP, как от любого урона не от игрока
	local floor = ply:getDarkRPVar("adren") and math.min(ADREN_HP, ply:GetMaxHealth()) or 0
	local hp = ply:Health()

	if hp - 1 > floor then
		ply:SetHealth(hp - 1)
	elseif floor > 0 then
		if hp > floor then ply:SetHealth(floor) end
	else
		freezeOut(ply)
	end
end

local function coldTick(ply, CT)
	local var = tonumber(ply:getDarkRPVar("cold")) or 0
	local st = colds[ply]

	-- холод сняли или поставили со стороны: адреналин, FullHeal, команда
	if not st or math.ceil(st.level) ~= var then
		st = {level = var}
		colds[ply] = st
	end

	if inWater(ply) then
		if st.level < COLD_MAX then
			st.level = math.min(st.level + COLD_GAIN * COLD_TICK, COLD_MAX)
		end
	elseif st.level > 0 then
		st.level = math.max(st.level - COLD_WARM * COLD_TICK, 0)
	end

	local whole = math.ceil(st.level)
	if whole ~= var then ply:SetSelfDarkRPVar("cold", whole) end

	coldHurt(ply, st, CT)
end

timer.Create("MES.Cold", COLD_TICK, 0, function()
	local CT = CurTime()

	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() then
			coldTick(ply, CT)
		end
	end
end)

hook.Add("PlayerSpawn", "MES.Cold", function(ply)
	colds[ply] = nil

	-- подняли на месте после СЛР: тело то же, холод остаётся
	if ply.emsspawned then return end

	if (tonumber(ply:getDarkRPVar("cold")) or 0) > 0 then
		ply:SetSelfDarkRPVar("cold", 0)
	end
end)

hook.Add("PlayerDisconnected", "MES.Cold", function(ply)
	colds[ply] = nil
end)

--[[---------------------------------------------------------------------------
	Смерть, возрождение, выход
---------------------------------------------------------------------------]]
local function onDeath(ply)
	bloodFrac[ply] = nil
	ply.MESSLRTries = nil
	ply.saline = nil
	stopAction(ply)
end

hook.Add("PlayerDeath", "MES.Medic", onDeath)
hook.Add("PlayerSilentDeath", "MES.Medic", onDeath)

hook.Add("PlayerSpawn", "MES.Medic", function(ply)
	bloodFrac[ply] = nil
	ply.MESSLRTries = nil

	-- подняли на месте после СЛР: кровь и физраствор остаются
	if ply.emsspawned then return end

	ply.saline = nil
	ply:SetSelfDarkRPVar("blood", BLOOD_MAX)
end)

hook.Add("PlayerDisconnected", "MES.Medic", function(ply)
	actions[ply] = nil
	bloodFrac[ply] = nil

	local list = addictions[ply]
	addictions[ply] = nil

	if list then
		savedAddictions[DarkRP.CharacterID(ply)] = list
	end
end)
