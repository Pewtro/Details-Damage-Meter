--[=[
    Dumping logical functions here, make the code of the main file smaller
--]=]



if (not LIB_OPEN_RAID_CAN_LOAD) then
	return
end

local openRaidLib = LibStub:GetLibrary("LibOpenRaid-1.0")

local CONST_FRACTION_OF_A_SECOND = 0.01

local CONST_COOLDOWN_TYPE_OFFENSIVE = 1
local CONST_COOLDOWN_TYPE_DEFENSIVE_PERSONAL = 2
local CONST_COOLDOWN_TYPE_DEFENSIVE_TARGET = 3
local CONST_COOLDOWN_TYPE_DEFENSIVE_RAID = 4
local CONST_COOLDOWN_TYPE_UTILITY = 5
local CONST_COOLDOWN_TYPE_INTERRUPT = 6

--hold spellIds and which custom caches the spell is in
--map[spellId] = map[filterName] = true
local spellsWithCustomFiltersCache = {}

--simple non recursive table copy
function openRaidLib.TCopy(tableToReceive, tableToCopy)
    if (not tableToCopy) then
        print(debugstack())
    end
    for key, value in pairs(tableToCopy) do
        tableToReceive[key] = value
    end
end

--find the normalized percent of the value in the range. e.g range of 200-400 and a value of 250 result in 0.25
--from details! framework
function openRaidLib.GetRangePercent(minValue, maxValue, value)
	return (value - minValue) / max((maxValue - minValue), 0.0000001)
end

--transform a table index into a string dividing values with a comma
--@table: an indexed table with unknown size
function openRaidLib.PackTable(table)
    local tableSize = #table
    local newString = "" .. tableSize .. ","
    for i = 1, tableSize do
        newString = newString .. table[i] .. ","
    end

    newString = newString:gsub(",$", "")
    return newString
end

function openRaidLib.PackTableAndSubTables(table)
    local totalSize = 0
    local subTablesAmount = #table
    for i = 1, subTablesAmount do
        totalSize = totalSize + #table[i]
    end

    local newString = "" .. totalSize .. ","

    for i = 1, subTablesAmount do
        local subTable = table[i]
        for subIndex = 1, #subTable do
            newString = newString .. subTable[subIndex] .. ","
        end
    end

    newString = newString:gsub(",$", "")
    return newString
end

--return is a number is almost equal to another within a tolerance range
function openRaidLib.isNearlyEqual(value1, value2, tolerance)
    tolerance = tolerance or CONST_FRACTION_OF_A_SECOND
    return abs(value1 - value2) <= tolerance
end

--return true if the lib is allowed to receive comms from other players
function openRaidLib.IsCommAllowed()
    return IsInGroup() or IsInRaid()
end

--stract some indexes of a table
local selectIndexes = function(table, startIndex, amountIndexes, zeroIfNil)
    local values = {}
    for i = startIndex, startIndex+amountIndexes do
        values[#values+1] = tonumber(table[i]) or (zeroIfNil and 0) or table[i]
    end
    return values
end

--transform a string table into a regular table
--@table: a table with unknown values
--@index: where in the table is the information we want
--@isPair: if true treat the table as pairs(), ipairs() otherwise
--@valueAsTable: return {value1, value2, value3}
--@amountOfValues: for the parameter above
function openRaidLib.UnpackTable(table, index, isPair, valueIsTable, amountOfValues)
    local result = {}
    local reservedIndexes = table[index]
    if (not reservedIndexes) then
        return result
    end
    local indexStart = index+1
    local indexEnd = reservedIndexes+index

    if (isPair) then
        amountOfValues = amountOfValues or 2
        for i = indexStart, indexEnd, amountOfValues do
            if (valueIsTable) then
                local key = tonumber(table[i])
                local values = selectIndexes(table, i+1, max(amountOfValues-2, 1), true)
                result[key] = values
            else
                local key = tonumber(table[i])
                local value = tonumber(table[i+1])
                result[key] = value
            end
        end
    else
        if (valueIsTable) then
            for i = indexStart, indexEnd, amountOfValues do
                local values = selectIndexes(table, i, amountOfValues - 1)
                tinsert(result, values)
            end
        else
            for i = indexStart, indexEnd do
                local value = tonumber(table[i])
                result[#result+1] = value
            end
        end
    end

    return result
end

--returns if the player is in group
function openRaidLib.IsInGroup()
    local inParty = IsInGroup()
    local inRaid = IsInRaid()
    return inParty or inRaid
end

function openRaidLib.UpdateUnitIDCache()
    openRaidLib.UnitIDCache = {}
    if (IsInRaid()) then
        for i = 1, GetNumGroupMembers() do
            local unitName = GetUnitName("raid"..i, true)
            if (unitName) then
                openRaidLib.UnitIDCache[unitName] = "raid"..i
            end
        end

    elseif (IsInGroup()) then
        for i = 1, GetNumGroupMembers() - 1 do
            local unitName = GetUnitName("party"..i, true)
            if (unitName) then
                openRaidLib.UnitIDCache[unitName] = "party"..i
            end
        end
    end

    openRaidLib.UnitIDCache[UnitName("player")] = "player"
end

function openRaidLib.GetUnitID(playerName)
    return openRaidLib.UnitIDCache[playerName] or playerName
end

--report: "filterStringToCooldownType doesn't include the new filters."
--answer: custom filter does not have a cooldown type, it is a mesh of spells
local filterStringToCooldownType = {
    ["defensive-raid"] = CONST_COOLDOWN_TYPE_DEFENSIVE_RAID,
    ["defensive-target"] = CONST_COOLDOWN_TYPE_DEFENSIVE_TARGET,
    ["defensive-personal"] = CONST_COOLDOWN_TYPE_DEFENSIVE_PERSONAL,
    ["ofensive"] = CONST_COOLDOWN_TYPE_OFFENSIVE,
    ["utility"] = CONST_COOLDOWN_TYPE_UTILITY,
    ["interrupt"] = CONST_COOLDOWN_TYPE_INTERRUPT,
}

local filterStringToCooldownTypeReverse = {
    [CONST_COOLDOWN_TYPE_DEFENSIVE_RAID] = "defensive-raid",
    [CONST_COOLDOWN_TYPE_DEFENSIVE_TARGET] = "defensive-target",
    [CONST_COOLDOWN_TYPE_DEFENSIVE_PERSONAL] = "defensive-personal",
    [CONST_COOLDOWN_TYPE_OFFENSIVE] = "ofensive",
    [CONST_COOLDOWN_TYPE_UTILITY] = "utility",
    [CONST_COOLDOWN_TYPE_INTERRUPT] = "interrupt",
}

local removeSpellFromCustomFilterCache = function(spellId, filterName)
    local spellFilterCache = spellsWithCustomFiltersCache[spellId]
    if (spellFilterCache) then
        spellFilterCache[filterName] = nil
    end
end

local addSpellToCustomFilterCache = function(spellId, filterName)
    local spellFilterCache = spellsWithCustomFiltersCache[spellId]
    if (not spellFilterCache) then
        spellFilterCache = {}
        spellsWithCustomFiltersCache[spellId] = spellFilterCache
    end
    spellFilterCache[filterName] = true
end

local getSpellCustomFiltersFromCache = function(spellId)
    local spellFilterCache = spellsWithCustomFiltersCache[spellId]
    local result = {}
    if (spellFilterCache) then
        for filterName in pairs(spellFilterCache) do
            result[filterName] = true
        end
    end
    return result
end

--LIB_OPEN_RAID_COOLDOWNS_INFO store all registered cooldowns in the file ThingsToMantain_<game version>
function openRaidLib.CooldownManager.GetAllRegisteredCooldowns()
    return LIB_OPEN_RAID_COOLDOWNS_INFO
end

function openRaidLib.CooldownManager.GetCooldownInfo(spellId)
    return openRaidLib.CooldownManager.GetAllRegisteredCooldowns()[spellId]
end

--return a map of filter names which the spell is in, map: {[filterName] = true}
--API Call documented in the docs.txt as openRaidLib.GetSpellFilters() the declaration is on the main file of the lib
function openRaidLib.CooldownManager.GetSpellFilters(spellId, defaultFilterOnly, customFiltersOnly)
    local result = {}

    if (not customFiltersOnly) then
        local thisCooldownInfo = openRaidLib.CooldownManager.GetCooldownInfo(spellId)
        local cooldownTypeFilter = filterStringToCooldownTypeReverse[thisCooldownInfo.type]
        if (cooldownTypeFilter) then
            result[cooldownTypeFilter] = true
        end
    end

    if (defaultFilterOnly) then
        return result
    end

    local customFilters = getSpellCustomFiltersFromCache(spellId)
    for filterName in pairs(customFilters) do
        result[filterName] = true
    end

    return result
end

function openRaidLib.CooldownManager.DoesSpellPassFilters(spellId, filters)
    --table with information about a single cooldown
    local thisCooldownInfo = openRaidLib.CooldownManager.GetCooldownInfo(spellId)
    --check if this spell is registered as a cooldown
    if (thisCooldownInfo) then
        for filter in filters:gmatch("([^,%s]+)") do