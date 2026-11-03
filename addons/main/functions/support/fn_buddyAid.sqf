/* SAI_fnc_buddyAid (spawn) - smoke if needed, run to the wounded, heal, rejoin */
params ["_medic", "_wounded", "_threatASL"];
_wounded setVariable ["SAI_beingTreated", true];
_medic setVariable ["SAI_busyUntil", time + 45];
_wounded setVariable ["SAI_busyUntil", time + 45];
_wounded setUnitPos "DOWN";

if (SAI_smoke && {(_wounded distance2D _threatASL) < 250}) then {
    private _smokePos = AGLToASL ((getPosATL _wounded) getPos [10, _wounded getDir _threatASL]);
    [_medic, _smokePos, true] call SAI_fnc_throwGrenade;
    sleep 2.5;
    _medic setVariable ["SAI_busyUntil", time + 45];
};

_medic doMove (getPosATL _wounded);
private _timeout = time + 30;
waitUntil { sleep 0.5; !alive _medic || {!alive _wounded} || {_medic distance _wounded < 2.5} || {time > _timeout} };

if (alive _medic && {alive _wounded} && {_medic distance _wounded < 3}) then {
    doStop _medic;
    _medic action ["HealSoldier", _wounded];
    sleep 9;
};
if (alive _wounded) then { _wounded setUnitPos "AUTO"; _wounded setVariable ["SAI_beingTreated", false]; _wounded setVariable ["SAI_busyUntil", 0] };
if (alive _medic) then { _medic setVariable ["SAI_busyUntil", 0]; if (leader _medic != _medic) then { _medic doFollow leader _medic } };
