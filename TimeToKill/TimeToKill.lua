-- Table to store (time, health) data points
local dataPoints = {}

-- Only compute regression if at least 2 points are available
local minDataPoints = 2
local updateInterval = 0.5  -- seconds between updates
local timeSinceLastUpdate = 0
local inCombat = false

local frame = CreateFrame("Frame", "TimeToKillAddonFrame", UIParent)
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UNIT_HEALTH")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED") -- Combat started
frame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Combat ended

-- Reset the stored data when you change target
local function ResetDataPoints()
    dataPoints = {}
end

-- Add a data point if a valid target exists and is alive
local function AddDataPoint()
    if UnitExists("target") and not UnitIsDead("target") then
        local currentHealth = UnitHealth("target")
        local currentTime = GetTime()
        table.insert(dataPoints, { time = currentTime, health = currentHealth })
        -- Optional: keep only data for the last 30 seconds
        while (#dataPoints > 0 and (currentTime - dataPoints[1].time > 30)) do
            table.remove(dataPoints, 1)
        end
    end
end

-- Perform linear regression on the collected points
local function LinearRegression(points)
    local n = #points
    if n < minDataPoints then
        return nil
    end

    local sumX, sumY, sumXY, sumXX = 0, 0, 0, 0
    for _, point in ipairs(points) do
        sumX = sumX + point.time
        sumY = sumY + point.health
        sumXY = sumXY + point.time * point.health
        sumXX = sumXX + point.time * point.time
    end

    local denominator = (n * sumXX - sumX * sumX)
    if denominator == 0 then
        return nil
    end

    local slope = (n * sumXY - sumX * sumY) / denominator
    local intercept = (sumY - slope * sumX) / n

    return slope, intercept
end

-- Calculate and update the time-to-kill display
local function UpdateTimeToKill()
    if not UnitExists("target") or UnitIsDead("target") then
        TimeToKillFrameText:SetText("Time To Kill: N/A")
        return
    end

    local slope, intercept = LinearRegression(dataPoints)
    if not slope or slope >= 0 then
        -- If we don't have enough data or the health isn't decreasing
        TimeToKillFrameText:SetText("Time To Kill: Calculating...")
        return
    end

    local currentTime = GetTime()
    local currentHealth = UnitHealth("target")
    -- The regression gives: health = slope * time + intercept.
    -- We solve for time when health = 0:
    local predictedDeathTime = -intercept / slope
    local timeRemaining = predictedDeathTime - currentTime
    if timeRemaining < 0 then timeRemaining = 0 end

    TimeToKillFrameText:SetText(string.format("Time To Kill: %.1f sec", timeRemaining))
end

-- Toggle frame visibility based on combat state and settings
local function UpdateFrameVisibility()
    -- If alwaysShow is enabled, show the frame regardless of combat
    if TimeToKillDB and TimeToKillDB.alwaysShow then
        TimeToKillFrame:Show()
    -- Otherwise, only show in combat with a valid target
    elseif inCombat and UnitExists("target") and not UnitIsDead("target") then
        TimeToKillFrame:Show()
    else
        TimeToKillFrame:Hide()
    end
end

-- Make the frame movable and resizable
local function SetupMovableFrame()
    local displayFrame = TimeToKillFrame
    
    -- Explicitly set frame properties
    displayFrame:SetMovable(true)
    displayFrame:EnableMouse(true)
    displayFrame:SetClampedToScreen(true)
    displayFrame:SetResizable(true)
    
    -- Set backdrop properties in Lua instead of XML
    displayFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    
    -- Register for different mouse actions
    displayFrame:RegisterForDrag("LeftButton")
    
    -- Create a resize button in the bottom-right corner
    local resizeBtn = CreateFrame("Button", nil, displayFrame)
    resizeBtn:SetPoint("BOTTOMRIGHT")
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    
    -- Setup script handlers
    displayFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    
    displayFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position between sessions
        local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
        if not TimeToKillDB then TimeToKillDB = {} end
        TimeToKillDB.position = {point = point, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs}
    end)
    
    resizeBtn:SetScript("OnMouseDown", function()
        displayFrame:StartSizing("BOTTOMRIGHT")
    end)
    
    resizeBtn:SetScript("OnMouseUp", function()
        displayFrame:StopMovingOrSizing()
        -- Save size between sessions
        if not TimeToKillDB then TimeToKillDB = {} end
        TimeToKillDB.width = displayFrame:GetWidth()
        TimeToKillDB.height = displayFrame:GetHeight()
    end)
    
    -- Load saved position and size
    if TimeToKillDB then
        if TimeToKillDB.position then
            displayFrame:ClearAllPoints()
            displayFrame:SetPoint(
                TimeToKillDB.position.point,
                nil,
                TimeToKillDB.position.relativePoint,
                TimeToKillDB.position.xOfs,
                TimeToKillDB.position.yOfs
            )
        end
        
        if TimeToKillDB.width and TimeToKillDB.height then
            displayFrame:SetSize(TimeToKillDB.width, TimeToKillDB.height)
        end
    end
    
    -- Initially update visibility based on combat state
    UpdateFrameVisibility()
end

-- Add slash command functionality
SLASH_TIMETOKILL1 = "/ttk"
SlashCmdList["TIMETOKILL"] = function(msg)
    msg = msg:lower()
    
    if msg == "show" then
        -- Force show the frame regardless of combat state
        TimeToKillDB = TimeToKillDB or {}
        TimeToKillDB.alwaysShow = true
        TimeToKillFrame:Show()
        print("TimeToKill: Frame always shown")
    elseif msg == "hide" then
        -- Force hide the frame regardless of combat state
        TimeToKillDB = TimeToKillDB or {}
        TimeToKillDB.alwaysShow = false
        TimeToKillFrame:Hide()
        print("TimeToKill: Frame hidden outside of combat")
    elseif msg == "toggle" then
        -- Toggle between always show and combat-only show
        TimeToKillDB = TimeToKillDB or {}
        TimeToKillDB.alwaysShow = not (TimeToKillDB.alwaysShow or false)
        if TimeToKillDB.alwaysShow then
            TimeToKillFrame:Show()
            print("TimeToKill: Frame always shown")
        else
            UpdateFrameVisibility()
            print("TimeToKill: Frame hidden outside of combat")
        end
    else
        -- Show help text
        print("TimeToKill commands:")
        print("  /ttk show - Always show the frame")
        print("  /ttk hide - Only show the frame in combat")
        print("  /ttk toggle - Toggle between always show and combat-only")
    end
end

-- Event handler
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_TARGET_CHANGED" then
        ResetDataPoints()
        UpdateFrameVisibility()
    elseif event == "UNIT_HEALTH" then
        if arg1 == "target" then
            AddDataPoint()
        end
    elseif event == "ADDON_LOADED" and arg1 == "TimeToKill" then
        -- Set up the movable frame when the addon is fully loaded
        SetupMovableFrame()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Player entered combat
        inCombat = true
        UpdateFrameVisibility()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Player left combat
        inCombat = false
        UpdateFrameVisibility()
    end
end)

-- OnUpdate handler to periodically update the display
frame:SetScript("OnUpdate", function(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    if timeSinceLastUpdate >= updateInterval then
        UpdateTimeToKill()
        timeSinceLastUpdate = 0
    end
end)