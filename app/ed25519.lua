-- Ed25519 signature checking (RFC 8032), in plain Lua: the updater uses it to
-- make sure a release was signed by the key built into the app. Checking only,
-- never signing; written after TweetNaCl, whose arithmetic keeps a number in
-- 16 limbs of 16 bits (a Lua number holds the products exactly).
--
--   Ed25519.verify(signature, message, public_key) -> true or false
--
-- All three are strings of bytes (64, any length, 32). Not constant-time, which
-- doesn't matter here: nothing secret goes in. It takes a few hundredths of a
-- second with LuaJIT's compiler on, a second or so without it.
local M = {}

local floor = math.floor

-- The hash is LÖVE's; a test can replace it.
function M.sha512(s) return love.data.hash("sha512", s) end

local function gf(init)
    local r = {}
    for i = 1, 16 do r[i] = init and init[i] or 0 end
    return r
end

local gf0, gf1 = gf(), gf({ 1 })
local D = gf({ 30883, 4953, 19914, 30187, 55467, 16705, 2637, 112, 59544, 30585, 16505, 36039, 65139, 11119, 27886, 20995 })
local D2 = gf({ 61785, 9906, 39828, 60374, 45398, 33411, 5274, 224, 53552, 61171, 33010, 6542, 64743, 22239, 55772, 9222 })
local X = gf({ 54554, 36645, 11616, 51542, 42930, 38181, 51040, 26924, 56412, 64982, 57905, 49316, 21502, 52590, 14035, 8553 })
local Y = gf({ 26200, 26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214 })
local I = gf({ 41136, 18958, 6951, 50414, 58488, 44335, 6150, 12099, 55207, 15867, 153, 11085, 57099, 20417, 9344, 11139 })

-- The order of the base point, L, as 32 bytes (little-endian).
local L = { 237, 211, 245, 92, 26, 99, 18, 88, 214, 156, 247, 162, 222, 249, 222, 20,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16 }

local function set(r, a) for i = 1, 16 do r[i] = a[i] end end

local function car(o)
    local c = 1
    for i = 1, 16 do
        local v = o[i] + c + 65535
        c = floor(v / 65536)
        o[i] = v - c * 65536
    end
    o[1] = o[1] + c - 1 + 37 * (c - 1)
end

local function add_f(o, a, b) for i = 1, 16 do o[i] = a[i] + b[i] end end
local function sub_f(o, a, b) for i = 1, 16 do o[i] = a[i] - b[i] end end

local t31 = {}
local function mul(o, a, b)
    for i = 1, 31 do t31[i] = 0 end
    for i = 1, 16 do
        local ai = a[i]
        for j = 1, 16 do t31[i + j - 1] = t31[i + j - 1] + ai * b[j] end
    end
    for i = 1, 15 do t31[i] = t31[i] + 38 * t31[i + 16] end
    for i = 1, 16 do o[i] = t31[i] end
    car(o); car(o)
end
local function sqr(o, a) mul(o, a, a) end

local function inv(o, i)
    local c = gf(); set(c, i)
    for a = 253, 0, -1 do
        sqr(c, c)
        if a ~= 2 and a ~= 4 then mul(c, c, i) end
    end
    set(o, c)
end

local function pow2523(o, i)
    local c = gf(); set(c, i)
    for a = 250, 0, -1 do
        sqr(c, c)
        if a ~= 1 then mul(c, c, i) end
    end
    set(o, c)
end

-- The 32 bytes of a number, fully reduced (below 2^255 - 19).
local P = { 0xffed, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff,
    0xffff, 0xffff, 0x7fff }
local function pack(n)
    local t = gf(); set(t, n)
    car(t); car(t); car(t)
    for _ = 1, 2 do
        local m, borrow = {}, 0
        for i = 1, 16 do
            local v = t[i] - P[i] - borrow
            if v < 0 then v = v + 65536; borrow = 1 else borrow = 0 end
            m[i] = v
        end
        if borrow == 0 then t = m end
    end
    local out = {}
    for i = 1, 16 do
        out[2 * i - 1] = t[i] % 256
        out[2 * i] = floor(t[i] / 256)
    end
    return out
end

local function unpack_f(o, bytes)        -- bytes: array of 32 numbers
    for i = 1, 16 do o[i] = bytes[2 * i - 1] + bytes[2 * i] * 256 end
    o[16] = o[16] % 32768                -- (bit 255 is the sign of x, not part of y)
end

local function neq(a, b)
    local pa, pb = pack(a), pack(b)
    for i = 1, 32 do if pa[i] ~= pb[i] then return true end end
    return false
end

local function par(a) return pack(a)[1] % 2 end

-- Points are { x, y, z, t } (extended coordinates).
local function point() return { gf(), gf(), gf(), gf() } end

local ta, tb, tc, td, te, tf, tg, th, tt = gf(), gf(), gf(), gf(), gf(), gf(), gf(), gf(), gf()
local function padd(p, q)
    sub_f(ta, p[2], p[1]); sub_f(tt, q[2], q[1]); mul(ta, ta, tt)
    add_f(tb, p[1], p[2]); add_f(tt, q[1], q[2]); mul(tb, tb, tt)
    mul(tc, p[4], q[4]); mul(tc, tc, D2)
    mul(td, p[3], q[3]); add_f(td, td, td)
    sub_f(te, tb, ta); sub_f(tf, td, tc); add_f(tg, td, tc); add_f(th, tb, ta)
    mul(p[1], te, tf); mul(p[2], th, tg); mul(p[3], tg, tf); mul(p[4], te, th)
end

local function cswap(p, q)
    for i = 1, 4 do p[i], q[i] = q[i], p[i] end
end

-- p = s * q, s: array of bytes (little-endian), `bits` of them used.
local function scalarmult(p, q, s, bits)
    set(p[1], gf0); set(p[2], gf1); set(p[3], gf1); set(p[4], gf0)
    for i = bits - 1, 0, -1 do
        local b = floor(s[floor(i / 8) + 1] / 2 ^ (i % 8)) % 2
        if b == 1 then cswap(p, q) end
        padd(q, p)
        padd(p, p)
        if b == 1 then cswap(p, q) end
    end
end

local function scalarbase(p, s)
    local q = point()
    set(q[1], X); set(q[2], Y); set(q[3], gf1); mul(q[4], X, Y)
    scalarmult(p, q, s, 256)
end

local function packpoint(p)
    local zi, tx, ty = gf(), gf(), gf()
    inv(zi, p[3])
    mul(tx, p[1], zi); mul(ty, p[2], zi)
    local r = pack(ty)
    r[32] = r[32] + par(tx) * 128
    return r
end

-- The point with the encoded y, negated (so adding it subtracts the key).
local function unpackneg(r, pk)
    local t, chk, num, den, den2, den4, den6 = gf(), gf(), gf(), gf(), gf(), gf(), gf()
    set(r[3], gf1)
    unpack_f(r[2], pk)
    sqr(num, r[2])
    mul(den, num, D)
    sub_f(num, num, r[3])
    add_f(den, r[3], den)
    sqr(den2, den); sqr(den4, den2); mul(den6, den4, den2)
    mul(t, den6, num); mul(t, t, den)
    pow2523(t, t)
    mul(t, t, num); mul(t, t, den); mul(t, t, den)
    mul(r[1], t, den)
    sqr(chk, r[1]); mul(chk, chk, den)
    if neq(chk, num) then mul(r[1], r[1], I) end
    sqr(chk, r[1]); mul(chk, chk, den)
    if neq(chk, num) then return false end
    if par(r[1]) == floor(pk[32] / 128) then sub_f(r[1], gf0, r[1]) end
    mul(r[4], r[1], r[2])
    return true
end

local function bytes_of(s) return { s:byte(1, #s) } end

function M.verify(signature, message, public_key)
    if type(signature) ~= "string" or #signature ~= 64 or type(public_key) ~= "string" or #public_key ~= 32 then
        return false
    end
    local sig, pk = bytes_of(signature), bytes_of(public_key)
    -- S must be below L (no second signature for the same message).
    local s = {}
    for i = 1, 32 do s[i] = sig[32 + i] end
    for i = 32, 1, -1 do
        if s[i] < L[i] then break end
        if s[i] > L[i] or i == 1 then return false end
    end
    local q = point()
    if not unpackneg(q, pk) then return false end
    -- h = SHA-512(R || A || message), used as it is (64 bytes): the key has the
    -- order of the base point, so a longer number gives the same product.
    local r_bytes = signature:sub(1, 32)
    local h = bytes_of(M.sha512(r_bytes .. public_key .. message))
    local p = point()
    scalarmult(p, q, h, 512)
    local b = point()
    scalarbase(b, s)
    padd(p, b)
    local t = packpoint(p)
    for i = 1, 32 do if t[i] ~= sig[i] then return false end end
    return true
end

return M
