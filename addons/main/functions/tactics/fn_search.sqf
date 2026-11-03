/*
    SAI_fnc_search
    Contact lost: don't forget the enemy like vanilla AI - go check the
    last known position carefully.
*/
params ["_grp", "_pos"];
_grp setVariable ["SAI_searchUntil", time + 150];
_grp setBehaviour "AWARE";
_grp setSpeedMode "NORMAL";
private _wp = _grp addWaypoint [_pos, 20];
_wp setWaypointType "SAD";
_wp setWaypointCombatMode "RED";
_grp setCurrentWaypoint _wp;
_grp setVariable ["SAI_tempWPs", (_grp getVariable ["SAI_tempWPs", []]) + [_wp]];
["Group %1 searching last known enemy position", groupId _grp] call SAI_fnc_log;
