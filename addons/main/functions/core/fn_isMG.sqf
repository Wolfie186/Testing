/* SAI_fnc_isMG - true if the unit carries a belt-fed / high-capacity primary weapon */
params ["_unit"];
private _mags = primaryWeaponMagazine _unit;
if (_mags isEqualTo []) exitWith {false};
getNumber (configFile >> "CfgMagazines" >> (_mags select 0) >> "count") >= 75
