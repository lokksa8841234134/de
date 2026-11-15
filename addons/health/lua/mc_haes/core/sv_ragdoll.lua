--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Рэгдоллы и потеря сознания - сервер (общая часть в sh_ragdoll.lua)

	ply:Ragdollize(время[, сила, _, _, глубина]) - игрок падает без сознания
	  на время в секундах. Игрок прячется (невидим, не твёрдый, не двигается)
	  и ходит за рэгдоллом prop_ragdoll, клиент смотрит из глаз рэгдолла.
	  Переменная "unconscious" - глубина: больше 9 - чёрный экран и глухой
	  звук у клиента, по умолчанию глубина равна времени (электрошокер
	  передаёт 10 - отключает сразу). Повторный вызов только продлевает:
	  время и глубина - наибольшие из прежних и новых.
	  сила = true - уронить и того, кто в noclip (sAdmin ragdoll, электрошокер,
	  удар кулаком). Параметры 3 и 4 никто не передаёт.
	  Возвращает рэгдолл (электрошокер трясёт его через MES.Convulse). В транспорте рэгдолла нет:
	  игрок остаётся на сиденье (позу без сознания рисует клиент) и падает,
	  когда его вытащат.
	ply:UnRagdollize() - очнуться сейчас (sAdmin unragdoll и revive, адреналин).
	ply:DeRagdollize() - убрать рэгдолл, но остаться без сознания: так носилки
	  кладут игрока на себя. ply:GoUncon() - снова лечь рэгдоллом.
	ply:IsUncon() - без сознания ли игрок (и на носилках тоже).
	ply:SincRagdoll(rag, наручники[, кому]) - net DarkRP.ClientRagdoll S->C:
	  Entity игрок, UInt(32) индекс рэгдолла, Vector цвет игрока, Bool
	  наручники. Клиент ставит ply.DeathRagdoll и rag.SelfPlayer (по нему
	  меню медика "Начать СЛР") и рисует на рэгдолле одежду игрока. Клиент,
	  у которого рэгдолла в этот момент нет (далеко), ничего не запоминает,
	  поэтому сервер досылает сообщение каждому, у кого рэгдолл пробыл в
	  зоне видимости (PVS) полсекунды.

	Поля рэгдолла: rag.player - игрок (наручники, носилки, судмедэкспертиза),
	rag.ragdollize - рэгдолл живого игрока без сознания (у трупа nil),
	rag.cuffed и rag.CuffsRope - наручники (police/sv_cuffs.lua),
	rag.crithit - тело не откачать (sAdmin slay, морфин при передозировке,
	снесённая голова).
	ply.DeathRagdoll - рэгдолл без сознания или труп.

	Урон по рэгдоллу без сознания получает игрок. Удары рэгдолла о мир и
	слабые (меньше 10) удары предметов не считаются. Прямой урон по
	спрятанному игроку (пули, взрыв, удары) не проходит - только через
	рэгдолл, иначе взрыв задел бы дважды.

	Смерть: рэгдолл без сознания становится трупом, иначе труп создаётся
	заново (стандартный рэгдолл движка убирается). Труп лежит до возрождения
	игрока: медикам (часть 8.2) он нужен для СЛР. При возрождении на месте
	(ply.emsspawned) труп не убирается - его заберёт модуль медиков.

	Выстрел (пуля, дробь). Убитый или упавший без сознания отлетает от пули:
	верх тела получает скорость по ходу выстрела - от KICK_MIN до KICK_MAX,
	больше у мощного оружия, руки отстают, - ноги остаются, и тело валится
	навзничь. Толкает выстрел не старше KICK_TIME; почти сверху или снизу и
	в транспорте - нет. Смертельная пуля в голову, а у трупа любая пуля в
	голову сносит голову: голова исчезает, тело не откачать, кровь летит на
	стены по ходу пули (MES.HeadGore, sv_gore.lua). Попадание в голову у
	стоящего - по ScalePlayerDamage, у рэгдолла - трассой по ходу пули через
	место попадания. Смертельная пуля в тело и пуля по лежащему или трупу -
	брызги на пол и стену позади (MES.BloodSpatter).

	Травматический снаряд (police_beanbag, урон DMG_PARALYZE) не роняет
	(8.4.3): даёт стан, как электрошокер, - временный показатель "shock"
	на BEANBAG_SHOCK_MIN..BEANBAG_SHOCK_MAX секунд, не тому, кто под
	героином, в транспорте, в noclip или бессмертен. Убил снаряд - тело
	отлетает, как от пули, но голову не сносит и крови нет. Электрошокер
	(weapon_taser) с шансом роняет нашим рэгдоллом и трясёт его -
	MES.Convulse(rag, секунд): кости получают случайные толчки, руки и ноги
	сильнее, к концу слабее.

	Труп на носилках. Носилки автора кладут на себя только живого без
	сознания: сажают его в невидимое сиденье, мёртвого туда не посадить.
	Поэтому тело, коснувшееся свободных носилок, заменяет манекен
	prop_dynamic: внешность трупа, поза lying_down (её же сиденье носилок
	даёт лежащему), прикреплён к носилкам и ездит с ними. Пока тело на
	носилках, ply.DeathRagdoll - манекен (поля player, crithit), рэгдолла
	нет. [E] по носилкам - тело ложится рядом снова рэгдоллом, так же,
	если носилки удалили. Класть тело на носилки не обязательно.

	Носилки (entities/ent_stretcher) ждут от гейммода GAMEMODE.Util:
	UnstuckPlayer(ply, расстояние) - вытолкнуть игрока из стены и
	NextTick(fn) - выполнить в следующем кадре. sAdmin slay_shot ждёт
	DarkRP.BlowHead(rag, ply) - снести голову трупу: кровь летит по ходу
	последней пули в игрока, без неё - во все стороны.
---------------------------------------------------------------------------]]

util.AddNetworkString("DarkRP.ClientRagdoll")

local plyMeta = FindMetaTable("Player")

local MAX_TIME = 3600 -- секунд без сознания, не больше
local FOLLOW = 0.1 -- игрок ходит за рэгдоллом
local REATTACH = 0.5 -- рэгдолл пропал (очистка карты, выход из машины): лечь снова через
local TELEPORT = 64 -- игрока перенесли дальше (bring, jail) - рэгдолл переезжает
local UNSTUCK = 72
local UNSTUCK_STEP = 8
local CRUSH_MIN = 10
local MAX_FORCE = 5000 -- толчок трупа от смертельного урона
local FORCE_DIST = 100 -- урон дальше от тела - толчок в центр ближайшей кости
local SYNC_EVERY = 0.5
local SYNC_DWELL = 0.5
local HEAD = "ValveBiped.Bip01_Head1"

-- выстрел: тело отлетает, голову сносит
local SHOT = bit.bor(DMG_BULLET, DMG_BUCKSHOT)
local KICK_TIME = 0.5 -- выстрел не старше - толкает тело
local KICK_MIN = 520 -- скорость верха тела от выстрела
local KICK_MAX = 760
local KICK_SCALE = 0.012 -- прибавка скорости за единицу силы пули
local KICK_ARMS = 0.6 -- руки отстают от тела
local KICK_FLAT = 0.2 -- выстрел почти сверху или снизу не толкает
local KICK_HEIGHT = 24
local HEAD_TRACE = 8 -- трасса по ходу пули через место попадания
local HEAD_HIT = 12 -- трасса не нашла кость: попадание ближе к голове - в голову
local SPATTER_BODY = 4 -- пятен от смертельной пули в тело
local SPATTER_BODY_DIST = 160
local SPATTER_RAG = 3 -- пятен от пули по лежащему или трупу
local SPATTER_RAG_DIST = 128
local BEANBAG = DMG_PARALYZE -- травматический снаряд police_beanbag: стан
local BEANBAG_SHOCK_MIN = 17 -- секунд стана "shock", как у электрошокера
local BEANBAG_SHOCK_MAX = 28
local KICKS = bit.bor(SHOT, BEANBAG) -- толкают тело убитого

-- прямой урон, который должен прийти через рэгдолл
local DIRECT = bit.bor(DMG_BULLET, DMG_BUCKSHOT, DMG_CLUB, DMG_SLASH, DMG_BLAST, DMG_CRUSH, DMG_VEHICLE, DMG_SHOCK)

-- [ply] = {finish, level, rag, hidden, pos, lost, norag}
local uncon = {}
-- [ply] = hidden: умер спрятанным, показать при возрождении
local deadHidden = {}
-- [rag] = {cuffed, sent = {[pl] = true}, seen = {[pl] = CurTime}}
local bodies = {}
-- [ply] = {t, sum, force, head}: пули по игроку за кадр t - сумма сил,
-- её длина и было ли попадание в голову
local shots = {}
local transferring = false

--[[---------------------------------------------------------------------------
	GAMEMODE.Util для носилок
---------------------------------------------------------------------------]]
local Util = {}

local function hullFree(pos, mins, maxs, filter)
	local tr = util.TraceHull({start = pos, endpos = pos, mins = mins, maxs = maxs, mask = MASK_PLAYERSOLID, filter = filter})
	return not tr.Hit and not tr.StartSolid
end

-- без прямой видимости через стену в соседнюю комнату не выталкиваем
local function inSight(from, to, z)
	local up = Vector(0, 0, z)
	return not util.TraceLine({start = from + up, endpos = to + up, mask = MASK_PLAYERSOLID_BRUSHONLY}).Hit
end

local RING = {}
for i = 0, 7 do
	local a = math.rad(i * 45)
	RING[#RING + 1] = Vector(math.cos(a), math.sin(a), 0)
end

--[[---------------------------------------------------------------------------
	Util:UnstuckPlayer(ply, dist[, ignore]) - игрок застрял (в стене, в полу,
	в другом игроке): ищем свободное место не дальше dist - выше, по кругу и
	по кругу выше, сначала в прямой видимости. ignore - энтити, которую не
	считать препятствием (рэгдолл, который убирается в этом кадре).
	Возвращает true, если игрок стоит свободно
---------------------------------------------------------------------------]]
function Util:UnstuckPlayer(ply, dist, ignore)
	if not IsValid(ply) then return false end

	local mins, maxs = ply:GetHull()
	if ply:Crouching() then mins, maxs = ply:GetHullDuck() end

	local filter = {ply}
	if IsValid(ignore) then filter[2] = ignore end

	local origin = ply:GetPos()
	if hullFree(origin, mins, maxs, filter) then return true end

	dist = math.max(tonumber(dist) or UNSTUCK, UNSTUCK_STEP)
	local eye = (maxs.z - mins.z) / 2

	for pass = 1, 2 do
		for r = UNSTUCK_STEP, dist, UNSTUCK_STEP do
			local spots = {origin + Vector(0, 0, r)}

			for _, dir in ipairs(RING) do
				spots[#spots + 1] = origin + dir * r
			end

			for _, dir in ipairs(RING) do
				spots[#spots + 1] = origin + dir * r + Vector(0, 0, r)
			end

			for _, pos in ipairs(spots) do
				if hullFree(pos, mins, maxs, filter) and (pass == 2 or inSight(origin, pos, eye)) then
					ply:SetPos(pos)
					return true
				end
			end
		end
	end

	return false
end

function Util:NextTick(fn)
	timer.Simple(0, fn)
end

--[[---------------------------------------------------------------------------
	Пули по игроку и голова рэгдолла (кровь - sv_gore.lua)
---------------------------------------------------------------------------]]
-- запись о пулях за этот кадр: дробь и несколько стрелков складываются
local function shotOf(ply)
	local CT = CurTime()
	local rec = shots[ply]

	if not rec or rec.t ~= CT then
		rec = {t = CT, sum = Vector(0, 0, 0), force = 0}
		shots[ply] = rec
	end

	return rec
end

local function noteShot(ply, dmg)
	local rec = shotOf(ply)
	local force = dmg:GetDamageForce()

	rec.sum = rec.sum + force
	rec.force = rec.force + force:Length()
end

-- недавний выстрел: сумма сил и её длина
local function recentShot(ply)
	local rec = shots[ply]

	if rec and CurTime() - rec.t <= KICK_TIME and not rec.sum:IsZero() then
		return rec.sum, rec.force
	end
end

-- куда летела пуля: по урону, иначе по недавнему выстрелу
local function shotDir(ply, dmg)
	if dmg and bit.band(dmg:GetDamageType(), SHOT) ~= 0 then
		local force = dmg:GetDamageForce()
		if not force:IsZero() then return force end
	end

	return (recentShot(ply))
end

-- толчок от выстрела: направление по земле и скорость верха тела
local function kickOf(ply, dmg)
	local dir, force = recentShot(ply)

	if not dir and dmg and bit.band(dmg:GetDamageType(), KICKS) ~= 0 then
		dir = dmg:GetDamageForce()
		force = dir:Length()
	end

	if not dir or dir:IsZero() then return end

	local flat = Vector(dir.x, dir.y, 0)
	local share = flat:Length() / dir:Length()
	if share < KICK_FLAT then return end

	flat:Normalize()

	return flat, math.Clamp(KICK_MIN + force * KICK_SCALE, KICK_MIN, KICK_MAX) * share
end

-- физика головы, если у модели она своя
local function headPhys(rag, bone)
	local idx = rag:TranslateBoneToPhysBone(bone)
	if not idx or idx < 0 or rag:TranslatePhysBoneToBone(idx) ~= bone then return end

	local phys = rag:GetPhysicsObjectNum(idx)
	if IsValid(phys) then return phys end
end

-- пуля попала в голову рэгдолла: трасса по ходу пули через место
-- попадания, не задела рэгдолл - ближайшая к месту кость
local function hitHead(rag, dmg)
	local bone = rag:LookupBone(HEAD)
	if not bone then return false end

	local head = headPhys(rag, bone)
	if not head then return false end

	local at = dmg:GetDamagePosition()
	local dir = dmg:GetDamageForce()

	if not dir:IsZero() then
		dir:Normalize()

		local tr = util.TraceLine({
			start = at - dir * HEAD_TRACE,
			endpos = at + dir * HEAD_TRACE,
			filter = function(e) return e == rag end,
			ignoreworld = true,
			mask = MASK_SHOT
		})

		if tr.Entity == rag then
			return rag:TranslatePhysBoneToBone(tr.PhysicsBone) == bone
		end
	end

	local best, bestDist

	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		if not IsValid(phys) then continue end

		local d = phys:LocalToWorld(phys:GetMassCenter()):DistToSqr(at)
		if not bestDist or d < bestDist then best, bestDist = phys, d end
	end

	return best == head and bestDist <= HEAD_HIT * HEAD_HIT
end

-- снести голову: голова исчезает (размер кости 0 - его же копирует манекен
-- на носилках), тело не откачать, кровь по ходу пули dir
local function blowHead(rag, dir)
	if not IsValid(rag) then return end

	rag.crithit = true

	local bone = rag:LookupBone(HEAD)
	if not bone or rag:GetManipulateBoneScale(bone):IsZero() then return end

	rag:ManipulateBoneScale(bone, Vector(0, 0, 0))

	local phys = headPhys(rag, bone)
	local pos = phys and phys:LocalToWorld(phys:GetMassCenter()) or rag:GetBonePosition(bone)

	MES.HeadGore(rag, pos, dir, phys)
end

-- пуля по трупу: в голову - голову сносит, иначе брызги
local function shotCorpse(rag, dmg)
	local ply = rag.player
	if not IsValid(ply) or ply:Alive() or ply.DeathRagdoll ~= rag or rag:GetClass() ~= "prop_ragdoll" then return end

	if hitHead(rag, dmg) then
		blowHead(rag, dmg:GetDamageForce())
	else
		MES.BloodSpatter(dmg:GetDamagePosition(), dmg:GetDamageForce(), rag, SPATTER_RAG, SPATTER_RAG_DIST)
	end
end

local function setup()
	GAMEMODE.Util = GAMEMODE.Util or {}
	GAMEMODE.Util.UnstuckPlayer = Util.UnstuckPlayer
	GAMEMODE.Util.NextTick = Util.NextTick

	DarkRP.BlowHead = function(rag, ply)
		blowHead(rag, IsValid(ply) and shotDir(ply) or nil)
	end
end

-- аддон грузится до гейммода
hook.Add("PostGamemodeLoaded", "MES.Ragdoll", setup)
if GAMEMODE and DarkRP then setup() end

--[[---------------------------------------------------------------------------
	Рэгдолл по игроку: внешность, поза костей, скорость
---------------------------------------------------------------------------]]
local function pushBody(rag, dmg)
	local force = dmg:GetDamageForce()
	local len = force:Length()
	if len <= 0 then return end
	if len > MAX_FORCE then force = force * (MAX_FORCE / len) end

	local at = dmg:GetDamagePosition()
	local best, bestDist

	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		if not IsValid(phys) then continue end

		local d = phys:GetPos():DistToSqr(at)
		if not bestDist or d < bestDist then best, bestDist = phys, d end
	end

	if not best then return end

	if bestDist <= FORCE_DIST * FORCE_DIST then
		best:ApplyForceOffset(force, at)
	else
		rag:GetPhysicsObjectNum(0):ApplyForceCenter(force)
	end
end

-- кость руки: от выстрела отстаёт
local function isArm(ent, bone)
	local name = string.lower(ent:GetBoneName(bone) or "")

	return string.find(name, "arm", 1, true) ~= nil or string.find(name, "hand", 1, true) ~= nil
end

-- kickDir, kickSpeed - толчок от выстрела (kickOf)
local function makeRagdoll(ply, dmg, kickDir, kickSpeed)
	local model = ply:GetModel()
	if not isstring(model) or model == "" then return end

	local rag = ents.Create("prop_ragdoll")
	if not IsValid(rag) then return end

	rag:SetModel(model)
	rag:SetPos(ply:GetPos())
	rag:SetAngles(Angle(0, ply:GetAngles().y, 0))
	rag:SetSkin(ply:GetSkin())

	for _, bg in ipairs(ply:GetBodyGroups() or {}) do
		rag:SetBodygroup(bg.id, ply:GetBodygroup(bg.id))
	end

	for i = 0, 31 do
		local sub = ply:GetSubMaterial(i)
		if sub and sub ~= "" then rag:SetSubMaterial(i, sub) end
	end

	-- "null" - невидимость sAdmin
	local mat = ply:GetMaterial()
	if mat ~= "" and mat ~= "null" then rag:SetMaterial(mat) end

	local col = ply:GetColor()
	rag:SetColor(Color(col.r, col.g, col.b, 255))

	rag:Spawn()
	rag:Activate()

	local count = rag:GetPhysicsObjectCount()
	if count < 1 then
		rag:Remove()
		return
	end

	local vel = ply:GetVelocity()
	local base = ply:GetPos().z
	local height = math.max(ply:EyePos().z - base, KICK_HEIGHT)

	for i = 0, count - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		if not IsValid(phys) then continue end

		local bone = rag:TranslatePhysBoneToBone(i)
		local pos, ang

		if bone and bone >= 0 then
			pos, ang = ply:GetBonePosition(bone)
		end

		if pos and ang then
			phys:SetPos(pos)
			phys:SetAngles(ang)
		end

		local v = vel

		-- выстрел: чем выше кость, тем быстрее летит от пули, ноги на месте
		if kickDir then
			local f = math.Clamp(((pos or phys:GetPos()).z - base) / height, 0, 1)

			if bone and bone >= 0 and isArm(rag, bone) then
				f = f * KICK_ARMS
			end

			v = vel + kickDir * (kickSpeed * f)
		end

		phys:SetVelocity(v)
		phys:Wake()
	end

	if dmg then
		pushBody(rag, dmg)
	end

	-- игроки проходят сквозь тела, пули и [E] - нет
	if ply:InVehicle() then
		-- умер в машине: секунду тело проходит сквозь всё, кроме мира, иначе
		-- физика выбросит его из кузова
		rag:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

		timer.Simple(1, function()
			if not IsValid(rag) then return end

			if rag:GetCollisionGroup() == COLLISION_GROUP_DEBRIS then
				rag:SetCollisionGroup(COLLISION_GROUP_WEAPON)
			elseif rag.oldcollision == COLLISION_GROUP_DEBRIS then
				-- тело уже несут ключами: группа вернётся, когда отпустят
				rag.oldcollision = COLLISION_GROUP_WEAPON
			end
		end)
	else
		rag:SetCollisionGroup(COLLISION_GROUP_WEAPON)
	end

	return rag
end

--[[---------------------------------------------------------------------------
	Спрятать игрока под рэгдоллом и показать обратно
---------------------------------------------------------------------------]]
local function hidePlayer(ply, st)
	if not st.hidden then
		st.hidden = {nodraw = ply:GetNoDraw(), solid = ply:IsSolid(), movetype = ply:GetMoveType()}
	end

	ply:SetNoDraw(true)
	ply:DrawWorldModel(false)
	ply:SetNotSolid(true)
	ply:SetMoveType(MOVETYPE_NONE)
end

-- keepMove: тип движения не трогать (возрождение ставит его само)
local function restore(ply, h, keepMove)
	-- без выбранного персонажа игрока прячет модуль персонажей
	if not ply.MCRHidden then
		ply:SetNoDraw(h.nodraw)
		ply:SetNotSolid(not h.solid)
	end

	ply:DrawWorldModel(true)

	if not keepMove and ply:GetMoveType() == MOVETYPE_NONE then
		ply:SetMoveType(h.movetype == MOVETYPE_NOCLIP and MOVETYPE_NOCLIP or MOVETYPE_WALK)
	end
end

local function showPlayer(ply, st, keepMove)
	local h = st.hidden
	if not h then return end

	st.hidden = nil
	restore(ply, h, keepMove)
end

-- куда встать: на землю под рэгдоллом
local function standPos(rag, ply)
	local pos = rag:GetPos()
	local tr = util.TraceLine({start = pos + Vector(0, 0, 16), endpos = pos - Vector(0, 0, 64), mask = MASK_PLAYERSOLID, filter = {rag, ply}})

	if tr.Hit and not tr.StartSolid then return tr.HitPos end

	return pos
end

local function onRagRemoved(rag)
	bodies[rag] = nil

	local ply = rag.player
	if not IsValid(ply) then return end

	if ply.DeathRagdoll == rag then
		ply.DeathRagdoll = nil
	end

	local st = uncon[ply]

	-- рэгдолл убрали со стороны (очистка карты, админ): игрок ляжет снова
	if st and st.rag == rag then
		st.rag = nil
		st.lost = CurTime()
	end
end

-- тот, кто теряет сознание, отпускает всё: задержанного, предмет в ключах
local function releaseHands(ply)
	if ply.ReleaseDrag then
		ply:ReleaseDrag()
	end

	local wep = ply:GetActiveWeapon()

	if IsValid(wep) and wep:GetClass() == "keys" and IsValid(wep.EntHolding) and wep.Reset then
		wep:Reset()
	end
end

local function attachRagdoll(ply, st)
	if st.norag then return end

	releaseHands(ply)

	-- упал от выстрела - отлетает, как труп
	local rag = makeRagdoll(ply, nil, kickOf(ply))

	if not rag then
		-- у модели нет физики: игрок остаётся стоять без сознания
		st.norag = true
		showPlayer(ply, st)
		return
	end

	rag.player = ply
	rag.ragdollize = true
	rag:CallOnRemove("MES.Ragdoll", onRagRemoved)

	hidePlayer(ply, st)

	st.rag = rag
	st.pos = ply:GetPos()
	st.lost = nil
	ply.DeathRagdoll = rag

	if ply.HandCuffed and DarkRP.applyCuffsToRag then
		DarkRP.applyCuffsToRag(rag)
	end

	ply:SincRagdoll(rag, rag.cuffed)

	return rag
end

-- очнуться: встать у рэгдолла
local function wake(ply, st)
	uncon[ply] = nil

	local rag = st.rag
	st.rag = nil

	local pos

	if IsValid(rag) then
		pos = standPos(rag, ply)
		rag:Remove()
	end

	showPlayer(ply, st)

	if pos and not ply:InVehicle() then
		ply:SetPos(pos)
		Util:UnstuckPlayer(ply, UNSTUCK, rag)
	end

	ply:SetDarkRPVar("unconscious", nil)
end

-- toDead: игрок умер, показать его при возрождении
local function clearState(ply, toDead)
	local st = uncon[ply]
	if not st then return end

	uncon[ply] = nil

	local rag = st.rag
	st.rag = nil

	if IsValid(rag) then
		rag:Remove()
	end

	if not IsValid(ply) then return end

	if toDead then
		deadHidden[ply] = st.hidden
	else
		showPlayer(ply, st, true)
	end

	ply:SetDarkRPVar("unconscious", nil)
end

local function removeBody(ply)
	local rag = ply.DeathRagdoll
	ply.DeathRagdoll = nil

	if IsValid(rag) and not rag.ragdollize then
		rag:Remove()
	end
end

--[[---------------------------------------------------------------------------
	Методы игрока
---------------------------------------------------------------------------]]
function plyMeta:Ragdollize(time, force, _, _, level)
	time = tonumber(time)
	if not time or time ~= time or time <= 0 then return end
	if not self:Alive() or self.MCRHidden or IsValid(self.pk_pill_ent) then return end
	if not force and self:GetMoveType() == MOVETYPE_NOCLIP then return end

	time = math.min(time, MAX_TIME)

	level = tonumber(level)
	if not level or level ~= level then level = time end
	level = math.Clamp(math.Round(level), 1, MAX_TIME)

	local finish = CurTime() + time
	local st = uncon[self]

	if st then
		st.finish = math.max(st.finish, finish)
		st.level = math.max(st.level, level)
	else
		st = {finish = finish, level = level}
		uncon[self] = st
	end

	self:SetDarkRPVar("unconscious", st.level)

	if self:InVehicle() then return end
	if IsValid(st.rag) then return st.rag end

	return attachRagdoll(self, st)
end

function plyMeta:UnRagdollize()
	local st = uncon[self]
	if not st then return false end

	wake(self, st)

	return true
end

function plyMeta:DeRagdollize()
	local st = uncon[self]
	if not st then return end

	local rag = st.rag
	st.rag = nil
	st.lost = CurTime()

	local pos

	if IsValid(rag) then
		pos = standPos(rag, self)
		rag:Remove()
	end

	showPlayer(self, st)

	if pos then
		self:SetPos(pos)
	end
end

function plyMeta:GoUncon()
	local st = uncon[self]
	if not st or not self:Alive() or self:InVehicle() then return end
	if IsValid(st.rag) then return st.rag end

	return attachRagdoll(self, st)
end

function plyMeta:IsUncon()
	return uncon[self] ~= nil
end

function plyMeta:SincRagdoll(rag, cuffed, target)
	if not IsValid(rag) then return end

	cuffed = cuffed and true or false

	local data = bodies[rag]

	if not data then
		data = {sent = {}, seen = {}}
		bodies[rag] = data
	end

	-- всем: кто видит рэгдолл, получит его ещё раз от таймера ниже
	if not target then
		data.cuffed = cuffed
		data.sent = {}
	end

	net.Start("DarkRP.ClientRagdoll")
		net.WriteEntity(self)
		net.WriteUInt(rag:EntIndex(), 32)
		net.WriteVector(self:GetPlayerColor())
		net.WriteBool(cuffed)
	if target then net.Send(target) else net.Broadcast() end
end

--[[---------------------------------------------------------------------------
	Труп на носилках (описание в начале файла)
---------------------------------------------------------------------------]]
local LIE_SEQ = "lying_down"
local LIE_ATTACH = "vehicle_feet_passenger0" -- точка сиденья, где лежит игрок
local LIE_TOUCH = 5 -- как у носилок: положили - 5 секунд их не трогают
local LIE_KICK = 10 -- как у носилок: сняли - 10 секунд тело не ляжет обратно
local LIE_SIDE = 24 -- тело кладём сбоку: зазор от края носилок
local LIE_FLOOR = 128 -- пол ищем не ниже
local LIE_LIFT = 8 -- тело опускается на пол с высоты
local ONE = Vector(1, 1, 1)

local cleaning = false

-- внешность с энтити на энтити той же модели: скин, группы тела,
-- материалы, цвет и размеры костей (снесённая голова)
local function copyLook(from, to)
	to:SetSkin(from:GetSkin())

	for _, bg in ipairs(from:GetBodyGroups() or {}) do
		to:SetBodygroup(bg.id, from:GetBodygroup(bg.id))
	end

	for i = 0, 31 do
		local sub = from:GetSubMaterial(i)
		if sub and sub ~= "" then to:SetSubMaterial(i, sub) end
	end

	local mat = from:GetMaterial()
	if mat ~= "" then to:SetMaterial(mat) end

	to:SetColor(from:GetColor())

	for i = 0, from:GetBoneCount() - 1 do
		local scale = from:GetManipulateBoneScale(i)
		if scale ~= ONE then to:ManipulateBoneScale(i, scale) end
	end
end

local function onDummyRemoved(dummy)
	bodies[dummy] = nil

	local gurney = dummy.MESStretcher

	if IsValid(gurney) and gurney.MESBody == dummy then
		gurney.MESBody = nil
		gurney.m_intLastTouch = CurTime() + LIE_TOUCH
	end

	local ply = dummy.player

	if IsValid(ply) and ply.DeathRagdoll == dummy then
		ply.DeathRagdoll = nil
	end
end

local function makeDummy(gurney, rag)
	local dummy = ents.Create("prop_dynamic")
	if not IsValid(dummy) then return end

	dummy:SetModel(rag:GetModel())

	-- без позы манекен стоял бы на носилках
	local seq = dummy:LookupSequence(LIE_SEQ)

	if not seq or seq < 0 then
		dummy:Remove()
		return
	end

	-- как лежит тот, кого носилки посадили в сиденье
	local seat = gurney.Stretcher
	local id = seat:LookupAttachment(LIE_ATTACH)
	local att = id and id > 0 and seat:GetAttachment(id)

	dummy:SetPos(att and att.Pos or seat:GetPos())
	dummy:SetAngles(att and att.Ang or seat:GetAngles())
	dummy:SetKeyValue("solid", "0")
	dummy:SetKeyValue("DefaultAnim", LIE_SEQ)
	dummy:Spawn()
	dummy:ResetSequence(seq)
	copyLook(rag, dummy)
	dummy:SetParent(gurney)

	return dummy
end

-- куда переложить тело с носилок: сбоку на пол, в прямой видимости от
-- носилок. Некуда - тело остаётся на носилках, но уже рэгдоллом
local function sideShift(gurney, dummy, center, low)
	if not IsValid(gurney) then return Vector(0, 0, LIE_LIFT) end

	local filter = {gurney, dummy}
	if IsValid(gurney.Stretcher) then filter[#filter + 1] = gurney.Stretcher end
	if IsValid(gurney:GetParent()) then filter[#filter + 1] = gurney:GetParent() end

	-- поперёк носилок
	local size = gurney:OBBMaxs() - gurney:OBBMins()
	local side, half = gurney:GetRight(), size.y / 2

	if size.y > size.x then
		side, half = gurney:GetForward(), size.x / 2
	end

	local from = gurney:WorldSpaceCenter()

	for _, sign in ipairs({1, -1}) do
		local spot = from + side * (sign * (half + LIE_SIDE))

		if not util.TraceLine({start = from, endpos = spot, mask = MASK_SOLID, filter = filter}).Hit then
			local tr = util.TraceLine({start = spot, endpos = spot - Vector(0, 0, LIE_FLOOR), mask = MASK_SOLID, filter = filter})

			if tr.Hit and not tr.StartSolid then
				return Vector(spot.x - center.x, spot.y - center.y, tr.HitPos.z + LIE_LIFT - low)
			end
		end
	end

	return Vector(0, 0, LIE_LIFT)
end

-- рэгдолл в позе манекена
local function bodyFromDummy(dummy, gurney)
	local rag = ents.Create("prop_ragdoll")
	if not IsValid(rag) then return end

	rag:SetModel(dummy:GetModel())
	rag:SetPos(dummy:GetPos())
	rag:SetAngles(dummy:GetAngles())
	rag:Spawn()
	rag:Activate()

	local count = rag:GetPhysicsObjectCount()

	if count < 1 then
		rag:Remove()
		return
	end

	copyLook(dummy, rag)

	local poses, low, sum, n = {}, math.huge, Vector(0, 0, 0), 0

	for i = 0, count - 1 do
		local bone = rag:TranslatePhysBoneToBone(i)
		local pos, ang

		if bone and bone >= 0 then
			pos, ang = dummy:GetBonePosition(bone)
		end

		if pos and ang then
			poses[i] = {pos, ang}
			low = math.min(low, pos.z)
			sum = sum + pos
			n = n + 1
		end
	end

	local shift = n > 0 and sideShift(gurney, dummy, sum / n, low) or Vector(0, 0, LIE_LIFT)

	for i = 0, count - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		if not IsValid(phys) then continue end

		local pose = poses[i]

		if pose then
			phys:SetPos(pose[1] + shift)
			phys:SetAngles(pose[2])
		end

		phys:Wake()
	end

	rag:SetCollisionGroup(COLLISION_GROUP_WEAPON)

	return rag
end

local putOnStretcher

-- тело коснулось носилок. В обработчике столкновения физику менять
-- нельзя - кладём в следующем кадре
local function bodyCollide(rag, data)
	local gurney = data.HitEntity
	if rag.MESLieNext or not IsValid(gurney) or gurney:GetClass() ~= "ent_stretcher" then return end

	rag.MESLieNext = true

	timer.Simple(0, function()
		if not IsValid(rag) then return end

		rag.MESLieNext = nil
		putOnStretcher(gurney, rag)
	end)
end

local function watchBody(rag)
	if rag.MESWatched then return end

	rag.MESWatched = true
	rag:AddCallback("PhysicsCollide", bodyCollide)
end

-- снять тело с носилок: рэгдолл рядом с носилками
local function takeOff(dummy)
	local ply = dummy.player
	local gurney = dummy.MESStretcher

	if not IsValid(ply) or ply:Alive() or ply.DeathRagdoll ~= dummy then
		dummy:Remove()
		return
	end

	local rag = bodyFromDummy(dummy, gurney)
	if not rag then return end

	rag.player = ply
	rag.crithit = dummy.crithit
	rag:CallOnRemove("MES.Ragdoll", onRagRemoved)
	watchBody(rag)

	ply.DeathRagdoll = rag
	dummy:Remove()

	if IsValid(gurney) then
		gurney.m_intLastTouch = CurTime() + LIE_KICK
	end

	ply:SincRagdoll(rag, false)

	return rag
end

-- носилки удалили (убрали машину скорой, админ): тело остаётся рядом.
-- При очистке карты убираются и носилки, и манекен
local function onGurneyRemoved(gurney)
	local dummy = gurney.MESBody
	if not IsValid(dummy) or cleaning then return end

	takeOff(dummy)
end

function putOnStretcher(gurney, rag)
	if not IsValid(gurney) or not IsValid(rag) or rag.ragdollize then return end

	local seat = gurney.Stretcher
	if not IsValid(seat) or IsValid(seat:GetDriver()) or IsValid(gurney.MESBody) then return end
	if (gurney.m_intLastTouch or 0) > CurTime() then return end

	local ply = rag.player
	if not IsValid(ply) or ply:Alive() or ply.DeathRagdoll ~= rag then return end

	local dummy = makeDummy(gurney, rag)
	if not dummy then return end

	dummy.player = ply
	dummy.crithit = rag.crithit
	dummy.MESStretcher = gurney
	dummy:CallOnRemove("MES.Ragdoll", onDummyRemoved)

	-- носилки заняты: касание и [E] автора (ENT:StartTouch, ENT:Use) не срабатывают
	gurney.MESBody = dummy
	gurney.m_intLastTouch = math.huge
	gurney:CallOnRemove("MES.StretcherBody", onGurneyRemoved)

	-- тело несли ключами
	local keys = rag.Draged

	if IsValid(keys) and keys.Reset then
		keys:Reset()
	end

	ply.DeathRagdoll = dummy
	rag:Remove()

	ply:SincRagdoll(dummy, false)

	return dummy
end

-- [E] по носилкам с телом - снять тело. Shift+[E] - как у автора: прицепить
-- носилки к машине скорой или отцепить. С прицепленных тело не снять
hook.Add("PlayerUse", "MES.StretcherBody", function(ply, ent)
	local dummy = ent.MESBody
	if not IsValid(dummy) or ply:KeyDown(IN_SPEED) then return end

	local CT = CurTime()

	if not IsValid(ent.parented) and (ent.used or 0) <= CT then
		ent.used = CT + 1
		takeOff(dummy)
	end

	return false
end)

hook.Add("PreCleanupMap", "MES.Ragdoll", function() cleaning = true end)
hook.Add("PostCleanupMap", "MES.Ragdoll", function() cleaning = false end)

--[[---------------------------------------------------------------------------
	Таймеры: срок, игрок за рэгдоллом, досылка рэгдоллов
---------------------------------------------------------------------------]]
timer.Create("MES.Ragdoll", FOLLOW, 0, function()
	local CT = CurTime()

	for ply, st in pairs(uncon) do
		if not IsValid(ply) then
			uncon[ply] = nil
			if IsValid(st.rag) then st.rag:Remove() end
			continue
		end

		if not ply:Alive() then
			clearState(ply, true)
			continue
		end

		if CT >= st.finish then
			wake(ply, st)
			continue
		end

		local rag = st.rag

		if IsValid(rag) then
			if ply:InVehicle() then
				-- посадили в транспорт: рэгдолл не нужен
				st.rag = nil
				rag:Remove()
				showPlayer(ply, st)
			elseif ply:GetPos():DistToSqr(st.pos) > TELEPORT * TELEPORT then
				-- игрока перенесли: рэгдолл появляется на новом месте
				st.rag = nil
				rag:Remove()
				attachRagdoll(ply, st)
			else
				local pos = rag:GetPos()
				ply:SetPos(pos)
				st.pos = pos
			end
		elseif ply:InVehicle() then
			st.lost = nil
		elseif not st.norag then
			st.lost = st.lost or CT

			if CT - st.lost >= REATTACH then
				attachRagdoll(ply, st)
			end
		end
	end
end)

timer.Create("MES.RagdollSync", SYNC_EVERY, 0, function()
	local CT = CurTime()
	local humans

	for rag, data in pairs(bodies) do
		if not IsValid(rag) then
			bodies[rag] = nil
			continue
		end

		local owner = rag.player
		if not IsValid(owner) then continue end

		humans = humans or player.GetHumans()

		for _, pl in ipairs(humans) do
			if data.sent[pl] then continue end

			if not pl:TestPVS(rag) then
				data.seen[pl] = nil
			elseif not data.seen[pl] then
				data.seen[pl] = CT
			elseif CT - data.seen[pl] >= SYNC_DWELL then
				data.seen[pl] = nil
				data.sent[pl] = true
				owner:SincRagdoll(rag, data.cuffed, pl)
			end
		end
	end
end)

--[[---------------------------------------------------------------------------
	Смерть, возрождение, выход
---------------------------------------------------------------------------]]
hook.Add("DoPlayerDeath", "MES.Ragdoll", function(ply, attacker, dmg)
	if IsValid(ply.pk_pill_ent) then return end

	removeBody(ply)

	local st = uncon[ply]
	local rag

	if st then
		uncon[ply] = nil
		rag = st.rag
		st.rag = nil
		deadHidden[ply] = st.hidden
		ply:SetDarkRPVar("unconscious", nil)
	end

	local shot = dmg ~= nil and bit.band(dmg:GetDamageType(), SHOT) ~= 0
	local kick = dmg ~= nil and bit.band(dmg:GetDamageType(), KICKS) ~= 0
	local head = false

	if IsValid(rag) then
		rag.ragdollize = nil
		head = shot and hitHead(rag, dmg)
	else
		local kickDir, kickSpeed

		if kick and not ply:InVehicle() then
			kickDir, kickSpeed = kickOf(ply, dmg)
		end

		rag = makeRagdoll(ply, dmg, kickDir, kickSpeed)
		if not rag then return end

		rag.player = ply
		rag:CallOnRemove("MES.Ragdoll", onRagRemoved)
		ply:SincRagdoll(rag, false)

		local rec = shots[ply]
		head = shot and rec ~= nil and rec.t == CurTime() and (rec.head or ply:LastHitGroup() == HITGROUP_HEAD)
	end

	ply.DeathRagdoll = rag
	watchBody(rag)

	-- смертельный выстрел в голову (sAdmin slay_shot, пилюли ppp)
	if ply.crithit then
		ply.crithit = nil
		rag.crithit = true
	end

	if head then
		blowHead(rag, shotDir(ply, dmg))
	elseif shot then
		MES.BloodSpatter(dmg:GetDamagePosition(), dmg:GetDamageForce(), {rag, ply}, SPATTER_BODY, SPATTER_BODY_DIST)
	end
end)

-- стандартный рэгдолл движка (GM:DoPlayerDeath) не нужен, если есть свой
hook.Add("PlayerDeath", "MES.Ragdoll", function(ply)
	if not IsValid(ply.DeathRagdoll) then return end

	local engineRag = ply:GetRagdollEntity()

	if IsValid(engineRag) and engineRag ~= ply.DeathRagdoll then
		engineRag:Remove()
	end
end)

hook.Add("PlayerSilentDeath", "MES.Ragdoll", function(ply)
	clearState(ply, true)
end)

hook.Add("PlayerSpawn", "MES.Ragdoll", function(ply)
	clearState(ply)
	shots[ply] = nil

	local h = deadHidden[ply]

	if h then
		deadHidden[ply] = nil
		restore(ply, h, true)
	end

	if not ply.emsspawned then
		removeBody(ply)
	end
end)

hook.Add("PlayerDisconnected", "MES.Ragdoll", function(ply)
	local st = uncon[ply]
	uncon[ply] = nil
	deadHidden[ply] = nil
	shots[ply] = nil

	if st and IsValid(st.rag) then
		st.rag:Remove()
	end

	removeBody(ply)

	for _, data in pairs(bodies) do
		data.sent[ply] = nil
		data.seen[ply] = nil
	end
end)

-- наручники надели на лежащего без сознания (дубинка, sAdmin) или сняли
hook.Add("DarkRPVarChanged", "MES.Ragdoll", function(ply, var, old, new)
	if var ~= "HandCuffed" then return end

	local rag = ply.DeathRagdoll
	if not IsValid(rag) then return end

	if new == nil then
		if not rag.cuffed then return end

		if IsValid(rag.CuffsRope) then
			rag.CuffsRope:Remove()
		end

		rag.CuffsRope = nil
		rag.cuffed = nil
		ply:SincRagdoll(rag, false)
	elseif rag.ragdollize and not rag.cuffed and DarkRP.applyCuffsToRag then
		DarkRP.applyCuffsToRag(rag)
		ply:SincRagdoll(rag, true)
	end
end)

--[[---------------------------------------------------------------------------
	Урон: по рэгдоллу - игроку, по спрятанному игроку - только через рэгдолл.
	Пули по игроку запоминаются (отлёт, голова), пуля по трупу сносит голову
	или оставляет брызги
---------------------------------------------------------------------------]]
hook.Add("EntityTakeDamage", "MES.Ragdoll", function(ent, dmg)
	if transferring then return end

	if ent:IsPlayer() then
		local st = uncon[ent]

		if st and IsValid(st.rag) and bit.band(dmg:GetDamageType(), DIRECT) ~= 0 then
			return true
		end

		if bit.band(dmg:GetDamageType(), KICKS) ~= 0 then
			noteShot(ent, dmg)
		end

		return
	end

	local shot = bit.band(dmg:GetDamageType(), SHOT) ~= 0 and dmg:GetDamage() > 0

	if not ent.ragdollize then
		if shot then shotCorpse(ent, dmg) end
		return
	end

	local ply = ent.player
	local st = IsValid(ply) and uncon[ply]
	if not st or st.rag ~= ent or not ply:Alive() then return end

	local attacker = dmg:GetAttacker()

	if dmg:IsDamageType(DMG_CRUSH) and (dmg:GetDamage() < CRUSH_MIN or not IsValid(attacker) or attacker == ent or attacker == ply or attacker:IsWorld()) then
		return
	end

	local inflictor = dmg:GetInflictor()
	local info = DamageInfo()
	info:SetDamage(dmg:GetDamage())
	info:SetDamageType(dmg:GetDamageType())
	info:SetAttacker(IsValid(attacker) and attacker or game.GetWorld())
	info:SetInflictor(IsValid(inflictor) and inflictor or info:GetAttacker())
	info:SetDamageForce(dmg:GetDamageForce())
	info:SetDamagePosition(dmg:GetDamagePosition())

	transferring = true
	ply:TakeDamageInfo(info)
	transferring = false

	-- пуля по лежащему без сознания: брызги (убила - их делает DoPlayerDeath)
	if shot and ply:Alive() then
		MES.BloodSpatter(dmg:GetDamagePosition(), dmg:GetDamageForce(), ent, SPATTER_RAG, SPATTER_RAG_DIST)
	end
end)

-- попадание в голову стоящего: ScalePlayerDamage приходит раньше урона
hook.Add("ScalePlayerDamage", "MES.Ragdoll", function(ply, hitgroup)
	if hitgroup == HITGROUP_HEAD then
		shotOf(ply).head = true
	end
end)

-- травматический снаряд (8.4.3): не роняет, а даёт стан электрошокера -
-- "shock" на 17-28 секунд (дезориентация: атака срывается, мышь медленная,
-- без прыжка, шаг 70). Урон уже прошёл, игрок жив. Как у электрошокера
-- автора: не под героином и не в транспорте; не в noclip. Стан и тогда,
-- когда урон не прошёл (took = false: броня, хуки урона), но не тому, кого
-- урон не берёт по правилам (бессмертие - PlayerShouldTakeDamage).
-- Лежащему без сознания стан тоже: урон по рэгдоллу приходит игроку
hook.Add("PostEntityTakeDamage", "MES.Beanbag", function(ent, dmg, took)
	if not IsValid(ent) or not ent:IsPlayer() or not ent:Alive() then return end
	if bit.band(dmg:GetDamageType(), BEANBAG) == 0 or dmg:GetDamage() <= 0 then return end
	if ent:InVehicle() or ent:getDarkRPVar("heroin") or ent:HasGodMode() then return end
	if ent:GetMoveType() == MOVETYPE_NOCLIP then return end
	if not took and hook.Run("PlayerShouldTakeDamage", ent, dmg:GetAttacker()) == false then return end
	if not ent.AddTempStat then return end

	ent:AddTempStat("shock", math.random(BEANBAG_SHOCK_MIN, BEANBAG_SHOCK_MAX))
end)

--[[---------------------------------------------------------------------------
	Судороги рэгдолла (электрошокер): MES.Convulse(rag, секунд)
	Каждые CONVULSE_STEP секунд каждая кость получает толчок в случайную
	сторону: CONVULSE_SPEED в начале, к концу слабеет до доли CONVULSE_FADE.
	Руки и ноги дёргаются сильнее корпуса (CONVULSE_BONES - доля по части
	имени кости, остальные - CONVULSE_OTHER). Повторный вызов продлевает.
	Судороги кончаются, когда рэгдолл пропал или игрок умер (рэгдолл стал
	трупом).
---------------------------------------------------------------------------]]
local CONVULSE_STEP = 0.06
local CONVULSE_SPEED = 150
local CONVULSE_FADE = 0.3
local CONVULSE_MAX = 30 -- секунд, не больше
local CONVULSE_OTHER = 0.5
local CONVULSE_BONES = {
	{"Hand", 1}, {"Forearm", 1}, {"UpperArm", 1},
	{"Thigh", 0.8}, {"Calf", 0.8}, {"Foot", 0.8},
	{"Head", 0.6}, {"Spine", 0.35}, {"Pelvis", 0.25},
}

local convulse = {}

local function convulseWeight(rag, physIdx)
	local name = rag:GetBoneName(rag:TranslatePhysBoneToBone(physIdx)) or ""

	for _, w in ipairs(CONVULSE_BONES) do
		if string.find(name, w[1], 1, true) then return w[2] end
	end

	return CONVULSE_OTHER
end

function MES.Convulse(rag, seconds)
	seconds = tonumber(seconds)
	if not IsValid(rag) or rag:GetClass() ~= "prop_ragdoll" then return end
	if not seconds or seconds ~= seconds or seconds <= 0 then return end

	seconds = math.min(seconds, CONVULSE_MAX)

	local now = CurTime()
	local st = convulse[rag]

	if st and st.finish > now then
		st.finish = math.max(st.finish, now + seconds)
		return
	end

	local weights = {}

	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		weights[i] = convulseWeight(rag, i)
	end

	convulse[rag] = {start = now, finish = now + seconds, nextAt = now, weights = weights, live = rag.ragdollize}
end

hook.Add("Think", "MES.Convulse", function()
	if not next(convulse) then return end

	local now = CurTime()

	for rag, st in pairs(convulse) do
		if not IsValid(rag) or now >= st.finish or (st.live and not rag.ragdollize) then
			convulse[rag] = nil
		elseif now >= st.nextAt then
			st.nextAt = now + CONVULSE_STEP

			local left = (st.finish - now) / math.max(st.finish - st.start, 0.01)
			local speed = CONVULSE_SPEED * (CONVULSE_FADE + (1 - CONVULSE_FADE) * left)

			for i, w in pairs(st.weights) do
				local phys = rag:GetPhysicsObjectNum(i)

				if IsValid(phys) then
					phys:Wake()
					phys:AddVelocity(VectorRand() * speed * w)
				end
			end
		end
	end
end)

--[[---------------------------------------------------------------------------
	Транспорт и носилки
---------------------------------------------------------------------------]]
hook.Add("CanExitVehicle", "MES.Ragdoll", function(veh, ply)
	if uncon[ply] then return false end

	local stretcher = veh.Stretcher
	if not IsValid(stretcher) or not stretcher.KickPlayer then return end

	-- с носилок встают через ENT:KickPlayer: рядом с носилками, не в стене
	Util:NextTick(function()
		if IsValid(stretcher) and IsValid(veh) and IsValid(ply) and veh:GetDriver() == ply then
			stretcher:KickPlayer()
		end
	end)

	return false
end)

hook.Add("PlayerLeaveVehicle", "MES.Ragdoll", function(ply, veh)
	local stretcher = veh.Stretcher
	if not IsValid(stretcher) and not uncon[ply] then return end

	Util:NextTick(function()
		if not IsValid(ply) or not ply:Alive() or ply:InVehicle() then return end

		if IsValid(stretcher) then
			-- ENT:Enter ставит игроку группу столкновений оружия, снять её больше некому
			if ply:GetCollisionGroup() == COLLISION_GROUP_WEAPON then
				ply:SetCollisionGroup(COLLISION_GROUP_PLAYER)
			end

			-- сняли с носилок не через KickPlayer (врач нажал [E], носилки удалили)
			if (ply.m_intStretcherExitTime or 0) <= CurTime() then
				ply:SetPos(stretcher:GetPos())
				Util:UnstuckPlayer(ply, UNSTUCK)
			end
		end

		ply:GoUncon()
	end)
end)
