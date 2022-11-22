return result
end

function openRaidLib.CooldownManager.DoesSpellPassFilters(spellId, filters)
    --table with information about a single cooldown
    local thisCooldownInfo = openRaidLib.CooldownManager.GetCooldownInfo(spellId)
    --check if this spell is registered as a cooldown
    if (thisCooldownInfo) then
        for filter in filters:gmatch("([^,%s]+)") do
            --filterStringToCooldownType is a map where the key is the filter name and value is the cooldown type
            local cooldownType = filterStringToCooldownType[filter]
            --cooldown type is a number from 1 to 8 telling its type
            if (cooldownType == thisCooldownInfo.type) then
                return true

            --check for custom filter, the custom filter name is set as a key in the cooldownInfo: cooldownInfo[filterName] = true
            elseif (thisCooldownInfo[filter]) then
                return true
            end
        end
    end

    return false
end

local getCooldownsForFilter = function(unitName, allCooldowns, unitDataFilteredCache, filter)
    local allCooldownsData = openRaidLib.CooldownManager.GetAllRegisteredCooldowns()
    local filterTable = unitDataFilteredCache[filter]
    --if the unit already sent its full list of cooldowns, the cache can be built
    --when NeedRebuildFilters is true, HasFullCooldownList is always true

    --bug: filterTable is nil and HasFullCooldownList is also nil, happening after leaving a group internal callback
    --November 06, 2022 note: is this bug still happening?

    local doesNotHaveFilterYet = not filterTable and openRaidLib.CooldownManager.HasFullCooldownList[unitName]
    local isDirty = openRaidLib.CooldownManager.NeedRebuildFilters[unitName]

    if (doesNotHaveFilterYet or isDirty) then
        --reset the filterTable
        filterTable = {}
        unitDataFilteredCache[filter] = filterTable

        --
        for spellId, cooldownInfo in pairs(allCooldowns) do
            local cooldownData = allCooldownsData[spellId]
            if (cooldownData) then
                if (cooldownData.type == filterStringToCooldownType[filter]) then
                    filterTable[spellId] = cooldownInfo

                elseif (cooldownData[filter]) then --custom filter
                    filterTable[spellId] = cooldownInfo
                end
            end
        end
    end
    return filterTable
end

--API Call
--@filterName: a string representing a name of the filter
--@spells: an array of spellIds
--important: a spell can be part of any amount of custom filters,
--declaring a spell on a new filter does NOT remove it from other filters where it was previously added
function openRaidLib.AddCooldownFilter(filterName, spells)
    --integrity check
    if (type(filterName) ~= "string") then
        openRaidLib.DiagnosticError("Usage: openRaidLib.AddFilter(string: filterName, table: spells)", debugstack())
        return false

    elseif (type(spells) ~= "table") then
        openRaidLib.DiagnosticError("Usage: openRaidLib.AddFilter(string: filterName, table: spells)", debugstack())
        return false
    end

    local allCooldownsData = openRaidLib.CooldownManager.GetAllRegisteredCooldowns()

    --iterate among the all cooldowns table and erase the filterName from all spells
    for spellId, cooldownData in pairs(allCooldownsData) do
        cooldownData[filterName] = nil
        removeSpellFromCustomFilterCache(spellId, filterName)
    end

    --iterate among spells passed within the spells table and set the new filter on them
    --problem: the filter is set directly into the global cooldown table
    --this could in rare cases make an addon to override settings of another addon
    for spellIndex, spellId in ipairs(spells) do
        local cooldownData = allCooldownsData[spellId]
        if (cooldownData) then
            cooldownData[filterName] = true
            addSpellToCustomFilterCache(spellId, filterName)
        else
            openRaidLib.DiagnosticError("A spellId on your spell list for openRaidLib.AddFilter isn't registered as cooldown:", spellId, debugstack())
        end
    end

    --tag all cache filters as dirt
    local allUnitsCooldowns = openRaidLib.GetAllUnitsCooldown()
    for unitName in pairs(allUnitsCooldowns) do
        openRaidLib.CooldownManager.NeedRebuildFilters[unitName] = true
    end

    return true
end

--API Call
--@allCooldowns: all cooldowns sent by a unit, map{[spellId] = cooldownInfo}
--@filters: string with filter names: array{"defensive-raid, "defensive-personal"}
function openRaidLib.FilterCooldowns(unitName, allCooldowns, filters)
    local allDataFiltered = openRaidLib.CooldownManager.UnitDataFilterCache --["unitName"] = {defensive-raid = {[spellId = cooldownInfo]}}
    local unitDataFilteredCache = allDataFiltered[unitName]
    if (not unitDataFilteredCache) then
        unitDataFilteredCache = {}
        allDataFiltered[unitName] = unitDataFilteredCache
    end

    --before break the string into parts and build the filters, attempt to get cooldowns from the cache using the whole filter string
    local filterAlreadyInCache = unitDataFilteredCache[filters]
    if (filterAlreadyInCache and not openRaidLib.CooldownManager.NeedRebuildFilters[unitName]) then
        return filterAlreadyInCache
    end

    local resultFilters = {}

    --break the string into pieces and filter cooldowns
    for filter in filters:gmatch("([^,%s]+)") do
        local filterTable = getCooldownsForFilter(unitName, allCooldowns, unitDataFilteredCache, filter)
        if (filterTable) then
            openRaidLib.TCopy(resultFilters, filterTable)  --filter table is nil
        end
    end

    --cache the whole filter string
    if (next(resultFilters)) then
        unitDataFilteredCache[filters] = resultFilters
    end

    return resultFilters
end

--use to check if a spell is a flask buff, return a table containing .tier{}
function openRaidLib.GetFlaskInfoBySpellId(spellId)
    return LIB_OPEN_RAID_FLASK_BUFF[spellId]
end

--return a number indicating the flask tier, if the aura isn't a flask return nil
function openRaidLib.GetFlaskTierFromAura(auraInfo)
    local flaskTable = openRaidLib.GetFlaskInfoBySpellId(auraInfo.spellId)
    if (flaskTable) then
        local points = auraInfo.points
        if (points) then
            for i = 1, #points do
                local flaskTier = flaskTable.tier[points[i]]
                if (flaskTier) then
                    return flaskTier
                end
            end
        end
    end
    return nil
end

--use to check if a spell is a food buff, return a table containing .tier{} .status{} .localized{}
function openRaidLib.GetFoodInfoBySpellId(spellId)
    return LIB_OPEN_RAID_FOOD_BUFF[spellId]
end

--return a number indicating the food tier, if the aura isn't a food return nil
function openRaidLib.GetFoodTierFromAura(auraInfo)
    local foodTable = openRaidLib.GetFoodInfoBySpellId(auraInfo.spellId)
    if (foodTable) then
        local points = auraInfo.points
        if (points) then
            for i = 1, #points do
                local foodTier = foodTable.tier[points[i]]
                if (foodTier) then
                    return foodTier
                end
            end
        end
    end
    return nil
end

--called from AddUnitGearList() on LibOpenRaid file
function openRaidLib.GearManager.BuildEquipmentItemLinks(equippedGearList)
    equippedGearList = equippedGearList or {} --nil table for older versions

    for i = 1, #equippedGearList do
        local equipmentTable = equippedGearList[i]

        --equippedGearList is a indexed table with 4 indexes:
        local slotId = equipmentTable[1]
        local numGemSlots = equipmentTable[2]
        local itemLevel = equipmentTable[3]
        local partialItemLink = equipmentTable[4]

        if (partialItemLink and type(partialItemLink) == "string") then
            --get the itemId from the partial link to query the itemName with GetItemInfo
            local itemId = partialItemLink:match("^%:(%d+)%:")
            itemId = tonumber(itemId)

            if (itemId) then
                local itemName = GetItemInfo(itemId)
                if (itemName) then
                    --build the full item link
                    local itemLink = "|cFFEEEEEE|Hitem" .. partialItemLink .. "|h[" .. itemName .. "]|r"

                    --use GetItemInfo again with the now completed itemLink to query the item color
                    local _, _, itemQuality = GetItemInfo(itemLink)
                    itemQuality = itemQuality or 1
                    local qualityColor = ITEM_QUALITY_COLORS[itemQuality]

                    --replace the item color
                    --local r, g, b, hex = GetItemQualityColor(qualityColor)
                    itemLink = itemLink:gsub("FFEEEEEE", qualityColor.color:GenerateHexColor())

                    wipe(equipmentTable)

                    equipmentTable.slotId = slotId
                    equipmentTable.gemSlots = numGemSlots
                    equipmentTable.itemLevel = itemLevel
                    equipmentTable.itemLink = itemLink
                    equipmentTable.itemQuality = itemQuality
                    equipmentTable.itemId = itemId
                    equipmentTable.itemName = itemName

                    local _, _, enchantId, gemId1, gemId2, gemId3, gemId4, suffixId, uniqueId, levelOfTheItem, specId, upgradeInfo, instanceDifficultyId, numBonusIds, restLink = strsplit(":", itemLink)

                    local enchantAttribute = LIB_OPEN_RAID_ENCHANT_SLOTS[slotId]
                    local nEnchantId = 0
                    if (enchantAttribute) then --this slot can receive an enchat
                        if (enchantId and enchantId ~= "") then
                            enchantId = tonumber(enchantId)
                            nEnchantId = enchantId
                        end

                        --6400 and above is dragonflight enchantId number space
                        if (nEnchantId < 6300 and not LIB_OPEN_RAID_DEATHKNIGHT_RUNEFORGING_ENCHANT_IDS[nEnchantId]) then
                            nEnchantId = 0
                        end
                    end
                    equipmentTable.enchantId = nEnchantId

                    local nGemId = 0
                    local gemsIds = {gemId1, gemId2, gemId3, gemId4}

                    --check if the item has a socket
                    if (numGemSlots) then
                        --check if the socket is empty
                        for gemSlotId = 1, numGemSlots do
                            local gemId = tonumber(gemsIds[gemSlotId])
                            if (gemId and gemId >= 180000) then
                                nGemId = gemId
                                break
                            end
                        end
                    end

                    equipmentTable.gemId = nGemId
                end
            end
        end
    end
end