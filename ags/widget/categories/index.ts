import { CategoryDef } from "../../lib/registry"
import Appearance from "./Appearance"
import Animations from "./Animations"
import Windows from "./Windows"
import Input from "./Input"
import Notifications from "./Notifications"
import Monitors from "./Monitors"     // Task 5
import Power from "./Power"
import Startup from "./Startup"       // Task 5
import DefaultApps from "./DefaultApps"

export const CATEGORIES: CategoryDef[] = [
    Appearance, Animations,               // Look & Feel
    Windows, Input, Notifications,        // Behavior
    Monitors, Power,                      // Hardware
    Startup, DefaultApps,                 // System
]
