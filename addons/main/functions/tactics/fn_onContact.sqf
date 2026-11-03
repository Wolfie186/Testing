/*
    SAI_fnc_onContact
    First contact drill: switch to combat, machine gunners lay down fire,
    everybody else breaks for cover (staggered, not all at once).
*/
params ["_grp", "_units", "_ePos", "_canFire"];
private _leader = leader _grp;
_grp setBehaviour "COMBAT";
private _ePosASL = AGLToASL _ePos;
{
    private _u = _x;
    if (_u != _leader && {isNull objectParent _u} && {(_u getVariable ["SAI_busyUntil", 0]) < time}) then {
        if (_canFire && {SAI_suppression} && {[_u] call SAI_fnc_isMG}) then {
            [_u, _ePosASL] spawn SAI_fnc_suppressFire;
        } else {
            if (SAI_cover && {random 1 < 0.75}) then {
                [_u, _ePosASL, 0.3 + random 1.5] spawn SAI_fnc_takeCover;
            };
        };
    };
} forEach _units;
