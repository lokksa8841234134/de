--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	NPC квестов MQS (mqs_npc) - сервер

	Ставит MQS.SpawnNPCs (sv_tasks.lua) по MQS.Config.NPC.list: npcData
	(модель, скин, бодигруппы, анимация) задаётся до Spawn, UID и имя - в
	сетевых полях. По E открывает игроку меню квестов (npc_menu.lua);
	квест из меню стартует через net MQS.StartTask со ссылкой на этого NPC.
	Бессмертен.
---------------------------------------------------------------------------]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local DEF_MODEL = "models/humans/group01/male_02.mdl"
local USE_DELAY = 1				-- меню не чаще, с

function ENT:Initialize()
	local npc = istable(self.npcData) and self.npcData or {}
	local mdl = isstring(npc.model) and util.IsValidModel(npc.model) and npc.model or DEF_MODEL

	self:SetModel(mdl)
	self:SetHullType(HULL_HUMAN)
	self:SetHullSizeNormal()
	self:SetNPCState(NPC_STATE_SCRIPT)
	self:SetSolid(SOLID_BBOX)
	self:CapabilitiesAdd(bit.bor(CAP_ANIMATEDFACE, CAP_TURN_HEAD))
	self:SetUseType(SIMPLE_USE)

	if tonumber(npc.skin) then self:SetSkin(tonumber(npc.skin)) end

	if istable(npc.bgr) then
		for k, v in pairs(npc.bgr) do
			if tonumber(k) and tonumber(v) then self:SetBodygroup(tonumber(k), tonumber(v)) end
		end
	end

	self.seq = -1

	if isstring(npc.sequence) and npc.sequence ~= "" then
		self.seq = self:LookupSequence(npc.sequence) or -1
	end

	if self.seq >= 0 then self:ResetSequence(self.seq) end
end

-- своя анимация (сидит, курит): ИИ движка её сбивает - возвращаем
function ENT:Think()
	if self.seq and self.seq >= 0 and self:GetSequence() ~= self.seq then
		self:ResetSequence(self.seq)
	end

	self:NextThink(CurTime() + 1)

	return true
end

function ENT:Use(ply)
	if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
	if (ply.MQSNPCUse or 0) > CurTime() then return end

	ply.MQSNPCUse = CurTime() + USE_DELAY

	net.Start("MQS.OpenNPCMenu")
	net.WriteEntity(self)
	net.Send(ply)
end

function ENT:OnTakeDamage()
	return 0
end
