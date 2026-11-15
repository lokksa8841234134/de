--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
function Slawer.Mayor:ShowWarrants(scroll)
	scroll:Clear()
	Slawer.Mayor.PropertyList = scroll

	local tlist = {}
	local ter
	for k,v in SortedPairsByMemberValue(Territories.list, "printStr") do
		if not v.buyable then continue end
		table.insert(tlist, {(v.printStr and v.printStr .. ", " or "") .. v.printName, k})
	end

	Win98.InfoTextF1(scroll, "Введите адрес для поиска недвижемости", scroll:GetWide() - 10, "Roman.38", color_white, color_black)

	local TerLabel
	local Entry = Win98.TextEntryAlt(scroll, nil, nil, scroll:GetWide() - 255, 45, "", function() end, false, nil, false, false, color_white, function(s, wd, hd)
		MSDX.Draw(0, 0, 0, wd, hd, Win98.Cls.nypd)
		Win98.InnerRec(0, 0, wd, hd)

		if s:GetValue() == "" then
			draw.SimpleText("Поиск адреса", "Roman.22", 5, hd / 2, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end)
	Entry:SetFont("Roman.32")

	local btnSave = Win98.ButtonBlack(scroll, "Поиск", "Roman.38", "search_directory-5", 240, 45, function()
		for k,v in pairs(tlist) do
			if string.find(utf8.lower(v[1]), utf8.lower(Entry:GetValue())) then
				TerLabel.text = v[1]
				ter = v[2]
				break
			end
		end
	end)
	scroll:AddItem(btnSave)

	Win98.InfoTextF1(scroll, "Адрес для ордера:", scroll:GetWide() - 10, "Roman.22", color_white, color_black)
	TerLabel = Win98.InfoTextF1(scroll, "...", scroll:GetWide() - 10, "Roman.38", color_white, color_black)
	Win98.InfoTextF1(scroll, "Причина для ордера:", scroll:GetWide() - 10, "Roman.22", color_white, color_black)
	local txtReason = Win98.TextEntryAlt(scroll, nil, nil, scroll:GetWide() - 10, 45, "", function() end, false, nil, false, false, color_white, function(s, wd, hd)
		MSDX.Draw(0, 0, 0, wd, hd, Win98.Cls.nypd)
		Win98.InnerRec(0, 0, wd, hd)

		if s:GetValue() == "" then
			draw.SimpleText("Укажите причину", "Roman.22", 5, hd / 2, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end)
	txtReason:SetFont("Roman.32")

	local btnSave2 = Win98.ButtonBlack(scroll, "Запросить ордер", "Roman.38", "search_directory-5", scroll:GetWide() - 10, 45, function()
		if not ter or txtReason:GetValue() == "" then return end
		RunConsoleCommand("drp_warrant", ter, txtReason:GetText())

		scroll:Clear()
		Win98.InfoTextF1(scroll, "Запрос отправлен, ожидайте", scroll:GetWide() - 10, "Roman.32", color_white, color_black)
	end)
	scroll:AddItem(btnSave2)
end

Slawer.Mayor:NetReceive("SyncWarrants", function(tbl)
	Slawer.Mayor.WarrantsList = tbl
	Slawer.Mayor:RefreshPanel("Warrants")
end)

Slawer.Mayor:NetReceive("GetOwners", function(tbl)
	if IsValid(Slawer.Mayor.PropertyList) then
		Slawer.Mayor.PropertyList.update(tbl)
	end
end)