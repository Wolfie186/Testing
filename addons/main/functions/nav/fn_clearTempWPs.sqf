/* SAI_fnc_clearTempWPs - remove waypoints Smart AI added after the current one (never mission waypoints before it) */
params ["_grp"];
private _cur = currentWaypoint _grp;
for "_i" from ((count waypoints _grp) - 1) to (_cur max 1) step -1 do {
    deleteWaypoint [_grp, _i];
};
_grp setVariable ["SAI_tempWPs", []];
