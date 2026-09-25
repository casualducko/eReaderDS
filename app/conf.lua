function love.conf(t)
    t.identity = "book-reader"
    t.version = "11.5"
    t.console = false
    local scale = tonumber(os.getenv("READER_SCALE")) or 1
    t.window.title = "Book Reader"
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
end
