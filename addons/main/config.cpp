#include "script_version.hpp"

class CfgPatches {
    class sai_main {
        name = "Smart AI";
        author = "wolfie186";
        url = "https://github.com/wolfie186/Testing";
        units[] = {};
        weapons[] = {};
        requiredVersion = 2.14;
        requiredAddons[] = {"A3_Functions_F", "A3_Characters_F", "A3_Weapons_F", "cba_main", "cba_settings", "cba_xeh"};
        version = MAJOR.MINOR;
        versionStr = "1.0.0";
        versionAr[] = {MAJOR, MINOR, PATCHLVL};
    };
};

class Extended_PreInit_EventHandlers {
    class sai_main {
        init = "call compileScript ['\z\sai\addons\main\XEH_preInit.sqf']";
    };
};

class CfgFunctions {
    class SAI {
        tag = "SAI";

        class core {
            file = "\z\sai\addons\main\functions\core";
            class settings {};
            class init {};
            class loop {};
            class isValidGroup {};
            class initGroup {};
            class initUnit {};
            class applySkill {};
            class groupBrain {};
            class knownEnemies {};
            class canMove {};
            class isMG {};
            class isFriendlyNear {};
        };

        class tactics {
            file = "\z\sai\addons\main\functions\tactics";
            class onSuppressed {};
            class onHit {};
            class onKilled {};
            class onContact {};
            class findCover {};
            class takeCover {};
            class suppressFire {};
            class flank {};
            class flankMove {};
            class grenadeCheck {};
            class getGrenadeMuzzle {};
            class throwGrenade {};
            class fallback {};
            class search {};
            class vehicleBrain {};
        };

        class support {
            file = "\z\sai\addons\main\functions\support";
            class shareIntel {};
            class receiveIntel {};
            class requestReinforcements {};
            class handleReinforceRequest {};
            class buddyAidCheck {};
            class buddyAid {};
            class aceIsWounded {};
            class aceTreat {};
        };

        class debug {
            file = "\z\sai\addons\main\functions\debug";
            class debugMarker {};
            class debugTest {};
            class log {};
        };
    };
};
