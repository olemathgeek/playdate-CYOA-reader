-- Story Paths
-- An easy-reader choose-your-own-adventure for Playdate.
-- The story lives in story.lua. The reader's spot is saved with
-- playdate.datastore so "Continue" picks up where they left off.
--
-- Controls:
--   Up / Down or crank : read more, then pick a choice
--   A                  : choose
--   B                  : go back one page

import "CoreLibs/graphics"
import "story"

local pd  <const> = playdate
local gfx <const> = playdate.graphics

local fontLg  = gfx.font.new("fonts/Roobert-20-Medium")   -- story text / titles
local fontMd  = gfx.font.new("fonts/Roobert-11-Medium")   -- hints
local fontBld = gfx.font.new("fonts/Roobert-11-Bold")     -- choices

-- ─────────────────────────────────────────────
-- CONSTANTS
-- ─────────────────────────────────────────────
local SCREEN_W    <const> = 400
local SCREEN_H    <const> = 240
local MARGIN      <const> = 14
local TEXT_W      <const> = SCREEN_W - MARGIN * 2
local FOOTER_H    <const> = 20
local VIEW_H      <const> = SCREEN_H - FOOTER_H
local LINE_GAP    <const> = 4
local CHOICE_PAD  <const> = 6
local CHOICE_GAP  <const> = 6
local SCROLL_STEP <const> = 40
local SAVE_KEY    <const> = "progress"

local STATE_TITLE <const> = 1
local STATE_PAGE  <const> = 2

-- ─────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────
local state       = STATE_TITLE
local pageId      = STORY_START
local history     = {}     -- page ids visited before this one, for B = back
local layout      = nil    -- cached positions for the current page
local scrollY     = 0
local selected    = nil    -- index of highlighted choice, nil = still reading
local titleIndex  = 1
local titleItems  = {}

-- ─────────────────────────────────────────────
-- SAVE / LOAD
-- ─────────────────────────────────────────────
local function saveProgress()
    if state ~= STATE_PAGE then return end
    pd.datastore.write({ page = pageId, history = history }, SAVE_KEY)
end

local function clearProgress()
    pd.datastore.delete(SAVE_KEY)
end

local function loadProgress()
    local data = pd.datastore.read(SAVE_KEY)
    if data == nil or STORY[data.page] == nil then return nil end
    local cleanHistory = {}
    for _, id in ipairs(data.history or {}) do
        if STORY[id] then cleanHistory[#cleanHistory + 1] = id end
    end
    return data.page, cleanHistory
end

-- ─────────────────────────────────────────────
-- LAYOUT
-- ─────────────────────────────────────────────
-- Splits text into lines that fit maxWidth using the given font.
local function wrapText(text, font, maxWidth)
    local lines = {}
    local line = ""
    for word in text:gmatch("%S+") do
        local candidate = (line == "") and word or (line .. " " .. word)
        if font:getTextWidth(candidate) <= maxWidth or line == "" then
            line = candidate
        else
            lines[#lines + 1] = line
            line = word
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

local function choicesFor(page)
    if page.ending then
        return { { label = "Read again!", restart = true } }
    end
    return page.choices or {}
end

local function buildLayout(page)
    local l = { lines = {}, choices = {} }
    local y = MARGIN
    local lineH = fontLg:getHeight() + LINE_GAP

    for _, text in ipairs(wrapText(page.text, fontLg, TEXT_W)) do
        l.lines[#l.lines + 1] = { text = text, y = y }
        y += lineH
    end
    y += 10

    local choiceLineH = fontBld:getHeight() + 2
    for i, choice in ipairs(choicesFor(page)) do
        local wrapped = wrapText(choice.label, fontBld, TEXT_W - CHOICE_PAD * 2 - 16)
        local h = #wrapped * choiceLineH + CHOICE_PAD * 2
        l.choices[i] = { lines = wrapped, y = y, h = h, data = choice }
        y += h + CHOICE_GAP
    end

    l.contentH = y + MARGIN - CHOICE_GAP
    l.maxScroll = math.max(0, l.contentH - VIEW_H)
    return l
end

-- ─────────────────────────────────────────────
-- NAVIGATION
-- ─────────────────────────────────────────────
local function showPage(id)
    pageId   = id
    layout   = buildLayout(STORY[id])
    scrollY  = 0
    selected = nil
    -- Short pages: highlight the first choice right away.
    if layout.maxScroll == 0 and #layout.choices > 0 then selected = 1 end
    state = STATE_PAGE
    if STORY[id].ending then clearProgress() else saveProgress() end
end

local function startNew()
    history = {}
    showPage(STORY_START)
end

local function goTo(id)
    history[#history + 1] = pageId
    showPage(id)
end

local function goBack()
    if #history == 0 then return end
    showPage(table.remove(history))
end

local function buildTitleMenu()
    titleItems = {}
    local savedPage, savedHistory = loadProgress()
    if savedPage then
        titleItems[#titleItems + 1] = { label = "Keep reading", action = function()
            history = savedHistory
            showPage(savedPage)
        end }
        titleItems[#titleItems + 1] = { label = "Start over", action = startNew }
    else
        titleItems[#titleItems + 1] = { label = "Start", action = startNew }
    end
    titleIndex = 1
end

local function goToTitle()
    saveProgress()
    state = STATE_TITLE
    buildTitleMenu()
end

-- Keeps the highlighted choice on screen.
local function scrollToSelected()
    if not selected then return end
    local c = layout.choices[selected]
    if c.y - scrollY < MARGIN then
        scrollY = c.y - MARGIN
    elseif c.y + c.h - scrollY > VIEW_H - MARGIN then
        scrollY = c.y + c.h - VIEW_H + MARGIN
    end
    scrollY = math.max(0, math.min(layout.maxScroll, scrollY))
end

local function choiceFullyVisible(i)
    local c = layout.choices[i]
    return c and c.y + c.h - scrollY <= VIEW_H
end

-- ─────────────────────────────────────────────
-- INPUT
-- ─────────────────────────────────────────────
local function pageDown()
    if selected then
        selected = math.min(selected + 1, #layout.choices)
        scrollToSelected()
    elseif #layout.choices > 0 and choiceFullyVisible(1) then
        selected = 1
        scrollToSelected()
    else
        scrollY = math.min(layout.maxScroll, scrollY + SCROLL_STEP)
    end
end

local function pageUp()
    if selected and selected > 1 then
        selected -= 1
        scrollToSelected()
    else
        if selected and layout.maxScroll > 0 then selected = nil end
        scrollY = math.max(0, scrollY - SCROLL_STEP)
    end
end

local function pageChoose()
    if not selected then
        pageDown()
        return
    end
    local choice = layout.choices[selected].data
    if choice.restart then
        startNew()
    elseif STORY[choice.to] then
        goTo(choice.to)
    else
        print("story.lua: no page called '" .. tostring(choice.to) .. "'")
    end
end

-- ─────────────────────────────────────────────
-- DRAWING
-- ─────────────────────────────────────────────
local function drawFooter(hint)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(0, VIEW_H, SCREEN_W, FOOTER_H)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(0, VIEW_H, SCREEN_W, VIEW_H)
    fontMd:drawText(hint, MARGIN, VIEW_H + 4)
end

local function drawTitle()
    local w = fontLg:getTextWidth(STORY_TITLE)
    if w <= TEXT_W then
        fontLg:drawText(STORY_TITLE, (SCREEN_W - w) / 2, 50)
    else
        local lines = wrapText(STORY_TITLE, fontLg, TEXT_W)
        for i, line in ipairs(lines) do
            local lw = fontLg:getTextWidth(line)
            fontLg:drawText(line, (SCREEN_W - lw) / 2, 30 + (i - 1) * (fontLg:getHeight() + LINE_GAP))
        end
    end

    local boxW, boxH = 180, 30
    for i, item in ipairs(titleItems) do
        local x, y = (SCREEN_W - boxW) / 2, 120 + (i - 1) * (boxH + 10)
        local tw = fontBld:getTextWidth(item.label)
        if i == titleIndex then
            gfx.fillRoundRect(x, y, boxW, boxH, 6)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
            fontBld:drawText(item.label, x + (boxW - tw) / 2, y + (boxH - fontBld:getHeight()) / 2)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        else
            gfx.drawRoundRect(x, y, boxW, boxH, 6)
            fontBld:drawText(item.label, x + (boxW - tw) / 2, y + (boxH - fontBld:getHeight()) / 2)
        end
    end

    drawFooter("Up/Down: pick     A: go")
end

local function drawPage()
    for _, line in ipairs(layout.lines) do
        local y = line.y - scrollY
        if y > -40 and y < VIEW_H then
            fontLg:drawText(line.text, MARGIN, y)
        end
    end

    local choiceLineH = fontBld:getHeight() + 2
    for i, c in ipairs(layout.choices) do
        local y = c.y - scrollY
        if y + c.h > 0 and y < VIEW_H then
            local isSel = (i == selected)
            if isSel then
                gfx.fillRoundRect(MARGIN, y, TEXT_W, c.h, 6)
                gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
            else
                gfx.drawRoundRect(MARGIN, y, TEXT_W, c.h, 6)
            end
            fontBld:drawText(isSel and ">" or "-", MARGIN + CHOICE_PAD, y + CHOICE_PAD)
            for j, text in ipairs(c.lines) do
                fontBld:drawText(text, MARGIN + CHOICE_PAD + 16, y + CHOICE_PAD + (j - 1) * choiceLineH)
            end
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end
    end

    -- Little arrow when there is more to read below.
    if scrollY < layout.maxScroll then
        local cx, cy = SCREEN_W - 14, VIEW_H - 10
        gfx.fillTriangle(cx - 6, cy - 4, cx + 6, cy - 4, cx, cy + 3)
    end

    local hint = "A: choose"
    if not selected then hint = "Down: read more" end
    if #history > 0 then hint = hint .. "     B: back" end
    drawFooter(hint)
end

-- ─────────────────────────────────────────────
-- SYSTEM MENU
-- ─────────────────────────────────────────────
local menu = pd.getSystemMenu()
menu:addMenuItem("title screen", goToTitle)
menu:addMenuItem("start over", function()
    clearProgress()
    startNew()
end)

-- Save when the game is closed or the device goes to sleep.
function pd.gameWillTerminate() saveProgress() end
function pd.deviceWillSleep() saveProgress() end

-- ─────────────────────────────────────────────
-- MAIN LOOP
-- ─────────────────────────────────────────────
buildTitleMenu()

function pd.update()
    if state == STATE_TITLE then
        if pd.buttonJustPressed(pd.kButtonUp) then
            titleIndex = math.max(1, titleIndex - 1)
        elseif pd.buttonJustPressed(pd.kButtonDown) then
            titleIndex = math.min(#titleItems, titleIndex + 1)
        elseif pd.buttonJustPressed(pd.kButtonA) then
            titleItems[titleIndex].action()
        end
    else
        if pd.buttonJustPressed(pd.kButtonDown) then
            pageDown()
        elseif pd.buttonJustPressed(pd.kButtonUp) then
            pageUp()
        elseif pd.buttonJustPressed(pd.kButtonA) then
            pageChoose()
        elseif pd.buttonJustPressed(pd.kButtonB) then
            goBack()
        end

        local crank = pd.getCrankChange()
        if crank ~= 0 and layout.maxScroll > 0 then
            scrollY = math.max(0, math.min(layout.maxScroll, scrollY + crank))
        end
    end

    gfx.clear(gfx.kColorWhite)
    if state == STATE_TITLE then drawTitle() else drawPage() end
end
