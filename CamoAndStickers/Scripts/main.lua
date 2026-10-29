-- Camo & Stickers for Into the Radius 2 (UE4SS Lua mod)
--
-- Paints weapons with camo patterns and sticks stickers on them at runtime:
--   * camo/sticker PNGs are loaded from the mod folder (drop your own in, no repacking),
--   * the weapon's base color texture is composited with camo + stickers into a render
--     target that replaces it through a dynamic material instance,
--   * choices are saved per weapon type in presets.lua and re-applied to every gun of
--     that type, including ones that spawn later,
--   * everything is driven from the CamoPanel desktop window (no hotkeys by default).

local MOD = "[CamoAndStickers] "
local Config = require("config")

local function log(fmt, ...)
    print(MOD .. string.format(fmt, ...) .. "\n")
end

local function dlog(fmt, ...)
    if Config.Debug then log(fmt, ...) end
end

------------------------------------------------------------------------ paths

local function detectModDir()
    local src = debug and debug.getinfo and debug.getinfo(1, "S").source or ""
    src = src:gsub("^@", "")
    local scripts = src:match("^(.*)[/\\][^/\\]+$")
    local dir = scripts and scripts:match("^(.*)[/\\][^/\\]+$")
    return dir or "Mods\\CamoAndStickers"
end

local MOD_DIR = detectModDir()
local SEP = MOD_DIR:find("\\", 1, true) and "\\" or "/"
local CAMO_DIR = MOD_DIR .. SEP .. "Camo"
local STICKER_DIR = MOD_DIR .. SEP .. "Stickers"
local PRESETS_FILE = MOD_DIR .. SEP .. "presets.lua"

-- Textures that ship with the mod; used when the folder can't be listed.
local BUILTIN_CAMOS = {
    "01_Woodland", "02_Desert", "03_Snow", "04_Urban", "05_DigitalForest", "06_DigitalDesert",
    "07_Tiger", "08_Flora", "09_HunterRed", "10_Anomaly", "11_Carbon", "12_Gold",
}
local BUILTIN_STICKERS = {
    "01_Radiation", "02_Biohazard", "03_RedStar", "04_Skull", "05_Smiley", "06_Stalker",
    "07_Pechorsk", "08_NoFear", "09_Tally", "10_Target", "11_HazardStripes", "12_GreenStar",
}

local function fileExists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

local IMAGE_EXTENSIONS = { png = true, jpg = true, jpeg = true, bmp = true, tga = true }

local function imageName(file)
    local name, ext = file:match("^(.+)%.([^.]+)$")
    if name and IMAGE_EXTENSIONS[ext:lower()] then return name end
    return nil
end

local function trimSlashes(path)
    return (path:gsub("[/\\]+$", ""))
end

-- File names in a folder via UE4SS's game directory table (no console window, but only
-- works for folders inside the game install). Returns nil if the folder isn't reachable.
local function listViaGameDirectories(gameDirs, dir)
    local files
    pcall(function()
        local win64 = gameDirs.Game.Binaries.Win64
        local base = trimSlashes(win64.__absolute_path):lower()
        local target = trimSlashes(dir):lower()
        if target:sub(1, #base) ~= base then return end
        local node = win64
        for part in target:sub(#base + 1):gmatch("[^/\\]+") do
            local nextNode
            for key, child in pairs(node) do
                if type(key) == "string" and key:lower() == part then nextNode = child break end
            end
            if not nextNode then return end
            node = nextNode
        end
        files = {}
        for _, file in pairs(node.__files) do files[#files + 1] = file.__name end
    end)
    return files
end

-- File names in any folder through the shell (dir on Windows, ls elsewhere).
local function listViaShell(dir)
    -- chcp 65001 makes dir print UTF-8, which is what the engine expects for file names.
    local cmd = SEP == "\\" and string.format('chcp 65001 >nul & dir /b /a-d "%s" 2>nul', dir)
        or string.format('ls -1 "%s" 2>/dev/null', dir)
    local ok, pipe = pcall(io.popen, cmd)
    if not ok or not pipe then return nil end
    local files = {}
    for line in pipe:lines() do files[#files + 1] = line:gsub("\r$", "") end
    pipe:close()
    return files
end

-- Builds { { Name, Path }, ... } from the mod's own folder plus the user's extra folders.
-- A file in a later folder replaces a same-named one from an earlier folder, so a custom
-- "01_Woodland.png" overrides the built-in one.
local function scanImages(dirs, builtin, gameDirs)
    local byName, names = {}, {}
    for _, dir in ipairs(dirs) do
        dir = trimSlashes(SEP == "\\" and dir:gsub("/", "\\") or dir)
        local files = (gameDirs and listViaGameDirectories(gameDirs, dir)) or listViaShell(dir)
        if not files or #files == 0 then
            -- Last resort: probe the names that ship with the mod.
            files = {}
            for _, name in ipairs(builtin) do
                if fileExists(dir .. SEP .. name .. ".png") then files[#files + 1] = name .. ".png" end
            end
        end
        for _, file in ipairs(files) do
            local name = imageName(file)
            if name then
                if not byName[name] then names[#names + 1] = name end
                byName[name] = dir .. SEP .. file
            end
        end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    local list = {}
    for _, name in ipairs(names) do list[#list + 1] = { Name = name, Path = byName[name] } end
    return list
end

local Camos, Stickers = {}, {}

local function scanAllImages()
    local okDirs, gameDirs = pcall(IterateGameDirectories)
    if not okDirs or type(gameDirs) ~= "table" then gameDirs = nil end
    local camoDirs, stickerDirs = { CAMO_DIR }, { STICKER_DIR }
    for _, d in ipairs(Config.CustomCamoFolders or {}) do camoDirs[#camoDirs + 1] = d end
    for _, d in ipairs(Config.CustomStickerFolders or {}) do stickerDirs[#stickerDirs + 1] = d end
    Camos = scanImages(camoDirs, BUILTIN_CAMOS, gameDirs)
    Stickers = scanImages(stickerDirs, BUILTIN_STICKERS, gameDirs)
end

scanAllImages()

local function indexByName(list, name)
    for i, item in ipairs(list) do
        if item.Name == name then return i end
    end
    return nil
end

------------------------------------------------------------------------ presets

-- Presets[WeaponClassName] = {
--     Camo = "01_Woodland" | nil, Scale = 2.0, Strength = 0.85, Active = 1,
--     Stickers = { { Name = "01_Radiation", U = 0.3, V = 0.3, Size = 0.12, Rot = 0, Tex = 1 }, ... },
-- }
local Presets = {}

local function serialize(value, indent)
    indent = indent or ""
    local t = type(value)
    if t == "number" then
        return (math.type(value) == "integer") and tostring(value) or string.format("%.4f", value)
    elseif t == "string" then
        return string.format("%q", value)
    elseif t == "boolean" then
        return tostring(value)
    elseif t == "table" then
        local inner = indent .. "    "
        local parts, keys = {}, {}
        for k in pairs(value) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        for _, k in ipairs(keys) do
            local key = type(k) == "number" and "" or
                (k:match("^[%a_][%w_]*$") and (k .. " = ") or ("[" .. string.format("%q", k) .. "] = "))
            parts[#parts + 1] = inner .. key .. serialize(value[k], inner) .. ","
        end
        if #parts == 0 then return "{}" end
        return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
    end
    return "nil"
end

local function savePresets()
    local f, err = io.open(PRESETS_FILE, "w")
    if not f then
        log("Can't save presets to %s: %s", PRESETS_FILE, tostring(err))
        return
    end
    f:write("-- Saved by Camo & Stickers. Safe to edit or delete.\nreturn ", serialize(Presets), "\n")
    f:close()
end

local function loadPresets()
    Presets = {}
    if not fileExists(PRESETS_FILE) then return end
    local chunk, err = loadfile(PRESETS_FILE, "t", {})
    if not chunk then
        log("presets.lua is broken, ignoring it: %s", tostring(err))
        return
    end
    local ok, data = pcall(chunk)
    if ok and type(data) == "table" then
        Presets = data
    else
        log("presets.lua is broken, ignoring it: %s", tostring(data))
    end
end

local function presetIsEmpty(p)
    return p == nil or (p.Camo == nil and (p.Stickers == nil or #p.Stickers == 0))
end

local function presetSignature(p)
    if presetIsEmpty(p) then return "" end
    local parts = {
        tostring(p.Camo), string.format("%.3f", p.Scale or 1), string.format("%.3f", p.Strength or 1), Config.Mode,
    }
    for _, s in ipairs(p.Stickers or {}) do
        parts[#parts + 1] = string.format("%s@%d:%.3f,%.3f,%.3f,%.1f", s.Name, s.Tex or 1, s.U, s.V, s.Size, s.Rot or 0)
    end
    return table.concat(parts, "|")
end

------------------------------------------------------------------------ engine helpers

local Classes = {}

local function class(path)
    local c = Classes[path]
    if c == nil or not c:IsValid() then
        c = StaticFindObject(path)
        Classes[path] = c
    end
    return c
end

local function valid(obj)
    local t = type(obj)
    return (t == "userdata" or t == "table") and obj:IsValid()
end

local CachedPC

local function isLocalController(pc)
    local ok, isLocal = pcall(function() return pc:IsLocalController() end)
    return not ok or isLocal -- if the call isn't available, assume single player
end

-- The local player's controller (skips any controller that isn't locally controlled).
local function getPC()
    if valid(CachedPC) and valid(CachedPC.Pawn) then return CachedPC end
    CachedPC = nil
    local pcs = FindAllOf("PlayerController") or {}
    for _, pc in ipairs(pcs) do
        if valid(pc) and isLocalController(pc) and valid(pc.Pawn) then
            CachedPC = pc
            return pc
        end
    end
    for _, pc in ipairs(pcs) do
        if valid(pc) and isLocalController(pc) then return pc end
    end
    return nil
end

local function renderingLib()
    return StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
end

local function contains(haystack, needles)
    haystack = haystack:lower()
    for _, n in ipairs(needles) do
        if haystack:find(n:lower(), 1, true) then return true end
    end
    return false
end

local function shortClassName(obj)
    return obj:GetClass():GetFName():ToString()
end

local function objName(obj)
    return obj:GetFName():ToString()
end

local WeaponClassCache = {}

local function isWeaponClass(name)
    local cached = WeaponClassCache[name]
    if cached == nil then
        cached = contains(name, Config.WeaponClassPatterns) and not contains(name, Config.WeaponClassExcludePatterns)
        WeaponClassCache[name] = cached
    end
    return cached
end

-- Converts a TArray (or plain table) of objects into a Lua list.
local function toList(arr)
    local list = {}
    if arr == nil then return list end
    if type(arr) == "table" and arr.ForEach == nil then
        for _, v in ipairs(arr) do list[#list + 1] = v end
    else
        arr:ForEach(function(_, elem) list[#list + 1] = elem:get() end)
    end
    return list
end

local function cameraLocation(pc)
    local ok, loc = pcall(function() return pc.PlayerCameraManager:GetCameraLocation() end)
    if ok and loc then return loc end
    if valid(pc.Pawn) then return pc.Pawn:K2_GetActorLocation() end
    return nil
end

local function dist(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- All actors sorted by distance to the camera: { { Actor, Class, Dist }, ... }
local function nearbyActors(pc, maxDist, weaponsOnly)
    local cam = cameraLocation(pc)
    if not cam then return {} end
    local result = {}
    for _, actor in ipairs(FindAllOf("Actor") or {}) do
        if valid(actor) then
            local ok, cls = pcall(shortClassName, actor)
            if ok and (not weaponsOnly or isWeaponClass(cls)) then
                local okLoc, loc = pcall(function() return actor:K2_GetActorLocation() end)
                if okLoc and loc then
                    local d = dist(cam, loc)
                    if d <= maxDist then
                        result[#result + 1] = { Actor = actor, Class = cls, Dist = d }
                    end
                end
            end
        end
    end
    table.sort(result, function(a, b) return a.Dist < b.Dist end)
    return result
end

local function meshComponents(actor)
    local meshClass = class("/Script/Engine.MeshComponent")
    local list = {}
    local ok, arr = pcall(function() return actor:K2_GetComponentsByClass(meshClass) end)
    if not ok then
        dlog("K2_GetComponentsByClass failed: %s", tostring(arr))
        return list
    end
    for _, comp in ipairs(toList(arr)) do
        if valid(comp) and not contains(objName(comp), Config.ComponentExcludePatterns) then
            list[#list + 1] = comp
        end
    end
    return list
end

------------------------------------------------------------------------ materials

local MID_PREFIX = "CAS_MID_"
local MidCounter = 0

local function isOurMid(mat)
    return valid(mat) and objName(mat):sub(1, #MID_PREFIX) == MID_PREFIX
end

-- The material the game assigned, ignoring a MID we put on top of it.
local function baseMaterialOf(mat)
    if isOurMid(mat) then
        local parent = mat.Parent
        if valid(parent) then return parent end
    end
    return mat
end

-- Collects { name = texture } for texture parameters along a material instance chain
-- (child values win over parents).
local function textureParams(mat)
    local params, order = {}, {}
    local miClass = class("/Script/Engine.MaterialInstance")
    local depth = 0
    while valid(mat) and depth < 16 do
        local okIsA, isMI = pcall(function() return mat:IsA(miClass) end)
        if not (okIsA and isMI) then break end
        pcall(function()
            mat.TextureParameterValues:ForEach(function(_, elem)
                local v = elem:get()
                local name = v.ParameterInfo.Name:ToString()
                if params[name] == nil then
                    params[name] = v.ParameterValue
                    order[#order + 1] = name
                end
            end)
        end)
        mat = mat.Parent
        depth = depth + 1
    end
    return params, order
end

-- Returns the base color parameter name and its current texture (both may be nil).
local function findBaseColorParam(mat)
    local params, order = textureParams(mat)
    for _, wanted in ipairs(Config.BaseColorParamNames) do
        for _, name in ipairs(order) do
            if name:lower() == wanted:lower() and valid(params[name]) then return name, params[name] end
        end
    end
    for _, name in ipairs(order) do
        if contains(name, Config.BaseColorParamHints) and not contains(name, Config.BaseColorParamBlacklist)
            and valid(params[name]) then
            return name, params[name]
        end
    end
    return nil, nil
end

------------------------------------------------------------------------ textures

-- Cached objects are re-checked by full name, because a garbage-collected object's slot
-- can be reused by an unrelated object.
local TextureCache = {}   -- path -> { Obj, FullName }
local CompositeCache = {} -- key  -> { Obj, FullName }

local function cacheGet(cache, key)
    local entry = cache[key]
    if entry and valid(entry.Obj) and entry.Obj:GetFullName() == entry.FullName then return entry.Obj end
    cache[key] = nil
    return nil
end

local function cachePut(cache, key, obj)
    local n = 0
    for _ in pairs(cache) do n = n + 1 end
    if n > 128 then
        -- Stale entries (old presets, despawned guns) only cost a lookup; drop them now and then.
        for k in pairs(cache) do cache[k] = nil end
    end
    cache[key] = { Obj = obj, FullName = obj:GetFullName() }
end

local function loadTexture(path)
    local tex = cacheGet(TextureCache, path)
    if tex then return tex end
    local pc = getPC()
    if not pc then return nil end
    local ok, result = pcall(function() return renderingLib():ImportFileAsTexture2D(pc, path) end)
    if ok and valid(result) then
        cachePut(TextureCache, path, result)
        return result
    end
    log("Failed to load texture %s (%s)", path, tostring(result))
    return nil
end

local function imagePath(kind, name)
    if not name then return nil end
    local list = kind == "camo" and Camos or Stickers
    local i = indexByName(list, name)
    return i and list[i].Path or nil
end

local function camoTexture(name)
    local path = imagePath("camo", name)
    return path and loadTexture(path) or nil
end

local function stickerTexture(name)
    local path = imagePath("sticker", name)
    return path and loadTexture(path) or nil
end

local CompositeSupported = true

local RTF_RGBA8_SRGB = 3
local BLEND_OPAQUE, BLEND_TRANSLUCENT = 0, 2

local function createRenderTarget(pc, size)
    local lib = renderingLib()
    local black = { R = 0, G = 0, B = 0, A = 1 }
    -- The parameter list differs between engine versions (bSupportUAVs was added in UE5).
    local ok, rt = pcall(function() return lib:CreateRenderTarget2D(pc, size, size, RTF_RGBA8_SRGB, black, true, false) end)
    if not (ok and valid(rt)) then
        ok, rt = pcall(function() return lib:CreateRenderTarget2D(pc, size, size, RTF_RGBA8_SRGB, black, true) end)
    end
    if ok and valid(rt) then return rt end
    log("CreateRenderTarget2D failed: %s", tostring(rt))
    return nil
end

local function vec2(x, y) return { X = x, Y = y } end
local WHITE = { R = 1, G = 1, B = 1, A = 1 }

-- Draws base texture + camo + stickers into a render target. Returns the RT or nil.
local function buildComposite(key, baseTex, preset, texIndex, size)
    local rt = cacheGet(CompositeCache, key)
    if rt then return rt end

    local pc = getPC()
    if not pc then return nil end
    size = size or Config.RenderTargetSize
    rt = createRenderTarget(pc, size)
    if not rt then
        CompositeSupported = false
        return nil
    end

    local camo = camoTexture(preset.Camo)
    local stickers = {}
    for _, s in ipairs(preset.Stickers or {}) do
        if (s.Tex or 1) == texIndex then
            local tex = stickerTexture(s.Name)
            if tex then stickers[#stickers + 1] = { Tex = tex, Def = s } end
        end
    end

    local lib = renderingLib()
    local canvasOut, sizeOut, ctxOut = {}, {}, {}
    local okBegin, errBegin = pcall(function()
        lib:BeginDrawCanvasToRenderTarget(pc, rt, canvasOut, sizeOut, ctxOut)
    end)
    if not okBegin then
        log("BeginDrawCanvasToRenderTarget failed, falling back to 'replace' mode: %s", tostring(errBegin))
        CompositeSupported = false
        return nil
    end

    local okDraw, errDraw = pcall(function()
        local canvas = canvasOut.Canvas
        if not valid(canvas) then canvas = pc:GetWorld().CanvasForDrawMaterialToRenderTarget end
        assert(valid(canvas), "no canvas")
        local full = vec2(size, size)
        if valid(baseTex) then
            canvas:K2_DrawTexture(baseTex, vec2(0, 0), full, vec2(0, 0), vec2(1, 1), WHITE, BLEND_OPAQUE, 0, vec2(0.5, 0.5))
        end
        if camo then
            local strength = valid(baseTex) and (preset.Strength or Config.DefaultCamoStrength) or 1
            local scale = preset.Scale or Config.DefaultCamoScale
            canvas:K2_DrawTexture(camo, vec2(0, 0), full, vec2(0, 0), vec2(scale, scale),
                { R = 1, G = 1, B = 1, A = strength }, BLEND_TRANSLUCENT, 0, vec2(0.5, 0.5))
        end
        for _, s in ipairs(stickers) do
            local d = s.Def
            local w = d.Size * size
            local h = w
            local okSize, sx, sy = pcall(function() return s.Tex:Blueprint_GetSizeX(), s.Tex:Blueprint_GetSizeY() end)
            if okSize and sx and sy and sx > 0 then h = w * sy / sx end
            canvas:K2_DrawTexture(s.Tex, vec2(d.U * size - w / 2, d.V * size - h / 2), vec2(w, h),
                vec2(0, 0), vec2(1, 1), WHITE, BLEND_TRANSLUCENT, d.Rot or 0, vec2(0.5, 0.5))
        end
    end)

    pcall(function() lib:EndDrawCanvasToRenderTarget(pc, ctxOut) end)

    if not okDraw then
        log("Drawing the composite failed, falling back to 'replace' mode: %s", tostring(errDraw))
        CompositeSupported = false
        return nil
    end
    cachePut(CompositeCache, key, rt)
    return rt
end

------------------------------------------------------------------------ applying

local Applied = {} -- actor full name -> signature

local function setTextureParam(mid, paramName, tex)
    if paramName then
        mid:SetTextureParameterValue(FName(paramName), tex)
    else
        -- Plain UMaterial: its parameters can't be listed, so try the usual names.
        for _, name in ipairs(Config.BaseColorParamNames) do
            mid:SetTextureParameterValue(FName(name), tex)
        end
    end
end

local function newMidName()
    MidCounter = MidCounter + 1
    return string.format("%s%d_%d", MID_PREFIX, os.time() % 100000, MidCounter)
end

-- Every material slot of the weapon: { Comp, Index, Current, Base }
local function materialSlots(actor)
    local slots = {}
    for _, comp in ipairs(meshComponents(actor)) do
        local okNum, num = pcall(function() return comp:GetNumMaterials() end)
        for i = 0, (okNum and num or 0) - 1 do
            local cur = comp:GetMaterial(i)
            if valid(cur) then
                slots[#slots + 1] = { Comp = comp, Index = i, Current = cur, Base = baseMaterialOf(cur) }
            end
        end
    end
    return slots
end

-- Distinct base color textures of a weapon, in a stable order. Stickers target one of them.
local function baseTextures(slots)
    local list, seen = {}, {}
    for _, slot in ipairs(slots) do
        local param, tex = findBaseColorParam(slot.Base)
        local _, order = textureParams(slot.Base)
        slot.Param, slot.BaseTex, slot.Listed = param, tex, #order > 0
        if valid(tex) then
            local key = tex:GetFullName()
            if not seen[key] then
                seen[key] = #list + 1
                list[#list + 1] = tex
            end
            slot.TexIndex = seen[key]
        end
    end
    return list
end

local function resetActor(actor)
    for _, slot in ipairs(materialSlots(actor)) do
        if isOurMid(slot.Current) then slot.Comp:SetMaterial(slot.Index, slot.Base) end
    end
end

local function applyToActor(actor, preset)
    local okName, fullName = pcall(function() return actor:GetFullName() end)
    if not okName then return end
    if presetIsEmpty(preset) then
        resetActor(actor)
        Applied[fullName] = nil
        return
    end

    local sig = presetSignature(preset)
    local slots = materialSlots(actor)
    local texCount = #baseTextures(slots)
    local camo = camoTexture(preset.Camo)
    local touched = 0

    for _, slot in ipairs(slots) do
        local tex
        -- An instance whose params we can list but none is a base color (glass, emissive
        -- dots…) is left alone. Plain materials get the blind name guess in setTextureParam.
        local paintable = slot.Param ~= nil or not slot.Listed
        local hasStickers = false
        for _, s in ipairs(preset.Stickers or {}) do
            if (s.Tex or 1) == (slot.TexIndex or 1) then hasStickers = true break end
        end
        if paintable and (camo or hasStickers) then
            if Config.Mode == "composite" and CompositeSupported then
                local baseKey = valid(slot.BaseTex) and slot.BaseTex:GetFullName() or "none"
                tex = buildComposite(baseKey .. "#" .. sig, slot.BaseTex, preset, slot.TexIndex or 1)
            end
            if not tex then tex = camo end
        end

        if tex then
            local mid = slot.Current
            if not isOurMid(mid) then
                mid = slot.Comp:CreateDynamicMaterialInstance(slot.Index, slot.Base, FName(newMidName()))
            end
            if valid(mid) then
                setTextureParam(mid, slot.Param, tex)
                touched = touched + 1
            end
        elseif isOurMid(slot.Current) then
            -- Nothing to show on this slot any more: give it back the game's material.
            slot.Comp:SetMaterial(slot.Index, slot.Base)
        end
    end
    Applied[fullName] = sig
    dlog("Applied to %s (%d slots, %d textures)", fullName, touched, texCount)
end

-- Is our MID still on the actor? (The game may have swapped materials since.)
local function stillApplied(actor)
    for _, slot in ipairs(materialSlots(actor)) do
        if isOurMid(slot.Current) then return true end
    end
    return false
end


local function applyClass(cls)
    local preset = Presets[cls]
    for _, actor in ipairs(FindAllOf(cls) or {}) do
        if valid(actor) then
            local ok, err = pcall(applyToActor, actor, preset)
            if not ok then log("Failed to apply to %s: %s", cls, tostring(err)) end
        end
    end
end

-- Classes painted on the previous pass, so guns whose preset was removed get reset once.
local PaintedClasses = {}

local function autoApply()
    local classes = {}
    for cls in pairs(Presets) do classes[cls] = true end
    for cls in pairs(PaintedClasses) do classes[cls] = true end
    PaintedClasses = {}
    for cls in pairs(Presets) do PaintedClasses[cls] = true end

    for cls in pairs(classes) do
        local preset = Presets[cls]
        local sig = presetIsEmpty(preset) and "" or presetSignature(preset)
        for _, actor in ipairs(FindAllOf(cls) or {}) do
            if valid(actor) then
                local ok, err = pcall(function()
                    local fullName = actor:GetFullName()
                    if sig == "" then
                        if Applied[fullName] ~= nil or stillApplied(actor) then
                            resetActor(actor)
                            Applied[fullName] = nil
                        end
                    elseif Applied[fullName] ~= sig or not stillApplied(actor) then
                        applyToActor(actor, preset)
                    end
                end)
                if not ok then dlog("Auto-apply failed for %s: %s", cls, tostring(err)) end
            end
        end
    end
end

------------------------------------------------------------------------ files

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("a")
    f:close()
    return data
end

local function writeFile(path, data)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

-- Write-then-rename, so a reader never sees a half-written file.
local function writeFileAtomic(path, data)
    if not writeFile(path .. ".tmp", data) then return false end
    os.remove(path)
    return os.rename(path .. ".tmp", path) ~= nil
end

local function ensureDir(dir)
    local probe = dir .. SEP .. ".cas_probe"
    if writeFile(probe, "") then
        os.remove(probe)
        return true
    end
    -- The release ships the folder, so this only runs if someone deleted it.
    os.execute(SEP == "\\" and string.format('mkdir "%s" 2>nul', dir) or string.format('mkdir -p "%s"', dir))
    if writeFile(probe, "") then
        os.remove(probe)
        return true
    end
    return false
end

------------------------------------------------------------------------ editing

-- Every change goes through these, whether it comes from the control panel or a hotkey.
-- They take the weapon class explicitly, so the panel can edit any weapon type, not only
-- the one in your hands.

local Status = "Ready"
local StateDirty = true
local PreviewInfo -- { Class, Tex, Count, File, Counter } of the last exported preview
local exportPreview -- defined with the panel code below

local function setStatus(fmt, ...)
    Status = string.format(fmt, ...)
    StateDirty = true
    log("%s", Status)
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function presetFor(cls)
    local p = Presets[cls]
    if not p then
        p = { Scale = Config.DefaultCamoScale, Strength = Config.DefaultCamoStrength, Stickers = {} }
        Presets[cls] = p
    end
    p.Stickers = p.Stickers or {}
    return p
end

local function commit(cls)
    if presetIsEmpty(Presets[cls]) then Presets[cls] = nil end
    applyClass(cls)
    savePresets()
    StateDirty = true
    if PreviewInfo and PreviewInfo.Class == cls then exportPreview(cls, PreviewInfo.Tex) end
end

local Edit = {}

function Edit.camo(cls, name)
    local p = presetFor(cls)
    p.Camo = (name and name ~= "" and indexByName(Camos, name)) and name or nil
    commit(cls)
    setStatus("%s: camo = %s", cls, p.Camo or "none")
end

function Edit.scale(cls, v)
    if not v then return end
    presetFor(cls).Scale = clamp(v, 0.25, 16)
    commit(cls)
end

function Edit.strength(cls, v)
    if not v then return end
    presetFor(cls).Strength = clamp(v, 0, 1)
    commit(cls)
end

function Edit.addSticker(cls, name)
    if #Stickers == 0 then return setStatus("No sticker images in %s", STICKER_DIR) end
    if not indexByName(Stickers, name) then name = Stickers[1].Name end
    local p = presetFor(cls)
    local slot = Config.StickerSlots[(#p.Stickers % #Config.StickerSlots) + 1]
    p.Stickers[#p.Stickers + 1] = { Name = name, U = slot.U, V = slot.V, Size = Config.DefaultStickerSize, Rot = 0, Tex = 1 }
    commit(cls)
    setStatus("%s: added sticker #%d (%s)", cls, #p.Stickers, name)
    return #p.Stickers
end

-- fields: any of Name, U, V, Size, Rot, Tex
function Edit.setSticker(cls, index, fields)
    local p = Presets[cls]
    local s = p and p.Stickers and p.Stickers[index]
    if not s then return end
    if fields.Name and indexByName(Stickers, fields.Name) then s.Name = fields.Name end
    if fields.U then s.U = clamp(fields.U, 0, 1) end
    if fields.V then s.V = clamp(fields.V, 0, 1) end
    if fields.Size then s.Size = clamp(fields.Size, 0.02, 1) end
    if fields.Rot then s.Rot = fields.Rot % 360 end
    if fields.Tex then s.Tex = math.max(1, math.floor(fields.Tex)) end
    commit(cls)
end

function Edit.removeSticker(cls, index)
    local p = Presets[cls]
    if not (p and p.Stickers and p.Stickers[index]) then return end
    table.remove(p.Stickers, index)
    commit(cls)
    setStatus("%s: sticker removed, %d left", cls, #p.Stickers)
end

function Edit.reset(cls)
    Presets[cls] = nil
    commit(cls)
    setStatus("%s: back to factory finish", cls)
end

-- Re-reads the image folders and presets, and reloads every texture from disk, so new or
-- edited pictures show up without restarting the game.
function Edit.reload()
    scanAllImages()
    for k in pairs(TextureCache) do TextureCache[k] = nil end
    for k in pairs(CompositeCache) do CompositeCache[k] = nil end
    CompositeSupported = true
    loadPresets()
    Applied = {}
    autoApply()
    local n = 0
    for _ in pairs(Presets) do n = n + 1 end
    setStatus("Reloaded: %d camos, %d stickers, %d weapon presets", #Camos, #Stickers, n)
end

------------------------------------------------------------------------ control panel
--
-- CamoPanel (a desktop window) and the mod talk through two files in Panel\:
--   commands.txt  appended by the panel: "<seq>\t<command>\t<args...>" per line,
--   state.txt     rewritten by the mod: lists, presets, weapon in hands, status, preview.
-- No keys involved, so nothing can clash with other mods.

local PANEL_DIR = MOD_DIR .. SEP .. "Panel"
local COMMANDS_FILE = PANEL_DIR .. SEP .. "commands.txt"
local STATE_FILE = PANEL_DIR .. SEP .. "state.txt"
local DIAG_FILE = PANEL_DIR .. SEP .. "diagnostics.txt"
local VERSION = "2.0.0"

local LastSeq          -- highest command already handled; nil until the first read
local LastCommandsSize = -1
local PanelSeenAt = -math.huge
local HeldClass        -- weapon class in your hands (closest to the camera)
local SeenClasses = {} -- weapon classes seen around you, listed in the panel
local LastStateBody, LastStateWrite = nil, -math.huge
local PreviewCounter = 0

local function panelActive()
    return os.time() - PanelSeenAt < 10
end

local function scanWeapons()
    local pc = getPC()
    if not pc then return end
    local near = nearbyActors(pc, Config.PanelWeaponRadius, true)
    local held = near[1] and near[1].Dist <= Config.TargetMaxDistance and near[1].Class or nil
    if held ~= HeldClass then
        HeldClass = held
        StateDirty = true
    end
    for _, e in ipairs(near) do
        if not SeenClasses[e.Class] then
            SeenClasses[e.Class] = true
            StateDirty = true
        end
    end
end

-- Draws the selected weapon texture (with its camo and stickers) at preview size and saves
-- it as a PNG for the panel, where stickers are placed by dragging on it.
exportPreview = function(cls, texIndex)
    local actor
    for _, a in ipairs(FindAllOf(cls) or {}) do
        if valid(a) then actor = a break end
    end
    if not actor then
        PreviewInfo = { Class = cls, Tex = texIndex or 1, Count = 0, Error = "no weapon of this type is loaded nearby" }
        StateDirty = true
        return
    end
    local texs = baseTextures(materialSlots(actor))
    texIndex = clamp(math.floor(texIndex or 1), 1, math.max(1, #texs))
    local preset = Presets[cls] or { Stickers = {} }
    local baseTex = texs[texIndex]
    PreviewInfo = { Class = cls, Tex = texIndex, Count = #texs }
    StateDirty = true

    if Config.Mode ~= "composite" or not CompositeSupported then
        PreviewInfo.Error = "preview needs composite mode"
        return
    end
    local key = "preview#" .. (valid(baseTex) and baseTex:GetFullName() or "none") .. "#" .. texIndex .. "#"
        .. presetSignature(preset)
    local rt = buildComposite(key, baseTex, preset, texIndex, Config.PreviewSize)
    if not rt then
        PreviewInfo.Error = "couldn't draw the preview"
        return
    end
    -- Alternate between two files so the panel never reads one that is being written.
    PreviewCounter = PreviewCounter + 1
    local file = string.format("preview_%d.png", PreviewCounter % 2)
    os.remove(PANEL_DIR .. SEP .. file)
    local ok, err = pcall(function() renderingLib():ExportRenderTarget(getPC(), rt, PANEL_DIR, file) end)
    if ok and fileExists(PANEL_DIR .. SEP .. file) then
        PreviewInfo.File, PreviewInfo.Counter = file, PreviewCounter
    else
        PreviewInfo.Error = "the game couldn't save the preview image"
        dlog("ExportRenderTarget failed: %s", tostring(err))
    end
end

local function num(v) return string.format("%.4f", v) end

local function stateBody()
    local lines = { "CAS-STATE\t2", "version\t" .. VERSION, "status\t" .. Status, "held\t" .. (HeldClass or "") }
    lines[#lines + 1] = "mode\t" .. ((Config.Mode == "composite" and CompositeSupported) and "composite" or "replace")
    for _, c in ipairs(Camos) do lines[#lines + 1] = "camo\t" .. c.Name .. "\t" .. c.Path end
    for _, s in ipairs(Stickers) do lines[#lines + 1] = "sticker\t" .. s.Name .. "\t" .. s.Path end

    local classes = {}
    for cls in pairs(SeenClasses) do classes[cls] = true end
    for cls in pairs(Presets) do classes[cls] = true end
    if HeldClass then classes[HeldClass] = true end
    local sorted = {}
    for cls in pairs(classes) do sorted[#sorted + 1] = cls end
    table.sort(sorted)
    for _, cls in ipairs(sorted) do
        lines[#lines + 1] = "weapon\t" .. cls
        local p = Presets[cls]
        if p then
            lines[#lines + 1] = table.concat({ "preset", cls, p.Camo or "",
                num(p.Scale or Config.DefaultCamoScale), num(p.Strength or Config.DefaultCamoStrength) }, "\t")
            for i, s in ipairs(p.Stickers or {}) do
                lines[#lines + 1] = table.concat({ "st", cls, tostring(i), s.Name, num(s.U), num(s.V), num(s.Size),
                    num(s.Rot or 0), tostring(s.Tex or 1) }, "\t")
            end
        end
    end
    if PreviewInfo then
        lines[#lines + 1] = table.concat({ "preview", PreviewInfo.Class, tostring(PreviewInfo.Tex),
            tostring(PreviewInfo.Count), PreviewInfo.File and (PANEL_DIR .. SEP .. PreviewInfo.File) or "",
            tostring(PreviewInfo.Counter or 0), PreviewInfo.Error or "" }, "\t")
    end
    lines[#lines + 1] = "ack\t" .. tostring(LastSeq or 0)
    return table.concat(lines, "\n") .. "\n"
end

local function writeState(force)
    local body = stateBody()
    local now = os.time()
    -- The time line doubles as a heartbeat: the panel shows "connected" while it moves.
    local heartbeatDue = now - LastStateWrite >= (panelActive() and 2 or 10)
    if not force and body == LastStateBody and not heartbeatDue then return end
    if writeFileAtomic(STATE_FILE, "time\t" .. now .. "\n" .. body) then
        LastStateBody, LastStateWrite = body, now
        StateDirty = false
    end
end

local function diagnostics()
    local out = {}
    local function add(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
    local pc = getPC()
    if not pc then
        add("No player controller yet: load a save first.")
        return out
    end
    add("Actors within 2 m (W = recognised as a weapon):")
    local near = nearbyActors(pc, 200, false)
    for i = 1, math.min(20, #near) do
        local e = near[i]
        add("  %s %6.1f cm  %s", isWeaponClass(e.Class) and "W" or " ", e.Dist, e.Class)
    end
    local hit = nearbyActors(pc, Config.TargetMaxDistance, true)[1]
    if not hit then
        add("")
        add("No weapon within %d cm. If your gun is in the list above without W, add part of", Config.TargetMaxDistance)
        add("its class name to WeaponClassPatterns in Scripts\\config.lua.")
        return out
    end
    add("")
    add("Weapon in hands: %s", hit.Actor:GetFullName())
    local slots = materialSlots(hit.Actor)
    local texs = baseTextures(slots)
    for _, slot in ipairs(slots) do
        local _, order = textureParams(slot.Base)
        add("  %s [%d] %s", objName(slot.Comp), slot.Index, slot.Base:GetFullName())
        add("      texture params: %s", #order > 0 and table.concat(order, ", ") or "(none listed, plain material)")
        add("      base color: %s  (texture #%s)", tostring(slot.Param), tostring(slot.TexIndex))
    end
    add("  %d distinct base color textures; mode: %s", #texs,
        (Config.Mode == "composite" and CompositeSupported) and "composite" or "replace")
    return out
end

function Edit.diagnostics()
    local lines = diagnostics()
    for _, l in ipairs(lines) do log("%s", l) end
    writeFileAtomic(DIAG_FILE, table.concat(lines, "\n") .. "\n")
    setStatus("Diagnostics written (%d lines)", #lines)
end

local function split(line)
    local f = {}
    for field in (line:gsub("\r$", "") .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = field end
    return f
end

local Commands = {
    hello = function() StateDirty = true end,
    ping = function() end,
    camo = function(f) Edit.camo(f[3], f[4]) end,
    scale = function(f) Edit.scale(f[3], tonumber(f[4])) end,
    strength = function(f) Edit.strength(f[3], tonumber(f[4])) end,
    add_sticker = function(f) Edit.addSticker(f[3], f[4]) end,
    set_sticker = function(f)
        Edit.setSticker(f[3], tonumber(f[4]) or 0, {
            Name = f[5] ~= "" and f[5] or nil, U = tonumber(f[6]), V = tonumber(f[7]),
            Size = tonumber(f[8]), Rot = tonumber(f[9]), Tex = tonumber(f[10]),
        })
    end,
    remove_sticker = function(f) Edit.removeSticker(f[3], tonumber(f[4]) or 0) end,
    reset = function(f) Edit.reset(f[3]) end,
    reload = function() Edit.reload() end,
    preview = function(f) exportPreview(f[3], tonumber(f[4]) or 1) end,
    diagnostics = function() Edit.diagnostics() end,
    scan = function() scanWeapons() end,
}

local function pollCommands()
    local f = io.open(COMMANDS_FILE, "rb")
    if not f then
        if LastSeq == nil then LastSeq = 0 end
        return
    end
    local size = f:seek("end")
    if size == LastCommandsSize then
        f:close()
        return
    end
    f:seek("set")
    local text = f:read("a")
    f:close()
    LastCommandsSize = size

    local entries, maxSeq = {}, 0
    for line in text:gmatch("([^\n]*)\n") do -- only complete lines
        local fields = split(line)
        local seq = math.tointeger(tonumber(fields[1]))
        if seq then
            entries[#entries + 1] = { Seq = seq, Fields = fields }
            maxSeq = math.max(maxSeq, seq)
        end
    end
    if LastSeq == nil then
        -- Commands left over from an earlier game session are not replayed.
        LastSeq = maxSeq
        return
    end
    if maxSeq < LastSeq then LastSeq = 0 end -- the panel started a fresh file
    for _, e in ipairs(entries) do
        if e.Seq > LastSeq then
            LastSeq = e.Seq
            PanelSeenAt = os.time()
            local handler = Commands[e.Fields[2]]
            if handler then
                local ok, err = pcall(handler, e.Fields)
                if not ok then setStatus("Command '%s' failed: %s", tostring(e.Fields[2]), tostring(err)) end
            else
                dlog("Unknown panel command '%s'", tostring(e.Fields[2]))
            end
            StateDirty = true
        end
    end
end

local PanelTicks = 0

local function panelTick()
    pollCommands()
    PanelTicks = PanelTicks + 1
    if panelActive() and PanelTicks * Config.PanelPollMs >= 1000 then
        PanelTicks = 0
        scanWeapons()
    end
    writeState(StateDirty)
end

------------------------------------------------------------------------ optional hotkeys

local function cycle(list, current, step)
    -- Index 0 means "none".
    local n = #list
    local i = (current or 0) + step
    if i > n then i = 0 elseif i < 0 then i = n end
    return i
end

local function stepThrough(steps, current)
    for i, v in ipairs(steps) do
        if math.abs(v - current) < 1e-3 then return steps[i % #steps + 1] end
    end
    return steps[1]
end

local function withHeld(fn)
    local pc = getPC()
    local hit = pc and nearbyActors(pc, Config.TargetMaxDistance, true)[1]
    if not hit then return setStatus("No weapon within %d cm", Config.TargetMaxDistance) end
    fn(hit.Class, presetFor(hit.Class))
end

local Actions = {
    NextCamo = function() withHeld(function(cls, p)
        local i = cycle(Camos, indexByName(Camos, p.Camo), 1)
        Edit.camo(cls, i > 0 and Camos[i].Name or "")
    end) end,
    PrevCamo = function() withHeld(function(cls, p)
        local i = cycle(Camos, indexByName(Camos, p.Camo), -1)
        Edit.camo(cls, i > 0 and Camos[i].Name or "")
    end) end,
    NextSticker = function() withHeld(function(cls, p)
        local s = p.Stickers[#p.Stickers]
        if not s then return Edit.addSticker(cls) end
        local i = (indexByName(Stickers, s.Name) or 0) % #Stickers + 1
        Edit.setSticker(cls, #p.Stickers, { Name = Stickers[i].Name })
    end) end,
    AddSticker = function() withHeld(function(cls) Edit.addSticker(cls) end) end,
    RemoveSticker = function() withHeld(function(cls, p) Edit.removeSticker(cls, #p.Stickers) end) end,
    ResetWeapon = function() withHeld(function(cls) Edit.reset(cls) end) end,
    CycleCamoScale = function() withHeld(function(cls, p)
        Edit.scale(cls, stepThrough(Config.CamoScaleSteps, p.Scale or Config.DefaultCamoScale))
    end) end,
    CycleStrength = function() withHeld(function(cls, p)
        Edit.strength(cls, stepThrough(Config.CamoStrengthSteps, p.Strength or Config.DefaultCamoStrength))
    end) end,
}

local function runSafe(name, fn)
    ExecuteInGameThread(function()
        local ok, err = pcall(fn)
        if not ok then log("%s failed: %s", name, tostring(err)) end
    end)
end

if Config.EnableHotkeys then
    for action, bind in pairs(Config.Keys or {}) do
        local fn = Actions[action]
        local key = bind.Key and Key[bind.Key]
        if not fn then
            log("Unknown action '%s' in config.Keys", action)
        elseif not key then
            log("Unknown key '%s' for %s", tostring(bind.Key), action)
        else
            local mods = {}
            for _, m in ipairs(bind.Modifiers or {}) do
                if ModifierKey[m] then mods[#mods + 1] = ModifierKey[m] else log("Unknown modifier '%s' for %s", m, action) end
            end
            local callback = function() runSafe(action, fn) end
            if #mods > 0 then RegisterKeyBind(key, mods, callback) else RegisterKeyBind(key, callback) end
        end
    end
end

------------------------------------------------------------------------ startup

loadPresets()
if not ensureDir(PANEL_DIR) then log("Can't use the panel folder %s", PANEL_DIR) end

LoopAsync(Config.AutoApplyIntervalMs, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(autoApply)
        if not ok then dlog("autoApply: %s", tostring(err)) end
    end)
    return false
end)

LoopAsync(Config.PanelPollMs, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(panelTick)
        if not ok then dlog("panel: %s", tostring(err)) end
    end)
    return false
end)

log("Loaded v%s: %d camos, %d stickers, %d saved weapon presets. Mod folder: %s", VERSION,
    #Camos, #Stickers, (function() local n = 0 for _ in pairs(Presets) do n = n + 1 end return n end)(), MOD_DIR)
