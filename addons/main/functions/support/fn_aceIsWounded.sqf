/*
    SAI_fnc_aceIsWounded
    Does this unit need treatment under ACE medical?
    Returns priority: 0 = fine, 1 = pain / low blood, 2 = bleeding, 3 = unconscious / cardiac arrest.
*/
params ["_unit"];
if (!alive _unit) exitWith {0};
if (_unit getVariable ["ace_medical_inCardiacArrest", false]) exitWith {3};
if (_unit getVariable ["ACE_isUnconscious", false]) exitWith {3};
if ((_unit getVariable ["ace_medical_woundBleeding", 0]) > 0) exitWith {2};
if ((_unit getVariable ["ace_medical_bloodVolume", 6]) < 5) exitWith {1};
if ((_unit getVariable ["ace_medical_pain", 0]) > 0.5) exitWith {1};
0
