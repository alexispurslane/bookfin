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

function open_book()
    if document then document:close() end
    document = cre.newDocView(width_px, height_px, 1)
    document:setHeaderInfo(0)
    document:setFontFace("Source Serif 4")
    document:setFontSize(math.floor(18 * density + 0.5))
    document:setDefaultInterlineSpace(165)
    document:setPageMargins(math.floor(18*density), 0, math.floor(18*density), 0)
    document:setBackgroundColor(0xf6efe2)
    document:setIntProperty("font.color.default", 0x39291f)
    document:setIntProperty("crengine.doc.embedded.fonts.enabled", 1)
    document:setIntProperty("crengine.doc.embedded.styles.enabled", 1)
    document:setStyleSheet(data_path .. "/epub.css")
    assert(document:loadDocument(book_path), "KOReader crengine did not load the EPUB")
    document:renderDocument()
    local found = false
    for _, entry in ipairs(document:getToc()) do
        if entry.title == heading then
            document:gotoXPointer(entry.xpointer)
            found = true
            break
        end
    end
    assert(found, "Target heading was not found in KOReader contents: " .. heading)
    font_size = 18
end

function perform(operation)
    if operation == "open" or operation == "reopen" then
        open_book()
    elseif operation == "page_turn" then
        document:gotoPage(document:getCurrentPage()+1)
    elseif operation == "section_jump" then
        local page = document:getCurrentPage()
        local found = false
        for _, entry in ipairs(document:getToc()) do
            if entry.page > page then
                document:gotoXPointer(entry.xpointer)
                found = true
                break
            end
        end
        assert(found, "There is no following contents entry")
    elseif operation == "font_change" then
        font_size = font_size == 18 and 20 or 18
        document:setFontSize(math.floor(font_size*density+0.5))
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
        .. ',"cfi":' .. quote(document:getPageEPubCFI(page)) .. ',"visible_text":' .. quote(text)
        .. ',"text_size_css_px":' .. font_size .. ',"whole_book_paginated":true}'
end
