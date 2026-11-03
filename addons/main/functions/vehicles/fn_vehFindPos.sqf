/*
    SAI_fnc_vehFindPos - firing / hiding positions for a vehicle relative to a threat.
    Modes:
      "HULLDOWN" - hull hidden by terrain, turret/sights see the threat, near stand-off range
      "HIDDEN"   - whole vehicle out of sight and not closer to the threat (dismount / back off)
    Returns AGL position or [].
*/
params ["_veh", "_tPos", ["_radius", 200], ["_mode", "HULLDOWN"], ["_standoff", 500]];
private _vPos = getPosATL _veh;
private _tEye = (AGLToASL _tPos) vectorAdd [0, 0, 1.8];
private _bb = boundingBoxReal _veh;
private _h = ((_bb select 1 select 2) - (_bb select 0 select 2)) max 1.5;
private _toT = _vPos getDir _tPos;
private _best = [];
private _bestScore = 1e9;
for "_i" from 0 to 27 do {
    private _ang = if (_mode == "HULLDOWN") then { _toT + (random 240) - 120 } else { _toT + 180 + (random 140) - 70 };
    private _p = _vPos getPos [20 + random _radius, _ang];
    if (
        !surfaceIsWater _p
        && {((surfaceNormal _p) select 2) > 0.88}
        && {(nearestTerrainObjects [_p, ["TREE", "HOUSE", "BUILDING", "ROCK", "ROCKS", "WALL", "FENCE", "CHURCH", "CHAPEL", "BUNKER", "FORTRESS"], 7, false, true]) isEqualTo []}
        && {((_p nearEntities [["LandVehicle"], 9]) - [_veh]) isEqualTo []}
    ) then {
        private _pASL = AGLToASL _p;
        private _dT = _p distance2D _tPos;
        private _top = [_veh, "VIEW"] checkVisibility [_tEye, _pASL vectorAdd [0, 0, _h * 0.95]];
        private _ok = if (_mode == "HULLDOWN") then {
            _top > 0.6 && {_dT > _standoff * 0.5} && {([_veh, "FIRE"] checkVisibility [_tEye, _pASL vectorAdd [0, 0, _h * 0.45]]) < 0.35}
        } else {
            _top < 0.3 && {_dT >= (_vPos distance2D _tPos) - 10}
        };
        if (_ok) then {
            private _score = (_p distance2D _vPos) + (abs (_dT - _standoff)) * ([0.1, 0.4] select (_mode == "HULLDOWN"));
            if (_score < _bestScore) then { _bestScore = _score; _best = _p };
        };
    };
};
_best
