--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
if SERVER then
	util.AddNetworkString("Slawer.Elections")
end

Slawer.Elections.NetsList = Slawer.Elections.NetsList or {}

function Slawer.Elections:NetReceive(strName, fnCallback)
	Slawer.Elections.NetsList[strName] = fnCallback
end

function Slawer.Elections:NetStart(strName, tblToSend, pTo)
	local tbl, iLen = Slawer.Elections:Compress(tblToSend)
	net.Start("Slawer.Elections")
	net.WriteString(strName)
	net.WriteUInt(iLen, 32)
	net.WriteData(tbl, iLen)

	if SERVER then
		if pTo and IsValid(pTo) then
			net.Send(pTo)
		else
			net.Broadcast()
		end
	else
		net.SendToServer()
	end
end

net.Receive("Slawer.Elections", function(_, pSender)
	local strName = net.ReadString()
	if not Slawer.Elections.NetsList[strName] then return end

	-- net delay
	if SERVER then
		pSender.SlawerElectionsNets = pSender.SlawerElectionsNets or {}
		if (pSender.SlawerElectionsNets[strName] or 0) > CurTime() then return end
		pSender.SlawerElectionsNets[strName] = CurTime() + 0.1
	end

	local iLen = net.ReadUInt(32)
	local tCompressed = net.ReadData(iLen)
	local tblToSend = Slawer.Elections:Decompress(tCompressed)

	if SERVER then
		Slawer.Elections.NetsList[strName](pSender, tblToSend)
	else
		Slawer.Elections.NetsList[strName](tblToSend)
	end
end)