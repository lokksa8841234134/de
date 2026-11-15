--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()

function SWEP:doSuppressorStats()
	self.Primary.Sound = Sound("p27_pi_papa220_sup_plr")

	self.Reverb = {
		RoomScale = 50000,
		Sounds = {
			Outside = {
				Layer = Sound("p27_pi_papa220_fire_sup_atmo_out"),
				Reflection = Sound("Reflection_ARSUP.Outside")
			},
			Inside = {
				Layer = Sound("p27_pi_papa220_fire_sup_atmo_in"),
				Reflection = Sound("Reflection_ARSUP.Inside")
			}
		}
	}

	self.ParticleEffects.MuzzleFlash = "AC_muzzle_pistol_suppressed"
end

SWEP.Customization = {
	{"att_ammo",  "attachment_vm_pi_papa220_mag"},
	{"att_receiver"},
	{"att_trigger_papa220"},
	{"attachment_vm_pi_papa220_pistgrip"},
	{"attachment_vm_pi_papa220_slide"},
	{"att_laser", "att_vm_laser01_pstl", "att_vm_laser03_pstl"},
}

--{"attachment_vm_pi_papa220_slide", "attachment_vm_pi_papa220_barshort"},