/*
    SAI_fnc_settings (preInit)
    Registers mod settings. With CBA_A3 loaded they appear in
    Options -> Addon Options -> Smart AI. Without CBA the defaults below are used;
    a mission can override any of them in init.sqf, e.g.  SAI_flanking = false;
*/

// [variable, type, valueInfo (CBA format), default, subcategory]
private _defs = [
    ["SAI_enabled",          "CHECKBOX", true,                 true,  "STR_SAI_cat_general"],
    ["SAI_debug",            "CHECKBOX", false,                false, "STR_SAI_cat_general"],
    ["SAI_tick",             "SLIDER",   [1, 10, 3, 1],        3,     "STR_SAI_cat_general"],
    ["SAI_applySkills",      "CHECKBOX", true,                 true,  "STR_SAI_cat_skill"],
    ["SAI_skill",            "SLIDER",   [0.1, 1, 0.6, 2],     0.6,   "STR_SAI_cat_skill"],
    ["SAI_cover",            "CHECKBOX", true,                 true,  "STR_SAI_cat_tactics"],
    ["SAI_suppression",      "CHECKBOX", true,                 true,  "STR_SAI_cat_tactics"],
    ["SAI_flanking",         "CHECKBOX", true,                 true,  "STR_SAI_cat_tactics"],
    ["SAI_grenades",         "CHECKBOX", true,                 true,  "STR_SAI_cat_tactics"],
    ["SAI_smoke",            "CHECKBOX", true,                 true,  "STR_SAI_cat_tactics"],
    ["SAI_fallback",         "CHECKBOX", true,                 true,  "STR_SAI_cat_tactics"],
    ["SAI_search",           "CHECKBOX", true,                 true,  "STR_SAI_cat_tactics"],
    ["SAI_buddyAid",         "CHECKBOX", true,                 true,  "STR_SAI_cat_tactics"],
    ["SAI_intel",            "CHECKBOX", true,                 true,  "STR_SAI_cat_coord"],
    ["SAI_intelRadius",      "SLIDER",   [100, 3000, 800, 0],  800,   "STR_SAI_cat_coord"],
    ["SAI_reinforce",        "CHECKBOX", true,                 true,  "STR_SAI_cat_coord"],
    ["SAI_reinforceRadius",  "SLIDER",   [200, 5000, 1500, 0], 1500,  "STR_SAI_cat_coord"],
    ["SAI_respectWaypoints", "CHECKBOX", true,                 true,  "STR_SAI_cat_coord"]
];

private _hasCBA = !isNil "CBA_fnc_addSetting";

{
    _x params ["_var", "_type", "_info", "_default", "_sub"];
    if (_hasCBA) then {
        [
            _var, _type,
            [localize format ["STR_%1", _var], localize format ["STR_%1_tip", _var]],
            [localize "STR_SAI_cat_main", localize _sub],
            _info,
            1   // global: the server value is forced on all machines
        ] call CBA_fnc_addSetting;
    } else {
        if (isNil _var) then { missionNamespace setVariable [_var, _default] };
    };
} forEach _defs;
