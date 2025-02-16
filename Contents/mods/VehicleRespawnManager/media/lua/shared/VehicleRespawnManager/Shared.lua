local Globals = require("Starlit/Globals");

local VehicleRespawnManager = {};
VehicleRespawnManager.Shared = {};
VehicleRespawnManager.Shared.VehicleScripts = {};
VehicleRespawnManager.Shared.ExcludedVehicleScripts = {
    ["Base.ModernCar_Martin"] = true,
    ["Base.SportsCar_ez"] = true,
}

function VehicleRespawnManager.Shared.InitVehicleScripts()
    local allScripts = getScriptManager():getAllVehicleScripts();
    for i = 0, allScripts:size() - 1 do
        local script = allScripts:get(i);
        local scriptName = script:getFullName();

        if not VehicleRespawnManager.Shared.ExcludedVehicleScripts[scriptName] then
            VehicleRespawnManager.Shared.VehicleScripts[scriptName] = true;
        end
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
