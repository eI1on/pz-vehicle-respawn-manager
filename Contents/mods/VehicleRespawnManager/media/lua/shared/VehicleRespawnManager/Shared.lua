local Globals = require("Starlit/Globals");

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
    if Globals.isClient then
        sendClientCommand("VehicleRespawnManager", "LoadZones", {});
    else
        VehicleRespawnManager.Zones = ModData.getOrCreate("VehicleRespawnManagerZones");
    end
    return VehicleRespawnManager.Zones;
end

return VehicleRespawnManager
