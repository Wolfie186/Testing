/* SAI_fnc_buddyAidCheck - pick a wounded man and someone to patch him up (vanilla medical only) */
params ["_grp", "_units", "_ePos"];
private _now = time;
if (_now < _grp getVariable ["SAI_nextAid", 0]) exitWith {};
_grp setVariable ["SAI_nextAid", _now + 8];

private _wounded = _units select {
    vehicle _x == _x && {damage _x > 0.3 || {lifeState _x == "INCAPACITATED"}} && {!(_x getVariable ["SAI_beingTreated", false])}
};
if (_wounded isEqualTo []) exitWith {};
private _w = _wounded select 0;

private _hasKit = { params ["_u"]; ("FirstAidKit" in items _u) || {"Medikit" in items _u} };
private _medics = (_units - [_w]) select {
    vehicle _x == _x && {(_x getVariable ["SAI_busyUntil", 0]) < _now} && {lifeState _x != "INCAPACITATED"}
    && {_x checkAIFeature "PATH"} && {[_x] call _hasKit} && {_x distance _w < 80}
};
if (_medics isEqualTo []) exitWith {};
private _sorted = _medics apply { [(_x distance _w) - ([0, 40] select (_x getUnitTrait "Medic")), _x] };
_sorted sort true;
[_sorted select 0 select 1, _w, AGLToASL _ePos] spawn SAI_fnc_buddyAid;
