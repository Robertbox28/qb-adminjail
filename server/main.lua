local QBCore = exports['qb-core']:GetCoreObject()
local T = Config.Text

-- [src] = { time, reason, by, active, started }
local Jailed = {}
-- [src] = { started, kick }
local Deporting = {}
local PERMANENT = 2147483647

local function Notify(src, msg, typ)
    if src == 0 then print('[qb-adminjail] ' .. msg) return end
    TriggerClientEvent('QBCore:Notify', src, msg, typ or 'primary', 6000)
end

local function Log(title, msg)
    print(('[qb-adminjail] %s: %s'):format(title, msg))
    if Config.QbLog.enabled then
        TriggerEvent('qb-log:server:CreateLog', Config.QbLog.webhook, title, 'red', msg)
    end
end

local function CharName(Player)
    local c = Player.PlayerData.charinfo
    return ('%s %s (%s)'):format(c.firstname, c.lastname, GetPlayerName(Player.PlayerData.source))
end

local function SaveMeta(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local j = Jailed[src]
    if j then
        Player.Functions.SetMetaData('adminjail', { time = j.time, reason = j.reason, by = j.by })
    else
        Player.Functions.SetMetaData('adminjail', false)
    end
end

local function StartJail(src, minutes, reason, by, transport)
    Jailed[src] = { time = minutes, reason = reason, by = by, active = false, started = os.time() }
    SaveMeta(src)
    TriggerClientEvent('qb-adminjail:client:start', src, { time = minutes, reason = reason, transport = transport })
end

local function Release(src)
    if not Jailed[src] then return false end
    Jailed[src] = nil
    SaveMeta(src)
    TriggerClientEvent('qb-adminjail:client:release', src)
    return true
end

-- ===== Befehle =====

QBCore.Commands.Add(Config.Commands.Jail, 'Spieler ins Admin-Jail schicken (NPC-Abholung)', {
    { name = 'id', help = 'Spieler-ID' },
    { name = 'minuten', help = 'Dauer in Minuten' },
    { name = 'grund', help = 'Grund (optional)' },
}, false, function(source, args)
    local src = source
    local target = tonumber(args[1])
    local minutes = tonumber(args[2])
    local Target = target and QBCore.Functions.GetPlayer(target)
    if not Target then return Notify(src, T.noPlayer, 'error') end
    if not minutes or minutes < 1 or minutes > Config.MaxMinutes then
        return Notify(src, T.badTime:format(Config.MaxMinutes), 'error')
    end
    if Jailed[target] then return Notify(src, T.alreadyJailed, 'error') end

    minutes = math.floor(minutes)
    local reason = table.concat(args, ' ', 3)
    if reason == '' then reason = Config.DefaultReason end
    local by = src == 0 and 'Konsole' or GetPlayerName(src)

    StartJail(target, minutes, reason, by, true)
    Notify(target, T.jailed:format(minutes, reason), 'error')
    Notify(src, T.adminJailed:format(CharName(Target), minutes), 'success')
    Log('Admin-Jail', ('%s hat %s für %d Min. ins Admin-Jail geschickt. Grund: %s'):format(by, CharName(Target), minutes, reason))
end, Config.Permission)

QBCore.Commands.Add(Config.Commands.Unjail, 'Spieler aus dem Admin-Jail entlassen', {
    { name = 'id', help = 'Spieler-ID' },
}, true, function(source, args)
    local src = source
    local target = tonumber(args[1])
    local Target = target and QBCore.Functions.GetPlayer(target)
    if not Target then return Notify(src, T.noPlayer, 'error') end
    if not Release(target) then return Notify(src, T.notJailed, 'error') end
    Notify(src, T.adminReleased:format(CharName(Target)), 'success')
    Log('Admin-Jail', ('%s hat %s aus dem Admin-Jail entlassen.'):format(src == 0 and 'Konsole' or GetPlayerName(src), CharName(Target)))
end, Config.Permission)

QBCore.Commands.Add(Config.Commands.SetTime, 'Admin-Jail-Zeit ändern', {
    { name = 'id', help = 'Spieler-ID' },
    { name = 'minuten', help = 'Neue Restzeit in Minuten' },
}, true, function(source, args)
    local src = source
    local target = tonumber(args[1])
    local minutes = tonumber(args[2])
    local Target = target and QBCore.Functions.GetPlayer(target)
    if not Target then return Notify(src, T.noPlayer, 'error') end
    if not Jailed[target] then return Notify(src, T.notJailed, 'error') end
    if not minutes or minutes < 1 or minutes > Config.MaxMinutes then
        return Notify(src, T.badTime:format(Config.MaxMinutes), 'error')
    end
    Jailed[target].time = math.floor(minutes)
    SaveMeta(target)
    TriggerClientEvent('qb-adminjail:client:update', target, Jailed[target].time)
    Notify(target, T.timeChanged:format(Jailed[target].time))
    Notify(src, T.adminTimeSet:format(CharName(Target), Jailed[target].time), 'success')
end, Config.Permission)

QBCore.Commands.Add(Config.Commands.List, 'Alle Spieler im Admin-Jail anzeigen', {}, false, function(source)
    local src = source
    local lines = {}
    for id, j in pairs(Jailed) do
        local P = QBCore.Functions.GetPlayer(id)
        if P then
            lines[#lines + 1] = ('[%d] %s – %d Min. – %s (von %s)%s'):format(
                id, CharName(P), j.time, j.reason, j.by, j.active and '' or ' – unterwegs')
        end
    end
    if #lines == 0 then return Notify(src, T.listEmpty) end
    for _, l in ipairs(lines) do
        if src == 0 then print(l) else
            TriggerClientEvent('chat:addMessage', src, { color = { 255, 80, 80 }, args = { 'Admin-Jail', l } })
        end
    end
end, Config.Permission)

-- ===== Abschiebung (Bann) =====

-- "30m", "12h", "7d", "2w", "perm" (nur Zahl = Stunden)
local function ParseDuration(s)
    s = (s or ''):lower()
    if s == 'perm' or s == 'permanent' then return PERMANENT, T.permanent end
    local n, unit = s:match('^(%d+)([mhdw]?)$')
    n = tonumber(n)
    if not n or n <= 0 then return nil end
    local mult = ({ m = 60, h = 3600, d = 86400, w = 604800 })[unit] or 3600
    local expire = os.time() + n * mult
    return expire, T.untilDate:format(os.date('%d.%m.%Y %H:%M', expire))
end

local function WriteBan(src, expire, reason, by)
    MySQL.insert('INSERT INTO bans (name, license, discord, ip, reason, expire, bannedby) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        GetPlayerName(src),
        QBCore.Functions.GetIdentifier(src, 'license'),
        QBCore.Functions.GetIdentifier(src, 'discord'),
        QBCore.Functions.GetIdentifier(src, 'ip'),
        reason,
        expire,
        by,
    })
end

QBCore.Commands.Add(Config.Commands.Deport, 'Spieler bannen und per NPC zum Flughafen abschieben', {
    { name = 'id', help = 'Spieler-ID' },
    { name = 'dauer', help = '30m, 12h, 7d, 2w oder perm' },
    { name = 'grund', help = 'Grund (optional)' },
}, false, function(source, args)
    local src = source
    local target = tonumber(args[1])
    local Target = target and QBCore.Functions.GetPlayer(target)
    if not Target then return Notify(src, T.noPlayer, 'error') end
    if Deporting[target] then return Notify(src, T.alreadyJailed, 'error') end
    local expire, label = ParseDuration(args[2])
    if not expire then return Notify(src, T.badDuration, 'error') end

    local reason = table.concat(args, ' ', 3)
    if reason == '' then reason = Config.DefaultReason end
    local by = src == 0 and 'Konsole' or GetPlayerName(src)
    local name = CharName(Target)

    -- Bann sofort speichern: wer während der Fahrt rausgeht, ist trotzdem gebannt
    WriteBan(target, expire, reason, by)

    if Jailed[target] then Jailed[target] = nil SaveMeta(target) end
    Deporting[target] = { started = os.time(), kick = T.kickMessage:format(reason, label) }
    TriggerClientEvent('qb-adminjail:client:deport', target)
    Notify(target, T.deportStart:format(label, reason), 'error')
    Notify(src, T.adminDeported:format(name, label), 'success')
    Log('Abschiebung', ('%s hat %s gebannt (%s) und abgeschoben. Grund: %s'):format(by, name, label, reason))
end, Config.Deport.Permission)

RegisterNetEvent('qb-adminjail:server:deported', function()
    local src = source
    local d = Deporting[src]
    if not d then return end
    Deporting[src] = nil
    DropPlayer(src, d.kick)
end)

QBCore.Commands.Add(Config.Commands.Coords, 'Eigene Position für die Config anzeigen', {}, false, function(source)
    if source ~= 0 then TriggerClientEvent('qb-adminjail:client:coords', source) end
end, Config.Permission)

-- ===== Events =====

RegisterNetEvent('qb-adminjail:server:arrived', function()
    local src = source
    local j = Jailed[src]
    if not j or j.active then return end
    j.active = true
    Notify(src, T.arrived:format(j.time), 'error')
end)

-- Wird vom Client nach dem Einloggen / Resource-Neustart gefragt
RegisterNetEvent('qb-adminjail:server:check', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local meta = Player.PlayerData.metadata.adminjail
    if type(meta) ~= 'table' or (tonumber(meta.time) or 0) <= 0 then return end
    StartJail(src, tonumber(meta.time), meta.reason or Config.DefaultReason, meta.by or '?', false)
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    Jailed[src] = nil
end)

AddEventHandler('playerDropped', function()
    Jailed[source] = nil
    Deporting[source] = nil
end)

-- ===== Minuten-Takt =====

CreateThread(function()
    while true do
        Wait(60000)
        -- Abschiebung hängt: trotzdem kicken (Bann ist schon gespeichert)
        for src, d in pairs(Deporting) do
            if os.time() - d.started > Config.Transport.MaxDriveTime + 180 then
                Deporting[src] = nil
                if GetPlayerName(src) then DropPlayer(src, d.kick) end
            end
        end
        for src, j in pairs(Jailed) do
            if not GetPlayerName(src) then
                Jailed[src] = nil
            elseif j.active then
                j.time = j.time - 1
                if j.time <= 0 then
                    Release(src)
                    Notify(src, T.timeUp, 'success')
                    Log('Admin-Jail', ('%s hat die Admin-Jail-Zeit abgesessen.'):format(GetPlayerName(src)))
                else
                    SaveMeta(src)
                    TriggerClientEvent('qb-adminjail:client:update', src, j.time)
                    -- serverseitige Kontrolle, ob der Spieler noch in der Zone ist
                    local ped = GetPlayerPed(src)
                    if ped ~= 0 and #(GetEntityCoords(ped) - Config.Jail.Center) > Config.Jail.Radius + 25.0 then
                        TriggerClientEvent('qb-adminjail:client:returnToJail', src)
                    end
                end
            elseif os.time() - j.started > Config.Transport.MaxDriveTime + 120 then
                -- Abholung hängt: direkt ins Jail setzen
                j.started = os.time()
                TriggerClientEvent('qb-adminjail:client:start', src, { time = j.time, reason = j.reason, transport = false })
            end
        end
    end
end)

-- ===== Exports für andere Resources =====

exports('JailPlayer', function(src, minutes, reason, by, transport)
    if Jailed[src] or not QBCore.Functions.GetPlayer(src) then return false end
    StartJail(src, minutes, reason or Config.DefaultReason, by or 'System', transport ~= false)
    return true
end)
exports('ReleasePlayer', Release)
exports('IsJailed', function(src) return Jailed[src] ~= nil end)
