/*
    SAI_fnc_applySkill
    "Smart, not aimbot": high awareness and tactics, human-like aim.
    SAI_skill (0.1 .. 1) scales how dangerous the shooting is.
*/
params ["_unit"];
private _s = SAI_skill;
private _j = { (random 0.1) - 0.05 }; // individual variation

_unit setSkill ["general",        (0.8 + 0.2 * _s) min 1];
_unit setSkill ["commanding",     1];
_unit setSkill ["courage",        (0.6 + 0.4 * _s + call _j) min 1];
_unit setSkill ["spotDistance",   (0.55 + 0.4 * _s + call _j) min 1];
_unit setSkill ["spotTime",       (0.45 + 0.4 * _s + call _j) min 1];
_unit setSkill ["aimingAccuracy", (0.12 + 0.43 * _s + call _j) max 0.05];
_unit setSkill ["aimingShake",    (0.3 + 0.45 * _s + call _j) max 0.1];
_unit setSkill ["aimingSpeed",    (0.3 + 0.45 * _s + call _j) max 0.1];
_unit setSkill ["reloadSpeed",    (0.6 + 0.4 * _s) min 1];

// Smart AI decides when to retreat; vanilla panic-fleeing is disabled.
_unit allowFleeing 0;
