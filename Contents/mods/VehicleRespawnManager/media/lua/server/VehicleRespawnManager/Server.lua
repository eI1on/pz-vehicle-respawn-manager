local Globals = require("Starlit/Globals");

local Logger = require("ElyonLib/Logger"):new("Vehicle Respawn Manager");

local VehicleRespawnManager = require("VehicleRespawnManager/Shared");
VehicleRespawnManager.Server = {};
VehicleRespawnManager.Server.ServerCommands = {};

--------------------------------------------------
-- PUSHING UPDATES TO CLIENTS
--------------------------------------------------
function VehicleRespawnManager.Server.PushUpdateToAll(zones)
    if Globals.isServer then
        sendServerCommand("VehicleRespawnManager", "LoadZones", zones);
    else
        VehicleRespawnManager.Zones = zones;
    end
    VehicleRespawnManager.RespawnSystem.InitZones();
end

function VehicleRespawnManager.Server.PushUpdateToPlayer(player, zones)
    if Globals.isServer then
        sendServerCommand(player, "VehicleRespawnManager", "LoadZones", zones);
    else
        VehicleRespawnManager.Zones = zones;
    end
    VehicleRespawnManager.RespawnSystem.InitZones();
end

--------------------------------------------------
-- SERVER COMMAND HANDLERS
--------------------------------------------------
function VehicleRespawnManager.Server.ServerCommands.LoadZones(player, args)
    local zones = VehicleRespawnManager.Shared.RequestZones();
    VehicleRespawnManager.Server.PushUpdateToPlayer(player, zones);
end

function VehicleRespawnManager.Server.ServerCommands.AddZone(player, args)
    local zones = VehicleRespawnManager.Shared.RequestZones();
    local newZone = args.newZone;
    table.insert(zones, newZone);
    VehicleRespawnManager.Server.PushUpdateToPlayer(player, zones);
end

function VehicleRespawnManager.Server.ServerCommands.RemoveZone(player, args)
    local zones = VehicleRespawnManager.Shared.RequestZones();
    local selectedIdx = args.selectedIdx;
    table.remove(zones, selectedIdx);
    VehicleRespawnManager.Server.PushUpdateToPlayer(player, zones);
end

-- Edit zone data
local function navigateOrCreateTable(tbl, path)
    local current = tbl;
    for key in string.gmatch(path or "", "([^%.]+)") do
        if not current[key] then current[key] = {}; end
        current = current[key];
    end
    return current;
end

function VehicleRespawnManager.Server.ServerCommands.EditZoneData(player, args)
    local zones = VehicleRespawnManager.Shared.RequestZones();

    local dataSelected = args.selectedIdx;
    local selectedZone = zones[dataSelected];
    local newKey = args.newKey;
    local newValue = args.newValue;

    if not selectedZone then
        Logger:error("selectedZone not found dataSelected = %s", dataSelected);
        return;
    end

    local parentTablePath, finalKey = string.match(newKey, "^(.*)%.([^%.]+)$");
    local modifying = parentTablePath and navigateOrCreateTable(selectedZone, parentTablePath) or selectedZone;

    if not modifying then
        Logger:error("Could not find the table to modify: selectedZone = %s, parentTablePath = %s", selectedZone,
            parentTablePath);
        return;
    end

    local modifyingKey = finalKey or newKey;

    if newValue == nil then
        if modifying[modifyingKey] ~= nil then
            modifying[modifyingKey] = nil;
        end
    else
        modifying[modifyingKey] = tonumber(newValue) or newValue;
    end

    VehicleRespawnManager.Server.PushUpdateToPlayer(player, zones);
end

function VehicleRespawnManager.Server.ServerCommands.ImportZoneData(player, args)
    local newZones = args.zones;
    local zones = VehicleRespawnManager.Shared.RequestZones();

    for i = #zones, #newZones + 1, -1 do table.remove(zones, i); end
    for _, newZone in pairs(newZones) do table.insert(zones, newZone); end

    VehicleRespawnManager.Server.PushUpdateToPlayer(player, zones);
end

function VehicleRespawnManager.Server.ServerCommands.ExportRespawnSystemData(player, args)
    sendServerCommand("VehicleRespawnManager", "ExportRespawnSystemData",
        { data = VehicleRespawnManager.RespawnSystem.getGMD() });
end

function VehicleRespawnManager.Server.ServerCommands.SetLogLevel(player, args)
    local level = args.level and args.level or "INFO";
    Logger:setLogLevel(level);
end

--------------------------------------------------
-- SERVER COMMAND HANDLER: QueueVehicle
--------------------------------------------------
function VehicleRespawnManager.Server.ServerCommands.QueueVehicle(player, args)
    local queueType = args.type;
    if queueType == "random" then
        if not args.count then
            VehicleRespawnManager.RespawnSystem.QueueRandomVehicle();
        else
            local count = tonumber(args.count);
            if count and count > 0 then
                for i = 1, count do
                    VehicleRespawnManager.RespawnSystem.QueueRandomVehicle();
                end
            end
        end
    elseif queueType == "fixed" then
        local scriptName = args.scriptName;
        if not scriptName then
            return;
        end
        if not VehicleRespawnManager.Shared.VehicleScripts[scriptName] then
            return;
        end
        if not args.count then
            VehicleRespawnManager.RespawnSystem.QueueFixedVehicle(scriptName);
        else
            local count = tonumber(args.count);
            if count and count > 0 then
                for i = 1, count do
                    VehicleRespawnManager.RespawnSystem.QueueFixedVehicle(scriptName);
                end
            end
        end
    end
end

function VehicleRespawnManager.Server.onClientCommand(module, command, player, args)
    if module ~= "VehicleRespawnManager" then return; end
    if VehicleRespawnManager.Server.ServerCommands[command] then
        VehicleRespawnManager.Server.ServerCommands[command](player, args);
    end
end

Events.OnClientCommand.Add(VehicleRespawnManager.Server.onClientCommand);
