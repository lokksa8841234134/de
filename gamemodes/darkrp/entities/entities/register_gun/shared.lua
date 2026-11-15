--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Оружейный шкаф"
ENT.Author = "Mactavish"
ENT.Spawnable = true
ENT.AdminSpawnable = false
ENT.CanPack = true
ENT.AutomaticFrameAdvance = true
ENT.ShowOnHud = true

function ENT:SetupDataTables()
	self:NetworkVar("Entity",0,"owning_ent")
	self:NetworkVar("Entity",1,"screen")
	self:NetworkVar("Float",0,"CustomPrice")
	self:NetworkVar("Float",1,"Space")
	self:NetworkVar("String",0,"StorageName")
end

local canlockets = {
	["register_gun"] = true,
	["static_safe"] = true
}

ENT.SellTypes = {
	[INV_WEAPON] = true,
	[INV_AMMO] = true,
	[INV_FOOD] = nil,
}

hook.Add("canKeysLock", "SafeLock", function(ply, ent)
	if canlockets[ent:GetClass()] and ent:CPPIGetOwner() and ply == ent:CPPIGetOwner() then
		return true
	end
end)

hook.Add("canLockpick", "SafeLock.canLockpick", function(p, e)
	if canlockets[e:GetClass()] and not e.IsUnLocked then return true end
end)

hook.Add("lockpickTime", "SafeLock.lockpickTime", function(p, e)
	if canlockets[e:GetClass()] then return 98 end
end)

hook.Add("onLockpickCompleted", "SafeLock.onLockpickCompleted", function(p, b, e)
	if CLIENT then return end
	if not b then return end
	if not canlockets[e:GetClass()] then return end
	e:UnLock()
	e.IsUnLocked = true
end)