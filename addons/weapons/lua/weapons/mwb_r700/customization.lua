--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()

function SWEP:doSuppressorStats()
	self.Primary.Sound = Sound("weap_romeo700_sup_plr")

	self.Reverb = {
		RoomScale = 50000,
		Sounds = {
			Outside = {
				Layer = Sound("Atmo_DMR_Sup.Outside"),
				Reflection = Sound("Reflection_Sniper.Outside")
			},
			Inside = {
				Layer = Sound("Atmo_DMR_Sup.Inside"),
				Reflection = Sound("Reflection_Sniper.Inside")
			}
		}
	}

	self.ParticleEffects.MuzzleFlash = "mwb_suppressor_0"
end

SWEP.Customization = {
	{"att_ammo", "romeo700_mag"},
	{"romeo700_stock"},
	{"romeo700_bolt"},
	{"att_sight", "weapon_vm_scope_kilo98", "romeo700_scope"},
}