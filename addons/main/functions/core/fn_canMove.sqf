/*
    SAI_fnc_canMove
    May Smart AI give this group new movement orders (search / reinforce / fall back)?
    Groups following mission waypoints are left alone when SAI_respectWaypoints is on.
    Opt out manually:  _grp setVariable ["SAI_noMove", true, true];
*/
params ["_grp"];
private _leader = leader _grp;
if (_grp getVariable ["SAI_noMove", false]) exitWith {false};
if !(_leader checkAIFeature "PATH") exitWith {false};
if (!SAI_respectWaypoints) exitWith {true};
private _wps = waypoints _grp;
private _cur = currentWaypoint _grp;
(_cur >= count _wps) || {(_wps select _cur) in (_grp getVariable ["SAI_tempWPs", []])}
