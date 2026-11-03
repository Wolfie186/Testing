/*
    SAI_fnc_isValidGroup
    True if the group should be controlled by Smart AI on this machine.
    Mission makers can opt a group out with:  _grp setVariable ["SAI_disable", true, true];
*/
params [["_grp", grpNull, [grpNull]]];
if (isNull _grp || {!local _grp}) exitWith {false};
private _leader = leader _grp;
!isNull _leader
&& {alive _leader}
&& {side _grp in [west, east, independent]}
&& {!(_grp getVariable ["SAI_disable", false])}
&& {behaviour _leader != "CARELESS"}
&& {(units _grp) findIf {isPlayer _x} == -1}
