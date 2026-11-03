/*
    SAI_fnc_takeCover (spawn)
    Move to real cover facing the threat, hold for a while, then rejoin formation.
    No cover nearby -> go prone where you are.
*/
params ["_unit", "_threatASL", ["_delay", 0]];
if (_delay > 0) then { sleep _delay };
if (!alive _unit || {!isNull objectParent _unit} || {(_unit getVariable ["SAI_busyUntil", 0]) > time}) exitWith {};
if (lifeState _unit == "INCAPACITATED") exitWith {};

private _isLeader = leader _unit == _unit;
private _canPath = _unit checkAIFeature "PATH";
_unit setVariable ["SAI_busyUntil", time + 30];

private _cover = if (_isLeader || {!_canPath}) then { [] } else { [_unit, _threatASL, 25] call SAI_fnc_findCover };

if (_cover isEqualTo []) exitWith {
    _unit setUnitPos (["MIDDLE", "DOWN"] select ((_unit getVariable ["SAI_supp", 0]) > 0.5));
    sleep (4 + random 5);
    if (alive _unit) then { _unit setUnitPos "AUTO" };
    _unit setVariable ["SAI_busyUntil", time + 2];
};

_unit doMove _cover;
private _timeout = time + 15;
waitUntil {
    sleep 0.5;
    !alive _unit || {_unit distance2D _cover < 1.8} || {time > _timeout} || {moveToFailed _unit}
};
if (!alive _unit) exitWith {};

doStop _unit;
_unit setUnitPos (["MIDDLE", "DOWN"] select ((_unit getVariable ["SAI_supp", 0]) > 0.7));
_unit doWatch (ASLToAGL _threatASL);
sleep (8 + random 12);

if (alive _unit) then {
    _unit setUnitPos "AUTO";
    _unit doWatch objNull;
    if (leader _unit != _unit) then { _unit doFollow leader _unit };
};
_unit setVariable ["SAI_busyUntil", 0];
