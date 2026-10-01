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
    local src = ffi.cast("uint8_t *", id:getFFIPointer())
    local dst = ffi.cast("uint8_t *", out:getFFIPointer())
    local xs = {}
    for dx = 0, dw do xs[dx] = math.floor(dx * w / dw) end
    for dy = 0, dh - 1 do
        local sy0 = math.floor(dy * h / dh)
        local sy1 = math.max(sy0 + 1, math.floor((dy + 1) * h / dh))
        local o = dy * dw * 4
        for dx = 0, dw - 1 do
            local sx0, sx1 = xs[dx], math.max(xs[dx] + 1, xs[dx + 1])
            local r, g, b, a = 0, 0, 0, 0
            for sy = sy0, sy1 - 1 do
                local i = (sy * w + sx0) * 4
                for _ = sx0, sx1 - 1 do
                    r, g, b, a = r + src[i], g + src[i + 1], b + src[i + 2], a + src[i + 3]
                    i = i + 4
                end
            end
            local n = (sy1 - sy0) * (sx1 - sx0)
            dst[o], dst[o + 1], dst[o + 2], dst[o + 3] = r / n, g / n, b / n, a / n
            o = o + 4
        end
    end
    return out
end

return M
