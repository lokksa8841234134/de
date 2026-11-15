--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Наручники и таскание - сервер (общая часть в sh_cuffs.lua)

	Наручники надевает SWEP arrest_stick (предмет INV_JUNK "cuffs"), снимают
	arrest_stick (ПКМ), отмычка и команда sAdmin "cuffs". Все вызывают
	ply:CuffHands(front) - переключатель.

	Переменная HandCuffed: 0 - руки спереди, 1 - за спиной (SetupMove
	"DarkRP.Cuffs" в sh_init.lua замедляет вдвое), nil - без наручников.
	Поля игрока: HandCuffed и Restrained (их проверяют arrest_stick, отмычка,
	animations.lua, sAdmin), restainBy - кто надел (ставит arrest_stick).

	Таскание: [E] по игроку в наручниках - вести за собой, [E] ещё раз -
	отпустить (подсказки в client/hud.lua). Вести может любой свободный игрок.
	Ведущему - переменная "Player.Drag" (скорость: хук HC_Move в
	shared/commands.lua), ведомому - поле DraggedBy (движение: SetupMove
	"DarkRP.Cuffs") и NW2 "DarkRP.DraggedBy" для клиента.
---------------------------------------------------------------------------]]

util.AddNetworkString("Police.ForceWp")

local plyMeta = FindMetaTable("Player")

local DRAG_START_DIST = 30000 -- квадрат: как подсказка "Игрок в наручниках" в client/hud.lua
local DRAG_BREAK_DIST = 1000 * 1000 -- квадрат: дальше таскание обрывается (телепорт, отстал)
local DRAG_USE_DIST = 100 * 100 -- квадрат: [E] по двери, NPC или машине рядом не отпускает
local DRAG_COOLDOWN = 0.5
local CHECK_INTERVAL = 0.5

local HAND_L, HAND_R = "ValveBiped.Bip01_L_Hand", "ValveBiped.Bip01_R_Hand"
local RAG_CUFFS_LENGTH = 8

--[[---------------------------------------------------------------------------
	Руки закованного: ключи в состоянии 1 (без кулаков), то, что держал,
	падает. Клиенту - Police.ForceWp (приёмник в sh_init.lua).
	Для других модулей - DarkRP.ForceKeys(ply) (арест, sv_arrest.lua)
---------------------------------------------------------------------------]]
local function forceKeys(ply)
	local keys = ply:GetWeapon("keys")

	if not IsValid(keys) then
		keys = ply:Give("keys")
		if not IsValid(keys) then return end
	end

	if ply:GetActiveWeapon() ~= keys then
		if keys.SetState then keys:SetState(1) end

		ply:SelectWeapon("keys")

		net.Start("Police.ForceWp")
			net.WriteEntity(keys)
		net.Send(ply)
	elseif keys.ChangeState and keys:GetState() ~= 1 then
		keys:ChangeState(1)
	end

	if keys.Reset then keys:Reset() end
end

DarkRP.ForceKeys = forceKeys

--[[---------------------------------------------------------------------------
	Таскание
---------------------------------------------------------------------------]]
local function canDrag(ply)
	return ply:IsFreeman() and not ply:InVehicle()
end

local function canBeDragged(target)
	return target.HandCuffed and target:Alive() and not target:InVehicle() and not target:getDarkRPVar("unconscious")
end

local function startDrag(dragger, target)
	dragger.Dragging = target
	dragger:SetDarkRPVar("Player.Drag", true)

	target.DraggedBy = dragger
	target:SetNW2Entity("DarkRP.DraggedBy", dragger)
end

-- Отпустить того, кого ведёт dragger. Возвращает ведомого
local function stopDrag(dragger)
	local target = dragger.Dragging

	dragger.Dragging = nil
	dragger:SetDarkRPVar("Player.Drag", nil)

	if IsValid(target) and target.DraggedBy == dragger then
		target.DraggedBy = nil
		target:SetNW2Entity("DarkRP.DraggedBy", NULL)
	end

	return target
end

--[[---------------------------------------------------------------------------
	ply:ReleaseDrag() - разорвать таскание с участием игрока:
	и если ведёт он, и если ведут его
---------------------------------------------------------------------------]]
function plyMeta:ReleaseDrag()
	if self.Dragging ~= nil then
		stopDrag(self)
	end

	local dragger = self.DraggedBy
	if dragger == nil then return end

	if IsValid(dragger) and dragger.Dragging == self then
		stopDrag(dragger)
	else
		self.DraggedBy = nil
		self:SetNW2Entity("DarkRP.DraggedBy", NULL)
	end
end

--[[---------------------------------------------------------------------------
	ply:CuffHands(front) - надеть или снять наручники (переключатель).
	front = true - руки спереди (HandCuffed 0), иначе за спиной (1).
	Возвращает true, если наручники теперь надеты
---------------------------------------------------------------------------]]
function plyMeta:CuffHands(front)
	if self.HandCuffed then
		self.HandCuffed = nil
		self.Restrained = nil
		self.restainBy = nil
		self:SetDarkRPVar("HandCuffed", nil)
		self:ReleaseDrag()

		return false
	end

	if not self:Alive() then return false end

	self.HandCuffed = true
	self.Restrained = true
	self:SetDarkRPVar("HandCuffed", front and 0 or 1)
	self:ReleaseDrag()

	if self:InVehicle() then
		self:ExitVehicle()
	end

	forceKeys(self)

	return true
end

--[[---------------------------------------------------------------------------
	DarkRP.applyCuffsToRag(rag) - наручники на рэгдолле игрока без сознания
	(arrest_stick). Метка rag.cuffed и невидимая связка кистей длиной с цепь.
	Рэгдоллы и SincRagdoll - модуль health (шаг 8)
---------------------------------------------------------------------------]]
function DarkRP.applyCuffsToRag(rag)
	if not IsValid(rag) or rag.cuffed then return end

	rag.cuffed = true

	local boneL, boneR = rag:LookupBone(HAND_L), rag:LookupBone(HAND_R)
	if not boneL or not boneR then return end

	local physL, physR = rag:TranslateBoneToPhysBone(boneL), rag:TranslateBoneToPhysBone(boneR)
	if physL < 0 or physR < 0 or physL == physR then return end
	if not IsValid(rag:GetPhysicsObjectNum(physL)) or not IsValid(rag:GetPhysicsObjectNum(physR)) then return end

	rag.CuffsRope = constraint.Rope(rag, rag, physL, physR, vector_origin, vector_origin, RAG_CUFFS_LENGTH, 0, 0, 0, "", false)
end

--[[---------------------------------------------------------------------------
	[E]: вести закованного / отпустить.
	Пока ведёт, [E] по двери, NPC или машине рядом работает как обычно
	(в больнице полицейский говорит с NPC, не отпуская задержанного)
---------------------------------------------------------------------------]]
hook.Add("KeyPress", "DarkRP.CuffsDrag", function(ply, key)
	if key ~= IN_USE then return end

	local CT = CurTime()
	if (ply.NextDragUse or 0) > CT then return end

	local tr = ply:GetEyeTrace()
	local ent = tr.Entity

	if ply.Dragging ~= nil then
		if IsValid(ent) and not ent:IsPlayer() and tr.HitPos:DistToSqr(tr.StartPos) <= DRAG_USE_DIST then return end

		ply.NextDragUse = CT + DRAG_COOLDOWN

		local target = stopDrag(ply)
		DarkRP.log("police", ply, IsValid(target) and target or nil, "отпустил задержанного")
		return
	end

	if not IsValid(ent) or not ent:IsPlayer() or ent == ply then return end
	if ent:GetPos():DistToSqr(ply:GetPos()) >= DRAG_START_DIST then return end
	if not canDrag(ply) or not canBeDragged(ent) then return end
	if IsValid(ent.DraggedBy) and ent.DraggedBy.Dragging == ent then return end

	ply.NextDragUse = CT + DRAG_COOLDOWN

	startDrag(ply, ent)
	DarkRP.log("police", ply, ent, "повёл за собой")
end)

--[[---------------------------------------------------------------------------
	Проверка раз в CHECK_INTERVAL: таскание рвётся, если кто-то умер, сел
	в машину, потерял сознание, ведущий скован или арестован, наручники сняты
	или игроки далеко друг от друга. Закованный, у которого оружие не убралось
	при надевании наручников, снова получает в руки ключи
---------------------------------------------------------------------------]]
local function dragBroken(dragger, target)
	if not IsValid(target) or target.DraggedBy ~= dragger then return true end
	if not canDrag(dragger) or not canBeDragged(target) then return true end

	return dragger:GetPos():DistToSqr(target:GetPos()) > DRAG_BREAK_DIST
end

timer.Create("DarkRP.CuffsDrag", CHECK_INTERVAL, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		if ply.Dragging ~= nil and dragBroken(ply, ply.Dragging) then
			stopDrag(ply)
		end

		if ply.HandCuffed and ply:Alive() and not ply:InVehicle() then
			local wep = ply:GetActiveWeapon()

			if IsValid(wep) and wep:GetClass() ~= "keys" then
				forceKeys(ply)
			end
		end
	end
end)

--[[---------------------------------------------------------------------------
	Хуки
---------------------------------------------------------------------------]]
-- В наручниках нельзя открывать двери, садиться в машины и пользоваться вещами
hook.Add("PlayerUse", "DarkRP.Cuffs", function(ply)
	if ply.HandCuffed then return false end
end)

-- Смерть и смена персонажа снимают наручники (предмет пропадает)
local function clearCuffs(ply)
	ply:ReleaseDrag()

	if ply.HandCuffed then
		ply:CuffHands()
	end
end

hook.Add("PlayerDeath", "DarkRP.Cuffs", clearCuffs)
hook.Add("PlayerSilentDeath", "DarkRP.Cuffs", clearCuffs)
hook.Add("MCR.CharacterReset", "DarkRP.Cuffs", clearCuffs)

-- HandCuffed у вышедшего не трогаем: по нему инвентарь бросает его карманы
hook.Add("PlayerDisconnected", "DarkRP.Cuffs", function(ply)
	ply:ReleaseDrag()
end)
