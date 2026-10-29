-- Camo & Stickers for Into the Radius 2 — settings.
-- Edit this file with any text editor; restart the game (or hot-reload UE4SS mods) to apply.

return {
    -- Your own pictures. Images in the mod's Camo\ and Stickers\ folders are always used;
    -- list extra folders here (anywhere on disk). Formats: png, jpg, jpeg, bmp, tga.
    -- After adding or editing files press "Обновить картинки" in the control panel.
    -- Example: CustomCamoFolders = { [[C:\Users\Me\Pictures\ITR2 Camo]] },
    CustomCamoFolders = {},
    CustomStickerFolders = {},

    -- "composite": camo is blended over the weapon's original texture and stickers are
    --              drawn on top (needs the weapon material to expose a base color texture param).
    -- "replace":   the base color texture is simply swapped for the camo texture.
    --              Most compatible, but stickers are not shown in this mode.
    Mode = "composite",

    -- Size of the generated weapon textures (composite mode). 1024 or 2048.
    RenderTargetSize = 2048,

    -- How strongly the camo covers the original paint (composite mode). 1.0 = fully covered.
    -- CamoStrengthSteps / CamoScaleSteps are only used by the optional hotkeys.
    DefaultCamoStrength = 0.85,
    CamoStrengthSteps = { 0.55, 0.7, 0.85, 1.0 },

    -- Camo tiling: bigger value = smaller pattern.
    DefaultCamoScale = 2.0,
    CamoScaleSteps = { 1.0, 2.0, 3.0, 4.0, 6.0 },

    -- Default sticker size as a fraction of the texture width, and nudge steps for the hotkeys.
    DefaultStickerSize = 0.12,
    StickerMoveStep = 0.01,
    StickerSizeStep = 0.01,
    StickerRotateStep = 15,

    -- Where new stickers are placed (UV space, 0..1). Every weapon has its own UV layout,
    -- so drag the sticker on the preview in the control panel to where it looks right.
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
    -- The panel's "Диагностика" button lists nearby classes so you can add yours here.
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

    -- Control panel (CamoPanel.bat in the mod folder). It talks to the mod through files in
    -- the mod's Panel\ folder; these are how often the mod checks for panel commands and
    -- how far it looks for weapons to list in the panel.
    PanelPollMs = 250,
    PanelWeaponRadius = 500,
    PreviewSize = 512,

    -- Hotkeys are OFF by default so they can't clash with other mods: everything is in the
    -- control panel. Set EnableHotkeys = true to use them; names are UE4SS Key names,
    -- Modifiers can be "SHIFT", "CONTROL", "ALT" (F5 and SHIFT+F5 are separate bindings).
    EnableHotkeys = false,
    Keys = {
        NextCamo        = { Key = "F5", Modifiers = { "CONTROL", "ALT" } },
        PrevCamo        = { Key = "F5", Modifiers = { "CONTROL", "ALT", "SHIFT" } },
        NextSticker     = { Key = "F6", Modifiers = { "CONTROL", "ALT" } },
        AddSticker      = { Key = "F7", Modifiers = { "CONTROL", "ALT" } },
        RemoveSticker   = { Key = "F7", Modifiers = { "CONTROL", "ALT", "SHIFT" } },
        ResetWeapon     = { Key = "F8", Modifiers = { "CONTROL", "ALT" } },
        CycleCamoScale  = { Key = "F9", Modifiers = { "CONTROL", "ALT" } },
        CycleStrength   = { Key = "F10", Modifiers = { "CONTROL", "ALT" } },
    },

    -- Print extra diagnostics to the UE4SS console/log.
    Debug = false,
}
