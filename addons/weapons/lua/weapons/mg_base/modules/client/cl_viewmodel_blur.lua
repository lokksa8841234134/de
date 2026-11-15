--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
AddCSLuaFile()

function SWEP:ViewModelBlurModule()
    if (!IsValid(self:GetOwner())) then
        return
    end

    local bPixelShaders2 = render.SupportsPixelShaders_2_0()

    if (!bPixelShaders2) then
        return
    end

   -- self:ViewBlur()
end

function SWEP:ViewBlur()
end