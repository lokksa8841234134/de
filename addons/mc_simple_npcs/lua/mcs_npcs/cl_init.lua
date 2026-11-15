--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
--  _______               __          _______  __                   __          _______  ______  ______        
-- |   |   |.---.-..----.|  |.-----. |     __||__|.--------..-----.|  |.-----. |    |  ||   __ \|      |.-----.
-- |       ||  _  ||  __| |_||__ --| |__     ||  ||        ||  _  ||  ||  -__| |       ||    __/|   ---||__ --|
-- |__|_|__||___._||____|    |_____| |_______||__||__|__|__||   __||__||_____| |__|____||___|   |______||_____|
--                                                          |__|                                               
--//////////////////////////////////////////////////////////////////////////////////////////////////////////////
--/////////////////////// Warning! Edit this only if you know what are you doing ///////////////////////////////
--//////////////////////////////////////////////////////////////////////////////////////////////////////////////

function MCS.Blur(panel, inn, density, alpha, w, h)
	MSD.BlurPanel(panel, (3 / inn) * density, w, h, alpha)
end

function MCS.Frame(x, y, w, h, lw, color, otcolor)
	surface.SetDrawColor(color)
	surface.DrawOutlinedRect(x, y, w, h)
	surface.SetDrawColor(otcolor)

	if lw then
		surface.DrawLine(x, y, x + lw, y)
		surface.DrawLine(w + x - 1, y, w + x - lw - 1, y)
		surface.DrawLine(x, y + h - 1, x + lw, y + h - 1)
		surface.DrawLine(w + x - 1, y + h - 1, w + x - lw - 1, y + h - 1)
		surface.DrawLine(x, y, x, y + lw)
		surface.DrawLine(w + x - 1, y, w + x - 1, y + lw)
		surface.DrawLine(x, y, x, y + lw)
		surface.DrawLine(w + x - 1, y + h - 1, w + x - 1, y + h - lw - 1)
		surface.DrawLine(x, y + h - 1, x, y + h - lw - 1)
	end
end

function MCS.GetBoneOrientation(ent, bone, pos, ang, scale)

	if !pos or !ang then return end

	if !bone then return pos, ang end

	local m = ent:GetBoneMatrix(bone)

	if (m) then
		pos, ang = m:GetTranslation(), m:GetAngles()
	end

	return pos, ang
end