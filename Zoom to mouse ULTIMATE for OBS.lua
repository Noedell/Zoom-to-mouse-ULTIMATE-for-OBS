local obs = obslua
-- Compatibility wrappers for OBS versions where *_get_info/*_set_info were renamed to *_get_info2/*_set_info2
sceneitem_get_info = obs.obs_sceneitem_get_info2 or obs.obs_sceneitem_get_info
sceneitem_set_info = obs.obs_sceneitem_set_info2 or obs.obs_sceneitem_set_info
sceneitem_get_crop = obs.obs_sceneitem_get_crop
sceneitem_set_crop = obs.obs_sceneitem_set_crop

local ffi = require("ffi")
local VERSION = "1.0+"

local UI_TOOLTIPS = {
    hold_to_zoom = "When enabled: hold the Zoom hotkey to stay zoomed in; release to zoom out. When disabled: the Zoom hotkey toggles zoom in/out.",
    zoom_value = "How much to zoom in. Example: 1.50 = 150% zoom. Higher values zoom closer but show less of the screen.",
    zoom_speed_in = "Zoom-in speed. Lower values are slower and smoother. For calm tutorial footage start around 0.30–0.60 in this build.",
    zoom_speed_out = "Zoom-out speed. Lower values are slower and smoother. For calm tutorial footage start around 0.25–0.55 in this build.",
    easing_preset = "Zoom-in easing curve. Controls acceleration and deceleration during zoom-in.",
    zoom_out_easing = "Zoom-out easing curve. Controls acceleration and deceleration during zoom-out.",

    enable_closeup_zoom = "Enable an extra zoom level called Close-up. Use its hotkey to zoom further than the normal zoom. If disabled, the Close-up hotkey does nothing.",
    closeup_extra_multiplier = "How much extra zoom Close-up adds compared to normal zoom. Example: if Zoom Factor is 1.50 and Close-up multiplier is 1.50, Close-up becomes 2.25 (1.50 × 1.50).",
    enable_macro_zoom = "Enable an extra zoom level called Macro. Use its hotkey to zoom even further than Close-up. If disabled, the Macro hotkey does nothing.",
    macro_extra_multiplier = "How much extra zoom Macro adds compared to normal zoom. Example: if Zoom Factor is 1.50 and Macro multiplier is 2.25, Macro becomes 3.38 (1.50 × 2.25).",

    enable_nano_zoom = "Enable an extra zoom level called Nano. Use its hotkey to zoom further than Macro. If disabled, the Nano hotkey does nothing.",
    nano_extra_multiplier = "How much extra zoom Nano adds compared to normal zoom. Example: if Zoom Factor is 1.50 and Nano multiplier is 3.00, Nano becomes 4.50 (1.50 × 3.00).",
    enable_pico_zoom = "Enable an extra zoom level called Pico. Use its hotkey to zoom further than Nano. If disabled, the Pico hotkey does nothing.",
    pico_extra_multiplier = "How much extra zoom Pico adds compared to normal zoom. Example: if Zoom Factor is 1.50 and Pico multiplier is 4.00, Pico becomes 6.00 (1.50 × 4.00).",
    follow_speed = "How quickly the camera follows the cursor while zoomed in. Lower values follow more slowly and feel smoother. Higher values follow more aggressively.",
    jelly_follow_strength = "Adds extra averaging to the camera movement while following the cursor. This reduces jitter near edges and makes movement feel like smooth jelly. Higher values add more delay, but the script will still try to keep the cursor inside the view.",
    follow_border = "Defines a safe margin inside the zoomed view. When the cursor moves toward the edge by this amount, the camera starts panning again. Higher values mean the cursor can move closer to the edge before the camera follows.",
    follow_safezone_sensitivity = "When following, the camera will stop moving once it is close enough to the target. Lower values reduce jitter and make it lock sooner. Higher values keep micro-adjusting longer.",
    adaptive_smoothing_enabled = "Adds extra smoothing when the cursor movement is small, and speeds up slightly when movement is large. This helps reduce jitter without feeling laggy.",
    adaptive_smoothing_strength = "Strength of adaptive smoothing. Higher values smooth more but can feel less responsive. Start around 0.40–0.70.",
    smart_prediction_enabled = "Predicts the cursor movement slightly to reduce perceived lag while following. Can look unnatural in some cases, so it can be disabled.",

}
-- Safety stubs: these are overwritten by real implementations later in the file.
if detect_platform_status == nil then
    function detect_platform_status() end
end
if platform_status_line_1 == nil then
    function platform_status_line_1() return "OS: unknown | OBS: unknown | Session: unknown" end
end
if platform_status_line_2 == nil then
    function platform_status_line_2() return "Cursor backend: unknown | Status: unknown" end
end
if platform_status_line_3 == nil then
    function platform_status_line_3() return "Warnings: unknown" end

if log_platform_warnings_once == nil then
    function log_platform_warnings_once() end
end
end

local CROP_FILTER_NAME = "obs-zoom-to-mouse-crop"

source_name = ""
source = nil
sceneitem = nil
sceneitem_info_orig = nil
sceneitem_crop_orig = nil
sceneitem_info = nil
sceneitem_crop = nil
crop_filter = nil
crop_filter_temp = nil
crop_filter_settings = nil
crop_filter_info_orig = { x = 0, y = 0, w = 0, h = 0 }
crop_filter_info = { x = 0, y = 0, w = 0, h = 0 }
crop_last_applied = { left = nil, top = nil, cx = nil, cy = nil }

monitor_info = nil
zoom_info = {
    source_size = { width = 0, height = 0 },
    source_crop = { x = 0, y = 0, w = 0, h = 0 },
    source_crop_filter = { x = 0, y = 0, w = 0, h = 0 },
    zoom_to = 2
}
zoom_time = 0
zoom_target = nil
locked_center = nil
locked_last_pos = nil
hotkey_zoom_id = nil
hotkey_follow_id = nil
hotkey_hold_zoom_id = nil
hotkey_hold_closeup_id = nil
hotkey_hold_macro_id = nil
hotkey_hold_nano_id = nil
hotkey_hold_pico_id = nil
hold_hotkey_active_level = nil

is_timer_running = false

timer_error_logged = false
win_point = nil
x11_display = nil
x11_root = nil
x11_mouse = nil
osx_lib = nil
osx_nsevent = nil
osx_mouse_location = nil

use_auto_follow_mouse = true
use_follow_outside_bounds = false
is_following_mouse = false
follow_speed = 0.1

jelly_follow_strength = 0.0
jelly_follow_tau_min = 0.00
jelly_follow_tau_max = 0.40
jelly_follow_state = nil

adaptive_smoothing_enabled = true
adaptive_smoothing_strength = 0.60
adaptive_smoothing_min = 0.06
adaptive_smoothing_max = 0.35

smart_prediction_enabled = true
smart_prediction_strength = 0.18
pred_last_mouse = nil
pred_vel = { x = 0.0, y = 0.0 }

click_sound_enabled = false
click_sound_source_name = "Click Sound"
click_sound_volume = 1.0
click_sound_warned = false

follow_border = 0
follow_safezone_sensitivity = 10
use_follow_auto_lock = false
zoom_value = 2
allow_all_sources = false
use_monitor_override = false
monitor_override_x = 0
monitor_override_y = 0
monitor_override_w = 0
monitor_override_h = 0
monitor_override_sx = 0
monitor_override_sy = 0
monitor_override_dw = 0
monitor_override_dh = 0
debug_logs = false

-- New optional settings (off by default)
mouse_smoothing = 0.0      -- 0..0.95 (0=off, higher=smoother)
hold_to_zoom = false       -- if true: press to zoom in, release to zoom out
hold_to_zoom_closeup = false  -- if true: press Close-up to zoom in, release to zoom out
hold_to_zoom_macro = false    -- if true: press Macro to zoom in, release to zoom out
hold_to_zoom_nano = false     -- if true: press Nano to zoom in, release to zoom out
hold_to_zoom_pico = false     -- if true: press Pico to zoom in, release to zoom out
-- Click effect (manual trigger via hotkey)
click_effect_enabled = true
click_effect_source_name = "Click Effect"
click_effect_type = 0 -- 0=Pulse, 1=Ripple, 2=Pop
click_effect_color = 0xFFFFFFFF -- AARRGGBB (used when the effect source is a Color Source)
click_effect_duration = 0.30 -- seconds
click_effect_max_scale = 2.2
click_effect_spin_degrees = 0 -- rotate during animation
click_effect_pulses = 1 -- for Radar/Ping styles
-- Spotlight overlay (requires an existing source in the scene)
spotlight_enabled = false
spotlight_source_name = "Spotlight Overlay"
spotlight_size = 420
spotlight_softness = 0.35
spotlight_follow = true
hotkey_spotlight_id = nil
spotlight_source = nil
spotlight_sceneitem = nil
spotlight_info_orig = nil
spotlight_visible_orig = nil

-- Cursor trail (requires N duplicate sources in the scene: 'Cursor Trail 1'..)
trail_enabled = false
trail_count = 6
trail_spacing = 0.04
trail_source_prefix = "Cursor Trail "
hotkey_trail_id = nil
trail_items = {}
trail_buf = {}

-- Cinematic easing presets
easing_preset = 0 -- 0=Classic,1=Cinematic,2=Snappy,3=EaseOut,4=Quint
follow_easing = 0 -- 0=Linear,1=EaseOut,2=EaseInOut


-- Per-zoom-level animation overrides (speed + easing)
closeup_zoom_speed_in = nil
closeup_zoom_speed_out = nil
closeup_zoom_easing_in = nil
closeup_zoom_easing_out = nil
macro_zoom_speed_in = nil
macro_zoom_speed_out = nil
macro_zoom_easing_in = nil
macro_zoom_easing_out = nil
nano_zoom_speed_in = nil
nano_zoom_speed_out = nil
nano_zoom_easing_in = nil
nano_zoom_easing_out = nil
pico_zoom_speed_in = nil
pico_zoom_speed_out = nil
pico_zoom_easing_in = nil
pico_zoom_easing_out = nil
current_zoom_anim_speed = nil
current_zoom_anim_easing = nil

-- Keyframe zoom positions
keyframes_text = ""
keyframes = {}
keyframe_index = 0
hotkey_keyframe_next_id = nil
hotkey_keyframe_prev_id = nil

-- Motion blur (optional; requires a filter plugin on Zoom Source)
motion_blur_enabled = false
motion_blur_filter_name = "Motion Blur"
hotkey_motion_blur_id = nil

-- Brand preset profiles (stored as Lua table text in settings)

hotkey_click_id = nil

click_effect_source = nil
click_effect_sceneitem = nil
click_effect_info_orig = nil
click_anim_active = false
click_anim_t = 0.0
click_visible_orig = nil


click_effect_warned = false
-- Internal state for smoothing/timing
mouse_filtered = nil
last_timer_ns = nil

ZoomState = {
    None = 0,
    ZoomingIn = 1,
    ZoomingOut = 2,
    ZoomedIn = 3,
}
zoom_state = ZoomState.None

version = obs.obs_get_version_string()
major = tonumber(version:match("(%d+%.%d+)")) or 0

-- Define the mouse cursor functions for each platform
if ffi.os == "Windows" then
    ffi.cdef([[
        typedef int BOOL;
        typedef struct{
            long x;
            long y;
        } POINT, *LPPOINT;
        BOOL GetCursorPos(LPPOINT);
    ]])
    win_point = ffi.new("POINT[1]")
elseif ffi.os == "Linux" then
    ffi.cdef([[
        typedef unsigned long XID;
        typedef XID Window;
        typedef void Display;
        Display* XOpenDisplay(char*);
        XID XDefaultRootWindow(Display *display);
        int XQueryPointer(Display*, Window, Window*, Window*, int*, int*, int*, int*, unsigned int*);
        int XCloseDisplay(Display*);
    ]])

    x11_lib = ffi.load("X11.so.6")
    x11_display = x11_lib.XOpenDisplay(nil)
    if x11_display ~= nil then
        x11_root = x11_lib.XDefaultRootWindow(x11_display)
        x11_mouse = {
            root_win = ffi.new("Window[1]"),
            child_win = ffi.new("Window[1]"),
            root_x = ffi.new("int[1]"),
            root_y = ffi.new("int[1]"),
            win_x = ffi.new("int[1]"),
            win_y = ffi.new("int[1]"),
            mask = ffi.new("unsigned int[1]")
        }
    end
elseif ffi.os == "OSX" then
    ffi.cdef([[
        typedef struct {
            double x;
            double y;
        } CGPoint;
        typedef void* SEL;
        typedef void* id;
        typedef void* Method;

        SEL sel_registerName(const char *str);
        id objc_getClass(const char*);
        Method class_getClassMethod(id cls, SEL name);
        void* method_getImplementation(Method);
        int access(const char *path, int amode);
    ]])

    osx_lib = ffi.load("libobjc")
    if osx_lib ~= nil then
        osx_nsevent = {
            class = osx_lib.objc_getClass("NSEvent"),
            sel = osx_lib.sel_registerName("mouseLocation")
        }
        method = osx_lib.class_getClassMethod(osx_nsevent.class, osx_nsevent.sel)
        if method ~= nil then
            imp = osx_lib.method_getImplementation(method)
            osx_mouse_location = ffi.cast("CGPoint(*)(void*, void*)", imp)
        end
    end
end

---
-- Logs a message to the OBS script console
---@param msg string
function log(msg)
    if debug_logs then
        obs.script_log(obs.OBS_LOG_INFO, msg)
    end


-- Platform / environment status (for UI + warnings)
local PLATFORM_STATUS = {
    os = ffi.os,
    obs_version = obs.obs_get_version_string(),
    obs_major = major,
    session_type = "",
    is_wayland = false,
    cursor_backend = "",
    cursor_backend_ok = true,
    warnings = {}
}

function detect_platform_status()
    PLATFORM_STATUS.warnings = {}
    PLATFORM_STATUS.os = ffi.os
    PLATFORM_STATUS.obs_version = obs.obs_get_version_string()
    PLATFORM_STATUS.obs_major = major
    PLATFORM_STATUS.session_type = (os.getenv("XDG_SESSION_TYPE") or ""):lower()
    local wayland_display = os.getenv("WAYLAND_DISPLAY") or ""
    PLATFORM_STATUS.is_wayland = (PLATFORM_STATUS.session_type == "wayland") or (wayland_display ~= "")

    if ffi.os == "Windows" then
        PLATFORM_STATUS.cursor_backend = "Win32 GetCursorPos"
        PLATFORM_STATUS.cursor_backend_ok = (win_point ~= nil)
    elseif ffi.os == "Linux" then
        PLATFORM_STATUS.cursor_backend = "X11 XQueryPointer"
        -- Under Wayland global cursor position is typically blocked; XQueryPointer may fail or give incorrect values.
        if PLATFORM_STATUS.is_wayland then
            PLATFORM_STATUS.cursor_backend_ok = false
            table.insert(PLATFORM_STATUS.warnings,
                "Linux Wayland detected: global cursor position is restricted. Cursor tracking features may not work. Use an X11 session for full functionality.")
        else
            PLATFORM_STATUS.cursor_backend_ok = (x11_display ~= nil and x11_root ~= nil and x11_mouse ~= nil)
            if not PLATFORM_STATUS.cursor_backend_ok then
                table.insert(PLATFORM_STATUS.warnings,
                    "Linux X11 cursor backend not initialized (XOpenDisplay failed). Cursor tracking may not work.")
            end
        end
    elseif ffi.os == "OSX" then
        PLATFORM_STATUS.cursor_backend = "macOS NSEvent mouseLocation"
        PLATFORM_STATUS.cursor_backend_ok = (osx_lib ~= nil and osx_nsevent ~= nil and osx_mouse_location ~= nil)
        -- macOS requires permissions for screen/cursor capture in many setups.
        table.insert(PLATFORM_STATUS.warnings,
            "macOS: ensure OBS has Screen Recording permission. For reliable cursor tracking, also allow Accessibility permission (System Settings → Privacy & Security).")
        if not PLATFORM_STATUS.cursor_backend_ok then
            table.insert(PLATFORM_STATUS.warnings,
                "macOS cursor backend not available (Objective-C bridge failed). Cursor tracking may not work.")
        end
    else
        PLATFORM_STATUS.cursor_backend = "Unknown"
        PLATFORM_STATUS.cursor_backend_ok = false
        table.insert(PLATFORM_STATUS.warnings, "Unknown OS: platform support is untested.")
    end
end

function platform_status_line_1()
    local st = PLATFORM_STATUS.session_type
    if st == "" then st = "unknown" end
    if ffi.os ~= "Linux" then st = "n/a" end
    return "OS: " .. tostring(PLATFORM_STATUS.os) ..
        " | OBS: " .. tostring(PLATFORM_STATUS.obs_version) ..
        " | Session: " .. st
end

function platform_status_line_2()
    return "Cursor backend: " .. tostring(PLATFORM_STATUS.cursor_backend) ..
        " | Status: " .. (PLATFORM_STATUS.cursor_backend_ok and "OK" or "LIMITED")
end

function platform_status_line_3()
    if PLATFORM_STATUS.warnings == nil or #PLATFORM_STATUS.warnings == 0 then
        return "Warnings: none"
    end
    return "Warnings: " .. tostring(#PLATFORM_STATUS.warnings) .. " (see Script Log / More info)"
end

local function log_platform_warnings_once()
    if PLATFORM_STATUS.warnings ~= nil and #PLATFORM_STATUS.warnings > 0 then
        for _, w in ipairs(PLATFORM_STATUS.warnings) do
            obs.script_log(obs.OBS_LOG_WARNING, "[obs-zoom-to-mouse] " .. w)
        end
    end
end

end

---
-- Format the given lua table into a string
function format_table(tbl, indent)
    if not indent then indent = 0 end
    str = "{ "
    for key, value in pairs(tbl) do
        tabs = string.rep("  ", indent + 1)
        if type(value) == "table" then
            str = str .. tabs .. key .. " = " .. format_table(value, indent + 1) .. ", "
        else
            str = str .. tabs .. key .. " = " .. tostring(value) .. ", "
        end
    end
    str = str .. string.rep("  ", indent) .. "}"
    return str
end

---
-- Linear interpolate between v0 and v1
function lerp(v0, v1, t)
    return v0 * (1 - t) + v1 * t
end

---
-- Ease a time value in and out
function ease_in_out(t)
    t = t * 2
    if t < 1 then
        return 0.5 * t * t * t
    else
        t = t - 2
        return 0.5 * (t * t * t + 2)
    end
end


-- Additional easing helpers (t in [0..1])
function ease_linear(t) return t end
function ease_in_quad(t) return t * t end
function ease_out_quad(t) return 1 - (1 - t) * (1 - t) end
function ease_in_out_quad(t) return (t < 0.5) and (2 * t * t) or (1 - math.pow(-2 * t + 2, 2) / 2) end

function ease_in_cubic(t) return t * t * t end
function ease_out_cubic2(t) return 1 - math.pow(1 - t, 3) end
function ease_in_out_cubic(t) return (t < 0.5) and (4 * t * t * t) or (1 - math.pow(-2 * t + 2, 3) / 2) end

function ease_in_quart(t) return t * t * t * t end
function ease_out_quart(t) return 1 - math.pow(1 - t, 4) end
function ease_in_out_quart(t) return (t < 0.5) and (8 * t * t * t * t) or (1 - math.pow(-2 * t + 2, 4) / 2) end

function ease_in_quint2(t) return t * t * t * t * t end
function ease_out_quint2(t) return 1 - math.pow(1 - t, 5) end
function ease_in_out_quint2(t) return (t < 0.5) and (16 * t * t * t * t * t) or (1 - math.pow(-2 * t + 2, 5) / 2) end

function ease_in_expo(t) return (t == 0) and 0 or math.pow(2, 10 * t - 10) end
function ease_out_expo(t) return (t == 1) and 1 or (1 - math.pow(2, -10 * t)) end
function ease_in_out_expo(t)
    if t == 0 then return 0 end
    if t == 1 then return 1 end
    return (t < 0.5) and (math.pow(2, 20 * t - 10) / 2) or ((2 - math.pow(2, -20 * t + 10)) / 2)
end

function ease_in_circ(t) return 1 - math.sqrt(1 - t * t) end
function ease_out_circ(t) return math.sqrt(1 - math.pow(t - 1, 2)) end
function ease_in_out_circ(t)
    return (t < 0.5) and ((1 - math.sqrt(1 - math.pow(2 * t, 2))) / 2) or ((math.sqrt(1 - math.pow(-2 * t + 2, 2)) + 1) / 2)
end

function ease_out_back(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
end

function ease_out_bounce(t)
    local n1 = 7.5625
    local d1 = 2.75
    if t < 1 / d1 then
        return n1 * t * t
    elseif t < 2 / d1 then
        t = t - 1.5 / d1
        return n1 * t * t + 0.75
    elseif t < 2.5 / d1 then
        t = t - 2.25 / d1
        return n1 * t * t + 0.9375
    else
        t = t - 2.625 / d1
        return n1 * t * t + 0.984375
    end
end

-- Map easing id -> eased value
-- Note: we keep ids stable so older configs don't break too badly.
function ease_by_id(id, t)
    t = clamp(0, 1, t)
    if id == 0 then return ease_linear(t) end
    if id == 1 then return ease_in_out_quint2(t) end          -- Cinematic (default)
    if id == 2 then return ease_out_cubic2(t) end             -- Snappy
    if id == 3 then return ease_out_quad(t) end               -- Ease-out
    if id == 4 then return ease_in_out_cubic(t) end           -- Classic cubic
    if id == 5 then return ease_in_out_quad(t) end            -- Smooth (quad)
    if id == 6 then return ease_in_out_quart(t) end           -- Heavy (quart)
    if id == 7 then return ease_in_out_expo(t) end            -- Dramatic (expo)
    if id == 8 then return ease_in_out_circ(t) end            -- Circular
    if id == 9 then return ease_out_back(t) end               -- Overshoot
    if id == 10 then return ease_out_bounce(t) end            -- Bounce-out
    return ease_in_out(t)
end

-- Populate an OBS list property with available zoom easing curves (ids map to ease_by_id)
function add_zoom_easing_items(list_prop)
    if list_prop == nil then return end
    -- We keep ids stable; labels are user-facing.
    obs.obs_property_list_add_int(list_prop, "Linear", 0)
    obs.obs_property_list_add_int(list_prop, "Cinematic", 1)
    obs.obs_property_list_add_int(list_prop, "Snappy", 2)
    obs.obs_property_list_add_int(list_prop, "Ease-out", 3)
    obs.obs_property_list_add_int(list_prop, "Classic cubic", 4)
    obs.obs_property_list_add_int(list_prop, "Smooth", 5)
    obs.obs_property_list_add_int(list_prop, "Heavy", 6)
    obs.obs_property_list_add_int(list_prop, "Dramatic", 7)
    obs.obs_property_list_add_int(list_prop, "Circular", 8)
    obs.obs_property_list_add_int(list_prop, "Overshoot", 9)
    obs.obs_property_list_add_int(list_prop, "Bounce-out", 10)
end

function ease_out_cubic(t)
    return 1 - ((1 - t) * (1 - t) * (1 - t))
end

function ease_in_out_quint(t)
    if t < 0.5 then
        return 16 * t * t * t * t * t
    else
        f = (2 * t) - 2
        return 0.5 * f * f * f * f * f + 1
    end
end

function ease_preset_value(t, preset)
    local p = preset
    if p == nil then p = easing_preset end

    if p == 0 then
        return ease_in_out(t)
    elseif p == 1 then
        return ease_in_out_quint(t)
    elseif p == 2 then
        return ease_out_cubic(t)
    elseif p == 3 then
        return ease_out_cubic(t)
    else
        return ease_in_out_quint(t)
    end
end

function ease_preset_value_out(t, preset)
    local p = preset
    if p == nil then p = zoom_out_easing end

    if p == 0 then
        return ease_in_out(t)
    elseif p == 1 then
        return ease_in_out_quint(t)
    elseif p == 2 then
        return ease_out_cubic(t)
    elseif p == 3 then
        return ease_out_cubic(t)
    else
        return ease_in_out_quint(t)
    end
end

function follow_ease_value(t)
    if follow_easing == 0 then return t end
    if follow_easing == 1 then return ease_out_cubic(t) end
    return ease_in_out(t)
end

---
-- Clamps a given value between min and max
function clamp(min, max, value)
    return math.max(min, math.min(max, value))
end

---
-- Best-effort time in ns
local function now_ns()
    if obs.os_gettime_ns then
        return obs.os_gettime_ns()
    end
    return math.floor(os.clock() * 1e9)
end

---
-- Get the current mouse position
---@return table
function get_mouse_pos()
    mouse = { x = 0, y = 0 }

    if ffi.os == "Windows" then
        if win_point and ffi.C.GetCursorPos(win_point) ~= 0 then
            mouse.x = win_point[0].x
            mouse.y = win_point[0].y
        end
    elseif ffi.os == "Linux" then
        if x11_lib ~= nil and x11_display ~= nil and x11_root ~= nil and x11_mouse ~= nil then
            if x11_lib.XQueryPointer(x11_display, x11_root, x11_mouse.root_win, x11_mouse.child_win,
                    x11_mouse.root_x, x11_mouse.root_y, x11_mouse.win_x, x11_mouse.win_y, x11_mouse.mask) ~= 0 then
                mouse.x = tonumber(x11_mouse.win_x[0])
                mouse.y = tonumber(x11_mouse.win_y[0])
            end
        end
    elseif ffi.os == "OSX" then
        if osx_lib ~= nil and osx_nsevent ~= nil and osx_mouse_location ~= nil then
            point = osx_mouse_location(osx_nsevent.class, osx_nsevent.sel)
            mouse.x = point.x
            if monitor_info ~= nil then
                if monitor_info.display_height > 0 then
                    mouse.y = monitor_info.display_height - point.y
                else
                    mouse.y = monitor_info.height - point.y
                end
            end
        end
    end

    -- Optional smoothing in desktop coordinates
    if mouse_smoothing and mouse_smoothing > 0 then
        if mouse_filtered == nil then
            mouse_filtered = { x = mouse.x, y = mouse.y }
        else
            alpha = clamp(0.01, 1.0, 1.0 - mouse_smoothing)
            mouse_filtered.x = lerp(mouse_filtered.x, mouse.x, alpha)
            mouse_filtered.y = lerp(mouse_filtered.y, mouse.y, alpha)
        end
        return { x = mouse_filtered.x, y = mouse_filtered.y }
    end

    return mouse
end

---
-- Get the information about display capture sources for the current platform
function get_dc_info()
    if ffi.os == "Windows" then
        return { source_id = "monitor_capture", prop_id = "monitor_id", prop_type = "string" }
    elseif ffi.os == "Linux" then
        return { source_id = "xshm_input", prop_id = "screen", prop_type = "int" }
    elseif ffi.os == "OSX" then
        if major > 29.0 then
            return { source_id = "screen_capture", prop_id = "display_uuid", prop_type = "string" }
        else
            return { source_id = "display_capture", prop_id = "display", prop_type = "int" }
        end
    end
    return nil
end

---
-- Check to see if the specified source is a display capture source
-- FIXED: previously returned true for any source when allow_all_sources=false
function is_display_capture(source_to_check)
    if source_to_check == nil then return false end
    dc_info = get_dc_info()
    if dc_info == nil then return false end
    source_type = obs.obs_source_get_id(source_to_check)
    return source_type == dc_info.source_id
end

---
-- Get the size and position of the monitor so that we know the top-left mouse point
function get_monitor_info(source_to_use)
    info = nil

    if is_display_capture(source_to_use) and not use_monitor_override then
        dc_info = get_dc_info()
        if dc_info ~= nil then
            props = obs.obs_source_properties(source_to_use)
            if props ~= nil then
                monitor_id_prop = obs.obs_properties_get(props, dc_info.prop_id)
                if monitor_id_prop then
                    found = nil
                    settings = obs.obs_source_get_settings(source_to_use)
                    if settings ~= nil then
                        local to_match
                        if dc_info.prop_type == "string" then
                            to_match = obs.obs_data_get_string(settings, dc_info.prop_id)
                        elseif dc_info.prop_type == "int" then
                            to_match = obs.obs_data_get_int(settings, dc_info.prop_id)
                        end

                        item_count = obs.obs_property_list_item_count(monitor_id_prop)
                        for i = 0, item_count do
                            name = obs.obs_property_list_item_name(monitor_id_prop, i)
                            local value
                            if dc_info.prop_type == "string" then
                                value = obs.obs_property_list_item_string(monitor_id_prop, i)
                            elseif dc_info.prop_type == "int" then
                                value = obs.obs_property_list_item_int(monitor_id_prop, i)
                            end

                            if value == to_match then
                                found = name
                                break
                            end
                        end
                        obs.obs_data_release(settings)
                    end

                    if found then
                        log("Parsing display name: " .. found)
                        local x, y = found:match("(-?%d+),(-?%d+)")
                        local width, height = found:match("(%d+)x(%d+)")

                        info = { x = 0, y = 0, width = 0, height = 0 }
                        info.x = tonumber(x, 10)
                        info.y = tonumber(y, 10)
                        info.width = tonumber(width, 10)
                        info.height = tonumber(height, 10)
                        info.scale_x = 1
                        info.scale_y = 1
                        info.display_width = info.width
                        info.display_height = info.height

                        log("Parsed the following display information " .. format_table(info))

                        if info.width == 0 and info.height == 0 then
                            info = nil
                        end
                    end
                end

                obs.obs_properties_destroy(props)
            end
        end
    end

    if use_monitor_override then
        info = {
            x = monitor_override_x,
            y = monitor_override_y,
            width = monitor_override_w,
            height = monitor_override_h,
            scale_x = monitor_override_sx,
            scale_y = monitor_override_sy,
            display_width = monitor_override_dw,
            display_height = monitor_override_dh
        }
    end

    if not info then
        log("WARNING: Could not auto calculate zoom source position and size. " ..
            "         Try using the 'Set manual source position' option and adding override values")
    end

    return info
end

---
-- Releases the current sceneitem and resets data back to default
function release_sceneitem()
    if is_timer_running then
        obs.timer_remove(on_timer)
        is_timer_running = false
    end

    zoom_state = ZoomState.None
    zoom_time = 0
    zoom_target = nil
    locked_center = nil
    locked_last_pos = nil
    last_timer_ns = nil
    crop_last_applied = { left = nil, top = nil, cx = nil, cy = nil }
    mouse_filtered = nil

    if sceneitem ~= nil then
if not sceneitem_get_info or not sceneitem_set_info then
    obs.script_log(obs.OBS_LOG_ERROR,
        "[obs-better-zoom-to-mouse] Your OBS build does not expose sceneitem get/set info functions to Lua (expected obs_sceneitem_get_info2/obs_sceneitem_set_info2).")
    return
end

        if crop_filter ~= nil and source ~= nil then
            log("Zoom crop filter removed")
            obs.obs_source_filter_remove(source, crop_filter)
            obs.obs_source_release(crop_filter)
            crop_filter = nil
        end

        if crop_filter_temp ~= nil and source ~= nil then
            log("Conversion crop filter removed")
            obs.obs_source_filter_remove(source, crop_filter_temp)
            obs.obs_source_release(crop_filter_temp)
            crop_filter_temp = nil
        end

        if crop_filter_settings ~= nil then
            obs.obs_data_release(crop_filter_settings)
            crop_filter_settings = nil
        end

        if sceneitem_info_orig ~= nil then
            log("Transform info reset back to original")
            sceneitem_get_info(sceneitem, sceneitem_info_orig)
            sceneitem_info_orig = nil
        end

        if sceneitem_crop_orig ~= nil then
            log("Transform crop reset back to original")
            obs.obs_sceneitem_set_crop(sceneitem, sceneitem_crop_orig)
            sceneitem_crop_orig = nil
        end

        obs.obs_sceneitem_release(sceneitem)
        sceneitem = nil
    end

    if source ~= nil then
        obs.obs_source_release(source)
        source = nil
    end
end

---
-- Updates the current sceneitem with a refreshed set of data from the source

---
-- Apply crop/pad filter settings for our zoom filter
-- (Fix) This function was missing in some builds; on_timer() calls it.
function set_crop_settings(crop)
    if crop_filter ~= nil and crop_filter_settings ~= nil then
        left = math.floor(crop.x)
        top = math.floor(crop.y)
        cx = math.floor(crop.w)
        cy = math.floor(crop.h)

        -- Avoid redundant updates (can be expensive and spam logs if something goes wrong)
        if crop_last_applied ~= nil then
            if crop_last_applied.left == left and crop_last_applied.top == top and crop_last_applied.cx == cx and crop_last_applied.cy == cy then
                return
            end
            crop_last_applied.left = left
            crop_last_applied.top  = top
            crop_last_applied.cx   = cx
            crop_last_applied.cy   = cy
        end

        obs.obs_data_set_int(crop_filter_settings, "left", left)
        obs.obs_data_set_int(crop_filter_settings, "top", top)
        obs.obs_data_set_int(crop_filter_settings, "cx", cx)
        obs.obs_data_set_int(crop_filter_settings, "cy", cy)
        obs.obs_source_update(crop_filter, crop_filter_settings)
    end
end


local function find_sceneitem_in_current_scene(target_name)
    scene_source = obs.obs_frontend_get_current_scene()
    if scene_source == nil then return nil end

    local function bfs(root_scene)
        queue = {}
        table.insert(queue, root_scene)

        while #queue > 0 do
            s = table.remove(queue, 1)

            found = obs.obs_scene_find_source(s, target_name)
            if found ~= nil then
                obs.obs_sceneitem_addref(found)
                return found
            end

            all_items = obs.obs_scene_enum_items(s)
            if all_items then
                for _, item in pairs(all_items) do
                    nested = obs.obs_sceneitem_get_source(item)
                    if nested ~= nil and obs.obs_source_is_scene(nested) then
                        nested_scene = obs.obs_scene_from_source(nested)
                        table.insert(queue, nested_scene)
                    end
                end
                obs.sceneitem_list_release(all_items)
            end
        end
        return nil
    end

    current = obs.obs_scene_from_source(scene_source)
    item = bfs(current)
    obs.obs_source_release(scene_source)
    return item
end


function refresh_sceneitem(find_newest)
    source_raw = { width = 0, height = 0 }

    if find_newest then
        release_sceneitem()

        if source_name == "obs-zoom-to-mouse-none" then
            return
        end

        log("Finding sceneitem for Zoom Source '" .. source_name .. "'")
        if source_name ~= nil then
            source = obs.obs_get_source_by_name(source_name)
            if source ~= nil then
                source_raw.width = obs.obs_source_get_width(source)
                source_raw.height = obs.obs_source_get_height(source)

                scene_source = obs.obs_frontend_get_current_scene()
                if scene_source ~= nil then
                    local function find_scene_item_by_name(root_scene)
                        queue = {}
                        table.insert(queue, root_scene)

                        while #queue > 0 do
                            s = table.remove(queue, 1)
                            log("Looking in scene '" .. obs.obs_source_get_name(obs.obs_scene_get_source(s)) .. "'")

                            found = obs.obs_scene_find_source(s, source_name)
                            if found ~= nil then
                                log("Found sceneitem '" .. source_name .. "'")
                                obs.obs_sceneitem_addref(found)
                                return found
                            end

                            all_items = obs.obs_scene_enum_items(s)
                            if all_items then
                                for _, item in pairs(all_items) do
                                    nested = obs.obs_sceneitem_get_source(item)
                                    if nested ~= nil and obs.obs_source_is_scene(nested) then
                                        nested_scene = obs.obs_scene_from_source(nested)
                                        table.insert(queue, nested_scene)
                                    end
                                end
                                obs.sceneitem_list_release(all_items)
                            end
                        end

                        return nil
                    end

                    current = obs.obs_scene_from_source(scene_source)
                    sceneitem = find_scene_item_by_name(current)

                    obs.obs_source_release(scene_source)
                end

                if not sceneitem then
                    log("WARNING: Source not part of the current scene hierarchy. " ..
                        "         Try selecting a different zoom source or switching scenes.")
                    if source ~= nil then obs.obs_source_release(source) end
                    sceneitem = nil
                    source = nil
                    return
                end
            end
        end
    end

    if not monitor_info then
        monitor_info = get_monitor_info(source)
    end

    is_non_display_capture = (source ~= nil) and (not is_display_capture(source))
    if is_non_display_capture then
        if not use_monitor_override then
            log("ERROR: Selected Zoom Source is not a display capture source. " ..
                "       You MUST enable 'Set manual source position' and set the correct override values for size and position.")
        end
    end

    if sceneitem ~= nil then
        sceneitem_info_orig = obs.obs_transform_info()
        sceneitem_get_info(sceneitem, sceneitem_info_orig)

        sceneitem_crop_orig = obs.obs_sceneitem_crop()
        obs.obs_sceneitem_get_crop(sceneitem, sceneitem_crop_orig)

        sceneitem_info = obs.obs_transform_info()
        sceneitem_get_info(sceneitem, sceneitem_info)

        sceneitem_crop = obs.obs_sceneitem_crop()
        obs.obs_sceneitem_get_crop(sceneitem, sceneitem_crop)

        if is_non_display_capture then
            sceneitem_crop_orig.left = 0
            sceneitem_crop_orig.top = 0
            sceneitem_crop_orig.right = 0
            sceneitem_crop_orig.bottom = 0
        end

        if not source then
            log("ERROR: Could not get source for sceneitem (" .. source_name .. ")")
        end

        source_width = obs.obs_source_get_base_width(source)
        source_height = obs.obs_source_get_base_height(source)

        if source_width == 0 then source_width = source_raw.width end
        if source_height == 0 then source_height = source_raw.height end

        if source_width == 0 or source_height == 0 then
            log("ERROR: Something went wrong determining source size." ..
                "       Try using the 'Set manual source position' option and adding override values")

            if monitor_info ~= nil then
                source_width = monitor_info.width
                source_height = monitor_info.height
            end
        else
            log("Using source size: " .. source_width .. ", " .. source_height)
        end

        if sceneitem_info.bounds_type == obs.OBS_BOUNDS_NONE then
            sceneitem_info.bounds_type = obs.OBS_BOUNDS_SCALE_INNER
            sceneitem_info.bounds_alignment = 5
            sceneitem_info.bounds.x = source_width * sceneitem_info.scale.x
            sceneitem_info.bounds.y = source_height * sceneitem_info.scale.y

            sceneitem_set_info(sceneitem, sceneitem_info)

            log("WARNING: Found existing non-boundingbox transform. This may cause issues with zooming. " ..
                "         Settings have been auto converted to a bounding box scaling transfrom instead. " ..
                "         If you have issues with your layout consider making the transform use a bounding box manually.")
        end

        zoom_info.source_crop_filter = { x = 0, y = 0, w = 0, h = 0 }
        found_crop_filter = false
        filters = obs.obs_source_enum_filters(source)
        if filters ~= nil then
            for _, v in pairs(filters) do
                id = obs.obs_source_get_id(v)
                if id == "crop_filter" then
                    name = obs.obs_source_get_name(v)
                    if name ~= CROP_FILTER_NAME and name ~= "temp_" .. CROP_FILTER_NAME then
                        found_crop_filter = true
                        settings = obs.obs_source_get_settings(v)
                        if settings ~= nil then
                            if not obs.obs_data_get_bool(settings, "relative") then
                                zoom_info.source_crop_filter.x = zoom_info.source_crop_filter.x + obs.obs_data_get_int(settings, "left")
                                zoom_info.source_crop_filter.y = zoom_info.source_crop_filter.y + obs.obs_data_get_int(settings, "top")
                                zoom_info.source_crop_filter.w = zoom_info.source_crop_filter.w + obs.obs_data_get_int(settings, "cx")
                                zoom_info.source_crop_filter.h = zoom_info.source_crop_filter.h + obs.obs_data_get_int(settings, "cy")
                                log("Found existing relative crop/pad filter (" .. name .. "). Applying settings " .. format_table(zoom_info.source_crop_filter))
                            else
                                log("WARNING: Found existing non-relative crop/pad filter (" .. name .. "). " ..
                                    "         This will cause issues with zooming. Convert to relative settings instead.")
                            end
                            obs.obs_data_release(settings)
                        end
                    end
                end
            end

            obs.source_list_release(filters)
        end

        if not found_crop_filter and (sceneitem_crop_orig.left ~= 0 or sceneitem_crop_orig.top ~= 0 or sceneitem_crop_orig.right ~= 0 or sceneitem_crop_orig.bottom ~= 0) then
            log("Creating new crop filter")

            source_width = source_width - (sceneitem_crop_orig.left + sceneitem_crop_orig.right)
            source_height = source_height - (sceneitem_crop_orig.top + sceneitem_crop_orig.bottom)

            zoom_info.source_crop_filter.x = sceneitem_crop_orig.left
            zoom_info.source_crop_filter.y = sceneitem_crop_orig.top
            zoom_info.source_crop_filter.w = source_width
            zoom_info.source_crop_filter.h = source_height

            settings = obs.obs_data_create()
            obs.obs_data_set_bool(settings, "relative", false)
            obs.obs_data_set_int(settings, "left", zoom_info.source_crop_filter.x)
            obs.obs_data_set_int(settings, "top", zoom_info.source_crop_filter.y)
            obs.obs_data_set_int(settings, "cx", zoom_info.source_crop_filter.w)
            obs.obs_data_set_int(settings, "cy", zoom_info.source_crop_filter.h)
            crop_filter_temp = obs.obs_source_create_private("crop_filter", "temp_" .. CROP_FILTER_NAME, settings)
            obs.obs_source_filter_add(source, crop_filter_temp)
            obs.obs_data_release(settings)

            sceneitem_crop.left = 0
            sceneitem_crop.top = 0
            sceneitem_crop.right = 0
            sceneitem_crop.bottom = 0
            obs.obs_sceneitem_set_crop(sceneitem, sceneitem_crop)

            log("WARNING: Found existing transform crop. This may cause issues with zooming. " ..
                "         Settings have been auto converted to a relative crop/pad filter instead. " ..
                "         If you have issues with your layout consider making the filter manually.")
        elseif found_crop_filter then
            source_width = zoom_info.source_crop_filter.w
            source_height = zoom_info.source_crop_filter.h
        end

        zoom_info.source_size = { width = source_width, height = source_height }
        zoom_info.source_crop = {
            l = sceneitem_crop_orig.left,
            t = sceneitem_crop_orig.top,
            r = sceneitem_crop_orig.right,
            b = sceneitem_crop_orig.bottom
        }

        crop_filter_info_orig = { x = 0, y = 0, w = zoom_info.source_size.width, h = zoom_info.source_size.height }
        crop_filter_info = { x = crop_filter_info_orig.x, y = crop_filter_info_orig.y, w = crop_filter_info_orig.w, h = crop_filter_info_orig.h }

        crop_filter = obs.obs_source_get_filter_by_name(source, CROP_FILTER_NAME)
        if crop_filter == nil then
            crop_filter_settings = obs.obs_data_create()
            obs.obs_data_set_bool(crop_filter_settings, "relative", false)
            crop_filter = obs.obs_source_create_private("crop_filter", CROP_FILTER_NAME, crop_filter_settings)
            obs.obs_source_filter_add(source, crop_filter)
        else
            crop_filter_settings = obs.obs_source_get_settings(crop_filter)
        end

        obs.obs_source_filter_set_order(source, crop_filter, obs.OBS_ORDER_MOVE_BOTTOM)
        set_crop_settings(crop_filter_info_orig)
    end
end

---
-- Get the target position that we will attempt to zoom towards
function refresh_click_effect(find_newest)
    if not click_effect_enabled then
        return
    end

    if find_newest then
        if click_effect_sceneitem ~= nil then
            obs.obs_sceneitem_release(click_effect_sceneitem)
            click_effect_sceneitem = nil
        end
        if click_effect_source ~= nil then
            obs.obs_source_release(click_effect_source)
            click_effect_source = nil
        end
        click_effect_info_orig = nil
        click_visible_orig = nil

        if click_effect_source_name ~= nil and click_effect_source_name ~= "" then
            click_effect_source = obs.obs_get_source_by_name(click_effect_source_name)
            if click_effect_source ~= nil then
                click_effect_sceneitem = find_sceneitem_in_current_scene(click_effect_source_name)
                if click_effect_sceneitem == nil then
                    log("[obs-better-zoom-to-mouse] Click effect source '" .. click_effect_source_name .. "' found but not in current scene hierarchy.")
obs.obs_source_release(click_effect_source)
                    click_effect_source = nil
                else
                    click_effect_info_orig = obs.obs_transform_info()
                    sceneitem_get_info(click_effect_sceneitem, click_effect_info_orig)
                    click_visible_orig = obs.obs_sceneitem_visible(click_effect_sceneitem)
                    -- Hide by default; we only show when triggered
                    obs.obs_sceneitem_set_visible(click_effect_sceneitem, false)

                    -- If it's a color source, apply configured color
                    sid = obs.obs_source_get_id(click_effect_source)
                    if sid == "color_source" then
                        s = obs.obs_source_get_settings(click_effect_source)
                        if s ~= nil then
                            obs.obs_data_set_int(s, "color", click_effect_color)
                            obs.obs_source_update(click_effect_source, s)
                            obs.obs_data_release(s)
                        end
                    end
                end
            else
                log("[obs-better-zoom-to-mouse] Click effect source '" .. click_effect_source_name .. "' not found.")
end
        end
    end
end


function get_target_position(zoom, mouse_override)
    mouse = mouse_override or get_mouse_pos()

    if monitor_info then
        mouse.x = mouse.x - monitor_info.x
        mouse.y = mouse.y - monitor_info.y
    end

    mouse.x = mouse.x - zoom.source_crop_filter.x
    mouse.y = mouse.y - zoom.source_crop_filter.y

    if monitor_info and monitor_info.scale_x and monitor_info.scale_y then
        mouse.x = mouse.x * monitor_info.scale_x
        mouse.y = mouse.y * monitor_info.scale_y
    end

    new_size = {
        width = zoom.source_size.width / zoom.zoom_to,
        height = zoom.source_size.height / zoom.zoom_to
    }

    pos = {
        x = mouse.x - new_size.width * 0.5,
        y = mouse.y - new_size.height * 0.5
    }

    crop = { x = pos.x, y = pos.y, w = new_size.width, h = new_size.height }

    crop.x = math.floor(clamp(0, (zoom.source_size.width - new_size.width), crop.x))
    crop.y = math.floor(clamp(0, (zoom.source_size.height - new_size.height), crop.y))

    return { crop = crop, raw_center = mouse, clamped_center = { x = math.floor(crop.x + crop.w * 0.5), y = math.floor(crop.y + crop.h * 0.5) } }
end

function on_toggle_follow(pressed)
    if pressed then
        is_following_mouse = not is_following_mouse
        log("Tracking mouse is " .. (is_following_mouse and "on" or "off"))

        if is_following_mouse and zoom_state == ZoomState.ZoomedIn then
            if is_timer_running == false then
                is_timer_running = true
                last_timer_ns = nil
                timer_interval = math.floor(obs.obs_get_frame_interval_ns() / 1000000)
                obs.timer_add(on_timer, timer_interval)
            end
        end
    end
end

local function start_timer_if_needed()
    if is_timer_running == false then
        is_timer_running = true
        last_timer_ns = nil
        timer_interval = math.floor(obs.obs_get_frame_interval_ns() / 1000000)
        obs.timer_add(on_timer, timer_interval)
    end
end

-- Start a zoom (in or out) to a specific target zoom factor and record the current zoom level label.
function get_level_anim_settings(level_label)
    local lvl = level_label or "base"
    if lvl == "closeup" then
        return closeup_zoom_speed_in or zoom_speed_in,
               closeup_zoom_speed_out or zoom_speed_out,
               closeup_zoom_easing_in or easing_preset,
               closeup_zoom_easing_out or zoom_out_easing
    elseif lvl == "macro" then
        return macro_zoom_speed_in or zoom_speed_in,
               macro_zoom_speed_out or zoom_speed_out,
               macro_zoom_easing_in or easing_preset,
               macro_zoom_easing_out or zoom_out_easing
    elseif lvl == "nano" then
        return nano_zoom_speed_in or zoom_speed_in,
               nano_zoom_speed_out or zoom_speed_out,
               nano_zoom_easing_in or easing_preset,
               nano_zoom_easing_out or zoom_out_easing
    elseif lvl == "pico" then
        return pico_zoom_speed_in or zoom_speed_in,
               pico_zoom_speed_out or zoom_speed_out,
               pico_zoom_easing_in or easing_preset,
               pico_zoom_easing_out or zoom_out_easing
    end

    return zoom_speed_in, zoom_speed_out, easing_preset, zoom_out_easing
end

function set_current_anim_profile(level_label, is_out)
    local si, so, ei, eo = get_level_anim_settings(level_label)
    if is_out then
        current_zoom_anim_speed = so
        current_zoom_anim_easing = eo
    else
        current_zoom_anim_speed = si
        current_zoom_anim_easing = ei
    end
end

function start_zoom_to_factor(target_zoom, level_label)
    if zoom_state ~= ZoomState.ZoomedIn and zoom_state ~= ZoomState.None then
        return
    end

    if zoom_state == ZoomState.ZoomedIn then
        -- If already zoomed in, we zoom out first only when target is base toggle request.
        log("Zooming out")
        zoom_state = ZoomState.ZoomingOut
        set_current_anim_profile(current_zoom_level, true)
        zoom_time = 0
        locked_center = nil
        locked_last_pos = nil
        zoom_target = { crop = crop_filter_info_orig, c = sceneitem_crop_orig }
        current_zoom_level = "none"
        if is_following_mouse then
            is_following_mouse = false
            log("Tracking mouse is off (due to zoom out)")
        end
    else
        log("Zooming in (" .. tostring(level_label) .. ")")
        zoom_state = ZoomState.ZoomingIn
        zoom_info.zoom_to = target_zoom
        zoom_time = 0
        locked_center = nil
        locked_last_pos = nil
        zoom_target = get_target_position(zoom_info)
        current_zoom_level = level_label or "base"
        set_current_anim_profile(current_zoom_level, false)
    end

    if is_timer_running == false then
        is_timer_running = true
        local timer_interval = math.floor(obs.obs_get_frame_interval_ns() / 1000000)
        obs.timer_add(on_timer, timer_interval)
    end
end

-- Zoom to a desired level without forcing a zoom-out toggle behavior.
-- If currently zoomed out, it zooms in. If currently zoomed in, it retargets to the requested level.
function retarget_zoom_level(target_zoom, level_label)
    if zoom_state == ZoomState.None then
        start_zoom_to_factor(target_zoom, level_label)
        return
    end

    if zoom_state == ZoomState.ZoomedIn then
        -- retarget while staying zoomed in
        log("Retarget zoom (" .. tostring(level_label) .. ")")
        zoom_state = ZoomState.ZoomingIn
        zoom_info.zoom_to = target_zoom
        zoom_time = 0
        locked_center = nil
        locked_last_pos = nil
        zoom_target = get_target_position(zoom_info)
        current_zoom_level = level_label or current_zoom_level
        set_current_anim_profile(current_zoom_level, false)
        if is_timer_running == false then
            is_timer_running = true
            local timer_interval = math.floor(obs.obs_get_frame_interval_ns() / 1000000)
            obs.timer_add(on_timer, timer_interval)
        end
    end
end


function on_toggle_zoom(pressed)
    if hold_to_zoom then
        if pressed then
            if zoom_state == ZoomState.None or zoom_state == ZoomState.ZoomedIn then
                log("Zooming in (hold-to-zoom)")
                zoom_state = ZoomState.ZoomingIn
                zoom_info.zoom_to = zoom_value
                zoom_time = 0
                locked_center = nil
                locked_last_pos = nil
                zoom_anim_start = { x = crop_filter_info.x, y = crop_filter_info.y, w = crop_filter_info.w, h = crop_filter_info.h }
                zoom_target = get_target_position(zoom_info, (smart_prediction_enabled and predicted_mouse) or nil)
                start_timer_if_needed()
            end
        else
            if zoom_state == ZoomState.ZoomedIn or zoom_state == ZoomState.ZoomingIn then
                log("Zooming out (hold-to-zoom)")
                zoom_state = ZoomState.ZoomingOut
                zoom_time = 0
                locked_center = nil
                locked_last_pos = nil
                zoom_anim_start = { x = crop_filter_info.x, y = crop_filter_info.y, w = crop_filter_info.w, h = crop_filter_info.h }
                zoom_target = { crop = crop_filter_info_orig, c = sceneitem_crop_orig }
                if is_following_mouse then
                    is_following_mouse = false
                    log("Tracking mouse is off (due to zoom out)")
                end
                start_timer_if_needed()
            end
        end
        return
    end

    if pressed then
        if zoom_state == ZoomState.ZoomedIn or zoom_state == ZoomState.None then
            if zoom_state == ZoomState.ZoomedIn then
                log("Zooming out")
                zoom_state = ZoomState.ZoomingOut
                zoom_time = 0
                locked_center = nil
                locked_last_pos = nil
                zoom_target = { crop = crop_filter_info_orig, c = sceneitem_crop_orig }
                if is_following_mouse then
                    is_following_mouse = false
                    log("Tracking mouse is off (due to zoom out)")
                end
            else
                log("Zooming in")
                zoom_state = ZoomState.ZoomingIn
                zoom_info.zoom_to = zoom_value
                zoom_time = 0
                locked_center = nil
                locked_last_pos = nil
                zoom_target = get_target_position(zoom_info, (smart_prediction_enabled and predicted_mouse) or nil)
            end

            start_timer_if_needed()
        end
    end
end


function request_zoom_out_from_hold()
    if zoom_state == ZoomState.ZoomedIn or zoom_state == ZoomState.ZoomingIn then
        log("Hold release: zooming out")
        zoom_state = ZoomState.ZoomingOut
        set_current_anim_profile(current_zoom_level, true)
        zoom_time = 0
        locked_center = nil
        locked_last_pos = nil
        zoom_target = { crop = crop_filter_info_orig, c = sceneitem_crop_orig }
        current_zoom_level = "none"
        if is_following_mouse then
            is_following_mouse = false
        end

        if not is_timer_running then
            is_timer_running = true
            last_timer_ns = nil
            timer_interval = math.floor(obs.obs_get_frame_interval_ns() / 1000000)
            obs.timer_add(on_timer, timer_interval)
        end
    else
        log("Not zoomed in - ignore hold release")
    end
end

function on_toggle_spotlight(pressed)
    if not pressed then return end
    spotlight_enabled = not spotlight_enabled
    refresh_spotlight(false)
end

function on_toggle_trail(pressed)
    if not pressed then return end
    trail_enabled = not trail_enabled
    refresh_trail(true)
end

function on_keyframe_next(pressed)
    if not pressed then return end
    if #keyframes == 0 then return end
    keyframe_index = (keyframe_index % #keyframes) + 1
    kf = keyframes[keyframe_index]

    zoom_info.zoom_to = kf.zoom
    zoom_time = 0
    zoom_state = ZoomState.ZoomingIn
    locked_center = nil
    locked_last_pos = nil

    new_size = { width = zoom_info.source_size.width / zoom_info.zoom_to, height = zoom_info.source_size.height / zoom_info.zoom_to }
    crop = { x = kf.x - new_size.width*0.5, y = kf.y - new_size.height*0.5, w = new_size.width, h = new_size.height }
    crop.x = math.floor(clamp(0, (zoom_info.source_size.width - new_size.width), crop.x))
    crop.y = math.floor(clamp(0, (zoom_info.source_size.height - new_size.height), crop.y))
    zoom_target = { crop = crop, raw_center = {x=kf.x,y=kf.y}, clamped_center = {x=math.floor(crop.x+crop.w*0.5), y=math.floor(crop.y+crop.h*0.5)} }

    if is_timer_running == false then
        is_timer_running = true
        last_timer_ns = nil
        timer_interval = math.floor(obs.obs_get_frame_interval_ns() / 1000000)
        obs.timer_add(on_timer, timer_interval)
    end
end

function on_keyframe_prev(pressed)
    if not pressed then return end
    if #keyframes == 0 then return end
    keyframe_index = keyframe_index - 1
    if keyframe_index < 1 then keyframe_index = #keyframes end
    on_keyframe_next(true)
end

function on_toggle_motion_blur(pressed)
    if not pressed then return end
    motion_blur_enabled = not motion_blur_enabled
    if source ~= nil then
        f = obs.obs_source_get_filter_by_name(source, motion_blur_filter_name)
        if f ~= nil then
            obs.obs_source_set_enabled(f, motion_blur_enabled)
            obs.obs_source_release(f)
        end
    end
end

function on_trigger_click_effect(pressed)
    if not pressed then return end
    play_click_sound()
    if not click_effect_enabled then return end

    if click_effect_sceneitem == nil then
        refresh_click_effect(true)
        refresh_spotlight(true)
        refresh_trail(true)
    end
    if click_effect_sceneitem == nil or sceneitem_get_info == nil or sceneitem_set_info == nil then
        if not click_effect_warned then
            obs.script_log(obs.OBS_LOG_WARNING,
                "[obs-better-zoom-to-mouse] Click effect cannot run: create a source named '" .. click_effect_source_name ..
                "' in the current scene (e.g. Image Source with a ring PNG, or a Color Source).")
            click_effect_warned = true
        end
        return
    end

    click_anim_active = true
    click_anim_t = 0.0
    timer_error_logged = false
    obs.obs_sceneitem_set_visible(click_effect_sceneitem, true)

    -- Make sure the timer runs while the animation plays
    if not is_timer_running then
        is_timer_running = true
        last_timer_ns = nil
        timer_interval = math.floor(obs.obs_get_frame_interval_ns() / 1000000)
        obs.timer_add(on_timer, timer_interval)
    end
end


function on_toggle_closeup(pressed)
    if hold_to_zoom_closeup then
        if pressed then
            -- press: zoom in to this level (or retarget if already zoomed in)
        else
            -- release: zoom out
            request_zoom_out_from_hold()
            return
        end
    end
    if not pressed then return end
    if not enable_closeup_zoom then
        log("Close-up zoom is disabled")
        return
    end
    local target = zoom_value * closeup_extra_multiplier
    retarget_zoom_level(target, "closeup")
end

function on_toggle_macro(pressed)
    if hold_to_zoom_macro then
        if pressed then
            -- press: zoom in to this level (or retarget if already zoomed in)
        else
            -- release: zoom out
            request_zoom_out_from_hold()
            return
        end
    end
    if not pressed then return end
    if not enable_macro_zoom then
        log("Macro zoom is disabled")
        return
    end
    local target = zoom_value * macro_extra_multiplier
    retarget_zoom_level(target, "macro")
end


function on_toggle_nano(pressed)
    if hold_to_zoom_nano then
        if pressed then
            -- press: zoom in to this level (or retarget if already zoomed in)
        else
            -- release: zoom out
            request_zoom_out_from_hold()
            return
        end
    end
    if not pressed then return end
    if not enable_nano_zoom then
        log("Nano zoom is disabled")
        return
    end
    local target = zoom_value * nano_extra_multiplier
    retarget_zoom_level(target, "nano")
end

function on_toggle_pico(pressed)
    if hold_to_zoom_pico then
        if pressed then
            -- press: zoom in to this level (or retarget if already zoomed in)
        else
            -- release: zoom out
            request_zoom_out_from_hold()
            return
        end
    end
    if not pressed then return end
    if not enable_pico_zoom then
        log("Pico zoom is disabled")
        return
    end
    local target = zoom_value * pico_extra_multiplier
    retarget_zoom_level(target, "pico")
end



-- Dedicated HOLD hotkeys
-- Press = zoom in (base zoom), Release = zoom out.
function on_hold_zoom(pressed)
    if pressed then
        hold_hotkey_active_level = "base"
        local target = zoom_value
        retarget_zoom_level(target, "base")
    else
        if hold_hotkey_active_level == "base" then
            hold_hotkey_active_level = nil
            request_zoom_out_from_hold()
        end
    end
end

-- Dedicated HOLD hotkeys (per zoom level)
-- Press = zoom in to that level, Release = zoom out.
function on_hold_closeup(pressed)
    if not enable_closeup_zoom then return end
    if pressed then
        hold_hotkey_active_level = "closeup"
        local target = zoom_value * closeup_extra_multiplier
        retarget_zoom_level(target, "closeup")
    else
        if hold_hotkey_active_level == "closeup" then
            hold_hotkey_active_level = nil
            request_zoom_out_from_hold()
        end
    end
end

function on_hold_macro(pressed)
    if not enable_macro_zoom then return end
    if pressed then
        hold_hotkey_active_level = "macro"
        local target = zoom_value * macro_extra_multiplier
        retarget_zoom_level(target, "macro")
    else
        if hold_hotkey_active_level == "macro" then
            hold_hotkey_active_level = nil
            request_zoom_out_from_hold()
        end
    end
end

function on_hold_nano(pressed)
    if not enable_nano_zoom then return end
    if pressed then
        hold_hotkey_active_level = "nano"
        local target = zoom_value * nano_extra_multiplier
        retarget_zoom_level(target, "nano")
    else
        if hold_hotkey_active_level == "nano" then
            hold_hotkey_active_level = nil
            request_zoom_out_from_hold()
        end
    end
end

function on_hold_pico(pressed)
    if not enable_pico_zoom then return end
    if pressed then
        hold_hotkey_active_level = "pico"
        local target = zoom_value * pico_extra_multiplier
        retarget_zoom_level(target, "pico")
    else
        if hold_hotkey_active_level == "pico" then
            hold_hotkey_active_level = nil
            request_zoom_out_from_hold()
        end
    end
end




function on_timer()
    if crop_filter_info ~= nil and zoom_target ~= nil then
-- Safety: if crop filter isn't ready, stop the timer to avoid log spam
if crop_filter == nil or crop_filter_settings == nil then
    if not timer_error_logged then
        obs.script_log(obs.OBS_LOG_WARNING,
            "[obs-better-zoom-to-mouse] Crop filter not initialized yet (crop_filter/crop_filter_settings is nil). " ..
            "Stopping timer to prevent repeated errors. Make sure a valid Zoom Source is selected and refresh_sceneitem() has run.")
        timer_error_logged = true
    end
    if is_timer_running then
        is_timer_running = false
        obs.timer_remove(on_timer)
    end
    return
end

        tns = now_ns()
        dt = 0
        if last_timer_ns ~= nil then
            dt = (tns - last_timer_ns) / 1e9
        end
        last_timer_ns = tns

-- v3: smart prediction (simple velocity-based look-ahead)
raw_mouse = get_mouse_pos()
if monitor_info then
    raw_mouse.x = raw_mouse.x - monitor_info.x
    raw_mouse.y = raw_mouse.y - monitor_info.y
end
if zoom_info and zoom_info.source_crop_filter then
    raw_mouse.x = raw_mouse.x - zoom_info.source_crop_filter.x
    raw_mouse.y = raw_mouse.y - zoom_info.source_crop_filter.y
end
if monitor_info and monitor_info.scale_x and monitor_info.scale_y then
    raw_mouse.x = raw_mouse.x * monitor_info.scale_x
    raw_mouse.y = raw_mouse.y * monitor_info.scale_y
end

predicted_mouse = raw_mouse
if smart_prediction_enabled and dt > 0 then
    if pred_last_mouse ~= nil then
        vx = (raw_mouse.x - pred_last_mouse.x) / dt
        vy = (raw_mouse.y - pred_last_mouse.y) / dt
        pred_vel.x = lerp(pred_vel.x, vx, 0.35)
        pred_vel.y = lerp(pred_vel.y, vy, 0.35)
    end
    pred_last_mouse = { x = raw_mouse.x, y = raw_mouse.y }
    predicted_mouse = {
        x = raw_mouse.x + pred_vel.x * smart_prediction_strength,
        y = raw_mouse.y + pred_vel.y * smart_prediction_strength
    }
end

        -- Preserve original "per frame" feel by scaling with ~60fps
        local zspd = current_zoom_anim_speed or zoom_speed_in
        if zoom_state == ZoomState.ZoomingOut then
            if current_zoom_anim_speed == nil or current_zoom_anim_easing == nil then
                set_current_anim_profile(current_zoom_level, true)
            end
            zspd = current_zoom_anim_speed or zoom_speed_out
        else
            if current_zoom_anim_speed == nil or current_zoom_anim_easing == nil then
                set_current_anim_profile(current_zoom_level, false)
            end
            zspd = current_zoom_anim_speed or zoom_speed_in
        end

        -- Speed scaling: keep ultra-slow values possible, but make the top end usable.
        -- Previously, values above ~0.05 could become "too fast" and feel instant.
        -- We scale the user-facing value down so 0.30–0.60 becomes a sensible working range,
        -- while 0.001 still remains extremely slow as expected.
        local zspd_eff = zspd * 0.10
        zoom_time = zoom_time + (dt * zspd_eff * 60.0)

        if zoom_state == ZoomState.ZoomingOut or zoom_state == ZoomState.ZoomingIn then
            if zoom_time <= 1 then
                if zoom_state == ZoomState.ZoomingIn and use_auto_follow_mouse then
                    zoom_target = get_target_position(zoom_info, (smart_prediction_enabled and predicted_mouse) or nil)
                end
                if zoom_state == ZoomState.ZoomingOut then
                    e = ease_preset_value_out(zoom_time, current_zoom_anim_easing)
                else
                    e = ease_preset_value(zoom_time, current_zoom_anim_easing)
                end
                local desired = {
                    x = lerp((zoom_anim_start and zoom_anim_start.x) or crop_filter_info.x, zoom_target.crop.x, e),
                    y = lerp((zoom_anim_start and zoom_anim_start.y) or crop_filter_info.y, zoom_target.crop.y, e),
                    w = lerp((zoom_anim_start and zoom_anim_start.w) or crop_filter_info.w, zoom_target.crop.w, e),
                    h = lerp((zoom_anim_start and zoom_anim_start.h) or crop_filter_info.h, zoom_target.crop.h, e)
                }

                local sm_en = zoom_smoothing_in_enabled
                local sm = zoom_smoothing_in
                if zoom_state == ZoomState.ZoomingOut then
                    sm_en = zoom_smoothing_out_enabled
                    sm = zoom_smoothing_out
                end

                if sm_en and sm > 0 then
                    crop_filter_info.x = lerp(crop_filter_info.x, desired.x, clamp(0.0, 1.0, sm))
                    crop_filter_info.y = lerp(crop_filter_info.y, desired.y, clamp(0.0, 1.0, sm))
                    crop_filter_info.w = lerp(crop_filter_info.w, desired.w, clamp(0.0, 1.0, sm))
                    crop_filter_info.h = lerp(crop_filter_info.h, desired.h, clamp(0.0, 1.0, sm))
                else
                    crop_filter_info.x = desired.x
                    crop_filter_info.y = desired.y
                    crop_filter_info.w = desired.w
                    crop_filter_info.h = desired.h
                end

                set_crop_settings(crop_filter_info)
            end
        else
            if is_following_mouse then
                zoom_target = get_target_position(zoom_info, (smart_prediction_enabled and predicted_mouse) or nil)

                skip_frame = false
                if not use_follow_outside_bounds then
                    if zoom_target.raw_center.x < zoom_target.crop.x or
                        zoom_target.raw_center.x > zoom_target.crop.x + zoom_target.crop.w or
                        zoom_target.raw_center.y < zoom_target.crop.y or
                        zoom_target.raw_center.y > zoom_target.crop.y + zoom_target.crop.h then
                        skip_frame = true
                    end
                end

                if not skip_frame then
                    if locked_center ~= nil then
                        diff = { x = zoom_target.raw_center.x - locked_center.x, y = zoom_target.raw_center.y - locked_center.y }
                        track = { x = zoom_target.crop.w * (0.5 - (follow_border * 0.01)), y = zoom_target.crop.h * (0.5 - (follow_border * 0.01)) }

                        if math.abs(diff.x) > track.x or math.abs(diff.y) > track.y then
                            locked_center = nil
                            locked_last_pos = { x = zoom_target.raw_center.x, y = zoom_target.raw_center.y, diff_x = diff.x, diff_y = diff.y }
                            log("Locked area exited - resume tracking")
                        end
                    end

                    if locked_center == nil and (zoom_target.crop.x ~= crop_filter_info.x or zoom_target.crop.y ~= crop_filter_info.y) then
                        
                        -- Extra jelly smoothing to reduce jitter near edges (averages the target over time)
                        desired_x = zoom_target.crop.x
                        desired_y = zoom_target.crop.y
                        if jelly_follow_strength ~= nil and jelly_follow_strength > 0.0001 and dt ~= nil and dt > 0 then
                            if jelly_follow_state == nil then
                                jelly_follow_state = { x = crop_filter_info.x, y = crop_filter_info.y }
                            end
                            tau = lerp(jelly_follow_tau_min, jelly_follow_tau_max, clamp(0.0, 1.0, jelly_follow_strength))
                            alpha = 1.0
                            if tau > 0.0001 then
                                alpha = 1.0 - math.exp(-dt / tau)
                            end
                            jelly_follow_state.x = jelly_follow_state.x + (desired_x - jelly_follow_state.x) * alpha
                            jelly_follow_state.y = jelly_follow_state.y + (desired_y - jelly_follow_state.y) * alpha

                            -- Keep the cursor inside the view: if smoothing would push the cursor out, snap to the real target for this frame.
                            margin = zoom_target.crop.w * 0.03
                            if zoom_target.raw_center.x < jelly_follow_state.x + margin or
                               zoom_target.raw_center.x > jelly_follow_state.x + zoom_target.crop.w - margin or
                               zoom_target.raw_center.y < jelly_follow_state.y + margin or
                               zoom_target.raw_center.y > jelly_follow_state.y + zoom_target.crop.h - margin then
                                jelly_follow_state.x = desired_x
                                jelly_follow_state.y = desired_y
                            end
                            desired_x = jelly_follow_state.x
                            desired_y = jelly_follow_state.y
                        else
                            jelly_follow_state = nil
                        end

                        -- v3: adaptive zoom smoothing (faster on large moves, smoother on small moves)
                        dx = math.abs(crop_filter_info.x - desired_x)
                        dy = math.abs(crop_filter_info.y - desired_y)
                        dist = math.sqrt(dx*dx + dy*dy)
                        diag = math.sqrt((zoom_target.crop.w*zoom_target.crop.w) + (zoom_target.crop.h*zoom_target.crop.h))
                        nd = 0.0
                        if diag > 0 then nd = clamp(0.0, 1.0, dist / diag) end
                        follow_t = follow_speed
                        if adaptive_smoothing_enabled then
                            boost = adaptive_smoothing_strength * nd
                            follow_t = clamp(adaptive_smoothing_min, adaptive_smoothing_max, follow_speed + boost)
                        end
                        crop_filter_info.x = lerp(crop_filter_info.x, desired_x, follow_ease_value(follow_t))
                        crop_filter_info.y = lerp(crop_filter_info.y, desired_y, follow_ease_value(follow_t))
                        set_crop_settings(crop_filter_info)

                        if is_following_mouse and locked_center == nil and locked_last_pos ~= nil then
                            diff = {
                                x = math.abs(crop_filter_info.x - zoom_target.crop.x),
                                y = math.abs(crop_filter_info.y - zoom_target.crop.y),
                                auto_x = zoom_target.raw_center.x - locked_last_pos.x,
                                auto_y = zoom_target.raw_center.y - locked_last_pos.y
                            }

                            locked_last_pos.x = zoom_target.raw_center.x
                            locked_last_pos.y = zoom_target.raw_center.y

                            lock = false
                            if math.abs(locked_last_pos.diff_x) > math.abs(locked_last_pos.diff_y) then
                                if (diff.auto_x < 0 and locked_last_pos.diff_x > 0) or (diff.auto_x > 0 and locked_last_pos.diff_x < 0) then
                                    lock = true
                                end
                            else
                                if (diff.auto_y < 0 and locked_last_pos.diff_y > 0) or (diff.auto_y > 0 and locked_last_pos.diff_y < 0) then
                                    lock = true
                                end
                            end

                            if (lock and use_follow_auto_lock) or (diff.x <= follow_safezone_sensitivity and diff.y <= follow_safezone_sensitivity) then
                                locked_center = { x = math.floor(crop_filter_info.x + zoom_target.crop.w * 0.5), y = math.floor(crop_filter_info.y + zoom_target.crop.h * 0.5) }
                                log("Cursor stopped. Tracking locked to " .. locked_center.x .. ", " .. locked_center.y)
                            end
                        end
                    end
                end
            end
        end
-- [obs-better-zoom-to-mouse] click_effect_update
if click_anim_active and click_effect_sceneitem ~= nil and sceneitem_get_info ~= nil and sceneitem_set_info ~= nil then
    -- Advance time
    click_anim_t = click_anim_t + dt
    p = 0.0
    if click_effect_duration > 0 then
        p = click_anim_t / click_effect_duration
    else
        p = 1.0
    end
    p = clamp(0.0, 1.0, p)

    -- Get current cursor location in zoom-source coordinates
    tgt = get_target_position(zoom_info)
    raw = tgt.raw_center

    -- Map cursor location to canvas coordinates based on how the zoom source is currently shown
    -- Assumes bounds are top-left aligned (the script forces bounds scaling when needed)
    norm_x = 0.5
    norm_y = 0.5
    if crop_filter_info ~= nil and crop_filter_info.w > 0 and crop_filter_info.h > 0 then
        norm_x = (raw.x - crop_filter_info.x) / crop_filter_info.w
        norm_y = (raw.y - crop_filter_info.y) / crop_filter_info.h
    end
    norm_x = clamp(0.0, 1.0, norm_x)
    norm_y = clamp(0.0, 1.0, norm_y)

    -- Read zoom source transform info for canvas mapping
    zinfo = obs.obs_transform_info()
    sceneitem_get_info(sceneitem, zinfo)
    canvas_x = zinfo.pos.x + (norm_x * zinfo.bounds.x)
    canvas_y = zinfo.pos.y + (norm_y * zinfo.bounds.y)

    -- Compute scale curve by type
s = 1.0
pulses = math.max(1, click_effect_pulses or 1)
if click_effect_type == 0 then
    -- Pulse: up then settle
    s = 1.0 + (math.sin(p * math.pi) * (click_effect_max_scale - 1.0))
elseif click_effect_type == 1 then
    -- Ripple: ease-out growth
    e = 1.0 - ((1.0 - p) * (1.0 - p))
    s = 1.0 + (e * (click_effect_max_scale - 1.0))
elseif click_effect_type == 2 then
    -- Pop: small dip then pop
    if p < 0.25 then
        s = 1.0 - (p / 0.25) * 0.15
    else
        pp = (p - 0.25) / 0.75
        s = 0.85 + (math.sin(pp * math.pi) * (click_effect_max_scale - 0.85))
    end
elseif click_effect_type == 3 then
    -- Bounce: overshoot then settle
    e = ease_in_out(p)
    overshoot = math.sin(e * math.pi) * 0.35
    s = 1.0 + (e * (click_effect_max_scale - 1.0)) + overshoot
elseif click_effect_type == 4 then
    -- Radar: multiple pulses inside duration
    pp = (p * pulses) % 1.0
    s = 1.0 + (math.sin(pp * math.pi) * (click_effect_max_scale - 1.0))
elseif click_effect_type == 5 then
    -- Ping: quick burst then hold
    e = (p < 0.35) and (p / 0.35) or 1.0
    s = 1.0 + (ease_in_out(e) * (click_effect_max_scale - 1.0))
elseif click_effect_type == 6 then
    -- Spiral: steady grow
    s = 1.0 + (p * (click_effect_max_scale - 1.0))
elseif click_effect_type == 8 then
    -- Double Ring: two pulses
    s = 1.0 + (math.sin(p * math.pi * 2) * 0.5 + 0.5) * (click_effect_max_scale - 1.0)
elseif click_effect_type == 9 then
    -- Flash: very fast punch-in then settle
    e = (p < 0.18) and (p / 0.18) or (1.0 - (p - 0.18) / 0.82)
    e = clamp(0.0, 1.0, e)
    s = 1.0 + (ease_in_out(e) * (click_effect_max_scale - 1.0))
elseif click_effect_type == 10 then
    -- Elastic: overshoot and decay
    decay = math.exp(-6 * p)
    osc = math.sin(p * math.pi * 6)
    s = 1.0 + (p * (click_effect_max_scale - 1.0)) + (osc * 0.35 * decay)
elseif click_effect_type == 11 then
    -- Drift: slow grow with gentle sway
    s = 1.0 + (ease_in_out(p) * (click_effect_max_scale - 1.0) * 0.85) + (math.sin(p * math.pi * 2) * 0.08)
elseif click_effect_type == 12 then
    -- Heartbeat: two quick pulses
    pp = p
    beat = 0.0
    if pp < 0.25 then beat = math.sin((pp/0.25) * math.pi) elseif pp < 0.55 then beat = math.sin(((pp-0.35)/0.20) * math.pi) end
    beat = clamp(0.0, 1.0, beat)
    s = 1.0 + (beat * (click_effect_max_scale - 1.0))
elseif click_effect_type == 13 then
    -- Snap: quick snap to size then tiny settle
    e2 = 1.0 - math.pow(1.0 - p, 5)
    settle = math.sin(p * math.pi * 3) * math.exp(-5*p) * 0.12
    s = 1.0 + (e2 * (click_effect_max_scale - 1.0)) + settle
else
    -- Wobble: subtle oscillation
    s = 1.0 + ((click_effect_max_scale - 1.0) * 0.6) + (math.sin(p * math.pi * 4) * 0.15)
end

-- Apply to click effect sceneitem (keep original rotation and other properties)
    cinfo = obs.obs_transform_info()
    sceneitem_get_info(click_effect_sceneitem, cinfo)

    cinfo.pos.x = canvas_x
    cinfo.pos.y = canvas_y

    -- Anchor center if possible
    cinfo.alignment = 0 -- OBS_ALIGN_CENTER

    cinfo.scale.x = s
    cinfo.scale.y = s

    sceneitem_set_info(click_effect_sceneitem, cinfo)

    if p >= 1.0 then
        click_anim_active = false
        obs.obs_sceneitem_set_visible(click_effect_sceneitem, false)
    end
end


        if zoom_time >= 1 then
            should_stop_timer = false
            if zoom_state == ZoomState.ZoomingOut then
                log("Zoomed out")
                zoom_state = ZoomState.None
                should_stop_timer = true and (not click_anim_active)
            elseif zoom_state == ZoomState.ZoomingIn then
                log("Zoomed in")
                zoom_state = ZoomState.ZoomedIn
                should_stop_timer = (not use_auto_follow_mouse) and (not is_following_mouse)

                if use_auto_follow_mouse then
                    is_following_mouse = true
                    log("Tracking mouse is " .. (is_following_mouse and "on" or "off") .. " (due to auto follow)")
                end

                if is_following_mouse and follow_border < 50 then
                    zoom_target = get_target_position(zoom_info, (smart_prediction_enabled and predicted_mouse) or nil)
                    locked_center = { x = zoom_target.clamped_center.x, y = zoom_target.clamped_center.y }
                    log("Cursor stopped. Tracking locked to " .. locked_center.x .. ", " .. locked_center.y)
                end
            end

            if should_stop_timer then
                is_timer_running = false
                obs.timer_remove(on_timer)
                last_timer_ns = nil
            end
        end
    end
end

function on_transition_start(t)
    log("Transition started")
    release_sceneitem()
end

function on_frontend_event(event)
    if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
        log("Scene changed")
        refresh_sceneitem(true)
        refresh_click_effect(true)
        refresh_spotlight(true)
        refresh_trail(true)
    end
end

function on_update_transform()
    refresh_sceneitem(true)
    return true
end

function on_settings_modified(props, prop, settings)
    name = obs.obs_property_name(prop)

    if name == "use_monitor_override" then
        visible = obs.obs_data_get_bool(settings, "use_monitor_override")
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_x"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_y"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_w"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_h"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_sx"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_sy"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_dw"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_dh"), visible)
        return true
    elseif name == "allow_all_sources" then
        sources_list = obs.obs_properties_get(props, "source")
        populate_zoom_sources(sources_list)
        return true
    elseif name == "debug_logs" then
        if obs.obs_data_get_bool(settings, "debug_logs") then
            log_current_settings()
        end
    end

    return false
end

function log_current_settings()
    settings = {
        zoom_value = zoom_value,
        use_auto_follow_mouse = use_auto_follow_mouse,
        use_follow_outside_bounds = use_follow_outside_bounds,
        follow_speed = follow_speed,
        follow_border = follow_border,
        follow_safezone_sensitivity = follow_safezone_sensitivity,
        use_follow_auto_lock = use_follow_auto_lock,
        allow_all_sources = allow_all_sources,
        use_monitor_override = use_monitor_override,
        monitor_override_x = monitor_override_x,
        monitor_override_y = monitor_override_y,
        monitor_override_w = monitor_override_w,
        monitor_override_h = monitor_override_h,
        monitor_override_sx = monitor_override_sx,
        monitor_override_sy = monitor_override_sy,
        monitor_override_dw = monitor_override_dw,
        monitor_override_dh = monitor_override_dh,
        mouse_smoothing = mouse_smoothing,
        hold_to_zoom = hold_to_zoom,
        debug_logs = debug_logs
    }

    log("OBS Version: " .. string.format("%.1f", major))
    log("Current settings:")
    log(format_table(settings))
end

function on_print_help()
    local help = [[
Advanced Multi-Level Zoom & Cursor Focus for OBS

This script transforms a standard display capture into a dynamic, production-grade zoom system built for tutorials, technical demonstrations, coding streams, UI walkthroughs, and detailed visual presentations. It allows you to zoom into your screen smoothly, follow the cursor intelligently, and create multiple levels of close-up focus — all controllable with dedicated hotkeys.

It is designed for creators who need precision, control, and flexibility beyond basic zoom scripts.

Who This Is For

This script is ideal for:

Software tutorial creators

Developers and programmers explaining code

Technical educators and trainers

UI/UX designers presenting interfaces

Reviewers demonstrating small details

Anyone producing screen-based content where clarity matters

If you regularly say “let me zoom into that” during recordings, this tool is built for you.

Core Capabilities
Multi-Level Zoom System

You are not limited to a single zoom level. The script supports:

Normal Zoom

Close-up Zoom

Macro Zoom

Nano Zoom

Pico Zoom

Each zoom level:

Can be enabled or disabled independently

Has its own extra zoom multiplier

Has its own toggle hotkey

Has its own hold-to-zoom hotkey

Has its own animation speed and easing settings

This allows progressive focus. For example:

One key for general emphasis

Another for a detailed close-up

Another for extreme precision inspection

You can zoom deeper while already zoomed in, allowing layered magnification.

Independent Hold-to-Zoom Hotkeys

Every zoom level has its own dedicated hold hotkey.

When using a hold hotkey:

Press → Zoom in

Release → Zoom out

This allows quick momentary focus without toggling states. It is perfect for highlighting specific UI elements temporarily during live explanation.

Separate Animation Settings Per Zoom Level

Each zoom level has its own:

Zoom speed (In)

Zoom speed (Out)

Easing (In)

Easing (Out)

This means:

Your normal zoom can feel smooth and cinematic.

Your Macro zoom can be snappier.

Your Pico zoom can be slower and dramatic.

You have full control over the animation personality of each zoom level.

Animation & Motion Controls
Zoom Speeds (In and Out)

You can independently configure how fast zooming in and zooming out occurs.

This allows:

Fast zoom-in + slow zoom-out

Slow cinematic zoom-in + fast reset

Completely symmetrical motion

Easing Options

Multiple easing curves are available, including cinematic and smooth acceleration curves.

Easing defines how the motion feels:

Linear → mechanical and direct

Cinematic → natural and professional

Quintic and other curves → more dramatic or subtle movement

Each direction (In / Out) can use a different easing type.

Extra Zoom Smoothing (In and Out)

Optional smoothing layers add additional motion refinement during zoom transitions.

This helps eliminate abrupt acceleration or mechanical feeling.

Each direction can enable smoothing independently and define its strength.

Cursor Tracking & Follow System
Auto Follow Cursor

When enabled, the zoom area follows the on-screen cursor.

This is ideal for:

Live coding

UI walkthroughs

Interactive demos

The zoom window intelligently tracks the cursor while maintaining smooth motion.

Follow Outside Bounds

Allows the camera to keep tracking the cursor even when it approaches the edge of the source area.

Follow Speed

Controls how quickly the zoom window catches up to the cursor.

Higher values:

Faster camera tracking

Lower values:

More cinematic lag

Jelly Smoothing

This feature averages follow motion to eliminate jitter, especially near screen edges.

It:

Reduces micro-twitches

Prevents hard snapping

Maintains cursor visibility

This is especially useful when working with high DPI mice or very small UI elements.

Smart Prediction

Predicts cursor direction slightly to improve tracking smoothness.

This reduces perceived lag while keeping movement controlled.

Strength can be adjusted to balance responsiveness and stability.

Adaptive Smoothing

Automatically adjusts follow responsiveness based on cursor movement speed.

You can define:

Minimum follow responsiveness

Maximum follow responsiveness

Overall adaptive strength

This creates a system where:

Slow cursor movement = precise control

Fast cursor movement = responsive tracking

Safety & Locking System
Lock Sensitivity

Defines when the zoom window locks in place once the cursor slows down.

Prevents constant micro-adjustments.

Auto Lock on Reverse Direction

If the cursor reverses direction abruptly, tracking can automatically pause briefly.

This reduces jitter during quick directional corrections.

Manual Source Handling
Allow Any Zoom Source

By default, the script works best with Display Capture.

When enabled, you can use:

Window Capture

Game Capture

Other source types

However, manual positioning may be required for non-display sources.

Manual Source Position Override

Allows you to manually define:

Source position

Width and height

Scale

Useful when:

Using cropped sources

Working with unusual layouts

Combining multiple scenes

Mouse Smoothing

This setting smooths raw cursor input before it affects zoom tracking.

Useful when:

Using very high sensitivity mice

Working on very high resolution displays

Experiencing jitter

Hotkey System

Each zoom level includes:

Toggle hotkey

Hold hotkey

You configure these in:

OBS → Settings → Hotkeys

Search for the zoom level names.

Platform Notes
Windows

Fully supported.
Works best with Display Capture.

macOS

Important:

OBS must have:

Screen Recording permission

(Recommended) Accessibility permission

Without Screen Recording permission:
The script cannot properly detect or zoom display content.

You can enable permissions in:
System Settings → Privacy & Security → Screen Recording

If cursor tracking behaves strangely, verify Accessibility permission is enabled.

Linux

Works on X11 sessions.

Wayland sessions may limit global cursor access depending on compositor security restrictions.

If cursor tracking does not behave correctly under Wayland:

Switch to an X11 session if possible.

Display Capture support varies by distribution and desktop environment.

What This Script Can Do

Multi-layer progressive zoom

Independent animation personalities per zoom level

Cinematic motion control

Intelligent cursor following

Precision smoothing

Temporary hold-based quick focus

Extreme close-up inspection

Live production ready motion behavior

What This Script Cannot Do

It cannot bypass OS security restrictions (macOS / Wayland limitations).

It cannot zoom external hardware monitors independently.

It does not modify source resolution; it crops and scales visually.

It does not replace a full camera system or 3D tracking environment.

It cannot access cursor data if the operating system blocks it.

Recommended Setup Workflow

Add a Display Capture source.

Open Scripts and load the script.

Select your Zoom Source.

Bind hotkeys for:

Normal Zoom

Close-up

Macro

Nano

Pico

Their Hold variants

Tune:

Zoom speeds

Easing curves

Follow behavior

Test during recording before going live.

Final Notes

This script is built for people who care about visual clarity, smooth motion, and professional presentation.

It is not just a zoom toggle. It is a layered, configurable camera system for screen content.

Once configured properly, it becomes an essential part of high-quality tutorial and technical video production.
]]
    obs.script_log(obs.OBS_LOG_INFO, help)
end

function update_click_effect_status(props)
    prop = obs.obs_properties_get(props, "click_effect_status")
    if prop == nil then return end

    if not click_effect_enabled then
        obs.obs_property_set_long_description(prop, "Disabled.")
        return
    end

    src = obs.obs_get_source_by_name(click_effect_source_name)
    if src == nil then
        obs.obs_property_set_long_description(prop, "❌ Source not found. Create a source named '" .. click_effect_source_name .. "' in the current scene.")
        return
    end

    item = find_sceneitem_in_current_scene(click_effect_source_name)
    if item == nil then
        obs.obs_property_set_long_description(prop, "⚠️ Source exists but is not in the current scene hierarchy (or is inside a different scene).")
    else
        obs.obs_property_set_long_description(prop, "✅ Ready. Source found in current scene. Hotkey: 'Trigger click effect'.")
        obs.obs_sceneitem_release(item)
    end

    obs.obs_source_release(src)
end

function play_click_sound()
    if not click_sound_enabled then return end
    if click_sound_source_name == nil or click_sound_source_name == "" then return end
    s = obs.obs_get_source_by_name(click_sound_source_name)
    if s ~= nil then
        if obs.obs_source_media_restart ~= nil then
            if obs.obs_source_set_volume ~= nil then
                obs.obs_source_set_volume(s, click_sound_volume)
            end
            obs.obs_source_media_restart(s)
        else
            if not click_sound_warned then
                click_sound_warned = true
                obs.script_log(obs.OBS_LOG_WARNING, "[obs-better-zoom-to-mouse] Click sound requested, but obs_source_media_restart is not available in this OBS build.")
            end
        end
        obs.obs_source_release(s)
    else
        if not click_sound_warned then
            click_sound_warned = true
            obs.script_log(obs.OBS_LOG_WARNING, "[obs-better-zoom-to-mouse] Click sound source not found. Make sure the name matches the script setting exactly.")
        end
    end
end

function script_description()
function refresh_spotlight(find_newest)
    if find_newest then
        if spotlight_sceneitem ~= nil then obs.obs_sceneitem_release(spotlight_sceneitem) spotlight_sceneitem = nil end
        if spotlight_source ~= nil then obs.obs_source_release(spotlight_source) spotlight_source = nil end
        spotlight_info_orig = nil
        spotlight_visible_orig = nil

        if spotlight_source_name ~= nil and spotlight_source_name ~= "" then
            spotlight_source = obs.obs_get_source_by_name(spotlight_source_name)
            if spotlight_source ~= nil then
                spotlight_sceneitem = find_sceneitem_in_current_scene(spotlight_source_name)
                if spotlight_sceneitem ~= nil then
                    spotlight_info_orig = obs.obs_transform_info()
                    sceneitem_get_info(spotlight_sceneitem, spotlight_info_orig)
                    spotlight_visible_orig = obs.obs_sceneitem_visible(spotlight_sceneitem)
                    obs.obs_sceneitem_set_visible(spotlight_sceneitem, spotlight_enabled)
                else
                    obs.obs_source_release(spotlight_source)
                    spotlight_source = nil
                end
            end
        end
    else
        if spotlight_sceneitem ~= nil then
            obs.obs_sceneitem_set_visible(spotlight_sceneitem, spotlight_enabled)
        end
    end
end

function refresh_trail(find_newest)
    if find_newest then
        for _, t in ipairs(trail_items) do
            if t.item ~= nil then obs.obs_sceneitem_release(t.item) end
            if t.source ~= nil then obs.obs_source_release(t.source) end
        end
        trail_items = {}
        trail_buf = {}

        if trail_enabled and trail_count > 0 then
            for i=1, trail_count do
                nm = trail_source_prefix .. tostring(i)
                src = obs.obs_get_source_by_name(nm)
                if src ~= nil then
                    it = find_sceneitem_in_current_scene(nm)
                    if it ~= nil then
                        io = obs.obs_transform_info()
                        sceneitem_get_info(it, io)
                        vis = obs.obs_sceneitem_visible(it)
                        obs.obs_sceneitem_set_visible(it, false)
                        table.insert(trail_items, { source=src, item=it, info_orig=io, vis_orig=vis })
                    else
                        obs.obs_source_release(src)
                    end
                end
            end
        end
    else
        for _, t in ipairs(trail_items) do
            if t.item ~= nil then obs.obs_sceneitem_set_visible(t.item, false) end
        end
    end
end

function parse_keyframes(text)
    out = {}
    if text == nil then return out end
    for part in string.gmatch(text, "([^;]+)") do
        local name, rest = part:match("^%s*([^:]+)%s*:%s*(.+)%s*$")
        if name and rest then
            local x,y,z = rest:match("^%s*(-?[%d%.]+)%s*,%s*(-?[%d%.]+)%s*,%s*([%d%.]+)%s*$")
            if x and y and z then
                table.insert(out, { name = name, x = tonumber(x), y = tonumber(y), zoom = tonumber(z) })
            end
        end
    end
    return out
end


function get_current_settings_table()
    return {
        zoom_value = zoom_value,
        follow = use_auto_follow_mouse,
        follow_outside_bounds = use_follow_outside_bounds,
        follow_speed = follow_speed,
        follow_border = follow_border,
        follow_safezone_sensitivity = follow_safezone_sensitivity,
        follow_auto_lock = use_follow_auto_lock,
        click_effect_enabled = click_effect_enabled,
        click_effect_source_name = click_effect_source_name,
        click_effect_type = click_effect_type,
        click_effect_color = click_effect_color,
        click_effect_duration = click_effect_duration,
        click_effect_max_scale = click_effect_max_scale,
        click_effect_spin_degrees = click_effect_spin_degrees,
        click_effect_pulses = click_effect_pulses,
        spotlight_enabled = spotlight_enabled,
        spotlight_source_name = spotlight_source_name,
        spotlight_size = spotlight_size,
        spotlight_softness = spotlight_softness,
        spotlight_follow = spotlight_follow,
        trail_enabled = trail_enabled,
        trail_count = trail_count,
        trail_spacing = trail_spacing,
        trail_source_prefix = trail_source_prefix,
        easing_preset = easing_preset,
        follow_easing = follow_easing,
        keyframes_text = keyframes_text,
        motion_blur_enabled = motion_blur_enabled,
        motion_blur_filter_name = motion_blur_filter_name
    }
end

    return "Zoom the selected display-capture source to focus on the mouse"
end

function script_properties()

    props = obs.obs_properties_create()


    local __spacer_id = 0
    local function __spacer()
        __spacer_id = __spacer_id + 1
        obs.obs_properties_add_text(props, "sp_" .. tostring(__spacer_id), " ", obs.OBS_TEXT_INFO)
    end
    hdr_sources = obs.obs_properties_add_text(props, "hdr_sources", "Source selection", obs.OBS_TEXT_INFO)
    spacer_sources_zoom = obs.obs_properties_add_text(props, "spacer_sources_zoom", " ", obs.OBS_TEXT_INFO)
    __spacer()
    sources_list = obs.obs_properties_add_list(props, "source", "Zoom Source", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    __spacer()
    obs.obs_property_set_long_description(sources_list, "Select the source you want to zoom. Usually this is a Display Capture source in the current scene. The source name must exist in the active scene (or in a nested scene). If you rename sources or switch scenes, click Refresh zoom sources.")
    populate_zoom_sources(sources_list)

    refresh_sources = obs.obs_properties_add_button(props, "refresh", "Refresh zoom sources",
        function()
            populate_zoom_sources(sources_list)
            monitor_info = get_monitor_info(source)
            return true
        end)
    obs.obs_property_set_long_description(refresh_sources, UI_TOOLTIPS["refresh"])
    __spacer()

hdr_zoom_anim = obs.obs_properties_add_text(props, "hdr_zoom_anim", "Zoom Animation", obs.OBS_TEXT_INFO)
    zoom_factor = obs.obs_properties_add_float(props, "zoom_value", "Zoom Factor", 1, 5, 0.5)
    __spacer()
    obs.obs_property_set_long_description(zoom_factor, "How much to zoom in. 1.0 = no zoom. 1.5 is subtle and calm. 2.0 is strong. Higher values show less of the screen but give more detail.")
    __spacer()
    hold = obs.obs_properties_add_bool(props, "hold_to_zoom", "Hold-to-zoom ")
    __spacer()
    obs.obs_property_set_long_description(hold, UI_TOOLTIPS["hold_to_zoom"])



    __spacer()
    zoom_speed_in_prop = obs.obs_properties_add_float_slider(props, "zoom_speed_in", "Zoom Speed (In)", 0.001, 1.0, 0.001)
    __spacer()
    obs.obs_property_set_long_description(zoom_speed_in_prop, "Controls how fast the zoom-in animation plays. Lower values are slower and smoother. " ..
        "Typical cinematic range is around 0.30 to 0.60. Very slow motion starts below ~0.10.")

    zoom_speed_out_prop = obs.obs_properties_add_float_slider(props, "zoom_speed_out", "Zoom Speed (Out)", 0.001, 1.0, 0.001)
    __spacer()
    obs.obs_property_set_long_description(zoom_speed_out_prop, "Controls how fast the zoom-out animation plays. Lower values are slower and smoother. " ..
        "Typical cinematic range is around 0.25 to 0.55. A slightly slower zoom-out often feels more calm.")

    smooth_in_en = obs.obs_properties_add_bool(props, "zoom_smoothing_in_enabled", "Enable extra smoothing (In) ")
    __spacer()
    obs.obs_property_set_long_description(smooth_in_en, "Adds extra damping on top of the zoom-in easing curve. Enable this if you want a very calm camera that never looks jittery.")

    smooth_in = obs.obs_properties_add_float_slider(props, "zoom_smoothing_in", "Zoom smoothing strength (In)", 0.00, 0.50, 0.01)
    __spacer()
    obs.obs_property_set_long_description(smooth_in, "How strong the extra smoothing is during zoom-in. 0.00 = no extra smoothing. Higher values create slower, more damped motion.")

    smooth_out_en = obs.obs_properties_add_bool(props, "zoom_smoothing_out_enabled", "Enable extra smoothing (Out) ")
    __spacer()
    obs.obs_property_set_long_description(smooth_out_en, "Adds extra damping on top of the zoom-out easing curve. Useful for a gentle return to the full view.")

    smooth_out = obs.obs_properties_add_float_slider(props, "zoom_smoothing_out", "Zoom smoothing strength (Out)", 0.00, 0.50, 0.01)
    __spacer()
    obs.obs_property_set_long_description(smooth_out, "How strong the extra smoothing is during zoom-out. 0.00 = no extra smoothing. Higher values create slower, more damped motion.")


ease_list = obs.obs_properties_add_list(props, "easing_preset", "Zoom easing (In)", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
    __spacer()
    obs.obs_property_set_long_description(ease_list, "Easing curve used for the zoom-in animation. Different easings change how the zoom accelerates and decelerates. For calm tutorials, try Cinematic, Smooth, or Circular.")
    obs.obs_property_list_add_int(ease_list, "Linear", 0)
    obs.obs_property_list_add_int(ease_list, "Cinematic (quint in/out)", 1)
    obs.obs_property_list_add_int(ease_list, "Snappy (cubic out)", 2)
    obs.obs_property_list_add_int(ease_list, "Ease-out (quad)", 3)
    obs.obs_property_list_add_int(ease_list, "Classic (cubic in/out)", 4)
    obs.obs_property_list_add_int(ease_list, "Smooth (quad in/out)", 5)
    obs.obs_property_list_add_int(ease_list, "Heavy (quart in/out)", 6)
    obs.obs_property_list_add_int(ease_list, "Dramatic (expo in/out)", 7)
    obs.obs_property_list_add_int(ease_list, "Circular (circ in/out)", 8)
    obs.obs_property_list_add_int(ease_list, "Overshoot (back out)", 9)
    obs.obs_property_list_add_int(ease_list, "Bounce-out", 10)

    ease_out_list = obs.obs_properties_add_list(props, "zoom_out_easing", "Zoom easing (Out)", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
    __spacer()
    obs.obs_property_set_long_description(ease_out_list, "Easing curve used for the zoom-out animation. You can make zoom-out calmer or snappier than zoom-in. For a gentle return, try Cinematic or Smooth.")
    obs.obs_property_list_add_int(ease_out_list, "Linear", 0)
    obs.obs_property_list_add_int(ease_out_list, "Cinematic (quint in/out)", 1)
    obs.obs_property_list_add_int(ease_out_list, "Snappy (cubic out)", 2)
    obs.obs_property_list_add_int(ease_out_list, "Ease-out (quad)", 3)
    obs.obs_property_list_add_int(ease_out_list, "Classic (cubic in/out)", 4)
    obs.obs_property_list_add_int(ease_out_list, "Smooth (quad in/out)", 5)
    obs.obs_property_list_add_int(ease_out_list, "Heavy (quart in/out)", 6)
    obs.obs_property_list_add_int(ease_out_list, "Dramatic (expo in/out)", 7)
    obs.obs_property_list_add_int(ease_out_list, "Circular (circ in/out)", 8)
    obs.obs_property_list_add_int(ease_out_list, "Overshoot (back out)", 9)
    obs.obs_property_list_add_int(ease_out_list, "Bounce-out", 10)

    __spacer()
    closeup_enable = obs.obs_properties_add_bool(props, "enable_closeup_zoom", "Enable Close-up zoom ")
    __spacer()
    obs.obs_property_set_long_description(closeup_enable, UI_TOOLTIPS["enable_closeup_zoom"])
    __spacer()
    closeup_mult = obs.obs_properties_add_float_slider(props, "closeup_extra_multiplier", "Close-up extra zoom multiplier", 1.05, 3.00, 0.05)
    __spacer()
    obs.obs_property_set_long_description(closeup_mult, UI_TOOLTIPS["closeup_extra_multiplier"])
    __spacer()
    closeup_hold = obs.obs_properties_add_bool(props, "hold_to_zoom_closeup", "Hold-to-zoom (Close-up) ")
    __spacer()
    obs.obs_property_set_long_description(closeup_hold, "When enabled, pressing the Close-up hotkey will zoom in to Close-up only while you hold the key. Releasing the key zooms back out. Turn this off if you prefer a toggle.")
    __spacer()
    macro_enable = obs.obs_properties_add_bool(props, "enable_macro_zoom", "Enable Macro zoom ")
    __spacer()
    obs.obs_property_set_long_description(macro_enable, UI_TOOLTIPS["enable_macro_zoom"])
    __spacer()
    macro_mult = obs.obs_properties_add_float_slider(props, "macro_extra_multiplier", "Macro extra zoom multiplier", 1.10, 5.00, 0.05)
    __spacer()
    obs.obs_property_set_long_description(macro_mult, UI_TOOLTIPS["macro_extra_multiplier"])
    __spacer()
    macro_hold = obs.obs_properties_add_bool(props, "hold_to_zoom_macro", "Hold-to-zoom (Macro) ")
    __spacer()
    obs.obs_property_set_long_description(macro_hold, "Same idea as Hold-to-zoom, but for the Macro hotkey.")



    __spacer()
    nano_enable = obs.obs_properties_add_bool(props, "enable_nano_zoom", "Enable Nano zoom ")
    __spacer()
    obs.obs_property_set_long_description(nano_enable, UI_TOOLTIPS["enable_nano_zoom"])
    __spacer()
    nano_mult = obs.obs_properties_add_float_slider(props, "nano_extra_multiplier", "Nano extra zoom multiplier", 1.10, 8.00, 0.05)
    __spacer()
    obs.obs_property_set_long_description(nano_mult, UI_TOOLTIPS["nano_extra_multiplier"])
    __spacer()
    nano_hold = obs.obs_properties_add_bool(props, "hold_to_zoom_nano", "Hold-to-zoom (Nano) ")
    __spacer()
    obs.obs_property_set_long_description(nano_hold, "Same idea as Hold-to-zoom, but for the Nano hotkey.")

    __spacer()
    pico_enable = obs.obs_properties_add_bool(props, "enable_pico_zoom", "Enable Pico zoom ")
    __spacer()
    obs.obs_property_set_long_description(pico_enable, UI_TOOLTIPS["enable_pico_zoom"])
    __spacer()
    pico_mult = obs.obs_properties_add_float_slider(props, "pico_extra_multiplier", "Pico extra zoom multiplier", 1.10, 12.00, 0.05)
    __spacer()
    obs.obs_property_set_long_description(pico_mult, UI_TOOLTIPS["pico_extra_multiplier"])
    __spacer()
    pico_hold = obs.obs_properties_add_bool(props, "hold_to_zoom_pico", "Hold-to-zoom (Pico) ")
    __spacer()
    obs.obs_property_set_long_description(pico_hold, "Same idea as Hold-to-zoom, but for the Pico hotkey.")

    local spacer_anim_levels = obs.obs_properties_add_text(props, "__spacer_anim_levels", " ", obs.OBS_TEXT_INFO)

    local hdr_anim_levels = obs.obs_properties_add_text(props, "__hdr_anim_levels", "Per-Zoom-Level Animation Overrides", obs.OBS_TEXT_INFO)
    obs.obs_property_set_long_description(hdr_anim_levels, "Optional advanced controls. These settings let you make each zoom level feel different. If you leave them as-is, they behave like the base zoom animation.")

    local function add_level_anim_controls(level_key, pretty_name)
        local h = obs.obs_properties_add_text(props, "__hdr_anim_" .. level_key, pretty_name .. " animation", obs.OBS_TEXT_INFO)
        obs.obs_property_set_long_description(h, "Animation controls used when switching to this zoom level with its hotkey.")

        local sp_in = obs.obs_properties_add_float_slider(props, level_key .. "_zoom_speed_in", pretty_name .. " zoom speed IN", 0.001, 1.000, 0.001)
        obs.obs_property_set_long_description(sp_in, "How fast the zoom-IN animation plays for " .. pretty_name .. ". Lower values are slower and smoother.")

        local sp_out = obs.obs_properties_add_float_slider(props, level_key .. "_zoom_speed_out", pretty_name .. " zoom speed OUT", 0.001, 1.000, 0.001)
        obs.obs_property_set_long_description(sp_out, "How fast the zoom-OUT animation plays for " .. pretty_name .. ". Lower values are slower and smoother.")

        local ei = obs.obs_properties_add_list(props, level_key .. "_zoom_easing_in", pretty_name .. " easing IN", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
        add_zoom_easing_items(ei)
        obs.obs_property_set_long_description(ei, "Easing curve for zooming IN to " .. pretty_name .. ".")

        local eo = obs.obs_properties_add_list(props, level_key .. "_zoom_easing_out", pretty_name .. " easing OUT", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
        add_zoom_easing_items(eo)
        obs.obs_property_set_long_description(eo, "Easing curve for zooming OUT from " .. pretty_name .. " back to the full view.")

        local sp2 = obs.obs_properties_add_text(props, "__spacer_anim_" .. level_key, " ", obs.OBS_TEXT_INFO)
    end

    add_level_anim_controls("closeup", "Close-up")
    add_level_anim_controls("macro", "Macro")
    add_level_anim_controls("nano", "Nano")
    add_level_anim_controls("pico", "Pico")
    spacer_zoom_follow = obs.obs_properties_add_text(props, "spacer_zoom_follow", " ", obs.OBS_TEXT_INFO)
hdr_follow_beh = obs.obs_properties_add_text(props, "hdr_follow_beh", "Follow Behaviour", obs.OBS_TEXT_INFO)

    follow = obs.obs_properties_add_bool(props, "follow", "Auto follow cursor ")
    __spacer()
    obs.obs_property_set_long_description(follow, "When enabled mouse tracking will auto-start when zoomed in without waiting for tracking toggle hotkey")
    __spacer()
    smooth = obs.obs_properties_add_float_slider(props, "mouse_smoothing", "Mouse smoothing", 0.0, 0.95, 0.01)
    __spacer()
    obs.obs_property_set_long_description(smooth, "Smooths the mouse/cursor input before it is used for zoom targeting and follow tracking. Increase this if your cursor position feels jittery. 0 turns it off.")

    follow_outside_bounds = obs.obs_properties_add_bool(props, "follow_outside_bounds", "Follow outside bounds ")
    __spacer()
    obs.obs_property_set_long_description(follow_outside_bounds, "When enabled the mouse will be tracked even when the cursor is outside the bounds of the zoom source")
    
    smart_pred = obs.obs_properties_add_bool(props, "smart_prediction_enabled", "Enable smart prediction ")
    __spacer()
    obs.obs_property_set_long_description(smart_pred,
        "When enabled, the camera predicts the cursor direction and slightly leads it. " ..
        "This can feel more responsive, but on some content it may look strange, so keep it optional.")

    obs.obs_properties_add_float_slider(props, "smart_prediction_strength", "Smart prediction strength (s)", 0.00, 0.50, 0.01)
    __spacer()

    adaptive_sm = obs.obs_properties_add_bool(props, "adaptive_smoothing_enabled", "Adaptive smoothing ")
    __spacer()
    obs.obs_property_set_long_description(adaptive_sm,
        "Automatically adjusts follow speed based on how far the cursor moved. " ..
        "Small moves stay smooth; big jumps catch up faster.")

    obs.obs_properties_add_float_slider(props, "adaptive_smoothing_strength", "Adaptive smoothing strength", 0.00, 2.00, 0.01)
    __spacer()
    obs.obs_properties_add_float_slider(props, "adaptive_smoothing_min", "Adaptive smoothing min follow", 0.01, 1.00, 0.01)
    __spacer()
    obs.obs_properties_add_float_slider(props, "adaptive_smoothing_max", "Adaptive smoothing max follow", 0.01, 1.00, 0.01)
    __spacer()


    obs.obs_properties_add_float_slider(props, "follow_speed", "Follow Speed", 0.01, 1, 0.01)
    __spacer()
    obs.obs_property_set_long_description(obs.obs_properties_get(props, "follow_speed"), UI_TOOLTIPS["follow_speed"])
    __spacer()
    follow_jelly = obs.obs_properties_add_float_slider(props, "jelly_follow_strength", "Jelly smoothing", 0.00, 1.00, 0.01)
    __spacer()
    obs.obs_property_set_long_description(follow_jelly, UI_TOOLTIPS["jelly_follow_strength"])
    __spacer()
    obs.obs_properties_add_int_slider(props, "follow_border", "Follow Border", 0, 50, 1)
    __spacer()
    obs.obs_property_set_long_description(obs.obs_properties_get(props, "follow_border"), UI_TOOLTIPS["follow_border"])
    __spacer()
    obs.obs_properties_add_int_slider(props, "follow_safezone_sensitivity", "Lock Sensitivity", 1, 20, 1)
    __spacer()

    obs.obs_property_set_long_description(obs.obs_properties_get(props, "follow_safezone_sensitivity"), UI_TOOLTIPS["follow_safezone_sensitivity"])
    __spacer()
    follow_auto_lock = obs.obs_properties_add_bool(props, "follow_auto_lock", "Auto Lock on reverse direction ")
    __spacer()
    obs.obs_property_set_long_description(follow_auto_lock,
        "When enabled moving the mouse to edge of the zoom source will begin tracking, " ..
        "but moving back towards the center will stop tracking simliar to panning the camera in a RTS game")
allow_all = obs.obs_properties_add_bool(props, "allow_all_sources", "Allow any zoom source ")
    __spacer()
    obs.obs_property_set_long_description(allow_all, "Enable to allow selecting any source as the Zoom Source " ..
        "You MUST set manual source position for non-display capture sources")
override = obs.obs_properties_add_bool(props, "use_monitor_override", "Set manual source position ")
    __spacer()
    obs.obs_property_set_long_description(override, "When enabled the specified size/position settings will be used for the zoom source instead of the auto-calculated ones")

    override_x = obs.obs_properties_add_int(props, "monitor_override_x", "X", -10000, 10000, 1)
    __spacer()
    obs.obs_property_set_long_description(override_x, "Top-left X of the captured monitor/source in desktop coordinates.")
    override_y = obs.obs_properties_add_int(props, "monitor_override_y", "Y", -10000, 10000, 1)
    __spacer()
    obs.obs_property_set_long_description(override_y, "Top-left Y of the captured monitor/source in desktop coordinates.")
    override_w = obs.obs_properties_add_int(props, "monitor_override_w", "Width", 0, 10000, 1)
    __spacer()
    obs.obs_property_set_long_description(override_w, "Width of the captured area in pixels.")
    override_h = obs.obs_properties_add_int(props, "monitor_override_h", "Height", 0, 10000, 1)
    __spacer()
    obs.obs_property_set_long_description(override_h, "Height of the captured area in pixels.")
    override_sx = obs.obs_properties_add_float(props, "monitor_override_sx", "Scale X ", 0, 100, 0.01)
    obs.obs_property_set_long_description(override_sx, UI_TOOLTIPS["monitor_override_sx"])
    __spacer()
    override_sy = obs.obs_properties_add_float(props, "monitor_override_sy", "Scale Y ", 0, 100, 0.01)
    obs.obs_property_set_long_description(override_sy, UI_TOOLTIPS["monitor_override_sy"])
    __spacer()
    override_dw = obs.obs_properties_add_int(props, "monitor_override_dw", "Monitor Width ", 0, 10000, 1)
    obs.obs_property_set_long_description(override_dw, UI_TOOLTIPS["monitor_override_dw"])
    __spacer()
    override_dh = obs.obs_properties_add_int(props, "monitor_override_dh", "Monitor Height ", 0, 10000, 1)
    obs.obs_property_set_long_description(override_dh, UI_TOOLTIPS["monitor_override_dh"])
    __spacer()

    obs.obs_property_set_long_description(override_sx, "Usually 1 - unless you are using a scaled source")
    obs.obs_property_set_long_description(override_sy, "Usually 1 - unless you are using a scaled source")
    obs.obs_property_set_long_description(override_dw, "X resolution of your monitor")
    obs.obs_property_set_long_description(override_dh, "Y resolution of your monitor")

click_en = obs.obs_properties_add_bool(props, "click_effect_enabled", "Click effect enabled ")
    __spacer()
        obs.obs_property_set_long_description(click_en, "Show a brief animation at the cursor position when you press the click-effect hotkey.")


click_note = obs.obs_properties_add_text(props, "click_effect_note", "Click effect setup", obs.OBS_TEXT_INFO)
obs.obs_property_set_long_description(click_note,
    "Create a source in your scene named exactly '" .. click_effect_source_name .. "'." ..
    " Recommended: Image Source with a ring PNG (transparent background)." ..
    " Alternative: Color Source (color picker below applies)." ..
    " Then set a hotkey for 'Trigger click effect' in OBS.")

click_status = obs.obs_properties_add_text(props, "click_effect_status", "Click effect status", obs.OBS_TEXT_INFO)
    __spacer()
obs.obs_property_set_long_description(click_status, "Status updates when you change settings, click Refresh, or press Test.")

click_src = obs.obs_properties_add_text(props, "click_effect_source_name", "Click effect source name", obs.OBS_TEXT_DEFAULT)
    obs.obs_property_set_long_description(click_src, UI_TOOLTIPS["click_effect_source_name"])
    __spacer()
    info_click_name_match = obs.obs_properties_add_text(props, "info_click_name_match", "Important: source name must match", obs.OBS_TEXT_INFO)
    obs.obs_property_set_long_description(info_click_name_match, "The source name you type above must be exactly the same as the source name in your current scene. If OBS cannot find it, the effect will not show. Tip: copy the name from the Sources list and paste it here.")
        obs.obs_property_set_long_description(click_src, "Name of an existing source in the current scene used for the click animation.")
        obs.obs_property_set_long_description(click_src,
            "Name of an existing source in the current scene used as the click effect (e.g. an Image Source with a ring, or a Color Source)." ..
            " Tip: Create a small ring PNG image source named 'Click Effect' and set it to hidden by default; the script will show/move it when triggered.")

        click_type = obs.obs_properties_add_list(props, "click_effect_type", "Click effect type", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
    __spacer()
        obs.obs_property_set_long_description(click_type, "Pick the animation style (scale/rotation curve).")
obs.obs_property_list_add_int(click_type, "Pulse", 0)
obs.obs_property_list_add_int(click_type, "Ripple", 1)
obs.obs_property_list_add_int(click_type, "Pop", 2)
obs.obs_property_list_add_int(click_type, "Bounce", 3)
obs.obs_property_list_add_int(click_type, "Radar (multi-pulse)", 4)
obs.obs_property_list_add_int(click_type, "Ping (quick)", 5)
obs.obs_property_list_add_int(click_type, "Spiral", 6)
obs.obs_property_list_add_int(click_type, "Wobble", 7)
        
obs.obs_property_list_add_int(click_type, "Double Ring", 8)
obs.obs_property_list_add_int(click_type, "Flash", 9)
obs.obs_property_list_add_int(click_type, "Elastic", 10)
obs.obs_property_list_add_int(click_type, "Drift", 11)
obs.obs_property_list_add_int(click_type, "Heartbeat", 12)
obs.obs_property_list_add_int(click_type, "Snap", 13)
click_col = obs.obs_properties_add_color_alpha(props, "click_effect_color", "Click effect color")
    __spacer()
        obs.obs_property_set_long_description(click_col, "Only used if the click effect source is a Color Source.")

        obs.obs_properties_add_float_slider(props, "click_effect_duration", "Click effect duration (s)", 0.10, 1.00, 0.01)
    __spacer()
        obs.obs_properties_add_float_slider(props, "click_effect_max_scale", "Click effect max scale", 1.10, 6.00, 0.10)
    __spacer()


        obs.obs_properties_add_float_slider(props, "click_effect_spin_degrees", "Click effect spin (degrees)", -1080, 1080, 5)
    __spacer()
        obs.obs_properties_add_int_slider(props, "click_effect_pulses", "Click effect pulses", 1, 6, 1)
    __spacer()
spot_en = obs.obs_properties_add_bool(props, "spotlight_enabled", "Enable spotlight overlay ")
    __spacer()
obs.obs_property_set_long_description(spot_en, "Shows a spotlight overlay at the cursor. Requires a scene source named in 'Spotlight source name'.")

spot_src = obs.obs_properties_add_text(props, "spotlight_source_name", "Spotlight source name", obs.OBS_TEXT_DEFAULT)
    obs.obs_property_set_long_description(spot_src, UI_TOOLTIPS["spotlight_source_name"])
    __spacer()
    info_spotlight_name_match = obs.obs_properties_add_text(props, "info_spotlight_name_match", "Important: spotlight source name must match", obs.OBS_TEXT_INFO)
    obs.obs_property_set_long_description(info_spotlight_name_match, "Create or choose a source in your scene (for example an Image Source with a soft circle PNG). The source name in OBS must match the name you type here exactly.")
obs.obs_property_set_long_description(spot_src, "Name of an existing source in the current scene (recommended: Image Source with feathered circle PNG).")

obs.obs_properties_add_int_slider(props, "spotlight_size", "Spotlight size (px)", 50, 1200, 10)
    __spacer()
obs.obs_properties_add_float_slider(props, "spotlight_softness", "Spotlight softness", 0.0, 1.0, 0.01)
    __spacer()

spot_follow = obs.obs_properties_add_bool(props, "spotlight_follow", "Spotlight follows cursor ")
    __spacer()
obs.obs_property_set_long_description(spot_follow, "When enabled, the spotlight element tracks the cursor each frame.")

trail_en = obs.obs_properties_add_bool(props, "trail_enabled", "Enable cursor trail ")
    __spacer()
obs.obs_property_set_long_description(trail_en, "Requires sources: 'Cursor Trail 1'..'Cursor Trail N' (duplicates of a small ring/dot).")

obs.obs_properties_add_int_slider(props, "trail_count", "Trail count", 1, 12, 1)
    __spacer()
obs.obs_properties_add_float_slider(props, "trail_spacing", "Trail spacing (s)", 0.01, 0.20, 0.01)
    __spacer()
obs.obs_properties_add_text(props, "trail_source_prefix", "Trail source prefix", obs.OBS_TEXT_DEFAULT)
    __spacer()

    info_trail_names = obs.obs_properties_add_text(props, "info_trail_names", "Important: trail sources must exist", obs.OBS_TEXT_INFO)
    obs.obs_property_set_long_description(info_trail_names, "To use trail, you must create multiple sources in your scene: Cursor Trail 1, Cursor Trail 2, etc. The prefix must match and the numbers must start at 1.")


follow_list = obs.obs_properties_add_list(props, "follow_easing", "Follow easing", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
    obs.obs_property_set_long_description(follow_list, UI_TOOLTIPS["follow_easing"])
    __spacer()
obs.obs_property_list_add_int(follow_list, "Linear", 0)
obs.obs_property_list_add_int(follow_list, "Ease-out", 1)
obs.obs_property_list_add_int(follow_list, "Ease-in/out", 2)

kf_text = obs.obs_properties_add_text(props, "keyframes_text", "Keyframes", obs.OBS_TEXT_MULTILINE)
obs.obs_property_set_long_description(kf_text, "Format: name:x,y,zoom;name2:x,y,zoom (x/y are source coords after offsets/crop). Example: Intro:960,540,2;Detail:1400,600,3")

mb_en = obs.obs_properties_add_bool(props, "motion_blur_enabled", "Enable motion blur (filter) ")
    __spacer()
obs.obs_property_set_long_description(mb_en, "Requires a filter plugin. Script enables/disables a filter with the name below on the Zoom Source.")

mb_name = obs.obs_properties_add_text(props, "motion_blur_filter_name", "Motion blur filter name", obs.OBS_TEXT_DEFAULT)
    obs.obs_property_set_long_description(mb_name, UI_TOOLTIPS["motion_blur_filter_name"])
    __spacer()
    info_blur_filter = obs.obs_properties_add_text(props, "info_blur_filter", "Important: filter name must match", obs.OBS_TEXT_INFO)
    obs.obs_property_set_long_description(info_blur_filter, "Motion blur is toggled by enabling/disabling a filter on the Zoom Source. The filter name in OBS must match this setting exactly. If you do not have a blur filter plugin, keep this feature disabled.")
obs.obs_property_set_long_description(mb_name, "Name of the filter on the Zoom Source (e.g. StreamFX/ShaderFilter).")
help = obs.obs_properties_add_button(props, "help_button", "More Info", on_print_help)
    __spacer()
    obs.obs_property_set_long_description(help, "Click to show help information (via the script log)")

    debug = obs.obs_properties_add_bool(props, "debug_logs", "Enable debug logging ")
    __spacer()
    obs.obs_property_set_long_description(debug, "When enabled the script will output diagnostics messages to the script log (useful for debugging/github issues)")

    obs.obs_property_set_visible(override_x, use_monitor_override)
    obs.obs_property_set_visible(override_y, use_monitor_override)
    obs.obs_property_set_visible(override_w, use_monitor_override)
    obs.obs_property_set_visible(override_h, use_monitor_override)
    obs.obs_property_set_visible(override_sx, use_monitor_override)
    obs.obs_property_set_visible(override_sy, use_monitor_override)
    obs.obs_property_set_visible(override_dw, use_monitor_override)
    obs.obs_property_set_visible(override_dh, use_monitor_override)
    obs.obs_property_set_modified_callback(override, on_settings_modified)
    obs.obs_property_set_modified_callback(allow_all, on_settings_modified)
    obs.obs_property_set_modified_callback(debug, on_settings_modified)

    -- Apply tooltips for ALL UI elements
    _tt = {
        ["hdr_sources"] = "Choose which OBS sources the script will use. Start here.",
        ["hdr_zoom_anim"] = "How the zoom animation behaves: zoom amount, zoom speed and cinematic feel.",
        ["hdr_follow_beh"] = "How the camera follows your cursor while zoomed in.",
        ["hdr_safety"] = "Rules that stop the camera from moving too much: borders, locks and safe zones.",
        ["hdr_fx_click"] = "Click animations shown around the cursor. Great for tutorials.",
        ["hdr_fx_overlay"] = "Overlays like spotlight, cursor trail and motion blur.",
        ["hdr_brand"] = "Save and load your branding presets and keyframe positions.",
        ["adaptive_smoothing_enabled"] = "Adaptive smoothing: small moves are very smooth, big jumps speed up automatically.",
        ["adaptive_smoothing_max"] = "Maximum follow speed for large moves.",
        ["adaptive_smoothing_min"] = "Minimum follow speed for small moves.",
        ["adaptive_smoothing_strength"] = "How much extra follow speed is added when the cursor jumps far.",
        ["allow_all_sources"] = "Allow selecting any source as zoom source (not only Display Capture). If enabled, you may need Manual Source Position so coordinates match.",
        ["click_effect_color"] = "Color (with alpha) applied to the click effect, so it can match your branding.",
        ["click_effect_duration"] = "How long the click animation is visible (seconds).",
        ["click_effect_enabled"] = "Enable click animation. When enabled, press the Click FX hotkey to play an animation around the cursor.",
        ["click_effect_max_scale"] = "How large the click effect can grow at peak.",
        ["click_effect_note"] = "This is a reminder text only. Create the required sources/filters in OBS and make sure names match these settings.",
        ["click_effect_pulses"] = "Only used by multi-pulse styles. Higher = more pulses.",
        ["click_effect_source_name"] = "Name of an existing source in your current scene used as the click effect graphic. Important: this must match the OBS source name exactly (spaces + capitals).",
        ["click_effect_spin_degrees"] = "How much the click effect rotates during the animation.",
        ["click_effect_status"] = "Status indicator showing whether required sources were found.",
        ["click_effect_type"] = "Pick the animation style. Different types change the scale curve and feel.",
        ["click_sound_enabled"] = "Play a short click sound when you trigger click FX. Requires a Media Source.",
        ["click_sound_source_name"] = "Name of the Media Source to play. Must match exactly.",
        ["click_sound_volume"] = "Volume for the click sound.",
        ["debug_logs"] = "Enable verbose debugging logs (useful for troubleshooting).",
        ["easing_preset"] = "Preset for zoom animation curve. Cinematic feels smooth. Snappy feels quick.",
        ["follow"] = "When enabled, the camera automatically starts following your cursor after you zoom in. If disabled, you can still toggle follow with the follow hotkey.",
        ["follow_auto_lock"] = "If enabled, the camera can stop tracking when you reverse direction. Feels like RTS panning: move toward edge to pan, move back to center to stop.",
        ["follow_border"] = "Safe zone size. 50 means: track again quickly as you move away from the center. Lower values mean: cursor must approach the edge before tracking resumes.",
        ["follow_easing"] = "How the follow movement feels. Linear is direct. Ease-out feels smoother.",
        ["follow_outside_bounds"] = "When enabled, the camera keeps tracking even if your cursor moves outside the capture area. Useful for multi-monitor setups or when the cursor briefly leaves the captured region.",
        ["follow_safezone_sensitivity"] = "How close the camera must get to the target before it 'locks' and stops moving. Lower values lock sooner and feel steadier.",
        ["follow_speed"] = "Base follow speed. Lower values are smoother (but may lag). Higher values are more responsive.",
        ["help_button"] = "Print help and troubleshooting info into the OBS Script Log.",
        ["hold_to_zoom"] = "If enabled, zoom stays active only while you hold the zoom hotkey. When you release, it zooms back out.",
        ["info_blur_filter"] = "Reminder: blur filter name must match exactly.",
        ["info_click_name_match"] = "Reminder: the source name must match exactly.",
        ["info_click_sound_name"] = "Reminder: click sound source name must match exactly.",
        ["info_spotlight_name_match"] = "Reminder: the spotlight source name must match exactly.",
        ["info_trail_names"] = "Reminder: trail sources must exist and follow the naming pattern.",
        ["keyframes_text"] = "Define keyframe zoom positions you can jump to. Format: Name:x,y,zoom;Name2:x,y,zoom Example: Intro:960,540,1.5;Detail:1400,620,2.5",
        ["monitor_override_dh"] = "Physical monitor height in pixels (used for some platform conversions).",
        ["monitor_override_dw"] = "Physical monitor width in pixels (used for some platform conversions).",
        ["monitor_override_h"] = "Height of the captured area in pixels (usually your monitor resolution).",
        ["monitor_override_sx"] = "Mouse scale factor X. Usually 1.0. Use if the source is scaled (e.g. scene clone).",
        ["monitor_override_sy"] = "Mouse scale factor Y. Usually 1.0. Use if the source is scaled (e.g. scene clone).",
        ["monitor_override_w"] = "Width of the captured area in pixels (usually your monitor resolution).",
        ["monitor_override_x"] = "Top-left X of the captured source on the full desktop (can be negative with multi-monitor).",
        ["monitor_override_y"] = "Top-left Y of the captured source on the full desktop (can be negative with multi-monitor).",
        ["motion_blur_enabled"] = "Enable motion blur toggle. This turns a filter on/off on the Zoom Source. Requires a blur filter plugin.",
        ["motion_blur_filter_name"] = "Name of the blur filter on the Zoom Source. Must match exactly.",
        ["mouse_smoothing"] = "Extra smoothing to reduce jitter. Higher values reduce shake but add lag.",
        ["refresh"] = "Re-scan your OBS sources and update the 'Zoom Source' dropdown. Use this if you renamed sources or added a new capture source.",
        ["section_click"] = "Click animation settings. Requires a source in your scene; the name must match exactly.",
        ["section_follow"] = "Zoom and follow behaviour. These settings control how the camera moves.",
        ["section_fx"] = "Visual effects. Click effects, spotlight, trail and motion blur.",
        ["section_override"] = "Manual position/size settings. Only needed if cursor alignment is wrong.",
        ["section_presets"] = "Presets and keyframes. Save/load brand profiles and define keyframe jump points.",
        ["section_sources"] = "Pick which OBS source the script should control. Usually your Display Capture source.",
        ["smart_prediction_enabled"] = "Predict cursor movement slightly ahead so the camera leads instead of lags.",
        ["smart_prediction_strength"] = "How far ahead the prediction looks (seconds).",
        ["source"] = "Select which source in your current scene will be zoomed and followed. Usually this is your Display Capture source. Tip: the source must exist in the current scene (or inside a nested scene).",
        ["spotlight_enabled"] = "Enable spotlight overlay. Shows a soft branded spotlight around the cursor.",
        ["spotlight_follow"] = "If enabled, spotlight follows the cursor continuously.",
        ["spotlight_size"] = "How big the spotlight appears on your canvas.",
        ["spotlight_softness"] = "Extra smoothing for spotlight movement/size to make it feel softer.",
        ["spotlight_source_name"] = "Name of the spotlight source in your scene. Must match exactly.",
        ["trail_count"] = "How many trail sources to use. More looks smoother but costs performance.",
        ["trail_enabled"] = "Enable cursor trail. Requires multiple trail sources in your scene.",
        ["trail_source_prefix"] = "Prefix for trail sources. The script expects: Prefix 1, Prefix 2, etc.",
        ["trail_spacing"] = "Spacing/delay between trail elements. Higher makes a longer trail.",
        ["use_monitor_override"] = "Use manual position/size values instead of auto-detect. Turn on if the zoom does not line up with your cursor.",
        ["zoom_value"] = "How much to zoom in. 1.0 means no zoom. 1.5 is subtle. 2.0+ is strong. Used when you press the zoom hotkey.",
    }
    for id, text in pairs(_tt) do
        p = obs.obs_properties_get(props, id)
        if p ~= nil then
            obs.obs_property_set_long_description(p, text)
        end
    end


    __spacer()
    obs.obs_properties_add_text(props, "hdr_platform_status", "Platform status", obs.OBS_TEXT_INFO)
    obs.obs_properties_add_text(props, "status_line_1", platform_status_line_1(), obs.OBS_TEXT_INFO)
    obs.obs_properties_add_text(props, "status_line_2", platform_status_line_2(), obs.OBS_TEXT_INFO)
    obs.obs_properties_add_text(props, "status_line_3", platform_status_line_3(), obs.OBS_TEXT_INFO)
    obs.obs_properties_add_text(props, "status_hint", "Tip: If cursor tracking feels wrong on Linux, you may be on Wayland. Switch to an X11 session for full support.", obs.OBS_TEXT_INFO)
    __spacer()
    return props
end

function script_load(settings)
    
    __current_settings = settings
detect_platform_status()
    log_platform_warnings_once()
    sceneitem_info_orig = nil

    hotkey_zoom_id = obs.obs_hotkey_register_frontend("toggle_zoom_hotkey", "Toggle zoom to mouse", on_toggle_zoom)
    hotkey_follow_id = obs.obs_hotkey_register_frontend("toggle_follow_hotkey", "Toggle follow mouse during zoom", on_toggle_follow)
hotkey_hold_zoom_id = obs.obs_hotkey_register_frontend("hold_zoom_hotkey", "Hold Zoom (press to zoom, release to reset)", on_hold_zoom)
    hotkey_closeup_id = obs.obs_hotkey_register_frontend("toggle_closeup_hotkey", "Zoom Close-up (extra zoom)", on_toggle_closeup)
    hotkey_macro_id = obs.obs_hotkey_register_frontend("toggle_macro_hotkey", "Zoom Macro (extra zoom)", on_toggle_macro)
    hotkey_nano_id = obs.obs_hotkey_register_frontend("toggle_nano_hotkey", "Zoom Nano (extra zoom)", on_toggle_nano)
    hotkey_pico_id = obs.obs_hotkey_register_frontend("toggle_pico_hotkey", "Zoom Pico (extra zoom)", on_toggle_pico)

    hotkey_hold_closeup_id = obs.obs_hotkey_register_frontend("hold_closeup_hotkey", "Hold Close-up (press to zoom, release to reset)", on_hold_closeup)
    hotkey_hold_macro_id = obs.obs_hotkey_register_frontend("hold_macro_hotkey", "Hold Macro (press to zoom, release to reset)", on_hold_macro)
    hotkey_hold_nano_id = obs.obs_hotkey_register_frontend("hold_nano_hotkey", "Hold Nano (press to zoom, release to reset)", on_hold_nano)
    hotkey_hold_pico_id = obs.obs_hotkey_register_frontend("hold_pico_hotkey", "Hold Pico (press to zoom, release to reset)", on_hold_pico)


    hotkey_spotlight_id = obs.obs_hotkey_register_frontend("toggle_spotlight_hotkey", "Toggle spotlight overlay", on_toggle_spotlight)
    hotkey_trail_id = obs.obs_hotkey_register_frontend("toggle_trail_hotkey", "Toggle cursor trail", on_toggle_trail)
    hotkey_keyframe_next_id = obs.obs_hotkey_register_frontend("keyframe_next_hotkey", "Next keyframe zoom", on_keyframe_next)
    hotkey_keyframe_prev_id = obs.obs_hotkey_register_frontend("keyframe_prev_hotkey", "Previous keyframe zoom", on_keyframe_prev)
    hotkey_motion_blur_id = obs.obs_hotkey_register_frontend("toggle_motion_blur_hotkey", "Toggle motion blur (filter)", on_toggle_motion_blur)
    hotkey_click_id = obs.obs_hotkey_register_frontend("toggle_click_effect_hotkey", "Trigger click effect", on_trigger_click_effect)
    hotkey_save_array = obs.obs_data_get_array(settings, "obs_zoom_to_mouse.hotkey.zoom")
    obs.obs_hotkey_load(hotkey_zoom_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    hotkey_save_array = obs.obs_data_get_array(settings, "obs_zoom_to_mouse.hotkey.follow")
    obs.obs_hotkey_load(hotkey_follow_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)



    hotkey_save_array = obs.obs_data_get_array(settings, "obs_zoom_to_mouse.hotkey.hold_zoom")
    obs.obs_hotkey_load(hotkey_hold_zoom_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
    hotkey_save_array = obs.obs_data_get_array(settings, "obs_zoom_to_mouse.hotkey.closeup")
    obs.obs_hotkey_load(hotkey_closeup_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    hotkey_save_array = obs.obs_data_get_array(settings, "obs_zoom_to_mouse.hotkey.macro")
    obs.obs_hotkey_load(hotkey_macro_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)


    hotkey_save_array = obs.obs_data_get_array(settings, "obs_zoom_to_mouse.hotkey.nano")
    obs.obs_hotkey_load(hotkey_nano_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    hotkey_save_array = obs.obs_data_get_array(settings, "obs_zoom_to_mouse.hotkey.pico")
    obs.obs_hotkey_load(hotkey_pico_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)


    hotkey_save_array = obs.obs_data_get_array(settings, "obs_zoom_to_mouse.hotkey.hold_closeup")
    obs.obs_hotkey_load(hotkey_hold_closeup_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    hotkey_save_array = obs.obs_data_get_array(settings, "obs_zoom_to_mouse.hotkey.hold_macro")
    obs.obs_hotkey_load(hotkey_hold_macro_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    hotkey_save_array = obs.obs_data_get_array(settings, "obs_zoom_to_mouse.hotkey.hold_nano")
    obs.obs_hotkey_load(hotkey_hold_nano_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    hotkey_save_array = obs.obs_data_get_array(settings, "obs_zoom_to_mouse.hotkey.hold_pico")
    obs.obs_hotkey_load(hotkey_hold_pico_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    hotkey_save_array = obs.obs_data_get_array(settings, "obs_zoom_to_mouse.hotkey.click")
    obs.obs_hotkey_load(hotkey_click_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
    zoom_value = obs.obs_data_get_double(settings, "zoom_value")
    enable_closeup_zoom = obs.obs_data_get_bool(settings, "enable_closeup_zoom")
    closeup_extra_multiplier = obs.obs_data_get_double(settings, "closeup_extra_multiplier")
    enable_macro_zoom = obs.obs_data_get_bool(settings, "enable_macro_zoom")
    macro_extra_multiplier = obs.obs_data_get_double(settings, "macro_extra_multiplier")
    enable_nano_zoom = obs.obs_data_get_bool(settings, "enable_nano_zoom")
    nano_extra_multiplier = obs.obs_data_get_double(settings, "nano_extra_multiplier")
    enable_pico_zoom = obs.obs_data_get_bool(settings, "enable_pico_zoom")
    pico_extra_multiplier = obs.obs_data_get_double(settings, "pico_extra_multiplier")
    enable_nano_zoom = obs.obs_data_get_bool(settings, "enable_nano_zoom")
    nano_extra_multiplier = obs.obs_data_get_double(settings, "nano_extra_multiplier")
    enable_pico_zoom = obs.obs_data_get_bool(settings, "enable_pico_zoom")
    pico_extra_multiplier = obs.obs_data_get_double(settings, "pico_extra_multiplier")
    enable_closeup_zoom = obs.obs_data_get_bool(settings, "enable_closeup_zoom")
    closeup_extra_multiplier = obs.obs_data_get_double(settings, "closeup_extra_multiplier")
    enable_macro_zoom = obs.obs_data_get_bool(settings, "enable_macro_zoom")
    macro_extra_multiplier = obs.obs_data_get_double(settings, "macro_extra_multiplier")
    zoom_speed_in = obs.obs_data_get_double(settings, "zoom_speed_in")
    zoom_speed_out = obs.obs_data_get_double(settings, "zoom_speed_out")
    zoom_out_easing = obs.obs_data_get_int(settings, "zoom_out_easing")
    closeup_zoom_speed_in = obs.obs_data_get_double(settings, "closeup_zoom_speed_in")
    closeup_zoom_speed_out = obs.obs_data_get_double(settings, "closeup_zoom_speed_out")
    closeup_zoom_easing_in = obs.obs_data_get_int(settings, "closeup_zoom_easing_in")
    closeup_zoom_easing_out = obs.obs_data_get_int(settings, "closeup_zoom_easing_out")
    macro_zoom_speed_in = obs.obs_data_get_double(settings, "macro_zoom_speed_in")
    macro_zoom_speed_out = obs.obs_data_get_double(settings, "macro_zoom_speed_out")
    macro_zoom_easing_in = obs.obs_data_get_int(settings, "macro_zoom_easing_in")
    macro_zoom_easing_out = obs.obs_data_get_int(settings, "macro_zoom_easing_out")
    nano_zoom_speed_in = obs.obs_data_get_double(settings, "nano_zoom_speed_in")
    nano_zoom_speed_out = obs.obs_data_get_double(settings, "nano_zoom_speed_out")
    nano_zoom_easing_in = obs.obs_data_get_int(settings, "nano_zoom_easing_in")
    nano_zoom_easing_out = obs.obs_data_get_int(settings, "nano_zoom_easing_out")
    pico_zoom_speed_in = obs.obs_data_get_double(settings, "pico_zoom_speed_in")
    pico_zoom_speed_out = obs.obs_data_get_double(settings, "pico_zoom_speed_out")
    pico_zoom_easing_in = obs.obs_data_get_int(settings, "pico_zoom_easing_in")
    pico_zoom_easing_out = obs.obs_data_get_int(settings, "pico_zoom_easing_out")
    zoom_smoothing_in_enabled = obs.obs_data_get_bool(settings, "zoom_smoothing_in_enabled")
    zoom_smoothing_out_enabled = obs.obs_data_get_bool(settings, "zoom_smoothing_out_enabled")
    zoom_smoothing_in = obs.obs_data_get_double(settings, "zoom_smoothing_in")
    zoom_smoothing_out = obs.obs_data_get_double(settings, "zoom_smoothing_out")
    zoom_speed_in = obs.obs_data_get_double(settings, "zoom_speed_in")
    zoom_speed_out = obs.obs_data_get_double(settings, "zoom_speed_out")
    zoom_out_easing = obs.obs_data_get_int(settings, "zoom_out_easing")
    closeup_zoom_speed_in = obs.obs_data_get_double(settings, "closeup_zoom_speed_in")
    closeup_zoom_speed_out = obs.obs_data_get_double(settings, "closeup_zoom_speed_out")
    closeup_zoom_easing_in = obs.obs_data_get_int(settings, "closeup_zoom_easing_in")
    closeup_zoom_easing_out = obs.obs_data_get_int(settings, "closeup_zoom_easing_out")
    macro_zoom_speed_in = obs.obs_data_get_double(settings, "macro_zoom_speed_in")
    macro_zoom_speed_out = obs.obs_data_get_double(settings, "macro_zoom_speed_out")
    macro_zoom_easing_in = obs.obs_data_get_int(settings, "macro_zoom_easing_in")
    macro_zoom_easing_out = obs.obs_data_get_int(settings, "macro_zoom_easing_out")
    nano_zoom_speed_in = obs.obs_data_get_double(settings, "nano_zoom_speed_in")
    nano_zoom_speed_out = obs.obs_data_get_double(settings, "nano_zoom_speed_out")
    nano_zoom_easing_in = obs.obs_data_get_int(settings, "nano_zoom_easing_in")
    nano_zoom_easing_out = obs.obs_data_get_int(settings, "nano_zoom_easing_out")
    pico_zoom_speed_in = obs.obs_data_get_double(settings, "pico_zoom_speed_in")
    pico_zoom_speed_out = obs.obs_data_get_double(settings, "pico_zoom_speed_out")
    pico_zoom_easing_in = obs.obs_data_get_int(settings, "pico_zoom_easing_in")
    pico_zoom_easing_out = obs.obs_data_get_int(settings, "pico_zoom_easing_out")
    zoom_smoothing_in_enabled = obs.obs_data_get_bool(settings, "zoom_smoothing_in_enabled")
    zoom_smoothing_out_enabled = obs.obs_data_get_bool(settings, "zoom_smoothing_out_enabled")
    zoom_smoothing_in = obs.obs_data_get_double(settings, "zoom_smoothing_in")
    zoom_smoothing_out = obs.obs_data_get_double(settings, "zoom_smoothing_out")
    use_auto_follow_mouse = obs.obs_data_get_bool(settings, "follow")
    use_follow_outside_bounds = obs.obs_data_get_bool(settings, "follow_outside_bounds")
    follow_speed = obs.obs_data_get_double(settings, "follow_speed")
    jelly_follow_strength = obs.obs_data_get_double(settings, "jelly_follow_strength")
    jelly_follow_strength = obs.obs_data_get_double(settings, "jelly_follow_strength")
    adaptive_smoothing_enabled = obs.obs_data_get_bool(settings, "adaptive_smoothing_enabled")
    adaptive_smoothing_strength = obs.obs_data_get_double(settings, "adaptive_smoothing_strength")
    adaptive_smoothing_min = obs.obs_data_get_double(settings, "adaptive_smoothing_min")
    adaptive_smoothing_max = obs.obs_data_get_double(settings, "adaptive_smoothing_max")
    smart_prediction_enabled = obs.obs_data_get_bool(settings, "smart_prediction_enabled")
    smart_prediction_strength = obs.obs_data_get_double(settings, "smart_prediction_strength")
    click_sound_enabled = obs.obs_data_get_bool(settings, "click_sound_enabled")
    click_sound_source_name = obs.obs_data_get_string(settings, "click_sound_source_name")
    click_sound_volume = obs.obs_data_get_double(settings, "click_sound_volume")
    follow_border = obs.obs_data_get_int(settings, "follow_border")
    follow_safezone_sensitivity = obs.obs_data_get_int(settings, "follow_safezone_sensitivity")
    use_follow_auto_lock = obs.obs_data_get_bool(settings, "follow_auto_lock")
    allow_all_sources = obs.obs_data_get_bool(settings, "allow_all_sources")
    use_monitor_override = obs.obs_data_get_bool(settings, "use_monitor_override")
    monitor_override_x = obs.obs_data_get_int(settings, "monitor_override_x")
    monitor_override_y = obs.obs_data_get_int(settings, "monitor_override_y")
    monitor_override_w = obs.obs_data_get_int(settings, "monitor_override_w")
    monitor_override_h = obs.obs_data_get_int(settings, "monitor_override_h")
    monitor_override_sx = obs.obs_data_get_double(settings, "monitor_override_sx")
    monitor_override_sy = obs.obs_data_get_double(settings, "monitor_override_sy")
    monitor_override_dw = obs.obs_data_get_int(settings, "monitor_override_dw")
    monitor_override_dh = obs.obs_data_get_int(settings, "monitor_override_dh")
    mouse_smoothing = obs.obs_data_get_double(settings, "mouse_smoothing")
    hold_to_zoom = obs.obs_data_get_bool(settings, "hold_to_zoom")
    hold_to_zoom_closeup = obs.obs_data_get_bool(settings, "hold_to_zoom_closeup")
    hold_to_zoom_macro = obs.obs_data_get_bool(settings, "hold_to_zoom_macro")
    hold_to_zoom_nano = obs.obs_data_get_bool(settings, "hold_to_zoom_nano")
    hold_to_zoom_pico = obs.obs_data_get_bool(settings, "hold_to_zoom_pico")
    debug_logs = obs.obs_data_get_bool(settings, "debug_logs")

spotlight_enabled = obs.obs_data_get_bool(settings, "spotlight_enabled")
spotlight_source_name = obs.obs_data_get_string(settings, "spotlight_source_name")
spotlight_size = obs.obs_data_get_int(settings, "spotlight_size")
spotlight_softness = obs.obs_data_get_double(settings, "spotlight_softness")
spotlight_follow = obs.obs_data_get_bool(settings, "spotlight_follow")
trail_enabled = obs.obs_data_get_bool(settings, "trail_enabled")
trail_count = obs.obs_data_get_int(settings, "trail_count")
trail_spacing = obs.obs_data_get_double(settings, "trail_spacing")
trail_source_prefix = obs.obs_data_get_string(settings, "trail_source_prefix")
easing_preset = obs.obs_data_get_int(settings, "easing_preset")
follow_easing = obs.obs_data_get_int(settings, "follow_easing")
keyframes_text = obs.obs_data_get_string(settings, "keyframes_text")
keyframes = parse_keyframes(keyframes_text)
motion_blur_enabled = obs.obs_data_get_bool(settings, "motion_blur_enabled")
motion_blur_filter_name = obs.obs_data_get_string(settings, "motion_blur_filter_name")
refresh_spotlight(true)
refresh_trail(true)
spotlight_enabled = obs.obs_data_get_bool(settings, "spotlight_enabled")
spotlight_source_name = obs.obs_data_get_string(settings, "spotlight_source_name")
spotlight_size = obs.obs_data_get_int(settings, "spotlight_size")
spotlight_softness = obs.obs_data_get_double(settings, "spotlight_softness")
spotlight_follow = obs.obs_data_get_bool(settings, "spotlight_follow")
trail_enabled = obs.obs_data_get_bool(settings, "trail_enabled")
trail_count = obs.obs_data_get_int(settings, "trail_count")
trail_spacing = obs.obs_data_get_double(settings, "trail_spacing")
trail_source_prefix = obs.obs_data_get_string(settings, "trail_source_prefix")
easing_preset = obs.obs_data_get_int(settings, "easing_preset")
follow_easing = obs.obs_data_get_int(settings, "follow_easing")
keyframes_text = obs.obs_data_get_string(settings, "keyframes_text")
keyframes = parse_keyframes(keyframes_text)
motion_blur_enabled = obs.obs_data_get_bool(settings, "motion_blur_enabled")
motion_blur_filter_name = obs.obs_data_get_string(settings, "motion_blur_filter_name")
refresh_spotlight(true)
refresh_trail(true)
    click_effect_enabled = obs.obs_data_get_bool(settings, "click_effect_enabled")
    click_effect_source_name = obs.obs_data_get_string(settings, "click_effect_source_name")
    click_effect_type = obs.obs_data_get_int(settings, "click_effect_type")
    click_effect_color = obs.obs_data_get_int(settings, "click_effect_color")
    click_effect_duration = obs.obs_data_get_double(settings, "click_effect_duration")
    click_effect_max_scale = obs.obs_data_get_double(settings, "click_effect_max_scale")
    click_effect_spin_degrees = obs.obs_data_get_double(settings, "click_effect_spin_degrees")
    click_effect_pulses = obs.obs_data_get_int(settings, "click_effect_pulses")
    obs.obs_frontend_add_event_callback(on_frontend_event)

    if debug_logs then
        log_current_settings()
    end

    transitions = obs.obs_frontend_get_transitions()
    if transitions ~= nil then
        for _, s in pairs(transitions) do
            name = obs.obs_source_get_name(s)
            log("Adding transition_start listener to " .. name)
            handler = obs.obs_source_get_signal_handler(s)
            obs.signal_handler_connect(handler, "transition_start", on_transition_start)
        end
        obs.source_list_release(transitions)
    end

    if ffi.os == "Linux" and not x11_display then
        log("ERROR: Could not get X11 Display for Linux Mouse position will be incorrect.")
    end
end

function script_unload()
    if major > 29.0 then
        transitions = obs.obs_frontend_get_transitions()
        if transitions ~= nil then
            for _, s in pairs(transitions) do
                handler = obs.obs_source_get_signal_handler(s)
                obs.signal_handler_disconnect(handler, "transition_start", on_transition_start)
            end
            obs.source_list_release(transitions)
        end

        obs.obs_hotkey_unregister(on_toggle_zoom)
        obs.obs_hotkey_unregister(on_toggle_follow)
        obs.obs_hotkey_unregister(on_trigger_click_effect)
        obs.obs_hotkey_unregister(on_hold_zoom)
        obs.obs_hotkey_unregister(on_hold_closeup)
        obs.obs_hotkey_unregister(on_hold_macro)
        obs.obs_hotkey_unregister(on_hold_nano)
        obs.obs_hotkey_unregister(on_hold_pico)
        obs.obs_frontend_remove_event_callback(on_frontend_event)
        release_sceneitem()
    end

    if x11_lib ~= nil and x11_display ~= nil then
        x11_lib.XCloseDisplay(x11_display)
    end
end

function script_defaults(settings)
obs.obs_data_set_default_bool(settings, "click_effect_enabled", false)
obs.obs_data_set_default_string(settings, "click_effect_source_name", "Click Effect")
obs.obs_data_set_default_int(settings, "click_effect_type", 0)
obs.obs_data_set_default_int(settings, "click_effect_color", 0xFFFFFFFF)
obs.obs_data_set_default_double(settings, "click_effect_duration", 0.30)
obs.obs_data_set_default_double(settings, "click_effect_max_scale", 2.2)

        obs.obs_data_set_default_double(settings, "click_effect_spin_degrees", 0)
        obs.obs_data_set_default_int(settings, "click_effect_pulses", 1)
    obs.obs_data_set_default_double(settings, "zoom_value", 1.80)
    obs.obs_data_set_default_bool(settings, "enable_closeup_zoom", true)
    obs.obs_data_set_default_double(settings, "closeup_extra_multiplier", 1.50)
    obs.obs_data_set_default_bool(settings, "enable_macro_zoom", true)
    obs.obs_data_set_default_double(settings, "macro_extra_multiplier", 2.25)
    obs.obs_data_set_default_bool(settings, "enable_nano_zoom", false)
    obs.obs_data_set_default_double(settings, "nano_extra_multiplier", 3.00)
    obs.obs_data_set_default_bool(settings, "enable_pico_zoom", false)
    obs.obs_data_set_default_double(settings, "pico_extra_multiplier", 4.00)
    obs.obs_data_set_default_double(settings, "zoom_speed_in", 0.080)
    obs.obs_data_set_default_double(settings, "zoom_speed_out", 0.080)
    -- Per-level animation defaults (use the same feel as the base zoom by default)
    obs.obs_data_set_default_double(settings, "closeup_zoom_speed_in", 0.080)
    obs.obs_data_set_default_double(settings, "closeup_zoom_speed_out", 0.080)
    obs.obs_data_set_default_int(settings, "closeup_zoom_easing_in", 1)
    obs.obs_data_set_default_int(settings, "closeup_zoom_easing_out", 1)
    obs.obs_data_set_default_double(settings, "macro_zoom_speed_in", 0.080)
    obs.obs_data_set_default_double(settings, "macro_zoom_speed_out", 0.080)
    obs.obs_data_set_default_int(settings, "macro_zoom_easing_in", 1)
    obs.obs_data_set_default_int(settings, "macro_zoom_easing_out", 1)
    obs.obs_data_set_default_double(settings, "nano_zoom_speed_in", 0.080)
    obs.obs_data_set_default_double(settings, "nano_zoom_speed_out", 0.080)
    obs.obs_data_set_default_int(settings, "nano_zoom_easing_in", 1)
    obs.obs_data_set_default_int(settings, "nano_zoom_easing_out", 1)
    obs.obs_data_set_default_double(settings, "pico_zoom_speed_in", 0.080)
    obs.obs_data_set_default_double(settings, "pico_zoom_speed_out", 0.080)
    obs.obs_data_set_default_int(settings, "pico_zoom_easing_in", 1)
    obs.obs_data_set_default_int(settings, "pico_zoom_easing_out", 1)
    obs.obs_data_set_default_int(settings, "zoom_out_easing", 1)
    obs.obs_data_set_default_bool(settings, "zoom_smoothing_in_enabled", true)
    obs.obs_data_set_default_bool(settings, "zoom_smoothing_out_enabled", true)
    obs.obs_data_set_default_double(settings, "zoom_smoothing_in", 0.50)
    obs.obs_data_set_default_double(settings, "zoom_smoothing_out", 0.50)
    obs.obs_data_set_default_bool(settings, "follow", true)
    obs.obs_data_set_default_bool(settings, "follow_outside_bounds", true)
    obs.obs_data_set_default_double(settings, "follow_speed", 0.25)
    obs.obs_data_set_default_double(settings, "jelly_follow_strength", 0.60)
    obs.obs_data_set_default_int(settings, "follow_border", 50)
    obs.obs_data_set_default_int(settings, "follow_safezone_sensitivity", 2)
    obs.obs_data_set_default_bool(settings, "follow_auto_lock", true)
    obs.obs_data_set_default_bool(settings, "allow_all_sources", false)
    obs.obs_data_set_default_bool(settings, "use_monitor_override", false)
    obs.obs_data_set_default_int(settings, "monitor_override_x", 0)
    obs.obs_data_set_default_int(settings, "monitor_override_y", 0)
    obs.obs_data_set_default_int(settings, "monitor_override_w", 1920)
    obs.obs_data_set_default_int(settings, "monitor_override_h", 1080)
    obs.obs_data_set_default_double(settings, "monitor_override_sx", 1)
    obs.obs_data_set_default_double(settings, "monitor_override_sy", 1)
    obs.obs_data_set_default_int(settings, "monitor_override_dw", 1920)
    obs.obs_data_set_default_int(settings, "monitor_override_dh", 1080)
    obs.obs_data_set_default_double(settings, "mouse_smoothing", 0.60)
    obs.obs_data_set_default_bool(settings, "hold_to_zoom", false)
    obs.obs_data_set_default_bool(settings, "hold_to_zoom_closeup", false)
    obs.obs_data_set_default_bool(settings, "hold_to_zoom_macro", false)
    obs.obs_data_set_default_bool(settings, "hold_to_zoom_nano", false)
    obs.obs_data_set_default_bool(settings, "hold_to_zoom_pico", false)
    obs.obs_data_set_default_bool(settings, "debug_logs", false)
    obs.obs_data_set_default_bool(settings, "adaptive_smoothing_enabled", true)
    obs.obs_data_set_default_double(settings, "adaptive_smoothing_strength", 0.50)
    obs.obs_data_set_default_double(settings, "adaptive_smoothing_min", 0.05)
    obs.obs_data_set_default_double(settings, "adaptive_smoothing_max", 0.45)
    obs.obs_data_set_default_bool(settings, "smart_prediction_enabled", true)
    obs.obs_data_set_default_double(settings, "smart_prediction_strength", 0.05)
    obs.obs_data_set_default_bool(settings, "click_sound_enabled", false)
    obs.obs_data_set_default_string(settings, "click_sound_source_name", "Click Sound")
    obs.obs_data_set_default_double(settings, "click_sound_volume", 1.0)
obs.obs_data_set_default_bool(settings, "spotlight_enabled", false)
obs.obs_data_set_default_string(settings, "spotlight_source_name", "Spotlight Overlay")
obs.obs_data_set_default_int(settings, "spotlight_size", 420)
obs.obs_data_set_default_double(settings, "spotlight_softness", 0.35)
obs.obs_data_set_default_bool(settings, "spotlight_follow", false)
obs.obs_data_set_default_bool(settings, "trail_enabled", false)
obs.obs_data_set_default_int(settings, "trail_count", 6)
obs.obs_data_set_default_double(settings, "trail_spacing", 0.04)
obs.obs_data_set_default_string(settings, "trail_source_prefix", "Cursor Trail ")
obs.obs_data_set_default_int(settings, "easing_preset", 1)
obs.obs_data_set_default_int(settings, "follow_easing", 0)
obs.obs_data_set_default_string(settings, "keyframes_text", "")
obs.obs_data_set_default_bool(settings, "motion_blur_enabled", false)
obs.obs_data_set_default_string(settings, "motion_blur_filter_name", "Motion Blur")
end

function script_save(settings)
    if hotkey_zoom_id ~= nil then
        hotkey_save_array = obs.obs_hotkey_save(hotkey_zoom_id)
        obs.obs_data_set_array(settings, "obs_zoom_to_mouse.hotkey.zoom", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end


    if hotkey_hold_zoom_id ~= nil then
        local hotkey_save_array = obs.obs_hotkey_save(hotkey_hold_zoom_id)
        obs.obs_data_set_array(settings, "obs_zoom_to_mouse.hotkey.hold_zoom", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end

    if hotkey_follow_id ~= nil then
        hotkey_save_array = obs.obs_hotkey_save(hotkey_follow_id)
        obs.obs_data_set_array(settings, "obs_zoom_to_mouse.hotkey.follow", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end

    if hotkey_closeup_id ~= nil then
        hotkey_save_array = obs.obs_hotkey_save(hotkey_closeup_id)
        obs.obs_data_set_array(settings, "obs_zoom_to_mouse.hotkey.closeup", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end

    if hotkey_macro_id ~= nil then
        hotkey_save_array = obs.obs_hotkey_save(hotkey_macro_id)
        obs.obs_data_set_array(settings, "obs_zoom_to_mouse.hotkey.macro", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end


    if hotkey_nano_id ~= nil then
        hotkey_save_array = obs.obs_hotkey_save(hotkey_nano_id)
        obs.obs_data_set_array(settings, "obs_zoom_to_mouse.hotkey.nano", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end

    if hotkey_pico_id ~= nil then
        hotkey_save_array = obs.obs_hotkey_save(hotkey_pico_id)
        obs.obs_data_set_array(settings, "obs_zoom_to_mouse.hotkey.pico", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end

    if hotkey_hold_closeup_id ~= nil then
        hotkey_save_array = obs.obs_hotkey_save(hotkey_hold_closeup_id)
        obs.obs_data_set_array(settings, "obs_zoom_to_mouse.hotkey.hold_closeup", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end

    if hotkey_hold_macro_id ~= nil then
        hotkey_save_array = obs.obs_hotkey_save(hotkey_hold_macro_id)
        obs.obs_data_set_array(settings, "obs_zoom_to_mouse.hotkey.hold_macro", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end

    if hotkey_hold_nano_id ~= nil then
        hotkey_save_array = obs.obs_hotkey_save(hotkey_hold_nano_id)
        obs.obs_data_set_array(settings, "obs_zoom_to_mouse.hotkey.hold_nano", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end

    if hotkey_hold_pico_id ~= nil then
        hotkey_save_array = obs.obs_hotkey_save(hotkey_hold_pico_id)
        obs.obs_data_set_array(settings, "obs_zoom_to_mouse.hotkey.hold_pico", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end

end
function script_update(settings)
    
    __current_settings = settings
detect_platform_status()
    old_source_name = source_name
    old_override = use_monitor_override
    old_x = monitor_override_x
    old_y = monitor_override_y
    old_w = monitor_override_w
    old_h = monitor_override_h
    old_sx = monitor_override_sx
    old_sy = monitor_override_sy
    old_dw = monitor_override_dw
    old_dh = monitor_override_dh

    source_name = obs.obs_data_get_string(settings, "source")
    zoom_value = obs.obs_data_get_double(settings, "zoom_value")
    use_auto_follow_mouse = obs.obs_data_get_bool(settings, "follow")
    use_follow_outside_bounds = obs.obs_data_get_bool(settings, "follow_outside_bounds")
    follow_speed = obs.obs_data_get_double(settings, "follow_speed")
    follow_border = obs.obs_data_get_int(settings, "follow_border")
    follow_safezone_sensitivity = obs.obs_data_get_int(settings, "follow_safezone_sensitivity")
    use_follow_auto_lock = obs.obs_data_get_bool(settings, "follow_auto_lock")
    allow_all_sources = obs.obs_data_get_bool(settings, "allow_all_sources")
    use_monitor_override = obs.obs_data_get_bool(settings, "use_monitor_override")
    monitor_override_x = obs.obs_data_get_int(settings, "monitor_override_x")
    monitor_override_y = obs.obs_data_get_int(settings, "monitor_override_y")
    monitor_override_w = obs.obs_data_get_int(settings, "monitor_override_w")
    monitor_override_h = obs.obs_data_get_int(settings, "monitor_override_h")
    monitor_override_sx = obs.obs_data_get_double(settings, "monitor_override_sx")
    monitor_override_sy = obs.obs_data_get_double(settings, "monitor_override_sy")
    monitor_override_dw = obs.obs_data_get_int(settings, "monitor_override_dw")
    monitor_override_dh = obs.obs_data_get_int(settings, "monitor_override_dh")
    mouse_smoothing = obs.obs_data_get_double(settings, "mouse_smoothing")
    hold_to_zoom = obs.obs_data_get_bool(settings, "hold_to_zoom")
    hold_to_zoom_closeup = obs.obs_data_get_bool(settings, "hold_to_zoom_closeup")
    hold_to_zoom_macro = obs.obs_data_get_bool(settings, "hold_to_zoom_macro")
    hold_to_zoom_nano = obs.obs_data_get_bool(settings, "hold_to_zoom_nano")
    hold_to_zoom_pico = obs.obs_data_get_bool(settings, "hold_to_zoom_pico")
    debug_logs = obs.obs_data_get_bool(settings, "debug_logs")

    if source_name ~= old_source_name then
        refresh_sceneitem(true)
        refresh_click_effect(true)
        refresh_spotlight(true)
        refresh_trail(true)
    end

    if source_name ~= old_source_name or
        use_monitor_override ~= old_override or
        monitor_override_x ~= old_x or
        monitor_override_y ~= old_y or
        monitor_override_w ~= old_w or
        monitor_override_h ~= old_h or
        monitor_override_sx ~= old_sx or
        monitor_override_sy ~= old_sy or
        monitor_override_w ~= old_dw or
        monitor_override_h ~= old_dh then
        monitor_info = get_monitor_info(source)
    end
end

function populate_zoom_sources(list)
    obs.obs_property_list_clear(list)

    sources = obs.obs_enum_sources()
    if sources ~= nil then
        dc_info = get_dc_info()
        obs.obs_property_list_add_string(list, "<None>", "obs-zoom-to-mouse-none")
        for _, src in ipairs(sources) do
            source_type = obs.obs_source_get_id(src)
            if (dc_info and source_type == dc_info.source_id) or allow_all_sources then
                name = obs.obs_source_get_name(src)
                obs.obs_property_list_add_string(list, name, name)
            end
        end

        obs.source_list_release(sources)
    end
end
-- Reset-to-defaults helpers
local __current_settings = nil

local function apply_default_values_to_settings(s)
    if s == nil then return end

    -- Zoom levels
    obs.obs_data_set_double(s, "zoom_value", 1.80)
    obs.obs_data_set_bool(s, "hold_to_zoom", false)
    obs.obs_data_set_bool(s, "enable_closeup_zoom", true)
    obs.obs_data_set_double(s, "closeup_extra_multiplier", 1.50)
    obs.obs_data_set_bool(s, "enable_macro_zoom", true)
    obs.obs_data_set_double(s, "macro_extra_multiplier", 2.25)

    -- Zoom animation
    obs.obs_data_set_double(s, "zoom_speed_in", 0.080)
    obs.obs_data_set_double(s, "zoom_speed_out", 0.080)
    obs.obs_data_set_int(s, "easing_preset", 1)       -- Cinematic
    obs.obs_data_set_int(s, "zoom_out_easing", 1)     -- Cinematic
    obs.obs_data_set_bool(s, "zoom_smoothing_in_enabled", true)
    obs.obs_data_set_double(s, "zoom_smoothing_in", 0.50)
    obs.obs_data_set_bool(s, "zoom_smoothing_out_enabled", true)
    obs.obs_data_set_double(s, "zoom_smoothing_out", 0.50)

    -- Follow behaviour / safety
    obs.obs_data_set_bool(s, "follow", true)
    obs.obs_data_set_bool(s, "follow_outside_bounds", true)
    obs.obs_data_set_double(s, "follow_speed", 0.25)
    obs.obs_data_set_double(s, "jelly_follow_strength", 0.60)
    obs.obs_data_set_int(s, "follow_border", 50)
    obs.obs_data_set_int(s, "follow_safezone_sensitivity", 2)
    obs.obs_data_set_bool(s, "follow_auto_lock", true)

    -- Smart prediction + adaptive smoothing
    obs.obs_data_set_bool(s, "smart_prediction_enabled", true)
    obs.obs_data_set_double(s, "smart_prediction_strength", 0.05)
    obs.obs_data_set_bool(s, "adaptive_smoothing_enabled", true)
    obs.obs_data_set_double(s, "adaptive_smoothing_strength", 0.50)
    obs.obs_data_set_double(s, "adaptive_smoothing_min", 0.05)
    obs.obs_data_set_double(s, "adaptive_smoothing_max", 0.45)

    -- General smoothing
    obs.obs_data_set_double(s, "mouse_smoothing", 0.60)

    -- Visual FX defaults
    obs.obs_data_set_bool(s, "click_effect_enabled", false)
    obs.obs_data_set_bool(s, "spotlight_enabled", false)
    obs.obs_data_set_bool(s, "spotlight_follow", false)
    obs.obs_data_set_bool(s, "trail_enabled", false)
    obs.obs_data_set_bool(s, "motion_blur_enabled", false)

    -- Source selection defaults
    obs.obs_data_set_bool(s, "allow_all_sources", false)
    obs.obs_data_set_bool(s, "use_monitor_override", false)
end
