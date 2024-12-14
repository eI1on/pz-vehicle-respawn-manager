local Logger = require("ElyonLib/Logger"):new("Vehicle Respawn Manager");
local FileUtils = require("ElyonLib/FileUtils");

local VehicleRespawnManager = {};
VehicleRespawnManager.Shared = {};
VehicleRespawnManager.Shared.VehicleScripts = {};

function VehicleRespawnManager.Shared.InitVehicleScripts()
    local allScripts = getScriptManager():getAllVehicleScripts();
    local size = allScripts:size();
    for i = 1, size do
        local script = allScripts:get(i - 1);
        VehicleRespawnManager.Shared.VehicleScripts[script:getFullName()] = true;
    end
end

Events.OnInitGlobalModData.Add(VehicleRespawnManager.Shared.InitVehicleScripts)


function VehicleRespawnManager.Shared.RequestZones()
    if not VehicleRespawnManager.Zones then
        if isClient() then
            sendClientCommand("VehicleRespawnManager", "LoadZones", {});
        elseif isServer() or (not isClient() and not isServer()) then
            VehicleRespawnManager.Zones = ModData.getOrCreate("VehicleRespawnManagerZones");
        end
    end
    return VehicleRespawnManager.Zones;
end

return VehicleRespawnManager
