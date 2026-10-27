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

local function isLocalController(pc)
    local ok, isLocal = pcall(function() return pc:IsLocalController() end)
    return not ok or isLocal -- if the call isn't available, assume single player
end

-- The local player's controller. On a co-op host every client has a PlayerController
-- there too, so pick the one that is ours.
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

-- Remote[playerName] = { Presets = {...}, Images = { camo = { name = path }, sticker = {...} } }
-- filled by the sync code below; source "" means the local player.
local Remote = {}

local function imagePath(kind, name, source)
    if not name then return nil end
    if source and source ~= "" then
        local r = Remote[source]
        return r and r.Images[kind][name] or nil
    end
    local list = kind == "camo" and Camos or Stickers
    local i = indexByName(list, name)
    return i and list[i].Path or nil
end

local function camoTexture(name, source)
    local path = imagePath("camo", name, source)
    return path and loadTexture(path) or nil
end

local function stickerTexture(name, source)
    local path = imagePath("sticker", name, source)
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
local function buildComposite(key, baseTex, preset, texIndex, source)
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

    local camo = camoTexture(preset.Camo, source)
    local stickers = {}
    for _, s in ipairs(preset.Stickers or {}) do
        if (s.Tex or 1) == texIndex then
            local tex = stickerTexture(s.Name, source)
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

-- source: "" for the local player's preset, otherwise the name of the player it came from.
local function applyToActor(actor, preset, source)
    source = source or ""
    local okName, fullName = pcall(function() return actor:GetFullName() end)
    if not okName then return end
    if presetIsEmpty(preset) then
        resetActor(actor)
        Applied[fullName] = nil
        return
    end

    local sig = source .. "|" .. presetSignature(preset)
    local slots = materialSlots(actor)
    local texCount = #baseTextures(slots)
    local camo = camoTexture(preset.Camo, source)
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
                tex = buildComposite(baseKey .. "#" .. sig, slot.BaseTex, preset, slot.TexIndex or 1, source)
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

------------------------------------------------------------------------ multiplayer sync
--
-- Co-op sync works through a shared folder, because a Lua mod can't add replicated data
-- to the game's own netcode:
--   * every player's mod writes its presets + the pictures they use to
--     <SyncFolder>\<PlayerName>\ (profile.txt and images\),
--   * the folders are mirrored between players by SyncTool\camo_sync.py (host/join over
--     TCP) or by any cloud folder (Dropbox, OneDrive, Syncthing…),
--   * a weapon is painted with the preset of the player holding it (found through its
--     attachment/owner chain), so everyone with the mod sees everyone's camo.

local SyncCfg = Config.Sync or {}
local SYNC_DIR = trimSlashes((SyncCfg.Folder and SyncCfg.Folder ~= "") and SyncCfg.Folder or (MOD_DIR .. SEP .. "Sync"))
if SEP == "\\" then SYNC_DIR = SYNC_DIR:gsub("/", "\\") end

local MyName           -- local player's name as the game reports it
local LastHolder = {}  -- actor full name -> player name, so a dropped gun keeps its owner's look
local RemoteRaw = {}   -- player name -> last profile.txt contents

local function syncEnabled()
    return SyncCfg.Enabled == true
end

-- Player names become folder names: keep them file-system safe and predictable.
local function folderName(player)
    local name = player:gsub('[<>:"/\\|%?%*%c]', "_"):gsub("^[%s%.]+", ""):gsub("[%s%.]+$", "")
    return name ~= "" and name or "_"
end

local function fstr(v)
    if type(v) == "string" then return v end
    local ok, str = pcall(function() return v:ToString() end)
    return ok and str or nil
end

local function playerNameOfState(ps)
    if not valid(ps) then return nil end
    local ok, name = pcall(function() return fstr(ps:GetPlayerName()) end)
    if ok and name and name ~= "" then return name end
    return nil
end

-- Name of the player behind a pawn or controller, or nil.
local function playerNameOf(obj)
    local ok, ps = pcall(function() return obj.PlayerState end)
    if ok then return playerNameOfState(ps) end
    return nil
end

local function localPlayerName()
    local pc = getPC()
    return pc and playerNameOf(pc) or nil
end

-- Who holds this weapon: walk attachment parents (hand, holster, backpack…) and owners up
-- to a pawn or controller that has a PlayerState.
local function holderOf(actor)
    local cur = actor
    for _ = 1, 8 do
        local parent
        pcall(function() parent = cur:GetAttachParentActor() end)
        if not valid(parent) then pcall(function() parent = cur:GetOwner() end) end
        if not valid(parent) then return nil end
        local name = playerNameOf(parent)
        if name then return name end
        cur = parent
    end
    return nil
end

-- The preset and its source for one weapon actor.
local function effectivePreset(actor, cls)
    if not syncEnabled() then return Presets[cls], "" end
    local okName, fullName = pcall(function() return actor:GetFullName() end)
    local holder = holderOf(actor)
    if okName then
        if holder then
            LastHolder[fullName] = holder
        elseif SyncCfg.KeepLastOwner ~= false then
            holder = LastHolder[fullName]
        end
    end
    if holder == nil then
        if SyncCfg.UnownedWeapons == "factory" then return nil, "" end
        return Presets[cls], ""
    end
    if holder == MyName then return Presets[cls], "" end
    local r = Remote[holder]
    if r then return r.Presets[cls], holder end
    -- That player has no synced profile (no mod, or sync not set up on their side).
    if SyncCfg.PlayersWithoutMod == "mine" then return Presets[cls], "" end
    return nil, ""
end

local function refreshActor(actor, cls, force)
    local preset, source = effectivePreset(actor, cls)
    local fullName = actor:GetFullName()
    local sig = presetIsEmpty(preset) and "" or (source .. "|" .. presetSignature(preset))
    if sig == "" then
        if force or Applied[fullName] ~= nil or stillApplied(actor) then
            resetActor(actor)
            Applied[fullName] = nil
        end
    elseif force or Applied[fullName] ~= sig or not stillApplied(actor) then
        applyToActor(actor, preset, source)
    end
end

local function refreshClass(cls, force)
    for _, actor in ipairs(FindAllOf(cls) or {}) do
        if valid(actor) then
            local ok, err = pcall(refreshActor, actor, cls, force)
            if not ok then log("Failed to apply to %s: %s", cls, tostring(err)) end
        end
    end
end

-- Every weapon class someone has a preset for, plus classes that are currently painted.
local function knownClasses()
    local set = {}
    for cls in pairs(Presets) do set[cls] = true end
    for _, r in pairs(Remote) do
        for cls in pairs(r.Presets) do set[cls] = true end
    end
    return set
end

local PaintedClasses = {}

local function autoApply()
    local classes = knownClasses()
    -- Classes that lost their last preset still need one pass to reset painted guns.
    for cls in pairs(PaintedClasses) do classes[cls] = true end
    PaintedClasses = knownClasses()
    for cls in pairs(classes) do refreshClass(cls, false) end
end

---------------------------------------------------------------- profile files

local IMAGE_FILE_OK = { png = true, jpg = true, jpeg = true, bmp = true, tga = true }

local function baseName(path)
    return path:match("([^/\\]+)$") or path
end

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

local function ensureDir(dir)
    if writeFile(dir .. SEP .. ".cas_probe", "") then
        os.remove(dir .. SEP .. ".cas_probe")
        return true
    end
    -- Only runs the first time a folder is needed.
    os.execute(SEP == "\\" and string.format('mkdir "%s" 2>nul', dir) or string.format('mkdir -p "%s"', dir))
    return writeFile(dir .. SEP .. ".cas_probe", "") and os.remove(dir .. SEP .. ".cas_probe") ~= nil
end

local CopiedImages = {} -- destination -> size, to skip re-copying unchanged pictures

local function copyImage(src, dst)
    local data = readFile(src)
    if not data then return false end
    if CopiedImages[dst] == #data then return true end
    if writeFile(dst, data) then
        CopiedImages[dst] = #data
        return true
    end
    return false
end

local function num(v) return string.format("%.4f", v) end

-- Writes <SyncFolder>\<me>\profile.txt and copies the pictures it uses.
local function publishProfile()
    if not syncEnabled() or not MyName then return end
    local myDir = SYNC_DIR .. SEP .. folderName(MyName)
    local imgDir = myDir .. SEP .. "images"
    if not (ensureDir(SYNC_DIR) and ensureDir(myDir) and ensureDir(imgDir)) then
        log("Can't create sync folder %s", myDir)
        return
    end
    -- Tells camo_sync.py which folder this machine owns (dot files are never synced).
    writeFile(SYNC_DIR .. SEP .. ".me", folderName(MyName))

    local lines = { "CAS-PROFILE\t1", "player\t" .. MyName }
    local imageLines, used = {}, {}
    local function useImage(kind, name)
        local key = kind .. "\t" .. name
        if used[key] then return end
        used[key] = true
        local src = imagePath(kind, name, "")
        if not src then return end
        local file = (kind == "camo" and "c_" or "s_") .. baseName(src)
        if copyImage(src, imgDir .. SEP .. file) then
            imageLines[#imageLines + 1] = table.concat({ "image", kind, name, file }, "\t")
        end
    end

    local classes = {}
    for cls in pairs(Presets) do classes[#classes + 1] = cls end
    table.sort(classes)
    for _, cls in ipairs(classes) do
        local p = Presets[cls]
        if not presetIsEmpty(p) then
            if p.Camo then useImage("camo", p.Camo) end
            lines[#lines + 1] = table.concat({ "preset", cls, p.Camo or "",
                num(p.Scale or Config.DefaultCamoScale), num(p.Strength or Config.DefaultCamoStrength) }, "\t")
            for _, st in ipairs(p.Stickers or {}) do
                useImage("sticker", st.Name)
                lines[#lines + 1] = table.concat({ "sticker", cls, st.Name, num(st.U), num(st.V), num(st.Size),
                    num(st.Rot or 0), tostring(st.Tex or 1) }, "\t")
            end
        end
    end
    for _, l in ipairs(imageLines) do lines[#lines + 1] = l end

    -- Write-then-rename so the sync tool never picks up a half-written file.
    local final, tmp = myDir .. SEP .. "profile.txt", myDir .. SEP .. "profile.txt.tmp"
    if writeFile(tmp, table.concat(lines, "\n") .. "\n") then
        os.remove(final)
        os.rename(tmp, final)
    end
end

-- Parses another player's profile.txt. Remote files are untrusted: plain data only, file
-- names are reduced to a bare name with an image extension inside that player's folder.
local function parseProfile(text, dir)
    if not text:match("^CAS%-PROFILE\t1") then return nil end
    local profile = { Presets = {}, Images = { camo = {}, sticker = {} } }
    local count = 0
    for line in text:gmatch("[^\n]+") do
        count = count + 1
        if count > 4000 then break end
        local f = {}
        for field in (line:gsub("\r$", "") .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = field end
        local kind = f[1]
        if kind == "player" then
            profile.Player = f[2]
        elseif kind == "preset" and f[2] and f[2] ~= "" then
            profile.Presets[f[2]] = {
                Camo = (f[3] ~= nil and f[3] ~= "") and f[3] or nil,
                Scale = tonumber(f[4]) or Config.DefaultCamoScale,
                Strength = tonumber(f[5]) or Config.DefaultCamoStrength,
                Stickers = {},
            }
        elseif kind == "sticker" and profile.Presets[f[2] or ""] then
            local st = profile.Presets[f[2]].Stickers
            local u, v, size = tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
            if f[3] and u and v and size and #st < 32 then
                st[#st + 1] = { Name = f[3], U = u, V = v, Size = size, Rot = tonumber(f[7]) or 0,
                    Tex = math.tointeger(tonumber(f[8])) or 1 }
            end
        elseif kind == "image" and (f[2] == "camo" or f[2] == "sticker") and f[3] and f[4] then
            local file = f[4]
            local ext = file:match("%.([%w]+)$")
            if not file:find("[/\\]") and not file:find("^%.") and ext and IMAGE_FILE_OK[ext:lower()] then
                profile.Images[f[2]][f[3]] = dir .. SEP .. "images" .. SEP .. file
            end
        end
    end
    return profile
end

-- Reads the profiles of the other players in the session. Their names come from the
-- game's PlayerStates, so no folder listing is needed.
local function pollRemoteProfiles()
    local present = {}
    for _, ps in ipairs(FindAllOf("PlayerState") or {}) do
        local name = playerNameOfState(ps)
        if name and name ~= MyName then present[name] = true end
    end
    for name in pairs(present) do
        local dir = SYNC_DIR .. SEP .. folderName(name)
        local text = readFile(dir .. SEP .. "profile.txt")
        if text and text ~= RemoteRaw[name] then
            local profile = parseProfile(text, dir)
            if profile then
                RemoteRaw[name] = text
                -- Pictures may have been replaced under the same file name.
                for key in pairs(TextureCache) do
                    if key:sub(1, #dir) == dir then TextureCache[key] = nil end
                end
                Remote[name] = profile
                log("Synced camo profile of %s", name)
            end
        end
    end
    for name in pairs(Remote) do
        if not present[name] then
            Remote[name] = nil
            RemoteRaw[name] = nil
        end
    end
end

local function syncTick()
    if not syncEnabled() then return end
    local name = localPlayerName()
    if name and name ~= MyName then
        MyName = name
        publishProfile()
        log("Sync: you are '%s', profile folder %s", MyName, SYNC_DIR .. SEP .. folderName(MyName))
    end
    pollRemoteProfiles()
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
    refreshClass(cls, true)
    savePresets()
    publishProfile()
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
    log("  %d distinct base color textures; your preset: %s", #texs, presetSignature(Presets[cls]))
    if syncEnabled() then
        local preset, source = effectivePreset(actor, cls)
        log("  sync: you = %s, holder = %s, showing %s preset: %s", tostring(MyName), tostring(holderOf(actor)),
            source == "" and "your" or (source .. "'s"), presetSignature(preset))
        local names = {}
        for name in pairs(Remote) do names[#names + 1] = name end
        log("  synced players: %s (folder %s)", #names > 0 and table.concat(names, ", ") or "none", SYNC_DIR)
    end
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
    RemoteRaw = {}
    CopiedImages = {}
    syncTick()
    publishProfile()
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
        local okSync, errSync = pcall(syncTick)
        if not okSync then dlog("sync: %s", tostring(errSync)) end
        local ok, err = pcall(autoApply)
        if not ok then dlog("autoApply: %s", tostring(err)) end
    end)
    return false
end)

log("Loaded: %d camos, %d stickers, %d saved weapon presets. Mod folder: %s",
    #Camos, #Stickers, (function() local n = 0 for _ in pairs(Presets) do n = n + 1 end return n end)(), MOD_DIR)
