local ffi = require("ffi")
ffi.cdef[[
typedef struct {
    unsigned int w;
    unsigned int pixel_stride;
    unsigned int h;
    size_t stride;
    uint8_t *data;
    uint8_t config;
} ProbeBuffer;
]]

local function quote(value)
    return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(character)
        return string.format("\\u%04x", string.byte(character))
    end) .. '"'
end

local function normalize(title)
    return title:gsub("%s", ""):gsub("\194\160", "")
end

local function find_heading(title)
    for _, entry in ipairs(document:getToc()) do
        if normalize(entry.title) == normalize(title) then
            return entry
        end
    end
    error("Target heading was not found in KOReader contents: " .. title)
end

local function go_heading(title)
    document:gotoXPointer(find_heading(title).xpointer)
end

function open_book()
    if document then document:close() end
    document = cre.newDocView(width_px, height_px, 1)
    document:setHeaderInfo(0)
    document:setIntProperty("crengine.render.dpi", math.floor(96*density+0.5))
    document:setIntProperty("crengine.render.scale.font.with.dpi", 0)
    for _, direction in ipairs({"zoomin", "zoomout"}) do
        for _, kind in ipairs({"block", "inline"}) do
            document:setIntProperty("crengine.image.scaling." .. direction .. "." .. kind .. ".mode", 0)
            document:setIntProperty("crengine.image.scaling." .. direction .. "." .. kind .. ".scale", 1)
        end
    end
    document:setFontFace("Source Serif 4")
    document:setFontSize(math.floor(18 * density + 0.5))
    document:setDefaultInterlineSpace(100)
    document:setPageMargins(math.floor(15*density), math.floor(20*density), math.floor(15*density), math.floor(20*density))
    document:setStringProperty("font.color.default", "#39291f")
    document:setStringProperty("background.color.default", "#f6efe2")
    document:setIntProperty("crengine.cache.filesize.min", 65536)
    document:setIntProperty("crengine.doc.embedded.fonts.enabled", 1)
    document:setIntProperty("crengine.doc.embedded.styles.enabled", 1)
    document:setStyleSheet(data_path .. "/epub.css", "body { line-height: 1.65 !important; }")
    assert(document:loadDocument(book_path), "KOReader crengine did not load the EPUB")
    document:renderDocument()
    go_heading(heading)
    font_size = 18
end

function perform(operation)
    if operation == "fresh_open" or operation == "cached_reopen" then
        open_book()
    elseif operation == "page_turn" or operation == "chapter_crossing" then
        document:gotoPage(document:getCurrentPage()+1)
    elseif operation == "prepare_crossing" then
        font_size = 18
        document:setFontSize(math.floor(font_size*density+0.5))
        go_heading(next_heading)
        document:gotoPage(document:getCurrentPage()-1)
    elseif operation == "prepare_target" then
        font_size = 18
        document:setFontSize(math.floor(font_size*density+0.5))
        go_heading(heading)
    elseif operation == "prepare_reopen" then
        go_heading(next_heading)
    elseif operation == "font_change" then
        local anchor = document:getXPointer()
        font_size = 20
        document:setFontSize(math.floor(font_size*density+0.5))
        document:gotoXPointer(anchor)
    elseif operation == "paginate" then
        document:renderDocument()
        document:close()
        document = nil
        open_book()
    else
        error("Unknown operation: " .. operation)
    end
    local data = ffi.new("uint8_t[?]", width_px * height_px * 4)
    local buffer = ffi.new("ProbeBuffer", {width_px, width_px, height_px, width_px*4, data, 5*16})
    document:drawCurrentPage(buffer, true, false, true, false)
    pixels = ffi.string(data, width_px*height_px*4)
    local page = document:getCurrentPage()
    local start = document:getPageXPointer(page)
    local finish = document:getPageXPointer(math.min(page+1, document:getPages()))
    local text = document:getTextFromXPointers(start, finish) or ""
    return '{"operation":' .. quote(operation) .. ',"page":' .. page .. ',"pages":' .. document:getPages()
        .. ',"selected_heading_page":' .. find_heading(heading).page .. ',"following_heading_page":' .. find_heading(next_heading).page
        .. ',"cache_file":' .. quote(document:getCacheFilePath() or "")
        .. ',"location":' .. quote(start) .. ',"location_format":"koreader_xpointer","visible_text":' .. quote(text)
        .. ',"text_size_css_px":' .. font_size .. ',"whole_book_paginated":true}'
end
