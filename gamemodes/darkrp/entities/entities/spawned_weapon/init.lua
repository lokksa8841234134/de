--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

util.AddNetworkString("att_data_spwaned_weapon")

local DEFAULT_MODEL = "models/weapons/w_pistol.mdl"
local REQUESTS_PER_SEC = 20

-- модель, обвесы и патроны ставит тот, кто кладёт оружие на землю (DropDRPWeapon, McINV.SpawnItem)
function ENT:Initialize()
	local model = self:GetModel()

	if not model or model == "" then
		self:SetModel(DEFAULT_MODEL)
	end

	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetCollisionGroup(COLLISION_GROUP_WEAPON)

	local phys = self:GetPhysicsObject()

	if IsValid(phys) then
		phys:Wake()
	end
end

function ENT:OnTakeDamage(dmg)
	self:TakePhysicsDamage(dmg)
end

--[[---------------------------------------------------------------------------
	Обвесы и настоящая модель (cl_init.lua спрашивает через секунду после появления)
	ответ: Entity, Table обвесы, Bool есть remodel, [String remodel]
---------------------------------------------------------------------------]]
net.Receive("att_data_spwaned_weapon", function(_, ply)
	if not IsValid(ply) then return end

	-- клиент спрашивает про каждое оружие, которое появилось рядом; чаще - спам
	local CT = CurTime()

	if not ply.McINVAttTime or ply.McINVAttTime <= CT then
		ply.McINVAttTime = CT + 1
		ply.McINVAttCount = 0
	end

	ply.McINVAttCount = ply.McINVAttCount + 1
	if ply.McINVAttCount > REQUESTS_PER_SEC then return end

	local ent = net.ReadEntity()
	if not IsValid(ent) or ent:GetClass() ~= "spawned_weapon" then return end

	local atts = istable(ent.att_saved) and ent.att_saved or nil
	local remodel = isstring(ent.remodel) and ent.remodel or nil
	if not atts and not remodel then return end

	net.Start("att_data_spwaned_weapon")
		net.WriteEntity(ent)
		net.WriteTable(atts or {})
		net.WriteBool(remodel ~= nil)

		if remodel then
			net.WriteString(remodel)
		end
	net.Send(ply)
end)
