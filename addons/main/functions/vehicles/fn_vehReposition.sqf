/* SAI_fnc_vehReposition (spawn) - move to a hull-down / hidden position, then hold there for a while */
params ["_veh", "_ePos", "_mode", ["_standoff", 500]];
_veh setVariable ["SAI_vstate", "MOVING"];
private _pos = if (_mode == "BACKOFF") then {
    private _p = [_veh, _ePos, 200, "HIDDEN"] call SAI_fnc_vehFindPos;
    if (_p isEqualTo []) then { (getPosATL _veh) getPos [150, _ePos getDir _veh] } else { _p };
} else {
    [_veh, _ePos, 220, "HULLDOWN", _standoff] call SAI_fnc_vehFindPos
};
private _hold = {
    _veh setVariable ["SAI_vstate", "HOLD"];
    _veh setVariable ["SAI_holdUntil", time + 30 + random 30];
    _veh setVariable ["SAI_shots", 0];
    _veh setVariable ["SAI_scoot", false];
};
if (_pos isEqualTo [] || {surfaceIsWater _pos}) exitWith { call _hold; _veh setVariable ["SAI_holdUntil", time + 20] };

if (_mode == "BACKOFF" || {_veh getVariable ["SAI_scoot", false]}) then { [_veh] call SAI_fnc_vehSmoke };
private _cmdr = effectiveCommander _veh;
_cmdr doMove _pos;
["%1 -> %2 position", typeOf _veh, _mode] call SAI_fnc_log;
private _t = time + 45;
waitUntil { sleep 1; !alive _veh || {!canMove _veh} || {(_veh distance2D _pos) < 8} || {time > _t} };
if (alive _veh) then { call _hold };
