local VehicleRespawnManager = require("VehicleRespawnManager/Shared");

local VehicleScriptTextBox = ISTextBox:derive("VehicleScriptTextBox")

local function isScriptNameValid(scriptName)
    return VehicleRespawnManager.Shared.VehicleScripts[scriptName] and not string.match(scriptName, "[^%w%._%-]");
end

function VehicleScriptTextBox:updateButtons()
    self.yes:setEnable(true);
    self.yes.tooltip = nil;
    local text = self.entry:getText():trim();

    if self.checkVehicleScripts then
        local singleVehicleMode = self.singleVehicleMode;

        local isValid = true;
        if singleVehicleMode then
            isValid = isScriptNameValid(text);
        else
            for scriptName in string.gmatch(text, "[^;]+") do
                scriptName = string.trim(scriptName);
                if not isScriptNameValid(scriptName) then
                    isValid = false;
                    break;
                end
            end
        end

        if not isValid then
            self.yes:setEnable(false);
            self.yes.tooltip = getText("IGUI_VRM_InvalidVehicleScript");
            return;
        end
    end

    ISTextBox.updateButtons(self);
end

function VehicleScriptTextBox:setSingleVehicleMode(mode)
    self.singleVehicleMode = mode;
end

function VehicleScriptTextBox:setCheckVehicleScripts(mode)
    self.checkVehicleScripts = mode;
end

return VehicleScriptTextBox;
