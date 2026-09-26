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
    t.window.highdpi = false
    t.window.vsync = 1
    t.window.display = tonumber(os.getenv("READER_DISPLAY")) or 1
    t.modules.audio = false
    t.modules.sound = false
    t.modules.physics = false
    t.modules.video = false
    t.modules.mouse = true
    if love._os == "Android" then
        -- Surface Duo: a normal resizable window that the user spans across
        -- both screens; it goes full screen once spanned (see love.resize).
        t.window.width, t.window.height = 0, 0
        t.window.borderless = false
        t.window.resizable = true
        t.window.fullscreen = false
        t.window.highdpi = true        -- real pixels, not scaled-down "dp" units
        t.window.usedpiscale = false
    end
end
