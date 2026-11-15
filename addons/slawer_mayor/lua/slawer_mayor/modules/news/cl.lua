--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
function Slawer.Mayor:ShowNews(pnlContent)
	local pnlBox = vgui.Create("DPanel", pnlContent)
	pnlBox:SetSize(pnlContent:GetWide() - 10, 310)
	pnlBox:SetPos(5, 25)
	pnlBox.Paint = nil
	local rlist = vgui.Create("WINPanelList", pnlBox)
	rlist:SetSize(pnlContent:GetWide() - 10, 310)
	rlist:SetPos(0, 0)
	rlist:EnableVerticalScrollbar()
	rlist:EnableHorizontal(true)
	rlist:SetSpacing(2)
	rlist.IgnoreVbar = true
	Win98.Header(rlist, "Написать новости района", TEXT_ALIGN_CENTER, color_black, nil, "Roman.36")
	local text = ""

	Win98.TextEntry(rlist, "static", nil, 1, 160, "Новости...", "", "", function(s, value)
		text = value
	end, true, nil, true)

	local btnSave = Win98.ButtonBlack(rlist, "Отправить", "Roman.26", "envelope_closed-0", pnlContent:GetWide() - 10, 44, function()
		Slawer.Mayor:NetStart("UpdateNews", {
			message = text
		})
	end)

	btnSave.bgc = Win98.Cls.gray
	btnSave.tc = color_black
	btnSave.htc = Win98.Text.b

	btnSave.pbg = function(s, w, h)
		surface.SetDrawColor(s.bgc)
		surface.DrawRect(0, 0, w, h)
		Win98.InnerRec(1, 1, w - 2, h - 2)
	end

	rlist:AddItem(btnSave)
end