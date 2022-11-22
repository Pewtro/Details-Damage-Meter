
            --keystones are only available on retail
            if (not checkClientVersion("retail")) then
                return
            end

            --generate keystone info for the player
            local unitName = UnitName("player")
            local keystoneInfo = openRaidLib.KeystoneInfoManager.GetKeystoneInfo(unitName, true)
            openRaidLib.KeystoneInfoManager.UpdatePlayerKeystoneInfo(keystoneInfo)

            openRaidLib.publicCallback.TriggerCallback("KeystoneUpdate", unitName, keystoneInfo, openRaidLib.KeystoneInfoManager.KeystoneData)
            return true
        end

    --manager constructor
        openRaidLib.KeystoneInfoManager = {
            --structure:
            --[playerName] = {level = 2, mapID = 222}
            KeystoneData = {},
        }

        local keystoneTablePrototype = {
            level = 0,
            mapID = 0,
            challengeMapID = 0,
            classID = 0,
            rating = 0,
            mythicPlusMapID = 0,
        }

    --search the player backpack to find a mythic keystone
    --with the keystone object, it'll attempt to get the mythicPlusMapID to be used with C_ChallengeMode.GetMapUIInfo(mythicPlusMapID)
    --ATM we are obligated to do this due to C_MythicPlus.GetOwnedKeystoneMapID() return the same mapID for the two Tazavesh dungeons
    local getMythicPlusMapID = function()
        for backpackId = 0, 4 do
            for slotId = 1, GetContainerNumSlots(backpackId) do
                local itemId = GetContainerItemID(backpackId, slotId)
                if (itemId == LIB_OPEN_RAID_MYTHICKEYSTONE_ITEMID) then
                    local itemLink = GetContainerItemLink(backpackId, slotId)
                    local destroyedItemLink = itemLink:gsub("|", "")
                    local color, itemID, mythicPlusMapID = strsplit(":", destroyedItemLink)
                    return tonumber(mythicPlusMapID)
                end
            end
        end
    end

    function openRaidLib.KeystoneInfoManager.UpdatePlayerKeystoneInfo(keystoneInfo)
        keystoneInfo.level = C_MythicPlus.GetOwnedKeystoneLevel() or 0
        keystoneInfo.mapID = C_MythicPlus.GetOwnedKeystoneMapID() or 0
        keystoneInfo.mythicPlusMapID = getMythicPlusMapID() or 0
        keystoneInfo.challengeMapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID() or 0

        local _, _, playerClassID = UnitClass("player")
        keystoneInfo.classID = playerClassID

        local ratingSummary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
        keystoneInfo.rating = ratingSummary and ratingSummary.currentSeasonScore or 0
    end

    function openRaidLib.KeystoneInfoManager.GetAllKeystonesInfo()
        return openRaidLib.KeystoneInfoManager.KeystoneData
    end

    --get the keystone info table or create a new one if 'createNew' is true
    function openRaidLib.KeystoneInfoManager.GetKeystoneInfo(unitName, createNew)
        local keystoneInfo = openRaidLib.KeystoneInfoManager.KeystoneData[unitName]
        if (not keystoneInfo and createNew) then
            keystoneInfo = {}
            openRaidLib.TCopy(keystoneInfo, keystoneTablePrototype)
            openRaidLib.KeystoneInfoManager.KeystoneData[unitName] = keystoneInfo
        end
        return keystoneInfo
    end

    local getKeystoneInfoToComm = function()
        local playerName = UnitName("player")
        local keystoneInfo = openRaidLib.KeystoneInfoManager.GetKeystoneInfo(playerName, true)
        openRaidLib.KeystoneInfoManager.UpdatePlayerKeystoneInfo(keystoneInfo)

        local dataToSend = CONST_COMM_KEYSTONE_DATA_PREFIX .. "," .. keystoneInfo.level .. "," .. keystoneInfo.mapID .. "," .. keystoneInfo.challengeMapID .. "," .. keystoneInfo.classID .. "," .. keystoneInfo.rating .. "," .. keystoneInfo.mythicPlusMapID
        return dataToSend
    end

    function openRaidLib.KeystoneInfoManager.SendPlayerKeystoneInfoToParty()
        local dataToSend = getKeystoneInfoToComm()
        openRaidLib.commHandler.SendCommData(dataToSend, CONST_COMM_SENDTO_PARTY)
        diagnosticComm("SendPlayerKeystoneInfoToParty| " .. dataToSend) --debug
    end

    function openRaidLib.KeystoneInfoManager.SendPlayerKeystoneInfoToGuild()
        local dataToSend = getKeystoneInfoToComm()
        openRaidLib.commHandler.SendCommData(dataToSend, CONST_COMM_SENDTO_GUILD)
        diagnosticComm("SendPlayerKeystoneInfoToGuild| " .. dataToSend) --debug
    end

    --when a request data is received, only send the data to party and guild
    --sending stuff to raid need to be called my the application with 'openRaidLib.RequestKeystoneDataFromRaid()'
    function openRaidLib.KeystoneInfoManager.OnReceiveRequestData()
        if (not checkClientVersion("retail")) then
            return
        end

        --update the information about the key stone the player has
        local keystoneInfo = openRaidLib.KeystoneInfoManager.GetKeystoneInfo(UnitName("player"), true)
        openRaidLib.KeystoneInfoManager.UpdatePlayerKeystoneInfo(keystoneInfo)

        if (IsInGroup() and not IsInRaid()) then
            openRaidLib.Schedules.NewUniqueTimer(0.1, openRaidLib.KeystoneInfoManager.SendPlayerKeystoneInfoToParty, "KeystoneInfoManager", "sendKeystoneInfoToParty_Schedule")
        end

        if (IsInGuild()) then
            openRaidLib.Schedules.NewUniqueTimer(math.random(0, 3) + math.random(), openRaidLib.KeystoneInfoManager.SendPlayerKeystoneInfoToGuild, "KeystoneInfoManager", "sendKeystoneInfoToGuild_Schedule")
        end
    end
    openRaidLib.commHandler.RegisterComm(CONST_COMM_KEYSTONE_DATAREQUEST_PREFIX, openRaidLib.KeystoneInfoManager.OnReceiveRequestData)

    function openRaidLib.KeystoneInfoManager.OnReceiveKeystoneData(data, unitName)
        if (not checkClientVersion("retail")) then
            return
        end

        local level = tonumber(data[1])
        local mapID = tonumber(data[2])
        local challengeMapID = tonumber(data[3])
        local classID = tonumber(data[4])
        local rating = tonumber(data[5])
        local mythicPlusMapID = tonumber(data[6])

        if (level and mapID and challengeMapID and classID and rating and mythicPlusMapID) then
            local keystoneInfo = openRaidLib.KeystoneInfoManager.GetKeystoneInfo(unitName, true)
            keystoneInfo.level = level
            keystoneInfo.mapID = mapID
            keystoneInfo.mythicPlusMapID = mythicPlusMapID
            keystoneInfo.challengeMapID = challengeMapID
            keystoneInfo.classID = classID
            keystoneInfo.rating = rating

            --trigger public callback
            openRaidLib.publicCallback.TriggerCallback("KeystoneUpdate", unitName, keystoneInfo, openRaidLib.KeystoneInfoManager.KeystoneData)
        end
    end
    openRaidLib.commHandler.RegisterComm(CONST_COMM_KEYSTONE_DATA_PREFIX, openRaidLib.KeystoneInfoManager.OnReceiveKeystoneData)

    --on entering a group, send keystone information for the party
    function openRaidLib.KeystoneInfoManager.OnPlayerEnterGroup()
        --keystones are only available on retail
        if (not checkClientVersion("retail")) then
            return
        end

        if (IsInGroup() and not IsInRaid()) then
            --update the information about the key stone the player has
            local keystoneInfo = openRaidLib.KeystoneInfoManager.GetKeystoneInfo(UnitName("player"), true)
            openRaidLib.KeystoneInfoManager.UpdatePlayerKeystoneInfo(keystoneInfo)

            --send to the group which keystone the player has
            openRaidLib.Schedules.NewUniqueTimer(1 + math.random(0, 2) + math.random(), openRaidLib.KeystoneInfoManager.SendPlayerKeystoneInfoToParty, "KeystoneInfoManager", "sendKeystoneInfoToParty_Schedule")
        end
    end

    function openRaidLib.KeystoneInfoManager.OnPlayerEnterWorld()
        --keystones are only available on retail
        if (not checkClientVersion("retail")) then
            return
        end
        --hack: on received data send data to party and guild
        openRaidLib.KeystoneInfoManager.OnReceiveRequestData()

        --trigger public callback
        local unitName = UnitName("player")
        local keystoneInfo = openRaidLib.KeystoneInfoManager.GetKeystoneInfo(unitName, true)
        openRaidLib.KeystoneInfoManager.UpdatePlayerKeystoneInfo(keystoneInfo)

        openRaidLib.publicCallback.TriggerCallback("KeystoneUpdate", unitName, keystoneInfo, openRaidLib.KeystoneInfoManager.KeystoneData)
    end

    function openRaidLib.KeystoneInfoManager.OnMythicDungeonFinished()
        --keystones are only available on retail
        if (not checkClientVersion("retail")) then
            return
        end
        --hack: on received data send data to party and guild
        openRaidLib.KeystoneInfoManager.OnReceiveRequestData()

        --trigger public callback
        local unitName = UnitName("player")
        local keystoneInfo = openRaidLib.KeystoneInfoManager.GetKeystoneInfo(unitName, true)
        openRaidLib.KeystoneInfoManager.UpdatePlayerKeystoneInfo(keystoneInfo)

        openRaidLib.publicCallback.TriggerCallback("KeystoneUpdate", unitName, keystoneInfo, openRaidLib.KeystoneInfoManager.KeystoneData)
    end

    openRaidLib.internalCallback.RegisterCallback("onEnterWorld", openRaidLib.KeystoneInfoManager.OnPlayerEnterWorld)
    openRaidLib.internalCallback.RegisterCallback("onEnterGroup", openRaidLib.KeystoneInfoManager.OnPlayerEnterGroup)
    openRaidLib.internalCallback.RegisterCallback("mythicDungeonEnd", openRaidLib.KeystoneInfoManager.OnMythicDungeonFinished)

--------------------------------------------------------------------------------------------------------------------------------
--data

--vintage cooldown tracker and interrupt tracker
C_Timer.After(0.1, function()
    local vintageCDTrackerFrame = CreateFrame("frame")
    vintageCDTrackerFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    local allCooldownsFromLib = LIB_OPEN_RAID_COOLDOWNS_INFO
    local recentCastedSpells =  {}

    vintageCDTrackerFrame:SetScript("OnEvent", function(self, event, ...)
        if (event == "UNIT_SPELLCAST_SUCCEEDED") then
            local unit, castGUID, spellId = ...

            local unitIsThePlayer = UnitIsUnit(unit, "player")
            if (not unitIsThePlayer) then
                local unitName = GetUnitName(unit, true)
                local hasLib = openRaidLib.CooldownManager.HasFullCooldownList[unitName]
                if (unitName and not hasLib) then
                    local unitInGroup = UnitInParty(unit) or UnitInRaid(unit)
                    if (unitInGroup) then
                        local cooldownInfo = allCooldownsFromLib[spellId]
                        if (cooldownInfo) then -- and not openRaidLib.GetUnitCooldown(unitName)
                            --check for cast_success spam from channel spells
                            local unitCastCooldown = recentCastedSpells[unitName]
                            if (not unitCastCooldown) then
                                unitCastCooldown = {}
                                recentCastedSpells[unitName] = unitCastCooldown
                            end

                            if (not unitCastCooldown[spellId] or unitCastCooldown[spellId]+5 < GetTime()) then
                                unitCastCooldown[spellId] = GetTime()

                                --trigger a cooldown usage
                                local duration = cooldownInfo.duration
                                --time left, charges, startTimeOffset, duration
                                openRaidLib.CooldownManager.CooldownSpellUpdate(unitName, spellId, duration, 0, 0, duration, 0)
                                local cooldownInfo = cooldownGetSpellInfo(unitName, spellId)
                                local unitCooldownsTable = openRaidLib.GetUnitCooldowns(unitName)

                                --trigger a public callback
                                openRaidLib.publicCallback.TriggerCallback("CooldownUpdate", openRaidLib.GetUnitID(unitName), spellId, cooldownInfo, unitCooldownsTable, openRaidLib.CooldownManager.UnitData)
                            end
                        end
                    end
                end
            end
        end
    end)
end)

tempCache.RestoreData()


--[=[
3x ...ns/Details/Libs/LibOpenRaid/GetPlayerInformation.lua:603: attempt to index field '?' (a nil value)
[string "@Interface/AddOns/Details/Libs/LibOpenRaid/GetPlayerInformation.lua"]:634: in function `GetPlayerCooldownStatus'
[string "@Interface/AddOns/Details/Libs/LibOpenRaid/LibOpenRaid.lua"]:1696: in function `CleanupCooldownTickers'
[string "@Interface/AddOns/Details/Libs/LibOpenRaid/LibOpenRaid.lua"]:1925: in function <...face/AddOns/Details/Libs/LibOpenRaid/LibOpenRaid.lua:1924>
[string "=[C]"]: in function `xpcall'
[string "@Interface/AddOns/Details/Libs/LibOpenRaid/LibOpenRaid.lua"]:506: in function <...face/AddOns/Details/Libs/LibOpenRaid/LibOpenRaid.lua:496>
]=]