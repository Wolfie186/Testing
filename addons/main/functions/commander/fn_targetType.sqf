/* SAI_fnc_targetType - "armor" | "car" | "air" | "static" | "inf" */
params ["_t"];
switch (true) do {
    case (_t isKindOf "CAManBase"): {"inf"};
    case (_t isKindOf "Tank"); case (_t isKindOf "Wheeled_APC_F"): {"armor"};
    case (_t isKindOf "Air"): {"air"};
    case (_t isKindOf "StaticWeapon"): {"static"};
    default {"car"};
}
