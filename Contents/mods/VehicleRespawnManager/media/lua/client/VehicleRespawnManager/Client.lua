local Logger = require("ElyonLib/Logger"):new("Vehicle Respawn Manager");

local VehicleRespawnManager = require("VehicleRespawnManager/Shared");
VehicleRespawnManager.Client = {};
VehicleRespawnManager.Client.ClientCommands = {};

function VehicleRespawnManager.Client.ClientCommands.LoadZones(args)
    if type(args) ~= "table" then args = {}; end
    VehicleRespawnManager.Zones = args;
end

function VehicleRespawnManager.Client.ClientCommands.onServerCommand(module, command, args)
    if module ~= "VehicleRespawnManager" then return; end
    if VehicleRespawnManager.Client.ClientCommands[command] then
        VehicleRespawnManager.Client.ClientCommands[command](args);
    end
end

Events.OnServerCommand.Add(VehicleRespawnManager.Client.ClientCommands.onServerCommand);
