/*
    SAI_fnc_cmdPlan (server)
    The side commander. Looks at the battle picture (only what its groups
    actually reported) and decides operations for groups that are free:

      ENVELOP  - enemy is fixed by our engaged groups -> a free group attacks
                 from a flank via a concealed route, synchronised with a fire mission
      AMBUSH   - enemy is moving and nobody is fighting it yet -> set an ambush
                 on its predicted route
      AT_HUNT  - enemy armour -> a group with AT launchers stalks it from the side
      BLOCK    - enemy too strong -> free groups build a second line behind ours
      HUNT     - contact lost -> search where the enemy is predicted to be
                 and put a cut-off group further along his route
    About a quarter of the free groups stay in reserve.
*/
params ["_side"];
private _clusters = [_side] call SAI_fnc_cmdClusters;
if (_clusters isEqualTo []) exitWith {};
private _now = time;

private _groups = allGroups select { side _x == _side && {[_x, false] call SAI_fnc_isValidGroup} };
private _free = _groups select {
    (_x getVariable ["SAI_task", []]) isEqualTo []
    && {(_x getVariable ["SAI_state", "SAFE"]) in ["SAFE", "ALERT"]}
    && {vehicle leader _x == leader _x}
    && {!(_x getVariable ["SAI_noReinforce", false])}
    && {[_x] call SAI_fnc_canMove}
};
if (_free isEqualTo []) exitWith {};

// keep a reserve: the free groups farthest from any contact stay put
private _reserve = floor (count _free / 4);
if (_reserve > 0) then {
    private _byDist = _free apply {
        private _g = _x;
        [selectMin (_clusters apply { (leader _g) distance2D (_x select 0) }), _g]
    };
    _byDist sort false;
    _free = _free - ((_byDist select [0, _reserve]) apply { _x select 1 });
};

private _strengthOf = { params ["_gs"]; private _n = 0; { _n = _n + ({alive _x} count units _x) } forEach _gs; _n };
private _nearestFree = {
    params ["_pos", ["_filter", {true}], ["_maxDist", SAI_reinforceRadius]];
    private _c = (_free select _filter) select { (leader _x) distance2D _pos < _maxDist };
    if (_c isEqualTo []) exitWith {grpNull};
    private _s = _c apply { [(leader _x) distance2D _pos, _x] };
    _s sort true;
    _s select 0 select 1
};
private _issued = 0;

{
    if (_issued >= 3 || {_free isEqualTo []}) exitWith {};
    _x params ["_cPos", "_strength", "_lastT", "_vel", "_armor", "_positions"];
    private _age = _now - _lastT;
    private _speed = vectorMagnitude (_vel + [0]);
    private _heading = if (_speed > 0.3) then { [0, 0, 0] getDir (_vel + [0]) } else { -1 };
    private _threats = _positions select [0, 4];
    private _engaged = _groups select {
        (_x getVariable ["SAI_state", "SAFE"]) in ["ENGAGED", "FLANKING", "FALLBACK", "AMBUSH"] && {(leader _x) distance2D _cPos < 700}
    };
    private _ourNear = [_engaged] call _strengthOf;

    if (_age < 45) then {
        // ---------------------------------------------------------------- live contact
        if (SAI_antiTank && {_armor} && {!([_side, _cPos, "AT_HUNT", 400, 180] call SAI_fnc_cmdRecent)}) then {
            private _g = [_cPos, { (units _x) findIf { alive _x && {([_x] call SAI_fnc_launcherType) == "AT"} } != -1 }, 1500] call _nearestFree;
            if (!isNull _g) then {
                [_g, "AT_HUNT", [_cPos, _threats], _side] call SAI_fnc_cmdAssign;
                _free = _free - [_g]; _issued = _issued + 1;
            };
        };

        if (_free isEqualTo []) exitWith {};
        if (_engaged isNotEqualTo []) then {
            private _g = [_cPos] call _nearestFree;
            if (!isNull _g) then {
                private _gN = {alive _x} count units _g;
                if (_strength <= (_ourNear + _gN) * 1.3) then {
                    if !([_side, _cPos, "ATTACK", 300, 150] call SAI_fnc_cmdRecent) then {
                        // attack axis perpendicular to the line fixers -> enemy, on the side nearer to the attacker
                        private _fixPos = getPosATL leader (_engaged select 0);
                        private _axis = _cPos getDir _fixPos;
                        private _jumpA = _cPos getPos [170, _axis + 90];
                        private _jumpB = _cPos getPos [170, _axis - 90];
                        private _jump = [_jumpB, _jumpA] select (((leader _g) distance2D _jumpA) < ((leader _g) distance2D _jumpB));
                        if (surfaceIsWater _jump) then { _jump = [_jumpA, _jumpB] select (_jump isEqualTo _jumpA) };
                        [_g, "ATTACK", [_cPos, _jump, _threats, _engaged], _side] call SAI_fnc_cmdAssign;
                        _free = _free - [_g]; _issued = _issued + 1;
                    };
                } else {
                    if !([_side, _cPos, "BLOCK", 400, 240] call SAI_fnc_cmdRecent) then {
                        // second line ~200 m behind the engaged groups
                        private _fixPos = getPosATL leader (_engaged select 0);
                        private _bPos = _fixPos getPos [200, _cPos getDir _fixPos];
                        [_g, "BLOCK", [_bPos, _bPos getDir _cPos, _threats], _side] call SAI_fnc_cmdAssign;
                        _free = _free - [_g]; _issued = _issued + 1;
                    };
                };
            };
        } else {
            if (SAI_ambush && {_speed > 0.7} && {!([_side, _cPos, "AMBUSH", 500, 240] call SAI_fnc_cmdRecent)}) then {
                // predict where he will be in ~90 s and get there first
                private _pred = _cPos vectorAdd ((_vel + [0]) vectorMultiply 90);
                if ((_pred distance2D _cPos) > 400) then { _pred = _cPos getPos [400, _heading] };
                private _g = [_pred, { true }, 1200] call _nearestFree;
                if (!isNull _g && {((leader _g) distance2D _pred) / 3 < 90 * 1.1}) then {
                    private _side1 = _pred getPos [70, _heading + 90];
                    private _side2 = _pred getPos [70, _heading - 90];
                    private _cover = { count (nearestTerrainObjects [_this, ["TREE", "BUSH", "ROCK", "ROCKS", "HOUSE", "WALL", "HIDE"], 30, false, true]) };
                    private _aPos = [_side2, _side1] select ((_side1 call _cover) >= (_side2 call _cover));
                    if (surfaceIsWater _aPos) then { _aPos = [_side1, _side2] select (_aPos isEqualTo _side1) };
                    [_g, "AMBUSH", [_aPos, _aPos getDir _pred, _threats, _heading], _side] call SAI_fnc_cmdAssign;
                    _free = _free - [_g]; _issued = _issued + 1;
                };
            } else {
                // stationary enemy that nobody is fighting: deliberate attack
                if (_strength <= 4 && {!([_side, _cPos, "ATTACK", 300, 180] call SAI_fnc_cmdRecent)}) then {
                    private _g = [_cPos, { ({alive _x} count units _x) >= 4 }, 1000] call _nearestFree;
                    if (!isNull _g) then {
                        private _jump = _cPos getPos [180, (_cPos getDir leader _g) + (random 80) - 40];
                        [_g, "ATTACK", [_cPos, _jump, _threats, []], _side] call SAI_fnc_cmdAssign;
                        _free = _free - [_g]; _issued = _issued + 1;
                    };
                };
            };
        };
    } else {
        // ---------------------------------------------------------------- contact lost
        if (SAI_search && {_age < 240} && {!([_side, _cPos, "HUNT", 400, 200] call SAI_fnc_cmdRecent)}) then {
            private _t = _age min 120;
            private _pred = _cPos vectorAdd ((_vel + [0]) vectorMultiply _t);
            if ((_pred distance2D _cPos) > 350) then { _pred = _cPos getPos [350, _heading] };
            if (surfaceIsWater _pred) then { _pred = _cPos };
            private _g = [_pred] call _nearestFree;
            if (!isNull _g) then {
                [_g, "HUNT", [_pred, _threats], _side] call SAI_fnc_cmdAssign;
                _free = _free - [_g]; _issued = _issued + 1;
                // cut-off: wait further along his route
                if (_heading >= 0 && {SAI_ambush}) then {
                    private _cut = _pred getPos [250, _heading];
                    private _g2 = [_cut, { true }, 1500] call _nearestFree;
                    if (!isNull _g2 && {!surfaceIsWater _cut}) then {
                        [_g2, "AMBUSH", [_cut, _cut getDir _pred, _threats, _heading], _side] call SAI_fnc_cmdAssign;
                        _free = _free - [_g2]; _issued = _issued + 1;
                    };
                };
            };
        };
    };

    if (SAI_debug) then { [_side, _forEachIndex, _x] call SAI_fnc_debugCluster };
} forEach _clusters;
