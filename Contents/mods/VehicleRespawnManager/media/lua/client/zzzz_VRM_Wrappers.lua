---@diagnostic disable: undefined-global
local original_ISRemoveBurntVehicle_perform = ISRemoveBurntVehicle.perform;
---@diagnostic disable-next-line: duplicate-set-field
function ISRemoveBurntVehicle:perform()
    local res = original_ISRemoveBurntVehicle_perform(self);
    sendClientCommand("VehicleRespawnManager", "QueueVehicle",
        {
            type = "random",
        }
    );
    return res;
end

if RecycleVehicleAction then
    local original_RecycleVehicleAction_perform = RecycleVehicleAction.perform

    function RecycleVehicleAction:perform()
        local res = original_RecycleVehicleAction_perform(self);
        sendClientCommand("VehicleRespawnManager", "QueueVehicle",
            {
                type = "random",
            }
        );
        return res;
    end
end

if ISVehicleSalvage then
    local original_ISVehicleSalvage_perform = ISVehicleSalvage.perform;

    function ISVehicleSalvage:perform()
        local res = original_ISVehicleSalvage_perform(self)
        sendClientCommand("VehicleRespawnManager", "QueueVehicle",
            {
                type = "random",
            }
        );
        return res;
    end
end
