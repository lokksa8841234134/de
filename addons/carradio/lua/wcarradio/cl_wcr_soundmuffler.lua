--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
local wcr_mufflesounds = CreateConVar("wyozicr_mufflesounds", "1", FCVAR_ARCHIVE)

hook.Remove("Think", "WCR_SoundMuffler", function()
	-- VCMod exists, shouldn't use our own implementation
	local lveh = LocalPlayer():GetVehicle()

	local muffled = wyozicr.SoundMuffled

	-- Check if vehicle is valid and CarEntity is valid (ie. CarRadio UI is drawn for this vehicle)
	local shouldbemuffled = IsValid(lveh) and IsValid(lveh:WCR_GetCarEntity()) and wcr_mufflesounds:GetBool()

	if muffled ~= shouldbemuffled then
		LocalPlayer():SetDSP(shouldbemuffled and 31 or 0, false)
		wyozicr.SoundMuffled = shouldbemuffled
	end
end)
