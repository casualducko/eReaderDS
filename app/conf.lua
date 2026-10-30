function love.conf(t)
    t.identity = "ereaderds"
    t.version = "11.5"
    t.console = false
    local scale = tonumber(os.getenv("READER_SCALE")) or 1
    t.window.title = "eReaderDS"
    t.window.width = math.floor(2048 * scale)
    t.window.height = math.floor(768 * scale)
    t.window.borderless = os.getenv("READER_SCALE") == nil
    t.window.resizable = false
    -- Android (GammaOS): a fixed window this wide makes SDL ask for landscape,
    -- and when the app comes back (after sleep, or GammaOS's menu) with
    -- DualStack's tall 1024x1536 surface, SDL waits for a rotation that never
    -- comes and the app freezes. Resizable lets it accept any shape.
    if love._os == "Android" then t.window.resizable = true end
    -- iOS: the screen's own pixels (the frame is scaled up from a canvas, so
    -- without this it comes out soft), and a window that follows the display
    -- as it folds, unfolds or turns.
    t.window.highdpi = love._os == "iOS"
    if love._os == "iOS" then t.window.resizable = true end
    -- A Surface Duo: real pixels, not Android's density-independent units (the
    -- pages are drawn at the screen's own density: see android.lua).
    if love._os == "Android" then
        pcall(function()
            local ffi = require("ffi")
            pcall(ffi.cdef, "int __system_property_get(const char *name, char *value);")
            local buf = ffi.new("char[92]")
            local n = ffi.C.__system_property_get("ro.product.manufacturer", buf)
            if n > 0 and ffi.string(buf, n):lower():find("microsoft", 1, true) then
                t.window.highdpi = true
                t.window.usedpiscale = false
            end
        end)
    end
    -- A Mac: a resizable window with a book's proportions (two pages), at the screen's own pixels.
    if love._os == "OS X" and os.getenv("READER_SCALE") == nil then
        t.window.width, t.window.height = 1440, 960
        t.window.borderless, t.window.resizable, t.window.highdpi = false, true, true
        t.window.minwidth, t.window.minheight = 720, 480
    end
    t.window.vsync = 1
    t.window.display = tonumber(os.getenv("READER_DISPLAY")) or 1
    t.modules.audio = false
    t.modules.sound = false
    t.modules.physics = false
    t.modules.video = false
    t.modules.mouse = true
end
