/* SAI_fnc_taskExec - start a commander task on the machine that owns the group (once per task) */
params ["_grp"];
private _task = _grp getVariable ["SAI_task", []];
if (_task isEqualTo []) exitWith {};
_task params ["_id", "_type", "_args"];
if ((_grp getVariable ["SAI_taskRunning", -1]) == _id) exitWith {};
_grp setVariable ["SAI_taskRunning", _id];
[_grp, _type, _args, _id] spawn SAI_fnc_taskRun;
