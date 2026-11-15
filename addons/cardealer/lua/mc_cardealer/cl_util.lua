--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
-- ╔══╗───╔╗╔══╗───────────╔╗──--
-- ║═╦╩╦╦╗║║║╔╗║╔═╦╦╦═╦╦═╦═╣╚╗─--
-- ║╔╣╬║╔╝║╚╣╠╣║║╬║╔╣╬╠╣╩╣═╣╔╣─--
-- ╚╝╚═╩╝─╚═╩╝╚╝║╔╩╝╚╦╝╠═╩═╩═╝─--
-- ─────────────╚╝───╚═╝───────--
-- ───── By Mactavish ─────────--
local ply = LocalPlayer()
local ScrW, ScrH = ScrW, ScrH
local NewFont = surface.CreateFont

NewFont("McCD.Sub1", {
	font = "mr_NeonAbsoluteSansG",
	extended = true,
	size = 62,
	antialias = true,
	weight = 800
})


function McCD.Blur(panel, inn, density, alpha, w, h)
	MSD.BlurPanel(panel, (3 / inn) * density, w, h, alpha)
end

function McCD.Underglow(ent, cl)
	if (not ent.neondata) then
		local center = ent:OBBCenter()
		local mins = ent:OBBMins()
		local maxs = ent:OBBMaxs()

		local s = mins.x > mins.y

		ent.neondata = {
			Vector(center.x, center.y, mins.z + 15),
			Vector(s and center.x or Lerp(0.5, mins.x, center.x), s and Lerp(0.5, mins.y, center.y) or center.y, mins.z + 15),
			Vector(s and center.x or Lerp(0.5, maxs.x, center.x), s and Lerp(0.5, maxs.y, center.y) or center.y, mins.z + 15),
		}

		ent.ndl = {}
	end

	for i, v in ipairs(ent.neondata) do
		if IsValid(ent.ndl[i]) then
			ent.ndl[i].pos = ent:LocalToWorld(v)
			ent.ndl[i].DieTime = CurTime() + 0.3
			continue
		end
		ent.ndl[i] = DynamicLight(512 + ent:EntIndex() + i)
		ent.ndl[i].pos = ent:LocalToWorld(v)
		ent.ndl[i].nomodel = true
		ent.ndl[i].brightness = 7
		ent.ndl[i].Decay = 1000
		ent.ndl[i].Size = 100
		ent.ndl[i].DieTime = CurTime()  + 0.3
		ent.ndl[i].r, ent.ndl[i].g, ent.ndl[i].b = cl.r, cl.g, cl.b
	end
end

function McCD.PlaySound(snd)
	if McCD.Sound then
		McCD.Sound:Stop()
	end

	McCD.Sound = nil
	McCD.Sound = CreateSound(ply, snd)
	McCD.Sound:PlayEx(0.3, 100)
end