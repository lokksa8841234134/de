--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "WorkStation"
ENT.Author = "Mactavish"
ENT.Spawnable = true
ENT.AdminSpawnable = false
ENT.CanPack = true
ENT.ShowOnHud = true
ENT.BuffMult = 1

ENT.BluePrints = {}
ENT.SameClasses = {
	["whater"] = {
		["whater_carb"] = true,
		["whater_jug"] = true,
	},
}

ENT.SameClassesName = {
	["whater"] = "Вода"
}

function ENT:SetupDataTables()
	self:NetworkVar("Entity",0,"owning_ent")
	self:NetworkVar("Float",0,"Space")
	self:NetworkVar("Float",1,"CraftStart")
	self:NetworkVar("Float",2,"CraftDelay")
	self:NetworkVar("Float",3,"Temp")
	self:NetworkVar("String",0,"StorageName")
	self:NetworkVar("String",1,"CraftingItem")
	self:NetworkVar("Bool",0,"Crafting")
	self:NetworkVar("Bool",1,"StopCraft")
end

function ENT:CanCraft(id, ply)
	if not self.BluePrints[id] then return false end
	if self:GetCrafting() then return false end
	local craft = self.BluePrints[id]

	if craft.price and not ply:canAfford(craft.price) then return false end
	if craft.unlock and sAdmin.mcTime(ply) < craft.unlock then return false end
	if craft.pack and not MQS.GetSData(ply, craft.pack) then return false end

	for _, cp in pairs(craft.componets) do
		local count = self:GetItemCount(cp.type, cp.class, nil, not cp.ignuses, cp.consume, cp.check)
		if count < cp.count then
			if self.SameClasses and self.SameClasses[cp.class] then
				local found = false
				for enc, _ in pairs(self.SameClasses[cp.class]) do
					if self:GetItemCount(cp.type, enc, nil, not cp.ignuses, cp.consume, cp.check) + count >= cp.count then
						found = true
						break
					end
				end
				if found then continue end
			end
			return false
		end
	end

	return true
end