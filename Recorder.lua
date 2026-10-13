-- RXP Live Flight Recorder
-- Captures player quest events, coords, trainer visits, and flights into raw RXP syntax.

local ADDON_NAME = "RXP_Recorder"
local frame = CreateFrame("Frame", "RXP_RecorderEventFrame")

RXP_RecorderDB = RXP_RecorderDB or {
    isRecording = true,
    steps = {}
}

local questSnapshot = {} -- questID -> { [objIdx] = numFulfilled }

-- Helper to safely check for Blizzard's protected secret values (12.0+ / Midnight API)
local function IsSecret(v)
    if v == nil then return false end
    if _G.issecretvalue then
        local ok, isSec = pcall(_G.issecretvalue, v)
        if ok and isSec then return true end
    end
    if type(v) == "secret" then
        return true
    end
    return false
end

-- Safe coordinate & zone locator
local function GetLocation()
    local x, y, uiMapID, zoneName

    local okHBD, HBD = pcall(function() return LibStub and LibStub("HereBeDragons-2.0", true) end)
    if okHBD and HBD then
        pcall(function()
            local hx, hy, hMap = HBD:GetPlayerZonePosition()
            if hx and not IsSecret(hx) and hy and not IsSecret(hy) then
                x, y, uiMapID = hx, hy, hMap
            end
        end)
    end

    if (not x or IsSecret(x)) and C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
        pcall(function()
            local mapID = C_Map.GetBestMapForUnit("player")
            if mapID and not IsSecret(mapID) then
                uiMapID = mapID
                local pos = C_Map.GetPlayerMapPosition(mapID, "player")
                if pos and pos.x and pos.y and not IsSecret(pos.x) and not IsSecret(pos.y) then
                    x, y = pos.x, pos.y
                end
            end
        end)
    end

    if uiMapID and not IsSecret(uiMapID) and C_Map and C_Map.GetMapInfo then
        pcall(function()
            local mapInfo = C_Map.GetMapInfo(uiMapID)
            if mapInfo and mapInfo.name and not IsSecret(mapInfo.name) and mapInfo.name ~= "" then
                zoneName = mapInfo.name
            end
        end)
    end

    if not zoneName or zoneName == "" or IsSecret(zoneName) then
        local realZone = GetRealZoneText and GetRealZoneText()
        local zoneText = GetZoneText and GetZoneText()
        if realZone and not IsSecret(realZone) and realZone ~= "" then
            zoneName = realZone
        elseif zoneText and not IsSecret(zoneText) and zoneText ~= "" then
            zoneName = zoneText
        else
            zoneName = "UnknownZone"
        end
    end

    if x and y and not IsSecret(x) and not IsSecret(y) and type(x) == "number" and type(y) == "number" then
        return zoneName, x * 100, y * 100
    end

    return zoneName, 0, 0
end

local function GetTargetName()
    local ok, name = pcall(function()
        return UnitName("target") or UnitName("npc")
    end)
    if not ok or not name or IsSecret(name) or type(name) ~= "string" or name == "" then
        return nil
    end
    return name
end

-- Core logging function
local function AppendStep(lines, tagNote)
    if not RXP_RecorderDB.isRecording then return end

    local zone, x, y = GetLocation()
    local stepBlock = {}

    -- Only include .goto if we have valid coordinates and a known zone
    if zone and zone ~= "UnknownZone" and not IsSecret(zone) and x and y and (x > 0 or y > 0) then
        table.insert(stepBlock, string.format("    .goto %s,%.2f,%.2f", zone, x, y))
    end

    if type(lines) == "table" then
        for _, l in ipairs(lines) do
            if l and not IsSecret(l) and type(l) == "string" and l ~= "" then
                table.insert(stepBlock, "    " .. l)
            end
        end
    end

    if #stepBlock == 0 then return end

    -- Safe table.concat defense against any residual secret values or invalid types
    local safeConcat = {}
    for _, str in ipairs(stepBlock) do
        if str and not IsSecret(str) and (type(str) == "string" or type(str) == "number") then
            table.insert(safeConcat, str)
        end
    end

    if #safeConcat == 0 then return end

    local fullStep = "step\n" .. table.concat(safeConcat, "\n")
    table.insert(RXP_RecorderDB.steps, fullStep)

    local safeTag = (tagNote and not IsSecret(tagNote) and type(tagNote) == "string" and tagNote) or "Action"
    print(string.format("|cff00ff00[RXP Record]|r %s (Step #%d logged)", safeTag, #RXP_RecorderDB.steps))
end

-- Snapshot helper to detect which objective just increased
local function SnapshotQuests()
    questSnapshot = {}
    if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then return end

    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    if not numEntries or IsSecret(numEntries) then return end

    for index = 1, numEntries do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and info.questID and not IsSecret(info.questID) and info.questID > 0 then
            questSnapshot[info.questID] = {}
            local objectives = C_QuestLog.GetQuestObjectives(info.questID)
            if objectives then
                for objIdx, obj in ipairs(objectives) do
                    local fulfilled = (obj and obj.numFulfilled and not IsSecret(obj.numFulfilled)) and obj.numFulfilled or 0
                    questSnapshot[info.questID][objIdx] = fulfilled
                end
            end
        end
    end
end

-- UI Window for viewing & copying (Custom robust frame without legacy template dependencies)
local copyWindow = nil
local function ShowCopyWindow()
    if not copyWindow then
        local f = CreateFrame("Frame", "RXPRecorderCopyFrame", UIParent, "BackdropTemplate")
        f:SetSize(540, 480)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)

        -- Modern Backdrop styling
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false,
            edgeSize = 2,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        f:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
        f:SetBackdropBorderColor(0.25, 0.78, 0.35, 1.0) -- Distinct Green border

        -- Header Bar
        local header = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        header:SetPoint("TOPLEFT", 16, -14)
        header:SetText("|cff00ff00RXP Live Flight Recorder|r - Steps")

        -- Close Button (X)
        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        -- Subtitle instructions
        local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sub:SetPoint("TOPLEFT", 16, -38)
        sub:SetText("Press |cffffff00Ctrl+A|r then |cffffff00Ctrl+C|r to copy all steps into your guide file:")

        -- ScrollFrame
        local sf = CreateFrame("ScrollFrame", "RXPRecorderScrollFrame", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 16, -60)
        sf:SetPoint("BOTTOMRIGHT", -36, 50)

        -- Scroll child edit box container
        local eb = CreateFrame("EditBox", "RXPRecorderEditBox", sf)
        eb:SetMultiLine(true)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(480)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.editBox = eb

        -- Bottom Button: Select All
        local selectBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        selectBtn:SetPoint("BOTTOMLEFT", 16, 12)
        selectBtn:SetSize(130, 26)
        selectBtn:SetText("Select All")
        selectBtn:SetScript("OnClick", function()
            eb:SetFocus()
            eb:HighlightText()
        end)

        -- Bottom Button: Clear Buffer
        local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        clearBtn:SetPoint("BOTTOMRIGHT", -16, 12)
        clearBtn:SetSize(130, 26)
        clearBtn:SetText("Clear All Steps")
        clearBtn:SetScript("OnClick", function()
            RXP_RecorderDB.steps = {}
            eb:SetText("-- All steps cleared.")
            print("|cff00ff00[RXP Record]|r All recorded steps cleared.")
        end)

        copyWindow = f
    end

    local safeSteps = {}
    for _, s in ipairs(RXP_RecorderDB.steps or {}) do
        if s and not IsSecret(s) and type(s) == "string" then
            table.insert(safeSteps, s)
        end
    end

    local text = table.concat(safeSteps, "\n\n")
    if #safeSteps == 0 then
        text = "-- No steps recorded yet. Play normally or use /rc wp to drop a manual point."
    end
    copyWindow.editBox:SetText(text)
    copyWindow:Show()
    copyWindow.editBox:SetFocus()
    copyWindow.editBox:HighlightText()
end

-- Event Handling
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("QUEST_WATCH_UPDATE")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("TRAINER_SHOW")
frame:RegisterEvent("TAXIMAP_OPENED")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then
            RXP_RecorderDB = RXP_RecorderDB or {}
            if RXP_RecorderDB.isRecording == nil then RXP_RecorderDB.isRecording = true end
            RXP_RecorderDB.steps = RXP_RecorderDB.steps or {}
            local clean = {}
            for _, s in ipairs(RXP_RecorderDB.steps) do
                if s and not IsSecret(s) and type(s) == "string" then
                    table.insert(clean, s)
                end
            end
            RXP_RecorderDB.steps = clean
            SnapshotQuests()
            print(string.format("|cff00ff00[RXP Record]|r Loaded. Status: %s. Commands: |cff00ffff/rc|r or |cff00ffff/rxprecord|r", 
                RXP_RecorderDB.isRecording and "|cff00ff00RECORDING|r" or "|cffff0000PAUSED|r"))
        end

    elseif event == "QUEST_ACCEPTED" then
        local questID = ...
        if not questID or IsSecret(questID) then return end
        local rawTitle = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
        local title = (rawTitle and not IsSecret(rawTitle) and rawTitle) or ("Quest " .. tostring(questID))
        local target = GetTargetName()
        local lines = {
            string.format(".accept %d >>Accept %s", questID, title)
        }
        if target and not IsSecret(target) then
            table.insert(lines, string.format(".target %s", target))
        end
        AppendStep(lines, "Accepted: " .. title)
        SnapshotQuests()

    elseif event == "QUEST_TURNED_IN" then
        local questID = ...
        if not questID or IsSecret(questID) then return end
        local rawTitle = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
        local title = (rawTitle and not IsSecret(rawTitle) and rawTitle) or ("Quest " .. tostring(questID))
        local target = GetTargetName()
        local lines = {
            string.format(".turnin %d >>Turn in %s", questID, title)
        }
        if target and not IsSecret(target) then
            table.insert(lines, string.format(".target %s", target))
        end
        AppendStep(lines, "Turn-in: " .. title)
        SnapshotQuests()

    elseif event == "QUEST_WATCH_UPDATE" or event == "QUEST_LOG_UPDATE" then
        if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then return end
        local numEntries = C_QuestLog.GetNumQuestLogEntries()
        if not numEntries or IsSecret(numEntries) then return end
        for index = 1, numEntries do
            local info = C_QuestLog.GetInfo(index)
            if info and not info.isHeader and info.questID and not IsSecret(info.questID) and info.questID > 0 then
                local qID = info.questID
                local objectives = C_QuestLog.GetQuestObjectives(qID)
                if objectives then
                    for objIdx, obj in ipairs(objectives) do
                        local prev = (questSnapshot[qID] and questSnapshot[qID][objIdx]) or 0
                        local curr = (obj and obj.numFulfilled and not IsSecret(obj.numFulfilled)) and obj.numFulfilled or 0
                        local needed = (obj and obj.numRequired and not IsSecret(obj.numRequired)) and obj.numRequired or 0
                        local finished = (obj and obj.finished and not IsSecret(obj.finished)) and obj.finished or false

                        -- Objective completed or progressed
                        if curr > prev and (curr == needed or finished) then
                            local desc = (obj and obj.text and not IsSecret(obj.text)) and obj.text or ("Objective " .. objIdx)
                            local cleanText = desc:gsub(":%s*%d+/%d+", ""):gsub("%s*%(%d+%)", "")
                            AppendStep({
                                string.format(".complete %d,%d --%s", qID, objIdx, cleanText)
                            }, "Completed Obj: " .. cleanText)
                        end
                    end
                end
            end
        end
        SnapshotQuests()

    elseif event == "TRAINER_SHOW" then
        local trainerName = GetTargetName()
        local lines = {
            ".trainer >>Train spells"
        }
        if trainerName and not IsSecret(trainerName) then
            table.insert(lines, string.format(".target %s", trainerName))
        end
        local tag = (trainerName and not IsSecret(trainerName)) and ("Trainer: " .. trainerName) or "Trainer"
        AppendStep(lines, tag)

    elseif event == "TAXIMAP_OPENED" then
        AppendStep({
            ">>Take flight path"
        }, "Flight Master")
    end
end)

-- Slash Commands:
-- Note: /rxp is claimed by RXPGuides itself. We register /rc and /rxprecord to guarantee zero collisions.
local function SlashHandler(msg)
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "start" or cmd == "on" then
        RXP_RecorderDB.isRecording = true
        SnapshotQuests()
        print("|cff00ff00[RXP Record]|r Recording |cff00ff00STARTED|r. Play normally!")
    elseif cmd == "stop" or cmd == "pause" or cmd == "off" then
        RXP_RecorderDB.isRecording = false
        print("|cff00ff00[RXP Record]|r Recording |cffff0000PAUSED|r.")
    elseif cmd == "show" or cmd == "copy" or cmd == "view" or cmd == "" then
        ShowCopyWindow()
    elseif cmd == "clear" then
        RXP_RecorderDB.steps = {}
        print("|cff00ff00[RXP Record]|r Cleared all recorded steps.")
    elseif cmd == "wp" or cmd == "goto" or cmd == "note" then
        local note = (arg and arg ~= "") and (" >>" .. arg) or ""
        local tag = (arg and arg ~= "") and arg or "Manual Waypoint"
        AppendStep({ note ~= "" and note or ">>Travel here" }, tag)
    else
        print("|cff00ff00=== RXP Live Flight Recorder ===|r")
        print("  |cff00ffff/rc|r (or |cff00ffff/rc show|r)  - Open copy-paste window with recorded steps")
        print("  |cff00ffff/rc wp [note]|r - Drop a manual waypoint step at your current spot")
        print("  |cff00ffff/rc start|r     - Resume recording")
        print("  |cff00ffff/rc stop|r      - Pause recording")
        print("  |cff00ffff/rc clear|r     - Clear buffer")
    end
end

SLASH_RXPRECORD_CMD1 = "/rc"
SLASH_RXPRECORD_CMD2 = "/rxprecord"
SLASH_RXPRECORD_CMD3 = "/rxpr"
SlashCmdList["RXPRECORD_CMD"] = SlashHandler
