-- Catálogo de vehículos: qué modelos conoce el servidor y qué sabe de cada uno.
--
-- Agrupado por la actualización que trajo cada coche y en orden: la base de 2013 arriba y la última
-- DLC abajo, que es donde se añaden las nuevas. Manda sobre qué modelos existen:
-- `kec.vehicle:isValidModel` contesta con esta tabla, así que un modelo que falte aquí no se puede
-- spawnear aunque el dump del juego lo traiga.
--
-- `class` es el nombre de clase de `kec.enum.eVehicleClass` — el mismo que usan las tablas de
-- configuración, como VEHICLE_TRUNK_BY_CLASS de inventory. En el CLIENTE la clase no hace falta
-- (ahí está el native `GetVehicleClass`), pero viaja con el catálogo; el servidor, que no tiene
-- ese native, es quien la pregunta aquí.
--
-- Las clases salieron de una vez del propio juego, porque el build que corre es el que manda y hay
-- modelos que el dump de DurtyFree todavía no trae. De ahí en adelante se mantienen a mano, como el
-- resto: un modelo nuevo se añade con su clase.

local kec = ...

local eWindowId = {
	VEH_EXT_WINDOW_LF = 0,
	VEH_EXT_WINDOW_RF = 1,
	VEH_EXT_WINDOW_LR = 2,
	VEH_EXT_WINDOW_RR = 3,
	VEH_EXT_WINDOW_LM = 4,
	VEH_EXT_WINDOW_RM = 5,
	VEH_EXT_WINDSCREEN = 6,
	VEH_EXT_WINDSCREEN_R = 7,
}

local models = {
    -- 2013 Base game

    [`AMBULANCE`] = { class = "EMERGENCY" },      [`Airbus`] = { class = "SERVICE" },
    [`Airtug`] = { class = "UTILITY" },           [`BARRACKS`] = { class = "MILITARY" },
    [`BARRACKS2`] = { class = "MILITARY" },       [`BLIMP`] = { class = "PLANE" },
    [`BMX`] = { class = "CYCLE" },                [`BUS`] = { class = "SERVICE" },
    [`Baller`] = { class = "SUV" },               [`Benson`] = { class = "COMMERCIAL" },
    [`BfInjection`] = { class = "OFF_ROAD" },     [`Biff`] = { class = "COMMERCIAL" },
    [`Bison2`] = { class = "VAN" },               [`Bison3`] = { class = "VAN" },
    [`BjXL`] = { class = "SUV" },                 [`Burrito`] = { class = "VAN" },
    [`Burrito4`] = { class = "VAN" },             [`Buzzard2`] = { class = "HELICOPTER" },
    [`CAMPER`] = { class = "VAN" },               [`CRUSADER`] = { class = "MILITARY" },
    [`Caddy2`] = { class = "UTILITY" },           [`Cargobob`] = { class = "HELICOPTER" },
    [`Cargobob3`] = { class = "HELICOPTER" },     [`Dinghy`] = { class = "BOAT" },
    [`Dominator`] = { class = "MUSCLE" },         [`Emperor2`] = { class = "SEDAN" },
    [`FBI`] = { class = "EMERGENCY" },            [`FBI2`] = { class = "EMERGENCY" },
    [`FLATBED`] = { class = "INDUSTRIAL" },       [`FORKLIFT`] = { class = "UTILITY" },
    [`Frogger`] = { class = "HELICOPTER" },       [`GRANGER`] = { class = "SUV" },
    [`Gauntlet`] = { class = "MUSCLE" },          [`Hauler`] = { class = "COMMERCIAL" },
    [`Lazer`] = { class = "PLANE" },              [`MESA`] = { class = "SUV" },
    [`MESA3`] = { class = "OFF_ROAD" },           [`Mixer`] = { class = "INDUSTRIAL" },
    [`Mixer2`] = { class = "INDUSTRIAL" },        [`Mower`] = { class = "UTILITY" },
    [`Mule`] = { class = "COMMERCIAL" },          [`Mule2`] = { class = "COMMERCIAL" },
    [`Packer`] = { class = "COMMERCIAL" },        [`Phantom`] = { class = "COMMERCIAL" },
    [`Phoenix`] = { class = "MUSCLE" },           [`Pounder`] = { class = "COMMERCIAL" },
    [`Predator`] = { class = "BOAT" },            [`RHINO`] = { class = "MILITARY" },
    [`RIOT`] = { class = "EMERGENCY" },           [`RancherXL`] = { class = "OFF_ROAD" },
    [`RapidGT`] = { class = "SPORT" },            [`RapidGT2`] = { class = "SPORT" },
    [`Rebel`] = { class = "OFF_ROAD" },           [`Rentalbus`] = { class = "SERVICE" },
    [`Ripley`] = { class = "UTILITY" },           [`Rubble`] = { class = "INDUSTRIAL" },
    [`SHERIFF`] = { class = "EMERGENCY" },        [`SURFER`] = { class = "VAN" },
    [`Sadler`] = { class = "UTILITY" },           [`Sanchez`] = { class = "MOTORCYCLE" },
    [`Seminole`] = { class = "SUV" },             [`Shamal`] = { class = "PLANE" },
    [`Stunt`] = { class = "PLANE" },              [`Suntrap`] = { class = "BOAT" },
    [`Surano`] = { class = "SPORT" },             [`Surfer2`] = { class = "VAN" },
    [`TOURBUS`] = { class = "SERVICE" },          [`TOWTRUCK`] = { class = "UTILITY" },
    [`TRACTOR`] = { class = "UTILITY" },          [`Taco`] = { class = "VAN" },
    [`TipTruck`] = { class = "INDUSTRIAL" },      [`TipTruck2`] = { class = "INDUSTRIAL" },
    [`Towtruck2`] = { class = "UTILITY" },        [`Trash`] = { class = "SERVICE" },
    [`Utillitruck3`] = { class = "UTILITY" },     [`Vader`] = { class = "MOTORCYCLE" },
    [`Ztype`] = { class = "SPORT_CLASSIC" },      [`adder`] = { class = "SUPER" },
    [`akuma`] = { class = "MOTORCYCLE" },         [`annihilator`] = { class = "HELICOPTER" },
    [`armytanker`] = { class = "UTILITY" },       [`armytrailer`] = { class = "UTILITY" },
    [`armytrailer2`] = { class = "UTILITY" },     [`asea`] = { class = "SEDAN" },
    [`asea2`] = { class = "SEDAN" },              [`asterope`] = { class = "SEDAN" },
    [`bagger`] = { class = "MOTORCYCLE" },        [`baletrailer`] = { class = "UTILITY" },
    [`baller2`] = { class = "SUV" },              [`banshee`] = { class = "SPORT" },
    [`bati`] = { class = "MOTORCYCLE" },          [`bati2`] = { class = "MOTORCYCLE" },
    [`bison`] = { class = "VAN" },                [`blazer`] = { class = "OFF_ROAD" },
    [`blazer2`] = { class = "OFF_ROAD" },         [`blazer3`] = { class = "OFF_ROAD" },
    [`blista`] = { class = "COMPACT" },           [`boattrailer`] = { class = "UTILITY" },
    [`boxville`] = { class = "VAN" },             [`boxville2`] = { class = "VAN" },
    [`boxville3`] = { class = "VAN" },            [`buccaneer`] = { class = "MUSCLE" },
    [`buffalo`] = { class = "SPORT" },            [`buffalo2`] = { class = "SPORT" },
    [`bulldozer`] = { class = "INDUSTRIAL" },     [`bullet`] = { class = "SUPER" },
    [`burrito2`] = { class = "VAN" },             [`burrito3`] = { class = "VAN" },
    [`burrito5`] = { class = "VAN" },             [`buzzard`] = { class = "HELICOPTER" },
    [`cablecar`] = { class = "TRAIN" },           [`caddy`] = { class = "UTILITY" },
    [`carbonizzare`] = { class = "SPORT" },       [`carbonrs`] = { class = "MOTORCYCLE" },
    [`cargobob2`] = { class = "HELICOPTER" },     [`cargoplane`] = { class = "PLANE" },
    [`cavalcade`] = { class = "SUV" },            [`cavalcade2`] = { class = "SUV" },
    [`cheetah`] = { class = "SUPER" },            [`coach`] = { class = "SERVICE" },
    [`cogcabrio`] = { class = "COUPE" },          [`comet2`] = { class = "SPORT" },
    [`coquette`] = { class = "SPORT" },           [`cruiser`] = { class = "CYCLE" },
    [`cuban800`] = { class = "PLANE" },           [`cutter`] = { class = "INDUSTRIAL" },
    [`daemon`] = { class = "MOTORCYCLE" },        [`dilettante`] = { class = "COMPACT" },
    [`dilettante2`] = { class = "COMPACT" },      [`dinghy2`] = { class = "BOAT" },
    [`dloader`] = { class = "OFF_ROAD" },         [`docktrailer`] = { class = "UTILITY" },
    [`docktug`] = { class = "UTILITY" },          [`double`] = { class = "MOTORCYCLE" },
    [`dubsta`] = { class = "SUV" },               [`dubsta2`] = { class = "SUV" },
    [`dump`] = { class = "INDUSTRIAL" },          [`dune`] = { class = "OFF_ROAD" },
    [`dune2`] = { class = "OFF_ROAD" },           [`duster`] = { class = "PLANE" },
    [`elegy2`] = { class = "SPORT" },             [`emperor`] = { class = "SEDAN" },
    [`emperor3`] = { class = "SEDAN" },           [`entityxf`] = { class = "SUPER" },
    [`exemplar`] = { class = "COUPE" },           [`f620`] = { class = "COUPE" },
    [`faggio2`] = { class = "MOTORCYCLE" },       [`felon`] = { class = "COUPE" },
    [`felon2`] = { class = "COUPE" },             [`feltzer2`] = { class = "SPORT" },
    [`firetruk`] = { class = "EMERGENCY" },       [`fixter`] = { class = "CYCLE" },
    [`fq2`] = { class = "SUV" },                  [`freight`] = { class = "TRAIN" },
    [`freightcar`] = { class = "TRAIN" },         [`freightcont1`] = { class = "TRAIN" },
    [`freightcont2`] = { class = "TRAIN" },       [`freightgrain`] = { class = "TRAIN" },
    [`freighttrailer`] = { class = "UTILITY" },   [`frogger2`] = { class = "HELICOPTER" },
    [`fugitive`] = { class = "SEDAN" },           [`fusilade`] = { class = "SPORT" },
    [`futo`] = { class = "SPORT" },               [`gburrito`] = { class = "VAN" },
    [`graintrailer`] = { class = "UTILITY" },     [`gresley`] = { class = "SUV" },
    [`habanero`] = { class = "SUV" },             [`handler`] = { class = "INDUSTRIAL" },
    [`hexer`] = { class = "MOTORCYCLE" },         [`hotknife`] = { class = "MUSCLE" },
    [`infernus`] = { class = "SUPER" },           [`ingot`] = { class = "SEDAN" },
    [`intruder`] = { class = "SEDAN" },           [`issi2`] = { class = "COMPACT" },
    [`jackal`] = { class = "COUPE" },             [`jb700`] = { class = "SPORT_CLASSIC" },
    [`jet`] = { class = "PLANE" },                [`jetmax`] = { class = "BOAT" },
    [`journey`] = { class = "VAN" },              [`khamelion`] = { class = "SPORT" },
    [`landstalker`] = { class = "SUV" },          [`lguard`] = { class = "EMERGENCY" },
    [`luxor`] = { class = "PLANE" },              [`mammatus`] = { class = "PLANE" },
    [`manana`] = { class = "SPORT_CLASSIC" },     [`marquis`] = { class = "BOAT" },
    [`maverick`] = { class = "HELICOPTER" },      [`mesa2`] = { class = "SUV" },
    [`metrotrain`] = { class = "TRAIN" },         [`minivan`] = { class = "VAN" },
    [`monroe`] = { class = "SPORT_CLASSIC" },     [`nemesis`] = { class = "MOTORCYCLE" },
    [`ninef`] = { class = "SPORT" },              [`ninef2`] = { class = "SPORT" },
    [`oracle`] = { class = "COUPE" },             [`oracle2`] = { class = "COUPE" },
    [`pRanger`] = { class = "EMERGENCY" },        [`patriot`] = { class = "SUV" },
    [`pbus`] = { class = "EMERGENCY" },           [`pcj`] = { class = "MOTORCYCLE" },
    [`penumbra`] = { class = "SPORT" },           [`peyote`] = { class = "SPORT_CLASSIC" },
    [`picador`] = { class = "MUSCLE" },           [`police`] = { class = "EMERGENCY" },
    [`police2`] = { class = "EMERGENCY" },        [`police3`] = { class = "EMERGENCY" },
    [`police4`] = { class = "EMERGENCY" },        [`policeb`] = { class = "EMERGENCY" },
    [`policeold1`] = { class = "EMERGENCY" },     [`policeold2`] = { class = "EMERGENCY" },
    [`policet`] = { class = "EMERGENCY" },        [`polmav`] = { class = "HELICOPTER" },
    [`pony`] = { class = "VAN" },                 [`pony2`] = { class = "VAN" },
    [`prairie`] = { class = "COMPACT" },          [`premier`] = { class = "SEDAN" },
    [`primo`] = { class = "SEDAN" },              [`proptrailer`] = { class = "UTILITY" },
    [`radi`] = { class = "SUV" },                 [`raketrailer`] = { class = "UTILITY" },
    [`rancherxl2`] = { class = "OFF_ROAD" },      [`ratloader`] = { class = "MUSCLE" },
    [`rebel2`] = { class = "OFF_ROAD" },          [`regina`] = { class = "SEDAN" },
    [`rocoto`] = { class = "SUV" },               [`romero`] = { class = "SEDAN" },
    [`ruffian`] = { class = "MOTORCYCLE" },       [`ruiner`] = { class = "MUSCLE" },
    [`rumpo`] = { class = "VAN" },                [`rumpo2`] = { class = "VAN" },
    [`sabregt`] = { class = "MUSCLE" },           [`sadler2`] = { class = "UTILITY" },
    [`sanchez2`] = { class = "MOTORCYCLE" },      [`sandking`] = { class = "OFF_ROAD" },
    [`sandking2`] = { class = "OFF_ROAD" },       [`schafter2`] = { class = "SEDAN" },
    [`schwarzer`] = { class = "SPORT" },          [`scorcher`] = { class = "CYCLE" },
    [`scrap`] = { class = "UTILITY" },            [`seashark`] = { class = "BOAT" },
    [`seashark2`] = { class = "BOAT" },           [`sentinel`] = { class = "COUPE" },
    [`sentinel2`] = { class = "COUPE" },          [`serrano`] = { class = "SUV" },
    [`sheriff2`] = { class = "EMERGENCY" },       [`skylift`] = { class = "HELICOPTER" },
    [`speedo`] = { class = "VAN" },               [`speedo2`] = { class = "VAN" },
    [`squalo`] = { class = "BOAT" },              [`stanier`] = { class = "SEDAN" },
    [`stinger`] = { class = "SPORT_CLASSIC" },    [`stingergt`] = { class = "SPORT_CLASSIC" },
    [`stockade`] = { class = "COMMERCIAL" },      [`stockade3`] = { class = "COMMERCIAL" },
    [`stratum`] = { class = "SEDAN" },            [`stretch`] = { class = "SEDAN" },
    [`submersible`] = { class = "BOAT" },         [`sultan`] = { class = "SPORT" },
    [`superd`] = { class = "SEDAN" },             [`surge`] = { class = "SEDAN" },
    [`tailgater`] = { class = "SEDAN" },          [`tanker`] = { class = "UTILITY" },
    [`tankercar`] = { class = "TRAIN" },          [`taxi`] = { class = "SERVICE" },
    [`titan`] = { class = "PLANE" },              [`tornado`] = { class = "SPORT_CLASSIC" },
    [`tornado2`] = { class = "SPORT_CLASSIC" },   [`tornado3`] = { class = "SPORT_CLASSIC" },
    [`tornado4`] = { class = "SPORT_CLASSIC" },   [`tr2`] = { class = "UTILITY" },
    [`tr3`] = { class = "UTILITY" },              [`tr4`] = { class = "UTILITY" },
    [`tractor2`] = { class = "UTILITY" },         [`tractor3`] = { class = "UTILITY" },
    [`trailerlogs`] = { class = "UTILITY" },      [`trailers`] = { class = "UTILITY" },
    [`trailers2`] = { class = "UTILITY" },        [`trailers3`] = { class = "UTILITY" },
    [`trailersmall`] = { class = "UTILITY" },     [`trflat`] = { class = "UTILITY" },
    [`tribike`] = { class = "CYCLE" },            [`tribike2`] = { class = "CYCLE" },
    [`tribike3`] = { class = "CYCLE" },           [`tropic`] = { class = "BOAT" },
    [`tvtrailer`] = { class = "UTILITY" },        [`utillitruck`] = { class = "UTILITY" },
    [`utillitruck2`] = { class = "UTILITY" },     [`vacca`] = { class = "SUPER" },
    [`velum`] = { class = "PLANE" },              [`vigero`] = { class = "MUSCLE" },
    [`voltic`] = { class = "SUPER" },             [`voodoo2`] = { class = "MUSCLE" },
    [`washington`] = { class = "SEDAN" },         [`youga`] = { class = "VAN" },
    [`zion`] = { class = "COUPE" },               [`zion2`] = { class = "COUPE" },

    -- 2013 Beach Bum Update

    [`bifta`] = { class = "OFF_ROAD" },           [`kalahari`] = { class = "OFF_ROAD" },
    [`paradise`] = { class = "VAN" },             [`speeder`] = { class = "BOAT" },

    -- 2014 Valentine's Day Massacre Special

    [`btype`] = { class = "SPORT_CLASSIC" },

    -- 2014 Business Update

    [`alpha`] = { class = "SPORT" },              [`jester`] = { class = "SPORT" },
    [`turismor`] = { class = "SUPER" },           [`vestra`] = { class = "PLANE" },

    -- 2014 High Life Update

    [`huntley`] = { class = "SUV" },              [`massacro`] = { class = "SPORT" },
    [`thrust`] = { class = "MOTORCYCLE" },        [`zentorno`] = { class = "SUPER" },

    -- 2014 The "I'm Not a Hipster" Update

    [`blade`] = { class = "MUSCLE" },             [`dubsta3`] = { class = "OFF_ROAD" },
    [`glendale`] = { class = "SEDAN" },           [`panto`] = { class = "COMPACT" },
    [`pigalle`] = { class = "SPORT_CLASSIC" },    [`rhapsody`] = { class = "COMPACT" },
    [`warrener`] = { class = "SEDAN" },

    -- 2014 Independence Day Special

    [`monster`] = { class = "OFF_ROAD" },         [`sovereign`] = { class = "MOTORCYCLE" },

    -- 2014 San Andreas Flight School Update

    [`Miljet`] = { class = "PLANE" },             [`besra`] = { class = "PLANE" },
    [`coquette2`] = { class = "SPORT_CLASSIC" },  [`swift`] = { class = "HELICOPTER" },

    -- 2014 Last Team Standing Update

    [`furoregt`] = { class = "SPORT" },           [`hakuchou`] = { class = "MOTORCYCLE" },
    [`innovation`] = { class = "MOTORCYCLE" },

    -- 2014 Returning Player Bonus

    [`BLIMP2`] = { class = "PLANE" },             [`blista2`] = { class = "SPORT" },
    [`blista3`] = { class = "SPORT" },            [`buffalo3`] = { class = "SPORT" },
    [`dodo`] = { class = "PLANE" },               [`dominator2`] = { class = "MUSCLE" },
    [`dukes`] = { class = "MUSCLE" },             [`dukes2`] = { class = "MUSCLE" },
    [`gauntlet2`] = { class = "MUSCLE" },         [`marshall`] = { class = "OFF_ROAD" },
    [`stalion`] = { class = "MUSCLE" },           [`stalion2`] = { class = "MUSCLE" },
    [`submersible2`] = { class = "BOAT" },

    -- 2014 Festive Surprise

    [`jester2`] = { class = "SPORT" },            [`massacro2`] = { class = "SPORT" },
    [`ratloader2`] = { class = "MUSCLE" },        [`slamvan`] = { class = "MUSCLE" },

    -- 2015 Heists

    [`BARRACKS3`] = { class = "MILITARY" },       [`Mule3`] = { class = "COMMERCIAL" },
    [`boxville4`] = { class = "VAN" },            [`casco`] = { class = "SPORT_CLASSIC" },
    [`dinghy3`] = { class = "BOAT" },             [`enduro`] = { class = "MOTORCYCLE" },
    [`gburrito2`] = { class = "VAN" },            [`guardian`] = { class = "INDUSTRIAL" },
    [`hydra`] = { class = "PLANE" },              [`insurgent`] = { class = "OFF_ROAD" },
    [`insurgent2`] = { class = "OFF_ROAD" },      [`kuruma`] = { class = "SPORT" },
    [`kuruma2`] = { class = "SPORT" },            [`lectro`] = { class = "MOTORCYCLE" },
    [`savage`] = { class = "HELICOPTER" },        [`slamvan2`] = { class = "MUSCLE" },
    [`tanker2`] = { class = "UTILITY" },          [`technical`] = { class = "OFF_ROAD" },
    [`trash2`] = { class = "SERVICE" },           [`valkyrie`] = { class = "HELICOPTER" },
    [`velum2`] = { class = "PLANE" },

    -- 2015 Ill-Gotten Gains Part 1

    [`feltzer3`] = { class = "SPORT_CLASSIC" },   [`luxor2`] = { class = "PLANE" },
    [`osiris`] = { class = "SUPER" },             [`swift2`] = { class = "HELICOPTER" },
    [`virgo`] = { class = "MUSCLE" },             [`windsor`] = { class = "COUPE" },

    -- 2015 Ill-Gotten Gains Part 2

    [`brawler`] = { class = "OFF_ROAD" },         [`chino`] = { class = "MUSCLE" },
    [`coquette3`] = { class = "MUSCLE" },         [`t20`] = { class = "SUPER" },
    [`toro`] = { class = "BOAT" },                [`vindicator`] = { class = "MOTORCYCLE" },

    -- 2015 Lowriders

    [`buccaneer2`] = { class = "MUSCLE" },        [`chino2`] = { class = "MUSCLE" },
    [`faction`] = { class = "MUSCLE" },           [`faction2`] = { class = "MUSCLE" },
    [`moonbeam`] = { class = "MUSCLE" },          [`moonbeam2`] = { class = "MUSCLE" },
    [`primo2`] = { class = "SEDAN" },             [`voodoo`] = { class = "MUSCLE" },

    -- 2015 Halloween Surprise

    [`btype2`] = { class = "SPORT_CLASSIC" },     [`lurcher`] = { class = "MUSCLE" },

    -- 2015 Executives and Other Criminals

    [`Cargobob4`] = { class = "HELICOPTER" },     [`baller3`] = { class = "SUV" },
    [`baller4`] = { class = "SUV" },              [`baller5`] = { class = "SUV" },
    [`baller6`] = { class = "SUV" },              [`cog55`] = { class = "SEDAN" },
    [`cog552`] = { class = "SEDAN" },             [`cognoscenti`] = { class = "SEDAN" },
    [`cognoscenti2`] = { class = "SEDAN" },       [`dinghy4`] = { class = "BOAT" },
    [`limo2`] = { class = "SEDAN" },              [`mamba`] = { class = "SPORT_CLASSIC" },
    [`nightshade`] = { class = "MUSCLE" },        [`schafter3`] = { class = "SPORT" },
    [`schafter4`] = { class = "SPORT" },          [`schafter5`] = { class = "SEDAN" },
    [`schafter6`] = { class = "SEDAN" },          [`seashark3`] = { class = "BOAT" },
    [`speeder2`] = { class = "BOAT" },            [`supervolito`] = { class = "HELICOPTER" },
    [`supervolito2`] = { class = "HELICOPTER" },  [`toro2`] = { class = "BOAT" },
    [`tropic2`] = { class = "BOAT" },             [`valkyrie2`] = { class = "HELICOPTER" },
    [`verlierer2`] = { class = "SPORT" },

    -- 2015 Festive Surprise 2015

    [`tampa`] = { class = "MUSCLE" },

    -- 2016 January 2016 Update

    [`banshee2`] = { class = "SUPER" },           [`sultanrs`] = { class = "SUPER" },

    -- 2016 Be My Valentine

    [`btype3`] = { class = "SPORT_CLASSIC" },

    -- 2016 Lowriders: Custom Classics

    [`faction3`] = { class = "MUSCLE" },          [`minivan2`] = { class = "VAN" },
    [`sabregt2`] = { class = "MUSCLE" },          [`slamvan3`] = { class = "MUSCLE" },
    [`tornado5`] = { class = "SPORT_CLASSIC" },   [`virgo2`] = { class = "MUSCLE" },
    [`virgo3`] = { class = "MUSCLE" },

    -- 2016 Further Adventures in Finance and Felony

    [`SEVEN70`] = { class = "SPORT" },            [`bestiagts`] = { class = "SPORT" },
    [`brickade`] = { class = "SERVICE" },         [`fmj`] = { class = "SUPER" },
    [`nimbus`] = { class = "PLANE" },             [`pfister811`] = { class = "SUPER" },
    [`prototipo`] = { class = "SUPER" },          [`reaper`] = { class = "SUPER" },
    [`rumpo3`] = { class = "VAN" },               [`tug`] = { class = "BOAT" },
    [`volatus`] = { class = "HELICOPTER" },       [`windsor2`] = { class = "COUPE" },
    [`xls`] = { class = "SUV" },                  [`xls2`] = { class = "SUV" },

    -- 2016 Cunning Stunts

    [`bf400`] = { class = "MOTORCYCLE" },         [`brioso`] = { class = "COMPACT" },
    [`cliffhanger`] = { class = "MOTORCYCLE" },   [`contender`] = { class = "SUV" },
    [`gargoyle`] = { class = "MOTORCYCLE" },      [`le7b`] = { class = "SUPER" },
    [`lynx`] = { class = "SPORT" },               [`omnis`] = { class = "SPORT" },
    [`rallytruck`] = { class = "SERVICE" },       [`sheava`] = { class = "SUPER" },
    [`tampa2`] = { class = "SPORT" },             [`trophytruck`] = { class = "OFF_ROAD" },
    [`trophytruck2`] = { class = "OFF_ROAD" },    [`tropos`] = { class = "SPORT" },
    [`tyrus`] = { class = "SUPER" },

    -- 2016 Bikers

    [`avarus`] = { class = "MOTORCYCLE" },        [`blazer4`] = { class = "OFF_ROAD" },
    [`chimera`] = { class = "MOTORCYCLE" },       [`daemon2`] = { class = "MOTORCYCLE" },
    [`defiler`] = { class = "MOTORCYCLE" },       [`esskey`] = { class = "MOTORCYCLE" },
    [`faggio`] = { class = "MOTORCYCLE" },        [`faggio3`] = { class = "MOTORCYCLE" },
    [`hakuchou2`] = { class = "MOTORCYCLE" },     [`manchez`] = { class = "MOTORCYCLE" },
    [`nightblade`] = { class = "MOTORCYCLE" },    [`raptor`] = { class = "SPORT" },
    [`ratbike`] = { class = "MOTORCYCLE" },       [`sanctus`] = { class = "MOTORCYCLE" },
    [`shotaro`] = { class = "MOTORCYCLE" },       [`tornado6`] = { class = "SPORT_CLASSIC" },
    [`vortex`] = { class = "MOTORCYCLE" },        [`wolfsbane`] = { class = "MOTORCYCLE" },
    [`youga2`] = { class = "VAN" },               [`zombiea`] = { class = "MOTORCYCLE" },
    [`zombieb`] = { class = "MOTORCYCLE" },

    -- 2016 Import/Export

    [`SPECTER`] = { class = "SPORT" },            [`SPECTER2`] = { class = "SPORT" },
    [`blazer5`] = { class = "OFF_ROAD" },         [`boxville5`] = { class = "VAN" },
    [`comet3`] = { class = "SPORT" },             [`diablous`] = { class = "MOTORCYCLE" },
    [`diablous2`] = { class = "MOTORCYCLE" },     [`dune4`] = { class = "OFF_ROAD" },
    [`dune5`] = { class = "OFF_ROAD" },           [`elegy`] = { class = "SPORT" },
    [`fcr`] = { class = "MOTORCYCLE" },           [`fcr2`] = { class = "MOTORCYCLE" },
    [`italigtb`] = { class = "SUPER" },           [`italigtb2`] = { class = "SUPER" },
    [`nero`] = { class = "SUPER" },               [`nero2`] = { class = "SUPER" },
    [`penetrator`] = { class = "SUPER" },         [`phantom2`] = { class = "COMMERCIAL" },
    [`ruiner2`] = { class = "MUSCLE" },           [`ruiner3`] = { class = "MUSCLE" },
    [`technical2`] = { class = "OFF_ROAD" },      [`tempesta`] = { class = "SUPER" },
    [`voltic2`] = { class = "SUPER" },            [`wastelander`] = { class = "SERVICE" },

    -- 2017 Cunning Stunts: Special Vehicle Circuit

    [`gp1`] = { class = "SUPER" },                [`infernus2`] = { class = "SPORT_CLASSIC" },
    [`ruston`] = { class = "SPORT" },             [`turismo2`] = { class = "SPORT_CLASSIC" },

    -- 2017 Gunrunning

    [`Hauler2`] = { class = "COMMERCIAL" },       [`apc`] = { class = "MILITARY" },
    [`ardent`] = { class = "SPORT_CLASSIC" },     [`caddy3`] = { class = "UTILITY" },
    [`cheetah2`] = { class = "SPORT_CLASSIC" },   [`dune3`] = { class = "OFF_ROAD" },
    [`halftrack`] = { class = "MILITARY" },       [`insurgent3`] = { class = "OFF_ROAD" },
    [`nightshark`] = { class = "OFF_ROAD" },      [`oppressor`] = { class = "MOTORCYCLE" },
    [`phantom3`] = { class = "COMMERCIAL" },      [`tampa3`] = { class = "MUSCLE" },
    [`technical3`] = { class = "OFF_ROAD" },      [`torero`] = { class = "SPORT_CLASSIC" },
    [`trailerlarge`] = { class = "UTILITY" },     [`trailers4`] = { class = "UTILITY" },
    [`trailersmall2`] = { class = "MILITARY" },   [`vagner`] = { class = "SUPER" },
    [`xa21`] = { class = "SUPER" },

    -- 2017 Smuggler's Run

    [`alphaz1`] = { class = "PLANE" },            [`cyclone`] = { class = "SUPER" },
    [`havok`] = { class = "HELICOPTER" },         [`howard`] = { class = "PLANE" },
    [`hunter`] = { class = "HELICOPTER" },        [`microlight`] = { class = "PLANE" },
    [`mogul`] = { class = "PLANE" },              [`molotok`] = { class = "PLANE" },
    [`nokota`] = { class = "PLANE" },             [`pyro`] = { class = "PLANE" },
    [`rapidgt3`] = { class = "SPORT_CLASSIC" },   [`retinue`] = { class = "SPORT_CLASSIC" },
    [`rogue`] = { class = "PLANE" },              [`seabreeze`] = { class = "PLANE" },
    [`starling`] = { class = "PLANE" },           [`tula`] = { class = "PLANE" },
    [`vigilante`] = { class = "SUPER" },          [`visione`] = { class = "SUPER" },

    -- 2017 The Doomsday Heist

    [`akula`] = { class = "HELICOPTER" },         [`autarch`] = { class = "SUPER" },
    [`avenger`] = { class = "PLANE" },            [`avenger2`] = { class = "PLANE" },
    [`barrage`] = { class = "MILITARY" },         [`chernobog`] = { class = "MILITARY" },
    [`comet4`] = { class = "SPORT" },             [`comet5`] = { class = "SPORT" },
    [`deluxo`] = { class = "SPORT_CLASSIC" },     [`gt500`] = { class = "SPORT_CLASSIC" },
    [`hermes`] = { class = "MUSCLE" },            [`hustler`] = { class = "MUSCLE" },
    [`kamacho`] = { class = "OFF_ROAD" },         [`khanjali`] = { class = "MILITARY" },
    [`neon`] = { class = "SPORT" },               [`pariah`] = { class = "SPORT" },
    [`raiden`] = { class = "SPORT" },             [`revolter`] = { class = "SPORT" },
    [`riata`] = { class = "OFF_ROAD" },           [`riot2`] = { class = "EMERGENCY" },
    [`savestra`] = { class = "SPORT_CLASSIC" },   [`sc1`] = { class = "SUPER" },
    [`sentinel3`] = { class = "SPORT" },          [`streiter`] = { class = "SPORT" },
    [`stromberg`] = { class = "SPORT_CLASSIC" },  [`thruster`] = { class = "MILITARY" },
    [`viseris`] = { class = "SPORT_CLASSIC" },    [`volatol`] = { class = "PLANE" },
    [`yosemite`] = { class = "MUSCLE" },          [`z190`] = { class = "SPORT_CLASSIC" },

    -- 2018 Southern San Andreas Super Sport Series

    [`caracara`] = { class = "OFF_ROAD" },        [`cheburek`] = { class = "SPORT_CLASSIC" },
    [`dominator3`] = { class = "MUSCLE" },        [`ellie`] = { class = "MUSCLE" },
    [`entity2`] = { class = "SUPER" },            [`fagaloa`] = { class = "SPORT_CLASSIC" },
    [`flashgt`] = { class = "SPORT" },            [`gb200`] = { class = "SPORT" },
    [`hotring`] = { class = "SPORT" },            [`issi3`] = { class = "COMPACT" },
    [`jester3`] = { class = "SPORT" },            [`michelli`] = { class = "SPORT_CLASSIC" },
    [`seasparrow`] = { class = "HELICOPTER" },    [`taipan`] = { class = "SUPER" },
    [`tezeract`] = { class = "SUPER" },           [`tyrant`] = { class = "SUPER" },

    -- 2018 After Hours

    [`blimp3`] = { class = "PLANE" },             [`freecrawler`] = { class = "OFF_ROAD" },
    [`menacer`] = { class = "OFF_ROAD" },         [`mule4`] = { class = "COMMERCIAL" },
    [`oppressor2`] = { class = "MOTORCYCLE" },    [`patriot2`] = { class = "SUV" },
    [`pbus2`] = { class = "SERVICE" },            [`pounder2`] = { class = "COMMERCIAL" },
    [`scramjet`] = { class = "SUPER" },           [`speedo4`] = { class = "VAN" },
    [`stafford`] = { class = "SEDAN" },           [`strikeforce`] = { class = "PLANE" },
    [`swinger`] = { class = "SPORT_CLASSIC" },    [`terbyte`] = { class = "COMMERCIAL" },

    -- 2018 Arena War

    [`bruiser`] = { class = "OFF_ROAD" },         [`bruiser2`] = { class = "OFF_ROAD" },
    [`bruiser3`] = { class = "OFF_ROAD" },        [`brutus`] = { class = "OFF_ROAD" },
    [`brutus2`] = { class = "OFF_ROAD" },         [`brutus3`] = { class = "OFF_ROAD" },
    [`cerberus`] = { class = "COMMERCIAL" },      [`cerberus2`] = { class = "COMMERCIAL" },
    [`cerberus3`] = { class = "COMMERCIAL" },     [`clique`] = { class = "MUSCLE" },
    [`deathbike`] = { class = "MOTORCYCLE" },     [`deathbike2`] = { class = "MOTORCYCLE" },
    [`deathbike3`] = { class = "MOTORCYCLE" },    [`deveste`] = { class = "SUPER" },
    [`deviant`] = { class = "MUSCLE" },           [`dominator4`] = { class = "MUSCLE" },
    [`dominator5`] = { class = "MUSCLE" },        [`dominator6`] = { class = "MUSCLE" },
    [`impaler`] = { class = "MUSCLE" },           [`impaler2`] = { class = "MUSCLE" },
    [`impaler3`] = { class = "MUSCLE" },          [`impaler4`] = { class = "MUSCLE" },
    [`imperator`] = { class = "MUSCLE" },         [`imperator2`] = { class = "MUSCLE" },
    [`imperator3`] = { class = "MUSCLE" },        [`issi4`] = { class = "COMPACT" },
    [`issi5`] = { class = "COMPACT" },            [`issi6`] = { class = "COMPACT" },
    [`italigto`] = { class = "SPORT" },           [`monster3`] = { class = "OFF_ROAD" },
    [`monster4`] = { class = "OFF_ROAD" },        [`monster5`] = { class = "OFF_ROAD" },
    [`rcbandito`] = { class = "OFF_ROAD" },       [`scarab`] = { class = "MILITARY" },
    [`scarab2`] = { class = "MILITARY" },         [`scarab3`] = { class = "MILITARY" },
    [`schlagen`] = { class = "SPORT" },           [`slamvan4`] = { class = "MUSCLE" },
    [`slamvan5`] = { class = "MUSCLE" },          [`slamvan6`] = { class = "MUSCLE" },
    [`toros`] = { class = "SUV" },                [`tulip`] = { class = "MUSCLE" },
    [`vamos`] = { class = "MUSCLE" },             [`zr380`] = { class = "SPORT" },
    [`zr3802`] = { class = "SPORT" },             [`zr3803`] = { class = "SPORT" },

    -- 2019 The Diamond Casino & Resort

    [`Dynasty`] = { class = "SPORT_CLASSIC" },    [`Novak`] = { class = "SUV" },
    [`caracara2`] = { class = "OFF_ROAD" },       [`drafter`] = { class = "SPORT" },
    [`emerus`] = { class = "SUPER" },             [`gauntlet3`] = { class = "MUSCLE" },
    [`gauntlet4`] = { class = "MUSCLE" },         [`hellion`] = { class = "OFF_ROAD" },
    [`issi7`] = { class = "SPORT" },              [`jugular`] = { class = "SPORT" },
    [`krieger`] = { class = "SUPER" },            [`locust`] = { class = "SPORT" },
    [`nebula`] = { class = "SPORT_CLASSIC" },     [`neo`] = { class = "SPORT" },
    [`paragon`] = { class = "SPORT" },            [`paragon2`] = { class = "SPORT" },
    [`peyote2`] = { class = "MUSCLE" },           [`rrocket`] = { class = "MOTORCYCLE" },
    [`s80`] = { class = "SUPER" },                [`thrax`] = { class = "SUPER" },
    [`zion3`] = { class = "SPORT_CLASSIC" },      [`zorrusso`] = { class = "SUPER" },

    -- 2019 The Diamond Casino Heist

    [`Stryder`] = { class = "MOTORCYCLE" },       [`Sugoi`] = { class = "SPORT" },
    [`asbo`] = { class = "COMPACT" },             [`everon`] = { class = "OFF_ROAD" },
    [`formula`] = { class = "OPEN_WHEEL" },       [`formula2`] = { class = "OPEN_WHEEL" },
    [`furia`] = { class = "SUPER" },              [`imorgon`] = { class = "SPORT" },
    [`jb7002`] = { class = "SPORT_CLASSIC" },     [`kanjo`] = { class = "COMPACT" },
    [`komoda`] = { class = "SPORT" },             [`minitank`] = { class = "MILITARY" },
    [`outlaw`] = { class = "OFF_ROAD" },          [`rebla`] = { class = "SUV" },
    [`retinue2`] = { class = "SPORT_CLASSIC" },   [`sultan2`] = { class = "SPORT" },
    [`vagrant`] = { class = "OFF_ROAD" },         [`vstr`] = { class = "SPORT" },
    [`yosemite2`] = { class = "MUSCLE" },         [`zhaba`] = { class = "OFF_ROAD" },

    -- 2020 Los Santos Summer Special

    [`club`] = { class = "COMPACT" },             [`coquette4`] = { class = "SPORT" },
    [`dukes3`] = { class = "MUSCLE" },            [`gauntlet5`] = { class = "MUSCLE" },
    [`glendale2`] = { class = "SEDAN" },          [`landstalker2`] = { class = "SUV" },
    [`manana2`] = { class = "MUSCLE" },           [`openwheel1`] = { class = "OPEN_WHEEL" },
    [`openwheel2`] = { class = "OPEN_WHEEL" },    [`penumbra2`] = { class = "SPORT" },
    [`peyote3`] = { class = "SPORT_CLASSIC" },    [`seminole2`] = { class = "SUV" },
    [`tigon`] = { class = "SUPER" },              [`yosemite3`] = { class = "OFF_ROAD" },
    [`youga3`] = { class = "VAN" },

    -- 2020 The Cayo Perico Heist

    [`alkonost`] = { class = "PLANE" },           [`annihilator2`] = { class = "HELICOPTER" },
    [`avisa`] = { class = "BOAT" },               [`brioso2`] = { class = "COMPACT" },
    [`dinghy5`] = { class = "BOAT" },             [`italirsx`] = { class = "SPORT" },
    [`kosatka`] = { class = "BOAT" },             [`longfin`] = { class = "BOAT" },
    [`manchez2`] = { class = "MOTORCYCLE" },      [`patrolboat`] = { class = "BOAT" },
    [`seasparrow2`] = { class = "HELICOPTER" },   [`seasparrow3`] = { class = "HELICOPTER" },
    [`slamtruck`] = { class = "UTILITY" },        [`squaddie`] = { class = "SUV" },
    [`toreador`] = { class = "SPORT_CLASSIC" },   [`verus`] = { class = "OFF_ROAD" },
    [`vetir`] = { class = "MILITARY" },           [`veto`] = { class = "SPORT" },
    [`veto2`] = { class = "SPORT" },              [`weevil`] = { class = "COMPACT" },
    [`winky`] = { class = "OFF_ROAD" },

    -- 2021 Los Santos Tuners

    [`Euros`] = { class = "SPORT" },              [`calico`] = { class = "SPORT" },
    [`comet6`] = { class = "SPORT" },             [`cypher`] = { class = "SPORT" },
    [`dominator7`] = { class = "MUSCLE" },        [`dominator8`] = { class = "MUSCLE" },
    [`freightcar2`] = { class = "TRAIN" },        [`futo2`] = { class = "SPORT" },
    [`growler`] = { class = "SPORT" },            [`jester4`] = { class = "SPORT" },
    [`previon`] = { class = "COUPE" },            [`remus`] = { class = "SPORT" },
    [`rt3000`] = { class = "SPORT" },             [`sultan3`] = { class = "SPORT" },
    [`tailgater2`] = { class = "SEDAN" },         [`vectre`] = { class = "SPORT" },
    [`warrener2`] = { class = "SEDAN" },          [`zr350`] = { class = "SPORT" },

    -- 2021 The Contract

    [`astron`] = { class = "SUV" },               [`baller7`] = { class = "SUV" },
    [`buffalo4`] = { class = "MUSCLE" },          [`champion`] = { class = "SUPER" },
    [`cinquemila`] = { class = "SEDAN" },         [`comet7`] = { class = "SPORT" },
    [`deity`] = { class = "SEDAN" },              [`granger2`] = { class = "SUV" },
    [`ignus`] = { class = "SUPER" },              [`iwagen`] = { class = "SUV" },
    [`jubilee`] = { class = "SUV" },              [`mule5`] = { class = "COMMERCIAL" },
    [`patriot3`] = { class = "OFF_ROAD" },        [`reever`] = { class = "MOTORCYCLE" },
    [`shinobi`] = { class = "MOTORCYCLE" },       [`youga4`] = { class = "VAN" },
    [`zeno`] = { class = "SUPER" },

    -- 2022 Expanded & Enhanced

    [`arbitergt`] = { class = "MUSCLE" },         [`astron2`] = { class = "SUV" },
    [`cyclone2`] = { class = "SUPER" },           [`ignus2`] = { class = "SUPER" },
    [`s95`] = { class = "SPORT" },

    -- 2022 The Criminal Enterprises

    [`brioso3`] = { class = "COMPACT" },          [`conada`] = { class = "HELICOPTER" },
    [`corsita`] = { class = "SPORT" },            [`draugur`] = { class = "OFF_ROAD" },
    [`greenwood`] = { class = "MUSCLE" },         [`kanjosj`] = { class = "COUPE" },
    [`lm87`] = { class = "SUPER" },               [`omnisegt`] = { class = "SPORT" },
    [`postlude`] = { class = "COUPE" },           [`rhinehart`] = { class = "SEDAN" },
    [`ruiner4`] = { class = "MUSCLE" },           [`sentinel4`] = { class = "SPORT" },
    [`sm722`] = { class = "SPORT" },              [`tenf`] = { class = "SPORT" },
    [`tenf2`] = { class = "SPORT" },              [`torero2`] = { class = "SUPER" },
    [`vigero2`] = { class = "MUSCLE" },           [`weevil2`] = { class = "MUSCLE" },

    -- 2022 Los Santos Drug Wars

    [`boor`] = { class = "OFF_ROAD" },            [`brickade2`] = { class = "SERVICE" },
    [`broadway`] = { class = "MUSCLE" },          [`cargoplane2`] = { class = "PLANE" },
    [`entity3`] = { class = "SUPER" },            [`eudora`] = { class = "MUSCLE" },
    [`everon2`] = { class = "SPORT" },            [`issi8`] = { class = "SUV" },
    [`journey2`] = { class = "VAN" },             [`manchez3`] = { class = "MOTORCYCLE" },
    [`panthere`] = { class = "SPORT" },           [`powersurge`] = { class = "MOTORCYCLE" },
    [`r300`] = { class = "SPORT" },               [`surfer3`] = { class = "VAN" },
    [`tahoma`] = { class = "MUSCLE" },            [`tulip2`] = { class = "MUSCLE" },
    [`virtue`] = { class = "SUPER" },

    -- 2023 San Andreas Mercenaries

    [`avenger3`] = { class = "PLANE" },           [`avenger4`] = { class = "PLANE" },
    [`brigham`] = { class = "MUSCLE" },           [`buffalo5`] = { class = "MUSCLE" },
    [`clique2`] = { class = "MUSCLE" },           [`conada2`] = { class = "HELICOPTER" },
    [`coureur`] = { class = "SPORT" },            [`gauntlet6`] = { class = "SPORT" },
    [`inductor`] = { class = "CYCLE" },           [`inductor2`] = { class = "CYCLE" },
    [`l35`] = { class = "OFF_ROAD" },             [`monstrociti`] = { class = "OFF_ROAD" },
    [`raiju`] = { class = "PLANE" },              [`ratel`] = { class = "OFF_ROAD" },
    [`speedo5`] = { class = "VAN" },              [`stingertt`] = { class = "SPORT" },
    [`streamer216`] = { class = "PLANE" },

    -- 2023 The Chop Shop

    [`Phantom4`] = { class = "COMMERCIAL" },      [`aleutian`] = { class = "SUV" },
    [`asterope2`] = { class = "SEDAN" },          [`baller8`] = { class = "SUV" },
    [`benson2`] = { class = "COMMERCIAL" },       [`boattrailer2`] = { class = "UTILITY" },
    [`boattrailer3`] = { class = "UTILITY" },     [`boxville6`] = { class = "VAN" },
    [`cavalcade3`] = { class = "SUV" },           [`dominator9`] = { class = "MUSCLE" },
    [`dorado`] = { class = "SUV" },               [`drifteuros`] = { class = "SPORT" },
    [`driftfr36`] = { class = "COUPE" },          [`driftfuto`] = { class = "SPORT" },
    [`driftjester`] = { class = "SPORT" },        [`driftremus`] = { class = "SPORT" },
    [`drifttampa`] = { class = "SPORT" },         [`driftyosemite`] = { class = "MUSCLE" },
    [`driftzr350`] = { class = "SPORT" },         [`fr36`] = { class = "COUPE" },
    [`freight2`] = { class = "TRAIN" },           [`impaler5`] = { class = "MUSCLE" },
    [`impaler6`] = { class = "MUSCLE" },          [`polgauntlet`] = { class = "EMERGENCY" },
    [`police5`] = { class = "EMERGENCY" },        [`terminus`] = { class = "OFF_ROAD" },
    [`towtruck3`] = { class = "UTILITY" },        [`towtruck4`] = { class = "UTILITY" },
    [`trailers5`] = { class = "UTILITY" },        [`turismo3`] = { class = "SUPER" },
    [`tvtrailer2`] = { class = "UTILITY" },       [`vigero3`] = { class = "MUSCLE" },
    [`vivanite`] = { class = "SUV" },

    -- 2024 Bottom Dollar Bounties

    [`castigator`] = { class = "SUV" },           [`coquette5`] = { class = "SPORT_CLASSIC" },
    [`dominator10`] = { class = "MUSCLE" },       [`driftcypher`] = { class = "SPORT" },
    [`driftnebula`] = { class = "SPORT_CLASSIC" },[`driftsentinel`] = { class = "SPORT" },
    [`driftvorschlag`] = { class = "SEDAN" },     [`envisage`] = { class = "SPORT" },
    [`eurosX32`] = { class = "COUPE" },           [`niobe`] = { class = "SPORT" },
    [`paragon3`] = { class = "SPORT" },           [`pipistrello`] = { class = "SUPER" },
    [`pizzaboy`] = { class = "MOTORCYCLE" },      [`poldominator10`] = { class = "EMERGENCY" },
    [`poldorado`] = { class = "EMERGENCY" },      [`polgreenwood`] = { class = "EMERGENCY" },
    [`policet3`] = { class = "EMERGENCY" },       [`polimpaler5`] = { class = "EMERGENCY" },
    [`polimpaler6`] = { class = "EMERGENCY" },    [`vorschlaghammer`] = { class = "SEDAN" },
    [`yosemite1500`] = { class = "OFF_ROAD" },

    -- 2024 Agents of Sabotage

    [`banshee3`] = { class = "SPORT" },           [`cargobob5`] = { class = "HELICOPTER" },
    [`chavosv6`] = { class = "SEDAN" },           [`coquette6`] = { class = "SPORT" },
    [`driftcheburek`] = { class = "SPORT_CLASSIC" },[`driftfuto2`] = { class = "SPORT" },
    [`driftjester3`] = { class = "SPORT_CLASSIC" },[`duster2`] = { class = "PLANE" },
    [`firebolt`] = { class = "OFF_ROAD" },        [`freightcar3`] = { class = "TRAIN" },
    [`jester5`] = { class = "SPORT" },            [`polcaracara`] = { class = "EMERGENCY" },
    [`polcoquette4`] = { class = "EMERGENCY" },   [`polfaction2`] = { class = "EMERGENCY" },
    [`polterminus`] = { class = "EMERGENCY" },    [`titan2`] = { class = "PLANE" },
    [`uranus`] = { class = "SPORT_CLASSIC" },     [`youga5`] = { class = "VAN" },

    -- 2025 Money Fronts

    [`cheetah3`] = { class = "SPORT_CLASSIC" },   [`driftchavosv6`] = { class = "SEDAN" },
    [`driftdominator10`] = { class = "MUSCLE" },  [`driftgauntlet4`] = { class = "MUSCLE" },
    [`drifthardy`] = { class = "SEDAN" },         [`driftl352`] = { class = "OFF_ROAD" },
    [`everon3`] = { class = "SUV" },              [`flatbed2`] = { class = "INDUSTRIAL" },
    [`hardy`] = { class = "SEDAN" },              [`l352`] = { class = "OFF_ROAD" },
    [`maverick2`] = { class = "HELICOPTER" },     [`minimus`] = { class = "SEDAN" },
    [`policeb2`] = { class = "EMERGENCY" },       [`rapidgt4`] = { class = "SPORT" },
    [`sentinel5`] = { class = "SPORT" },          [`stockade4`] = { class = "COMMERCIAL" },
    [`suzume`] = { class = "SUPER" },             [`tampa4`] = { class = "MUSCLE" },
    [`woodlander`] = { class = "SUV" },

    -- 2025 A Safehouse in the Hills

    [`astrale`] = { class = "SPORT_CLASSIC" },    [`driftdominator9`] = { class = "MUSCLE" },
    [`driftkeitora`] = { class = "UTILITY" },     [`driftrt3000`] = { class = "SPORT" },
    [`driftsentinel2`] = { class = "COUPE" },     [`fmj2`] = { class = "SUPER" },
    [`gt750`] = { class = "SPORT_CLASSIC" },      [`itali2`] = { class = "SPORT_CLASSIC" },
    [`keitora`] = { class = "UTILITY" },          [`luiva`] = { class = "SUPER" },
    [`polbuffalo`] = { class = "EMERGENCY" },     [`polbuffalo6`] = { class = "EMERGENCY" },
    [`sentinel6`] = { class = "SEDAN" },          [`vivanite2`] = { class = "SERVICE" },
    [`xtreme`] = { class = "SUPER" },

    -- 2026 The Kortz Center Heist

    [`caracara3`] = { class = "OFF_ROAD" },       [`cartuccia`] = { class = "SPORT" },
    [`driftcoquette`] = { class = "SPORT" },      [`driftdominator8`] = { class = "MUSCLE" },
    [`driftelegy`] = { class = "SPORT" },         [`estride`] = { class = "SUV" },
    [`horus`] = { class = "SUPER" },              [`laufer`] = { class = "VAN" },
    [`lrcgt`] = { class = "SUPER" },              [`merula`] = { class = "SEDAN" },
    [`polignus`] = { class = "EMERGENCY" },       [`trflat2`] = { class = "UTILITY" },
    [`velenogt`] = { class = "SUPER" },           [`warden`] = { class = "SUV" },
}

return {
    models = models,
    eWindowId = eWindowId
}
