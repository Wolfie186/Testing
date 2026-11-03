/*
    SAI_fnc_throwGrenade
    Throws a frag (or smoke) grenade at a position. Never throws a frag near friendlies.
    Returns true if a throw was started.
*/
params ["_unit", "_posASL", ["_smoke", false]];
if (!alive _unit || {vehicle _unit != _unit} || {lifeState _unit == "INCAPACITATED"}) exitWith {false};
private _muzzle = [_unit, _smoke] call SAI_fnc_getGrenadeMuzzle;
if (_muzzle == "") exitWith {false};
if (!_smoke && {[side group _unit, _posASL, 10] call SAI_fnc_isFriendlyNear}) exitWith {false};

_unit setVariable ["SAI_busyUntil", time + 5];
[_unit, _posASL, _muzzle] spawn {
    params ["_unit", "_posASL", "_muzzle"];
    private _d = _unit distance2D _posASL;
    // aim above the target so the throw arcs over cover
    _unit doWatch (ASLToAGL (_posASL vectorAdd [0, 0, (_d * 0.35) min 12]));
    sleep 1.2;
    if (alive _unit && {lifeState _unit != "INCAPACITATED"}) then {
        _unit forceWeaponFire [_muzzle, _muzzle];
    };
    sleep 1.5;
    if (alive _unit) then { _unit doWatch objNull };
    _unit setVariable ["SAI_busyUntil", 0];
};
true
