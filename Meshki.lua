MeshkiDB = MeshkiDB or {
    duration = 15,
    profile = "global",
    totalBags = 0,
    enabled = true,
    scale = 1,
    alpha = 1,
    width = 240,
    height = 180,
}

MeshkiCharDB = MeshkiCharDB or {
    flaskBags = 0,
    predictedBags = 0,
    totalIntervals = 0,
    intervalCount = 0,
    dryTimeTotal = 0,
    dryEvents = 0,
}

local DB = MeshkiDB
local CDB = MeshkiCharDB

local FLASK_SPELL_ID = 313544
local FLASK_DURATION = 600

local timeLeft = 0
local flaskActive = false
local flaskStart = 0
local lastLoot = 0
local treasureIcon = "Interface\\Icons\\INV_Misc_Bag_10_Blue"

local isReadyState = false
local readyStartTime = 0
local alertActive = false

local frame = CreateFrame("Frame", "MeshkiFrame", UIParent)
frame:SetSize(DB.width, DB.height)
frame:SetPoint("CENTER")
frame:SetScale(DB.scale)
frame:SetAlpha(DB.alpha)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:Hide()

frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)

-- ALERT
local alertFrame = CreateFrame("Frame", nil, frame)
alertFrame:SetAllPoints()
alertFrame:SetFrameLevel(frame:GetFrameLevel() - 1)
alertFrame:Hide()

local glowTex = alertFrame:CreateTexture(nil, "OVERLAY")
glowTex:SetAllPoints()
glowTex:SetTexture("Interface\\Buttons\\WHITE8X8")
glowTex:SetVertexColor(0, 1, 0, 0)
glowTex:SetBlendMode("ADD")

local function UpdateAlert(elapsed)
    if not flaskActive then
        alertActive = false
        alertFrame:Hide()
        return
    end
    if timeLeft <= 0 and not alertActive then
        alertActive = true
        alertFrame:Show()
        PlaySound("IG_ABILITY_PAGE_TURN")
    elseif timeLeft > 0 then
        alertActive = false
        alertFrame:Hide()
    end
    if alertActive then
        local alpha = (math.sin(GetTime() * 2) + 1) * 0.15
        glowTex:SetVertexColor(0, 1, 0, alpha)
    end
end

-- HEADER
local headerBar = frame:CreateTexture(nil, "ARTWORK")
headerBar:SetHeight(20)
headerBar:SetPoint("TOPLEFT", 0, 0)
headerBar:SetPoint("TOPRIGHT", 0, 0)
headerBar:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
headerBar:SetVertexColor(0.06, 0.06, 0.06, 0.95)

local headerIcon = frame:CreateTexture(nil, "OVERLAY")
headerIcon:SetSize(16, 16)
headerIcon:SetPoint("LEFT", headerBar, "LEFT", 6, 0)
headerIcon:SetTexture(treasureIcon)
headerIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

local headerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerText:SetPoint("LEFT", headerIcon, "RIGHT", 5, 0)
headerText:SetText("|cff00ffffMeshki|r")
headerText:SetJustifyH("LEFT")

-- FRAME VISIBILITY (объявлена ДО closeBtn)
local function UpdateFrameVisibility()
    if DB.enabled then
        frame:Show()
    else
        frame:Hide()
    end
end

-- CLOSE BUTTON
local closeBtn = CreateFrame("Button", nil, frame)
closeBtn:SetSize(14, 14)
closeBtn:SetPoint("RIGHT", headerBar, "RIGHT", -4, 0)
closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")

closeBtn:SetScript("OnClick", function()
    DB.enabled = false
    if type(UpdateFrameVisibility) == "function" then
        UpdateFrameVisibility()
    else
        frame:Hide()
    end
    if MeshkiEnableCheck and type(MeshkiEnableCheck.SetChecked) == "function" then
        MeshkiEnableCheck:SetChecked(false)
    end
    print("|cff00ff00Meshki:|r Аддон закрыт. Включить можно через /mesh или в Интерфейс -> Аддоны -> Meshki")
end)

closeBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Закрыть Meshki")
    GameTooltip:AddLine("Скрывает аддон. Состояние сохраняется.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)

closeBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- BG
local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetPoint("TOPLEFT", 0, -20)
bg:SetPoint("BOTTOMRIGHT", 0, 0)
bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
bg:SetVertexColor(0.1, 0.1, 0.1, 0.7)

-- TIMER
local timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
timerText:SetPoint("TOP", frame, "TOP", 0, -30)
timerText:SetText("|cff00ff00READY|r")
timerText:SetShadowOffset(1, -1)
timerText:SetShadowColor(0,0,0,1)

local timerBar = CreateFrame("StatusBar", nil, frame)
timerBar:SetSize(DB.width - 30, 12)
timerBar:SetPoint("TOP", timerText, "BOTTOM", 0, -5)
timerBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
timerBar:SetMinMaxValues(0, DB.duration)
timerBar:SetValue(DB.duration)
timerBar:SetStatusBarColor(0, 1, 0)

local timerBg = timerBar:CreateTexture(nil, "BACKGROUND")
timerBg:SetAllPoints()
timerBg:SetTexture(0, 0, 0, 0.6)

local timerBorder = timerBar:CreateTexture(nil, "BORDER")
timerBorder:SetAllPoints()
timerBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
timerBorder:SetVertexColor(0.5, 0.5, 0.5, 0.5)

-- METRICS
local metrics = {}
local metricNames = {"Всего", "Фласка", "Прогноз", "Простой (с)", "Меш/ч", "Ср (сек)"}
for i = 1, #metricNames do
    metrics[i] = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    metrics[i]:SetPoint("TOPLEFT", 10, -70 - (i - 1) * 18)
    metrics[i]:SetJustifyH("LEFT")
end

-- HELPERS
local function CheckFlask()
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
        if spellId == FLASK_SPELL_ID then
            return true
        end
    end
    return false
end

local function AutoDetectIcon(msg)
    local itemLink = msg:match("|Hitem:(%d+):")
    if itemLink then
        local texture = GetItemIcon(itemLink)
        if texture then
            treasureIcon = texture
            headerIcon:SetTexture(texture)
        end
    end
end

local function ResetSessionStats()
    CDB.flaskBags = 0
    CDB.predictedBags = 0
    CDB.totalIntervals = 0
    CDB.intervalCount = 0
    CDB.dryTimeTotal = 0
    CDB.dryEvents = 0
    lastLoot = 0
    isReadyState = false
    readyStartTime = 0
end

local function UpdateMetrics()
    local avg = 0
    if CDB.intervalCount > 0 then
        avg = CDB.totalIntervals / CDB.intervalCount
    end
    local predicted = 0
    if avg > 0 then
        predicted = FLASK_DURATION / avg
    end
    CDB.predictedBags = predicted
    local perHour = 0
    if flaskActive and flaskStart > 0 then
        local elapsed = GetTime() - flaskStart
        if elapsed > 0 then
            perHour = (CDB.flaskBags / elapsed) * 3600
        end
    end
    local dryAvg = 0
    if CDB.dryEvents > 0 then
        dryAvg = CDB.dryTimeTotal / CDB.dryEvents
    end
    metrics[1]:SetText(string.format("Всего: |cffffff00%d|r", DB.totalBags))
    metrics[2]:SetText(string.format("За текущую фласку: |cff00ffff%d|r", CDB.flaskBags))
    metrics[3]:SetText(string.format("Прогноз: |cff00ff00%.1f|r", predicted))
    metrics[4]:SetText(string.format("Простой (с): |cffffff00%.1f|r", dryAvg))
    metrics[5]:SetText(string.format("Меш/ч: |cff00ff00%.1f|r", perHour))
    metrics[6]:SetText(string.format("Ср (сек): |cffffff00%.1f|r", avg))
end

-- ONUPDATE
frame:SetScript("OnUpdate", function(self, elapsed)
    if not frame:IsShown() then
        return -- окно скрыто: никакой пер-фреймовой активности
    end
    if timeLeft > 0 then
        timeLeft = timeLeft - elapsed
        if timeLeft < 0 then timeLeft = 0 end
        timerText:SetText(string.format("%.1f", timeLeft))
        timerText:SetTextColor(1, 0, 0)
        timerBar:SetValue(timeLeft)
        timerBar:SetStatusBarColor(1, 0, 0)
        if isReadyState then
            isReadyState = false
            readyStartTime = 0
        end
    else
        timerText:SetText("|cff00ff00READY|r")
        timerText:SetTextColor(0, 1, 0)
        timerBar:SetValue(DB.duration)
        timerBar:SetStatusBarColor(0, 1, 0)
        if not isReadyState then
            isReadyState = true
            readyStartTime = GetTime()
        end
    end
    UpdateAlert(elapsed)
end)

-- EVENTS
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(self, event, arg1)
    -- UNIT_AURA приходит на КАЖДУЮ единицу вокруг (неймплейты и т.д.) — игнорируем всё, кроме player
    if event == "UNIT_AURA" and arg1 ~= "player" then
        return
    end

    if event == "ADDON_LOADED" and arg1 == "Meshki" then
        UpdateFrameVisibility()
        UpdateMetrics()
        return
    end

    -- Пока окно скрыто — не сканируем и не считаем ничего
    if not frame:IsShown() then
        return
    end

    if event == "CHAT_MSG_LOOT" then
        if arg1 and (arg1:find("Мешочек сокровищ") or arg1:find("Treasure Bag")) then
            local now = GetTime()
            PlaySound("LEVELUP")
            if isReadyState and readyStartTime > 0 then
                local dryDiff = now - readyStartTime
                CDB.dryTimeTotal = CDB.dryTimeTotal + dryDiff
                CDB.dryEvents = CDB.dryEvents + 1
            end
            isReadyState = false
            readyStartTime = 0
            timeLeft = DB.duration
            DB.totalBags = DB.totalBags + 1
            if flaskActive then
                CDB.flaskBags = CDB.flaskBags + 1
            end
            if lastLoot > 0 then
                local diff = now - lastLoot
                CDB.totalIntervals = CDB.totalIntervals + diff
                CDB.intervalCount = CDB.intervalCount + 1
            end
            lastLoot = now
            AutoDetectIcon(arg1)
            UpdateMetrics()
        end
    elseif event == "UNIT_AURA" then
        if CheckFlask() then
            if not flaskActive then
                flaskActive = true
                flaskStart = GetTime()
                ResetSessionStats()
                UpdateMetrics()
            end
        else
            flaskActive = false
        end
    end
end)

-- SLASH
SLASH_MESHKI1 = "/mesh"
SLASH_MESHKI2 = "/meshki"
SlashCmdList["MESHKI"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(.-)%s*$")
    if cmd == "" then
        DB.enabled = not DB.enabled
        UpdateFrameVisibility()
        print("|cff00ff00Meshki:|r " .. (DB.enabled and "Включено" or "Выключено"))
    elseif cmd == "reset" then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER")
        print("|cff00ff00Meshki:|r Позиция сброшена.")
    elseif cmd == "stats" then
        DB.totalBags = 0
        ResetSessionStats()
        UpdateMetrics()
        print("|cff00ff00Meshki:|r Статистика сброшена.")
    elseif cmd == "config" then
        InterfaceOptionsFrame_OpenToCategory("Meshki")
    elseif cmd == "debug" then
        print("|cff00ffffMeshki:|r DEBUG:")
        print("  enabled=" .. tostring(DB.enabled))
        print("  flaskActive=" .. tostring(flaskActive))
        print("  frame:IsShown()=" .. tostring(frame:IsShown()))
        print("  frame:GetName()=" .. frame:GetName())
    else
        local seconds = tonumber(cmd)
        if seconds then
            DB.duration = seconds
            timerBar:SetMinMaxValues(0, DB.duration)
            print("|cff00ff00Meshki:|r Таймер установлен на " .. seconds .. " сек.")
        else
            print("|cff00ff00Meshki команды:")
            print("/mesh - вкл/выкл")
            print("/mesh 20 - таймер (сек)")
            print("/mesh reset - позиция")
            print("/mesh stats - сброс статистики")
            print("/mesh debug - дебаг инфо")
        end
    end
end

-- OPTIONS
local panel = CreateFrame("Frame", "MeshkiOptionsPanel")
panel.name = "Meshki"

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Meshki Настройки")

local enableCheck = CreateFrame("CheckButton", "MeshkiEnableCheck", panel, "InterfaceOptionsCheckButtonTemplate")
enableCheck:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -20)
MeshkiEnableCheckText:SetText("Включить аддон")
enableCheck:SetChecked(DB.enabled)
enableCheck:SetScript("OnClick", function(self)
    DB.enabled = self:GetChecked()
    UpdateFrameVisibility()
end)

local scaleSlider = CreateFrame("Slider", "MeshkiScaleSlider", panel, "OptionsSliderTemplate")
scaleSlider:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, -20)
scaleSlider:SetMinMaxValues(0.5, 2)
scaleSlider:SetValueStep(0.1)
scaleSlider:SetWidth(200)
scaleSlider:SetValue(DB.scale)
MeshkiScaleSliderLow:SetText("0.5")
MeshkiScaleSliderHigh:SetText("2.0")
MeshkiScaleSliderText:SetText("Масштаб")
scaleSlider:SetScript("OnValueChanged", function(self, value)
    DB.scale = value
    frame:SetScale(value)
end)

local alphaSlider = CreateFrame("Slider", "MeshkiAlphaSlider", panel, "OptionsSliderTemplate")
alphaSlider:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -20)
alphaSlider:SetMinMaxValues(0.3, 1)
alphaSlider:SetValueStep(0.1)
alphaSlider:SetWidth(200)
alphaSlider:SetValue(DB.alpha)
MeshkiAlphaSliderLow:SetText("0.3")
MeshkiAlphaSliderHigh:SetText("1.0")
MeshkiAlphaSliderText:SetText("Прозрачность")
alphaSlider:SetScript("OnValueChanged", function(self, value)
    DB.alpha = value
    frame:SetAlpha(value)
end)

local widthSlider = CreateFrame("Slider", "MeshkiWidthSlider", panel, "OptionsSliderTemplate")
widthSlider:SetPoint("TOPLEFT", alphaSlider, "BOTTOMLEFT", 0, -20)
widthSlider:SetMinMaxValues(150, 300)
widthSlider:SetValueStep(10)
widthSlider:SetWidth(200)
widthSlider:SetValue(DB.width)
MeshkiWidthSliderLow:SetText("150")
MeshkiWidthSliderHigh:SetText("300")
MeshkiWidthSliderText:SetText("Ширина")
widthSlider:SetScript("OnValueChanged", function(self, value)
    DB.width = value
    frame:SetSize(DB.width, DB.height)
    timerBar:SetSize(DB.width - 30, 12)
    headerBar:SetWidth(DB.width)
end)

local durationSlider = CreateFrame("Slider", "MeshkiDurationSlider", panel, "OptionsSliderTemplate")
durationSlider:SetPoint("TOPLEFT", widthSlider, "BOTTOMLEFT", 0, -20)
durationSlider:SetMinMaxValues(5, 60)
durationSlider:SetValueStep(1)
durationSlider:SetWidth(200)
durationSlider:SetValue(DB.duration)
MeshkiDurationSliderLow:SetText("5")
MeshkiDurationSliderHigh:SetText("60")
MeshkiDurationSliderText:SetText("Таймер (сек)")
durationSlider:SetScript("OnValueChanged", function(self, value)
    DB.duration = math.floor(value)
    timerBar:SetMinMaxValues(0, DB.duration)
end)

local resetBtn = CreateFrame("Button", "MeshkiResetBtn", panel, "UIPanelButtonTemplate")
resetBtn:SetSize(120, 22)
resetBtn:SetPoint("TOPLEFT", durationSlider, "BOTTOMLEFT", 0, -20)
resetBtn:SetText("Сбросить статистику")
resetBtn:SetScript("OnClick", function()
    DB.totalBags = 0
    ResetSessionStats()
    UpdateMetrics()
    print("|cff00ff00Meshki:|r Статистика сброшена.")
end)

InterfaceOptions_AddCategory(panel)

UpdateMetrics()
UpdateFrameVisibility()
