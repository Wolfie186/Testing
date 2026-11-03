/*
    SAI_fnc_onSuppressed ("Suppressed" event handler)
    Bullets cracking past -> build up suppression, seek cover,
    and get a buddy to return fire in the rough direction of the shooter.
*/
params ["_unit", "_distance", "_shooter", "_instigator"];
if (!SAI_enabled || {!alive _unit} || {!local _unit} || {isPlayer _unit}) exitWith {};
private _grp = group _unit;
if !([_grp] call SAI_fnc_isValidGroup) exitWith {};
if (vehicle _unit != _unit) exitWith {};

private _now = time;
private _supp = _unit getVariable ["SAI_supp", 0];
_supp = (_supp - (_now - (_unit getVariable ["SAI_suppTime", _now])) * 0.08) max 0; // decays over time
_supp = (_supp + ([0.12, 0.3] select (_distance < 3))) min 1;
_unit setVariable ["SAI_supp", _supp];
_unit setVariable ["SAI_suppTime", _now];

private _src = [_shooter, _instigator] select (!isNull _instigator);
if (isNull _src) exitWith {};

// We only roughly know where it came from
private _srcPos = (getPosASL _src) vectorAdd [(random 16) - 8, (random 16) - 8, 0];
_grp reveal [_src, 1];
if ((_grp getVariable ["SAI_state", ""]) == "AMBUSH") exitWith { [_grp, ASLToAGL _srcPos] call SAI_fnc_ambushSpring };

if (_unit getVariable ["SAI_busyUntil", 0] > _now) exitWith {
    // Busy (flanking, healing...): just hug the ground for a moment if it is really heavy
    if (_supp > 0.8 && {unitPos _unit != "DOWN"}) then {
        _unit setUnitPos "DOWN";
        _unit spawn { sleep (2 + random 2); if (alive _this) then { _this setUnitPos "AUTO" } };
    };
};

if (SAI_cover && {_supp > 0.25}) then {
    [_unit, _srcPos] spawn SAI_fnc_takeCover;
};

// Return fire: a groupmate who is not busy suppresses the shooter's area
if (SAI_suppression && {combatMode _grp in ["YELLOW", "RED"]} && {_now > _grp getVariable ["SAI_nextReturnFire", 0]}) then {
    private _buddies = ((units _grp) - [_unit]) select {
        alive _x && {vehicle _x == _x} && {(_x getVariable ["SAI_busyUntil", 0]) < _now} && {_x distance _unit < 50}
    };
    if (_buddies isNotEqualTo []) then {
        _grp setVariable ["SAI_nextReturnFire", _now + 6 + random 4];
        private _mgs = _buddies select { [_x] call SAI_fnc_isMG };
        [selectRandom ([_buddies, _mgs] select (_mgs isNotEqualTo [])), _srcPos] spawn SAI_fnc_suppressFire;
    };
};
