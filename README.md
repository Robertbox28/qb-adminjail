# qb-adminjail – Admin-Jail mit NPC-Abholung

Autor: Robertbox28 · [robertbox28.ch](https://robertbox28.ch/) · Für Culture City

Bei kleinen Regelverstössen schickt ein Admin den Spieler per Befehl ins Admin-Jail.
Ein NPC-Polizist fährt mit Blaulicht zum Spieler, legt ihm Handschellen an, setzt ihn
hinten in den Streifenwagen und fährt ihn ins Jail. Die Zeit läuft erst ab der Ankunft.

## Installation
1. Ordner `qb-adminjail` in `resources/[qb]` (oder eigenen Ordner) kopieren.
2. In der `server.cfg` **nach** qb-core eintragen: `ensure qb-adminjail`
3. `config.lua` anpassen (Jail-Ort, Berechtigung, Fuel-Resource).

## Befehle (Standard: ab Gruppe `admin`)
| Befehl | Beschreibung |
|---|---|
| `/adminjail [ID] [Minuten] [Grund]` | Spieler wird vom NPC abgeholt und ins Jail gebracht |
| `/adminunjail [ID]` | Spieler sofort entlassen |
| `/adminjailzeit [ID] [Minuten]` | Restzeit ändern |
| `/adminjailliste` | Alle Spieler im Admin-Jail im Chat anzeigen |
| `/abschieben [ID] [Dauer] [Grund]` | Bann + NPC-Abholung zum Flughafen, Abflug, Kick. Dauer: `30m`, `12h`, `7d`, `2w`, `perm` |
| `/ajkoords` | Eigene Position als `vector4` in Chat und F8 (zum Einrichten der Config) |

## Abschiebung
Der Bann wird **sofort** in die Tabelle `bans` von qb-core geschrieben. Wer sich während der Fahrt
ausloggt, ist trotzdem gebannt. Danach: NPC-Abholung → Fahrt zum Terminal LSIA → Abflug-Szene → Kick
mit Grund und Dauer. Benötigt `oxmysql`.

## Verhalten
- Während der Abholung: Steuerung gesperrt (Umsehen, Chat, Funk, ESC gehen), unverwundbar.
- Keine Strasse in der Nähe, Spieler tot oder Fahrzeug steckt fest → automatische Abblende und Teleport ins Jail.
- Im Jail: keine Waffen, Inventar gesperrt, kein Einsteigen, Restzeit unten am Bildschirm.
- Wer die Zone verlässt, wird zurückgesetzt (Client alle 2 Sek., Server jede Minute).
- Die Restzeit wird in den Spieler-Metadaten (`adminjail`) gespeichert und läuft nur, solange der Spieler online ist.
  Wer sich ausloggt, landet beim nächsten Einloggen direkt wieder im Jail.
- Danach Entlassung am `Config.Jail.Release`-Punkt.

## Hinweise
- Standard-Ort ist der Hof von Bolingbroke. Wenn ihr Admin-Jail und normales Gefängnis trennen wollt,
  tragt einen abgelegenen Ort ein (`Center`, `Radius`, `Spawns`, `Release`, `Transport.Dropoff`).
- Nutzt euer Server `sv_entityLockdown strict`, setzt `Config.Transport.Networked = false`
  (dann sieht nur der Betroffene den Streifenwagen).
- Kurze Variante ohne lange Fahrt: `Config.Transport.SkipDrive = true`.

## Exports (Server)
```lua
exports['qb-adminjail']:JailPlayer(src, minuten, grund, von, mitTransport)
exports['qb-adminjail']:ReleasePlayer(src)
exports['qb-adminjail']:IsJailed(src)
```
