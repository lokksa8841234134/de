--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Компьютер (мэрия, участок) - сервер. Меню открывает клиент по [E]
	(slawer_mayor/client/hooks.lua): модель pd_deskscreen - компьютер
	полиции. Расстановка в участке - slawer_mayor/server/sv_computers.lua
---------------------------------------------------------------------------]]
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

ENT.Model = "models/unioncity2/props_unioncity/pd_deskscreen.mdl"

function ENT:Initialize()
	local model = self:GetModel()

	if not model or model == "" or model == "models/error.mdl" then
		self:SetModel(self.Model)
	end

	-- у модели без физики - коробка по габаритам, чтобы [E] попадал
	if self:PhysicsInit(SOLID_VPHYSICS) then
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
	else
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_BBOX)
	end

	local phys = self:GetPhysicsObject()
	if IsValid(phys) then phys:EnableMotion(false) end
end
