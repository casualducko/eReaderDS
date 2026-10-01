-- Shrinking a decoded picture on the processor, averaging the pixels each
-- new one covers (so a comic's screentones don't shimmer). Used where the
-- full-size picture is decoded (the page thread, or the app itself), so only
-- the small copy ever reaches the graphics chip: a 1900 x 2700 scan is 20 MB
-- decoded, and copying it to the GPU to shrink it there took several times
-- that, which a 1 GB handheld (GammaOS) can't spare.
local ffi = require("ffi")
local M = {}

-- ImageData id no bigger than mw x mh: a new, smaller ImageData, or id itself
-- when it's small enough already (or isn't 8-bit RGBA, which is left to the
-- caller). The caller releases id.
function M.fit(id, mw, mh)
    local w, h = id:getDimensions()
    local s = math.min(1, mw / w, mh / h)
    if s > 0.9 or id:getFormat() ~= "rgba8" then return id end
    local dw, dh = math.max(1, math.floor(w * s + 0.5)), math.max(1, math.floor(h * s + 0.5))
    local out = love.image.newImageData(dw, dh)
    -- Row by row, each source row in one long straight loop that adds every
    -- pixel into its column (which column, worked out once), then each
    -- finished row of columns averaged. (Not a little loop for each new pixel:
    -- the compiler handles those poorly on ARM, several times slower.)
    local src = ffi.cast("uint8_t *", id:getFFIPointer())
    local dst = ffi.cast("uint8_t *", out:getFFIPointer())
    local col = ffi.new("int32_t[?]", w)            -- source x -> 4 * its column
    local cw = ffi.new("int32_t[?]", dw)            -- how many source columns each has
    for x = 0, w - 1 do
        local dx = math.min(dw - 1, math.floor(x * dw / w))
        col[x] = dx * 4
        cw[dx] = cw[dx] + 1
    end
    local acc = ffi.new("uint32_t[?]", dw * 4)
    local sy, row = 0, w * 4
    for dy = 0, dh - 1 do
        local sy1 = math.max(sy + 1, math.min(h, math.floor((dy + 1) * h / dh)))
        ffi.fill(acc, dw * 16)
        for y = sy, sy1 - 1 do
            local p = src + y * row
            for x = 0, w - 1 do
                local c, i = col[x], x * 4
                acc[c] = acc[c] + p[i]
                acc[c + 1] = acc[c + 1] + p[i + 1]
                acc[c + 2] = acc[c + 2] + p[i + 2]
                acc[c + 3] = acc[c + 3] + p[i + 3]
            end
        end
        local rows, o = sy1 - sy, dy * dw * 4
        for dx = 0, dw - 1 do
            local n, c = rows * cw[dx], dx * 4
            dst[o + c] = acc[c] / n
            dst[o + c + 1] = acc[c + 1] / n
            dst[o + c + 2] = acc[c + 2] / n
            dst[o + c + 3] = acc[c + 3] / n
        end
        sy = sy1
    end
    return out
end

return M
