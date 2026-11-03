/* SAI_fnc_isFriendlyNear - any friendly man within _radius of _posASL (grenade safety) */
params ["_side", "_posASL", ["_radius", 8]];
((ASLToAGL _posASL) nearEntities ["CAManBase", _radius]) findIf {
    alive _x && {(_side getFriend (side group _x)) >= 0.6}
} != -1
