local AccessLevelUtils = require("ElyonLib/PlayerUtils/AccessLevelUtils")
local FileUtils = require("ElyonLib/FileUtils/FileUtils");
local Logger = require("VehicleRespawnManager/Logger");
local VehicleRespawnManager = require("VehicleRespawnManager/Shared");

VehicleRespawnManager.Client = {};
VehicleRespawnManager.Client.ClientCommands = {};

function VehicleRespawnManager.Client.ClientCommands.LoadZones(args)
    if type(args) ~= "table" then args = {}; end
    VehicleRespawnManager.Zones = args;
end

function VehicleRespawnManager.Client.ClientCommands.ExportRespawnSystemData(args)
    if type(args) ~= "table" then args = {}; end
    local cacheDir = Core.getMyDocumentFolder() ..
        getFileSeparator() .. "Lua" .. getFileSeparator() .. "ExportRespawnSystemData.json";

    local success = false;
    success = FileUtils.writeJson("ExportRespawnSystemData.json", args.data, "Vehicle Respawn Manager",
        { createIfNull = true });

    if success then
        Logger:info("ExportRespawnSystemData EXPORTED SUCCESFULLY TO %s", cacheDir);
        if isDesktopOpenSupported() then
            showFolderInDesktop(cacheDir);
        else
            openUrl(cacheDir);
        end
    end
end

function VehicleRespawnManager.Client.ClientCommands.onServerCommand(module, command, args)
    if module ~= "VehicleRespawnManager" then return; end
    if VehicleRespawnManager.Client.ClientCommands[command] then
        VehicleRespawnManager.Client.ClientCommands[command](args);
    end
end

local doCommand = false;
local function sendCommand()
    if doCommand then
        if AccessLevelUtils.isPlayerAtLeast(getPlayer():getPlayerNum(), "Admin", getPlayer()) then
            sendClientCommand("VehicleRespawnManager", "LoadZones", {});
        end
        Events.OnTick.Remove(sendCommand);
    end
    doCommand = true;
end
Events.OnTick.Add(sendCommand);

Events.OnServerCommand.Add(VehicleRespawnManager.Client.ClientCommands.onServerCommand);
