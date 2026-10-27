-- Camo & Stickers for Into the Radius 2 (UE4SS Lua mod)
--
-- Paints weapons with camo patterns and sticks stickers on them at runtime:
--   * camo/sticker PNGs are loaded from the mod folder (drop your own in, no repacking),
--   * the weapon's base color texture is composited with camo + stickers into a render
--     target that replaces it through a dynamic material instance,
--   * choices are saved per weapon type in presets.lua and re-applied to every gun of
--     that type, including ones that spawn later.

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

local function getPC()
    if valid(CachedPC) and valid(CachedPC.Pawn) then return CachedPC end
    CachedPC = nil
    local pcs = FindAllOf("PlayerController") or {}
    for _, pc in ipairs(pcs) do
        if valid(pc) and valid(pc.Pawn) then
            CachedPC = pc
            return pc
        end
    end
    for _, pc in ipairs(pcs) do
        if valid(pc) then return pc end
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

local function targetWeapon()
    local pc = getPC()
    if not pc then
        log("No player controller yet.")
        return nil
    end
    local hit = nearbyActors(pc, Config.TargetMaxDistance, true)[1]
    if not hit then
        log("No weapon within %d cm. Hold or look at a gun (INS dumps nearby classes).", Config.TargetMaxDistance)
        return nil
    end
    return hit.Actor, hit.Class
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

local function camoTexture(name)
    local i = name and indexByName(Camos, name)
    return i and loadTexture(Camos[i].Path) or nil
end

local function stickerTexture(name)
    local i = name and indexByName(Stickers, name)
    return i and loadTexture(Stickers[i].Path) or nil
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
local function buildComposite(key, baseTex, preset, texIndex)
    local rt = cacheGet(CompositeCache, key)
    if rt then return rt end

    local pc = getPC()
    if not pc then return nil end
    local size = Config.RenderTargetSize
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

local function autoApply()
    for cls, preset in pairs(Presets) do
        local sig = presetSignature(preset)
        for _, actor in ipairs(FindAllOf(cls) or {}) do
            if valid(actor) then
                local ok, err = pcall(function()
                    local fullName = actor:GetFullName()
                    if Applied[fullName] ~= sig or not stillApplied(actor) then
                        applyToActor(actor, preset)
                    end
                end)
                if not ok then dlog("Auto-apply failed for %s: %s", cls, tostring(err)) end
            end
        end
    end
end

------------------------------------------------------------------------ actions

local function presetFor(cls)
    local p = Presets[cls]
    if not p then
        p = { Scale = Config.DefaultCamoScale, Strength = Config.DefaultCamoStrength, Stickers = {}, Active = 0 }
        Presets[cls] = p
    end
    p.Stickers = p.Stickers or {}
    return p
end

local function commit(cls)
    local p = Presets[cls]
    if presetIsEmpty(p) then Presets[cls] = nil end
    applyClass(cls)
    if Presets[cls] == nil then
        for _, actor in ipairs(FindAllOf(cls) or {}) do
            if valid(actor) then pcall(resetActor, actor) end
        end
    end
    savePresets()
end

local function cycle(list, current, step)
    -- Index 0 means "none".
    local n = #list
    local i = (current or 0) + step
    if i > n then i = 0 elseif i < 0 then i = n end
    return i
end

local function withWeapon(fn)
    local actor, cls = targetWeapon()
    if actor then fn(actor, cls, presetFor(cls)) end
end

local function changeCamo(step)
    if #Camos == 0 then return log("No camo images found in %s", CAMO_DIR) end
    withWeapon(function(_, cls, p)
        local i = cycle(Camos, indexByName(Camos, p.Camo), step)
        p.Camo = i > 0 and Camos[i].Name or nil
        commit(cls)
        log("%s: camo = %s", cls, p.Camo or "none")
    end)
end

local function activeSticker(p)
    if #p.Stickers == 0 then return nil end
    p.Active = math.max(1, math.min(p.Active or 1, #p.Stickers))
    return p.Stickers[p.Active]
end

local function addSticker()
    if #Stickers == 0 then return log("No sticker images found in %s", STICKER_DIR) end
    withWeapon(function(_, cls, p)
        local slot = Config.StickerSlots[(#p.Stickers % #Config.StickerSlots) + 1]
        p.Stickers[#p.Stickers + 1] = {
            Name = Stickers[1].Name, U = slot.U, V = slot.V, Size = Config.DefaultStickerSize, Rot = 0, Tex = 1,
        }
        p.Active = #p.Stickers
        commit(cls)
        log("%s: added sticker #%d (%s)", cls, p.Active, Stickers[1].Name)
    end)
end

local function changeSticker(step)
    if #Stickers == 0 then return log("No sticker images found in %s", STICKER_DIR) end
    withWeapon(function(_, cls, p)
        local s = activeSticker(p)
        if not s then return addSticker() end
        local i = (indexByName(Stickers, s.Name) or 1) + step
        if i > #Stickers then i = 1 elseif i < 1 then i = #Stickers end
        s.Name = Stickers[i].Name
        commit(cls)
        log("%s: sticker #%d = %s", cls, p.Active, s.Name)
    end)
end

local function removeSticker()
    withWeapon(function(_, cls, p)
        if not activeSticker(p) then return log("%s has no stickers", cls) end
        table.remove(p.Stickers, p.Active)
        p.Active = #p.Stickers
        commit(cls)
        log("%s: sticker removed, %d left", cls, #p.Stickers)
    end)
end

local function nextActiveLayer()
    withWeapon(function(actor, cls, p)
        if #p.Stickers == 0 then return log("%s has no stickers", cls) end
        p.Active = (p.Active or 0) % #p.Stickers + 1
        log("%s: editing sticker #%d (%s)", cls, p.Active, p.Stickers[p.Active].Name)
    end)
end

-- Moves the active sticker to the next distinct texture of the weapon (receiver, stock…).
local function nextStickerTexture()
    withWeapon(function(actor, cls, p)
        local s = activeSticker(p)
        if not s then return log("%s has no stickers", cls) end
        local count = math.max(1, #baseTextures(materialSlots(actor)))
        s.Tex = (s.Tex or 1) % count + 1
        commit(cls)
        log("%s: sticker #%d is on texture %d of %d", cls, p.Active, s.Tex, count)
    end)
end

local function editSticker(fn)
    withWeapon(function(_, cls, p)
        local s = activeSticker(p)
        if not s then return log("%s has no stickers (F7 adds one)", cls) end
        fn(s)
        s.U = math.max(0, math.min(1, s.U))
        s.V = math.max(0, math.min(1, s.V))
        s.Size = math.max(0.02, math.min(1, s.Size))
        s.Rot = (s.Rot or 0) % 360
        commit(cls)
    end)
end

local function stepThrough(steps, current)
    for i, v in ipairs(steps) do
        if math.abs(v - current) < 1e-3 then return steps[i % #steps + 1] end
    end
    return steps[1]
end

local function cycleScale()
    withWeapon(function(_, cls, p)
        p.Scale = stepThrough(Config.CamoScaleSteps, p.Scale or Config.DefaultCamoScale)
        commit(cls)
        log("%s: camo scale = %.2f", cls, p.Scale)
    end)
end

local function cycleStrength()
    withWeapon(function(_, cls, p)
        p.Strength = stepThrough(Config.CamoStrengthSteps, p.Strength or Config.DefaultCamoStrength)
        commit(cls)
        log("%s: camo strength = %.2f", cls, p.Strength)
    end)
end

local function resetWeapon()
    withWeapon(function(_, cls)
        Presets[cls] = nil
        commit(cls)
        log("%s: back to factory finish", cls)
    end)
end

local function dumpNearby()
    local pc = getPC()
    if not pc then return log("No player controller yet.") end
    log("---- Actors within 200 cm (W = matches weapon patterns) ----")
    local near = nearbyActors(pc, 200, false)
    for i = 1, math.min(15, #near) do
        local e = near[i]
        log("%s %6.1f cm  %s", isWeaponClass(e.Class) and "W" or " ", e.Dist, e.Class)
    end
    local actor, cls = targetWeapon()
    if not actor then return end
    log("---- Target weapon: %s ----", actor:GetFullName())
    local slots = materialSlots(actor)
    local texs = baseTextures(slots)
    for _, slot in ipairs(slots) do
        local _, order = textureParams(slot.Base)
        log("  %s [%d] %s", objName(slot.Comp), slot.Index, slot.Base:GetFullName())
        log("      texture params: %s", #order > 0 and table.concat(order, ", ") or "(none listed, plain material)")
        log("      base color: %s  (sticker texture #%s)", tostring(slot.Param), tostring(slot.TexIndex))
    end
    log("  %d distinct base color textures; preset: %s", #texs, presetSignature(Presets[cls]))
end

-- Re-reads the image folders and presets, and reloads every texture from disk, so new or
-- edited pictures show up without restarting the game.
local function reloadAll()
    scanAllImages()
    for k in pairs(TextureCache) do TextureCache[k] = nil end
    for k in pairs(CompositeCache) do CompositeCache[k] = nil end
    CompositeSupported = true
    loadPresets()
    Applied = {}
    autoApply()
    local n = 0
    for _ in pairs(Presets) do n = n + 1 end
    log("Reloaded: %d camos, %d stickers, %d weapon presets", #Camos, #Stickers, n)
end

------------------------------------------------------------------------ bindings

local Actions = {
    NextCamo = function() changeCamo(1) end,
    PrevCamo = function() changeCamo(-1) end,
    NextSticker = function() changeSticker(1) end,
    PrevSticker = function() changeSticker(-1) end,
    AddSticker = addSticker,
    RemoveSticker = removeSticker,
    NextActiveLayer = nextActiveLayer,
    NextStickerTexture = nextStickerTexture,
    CycleCamoScale = cycleScale,
    CycleStrength = cycleStrength,
    ResetWeapon = resetWeapon,
    DumpNearby = dumpNearby,
    Reload = reloadAll,
    ReloadPresets = reloadAll, -- old name, kept for edited configs
    StickerLeft = function() editSticker(function(s) s.U = s.U - Config.StickerMoveStep end) end,
    StickerRight = function() editSticker(function(s) s.U = s.U + Config.StickerMoveStep end) end,
    StickerUp = function() editSticker(function(s) s.V = s.V - Config.StickerMoveStep end) end,
    StickerDown = function() editSticker(function(s) s.V = s.V + Config.StickerMoveStep end) end,
    StickerBigger = function() editSticker(function(s) s.Size = s.Size + Config.StickerSizeStep end) end,
    StickerSmaller = function() editSticker(function(s) s.Size = s.Size - Config.StickerSizeStep end) end,
    StickerRotLeft = function() editSticker(function(s) s.Rot = (s.Rot or 0) - Config.StickerRotateStep end) end,
    StickerRotRight = function() editSticker(function(s) s.Rot = (s.Rot or 0) + Config.StickerRotateStep end) end,
}

local function runSafe(name, fn)
    ExecuteInGameThread(function()
        local ok, err = pcall(fn)
        if not ok then log("%s failed: %s", name, tostring(err)) end
    end)
end

for action, bind in pairs(Config.Keys) do
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

------------------------------------------------------------------------ startup

loadPresets()

LoopAsync(Config.AutoApplyIntervalMs, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(autoApply)
        if not ok then dlog("autoApply: %s", tostring(err)) end
    end)
    return false
end)

log("Loaded: %d camos, %d stickers, %d saved weapon presets. Mod folder: %s",
    #Camos, #Stickers, (function() local n = 0 for _ in pairs(Presets) do n = n + 1 end return n end)(), MOD_DIR)
