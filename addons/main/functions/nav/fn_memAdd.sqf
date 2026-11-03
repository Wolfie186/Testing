/*
    SAI_fnc_memAdd
    A unit of _side died at _victimPos, shot from _shooterPos.
    Every machine remembers it: the place becomes "dangerous ground" for pathing,
    and the shooter's position becomes a suspected enemy firing position.
*/
params ["_side", "_victimPos", "_shooterPos"];
if (isMultiplayer) then {
    [_side, _victimPos, _shooterPos] remoteExecCall ["SAI_fnc_memApply", 0];
} else {
    [_side, _victimPos, _shooterPos] call SAI_fnc_memApply;
};
