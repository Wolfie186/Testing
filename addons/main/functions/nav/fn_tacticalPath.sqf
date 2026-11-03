/*
    SAI_fnc_tacticalPath  (scheduled - may take a moment)
    A* over a terrain grid. Cell cost = distance x (1 + penalties):
      - exposure: line of sight from known enemy positions (up to 4)
      - open ground: little cover / concealment
      - slope, water (impassable)
      - dangerous ground: places where friendlies were killed recently
    Returns a list of AGL positions (roughly every 120 m) ending at _to, or [] on failure.
*/
params ["_from", "_to", ["_threats", []], ["_side", sideUnknown], ["_cell", 40]];
_from = +_from; _to = +_to;
_from resize 2; _to resize 2;
private _dist = _from distance2D _to;
if (_dist < _cell * 2.5) exitWith { [_to + [0]] };

private _margin = ((_dist * 0.5) max 150) min 600;
private _minX = ((_from select 0) min (_to select 0)) - _margin;
private _minY = ((_from select 1) min (_to select 1)) - _margin;
private _maxX = ((_from select 0) max (_to select 0)) + _margin;
private _maxY = ((_from select 1) max (_to select 1)) + _margin;
if (((_maxX - _minX) * (_maxY - _minY)) / (_cell * _cell) > 4000) then {
    _cell = sqrt (((_maxX - _minX) * (_maxY - _minY)) / 4000);
};
private _nx = ceil ((_maxX - _minX) / _cell);
private _ny = ceil ((_maxY - _minY) / _cell);

private _toIdx = { params ["_p"]; [floor (((_p select 0) - _minX) / _cell), floor (((_p select 1) - _minY) / _cell)] };
private _cellPos = { params ["_i", "_j"]; [_minX + (_i + 0.5) * _cell, _minY + (_j + 0.5) * _cell, 0] };
private _threatEyes = (_threats select [0, 4]) apply { (AGLToASL _x) vectorAdd [0, 0, 1.7] };
private _useMemory = SAI_memory && {_side != sideUnknown};

private _costCache = createHashMap;
private _cellCost = {
    params ["_i", "_j"];
    private _k = _i * 10000 + _j;
    private _c = _costCache getOrDefault [_k, -2];
    if (_c == -2) then {
        private _p = [_i, _j] call _cellPos;
        private _n = surfaceNormal _p;
        if (surfaceIsWater _p || {(_n select 2) < 0.6}) then {
            _c = -1;
        } else {
            private _pASL = (AGLToASL _p) vectorAdd [0, 0, 1.2];
            private _exposure = 0;
            {
                if ((_x distance2D _pASL) < 1000) then {
                    _exposure = _exposure + ([objNull, "VIEW"] checkVisibility [_x, _pASL]);
                };
            } forEach _threatEyes;
            private _cover = count (nearestTerrainObjects [_p, ["TREE", "SMALL TREE", "BUSH", "ROCK", "ROCKS", "HOUSE", "BUILDING", "WALL", "HIDE", "FOREST"], _cell * 0.6, false, true]);
            private _open = 1 - ((_cover min 12) / 12);
            private _danger = if (_useMemory) then { [_side, _p] call SAI_fnc_memDanger } else {0};
            _c = (_exposure * 4) + (_open * 1.2) + ((1 - (_n select 2)) * 10) + (_danger * 2);
        };
        _costCache set [_k, _c];
    };
    _c
};

private _start = [_from] call _toIdx;
private _goal = [_to] call _toIdx;
_goal params ["_gi", "_gj"];
private _startKey = (_start select 0) * 10000 + (_start select 1);
private _goalKey = _gi * 10000 + _gj;
private _h = { params ["_i", "_j"]; sqrt (((_i - _gi) ^ 2) + ((_j - _gj) ^ 2)) };

private _gScore = createHashMapFromArray [[_startKey, 0]];
private _came = createHashMap;
private _closed = createHashMap;
private _open = [[0, _start select 0, _start select 1]];
private _dirs = [[1, 0, 1], [-1, 0, 1], [0, 1, 1], [0, -1, 1], [1, 1, 1.414], [1, -1, 1.414], [-1, 1, 1.414], [-1, -1, 1.414]];
private _found = false;
private _iter = 0;

while {!_found && {_open isNotEqualTo []} && {_iter < 2500}} do {
    _iter = _iter + 1;
    if (_iter % 50 == 0) then { sleep 0.01 }; // stay friendly to the scheduler
    _open sort true;
    (_open deleteAt 0) params ["_f", "_ci", "_cj"];
    private _ck = _ci * 10000 + _cj;
    if !(_ck in _closed) then {
        _closed set [_ck, true];
        if (_ck == _goalKey) then {
            _found = true;
        } else {
            private _gc = _gScore get _ck;
            {
                _x params ["_di", "_dj", "_dl"];
                private _ni = _ci + _di;
                private _nj = _cj + _dj;
                if (_ni >= 0 && {_nj >= 0} && {_ni < _nx} && {_nj < _ny}) then {
                    private _nk = _ni * 10000 + _nj;
                    if !(_nk in _closed) then {
                        private _cc = [_ni, _nj] call _cellCost;
                        if (_cc >= 0) then {
                            private _tg = _gc + _dl * (1 + _cc);
                            if (_tg < (_gScore getOrDefault [_nk, 1e9])) then {
                                _gScore set [_nk, _tg];
                                _came set [_nk, _ck];
                                _open pushBack [_tg + ([_ni, _nj] call _h), _ni, _nj];
                            };
                        };
                    };
                };
            } forEach _dirs;
        };
    };
};
if (!_found) exitWith { [] };

private _keys = [];
private _k = _goalKey;
while {_k != _startKey} do { _keys pushBack _k; _k = _came get _k };
reverse _keys;

private _step = (ceil (120 / _cell)) max 1;
private _res = [];
{
    if ((_forEachIndex % _step) == (_step - 1) && {_forEachIndex < (count _keys - 2)}) then {
        _res pushBack ([floor (_x / 10000), _x % 10000] call _cellPos);
    };
} forEach _keys;
_res pushBack (_to + [0]);
_res
