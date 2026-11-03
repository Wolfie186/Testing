/*
    SAI_fnc_buddyAid (spawn)
    Smoke if the enemy is close, run to the wounded, treat (vanilla or ACE), rejoin.
    _medic == _wounded means self aid.
*/
params ["_medic", "_wounded", "_threatASL"];
private _self = _medic == _wounded;
_wounded setVariable ["SAI_beingTreated", true];
_medic setVariable ["SAI_busyUntil", time + 100];
_wounded setVariable ["SAI_busyUntil", time + 100];
if (lifeState _wounded != "INCAPACITATED") then { _wounded setUnitPos "DOWN" };

if (!_self) then {
    if (SAI_smoke && {(_wounded distance2D _threatASL) < 250}) then {
        private _smokePos = AGLToASL ((getPosATL _wounded) getPos [10, _wounded getDir _threatASL]);
        if ([_medic, _smokePos, true] call SAI_fnc_throwGrenade) then { sleep 2.5 };
        _medic setVariable ["SAI_busyUntil", time + 100];
    };
    _medic doMove (getPosATL _wounded);
    private _timeout = time + 30;
    waitUntil { sleep 0.5; !alive _medic || {!alive _wounded} || {_medic distance _wounded < 2.5} || {time > _timeout} };
};

if (alive _medic && {alive _wounded} && {_self || {_medic distance _wounded < 3}}) then {
    if (!_self) then { doStop _medic };
    if (SAI_hasACEMedical) then {
        [_medic, _wounded] call SAI_fnc_aceTreat;
    } else {
        if (_self) then { _medic action ["HealSoldierSelf", _medic] } else { _medic action ["HealSoldier", _wounded] };
        sleep 9;
    };
};

if (alive _wounded) then {
    _wounded setUnitPos "AUTO";
    _wounded setVariable ["SAI_beingTreated", false];
    _wounded setVariable ["SAI_busyUntil", 0];
};
if (alive _medic) then {
    _medic setVariable ["SAI_busyUntil", 0];
    if (!_self && {leader _medic != _medic}) then { _medic doFollow leader _medic };
};
