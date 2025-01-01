local Reflection = require("Starlit/utils/Reflection");
local Globals = require("Starlit/Globals");

local Logger = require("ElyonLib/Logger"):new("Vehicle Respawn Manager");

if Globals.isClient then return; end

local VehicleRespawnManager = require("VehicleRespawnManager/Shared");
VehicleRespawnManager.RespawnSystem = {};

VehicleRespawnManager.RespawnSystem.CachedWorldZonesByCell = table.newarray();

VehicleRespawnManager.RespawnSystem.GlobalBlacklistZones = table.newarray();
VehicleRespawnManager.RespawnSystem.GlobalZones = table.newarray();
VehicleRespawnManager.RespawnSystem.BlacklistZones = table.newarray();
VehicleRespawnManager.RespawnSystem.NonGlobalZones = table.newarray();

VehicleRespawnManager.RespawnSystem.MaxAttempts = 20;
VehicleRespawnManager.RespawnSystem.LastProcessTime = 0;
VehicleRespawnManager.RespawnSystem.ProcessInterval = 1000;

local CELL_SIZE = 300;
local rand = newrandom();


-----------------------------------------------------
-- Utility & Data Access
-----------------------------------------------------

function VehicleRespawnManager.RespawnSystem.getGMD()
    local gmd = ModData.getOrCreate("VehicleRespawnManagerData");
    if not gmd.SpawnRequestsQueue then gmd.SpawnRequestsQueue = {}; end
    if not gmd.LocationPendingSpawns then gmd.LocationPendingSpawns = {}; end
    if not gmd.TimedSpawns then gmd.TimedSpawns = {}; end
    return gmd;
end

local function getTimestamp()
    return Calendar.getInstance():getTimeInMillis();
end


-----------------------------------------------------
-- Zone Initialization & Category Processing
-----------------------------------------------------
-- Process default category for unassigned vehicles, taking into account zone blacklist.

function VehicleRespawnManager.RespawnSystem.InitZones()
    local originalZones = VehicleRespawnManager.Shared.RequestZones() or {};
    local zones = copyTable(originalZones);

    local GlobalBlacklistZones = table.newarray() --[[@as table]]
    local GlobalZones = table.newarray() --[[@as table]]
    local BlacklistZones = table.newarray() --[[@as table]]
    local NonGlobalZones = table.newarray() --[[@as table]]

    local insert = table.insert;
    local vehicleScripts = VehicleRespawnManager.Shared.VehicleScripts;

    for i = 1, #zones do
        local zone = zones[i];
        local isGlobal = zone.isGlobalZone;
        local isBlacklist = zone.isBlacklistZone;

        if isBlacklist and isGlobal then
            insert(GlobalBlacklistZones, zone);
        elseif isGlobal then
            insert(GlobalZones, zone);
        elseif isBlacklist then
            insert(BlacklistZones, zone);
        else
            insert(NonGlobalZones, zone);
        end

        -- if zone uses a default category for unassigned vehicles, fill that category with unassigned vehicles
        if zone.useDefaultCategoryForUnassigned then
            local defaultCatName = zone.defaultCategoryNameForUnassigned;
            if defaultCatName and defaultCatName ~= "None" then
                local categories = zone.vehicleSpawnCategories;
                if categories then
                    local defaultCategory = nil;
                    local assignedVehicles = {};

                    for _, catData in pairs(categories) do
                        local catVehicles = catData.vehicles;
                        if catData.name == defaultCatName then
                            defaultCategory = catData;
                        end
                        if catVehicles then
                            for vName in pairs(catVehicles) do
                                assignedVehicles[vName] = true;
                            end
                        end
                    end

                    if defaultCategory then
                        local defaultVehicles = defaultCategory.vehicles or {};
                        defaultCategory.vehicles = defaultVehicles;

                        for scriptName in pairs(vehicleScripts) do
                            if not assignedVehicles[scriptName] then
                                defaultVehicles[scriptName] = true;
                            end
                        end
                    end
                end
            end
        end
    end

    VehicleRespawnManager.RespawnSystem.GlobalBlacklistZones = GlobalBlacklistZones;
    VehicleRespawnManager.RespawnSystem.GlobalZones = GlobalZones;
    VehicleRespawnManager.RespawnSystem.BlacklistZones = BlacklistZones;
    VehicleRespawnManager.RespawnSystem.NonGlobalZones = NonGlobalZones;
end

function VehicleRespawnManager.RespawnSystem.InitOptions()
    local optionsVars = SandboxVars.VehicleRespawnManager;

    if optionsVars then
        local logLevel = optionsVars.enableLogging and "DEBUG" or "INFO";
        Logger:setLogLevel(logLevel);
    end
end

Events.OnInitGlobalModData.Add(function()
    VehicleRespawnManager.RespawnSystem.InitZones();
    VehicleRespawnManager.RespawnSystem.InitOptions();
end);

-----------------------------------------------------
-- World Cell Zones Retrieval & Utility
-----------------------------------------------------

local vehicleZonesDirByName = {
    ["trafficjams"] = "S",
    ["trafficjamn"] = "N",
    ["trafficjame"] = "E",
    ["trafficjamw"] = "W",
    ["rtrafficjams"] = "S",
    ["rtrafficjamn"] = "N",
    ["rtrafficjame"] = "E",
    ["rtrafficjamw"] = "W"
}

-- Utility function to check if a vehicle zone is within a buffer zone of any safehouse
function VehicleRespawnManager.RespawnSystem.IsZoneNearSafehouse(zone)
    local buffer = 5;

    for i = 0, SafeHouse.getSafehouseList():size() - 1 do
        local safe = SafeHouse.getSafehouseList():get(i);

        local safeX = safe:getX();
        local safeY = safe:getY();
        local safeW = safe:getW();
        local safeH = safe:getH();

        local bufferX1 = safeX - buffer;
        local bufferY1 = safeY - buffer;
        local bufferX2 = safeX + safeW + buffer;
        local bufferY2 = safeY + safeH + buffer;

        local zoneX1 = zone:getX();
        local zoneY1 = zone:getY();
        local zoneX2 = zoneX1 + zone:getWidth();
        local zoneY2 = zoneY1 + zone:getHeight();

        local intersectX = (zoneX1 >= bufferX1 and zoneX1 or bufferX1) <= (zoneX2 <= bufferX2 and zoneX2 or bufferX2);
        local intersectY = (zoneY1 >= bufferY1 and zoneY1 or bufferY1) <= (zoneY2 <= bufferY2 and zoneY2 or bufferY2);

        if intersectX and intersectY then return true; end
    end
    return false;
end

function VehicleRespawnManager.RespawnSystem.GetWorldZonesForCellAt(cellx, celly)
    local cacheY = VehicleRespawnManager.RespawnSystem.CachedWorldZonesByCell[celly];
    if cacheY then
        local cacheX = cacheY[cellx];
        if cacheX then
            return cacheX;
        end
    else
        VehicleRespawnManager.RespawnSystem.CachedWorldZonesByCell[celly] = table.newarray() --[[@as table]]
    end

    local world = getWorld();
    local grid = world:getMetaGrid();
    local cellData = grid:getCellDataAbs(cellx, celly);

    local zones = Reflection.getUnexposedObjectField(cellData, "vehicleZones");
    local cellVehicleZones = table.newarray() --[[@as table]]

    for i = 0, zones:size() - 1 do
        local zone = zones:get(i);
        local substring = string.sub(tostring(zone), 1, 34);
        if substring == "zombie.iso.IsoMetaGrid$VehicleZone" then
            local zoneName = zone:getName();
            local zoneDir = zone.dir;
            if vehicleZonesDirByName[zoneName] then
                zoneDir = vehicleZonesDirByName[zoneName];
            end

            -- check if the zone is near any safehouse; if so, skip it
            if not VehicleRespawnManager.RespawnSystem.IsZoneNearSafehouse(zone) then
                table.insert(cellVehicleZones, { zone = zone, direction = zoneDir });
            end
        end
    end

    VehicleRespawnManager.RespawnSystem.CachedWorldZonesByCell[celly][cellx] = cellVehicleZones;
    return cellVehicleZones;
end

-----------------------------------------------------
-- Zone & Category Selection Logic
-----------------------------------------------------

function VehicleRespawnManager.RespawnSystem.IsWater(square)
    return square:Is(IsoFlagType.water);
end

function VehicleRespawnManager.RespawnSystem.TestSquare(square)
    local x = square:getX();
    local y = square:getY();
    local z = square:getZ();
    local range = 3;

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
                local adjacentSquare = getSquare(adjX, adjY, z);
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

function VehicleRespawnManager.RespawnSystem.CountVehiclesInZone(zone)
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

function VehicleRespawnManager.RespawnSystem.ChooseVehicleCategory(zone)
    local categories = zone.vehicleSpawnCategories or {};
    local totalRate = 0;
    for _, cat in pairs(categories) do
        local rate = cat.spawnRate or 0;
        if rate > 0 then
            totalRate = totalRate + rate;
        end
    end

    if totalRate <= 0 then return nil; end

    local roll = rand:random(totalRate);
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

function VehicleRespawnManager.RespawnSystem.ChooseVehicleFromCategory(category)
    local validVehicles = table.newarray() --[[@as table]]
    for vName in pairs(category.vehicles or {}) do
        if VehicleRespawnManager.Shared.VehicleScripts[vName] then
            table.insert(validVehicles, vName);
        end
    end
    if #validVehicles == 0 then
        return nil;
    end
    return validVehicles[rand:random(#validVehicles)];
end

-- Zone priority:
-- 1. Global blacklist (if exists, no spawn at all)
-- 2. Global zones
-- 3. Non-global zones
function VehicleRespawnManager.RespawnSystem.SelectZone()
    if #VehicleRespawnManager.RespawnSystem.GlobalBlacklistZones > 0 then
        return nil, "globalBlacklist";
    end
    if #VehicleRespawnManager.RespawnSystem.GlobalZones > 0 then
        return VehicleRespawnManager.RespawnSystem.GlobalZones[1], "global";
    end
    if #VehicleRespawnManager.RespawnSystem.NonGlobalZones > 0 then
        return
            VehicleRespawnManager.RespawnSystem.NonGlobalZones
            [rand:random(#VehicleRespawnManager.RespawnSystem.NonGlobalZones)], "nonGlobal";
    end
    return nil, "noZones";
end

-- This tries random cells until it finds at least one world vehicle zone
local function GetRandomWorldVehicleZone()
    local world = getWorld();
    local grid = world:getMetaGrid();
    local minX = grid:getMinX();
    local minY = grid:getMinY();
    local maxX = grid:getMaxX();
    local maxY = grid:getMaxY();
    minX = (minX < 1) and 1 or minX;
    minY = (minY < 1) and 1 or minY;

    -- we limit attempts to avoid infinite loops
    for _ = 1, 20 do
        local randomCellX = rand:random(minX, maxX);
        local randomCellY = rand:random(minY, maxY);
        local zones = VehicleRespawnManager.RespawnSystem.GetWorldZonesForCellAt(randomCellX, randomCellY);
        if #zones > 0 then
            return zones[rand:random(1, #zones)];
        end
    end
    return nil;
end

function VehicleRespawnManager.RespawnSystem.IsPointInZone(x, y, zone)
    if not zone.coordinates then return false; end

    local coords = zone.coordinates;
    return x >= coords.x1 and x <= coords.x2 and y >= coords.y1 and y <= coords.y2;
end

function VehicleRespawnManager.RespawnSystem.FindSpawnCoordinates(zone, maxAttempts)
    maxAttempts = maxAttempts or VehicleRespawnManager.RespawnSystem.MaxAttempts;
    local cell = getCell();
    if not cell then return nil; end

    -- if this is a global zone, ignore the player-defined coordinates and pick from a random world zone
    if zone.isGlobalZone then
        local randomWorldZoneData = GetRandomWorldVehicleZone();
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
            local x = rand:random(vwzX, vwzX2 + 1);
            local y = rand:random(vwzY, vwzY2 + 1);

            local isInBlacklist = false;
            for i = 1, #VehicleRespawnManager.RespawnSystem.BlacklistZones do
                local blacklistZone = VehicleRespawnManager.RespawnSystem.BlacklistZones[i];
                if VehicleRespawnManager.RespawnSystem.IsPointInZone(x, y, blacklistZone) then
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

    local coords = zone.coordinates or {};
    local x1, x2 = coords.x1, coords.x2;
    local y1, y2 = coords.y1, coords.y2;

    local minCellX = math.floor(x1 / CELL_SIZE);
    local minCellY = math.floor(y1 / CELL_SIZE);

    local maxCellX = math.floor(x2 / CELL_SIZE);
    local maxCellY = math.floor(y2 / CELL_SIZE);

    if x1 <= 0 or x2 <= 0 or y1 <= 0 or y2 <= 0 then return "nonGlobalCoords", nil; end

    local possibleIntersections = table.newarray() --[[@as table]]

    for cx = minCellX, maxCellX do
        for cy = minCellY, maxCellY do
            local vehicleWorldZones = VehicleRespawnManager.RespawnSystem.GetWorldZonesForCellAt(cx, cy);
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
                            direction = vehicleWorldZones[i]
                                .direction
                        }
                    );
                end
            end
        end
    end

    if #possibleIntersections == 0 then return "nonGlobalCoords", nil; end

    local chosen = possibleIntersections[rand:random(#possibleIntersections)];

    for _ = 1, maxAttempts do
        local x = rand:random(chosen.x1, chosen.x2 + 1);
        local y = rand:random(chosen.y1, chosen.y2 + 1);
        local square = cell:getOrCreateGridSquare(x, y, 0);

        if square and square:getChunk() ~= nil
            and VehicleRespawnManager.RespawnSystem.TestSquare(square)
            and not VehicleRespawnManager.RespawnSystem.IsWater(square) then
            local isInBlacklist = false;
            for i = 1, #VehicleRespawnManager.RespawnSystem.BlacklistZones do
                local blacklistZone = VehicleRespawnManager.RespawnSystem.BlacklistZones[i];
                if VehicleRespawnManager.RespawnSystem.IsPointInZone(x, y, blacklistZone) then
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

function VehicleRespawnManager.RespawnSystem.SpawnVehicleAt(vehicleScript, x, y, direction)
    local cell = getCell();
    if not cell then return false, "noCell"; end

    local square = cell:getOrCreateGridSquare(x, y, 0);
    if not square then return false, "noSquare"; end

    if square:getChunk() == nil then return false, "chunkNotLoaded"; end

    if not VehicleRespawnManager.RespawnSystem.TestSquare(square) then return false, "occupied"; end

    Logger:debug("Spawning vehicle \"%s\" at %d,%d.", vehicleScript, x, y);

    local dir = IsoDirections.Max;
    dir = IsoDirections[direction] or IsoDirections.Max;

    ---@diagnostic disable-next-line: param-type-mismatch
    addVehicleDebug(vehicleScript, dir, nil, square);

    return true;
end

function VehicleRespawnManager.RespawnSystem.AttemptSpawnDetermined(vehicleScript, x, y, attempt, direction, zoneName,
                                                                    category)
    attempt = attempt or 0;
    local gmd = VehicleRespawnManager.RespawnSystem.getGMD();
    local success, reason = VehicleRespawnManager.RespawnSystem.SpawnVehicleAt(vehicleScript, x, y, direction);
    if not success then
        attempt = attempt + 1;
        if attempt > VehicleRespawnManager.RespawnSystem.MaxAttempts then
            Logger:debug(
                "Max attempts exceeded for spawn at %d,%d for vehicle \"%s\" in zone \"%s\" (category=%s), removing request.",
                x, y, vehicleScript, zoneName or "Unknown", category or "No Category");
            return
        end

        if reason == "chunkNotLoaded" or reason == "occupied" or reason == "noSquare" then
            local key = x .. "_" .. y;
            gmd.LocationPendingSpawns[key] = {
                vehicleScript = vehicleScript,
                x = x,
                y = y,
                attempt = attempt,
                direction = direction
            };
            Logger:debug("Spawn Location Pending at %d,%d for \"%s\" in zone \"%s\" (category=%s). Reason: %s",
                x, y, vehicleScript, zoneName or "Unknown", category or "No Category", reason);
        else
            local newTime = getTimestamp() + 1000;
            table.insert(gmd.TimedSpawns, {
                vehicleScript = vehicleScript,
                x = x,
                y = y,
                time = newTime,
                attempt = attempt,
                direction = direction
            });
            Logger:debug("Spawn scheduling retry after delay for \"%s\" at %d,%d in zone \"%s\" (Global=%s). Reason: %s",
                vehicleScript, x, y, zoneName or "Unknown", category or "No Category", reason);
        end
    end
end

-- Process a single spawn request from the queue
function VehicleRespawnManager.RespawnSystem.ProcessSingleRequest(req)
    req.attempt = req.attempt or 0;
    req.attempt = req.attempt + 1;
    if req.attempt > VehicleRespawnManager.RespawnSystem.MaxAttempts then
        Logger:debug("Request exceeded max attempts, removing. Request type=\"%s\" fixedScript=\"%s\"",
            req.type, req.fixedScript or "N/A");
        return;
    end

    local zone, zoneType = VehicleRespawnManager.RespawnSystem.SelectZone();
    if not zone then
        Logger:debug(
            "Request re-queued. Will attempt again next cycle. No suitable zone found for spawn request (type=\"%s\", fixedScript=\"%s\"). ZoneType=%s Attempt=%d",
            req.type, req.fixedScript or "N/A", zoneType, req.attempt);
        return "REQUEUE";
    end

    local zoneName = zone.name or "UnnamedZone";
    Logger:debug(
        "Selected zone \"%s\" for request (type=\"%s\", fixedScript=\"%s\"), attempt=%d",
        zoneName, req.type, req.fixedScript or "N/A", req.attempt);

    local maxCount = zone.maxVehicleCount or 999;
    local currentCount = VehicleRespawnManager.RespawnSystem.CountVehiclesInZone(zone);
    if currentCount >= maxCount then
        Logger:debug(
            "Zone \"%s\" max vehicle count reached (%d/%d), attempt=%d. Re-queueing.",
            zoneName, currentCount, maxCount, req.attempt);
        return "REQUEUE";
    end

    local vehicleScript = req.fixedScript;
    local categoryName = "NoCategory";
    if not vehicleScript then
        local category = VehicleRespawnManager.RespawnSystem.ChooseVehicleCategory(zone);
        if not category and zone.useDefaultCategoryForUnassigned and zone.defaultCategoryNameForUnassigned then
            for _, catData in pairs(zone.vehicleSpawnCategories or {}) do
                if catData.name == zone.defaultCategoryNameForUnassigned then
                    category = catData;
                    break;
                end
            end
        end

        if not category then
            Logger:debug(
                "No valid category found in zone \"%s\", attempt=%d. Re-queueing.",
                zoneName, req.attempt);
            return "REQUEUE";
        end

        categoryName = category.name;
        vehicleScript = VehicleRespawnManager.RespawnSystem.ChooseVehicleFromCategory(category);
        if not vehicleScript then
            Logger:debug(
                "No valid vehicle found in category \"%s\" in zone \"%s\", attempt=%d. Re-queueing.",
                categoryName, zoneName, req.attempt);
            return "REQUEUE";
        end
    else
        if not VehicleRespawnManager.Shared.VehicleScripts[vehicleScript] then
            Logger:debug(
                "Invalid fixedScript=\"%s\" in zone \"%s\", attempt=%d. Re-queueing.",
                vehicleScript, zoneName, req.attempt);
            return "REQUEUE";
        end
    end

    local coordsType, spawnCoords = VehicleRespawnManager.RespawnSystem.FindSpawnCoordinates(zone);
    local direction = "Max";

    if spawnCoords and spawnCoords.direction then direction = tostring(spawnCoords.direction); end

    if coordsType == "globalCoords" and spawnCoords and (spawnCoords.x and spawnCoords.y) then
        local gmd = VehicleRespawnManager.RespawnSystem.getGMD();
        local key = spawnCoords.x .. "_" .. spawnCoords.y;
        gmd.LocationPendingSpawns[key] = {
            vehicleScript = vehicleScript,
            x = spawnCoords.x,
            y = spawnCoords.y,
            attempt = req.attempt,
            direction = direction
        };
        Logger:debug("No coords found in global zone \"%s\" at attempt=%d. Scheduling a Location Pending spawns retry.",
            zoneName, req.attempt);
        return;
    elseif not spawnCoords then
        Logger:debug(
            "No suitable coords found in zone \"%s\". Request type=\"%s\" vehicleScript=\"%s\" Attempt=%d. Re-queueing.",
            zoneName, req.type, vehicleScript or "N/A", req.attempt);
        return "REQUEUE";
    end

    VehicleRespawnManager.RespawnSystem.AttemptSpawnDetermined(vehicleScript, spawnCoords.x, spawnCoords.y, 0, direction,
        zoneName, categoryName)
end

-----------------------------------------------------
-- Periodic Processing
-----------------------------------------------------
function VehicleRespawnManager.RespawnSystem.ProcessQueues()
    local now = getTimestamp();
    if now - VehicleRespawnManager.RespawnSystem.LastProcessTime < VehicleRespawnManager.RespawnSystem.ProcessInterval then
        return;
    end
    VehicleRespawnManager.RespawnSystem.LastProcessTime = now;

    local gmd = VehicleRespawnManager.RespawnSystem.getGMD();

    if #gmd.SpawnRequestsQueue > 0 then
        local req = table.remove(gmd.SpawnRequestsQueue, 1);
        local action = VehicleRespawnManager.RespawnSystem.ProcessSingleRequest(req);
        if action == "REQUEUE" then
            table.insert(gmd.SpawnRequestsQueue, req);
        end
    end

    local maxTimedSpawnsToProcess = 2;
    local processedTimedSpawns = 0;

    -- process TimedSpawns
    for i = #gmd.TimedSpawns, 1, -1 do
        if processedTimedSpawns >= maxTimedSpawnsToProcess then
            break;
        end

        local spawnData = gmd.TimedSpawns[i];
        if now >= spawnData.time then
            local success, reason = VehicleRespawnManager.RespawnSystem.SpawnVehicleAt(
                spawnData.vehicleScript,
                spawnData.x,
                spawnData.y,
                spawnData.direction
            );
            if success then
                table.remove(gmd.TimedSpawns, i);
            else
                spawnData.attempt = spawnData.attempt + 1;
                if spawnData.attempt > VehicleRespawnManager.RespawnSystem.MaxAttempts then
                    table.remove(gmd.TimedSpawns, i);
                    Logger:debug(
                        "Timed Spawn exceeded max attempts for \"%s\" at %d,%d, removing.",
                        spawnData.vehicleScript, spawnData.x, spawnData.y
                    );
                else
                    if reason == "chunkNotLoaded" or reason == "occupied" or reason == "noSquare" then
                        local key = spawnData.x .. "_" .. spawnData.y;
                        gmd.LocationPendingSpawns[key] = {
                            vehicleScript = spawnData.vehicleScript,
                            x = spawnData.x,
                            y = spawnData.y,
                            attempt = spawnData.attempt,
                            direction = spawnData.direction
                        };
                        table.remove(gmd.TimedSpawns, i);
                        Logger:debug("Timed Spawn moved to Location Pending Spawn for \"%s\" at %d,%d. Reason: %s",
                            spawnData.vehicleScript, spawnData.x, spawnData.y, reason);
                    else
                        spawnData.time = now + 1000;
                        Logger:debug("Timed Spawn retry for \"%s\" at %d,%d after delay. Reason: %s",
                            spawnData.vehicleScript, spawnData.x, spawnData.y, reason);
                    end
                end
            end
            processedTimedSpawns = processedTimedSpawns + 1;
        end
    end
end

Events.OnTick.Add(VehicleRespawnManager.RespawnSystem.ProcessQueues);


-- On grid square load, try LocationPendingSpawns
function VehicleRespawnManager.RespawnSystem.OnLoadGridsquare(square)
    local gmd = VehicleRespawnManager.RespawnSystem.getGMD();
    local key = square:getX() .. "_" .. square:getY();
    local toSpawn = gmd.LocationPendingSpawns[key];
    if toSpawn then
        local success, reason = VehicleRespawnManager.RespawnSystem.SpawnVehicleAt(
            toSpawn.vehicleScript,
            toSpawn.x,
            toSpawn.y,
            toSpawn.direction
        );
        if success then
            gmd.LocationPendingSpawns[key] = nil;
        else
            toSpawn.attempt = toSpawn.attempt + 1;
            if toSpawn.attempt > VehicleRespawnManager.RespawnSystem.MaxAttempts then
                gmd.LocationPendingSpawns[key] = nil;
                Logger:debug("Location Pending Spawn exceeded max attempts for \"%s\" at %d,%d, removing.",
                    toSpawn.vehicleScript, toSpawn.x, toSpawn.y
                );
            else
                if reason ~= "chunkNotLoaded" and reason ~= "occupied" and reason ~= "noSquare" then
                    local newTime = getTimestamp() + 1000;
                    table.insert(gmd.TimedSpawns, {
                        vehicleScript = toSpawn.vehicleScript,
                        x = toSpawn.x,
                        y = toSpawn.y,
                        time = newTime,
                        attempt = toSpawn.attempt,
                        direction = toSpawn.direction
                    });
                    gmd.LocationPendingSpawns[key] = nil;
                    Logger:debug("Location Pending Spawn for \"%s\" at %d,%d moved to Timed Spawns. Reason: %s",
                        toSpawn.vehicleScript, toSpawn.x, toSpawn.y, reason);
                end
            end
        end
    end
end

Events.LoadGridsquare.Add(VehicleRespawnManager.RespawnSystem.OnLoadGridsquare);


-----------------------------------------------------
-- Public API for queueing spawns
-----------------------------------------------------
function VehicleRespawnManager.RespawnSystem.QueueRandomVehicle()
    local gmd = VehicleRespawnManager.RespawnSystem.getGMD();
    table.insert(gmd.SpawnRequestsQueue, { type = "random" });
end

function VehicleRespawnManager.RespawnSystem.QueueFixedVehicle(scriptName)
    local gmd = VehicleRespawnManager.RespawnSystem.getGMD();
    table.insert(gmd.SpawnRequestsQueue, { type = "fixed", fixedScript = scriptName });
end

function VehicleRespawnManager.RespawnSystem.QueueMultipleRandom(count)
    for i = 1, count do
        VehicleRespawnManager.RespawnSystem.QueueRandomVehicle();
    end
end

function VehicleRespawnManager.RespawnSystem.QueueMultipleFixed(scriptName, count)
    for i = 1, count do
        VehicleRespawnManager.RespawnSystem.QueueFixedVehicle(scriptName);
    end
end
