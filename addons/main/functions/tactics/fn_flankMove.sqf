/* SAI_fnc_flankMove (spawn) - manoeuvre team: move to the flank point, then assault */
params ["_team", "_fp", "_ePos", "_grp"];
{
    _x setVariable ["SAI_busyUntil", time + 100];
    _x setUnitPos "AUTO";
    _x doMove (_fp getPos [2 + random 6, random 360]);
} forEach _team;

private _timeout = time + 75;
waitUntil {
    sleep 1;
    private _alive = _team select {alive _x};
    _alive isEqualTo []
    || {time > _timeout}
    || {({_x distance2D _fp < 15} count _alive) >= ((count _alive) / 2)}
};

// Assault from the flank toward the most recent known enemy position
private _target = _grp getVariable ["SAI_lastEnemyPos", _ePos];
{
    if (alive _x) then {
        _x setVariable ["SAI_busyUntil", time + 30];
        _x doMove (_target getPos [random 10, random 360]);
    };
} forEach _team;
sleep 25;

{
    if (alive _x) then {
        _x setVariable ["SAI_busyUntil", 0];
        _x assignTeam "MAIN";
        if (leader _x != _x) then { _x doFollow leader _x };
    };
} forEach _team;
