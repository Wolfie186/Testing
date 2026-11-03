/*
    SAI_fnc_buddyAidCheck
    Picks the worst wounded man and someone to treat him (vanilla or ACE medical).
    If nobody can help, a conscious wounded man treats himself.
*/
params ["_grp", "_units", "_ePos"];
private _now = time;
if (_now < _grp getVariable ["SAI_nextAid", 0]) exitWith {};
_grp setVariable ["SAI_nextAid", _now + 6];

private _ace = SAI_hasACEMedical;
private _severity = if (_ace) then {
    { [_this] call SAI_fnc_aceIsWounded }
} else {
    { if (lifeState _this == "INCAPACITATED") then {3} else { [0, 2] select (damage _this > 0.3) } }
};
private _hasKit = if (_ace) then {
    { params ["_u"]; (["ACE_fieldDressing", "ACE_packingBandage", "ACE_elasticBandage", "ACE_quikclot", "ACE_epinephrine", "ACE_bloodIV", "ACE_plasmaIV", "ACE_salineIV"] findIf {_x in items _u}) != -1 }
} else {
    { params ["_u"]; ("FirstAidKit" in items _u) || {"Medikit" in items _u} }
};

private _wounded = [];
{
    if (vehicle _x == _x && {!(_x getVariable ["SAI_beingTreated", false])}) then {
        private _s = _x call _severity;
        if (_s > 0) then { _wounded pushBack [-_s, _x distance (leader _grp), _x] };
    };
} forEach _units;
if (_wounded isEqualTo []) exitWith {};
_wounded sort true;
private _w = _wounded select 0 select 2;
private _wSeverity = -(_wounded select 0 select 0);

private _medics = (_units - [_w]) select {
    vehicle _x == _x
    && {(_x getVariable ["SAI_busyUntil", 0]) < _now}
    && {lifeState _x != "INCAPACITATED"}
    && {(_x call _severity) < 2}
    && {_x checkAIFeature "PATH"}
    && {_x distance _w < SAI_aidRadius}
    && {[_x] call _hasKit || {[_w] call _hasKit}}
};

if (_medics isEqualTo []) exitWith {
    // Self aid: conscious, carrying supplies, not already busy
    if (SAI_selfAid && {lifeState _w != "INCAPACITATED"} && {[_w] call _hasKit} && {(_w getVariable ["SAI_busyUntil", 0]) < _now}) then {
        [_w, _w, AGLToASL _ePos] spawn SAI_fnc_buddyAid;
    };
};

private _sorted = _medics apply {
    [(_x distance _w) - ([0, 40] select (_x getUnitTrait "Medic")) - ([0, 20] select (_wSeverity >= 3)), _x]
};
_sorted sort true;
[_sorted select 0 select 1, _w, AGLToASL _ePos] spawn SAI_fnc_buddyAid;
