--[[-------------------------------------------------------------------------
    Project: New York Noire - Core Framework Рефакторинг
    Author: Spoffer Dev Team
    Environment: Shared / Client / Server Core Modules
    Note: Чистая среда разработки. Локальная рабочая копия.
---------------------------------------------------------------------------]]
if SERVER then util.AddNetworkString("Slawer.Mayor") util.AddNetworkString("MayourAnsw") end

CreateConVar( "bill_board_1", "", FCVAR_REPLICATED)
CreateConVar( "bill_board_2", "", FCVAR_REPLICATED)
CreateConVar( "bill_board_3", "", FCVAR_REPLICATED)

Slawer.Mayor.NetsList = Slawer.Mayor.NetsList or {}

function Slawer.Mayor:NetReceive(strName, fnCallback)
	Slawer.Mayor.NetsList[strName] = fnCallback
end

function Slawer.Mayor:NetStart(strName, tblToSend, pTo)
	net.Start("Slawer.Mayor")
		net.WriteString(strName)
		if tblToSend then
			net.WriteBool(true)
			local cd, bn = DarkRP.TableCompress(tblToSend)
			net.WriteInt(bn, 32)
			net.WriteData(cd, bn)
		else
			net.WriteBool(false)
		end

	if SERVER then
		if pTo then
			net.Send(pTo)
		else
			net.Broadcast()
		end
	else
		net.SendToServer()
	end
end

-- от клиента: сжатые данные и они же после распаковки (сервер)
local MAX_NET = 60000
local MAX_JSON = 65536

net.Receive("Slawer.Mayor", function(_, pSender)
	if SERVER then
		if pSender.lastMayorNetSent and pSender.lastMayorNetSent > CurTime() then return end
		pSender.lastMayorNetSent = CurTime() + 0.2
	end
	local strName = net.ReadString()
	local tblToSend = {}
	if net.ReadBool() then
		local bytes_number = net.ReadInt(32)
		-- сервер не верит клиенту: размер и распаковка с пределом, иначе 60 КБ
		-- сжатого мусора распакуются в сотни мегабайт
		if SERVER and (bytes_number <= 0 or bytes_number > MAX_NET) then return end
		local compressed_data = net.ReadData(bytes_number)
		if SERVER then
			local json_data = util.Decompress(compressed_data, MAX_JSON)
			tblToSend = json_data and json_data ~= "" and util.JSONToTable(json_data)
			if not istable(tblToSend) then return end
		else
			tblToSend = DarkRP.TableDecompress(compressed_data)
		end
	end
	if !Slawer.Mayor.NetsList[strName] then return end
	if SERVER then
		Slawer.Mayor.NetsList[strName](pSender, tblToSend)
	else
		Slawer.Mayor.NetsList[strName](tblToSend)
	end
end)