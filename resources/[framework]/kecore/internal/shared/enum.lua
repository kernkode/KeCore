kec.enum = {
    entityType = {
        INVALID_ENTITY_ID = 0,
        ENTITY_TYPE_PED = 1,
        ENTITY_TYPE_VEHICLE = 2,
        ENTITY_TYPE_OBJECT = 3
    },

    ePedVarComp = {
        HEAD = 0,
        MASKS = 1,
        HAIR = 2,
        TORSOS = 3,
        LEGS = 4,
        BAGS = 5,
        SHOES = 6,
        ACCESSORIES = 7,
        UNDERSHIRTS = 8,
        ARMORS = 9,
        DECALS = 10,
        TOPS = 11
    },

    eVehicleDrivingFlags = {
        None = 0,
        StopForVehicles = 1,
        StopForPeds = 2,
        SwerveAroundAllVehicles = 4,
        SteerAroundStationaryVehicles = 8,
        SteerAroundPeds = 16,
        SteerAroundObjects = 32,
        DontSteerAroundPlayerPed = 64,
        StopAtTrafficLights = 128,
        GoOffRoadWhenAvoiding = 256,
        AllowGoingWrongWay = 512,
        Reverse = 1024,
        UseWanderFallbackInsteadOfStraightLine = 2048,
        AvoidRestrictedAreas = 4096,
        PreventBackgroundPathfinding = 8192,
        AdjustCruiseSpeedBasedOnRoadSpeed = 16384,
        UseShortCutLinks = 262144,
        ChangeLanesAroundObstructions = 524288,
        UseSwitchedOffNodes = 2097152,
        PreferNavmeshRoute = 4194304,
        PlaneTaxiMode = 8388608,
        ForceStraightLine = 16777216,
        UseStringPullingAtJunctions = 33554432,
        TryToAvoidHighways = 536870912,
        ForceJoinInRoadDirection = 1073741824,
        StopAtDestination = 2147483648,
        
        -- Modos de conducción combinados
        DrivingModeStopForVehicles = 786603,
        DrivingModeStopForVehiclesStrict = 262275,
        DrivingModeAvoidVehicles = 786469,
        DrivingModeAvoidVehiclesReckless = 786468,
        DrivingModeStopForVehiclesIgnoreLights = 786475,
        DrivingModeAvoidVehiclesObeyLights = 786597,
        DrivingModeAvoidVehiclesStopForPedsObeyLights = 786599,
    }
}