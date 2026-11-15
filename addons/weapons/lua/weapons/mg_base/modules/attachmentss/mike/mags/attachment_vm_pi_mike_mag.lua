--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_magazine"
ATTACHMENT.Model = Model("models/viper/mw/attachments/attachment_vm_pi_mike_mag.mdl")

ATTACHMENT.BulletList = {
    [1] = {"j_bullet1"},
    [2] = {"j_bullet2"},
    [3] = {"j_bullet3"},
    [4] = {"j_bullet4"},
    [5] = {"j_bullet5"},
    [6] = {"j_bullet6"},
    [7] = {"j_bullet7"},
    [8] = {"j_bullet8"},
    [9] = {"j_bullet9"},
    [10] = {"j_bullet10"},
}

local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)
function ATTACHMENT:Stats(weapon)
    BaseClass.Stats(self, weapon)
end