-- Camo & Stickers for Into the Radius 2 — settings.
-- Edit this file with any text editor; restart the game (or hot-reload UE4SS mods) to apply.

return {
    -- Your own pictures. Images in the mod's Camo\ and Stickers\ folders are always used;
    -- list extra folders here (anywhere on disk). Formats: png, jpg, jpeg, bmp, tga.
    -- After adding or editing files in-game press SHIFT+INS to reload, no restart needed.
    -- Example: CustomCamoFolders = { [[C:\Users\Me\Pictures\ITR2 Camo]] },
    CustomCamoFolders = {},
    CustomStickerFolders = {},

    -- Co-op sync: everyone with the mod sees the camo each player picked for the gun in
    -- their hands. See README ("Мультиплеер") for setup: SyncTool\host.bat on the host,
    -- SyncTool\join.bat on the others, or point Folder at a shared cloud folder.
    Sync = {
        Enabled = false,
        -- Shared folder with one subfolder per player. Empty = <mod folder>\Sync,
        -- which is where SyncTool\camo_sync.py mirrors to by default.
        Folder = "",
        -- Guns nobody holds (on the ground, in shops): "mine" = your preset, "factory".
        UnownedWeapons = "mine",
        -- Guns held by a player whose profile isn't synced (no mod): "factory" or "mine".
        PlayersWithoutMod = "factory",
        -- A dropped gun keeps the look of the last player who held it.
        KeepLastOwner = true,
    },

    -- "composite": camo is blended over the weapon's original texture and stickers are
    --              drawn on top (needs the weapon material to expose a base color texture param).
    -- "replace":   the base color texture is simply swapped for the camo texture.
    --              Most compatible, but stickers are not shown in this mode.
    Mode = "composite",

    -- Size of the generated weapon textures (composite mode). 1024 or 2048.
    RenderTargetSize = 2048,

    -- How strongly the camo covers the original paint (composite mode). 1.0 = fully covered.
    -- The F10 key cycles through CamoStrengthSteps in-game.
    DefaultCamoStrength = 0.85,
    CamoStrengthSteps = { 0.55, 0.7, 0.85, 1.0 },

    -- Camo tiling: bigger value = smaller pattern. F9 cycles through CamoScaleSteps.
    DefaultCamoScale = 2.0,
    CamoScaleSteps = { 1.0, 2.0, 3.0, 4.0, 6.0 },

    -- Default sticker size as a fraction of the texture width, and nudge steps for the numpad.
    DefaultStickerSize = 0.12,
    StickerMoveStep = 0.01,
    StickerSizeStep = 0.01,
    StickerRotateStep = 15,

    -- Where new stickers are placed (UV space, 0..1). Every weapon has its own UV layout,
    -- so use the numpad to move the active sticker to where it looks right; it is saved.
    StickerSlots = {
        { U = 0.30, V = 0.30 },
        { U = 0.60, V = 0.30 },
        { U = 0.30, V = 0.60 },
        { U = 0.60, V = 0.60 },
        { U = 0.45, V = 0.45 },
    },

    -- A weapon actor is "in your hands" when it is the closest weapon to the camera,
    -- within this many centimeters.
    TargetMaxDistance = 150,

    -- Actor class names (short names, e.g. "BP_Weapon_AKM_C") count as weapons when they
    -- contain one of these substrings (case-insensitive) and none of the excluded ones.
    -- Use the INS key next to an unpainted gun to dump nearby classes to the UE4SS log.
    WeaponClassPatterns = {
        "weapon", "firearm", "gun", "rifle", "pistol", "shotgun", "revolver", "smg",
        "carbine", "sniper", "akm", "ak74", "aks", "sks", "svd", "mosin", "makarov", "pm_",
        "tt33", "toz", "mp5", "m4a1", "glock", "saiga", "vss", "knife", "machete",
    },
    WeaponClassExcludePatterns = {
        "magazine", "mag_", "_mag", "ammo", "cartridge", "bullet", "shell", "round",
        "holster", "spawner", "projectile", "attachment", "scope", "sight", "suppressor",
        "silencer", "muzzle", "rack", "case", "box", "crate", "cleaning", "repair",
        "manager", "subsystem", "component", "widget", "hud", "spawn", "loot", "trader",
    },

    -- Mesh components whose name contains one of these are never painted (glass, reticles…).
    ComponentExcludePatterns = {
        "lens", "glass", "reticle", "holo", "laser", "beam", "flash", "fx", "decal",
    },

    -- Texture parameter names tried for the base color, in priority order (case-insensitive).
    -- If none matches, any texture param containing one of BaseColorParamHints is used.
    BaseColorParamNames = {
        "BaseColor", "Base Color", "BaseColorTexture", "BaseColorMap", "Albedo", "AlbedoTexture",
        "Diffuse", "DiffuseTexture", "Color", "ColorTexture", "T_BaseColor", "BC", "D", "Tex_BC",
    },
    BaseColorParamHints = { "basecolor", "albedo", "diffuse", "color", "_bc", "_d" },
    BaseColorParamBlacklist = { "normal", "rough", "metal", "mask", "orm", "arm", "ao", "emis", "height", "detail" },

    -- Re-apply saved camo to weapons that spawn (loaded saves, traders, stash) every N ms.
    AutoApplyIntervalMs = 3000,

    -- Hotkeys. Names are UE4SS Key names; Modifiers can be "SHIFT", "CONTROL", "ALT".
    -- A key with modifiers is a separate binding: F5 and SHIFT+F5 do different things.
    Keys = {
        NextCamo        = { Key = "F5" },
        PrevCamo        = { Key = "F5", Modifiers = { "SHIFT" } },
        NextSticker     = { Key = "F6" },
        PrevSticker     = { Key = "F6", Modifiers = { "SHIFT" } },
        AddSticker      = { Key = "F7" },
        RemoveSticker   = { Key = "F7", Modifiers = { "SHIFT" } },
        NextActiveLayer = { Key = "F8" },
        NextStickerTexture = { Key = "F8", Modifiers = { "SHIFT" } },
        CycleCamoScale  = { Key = "F9" },
        CycleStrength   = { Key = "F10" },
        ResetWeapon     = { Key = "DEL" },
        DumpNearby      = { Key = "INS" },
        Reload          = { Key = "INS", Modifiers = { "SHIFT" } }, -- rescan images + presets

        StickerLeft     = { Key = "NUM_FOUR" },
        StickerRight    = { Key = "NUM_SIX" },
        StickerUp       = { Key = "NUM_EIGHT" },
        StickerDown     = { Key = "NUM_TWO" },
        StickerBigger   = { Key = "ADD" },
        StickerSmaller  = { Key = "SUBTRACT" },
        StickerRotLeft  = { Key = "NUM_SEVEN" },
        StickerRotRight = { Key = "NUM_NINE" },
    },

    -- Print extra diagnostics to the UE4SS console/log.
    Debug = false,
}
