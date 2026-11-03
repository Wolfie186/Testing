/*
    SAI_fnc_cmdClusters (server)
    Groups known enemy contacts into elements (within 200 m of each other).
    Returns [[centroidAGL, strength, lastSeenTime, velocity, hasArmor, positions, count], ...]
    sorted by strength, strongest first.
*/
params ["_side"];
private _pic = SAI_picture getOrDefault [_side, createHashMap];
private _now = time;
{
    private _e = _pic get _x;
    if (!alive (_e select 0) || {(_now - (_e select 2)) > 300}) then { _pic deleteAt _x };
} forEach (keys _pic);

private _clusters = [];
{
    _y params ["_tgt", "_pos", "_t", "_vel", "_type"];
    private _w = switch (_type) do { case "armor": {6}; case "car": {2}; case "static": {2}; case "air": {4}; default {1} };
    private _idx = _clusters findIf { ((_x select 0) distance2D _pos) < 200 };
    if (_idx == -1) then {
        _clusters pushBack [_pos, _w, _t, _vel, _type == "armor", [_pos], 1];
    } else {
        private _c = _clusters select _idx;
        private _n = (_c select 6) + 1;
        _c set [0, ((_c select 0) vectorMultiply ((_n - 1) / _n)) vectorAdd (_pos vectorMultiply (1 / _n))];
        _c set [1, (_c select 1) + _w];
        _c set [2, (_c select 2) max _t];
        _c set [3, [((_c select 3 select 0) * (_n - 1) + (_vel select 0)) / _n, ((_c select 3 select 1) * (_n - 1) + (_vel select 1)) / _n]];
        _c set [4, (_c select 4) || {_type == "armor"}];
        (_c select 5) pushBack _pos;
        _c set [6, _n];
    };
} forEach _pic;
private _sorted = _clusters apply { [-(_x select 1), _x] };
_sorted sort true;
_sorted apply { _x select 1 }
