--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Кровь от выстрелов - сервер (облако крови рисует cl_gore.lua)

	MES.HeadGore(rag, pos, dir[, phys]) - голову снесло (sv_ragdoll.lua):
	pos - где была голова, dir - куда летела пуля (nil - пули не было,
	sAdmin slay_shot), phys - физика головы рэгдолла. Пятна крови:
	  - по ходу пули HEAD_SPRAY пятен на стены, машины и пол на расстоянии
	    от трети HEAD_DIST до HEAD_DIST (без пули их нет);
	  - сразу SPLATS капель на полу вокруг, от SPLAT_MIN до SPLAT_MAX от
	    головы, с пулей - больше по её ходу;
	  - под шеей лужа (шаг 11, как на видео с сервера): большое пятно сразу
	    и такое же через POOL_AGAIN_MIN..POOL_AGAIN_MAX секунд - там, где
	    шея в этот момент, со сдвигом до POOL_SHIFT (лужа растекается).
	    Пятна луж - декали автора Blood.Stain* (shared/workarounds.lua).
	Клиентам, у кого место в зоне видимости (PVS), уходит net MES.Gore
	S->C: Vector место, Normal направление пули, Bool была ли пуля -
	клиент рисует облако крови.

	MES.BloodSpatter(pos, dir, ignore, count, dist) - брызги от попадания в
	тело: count пятен на стене или полу позади, не дальше dist. ignore -
	энтити или таблица энтити, сквозь которые кровь пролетает (само тело).

	Брызги и капли - декаль движка "Blood", лужи - Blood.Stain*: их видят
	все, кто рядом.
---------------------------------------------------------------------------]]

util.AddNetworkString("MES.Gore")

local DECAL = "Blood"

local HEAD_DIST = 180
local HEAD_SPRAY = 12 -- пятен по ходу пули
local HEAD_NOISE = 0.5 -- разброс брызг вокруг хода пули
local SPRAY_UP = 0.35 -- брызги почти не летят вверх
local SPRAY_DOWN = -0.9

local SPLATS = 5 -- капель на полу вокруг головы
local SPLAT_MIN = 24
local SPLAT_MAX = 100
local SPLAT_BIAS = 0.8 -- с пулей капли ложатся больше по её ходу
local SPLAT_DEPTH = 128

local SPATTER_NOISE = 0.3

-- лужа под шеей: пятно сразу и такое же через 3-4 секунды
local POOL_DECALS = {"Blood.Stain1", "Blood.Stain2", "Blood.Stain3", "Blood.Stain5", "Blood.Stain6"}
local POOL_AGAIN_MIN, POOL_AGAIN_MAX = 3, 4
local POOL_SHIFT = 10
local POOL_LIFT = 8
local POOL_DEPTH = 128

local UP = Vector(0, 0, 1)

local function flatRandom()
	local a = math.Rand(0, math.pi * 2)
	return Vector(math.cos(a), math.sin(a), 0)
end

-- пятна по направлению dir с разбросом noise на расстоянии от 0.3 dist до dist
local function spray(pos, dir, noise, count, dist, ignore, near)
	for _ = 1, count do
		local v = dir + VectorRand() * noise
		v.z = math.Clamp(v.z, SPRAY_DOWN, SPRAY_UP)
		v:Normalize()

		util.Decal(DECAL, pos, pos + v * math.Rand(dist * (near or 0.5), dist), ignore)
	end
end

-- пятно на полу под точкой at (не сквозь стену от pos)
local function floorDecal(pos, at, ignore, depth)
	local tr = util.TraceLine({start = pos, endpos = at, filter = ignore, mask = MASK_SOLID_BRUSHONLY})

	if tr.Hit then
		at = tr.HitPos + tr.HitNormal * 2
	end

	util.Decal(DECAL, at, at - UP * depth, ignore)
end

-- капли на полу вокруг головы, с пулей - больше по её ходу
local function splats(pos, dir, count, ignore)
	local flat = dir and Vector(dir.x, dir.y, 0)

	if flat and flat:LengthSqr() > 0.01 then
		flat:Normalize()
	else
		flat = nil
	end

	for _ = 1, count do
		local v = flatRandom()

		if flat then
			v = v + flat * SPLAT_BIAS
			v:Normalize()
		end

		floorDecal(pos, pos + v * math.Rand(SPLAT_MIN, SPLAT_MAX), ignore, SPLAT_DEPTH)
	end
end

-- лужа под шеей (phys - физика головы) там, где тело лежит сейчас
local function pool(rag, phys, decal, shift)
	if not IsValid(rag) then return end

	local start = (IsValid(phys) and phys:GetPos() or rag:WorldSpaceCenter()) + UP * POOL_LIFT

	if shift then
		start = start + flatRandom() * math.Rand(0, shift)
	end

	util.Decal(decal, start, start - UP * POOL_DEPTH, rag)
end

function MES.HeadGore(rag, pos, dir, phys)
	if not IsValid(rag) or not pos then return end

	local aimed = dir ~= nil and not dir:IsZero()
	dir = aimed and dir:GetNormalized() or UP

	if aimed then
		spray(pos, dir, HEAD_NOISE, HEAD_SPRAY, HEAD_DIST, rag, 0.3)
	end

	splats(pos, aimed and dir or nil, SPLATS, rag)

	local decal = POOL_DECALS[math.random(#POOL_DECALS)]

	pool(rag, phys, decal)

	timer.Simple(math.Rand(POOL_AGAIN_MIN, POOL_AGAIN_MAX), function()
		pool(rag, phys, decal, POOL_SHIFT)
	end)

	net.Start("MES.Gore")
		net.WriteVector(pos)
		net.WriteNormal(dir)
		net.WriteBool(aimed)
	net.SendPVS(pos)
end

function MES.BloodSpatter(pos, dir, ignore, count, dist)
	if not pos or not dir or dir:IsZero() then return end

	spray(pos, dir:GetNormalized(), SPATTER_NOISE, count, dist, ignore)
end
