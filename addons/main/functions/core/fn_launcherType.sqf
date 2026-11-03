/* SAI_fnc_launcherType - "AT", "AA" or "" for the unit's launcher (works with mod launchers via ammo config) */
params ["_unit"];
private _w = secondaryWeapon _unit;
if (_w == "") exitWith {""};
private _mags = secondaryWeaponMagazine _unit;
if (_mags isEqualTo []) then {
    private _compat = compatibleMagazines _w;
    _mags = (magazines _unit) select {_x in _compat};
};
if (_mags isEqualTo []) exitWith {""};
private _ammo = configFile >> "CfgAmmo" >> getText (configFile >> "CfgMagazines" >> (_mags select 0) >> "ammo");
if (getNumber (_ammo >> "airLock") >= 1) exitWith {"AA"};
"AT"
