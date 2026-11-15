--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Еда - сервер

	[E] по еде на земле (spawned_food, ENT:Use) или [E] с едой в руках
	(ключи) - одна порция. Еда с delay в каталоге (spawnlist/food.lua)
	съедается за delay секунд: полоса прогресса (DrawProgressBar), звук
	из DarkRP.FoodSounds, модель еды в правой руке у всех ("ShowModelR").
	Отошёл дальше EAT_RANGE, еду унесли, потерял сознание, сел в машину,
	надели наручники, умер - порция не засчитана. Без delay (и у игрока-
	пилюли из ppp) - сразу. Пока едят, еду не взять в инвентарь (InUse).
	Пока употребляет сигареты или таблетки (sv_drugs.lua) - не ест.
	Сигарета во рту или закрытое лицо - нельзя (ply:CanConsume, sh_init.lua).

	Порция (поля каталога; у приготовленного - поля предмета, McINVItem):
	energy - калории до maxenergy (без него - до DarkRP.Hunger.ENERGY_MAX),
	минус - убавить; thirst - вода (минус - солёное и сладкое сушит);
	hunger - секунд сытости, stamina - секунд энергичности (временные
	состояния); alcohol - опьянение; toxic - отравление (сырое мясо).
	uses - порций в одной еде: последняя порция - еда исчезает, иначе
	uses и вес (ent.weight) убавляются.

	Испорченная еда: срок свежести (ent.mt, ставят DarkRP.SpawnFood и
	инвентарь) прошёл больше чем на btime * ROT_SPOIL - как значок
	испорченной еды в инвентаре (inventory/cl_init.lua). Калорий и
	сытости ROT_FOOD от обычного, отравление ROT_TOXIC, тошнота.

	API (сервер):
	DarkRP.EatFood(ply, ent[, сразу]) - начать есть; true - начал или съел.
	DarkRP.StopEating(ply) - прервать.
	DarkRP.IsEating(ply) - ест ли сейчас.
	hook "DarkRP.PlayerAte"(ply, класс, поля еды, ent, испорчена) - порция
	засчитана (ent уже может быть удалён).
---------------------------------------------------------------------------]]

local EAT_RANGE = 100 -- от глаз до центра еды
local EAT_GAP = 0.5 -- секунд между порциями (ply.eatdelay)
local EAT_CHECK = 0.1 -- секунд: проверка, что едящий может есть дальше
local SOUND_LEVEL = 60

local ROT_SPOIL = 5
local ROT_FOOD = 0.5
local ROT_TOXIC = 20
local ROT_NAUSEA = 60

-- поля порции, которые может переопределить предмет (приготовленная еда)
local FIELDS = {"energy", "maxenergy", "thirst", "hunger", "stamina", "alcohol", "toxic", "delay"}

-- [ply] = {ent, food, class, finish, sound}
local eating = {}

local function foodOf(ent)
	local class = ent.Geteclass and ent:Geteclass()
	local data = isstring(class) and DarkRP.Food[class]
	if not istable(data) then return nil end

	local food = {}

	for k, v in pairs(data) do
		food[k] = v
	end

	local item = ent.McINVItem

	if istable(item) then
		for _, key in ipairs(FIELDS) do
			local v = tonumber(item[key])
			if v and v == v and v ~= math.huge and v ~= -math.huge then food[key] = v end
		end
	end

	return food, class
end

local function isRotten(ent, food)
	local mt, btime = tonumber(ent.mt), tonumber(food.btime)
	if not mt or not btime then return false end

	return mt + btime * ROT_SPOIL < os.time()
end

-- вернёт текст отказа ("" - молча) или nil
local function blocked(ply, ent)
	if not ply:Alive() or ply:getDarkRPVar("unconscious") or ply:getDarkRPVar("HandCuffed") or ply:InVehicle() then return "" end
	if ent.McINVTaken then return "" end

	-- пилюля (ppp) кусает сама, её дальность своя
	if not IsValid(ply.pk_pill_ent) and ply:EyePos():DistToSqr(ent:WorldSpaceCenter()) > EAT_RANGE * EAT_RANGE then return "" end

	local user = ent.InUse
	if user == true or (isentity(user) and IsValid(user) and user ~= ply) then return "Это уже кто-то ест" end

	local keys = ent.Draged
	if keys == true then return "Еда закреплена" end
	if isentity(keys) and IsValid(keys) and keys:GetOwner() ~= ply then return "Еду держит другой человек" end

	return nil
end

local function stop(ply, finished)
	local e = eating[ply]
	if not e then return end

	eating[ply] = nil

	if IsValid(e.ent) and e.ent.InUse == ply then e.ent.InUse = nil end
	if not IsValid(ply) then return end

	if e.sound then ply:StopSound(e.sound) end
	if finished then return end

	net.SendSingleMessage("RemovePropgressBar", ply)
	DarkRP.UIEffect(nil, "ShowModelR", {ply:UserID(), 0, e.model, e.material})
end

local function portion(ply, ent, food, class)
	local rotten = isRotten(ent, food)
	local mul = rotten and ROT_FOOD or 1
	local hunger = DarkRP.Hunger

	local energy = tonumber(food.energy) or 0

	if energy > 0 then
		ply:AddEnergy(energy * mul, tonumber(food.maxenergy) or hunger.ENERGY_MAX)
	elseif energy < 0 then
		ply:TakeEnergy(-energy)
	end

	local thirst = tonumber(food.thirst) or 0

	if thirst > 0 then
		ply:AddThirst(thirst)
	elseif thirst < 0 then
		ply:TakeThirst(-thirst)
	end

	local sated = (tonumber(food.hunger) or 0) * mul
	if sated > 0 then ply:AddTempStat("hunger", sated) end

	local stamina = tonumber(food.stamina) or 0
	if stamina > 0 then ply:AddTempStat("stamina", stamina) end

	local alcohol = tonumber(food.alcohol) or 0
	if alcohol > 0 then ply:AddAlcohol(alcohol) end

	local toxic = (tonumber(food.toxic) or 0) + (rotten and ROT_TOXIC or 0)
	if toxic > 0 then ply:AddToxity(toxic) end

	if rotten then
		ply:AddTempStat("nausea", ROT_NAUSEA)
	end

	ply.eatdelay = CurTime() + EAT_GAP

	local uses = ent.Getuses and tonumber(ent:Getuses()) or 0

	if uses > 1 then
		ent:Setuses(uses - 1)
		ent.weight = (uses - 1) * (tonumber(food.weight) or 0) + (tonumber(food.conwht) or 0)
	else
		ent:Remove()
	end

	hook.Run("DarkRP.PlayerAte", ply, class, food, ent, rotten)
end

function DarkRP.EatFood(ply, ent, instant)
	if not IsValid(ply) or not ply:IsPlayer() or not IsValid(ent) or ent:GetClass() ~= "spawned_food" then return false end
	if eating[ply] or (DarkRP.IsUsingJunk and DarkRP.IsUsingJunk(ply)) then return false end

	local food, class = foodOf(ent)
	if not food then return false end

	local reason = blocked(ply, ent)

	if reason then
		return false
	end

	if not ply:CanConsume() then return false end

	local delay = tonumber(food.delay) or 0

	if instant or delay <= 0 then
		portion(ply, ent, food, class)
		return true
	end

	local model, material = ent:GetModel(), ent:GetMaterial()
	local snd = DarkRP.FoodSounds[food.sound]

	eating[ply] = {ent = ent, food = food, class = class, finish = CurTime() + delay, sound = snd, model = model, material = material}
	ent.InUse = ply

	net.Start("DrawProgressBar")
		net.WriteFloat(delay)
	net.Send(ply)

	if snd then ply:EmitSound(snd, SOUND_LEVEL) end

	DarkRP.UIEffect(nil, "ShowModelR", {ply:UserID(), delay, model, material})

	return true
end

function DarkRP.StopEating(ply)
	stop(ply)
end

function DarkRP.IsEating(ply)
	return eating[ply] ~= nil
end

timer.Create("DarkRP.Eating", EAT_CHECK, 0, function()
	local CT = CurTime()

	for ply, e in pairs(eating) do
		if not IsValid(ply) then
			stop(ply)
		elseif not IsValid(e.ent) or blocked(ply, e.ent) then
			stop(ply)
		elseif e.finish <= CT then
			stop(ply, true)
			portion(ply, e.ent, e.food, e.class)
		end
	end
end)

-- [E] с едой в руках: смотрит в сторону, а не на неё
hook.Add("KeyPress", "DarkRP.Eating", function(ply, key)
	if key ~= IN_USE or eating[ply] then return end

	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) or wep:GetClass() ~= "keys" then return end

	local held = wep.EntHolding
	if not IsValid(held) or held:GetClass() ~= "spawned_food" then return end

	-- смотрит на дверь, NPC, игрока - [E] для них
	local tr = ply:GetEyeTrace()
	local target = tr.Entity

	if IsValid(target) and target ~= held and tr.HitPos:DistToSqr(ply:EyePos()) < EAT_RANGE * EAT_RANGE then return end

	DarkRP.EatFood(ply, held)
end)

local function cancel(ply)
	stop(ply)
end

hook.Add("PlayerDeath", "DarkRP.Eating", cancel)
hook.Add("PlayerSilentDeath", "DarkRP.Eating", cancel)
hook.Add("PlayerSpawn", "DarkRP.Eating", cancel)
hook.Add("PlayerDisconnected", "DarkRP.Eating", cancel)
hook.Add("MCR.CharacterReset", "DarkRP.Eating", cancel)
