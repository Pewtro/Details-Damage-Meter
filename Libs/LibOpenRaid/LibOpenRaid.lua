--[=[
Please refer to the docs.txt within this file folder for a guide on how to use this library.
If you get lost on implementing the lib, be free to contact Tercio on Details! discord: https://discord.gg/AGSzAZX or email to terciob19@hotmail.com
UnitID:
    UnitID use: "player", "target", "raid18", "party3", etc...
    If passing the unit name, use GetUnitName(unitId, true) or Ambiguate(playerName, 'none')
Code Rules:
    - When a function or variable name refers to 'Player', it indicates the local player.
    - When 'Unit' is use instead, it indicates any entity.
    - Internal callbacks are the internal communication of the library, e.g. when an event triggers it send to all modules that registered that event.
    - Public callbacks are callbacks registered by an external addon.
    - added:
        * openRaidLib.GetFlaskInfoBySpellId(spellId)
        * openRaidLib.GetFlaskTierFromAura(auraInfo)
        * openRaidLib.GetFoodInfoBySpellId(spellId)
        * openRaidLib.GetFoodTierFromAura(auraInfo)
        * added dragonflight talents support
        * added openRaidLib.RequestCooldownInfo(spellId)
        * added openRaidLib.AddCooldownFilter(filterName, spells)
TODO:
    - [not required as the lib is passing the entire gear equipped] add into gear info how many tier set parts the player has
    - raid lockouts normal-heroic-mythic
BUGS:
    - after a /reload, it is not starting new tickers for spells under cooldown
    - (asakawa report) after receiving a comm, the callback is firing twice
--]=]

local versionString, revision, launchDate, gameVersion = GetBuildInfo()

local isExpansion_Dragonflight = function()
    if (gameVersion >= 100000) then
        return true
    end
end

--don't load if it's not retail, emergencial patch due to classic and bcc stuff not transposed yet
if (WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE and not isExpansion_Dragonflight()) then
    return
end

local major = "LibOpenRaid-1.0"
local CONST_LIB_VERSION = 90

if (not LIB_OPEN_RAID_MAX_VERSION) then
    LIB_OPEN_RAID_MAX_VERSION = CONST_LIB_VERSION
else
    LIB_OPEN_RAID_MAX_VERSION = math.max(LIB_OPEN_RAID_MAX_VERSION, CONST_LIB_VERSION)
end

LIB_OPEN_RAID_CAN_LOAD = false

local unpack = table.unpack or _G.unpack

--declae the library within the LibStub
local libStub = _G.LibStub
local openRaidLib = libStub:NewLibrary(major, CONST_LIB_VERSION)

if (not openRaidLib) then
    return
end

openRaidLib.__version = CONST_LIB_VERSION

LIB_OPEN_RAID_CAN_LOAD = true

openRaidLib.__errors = {} --/dump LibStub:GetLibrary("LibOpenRaid-1.0").__errors

--default values
openRaidLib.inGroup = false
openRaidLib.UnitIDCache = {}

local CONST_CVAR_TEMPCACHE = "LibOpenRaidTempCache"
local CONST_CVAR_TEMPCACHE_DEBUG = "LibOpenRaidTempCacheDebug"

--show failures (when the function return an error) results to chat
local CONST_DIAGNOSTIC_ERRORS = false
--show the data to be sent and data received from comm
local CONST_DIAGNOSTIC_COMM = false
--show data received from other players
local CONST_DIAGNOSTIC_COMM_RECEIVED = false

local CONST_COMM_PREFIX = "LRS"
local CONST_COMM_FULLINFO_PREFIX = "F"

local CONST_COMM_COOLDOWNUPDATE_PREFIX = "U"
local CONST_COMM_COOLDOWNFULLLIST_PREFIX = "C"
local CONST_COMM_COOLDOWNCHANGES_PREFIX = "S"
local CONST_COMM_COOLDOWNREQUEST_PREFIX = "Z"

local CONST_COMM_GEARINFO_FULL_PREFIX = "G"
local CONST_COMM_GEARINFO_DURABILITY_PREFIX = "R"

local CONST_COMM_PLAYER_DEAD_PREFIX = "D"
local CONST_COMM_PLAYER_ALIVE_PREFIX = "A"
local CONST_COMM_PLAYERINFO_PREFIX = "P"
local CONST_COMM_PLAYERINFO_TALENTS_PREFIX = "T"
local CONST_COMM_PLAYERINFO_PVPTALENTS_PREFIX = "V"

local CONST_COMM_KEYSTONE_DATA_PREFIX = "K"
local CONST_COMM_KEYSTONE_DATAREQUEST_PREFIX = "J"

local CONST_COMM_SENDTO_PARTY = "0x1"
local CONST_COMM_SENDTO_RAID = "0x2"
local CONST_COMM_SENDTO_GUILD = "0x4"

local CONST_ONE_SECOND = 1.0
local CONST_TWO_SECONDS = 2.0
local CONST_THREE_SECONDS = 3.0

local CONST_SPECIALIZATION_VERSION_CLASSIC = 0
local CONST_SPECIALIZATION_VERSION_MODERN = 1

local CONST_COOLDOWN_CHECK_INTERVAL = CONST_ONE_SECOND
local CONST_COOLDOWN_TIMELEFT_HAS_CHANGED = CONST_ONE_SECOND

local CONST_COOLDOWN_INDEX_TIMELEFT = 1
local CONST_COOLDOWN_INDEX_CHARGES = 2
local CONST_COOLDOWN_INDEX_TIMEOFFSET = 3
local CONST_COOLDOWN_INDEX_DURATION = 4
local CONST_COOLDOWN_INDEX_UPDATETIME = 5
local CONST_COOLDOWN_INDEX_AURA_DURATION = 6

local CONST_COOLDOWN_INFO_SIZE = 6

local GetContainerNumSlots = GetContainerNumSlots or C_Container.GetContainerNumSlots
local GetContainerItemID = GetContainerItemID or C_Container.GetContainerItemID
local GetContainerItemLink = GetContainerItemLink or C_Container.GetContainerItemLink

--from vanilla to cataclysm, the specID did not existed, hence its considered version 0
--for mists of pandaria and beyond it's version 1
local getSpecializationVersion = function()
    if (gameVersion >= 50000) then
        return CONST_SPECIALIZATION_VERSION_MODERN
    else
        return CONST_SPECIALIZATION_VERSION_CLASSIC
    end
end

function openRaidLib.ShowDiagnosticErrors(value)
    CONST_DIAGNOSTIC_ERRORS = value
end

--make the 'pri-nt' word be only used once, this makes easier to find lost debug pri-nts in the code
local sendChatMessage = function(...)
    print(...)
end

openRaidLib.DiagnosticError = function(msg, ...)
    if (CONST_DIAGNOSTIC_ERRORS) then
        sendChatMessage("|cFFFF9922OpenRaidLib|r:", msg, ...)
    end
end

local diagnosticFilter = nil
local diagnosticComm = function(msg, ...)
    if (CONST_DIAGNOSTIC_COMM) then
        if (diagnosticFilter) then
            local lowerMessage = msg:lower()
            if (lowerMessage:find(diagnosticFilter)) then
                sendChatMessage("|cFFFF9922OpenRaidLib|r:", msg, ...)
            --dumpt(msg)
            end
        else
            sendChatMessage("|cFFFF9922OpenRaidLib|r:", msg, ...)
        end
    end
end

local diagnosticCommReceivedFilter = nil
openRaidLib.diagnosticCommReceived = function(msg, ...)
    if (diagnosticCommReceivedFilter) then
        local lowerMessage = msg:lower()
        if (lowerMessage:find(diagnosticCommReceivedFilter)) then
            sendChatMessage("|cFFFF9922OpenRaidLib|r:", msg, ...)
        end
    else
        sendChatMessage("|cFFFF9922OpenRaidLib|r:", msg, ...)
    end
end

openRaidLib.DeprecatedMessage = function(msg)
    sendChatMessage("|cFFFF9922OpenRaidLib|r:", "|cFFFF5555" .. msg .. "|r")
end

local isTimewalkWoW = function()
    local _, _, _, buildInfo = GetBuildInfo()
    if (buildInfo < 40000) then
        return true
    end
end

local checkClientVersion = function(...)
    for i = 1, select("#", ...) do
        local clientVersion = select(i, ...)

        if (clientVersion == "retail" and (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE or isExpansion_Dragonflight())) then --retail
            return true
        elseif (clientVersion == "classic_era" and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC) then --classic era (vanila)
            return true
        elseif (clientVersion == "bcc" and WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC) then --the burning crusade classic
            return true
        end
    end
end

--------------------------------------------------------------------------------------------------------------------------------
--~internal cache
--use a console variable to create a flash cache to keep data while the game reload
--this is not a long term database as saved variables are and it get clean up often

C_CVar.RegisterCVar(CONST_CVAR_TEMPCACHE)
C_CVar.RegisterCVar(CONST_CVAR_TEMPCACHE_DEBUG)

--internal namespace
local tempCache = {
    debugString = ""
}

tempCache.copyCache = function(t1, t2)
    for key, value in pairs(t2) do
        if (type(value) == "table") then
            t1[key] = t1[key] or {}
            tempCache.copyCache(t1[key], t2[key])
        else
            t1[key] = value
        end
    end
    return t1
end

--use debug cvar to find issues that occurred during the logoff process
function openRaidLib.PrintTempCacheDebug()
    local debugMessage = C_CVar.GetCVar(CONST_CVAR_TEMPCACHE_DEBUG)
    sendChatMessage("|cFFFF9922OpenRaidLib|r Temp CVar Result:\n", debugMessage)
end

function tempCache.SaveDebugText()
    C_CVar.SetCVar(CONST_CVAR_TEMPCACHE_DEBUG, tempCache.debugString)
end
