--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]

--[[---------------------------------------------------------------------------
	Документы, ранг и номер телефона - сервер кнопок меню F4 (msd_ui,
	msd/ui/msdf4menu.lua, разделы «Документы», «Профессия», «Другое»)

	show_pass passport   - «Показать документ» → «Паспорт»
	show_pass inv <k>    - документ из карманов (предмет doc с docid, k - его
	                       номер в McINV.inv.junk клиента = ply.inv.junk сервера)
	show_pass mrs        - удостоверение MRS (есть группа MRS)
	  Документ видит игрок, на которого смотрит показывающий (не дальше
	  SHOW_RANGE, как /givemoney): эффекты клиента автора (client/util.lua)
	  showpass {UserID} - DarkRP.OpenPassport, opendoc {docid} -
	  DarkRP.LoadDock, showpdid {UserID} - DarkRP.OpenPDid. Игрокам рядом -
	  жест передачи anim_giveitem {UserID} (shared/animations.lua).
	show_rank            - «Скрыть свой ранг» / «Показать свой ранг»:
	                       переменная showrank (true - ранг скрыт, client/hud.lua)
	/givenumber          - «Передать свой номер игроку»: номер персонажа
	                       (McPhone.NumberChar) в контакты тому, на кого смотрит
	                       (McPhone.AddContacts → McPhone.Comtact, у него -
	                       уведомление автора о новом контакте)

	Показывает и передаёт только живой, в сознании, без наручников и не в
	машине. Отказ - молча, как у автора.
---------------------------------------------------------------------------]]

local SHOW_RANGE = 100		-- до того, кому показывают, юнитов (как /givemoney)
local ANIM_RANGE = 1000		-- жест видят игроки ближе, юнитов
local SHOW_DELAY = 2		-- между показами, с

local function canAct(ply)
	return IsValid(ply) and ply:Alive() and not ply.DarkRPUnInitialized
		and not ply:getDarkRPVar("unconscious") and ply:IsUnrestrained() and not ply:InVehicle()
end

-- игрок, на которого смотрит ply
local function facing(ply)
	local tr = util.TraceLine({
		start = ply:EyePos(),
		endpos = ply:EyePos() + ply:GetAimVector() * SHOW_RANGE,
		filter = ply
	})

	local target = tr.Entity

	if not IsValid(target) or not target:IsPlayer() or target == ply or not target:Alive() or target.DarkRPUnInitialized then
		return nil
	end

	return target
end

local function giveGesture(ply)
	local list, pos = {}, ply:GetPos()

	for _, v in ipairs(player.GetHumans()) do
		if v:GetPos():DistToSqr(pos) <= ANIM_RANGE * ANIM_RANGE then
			list[#list + 1] = v
		end
	end

	DarkRP.UIEffect(list, "anim_giveitem", {ply:UserID()})
end

local function mrsGroup(ply)
	return MRS and MRS.GetNWdata and MRS.GetNWdata(ply, "Group") or false
end

-- документ из карманов: предмет класса doc с данными документа
local function invDocument(ply, key)
	key = tonumber(key)
	if not key or key ~= math.floor(key) then return nil end

	local junk = ply.inv and ply.inv[INV_JUNK]
	local item = istable(junk) and junk[key]

	if not istable(item) or item.class ~= "doc" or not istable(item.docid) then return nil end

	return item
end

--[[---------------------------------------------------------------------------
	show_pass
---------------------------------------------------------------------------]]
concommand.Add("show_pass", function(ply, _, args)
	if not canAct(ply) or DarkRP.NetDelay(ply, SHOW_DELAY) then return end

	local kind = tostring(args[1] or "")
	local effect, data, what

	if kind == "passport" then
		effect, data, what = "showpass", {ply:UserID()}, "паспорт"
	elseif kind == "inv" then
		local item = invDocument(ply, args[2])
		if not item then return end

		effect, data, what = "opendoc", {item.docid}, tostring(item.name or "документ")
	elseif kind == "mrs" then
		local group = mrsGroup(ply)
		if not group then return end

		effect, data, what = "showpdid", {ply:UserID()}, "удостоверение " .. tostring(group)
	else
		return
	end

	local target = facing(ply)
	if not target then return end

	DarkRP.UIEffect(target, effect, data)
	giveGesture(ply)

	DarkRP.log("other", ply, target, "показал документ: " .. what)
end)

--[[---------------------------------------------------------------------------
	show_rank: кнопка в меню есть только у игрока с группой MRS
---------------------------------------------------------------------------]]
concommand.Add("show_rank", function(ply)
	if not IsValid(ply) or ply.DarkRPUnInitialized or DarkRP.NetDelay(ply, 1) then return end
	if not mrsGroup(ply) then return end

	ply:SetDarkRPVar("showrank", not ply:getDarkRPVar("showrank") or nil)
end)

-- новый персонаж - ранг снова виден
hook.Add("MCR.CharacterSelected", "DarkRP.ShowRank", function(ply)
	if ply:getDarkRPVar("showrank") then ply:SetDarkRPVar("showrank", nil) end
end)

--[[---------------------------------------------------------------------------
	/givenumber
---------------------------------------------------------------------------]]
DarkRP.defineChatCommand("givenumber", function(ply)
	if not canAct(ply) or DarkRP.NetDelay(ply, SHOW_DELAY) then return "" end
	if not McPhone or not McPhone.NumberChar or not McPhone.AddContacts then return "" end
	if ply:getDarkRPVar("character") == nil then return "" end

	local target = facing(ply)
	if not target or target:getDarkRPVar("character") == nil then return "" end

	local number = tostring(McPhone.NumberChar(ply))

	McPhone.AddContacts(number, ply:Nick(), target)
	giveGesture(ply)

	DarkRP.log("other", ply, target, "передал свой номер телефона " .. number)

	return ""
end)
