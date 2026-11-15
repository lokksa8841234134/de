--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

--[[---------------------------------------------------------------------------
	Грядка (станция) - сервер

	Ставится оружием установки из посылки (как ящик), Inventory.Pack -
	обратно в посылку: растение и вода при этом пропадают. Сажать,
	поливать, собирать и выкапывать может любой - хозяин грядки не
	проверяется, как у станций крафта.

	Семена и вода - предметом (spawned_junk), который коснулся грядки:
	уронить, бросить или поднести ключами.
	seed_weed, seed_coca, seed_opium - только в пустую грядку (Seeds = ""):
	пакет семян исчезает, растение растёт с нуля. В занятую - ничего.
	water_can - одна порция канистры (uses) за касание: +WATER_PER_USE
	воды, не больше WATER_MAX; последняя порция - канистра исчезает, иначе
	uses и вес убавляются (как порции еды). Полная грядка воду не берёт.
	Один предмет срабатывает не чаще раза в TOUCH_DELAY секунд.

	Рост - раз в THINK секунд, числа в shared.lua автора:
	вода испаряется на единицу раз в IdleEvapInterval секунд - в пустой
	грядке до IdleWaterFloor, с растением до нуля;
	Stage растёт на единицу за growTime секунд, пока вода в норме семян
	(SeedOptimalHydration), вне нормы - в SlowGrowMultiplier раз
	медленнее, без воды - стоит;
	вне нормы (и без воды) BadHydrationDelay секунд подряд или созревшее
	GrownDecayDelay секунд - растение гибнет: DyingStage 1, через каждые
	DyingStageInterval секунд следующая стадия до MaxDyingStage ("Мёртво"
	у клиента). Гибнущее не растёт, не спасается водой и не собирается -
	только выкопать.
	Свет (LightLevel) и подкормку (Boost) сервер не меняет: клиент их не
	показывает, по вашему ответу к 11.3 они не нужны.

	E - меню грядки (UI-эффект atm_open, ENT:OpenMenu в cl_init.lua).
	Действия из меню - net PlanterAction (C->S): Entity грядка, UInt(2):
	0 "Собрать урожай" - если ENT:CanHarvest, HarvestTime секунд;
	1 "Выкопать растение" - если что-то посажено, RemoveTime секунд.
	У игрока полоса прогресса (DrawProgressBar). Отошёл от грядки дальше
	USE_RANGE, сел в машину, потерял свободу (ply:IsFreeman), умер, вышел,
	сменил персонажа, грядку убрали или растение уже не то - действие
	прерывается (RemovePropgressBar). Одно действие на грядку и на
	игрока; пока оно идёт, растение не меняется, грядку не упаковать
	(McINVBusy).
	Урожай - HARVEST_COUNT предметов из PRODUCTS (листья конопли, листья
	коки, цветы мака) на землю над грядкой и HARVEST_XP очков опыта
	"planter" собравшему (с тату a5 - больше, ply:JobXPAdd). Грядка
	пустеет, вода остаётся. Выкопать - грядка пустеет без урожая.
---------------------------------------------------------------------------]]

util.AddNetworkString("PlanterAction")

local DEFAULT_MODEL = "models/props_foliage/urban_pot_xlsquare01.mdl" -- модель станции в DarkRP.Stations
local THINK = 1 -- секунд между шагами роста
local MAX_STEP = 5 -- секунд: шаг роста не длиннее (сервер подвис)
local WATER_MAX = 100 -- клиент рисует воду из 100
local WATER_PER_USE = 20 -- воды за порцию канистры
local WATER_CLASS = "water_can"
local TOUCH_DELAY = 1 -- секунд между срабатываниями одного предмета
local USE_RANGE = 200 -- как у меню клиента: дальше оно закрывается
local ACTION_CHECK = 0.1 -- секунд: проверка, что игрок может продолжать
local HARVEST_COUNT = 1
local HARVEST_XP = 500 -- ваш ответ к шагу 12: «давай 500» (было 100; лопата с 500 очков - после первого урожая)
local HARVEST_HEIGHT = 40 -- урожай появляется над центром грядки
local SEED_SOUND = "player/footsteps/grass1.wav"
local WATER_SOUND = "ambient/water/water_splash1.wav"

-- семена -> урожай (каталог spawnlist/junk.lua)
local PRODUCTS = {
	seed_weed = "green_weed",
	seed_coca = "green_coca",
	seed_opium = "green_opium",
}

local HARVEST, DIG = 0, 1

-- [ply] = {ent, kind, finish, seeds}
local actions = {}

ENT.PlanterServer = true

function ENT:Initialize()
	local model = self:GetModel()

	if not model or model == "" then
		self:SetModel(DEFAULT_MODEL)
	end

	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetUseType(SIMPLE_USE)
	self:SetTrigger(true)

	local phys = self:GetPhysicsObject()

	if IsValid(phys) then
		phys:Wake()
	end

	local CT = CurTime()

	self.LastGrow = CT
	self.EvapAt = CT + self.IdleEvapInterval
end

-- пустая грядка; вода остаётся
function ENT:ResetPlant()
	self:SetSeeds("")
	self:SetStage(0)
	self:SetDyingStage(0)

	self.BadSince = nil
	self.GrownSince = nil
	self.DyingNext = nil
end

--[[---------------------------------------------------------------------------
	Семена и вода
---------------------------------------------------------------------------]]
function ENT:TakeItem(ent)
	if ent.McINVTaken or ent:IsOnFire() then return end
	if ent.InUse == true or (isentity(ent.InUse) and IsValid(ent.InUse)) then return end

	local class = ent.Geteclass and ent:Geteclass()

	if PRODUCTS[class] then
		if self:GetSeeds() ~= "" or self.PlanterUser then return end

		self:ResetPlant()
		self:SetSeeds(class)

		ent.McINVTaken = true
		ent:Remove()

		self:EmitSound(SEED_SOUND)
	elseif class == WATER_CLASS then
		local water = self:GetWaterLevel()
		if water >= WATER_MAX then return end

		self:SetWaterLevel(math.min(water + WATER_PER_USE, WATER_MAX))

		local uses = ent.Getuses and tonumber(ent:Getuses()) or 0

		if uses > 1 then
			local data = DarkRP.Junk[class] or {}

			ent:Setuses(uses - 1)
			ent.weight = (uses - 1) * (tonumber(data.weight) or 0) + (tonumber(data.conwht) or 0)
		else
			ent.McINVTaken = true
			ent:Remove()
		end

		self:EmitSound(WATER_SOUND)
	end
end

-- удалять предмет прямо в обработчике касания и столкновения нельзя
function ENT:QueueItem(ent)
	if not IsValid(ent) or ent:GetClass() ~= "spawned_junk" or ent.McINVTaken then return end

	local CT = CurTime()
	if ent.PlanterTouch and ent.PlanterTouch > CT then return end

	ent.PlanterTouch = CT + TOUCH_DELAY

	local planter = self

	timer.Simple(0, function()
		if IsValid(planter) and IsValid(ent) then
			planter:TakeItem(ent)
		end
	end)
end

function ENT:StartTouch(ent)
	self:QueueItem(ent)
end

function ENT:PhysicsCollide(data)
	self:QueueItem(data.HitEntity)
end

--[[---------------------------------------------------------------------------
	Рост
---------------------------------------------------------------------------]]
function ENT:Evaporate(CT)
	if CT < (self.EvapAt or 0) then return end

	self.EvapAt = CT + self.IdleEvapInterval

	local floor = self:GetSeeds() == "" and self.IdleWaterFloor or 0
	local water = self:GetWaterLevel()

	if water > floor then
		self:SetWaterLevel(math.max(water - 1, floor))
	end
end

function ENT:StartDying(CT)
	self:SetDyingStage(1)
	self.DyingNext = CT + self.DyingStageInterval
end

function ENT:Grow(CT, step)
	if self:GetSeeds() == "" then return end

	local dying = self:GetDyingStage()

	if dying > 0 then
		self.DyingNext = self.DyingNext or CT + self.DyingStageInterval

		if dying < self.MaxDyingStage and CT >= self.DyingNext then
			self:SetDyingStage(dying + 1)
			self.DyingNext = CT + self.DyingStageInterval
		end

		return
	end

	if self:IsFullyGrown() then
		self.GrownSince = self.GrownSince or CT

		if CT - self.GrownSince >= self.GrownDecayDelay then
			self:StartDying(CT)
		end

		return
	end

	local water = self:GetWaterLevel()
	local good = water > 0 and self:IsHydrationOptimal()

	if good then
		self.BadSince = nil
	else
		self.BadSince = self.BadSince or CT

		if CT - self.BadSince >= self.BadHydrationDelay then
			self:StartDying(CT)
			return
		end
	end

	if water <= 0 then return end

	local time = self.growTime * (good and 1 or self.SlowGrowMultiplier)
	local stage = math.min(self:GetStage() + step / time, self.GrowStageMax)

	self:SetStage(stage)

	if stage >= self.GrowStageMax then
		self.GrownSince = CT
		self.BadSince = nil
	end
end

function ENT:Think()
	local CT = CurTime()
	local step = math.Clamp(CT - (self.LastGrow or CT), 0, MAX_STEP)

	self.LastGrow = CT
	self:Evaporate(CT)

	-- пока собирают или выкапывают, растение не меняется
	if not self.PlanterUser then
		self:Grow(CT, step)
	end

	self:NextThink(CT + THINK)

	return true
end

--[[---------------------------------------------------------------------------
	Меню: собрать урожай, выкопать
---------------------------------------------------------------------------]]
function ENT:Use(ply)
	if not IsValid(ply) or not ply:IsPlayer() or not ply:IsFreeman() then return end
	if DarkRP.UseDelay(ply, 1) then return end

	DarkRP.UIEffect(ply, "atm_open", {idx = self:EntIndex()})
end

local function canAct(ply, ent)
	return IsValid(ply) and IsValid(ent) and ply:IsFreeman() and not ply:InVehicle() and ent:GetPos():DistToSqr(ply:GetPos()) <= USE_RANGE * USE_RANGE
end

local function stopAction(ply, finished)
	local a = actions[ply]
	if not a then return end

	actions[ply] = nil

	local ent = a.ent

	if IsValid(ent) and ent.PlanterUser == ply then
		ent.PlanterUser = nil
		ent.McINVBusy = nil
	end

	if not finished and IsValid(ply) then
		net.SendSingleMessage("RemovePropgressBar", ply)
	end
end

local function finishAction(ply, a)
	local ent = a.ent

	if a.kind == HARVEST then
		local class = PRODUCTS[a.seeds]
		local data = class and DarkRP.Junk[class]

		if data then
			local pos, ang = ent:WorldSpaceCenter() + Vector(0, 0, HARVEST_HEIGHT), ent:GetAngles()

			for _ = 1, HARVEST_COUNT do
				local item = McINV.AddCustomItem(nil, INV_JUNK, class, data)

				if item then
					McINV.SpawnItem(INV_JUNK, item, pos, ang)
				end
			end
		end

		ply:JobXPAdd("planter", HARVEST_XP)
	end

	ent:ResetPlant()
end

function ENT:StartAction(ply, kind)
	if actions[ply] or self.PlanterUser or not canAct(ply, self) then return end

	local seeds = self:GetSeeds()
	if seeds == "" then return end

	local time

	if kind == HARVEST then
		if not self:CanHarvest() then return end
		time = self.HarvestTime
	elseif kind == DIG then
		time = self.RemoveTime
	else
		return
	end

	actions[ply] = {ent = self, kind = kind, finish = CurTime() + time, seeds = seeds}
	self.PlanterUser = ply
	self.McINVBusy = true

	net.Start("DrawProgressBar")
		net.WriteFloat(time)
	net.Send(ply)
end

function ENT:OnRemove()
	local ply = self.PlanterUser

	if ply then
		stopAction(ply)
	end
end

net.Receive("PlanterAction", function(_, ply)
	if not IsValid(ply) or DarkRP.NetDelay(ply, 0.5) then return end

	local ent = net.ReadEntity()
	local kind = net.ReadUInt(2)

	if not IsValid(ent) or not ent.PlanterServer then return end

	ent:StartAction(ply, kind)
end)

timer.Create("DarkRP.Planter", ACTION_CHECK, 0, function()
	local CT = CurTime()

	for ply, a in pairs(actions) do
		local ent = a.ent

		if not canAct(ply, ent) or ent:GetSeeds() ~= a.seeds or (a.kind == HARVEST and not ent:CanHarvest()) then
			stopAction(ply)
		elseif a.finish <= CT then
			stopAction(ply, true)
			finishAction(ply, a)
		end
	end
end)

local function cancel(ply)
	stopAction(ply)
end

hook.Add("PlayerDeath", "DarkRP.Planter", cancel)
hook.Add("PlayerSilentDeath", "DarkRP.Planter", cancel)
hook.Add("PlayerSpawn", "DarkRP.Planter", cancel)
hook.Add("PlayerDisconnected", "DarkRP.Planter", cancel)
hook.Add("MCR.CharacterReset", "DarkRP.Planter", cancel)
