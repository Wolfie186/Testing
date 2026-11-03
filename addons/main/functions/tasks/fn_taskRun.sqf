/*
    SAI_fnc_taskRun (spawn) - executes a commander task.
    Movement always uses the tactical (concealed) path when enabled.
*/
params ["_grp", "_type", "_args", "_id"];
private _side = side _grp;
private _alive = { !isNull _grp && {({alive _x} count units _grp) > 0} };
private _route = {
    params ["_to", "_threats"];
    private _path = [];
    if (SAI_tacticalPathing) then { _path = [getPosATL leader _grp, _to, _threats, _side] call SAI_fnc_tacticalPath };
    if (_path isEqualTo []) then { _path = [_to] };
    _path
};
private _waitArrive = {
    params ["_pos", "_radius", "_timeout", ["_abortOnContact", false]];
    private _end = time + _timeout;
    waitUntil {
        sleep 2;
        !(call _alive)
        || {((leader _grp) distance2D _pos) < _radius}
        || {time > _end}
        || {_abortOnContact && {(_grp getVariable ["SAI_state", ""]) in ["ENGAGED", "FALLBACK"]}}
    };
    (call _alive) && {((leader _grp) distance2D _pos) < _radius}
};

switch (_type) do {
    // ------------------------------------------------------------------ ATTACK
    case "ATTACK": {
        _args params ["_target", "_jump", "_threats", "_fixers"];
        _grp setVariable ["SAI_state", "MANOEUVRE", true];
        [_grp, [_jump, _threats] call _route, "MOVE", "AWARE", "FULL"] call SAI_fnc_moveAlongPath;
        private _ok = [_jump, 45, 300, true] call _waitArrive;
        if (!(call _alive)) exitWith {};
        // H-hour: everybody who is fixing the enemy fires, then we assault from the flank
        { if (!isNull _x) then { _x setVariable ["SAI_fireMission", [_target, _id], true] } } forEach _fixers;
        sleep 4;
        [_grp] call SAI_fnc_clearTempWPs;
        _grp setBehaviour "COMBAT";
        _grp setVariable ["SAI_state", "ENGAGED", true];
        [_grp, _target, 120] call SAI_fnc_bound;
    };
    // ------------------------------------------------------------------ AMBUSH
    case "AMBUSH": {
        _args params ["_pos", "_dir", "_threats", "_heading"];
        _grp setVariable ["SAI_state", "MANOEUVRE", true];
        [_grp, [_pos, _threats] call _route, "MOVE", "AWARE", "FULL"] call SAI_fnc_moveAlongPath;
        if ([_pos, 30, 240, true] call _waitArrive) then {
            [_grp] call SAI_fnc_clearTempWPs;
            [_grp, _pos, _dir] call SAI_fnc_ambushSetup;
            waitUntil { sleep 3; !(call _alive) || {(_grp getVariable ["SAI_state", ""]) != "AMBUSH"} };
        };
    };
    // ------------------------------------------------------------------ BLOCK (second line)
    case "BLOCK": {
        _args params ["_pos", "_dir", "_threats"];
        _grp setVariable ["SAI_state", "MANOEUVRE", true];
        [_grp, [_pos, _threats] call _route, "MOVE", "AWARE", "FULL"] call SAI_fnc_moveAlongPath;
        if ([_pos, 30, 240, true] call _waitArrive) then {
            [_grp] call SAI_fnc_clearTempWPs;
            _grp setVariable ["SAI_state", "ALERT", true];
            private _threatASL = AGLToASL (_pos getPos [150, _dir]);
            { if (alive _x && {isNull objectParent _x}) then { [_x, _threatASL, random 3] spawn SAI_fnc_takeCover } } forEach units _grp;
            sleep 120;
        };
    };
    // ------------------------------------------------------------------ AT_HUNT
    case "AT_HUNT": {
        _args params ["_pos", "_threats"];
        _grp setVariable ["SAI_state", "MANOEUVRE", true];
        // approach to ~250 m on the armour's flank
        private _side1 = _pos getPos [250, (_pos getDir leader _grp) + 70];
        private _side2 = _pos getPos [250, (_pos getDir leader _grp) - 70];
        private _fp = [_side2, _side1] select (((leader _grp) distance2D _side1) < ((leader _grp) distance2D _side2));
        [_grp, [_fp, _threats] call _route, "MOVE", "AWARE", "FULL"] call SAI_fnc_moveAlongPath;
        [_fp, 40, 300, true] call _waitArrive;
        if (!(call _alive)) exitWith {};
        [_grp] call SAI_fnc_clearTempWPs;
        _grp setBehaviour "COMBAT";
        private _end = time + 180;
        waitUntil {
            sleep 4;
            private _enemies = [_grp, 600, 60] call SAI_fnc_knownEnemies;
            [_grp, units _grp select {alive _x}, _enemies] call SAI_fnc_atCheck;
            !(call _alive) || {time > _end} || {(_enemies findIf { ([_x select 1] call SAI_fnc_targetType) == "armor" }) == -1}
        };
    };
    // ------------------------------------------------------------------ HUNT
    case "HUNT": {
        _args params ["_pos", "_threats"];
        _grp setVariable ["SAI_state", "SEARCH", true];
        _grp setVariable ["SAI_searchUntil", time + 240];
        [_grp, [_pos, _threats] call _route, "SAD", "AWARE", "NORMAL"] call SAI_fnc_moveAlongPath;
        [_pos, 40, 240, true] call _waitArrive;
        sleep 60;
    };
};

[_grp, _id] call SAI_fnc_taskDone;
