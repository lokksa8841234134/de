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
	Экран кассы (кассовый аппарат): ставит и удаляет касса или кран
	(McINV.AttachScreen, modules/inventory/sv_registers.lua), E - меню кассы
	или крана (McINV.UseRegister)
---------------------------------------------------------------------------]]
function ENT:Initialize()
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetUseType(SIMPLE_USE)

	local phys = self:GetPhysicsObject()

	if IsValid(phys) then
		phys:EnableMotion(false)
	end
end

function ENT:Use(ply)
	if not IsValid(ply) or not ply:IsPlayer() or not ply:IsFreeman() then return end
	if DarkRP.UseDelay(ply, 1) then return end

	McINV.UseRegister(self:Getbase_ent(), ply, true)
end
