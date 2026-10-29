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
-- A controller that isn't the local player's must be skipped.
local otherPC = newObject("PlayerController", "OtherPC", { Pawn = newObject("BP_Player_C", "Other") }, {
    IsLocalController = function() return false end,
})
local pc = newObject("PlayerController", "PC", {
    Pawn = pawn,
    PlayerCameraManager = { GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end },
})

local CurrentRT
local canvas = newObject("Canvas", "Canvas", {}, {
    K2_DrawTexture = function(_, tex, pos, size, uvPos, uvSize, color, blend, rot, pivot)
        assert(pos.X and size.X and uvSize.X and color.A and pivot.X, "bad K2_DrawTexture args")
        local d = { Tex = tex._name, Path = tex._path, Blend = blend, Alpha = color.A, Rot = rot, Pos = pos, Size = size, UV = uvSize }
        Draws[#Draws + 1] = d
        if CurrentRT then CurrentRT._draws[#CurrentRT._draws + 1] = d end
    end,
})

local KRL = newObject("KismetRenderingLibrary", "Default__KismetRenderingLibrary", {}, {
    ImportFileAsTexture2D = function(_, ctx, path)
        assert(ctx == pc, "world context must be the player controller")
        local f = assert(io.open(path, "rb"), "missing texture file " .. path)
        f:close()
        Imports[#Imports + 1] = path
        local tex = newObject("Texture2D", path:match("([^/\\]+)%.png$"), {}, {
            Blueprint_GetSizeX = function() return 256 end,
            Blueprint_GetSizeY = function() return 256 end,
        })
        tex._path = path
        return tex
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
        CurrentRT = rt
        rt._draws = {}
    end,
    EndDrawCanvasToRenderTarget = function(_, ctx, ctxOut)
        assert(ctxOut.Begun, "End without Begin context")
        ctxOut.Begun = false
        CurrentRT = nil
    end,
    ExportRenderTarget = function(_, ctx, rt, dir, file)
        assert(rt._class == "TextureRenderTarget2D" and rt.SizeX == 512, "preview should export a 512 px RT")
        Exports = (Exports or 0) + 1
        if not os.getenv("FAKE_GAME") then
            local f = assert(io.open(dir .. "/" .. file, "wb")) f:write("PNG") f:close()
            return
        end
        -- Fake game: turn the recorded draw calls into a real picture for the panel.
        local ops = dir .. "/ops.txt"
        local f = assert(io.open(ops, "w"))
        f:write("size\t" .. rt.SizeX .. "\n")
        for _, d in ipairs(rt._draws or {}) do
            f:write(table.concat({ "draw", d.Path, d.Pos.X, d.Pos.Y, d.Size.X, d.Size.Y, d.UV.X, d.UV.Y, d.Alpha, d.Blend, d.Rot }, "\t") .. "\n")
        end
        f:close()
        os.execute(string.format("python3.12 -I %q %q %q", ROOT .. "/tools/test/render_draws.py", ops, dir .. "/" .. file))
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
    if name == "PlayerController" then return { otherPC, pc } end
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

local tmp = os.getenv("FAKE_GAME") or os.tmpname()
if not os.getenv("FAKE_GAME") then os.remove(tmp) end
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
-- Commands left in the panel file by an earlier session must not be replayed.
os.execute(string.format("mkdir -p %q", tmp .. "/Panel"))
do
    local f = assert(io.open(tmp .. "/Panel/commands.txt", "w"))
    f:write("1\tcamo\tBP_Weapon_AKM_C\t01_Woodland\n2\treset\tBP_Weapon_AKM_C\n")
    f:close()
end
if os.getenv("HOTKEYS") then os.execute(string.format("sed -i %q %q", "s/EnableHotkeys = false/EnableHotkeys = true/", tmp .. "/Scripts/config.lua")) end
if os.getenv("DEBUG") then os.execute(string.format("sed -i %q %q", "s/Debug = false/Debug = true/", tmp .. "/Scripts/config.lua")) end
package.path = tmp .. "/Scripts/?.lua;" .. package.path
local chunk = assert(loadfile(tmp .. "/Scripts/main.lua"))
chunk()

local function lastLog() return logLines[#logLines] or "" end
local failures = 0
local function check(cond, msg)
    if cond then realPrint("ok    " .. msg) else failures = failures + 1 realPrint("FAIL  " .. msg .. "\n      last log: " .. lastLog()) end
end

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local d = f:read("a") f:close() return d
end

-- The panel's side of the protocol.
local CMD = tmp .. "/Panel/commands.txt"
local seq = 2
local applyLoop, panelLoop = Loops[1], Loops[2]
local function send(...)
    seq = seq + 1
    local f = assert(io.open(CMD, "ab"))
    f:write(seq .. "\t" .. table.concat({ ... }, "\t") .. "\n")
    f:close()
    panelLoop()
end
local function state()
    local st = { camos = {}, stickers = {}, weapons = {}, presets = {}, st = {} }
    for line in (readAll(tmp .. "/Panel/state.txt") or ""):gmatch("[^\n]+") do
        local f = {}
        for x in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = x end
        local k = f[1]
        if k == "camo" then st.camos[#st.camos + 1] = f[2]
        elseif k == "sticker" then st.stickers[#st.stickers + 1] = f[2]
        elseif k == "weapon" then st.weapons[#st.weapons + 1] = f[2]
        elseif k == "preset" then st.presets[f[2]] = { Camo = f[3], Scale = tonumber(f[4]), Strength = tonumber(f[5]) }
        elseif k == "st" then st.st[#st.st + 1] = { Cls = f[2], I = tonumber(f[3]), Name = f[4], U = tonumber(f[5]), V = tonumber(f[6]), Tex = tonumber(f[9]) }
        elseif k == "preview" then st.preview = { Cls = f[2], Tex = tonumber(f[3]), Count = tonumber(f[4]), Path = f[5], Counter = tonumber(f[6]), Error = f[7] }
        else st[k] = f[2] end
    end
    return st
end
local function drawsOf(name)
    local list = {}
    for _, d in ipairs(Draws) do if d.Tex == name then list[#list + 1] = d end end
    return list
end
local AKM = "BP_Weapon_AKM_C"
local body = weapon1._body

if os.getenv("FAKE_GAME") then
    -- Fake game for trying the control panel: CamoPanel.pyw in the same folder talks to
    -- this process like it would to the real game. Runs for FAKE_SECONDS (default 600).
    local fakeTex = tmp .. "/fake_receiver.png"
    os.execute(string.format("python3.12 -I %q --fake-texture %q", ROOT .. "/tools/test/render_draws.py", fakeTex))
    texReceiver._path, texStock._path = fakeTex, fakeTex
    rawset(texReceiver, "_name", "T_AKM_Receiver_BC")
    local stop = os.time() + tonumber(os.getenv("FAKE_SECONDS") or "600")
    local ticks = 0
    while os.time() < stop do
        panelLoop()
        ticks = ticks + 1
        if ticks % 12 == 0 then applyLoop() end
        os.execute("sleep 0.25")
    end
    os.exit(0)
end

if os.getenv("HOTKEYS") then
    -- Second run (HOTKEYS=1): the optional keys work on the gun in your hands.
    local function press(k) assert(Binds[k], "no bind " .. k)() end
    press("KEY_F5+CONTROL+ALT")
    check(body._mats[1]._name:find("^CAS_MID_"), "Ctrl+Alt+F5 paints the gun in hands")
    press("KEY_F7+CONTROL+ALT")
    press("KEY_F8+CONTROL+ALT")
    check(body._mats[1] == miReceiver, "Ctrl+Alt+F8 resets it")
    check(Binds["KEY_F5"] == nil, "plain F5 stays free for other mods")
    os.execute(string.format("rm -rf %q", tmp))
    realPrint(failures == 0 and "\nAll checks passed." or ("\n" .. failures .. " check(s) failed."))
    os.exit(failures == 0 and 0 or 1)
end

check(lastLog():find("12 camos, 13 stickers", 1, true), "startup lists the shipped images plus the custom folder's JPG")
check(next(Binds) == nil, "no hotkeys are registered by default (nothing to clash with other mods)")

panelLoop()
local st = state()
check(#st.camos == 12 and #st.stickers == 13 and st.time, "mod writes Panel/state.txt with the image lists and a heartbeat")
check(body._mats[1] == miReceiver, "commands left over from an earlier session are not replayed")

send("hello")
send("scan")
st = state()
check(st.held == AKM, "state reports the weapon in hands")
local listsMagazine = false
for _, w in ipairs(st.weapons) do if w:find("Magazine") then listsMagazine = true end end
check(not listsMagazine and #st.weapons == 1, "weapon list has the AKM and not the magazine")

Draws = {}
send("camo", AKM, "07_Tiger")
check(body._mats[1]._name:find("^CAS_MID_") and body._mats[1].Parent == miReceiver, "camo command puts a MID over the original material")
check(body._mats[1]._params.BaseColor and body._mats[1]._params.BaseColor._class == "TextureRenderTarget2D", "receiver gets the composite render target")
check(body._mats[2]._params.Albedo ~= nil, "stock uses its own 'Albedo' param")
check(weapon2._body._mats[1]._name:find("^CAS_MID_"), "every gun of that type is painted")
check(state().presets[AKM] and state().presets[AKM].Camo == "07_Tiger", "state shows the new preset")
check(#drawsOf("07_Tiger") > 0 and drawsOf("07_Tiger")[1].Blend == 2, "camo drawn translucent over the original")

Draws = {}
send("scale", AKM, "4")
send("strength", AKM, "0.5")
local d = drawsOf("07_Tiger")
check(#d > 0 and d[#d].UV.X == 4 and d[#d].Alpha == 0.5, "scale and strength sliders reach the drawing")

send("preview", AKM, "1")
st = state()
check(st.preview and st.preview.Count == 2 and st.preview.Path ~= "" and readAll(st.preview.Path) == "PNG",
    "preview command exports the weapon texture for the panel")
local counter = st.preview.Counter

Draws = {}
send("add_sticker", AKM, "05_Smiley")
st = state()
check(#st.st == 1 and st.st[1].Name == "05_Smiley", "add_sticker adds a sticker")
check(st.preview.Counter > counter, "the preview refreshes after an edit")
send("set_sticker", AKM, "1", "", "0.8", "0.2", "0.25", "45", "")
st = state()
check(math.abs(st.st[1].U - 0.8) < 1e-6 and math.abs(st.st[1].V - 0.2) < 1e-6, "set_sticker moves the sticker (drag on the preview)")
local sd = drawsOf("05_Smiley")
local onWeapon = false
for _, x in ipairs(sd) do if x.Rot == 45 and math.abs(x.Size.X - 0.25 * 2048) < 1e-6 then onWeapon = true end end
check(onWeapon, "rotation and size reach the weapon texture")
send("set_sticker", AKM, "1", "99_MyLogo", "", "", "", "", "2")
st = state()
check(st.st[1].Name == "99_MyLogo" and st.st[1].Tex == 2, "sticker image and target texture can be changed (got " .. tostring(st.st[1].Name) .. " tex " .. tostring(st.st[1].Tex) .. ")")

local saved = readAll(tmp .. "/presets.lua") or ""
check(saved:find(AKM, 1, true) and saved:find("99_MyLogo", 1, true), "presets.lua is saved")

-- A half-written line is not executed until it is complete.
do
    local f = assert(io.open(CMD, "ab")) f:write((seq + 1) .. "\tcamo\t" .. AKM .. "\t01_Wood") f:close()
    panelLoop()
    check(state().presets[AKM].Camo == "07_Tiger", "a partial command line is ignored")
    f = assert(io.open(CMD, "ab")) f:write("land\n") f:close()
    seq = seq + 1
    panelLoop()
    check(state().presets[AKM].Camo == "01_Woodland", "...and runs once the line is complete")
end

-- Guns that appear later get the preset; game resets are undone.
local weapon3 = newWeapon(AKM, 500)
Actors[#Actors + 1] = weapon3
applyLoop()
check(weapon3._body._mats[1]._name:find("^CAS_MID_"), "auto-apply paints a newly spawned gun")
weapon3._body._mats[1], weapon3._body._mats[2] = miReceiver, miStock
applyLoop()
check(weapon3._body._mats[1]._name:find("^CAS_MID_"), "auto-apply re-paints after the game resets materials")

-- New picture + "Обновить картинки".
os.execute(string.format("cp %q %q", tmp .. "/Camo/12_Gold.png", tmp .. "/Camo/13_MyCamo.png"))
local importsBefore = #Imports
send("reload")
check(#state().camos == 13, "reload picks up a newly added camo")
check(#Imports > importsBefore, "reload re-imports textures from disk")
send("camo", AKM, "13_MyCamo")
check(state().presets[AKM].Camo == "13_MyCamo", "the new camo can be selected")
send("camo", AKM, "no_such_camo")
check(state().presets[AKM].Camo == "", "an unknown camo name means no camo")

send("diagnostics")
local diag = readAll(tmp .. "/Panel/diagnostics.txt") or ""
check(diag:find(AKM, 1, true) and diag:find("Magazine", 1, true) and diag:find("BaseColor", 1, true),
    "diagnostics lists nearby classes and the weapon's material params")

send("remove_sticker", AKM, "1")
check(#state().st == 0, "remove_sticker removes it")
send("reset", AKM)
check(body._mats[1] == miReceiver and body._mats[2] == miStock, "reset restores the original materials")
check(not (readAll(tmp .. "/presets.lua") or ""):find(AKM, 1, true), "reset removes the saved preset")

-- The panel was restarted with a fresh commands file: numbering starts over.
os.remove(CMD)
seq = 0
send("camo", AKM, "02_Desert")
check(state().presets[AKM] and state().presets[AKM].Camo == "02_Desert", "a fresh commands file from a restarted panel works")

local glassUntouched = true
weapon1:K2_GetComponentsByClass():ForEach(function(_, e)
    local c = e:get()
    if c._mats[1] ~= miGlass and c._name ~= "WeaponMesh" then glassUntouched = false end
end)
check(glassUntouched, "glass/lens materials are left alone")

os.execute(string.format("rm -rf %q", tmp))
realPrint(failures == 0 and "\nAll checks passed." or ("\n" .. failures .. " check(s) failed."))
os.exit(failures == 0 and 0 or 1)
