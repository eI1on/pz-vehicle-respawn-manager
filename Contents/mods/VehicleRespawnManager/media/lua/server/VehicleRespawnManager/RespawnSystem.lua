local Reflection = require("Starlit/utils/Reflection");
local Globals = require("Starlit/Globals");
local Logger = require("VehicleRespawnManager/Logger");

if Globals.isClient then return; end

local VehicleRespawnManager         = require("VehicleRespawnManager/Shared");

local Constants                     = {
    CONFIG = {
        MAX_ATTEMPTS_REQ = 20,
        MAX_ATTEMPTS_RANDOM_VEHICLE_ZONE = 20,

        MAX_TIMED_SPAWNS_PROCESSED = 3,
        TIMED_SPAWNS_SPAWN_DELAY = 1000,

        QUEUE_PROCESS_INTERVAL = 1000,

        SAFEHOUSE_CHECK_INTERVAL = 10000,

        SAFEHOUSE_BUFFER = 20,
        CELL_SIZE = 300,

        SPAWN_SQUARE_CLEAR_RANGE = 3,
        SQUARE_LOAD_DELAY = 500,

        DEFAULT_ENGINE_QUALITY = "1;100",

        REQUEST_STATUS = {
            PENDING = "PENDING",
            PROCESSING = "PROCESSING",
            COMPLETED = "COMPLETED",
            FAILED = "FAILED"
        }
    },
    WORLD_VEHICLE_ZONES_DIRECTIONS = {
        trafficjams = "S",
        trafficjamn = "N",
        trafficjame = "E",
        trafficjamw = "W",
        rtrafficjams = "S",
        rtrafficjamn = "N",
        rtrafficjame = "E",
        rtrafficjamw = "W"
    }
}

-- Core classes
---@class State
local State                         = {
    cachedWorldZonesByCell = {},

    safehouseState = {},

    lastQueueProcessTime = 0,
    lastSafehouseCheck = 0,

    rand = newrandom()
}

---@class Zones
local Zones                         = {
    globalBlacklistZones = table.newarray(),
    globalZones = table.newarray(),
    blacklistZones = table.newarray(),
    nonGlobalZones = table.newarray(),
}

VehicleRespawnManager.RespawnSystem = {
    Config = Constants.CONFIG,
    State = State,
    Zones = Zones,
    RequestStatus = Constants.CONFIG.REQUEST_STATUS,

    ModDataManager = {},
    ZoneManager = {},
    SpawnManager = {}
}

local vehicleScripts                = VehicleRespawnManager.Shared.VehicleScripts;

-----------------------------------------------------
-- Utility & Data Access
-----------------------------------------------------

local function getTimestamp()
    return Calendar.getInstance():getTimeInMillis();
end

local function initOptions()
    local optionsVars = SandboxVars.VehicleRespawnManager;

    if optionsVars then
        local logLevel = optionsVars.enableLogging and "DEBUG" or "INFO";
        Logger:setLogLevel(logLevel);
    end
end

local function formatRequest(ctx)
    local parts = {};
    local function addField(field, pattern, value)
        if value ~= nil then
            table.insert(parts, string.format("[%s=" .. pattern .. "]", field, value));
        end
    end
    addField("id", "%s", ctx.id)
    addField("type", "%s", ctx.type)
    addField("status", "%s", ctx.status)
    addField("attempt", "%d", ctx.attempt)
    addField("zone", "%s", ctx.zone)
    addField("fixedScript", "%s", ctx.fixedScript)
    addField("vehicle", "%s", ctx.vehicle)
    addField("direction", "%s", ctx.direction)
    if ctx.x ~= nil and ctx.y ~= nil then
        table.insert(parts, string.format("[coords=%d,%d]", ctx.x, ctx.y));
    end
    return table.concat(parts);
end

function VehicleRespawnManager.RespawnSystem.ModDataManager.getModData()
    local globalModData = ModData.getOrCreate("VehicleRespawnManagerData");
    globalModData.SpawnRequestsQueue = globalModData.SpawnRequestsQueue or {};
    globalModData.LocationPendingSpawns = globalModData.LocationPendingSpawns or {};
    globalModData.TimedSpawns = globalModData.TimedSpawns or {};
    globalModData.LastRequestId = globalModData.LastRequestId or 0;
    globalModData.RequestsById = globalModData.RequestsById or {};
    return globalModData;
end

function VehicleRespawnManager.RespawnSystem.ModDataManager.CleanupOldRequests(maxAge)
    maxAge = maxAge or (7 * 24 * 60 * 60 * 1000); -- Default 7 days in milliseconds
    local currentTime = getTimestamp();
    local globalModData = VehicleRespawnManager.RespawnSystem.ModDataManager.getModData();

    for requestId, request in pairs(globalModData.RequestsById) do
        if (request.status == Constants.CONFIG.REQUEST_STATUS.COMPLETED or
                request.status == Constants.CONFIG.REQUEST_STATUS.FAILED) and
            (currentTime - request.timestamp > maxAge) then
            globalModData.RequestsById[requestId] = nil;
        end
    end
end

Events.EveryDays.Add(function()
    VehicleRespawnManager.RespawnSystem.ModDataManager.CleanupOldRequests()
end)


-----------------------------------------------------
-- Zone Initialization & Category Processing
-----------------------------------------------------

function VehicleRespawnManager.RespawnSystem.ZoneManager.initZones()
    local originalZones = VehicleRespawnManager.Shared.RequestZones() or {};
    local zones = copyTable(originalZones);

    Zones = {
        globalBlacklistZones = table.newarray(),
        globalZones = table.newarray(),
        blacklistZones = table.newarray(),
        nonGlobalZones = table.newarray(),
    };

    for i = 1, #zones do
        VehicleRespawnManager.RespawnSystem.ZoneManager.processZone(zones[i]);
    end
end

function VehicleRespawnManager.RespawnSystem.ZoneManager.processZone(zone)
    if zone.useDefaultCategoryForUnassigned then
        VehicleRespawnManager.RespawnSystem.ZoneManager.handleDefaultCategory(zone);
    end

    VehicleRespawnManager.RespawnSystem.ZoneManager.categorizeZone(zone);
end

function VehicleRespawnManager.RespawnSystem.ZoneManager.handleDefaultCategory(zone)
    local defaultCatName = zone.defaultCategoryNameForUnassigned;
    if not (defaultCatName and defaultCatName ~= "None") then return; end

    local categories = zone.vehicleSpawnCategories;
    if not categories then return; end

    local defaultCategory, assignedVehicles = VehicleRespawnManager.RespawnSystem.ZoneManager.findDefaultCategory(
    categories, defaultCatName);
    if defaultCategory then
        VehicleRespawnManager.RespawnSystem.ZoneManager.assignUnassignedVehicles(zone, defaultCategory, assignedVehicles);
    end
end

function VehicleRespawnManager.RespawnSystem.ZoneManager.findDefaultCategory(categories, defaultCatName)
    local defaultCategory = nil;
    local assignedVehicles = {};

    for _, catData in pairs(categories) do
        if catData.name == defaultCatName then
            defaultCategory = catData;
        end
        if catData.vehicles then
            for vName in pairs(catData.vehicles) do
                assignedVehicles[vName] = true;
            end
        end
    end

    return defaultCategory, assignedVehicles;
end

function VehicleRespawnManager.RespawnSystem.ZoneManager.assignUnassignedVehicles(zone, defaultCategory, assignedVehicles)
    local defaultVehicles = defaultCategory.vehicles or {};
    defaultCategory.vehicles = defaultVehicles;

    for scriptName in pairs(vehicleScripts) do
        if not assignedVehicles[scriptName] and not zone.zoneVehicleBlacklist[scriptName] then
            defaultVehicles[scriptName] = true;
        end
    end
end

function VehicleRespawnManager.RespawnSystem.ZoneManager.categorizeZone(zone)
    if zone.isBlacklistZone then
        if zone.isGlobalZone then
            table.insert(Zones.globalBlacklistZones, zone);
        else
            table.insert(Zones.blacklistZones, zone);
        end
    else
        if zone.isGlobalZone then
            table.insert(Zones.globalZones, zone);
        else
            table.insert(Zones.nonGlobalZones, zone);
        end
    end
end

Events.OnInitGlobalModData.Add(function()
    VehicleRespawnManager.RespawnSystem.ZoneManager.initZones();
    initOptions();
end);

-----------------------------------------------------
-- World Cell Zones Retrieval & Utility
-----------------------------------------------------

-- Utility function to check if a vehicle zone is within a buffer zone of any safehouse
function VehicleRespawnManager.RespawnSystem.ZoneManager.IsZoneNearSafehouse(zone)
    local zoneX1 = zone:getX();
    local zoneY1 = zone:getY();
    local zoneX2 = zoneX1 + zone:getWidth();
    local zoneY2 = zoneY1 + zone:getHeight();

    for i = 0, SafeHouse.getSafehouseList():size() - 1 do
        local safe = SafeHouse.getSafehouseList():get(i);

        local safeX = safe:getX();
        local safeY = safe:getY();
        local safeW = safe:getW();
        local safeH = safe:getH();

        local bufferX1 = safeX - VehicleRespawnManager.RespawnSystem.Config.SAFEHOUSE_BUFFER;
        local bufferY1 = safeY - VehicleRespawnManager.RespawnSystem.Config.SAFEHOUSE_BUFFER;
        local bufferX2 = safeX + safeW + VehicleRespawnManager.RespawnSystem.Config.SAFEHOUSE_BUFFER;
        local bufferY2 = safeY + safeH + VehicleRespawnManager.RespawnSystem.Config.SAFEHOUSE_BUFFER;

        local intersectX = (zoneX1 >= bufferX1 and zoneX1 or bufferX1) <= (zoneX2 <= bufferX2 and zoneX2 or bufferX2);
        local intersectY = (zoneY1 >= bufferY1 and zoneY1 or bufferY1) <= (zoneY2 <= bufferY2 and zoneY2 or bufferY2);

        if intersectX and intersectY then return true; end
    end
    return false;
end

function VehicleRespawnManager.RespawnSystem.ZoneManager.GetWorldZonesForCellAt(cellx, celly)
    local cacheY = VehicleRespawnManager.RespawnSystem.State.cachedWorldZonesByCell[celly];
    if cacheY then
        local cacheX = cacheY[cellx];
        if cacheX then
            return cacheX;
        end
    else
        VehicleRespawnManager.RespawnSystem.State.cachedWorldZonesByCell[celly] = table.newarray() --[[@as table]]
    end

    local world = getWorld();
    local grid = world:getMetaGrid();
    local cellData = grid:getCellDataAbs(cellx, celly);

    ---@diagnostic disable-next-line: deprecated
    local zones = Reflection.getUnexposedObjectField(cellData, "vehicleZones");
    local cellVehicleZones = table.newarray() --[[@as table]]

    for i = 0, zones:size() - 1 do
        local zone = zones:get(i);
        local substring = string.sub(tostring(zone), 1, 34);
        if substring == "zombie.iso.IsoMetaGrid$VehicleZone" then
            local zoneName = zone:getName();
            local zoneDir = zone.dir;
            if VehicleRespawnManager.RespawnSystem.Config.WORLD_VEHICLE_ZONES_DIRECTIONS[zoneName] then
                zoneDir = VehicleRespawnManager.RespawnSystem.Config.WORLD_VEHICLE_ZONES_DIRECTIONS[zoneName];
            end

            -- check if the zone is near any safehouse; if so, skip it
            if not VehicleRespawnManager.RespawnSystem.ZoneManager.IsZoneNearSafehouse(zone) then
                table.insert(cellVehicleZones, { zone = zone, direction = zoneDir });
            end
        end
    end

    VehicleRespawnManager.RespawnSystem.State.cachedWorldZonesByCell[celly][cellx] = cellVehicleZones;
    return cellVehicleZones;
end

function VehicleRespawnManager.RespawnSystem.ZoneManager.RecacheCellsForSafehouses(safehouses)
    for i = 1, #safehouses do
        local safe = safehouses[i];
        local minCellX = math.floor((safe.x - VehicleRespawnManager.RespawnSystem.Config.SAFEHOUSE_BUFFER) /
            VehicleRespawnManager.RespawnSystem.Config.CELL_SIZE);
        local maxCellX = math.floor((safe.x + safe.w + VehicleRespawnManager.RespawnSystem.Config.SAFEHOUSE_BUFFER) /
            VehicleRespawnManager.RespawnSystem.Config.CELL_SIZE);
        local minCellY = math.floor((safe.y - VehicleRespawnManager.RespawnSystem.Config.SAFEHOUSE_BUFFER) /
            VehicleRespawnManager.RespawnSystem.Config.CELL_SIZE);
        local maxCellY = math.floor((safe.y + safe.h + VehicleRespawnManager.RespawnSystem.Config.SAFEHOUSE_BUFFER) /
            VehicleRespawnManager.RespawnSystem.Config.CELL_SIZE);
        local cellX, cellY, cachedRow;

        for x = minCellX, maxCellX do
            for y = minCellY, maxCellY do
                cellX, cellY = tonumber(x), tonumber(y);
                if cellX and cellY then
                    cachedRow = VehicleRespawnManager.RespawnSystem.State.cachedWorldZonesByCell[cellY];
                    if cachedRow then cachedRow[cellX] = nil; end
                end
            end
        end
    end
end

function VehicleRespawnManager.RespawnSystem.ZoneManager.DetectSafehouseChanges()
    local currentSafehouses = {};
    local safehouseList = SafeHouse.getSafehouseList();

    for i = 0, safehouseList:size() - 1 do
        local safe = safehouseList:get(i);
        currentSafehouses[safe:getId()] = {
            x = safe:getX(),
            y = safe:getY(),
            w = safe:getW(),
            h = safe:getH(),
            id = safe:getId()
        };
    end

    local addedSafehouses = table.newarray() --[[@as table]]
    local removedSafehouses = table.newarray() --[[@as table]]

    local previousState = VehicleRespawnManager.RespawnSystem.State.safehouseState;

    for id, safe in pairs(currentSafehouses) do
        if not previousState[id] then
            table.insert(addedSafehouses, safe);
        end
    end

    for id, safe in pairs(previousState) do
        if not currentSafehouses[id] then
            table.insert(removedSafehouses, safe);
        end
    end

    return addedSafehouses, removedSafehouses, currentSafehouses;
end

local function pluck(tbl, key)
    local result = {};
    for i = 1, #tbl do
        table.insert(result, tbl[i][key]);
    end
    return result;
end

function VehicleRespawnManager.RespawnSystem.ZoneManager.HandleSafehouseChanges()
    local addedSafehouses, removedSafehouses, currentSafehouses = VehicleRespawnManager.RespawnSystem.ZoneManager
    .DetectSafehouseChanges();

    local changeLog = string.format(
        "Safehouse changes - added=%d removed=%d total=%d",
        #addedSafehouses,
        #removedSafehouses,
        SafeHouse.getSafehouseList():size()
    );

    if #addedSafehouses > 0 then
        VehicleRespawnManager.RespawnSystem.ZoneManager.RecacheCellsForSafehouses(addedSafehouses);
        Logger:info("%s Added: %s", changeLog, table.concat(pluck(addedSafehouses, "id"), ","));
    end

    if #removedSafehouses > 0 then
        VehicleRespawnManager.RespawnSystem.ZoneManager.RecacheCellsForSafehouses(removedSafehouses);
        Logger:info("%s Removed: %s", changeLog, table.concat(pluck(removedSafehouses, "id"), ","));
    end

    VehicleRespawnManager.RespawnSystem.State.safehouseState = currentSafehouses;
end

local lastCheckedTime = 0;
Events.EveryOneMinute.Add(function()
    local currentTime = getTimestamp();
    if currentTime - lastCheckedTime < VehicleRespawnManager.RespawnSystem.Config.SAFEHOUSE_CHECK_INTERVAL then return; end

    lastCheckedTime = currentTime;
    VehicleRespawnManager.RespawnSystem.ZoneManager.HandleSafehouseChanges();
end)

-----------------------------------------------------
-- Zone & Category Selection Logic
-----------------------------------------------------

function VehicleRespawnManager.RespawnSystem.SpawnManager.IsWater(square)
    return square:Is(IsoFlagType.water);
end

function VehicleRespawnManager.RespawnSystem.SpawnManager.IsSquareValid(square)
    local x = square:getX();
    local y = square:getY();
    local range = VehicleRespawnManager.RespawnSystem.Config.SPAWN_SQUARE_CLEAR_RANGE;

    local minX = x - range;
    local maxX = x + range;
    local minY = y - range;
    local maxY = y + range;

    local objects = square:getMovingObjects();
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i);
        if obj:getObjectName() == "Vehicle" then
            return false;
        end
    end

    for adjX = minX, maxX do
        for adjY = minY, maxY do
            if adjX ~= x or adjY ~= y then
                local adjacentSquare = getSquare(adjX, adjY, 0);
                if adjacentSquare then
                    local vehicles = adjacentSquare:getMovingObjects();
                    for i = 0, vehicles:size() - 1 do
                        local vehicle = vehicles:get(i);
                        if vehicle:getObjectName() == "Vehicle" then
                            return false;
                        end
                    end
                end
            end
        end
    end

    return true;
end

function VehicleRespawnManager.RespawnSystem.SpawnManager.CountVehiclesInZone(zone)
    local cell = getCell();
    if not cell then return 0; end

    local coords = zone.coordinates or {};

    local x1, x2 = coords.x1, coords.x2;
    local y1, y2 = coords.y1, coords.y2;

    local count = 0;
    local vehicles = cell:getVehicles();
    for i = 0, vehicles:size() - 1 do
        local v = vehicles:get(i);
        local vx, vy = v:getX(), v:getY();
        if vx >= x1 and vx <= x2 and vy >= y1 and vy <= y2 then
            count = count + 1;
        end
    end
    return count;
end

function VehicleRespawnManager.RespawnSystem.SpawnManager.ChooseVehicleCategory(zone)
    local categories = zone.vehicleSpawnCategories or {};
    local totalRate = 0;
    for _, cat in pairs(categories) do
        local rate = cat.spawnRate or 0;
        if rate > 0 then
            totalRate = totalRate + rate;
        end
    end

    if totalRate <= 0 then return nil; end

    local roll = VehicleRespawnManager.RespawnSystem.State.rand:random(totalRate);
    local cumulative = 0;
    for _, cat in pairs(categories) do
        local r = cat.spawnRate or 0;
        if r > 0 then
            cumulative = cumulative + r;
            if roll < cumulative then
                return cat;
            end
        end
    end
    return nil;
end

function VehicleRespawnManager.RespawnSystem.SpawnManager.ChooseVehicleFromCategory(category, zoneVehicleBlacklist)
    local validVehicles = table.newarray() --[[@as table]]
    for vName in pairs(category.vehicles or {}) do
        if vehicleScripts[vName] and not zoneVehicleBlacklist[vName] then
            table.insert(validVehicles, vName);
        end
    end
    if #validVehicles == 0 then
        return nil;
    end
    return validVehicles[VehicleRespawnManager.RespawnSystem.State.rand:random(#validVehicles)];
end

-- Zone priority:
-- 1. global blacklist (if exists, no spawn at all)
-- 2. global zones (first global zone)
-- 3. Non-global zones
function VehicleRespawnManager.RespawnSystem.SpawnManager.SelectZone()
    if #Zones.globalBlacklistZones > 0 then
        return nil, "globalBlacklistZones";
    end
    if #Zones.globalZones > 0 then
        return Zones.globalZones[1], "globalZones";
    end
    if #Zones.nonGlobalZones > 0 then
        return Zones.nonGlobalZones[VehicleRespawnManager.RespawnSystem.State.rand:random(#Zones.nonGlobalZones)],
            "nonGlobalZones";
    end
    return nil, "noZones";
end

-- This tries random cells until it finds at least one world vehicle zone
function VehicleRespawnManager.RespawnSystem.SpawnManager.GetRandomWorldVehicleZone()
    local world = getWorld();
    local grid = world:getMetaGrid();
    local minX = grid:getMinX();
    local minY = grid:getMinY();
    local maxX = grid:getMaxX();
    local maxY = grid:getMaxY();
    minX = (minX < 1) and 1 or minX;
    minY = (minY < 1) and 1 or minY;

    -- we limit attempts to avoid infinite loops
    for _ = 1, VehicleRespawnManager.RespawnSystem.Config.MAX_ATTEMPTS_RANDOM_VEHICLE_ZONE do
        local randomCellX = VehicleRespawnManager.RespawnSystem.State.rand:random(minX, maxX);
        local randomCellY = VehicleRespawnManager.RespawnSystem.State.rand:random(minY, maxY);
        local zones = VehicleRespawnManager.RespawnSystem.ZoneManager.GetWorldZonesForCellAt(randomCellX, randomCellY);
        if #zones > 0 then
            return zones[VehicleRespawnManager.RespawnSystem.State.rand:random(1, #zones)];
        end
    end
    return nil;
end

function VehicleRespawnManager.RespawnSystem.SpawnManager.IsPointInZone(x, y, zone)
    if not zone.coordinates then return false; end

    local coords = zone.coordinates;
    return x >= coords.x1 and x <= coords.x2 and y >= coords.y1 and y <= coords.y2;
end

function VehicleRespawnManager.RespawnSystem.SpawnManager.FindSpawnCoordinates(zone, maxAttempts)
    maxAttempts = maxAttempts or VehicleRespawnManager.RespawnSystem.Config.MAX_ATTEMPTS_REQ;

    -- if this is a global zone, ignore the player-defined coordinates and pick from a random world zone
    if zone.isGlobalZone then
        local randomWorldZoneData = VehicleRespawnManager.RespawnSystem.SpawnManager.GetRandomWorldVehicleZone();
        if not randomWorldZoneData then return "globalCoords", nil; end

        local randomWorldZone = randomWorldZoneData.zone;
        if not randomWorldZone then return "globalCoords", nil; end

        local vwzX = randomWorldZone:getX();
        local vwzY = randomWorldZone:getY();
        local vwzW = randomWorldZone:getWidth();
        local vwzH = randomWorldZone:getHeight();
        local vwzX2 = vwzX + vwzW - 1;
        local vwzY2 = vwzY + vwzH - 1;

        for _ = 1, maxAttempts do
            local x = VehicleRespawnManager.RespawnSystem.State.rand:random(vwzX, vwzX2 + 1);
            local y = VehicleRespawnManager.RespawnSystem.State.rand:random(vwzY, vwzY2 + 1);

            local isInBlacklist = false;
            for i = 1, #Zones.blacklistZones do
                local blacklistZone = Zones.blacklistZones[i];
                if VehicleRespawnManager.RespawnSystem.SpawnManager.IsPointInZone(x, y, blacklistZone) then
                    isInBlacklist = true;
                    break;
                end
            end

            if not isInBlacklist then
                return "globalCoords", { x = x, y = y, direction = randomWorldZoneData.direction };
            end
        end
        return "globalCoords", nil;
    end

    local cell = getCell();
    if not cell then return "nonGlobalCoords", nil; end

    local coords = zone.coordinates or {};
    local x1, x2 = coords.x1, coords.x2;
    local y1, y2 = coords.y1, coords.y2;

    local minCellX = math.floor(x1 / VehicleRespawnManager.RespawnSystem.Config.CELL_SIZE);
    local minCellY = math.floor(y1 / VehicleRespawnManager.RespawnSystem.Config.CELL_SIZE);

    local maxCellX = math.floor(x2 / VehicleRespawnManager.RespawnSystem.Config.CELL_SIZE);
    local maxCellY = math.floor(y2 / VehicleRespawnManager.RespawnSystem.Config.CELL_SIZE);

    if x1 <= 0 or x2 <= 0 or y1 <= 0 or y2 <= 0 then return "nonGlobalCoords", nil; end

    local possibleIntersections = table.newarray() --[[@as table]]

    for cx = minCellX, maxCellX do
        for cy = minCellY, maxCellY do
            local vehicleWorldZones = VehicleRespawnManager.RespawnSystem.ZoneManager.GetWorldZonesForCellAt(cx, cy);
            for i = 1, #vehicleWorldZones do
                local vwz = vehicleWorldZones[i].zone;
                local vwzX = vwz:getX();
                local vwzY = vwz:getY();
                local vwzW = vwz:getWidth();
                local vwzH = vwz:getHeight();

                local vwzX2 = vwzX + vwzW - 1;
                local vwzY2 = vwzY + vwzH - 1;

                local interX1 = (x1 > vwzX) and x1 or vwzX;
                local interX2 = (x2 < vwzX2) and x2 or vwzX2;
                local interY1 = (y1 > vwzY) and y1 or vwzY;
                local interY2 = (y2 < vwzY2) and y2 or vwzY2;

                if interX1 <= interX2 and interY1 <= interY2 then
                    table.insert(possibleIntersections,
                        {
                            x1 = interX1,
                            y1 = interY1,
                            x2 = interX2,
                            y2 = interY2,
                            direction = vehicleWorldZones[i].direction
                        }
                    );
                end
            end
        end
    end

    if #possibleIntersections == 0 then return "nonGlobalCoords", nil; end

    local chosen = possibleIntersections[VehicleRespawnManager.RespawnSystem.State.rand:random(#possibleIntersections)];

    for _ = 1, maxAttempts do
        local x = VehicleRespawnManager.RespawnSystem.State.rand:random(chosen.x1, chosen.x2 + 1);
        local y = VehicleRespawnManager.RespawnSystem.State.rand:random(chosen.y1, chosen.y2 + 1);
        local square = cell:getOrCreateGridSquare(x, y, 0);

        if square and square:getChunk() ~= nil and VehicleRespawnManager.RespawnSystem.SpawnManager.IsSquareValid(square) and not VehicleRespawnManager.RespawnSystem.SpawnManager.IsWater(square) then
            local isInBlacklist = false;
            for i = 1, #Zones.blacklistZones do
                local blacklistZone = Zones.blacklistZones[i];
                if VehicleRespawnManager.RespawnSystem.SpawnManager.IsPointInZone(x, y, blacklistZone) then
                    isInBlacklist = true;
                    break;
                end
            end

            if not isInBlacklist then
                return "nonGlobalCoords", { x = x, y = y, direction = chosen.direction };
            end
        end
    end
    return "nonGlobalCoords", nil;
end

-----------------------------------------------------
-- Spawn Attempt and Handling
-----------------------------------------------------

local function parseIntervalString(intervalString)
    local minEngineQuality, maxEngineQuality = 1, 100;

    if intervalString then
        local splitValues = {};
        for value in string.gmatch(intervalString, "([^;]+)") do
            table.insert(splitValues, tonumber(value));
        end

        if #splitValues == 1 then
            minEngineQuality, maxEngineQuality = splitValues[1], splitValues[1];
        elseif #splitValues == 2 then
            minEngineQuality, maxEngineQuality = math.min(splitValues[1], splitValues[2]),
                math.max(splitValues[1], splitValues[2]);
        end
    end

    return minEngineQuality, maxEngineQuality;
end

function VehicleRespawnManager.RespawnSystem.SpawnManager.SpawnVehicleAt(spawnRequestData)
    local logBase = formatRequest(spawnRequestData);

    local canSpawn, reason = true, nil;

    local cell = getCell();
    if not cell then
        canSpawn, reason = false, "noCell";
    end

    local square = cell:getOrCreateGridSquare(spawnRequestData.x, spawnRequestData.y, 0);
    if not square then
        canSpawn, reason = false, "noSquare";
    end

    if square:getChunk() == nil then
        canSpawn, reason = false, "chunkNotLoaded";
    end

    if not VehicleRespawnManager.RespawnSystem.SpawnManager.IsSquareValid(square) then
        canSpawn, reason = false, "occupied";
    end

    if canSpawn then
        local dir = IsoDirections.Max;
        dir = IsoDirections[spawnRequestData.direction] or IsoDirections.Max;
        ---@diagnostic disable-next-line: param-type-mismatch
        local vehicle = addVehicleDebug(spawnRequestData.vehicleScript, dir, nil, square);

        for i = 0, vehicle:getPartCount() do
            local part = vehicle:getPartByIndex(i);
            if part and part:getLuaFunction("create") then
                VehicleUtils.callLua(part:getLuaFunction("create"), vehicle, part);
            end
        end

        local intervalString = SandboxVars.VehicleRespawnManager.engineQuality or
            VehicleRespawnManager.RespawnSystem.Config.DEFAULT_ENGINE_QUALITY;
        local minEngineQuality, maxEngineQuality = parseIntervalString(intervalString);

        local vehicleScript = vehicle:getScript();

        local engineQuality, engineLoudness, enginePower = 100, 30, vehicleScript:getEngineForce();
        if SandboxVars.VehicleEasyUse then
            vehicle:setEngineFeature(engineQuality, engineLoudness, enginePower);
        else
            local randomizedQuality = VehicleRespawnManager.RespawnSystem.State.rand:random(minEngineQuality,
                maxEngineQuality)
            engineQuality = VehicleRespawnManager.RespawnSystem.State.rand:random(
                math.max(minEngineQuality, randomizedQuality - 10),
                math.min(maxEngineQuality, randomizedQuality + 10)
            );

            engineQuality = (engineQuality < minEngineQuality) and minEngineQuality or
                ((engineQuality > maxEngineQuality) and maxEngineQuality or engineQuality);

            engineLoudness = (vehicleScript:getEngineLoudness() or 100) *
                (SandboxVars.ZombieAttractionMultiplier or 1);

            local qualityBoosted = engineQuality * 1.6;
            qualityBoosted = (qualityBoosted > 100) and 100 or qualityBoosted;
            local qualityModifier = (qualityBoosted / 100);
            qualityModifier = (qualityModifier < 0.6) and 0.6 or qualityModifier;
            enginePower = vehicleScript:getEngineForce() * qualityModifier;

            vehicle:setEngineFeature(engineQuality, engineLoudness, enginePower);
        end

        Logger:debug("%s Spawned successfully: %s", logBase, string.format(
            "engineQuality=%d engineLoudness=%d enginePower=%d",
            engineQuality,
            engineLoudness,
            enginePower
        ))
    else
        Logger:warn("%s Spawn failed: %s", logBase, reason);
    end

    if spawnRequestData.requestId then
        local globalModData = VehicleRespawnManager.RespawnSystem.ModDataManager.getModData()
        local request = globalModData.RequestsById[spawnRequestData.requestId];
        if request then
            request.status = canSpawn and Constants.CONFIG.REQUEST_STATUS.COMPLETED or
                Constants.CONFIG.REQUEST_STATUS.FAILED;
            request.failureReason = reason;
        end
    end

    return canSpawn, reason;
end

-- Process a single spawn request from the queue
function VehicleRespawnManager.RespawnSystem.SpawnManager.ProcessRequest(req)
    local globalModData = VehicleRespawnManager.RespawnSystem.ModDataManager.getModData();
    local request = globalModData.RequestsById[req.id];
    if not request then return; end

    request.status = Constants.CONFIG.REQUEST_STATUS.PROCESSING;
    request.attempt = request.attempt or 0;
    request.attempt = request.attempt + 1;
    if request.attempt > VehicleRespawnManager.RespawnSystem.Config.MAX_ATTEMPTS_REQ then
        request.status = Constants.CONFIG.REQUEST_STATUS.FAILED;
        request.failureReason = "MAX_ATTEMPTS_EXCEEDED";

        Logger:debug("%s Processing request failed. Reason: %s", formatRequest(request), request.failureReason);
        return;
    end

    local zone, zoneType = VehicleRespawnManager.RespawnSystem.SpawnManager.SelectZone();
    if not zone then
        Logger:warn(
            "%s Zone selection failed: #globalZones=%d #nonGlobalZones=%d #globalBlacklistZones=%d. Requeuing.",
            formatRequest(request), #Zones.globalZones, #Zones.nonGlobalZones, #Zones.globalBlacklistZones
        );
        return "REQUEUE";
    end

    local zoneName = zone.name or "UnnamedZone";

    local maxCount = zone.maxVehicleCount or 999;
    local currentCount = VehicleRespawnManager.RespawnSystem.SpawnManager.CountVehiclesInZone(zone);
    if currentCount >= maxCount then return "REQUEUE"; end
    Logger:debug("%s Selected zone: %s (maxCount=%d currentCount=%d)", formatRequest(request), zone.name, maxCount,
        currentCount);

    local vehicleScript = request.fixedScript;
    local categoryName = "NoCategory";
    if not vehicleScript then
        local category = VehicleRespawnManager.RespawnSystem.SpawnManager.ChooseVehicleCategory(zone);
        if not category and zone.useDefaultCategoryForUnassigned and zone.defaultCategoryNameForUnassigned then
            for _, catData in pairs(zone.vehicleSpawnCategories or {}) do
                if catData.name == zone.defaultCategoryNameForUnassigned then
                    category = catData;
                    break;
                end
            end
        end

        if not category then return "REQUEUE"; end

        categoryName = category.name;
        vehicleScript = VehicleRespawnManager.RespawnSystem.SpawnManager.ChooseVehicleFromCategory(category,
            zone.zoneVehicleBlacklist);
        if not vehicleScript then
            Logger:debug(
                "%s Failed to select vehicleScript for zone=%s, category=%s, useDefault=%s, defaultCategory=%s. Requeuing.",
                formatRequest(request), zoneName, categoryName, tostring(zone.useDefaultCategoryForUnassigned),
                zone.defaultCategoryNameForUnassigned or "none"
            );
            return "REQUEUE";
        end
    else
        if not vehicleScripts[vehicleScript] then
            Logger:debug(
                "%s vehicleScript for zone=%s, category=%s, useDefault=%s, defaultCategory=%s is invalid. Requeuing.",
                formatRequest(request), zoneName, categoryName, tostring(zone.useDefaultCategoryForUnassigned),
                zone.defaultCategoryNameForUnassigned or "none"
            );
            return "REQUEUE";
        end
    end

    local coordsType, spawnCoords = VehicleRespawnManager.RespawnSystem.SpawnManager.FindSpawnCoordinates(zone);
    local direction = "Max";

    if spawnCoords and spawnCoords.direction then direction = tostring(spawnCoords.direction); end

    if spawnCoords and (spawnCoords.x and spawnCoords.y) then
        local timedSpawnRequest = {
            id = req.id,
            type = request.type,
            fixedScript = req.fixedScript,
            vehicleScript = vehicleScript,
            x = spawnCoords.x,
            y = spawnCoords.y,
            time = getTimestamp() + VehicleRespawnManager.RespawnSystem.Config.TIMED_SPAWNS_SPAWN_DELAY,
            attempt = request.attempt,
            direction = direction,
            status = Constants.CONFIG.REQUEST_STATUS.PROCESSING
        };
        table.insert(globalModData.TimedSpawns, timedSpawnRequest);
        globalModData.RequestsById[req.id] = timedSpawnRequest;
        return;
    else
        request.status = Constants.CONFIG.REQUEST_STATUS.PROCESSING;
        return "REQUEUE";
    end
end

-----------------------------------------------------
-- Periodic Processing
-----------------------------------------------------
function VehicleRespawnManager.RespawnSystem.SpawnManager.ProcessQueues()
    local now = getTimestamp();
    if now - VehicleRespawnManager.RespawnSystem.State.lastQueueProcessTime < VehicleRespawnManager.RespawnSystem.Config.QUEUE_PROCESS_INTERVAL then
        return;
    end
    VehicleRespawnManager.RespawnSystem.State.lastQueueProcessTime = now;

    local globalModData = VehicleRespawnManager.RespawnSystem.ModDataManager.getModData();

    if #globalModData.SpawnRequestsQueue > 0 then
        local request = table.remove(globalModData.SpawnRequestsQueue, 1);
        local action = VehicleRespawnManager.RespawnSystem.SpawnManager.ProcessRequest(request);
        if action == "REQUEUE" then
            table.insert(globalModData.SpawnRequestsQueue, request);
        end
    end

    local processedTimedSpawns = 0;
    for i = #globalModData.TimedSpawns, 1, -1 do
        if processedTimedSpawns >= VehicleRespawnManager.RespawnSystem.Config.MAX_TIMED_SPAWNS_PROCESSED then
            break;
        end

        local spawnRequestData = globalModData.TimedSpawns[i];
        if now >= spawnRequestData.time then
            local canSpawn, reason = VehicleRespawnManager.RespawnSystem.SpawnManager.SpawnVehicleAt(spawnRequestData);
            if canSpawn then
                table.remove(globalModData.TimedSpawns, i);
            else
                spawnRequestData.attempt = spawnRequestData.attempt + 1;
                if spawnRequestData.attempt > VehicleRespawnManager.RespawnSystem.Config.MAX_ATTEMPTS_REQ then
                    spawnRequestData.status = Constants.CONFIG.REQUEST_STATUS.FAILED;
                    spawnRequestData.failureReason = "MAX_ATTEMPTS_EXCEEDED";

                    table.remove(globalModData.TimedSpawns, i);

                    Logger:debug("%s Processing request failed. Reason: %s", formatRequest(spawnRequestData),
                        spawnRequestData.failureReason);
                else
                    if reason == "noCell" or reason == "chunkNotLoaded" or reason == "noSquare" then
                        local key = spawnRequestData.x .. "_" .. spawnRequestData.y;
                        globalModData.LocationPendingSpawns[key] = spawnRequestData;
                        table.remove(globalModData.TimedSpawns, i);

                        Logger:debug("%s Timed Spawn moved to Location Pending Spawn. Reason: %s",
                            formatRequest(spawnRequestData), reason);
                    elseif reason == "occupied" then
                        table.remove(globalModData.TimedSpawns, i);

                        local request = spawnRequestData;
                        request.status = VehicleRespawnManager.RespawnSystem.Config.REQUEST_STATUS.PENDING;
                        request.timestamp = getTimestamp();

                        table.insert(globalModData.SpawnRequestsQueue, request);
                    else
                        spawnRequestData.time = now + VehicleRespawnManager.RespawnSystem.Config
                            .TIMED_SPAWNS_SPAWN_DELAY;
                        Logger:debug("%s Timed Spawn retry after delay. Reason: %s", formatRequest(spawnRequestData),
                            reason);
                    end
                end
            end
            processedTimedSpawns = processedTimedSpawns + 1;
        end
    end
end

Events.OnTick.Add(VehicleRespawnManager.RespawnSystem.SpawnManager.ProcessQueues);



-- On grid square load, try LocationPendingSpawns
function VehicleRespawnManager.RespawnSystem.SpawnManager.OnLoadGridsquare(square)
    local globalModData = VehicleRespawnManager.RespawnSystem.ModDataManager.getModData();
    local key = square:getX() .. "_" .. square:getY();
    local spawnRequestData = globalModData.LocationPendingSpawns[key];
    if spawnRequestData then
        local canSpawn, reason = VehicleRespawnManager.RespawnSystem.SpawnManager.SpawnVehicleAt(spawnRequestData);
        if canSpawn then
            globalModData.LocationPendingSpawns[key] = nil;
        else
            spawnRequestData.attempt = spawnRequestData.attempt + 1;
            if spawnRequestData.attempt > VehicleRespawnManager.RespawnSystem.Config.MAX_ATTEMPTS_REQ then
                globalModData.LocationPendingSpawns[key] = nil;

                spawnRequestData.status = Constants.CONFIG.REQUEST_STATUS.FAILED;
                spawnRequestData.failureReason = "MAX_ATTEMPTS_EXCEEDED";

                Logger:debug("%s Location Pending Spawn failed. Reason: %s", formatRequest(spawnRequestData),
                    spawnRequestData.failureReason);
            else
                if reason == "occupied" then
                    globalModData.LocationPendingSpawns[key] = nil;

                    local request = spawnRequestData;
                    request.status = VehicleRespawnManager.RespawnSystem.Config.REQUEST_STATUS.PENDING;
                    request.timestamp = getTimestamp();

                    table.insert(globalModData.SpawnRequestsQueue, request);

                    Logger:debug("%s Location Pending Spawn was requeued. Reason: %s", formatRequest(request), reason);
                end
            end
        end
    end
end

Events.LoadGridsquare.Add(VehicleRespawnManager.RespawnSystem.SpawnManager.OnLoadGridsquare);


-----------------------------------------------------
-- Public API for queueing spawns
-----------------------------------------------------

function VehicleRespawnManager.RespawnSystem.SpawnManager.GenerateRequestId()
    local globalModData = VehicleRespawnManager.RespawnSystem.ModDataManager.getModData();
    globalModData.LastRequestId = globalModData.LastRequestId + 1;

    local timestamp = tostring(getTimestamp());
    local counter = string.format("%06d", globalModData.LastRequestId);

    return timestamp .. "_" .. counter;
end

function VehicleRespawnManager.RespawnSystem.SpawnManager.QueueRandomVehicle()
    local requestId = VehicleRespawnManager.RespawnSystem.SpawnManager.GenerateRequestId();
    local globalModData = VehicleRespawnManager.RespawnSystem.ModDataManager.getModData();

    local request = {
        id = requestId,
        type = "random",
        status = VehicleRespawnManager.RespawnSystem.Config.REQUEST_STATUS.PENDING,
        timestamp = getTimestamp(),
        attempt = 0
    };

    table.insert(globalModData.SpawnRequestsQueue, request);
    globalModData.RequestsById[requestId] = request;

    return requestId;
end

function VehicleRespawnManager.RespawnSystem.SpawnManager.QueueFixedVehicle(scriptName)
    local requestId = VehicleRespawnManager.RespawnSystem.SpawnManager.GenerateRequestId();
    local globalModData = VehicleRespawnManager.RespawnSystem.ModDataManager.getModData();

    local request = {
        id = requestId,
        type = "fixed",
        fixedScript = scriptName,
        status = VehicleRespawnManager.RespawnSystem.Config.REQUEST_STATUS.PENDING,
        timestamp = getTimestamp(),
        attempt = 0
    };

    table.insert(globalModData.SpawnRequestsQueue, request);
    globalModData.RequestsById[requestId] = request;

    return requestId;
end

function VehicleRespawnManager.RespawnSystem.SpawnManager.QueueMultipleRandom(count)
    for i = 1, count do
        VehicleRespawnManager.RespawnSystem.SpawnManager.QueueRandomVehicle();
    end
end

function VehicleRespawnManager.RespawnSystem.SpawnManager.QueueMultipleFixed(scriptName, count)
    for i = 1, count do
        VehicleRespawnManager.RespawnSystem.SpawnManager.QueueFixedVehicle(scriptName);
    end
end
