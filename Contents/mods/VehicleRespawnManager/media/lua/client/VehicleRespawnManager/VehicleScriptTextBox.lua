local VehicleRespawnManager = require("VehicleRespawnManager/Shared");

local VehicleScriptTextBox = ISPanelJoypad:derive("VehicleScriptTextBox");

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small);
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium);

function VehicleScriptTextBox:initialise()
    ISPanelJoypad.initialise(self);

    local fontHgt = FONT_HGT_SMALL;
    local buttonWid1 = getTextManager():MeasureStringX(UIFont.Small, "Ok") + 12;
    local buttonWid2 = getTextManager():MeasureStringX(UIFont.Small, "Cancel") + 12;
    local buttonWid = math.max(math.max(buttonWid1, buttonWid2), 100);
    local buttonHgt = math.max(fontHgt + 6, 25);
    local padBottom = 10;

    self.addBttn = ISButton:new((self:getWidth() / 2) - 5 - buttonWid, self:getHeight() - padBottom - buttonHgt, buttonWid,
        buttonHgt, getText("IGUI_VRM_Add"), self, VehicleScriptTextBox.onClick);
    self.addBttn.internal = "ADD";
    self.addBttn:initialise();
    self.addBttn:instantiate();
    self.addBttn.borderColor = { r = 1, g = 1, b = 1, a = 0.1 };
    self:addChild(self.addBttn);

    self.cancelBttn = ISButton:new((self:getWidth() / 2) + 5, self:getHeight() - padBottom - buttonHgt, buttonWid, buttonHgt,
        getText("IGUI_VRM_Cancel"), self, VehicleScriptTextBox.onClick);
    self.cancelBttn.internal = "CANCEL";
    self.cancelBttn:initialise();
    self.cancelBttn:instantiate();
    self.cancelBttn.borderColor = { r = 1, g = 1, b = 1, a = 0.1 };
    self:addChild(self.cancelBttn);

    self.fontHgt = FONT_HGT_MEDIUM;
    local inset = 2;
    local height = inset + self.fontHgt * self.numLines + inset;

    if self.singleVehicleMode then
        self.entry = ISComboBox:new(self:getWidth() / 2 - ((self:getWidth() - 40) / 2),
            (self:getHeight() - height) / 2, self:getWidth() - 40, height);
        self.entry:initialise();
        self.entry:instantiate();
        self.entry:setEditable(true);
        self.entry:setHeight(20);
        self.entry:setWidth(self:getWidth() - 40);
        self:addChild(self.entry);

        local vehicleScripts = VehicleRespawnManager.Shared.VehicleScripts;
        for scriptName, _ in pairs(vehicleScripts) do
            self.entry:addOption(scriptName);
        end

        self.entry.onTextChange = function()
            local input = self.entry:getInternalText():trim();
            self:filterComboBoxOptions(input);
        end;
    else
        self.entry = ISTextEntryBox:new(self.defaultEntryText, self:getWidth() / 2 - ((self:getWidth() - 40) / 2),
            (self:getHeight() - height) / 2, self:getWidth() - 40, height);
        self.entry.font = UIFont.Medium;
        self.entry:initialise();
        self.entry:instantiate();
        self.entry:setMaxLines(self.maxLines);
        self.entry:setMultipleLine(self.multipleLine);
        self:addChild(self.entry);
    end
end

function VehicleScriptTextBox:filterComboBoxOptions(input)
    self.entry:clear();
    local vehicleScripts = VehicleRespawnManager.Shared.VehicleScripts;
    for scriptName, _ in pairs(vehicleScripts) do
        if string.find(string.lower(scriptName), string.lower(input)) then
            self.entry:addOption(scriptName);
        end
    end
end

function VehicleScriptTextBox:setSingleVehicleMode(mode)
    self.singleVehicleMode = mode;
    if mode then
        self:initialise();
    else
        self:initialise();
    end
end

function VehicleScriptTextBox:setCheckVehicleScripts(mode)
    self.checkVehicleScripts = mode;
end

function VehicleScriptTextBox:setOnlyNumbers(onlyNumbers)
    self.entry:setOnlyNumbers(onlyNumbers);
end

function VehicleScriptTextBox:setMultipleLine(multiple)
    self.multipleLine = multiple;
end

function VehicleScriptTextBox:isMultipleLine()
    return self.javaObject:isMultipleLine();
end

function VehicleScriptTextBox:setNumberOfLines(numLines)
    self.numLines = numLines;
end

function VehicleScriptTextBox:setMaxLines(max)
    self.maxLines = max;
    if self.javaObject then
        self.javaObject:setMaxLines(max);
    end
end

function VehicleScriptTextBox:getMaxLines()
    return self.maxLines;
end

function VehicleScriptTextBox:setValidateFunction(target, func, arg1, arg2)
    self.validateTarget = target;
    self.validateFunc = func;
    self.validateArgs = { arg1, arg2 };
end

function VehicleScriptTextBox:setValidateTooltipText(text)
    self.validateTooltipText = text;
end

function VehicleScriptTextBox:destroy()
    UIManager.setShowPausedMessage(true);
    self:setVisible(false);
    self:removeFromUIManager();
end

function VehicleScriptTextBox:onClick(button)
    if self.player and JoypadState.players[self.player + 1] then
        setJoypadFocus(self.player, nil);
    elseif self.joyfocus and self.joyfocus.focus == self then
        self.joyfocus.focus = nil;
    end
    if self.onclick ~= nil then
        self.onclick(self.target, button, self.param1, self.param2, self.param3, self.param4);
    end
    if not self.showError then
        if button.internal == "CANCEL" then self:destroy(); end
    end
end

function VehicleScriptTextBox:titleBarHeight()
    return 16;
end

function VehicleScriptTextBox:prerender()
    self.backgroundColor.a = 0.8;
    self.entry.backgroundColor.a = 0.8;

    self:drawRect(0, 0, self.width, self.height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g,
        self.backgroundColor.b);

    local th = self:titleBarHeight();
    self:drawTextureScaled(self.titlebarbkg, 2, 1, self:getWidth() - 4, th - 2, 1, 1, 1, 1);

    self:drawRectBorder(0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g,
        self.borderColor.b);

    local fontHgt = getTextManager():getFontFromEnum(UIFont.Small):getLineHeight();
    self:drawTextCentre(self.text, self:getWidth() / 2, self.entry:getY() - 8 - fontHgt, 1, 1, 1, 1, UIFont.Small);

    if self.showError then
        local fontHgt = getTextManager():getFontFromEnum(UIFont.Small):getLineHeight();
        self:drawTextCentre(self.errorMsg, self:getWidth() / 2, self.entry:getY() + 50 - fontHgt, 1, 0, 0, 1,
            UIFont.Small);
    end

    self:updateButtons();
end

function VehicleScriptTextBox:showErrorMessage(show, errorMsg)
    self.showError = show;
    self.errorMsg = errorMsg;
end

local function isScriptNameValid(scriptName)
    return VehicleRespawnManager.Shared.VehicleScripts[scriptName] and not string.match(scriptName, "[^%w%._%-]");
end

function VehicleScriptTextBox:updateButtons()
    self.addBttn:setEnable(true);
    self.addBttn.tooltip = nil;
    local text = "";

    if self.singleVehicleMode then
        text = self.entry:getSelectedText():trim();
    else
        text = self.entry:getText():trim();
    end

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
            self.addBttn:setEnable(false);
            self.addBttn.tooltip = getText("IGUI_VRM_InvalidVehicleScript");
            return;
        end
    end

    if self.validateFunc and not self.validateFunc(self.validateTarget, text, self.validateArgs[1], self.validateArgs[2]) then
        self.addBttn:setEnable(false);
        self.addBttn.tooltip = self.validateTooltipText;
    end
    if self.maxChars and ((not self.singleVehicleMode and self.entry:getInternalText():len() > self.maxChars) or (self.singleVehicleMode and self.entry.editor and self.entry.editor:getInternalText():len() > self.maxChars)) then
        self.addBttn:setEnable(false);
        self.addBttn.tooltip = getText("IGUI_TextBox_TooManyChar", self.maxChars);
    end
    if self.cancelBttnEmpty and ((not self.singleVehicleMode and string.trim(self.entry:getInternalText()) == "") or (self.singleVehicleMode and self.entry.editor and string.trim(self.entry.editor:getInternalText()) == "")) then
        self.addBttn:setEnable(false);
        self.addBttn.tooltip = getText("IGUI_TextBox_CantBeEmpty");
    end
    if self.joyfocus and self.entry.joypadFocused then
        self.ISButtonA = nil;
        self.ISButtonB = nil;
        self.addBttn:clearJoypadButton();
        self.cancelBttn:clearJoypadButton();
    elseif self.joyfocus and not self.entry.joypadFocused then
        self:setISButtonForA(self.addBttn);
        self:setISButtonForB(self.cancelBttn);
    end
end

function VehicleScriptTextBox:render()
end

function VehicleScriptTextBox:onMouseMove(dx, dy)
    self.mouseOver = true;
    if self.moving then
        self:setX(self.x + dx);
        self:setY(self.y + dy);
        self:bringToTop();
    end
end

function VehicleScriptTextBox:onMouseMoveOutside(dx, dy)
    self.mouseOver = false;
    if self.moving then
        self:setX(self.x + dx);
        self:setY(self.y + dy);
        self:bringToTop();
    end
end

function VehicleScriptTextBox:onMouseDown(x, y)
    if not self:getIsVisible() then return; end
    self.downX = x;
    self.downY = y;
    self.moving = true;
    self:bringToTop();
end

function VehicleScriptTextBox:onMouseUp(x, y)
    if not self:getIsVisible() then
        return;
    end
    self.moving = false;
    if ISMouseDrag.tabPanel then
        ISMouseDrag.tabPanel:onMouseUp(x, y);
    end
    ISMouseDrag.dragView = nil;
end

function VehicleScriptTextBox:onMouseUpOutside(x, y)
    if not self:getIsVisible() then return; end
    self.moving = false;
    ISMouseDrag.dragView = nil;
end

function VehicleScriptTextBox:onGainJoypadFocus(joypadData)
    ISPanelJoypad.onGainJoypadFocus(self, joypadData);
    self:setISButtonForA(self.addBttn);
    self:setISButtonForB(self.cancelBttn);
    self.joypadButtonsY = {};
    self.joypadButtons = {};
    self.joypadIndexY = 1;
    self.joypadIndex = 1;
    self:insertNewLineOfButtons(self.entry);
    self.entry:setJoypadFocused(true, joypadData);
end

function VehicleScriptTextBox:onJoypadDirDown(joypadData)
    self.joypadIndexY = 0;
    self.entry:setJoypadFocused(false, joypadData);
end

function VehicleScriptTextBox:onJoypadDirUp(joypadData)
    self.joypadIndexY = 1;
    self.entry:setJoypadFocused(true, joypadData);
end

function VehicleScriptTextBox:onJoypadDown(button, joypadData)
    if button == Joypad.BButton then
        if self.joypadIndexY == 1 then
            self.joypadIndexY = 0;
            self.entry:setJoypadFocused(false, joypadData);
            return;
        end
    end
    ISPanelJoypad.onJoypadDown(self, button, joypadData);
end

function VehicleScriptTextBox:new(x, y, width, height, text, defaultEntryText, target, onclick, player, param1, param2,
                                  param3, param4)
    local o = {};
    o = ISPanelJoypad:new(x, y, width, height);
    setmetatable(o, self);
    self.__index = self;
    local playerObj = player and getSpecificPlayer(player) or nil;
    if y == 0 then
        if playerObj and playerObj:getJoypadBind() ~= -1 then
            o.y = getPlayerScreenTop(player) + (getPlayerScreenHeight(player) - height) / 2;
        else
            o.y = o:getMouseY() - (height / 2);
        end
        o:setY(o.y);
    end
    if x == 0 then
        if playerObj and playerObj:getJoypadBind() ~= -1 then
            o.x = getPlayerScreenLeft(player) + (getPlayerScreenWidth(player) - width) / 2;
        else
            o.x = o:getMouseX() - (width / 2);
        end
        o:setX(o.x);
    end
    o.name = nil;
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.5 };
    o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 };
    o.width = width;
    local txtWidth = getTextManager():MeasureStringX(UIFont.Small, text) + 10;
    if width < txtWidth then
        o.width = txtWidth;
    end
    o.height = height;
    o.anchorLeft = true;
    o.anchorRight = true;
    o.anchorTop = true;
    o.anchorBottom = true;
    o.text = text;
    o.target = target;
    o.onclick = onclick;
    o.player = player
    o.param1 = param1;
    o.param2 = param2;
    o.param3 = param3;
    o.param4 = param4;
    o.defaultEntryText = defaultEntryText;
    o.titlebarbkg = getTexture("media/ui/Panel_TitleBar.png");
    o.numLines = 1;
    o.maxLines = 1;
    o.multipleLine = false;
    return o;
end

function VehicleScriptTextBox:close()
    ISPanelJoypad.close(self);
    if JoypadState.players[self.player + 1] then
        setJoypadFocus(self.player, nil);
    end
end

return VehicleScriptTextBox;
