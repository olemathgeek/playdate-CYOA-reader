-- Story Paths
-- An easy-reader choose-your-own-adventure for Playdate.
-- Stories are JSON files in source/stories/ (see README for the format).
-- The reader's spot is saved with playdate.datastore so "Keep reading"
-- picks up where they left off.
--
-- Controls:
--   Up / Down or crank : read more, then pick a choice
--   A                  : choose
--   B                  : go back one page

import "CoreLibs/graphics"

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
local VIEW_BOTTOM <const> = VIEW_H - 4   -- rows must end above this to be drawn
local CRANK_STEP  <const> = 45          -- crank degrees per line
local SAVE_KEY    <const> = "progress"
local STORY_DIR   <const> = "stories/"
local TITLE_ROWS  <const> = 4      -- menu rows visible at once

local STATE_TITLE <const> = 1
local STATE_PAGE  <const> = 2

-- ─────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────
local state       = STATE_TITLE
local stories     = {}     -- { file, title, start, pages } for each valid JSON story
local story       = nil    -- the story being read
local pageId      = nil
local history     = {}     -- page ids visited before this one, for B = back
local layout      = nil    -- cached positions for the current page
local scrollY     = 0      -- always the top of a row, so no line is drawn half cut off
local crankAccum  = 0
local selected    = nil    -- index of highlighted choice, nil = still reading
local titleIndex  = 1
local titleTop    = 1      -- first menu row shown, for long story lists
local titleItems  = {}

-- ─────────────────────────────────────────────
-- STORIES
-- ─────────────────────────────────────────────
-- Loads one story file and checks every choice points at a real page.
local function loadStory(file)
    local data = json.decodeFile(STORY_DIR .. file)
    if type(data) ~= "table" or type(data.pages) ~= "table" then
        print("stories/" .. file .. ": not a story (needs \"pages\")")
        return nil
    end
    local start = data.start or "start"
    if data.pages[start] == nil then
        print("stories/" .. file .. ": no start page called '" .. start .. "'")
        return nil
    end
    for id, page in pairs(data.pages) do
        if type(page.text) ~= "string" then
            print("stories/" .. file .. ": page '" .. id .. "' has no text")
            return nil
        end
        for _, choice in ipairs(page.choices or {}) do
            if data.pages[choice.to] == nil then
                print("stories/" .. file .. ": page '" .. id .. "' points to missing page '" .. tostring(choice.to) .. "'")
                return nil
            end
        end
    end
    return { file = file, title = data.title or file, start = start, pages = data.pages }
end

local function loadAllStories()
    stories = {}
    for _, file in ipairs(pd.file.listFiles(STORY_DIR) or {}) do
        if file:match("%.json$") then
            local s = loadStory(file)
            if s then stories[#stories + 1] = s end
        end
    end
    table.sort(stories, function(a, b) return a.title < b.title end)
end

local function findStory(file)
    for _, s in ipairs(stories) do
        if s.file == file then return s end
    end
    return nil
end

-- ─────────────────────────────────────────────
-- SAVE / LOAD
-- ─────────────────────────────────────────────
local function saveProgress()
    if state ~= STATE_PAGE then return end
    pd.datastore.write({ story = story.file, page = pageId, history = history }, SAVE_KEY)
end

local function clearProgress()
    pd.datastore.delete(SAVE_KEY)
end

local function loadProgress()
    local data = pd.datastore.read(SAVE_KEY)
    if data == nil then return nil end
    local s = findStory(data.story)
    if s == nil or s.pages[data.page] == nil then return nil end
    local cleanHistory = {}
    for _, id in ipairs(data.history or {}) do
        if s.pages[id] then cleanHistory[#cleanHistory + 1] = id end
    end
    return s, data.page, cleanHistory
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
        return {
            { label = "Read again!", restart = true },
            { label = "Pick a new story", menu = true },
        }
    end
    return page.choices or {}
end

local function buildLayout(page)
    local l = { lines = {}, choices = {} }
    local y = MARGIN
    local lineH = fontLg:getHeight() + LINE_GAP

    l.rows = {}   -- every line and choice box as { y, bottom }, top to bottom
    for _, text in ipairs(wrapText(page.text, fontLg, TEXT_W)) do
        l.lines[#l.lines + 1] = { text = text, y = y }
        l.rows[#l.rows + 1] = { y = y, bottom = y + fontLg:getHeight() }
        y += lineH
    end
    y += 10

    local choiceLineH = fontBld:getHeight() + 2
    for i, choice in ipairs(choicesFor(page)) do
        local wrapped = wrapText(choice.label, fontBld, TEXT_W - CHOICE_PAD * 2 - 16)
        local h = #wrapped * choiceLineH + CHOICE_PAD * 2
        l.choices[i] = { lines = wrapped, y = y, h = h, data = choice }
        l.rows[#l.rows + 1] = { y = y, bottom = y + h }
        y += h + CHOICE_GAP
    end

    -- Furthest scroll: the first row from which everything left fits on screen.
    if #l.rows == 0 then l.rows[1] = { y = MARGIN, bottom = MARGIN } end
    local lastBottom = l.rows[#l.rows].bottom
    l.maxScroll = 0
    for _, row in ipairs(l.rows) do
        if lastBottom - (row.y - MARGIN) <= VIEW_BOTTOM then
            l.maxScroll = row.y - MARGIN
            break
        end
    end
    return l
end

-- Scroll position that puts a row at the top of the screen.
local function rowTop(row)
    return math.min(layout.maxScroll, row.y - MARGIN)
end

-- Smallest scroll that still shows everything down to bottomY.
local function scrollToShow(bottomY)
    for _, row in ipairs(layout.rows) do
        if bottomY - (row.y - MARGIN) <= VIEW_BOTTOM then return rowTop(row) end
    end
    return layout.maxScroll
end

local function rowVisible(y, bottom)
    return y - scrollY >= MARGIN and bottom - scrollY <= VIEW_BOTTOM
end

-- Moves the view one row down (dir = 1) or up (dir = -1).
local function stepRow(dir)
    if dir > 0 then
        for _, row in ipairs(layout.rows) do
            if row.y - MARGIN > scrollY then scrollY = rowTop(row) return end
        end
    else
        for i = #layout.rows, 1, -1 do
            local row = layout.rows[i]
            if row.y - MARGIN < scrollY then scrollY = rowTop(row) return end
        end
    end
end

-- ─────────────────────────────────────────────
-- NAVIGATION
-- ─────────────────────────────────────────────
local function showPage(id)
    pageId   = id
    layout   = buildLayout(story.pages[id])
    scrollY  = 0
    crankAccum = 0
    selected = nil
    -- Short pages: highlight the first choice right away.
    if layout.maxScroll == 0 and #layout.choices > 0 then selected = 1 end
    state = STATE_PAGE
    if story.pages[id].ending then clearProgress() else saveProgress() end
end

local function startNew(s)
    story   = s or story
    history = {}
    showPage(story.start)
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
    local savedStory, savedPage, savedHistory = loadProgress()
    if savedStory then
        titleItems[#titleItems + 1] = { label = "Keep reading: " .. savedStory.title, action = function()
            story   = savedStory
            history = savedHistory
            showPage(savedPage)
        end }
    end
    for _, s in ipairs(stories) do
        titleItems[#titleItems + 1] = { label = s.title, action = function() startNew(s) end }
    end
    titleIndex = 1
    titleTop   = 1
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
        scrollY = rowTop(c)
    elseif c.y + c.h - scrollY > VIEW_BOTTOM then
        scrollY = scrollToShow(c.y + c.h)
    end
end

local function choiceFullyVisible(i)
    local c = layout.choices[i]
    return c and rowVisible(c.y, c.y + c.h)
end

-- Jumps so the first line not yet fully shown is at the top.
local function nextScreen()
    for _, row in ipairs(layout.rows) do
        if row.bottom - scrollY > VIEW_BOTTOM then scrollY = rowTop(row) return end
    end
end

-- Jumps back a screen, ending on the line just above the current top.
local function prevScreen()
    local prev = nil
    for _, row in ipairs(layout.rows) do
        if row.y - MARGIN < scrollY then prev = row end
    end
    if prev then scrollY = scrollToShow(prev.bottom) end
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
        nextScreen()
    end
end

local function pageUp()
    if selected and selected > 1 then
        selected -= 1
        scrollToSelected()
    else
        if selected and layout.maxScroll > 0 then selected = nil end
        prevScreen()
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
    elseif choice.menu then
        goToTitle()
    else
        goTo(choice.to)
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
    local heading = "Story Paths"
    fontLg:drawText(heading, (SCREEN_W - fontLg:getTextWidth(heading)) / 2, 16)

    if #titleItems == 0 then
        local msg = "No stories found in source/stories/"
        fontMd:drawText(msg, (SCREEN_W - fontMd:getTextWidth(msg)) / 2, 110)
        drawFooter("")
        return
    end

    local boxW, boxH = 320, 34
    local x = (SCREEN_W - boxW) / 2
    local last = math.min(#titleItems, titleTop + TITLE_ROWS - 1)
    for i = titleTop, last do
        local item = titleItems[i]
        local y = 56 + (i - titleTop) * (boxH + 6)
        local label = item.label
        while fontBld:getTextWidth(label) > boxW - 16 and #label > 4 do
            label = label:sub(1, -5) .. "..."
        end
        local tw = fontBld:getTextWidth(label)
        if i == titleIndex then
            gfx.fillRoundRect(x, y, boxW, boxH, 6)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            gfx.drawRoundRect(x, y, boxW, boxH, 6)
        end
        fontBld:drawText(label, x + (boxW - tw) / 2, y + (boxH - fontBld:getHeight()) / 2)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
    end

    -- Arrows when the list is longer than the screen.
    local cx = SCREEN_W - 20
    if titleTop > 1 then gfx.fillTriangle(cx - 6, 64, cx + 6, 64, cx, 57) end
    if last < #titleItems then gfx.fillTriangle(cx - 6, VIEW_H - 14, cx + 6, VIEW_H - 14, cx, VIEW_H - 7) end

    drawFooter("Up/Down: pick a story     A: read")
end

local function drawPage()
    for _, line in ipairs(layout.lines) do
        if rowVisible(line.y, line.y + fontLg:getHeight()) then
            fontLg:drawText(line.text, MARGIN, line.y - scrollY)
        end
    end

    local choiceLineH = fontBld:getHeight() + 2
    for i, c in ipairs(layout.choices) do
        local y = c.y - scrollY
        if rowVisible(c.y, c.y + c.h) then
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
    if state == STATE_PAGE then startNew() end
end)

-- Save when the game is closed or the device goes to sleep.
function pd.gameWillTerminate() saveProgress() end
function pd.deviceWillSleep() saveProgress() end

-- ─────────────────────────────────────────────
-- MAIN LOOP
-- ─────────────────────────────────────────────
loadAllStories()
buildTitleMenu()

function pd.update()
    if state == STATE_TITLE then
        if pd.buttonJustPressed(pd.kButtonUp) then
            titleIndex = math.max(1, titleIndex - 1)
        elseif pd.buttonJustPressed(pd.kButtonDown) then
            titleIndex = math.min(#titleItems, titleIndex + 1)
        elseif pd.buttonJustPressed(pd.kButtonA) and titleItems[titleIndex] then
            titleItems[titleIndex].action()
        end
        if titleIndex < titleTop then titleTop = titleIndex end
        if titleIndex > titleTop + TITLE_ROWS - 1 then titleTop = titleIndex - TITLE_ROWS + 1 end
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

        crankAccum += pd.getCrankChange()
        while crankAccum >= CRANK_STEP do stepRow(1)  crankAccum -= CRANK_STEP end
        while crankAccum <= -CRANK_STEP do stepRow(-1) crankAccum += CRANK_STEP end
    end

    gfx.clear(gfx.kColorWhite)
    if state == STATE_TITLE then drawTitle() else drawPage() end
end
