--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Квестовый предмет MQS (mqs_ent) - сервер

	Ставит событие "Spawn quest entity" (sh_init.lua): поля model, task,
	task_ply, pointer, enablephys, pickeffect, loopsnd, task_id задаются до
	Spawn, updateobj и HP (Distractible) - после. Поднять предмет может
	только игрок квеста: E или удержание E (UseHold секунд); предмет с HP
	можно ещё и разбить. Засчитывает подбор sv_tasks.lua
	(MQS.QuestEntPicked): сбор предметов или переход к задаче updateobj.
	Без физики (аркадный вид) предмет висит на месте, его видит только
	свой игрок, остальные проходят сквозь него.
---------------------------------------------------------------------------]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local DEF_MODEL = "models/props_junk/cardboard_box001a.mdl"
local RELEASE = 0.25			-- E не держат дольше - удержание начинается заново, с
local PUNCH = 0.3				-- встряска предмета от удара (клиент рисует по PA), с
local PICK_SOUND = "items/itempickup.wav"

function ENT:Initialize()
	self.sounds = self.sounds or {}

	local mdl = isstring(self.model) and self.model ~= "" and self.model or DEF_MODEL
	if not util.IsValidModel(mdl) then mdl = DEF_MODEL end

	self:SetModel(mdl)
	self:SetCModel(mdl)

	if IsValid(self.task_ply) then self:SetTPly(self.task_ply) end

	self:SetShowPointer(self.pointer and true or false)
	self:SetEnablePhys(self.enablephys and true or false)

	self:PhysicsInit(SOLID_VPHYSICS)

	local phys = self:GetPhysicsObject()

	-- модель без физической модели: хотя бы коробка, чтобы E попадало
	if not IsValid(phys) then
		self:SetSolid(SOLID_BBOX)
	end

	if self.enablephys and not IsValid(self:GetParent()) then
		self:SetMoveType(MOVETYPE_VPHYSICS)

		if IsValid(phys) then phys:Wake() end
	else
		self:SetMoveType(MOVETYPE_NONE)

		if IsValid(phys) then phys:EnableMotion(false) end

		if not self.enablephys then
			self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
			self:DrawShadow(false)
		end
	end

	-- Use приходит каждый тик, пока держат E: нужно для удержания
	self:SetUseType(CONTINUOUS_USE)

	if isstring(self.loopsnd) and self.loopsnd ~= "" then
		self:CreateLoopingSound("loop", self.loopsnd, 70, true)
	end
end

function ENT:CanPick(ply)
	if self.picked or not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return false end
	if ply ~= self:GetTPly() then return false end

	return not MQS.CanPickQuestEnt or MQS.CanPickQuestEnt(ply, self)
end

function ENT:Use(ply)
	if not self:CanPick(ply) then return end

	local hold = self:GetUseHold()

	if hold <= 0 then return self:Pick(ply) end

	local now = CurTime()

	-- начал держать: клиенту - чей прогресс рисовать
	if self.picker ~= ply or not self.lastUse or self.lastUse + RELEASE < now then
		self.picker = ply
		self.pickStart = now

		net.Start("MQS.FixPickUP")
		net.WriteEntity(self)
		net.Send(ply)
	end

	self.lastUse = now

	local p = math.Clamp((now - self.pickStart) / hold, 0, 1)
	self:SetPickProgress(p)

	if p >= 1 then self:Pick(ply) end
end

function ENT:Pick(ply, broken)
	if self.picked then return end

	if MQS.QuestEntPicked and not MQS.QuestEntPicked(ply, self, broken) then return end

	self.picked = true

	if self.pickeffect then
		self:EmitSound(PICK_SOUND, 60)
	end

	self:Remove()
end

function ENT:Think()
	local now = CurTime()

	-- отпустил E - удержание сначала
	if self.picker and (not self.lastUse or self.lastUse + RELEASE < now) then
		self.picker = nil
		self:SetPickProgress(0)
	end

	if self:GetPA() and (self.punchEnd or 0) < now then
		self:SetPA(false)
	end

	self:NextThink(now + 0.1)

	return true
end

function ENT:OnTakeDamage(dmg)
	if self.picked or not self:GetDistractible() then return end

	self:SetPA(true)
	self.punchEnd = CurTime() + PUNCH

	local hp = self:GetHP() - dmg:GetDamage()
	self:SetHP(math.max(hp, 0))

	-- разбитый предмет засчитан игроку квеста
	if hp <= 0 then self:Pick(self:GetTPly(), true) end
end

function ENT:OnRemove()
	for id in pairs(self.sounds or {}) do
		self:StopLoopSounds(id)
	end
end
