fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Robertbox28 (https://robertbox28.ch/) – für Culture City'
description 'Admin-Jail mit NPC-Abholung für QBCore'
version '1.0.0'

shared_script 'config.lua'
client_script 'client/main.lua'
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

dependencies { 'qb-core', 'oxmysql' }
