--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
ATTACHMENT.Base = "att_vm_laser01"
ATTACHMENT.Name = ".red Swift"
ATTACHMENT.Laser = {
    BeamMaterial = Material("mw19_laserbeam.vmt"),
    DotMaterial = Material("mg/sprites/shoothouselaser.vmt"),
    BeamSize = 15,
    BeamWidth = 1,
    DotSize = 2,
    Color = Color(255, 0, 255, 255),
    Attachment = "laser"
}