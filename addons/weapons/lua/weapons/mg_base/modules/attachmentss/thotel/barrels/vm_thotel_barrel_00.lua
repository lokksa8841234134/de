--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_barrel"
ATTACHMENT.Model = Model("models/easy/vg/attachments/thotel/vm_thotel_barrel_00.mdl")
--[[ATTACHMENT.Flashlight = {
    FlashlightMaterial = Material("effects/flashlight001.vmt"),
    Color = Color(255, 255, 255, 255),
    Attachment = "flashlight"
}
ATTACHMENT.Laser = {} --needed for base to know its a laser

local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:DoLaserRender(weapon, laserModel)
end

function ATTACHMENT:DrawFlashlight(weapon, model)
    local grip = weapon:GetAttachmentInUseByCategory("Grips")
    local tacLaser = weapon:HasAttachment("attachment_vm_sm_mpapa5_laser01")

    if ((grip != nil && grip.Index > 1) || tacLaser) then
        self:RemoveFlashlightStuffFromModel(model)
        return
    end

    BaseClass.DrawFlashlight(self, weapon, model)
end]]