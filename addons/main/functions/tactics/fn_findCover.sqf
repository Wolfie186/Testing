/*
    SAI_fnc_findCover
    Finds a nearby position that is actually hidden from the threat
    (validated with a line-of-fire check at crouch height).
    Params: unit, threat position ASL, search radius
    Returns: position AGL, or [] if nothing found.
*/
params ["_unit", "_threatASL", ["_radius", 25]];
private _uPos = getPosATL _unit;
private _threatEye = _threatASL vectorAdd [0, 0, 1.5];
private _uThreatDist = _uPos distance2D _threatASL;

private _objs = nearestTerrainObjects [_uPos, ["TREE", "ROCK", "ROCKS", "WALL", "HIDE", "FENCE", "BUILDING", "HOUSE", "CHURCH", "CHAPEL", "BUNKER", "FORTRESS", "RUIN", "FUELSTATION", "TRANSMITTER", "WATERTOWER", "SHIPWRECK"], _radius, false, true];
{
    if (crew _x isEqualTo [] && {!(_x isKindOf "CAManBase")}) then { _objs pushBackUnique _x };
} forEach (nearestObjects [_uPos, ["Building", "Wall", "Car", "Tank", "Strategic"], _radius]);

private _sorted = _objs apply { [_x distance2D _unit, _x] };
_sorted sort true;

private _occupied = {
    params ["_p", "_me"];
    ((_p nearEntities ["CAManBase", 1.5]) - [_me]) isNotEqualTo []
};
private _isHidden = {
    params ["_p"];
    ([objNull, "FIRE"] checkVisibility [_threatEye, (AGLToASL _p) vectorAdd [0, 0, 1]]) < 0.2
};

private _best = [];
private _bestScore = 1e9;
private _found = 0;
{
    if (_forEachIndex > 24 || {_found >= 3}) exitWith {};
    private _obj = _x select 1;
    private _oPos = getPosATL _obj;
    private _candidates = [];

    // Behind the object, seen from the threat
    private _bb = boundingBoxReal _obj;
    private _half = ((((_bb select 1 select 0) - (_bb select 0 select 0)) max ((_bb select 1 select 1) - (_bb select 0 select 1))) / 2) min 5 max 0.4;
    private _dir = _threatASL getDir _oPos;
    { _candidates pushBack (_oPos getPos [_x, _dir]) } forEach [(_half * 0.5) + 0.8, _half + 1.2];

    // Inside buildings
    if (_obj isKindOf "House") then {
        { _candidates pushBack _x } forEach ((_obj buildingPos -1) select [0, 8]);
    };

    {
        private _c = _x;
        if (
            !surfaceIsWater _c
            && {(_c distance2D _uPos) <= _radius * 1.3}
            && {(_c distance2D _threatASL) > 8}
            && {(_c distance2D _threatASL) > _uThreatDist - 15}   // don't run toward the enemy
            && {!([_c, _unit] call _occupied)}
            && {[_c] call _isHidden}
        ) then {
            private _score = (_c distance2D _uPos) - ((_c distance2D _threatASL) - _uThreatDist) * 0.3;
            _found = _found + 1;
            if (_score < _bestScore) then { _bestScore = _score; _best = _c };
        };
    } forEach _candidates;
} forEach _sorted;

_best
