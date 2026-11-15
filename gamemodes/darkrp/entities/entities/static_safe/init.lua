--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- открывает только владелец (McINV.CanAccess), открытый ключами или отмычкой - любой
ENT.McINVOwnerOnly = true

--[[---------------------------------------------------------------------------
	Сейф (станция): ставится оружием установки из посылки, Inventory.Pack - обратно в посылку
	содержимое - self.inv, вместимость (кг) - Space
---------------------------------------------------------------------------]]
function ENT:Initialize()
	local model = self:GetModel()

	if not model or model == "" then
		self:SetModel("models/anthon/safebox.mdl")
	end

	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetUseType(SIMPLE_USE)

	local phys = self:GetPhysicsObject()

	if IsValid(phys) then
		phys:Wake()
	end

	if self:GetSpace() <= 0 then self:SetSpace(4) end
	if self:GetStorageName() == "" then self:SetStorageName("Сейф") end

	self.inv = self.inv or McINV.NewInventory()
end

function ENT:Use(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if DarkRP.UseDelay(self, 1) then return end

	if not McINV.CanAccess(ply, self) then
		return
	end

	if McINV.Loot(self, ply, false) then
		self:EmitSound("doors/door_latch3.wav")
	end
end

--[[---------------------------------------------------------------------------
	Замок: ключи владельца (doorsystem/sv_doors.lua, keysLock и keysUnLock)
	и отмычка (onLockpickCompleted в register_gun/shared.lua). Открытый сейф
	(IsUnLocked) открывается любому (McINV.CanAccess), запертый - снова только
	владельцу, у остальных содержимое закрывается
---------------------------------------------------------------------------]]
function ENT:Lock()
	self.IsUnLocked = nil
	McINV.CloseViewers(self)
end

function ENT:UnLock()
	self.IsUnLocked = true
end
