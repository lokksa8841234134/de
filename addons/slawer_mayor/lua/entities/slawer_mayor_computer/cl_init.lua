--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
include("shared.lua")

function ENT:CreateMenu()
	Slawer.Mayor.Menu = vgui.Create("Slawer.Mayor:Menu")
end

function ENT:Draw()
	self:DrawModel()
end

function ENT:OnRemove()
	Slawer.Mayor.FocusEntry = nil

	if Slawer.Mayor.LookingTo then
		gui.EnableScreenClicker(false)
		Slawer.Mayor.LookingTo = nil
	end

	if IsValid(Slawer.Mayor.FakeTextEntry) then
		Slawer.Mayor.FakeTextEntry:Remove()
	end

	if IsValid(Slawer.Mayor.Menu) then
		Slawer.Mayor.Menu:Remove()
		LocalPlayer():SetNoDraw(false)
	end
end