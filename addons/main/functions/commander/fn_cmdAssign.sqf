/* SAI_fnc_cmdAssign (server) - give a group a task; the machine owning the group executes it */
params ["_grp", "_type", "_args", "_side"];
SAI_taskCounter = SAI_taskCounter + 1;
_grp setVariable ["SAI_task", [SAI_taskCounter, _type, _args, time], true];
(SAI_recentTasks getOrDefault [_side, [], true]) pushBack [_args select 0, time, _type];
["Commander %1: %2 -> %3", _side, _type, groupId _grp] call SAI_fnc_log;
