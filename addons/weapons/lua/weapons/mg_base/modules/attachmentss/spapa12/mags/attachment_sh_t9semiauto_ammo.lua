--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_magazine"
ATTACHMENT.Name = "Default Mags"
ATTACHMENT.Model = Model("models/zeron/attachment_vm_sh_t9semiauto_ammo_LOD0.mdl")
local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:Stats(weapon)
    BaseClass.Stats(self, weapon)

end

-- function ATTACHMENT:PostProcess(weapon)
    -- BaseClass.PostProcess(self, weapon)
    -- weapon.Animations.Reload_Start = nil
    -- weapon.Animations.Reload_Loop = nil
    -- weapon.Animations.Reload_End = nil
    -- weapon.Animations.Reload_EndEmpty = nil
-- end 