local QBCore = exports['qb-core']:GetCoreObject()
local T = Config.Text
local TC = Config.Transport

local state = {
    jailed = false,       -- sitzt im Jail
    transporting = false, -- wird gerade abgeholt
    abort = nil,          -- nil | 'release' | 'finish'
    remaining = 0,
    reason = '',
}
local spawned = {}

-- ===== Hilfsfunktionen =====

local function Notify(msg, typ) QBCore.Functions.Notify(msg, typ or 'primary', 6000) end

local function LoadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(10) end
    return HasModelLoaded(hash) and hash or nil
end

local function LoadDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
end

local function DeleteSafe(ent)
    if ent and DoesEntityExist(ent) then
        SetEntityAsMissionEntity(ent, true, true)
        DeleteEntity(ent)
    end
end

local function Cleanup()
    if spawned.blip and DoesBlipExist(spawned.blip) then RemoveBlip(spawned.blip) end
    DeleteSafe(spawned.driver)
    DeleteSafe(spawned.veh)
    spawned = {}
end

local function IsDead()
    local pd = QBCore.Functions.GetPlayerData()
    return pd and pd.metadata and (pd.metadata.isdead or pd.metadata.inlaststand)
end

local function Teleport(coords)
    local ped = PlayerPedId()
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    SetEntityHeading(ped, coords.w or 0.0)
    local timeout = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do Wait(0) end
end

local function RandomJailSpawn()
    return Config.Jail.Spawns[math.random(1, #Config.Jail.Spawns)]
end

local function Fade(out)
    if out then
        DoScreenFadeOut(500)
        while not IsScreenFadedOut() do Wait(10) end
    else
        DoScreenFadeIn(500)
    end
end

local function SetInvBusy(val)
    if Config.Jail.DisableInventory then LocalPlayer.state:set('inv_busy', val, true) end
end

-- Steuerung sperren, solange abgeholt wird (Umsehen, Chat, Funk und Pause bleiben frei)
local allowed = { 1, 2, 199, 200, 245, 249 }
local function ControlLock()
    CreateThread(function()
        while state.transporting do
            DisableAllControlActions(0)
            for i = 1, #allowed do EnableControlAction(0, allowed[i], true) end
            Wait(0)
        end
    end)
end

local function FindSpawnPoint(origin)
    for _ = 1, 15 do
        local ok, pos, heading = GetNthClosestVehicleNodeWithHeading(origin.x, origin.y, origin.z, math.random(10, 40), 0, 0, 0)
        if ok then
            local d = #(pos - origin)
            if d >= TC.MinSpawnDistance and d <= TC.MaxSpawnDistance then return pos, heading end
        end
    end
    local ok, pos, heading = GetClosestVehicleNodeWithHeading(origin.x, origin.y, origin.z, 1, 3.0, 0)
    if ok and #(pos - origin) < 150.0 then return pos, heading end
    return nil
end

-- ===== Jail =====

local function DrawTimer()
    SetTextFont(4)
    SetTextScale(0.45, 0.45)
    SetTextColour(255, 255, 255, 215)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(T.timer:format(state.remaining, state.reason))
    EndTextCommandDisplayText(0.5, 0.93)
end

local function StartJailLoops()
    -- jedes Frame: Waffen, Fahrzeuge, Anzeige
    CreateThread(function()
        while state.jailed do
            local ped = PlayerPedId()
            if Config.Jail.DisableWeapons then
                if GetSelectedPedWeapon(ped) ~= `WEAPON_UNARMED` then
                    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
                end
                DisablePlayerFiring(PlayerId(), true)
                DisableControlAction(0, 24, true)  -- Angriff
                DisableControlAction(0, 25, true)  -- Zielen
                DisableControlAction(0, 37, true)  -- Waffenrad
                DisableControlAction(0, 140, true) -- Nahkampf
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                DisableControlAction(0, 257, true)
                DisableControlAction(0, 263, true)
            end
            DisableControlAction(0, 23, true)      -- F: kein Einsteigen
            if Config.Jail.ShowTimer then DrawTimer() end
            Wait(0)
        end
    end)
    -- alle 2 Sek.: Zone prüfen
    CreateThread(function()
        while state.jailed do
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) or #(GetEntityCoords(ped) - Config.Jail.Center) > Config.Jail.Radius then
                Fade(true)
                Teleport(RandomJailSpawn())
                Fade(false)
                Notify(T.cantLeave, 'error')
            end
            Wait(2000)
        end
    end)
end

local function BeginJail()
    if state.jailed then return end
    state.jailed = true
    SetInvBusy(true)
    StartJailLoops()
    TriggerServerEvent('qb-adminjail:server:arrived')
end

local function DirectToJail()
    Fade(true)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 16) Wait(300) end
    ClearPedTasksImmediately(ped)
    Teleport(RandomJailSpawn())
    Fade(false)
    BeginJail()
end

-- ===== NPC-Abholung =====

-- Abflug-Szene: Spieler sitzt im Flugzeug, Kamera schaut zu, danach Kick
local function DeportCutscene()
    local D = Config.Deport
    local ped = PlayerPedId()
    -- Bildschirm ist hier bereits schwarz
    local planeHash = LoadModel(D.PlaneModel)
    local pilotHash = LoadModel(D.PilotModel)
    if not planeHash or not pilotHash then
        return TriggerServerEvent('qb-adminjail:server:deported')
    end

    local air = D.Mode ~= 'runway'
    local start = air and D.AirStart or D.Runway
    ClearPedTasksImmediately(ped)
    Teleport(start)

    local plane = CreateVehicle(planeHash, start.x, start.y, start.z, start.w, false, false)
    local pilot = CreatePedInsideVehicle(plane, 6, pilotHash, -1, false, false)
    spawned.veh, spawned.driver = plane, pilot
    SetEntityInvincible(plane, true)
    SetEntityInvincible(pilot, true)
    SetBlockingOfNonTemporaryEvents(pilot, true)
    SetPedIntoVehicle(ped, plane, D.PlayerSeat)
    SetVehicleEngineOn(plane, true, true, false)

    if air then
        ControlLandingGear(plane, 3)            -- Fahrwerk eingefahren
        SetVehicleForwardSpeed(plane, 60.0)
    end
    local f = D.FlyTo
    TaskPlaneMission(pilot, plane, 0, 0, f.x, f.y, f.z, 4, 60.0, 0.0, -1.0, 1000.0, 100.0, false)

    -- Kamera
    local camPos = GetOffsetFromEntityInWorldCoords(plane, air and -35.0 or -60.0, air and -20.0 or 80.0, air and 8.0 or 10.0)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0, 55.0, false, 0)
    PointCamAtEntity(cam, plane, 0.0, 0.0, 0.0, true)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
    DisplayRadar(false)
    Wait(500)
    Fade(false)
    Notify(T.deportFlight, 'error')

    local t = GetGameTimer() + D.CutsceneTime * 1000
    while GetGameTimer() < t do
        if air and DoesEntityExist(plane) then
            -- Kamera folgt im Modus 'air' langsam hinterher
            local p = GetOffsetFromEntityInWorldCoords(plane, -35.0, -60.0, 12.0)
            SetCamCoord(cam, p.x, p.y, p.z)
        end
        Wait(0)
    end

    Fade(true)
    TriggerServerEvent('qb-adminjail:server:deported')
end

local function FinishTransport(mode)
    Fade(true)
    Cleanup()
    if mode == 'deport' then return DeportCutscene() end
    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    Teleport(RandomJailSpawn())
    SetEntityInvincible(ped, false)
    state.transporting = false
    state.abort = nil
    Fade(false)
    BeginJail()
end

local function DoTransport(mode)
    local ped = PlayerPedId()
    state.transporting = true
    state.abort = nil
    SetInvBusy(true)
    ControlLock()
    SetEntityInvincible(ped, true)
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)

    if IsPedInAnyVehicle(ped, false) then
        TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 16)
        Wait(800)
    end

    local vehHash = LoadModel(TC.VehicleModel)
    local pedHash = LoadModel(TC.PedModel)
    local spawnPos, spawnHeading = FindSpawnPoint(GetEntityCoords(ped))
    if not vehHash or not pedHash or not spawnPos then
        -- keine Strasse in der Nähe / Modell fehlt -> direkt teleportieren
        return FinishTransport(mode)
    end

    local veh = CreateVehicle(vehHash, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, TC.Networked, false)
    local driver = CreatePedInsideVehicle(veh, 6, pedHash, -1, TC.Networked, false)
    spawned.veh, spawned.driver = veh, driver
    SetModelAsNoLongerNeeded(vehHash)
    SetModelAsNoLongerNeeded(pedHash)

    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleOnGroundProperly(veh)
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleSiren(veh, TC.Siren)
    SetVehicleDoorsLocked(veh, 2)
    SetEntityInvincible(veh, true)
    SetVehicleFuelLevel(veh, 100.0)
    if Config.FuelResource then pcall(function() exports[Config.FuelResource]:SetFuel(veh, 100.0) end) end

    SetEntityAsMissionEntity(driver, true, true)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetPedKeepTask(driver, true)
    SetEntityInvincible(driver, true)
    SetPedCanBeDraggedOut(driver, false)
    SetDriverAbility(driver, 1.0)
    SetDriverAggressiveness(driver, 0.0)

    spawned.blip = AddBlipForEntity(veh)
    SetBlipSprite(spawned.blip, 56)
    SetBlipColour(spawned.blip, 38)
    Notify(mode == 'deport' and T.deportPickup or T.pickup, 'error')

    local function valid()
        return not state.abort and DoesEntityExist(veh) and DoesEntityExist(driver)
    end

    -- 1) Zum Spieler fahren
    local p = GetEntityCoords(PlayerPedId())
    TaskVehicleDriveToCoord(driver, veh, p.x, p.y, p.z, TC.ApproachSpeed, 0, vehHash, TC.DrivingStyle, 8.0, 1.0)
    local deadline = GetGameTimer() + TC.ApproachTimeout * 1000
    while valid() and #(GetEntityCoords(veh) - GetEntityCoords(PlayerPedId())) > 14.0 do
        if GetGameTimer() > deadline then
            local pc = GetEntityCoords(PlayerPedId())
            local ok, pos, h = GetClosestVehicleNodeWithHeading(pc.x, pc.y, pc.z, 1, 3.0, 0)
            if ok then
                SetEntityCoords(veh, pos.x, pos.y, pos.z, false, false, false, false)
                SetEntityHeading(veh, h)
                SetVehicleOnGroundProperly(veh)
            end
            break
        end
        Wait(250)
    end
    if state.abort == 'release' then return Cleanup() end
    if not valid() then return FinishTransport(mode) end

    -- 2) Anhalten, aussteigen, zum Spieler laufen
    TaskVehicleTempAction(driver, veh, 27, 3000)
    Wait(1500)
    TaskLeaveVehicle(driver, veh, 0)
    local t = GetGameTimer() + 5000
    while valid() and IsPedInAnyVehicle(driver, false) and GetGameTimer() < t do Wait(100) end
    if not valid() then if state.abort == 'release' then return Cleanup() end return FinishTransport(mode) end

    TaskGoToEntity(driver, PlayerPedId(), -1, 1.2, 2.0, 1073741824, 0)
    t = GetGameTimer() + 20000
    while valid() and #(GetEntityCoords(driver) - GetEntityCoords(PlayerPedId())) > 1.8 do
        if GetGameTimer() > t then
            local behind = GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, -1.0, 0.0)
            SetEntityCoords(driver, behind.x, behind.y, behind.z - 1.0, false, false, false, false)
            break
        end
        Wait(200)
    end
    if not valid() then if state.abort == 'release' then return Cleanup() end return FinishTransport(mode) end

    -- 3) Festnahme
    ped = PlayerPedId()
    TaskTurnPedToFaceEntity(driver, ped, 1000)
    Wait(1000)
    LoadDict('mp_arresting')
    TaskPlayAnim(driver, 'mp_arresting', 'a_uncuff', 8.0, -8.0, 3000, 0, 0, false, false, false)
    TaskPlayAnim(ped, 'mp_arresting', 'idle', 8.0, -8.0, -1, 49, 0, false, false, false)
    Notify(T.arrest, 'error')
    Wait(3000)
    if not valid() then if state.abort == 'release' then return Cleanup() end return FinishTransport(mode) end

    if TC.SkipDrive then return FinishTransport(mode) end

    -- 4) Ins Auto setzen
    Fade(true)
    SetPedIntoVehicle(driver, veh, -1)
    SetPedIntoVehicle(ped, veh, TC.PlayerSeat)
    Wait(300)
    TaskPlayAnim(ped, 'mp_arresting', 'idle', 8.0, -8.0, -1, 49, 0, false, false, false)
    Fade(false)

    -- 5) Ins Jail fahren
    local dest = mode == 'deport' and Config.Deport.Dropoff or TC.Dropoff
    TaskVehicleDriveToCoordLongrange(driver, veh, dest.x, dest.y, dest.z, TC.DriveSpeed, TC.DrivingStyle, 15.0)
    local start = GetGameTimer()
    local lastPos = GetEntityCoords(veh)
    local stuck, retries = 0, 0
    while valid() do
        Wait(1000)
        if not valid() then break end
        ped = PlayerPedId()
        if not IsPedInVehicle(ped, veh, false) then SetPedIntoVehicle(ped, veh, TC.PlayerSeat) end

        local vpos = GetEntityCoords(veh)
        if #(vpos - dest) < 25.0 then break end
        if GetGameTimer() - start > TC.MaxDriveTime * 1000 then break end

        if #(vpos - lastPos) < 2.0 then stuck = stuck + 1 else stuck = 0 end
        lastPos = vpos
        if stuck >= TC.StuckSeconds then
            retries = retries + 1
            if retries > 2 then break end
            stuck = 0
            ClearPedTasks(driver)
            TaskVehicleDriveToCoordLongrange(driver, veh, dest.x, dest.y, dest.z, TC.DriveSpeed, TC.DrivingStyle, 15.0)
        end
    end
    if state.abort == 'release' then return Cleanup() end

    -- 6) Ankunft
    FinishTransport(mode)
end

-- ===== Events =====

RegisterNetEvent('qb-adminjail:client:start', function(data)
    state.remaining = data.time
    state.reason = data.reason

    if state.transporting then
        if not data.transport then state.abort = 'finish' end
        return
    end
    if state.jailed then
        -- schon drin: nur sicherstellen, dass er auch dort ist
        if #(GetEntityCoords(PlayerPedId()) - Config.Jail.Center) > Config.Jail.Radius then
            Fade(true) Teleport(RandomJailSpawn()) Fade(false)
        end
        TriggerServerEvent('qb-adminjail:server:arrived')
        return
    end

    if data.transport and TC.Enabled and not IsDead() then
        CreateThread(function() DoTransport('jail') end)
    else
        DirectToJail()
    end
end)

RegisterNetEvent('qb-adminjail:client:deport', function()
    -- laufendes Admin-Jail / laufende Abholung beenden
    state.jailed = false
    if state.transporting then
        state.abort = 'release'
        Wait(1500)
        Cleanup()
    end
    state.abort = nil
    if TC.Enabled and not IsDead() then
        CreateThread(function() DoTransport('deport') end)
    else
        state.transporting = true
        ControlLock()
        SetInvBusy(true)
        SetEntityInvincible(PlayerPedId(), true)
        FinishTransport('deport')
    end
end)

RegisterNetEvent('qb-adminjail:client:coords', function()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local s = ('vector4(%.2f, %.2f, %.2f, %.1f)'):format(c.x, c.y, c.z, GetEntityHeading(ped))
    print('[qb-adminjail] ' .. s)
    TriggerEvent('chat:addMessage', { color = { 80, 200, 255 }, args = { 'Koordinaten', s } })
end)

RegisterNetEvent('qb-adminjail:client:update', function(time)
    state.remaining = time
end)

RegisterNetEvent('qb-adminjail:client:returnToJail', function()
    if not state.jailed then return end
    Fade(true) Teleport(RandomJailSpawn()) Fade(false)
    Notify(T.cantLeave, 'error')
end)

RegisterNetEvent('qb-adminjail:client:release', function()
    state.abort = 'release'
    state.jailed = false
    state.transporting = false
    Fade(true)
    Cleanup()
    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    SetEntityInvincible(ped, false)
    Teleport(Config.Jail.Release)
    SetInvBusy(false)
    Fade(false)
    Notify(T.released, 'success')
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(2000)
    TriggerServerEvent('qb-adminjail:server:check')
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    state.abort = 'release'
    state.jailed = false
    state.transporting = false
    Cleanup()
    SetInvBusy(false)
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    if LocalPlayer.state.isLoggedIn then
        Wait(1000)
        TriggerServerEvent('qb-adminjail:server:check')
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    Cleanup()
    if state.transporting or state.jailed then
        SetEntityInvincible(PlayerPedId(), false)
        SetInvBusy(false)
        DoScreenFadeIn(0)
    end
end)
