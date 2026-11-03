/*
    SAI_fnc_knownEnemies
    Enemies the group actually knows about (no cheating: uses the leader's
    perceived target positions, not real ones).
    Returns [[distance, target, perceivedPosAGL, age], ...] sorted by distance.
*/
params ["_grp", ["_maxDist", 1000], ["_maxAge", 60]];
private _leader = leader _grp;
private _side = side _grp;
private _res = [];
{
    _x params ["_acc", "_tgt", "_tSide", "_type", "_pos", "_age"];
    if (
        alive _tgt
        && {_age <= _maxAge}
        && {_tSide in [west, east, independent]}
        && {(_side getFriend _tSide) < 0.6}
        && {!(_tgt isKindOf "Air") || {(getPosATL _tgt select 2) < 50}}
    ) then {
        private _d = _leader distance2D _pos;
        if (_d <= _maxDist) then { _res pushBack [_d, _tgt, _pos, _age] };
    };
} forEach (_leader targetsQuery [objNull, sideUnknown, "", [], _maxAge]);
_res sort true;
_res
