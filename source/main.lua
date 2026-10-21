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
local FOOTER_H    <const> = 26
local VIEW_H      <const> = SCREEN_H - FOOTER_H
local LINE_GAP    <const> = 4
local CHOICE_PAD  <const> = 6
local CHOICE_GAP  <const> = 6
local VIEW_BOTTOM <const> = VIEW_H - 4   -- rows must end above this to be drawn
local CRANK_STEP  <const> = 90          -- crank degrees per screen
local SAVE_KEY    <const> = "progress"
local STORY_DIR   <const> = "stories/"
local MENU_TOP    <const> = 48     -- main menu buttons fill from here...
local MENU_BOTTOM <const> = VIEW_H - 4   -- ...to here, all on screen at once
local MENU_MIN_H  <const> = 26     -- shortest a button row can get before adding a column

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
local setScreen            -- defined below, used by showPage
local scrollY     = 0      -- top of the current screen (from layout.screens)
local screen      = 1      -- which screen of the page is showing
local crankAccum  = 0
local selected    = nil    -- index of highlighted choice, nil = still reading
local titleIndex  = 1
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

    -- Split the page into screens. Each screen starts with the first line the
    -- last one couldn't fit, so nothing shows twice. The choices stay together
    -- on one screen whenever they fit.
    local units = {}
    for _, line in ipairs(l.lines) do
        units[#units + 1] = { y = line.y, bottom = line.y + fontLg:getHeight() }
    end
    if #l.choices > 0 then
        local first, last = l.choices[1], l.choices[#l.choices]
        if last.y + last.h - first.y <= VIEW_BOTTOM - MARGIN then
            units[#units + 1] = { y = first.y, bottom = last.y + last.h }
        else
            for _, c in ipairs(l.choices) do units[#units + 1] = { y = c.y, bottom = c.y + c.h } end
        end
    end

    l.screens = { 0 }
    for _, u in ipairs(units) do
        if u.bottom - l.screens[#l.screens] > VIEW_BOTTOM then
            l.screens[#l.screens + 1] = u.y - MARGIN
        end
    end
    return l
end

local function rowVisible(y, bottom)
    return y - scrollY >= MARGIN and bottom - scrollY <= VIEW_BOTTOM
end

-- ─────────────────────────────────────────────
-- NAVIGATION
-- ─────────────────────────────────────────────
-- Shows screen n of the page. When the choices are on screen, the
-- first one is highlighted so A picks it right away.
setScreen = function(n)
    screen   = math.max(1, math.min(#layout.screens, n))
    scrollY  = layout.screens[screen]
    selected = nil
    local c = layout.choices[1]
    if c and rowVisible(c.y, c.y + c.h) then selected = 1 end
end

local function showPage(id)
    pageId   = id
    layout   = buildLayout(story.pages[id])
    crankAccum = 0
    setScreen(1)
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
end

local function goToTitle()
    saveProgress()
    state = STATE_TITLE
    buildTitleMenu()
end

local function choiceFullyVisible(i)
    local c = layout.choices[i]
    return c and rowVisible(c.y, c.y + c.h)
end

-- ─────────────────────────────────────────────
-- INPUT
-- ─────────────────────────────────────────────
local function pageDown()
    if selected and choiceFullyVisible(selected + 1) then
        selected += 1
    elseif not selected then
        setScreen(screen + 1)
    end
end

local function pageUp()
    if selected and selected > 1 and choiceFullyVisible(selected - 1) then
        selected -= 1
    else
        setScreen(screen - 1)
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
    fontMd:drawText(hint, MARGIN, VIEW_H + (FOOTER_H - fontMd:getHeight()) // 2 + 1)
end

-- Sizes the main menu so every option fits on screen at once: buttons
-- shrink to fit, and a second (or third) column is added if needed.
local function menuLayout()
    local n = #titleItems
    local avail = MENU_BOTTOM - MENU_TOP
    local perCol = math.max(1, avail // MENU_MIN_H)
    local cols = math.max(1, math.ceil(n / perCol))
    local rows = math.ceil(n / cols)
    local rowH = math.min(40, avail // rows)
    local gap = math.max(2, math.min(6, rowH - 24))
    local totalW = (cols == 1) and 320 or (SCREEN_W - MARGIN * 2)
    local boxW = (totalW - (cols - 1) * 8) // cols
    return {
        cols = cols, rows = rows, rowH = rowH, boxW = boxW, boxH = rowH - gap,
        left = (SCREEN_W - totalW) // 2,
        top  = MENU_TOP + (avail - rows * rowH) // 2,
    }
end

local function drawTitle()
    local heading = "Story Paths"
    fontLg:drawText(heading, (SCREEN_W - fontLg:getTextWidth(heading)) / 2, 8)

    if #titleItems == 0 then
        local msg = "No stories found in source/stories/"
        fontMd:drawText(msg, (SCREEN_W - fontMd:getTextWidth(msg)) / 2, 110)
        drawFooter("")
        return
    end

    local m = menuLayout()
    for i, item in ipairs(titleItems) do
        local col = (i - 1) // m.rows
        local row = (i - 1) % m.rows
        local x = m.left + col * (m.boxW + 8)
        local y = m.top + row * m.rowH
        local label = item.label
        while fontBld:getTextWidth(label) > m.boxW - 12 and #label > 4 do
            label = label:sub(1, -5) .. "..."
        end
        local tw = fontBld:getTextWidth(label)
        if i == titleIndex then
            gfx.fillRoundRect(x, y, m.boxW, m.boxH, 6)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            gfx.drawRoundRect(x, y, m.boxW, m.boxH, 6)
        end
        fontBld:drawText(label, x + (m.boxW - tw) / 2, y + (m.boxH - fontBld:getHeight()) / 2)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
    end

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
    if screen < #layout.screens then
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
        local rows = menuLayout().rows
        if pd.buttonJustPressed(pd.kButtonUp) then
            titleIndex = math.max(1, titleIndex - 1)
        elseif pd.buttonJustPressed(pd.kButtonDown) then
            titleIndex = math.min(#titleItems, titleIndex + 1)
        elseif pd.buttonJustPressed(pd.kButtonLeft) and titleIndex > rows then
            titleIndex -= rows
        elseif pd.buttonJustPressed(pd.kButtonRight) and titleIndex + rows <= #titleItems then
            titleIndex += rows
        elseif pd.buttonJustPressed(pd.kButtonA) and titleItems[titleIndex] then
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

        crankAccum += pd.getCrankChange()
        while crankAccum >= CRANK_STEP do setScreen(screen + 1) crankAccum -= CRANK_STEP end
        while crankAccum <= -CRANK_STEP do setScreen(screen - 1) crankAccum += CRANK_STEP end
    end

    gfx.clear(gfx.kColorWhite)
    if state == STATE_TITLE then drawTitle() else drawPage() end
end
