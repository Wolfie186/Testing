/*
    SAI_fnc_settings (called from XEH preInit)
    Registers all mod settings with CBA:
    Options -> Addon Options -> Smart AI  (server / mission / client tabs).
    Missions can force values in Eden: Attributes -> Addon Options, or via cba_settings.sqf.
*/

// [variable, type, valueInfo (CBA format), subcategory, needRestart]
private _defs = [
    ["SAI_enabled",          "CHECKBOX", true,                 "STR_SAI_cat_general", false],
    ["SAI_debug",            "CHECKBOX", false,                "STR_SAI_cat_general", false],
    ["SAI_tick",             "SLIDER",   [1, 10, 3, 1],        "STR_SAI_cat_general", false],
    ["SAI_applySkills",      "CHECKBOX", true,                 "STR_SAI_cat_skill",   false],
    ["SAI_skill",            "SLIDER",   [0.1, 1, 0.6, 2],     "STR_SAI_cat_skill",   false],
    ["SAI_cover",            "CHECKBOX", true,                 "STR_SAI_cat_tactics", false],
    ["SAI_suppression",      "CHECKBOX", true,                 "STR_SAI_cat_tactics", false],
    ["SAI_flanking",         "CHECKBOX", true,                 "STR_SAI_cat_tactics", false],
    ["SAI_grenades",         "CHECKBOX", true,                 "STR_SAI_cat_tactics", false],
    ["SAI_smoke",            "CHECKBOX", true,                 "STR_SAI_cat_tactics", false],
    ["SAI_fallback",         "CHECKBOX", true,                 "STR_SAI_cat_tactics", false],
    ["SAI_search",           "CHECKBOX", true,                 "STR_SAI_cat_tactics", false],
    ["SAI_buddyAid",         "CHECKBOX", true,                 "STR_SAI_cat_medical", false],
    ["SAI_selfAid",          "CHECKBOX", true,                 "STR_SAI_cat_medical", false],
    ["SAI_aidRadius",        "SLIDER",   [20, 200, 80, 0],     "STR_SAI_cat_medical", false],
    ["SAI_aceMedical",       "CHECKBOX", true,                 "STR_SAI_cat_medical", false],
    ["SAI_intel",            "CHECKBOX", true,                 "STR_SAI_cat_coord",   false],
    ["SAI_intelRadius",      "SLIDER",   [100, 3000, 800, 0],  "STR_SAI_cat_coord",   false],
    ["SAI_reinforce",        "CHECKBOX", true,                 "STR_SAI_cat_coord",   false],
    ["SAI_reinforceRadius",  "SLIDER",   [200, 5000, 1500, 0], "STR_SAI_cat_coord",   false],
    ["SAI_respectWaypoints", "CHECKBOX", true,                 "STR_SAI_cat_coord",   false]
];

{
    _x params ["_var", "_type", "_info", "_sub", "_restart"];
    [
        _var, _type,
        [localize format ["STR_%1", _var], localize format ["STR_%1_tip", _var]],
        [localize "STR_SAI_cat_main", localize _sub],
        _info,
        1,      // global: server value is forced on every machine
        {},
        _restart
    ] call CBA_fnc_addSetting;
} forEach _defs;
