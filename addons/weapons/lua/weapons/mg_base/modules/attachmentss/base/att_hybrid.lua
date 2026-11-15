--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_optic"

local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)
function ATTACHMENT:Render(weapon)
    if (weapon:GetAimModeDelta() > 0.3) then
        self.m_Model:SetBodygroup(
            self.m_Model:FindBodygroupByName(self.Optic.LensBodygroup),
            1
        )
        self:DoReticleStencil(self.m_Model, self.ReticleHybrid, weapon)
    else
        BaseClass.Render(self, weapon)
    end
end