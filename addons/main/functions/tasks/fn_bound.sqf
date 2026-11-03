/*
    SAI_fnc_bound (scheduled)
    Bounding overwatch assault: the group splits in two; one half moves 20-30 m
    from cover to cover while the other half suppresses, then they swap.
*/
params ["_grp", "_targetPos", ["_timeout", 120]];
private _end = time + _timeout;
private _units = (units _grp) select {alive _x && {vehicle _x == _x} && {_x checkAIFeature "PATH"} && {lifeState _x != "INCAPACITATED"}};
if (count _units < 2) exitWith {};
private _teams = [[], []];
{ (_teams select (_forEachIndex % 2)) pushBack _x } forEach _units;
private _threatASL = AGLToASL _targetPos;
private _moving = 0;
_grp setVariable ["SAI_bounding", true];
{ _x setVariable ["SAI_busyUntil", _end] } forEach _units;

while {
    time < _end
    && {({alive _x} count _units) > 0}
    && {(selectMin (_units select {alive _x} apply { _x distance2D _targetPos })) > 25}
} do {
    private _move = (_teams select _moving) select {alive _x && {lifeState _x != "INCAPACITATED"}};
    private _cover = (_teams select (1 - _moving)) select {alive _x && {lifeState _x != "INCAPACITATED"}};
    if (SAI_suppression) then { { [_x, _threatASL] spawn SAI_fnc_suppressFire } forEach _cover };
    sleep 1;
    {
        private _d = (_x distance2D _targetPos) min (20 + random 10);
        private _dest = _x getPos [_d, (_x getDir _targetPos) + (random 30) - 15];
        private _c = [_x, _threatASL, 12, _dest] call SAI_fnc_findCover;
        if (_c isNotEqualTo []) then { _dest = _c };
        _x setUnitPos "AUTO";
        _x doMove _dest;
    } forEach _move;
    private _tEnd = time + 18;
    waitUntil { sleep 1; time > _tEnd || {(_move findIf { alive _x && {!moveToCompleted _x} && {!moveToFailed _x} }) == -1} };
    { if (alive _x) then { doStop _x; _x setUnitPos "MIDDLE" } } forEach _move;
    _moving = 1 - _moving;
};
{
    if (alive _x) then {
        _x setVariable ["SAI_busyUntil", 0];
        _x setUnitPos "AUTO";
        if (leader _x != _x) then { _x doFollow leader _x };
    };
} forEach _units;
_grp setVariable ["SAI_bounding", false];
