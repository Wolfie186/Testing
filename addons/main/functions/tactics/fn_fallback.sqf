/*
    SAI_fnc_fallback
    Heavy losses vs. a stronger enemy: pop smoke, one man covers, the rest
    bound back to a position away from the enemy, then the group regroups.
*/
params ["_grp", "_units", "_ePos"];
private _leader = leader _grp;
private _now = time;
_grp setVariable ["SAI_nextFallback", _now + 300];
_grp setVariable ["SAI_fallbackUntil", _now + 70];

private _away = _ePos getDir (getPosATL _leader);
private _fp = [];
for "_i" from 0 to 5 do {
    private _p = (getPosATL _leader) getPos [120 + random 80, _away + (random 60) - 30];
    if (!surfaceIsWater _p) exitWith { _fp = _p };
};
if (_fp isEqualTo []) exitWith {};

// Smoke screen between us and them
if (SAI_smoke) then {
    private _smoker = (_units select {(_x getVariable ["SAI_busyUntil", 0]) < _now && {[_x, true] call SAI_fnc_getGrenadeMuzzle != ""}}) param [0, objNull];
    if (!isNull _smoker) then {
        [_smoker, AGLToASL ((getPosATL _smoker) getPos [15, _smoker getDir _ePos]), true] call SAI_fnc_throwGrenade;
    };
};

// One volunteer covers the withdrawal
if (SAI_suppression && {combatMode _grp in ["YELLOW", "RED"]}) then {
    private _cover = (_units - [_leader]) select {[_x] call SAI_fnc_isMG};
    if (_cover isEqualTo []) then { _cover = _units - [_leader] };
    if (_cover isNotEqualTo []) then { [_cover select 0, AGLToASL _ePos] spawn SAI_fnc_suppressFire };
};

{ _x setVariable ["SAI_busyUntil", 0]; _x doFollow _leader } forEach (_units - [_leader]);
_grp setBehaviour "AWARE";
_grp setSpeedMode "FULL";
private _wp = _grp addWaypoint [_fp, 10];
_wp setWaypointType "MOVE";
_wp setWaypointStatements ["true", "(group this) setBehaviour 'COMBAT'; (group this) setSpeedMode 'NORMAL';"];
_grp setCurrentWaypoint _wp;
_grp setVariable ["SAI_tempWPs", (_grp getVariable ["SAI_tempWPs", []]) + [_wp]];
_grp setVariable ["SAI_startSize", count _units]; // after regrouping, morale is reset
["Group %1 falling back", groupId _grp] call SAI_fnc_log;
