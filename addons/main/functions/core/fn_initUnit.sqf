/* SAI_fnc_initUnit - skills and event handlers for one unit (on the machine where it is local) */
params ["_unit"];
if (_unit getVariable ["SAI_init", false]) exitWith {};
_unit setVariable ["SAI_init", true];
_unit setVariable ["SAI_group", group _unit];

if (SAI_applySkills && {!(_unit getVariable ["SAI_keepSkill", false])}) then { [_unit] call SAI_fnc_applySkill };

_unit addEventHandler ["Suppressed", { _this call SAI_fnc_onSuppressed }];
_unit addEventHandler ["Hit",        { _this call SAI_fnc_onHit }];
_unit addEventHandler ["Killed",     { _this call SAI_fnc_onKilled }];
_unit addEventHandler ["Local", {
    // unit moved to another machine (e.g. headless client): let that machine re-init it
    params ["_unit", "_isLocal"];
    if (!_isLocal) then { _unit setVariable ["SAI_init", false] };
}];
