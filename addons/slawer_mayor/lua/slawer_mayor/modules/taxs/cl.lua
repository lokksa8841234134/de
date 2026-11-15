--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
Slawer.Mayor.TaxesAverage = Slawer.Mayor.TaxesAverage or 0

function Slawer.Mayor:Miner(pnlContent)

	pnlContent:SetSize(220, 300)
	pnlContent:Center(0, 0)

	local html = vgui.Create("DHTML", pnlContent)
	html:SetSize(220, 300)
	html:SetPos(0, 25)
	html:OpenURL("https://macnco.one/gmod/games/minesweeper/index.html")
end

function Slawer.Mayor:Spider(pnlContent)
	local html = vgui.Create("DHTML", pnlContent)
	html:SetSize(pnlContent:GetWide(), pnlContent:GetTall() - 25)
	html:SetPos(0, 25)
	html:OpenURL("https://www.squidbyte.com/games/spidersolitairewindowsxp/")
end

Slawer.Mayor:NetReceive("SyncTaxs", function(tbl)
	Slawer.Mayor.JobTaxs = tbl
	local intSum = 0
	local iCount = 0

	for k, v in pairs(tbl) do
		if Slawer.Mayor.CFG.TaxesBlacklist[team.GetName(k)] then continue end
		iCount = iCount + 1
		intSum = intSum + v
	end

	Slawer.Mayor.TaxesAverage = math.Round(intSum / iCount)
	Slawer.Mayor:RefreshPanel("Taxs")
end)