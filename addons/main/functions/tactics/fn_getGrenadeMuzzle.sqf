/*
    SAI_fnc_getGrenadeMuzzle
    Finds a throwable muzzle for which the unit carries a frag (or smoke) grenade.
    Works with vanilla and most mod grenades (detected by ammo config, not class names).
*/
params ["_unit", ["_smoke", false]];
private _mags = magazines _unit;
if (_mags isEqualTo []) exitWith {""};
private _throw = configFile >> "CfgWeapons" >> "Throw";
private _result = "";
{
    private _muzzle = _x;
    private _muzMags = getArray (_throw >> _muzzle >> "magazines");
    {
        if (_result == "" && {_x in _mags}) then {
            private _ammo = getText (configFile >> "CfgMagazines" >> _x >> "ammo");
            private _cfg = configFile >> "CfgAmmo" >> _ammo;
            private _sim = toLower getText (_cfg >> "simulation");
            private _names = toLower (_x + _ammo);
            private _ok = if (_smoke) then {
                _sim == "shotsmokex" && {getNumber (_cfg >> "indirectHit") < 1}
                && {(["chemlight", "strobe", "irgrenade", "flare"] findIf {_x in _names}) == -1}
            } else {
                _sim == "shotgrenade" && {getNumber (_cfg >> "indirectHit") >= 4}
            };
            if (_ok) then { _result = _muzzle };
        };
    } forEach _muzMags;
    if (_result != "") exitWith {};
} forEach getArray (_throw >> "muzzles");
_result
