--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
local PANEL = {}

function PANEL:Init()
	local dvBar = self:GetVBar()
	dvBar:SetWide(10)
	dvBar:SetHideButtons(true)

	function dvBar:Paint(iW, iH)
	end

	function dvBar.btnGrip:Paint(iW, iH)
		MSDX.Draw(2, iW - 5, 0, 5, iH, color_black)
	end

	--[[
		Code from Gigabait that I edited
	]]
	dvBar.LerpTarget = 0

	function dvBar:AddScroll(dlta)
		local OldScroll = self.LerpTarget or self:GetScroll()
		dlta = dlta * 75
		self.LerpTarget = math.Clamp(self.LerpTarget + dlta, -self.btnGrip:GetTall(), self.CanvasSize + self.btnGrip:GetTall())

		return OldScroll ~= self:GetScroll()
	end

	function dvBar:OnMousePressed(...)
		local _, y = self:CursorPos()
		local PageSize = self.BarSize

		if (y > self.btnGrip.y) then
			self.LerpTarget = self:GetScroll() + PageSize
		else
			self.LerpTarget = self:GetScroll() - PageSize
		end
	end

	dvBar.Think = function(s)
		if s.Dragging then
			s.LerpTarget = s:GetScroll()

			return
		end

		local frac = FrameTime() * 5

		if (math.abs(s.LerpTarget - s:GetScroll()) <= (s.CanvasSize / 10)) then
			frac = FrameTime() * 2
		end

		local newpos = Lerp(frac, s:GetScroll(), s.LerpTarget)
		s:SetScroll(math.Clamp(newpos, 0, s.CanvasSize))

		if (s.LerpTarget < 0 and s:GetScroll() <= 0) then
			s.LerpTarget = 0
		elseif (s.LerpTarget > s.CanvasSize and s:GetScroll() >= s.CanvasSize) then
			s.LerpTarget = s.CanvasSize
		end
	end
end

vgui.Register("Slawer.Elections:DScrollPanel", PANEL, "DScrollPanel")