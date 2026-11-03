/* SAI_fnc_memApply - store a loss in the side's danger map and the shooter in its list of enemy firing positions */
params ["_side", "_victimPos", "_shooterPos"];
private _mapVar = format ["SAI_danger_%1", _side];
private _map = missionNamespace getVariable [_mapVar, createHashMap];
missionNamespace setVariable [_mapVar, _map];
private _k = [_victimPos] call SAI_fnc_memKey;
private _lvl = ([_side, _victimPos] call SAI_fnc_memDanger) + 1;
_map set [_k, [_lvl min 5, time]];

private _nestVar = format ["SAI_nests_%1", _side];
private _nests = missionNamespace getVariable [_nestVar, []];
_nests pushBack [_shooterPos, time];
if (count _nests > 30) then { _nests deleteAt 0 };
missionNamespace setVariable [_nestVar, _nests];
