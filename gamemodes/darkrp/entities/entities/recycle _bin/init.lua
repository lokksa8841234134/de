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
	Мусорка - сервер

	Контейнер, как ящик (static_storage): E - открыть, класть и брать
	может любой, вместимость - Space (кг). Не станция: в посылку не
	пакуется и не двигается, ставит администратор.

	Переработка. У автора о мусорках только NPC (Лил Уэйн): «Компания,
	которая собирает и перерабатывает мусор, имеет с такими как мы тесные
	связи. Потому никто не сообщает о какой-нибудь пропаже, и в
	контейнерах можно хранить всё, что душе угодно. Например, наркотики».
	Поэтому предметы из DarkRP.NonDelete (config.lua: таблетки, наркотики,
	телефоны, маски и шляпы, хлам junk_*, детали parts_* и т.д.; "pills*" -
	все классы, которые так начинаются) лежат сколько угодно, остальное
	увозят: предмет пропадает через RECYCLE_TIME секунд после того, как
	мусорка его увидела (проверка раз в RECYCLE_CHECK секунд). Вынули и
	положили снова - отсчёт заново.

	Сдают наркотики не здесь, а в мусорки с мышкой на карте (точки
	GM.Config.DumpCO, modules/inventory/sv_init.lua).
---------------------------------------------------------------------------]]

local DEFAULT_MODEL = "models/props_junk/TrashDumpster01a.mdl"
local SPACE = 100 -- кг
local NAME = "Мусорка" -- ENT.PrintName автора
local RECYCLE_CHECK = 30 -- секунд между проверками
local RECYCLE_TIME = 600 -- секунд: столько лежит то, что увозят

local TYPES = {INV_WEAPON, INV_ENTITY, INV_AMMO, INV_FOOD, INV_JUNK}

-- DarkRP.NonDelete: точные классы и начала классов ("pills*")
local exact, prefixes

local function keep(class)
	if not isstring(class) then return false end

	if not exact then
		exact, prefixes = {}, {}

		for key, on in pairs(DarkRP.NonDelete or {}) do
			if on and isstring(key) then
				if key:sub(-1) == "*" then
					prefixes[#prefixes + 1] = key:sub(1, -2)
				else
					exact[key] = true
				end
			end
		end
	end

	if exact[class] then return true end

	for _, prefix in ipairs(prefixes) do
		if class:sub(1, #prefix) == prefix then return true end
	end

	return false
end

local function kept(item)
	return keep(item.class) or (istable(item.dt) and keep(item.dt.eclass))
end

function ENT:Initialize()
	local model = self:GetModel()

	if not model or model == "" then
		self:SetModel(DEFAULT_MODEL)
	end

	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetUseType(SIMPLE_USE)

	local phys = self:GetPhysicsObject()

	if IsValid(phys) then
		phys:EnableMotion(false)
	end

	if self:GetSpace() <= 0 then self:SetSpace(SPACE) end
	if self:GetStorageName() == "" then self:SetStorageName(NAME) end

	self.inv = self.inv or McINV.NewInventory()
	self.RecycleSeen = setmetatable({}, {__mode = "k"})
end

function ENT:Use(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if DarkRP.UseDelay(self, 1) then return end

	McINV.Loot(self, ply, false)
end

function ENT:Recycle()
	if not istable(self.inv) then return end

	local CT = CurTime()
	local seen = self.RecycleSeen

	for _, type in ipairs(TYPES) do
		local list = self.inv[type]

		for id = istable(list) and table.maxn(list) or 0, 1, -1 do
			local item = list[id]

			if istable(item) and not kept(item) then
				seen[item] = seen[item] or CT

				if CT - seen[item] >= RECYCLE_TIME then
					self:RemoveItem(type, id)
				end
			end
		end
	end
end

function ENT:Think()
	self:Recycle()
	self:NextThink(CurTime() + RECYCLE_CHECK)

	return true
end
