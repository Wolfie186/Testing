-- Offline smoke test: runs the mod against a fake UE4SS API in plain Lua 5.4.
-- Usage (from the repo root): lua5.4 tools/test/run_mock.lua
-- It checks the mod's own logic (cycling, presets, compositing calls); it can't
-- prove anything about the real game's classes or materials.

local ROOT = arg[0]:match("^(.*)/tools/test/") or "."
local MOD_DIR = ROOT .. "/CamoAndStickers"

------------------------------------------------------------------ fake objects

local objectId = 0
local Object = {}
Object.__index = function(self, k)
    local v = rawget(Object, k)
    if v ~= nil then return v end
    local fields = rawget(self, "_fields")
    return fields and fields[k]
end

local function newObject(className, name, fields, methods)
    objectId = objectId + 1
    local o = setmetatable({ _class = className, _name = name or (className .. "_" .. objectId), _fields = fields or {} }, Object)
    for k, fn in pairs(methods or {}) do rawset(o, k, fn) end
    return o
end

function Object:IsValid() return not rawget(self, "_dead") end
function Object:GetFName() local n = self._name return { ToString = function() return n end } end
function Object:GetFullName() return self._class .. " /Game/" .. self._name end
function Object:GetClass() local c = self._class return { GetFName = function() return { ToString = function() return c end } end } end
function Object:IsA(cls) return cls == MaterialInstanceClass and (self._class == "MaterialInstanceConstant" or self._class == "MaterialInstanceDynamic") end
function Object:GetWorld() return newObject("World", "World", { CanvasForDrawMaterialToRenderTarget = nil }) end

MaterialInstanceClass = newObject("Class", "MaterialInstance")

local function fakeArray(list)
    return {
        ForEach = function(_, fn)
            for i, v in ipairs(list) do fn(i, { get = function() return v end }) end
        end,
    }
end

local function texParam(name, tex)
    return { ParameterInfo = { Name = { ToString = function() return name end } }, ParameterValue = tex }
end

------------------------------------------------------------------ fake world

local Draws, Imports, RTs = {}, {}, 0

local texReceiver = newObject("Texture2D", "T_AKM_Receiver_BC")
local texStock = newObject("Texture2D", "T_AKM_Stock_BC")
local texNormal = newObject("Texture2D", "T_AKM_N")

local baseMat = newObject("Material", "M_Weapon_Master")
local miReceiver = newObject("MaterialInstanceConstant", "MI_AKM_Receiver", {
    Parent = baseMat,
    TextureParameterValues = fakeArray({ texParam("Normal", texNormal), texParam("BaseColor", texReceiver) }),
})
local miStock = newObject("MaterialInstanceConstant", "MI_AKM_Stock", {
    Parent = baseMat,
    TextureParameterValues = fakeArray({ texParam("Albedo", texStock) }),
})
local miGlass = newObject("MaterialInstanceConstant", "MI_Glass", {
    Parent = baseMat,
    TextureParameterValues = fakeArray({ texParam("Tint", texNormal) }),
})

local function newMeshComponent(name, materials)
    local comp = newObject("SkeletalMeshComponent", name)
    comp._mats = materials
    rawset(comp, "GetNumMaterials", function(self) return #self._mats end)
    rawset(comp, "GetMaterial", function(self, i) return self._mats[i + 1] end)
    rawset(comp, "SetMaterial", function(self, i, m) self._mats[i + 1] = m end)
    rawset(comp, "CreateDynamicMaterialInstance", function(self, i, parent, fname)
        local mid = newObject("MaterialInstanceDynamic", fname:ToString(), { Parent = parent })
        mid._params = {}
        rawset(mid, "SetTextureParameterValue", function(m, pname, tex) m._params[pname:ToString()] = tex end)
        self._mats[i + 1] = mid
        return mid
    end)
    return comp
end

local function newWeapon(cls, x)
    local body = newMeshComponent("WeaponMesh", { miReceiver, miStock })
    local scope = newMeshComponent("ScopeLens", { miGlass })
    local glassSlot = newMeshComponent("Body2", { miGlass })
    local actor = newObject(cls, nil, {}, {
        K2_GetActorLocation = function() return { X = x, Y = 0, Z = 0 } end,
        K2_GetComponentsByClass = function() return fakeArray({ body, scope, glassSlot }) end,
    })
    actor._body = body
    return actor
end

local weapon1 = newWeapon("BP_Weapon_AKM_C", 40)
local weapon2 = newWeapon("BP_Weapon_AKM_C", 900)
local magazine = newObject("BP_Magazine_AKM_C", nil, {}, {
    K2_GetActorLocation = function() return { X = 10, Y = 0, Z = 0 } end,
})
local Actors = { weapon1, weapon2, magazine }

local pawn = newObject("BP_Player_C", "Player")
local pc = newObject("PlayerController", "PC", {
    Pawn = pawn,
    PlayerCameraManager = { GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end },
})

local canvas = newObject("Canvas", "Canvas", {}, {
    K2_DrawTexture = function(_, tex, pos, size, uvPos, uvSize, color, blend, rot, pivot)
        assert(pos.X and size.X and uvSize.X and color.A and pivot.X, "bad K2_DrawTexture args")
        Draws[#Draws + 1] = { Tex = tex._name, Blend = blend, Alpha = color.A, Rot = rot, Pos = pos, Size = size, UV = uvSize }
    end,
})

local KRL = newObject("KismetRenderingLibrary", "Default__KismetRenderingLibrary", {}, {
    ImportFileAsTexture2D = function(_, ctx, path)
        assert(ctx == pc, "world context must be the player controller")
        local f = assert(io.open(path, "rb"), "missing texture file " .. path)
        f:close()
        Imports[#Imports + 1] = path
        return newObject("Texture2D", path:match("([^/\\]+)%.png$"), {}, {
            Blueprint_GetSizeX = function() return 256 end,
            Blueprint_GetSizeY = function() return 256 end,
        })
    end,
    CreateRenderTarget2D = function(_, ctx, w, h, fmt, clear, mips, uav)
        assert(uav ~= nil, "expects the UE5 signature in this mock")
        RTs = RTs + 1
        return newObject("TextureRenderTarget2D", nil, { SizeX = w, SizeY = h })
    end,
    BeginDrawCanvasToRenderTarget = function(_, ctx, rt, canvasOut, sizeOut, ctxOut)
        assert(type(canvasOut) == "table" and type(ctxOut) == "table")
        canvasOut.Canvas = canvas -- UE4SS writes object out params to a key named after the param
        ctxOut.Begun = true
    end,
    EndDrawCanvasToRenderTarget = function(_, ctx, ctxOut)
        assert(ctxOut.Begun, "End without Begin context")
        ctxOut.Begun = false
    end,
})

------------------------------------------------------------------ fake UE4SS globals

local Binds, Loops = {}, {}

Key = setmetatable({}, { __index = function(_, k) return "KEY_" .. k end })
ModifierKey = { SHIFT = "SHIFT", CONTROL = "CONTROL", ALT = "ALT" }

function RegisterKeyBind(key, a, b)
    local mods, fn = {}, a
    if b then mods, fn = a, b end
    Binds[key .. (#mods > 0 and ("+" .. table.concat(mods, "+")) or "")] = fn
end

function ExecuteInGameThread(fn) fn() end
function LoopAsync(_, fn) Loops[#Loops + 1] = fn end
function FName(s) return { ToString = function() return s end } end
function IterateGameDirectories() error("not in a game") end

function StaticFindObject(path)
    if path:find("KismetRenderingLibrary") then return KRL end
    if path:find("MaterialInstance") then return MaterialInstanceClass end
    return newObject("Class", path)
end

function FindAllOf(name)
    if name == "PlayerController" then return { pc } end
    if name == "Actor" then return Actors end
    local out = {}
    for _, a in ipairs(Actors) do
        if a._class == name and a:IsValid() then out[#out + 1] = a end
    end
    return #out > 0 and out or nil
end

local logLines = {}
local realPrint = print
print = function(s) logLines[#logLines + 1] = s if os.getenv("VERBOSE") then io.write(s) end end

------------------------------------------------------------------ load the mod from a temp copy

local tmp = os.tmpname()
os.remove(tmp)
os.execute(string.format("mkdir -p %q && cp -r %q/. %q", tmp, MOD_DIR, tmp))
os.remove(tmp .. "/presets.lua")
-- A user sticker folder outside the mod, holding a JPG.
local customDir = tmp .. "/MyStickers"
os.execute(string.format("mkdir -p %q && cp %q %q", customDir, tmp .. "/Stickers/04_Skull.png", customDir .. "/99_MyLogo.jpg"))
do
    local cfgPath = tmp .. "/Scripts/config.lua"
    local f = assert(io.open(cfgPath)) local cfg = f:read("a") f:close()
    cfg = cfg:gsub("CustomStickerFolders = {}", string.format("CustomStickerFolders = { %q }", customDir .. "/"))
    f = assert(io.open(cfgPath, "w")) f:write(cfg) f:close()
end
if os.getenv("DEBUG") then os.execute(string.format("sed -i %q %q", "s/Debug = false/Debug = true/", tmp .. "/Scripts/config.lua")) end
package.path = tmp .. "/Scripts/?.lua;" .. package.path
local chunk = assert(loadfile(tmp .. "/Scripts/main.lua"))
chunk()

local function press(k) assert(Binds[k], "no bind " .. k)() end
local function lastLog() return logLines[#logLines] or "" end
local failures = 0
local function check(cond, msg)
    if cond then realPrint("ok    " .. msg) else failures = failures + 1 realPrint("FAIL  " .. msg .. "\n      last log: " .. lastLog()) end
end

check(lastLog():find("12 camos, 13 stickers", 1, true), "startup lists the shipped images plus the custom folder's JPG")

local body = weapon1._body
press("KEY_F5")
check(body._mats[1]._name:find("^CAS_MID_"), "F5 puts a MID on the receiver slot")
check(body._mats[2]._name:find("^CAS_MID_"), "F5 puts a MID on the stock slot")
check(body._mats[1].Parent == miReceiver, "MID parent is the original material")
check(body._mats[1]._params.BaseColor and body._mats[1]._params.BaseColor._class == "TextureRenderTarget2D",
    "receiver BaseColor param gets the composite render target")
check(body._mats[2]._params.Albedo ~= nil, "stock uses its own 'Albedo' param")
check(weapon2._body._mats[1]._name:find("^CAS_MID_"), "same weapon type far away is painted too")
check(Draws[1] and Draws[1].Blend == 0 and Draws[1].Tex == "T_AKM_Receiver_BC", "composite starts with the original texture, opaque")
check(Draws[2] and Draws[2].Blend == 2 and Draws[2].Tex == "01_Woodland", "then the camo, translucent")

local rtsAfterFirst = RTs
press("KEY_F5")
check(body._mats[1]._params.BaseColor ~= nil and lastLog():find("02_Desert"), "F5 again cycles to the next camo")
check(RTs == rtsAfterFirst + 2, "one new render target per distinct base texture, shared across same-type guns")

Draws = {}
press("KEY_F7")
check(lastLog():find("added sticker #1"), "F7 adds a sticker")
local stickerDraws = 0
for _, d in ipairs(Draws) do if d.Tex == "01_Radiation" then stickerDraws = stickerDraws + 1 end end
check(stickerDraws == 1, "sticker drawn once into the composite both guns share (got " .. stickerDraws .. ")")

press("KEY_F6")
check(lastLog():find("02_Biohazard"), "F6 changes the active sticker image")
press("KEY_NUM_SIX") press("KEY_ADD") press("KEY_NUM_NINE")
press("KEY_F8+SHIFT")
check(lastLog():find("texture 2 of 2"), "Shift+F8 moves the sticker to the stock texture")

local f = io.open(tmp .. "/presets.lua")
local saved = f and f:read("a") or ""
if f then f:close() end
check(saved:find('BP_Weapon_AKM_C') and saved:find('02_Biohazard') and saved:find('Tex = 2'), "preset is saved to presets.lua")
local env = {}
check(load(saved, "presets", "t", env)().BP_Weapon_AKM_C.Stickers[1].U > 0.3, "saved preset reloads with the nudged position")

-- A freshly spawned gun of the same type gets the preset from the auto-apply loop.
local weapon3 = newWeapon("BP_Weapon_AKM_C", 500)
Actors[#Actors + 1] = weapon3
Loops[1]()
check(weapon3._body._mats[1]._name:find("^CAS_MID_"), "auto-apply paints a newly spawned gun")

-- The game swapping the material back is noticed and fixed.
weapon3._body._mats[1] = miReceiver
weapon3._body._mats[2] = miStock
Loops[1]()
check(weapon3._body._mats[1]._name:find("^CAS_MID_"), "auto-apply re-paints after the game resets materials")

press("KEY_F5+SHIFT")
check(lastLog():find("01_Woodland"), "Shift+F5 goes back")

press("KEY_INS")
check(table.concat(logLines):find("BP_Weapon_AKM_C") and table.concat(logLines):find("BP_Magazine_AKM_C"), "INS dumps nearby classes")

-- Drop a new camo into the folder while the game runs, then Shift+INS.
os.execute(string.format("cp %q %q", tmp .. "/Camo/12_Gold.png", tmp .. "/Camo/13_MyCamo.png"))
local importsBefore = #Imports
press("KEY_INS+SHIFT")
check(lastLog():find("13 camos, 13 stickers", 1, true), "Shift+INS picks up a newly added camo")
check(#Imports > importsBefore, "Shift+INS re-imports textures from disk (edited files refresh)")
check(body._mats[1]._name:find("^CAS_MID_"), "weapon is repainted after reload")
for _ = 1, 12 do press("KEY_F5") end
check(lastLog():find("13_MyCamo", 1, true), "the new camo can be selected")
press("KEY_F6+SHIFT") press("KEY_F6+SHIFT") -- 02 -> 01 -> wraps to the last one
check(lastLog():find("99_MyLogo", 1, true), "the custom-folder sticker can be selected")

press("KEY_DEL")
check(body._mats[1] == miReceiver and body._mats[2] == miStock, "DEL restores the original materials")
f = io.open(tmp .. "/presets.lua")
saved = f:read("a") f:close()
check(not saved:find("BP_Weapon_AKM_C"), "DEL removes the saved preset")

-- Glass instance (params listed, none is a base color) is never touched.
local scope = weapon1:K2_GetComponentsByClass()
local glassUntouched = true
scope:ForEach(function(_, e) local c = e:get() if c._mats[1] ~= miGlass and c._name ~= "WeaponMesh" then glassUntouched = false end end)
check(glassUntouched, "glass/lens materials are left alone")

os.execute(string.format("rm -rf %q", tmp))
realPrint(failures == 0 and "\nAll checks passed." or ("\n" .. failures .. " check(s) failed."))
os.exit(failures == 0 and 0 or 1)
