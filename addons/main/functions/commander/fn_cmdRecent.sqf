/* SAI_fnc_cmdRecent (server) - was a task of this type issued near this position recently? */
params ["_side", "_pos", "_type", ["_radius", 300], ["_window", 120]];
private _list = SAI_recentTasks getOrDefault [_side, [], true];
private _now = time;
SAI_recentTasks set [_side, _list select { (_now - (_x select 1)) < 600 }];
(_list findIf { (_x select 2) == _type && {(_now - (_x select 1)) < _window} && {((_x select 0) distance2D _pos) < _radius} }) != -1
