kec.weapons = {}

kec.weapons.data = {
    -- Heavy
    [`WEAPON_RPG`] = {name = "RPG", key = "WEAPON_RPG", gunFire = false},
    [`WEAPON_GRENADELAUNCHER`] = {name = "Grenade Launcher", key = "WEAPON_GRENADELAUNCHER", gunFire = false},
    [`WEAPON_GRENADELAUNCHER_SMOKE`] = {name = "Tear Gas Launcher", key = "WEAPON_GRENADELAUNCHER_SMOKE", gunFire = false},
    [`WEAPON_MINIGUN`] = {name = "Minigun", key = "WEAPON_MINIGUN", gunFire = true},
    [`WEAPON_FIREWORK`] = {name = "Firework Launcher", key = "WEAPON_FIREWORK", gunFire = false},
    [`WEAPON_RAILGUN`] = {name = "Railgun", key = "WEAPON_RAILGUN", gunFire = false},
    [`WEAPON_HOMINGLAUNCHER`] = {name = "Homing Launcher", key = "WEAPON_HOMINGLAUNCHER", gunFire = false},
    [`WEAPON_COMPACTLAUNCHER`] = {name = "Compact Grenade Launcher", key = "WEAPON_COMPACTLAUNCHER", gunFire = false},
    [`WEAPON_RAYMINIGUN`] = {name = "Widowmaker", key = "WEAPON_RAYMINIGUN", gunFire = false},
    [`WEAPON_EMPLAUNCHER`] = {name = "Compact EMP Launcher", key = "WEAPON_EMPLAUNCHER", gunFire = false},
    [`WEAPON_RAILGUNXM3`] = {name = "Railgun (XM3)", key = "WEAPON_RAILGUNXM3", gunFire = false},
    [`WEAPON_SNOWLAUNCHER`] = {name = "Snowball Launcher", key = "WEAPON_SNOWLAUNCHER", gunFire = false},

    -- Pistols
    [`WEAPON_PISTOL`] = {name = "Pistol", key = "WEAPON_PISTOL", gunFire = true},
    [`WEAPON_PISTOL_MK2`] = {name = "Pistol Mk II", key = "WEAPON_PISTOL_MK2", gunFire = true},
    [`WEAPON_COMBATPISTOL`] = {name = "Combat Pistol", key = "WEAPON_COMBATPISTOL", gunFire = true},
    [`WEAPON_APPISTOL`] = {name = "AP Pistol", key = "WEAPON_APPISTOL", gunFire = true},
    [`WEAPON_STUNGUN`] = {name = "Stun Gun", key = "WEAPON_STUNGUN", gunFire = false},
    [`WEAPON_PISTOL50`] = {name = "Pistol .50", key = "WEAPON_PISTOL50", gunFire = true},
    [`WEAPON_SNSPISTOL`] = {name = "SNS Pistol", key = "WEAPON_SNSPISTOL", gunFire = true},
    [`WEAPON_SNSPISTOL_MK2`] = {name = "SNS Pistol Mk II", key = "WEAPON_SNSPISTOL_MK2", gunFire = true},
    [`WEAPON_HEAVYPISTOL`] = {name = "Heavy Pistol", key = "WEAPON_HEAVYPISTOL", gunFire = true},
    [`WEAPON_VINTAGEPISTOL`] = {name = "Vintage Pistol", key = "WEAPON_VINTAGEPISTOL", gunFire = true},
    [`WEAPON_FLAREGUN`] = {name = "Flare Gun", key = "WEAPON_FLAREGUN", gunFire = false},
    [`WEAPON_MARKSMANPISTOL`] = {name = "Marksman Pistol", key = "WEAPON_MARKSMANPISTOL", gunFire = true},
    [`WEAPON_REVOLVER`] = {name = "Heavy Revolver", key = "WEAPON_REVOLVER", gunFire = true},
    [`WEAPON_REVOLVER_MK2`] = {name = "Heavy Revolver Mk II", key = "WEAPON_REVOLVER_MK2", gunFire = true},
    [`WEAPON_DOUBLEACTION`] = {name = "Double-Action Revolver", key = "WEAPON_DOUBLEACTION", gunFire = true},
    [`WEAPON_RAYPISTOL`] = {name = "Up-n-Atomizer", key = "WEAPON_RAYPISTOL", gunFire = false},
    [`WEAPON_CERAMICPISTOL`] = {name = "Ceramic Pistol", key = "WEAPON_CERAMICPISTOL", gunFire = true},
    [`WEAPON_NAVYREVOLVER`] = {name = "Navy Revolver", key = "WEAPON_NAVYREVOLVER", gunFire = true},
    [`WEAPON_GADGETPISTOL`] = {name = "Perico Pistol", key = "WEAPON_GADGETPISTOL", gunFire = true},
    [`WEAPON_PISTOLXM3`] = {name = "WM 29 Pistol", key = "WEAPON_PISTOLXM3", gunFire = true},
    [`WEAPON_STUNGUN_MP`] = {name = "Stun Gun (MP)", key = "WEAPON_STUNGUN_MP", gunFire = false},

    -- SMGs
    [`WEAPON_MICROSMG`] = {name = "Micro SMG", key = "WEAPON_MICROSMG", gunFire = true},
    [`WEAPON_SMG`] = {name = "SMG", key = "WEAPON_SMG", gunFire = true},
    [`WEAPON_SMG_MK2`] = {name = "SMG Mk II", key = "WEAPON_SMG_MK2", gunFire = true},
    [`WEAPON_ASSAULTSMG`] = {name = "Assault SMG", key = "WEAPON_ASSAULTSMG", gunFire = true},
    [`WEAPON_COMBATPDW`] = {name = "Combat PDW", key = "WEAPON_COMBATPDW", gunFire = true},
    [`WEAPON_MACHINEPISTOL`] = {name = "Machine Pistol", key = "WEAPON_MACHINEPISTOL", gunFire = true},
    [`WEAPON_MINISMG`] = {name = "Mini SMG", key = "WEAPON_MINISMG", gunFire = true},
    [`WEAPON_TECPISTOL`] = {name = "Tactical SMG", key = "WEAPON_TECPISTOL", gunFire = true},

    -- Shotguns
    [`WEAPON_PUMPSHOTGUN`] = {name = "Pump Shotgun", key = "WEAPON_PUMPSHOTGUN", gunFire = true},
    [`WEAPON_PUMPSHOTGUN_MK2`] = {name = "Pump Shotgun Mk II", key = "WEAPON_PUMPSHOTGUN_MK2", gunFire = true},
    [`WEAPON_SAWNOFFSHOTGUN`] = {name = "Sawed-Off Shotgun", key = "WEAPON_SAWNOFFSHOTGUN", gunFire = true},
    [`WEAPON_ASSAULTSHOTGUN`] = {name = "Assault Shotgun", key = "WEAPON_ASSAULTSHOTGUN", gunFire = true},
    [`WEAPON_BULLPUPSHOTGUN`] = {name = "Bullpup Shotgun", key = "WEAPON_BULLPUPSHOTGUN", gunFire = true},
    [`WEAPON_HEAVYSHOTGUN`] = {name = "Heavy Shotgun", key = "WEAPON_HEAVYSHOTGUN", gunFire = true},
    [`WEAPON_DBSHOTGUN`] = {name = "Double Barrel Shotgun", key = "WEAPON_DBSHOTGUN", gunFire = true},
    [`WEAPON_AUTOSHOTGUN`] = {name = "Sweeper Shotgun", key = "WEAPON_AUTOSHOTGUN", gunFire = true},
    [`WEAPON_COMBATSHOTGUN`] = {name = "Combat Shotgun", key = "WEAPON_COMBATSHOTGUN", gunFire = true},

    -- Assault Rifles
    [`WEAPON_ASSAULTRIFLE`] = {name = "Assault Rifle", key = "WEAPON_ASSAULTRIFLE", gunFire = true},
    [`WEAPON_ASSAULTRIFLE_MK2`] = {name = "Assault Rifle Mk II", key = "WEAPON_ASSAULTRIFLE_MK2", gunFire = true},
    [`WEAPON_CARBINERIFLE`] = {name = "Carbine Rifle", key = "WEAPON_CARBINERIFLE", gunFire = true},
    [`WEAPON_CARBINERIFLE_MK2`] = {name = "Carbine Rifle Mk II", key = "WEAPON_CARBINERIFLE_MK2", gunFire = true},
    [`WEAPON_ADVANCEDRIFLE`] = {name = "Advanced Rifle", key = "WEAPON_ADVANCEDRIFLE", gunFire = true},
    [`WEAPON_SPECIALCARBINE`] = {name = "Special Carbine", key = "WEAPON_SPECIALCARBINE", gunFire = true},
    [`WEAPON_SPECIALCARBINE_MK2`] = {name = "Special Carbine Mk II", key = "WEAPON_SPECIALCARBINE_MK2", gunFire = true},
    [`WEAPON_BULLPUPRIFLE`] = {name = "Bullpup Rifle", key = "WEAPON_BULLPUPRIFLE", gunFire = true},
    [`WEAPON_BULLPUPRIFLE_MK2`] = {name = "Bullpup Rifle Mk II", key = "WEAPON_BULLPUPRIFLE_MK2", gunFire = true},
    [`WEAPON_COMPACTRIFLE`] = {name = "Compact Rifle", key = "WEAPON_COMPACTRIFLE", gunFire = true},
    [`WEAPON_MILITARYRIFLE`] = {name = "Military Rifle", key = "WEAPON_MILITARYRIFLE", gunFire = true},
    [`WEAPON_HEAVYRIFLE`] = {name = "Heavy Rifle", key = "WEAPON_HEAVYRIFLE", gunFire = true},
    [`WEAPON_TACTICALRIFLE`] = {name = "Service Carbine", key = "WEAPON_TACTICALRIFLE", gunFire = true},
    [`WEAPON_BATTLERIFLE`] = {name = "Battle Rifle", key = "WEAPON_BATTLERIFLE", gunFire = true},

    -- LMGs
    [`WEAPON_MG`] = {name = "MG", key = "WEAPON_MG", gunFire = true},
    [`WEAPON_COMBATMG`] = {name = "Combat MG", key = "WEAPON_COMBATMG", gunFire = true},
    [`WEAPON_COMBATMG_MK2`] = {name = "Combat MG Mk II", key = "WEAPON_COMBATMG_MK2", gunFire = true},
    [`WEAPON_GUSENBERG`] = {name = "Gusenberg Sweeper", key = "WEAPON_GUSENBERG", gunFire = true},
    [`WEAPON_RAYCARBINE`] = {name = "Unholy Hellbringer", key = "WEAPON_RAYCARBINE", gunFire = false},

    -- Snipers
    [`WEAPON_SNIPERRIFLE`] = {name = "Sniper Rifle", key = "WEAPON_SNIPERRIFLE", gunFire = true},
    [`WEAPON_HEAVYSNIPER`] = {name = "Heavy Sniper", key = "WEAPON_HEAVYSNIPER", gunFire = true},
    [`WEAPON_HEAVYSNIPER_MK2`] = {name = "Heavy Sniper Mk II", key = "WEAPON_HEAVYSNIPER_MK2", gunFire = true},
    [`WEAPON_MARKSMANRIFLE`] = {name = "Marksman Rifle", key = "WEAPON_MARKSMANRIFLE", gunFire = true},
    [`WEAPON_MARKSMANRIFLE_MK2`] = {name = "Marksman Rifle Mk II", key = "WEAPON_MARKSMANRIFLE_MK2", gunFire = true},
    [`WEAPON_MUSKET`] = {name = "Musket", key = "WEAPON_MUSKET", gunFire = true},
    [`WEAPON_PRECISIONRIFLE`] = {name = "Precision Rifle", key = "WEAPON_PRECISIONRIFLE", gunFire = true},

    -- Thrown
    [`WEAPON_GRENADE`] = {name = "Grenade", key = "WEAPON_GRENADE", gunFire = false},
    [`WEAPON_STICKYBOMB`] = {name = "Sticky Bomb", key = "WEAPON_STICKYBOMB", gunFire = false},
    [`WEAPON_PROXMINE`] = {name = "Proximity Mine", key = "WEAPON_PROXMINE", gunFire = false},
    [`WEAPON_BZGAS`] = {name = "BZ Gas", key = "WEAPON_BZGAS", gunFire = false},
    [`WEAPON_SMOKEGRENADE`] = {name = "Tear Gas", key = "WEAPON_SMOKEGRENADE", gunFire = false},
    [`WEAPON_MOLOTOV`] = {name = "Molotov", key = "WEAPON_MOLOTOV", gunFire = false},
    [`WEAPON_FIREEXTINGUISHER`] = {name = "Fire Extinguisher", key = "WEAPON_FIREEXTINGUISHER", gunFire = false},
    [`WEAPON_PETROLCAN`] = {name = "Jerry Can", key = "WEAPON_PETROLCAN", gunFire = false},
    [`WEAPON_HAZARDCAN`] = {name = "Hazardous Jerry Can", key = "WEAPON_HAZARDCAN", gunFire = false},
    [`WEAPON_FERTILIZERCAN`] = {name = "Fertilizer Can", key = "WEAPON_FERTILIZERCAN", gunFire = false},
    [`WEAPON_BALL`] = {name = "Ball", key = "WEAPON_BALL", gunFire = false},
    [`WEAPON_SNOWBALL`] = {name = "Snowball", key = "WEAPON_SNOWBALL", gunFire = false},
    [`WEAPON_FLARE`] = {name = "Flare", key = "WEAPON_FLARE", gunFire = false},
    [`WEAPON_PIPEBOMB`] = {name = "Pipe Bomb", key = "WEAPON_PIPEBOMB", gunFire = false},
    [`WEAPON_ACIDPACKAGE`] = {name = "Acid Package", key = "WEAPON_ACIDPACKAGE", gunFire = false},

    -- Melee
    [`WEAPON_UNARMED`] = {name = "Unarmed", key = "WEAPON_UNARMED", gunFire = false},
    [`WEAPON_KNIFE`] = {name = "Knife", key = "WEAPON_KNIFE", gunFire = false},
    [`WEAPON_NIGHTSTICK`] = {name = "Nightstick", key = "WEAPON_NIGHTSTICK", gunFire = false},
    [`WEAPON_HAMMER`] = {name = "Hammer", key = "WEAPON_HAMMER", gunFire = false},
    [`WEAPON_BAT`] = {name = "Baseball Bat", key = "WEAPON_BAT", gunFire = false},
    [`WEAPON_GOLFCLUB`] = {name = "Golf Club", key = "WEAPON_GOLFCLUB", gunFire = false},
    [`WEAPON_CROWBAR`] = {name = "Crowbar", key = "WEAPON_CROWBAR", gunFire = false},
    [`WEAPON_BOTTLE`] = {name = "Bottle", key = "WEAPON_BOTTLE", gunFire = false},
    [`WEAPON_DAGGER`] = {name = "Antique Cavalry Dagger", key = "WEAPON_DAGGER", gunFire = false},
    [`WEAPON_HATCHET`] = {name = "Hatchet", key = "WEAPON_HATCHET", gunFire = false},
    [`WEAPON_KNUCKLE`] = {name = "Knuckle Duster", key = "WEAPON_KNUCKLE", gunFire = false},
    [`WEAPON_MACHETE`] = {name = "Machete", key = "WEAPON_MACHETE", gunFire = false},
    [`WEAPON_FLASHLIGHT`] = {name = "Flashlight", key = "WEAPON_FLASHLIGHT", gunFire = false},
    [`WEAPON_SWITCHBLADE`] = {name = "Switchblade", key = "WEAPON_SWITCHBLADE", gunFire = false},
    [`WEAPON_POOLCUE`] = {name = "Pool Cue", key = "WEAPON_POOLCUE", gunFire = false},
    [`WEAPON_WRENCH`] = {name = "Pipe Wrench", key = "WEAPON_WRENCH", gunFire = false},
    [`WEAPON_BATTLEAXE`] = {name = "Battle Axe", key = "WEAPON_BATTLEAXE", gunFire = false},
    [`WEAPON_STONE_HATCHET`] = {name = "Stone Hatchet", key = "WEAPON_STONE_HATCHET", gunFire = false},
    [`WEAPON_CANDYCANE`] = {name = "Candy Cane", key = "WEAPON_CANDYCANE", gunFire = false},
    [`WEAPON_STUNROD`] = {name = "The Shocker", key = "WEAPON_STUNROD", gunFire = false},

    -- Other
    [`WEAPON_HACKINGDEVICE`] = {name = "Hacking Device", key = "WEAPON_HACKINGDEVICE", gunFire = false},
    [`WEAPON_METALDETECTOR`] = {name = "Metal Detector", key = "WEAPON_METALDETECTOR", gunFire = false},
}

kec.weapons.models = {
    -- Heavy
    WEAPON_RPG = `WEAPON_RPG`,
    WEAPON_GRENADELAUNCHER = `WEAPON_GRENADELAUNCHER`,
    WEAPON_GRENADELAUNCHER_SMOKE = `WEAPON_GRENADELAUNCHER_SMOKE`,
    WEAPON_MINIGUN = `WEAPON_MINIGUN`,
    WEAPON_FIREWORK = `WEAPON_FIREWORK`,
    WEAPON_RAILGUN = `WEAPON_RAILGUN`,
    WEAPON_HOMINGLAUNCHER = `WEAPON_HOMINGLAUNCHER`,
    WEAPON_COMPACTLAUNCHER = `WEAPON_COMPACTLAUNCHER`,
    WEAPON_RAYMINIGUN = `WEAPON_RAYMINIGUN`,
    WEAPON_EMPLAUNCHER = `WEAPON_EMPLAUNCHER`,
    WEAPON_RAILGUNXM3 = `WEAPON_RAILGUNXM3`,
    WEAPON_SNOWLAUNCHER = `WEAPON_SNOWLAUNCHER`,

    -- Pistols
    WEAPON_PISTOL = `WEAPON_PISTOL`,
    WEAPON_PISTOL_MK2 = `WEAPON_PISTOL_MK2`,
    WEAPON_COMBATPISTOL = `WEAPON_COMBATPISTOL`,
    WEAPON_APPISTOL = `WEAPON_APPISTOL`,
    WEAPON_STUNGUN = `WEAPON_STUNGUN`,
    WEAPON_PISTOL50 = `WEAPON_PISTOL50`,
    WEAPON_SNSPISTOL = `WEAPON_SNSPISTOL`,
    WEAPON_SNSPISTOL_MK2 = `WEAPON_SNSPISTOL_MK2`,
    WEAPON_HEAVYPISTOL = `WEAPON_HEAVYPISTOL`,
    WEAPON_VINTAGEPISTOL = `WEAPON_VINTAGEPISTOL`,
    WEAPON_FLAREGUN = `WEAPON_FLAREGUN`,
    WEAPON_MARKSMANPISTOL = `WEAPON_MARKSMANPISTOL`,
    WEAPON_REVOLVER = `WEAPON_REVOLVER`,
    WEAPON_REVOLVER_MK2 = `WEAPON_REVOLVER_MK2`,
    WEAPON_DOUBLEACTION = `WEAPON_DOUBLEACTION`,
    WEAPON_RAYPISTOL = `WEAPON_RAYPISTOL`,
    WEAPON_CERAMICPISTOL = `WEAPON_CERAMICPISTOL`,
    WEAPON_NAVYREVOLVER = `WEAPON_NAVYREVOLVER`,
    WEAPON_GADGETPISTOL = `WEAPON_GADGETPISTOL`,
    WEAPON_PISTOLXM3 = `WEAPON_PISTOLXM3`,
    WEAPON_STUNGUN_MP = `WEAPON_STUNGUN_MP`,

    -- SMGs
    WEAPON_MICROSMG = `WEAPON_MICROSMG`,
    WEAPON_SMG = `WEAPON_SMG`,
    WEAPON_SMG_MK2 = `WEAPON_SMG_MK2`,
    WEAPON_ASSAULTSMG = `WEAPON_ASSAULTSMG`,
    WEAPON_COMBATPDW = `WEAPON_COMBATPDW`,
    WEAPON_MACHINEPISTOL = `WEAPON_MACHINEPISTOL`,
    WEAPON_MINISMG = `WEAPON_MINISMG`,
    WEAPON_TECPISTOL = `WEAPON_TECPISTOL`,

    -- Shotguns
    WEAPON_PUMPSHOTGUN = `WEAPON_PUMPSHOTGUN`,
    WEAPON_PUMPSHOTGUN_MK2 = `WEAPON_PUMPSHOTGUN_MK2`,
    WEAPON_SAWNOFFSHOTGUN = `WEAPON_SAWNOFFSHOTGUN`,
    WEAPON_ASSAULTSHOTGUN = `WEAPON_ASSAULTSHOTGUN`,
    WEAPON_BULLPUPSHOTGUN = `WEAPON_BULLPUPSHOTGUN`,
    WEAPON_HEAVYSHOTGUN = `WEAPON_HEAVYSHOTGUN`,
    WEAPON_DBSHOTGUN = `WEAPON_DBSHOTGUN`,
    WEAPON_AUTOSHOTGUN = `WEAPON_AUTOSHOTGUN`,
    WEAPON_COMBATSHOTGUN = `WEAPON_COMBATSHOTGUN`,

    -- Assault Rifles
    WEAPON_ASSAULTRIFLE = `WEAPON_ASSAULTRIFLE`,
    WEAPON_ASSAULTRIFLE_MK2 = `WEAPON_ASSAULTRIFLE_MK2`,
    WEAPON_CARBINERIFLE = `WEAPON_CARBINERIFLE`,
    WEAPON_CARBINERIFLE_MK2 = `WEAPON_CARBINERIFLE_MK2`,
    WEAPON_ADVANCEDRIFLE = `WEAPON_ADVANCEDRIFLE`,
    WEAPON_SPECIALCARBINE = `WEAPON_SPECIALCARBINE`,
    WEAPON_SPECIALCARBINE_MK2 = `WEAPON_SPECIALCARBINE_MK2`,
    WEAPON_BULLPUPRIFLE = `WEAPON_BULLPUPRIFLE`,
    WEAPON_BULLPUPRIFLE_MK2 = `WEAPON_BULLPUPRIFLE_MK2`,
    WEAPON_COMPACTRIFLE = `WEAPON_COMPACTRIFLE`,
    WEAPON_MILITARYRIFLE = `WEAPON_MILITARYRIFLE`,
    WEAPON_HEAVYRIFLE = `WEAPON_HEAVYRIFLE`,
    WEAPON_TACTICALRIFLE = `WEAPON_TACTICALRIFLE`,
    WEAPON_BATTLERIFLE = `WEAPON_BATTLERIFLE`,

    -- LMGs
    WEAPON_MG = `WEAPON_MG`,
    WEAPON_COMBATMG = `WEAPON_COMBATMG`,
    WEAPON_COMBATMG_MK2 = `WEAPON_COMBATMG_MK2`,
    WEAPON_GUSENBERG = `WEAPON_GUSENBERG`,
    WEAPON_RAYCARBINE = `WEAPON_RAYCARBINE`,

    -- Snipers
    WEAPON_SNIPERRIFLE = `WEAPON_SNIPERRIFLE`,
    WEAPON_HEAVYSNIPER = `WEAPON_HEAVYSNIPER`,
    WEAPON_HEAVYSNIPER_MK2 = `WEAPON_HEAVYSNIPER_MK2`,
    WEAPON_MARKSMANRIFLE = `WEAPON_MARKSMANRIFLE`,
    WEAPON_MARKSMANRIFLE_MK2 = `WEAPON_MARKSMANRIFLE_MK2`,
    WEAPON_MUSKET = `WEAPON_MUSKET`,
    WEAPON_PRECISIONRIFLE = `WEAPON_PRECISIONRIFLE`,

    -- Thrown
    WEAPON_GRENADE = `WEAPON_GRENADE`,
    WEAPON_STICKYBOMB = `WEAPON_STICKYBOMB`,
    WEAPON_PROXMINE = `WEAPON_PROXMINE`,
    WEAPON_BZGAS = `WEAPON_BZGAS`,
    WEAPON_SMOKEGRENADE = `WEAPON_SMOKEGRENADE`,
    WEAPON_MOLOTOV = `WEAPON_MOLOTOV`,
    WEAPON_FIREEXTINGUISHER = `WEAPON_FIREEXTINGUISHER`,
    WEAPON_PETROLCAN = `WEAPON_PETROLCAN`,
    WEAPON_HAZARDCAN = `WEAPON_HAZARDCAN`,
    WEAPON_FERTILIZERCAN = `WEAPON_FERTILIZERCAN`,
    WEAPON_BALL = `WEAPON_BALL`,
    WEAPON_SNOWBALL = `WEAPON_SNOWBALL`,
    WEAPON_FLARE = `WEAPON_FLARE`,
    WEAPON_PIPEBOMB = `WEAPON_PIPEBOMB`,
    WEAPON_ACIDPACKAGE = `WEAPON_ACIDPACKAGE`,

    -- Melee
    WEAPON_UNARMED = `WEAPON_UNARMED`,
    WEAPON_KNIFE = `WEAPON_KNIFE`,
    WEAPON_NIGHTSTICK = `WEAPON_NIGHTSTICK`,
    WEAPON_HAMMER = `WEAPON_HAMMER`,
    WEAPON_BAT = `WEAPON_BAT`,
    WEAPON_GOLFCLUB = `WEAPON_GOLFCLUB`,
    WEAPON_CROWBAR = `WEAPON_CROWBAR`,
    WEAPON_BOTTLE = `WEAPON_BOTTLE`,
    WEAPON_DAGGER = `WEAPON_DAGGER`,
    WEAPON_HATCHET = `WEAPON_HATCHET`,
    WEAPON_KNUCKLE = `WEAPON_KNUCKLE`,
    WEAPON_MACHETE = `WEAPON_MACHETE`,
    WEAPON_FLASHLIGHT = `WEAPON_FLASHLIGHT`,
    WEAPON_SWITCHBLADE = `WEAPON_SWITCHBLADE`,
    WEAPON_POOLCUE = `WEAPON_POOLCUE`,
    WEAPON_WRENCH = `WEAPON_WRENCH`,
    WEAPON_BATTLEAXE = `WEAPON_BATTLEAXE`,
    WEAPON_STONE_HATCHET = `WEAPON_STONE_HATCHET`,
    WEAPON_CANDYCANE = `WEAPON_CANDYCANE`,
    WEAPON_STUNROD = `WEAPON_STUNROD`,

    -- Other
    WEAPON_HACKINGDEVICE = `WEAPON_HACKINGDEVICE`,
    WEAPON_METALDETECTOR = `WEAPON_METALDETECTOR`,
}

-- Función para verificar si existe un arma
function kec.weapons:has(weaponHash)
    return kec.weapons.data[weaponHash] ~= nil
end

-- Función para obtener el nombre del arma
function kec.weapons:getWeaponName(weaponHash)
    local weapon = kec.weapons.data[weaponHash]
    return weapon and weapon.name or 'Unknown'
end

-- Función para obtener el key del arma
function kec.weapons:getWeaponKey(weaponHash)
    local weapon = kec.weapons.data[weaponHash]
    return weapon and weapon.key or 'WEAPON_UNKNOWN'
end

-- Función para obtener todos los datos del arma
function kec.weapons:getWeaponData(weaponHash)
    return kec.weapons.data[weaponHash] or {name = "Unknown", key = "WEAPON_UNKNOWN"}
end

-- Función para obtener el nombre desde el hash (alias para compatibilidad)
function kec.weapons:getNameFromHash(weaponHash)
    return self:getWeaponName(weaponHash)
end

function kec.weapons:isGunFire(weaponHash)
    return kec.weapons.data[weaponHash] and kec.weapons.data[weaponHash].gunFire
end