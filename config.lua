Config = {}

-- Wer darf die Befehle nutzen? ('mod', 'admin' oder 'god' – höhere Gruppen dürfen automatisch auch)
Config.Permission = 'admin'

-- Befehlsnamen (ohne /)
Config.Commands = {
    Jail    = 'adminjail',      -- /adminjail [ID] [Minuten] [Grund]
    Unjail  = 'adminunjail',    -- /adminunjail [ID]
    SetTime = 'adminjailzeit',  -- /adminjailzeit [ID] [Minuten]
    List    = 'adminjailliste', -- /adminjailliste
    Deport  = 'abschieben',     -- /abschieben [ID] [Dauer] [Grund]  (Dauer: 30m, 12h, 7d, 2w oder perm)
    Coords  = 'ajkoords',       -- /ajkoords  -> eigene Position als vector4 in Chat + F8 (zum Einrichten)
}

-- Abschiebung (Bann mit NPC-Abholung zum Flughafen)
Config.Deport = {
    Permission = 'admin',                              -- wer darf /abschieben
    Dropoff    = vector3(-1037.7, -2737.5, 20.17),     -- Ziel der Fahrt: Terminal LSIA
    PlaneModel = 'luxor',
    PilotModel = 's_m_m_pilot_01',
    PlayerSeat = 1,                                    -- Passagiersitz im Flugzeug

    -- 'air'    = Flugzeug ist schon in der Luft und fliegt davon (funktioniert immer)
    -- 'runway' = Flugzeug startet auf der Piste (Koordinaten mit /ajkoords im Spiel prüfen!)
    Mode       = 'air',
    AirStart   = vector4(-1350.0, -2700.0, 160.0, 240.0), -- Startpunkt Modus 'air'
    Runway     = vector4(-1600.0, -2770.0, 13.94, 240.0), -- Pistenanfang Modus 'runway'
    FlyTo      = vector3(-4500.0, -4500.0, 600.0),        -- wohin das Flugzeug fliegt (aufs Meer)
    CutsceneTime = 18,                                     -- Sek. Abflug-Szene bis zum Kick
}

Config.MaxMinutes    = 120
Config.DefaultReason = 'Regelverstoss'

-- Admin-Jail-Ort (Standard: Hof Bolingbroke – bei Bedarf eigenen, abgelegenen Ort eintragen)
Config.Jail = {
    Center = vector3(1675.0, 2525.0, 45.56),  -- Mittelpunkt der Zone
    Radius = 80.0,                            -- wer weiter weg ist, wird zurückgesetzt
    Spawns = {                                 -- hier wird der Spieler abgesetzt
        vector4(1661.05, 2524.68, 45.56, 260.5),
        vector4(1650.81, 2540.58, 45.56, 230.4),
        vector4(1654.96, 2545.54, 45.56, 230.4),
        vector4(1697.11, 2525.56, 45.56, 187.2),
    },
    Release = vector4(1848.13, 2586.05, 45.67, 269.5), -- Entlassungsort (vor dem Tor)
    DisableWeapons   = true,  -- keine Waffen im Jail
    DisableInventory = true,  -- Inventar gesperrt (inv_busy)
    ShowTimer        = true,  -- Restzeit unten am Bildschirm
}

-- NPC-Abholung
Config.Transport = {
    Enabled      = true,             -- false = Spieler wird direkt teleportiert
    VehicleModel = 'police',
    PedModel     = 's_m_y_cop_01',
    Networked    = true,             -- false, falls euer Server "sv_entityLockdown strict" nutzt
    Siren        = true,
    PlayerSeat   = 2,                -- 1 = hinten links, 2 = hinten rechts
    Dropoff      = vector3(1855.0, 2590.0, 45.67), -- Ziel der Fahrt (Gefängnistor)

    ApproachSpeed   = 35.0,          -- m/s auf dem Weg zum Spieler (35 ≈ 126 km/h, vorher 20)
    DriveSpeed      = 50.0,          -- m/s auf dem Weg ins Jail (50 ≈ 180 km/h, vorher 30)
    -- Fahrstil: 1074528293 = Einsatzfahrt (überholt, fährt um Autos herum, ignoriert Ampeln)
    --           786603     = normal (hält an Ampeln, langsamer)
    DrivingStyle    = 1074528293,
    Aggressiveness  = 1.0,           -- 0.0 = vorsichtig, 1.0 = sehr zügig

    MinSpawnDistance = 50.0,         -- Abstand, in dem der Streifenwagen erscheint
    MaxSpawnDistance = 160.0,

    ApproachTimeout = 60,            -- Sek. bis der Wagen sonst direkt neben den Spieler gesetzt wird
    MaxDriveTime    = 300,           -- Sek. maximale Fahrzeit, danach Teleport ins Jail
    StuckSeconds    = 20,            -- Sek. ohne Bewegung = festgefahren
    SkipDrive       = false,         -- true = nach der Festnahme Abblende und direkt ins Jail
}

-- Optional: Tank füllen (Name eurer Fuel-Resource, z. B. 'LegacyFuel' oder 'cdn-fuel', nil = aus)
Config.FuelResource = 'LegacyFuel'

-- Optional: Logs über qb-log
Config.QbLog = { enabled = false, webhook = 'default' }

Config.Text = {
    jailed        = 'Du wurdest für %d Minuten ins Admin-Jail geschickt. Grund: %s',
    pickup        = 'Ein Polizeifahrzeug ist auf dem Weg zu dir.',
    arrest        = 'Du wirst festgenommen.',
    arrived       = 'Du bist im Admin-Jail. Restzeit: %d Minuten.',
    cantLeave     = 'Du kannst das Admin-Jail nicht verlassen.',
    released      = 'Du wurdest aus dem Admin-Jail entlassen.',
    timeUp        = 'Deine Admin-Jail-Zeit ist abgelaufen.',
    timeChanged   = 'Deine Admin-Jail-Zeit wurde auf %d Minuten geändert.',
    timer         = '~r~ADMIN-JAIL~s~  |  Restzeit: ~y~%d Min.~s~  |  Grund: %s',
    -- Admin-Meldungen
    noPlayer      = 'Spieler nicht gefunden.',
    badTime       = 'Ungültige Dauer (1 bis %d Minuten).',
    alreadyJailed = 'Dieser Spieler ist bereits im Admin-Jail.',
    notJailed     = 'Dieser Spieler ist nicht im Admin-Jail.',
    adminJailed   = '%s wurde für %d Minuten ins Admin-Jail geschickt.',
    adminReleased = '%s wurde aus dem Admin-Jail entlassen.',
    adminTimeSet  = 'Admin-Jail-Zeit von %s auf %d Minuten gesetzt.',
    listEmpty     = 'Niemand ist im Admin-Jail.',
    -- Abschiebung
    deportStart   = 'Du wurdest gebannt (%s) und wirst abgeschoben. Grund: %s',
    deportPickup  = 'Die Polizei holt dich ab und bringt dich zum Flughafen.',
    deportFlight  = 'Dein Flug aus Los Santos startet. Auf Wiedersehen!',
    badDuration   = 'Ungültige Dauer. Beispiele: 30m, 12h, 7d, 2w oder perm',
    adminDeported = '%s wurde gebannt (%s) und wird abgeschoben.',
    permanent     = 'permanent',
    untilDate     = 'bis %s',
    kickMessage   = 'Du wurdest abgeschoben und vom Server gebannt.\nGrund: %s\nDauer: %s',
}
