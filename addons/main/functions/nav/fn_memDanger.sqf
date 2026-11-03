/* SAI_fnc_memDanger - how dangerous this 50 m cell is for _side (0..5), fading over 15 minutes */
params ["_side", "_pos"];
private _map = missionNamespace getVariable [format ["SAI_danger_%1", _side], createHashMap];
private _e = _map getOrDefault [[_pos] call SAI_fnc_memKey, []];
if (_e isEqualTo []) exitWith {0};
_e params ["_lvl", "_t"];
(_lvl * (1 - ((time - _t) / 900))) max 0
