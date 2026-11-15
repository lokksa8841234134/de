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
	Станция крафта (верстак, плита, лаборатория...) - сервер

	Ставится оружием установки из посылки (как ящик), E - меню станции
	(McINV.Loot с флагом craft: рецепты, содержимое станции, карманы).
	Наследники (workstation_alc, coffe, cook, drugs, guns, pharm, stove,
	table) задают только рецепты ENT.BluePrints - вся работа здесь.

	"Начать" (McINV.StartCraft): ENT:CanCraft (shared.lua) + профессия
	(TeamLimit, кроме nolimit) + рецепт открыт за очки опыта (xp).
	Сразу списываются деньги (price) и компоненты - так же, как их
	считает entityMeta:GetItemCount: целые предметы, порции (uses) или
	доли полного предмета (consume), сначала из початых. Взаимозаменяемые
	классы - SameClasses. Один предмет не засчитывается двум компонентам
	(CanCraft считает каждый компонент отдельно - тогда крафт не начнётся).
	Не тратятся: инструменты (dont_use) и предметы с change/failchange -
	они меняются в конце крафта (change, при провале - failchange). Пока идёт крафт,
	содержимое станции не взять и не положить (McINVBusy), станцию не
	упаковать - у клиента поверх меню полоса крафта.
	Успех: продукты (products, extras - поля предмета) в станцию, endfunc,
	очки опыта крафтеру (XPTable) - по таблицам опыта ниже.
	Оружие с флагом register у рецепта (стол оружейника) получает
	серийный номер: 8 случайных цифр, первая не ноль, зарегистрирован
	на крафтера (passid - DarkRP.CharacterID, как у экрана регистрации;
	берётся при старте - номер будет, даже если крафтер уже вышел).
	Номера выдаёт и хранит реестр (police/sv_gunreg.lua): спил стирает
	номер и в реестре, разобранный ствол (компонент рецепта) там отмечается.

	Вес: weight_store у компонента запоминает его вес, у продукта
	weight_apply - вес = запомненный, weight_mult - вес из каталога,
	умноженный на (запомненный / вес компонента по каталогу).
	BuffMult станции (домашняя плитка 0.1) умножает сытость и энергичность
	(hunger, stamina - секунды временных состояний) у приготовленной еды.

	Температура (mintemp/failtemp, лаборатория): старт с mintemp, нагрев
	HEAT градуса в секунду, "Охладить 30°" (McINV.ToggleCraft) - минус COOL.
	failtemp и выше - провал с перегревом; ниже mintemp - реакция стоит
	(StopCraft, время крафта не идёт); на COLD_FAIL ниже mintemp - провал
	без перегрева. Провал: failfunc(self, перегрев) рецепта (звук, огонь,
	ENT:Explode - облако Drugs.Explode), failproducts в станцию.

	skillchecker - проверка навыка (DarkRP.SC, server/sv_skillcheck.lua)
	у крафтера на всё время рецепта, окно раунда SC_WINDOW секунд, как у
	отмычки. Рецепт, который меняет серийный номер компонента (change.register,
	рабочий стол: "Убрать серийный номер с оружия"), идёт SERIAL_TIME
	секунд, а с татуировкой a5 "Острый ум" окно на секунду больше.
	Прошёл - change; промах, смерть, ушёл от станции дальше SC_RANGE или
	проверку прервала другая (отмычка) - провал и failchange.

	Сеть (C->S, меню станции должно быть открыто у игрока):
	McINV.StartCraft - String рецепт, Entity станция
	McINV.Upgrade    - String рецепт, Entity станция: открыть рецепт за
	                   очки опыта (xp - число или time * 4), requiredbp -
	                   сначала открыть тот рецепт
	McINV.ToggleCraft - Entity станция: охладить
	S->C: Drugs.Explode - Entity (облако у лабораторного стола);
	McINV.UpdateStorage "craft" - перестроить список рецептов.
	Сетевые переменные энтити приходят со снимком, а net - раньше него:
	обновление меню отправляется через SYNC_DELAY, иначе клиент не увидит
	начало крафта (оверлей крафта в меню переключается каждым обновлением).
---------------------------------------------------------------------------]]

util.AddNetworkString("McINV.StartCraft")
util.AddNetworkString("McINV.Upgrade")
util.AddNetworkString("McINV.ToggleCraft")
util.AddNetworkString("Drugs.Explode")

local SPACE = 30				-- вместимость станции, кг (плите кафе карта ставит 100)
local DEFAULT_MODEL = "models/props_wasteland/controlroom_desk001b.mdl"
local THINK = 0.5
local SYNC_DELAY = 0.3
local HEAT = 0.5				-- градусов в секунду (шкала охлаждения в меню рецепта)
local COOL = 30
local COLD_FAIL = 60
local COOL_DELAY = 1
local SC_RANGE = 200 * 200
local SC_WINDOW = 2				-- окно раунда проверки навыка, как у отмычки
local SERIAL_TIME = 15			-- спил серийного номера: вся мини-игра
local MAX_PRODUCTS = 50
local EPS = 0.0001
local BUFF_FIELDS = {"hunger", "stamina"}

--[[---------------------------------------------------------------------------
	Опыт за крафт: только за успешный, крафтеру, в опыт станции (XPTable).
	Пары {обычно, с татуировкой a5 "Острый ум"}:
	CRAFT_XP[станция][рецепт], иначе CRAFT_XP_CATEGORY[станция][категория],
	иначе время рецепта * XP_PER_SEC станции, с a5 - ещё * XP_A5.
	Лабораторный стол: опыт за каждую стадию, по её доле во времени всей
	цепочки (метамфетамин, 1020 секунд - 500, с a5 - 700). Стадию, которую
	пропустили (купили промежуточный продукт), не оплачивают.
	a5 здесь уже учтён - JobXPAdd получает exact и второй раз не умножает.
---------------------------------------------------------------------------]]
local CRAFT_XP = {
	guns = {
		buckshot = {100, 200},			-- картечь, остальные патроны - категорией
	},
	drugs = {
		craft_meth = {176, 247},		-- метамфетамин: 360 + 360 + 300 секунд, всего 500 (700)
		craft_meth_ice = {177, 247},
		done_meth = {147, 206},
		dry_coca = {206, 288},			-- кокаин: 420 + 300 + 300, всего 500 (700)
		craft_coca = {147, 206},
		done_coca = {147, 206},
		dry_opium = {206, 288},			-- опиум 420 - общая стадия героина и фентанила
		craft_sphingosine = {59, 82},	-- героин: 420 + 120 + 600, всего 560 (780)
		done_heroin = {295, 410},
		fentanyl = {84, 122},			-- фентанил: 420 + 180, всего 290 (410)
		dry_weed = {210, 290},			-- 420, фасуют на рабочем столе
		molotov = {180, 250},			-- 360
	},
}

local CRAFT_XP_CATEGORY = {
	guns = {
		["Патроны"] = {200, 300},
	},
}

-- оружие, обслуживание, разборка, УСМ - как открытие рецепта (время * 4)
local XP_PER_SEC = {guns = 4, drugs = 0.5}
local XP_PER_SEC_DEFAULT = 2	-- плита, дистиллятор, фармацевтический стол
local XP_A5 = 1.5

ENT.WorkStation = true

local function catalog(type, class)
	local data = McINV.GetItem(type, class)

	return istable(data) and data or nil
end

local function safeCall(fn, ...)
	local ok, err = pcall(fn, ...)

	if not ok then
		ErrorNoHalt("[workstation] " .. tostring(err) .. "\n")
	end

	return ok
end

-- значение поля из change: функция от предмета, копия таблицы или как есть
local function applyChange(item, change)
	if not istable(change) then return end

	for key, val in pairs(change) do
		if isfunction(val) then
			local ok, res = pcall(val, item)

			if ok then
				item[key] = res
			else
				ErrorNoHalt("[workstation] " .. tostring(res) .. "\n")
			end
		elseif istable(val) then
			item[key] = table.Copy(val)
		else
			item[key] = val
		end
	end
end

local function round(x)
	return math.Round(x, 3)
end

-- проверка навыка этого крафта ещё идёт (не закончилась и её не сменила другая)
local function scActive(data)
	return data.sc and IsValid(data.ply) and DarkRP.SC and DarkRP.SC.Session(data.ply) == data.sc or false
end

local function hasTattoo(ply, id)
	return IsValid(ply) and MCR and isfunction(MCR.HasTatoo) and MCR.HasTatoo(ply, id) or false
end

local function craftXP(code, id, recipe, ply)
	local a5 = hasTattoo(ply, "a5")
	local pair = CRAFT_XP[code] and CRAFT_XP[code][id] or CRAFT_XP_CATEGORY[code] and CRAFT_XP_CATEGORY[code][recipe.category]

	if pair then return a5 and pair[2] or pair[1] end

	local xp = (tonumber(recipe.time) or 0) * (XP_PER_SEC[code] or XP_PER_SEC_DEFAULT)

	return math.max(math.Round(a5 and xp * XP_A5 or xp), 1)
end

-- рецепт меняет серийный номер компонента
local function removesSerial(recipe)
	for _, cp in ipairs(recipe.componets) do
		if istable(cp) and istable(cp.change) and cp.change.register ~= nil then return true end
	end

	return false
end

--[[---------------------------------------------------------------------------
	Энтити
---------------------------------------------------------------------------]]
function ENT:Initialize()
	local data = DarkRP.Stations[self:GetClass()]
	local model = self:GetModel()

	if not model or model == "" then
		self:SetModel(data and data.model or DEFAULT_MODEL)
	end

	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetUseType(SIMPLE_USE)

	local phys = self:GetPhysicsObject()

	if IsValid(phys) then
		phys:Wake()
	end

	if self:GetSpace() <= 0 then self:SetSpace(SPACE) end
	if self:GetStorageName() == "" then self:SetStorageName(data and data.name or self.PrintName or "Станция") end

	self.inv = self.inv or McINV.NewInventory()
end

function ENT:Use(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if DarkRP.UseDelay(ply, 1) then return end

	McINV.Loot(self, ply, true)
end

-- у кого открыто меню этой станции
local function viewers(ent)
	local list = {}

	for ply in pairs(ent.McINVViewers or {}) do
		if IsValid(ply) and ply.McINVLoot == ent then
			list[#list + 1] = ply
		end
	end

	return list
end

local function sendCraft(ent, targets)
	targets = targets or viewers(ent)
	if #targets == 0 then return end

	net.Start("McINV.UpdateStorage")
		net.WriteEntity(ent)
		net.WriteString("craft")
	net.Send(targets)
end

--[[---------------------------------------------------------------------------
	Компоненты: план списания (ничего не трогает), потом списание
---------------------------------------------------------------------------]]
-- классы компонента: свой, потом взаимозаменяемые (SameClasses; BaseClass -
-- ссылка на таблицу базовой станции, её добавляет наследование энтити)
local function classesOf(ent, cp)
	local list = {cp.class}
	local same = ent.SameClasses and ent.SameClasses[cp.class]

	if istable(same) then
		local extra = {}

		for class in pairs(same) do
			if isstring(class) and class ~= cp.class and class ~= "BaseClass" then extra[#extra + 1] = class end
		end

		table.sort(extra)

		for _, class in ipairs(extra) do
			list[#list + 1] = class
		end
	end

	return list
end

-- предметы класса в станции: сначала початые (меньше порций) - так переливание
-- и рецепты с долями собирают остатки, а полные бутылки остаются
local function candidates(list, class)
	local found = {}

	for i, item in ipairs(list) do
		if item.class == class then
			found[#found + 1] = {item = item, i = i, uses = istable(item.dt) and tonumber(item.dt.uses) or math.huge}
		end
	end

	table.sort(found, function(a, b)
		if a.uses ~= b.uses then return a.uses < b.uses end

		return a.i < b.i
	end)

	for i, v in ipairs(found) do
		found[i] = v.item
	end

	return found
end

-- как считает entityMeta:GetItemCount: "whole" - предмет целиком (1),
-- "share" - доля полного (uses / uses каталога), "uses" - каждая порция (не меньше 1)
local function countMode(type, item, cp)
	if cp.ignuses or not istable(item.dt) or not item.dt.uses then return "whole" end

	local data = catalog(type, item.class)

	if cp.consume and data and data.uses then return "share", data.uses end

	return "uses"
end

-- взятия: {item, type, cp, take = true (целиком) или число порций, keep}
-- keep - предмет с change/failchange: остаётся в станции и меняется в конце.
-- used[item] - что уже взято другим компонентом: true или порций
local function planComponents(ent, recipe)
	local takes, used = {}, {}

	for _, cp in ipairs(recipe.componets) do
		if not istable(cp) or cp.dont_use then continue end

		local list = ent.inv[cp.type]
		if not istable(list) then return nil end

		local need = tonumber(cp.count) or 1
		local keep = cp.change ~= nil or cp.failchange ~= nil

		for _, class in ipairs(classesOf(ent, cp)) do
			if need <= EPS then break end

			for _, item in ipairs(candidates(list, class)) do
				if need <= EPS then break end

				local u = used[item]
				if u == true or keep and u then continue end

				if cp.check then
					local ok, res = pcall(cp.check, item)
					if not ok or not res then continue end
				end

				local mode, full = countMode(cp.type, item, cp)
				local uses = mode ~= "whole" and math.max(tonumber(item.dt.uses) or 0, 0) or 0

				if mode == "whole" or keep then
					if u then continue end

					local units = 1

					if mode == "share" then
						units = uses / full
					elseif mode == "uses" then
						units = math.max(uses, 1)
					end

					if units <= 0 then continue end

					takes[#takes + 1] = {item = item, type = cp.type, cp = cp, take = true, keep = keep}
					used[item] = true
					need = need - units
				elseif uses <= 0 then
					-- пустой предмет с порциями GetItemCount считает за одну порцию
					-- (math.max(uses, 1)), долей полного он не считается
					if u or mode ~= "uses" then continue end

					takes[#takes + 1] = {item = item, type = cp.type, cp = cp, take = true}
					used[item] = true
					need = need - 1
				else
					local left = uses - (u or 0)
					if left <= 0 then continue end

					local want = mode == "share" and math.ceil(need * full - EPS) or math.ceil(need - EPS)
					local take = math.min(left, want)

					takes[#takes + 1] = {item = item, type = cp.type, cp = cp, take = take}
					used[item] = (u or 0) + take
					need = need - (mode == "share" and take / full or take)
				end
			end
		end

		if need > EPS then return nil end
	end

	return takes
end

-- вес взятого: весь предмет (и его вес по каталогу) или порции (вес порции из каталога)
local function takenWeight(t)
	local data = catalog(t.type, t.item.class)

	if t.take == true then
		local base = data and (data.uses and ((tonumber(data.uses) or 0) * (tonumber(data.weight) or 0) + (tonumber(data.conwht) or 0)) or tonumber(data.weight)) or 1

		return tonumber(McINV.GetWeight(t.item, t.type, t.item.class)) or 0, base
	end

	local per = data and tonumber(data.weight) or 0

	return per * t.take, per * t.take
end

local function commitComponents(ent, takes, data)
	local remove = {}

	for _, t in ipairs(takes) do
		local item = t.item

		if t.keep then
			data.reserved[#data.reserved + 1] = t
			continue
		end

		if t.cp.weight_store then
			local w, base = takenWeight(t)
			data.stored = data.stored + w
			data.base = data.base + base
		end

		if t.take == true then
			remove[item] = true

			-- ствол с номером разобран (сломанное оружие на столе оружейника)
			if t.type == INV_WEAPON and istable(item.register) then
				DarkRP.GunDestroy(item.register.id, item.class, item.register.passid)
			end
		else
			local info = catalog(t.type, item.class)
			item.dt.uses = math.max((tonumber(item.dt.uses) or 0) - t.take, 0)

			if item.dt.uses <= 0 then
				remove[item] = true
			elseif info and info.weight then
				item.weight = item.dt.uses * info.weight + (info.conwht or 0)
			end
		end
	end

	for _, list in pairs(ent.inv) do
		for i = #list, 1, -1 do
			if remove[list[i]] then table.remove(list, i) end
		end
	end
end

--[[---------------------------------------------------------------------------
	Продукты
---------------------------------------------------------------------------]]
function ENT:MakeProduct(p, data)
	local info = catalog(p.type, p.class)
	if not info then return nil end

	local item = McINV.AddCustomItem(nil, p.type, p.class, info)
	if not item then return nil end

	for key, val in pairs(istable(p.extras) and p.extras or {}) do
		item[key] = istable(val) and table.Copy(val) or val
	end

	if data.stored > 0 then
		if p.weight_apply then
			item.weight = round(data.stored)
		elseif p.weight_mult then
			local w = tonumber(item.weight) or tonumber(info.weight) or 1
			item.weight = round(w * data.stored / math.max(data.base, EPS))
		end
	end

	if p.type == INV_WEAPON and item.gunstate == nil then
		item.gunstate = 1
	end

	-- новый ствол - на оружейника, пока тот не зарегистрирует его на другого
	if p.type == INV_WEAPON and data.ok and data.recipe.register and item.register == nil and data.passid ~= nil then
		item.register = {id = DarkRP.NewGunSerial(item.class, data.passid), passid = data.passid}
	end

	local mult = tonumber(self.BuffMult) or 1

	if p.type == INV_FOOD and mult ~= 1 then
		for _, key in ipairs(BUFF_FIELDS) do
			local v = tonumber(item[key])
			if v then item[key] = math.Round(v * mult) end
		end
	end

	return item
end

function ENT:GiveProducts(list, data)
	local given = false

	for _, p in ipairs(istable(list) and list or {}) do
		if not istable(p) or not McINV.ttypes[p.type] then continue end

		for _ = 1, math.Clamp(math.floor(tonumber(p.count) or 1), 1, MAX_PRODUCTS) do
			local item = self:MakeProduct(p, data)
			if not item then break end

			-- в станции уже 500 предметов этого типа (лимит инвентаря) - продукт рядом на землю
			if not self:AddItem(p.type, item) then
				McINV.SpawnItem(p.type, item, self:WorldSpaceCenter() + Vector(0, 0, 40), self:GetAngles())
			end

			given = true
		end
	end

	return given
end

--[[---------------------------------------------------------------------------
	Крафт
---------------------------------------------------------------------------]]
-- вернёт true, если крафт начался
function ENT:StartCraft(id, ply)
	if not isstring(id) or id == "" or id == "BaseClass" or #id > 64 then return false end
	if self.CraftData or self:GetCrafting() or self:IsOnFire() then return false end

	local recipe = self.BluePrints and self.BluePrints[id]
	if not istable(recipe) or not istable(recipe.componets) then return false end

	if self.TeamLimit and team.GetName(ply:Team()) ~= self.TeamLimit and not recipe.nolimit then return false end
	if recipe.xp and self.XPTable and not ply:JobXPOpen(self.XPTable, id) then return false end

	self.inv = self.inv or McINV.NewInventory()

	for _, type in ipairs({INV_WEAPON, INV_ENTITY, INV_AMMO, INV_FOOD, INV_JUNK}) do
		if not istable(self.inv[type]) then self.inv[type] = {} end
	end

	if not self:CanCraft(id, ply) then return false end

	local takes = planComponents(self, recipe)
	if not takes then return false end

	local price = tonumber(recipe.price) or 0

	if price > 0 then
		if not ply:canAfford(price) then return false end
		ply:addMoney(-price)
	end

	local data = {
		id = id,
		recipe = recipe,
		ply = ply,
		passid = DarkRP.CharacterID(ply), -- крафтер мог выйти до конца крафта
		reserved = {},
		stored = 0,
		base = 0,
		last = CurTime(),
		temp = recipe.mintemp or recipe.failtemp and (recipe.failtemp - COOL) or nil,
	}

	commitComponents(self, takes, data)

	local time = math.max(tonumber(recipe.time) or 1, 0.1)
	local serial = removesSerial(recipe)

	if serial then time = SERIAL_TIME end

	self.CraftData = data
	self.McINVBusy = true

	self:SetCraftingItem(id)
	self:SetCraftStart(CurTime())
	self:SetCraftDelay(time)
	self:SetStopCraft(false)
	self:SetTemp(data.temp and math.Round(data.temp) or 0)
	self:SetCrafting(true)

	if recipe.skillchecker and DarkRP.SC then
		local window = SC_WINDOW + ((serial and hasTattoo(ply, "a5")) and 1 or 0)

		data.sc = DarkRP.SC.Send(ply, window, time, function()
			if IsValid(self) and self.CraftData == data then self:FinishCraft(true) end
		end, function()
			if IsValid(self) and self.CraftData == data then self:FinishCraft(false) end
		end) or true
	end

	DarkRP.log("other", ply, nil, "начал крафт \"" .. tostring(recipe.name or id) .. "\" (" .. tostring(self:GetStorageName()) .. ")", nil, price > 0 and price or nil, self)

	-- компоненты убраны - меню у смотрящих обновится, когда придёт Crafting
	timer.Simple(SYNC_DELAY, function()
		if IsValid(self) then McINV.ContainerChanged(self) end
	end)

	return true
end

-- ok - успех; overhit - провал от перегрева
function ENT:FinishCraft(ok, overhit)
	local data = self.CraftData
	if not data then return end

	self.CraftData = nil
	self.McINVBusy = nil

	self:SetCrafting(false)
	self:SetStopCraft(false)
	self:SetCraftingItem("")

	if scActive(data) then
		DarkRP.SC.Fail(data.ply, true)
	end

	local recipe = data.recipe
	local ply = data.ply

	-- предметы с change ещё в станции (содержимое было закрыто)
	local inside = {}

	for _, list in pairs(self.inv) do
		for _, item in ipairs(list) do
			inside[item] = true
		end
	end

	if ok then
		for _, r in ipairs(data.reserved) do
			if inside[r.item] then
				local reg = istable(r.item.register) and r.item.register

				applyChange(r.item, r.cp.change)

				-- спил: номера больше нет и в реестре
				if reg and not (istable(r.item.register) and r.item.register.id == reg.id) then
					DarkRP.GunErase(reg.id, r.item.class, reg.passid)
				end
			end
		end

		data.ok = true
		self:GiveProducts(recipe.products, data)

		if isfunction(recipe.endfunc) then safeCall(recipe.endfunc, self) end

		if self.XPTable and IsValid(ply) then
			ply:JobXPAdd(self.XPTable, craftXP(self.XPTable, data.id, recipe, ply), true)
		end
	else
		if isfunction(recipe.failfunc) then safeCall(recipe.failfunc, self, overhit and true or false) end

		for _, r in ipairs(data.reserved) do
			if inside[r.item] and r.cp.failchange then applyChange(r.item, r.cp.failchange) end
		end

		self:GiveProducts(recipe.failproducts, data)
	end

	McINV.ContainerChanged(self)

	timer.Simple(SYNC_DELAY, function()
		if IsValid(self) and not self.CraftData then sendCraft(self) end
	end)
end

function ENT:Cool()
	local data = self.CraftData
	if not data or not data.temp then return false end

	data.temp = data.temp - COOL
	self:SetTemp(math.Round(data.temp))
	self:EmitSound("ambient/levels/canals/toxic_slime_sizzle" .. math.random(1, 4) .. ".wav", 60)

	if data.recipe.mintemp and data.temp <= data.recipe.mintemp - COLD_FAIL then
		self:FinishCraft(false, false)
	end

	return true
end

-- облако над лабораторным столом (клиент: workstation_drugs/cl_init.lua)
function ENT:Explode()
	net.Start("Drugs.Explode")
		net.WriteEntity(self)
	net.SendPVS(self:GetPos())
end

function ENT:CraftThink()
	local data = self.CraftData
	local CT = CurTime()
	local dt = math.max(CT - data.last, 0)
	data.last = CT

	-- проверку навыка заканчивает DarkRP.SC (успех или промах), здесь - всё остальное
	if data.sc then
		local ply = data.ply

		if not scActive(data) or not ply:Alive() or ply:GetPos():DistToSqr(self:GetPos()) > SC_RANGE then
			self:FinishCraft(false)
		end

		return
	end

	local recipe = data.recipe
	local paused = false

	if data.temp then
		data.temp = data.temp + HEAT * dt
		self:SetTemp(math.Round(data.temp))

		if recipe.failtemp and data.temp >= recipe.failtemp then
			self:FinishCraft(false, true)
			return
		end

		paused = recipe.mintemp and data.temp < recipe.mintemp or false
	end

	if paused then
		-- реакция стоит: время крафта не идёт, полоса у клиента замирает
		self:SetCraftStart(self:GetCraftStart() + dt)
	end

	if self:GetStopCraft() ~= paused then self:SetStopCraft(paused) end

	if not paused and CT >= self:GetCraftStart() + self:GetCraftDelay() then
		self:FinishCraft(true)
	end
end

function ENT:Think()
	if self.CraftData then self:CraftThink() end

	self:NextThink(CurTime() + THINK)
	return true
end

function ENT:OnRemove()
	local data = self.CraftData
	self.CraftData = nil

	if data and scActive(data) then
		DarkRP.SC.Fail(data.ply, true)
	end
end

--[[---------------------------------------------------------------------------
	Сеть
---------------------------------------------------------------------------]]
-- станция, меню которой открыто у игрока, и игрок может ею пользоваться
local function stationFor(ply, ent)
	if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() or not ply:IsUnrestrained() then return nil end
	if ply:getDarkRPVar("character") == nil then return nil end
	if not IsValid(ent) or not ent.WorkStation or ply.McINVLoot ~= ent or not istable(ent.inv) then return nil end
	if not McINV.CanAccess(ply, ent) or not McINV.CanLoot(ply, ent) then return nil end

	return ent
end

net.Receive("McINV.StartCraft", function(_, ply)
	if DarkRP.NetDelay(ply, 0.5) then return end

	local id = net.ReadString()
	local ent = stationFor(ply, net.ReadEntity())
	if not ent then return end

	ent:StartCraft(id, ply)
end)

net.Receive("McINV.Upgrade", function(_, ply)
	if DarkRP.NetDelay(ply, 0.5) then return end

	local id = net.ReadString()
	local ent = stationFor(ply, net.ReadEntity())
	if not ent or id == "BaseClass" then return end

	local recipe = ent.BluePrints and ent.BluePrints[id]
	local code = ent.XPTable
	if not istable(recipe) or not recipe.xp or not code then return end
	if ply:JobXPOpen(code, id) then return end
	if ent.TeamLimit and team.GetName(ply:Team()) ~= ent.TeamLimit and not recipe.nolimit then return end

	-- сначала изучить предыдущий рецепт (как подпись в меню)
	local req = recipe.requiredbp and ent.BluePrints[recipe.requiredbp]
	if istable(req) and req.xp and not ply:JobXPOpen(code, recipe.requiredbp) then return end

	local cost = tonumber(recipe.xp) or math.Round((tonumber(recipe.time) or 0) * 4)
	if ply:JobXP(code) < cost then return end

	ply:JobXPAdd(code, -cost)
	ply:JobXPUnlock(code, id)

	-- кнопка "Начать" вместо замка; во время крафта меню закрыто полосой крафта
	if not ent.CraftData then sendCraft(ent, {ply}) end
end)

net.Receive("McINV.ToggleCraft", function(_, ply)
	if DarkRP.NetDelay(ply, COOL_DELAY) then return end

	local ent = stationFor(ply, net.ReadEntity())
	if not ent then return end

	ent:Cool()
end)
