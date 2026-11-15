--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Кровь от выстрелов - клиент (пятна и лужу ставит sv_gore.lua)

	net MES.Gore S->C (Vector место, Normal направление пули, Bool была ли
	пуля) - голову снесло. Облако - эффекты крови движка, как в эффекте
	автора "headshot" (client/util.lua: bloodspray с флагами 3 и размером 6
	плюс BloodImpact): тёмное облако с ошмётками и каплями, за полсекунды
	оседает. Сразу: облако bloodspray (капли летят по ходу пули), брызги
	BloodImpact назад к стрелку и FORWARD_HITS вперёд по ходу пули. Через
	SECOND секунды ещё SECOND_HITS брызг вокруг места - облако расходится.
	Без пули всё летит во все стороны. Эффекты движка видны и при
	violence_hblood 0 (его ставит гейммод).
---------------------------------------------------------------------------]]

local SPRAY = "bloodspray"
local SPRAY_FLAGS = 3 -- капли и ошмётки (FX_BLOODSPRAY_DROPS + FX_BLOODSPRAY_GORE)
local SPRAY_SCALE = 6
local IMPACT = "BloodImpact" -- брызги летят против нормали эффекта
local FORWARD_HITS = 2
local FORWARD_NOISE = 0.25
local SECOND = 0.12
local SECOND_HITS = {4, 6}
local SECOND_OFFSET = 6

local ZERO = Vector(0, 0, 0)

local function effect(name, pos, normal, flags, scale)
	local ef = EffectData()
	ef:SetOrigin(pos)
	ef:SetNormal(normal)
	ef:SetColor(BLOOD_COLOR_RED)

	if flags then ef:SetFlags(flags) end
	if scale then ef:SetScale(scale) end

	util.Effect(name, ef)
end

-- брызги BloodImpact в сторону out
local function splash(pos, out)
	effect(IMPACT, pos, -out)
end

local function spread(dir, noise)
	local v = dir + VectorRand() * noise
	v:Normalize()

	return v
end

-- в стороны и немного вверх
local function aside()
	local a = math.Rand(0, math.pi * 2)
	local v = Vector(math.cos(a), math.sin(a), math.Rand(-0.2, 0.6))
	v:Normalize()

	return v
end

local function burst(pos, dir, aimed)
	effect(SPRAY, pos, aimed and dir or ZERO, SPRAY_FLAGS, SPRAY_SCALE)

	if aimed then
		splash(pos, -dir)

		for _ = 1, FORWARD_HITS do
			splash(pos, spread(dir, FORWARD_NOISE))
		end
	else
		for _ = 1, FORWARD_HITS + 1 do
			splash(pos, aside())
		end
	end
end

local function second(pos)
	for _ = 1, math.random(SECOND_HITS[1], SECOND_HITS[2]) do
		splash(pos + VectorRand() * SECOND_OFFSET, aside())
	end
end

net.Receive("MES.Gore", function()
	local pos = net.ReadVector()
	local dir = net.ReadNormal()
	local aimed = net.ReadBool()

	burst(pos, dir, aimed)

	timer.Simple(SECOND, function()
		second(pos)
	end)
end)
