/* SAI_fnc_manStatics - grab an empty static weapon nearby that can see the enemy */
params ["_grp", "_units", "_ePos"];
private _now = time;
if (_now < _grp getVariable ["SAI_nextStatic", 0] || {count _units < 3}) exitWith {};
_grp setVariable ["SAI_nextStatic", _now + 20];
private _statics = (nearestObjects [getPosATL leader _grp, ["StaticWeapon"], 70]) select {
    alive _x && {(crew _x) isEqualTo []} && {locked _x < 2} && {someAmmo _x}
    && {!(_x getVariable ["SAI_claimed", false])}
    && {([_x, "VIEW"] checkVisibility [(getPosASL _x) vectorAdd [0, 0, 1.5], (AGLToASL _ePos) vectorAdd [0, 0, 1]]) > 0.3}
};
if (_statics isEqualTo []) exitWith {};
private _st = _statics select 0;
private _cands = (_units - [leader _grp]) select {
    isNull objectParent _x && {(_x getVariable ["SAI_busyUntil", 0]) < _now} && {!([_x] call SAI_fnc_isMG)} && {([_x] call SAI_fnc_launcherType) == ""} && {_x checkAIFeature "PATH"}
};
if (_cands isEqualTo []) exitWith {};
private _s = _cands apply { [_x distance _st, _x] };
_s sort true;
private _u = _s select 0 select 1;
_st setVariable ["SAI_claimed", true, true];
_u setVariable ["SAI_busyUntil", _now + 1e6];
_u assignAsGunner _st;
[_u] orderGetIn true;
["%1 mans a %2", name _u, typeOf _st] call SAI_fnc_log;
