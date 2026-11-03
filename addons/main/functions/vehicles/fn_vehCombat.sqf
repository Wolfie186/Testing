/*
    SAI_fnc_vehCombat - armoured / armed vehicle tactics
      - target priority: enemy armour > AT soldiers > statics/armed cars > rest
      - hull-down firing positions at the vehicle's preferred stand-off range
      - shoot and scoot: relocate after a few main-gun shots, after being hit or locked
      - AT infantry close and no friendly infantry around -> pop smoke and back off
*/
params ["_veh", "_grp", "_enemies", "_standoff"];
if (_enemies isEqualTo []) exitWith {
    if ((_veh getVariable ["SAI_vstate", "IDLE"]) != "MOVING") then { _veh setVariable ["SAI_vstate", "IDLE"] };
};
private _now = time;
(_enemies select 0) params ["_d", "_tgt", "_ePos"];

// ---- target priority
private _gunner = gunner _veh;
if (alive _gunner && {canFire _veh} && {_now > _veh getVariable ["SAI_nextRetarget", 0]}) then {
    private _scored = _enemies apply {
        _x params ["_ed", "_et"];
        private _s = switch ([_et] call SAI_fnc_targetType) do {
            case "armor":  {100};
            case "static": {50};
            case "car":    { [30, 60] select (!isNull gunner _et) };
            case "air":    {5};
            default        { [10, 80] select (([_et] call SAI_fnc_launcherType) == "AT") };
        };
        [_s - (_ed / 25), _et]
    };
    _scored sort false;
    private _best = _scored select 0 select 1;
    if (_best != assignedTarget _gunner) then {
        _veh setVariable ["SAI_nextRetarget", _now + 6];
        (group _gunner) reveal [_best, 2];
        _gunner doTarget _best;
        _gunner doFire _best;
    };
};

// ---- manoeuvre (only for vehicles that are free to move)
if (!SAI_vehHullDown || {!canMove _veh} || {!alive driver _veh} || {!([_grp] call SAI_fnc_canMove)}) exitWith {};
private _vstate = _veh getVariable ["SAI_vstate", "IDLE"];
if (_vstate == "MOVING") exitWith {};

private _atClose = (_enemies findIf { (_x select 0) < 175 && {(_x select 1) isKindOf "CAManBase"} && {([_x select 1] call SAI_fnc_launcherType) == "AT"} }) != -1;
private _infNear = (allGroups select {
    side _x == side _grp && {_x != _grp} && {alive leader _x} && {vehicle leader _x == leader _x} && {(leader _x) distance2D _veh < 150}
}) isNotEqualTo [];
if (_atClose && {!_infNear}) exitWith { [_veh, _ePos, "BACKOFF", _standoff] spawn SAI_fnc_vehReposition };
if (_d < _standoff * 0.4 && {!_infNear} && {_veh getVariable ["SAI_vtype", ""] != "armor" || {_d < 120}}) exitWith {
    [_veh, _ePos, "BACKOFF", _standoff] spawn SAI_fnc_vehReposition;
};

private _needMove = _vstate == "IDLE"
    || {(_veh getVariable ["SAI_shots", 0]) >= 3 + floor random 3}
    || {_veh getVariable ["SAI_scoot", false]}
    || {_now > (_veh getVariable ["SAI_holdUntil", 0])};
if (_needMove) then { [_veh, _ePos, "HULLDOWN", _standoff] spawn SAI_fnc_vehReposition };
