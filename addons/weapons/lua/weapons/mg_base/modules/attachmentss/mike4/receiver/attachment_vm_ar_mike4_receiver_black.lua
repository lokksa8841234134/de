--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_receiver"
ATTACHMENT.Name = "Альтернативный ресивер (A2)"
ATTACHMENT.Model = Model("models/att/m4/a2_receiver.mdl")
local BaseClass = GetAttachmentBaseClass(ATTACHMENT.Base)

function ATTACHMENT:Stats(weapon)
	BaseClass.Stats(self, weapon)
	weapon.LaserAimAngles = Angle(0, 0, 0)
	weapon.LaserAimPos = Vector(0, 6, 0)
end

ATTACHMENT.Laser = {}