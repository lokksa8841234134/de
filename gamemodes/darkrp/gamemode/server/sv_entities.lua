--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	Предметы: покупка (DarkRP.PlayerBuyItem), хлам и патроны из спавн-меню,
	выброс оружия (DropDRPWeapon), уборка оружия в инвентарь (DropHeldWeapon),
	оружие как предмет инвентаря (WeaponItemData)
---------------------------------------------------------------------------]]
local pmeta = FindMetaTable("Player")
local DEFAULT_WMODEL = "models/weapons/w_pistol.mdl"

util.AddNetworkString("DarkRP.PlayerBuyItem")

-- категории, которые клиент может покупать (DarkRP[ctype][class])
local buyTypes = {
	Food = true,
	Weapons = true,
	Entities = true,
	Junk = true,
	Ammo = true,
	Stations = true,
}

-- Клиент: String ctype, String class, UInt7 count, Bool bank
net.Receive("DarkRP.PlayerBuyItem", function(_, ply)
	if not IsValid(ply) or ply.DarkRPUnInitialized then return end
	if DarkRP.NetDelay(ply, 0.5) then return end

	local ctype = net.ReadString()
	local class = net.ReadString()
	local count = math.Clamp(net.ReadUInt(7), 1, 100)
	local bank = net.ReadBool()

	if not buyTypes[ctype] or not istable(DarkRP[ctype]) or not DarkRP[ctype][class] then return end
	if not bank and not ply:Alive() then return end

	DarkRP.PlayerBuyItem(ply, ctype, class, count, bank)
end)

--[[---------------------------------------------------------------------------
	Хлам и патроны (SpawnFunction спавнлистов junk/attachments)
---------------------------------------------------------------------------]]
local function setupItem(ent, data, class)
	ent:SetModel(data.model or "models/props_junk/cardboard_box004a.mdl")
	ent:PhysicsInit(SOLID_VPHYSICS)
	ent:SetMoveType(MOVETYPE_VPHYSICS)

	local phys = ent:GetPhysicsObject()
	if IsValid(phys) then phys:Wake() end

	if data.material then
		ent:SetMaterial(data.material)
	end

	if data.submat then
		for k, v in pairs(data.submat) do
			ent:SetSubMaterial(k, v)
		end
	end

	if data.bgr then
		for k, v in pairs(data.bgr) do
			ent:SetBodygroup(k, v)
		end
	end

	ent.weight = data.weight
	ent.name = data.name

	if data.btime then
		ent.mt = os.time() + data.btime
	end

	ent:Seteclass(class)
end

local function createItem(entClass, class, data, pos, ang)
	local ent = ents.Create(entClass)
	if not IsValid(ent) then return end

	ent:SetPos(pos)

	if ang then
		ent:SetAngles(ang)
	end

	ent:Spawn()
	setupItem(ent, data, class)

	return ent
end

function DarkRP.CreateJunk(class, pos, ang)
	local data = DarkRP.Junk and DarkRP.Junk[class]
	if not data or not pos then return end

	local ent = createItem("spawned_junk", class, data, pos, ang)
	if not ent then return end

	if data.uses then
		ent:Setuses(data.uses)
		ent.weight = data.uses * (data.weight or 1) + (data.conwht or 0)
	end

	return ent
end

function DarkRP.CreateAmmo(class, pos, ang)
	local data = DarkRP.Ammo and DarkRP.Ammo[class]
	if not data or not pos then return end

	local ent = createItem("spawned_ammo", class, data, pos, ang)
	if not ent then return end

	local ammo = data.ammo or 0
	ent:SetAmmo(ammo)

	if data.bul then
		ent.weight = (data.weight or 1) + math.Round(ammo * data.bul, 2)
	end

	return ent
end

--[[---------------------------------------------------------------------------
	Оружие
---------------------------------------------------------------------------]]
-- обвесы mg_base: {{Slot = слот, m_Index = класс обвеса}}
-- ствол только что выдан из инвентаря или рецептом: обвесы att_saved ставит LoadSpawnPreset
-- через 0.2 секунды в руках (shared.lua), до этого сохраняются они - иначе пропал бы УСМ «Замены УСМ»
local function savedAttachments(wep)
	if not isfunction(wep.GetAllAttachmentsInUse) then return nil end
	if istable(wep.att_saved) then return table.Copy(wep.att_saved) end

	local inUse = wep:GetAllAttachmentsInUse()
	if not istable(inUse) then return nil end

	local saved = {}

	for slot, att in pairs(inUse) do
		if istable(att) and att.ClassName then
			saved[#saved + 1] = {Slot = slot, m_Index = att.ClassName}
		end
	end

	return #saved > 0 and saved or nil
end

local function weaponModel(wep, class)
	local data = DarkRP.Weapons and DarkRP.Weapons[class]
	local model = data and data.model or wep.WorldModel

	if not isstring(model) or model == "" then
		model = wep:GetModel()
	end

	if not isstring(model) or model == "" or not util.IsValidModel(model) then
		return DEFAULT_WMODEL
	end

	-- модели без нормальной физики: физика от замены, клиент рисует оригинал (remodel)
	local fix = GAMEMODE.Config.wmfix and GAMEMODE.Config.wmfix[model]

	if fix and util.IsValidModel(fix) then
		return fix, model
	end

	return model
end

-- Выбросить оружие на землю (spawned_weapon), патроны в запасе остаются у игрока
function pmeta:DropDRPWeapon(wep)
	if not IsValid(wep) or wep:GetOwner() ~= self then return end

	local class = wep:GetClass()
	local model, remodel = weaponModel(wep, class)
	local aim = self:GetAimVector()

	local tr = util.TraceLine({
		start = self:EyePos(),
		endpos = self:EyePos() + aim * 40,
		filter = self
	})

	local ent = ents.Create("spawned_weapon")
	if not IsValid(ent) then return end

	wep.Droping = true

	ent:SetPos(tr.HitPos - aim * 10)
	ent:SetAngles(Angle(0, self:EyeAngles().y, 0))
	ent:SetModel(model)
	ent:Seteclass(class)

	ent.clip1 = wep:Clip1()
	ent.clip2 = wep:Clip2()
	ent.att_saved = savedAttachments(wep)
	ent.gunstate = wep.gunstate
	ent.remodel = remodel

	ent:Spawn()
	ent:Activate()

	if not IsValid(ent:GetPhysicsObject()) then
		ent:PhysicsInit(SOLID_VPHYSICS)
		ent:SetMoveType(MOVETYPE_VPHYSICS)
		ent:SetSolid(SOLID_VPHYSICS)
	end

	local phys = ent:GetPhysicsObject()
	if IsValid(phys) then phys:Wake() end

	DarkRP.CopyGunDate(wep, ent)

	if ent.CPPISetOwner then
		ent:CPPISetOwner(self)
	end

	hook.Call("onDarkRPWeaponDropped", nil, self, ent, wep)

	self:StripWeapon(class)
	DarkRP.log("other", self, nil, "выбросил оружие " .. class, nil, nil, ent)

	return ent
end

-- Оружие как предмет инвентаря: запись каталога + патроны в магазине, обвесы, состояние, номер
-- (уборка в карманы, изъятие при обыске - police/sv_search.lua)
function DarkRP.WeaponItemData(wep)
	local data = table.Copy(DarkRP.Weapons and DarkRP.Weapons[wep:GetClass()] or {})
	data.clip1 = wep:Clip1()
	data.clip2 = wep:Clip2()
	data.att_saved = savedAttachments(wep)
	data.gunstate = wep.gunstate or 1
	DarkRP.CopyGunDate(wep, data)

	return data
end

-- Убрать оружие из рук в инвентарь; false - нет инвентаря или места
function DarkRP.DropHeldWeapon(ply, wep)
	if not IsValid(ply) or not IsValid(wep) or wep:GetOwner() ~= ply then return false end
	if not McINV or not isfunction(McINV.AddCustomItem) or not isfunction(ply.HaveSpace) then return false end

	local class = wep:GetClass()
	if not ply:HaveSpace(McINV.GetWeight(nil, INV_WEAPON, class)) then return false end

	if not McINV.AddCustomItem(ply, "Weapons", class, DarkRP.WeaponItemData(wep)) then return false end

	wep.Droping = true
	ply:StripWeapon(class)

	return true
end
