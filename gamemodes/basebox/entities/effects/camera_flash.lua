--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
function EFFECT:Init( data )

	local vOffset = data:GetOrigin()
	local ent = data:GetEntity()

	local dlight = DynamicLight( ent:EntIndex() )

	if ( dlight ) then

		dlight.Pos = vOffset
		dlight.r = 255
		dlight.g = 255
		dlight.b = 255
		dlight.Brightness = 10
		dlight.Size = 512
		dlight.DieTime = CurTime() + 0.02
		dlight.Decay = 512

	end

end

function EFFECT:Think()
	return false
end

function EFFECT:Render()
end
