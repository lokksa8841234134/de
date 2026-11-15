--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()

SWEP.Base = "mwb_glock17"
SWEP.PrintName = "Glock 17"
SWEP.Category = "Modern Warfare"
SWEP.SubCategory = "Police"
SWEP.NoUserAttachs = true
SWEP.IconOverride = "entities/mwb_glock17.png"

SWEP.Customization = {
	{"att_ammo", "att_vm_pi_golf17_mag", "att_vm_pi_golf17_mag_xmags", "att_vm_pi_golf17_mag_xmagslrg"},
	{"att_vm_pi_golf17_slide", "none2", "att_vm_pi_golf17_slide_light"},
	{"att_laser", "att_vm_laser01_pstl", "att_vm_laser03_pstl"},
	{"att_vm_pi_golf17def"},
	{"att_miscellaneous", "att_reargrip_golf"},
	{"att_muzzle", "att_vm_silencer04_pstl"},
}