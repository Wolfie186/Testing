/*
    SAI_fnc_vehHeli
      - transport: never land in a hot LZ - the landing waypoint is moved
        800-1000 m away from known enemies, onto a clear spot
      - known AA / missile launches: fly low (terrain masking)
      - armed helicopters keep stand-off from AT/AA infantry instead of hovering over them
*/
params ["_veh", "_grp", "_enemies"];
private _now = time;
private _side = side _grp;

// ---- hot LZ
private _cargo = fullCrew [_veh, "cargo", false];
if (_cargo isEqualTo []) then { _veh setVariable ["SAI_lzMoved", false] };
private _wps = waypoints _grp;
private _cur = currentWaypoint _grp;
if (_cargo isNotEqualTo [] && {_cur < count _wps} && {!(_veh getVariable ["SAI_lzMoved", false])}) then {
    private _wp = _wps select _cur;
    if ((waypointType _wp) in ["TR UNLOAD", "UNLOAD", "GETOUT"]) then {
        private _lz = waypointPosition _wp;
        private _near = (_enemies select { ((_x select 2) distance2D _lz) < 600 }) apply { _x select 2 };
        if (isServer && {SAI_commander}) then {
            { if (((_y select 1) distance2D _lz) < 600 && {(_now - (_y select 2)) < 180}) then { _near pushBack (_y select 1) } } forEach (SAI_picture getOrDefault [_side, createHashMap]);
        };
        { _near pushBack _x } forEach ([_side, _lz, 400] call SAI_fnc_memNests);
        if (_near isNotEqualTo []) then {
            private _c = [0, 0, 0];
            { _c = _c vectorAdd _x } forEach _near;
            _c = _c vectorMultiply (1 / count _near);
            private _dir = _c getDir _veh;
            private _newLz = [];
            for "_i" from 0 to 5 do {
                private _p = _c getPos [800 + random 200, _dir + (random 80) - 40];
                if (_newLz isEqualTo [] && {!surfaceIsWater _p}) then {
                    private _e = _p findEmptyPosition [0, 150, typeOf _veh];
                    if (_e isNotEqualTo [] && {((surfaceNormal _e) select 2) > 0.9}) exitWith { _newLz = _e };
                };
            };
            if (_newLz isNotEqualTo []) then {
                _wp setWaypointPosition [_newLz, 0];
                createVehicle ["Land_HelipadEmpty_F", _newLz, [], 0, "CAN_COLLIDE"];
                _veh setVariable ["SAI_lzMoved", true];
                ["%1: LZ is hot, diverting %2 m", typeOf _veh, round (_newLz distance2D _lz)] call SAI_fnc_log;
            };
        };
    };
};

// ---- AA awareness
private _aa = _enemies select {
    private _t = _x select 1;
    ((_t isKindOf "CAManBase") && {([_t] call SAI_fnc_launcherType) == "AA"}) || {(_t isKindOf "LandVehicle") && {"_aa" in toLower typeOf _t}}
};
private _aaMem = _veh getVariable ["SAI_aaThreat", []];
private _aaRecent = _aaMem isNotEqualTo [] && {(_now - (_aaMem select 1)) < 180};
if (_aa isNotEqualTo [] || {_aaRecent}) then {
    if !(_veh getVariable ["SAI_lowFly", false]) then { _veh flyInHeight 35; _veh setVariable ["SAI_lowFly", true] };
} else {
    if (_veh getVariable ["SAI_lowFly", false]) then { _veh flyInHeight 100; _veh setVariable ["SAI_lowFly", false] };
};

// ---- stand-off for gunships
private _armed = alive gunner _veh || {((_veh weaponsTurret [-1]) findIf { !("flare" in toLower _x) && {!("smoke" in toLower _x)} }) != -1};
if (_armed && {canMove _veh} && {_now > _veh getVariable ["SAI_nextStandoff", 0]} && {[_grp] call SAI_fnc_canMove}) then {
    private _danger = _enemies select { (_x select 0) < 900 && {(_x select 1) isKindOf "CAManBase"} && {([_x select 1] call SAI_fnc_launcherType) != ""} };
    if (_danger isNotEqualTo []) then {
        _veh setVariable ["SAI_nextStandoff", _now + 40];
        private _p = (_danger select 0) select 2;
        (effectiveCommander _veh) doMove (_p getPos [1600, _p getDir _veh]);
        ["%1 keeps stand-off from launcher teams", typeOf _veh] call SAI_fnc_log;
    };
};
