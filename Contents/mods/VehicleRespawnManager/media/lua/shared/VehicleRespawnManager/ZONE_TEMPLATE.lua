local vehicleRespawnZones = {};

vehicleRespawnZones = {
    name = "newZone",

    coordinates = { x1 = -1, y1 = -1, x2 = -1, y2 = -1 },

    isGlobalZone = false,
    isBlacklistZone = false,

    vehicleSpawnCategories = {},

    useDefaultCategoryForUnassigned = false,
    defaultCategoryNameForUnassigned = "None",
    maxVehicleCount = 999,

    zoneVehicleBlacklist = {},
};

return vehicleRespawnZones;
