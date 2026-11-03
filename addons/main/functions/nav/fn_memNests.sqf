/* SAI_fnc_memNests - remembered enemy firing positions within _radius of _pos (last 10 minutes) */
params ["_side", "_pos", ["_radius", 400]];
private _nests = missionNamespace getVariable [format ["SAI_nests_%1", _side], []];
(_nests select { (time - (_x select 1)) < 600 && {((_x select 0) distance2D _pos) < _radius} }) apply { _x select 0 }
