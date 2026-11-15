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
	Запакованная станция (ящик, сейф, верстак): eclass - класс станции, DeployModel - её модель
	E - оружие установки (deployment); после установки оно удаляет посылку (self.shipment)
---------------------------------------------------------------------------]]
function ENT:Initialize()
	local model = self:GetModel()

	if not model or model == "" then
		self:SetModel("models/props_junk/cardboard_box002a.mdl")
	end

	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetUseType(SIMPLE_USE)

	self.shipment = true

	local phys = self:GetPhysicsObject()

	if IsValid(phys) then
		phys:Wake()
	end
end

function ENT:Use(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if DarkRP.UseDelay(self, 1) then return end
	if self.McINVTaken or self.Draged then return end

	if isentity(self.InUse) and IsValid(self.InUse) then
		return
	end

	if not ply:IsUnrestrained() or ply:getDarkRPVar("character") == nil or ply:InVehicle() then return end

	-- обычный ящик (без станции внутри) не устанавливается
	local class = self:Geteclass()
	local station = DarkRP.Stations[class]
	if not station then return end

	local model = self:GetDeployModel()
	if model == "" then model = station.model end
	if not isstring(model) or model == "" then return end

	if ply:HasWeapon("deployment") then
		return
	end

	local wep = ply:Give("deployment")

	if not IsValid(wep) or wep:GetOwner() ~= ply then
		if IsValid(wep) and not IsValid(wep:GetOwner()) then wep:Remove() end
		return
	end

	wep:SetBaseEntity(self)
	wep:SetDeployModel(model)
	wep:SetDeployEnt(class)
	ply:SelectWeapon("deployment")

	-- пока идёт установка, посылку не подобрать и не сдвинуть
	self.InUse = wep

	local phys = self:GetPhysicsObject()

	if IsValid(phys) then
		phys:EnableMotion(false)
	end
end

-- оружие установки пропало без Holster (смерть, выход) - посылку снова можно трогать
function ENT:Think()
	if isentity(self.InUse) and not IsValid(self.InUse) then
		self.InUse = nil

		local phys = self:GetPhysicsObject()

		if IsValid(phys) then
			phys:EnableMotion(true)
		end
	end

	self:NextThink(CurTime() + 1)

	return true
end
