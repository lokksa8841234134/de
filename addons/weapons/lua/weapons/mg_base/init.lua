--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--[[---------------------------------------------------------------------------
	База оружия mg_base - сервер (шаг 12)

	Без этого файла сервер грузил только shared.lua: клиенту не уходили
	cl_init.lua (настройки mgbase_*, приём анимаций) и меню обвесов
	modules/client/cl_new_customizemenu.lua (в нём нет AddCSLuaFile),
	сообщения mgbase_* не были зарегистрированы, запросы клиента никто
	не принимал, а перезарядка магазином другого типа (UseMags) давала
	ошибку Lua: shared-код автора шлёт с сервера mgbase_customize_att_cl
	(sh_reload_behaviour.lua - обвес магазина у клиентов).

	Режим обвесов - net mgbase_customize (C->S, без данных; консольная
	команда mgbase_customize, у клиента автора - по C, если на неё нет
	бинда). Открыть - если включено mgbase_sv_customization и оружие
	в руках может (SWEP:CanCustomize автора: не перезаряжается, не
	достаётся, не целится, не бежит), закрыть - всегда. Смотреть обвесы
	может любой.

	Обвес - net mgbase_customize_att (C->S): Int(8) слот, Int(8) номер
	обвеса в SWEP.Customization[слот], Entity оружие. Только оружие в
	руках в режиме обвесов. Проверки - SWEP:AllowedToAttach автора
	(sh_customization.lua): с названием категории, как в меню клиента,
	затем со слотом - покупка автора: предмет обвеса уходит из карманов,
	снятый возвращается, у расходника (UseJunk) тратится заряд. Ставит
	оружейник (команда 9) у стола оружейника; складной приклад и другие
	пары DarkRP.InterCAT - кто угодно и где угодно; донатный обвес -
	владелец доната; право sAdmin weapon_upgrade - всё и бесплатно.
	Нажатие на стоящий обвес снимает его: в слот встаёт первый
	(стандартный) обвес слота, по тем же правилам. Отказ - молча.
---------------------------------------------------------------------------]]
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("weapons/mg_base/modules/client/cl_new_customizemenu.lua")

include("shared.lua")

util.AddNetworkString("mgbase_anim")
util.AddNetworkString("mgbase_tpanim")
util.AddNetworkString("mgbase_customize")
util.AddNetworkString("mgbase_customize_att")
util.AddNetworkString("mgbase_customize_att_cl")

local TOGGLE_DELAY = 0.25 -- секунд между открытием и закрытием режима обвесов
local ATTACH_DELAY = 0.2 -- секунд между обвесами

local customization = GetConVar("mgbase_sv_customization")

-- оружие mg_base в руках живого игрока
local function heldWeapon(ply, weapon)
	return IsValid(ply) and ply:Alive() and IsValid(weapon) and weapon.IsMWwp == true and weapon:GetOwner() == ply and ply:GetActiveWeapon() == weapon
end

net.Receive("mgbase_customize", function(_, ply)
	if DarkRP.NetDelay(ply, TOGGLE_DELAY) then return end

	local weapon = ply:GetActiveWeapon()
	if not heldWeapon(ply, weapon) then return end

	if weapon:GetIsCustomizing() then
		weapon:SetIsCustomizing(false)
		return
	end

	if not customization:GetBool() or not weapon:CanCustomize() then return end

	weapon:SetIsCustomizing(true)
end)

net.Receive("mgbase_customize_att", function(_, ply)
	local slot = net.ReadInt(8)
	local index = net.ReadInt(8)
	local weapon = net.ReadEntity()

	if DarkRP.NetDelay(ply, ATTACH_DELAY) then return end
	if not customization:GetBool() or not heldWeapon(ply, weapon) or not weapon:GetIsCustomizing() then return end

	local list = istable(weapon.Customization) and weapon.Customization[slot]
	local att = istable(list) and list[index]
	if not isstring(att) or not istable(MW_ATTS[att]) then return end

	-- меню клиента такие обвесы не показывает
	if DarkRP.RestrictedAT and DarkRP.RestrictedAT[att] then return end

	local current = weapon:GetAttachmentInUseForSlot(slot)
	if not istable(current) then return end

	local category = MW_ATTS[att].Category

	if current.ClassName == att then
		-- снять: стоящий обвес нажимается, только если его разрешает меню клиента
		local default = list[1]
		if default == att or not isstring(default) or not istable(MW_ATTS[default]) then return end
		if not weapon:IsAttachmentAllowed(MW_ATTS[att]) or not weapon:AllowedToAttach(index, att, category, false) then return end

		att, index = default, 1
	elseif not weapon:IsAttachmentAllowed(MW_ATTS[att]) then
		return
	end

	-- проверки меню клиента (по категории), затем покупка автора (по слоту)
	if not weapon:AllowedToAttach(index, att, category, false) then return end
	if not weapon:AllowedToAttach(index, att, slot, true) then return end

	weapon:CreateAttachmentEntity(att)
end)
