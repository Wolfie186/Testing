/*
    SAI_fnc_handleReinforceRequest - runs on every machine.
    The closest idle local group that is free to move answers the call.
    Opt a group out:  _grp setVariable ["SAI_noReinforce", true, true];
*/
params ["_side", "_pos", "_reqGrp"];
if (!SAI_enabled || {!SAI_reinforce}) exitWith {};
private _cands = allGroups select {
    _x != _reqGrp
    && {side _x == _side}
    && {[_x] call SAI_fnc_isValidGroup}
    && {!(_x getVariable ["SAI_noReinforce", false])}
    && {(_x getVariable ["SAI_state", "SAFE"]) in ["SAFE", "ALERT"]}
    && {(leader _x) distance2D _pos < SAI_reinforceRadius}
    && {canMove vehicle leader _x}
    && {!(vehicle leader _x isKindOf "Air")}
    && {[_x] call SAI_fnc_canMove}
};
if (_cands isEqualTo []) exitWith {};
private _sorted = _cands apply { [(leader _x) distance2D _pos, _x] };
_sorted sort true;
private _g = _sorted select 0 select 1;

_g setVariable ["SAI_state", "REINFORCING", true];
_g setVariable ["SAI_reinforceUntil", time + 300];
_g setBehaviour "AWARE";
_g setSpeedMode "FULL";
// Approach from a slight angle rather than straight down the same lane
private _approach = _pos getPos [40 + random 40, (_pos getDir leader _g) + (random 90) - 45];
private _wp1 = _g addWaypoint [_approach, 15];
_wp1 setWaypointType "MOVE";
private _wp2 = _g addWaypoint [_pos, 30];
_wp2 setWaypointType "SAD";
_wp2 setWaypointBehaviour "COMBAT";
_g setCurrentWaypoint _wp1;
_g setVariable ["SAI_tempWPs", (_g getVariable ["SAI_tempWPs", []]) + [_wp1, _wp2]];
["Group %1 responding to reinforcement request", groupId _g] call SAI_fnc_log;
