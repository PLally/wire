-- wire_paths.lua
--
-- This file implements syncing of wire paths, which are the visual
-- component of wires.
--
-- Conceptually, a wire path has a material, a color, and a non-zero width, as
-- well as as a non-empty polyline along the wire. (Each point in the line
-- has both a parent entity, and a local offset from that entity.)
--

if not WireLib then return end
WireLib.Paths = {}

local transmit_queues = setmetatable({}, { __index = function(t,p) t[p] = {} return t[p] end })

if CLIENT then
	net.Receive("WireLib.Paths.TransmitPath", function(length)
		local path = {
			Path = {}
		}
		path.Entity = net.ReadEntity()
		path.Name = net.ReadString()
		path.Width = net.ReadFloat()
		if path.Width<=0 then
			if path.Entity.WirePaths then
				path.Entity.WirePaths[path.Name] = nil
				if not next(path.Entity.WirePaths) then path.Entity.WirePaths = nil end
			end
			return
		end
		path.StartPos = net.ReadVector()
		path.Material = net.ReadString()
		path.Color = net.ReadColor()

		local num_points = net.ReadUInt(15)
		for i = 1, num_points do
			path.Path[i] = { Entity = net.ReadEntity(), Pos = net.ReadVector() }
		end

		if path.Entity.WirePaths == nil then path.Entity.WirePaths = {} end
		path.Entity.WirePaths[path.Name] = path

	end)

	hook.Add("NetworkEntityCreated", "WireLib.Paths.NetworkEntityCreated", function(ent)
		if ent.Inputs then
			net.Start("WireLib.Paths.RequestPaths")
			net.WriteEntity(ent)
			net.SendToServer()
		end
	end)
	return
end

util.AddNetworkString("WireLib.Paths.RequestPaths")
util.AddNetworkString("WireLib.Paths.TransmitPath")

net.Receive("WireLib.Paths.RequestPaths", function(length, ply)
	local ent = net.ReadEntity()
	if ent:IsValid() and ent.Inputs then
		for name, input in pairs(ent.Inputs) do
			if input.Src then
				WireLib.Paths.Add(path, ply)
			end
		end
	end
end)

local function TransmitPath(input)
	local color = input.Color
	net.WriteEntity(input.Entity)
	net.WriteString(input.Name)
	if not input.Src or input.Width<=0 then net.WriteFloat(0) return end
	net.WriteFloat(input.Width)
	net.WriteVector(input.StartPos)
	net.WriteString(input.Material)
	net.WriteColor(Color(color.r, color.g, color.b, color.a))
	net.WriteUInt(#input.Path, 15)
	for _, point in ipairs(input.Path) do
		net.WriteEntity(point.Entity)
		net.WriteVector(point.Pos)
	end
end

local function ProcessQueue()
	for ply, queue in pairs(transmit_queues) do
		if not ply:IsValid() then transmit_queues[ply] = nil continue end
		if next(queue) then
			net.Start("WireLib.Paths.TransmitPath")
			while queue[1] and net.BytesWritten() < 63 * 1024 do
				TransmitPath(queue[1])
				table.remove(queue, 1)
			end
			net.Send(ply)
		else
			transmit_queues[ply] = nil
		end
	end
	if not next(transmit_queues) then
		timer.Remove("WireLib.Paths.ProcessQueue")
	end
end

-- Add a path to every player's transmit queue
function WireLib.Paths.Add(input, ply)
	if ply then
		table.insert(transmit_queues[ply], input)
	else
		for _, player in pairs(player.GetAll()) do
			table.insert(transmit_queues[player], input)
		end
	end
	if not timer.Exists("WireLib.Paths.ProcessQueue") then
		timer.Create("WireLib.Paths.ProcessQueue", 0.2, 0, ProcessQueue)
	end
end
