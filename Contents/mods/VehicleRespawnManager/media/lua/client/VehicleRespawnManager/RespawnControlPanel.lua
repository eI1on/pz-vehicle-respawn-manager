local Logger = require("VehicleRespawnManager/Logger");
local FileUtils = require("ElyonLib/FileUtils");

local ZONE_TEMPLATE = require("VehicleRespawnManager/ZONE_TEMPLATE");

local VehicleRespawnManager = require("VehicleRespawnManager/Shared");
local VehicleScriptTextBox = require("VehicleRespawnManager/VehicleScriptTextBox");

---@class RespawnControlPanel : ISCollapsableWindowJoypad
local RespawnControlPanel = ISCollapsableWindowJoypad:derive("RespawnControlPanel");

---@type RespawnControlPanel|nil;
RespawnControlPanel.instance = nil;

local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium);

local font_size, scale = getCore():getOptionFontSize() or 1, { 1, 1.3, 1.65, 1.95, 2.3 };
RespawnControlPanel.scale = scale[font_size];

function RespawnControlPanel.openPanel()
    if RespawnControlPanel.instance then
        RespawnControlPanel.instance:close();
        return;
    end

    local playerObj = getPlayer();
    local modData = playerObj:getModData();
    local savedPosition = modData.VRMPosition or {};

    local screenWidth = getCore():getScreenWidth();
    local screenHeight = getCore():getScreenHeight();
    local width, height = 700, 650;

    width = savedPosition.width or width;
    height = savedPosition.height or height;
    local x = math.max(0, math.min(savedPosition.x or (screenWidth - width) / 2, screenWidth - width));
    local y = math.max(0, math.min(savedPosition.y or (screenHeight - height) / 2, screenHeight - height));

    ---@diagnostic disable-next-line: assign-type-mismatch
    RespawnControlPanel.instance = RespawnControlPanel:new(x, y, width, height, playerObj);
    RespawnControlPanel.instance:initialise();
    RespawnControlPanel.instance:addToUIManager();

    if JoypadState.players[RespawnControlPanel.instance.playerNum + 1] then
        setJoypadFocus(RespawnControlPanel.instance.playerNum, RespawnControlPanel.instance);
    end
end

local ISDebugMenu_setupButtons = ISDebugMenu.setupButtons;
function ISDebugMenu:setupButtons()
    sendClientCommand("VehicleRespawnManager", "LoadZones", {});
    self:addButtonInfo("Vehicle Respawn Manager", function() RespawnControlPanel.openPanel() end, "MAIN");
    ISDebugMenu_setupButtons(self);
end

local ISAdminPanelUI_create = ISAdminPanelUI.create;
function ISAdminPanelUI:create()
    ISAdminPanelUI_create(self);
    local fontHeight = getTextManager():getFontHeight(UIFont.Small);
    local btnWid = 150;
    local btnHgt = math.max(25, fontHeight + 3 * 2);
    local btnGapY = 5;

    local lastButton = self.children[self.IDMax - 1];
    lastButton = lastButton.internal == "CANCEL" and self.children[self.IDMax - 2] or lastButton;

    sendClientCommand("VehicleRespawnManager", "LoadZones", {});

    self.showVehicleRespawnManager = ISButton:new(lastButton.x, lastButton.y + btnHgt + btnGapY, btnWid, btnHgt,
        "Vehicle Respawn Manager", self, RespawnControlPanel.openPanel);
    self.showVehicleRespawnManager.internal = "";
    self.showVehicleRespawnManager:initialise();
    self.showVehicleRespawnManager:instantiate();
    self.showVehicleRespawnManager.borderColor = self.buttonBorderColor;
    self:addChild(self.showVehicleRespawnManager);
end

function RespawnControlPanel:new(x, y, width, height, player)
    local o = ISCollapsableWindowJoypad.new(self, x, y, width, height);

    o:setResizable(true);
    o.character           = player;
    o.playerNum           = player and player:getPlayerNum() or -1;
    o.title               = getText("IGUI_VRM_Title");
    o.minimumWidth        = 700;
    o.minimumHeight       = 650;

    o.vehicleRespawnZones = VehicleRespawnManager.Shared.RequestZones();

    return o;
end

function RespawnControlPanel:setupExportImportButtons(th, padding)
    local buttonWidth = (self:getWidth() / 3 - 2 * padding - padding) / 2;
    self.importButton = self:createButton(
        self:getWidth() - buttonWidth - padding,
        th + padding, buttonWidth, 20, getText("IGUI_VRM_Import"),
        self.onImport
    );
    self.importButton.borderColor = { r = 0.2, g = 0.6, b = 0.9, a = 1 };
    self.exportButton = self:createButton(
        self.importButton:getX() - buttonWidth - padding,
        th + padding, buttonWidth, 20, getText("IGUI_VRM_Export"),
        self.onExport
    );
    self.exportButton.borderColor = { r = 0.2, g = 0.6, b = 0.9, a = 1 };
end

function RespawnControlPanel:setupCoordinateInputs(padding)
    local xBase = self:getWidth() * 0.625;
    local yBase = self.zoneNameComboBox:getY();
    local halfPadding = padding / 2;

    self.coordsErrorLabel = self:createLabel(self.importButton:getX() - halfPadding, yBase - halfPadding, "");
    self.coordsErrorLabel.center = true;
    self.x1Label, self.x1Input = self:setupCoordinateField(xBase, self.coordsErrorLabel:getBottom() + halfPadding,
        getText("IGUI_VRM_X1"), "x1");
    self.y1Label, self.y1Input = self:setupCoordinateField(self:getWidth() * 0.75,
        self.coordsErrorLabel:getBottom() + halfPadding, getText("IGUI_VRM_Y1"), "y1");
    self.x2Label, self.x2Input = self:setupCoordinateField(xBase, self.x1Label:getBottom() + halfPadding,
        getText("IGUI_VRM_X2"), "x2");
    self.y2Label, self.y2Input = self:setupCoordinateField(self:getWidth() * 0.75, self.x1Label:getBottom() + halfPadding,
        getText("IGUI_VRM_Y2"), "y2");

    self.x1Input.tooltip = getText("IGUI_VRM_CoordsInputs_tooltip");
    self.y1Input.tooltip = getText("IGUI_VRM_CoordsInputs_tooltip");
    self.x2Input.tooltip = getText("IGUI_VRM_CoordsInputs_tooltip");
    self.y2Input.tooltip = getText("IGUI_VRM_CoordsInputs_tooltip");
end

function RespawnControlPanel:setupCoordinateField(x, y, labelText, coordType)
    local label = self:createLabel(x, y, labelText);
    local input = self:createTextInput(label:getRight() + 10, y);
    input.coordType = coordType;
    input.onTextChange = self.onCoordsInputChange;
    input:setOnlyNumbers(true);
    return label, input;
end

function RespawnControlPanel:setupZoneNameComboBox(th, padding)
    self.zoneNameLabel = self:createLabel(padding, th + padding, getText("IGUI_VRM_ZoneName"));
    self.zoneNameComboBox = self:createComboBox(padding, self.zoneNameLabel:getBottom() + padding, 0.375);
    self.zoneNameComboBox:setEditable(true);
    self.zoneNameComboBox.onChange = self.onChangeZoneNameBox;
    self.zoneNameComboBox.onMouseUp = self.onMouseUpZoneNameBox;
    self.zoneNameComboBox.target = self;
    local map = {};
    map["defaultTooltip"] = getText("IGUI_VRM_ZoneCombobox_tooltip");
    self.zoneNameComboBox:setToolTipMap(map);

    local buttonWidth = (self.zoneNameComboBox:getWidth() - padding) / 2;
    self.addZoneButton = self:createButton(
        padding, self.zoneNameComboBox:getBottom() + padding, buttonWidth, 25,
        getText("IGUI_VRM_AddZone"), self.onAddZone
    );
    self.addZoneButton.borderColor = { r = 0.2, g = 0.6, b = 0.9, a = 1 };
    self.addZoneButton.tooltip = getText("IGUI_VRM_AddZone_tooltip");

    self.removeZoneButton = self:createButton(
        self.addZoneButton:getRight() + padding, self.addZoneButton:getY(),
        buttonWidth, 25, getText("IGUI_VRM_RemoveZone"), self.onRemoveZone
    );
    self.removeZoneButton.borderColor = { r = 0.2, g = 0.6, b = 0.9, a = 1 };
    self.removeZoneButton.tooltip = getText("IGUI_VRM_RemoveZone_tooltip");
end

function RespawnControlPanel:createChildren()
    ISCollapsableWindowJoypad.createChildren(self);
    local th, padding, bttnHeight = self:titleBarHeight(), 10, 25;


    self:setupExportImportButtons(th, padding);
    self:setupZoneNameComboBox(th, padding);

    self.zoneOptionsTickBox = self:createTickBox(
        self.zoneNameComboBox:getRight() + padding, self.zoneNameComboBox:getY(),
        { getText("IGUI_VRM_ZoneIsGlobal"), getText("IGUI_VRM_ZoneIsBlacklist") }
    );
    self.zoneOptionsTickBox.changeOptionTarget = self;
    self.zoneOptionsTickBox.changeOptionMethod = self.onTickBoxZoneOptions;
    self.zoneOptionsTickBox.tooltip = getText("IGUI_VRM_ZoneOptions_tooltip");

    self:setupCoordinateInputs(padding);

    local twoThirdsListWidth = self:getWidth() * 2 / 3;

    local categoriesLabelX = padding + twoThirdsListWidth / 4;
    local categoriesLabelY = self.addZoneButton:getBottom() + padding;
    self.vehicleCategoriesLabel = self:createLabel(categoriesLabelX, categoriesLabelY,
        getText("IGUI_VRM_VehiclesCategories")
    );
    self.vehicleCategoriesLabel.center = true;


    local spawnRatesLabelX = padding + (twoThirdsListWidth / 4) * 3;
    local spawnRatesLabelY = categoriesLabelY;
    self.spawnRatesLabel = self:createLabel(spawnRatesLabelX, spawnRatesLabelY, getText("IGUI_VRM_SpawnRates"));
    self.spawnRatesLabel.center = true;


    self.vehiclesCategoriesList = self:createScrollingListBox(
        padding,
        self.vehicleCategoriesLabel:getBottom(),
        twoThirdsListWidth,
        150
    );
    self.vehiclesCategoriesList:setFont(UIFont.Medium, 7);
    self.vehiclesCategoriesList.doDrawItem = self.drawVehiclesCategoriesListItem;
    self.vehiclesCategoriesList.onMouseDown = self.onVehiclesCategoriesListMouseDown;
    self.vehiclesCategoriesList.onMouseMove = self.onVehiclesCategoriesListMouseMove;
    self.vehiclesCategoriesList.onMouseUp = self.onVehiclesCategoriesListMouseUp;

    self.vehiclesCategoriesList.onmousedown = self.onVehiclesCategoriesListmousedown;
    self.vehiclesCategoriesList.target = self;
    self:addVehicleCategoryButtons();


    local oneThirdListWidth = self:getWidth() / 3 - 2 * padding;

    self.vehiclesAssignedLabel = self:createLabel(
        self.vehiclesCategoriesList:getRight() + oneThirdListWidth / 2,
        self.vehicleCategoriesLabel:getY(),
        getText("IGUI_VRM_VehiclesAssigned")
    );
    self.vehiclesAssignedLabel.center = true;

    self.vehiclesAssignedList = self:createScrollingListBox(
        self.vehiclesCategoriesList:getRight(),
        self.vehiclesCategoriesList:getY(),
        oneThirdListWidth,
        150
    );
    self.vehiclesAssignedList:setFont(UIFont.Small, 7);
    self.vehiclesAssignedList.onmousedown = self.onVehiclesAssignedListMouseDown;
    self.vehiclesAssignedList.target = self;
    self:addVehicleAssignmentButtons();


    self.blacklistedVehiclesLabel = self:createLabel(
        self.addBatchVehiclesButton:getX() + (self:getWidth() / 3 - 2 * padding) / 2,
        self.addBatchVehiclesButton:getBottom() + padding, getText("IGUI_VRM_Blacklist")
    );
    self.blacklistedVehiclesLabel.center = true;


    self.blacklistedVehiclesList = self:createScrollingListBox(
        self.addBatchVehiclesButton:getX(),
        self.blacklistedVehiclesLabel:getBottom(),
        oneThirdListWidth,
        150
    );
    self.blacklistedVehiclesList:setFont(UIFont.Small, 7);
    self.blacklistedVehiclesList.onmousedown = self.onBlacklistedVehiclesListMouseDown;
    self.blacklistedVehiclesList.target = self;
    self:addBlacklistedVehiclesButtons();

    self:addDefaultCategoryOptions();

    self:addManualVehicleSpawn();

    self:populateElements();
end

function RespawnControlPanel:prerender()
    ISCollapsableWindowJoypad.prerender(self);

    if self.refresh and self.refresh > 0 then
        self.refresh = self.refresh - 1;
        if self.refresh <= 0 then
            self:populateElements();
        end
    end
end

function RespawnControlPanel:render()
    self:drawRectBorder(10, self.maxVehiclesPerZoneLabel:getBottom() + 3 * 10,
        self.spawnVehicleScriptLabel:getRight() + 10,
        (self.spawnManualVehicleButton:getBottom() + 10) - (self.maxVehiclesPerZoneLabel:getBottom() + 3 * 10),
        0.5, 1.0, 1.0, 1.0
    );

    ISCollapsableWindowJoypad.render(self);
end

function RespawnControlPanel:getSelectedZoneZoneIdx()
    return self.zoneNameComboBox and self.zoneNameComboBox.selected;
end

function RespawnControlPanel:getSelectedZoneData()
    local selected = self:getSelectedZoneZoneIdx();
    local options = self.zoneNameComboBox.options;

    if not selected or not options[selected] then return nil; end

    return options[selected].data;
end

function RespawnControlPanel:populateElements()
    self.vehicleRespawnZones = VehicleRespawnManager.Shared.RequestZones();

    self:populateZoneComboBox();

    self.addZoneButton:setEnable(true);

    local zoneData = self:getSelectedZoneData();
    if zoneData then
        self.removeZoneButton:setEnable(true);

        self.zoneOptionsTickBox.enable = true;
        self.zoneOptionsTickBox.selected[1] = zoneData.isGlobalZone;
        self.zoneOptionsTickBox.selected[2] = zoneData.isBlacklistZone;

        local optionNames = {
            getText("IGUI_VRM_ZoneIsGlobal"),
            getText("IGUI_VRM_ZoneIsBlacklist")
        }

        if zoneData.isGlobalZone then
            self.zoneOptionsTickBox:disableOption(optionNames[2], true)
        elseif zoneData.isBlacklistZone then
            self.zoneOptionsTickBox:disableOption(optionNames[1], true)
        else
            self.zoneOptionsTickBox:disableOption(optionNames[1], false)
            self.zoneOptionsTickBox:disableOption(optionNames[2], false)
        end

        self.x1Input:setEditable(true);
        self.x1Input:setSelectable(true);
        self.x1Input:setText(tostring(zoneData.coordinates.x1));

        self.y1Input:setEditable(true);
        self.y1Input:setSelectable(true);
        self.y1Input:setText(tostring(zoneData.coordinates.y1));

        self.x2Input:setEditable(true);
        self.x2Input:setSelectable(true);
        self.x2Input:setText(tostring(zoneData.coordinates.x2));

        self.y2Input:setEditable(true);
        self.y2Input:setSelectable(true);
        self.y2Input:setText(tostring(zoneData.coordinates.y2));

        self.defaultCatUnassignedVehiclesTickBox.enable = true;
        self.defaultCatUnassignedVehiclesTickBox.selected[1] = zoneData.useDefaultCategoryForUnassigned;

        self.currentDefaultCategoryLabel:setName(getText("IGUI_VRM_CurrentDefaultCatForUnassignedVehicles",
            zoneData.defaultCategoryNameForUnassigned)
        );

        self.maxVehiclesPerZoneInput:setEditable(true);
        self.maxVehiclesPerZoneInput:setSelectable(true);
        self.maxVehiclesPerZoneInput:setText(tostring(zoneData.maxVehicleCount));
    else
        self.removeZoneButton:setEnable(false);

        self.zoneOptionsTickBox.enable = false;
        self.zoneOptionsTickBox.selected[1] = false;
        self.zoneOptionsTickBox.selected[2] = false;

        local optionNames = {
            getText("IGUI_VRM_ZoneIsGlobal"),
            getText("IGUI_VRM_ZoneIsBlacklist")
        };
        self.zoneOptionsTickBox:disableOption(optionNames[1], false);
        self.zoneOptionsTickBox:disableOption(optionNames[2], false);

        self.x1Input:setEditable(false);
        self.x1Input:setSelectable(false);
        self.x1Input:setText("");

        self.y1Input:setEditable(false);
        self.y1Input:setSelectable(false);
        self.y1Input:setText("");

        self.x2Input:setEditable(false);
        self.x2Input:setSelectable(false);
        self.x2Input:setText("");

        self.y2Input:setEditable(false);
        self.y2Input:setSelectable(false);
        self.y2Input:setText("");

        self.defaultCatUnassignedVehiclesTickBox.enable = false;
        self.defaultCatUnassignedVehiclesTickBox.selected[1] = false;

        self.currentDefaultCategoryLabel:setName(getText("IGUI_VRM_CurrentDefaultCatForUnassignedVehicles", "None"));

        self.maxVehiclesPerZoneInput:setEditable(false);
        self.maxVehiclesPerZoneInput:setSelectable(false);
        self.maxVehiclesPerZoneInput:setText("");
    end


    self:populateVehiclesCategoriesList();

    if self:getSelectedZoneZoneIdx() > 0 then
        self.addCategoryButton:setEnable(true);
    else
        self.addCategoryButton:setEnable(false);
    end

    if self.vehiclesCategoriesList.count > 0 then
        self.removeCategoryButton:setEnable(true);
        if self.defaultCatUnassignedVehiclesTickBox:isSelected(1) then
            self.setDefaultCategoryButton:setEnable(true);
        end
    else
        self.removeCategoryButton:setEnable(false);
        if not self.defaultCatUnassignedVehiclesTickBox:isSelected(1) then
            self.setDefaultCategoryButton:setEnable(false);
        end
    end


    self:populateVehiclesAssignedList();

    if self.vehiclesCategoriesList.count > 0 then
        self.addVehicleButton:setEnable(true);
        self.addBatchVehiclesButton:setEnable(true);
    else
        self.addVehicleButton:setEnable(false);
        self.addBatchVehiclesButton:setEnable(false);
    end

    if self.vehiclesAssignedList.count > 0 then
        self.removeVehicleButton:setEnable(true);
    else
        self.removeVehicleButton:setEnable(false);
    end


    self:populateBlacklistedVehiclesList();

    if self:getSelectedZoneZoneIdx() > 0 then
        self.addBlacklistVehicleButton:setEnable(true);
        self.addBatchBlacklistVehiclesButton:setEnable(true);
    else
        self.addBlacklistVehicleButton:setEnable(false);
        self.addBatchBlacklistVehiclesButton:setEnable(false);
    end

    if self.blacklistedVehiclesList.count > 0 then
        self.removeBlacklistVehicleButton:setEnable(true);
    else
        self.removeBlacklistVehicleButton:setEnable(false);
    end
end

function RespawnControlPanel:getSelectedCategoriesList()
    local selected = self.vehiclesCategoriesList.selected;
    local options = self.vehiclesCategoriesList.items;

    if not selected or not options[selected] then return nil; end

    return options[selected];
end

function RespawnControlPanel:populateZoneComboBox()
    self.zoneNameComboBox:clear();
    if self.vehicleRespawnZones and #self.vehicleRespawnZones > 0 then
        for i = 1, #self.vehicleRespawnZones do
            self.zoneNameComboBox:addOptionWithData(self.vehicleRespawnZones[i].name, self.vehicleRespawnZones[i]);
        end
    end
end

function RespawnControlPanel:populateVehiclesCategoriesList()
    self.vehiclesCategoriesList:clear();
    local zoneData = self:getSelectedZoneData();
    if zoneData then
        for key, category in pairs(zoneData.vehicleSpawnCategories) do
            self.vehiclesCategoriesList:addItem(category.name,
                { key = key, vehicles = category.vehicles, spawnRate = category.spawnRate });
        end
    end
end

function RespawnControlPanel:populateVehiclesAssignedList(vehiclesCategoriesItem)
    self.vehiclesAssignedList:clear();
    local selectedCategoriesList = self:getSelectedCategoriesList();
    local selectedCategoriesItem = nil;
    if vehiclesCategoriesItem then
        selectedCategoriesItem = vehiclesCategoriesItem;
    elseif selectedCategoriesList then
        selectedCategoriesItem = selectedCategoriesList.item;
    end

    if selectedCategoriesItem then
        for key, value in pairs(selectedCategoriesItem.vehicles) do
            self.vehiclesAssignedList:addItem(key);
        end
    end
end

function RespawnControlPanel:populateBlacklistedVehiclesList()
    self.blacklistedVehiclesList:clear();

    local zoneData = self:getSelectedZoneData();

    if zoneData then
        for key, value in pairs(zoneData.zoneVehicleBlacklist) do
            self.blacklistedVehiclesList:addItem(key);
        end
    end
end

function RespawnControlPanel:drawVehiclesCategoriesListItem(y, item, alt)
    if not item.height then item.height = self.itemheight; end

    if self.selected == item.index then
        self:drawRect(0, y, self:getWidth(), item.height - 1, 0.3, 0.7, 0.35, 0.15);
    end

    self:drawRectBorder(0, y, self:getWidth(), item.height, 0.5, self.borderColor.r, self.borderColor.g,
        self.borderColor.b);

    local itemPadY = self.itemPadY or (item.height - self.fontHgt) / 2;
    self:drawText(item.text, 15, y + itemPadY, 0.9, 0.9, 0.9, 0.9, self.font);

    local sliderX = self:getWidth() / 2;
    local sliderWidth = self:getWidth() / 3;
    local sliderHeight = 10;
    local sliderY = y + (item.height / 2) - (sliderHeight / 2);
    local value = item.item.spawnRate or 0;

    self:drawRect(sliderX, sliderY, sliderWidth, sliderHeight, 0.4, 0.3, 0.3, 0.3);

    local handleX = sliderX + (sliderWidth * (value / 100)) - 5;
    self:drawRect(handleX, sliderY - 2, 10, sliderHeight + 4, 1, 0.2, 0.6, 0.9);

    local textPadding = 10;
    local rateText = string.format("%d%%", math.floor(value));
    local rateX = sliderX + sliderWidth + textPadding;
    self:drawText(rateText, rateX, sliderY - (self.fontHgt / 2) + (sliderHeight / 2), 0.9, 0.9, 0.9, 0.9, self.font);

    y = y + item.height;
    return y;
end

function RespawnControlPanel:onVehiclesCategoriesListMouseDown(x, y)
    if self.items and #self.items == 0 then return; end
    -- if #self.items == 1 then return; end

    local row = self:rowAt(x, y);

    if row > #self.items then
        row = #self.items;
    end
    if row < 1 then
        row = 1;
    end

    local function getRowY(row)
        return (row - 1) * self.itemheight - (self.vscroll and self.vscroll.pos or 0);
    end

    local item = self.items[row].item;
    local itemY = getRowY(row);

    local sliderX = self:getWidth() / 2;
    local sliderWidth = self:getWidth() / 3;
    local sliderHeight = 10;
    local sliderY = itemY + (self.itemheight / 2) - (sliderHeight / 2);

    local value = item.spawnRate or 0;
    local handleX = sliderX + (sliderWidth * (value / 100)) - 5;
    local handleWidth = 10;
    local handleHeight = sliderHeight + 4;
    local handleY = sliderY - 2;

    if x >= handleX and x <= handleX + handleWidth and y >= handleY and y <= handleY + handleHeight then
        self.draggingSlider = {
            item = item,
            sliderX = sliderX,
            sliderWidth = sliderWidth,
            initialMouseX = x,
            initialValue = value
        };
        return;
    end

    getSoundManager():playUISound("UISelectListItem");
    self.selected = row;
    if self.onmousedown then
        self.onmousedown(self.target, item);
    end
end

function RespawnControlPanel:onVehiclesCategoriesListmousedown(target, item)
    self:populateVehiclesAssignedList(item);
end

function RespawnControlPanel:onVehiclesCategoriesListMouseMove(dx, dy)
    -- self.parent:normalizeSpawnRates();

    if self.draggingSlider then
        local slider = self.draggingSlider;
        local mouseX = self:getMouseX();
        local delta = mouseX - slider.initialMouseX;
        local newValue = math.max(0, math.min(100, slider.initialValue + (delta / slider.sliderWidth) * 100));
        slider.item.spawnRate = newValue;
        return;
    end
    if self:isMouseOverScrollBar() then return; end
    self.mouseoverselected = self:rowAt(self:getMouseX(), self:getMouseY());
end

function RespawnControlPanel:onVehiclesCategoriesListMouseUp(x, y)
    -- local changes = self.parent:normalizeSpawnRates();

    if self.draggingSlider then
        self.parent:sendSpawnRateUpdate();
    end

    self.draggingSlider = nil;
    if self.vscroll then
        self.vscroll.scrolling = false;
    end
end

function RespawnControlPanel:normalizeSpawnRates()
    local total = 0;
    local items = self.vehiclesCategoriesList.items;
    local changed = false;

    for i = 1, #items do
        local item = items[i];
        total = total + (item.item.spawnRate or 0);
    end

    if total == 0 then
        local equalShare = 100 / #items;
        for i = 1, #items do
            local item = items[i];
            if item.item.spawnRate ~= equalShare then
                item.item.spawnRate = equalShare;
                changed = true;
            end
        end
        return changed;
    end

    local scaledRates = {};
    for i = 1, #items do
        local item = items[i];
        local rate = item.item.spawnRate or 0;
        local scaledRate = (rate / total) * 100;
        table.insert(scaledRates, math.floor(scaledRate));
    end

    local adjustedTotal = 0;
    for i = 1, #scaledRates do
        local rate = scaledRates[i];
        adjustedTotal = adjustedTotal + rate;
    end

    local difference = 100 - adjustedTotal;
    for i = 1, math.abs(difference) do
        local index = (i % #scaledRates) + 1;
        if difference > 0 then
            scaledRates[index] = scaledRates[index] + 1;
        elseif difference < 0 then
            scaledRates[index] = math.max(0, scaledRates[index] - 1);
        end
    end

    for i = 1, #items do
        local item = items[i];
        if item.item.spawnRate ~= scaledRates[i] then
            item.item.spawnRate = scaledRates[i];
            changed = true;
        end
    end

    return changed;
end

function RespawnControlPanel:sendSpawnRateUpdate()
    local selectedZoneIdx = self:getSelectedZoneZoneIdx();
    local items = self.vehiclesCategoriesList.items;

    for i = 1, #items do
        local item = items[i];
        local key = item.item.key;
        local spawnRate = math.floor(item.item.spawnRate) or 0;

        sendClientCommand("VehicleRespawnManager", "EditZoneData",
            {
                selectedIdx = selectedZoneIdx,
                newKey = "vehicleSpawnCategories." .. key .. ".spawnRate",
                newValue = spawnRate
            }
        );
    end
end

function RespawnControlPanel:createLabel(x, y, text)
    local label = ISLabel:new(x, y, getTextManager():MeasureStringY(UIFont.Medium, text), text, 1, 1, 1, 1, UIFont
        .Medium, true);
    label:initialise();
    label:instantiate();
    self:addChild(label);
    return label;
end

function RespawnControlPanel:createComboBox(x, y, widthRatio)
    local dropdown = ISComboBox:new(x, y, self:getWidth() * widthRatio, 30, self, nil);
    dropdown:initialise();
    dropdown:instantiate();
    self:addChild(dropdown);
    return dropdown;
end

function RespawnControlPanel:createButton(x, y, width, height, text, onClick)
    local button = ISButton:new(x, y, width, height, text, self, onClick);
    button:initialise();
    button:instantiate();
    self:addChild(button);
    return button;
end

function RespawnControlPanel:createTickBox(x, y, options)
    local tickBox = ISTickBox:new(x, y, 0, 30, "", self, nil);
    for i = 1, #options do
        tickBox:addOption(options[i]);
    end
    tickBox:setFont(UIFont.Medium);
    tickBox:setWidthToFit();
    self:addChild(tickBox);
    return tickBox;
end

function RespawnControlPanel:createScrollingListBox(x, y, width, height)
    local listBox = ISScrollingListBox:new(x, y, width, height);
    listBox:initialise();
    listBox:instantiate();
    listBox.joypadParent = self;
    listBox.drawBorder = true;
    listBox.mainUI = self;
    self:addChild(listBox);
    return listBox;
end

function RespawnControlPanel:createTextInput(x, y)
    local textBox = ISTextEntryBox:new("", x, y, 50, 20);
    textBox:initialise();
    textBox:instantiate();
    self:addChild(textBox);
    return textBox;
end

function RespawnControlPanel:addVehicleCategoryButtons()
    local buttonWidth = self.vehiclesCategoriesList:getWidth() / 4;
    local bttnHeight = 25;
    self.addCategoryButton = self:createButton(self.vehiclesCategoriesList:getX(),
        self.vehiclesCategoriesList:getBottom() + 10, buttonWidth, bttnHeight, getText("IGUI_VRM_AddCategory"),
        self.onAddCategoryModal
    );
    self.addCategoryButton.borderColor = { r = 0.2, g = 0.6, b = 0.9, a = 1 };
    self.addCategoryButton.tooltip = getText("IGUI_VRM_AddCategory_tooltip");

    self.removeCategoryButton = self:createButton(self.addCategoryButton:getRight() + 10,
        self.vehiclesCategoriesList:getBottom() + 10, buttonWidth, bttnHeight, getText("IGUI_VRM_RemoveCategory"),
        self.onRemoveCategory
    );
    self.removeCategoryButton.borderColor = { r = 0.2, g = 0.6, b = 0.9, a = 1 };
    self.removeCategoryButton.tooltip = getText("IGUI_VRM_RemoveCategory_tooltip");
end

function RespawnControlPanel:addVehicleAssignmentButtons()
    local padding = 10;
    local bttnHeight = 25;
    local buttonWidth = (self.vehiclesAssignedList:getWidth() - padding) / 2;

    self.addVehicleButton = self:createButton(self.vehiclesAssignedList:getX(),
        self.vehiclesAssignedList:getBottom() + padding, buttonWidth, bttnHeight, getText("IGUI_VRM_AddVehicle"),
        self.onAddVehicleModal
    );
    self.addVehicleButton.borderColor = { r = 0.2, g = 0.6, b = 0.9, a = 1 };
    self.addVehicleButton.tooltip = getText("IGUI_VRM_AddVehicle_tooltip");

    self.addBatchVehiclesButton = self:createButton(self.addVehicleButton:getX(),
        self.addVehicleButton:getBottom() + padding, buttonWidth, bttnHeight, getText("IGUI_VRM_BatchAddVehicle"),
        self.onAddBatchVehicleModal
    );
    self.addBatchVehiclesButton.borderColor = { r = 0.2, g = 0.6, b = 0.9, a = 1 };
    self.addBatchVehiclesButton.tooltip = getText("IGUI_VRM_AddVehicle_tooltip");

    self.removeVehicleButton = self:createButton(self.addVehicleButton:getRight() + padding,
        self.vehiclesAssignedList:getBottom() + padding, buttonWidth, bttnHeight, getText("IGUI_VRM_RemoveVehicle"),
        self.onRemoveVehicle
    );
    self.removeVehicleButton.borderColor = { r = 0.2, g = 0.6, b = 0.9, a = 1 };
    self.removeVehicleButton.tooltip = getText("IGUI_VRM_RemoveVehicle_tooltip");
end

function RespawnControlPanel:addBlacklistedVehiclesButtons()
    local padding = 10;
    local bttnHeight = 25;
    local buttonWidth = (self.blacklistedVehiclesList:getWidth() - padding) / 2;

    self.addBlacklistVehicleButton = self:createButton(self.blacklistedVehiclesList:getX(),
        self.blacklistedVehiclesList:getBottom() + padding, buttonWidth, bttnHeight, getText("IGUI_VRM_AddBlacklist"),
        self.onAddBlacklistVehicleModal);
    self.addBlacklistVehicleButton.borderColor = { r = 0.2, g = 0.6, b = 0.9, a = 1 };
    self.addBlacklistVehicleButton.tooltip = getText("IGUI_VRM_AddBlacklist_tooltip");

    self.addBatchBlacklistVehiclesButton = self:createButton(self.addBlacklistVehicleButton:getX(),
        self.addBlacklistVehicleButton:getBottom() + padding, buttonWidth, bttnHeight,
        getText("IGUI_VRM_BatchAddBlacklist"), self.onAddBatchBlacklistVehicleModal);
    self.addBatchBlacklistVehiclesButton.borderColor = { r = 0.2, g = 0.6, b = 0.9, a = 1 };
    self.addBatchBlacklistVehiclesButton.tooltip = getText("IGUI_VRM_AddBlacklist_tooltip");

    self.removeBlacklistVehicleButton = self:createButton(self.addBlacklistVehicleButton:getRight() + padding,
        self.blacklistedVehiclesList:getBottom() + padding, buttonWidth, bttnHeight, getText("IGUI_VRM_RemoveBlacklist"),
        self.onRemoveBlacklistVehicle);
    self.removeBlacklistVehicleButton.borderColor = { r = 0.2, g = 0.6, b = 0.9, a = 1 };
    self.removeBlacklistVehicleButton.tooltip = getText("IGUI_VRM_RemoveBlacklist_tooltip");
end

function RespawnControlPanel:addDefaultCategoryOptions()
    local padding = 10;
    local buttonWidth = self.vehiclesCategoriesList:getWidth() / 4;
    local bttnHeight = 25;

    self.defaultCatUnassignedVehiclesTickBox = self:createTickBox(padding, self.addCategoryButton:getBottom() + 2 *
        padding, { getText("IGUI_VRM_DefaultCatForUnassignedVehicles") }
    );
    self.defaultCatUnassignedVehiclesTickBox.changeOptionTarget = self;
    self.defaultCatUnassignedVehiclesTickBox.changeOptionMethod = self.onTickBoxDefaultCatUnassignedVehicles;
    self.defaultCatUnassignedVehiclesTickBox.tooltip = getText("IGUI_VRM_DefaultCatForUnassignedVehicles_tooltip");

    self.setDefaultCategoryButton = self:createButton(padding,
        self.defaultCatUnassignedVehiclesTickBox:getBottom() + padding, buttonWidth, bttnHeight,
        getText("IGUI_VRM_SetDefaultCat"), self.onSetDefaultCategory
    );
    self.setDefaultCategoryButton.borderColor = { r = 0.2, g = 0.6, b = 0.9, a = 1 };
    self.setDefaultCategoryButton.tooltip = getText("IGUI_VRM_SetDefaultCat_tooltip");

    self.currentDefaultCategoryLabel = self:createLabel(self.setDefaultCategoryButton:getRight() + padding,
        self.setDefaultCategoryButton:getY(), getText("IGUI_VRM_CurrentDefaultCatForUnassignedVehicles", "None")
    );
    self.currentDefaultCategoryLabel:setHeight(self.setDefaultCategoryButton:getHeight());

    self.maxVehiclesPerZoneLabel = self:createLabel(padding, self.setDefaultCategoryButton:getBottom() + padding,
        getText("IGUI_VRM_MaxVehiclesPerZone")
    );
    self.maxVehiclesPerZoneLabel:setHeight(25);

    self.maxVehiclesPerZoneInput = self:createTextInput(self.maxVehiclesPerZoneLabel:getRight() + padding,
        self.maxVehiclesPerZoneLabel:getY()
    );
    self.maxVehiclesPerZoneInput.onTextChange = self.onMaxVehiclesPerZoneInputChange;
    self.maxVehiclesPerZoneInput:setHeight(25);
    self.maxVehiclesPerZoneInput:setOnlyNumbers(true);
end

function RespawnControlPanel:addManualVehicleSpawn()
    local padding = 10;
    local bttnHeight = 25;

    self.manualVehicleSpawnLabel = self:createLabel(2 * padding, self.maxVehiclesPerZoneLabel:getBottom() + 2 * padding,
        getText("IGUI_VRM_ManualVehicleSpawn"));
    self.manualVehicleSpawnLabel.backgroundColor = { r = 0, g = 0, b = 0, a = 1 };


    self.vehicleSpawnMethodLabel = self:createLabel(3 * padding, self.manualVehicleSpawnLabel:getBottom() + padding,
        getText("IGUI_VRM_SpawnMethod"));
    self.vehicleSpawnMethodLabel.font = UIFont.Small;
    self.vehicleSpawnMethodLabel:setWidth(getTextManager():MeasureStringX(UIFont.Small, getText("IGUI_VRM_SpawnMethod")));

    self.vehicleSpawnMethodRadioBttn = ISRadioButtons:new(3 * padding,
        self.vehicleSpawnMethodLabel:getBottom() + padding / 2,
        self.vehicleSpawnMethodLabel:getWidth(), 20, self, self.onChangeVehicleSpawnMethod);
    self.vehicleSpawnMethodRadioBttn.choicesColor = { r = 1, g = 1, b = 1, a = 1 };
    self.vehicleSpawnMethodRadioBttn:initialise();
    self.vehicleSpawnMethodRadioBttn:instantiate();
    self.vehicleSpawnMethodRadioBttn.autoWidth = true;
    self:addChild(self.vehicleSpawnMethodRadioBttn);
    self.vehicleSpawnMethodRadioBttn:addOption(getText("IGUI_VRM_SpawnMethodRandom"));
    self.vehicleSpawnMethodRadioBttn:addOption(getText("IGUI_VRM_SpawnMethodFixed"));
    self.vehicleSpawnMethodRadioBttn:setSelected(1);
    self.vehicleSpawnMethodRadioBttn.tooltip = getText("IGUI_VRM_SpawnMethod_tooltip");


    self.spawnCountLabel = self:createLabel(self.vehicleSpawnMethodLabel:getRight() + padding,
        self.vehicleSpawnMethodLabel:getY(),
        getText("IGUI_VRM_SpawnCount"));
    self.spawnCountLabel.font = UIFont.Small;
    self.spawnCountLabel:setWidth(getTextManager():MeasureStringX(UIFont.Small, getText("IGUI_VRM_SpawnCount")));

    self.spawnCountInput = self:createTextInput(self.spawnCountLabel:getX(),
        self.vehicleSpawnMethodRadioBttn:getY()
    );
    self.spawnCountInput:setWidth(self.spawnCountLabel:getWidth());
    self.spawnCountInput.onTextChange = function()

    end;
    self.spawnCountInput:setText("1");
    self.spawnCountInput:setHeight(20);
    self.spawnCountInput:setOnlyNumbers(true);



    self.spawnVehicleScriptLabel = self:createLabel(self.spawnCountLabel:getRight() + padding,
        self.spawnCountLabel:getY(), getText("IGUI_VRM_SpawnVehicleScript"));
    self.spawnVehicleScriptLabel.font = UIFont.Small;
    self.spawnVehicleScriptLabel:setWidth(getTextManager():MeasureStringX(UIFont.Small,
        getText("IGUI_VRM_SpawnVehicleScript")));

    self.spawnVehicleInput = self:createTextInput(self.spawnVehicleScriptLabel:getX(),
        self.spawnVehicleScriptLabel:getBottom() + padding / 2
    );
    self.spawnVehicleInput:setWidth(self.spawnVehicleScriptLabel:getWidth());
    self.spawnVehicleInput.onTextChange = function()
        local text = self.spawnVehicleInput:getInternalText():trim();

        local isValid = true;
        isValid = VehicleRespawnManager.Shared.VehicleScripts[text] and not string.match(text, "[^%w%._%-]");

        if not isValid then
            self.spawnManualVehicleButton:setEnable(false);
            self.spawnManualVehicleButton.tooltip = getText("IGUI_VRM_InvalidVehicleScript");
            return;
        else
            self.spawnManualVehicleButton:setEnable(true);
            self.spawnManualVehicleButton.tooltip = nil;
        end
    end;
    self.spawnVehicleInput:setText("");
    self.spawnVehicleInput:setEditable(false);
    self.spawnVehicleInput:setSelectable(false);
    self.spawnVehicleInput:setHeight(20);
    self.spawnVehicleInput:setOnlyNumbers(false);

    self.spawnManualVehicleButton = self:createButton(2 * padding,
        self.vehicleSpawnMethodRadioBttn:getBottom() + padding, self.vehiclesCategoriesList:getWidth() / 4, bttnHeight,
        getText("IGUI_VRM_SpawnVehicle"), self.onSpawnVehicles
    );
    self.spawnManualVehicleButton.borderColor = { r = 0.2, g = 0.6, b = 0.9, a = 1 };
end

function RespawnControlPanel:onSpawnVehicles()
    local spawnMethod = nil;
    if self.vehicleSpawnMethodRadioBttn:isSelected(1) then
        spawnMethod = "random";
    elseif self.vehicleSpawnMethodRadioBttn:isSelected(2) then
        spawnMethod = "fixed";
    end

    local vehicleCount = self.spawnCountInput:getInternalText();
    vehicleCount = vehicleCount and tonumber(vehicleCount) or 1;

    local vehicleScriptName = nil;
    if spawnMethod == "fixed" then
        vehicleScriptName = self.spawnVehicleInput:getInternalText():trim();
    end

    sendClientCommand("VehicleRespawnManager", "QueueVehicle",
        {
            type = spawnMethod,
            count = vehicleCount,
            scriptName = vehicleScriptName
        }
    );
end

function RespawnControlPanel:onChangeVehicleSpawnMethod(buttons, index)
    if index == 1 then
        self.spawnVehicleInput:setText("");
        self.spawnVehicleInput:setEditable(false);
        self.spawnVehicleInput:setSelectable(false);
        self.spawnManualVehicleButton:setEnable(true);
        self.spawnManualVehicleButton.tooltip = "";
    elseif index == 2 then
        self.spawnVehicleInput:setText("");
        self.spawnVehicleInput:setEditable(true);
        self.spawnVehicleInput:setSelectable(true);
        self.spawnManualVehicleButton:setEnable(false);
        self.spawnManualVehicleButton.tooltip = getText("IGUI_VRM_WriteVehicleScript");
    end
end

function RespawnControlPanel:onResize()
    ISUIElement.onResize(self);
    local padding = 10;

    local oneThirdListWidth = self:getWidth() / 3 - 2 * padding;
    local buttonWidth = (oneThirdListWidth - padding) / 2;

    self.exportButton:setWidth(buttonWidth);
    self.exportButton:setX(self:getWidth() - buttonWidth - padding);

    self.importButton:setWidth(buttonWidth);
    self.importButton:setX(self.exportButton:getX() - buttonWidth - padding);

    self.zoneNameComboBox:setWidth(self:getWidth() * 0.375);

    self.addZoneButton:setWidth((self.zoneNameComboBox:getWidth() - padding) / 2);
    self.removeZoneButton:setWidth(self.addZoneButton:getWidth());
    self.removeZoneButton:setX(self.addZoneButton:getRight() + padding);

    self.zoneOptionsTickBox:setX(self.zoneNameComboBox:getRight() + padding);


    local twoThirdsListWidth = self:getWidth() * 2 / 3;

    self.vehicleCategoriesLabel:setX(padding + twoThirdsListWidth / 4);
    self.spawnRatesLabel:setX(padding + (twoThirdsListWidth / 4) * 3);
    self.vehiclesAssignedLabel:setX(self.vehiclesCategoriesList:getRight() + (self:getWidth() / 3 - 2 * padding) / 2);


    self.vehiclesCategoriesList:setWidth(twoThirdsListWidth);
    self.vehiclesAssignedList:setX(self.vehiclesCategoriesList:getRight());
    self.vehiclesAssignedList:setWidth(oneThirdListWidth);


    local xBase = self:getWidth() - 2 * buttonWidth - 2 * padding;
    local yBase = self:getWidth() - buttonWidth - padding;
    local halfPadding = padding / 2;

    self.coordsErrorLabel:setX(self.importButton:getRight() + halfPadding);

    for _, element in ipairs({ { self.x1Label, self.x1Input }, { self.x2Label, self.x2Input } }) do
        element[1]:setX(xBase);
        element[2]:setX(element[1]:getRight() + padding);
    end

    for _, element in ipairs({ { self.y1Label, self.y1Input }, { self.y2Label, self.y2Input } }) do
        element[1]:setX(yBase);
        element[2]:setX(element[1]:getRight() + padding);
    end


    buttonWidth = self.vehiclesCategoriesList:getWidth() / 4;
    self.addCategoryButton:setWidth(buttonWidth);
    self.removeCategoryButton:setWidth(buttonWidth);
    self.removeCategoryButton:setX(self.addCategoryButton:getRight() + padding);


    self.setDefaultCategoryButton:setWidth(buttonWidth);
    self.currentDefaultCategoryLabel:setX(self.setDefaultCategoryButton:getRight() + padding);


    buttonWidth = (self.vehiclesAssignedList:getWidth() - padding) / 2;

    self.addVehicleButton:setWidth(buttonWidth);
    self.addVehicleButton:setX(self.vehiclesAssignedList:getX());

    self.addBatchVehiclesButton:setWidth(buttonWidth);
    self.addBatchVehiclesButton:setX(self.vehiclesAssignedList:getX());

    self.removeVehicleButton:setWidth(buttonWidth);
    self.removeVehicleButton:setX(self.addVehicleButton:getRight() + padding);


    self.blacklistedVehiclesLabel:setX(self.addBatchVehiclesButton:getX() + (self:getWidth() / 3 - 2 * padding) / 2);

    self.blacklistedVehiclesList:setWidth(self.vehiclesAssignedList:getWidth());
    self.blacklistedVehiclesList:setX(self.addBatchVehiclesButton:getX());


    buttonWidth = (self.blacklistedVehiclesList:getWidth() - padding) / 2;

    self.addBlacklistVehicleButton:setWidth(buttonWidth);
    self.addBlacklistVehicleButton:setX(self.blacklistedVehiclesList:getX());

    self.addBatchBlacklistVehiclesButton:setWidth(buttonWidth);
    self.addBatchBlacklistVehiclesButton:setX(self.addBlacklistVehicleButton:getX());

    self.removeBlacklistVehicleButton:setWidth(buttonWidth);
    self.removeBlacklistVehicleButton:setX(self.addBlacklistVehicleButton:getRight() + padding);
end

function RespawnControlPanel:close()
    local modData = self.character:getModData();
    modData.VRMPosition = { x = self:getX(), y = self:getY(), width = self:getWidth(), height = self:getHeight() };

    self:setVisible(false);
    self:removeFromUIManager();
    RespawnControlPanel.instance = nil;
    if JoypadState.players[self.playerNum + 1] then
        setJoypadFocus(self.playerNum, nil);
    end
end

function RespawnControlPanel:onChangeZoneNameBox()
    self.refresh = 3;
end

function RespawnControlPanel:onMouseUpZoneNameBox(x, y)
    ISComboBox.onMouseUp(self, x, y);

    self.editor.onCommandEntered = function(self)
        local selectedValue = self:getInternalText():trim();
        selectedValue = tostring(selectedValue);

        if string.match(selectedValue, "^[0-9]") then return; end

        self:setText(selectedValue);

        sendClientCommand("VehicleRespawnManager", "EditZoneData",
            {
                selectedIdx = self.parentCombo.selected,
                newKey = "name",
                newValue = selectedValue
            }
        );
        self.parentCombo:forceClick();
        self.parentCombo.parent.refresh = 3;
    end;

    self.editor.onOtherKey = function(self, key)
        if key == Keyboard.KEY_ESCAPE then
            self.parentCombo.expanded = false;
            self.parentCombo:hidePopup();
        elseif key == Keyboard.KEY_RETURN then
            self.parentCombo.expanded = false;
            self.parentCombo:hidePopup();

            local selectedValue = self:getInternalText():trim();
            selectedValue = tostring(selectedValue);

            if string.match(selectedValue, "^[0-9]") then return; end

            self:setText(selectedValue);

            sendClientCommand("VehicleRespawnManager", "EditZoneData",
                {
                    selectedIdx = self.parentCombo.selected,
                    newKey = "name",
                    newValue = selectedValue
                }
            );

            self.parentCombo:forceClick();
            self.parentCombo.parent.refresh = 3;
        end
    end;

    self.editor.target = self;
end

function RespawnControlPanel:onTickBoxZoneOptions(index, selected)
    local otherIndex = index == 1 and 2 or 1;
    local optionNames = {
        getText("IGUI_VRM_ZoneIsGlobal"),
        getText("IGUI_VRM_ZoneIsBlacklist")
    };

    if selected then
        self.zoneOptionsTickBox.selected[otherIndex] = false;
        self.zoneOptionsTickBox:disableOption(optionNames[otherIndex], true);

        sendClientCommand("VehicleRespawnManager", "EditZoneData", {
            selectedIdx = self:getSelectedZoneZoneIdx(),
            newKey = otherIndex == 1 and "isGlobalZone" or "isBlacklistZone",
            newValue = false
        });
    else
        self.zoneOptionsTickBox:disableOption(optionNames[otherIndex], false);
    end

    sendClientCommand("VehicleRespawnManager", "EditZoneData", {
        selectedIdx = self:getSelectedZoneZoneIdx(),
        newKey = index == 1 and "isGlobalZone" or "isBlacklistZone",
        newValue = selected
    });
end

function RespawnControlPanel:onCoordsInputChange()
    local coordVal = self:getInternalText();
    local selectedZoneIdx = self.parent:getSelectedZoneZoneIdx();

    if coordVal == "" or not tonumber(coordVal) then
        coordVal = "-1";
    end

    local zone = self.parent.vehicleRespawnZones[selectedZoneIdx];
    if not zone then return; end

    zone.coordinates = zone.coordinates or {};
    zone.coordinates[self.coordType] = tonumber(coordVal);

    self.parent:validateCoords(zone);
end

function RespawnControlPanel:validateCoords(zone)
    if not zone.coordinates then
        self.coordsErrorLabel:setName("");
        return;
    end

    local x1 = zone.coordinates.x1 or -1;
    local x2 = zone.coordinates.x2 or -1;
    local y1 = zone.coordinates.y1 or -1;
    local y2 = zone.coordinates.y2 or -1;

    if x1 == -1 or x2 == -1 or y1 == -1 or y2 == -1 then
        self.coordsErrorLabel:setName("");
        return;
    end

    -- Conditions:
    -- West corner: (x1, y1) should have a lower y (further west) and lower x
    -- South corner: (x2, y2) should have a larger y (further south) and larger x
    -- So we want: x1 < x2 and y1 < y2

    if x1 < x2 and y1 < y2 then
        local selectedZoneIdx = self:getSelectedZoneZoneIdx();
        self.coordsErrorLabel:setName("")
        sendClientCommand("VehicleRespawnManager", "EditZoneData",
            {
                selectedIdx = selectedZoneIdx,
                newKey = "coordinates.x1",
                newValue = x1
            }
        );
        sendClientCommand("VehicleRespawnManager", "EditZoneData",
            {
                selectedIdx = selectedZoneIdx,
                newKey = "coordinates.y1",
                newValue = y1
            }
        );
        sendClientCommand("VehicleRespawnManager", "EditZoneData",
            {
                selectedIdx = selectedZoneIdx,
                newKey = "coordinates.x2",
                newValue = x2
            }
        );
        sendClientCommand("VehicleRespawnManager", "EditZoneData",
            {
                selectedIdx = selectedZoneIdx,
                newKey = "coordinates.y2",
                newValue = y2
            }
        );
    else
        self.coordsErrorLabel:setName(getText("IGUI_VRM_COORDS_ERROR"));
    end
end

function RespawnControlPanel:onMaxVehiclesPerZoneInputChange()
    local numberVal = self:getInternalText();
    local selectedZoneIdx = self.parent:getSelectedZoneZoneIdx();

    if numberVal == "" or not tonumber(numberVal) or (tonumber(numberVal) and tonumber(numberVal) < 1) then
        numberVal =
        "999";
    end

    sendClientCommand("VehicleRespawnManager", "EditZoneData",
        {
            selectedIdx = selectedZoneIdx,
            newKey = "maxVehicleCount",
            newValue = numberVal
        }
    );
end

function RespawnControlPanel:onTickBoxDefaultCatUnassignedVehicles(index, selected)
    sendClientCommand("VehicleRespawnManager", "EditZoneData",
        {
            selectedIdx = self:getSelectedZoneZoneIdx(),
            newKey = "useDefaultCategoryForUnassigned",
            newValue = selected
        }
    );

    local zoneData = self:getSelectedZoneData();
    if zoneData then
        sendClientCommand("VehicleRespawnManager", "EditZoneData",
            {
                selectedIdx = self:getSelectedZoneZoneIdx(),
                newKey = "defaultCategoryNameForUnassigned",
                newValue = zoneData.defaultCategoryNameForUnassigned
            }
        );
    end

    self.setDefaultCategoryButton:setEnable(selected);
end

function RespawnControlPanel:onImport()
    local zones = FileUtils.readJson("VehicleRespawnZones.json", "Vehicle Respawn Manager", { isModFile = false })

    if (not zones) or (type(zones) ~= "table") then
        Logger:error("VehicleRespawnZones IMPORT FAILED");
        return;
    end
    sendClientCommand("VehicleRespawnManager", "ImportZoneData", { zones = zones })

    self.refresh = 3;
end

function RespawnControlPanel:onExport()
    local cacheDir = Core.getMyDocumentFolder() ..
        getFileSeparator() .. "Lua" .. getFileSeparator() .. "VehicleRespawnZones.json";

    local zones = VehicleRespawnManager.Shared.RequestZones();

    local success = false;
    success = FileUtils.writeJson("VehicleRespawnZones.json", zones, "Vehicle Respawn Manager", { createIfNull = true })

    if success then
        Logger:info("VehicleRespawnZones EXPORTED SUCCESFULLY TO %s", cacheDir);
        local modal = ISModalDialog:new(0, 0, 350, 150, getText("IGUI_VRM_ExportSuccesful", cacheDir),
            true, nil, function(dummy, button, playerObj)
                if button.internal == "NO" then return; end
                if isDesktopOpenSupported() then
                    showFolderInDesktop(cacheDir)
                else
                    openUrl(cacheDir)
                end
            end, self.playerNum, self.character)
        modal:initialise()
        modal.moveWithMouse = true
        modal:addToUIManager()
        if JoypadState.players[self.playerNum + 1] then
            setJoypadFocus(self.playerNum, modal)
        end
    else
        Logger:error("VehicleRespawnZones FAILED TO EXPORT TO %s", cacheDir);
    end
end

function RespawnControlPanel:onAddZone()
    local newZone = copyTable(ZONE_TEMPLATE);
    if not newZone then return; end

    sendClientCommand("VehicleRespawnManager", "AddZone", { newZone = newZone });

    self.zoneNameComboBox.selected = #self.zoneNameComboBox.options + 1;

    self.refresh = 3;
end

function RespawnControlPanel:onRemoveZone()
    local selected = self:getSelectedZoneZoneIdx();
    if not selected or not self.vehicleRespawnZones[selected] then return; end

    sendClientCommand("VehicleRespawnManager", "RemoveZone", { selectedIdx = self:getSelectedZoneZoneIdx() });

    self.zoneNameComboBox.selected = 0;

    self.refresh = 3;
end

function RespawnControlPanel:onAddCategoryModal()
    local modal = ISTextBox:new(0, 0, 300, 200, getText("IGUI_VRM_CategoryName"), "", self,
        self.onAddCategory, self.playerNum);
    modal:initialise();
    modal:addToUIManager();
end

function RespawnControlPanel:onAddCategory(target)
    if target.internal ~= "OK" then return; end

    local text = target.parent.entry:getText();
    local zoneData = self:getSelectedZoneData();

    if not zoneData then return; end

    zoneData.highestCategoryKey = (zoneData.highestCategoryKey or 0) + 1;

    local nextKey = tostring(zoneData.highestCategoryKey);
    self.vehiclesCategoriesList:addItem(text, {
        key = nextKey,
        vehicles = {},
        spawnRate = 0
    });

    -- self:normalizeSpawnRates();
    self:sendSpawnRateUpdate();

    local selectedZoneIdx = self:getSelectedZoneZoneIdx();

    sendClientCommand("VehicleRespawnManager", "EditZoneData",
        {
            selectedIdx = selectedZoneIdx,
            newKey = "vehicleSpawnCategories." .. nextKey,
            newValue = {
                key = nextKey,
                name = text,
                vehicles = {},
                spawnRate = 0
            }
        }
    );

    sendClientCommand("VehicleRespawnManager", "EditZoneData",
        {
            selectedIdx = selectedZoneIdx,
            newKey = "highestCategoryKey",
            newValue = nextKey
        }
    );

    self.refresh = 3;
end

function RespawnControlPanel:onRemoveCategory()
    local selectedIndex = self.vehiclesCategoriesList.selected;

    if not selectedIndex or selectedIndex <= 0 then return; end

    local selectedItem = self.vehiclesCategoriesList.items[selectedIndex];
    if not selectedItem then return; end

    local keyToRemove = selectedItem.item.key;
    self.vehiclesCategoriesList:removeItemByIndex(selectedIndex);

    local updatedList = {};
    for i = 1, #self.vehiclesCategoriesList.items do
        local item = self.vehiclesCategoriesList.items[i]
        item.item.key = tostring(i);
        table.insert(updatedList, item);
    end
    self.vehiclesCategoriesList.items = updatedList;

    local selectedZoneIdx = self:getSelectedZoneZoneIdx();

    sendClientCommand("VehicleRespawnManager", "EditZoneData",
        {
            selectedIdx = selectedZoneIdx,
            newKey = "vehicleSpawnCategories." .. keyToRemove,
            newValue = nil
        }
    );

    sendClientCommand("VehicleRespawnManager", "EditZoneData",
        {
            selectedIdx = selectedZoneIdx,
            newKey = "vehicleSpawnCategories",
            newValue = self:extractCategoriesData()
        }
    );

    self.refresh = 3;
end

function RespawnControlPanel:extractCategoriesData()
    local data = {};
    for i = 1, #self.vehiclesCategoriesList.items do
        local item = self.vehiclesCategoriesList.items[i]
        data[item.item.key] = {
            key = item.item.key,
            name = item.text,
            vehicles = item.item.vehicles,
            spawnRate = item.item.spawnRate
        };
    end
    return data;
end

function RespawnControlPanel:onSetDefaultCategory()
    local context = ISContextMenu.get(self.playerNum,
        self.setDefaultCategoryButton:getAbsoluteX() + self.setDefaultCategoryButton:getWidth(),
        self.setDefaultCategoryButton:getAbsoluteY()
    );

    local zoneData = self:getSelectedZoneData();

    if zoneData then
        for key, category in pairs(zoneData.vehicleSpawnCategories) do
            context:addOption(category.name, RespawnControlPanel.instance,
                RespawnControlPanel.onSelectDefaultCategory, category.name);
        end
    end
end

function RespawnControlPanel.onSelectDefaultCategory(target, value)
    local zoneData = target:getSelectedZoneData();
    if zoneData then
        sendClientCommand("VehicleRespawnManager", "EditZoneData",
            {
                selectedIdx = target:getSelectedZoneZoneIdx(),
                newKey = "defaultCategoryNameForUnassigned",
                newValue = value
            }
        );
        target.currentDefaultCategoryLabel:setName(getText("IGUI_VRM_CurrentDefaultCatForUnassignedVehicles", value));
    else
        target.currentDefaultCategoryLabel:setName(getText("IGUI_VRM_CurrentDefaultCatForUnassignedVehicles", "None"));
    end
end

function RespawnControlPanel:onAddVehicleModal()
    local modal = VehicleScriptTextBox:new(0, 0, 300, 150, getText("IGUI_VRM_VehicleScript"), "", self,
        self.onAddVehicle, self.playerNum, "vehiclesAssignedList");
    modal.noEmpty = true;
    modal.checkVehicleScripts = true;
    modal.singleVehicleMode = true;
    modal:setMultipleLine(false);
    modal:initialise();
    modal:addToUIManager();
end

function RespawnControlPanel:onAddBatchVehicleModal()
    local modal = VehicleScriptTextBox:new(0, 0, 300, 150, getText("IGUI_VRM_VehicleScriptBatch"), "", self,
        self.onAddVehicle, self.playerNum, "vehiclesAssignedList");
    modal.maxLines = 999;
    modal.multipleLine = true;
    modal.noEmpty = true;
    modal.checkVehicleScripts = true;
    modal.singleVehicleMode = false;
    modal:setMultipleLine(false);
    modal:initialise();
    modal:addToUIManager();
end

local function isScriptNameValid(scriptName)
    return VehicleRespawnManager.Shared.VehicleScripts[scriptName]
        and not string.match(scriptName, "[^%w%._%-]");
end

function RespawnControlPanel:onAddVehicle(target, listType)
    if target.internal ~= "ADD" then return; end

    local zoneData = self:getSelectedZoneData();
    if not zoneData then return; end

    local vehiclesTable;
    if listType == "blacklistedVehiclesList" then
        vehiclesTable = zoneData.zoneVehicleBlacklist;
    else
        local selectedCategoryIdx = self.vehiclesCategoriesList.selected;
        if not selectedCategoryIdx or selectedCategoryIdx <= 0 then return; end

        local selectedCategoryItem = self.vehiclesCategoriesList.items[selectedCategoryIdx];
        if not selectedCategoryItem then return; end

        vehiclesTable = selectedCategoryItem.item.vehicles or {};
        selectedCategoryItem.item.vehicles = vehiclesTable;
    end

    local function addVehicle(scriptName)
        scriptName = string.trim(scriptName);
        if isScriptNameValid(scriptName) and not vehiclesTable[scriptName] then
            self[listType]:addItem(scriptName);
            vehiclesTable[scriptName] = true;
        end
    end

    local text = "";
    if target.parent.singleVehicleMode then
        text = target.parent.entry:getSelectedText();
        addVehicle(text);
    else
        text = target.parent.entry:getText();
        for scriptName in string.gmatch(text, "[^;]+") do
            addVehicle(scriptName);
        end
    end

    local selectedZoneIdx = self:getSelectedZoneZoneIdx();

    local commandKey, commandValue;
    if listType == "blacklistedVehiclesList" then
        commandKey = "zoneVehicleBlacklist";
        commandValue = vehiclesTable;
    else
        local selectedCategoryItem = self.vehiclesCategoriesList.items[self.vehiclesCategoriesList.selected];
        commandKey = "vehicleSpawnCategories." .. selectedCategoryItem.item.key .. ".vehicles";
        commandValue = vehiclesTable;
    end

    sendClientCommand("VehicleRespawnManager", "EditZoneData",
        {
            selectedIdx = selectedZoneIdx,
            newKey = commandKey,
            newValue = commandValue
        }
    );

    if listType == "blacklistedVehiclesList" then
        if self[listType].count > 0 then
            self.removeBlacklistVehicleButton:setEnable(true);
        else
            self.removeBlacklistVehicleButton:setEnable(false);
        end
    else
        if self[listType].count > 0 then
            self.removeVehicleButton:setEnable(true);
        else
            self.removeVehicleButton:setEnable(false);
        end
    end

    -- self.refresh = 3;
end

function RespawnControlPanel:onRemoveVehicle()
    local selectedVehicleIdx = self.vehiclesAssignedList.selected;

    if not selectedVehicleIdx or selectedVehicleIdx <= 0 then return; end

    local selectedVehicle = self.vehiclesAssignedList.items[selectedVehicleIdx];
    if not selectedVehicle then return; end

    local selectedCategoryIdx = self.vehiclesCategoriesList.selected;
    if not selectedCategoryIdx or selectedCategoryIdx <= 0 then return; end

    local selectedCategoryItem = self.vehiclesCategoriesList.items[selectedCategoryIdx];
    if not selectedCategoryItem then return; end
    local vehiclesTable = selectedCategoryItem.item.vehicles;

    local vehicleKey = selectedVehicle.text;
    if vehiclesTable[vehicleKey] then
        vehiclesTable[vehicleKey] = nil;
    end

    self.vehiclesAssignedList:removeItemByIndex(selectedVehicleIdx);

    local selectedZoneIdx = self:getSelectedZoneZoneIdx();
    sendClientCommand("VehicleRespawnManager", "EditZoneData",
        {
            selectedIdx = selectedZoneIdx,
            newKey = "vehicleSpawnCategories." .. selectedCategoryItem.item.key .. ".vehicles",
            newValue = vehiclesTable
        }
    );

    -- self.refresh = 3;
end

function RespawnControlPanel:onAddBlacklistVehicleModal()
    local modal = VehicleScriptTextBox:new(0, 0, 300, 150, getText("IGUI_VRM_VehicleScript"), "", self,
        self.onAddVehicle, self.playerNum, "blacklistedVehiclesList");
    modal.noEmpty = true;
    modal.checkVehicleScripts = true;
    modal.singleVehicleMode = true;
    modal:setMultipleLine(false);
    modal:initialise();
    modal:addToUIManager();
end

function RespawnControlPanel:onAddBatchBlacklistVehicleModal()
    local modal = VehicleScriptTextBox:new(0, 0, 300, 150, getText("IGUI_VRM_VehicleScriptBatch"), "", self,
        self.onAddVehicle, self.playerNum, "blacklistedVehiclesList");
    modal.maxLines = 999;
    modal.multipleLine = true;
    modal.noEmpty = true;
    modal.checkVehicleScripts = true;
    modal.singleVehicleMode = false;
    modal:setMultipleLine(false);
    modal:initialise();
    modal:addToUIManager();
end

function RespawnControlPanel:onRemoveBlacklistVehicle()
    local zoneData = self:getSelectedZoneData();
    if not zoneData then return; end

    local selectedVehicleIdx = self.blacklistedVehiclesList.selected;
    if not selectedVehicleIdx or selectedVehicleIdx <= 0 then return; end

    local selectedVehicle = self.blacklistedVehiclesList.items[selectedVehicleIdx];
    if not selectedVehicle then return; end

    local vehiclesTable = zoneData.zoneVehicleBlacklist;

    local vehicleKey = selectedVehicle.text;
    if vehiclesTable[vehicleKey] then
        vehiclesTable[vehicleKey] = nil;
    end

    self.blacklistedVehiclesList:removeItemByIndex(selectedVehicleIdx);

    local selectedZoneIdx = self:getSelectedZoneZoneIdx();
    sendClientCommand("VehicleRespawnManager", "EditZoneData",
        {
            selectedIdx = selectedZoneIdx,
            newKey = "zoneVehicleBlacklist",
            newValue = vehiclesTable
        }
    );

    -- self.refresh = 3;
end

return RespawnControlPanel
