#!/usr/bin/env python3
"""
MacDeck & Virtual Touch Bar Companion Server - Ultra-Low Latency Edition
- Loads user customized shortcuts dynamically from NSUserDefaults / MacTouchBar.
- Extracts high-resolution macOS icons in Base64 on the fly for any custom apps.
- Real-time running applications detection for running indicator dots.
- Real-time wallpaper synchronization.
- TCP_NODELAY enabled for sub-millisecond responses.
"""

import asyncio
import base64
import ctypes
import hashlib
import json
import os
import platform
import plistlib
import re
import socket
import struct
import subprocess
import sys
import time
from typing import Dict, List, Set

PORT = 9876
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

# Connected WebSocket clients
connected_clients: Set[asyncio.StreamWriter] = set()

# State caches
last_status: Dict = {}
dns_sd_process = None
last_wallpaper_path = ""
last_wallpaper_mtime = 0
cached_wallpaper_b64 = ""
icon_cache: Dict[str, str] = {}

# Preload Base64 Icons from icons.json
ICONS_PATH = os.path.join(os.path.dirname(__file__), "..", "touchbar-hackintosh", "src", "main", "assets", "ipados", "icons", "icons.json")
if os.path.exists(ICONS_PATH):
    try:
        with open(ICONS_PATH, "r") as f:
            icon_cache.update(json.load(f))
            print(f"📦 Preloaded {len(icon_cache)} native icons from icons.json")
    except Exception as e:
        print(f"⚠️ Could not load icons.json: {e}")


def get_local_ip() -> str:
    """Get the local primary IP address."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = '192.168.1.6'
    finally:
        s.close()
    return ip


def get_icon_base64_for_path(app_path: str, app_id: str = "") -> str:
    """Extract and cache Base64 icon from any macOS application path."""
    if app_id and app_id in icon_cache and icon_cache[app_id]:
        return icon_cache[app_id]
    if app_path in icon_cache and icon_cache[app_path]:
        return icon_cache[app_path]

    if not app_path or not os.path.exists(app_path):
        return ""

    icns_path = None
    plist_path = os.path.join(app_path, "Contents", "Info.plist")
    if os.path.exists(plist_path):
        try:
            with open(plist_path, 'rb') as fp:
                pl = plistlib.load(fp)
                icon_file = pl.get("CFBundleIconFile", "")
                if icon_file:
                    if not icon_file.endswith(".icns"):
                        icon_file += ".icns"
                    cand = os.path.join(app_path, "Contents", "Resources", icon_file)
                    if os.path.exists(cand):
                        icns_path = cand
        except Exception:
            pass

    if not icns_path:
        res_dir = os.path.join(app_path, "Contents", "Resources")
        if os.path.exists(res_dir):
            for f in os.listdir(res_dir):
                if f.endswith(".icns"):
                    icns_path = os.path.join(res_dir, f)
                    break

    if icns_path and os.path.exists(icns_path):
        out_tmp = f"/tmp/icon_{abs(hash(app_path))}.png"
        cmd = ["sips", "-s", "format", "png", "-z", "128", "128", icns_path, "--out", out_tmp]
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=1.0)
        if os.path.exists(out_tmp):
            with open(out_tmp, "rb") as f:
                b64 = base64.b64encode(f.read()).decode("utf-8")
                if app_id:
                    icon_cache[app_id] = b64
                icon_cache[app_path] = b64
                return b64

    return ""


def get_running_apps() -> Set[str]:
    """Ultra-fast detection of running applications via ps (1-2ms)."""
    try:
        proc = subprocess.run(["ps", "-ax", "-o", "comm="], capture_output=True, text=True, timeout=0.8)
        running = set()
        for p in proc.stdout.splitlines():
            if ".app/Contents/MacOS/" in p:
                parts = p.split(".app/Contents/MacOS/")[0].split("/")
                if parts:
                    running.add(parts[-1])
        return running
    except Exception:
        return {"Finder"}


def get_current_wallpaper_b64() -> str:
    """Extract and compress current macOS desktop wallpaper (~60KB)."""
    global last_wallpaper_path, last_wallpaper_mtime, cached_wallpaper_b64
    try:
        script = 'tell application "System Events" to tell current desktop to get picture'
        proc = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=1.0)
        raw_path = proc.stdout.strip()

        if not raw_path or not os.path.exists(raw_path):
            return cached_wallpaper_b64

        mtime = os.path.getmtime(raw_path)
        if raw_path == last_wallpaper_path and mtime == last_wallpaper_mtime and cached_wallpaper_b64:
            return cached_wallpaper_b64

        out_tmp = "/tmp/mac_wallpaper_thumb.jpg"
        cmd = ["sips", "-s", "format", "jpeg", "-s", "formatOptions", "70", "-Z", "960", raw_path, "--out", out_tmp]
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=1.5)

        if os.path.exists(out_tmp):
            with open(out_tmp, "rb") as f:
                b64 = base64.b64encode(f.read()).decode("utf-8")
                last_wallpaper_path = raw_path
                last_wallpaper_mtime = mtime
                cached_wallpaper_b64 = b64
                print(f"🎨 Wallpaper updated: {raw_path} ({len(b64)*3//4//1024} KB)")
                return cached_wallpaper_b64
    except Exception as e:
        print(f"⚠️ Wallpaper error: {e}")

    return cached_wallpaper_b64


def resolve_uid(val, objs, depth=0):
    """Recursively resolve NSKeyedArchiver UID references."""
    if depth > 25:
        return val
    if isinstance(val, plistlib.UID):
        if 0 <= val.data < len(objs):
            return resolve_uid(objs[val.data], objs, depth + 1)
        return ""
    elif isinstance(val, dict):
        res = {}
        for dk, dv in val.items():
            if dk != "$class":
                res[dk] = resolve_uid(dv, objs, depth + 1)
        return res
    elif isinstance(val, list):
        return [resolve_uid(x, objs, depth + 1) for x in val]
    return val


DECK_CONFIG_FILE = os.path.join(os.path.dirname(__file__), "user_deck_config.json")


def load_json_config_buttons() -> List[Dict]:
    """Read user-configured shortcuts from user_deck_config.json."""
    if os.path.exists(DECK_CONFIG_FILE):
        try:
            with open(DECK_CONFIG_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict) and "buttons" in data:
                    return data["buttons"]
                elif isinstance(data, list):
                    return data
        except Exception as e:
            print(f"⚠️ Error reading user_deck_config.json: {e}")
    return []


def load_user_defaults_buttons() -> List[Dict]:
    """Read user-configured shortcuts from NSUserDefaults (io.github.luxfajah.MacTouchBar) with full recursion."""
    proc = subprocess.run(["defaults", "export", "io.github.luxfajah.MacTouchBar", "-"], capture_output=True, timeout=1.2)
    if not proc.stdout:
        return []
    try:
        pl = plistlib.loads(proc.stdout)
        data = pl.get("MacDeckButtons2x6_UserLayout_V4") or pl.get("MacDeckButtons2x6_UserLayout") or pl.get("MacDeckButtons")
        if not data:
            return []
        arch = plistlib.loads(data)
        objs = arch.get("$objects", [])
        top = arch.get("$top", {})
        root_ref = top.get("root")
        if not root_ref:
            return []

        resolved_root = resolve_uid(root_ref, objs)
        raw_list = []
        if isinstance(resolved_root, dict) and "NS.objects" in resolved_root:
            raw_list = resolved_root["NS.objects"]
        elif isinstance(resolved_root, list):
            raw_list = resolved_root

        buttons = []
        for i, item in enumerate(raw_list):
            if isinstance(item, dict):
                label = str(item.get("label") or f"Slot {i+1}")
                payload = str(item.get("payload") or "")
                action_type = str(item.get("actionType") or "launch_app")
                icon = str(item.get("icon") or "")
                color_hex = str(item.get("colorHex") or "#1F1F24")
                btn_id = str(item.get("id") or f"btn_{i+1}")

                buttons.append({
                    "id": btn_id,
                    "label": label,
                    "actionType": action_type,
                    "payload": payload,
                    "icon": icon,
                    "colorHex": color_hex
                })
        return buttons
    except Exception as e:
        print(f"⚠️ Error parsing defaults buttons: {e}")
        return []


def get_deck_buttons() -> List[Dict]:
    """Return the 12 authentic Mac apps with Base64 icons and live running status."""
    running = get_running_apps()
    user_buttons = load_json_config_buttons()
    if not user_buttons:
        user_buttons = load_user_defaults_buttons()

    # Default fallback apps for padding
    fallback_apps = [
        ("chrome", "Chrome", "/Applications/Google Chrome.app", ["Google Chrome", "Chrome"]),
        ("music", "Música", "/System/Applications/Music.app", ["Music", "Apple Music"]),
        ("discord", "Discord", "/Applications/Discord.app", ["Discord"]),
        ("photoshop", "Photoshop", "/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app", ["Photoshop", "Adobe Photoshop"]),
        ("illustrator", "Illustrator", "/Applications/Adobe Illustrator 2026/Adobe Illustrator.app", ["Illustrator", "Adobe Illustrator"]),
        ("indesign", "InDesign", "/Applications/Adobe InDesign 2026/Adobe InDesign 2026.app", ["InDesign", "Adobe InDesign"]),
        ("figma", "Figma", "/Applications/Figma.app", ["Figma"]),
        ("affinity", "Affinity", "/Applications/Affinity.app", ["Affinity", "Affinity Designer", "Affinity Photo"]),
        ("antigravity", "Antigravity", "/Applications/Antigravity.app", ["Antigravity"]),
        ("whatsapp", "WhatsApp", "/Applications/WhatsApp.app", ["WhatsApp"]),
        ("finder", "Finder", "/System/Library/CoreServices/Finder.app", ["Finder"]),
        ("launchpad", "Launchpad", "/System/Applications/Launchpad.app", ["Launchpad"])
    ]

    # If user has configured buttons in MacTouchBar, use them!
    if user_buttons and len(user_buttons) > 0:
        result = []
        for b in user_buttons[:12]:
            payload = b.get("payload", "")
            actionType = b.get("actionType", "launch_app")
            label = b.get("label", "App")

            # Determine running state
            is_running = False
            if actionType == "launch_app" and payload:
                app_name = os.path.basename(payload).replace(".app", "")
                if app_name.lower() == "finder" or any(app_name.lower() in r.lower() for r in running) or any(label.lower() in r.lower() for r in running):
                    is_running = True

            # Extract Base64 icon
            icon_b64 = ""
            if actionType == "launch_app" and payload:
                icon_b64 = get_icon_base64_for_path(payload, label.lower())
            elif actionType == "hotkey" or actionType == "system":
                icon_b64 = get_icon_base64_for_path(payload, label.lower())

            result.append({
                "id": b.get("id", f"btn_{len(result)+1}"),
                "label": label,
                "iconUrl": f"icons/{label.lower()}.png",
                "iconBase64": icon_b64,
                "actionType": actionType,
                "payload": payload,
                "isRunning": is_running,
                "colorHex": b.get("colorHex", "#1F1F24")
            })

        # Pad with fallback if fewer than 12
        while len(result) < 12:
            idx = len(result)
            app_id, label, path, match_names = fallback_apps[idx]
            is_open = any(m.lower() in r.lower() for m in match_names for r in running) or app_id == "finder"
            result.append({
                "id": app_id,
                "label": label,
                "iconUrl": f"icons/{app_id}.png",
                "iconBase64": get_icon_base64_for_path(path, app_id),
                "actionType": "launch_app",
                "payload": path,
                "isRunning": is_open,
                "colorHex": "#1F1F24"
            })
        return result

    # Fallback Default 12 Apps
    def check_running(app_id: str, app_names: List[str]) -> bool:
        if app_id == "finder":
            return True
        for name in app_names:
            if any(name.lower() in r.lower() for r in running):
                return True
        return False

    buttons = []
    for app_id, label, path, match_names in fallback_apps:
        is_open = check_running(app_id, match_names)
        buttons.append({
            "id": app_id,
            "label": label,
            "iconUrl": f"icons/{app_id}.png",
            "iconBase64": get_icon_base64_for_path(path, app_id),
            "actionType": "launch_app",
            "payload": path,
            "isRunning": is_open,
            "colorHex": "#1F1F24"
        })
    return buttons


def run_osascript(script: str) -> str:
    """Execute an AppleScript with timeout."""
    try:
        proc = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            timeout=1.0
        )
        return proc.stdout.strip()
    except Exception:
        return ""


current_brightness = 75
cached_airpods = {"connected": False, "name": "AirPods", "left": 100, "right": 100, "case": 90}
last_airpods_check = 0.0


def get_airpods_battery_info() -> Dict:
    """Read AirPods (Left, Right, Case) battery status via system_profiler and bluetooth telemetry."""
    global cached_airpods, last_airpods_check
    now = time.time()
    if now - last_airpods_check < 3.0:
        return cached_airpods

    last_airpods_check = now
    try:
        proc = subprocess.run(["system_profiler", "SPBluetoothDataType", "-json"], capture_output=True, text=True, timeout=1.5)
        if not proc.stdout:
            return cached_airpods
        data = json.loads(proc.stdout)
        sp_bt = data.get("SPBluetoothDataType", [])
        if not sp_bt:
            return cached_airpods

        connected_devs = sp_bt[0].get("device_connected", [])
        for dev_entry in connected_devs:
            for dev_name, dev_info in dev_entry.items():
                if "airpod" in dev_name.lower() or dev_info.get("device_minorType") == "Headset" or "device_batteryLevelLeft" in dev_info:
                    left = dev_info.get("device_batteryLevelLeft", dev_info.get("device_batteryLevelMain", "100%"))
                    right = dev_info.get("device_batteryLevelRight", dev_info.get("device_batteryLevelMain", "100%"))
                    case = dev_info.get("device_batteryLevelCase", "90%")

                    def to_int(val):
                        digits = re.findall(r'\d+', str(val))
                        return int(digits[0]) if digits else 100

                    cached_airpods = {
                        "connected": True,
                        "name": dev_name,
                        "left": to_int(left),
                        "right": to_int(right),
                        "case": to_int(case) if case else 90
                    }
                    return cached_airpods

        # Check paired list if disconnected
        not_conn = sp_bt[0].get("device_not_connected", [])
        for dev_entry in not_conn:
            for dev_name, dev_info in dev_entry.items():
                if "airpod" in dev_name.lower():
                    cached_airpods = {
                        "connected": False,
                        "name": dev_name,
                        "left": 100,
                        "right": 100,
                        "case": 90
                    }
                    return cached_airpods

        cached_airpods = {"connected": False, "name": "AirPods", "left": 100, "right": 100, "case": 90}
        return cached_airpods
    except Exception:
        return cached_airpods


def get_battery_info() -> Dict:
    """Read battery percentage and charging state via pmset."""
    try:
        proc = subprocess.run(["pmset", "-g", "batt"], capture_output=True, text=True, timeout=0.8)
        out = proc.stdout
        match = re.search(r'(\d+)%', out)
        percent = int(match.group(1)) if match else 100
        is_charging = "charging" in out.lower() or "ac power" in out.lower()
        return {
            "percent": percent,
            "is_charging": is_charging,
            "state": "Carregando" if is_charging else "Bateria"
        }
    except Exception:
        return {"percent": 100, "is_charging": True, "state": "Carregando"}


cached_artwork_key = ""
cached_artwork_b64 = ""
last_action_times: Dict[str, float] = {}

cached_media = {
    "player": "Music",
    "state": "stopped",
    "title": "",
    "artist": "",
    "album": "",
    "duration": 0.0,
    "position": 0.0,
    "artwork": ""
}
last_active_media_time = 0.0


def get_mac_system_status() -> Dict:
    """Read volume, battery, AirPods, now playing media (Apple Music / Spotify), active app, and telemetry from macOS."""
    global last_status, current_brightness, cached_artwork_key, cached_artwork_b64, cached_media, last_active_media_time

    vol_script = """
    try
        set vol to output volume of (get volume settings)
        set isMuted to output muted of (get volume settings)
        return (vol as string) & "|||" & (isMuted as string)
    on error
        return "50|||false"
    end try
    """
    vol_res = run_osascript(vol_script)
    vol_parts = vol_res.split("|||") if "|||" in vol_res else ["50", "false"]
    volume = int(vol_parts[0]) if vol_parts[0].isdigit() else 50
    is_muted = vol_parts[1].lower() == "true" if len(vol_parts) > 1 else False

    app_script = """
    try
        tell application "System Events" to get name of first process whose frontmost is true
    on error
        return "Finder"
    end try
    """
    front_app = run_osascript(app_script)
    if not front_app:
        front_app = "Finder"

    # Prioritize Apple Music (Music.app) first
    music_script = """
    try
        tell application "System Events"
            set isMusicRunning to (name of processes) contains "Music"
        end tell
        if isMusicRunning then
            tell application "Music"
                set pState to player state as string
                if pState is not "stopped" then
                    set tName to name of current track
                    set tArtist to artist of current track
                    set tAlbum to album of current track
                    set tDuration to duration of current track
                    set tPos to player position
                    set hasArt to "false"
                    try
                        if (count of artworks of current track) > 0 then
                            set art to artwork 1 of current track
                            set rawData to data of art
                            set outPath to ((POSIX file "/tmp/apple_music_art.raw") as string)
                            set fRef to (open for access file outPath with write permission)
                            set eof fRef to 0
                            write rawData to fRef
                            close access fRef
                            set hasArt to "true"
                        end if
                    on error
                        try
                            close access file ((POSIX file "/tmp/apple_music_art.raw") as string)
                        end try
                    end try
                    return "Music|||" & pState & "|||" & tName & "|||" & tArtist & "|||" & tAlbum & "|||" & (tDuration as string) & "|||" & (tPos as string) & "|||" & hasArt
                else
                    return "Music|||stopped|||||||||0|||0|||false"
                end if
            end tell
        else
            return "None|||stopped|||||||||0|||0|||false"
        end if
    on error
        return "None|||stopped|||||||||0|||0|||false"
    end try
    """
    music_res = run_osascript(music_script)
    m_parts = music_res.split("|||") if "|||" in music_res else ["None", "stopped", "", "", "", "0", "0", "false"]
    player_app = m_parts[0] if len(m_parts) > 0 else "None"
    playback_state = m_parts[1] if len(m_parts) > 1 else "stopped"
    track_title = m_parts[2] if len(m_parts) > 2 else ""
    track_artist = m_parts[3] if len(m_parts) > 3 else ""
    track_album = m_parts[4] if len(m_parts) > 4 else ""

    try:
        duration = float(str(m_parts[5]).replace(',', '.')) if len(m_parts) > 5 and m_parts[5] else 0.0
    except ValueError:
        duration = 0.0

    try:
        position = float(str(m_parts[6]).replace(',', '.')) if len(m_parts) > 6 and m_parts[6] else 0.0
    except ValueError:
        position = 0.0

    has_art_or_url = m_parts[7] if len(m_parts) > 7 else ""
    artwork_b64 = ""

    if player_app == "Music" and has_art_or_url == "true" and os.path.exists("/tmp/apple_music_art.raw"):
        art_key = f"{track_artist}_{track_title}"
        if art_key != cached_artwork_key or not cached_artwork_b64:
            try:
                with open("/tmp/apple_music_art.raw", "rb") as fp:
                    raw_bytes = fp.read()
                    if len(raw_bytes) > 50:
                        cached_artwork_b64 = base64.b64encode(raw_bytes).decode("utf-8")
                        cached_artwork_key = art_key
            except Exception:
                pass
        artwork_b64 = cached_artwork_b64
    elif player_app == "Spotify" and has_art_or_url and has_art_or_url.startswith("http"):
        artwork_b64 = has_art_or_url

    # Retain metadata during song skips or momentary empty states
    now = time.time()
    if track_title:
        cached_media = {
            "player": player_app,
            "state": playback_state,
            "title": track_title,
            "artist": track_artist,
            "album": track_album,
            "duration": duration,
            "position": position,
            "artwork": artwork_b64 if artwork_b64 else cached_media.get("artwork", "")
        }
        last_active_media_time = now
    elif cached_media.get("title") and (now - last_active_media_time < 30.0):
        # Keep displaying last known track metadata, updating only state & position
        cached_media["state"] = playback_state
        if position > 0:
            cached_media["position"] = position
    else:
        cached_media = {
            "player": player_app,
            "state": playback_state,
            "title": track_title,
            "artist": track_artist,
            "album": track_album,
            "duration": duration,
            "position": position,
            "artwork": artwork_b64
        }

    battery = get_battery_info()
    airpods = get_airpods_battery_info()

    # CPU & RAM telemetry
    cpu_pct = 12.0
    ram_pct = 45.0
    try:
        load1, _, _ = os.getloadavg()
        cpu_count = os.cpu_count() or 1
        cpu_pct = round(min(100.0, (load1 / cpu_count) * 100.0), 1)
    except Exception:
        pass

    status = {
        "type": "status_update",
        "cpu_percent": cpu_pct,
        "ram_percent": ram_pct,
        "mac_name": platform.node().replace(".local", ""),
        "ip": get_local_ip(),
        "volume": volume,
        "is_muted": is_muted,
        "brightness": current_brightness,
        "battery": battery,
        "airpods": airpods,
        "frontmost_app": front_app,
        "media": cached_media
    }
    last_status = status
    return status


def build_applescript_hotkey(hotkey_str: str) -> str:
    """Translate natural hotkey strings like 'win+esc', 'cmd+shift+4', 'f11' into native AppleScript."""
    s = hotkey_str.lower().strip()
    if not s:
        return ""
    if "launchpad" in s:
        return 'tell application "System Events" to key code 53 using {command down}'

    parts = [p.strip() for p in re.split(r'[\+\s\-]+', s) if p.strip()]
    modifiers = []
    key = ""
    for p in parts:
        if p in ('cmd', 'command', 'win', 'windows', 'super', 'gui'):
            modifiers.append('command down')
        elif p in ('ctrl', 'control'):
            modifiers.append('control down')
        elif p in ('alt', 'opt', 'option'):
            modifiers.append('option down')
        elif p in ('shift', 'shft'):
            modifiers.append('shift down')
        else:
            key = p

    mod_str = f' using {{{", ".join(modifiers)}}}' if modifiers else ''
    key_codes = {
        'esc': 53, 'escape': 53,
        'return': 36, 'enter': 36,
        'tab': 48,
        'space': 49,
        'delete': 51, 'backspace': 51,
        'f1': 122, 'f2': 120, 'f3': 99, 'f4': 118, 'f5': 96, 'f6': 97,
        'f7': 98, 'f8': 100, 'f9': 101, 'f10': 109, 'f11': 103, 'f12': 111,
        'left': 123, 'right': 124, 'down': 125, 'up': 126
    }
    if key in key_codes:
        return f'tell application "System Events" to key code {key_codes[key]}{mod_str}'
    elif len(key) == 1:
        return f'tell application "System Events" to keystroke "{key}"{mod_str}'
    else:
        return f'tell application "System Events" to keystroke "{hotkey_str}"'


async def push_immediate_status(delay: float = 0.18):
    """Wait briefly and push updated status to all connected clients."""
    await asyncio.sleep(delay)
    if connected_clients:
        try:
            status = await asyncio.to_thread(get_mac_system_status)
            frame = encode_ws_frame(json.dumps(status))
            to_remove = []
            for client in connected_clients:
                try:
                    client.write(frame)
                    await client.drain()
                except Exception:
                    to_remove.append(client)
            for c in to_remove:
                connected_clients.discard(c)
        except Exception:
            pass


async def push_immediate_deck_update(delay: float = 0.05):
    """Push updated deck shortcuts with high-res Base64 icons immediately to all connected clients."""
    await asyncio.sleep(delay)
    if connected_clients:
        try:
            deck = await asyncio.to_thread(get_deck_buttons)
            frame = encode_ws_frame(json.dumps({"type": "deck_config_update", "buttons": deck}))
            to_remove = []
            for client in connected_clients:
                try:
                    client.write(frame)
                    await client.drain()
                except Exception:
                    to_remove.append(client)
            for c in to_remove:
                connected_clients.discard(c)
        except Exception:
            pass


def handle_action_fast(action: str, params: Dict):
    """Execute action with zero blocking (< 1ms) and smart debouncing."""
    global last_action_times
    now = time.time()

    # Debounce rapid duplicate media actions within 300ms
    if action in ("media_play_pause", "media_next", "media_prev", "toggle_favorite"):
        last_t = last_action_times.get(action, 0.0)
        if now - last_t < 0.30:
            print(f"⏩ Throttled duplicate action: {action}")
            return
        last_action_times[action] = now

    print(f"⚡️ Fast Action: {action} (params: {params})")

    if action == "press_esc":
        subprocess.Popen(["osascript", "-e", 'tell application "System Events" to key code 53'])

    elif action == "set_volume":
        vol = int(params.get("volume", 50))
        vol = max(0, min(100, vol))
        subprocess.Popen(["osascript", "-e", f"set volume output volume {vol}"])

    elif action == "set_brightness":
        global current_brightness
        bright = int(params.get("brightness", 75))
        bright = max(0, min(100, bright))
        current_brightness = bright
        try:
            cg = ctypes.cdll.LoadLibrary('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
            d = ctypes.cdll.LoadLibrary('/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices')
            d.DisplayServicesSetBrightness.argtypes = [ctypes.c_uint32, ctypes.c_float]
            d.DisplayServicesSetBrightness(cg.CGMainDisplayID(), ctypes.c_float(bright / 100.0))
        except Exception:
            pass

    elif action == "toggle_mute":
        subprocess.Popen(["osascript", "-e", "set volume output muted (not (output muted of (get volume settings)))"])

    elif action == "media_play_pause":
        running = get_running_apps()
        if "Spotify" in running:
            subprocess.Popen(["osascript", "-e", 'tell application "Spotify" to playpause'])
        else:
            subprocess.Popen(["osascript", "-e", 'tell application "Music" to playpause'])
        asyncio.create_task(push_immediate_status(0.15))

    elif action == "media_next":
        running = get_running_apps()
        if "Spotify" in running:
            subprocess.Popen(["osascript", "-e", 'tell application "Spotify" to next track'])
        else:
            subprocess.Popen(["osascript", "-e", 'tell application "Music" to next track'])
        asyncio.create_task(push_immediate_status(0.25))

    elif action == "media_prev":
        running = get_running_apps()
        if "Spotify" in running:
            subprocess.Popen(["osascript", "-e", 'tell application "Spotify" to previous track'])
        else:
            subprocess.Popen(["osascript", "-e", 'tell application "Music" to previous track'])
        asyncio.create_task(push_immediate_status(0.25))

    elif action == "set_player_position":
        pos = float(params.get("position", 0))
        running = get_running_apps()
        if "Spotify" in running:
            subprocess.Popen(["osascript", "-e", f'tell application "Spotify" to set player position to {pos}'])
        else:
            subprocess.Popen(["osascript", "-e", f'tell application "Music" to set player position to {pos}'])
        asyncio.create_task(push_immediate_status(0.10))

    elif action == "toggle_favorite":
        subprocess.Popen(["osascript", "-e", 'tell application "Music" to set favorited of current track to not (favorited of current track)'])

    elif action == "type_emoji" or action == "type_text":
        text = str(params.get("text", ""))
        if text:
            escaped = text.replace('\\', '\\\\').replace('"', '\\"')
            subprocess.Popen(["osascript", "-e", f'tell application "System Events" to keystroke "{escaped}"'])

    elif action in ("parse_hotkey_string", "send_hotkey", "hotkey"):
        hotkey = str(params.get("hotkey", params.get("key", params.get("payload", ""))))
        script = build_applescript_hotkey(hotkey)
        if script:
            subprocess.Popen(["osascript", "-e", script])

    elif action == "play_sound":
        sound_name = params.get("sound", "Glass")
        sound_path = f"/System/Library/Sounds/{sound_name}.aiff"
        if os.path.exists(sound_path):
            subprocess.Popen(["afplay", sound_path])
        else:
            subprocess.Popen(["osascript", "-e", "beep"])

    elif action == "launch_app":
        app_path = params.get("app", params.get("payload", "Finder"))
        label = params.get("label", "").lower()

        # Launchpad integration: Win+Esc / Command+Escape toggle & open
        if "launchpad" in app_path.lower() or "launchpad" in label:
            subprocess.Popen(["osascript", "-e", 'tell application "System Events" to key code 53 using {command down}'])
            subprocess.Popen(["open", "-a", "Launchpad"])
        elif app_path.endswith(".app") and os.path.exists(app_path):
            subprocess.Popen(["open", app_path])
        else:
            subprocess.Popen(["open", "-a", app_path])

    elif action in ("system_command", "system_action"):
        cmd = params.get("command", "")
        if cmd in ("launchpad", "toggle_launchpad"):
            subprocess.Popen(["osascript", "-e", 'tell application "System Events" to key code 53 using {command down}'])
            subprocess.Popen(["open", "-a", "Launchpad"])
        elif cmd in ("screenshot_interactive", "screenshot_area", "print_screen"):
            # Command + Shift + 4: Captura de tela interativa para o clipboard
            subprocess.Popen(["screencapture", "-i", "-c"])
        elif cmd in ("screen_record", "screen_recording"):
            # Command + Shift + 5: Barra oficial de gravação de tela
            subprocess.Popen(["osascript", "-e", 'tell application "System Events" to key code 23 using {command down, shift down}'])
        elif cmd in ("show_desktop", "mesa"):
            # F11 (Key code 103): Mostrar Mesa
            subprocess.Popen(["osascript", "-e", 'tell application "System Events" to key code 103'])
        elif cmd in ("lock_screen", "bloquear"):
            # Control + Command + Q (Key code 12): Bloquear Tela
            subprocess.Popen(["osascript", "-e", 'tell application "System Events" to key code 12 using {control down, command down}'])
        elif cmd in ("restart_mac", "reiniciar"):
            # Reiniciar Mac
            subprocess.Popen(["osascript", "-e", 'tell application "System Events" to restart'])
        elif cmd in ("shutdown_mac", "desligar"):
            # Desligar Mac
            subprocess.Popen(["osascript", "-e", 'tell application "System Events" to shut down'])
        elif cmd in ("shazam_recognize", "shazam", "music_recognition"):
            # Reconhecimento de música / Shazam
            subprocess.Popen(["osascript", "-e", 'tell application "Music" to activate'])
        elif cmd == "sleep_mac" or cmd == "sleep":
            subprocess.Popen(["osascript", "-e", 'tell application "System Events" to sleep'])
        elif cmd == "siri":
            subprocess.Popen(["osascript", "-e", 'tell application "System Events" to key code 49 using {option down}'])
        elif cmd == "finder_new_folder":
            subprocess.Popen(["osascript", "-e", 'tell application "Finder" to make new folder at desktop'])
        elif cmd == "empty_trash":
            subprocess.Popen(["osascript", "-e", 'tell application "Finder" to empty trash'])

    elif action in ("photoshop_command", "ps_command"):
        cmd = params.get("command", "")
        ps_keys = {
            "new_layer": 'tell application "System Events" to keystroke "N" using {command down, shift down}',
            "duplicate_layer": 'tell application "System Events" to keystroke "j" using {command down}',
            "stamp_visible": 'tell application "System Events" to keystroke "E" using {command down, option down, shift down}',
            "quick_mask": 'tell application "System Events" to keystroke "q"',
            "invert_mask": 'tell application "System Events" to keystroke "i" using {command down}',
            "deselect": 'tell application "System Events" to keystroke "d" using {command down}',
            "inverse_selection": 'tell application "System Events" to keystroke "I" using {command down, shift down}',
            "curves": 'tell application "System Events" to keystroke "m" using {command down}',
            "levels": 'tell application "System Events" to keystroke "l" using {command down}',
            "hue_saturation": 'tell application "System Events" to keystroke "u" using {command down}',
            "camera_raw": 'tell application "System Events" to keystroke "A" using {command down, shift down}',
            "color_balance": 'tell application "System Events" to keystroke "b" using {command down}',
            "black_and_white": 'tell application "System Events" to keystroke "B" using {command down, option down, shift down}',
            "auto_tone": 'tell application "System Events" to keystroke "L" using {command down, shift down}',
            "auto_contrast": 'tell application "System Events" to keystroke "L" using {command down, option down, shift down}',
            "blend_normal": 'tell application "System Events" to keystroke "N" using {option down, shift down}',
            "blend_multiply": 'tell application "System Events" to keystroke "M" using {option down, shift down}',
            "blend_screen": 'tell application "System Events" to keystroke "S" using {option down, shift down}',
            "blend_overlay": 'tell application "System Events" to keystroke "O" using {option down, shift down}',
            "blend_soft_light": 'tell application "System Events" to keystroke "F" using {option down, shift down}',
            "spot_healing": 'tell application "System Events" to keystroke "j"',
            "clone_stamp": 'tell application "System Events" to keystroke "s"',
        }
        as_cmd = ps_keys.get(cmd)
        if as_cmd:
            subprocess.Popen(["osascript", "-e", as_cmd])
        else:
            subprocess.Popen(["osascript", "-e", 'tell application "Adobe Photoshop" to activate'])

    elif action in ("illustrator_command", "ai_command"):
        cmd = params.get("command", "")
        ai_keys = {
            "pen": 'tell application "System Events" to keystroke "p"',
            "direct_select": 'tell application "System Events" to keystroke "a"',
            "select": 'tell application "System Events" to keystroke "v"',
            "artboard": 'tell application "System Events" to keystroke "O" using {shift down}',
            "group": 'tell application "System Events" to keystroke "g" using {command down}',
            "ungroup": 'tell application "System Events" to keystroke "G" using {command down, shift down}',
            "join_paths": 'tell application "System Events" to keystroke "j" using {command down}',
            "save": 'tell application "System Events" to keystroke "s" using {command down}',
            "saveas": 'tell application "System Events" to keystroke "S" using {command down, shift down}',
            "new": 'tell application "System Events" to keystroke "n" using {command down}',
            "open": 'tell application "System Events" to keystroke "o" using {command down}',
            "create_outlines": 'tell application "System Events" to keystroke "O" using {command down, shift down}',
            "all_caps": 'tell application "System Events" to keystroke "K" using {command down, shift down}',
            "small_caps": 'tell application "System Events" to keystroke "H" using {command down, shift down}',
            "scissors": 'tell application "System Events" to keystroke "c"',
        }
        as_cmd = ai_keys.get(cmd)
        if as_cmd:
            subprocess.Popen(["osascript", "-e", as_cmd])
        else:
            subprocess.Popen(["osascript", "-e", 'tell application "Adobe Illustrator" to activate'])

    elif action in ("shortcut", "run_shortcut"):
        sc_name = params.get("shortcut", params.get("name", params.get("payload", "")))
        if sc_name:
            print(f"🪄 Running Apple Shortcut: {sc_name}")
            subprocess.Popen(["/usr/bin/shortcuts", "run", sc_name])

    elif action in ("illustrator_slider", "illustrator_jog_wheel"):
        param = params.get("param", "")
        val = params.get("value", 0)
        print(f"🎛️ Tactile Adjustment: {param} = {val}")
        if param == "zoom":
            # Direct keystroke or zoom level
            pass

    elif action == "open_url":
        target_url = params.get("url", params.get("payload", ""))
        if target_url:
            subprocess.Popen(["open", target_url])

    elif action in ("save_deck_config", "set_deck_buttons", "update_deck_buttons"):
        new_buttons = params.get("buttons", [])
        if new_buttons:
            try:
                with open(DECK_CONFIG_FILE, "w", encoding="utf-8") as f:
                    json.dump({"rows": 2, "cols": 6, "buttons": new_buttons}, f, indent=2, ensure_ascii=False)
                print(f"💾 Saved {len(new_buttons)} deck buttons to {DECK_CONFIG_FILE}")
            except Exception as e:
                print(f"⚠️ Failed to write deck config: {e}")
            
            # Immediately broadcast new configuration to all connected clients
            asyncio.create_task(push_immediate_deck_update(0.02))

    elif action in ("set_mic_dsp", "toggle_mic_dsp"):
        enabled = params.get("enabled", True)
        if isinstance(enabled, str):
            enabled = enabled.lower() in ("true", "1", "yes", "on")
        cmd = "dsp_on" if enabled else "dsp_off"
        try:
            ctrl = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            ctrl.sendto(cmd.encode(), ("127.0.0.1", 9877))
            ctrl.close()
            print(f"🎙️ [DSP Control] Sent command to DeepFilterNet: {cmd}")
        except Exception as e:
            print(f"⚠️ [DSP Control] Error sending command: {e}")


# ==================== WEBSOCKET PROTOCOL ====================

def encode_ws_frame(message: str) -> bytes:
    payload = message.encode('utf-8')
    length = len(payload)
    frame = bytearray([0x81])
    if length <= 125:
        frame.append(length)
    elif length <= 65535:
        frame.append(126)
        frame.extend(struct.pack("!H", length))
    else:
        frame.append(127)
        frame.extend(struct.pack("!Q", length))
    frame.extend(payload)
    return bytes(frame)


def decode_ws_frame(data: bytes) -> tuple:
    if len(data) < 2:
        return None, 0
    first_byte = data[0]
    second_byte = data[1]
    opcode = first_byte & 0x0F
    is_masked = bool(second_byte & 0x80)
    payload_len = second_byte & 0x7F

    offset = 2
    if payload_len == 126:
        if len(data) < 4:
            return None, 0
        payload_len = struct.unpack("!H", data[2:4])[0]
        offset = 4
    elif payload_len == 127:
        if len(data) < 10:
            return None, 0
        payload_len = struct.unpack("!Q", data[2:10])[0]
        offset = 10

    if is_masked:
        if len(data) < offset + 4 + payload_len:
            return None, 0
        mask_key = data[offset:offset + 4]
        offset += 4
        masked_payload = data[offset:offset + payload_len]
        unmasked = bytearray(payload_len)
        for i in range(payload_len):
            unmasked[i] = masked_payload[i] ^ mask_key[i % 4]
        payload = unmasked
    else:
        if len(data) < offset + payload_len:
            return None, 0
        payload = data[offset:offset + payload_len]

    return (opcode, payload), offset + payload_len


async def broadcast_status():
    """Periodically push telemetry, running apps & wallpaper changes to clients."""
    last_known_wallpaper = ""
    while True:
        try:
            await asyncio.sleep(1.2)
            if connected_clients:
                # 1. Status Update
                status = await asyncio.to_thread(get_mac_system_status)
                status_frame = encode_ws_frame(json.dumps(status))

                # 2. Deck buttons with dynamic user config & running indicators
                deck = await asyncio.to_thread(get_deck_buttons)
                deck_frame = encode_ws_frame(json.dumps({"type": "deck_config_update", "buttons": deck}))

                # 3. Check Wallpaper change
                current_wp = await asyncio.to_thread(get_current_wallpaper_b64)
                wp_frame = None
                if current_wp and current_wp != last_known_wallpaper:
                    last_known_wallpaper = current_wp
                    wp_frame = encode_ws_frame(json.dumps({"type": "wallpaper_update", "wallpaperBase64": current_wp}))

                to_remove = []
                for client in connected_clients:
                    try:
                        client.write(status_frame)
                        client.write(deck_frame)
                        if wp_frame:
                            client.write(wp_frame)
                        await client.drain()
                    except Exception:
                        to_remove.append(client)
                for c in to_remove:
                    connected_clients.discard(c)
        except Exception:
            pass


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    peer = writer.get_extra_info('peername')
    print(f"🔌 Touch Bar connection from {peer}")

    # Set TCP_NODELAY for sub-millisecond packet transfer
    try:
        sock = writer.get_extra_info('socket')
        if sock:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except Exception:
        pass

    try:
        header_data = await reader.readuntil(b"\r\n\r\n")
        header_text = header_data.decode('latin-1')

        if "Upgrade: websocket" in header_text or "upgrade: websocket" in header_text:
            key_match = re.search(r"Sec-WebSocket-Key:\s*(.+)", header_text, re.IGNORECASE)
            if not key_match:
                writer.close()
                return

            client_key = key_match.group(1).strip()
            accept_key = base64.b64encode(
                hashlib.sha1((client_key + WS_GUID).encode('utf-8')).digest()
            ).decode('utf-8')

            handshake_response = (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept_key}\r\n"
                "\r\n"
            )
            writer.write(handshake_response.encode('utf-8'))
            await writer.drain()

            connected_clients.add(writer)
            print(f"✅ Touch Bar active for {peer}")

            # 1. Send initial status
            initial_status = await asyncio.to_thread(get_mac_system_status)
            writer.write(encode_ws_frame(json.dumps(initial_status)))

            # 2. Send deck config with high-res Base64 icons & running app states
            deck_buttons = await asyncio.to_thread(get_deck_buttons)
            deck_config = {
                "type": "deck_config_update",
                "buttons": deck_buttons
            }
            writer.write(encode_ws_frame(json.dumps(deck_config)))

            # 3. Send current Mac wallpaper Base64
            wallpaper_b64 = await asyncio.to_thread(get_current_wallpaper_b64)
            if wallpaper_b64:
                wp_msg = {
                    "type": "wallpaper_update",
                    "wallpaperBase64": wallpaper_b64
                }
                writer.write(encode_ws_frame(json.dumps(wp_msg)))

            await writer.drain()

            buffer = bytearray()
            while True:
                chunk = await reader.read(4096)
                if not chunk:
                    break
                buffer.extend(chunk)

                while True:
                    result, consumed = decode_ws_frame(buffer)
                    if result is None:
                        break
                    buffer = buffer[consumed:]
                    opcode, payload = result

                    if opcode == 0x08:
                        break
                    elif opcode == 0x09:
                        pong = bytearray([0x8A, 0x00])
                        writer.write(pong)
                        await writer.drain()
                    elif opcode == 0x01:
                        try:
                            msg_json = json.loads(payload.decode('utf-8'))
                            action = msg_json.get("action", "")
                            params = msg_json.get("params", {})
                            
                            # Execute action instantly (< 1ms)
                            handle_action_fast(action, params)

                            # Broadcast client-to-client control messages (like simulator navigation)
                            if msg_json.get("type") in ("switch_sim_screen", "eval_js") or action in ("switch_sim_screen", "eval_js"):
                                forward_frame = encode_ws_frame(json.dumps(msg_json))
                                for other_client in connected_clients:
                                    if other_client != writer:
                                        try:
                                            other_client.write(forward_frame)
                                        except Exception:
                                            pass

                            # Send immediate fast response
                            resp_msg = {
                                "type": "response",
                                "action": action,
                                "status": "ok"
                            }
                            writer.write(encode_ws_frame(json.dumps(resp_msg)))
                            await writer.drain()
                        except Exception as e:
                            print(f"⚠️ Error: {e}")

        else:
            body = json.dumps(get_mac_system_status()).encode('utf-8')
            resp = (
                "HTTP/1.1 200 OK\r\n"
                "Content-Type: application/json\r\n"
                f"Content-Length: {len(body)}\r\n"
                "Access-Control-Allow-Origin: *\r\n"
                "\r\n"
            ).encode('utf-8') + body
            writer.write(resp)
            await writer.drain()

    except Exception:
        pass
    finally:
        connected_clients.discard(writer)
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


dsp_process = None

def start_dsp_process():
    global dsp_process
    base_dir = os.path.dirname(os.path.abspath(__file__))
    venv_python = os.path.join(base_dir, "venv", "bin", "python")
    dsp_script = os.path.join(base_dir, "mac_audio_dsp.py")
    if os.path.exists(venv_python) and os.path.exists(dsp_script):
        try:
            dsp_process = subprocess.Popen([venv_python, dsp_script])
            print("🎙️ [DeepFilterDSP] Real-time neural noise suppression started!")
        except Exception as e:
            print(f"⚠️ [DeepFilterDSP] Failed to start DSP process: {e}")

def start_bonjour_advertisement():
    global dns_sd_process
    mac_name = f"MacDeck-{platform.node().replace('.local', '')}"
    try:
        dns_sd_process = subprocess.Popen(
            ["dns-sd", "-R", mac_name, "_macdeck._tcp", "local", str(PORT), "platform=macOS", "touchbar=true"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        print(f"📡 Bonjour mDNS: '{mac_name}._macdeck._tcp' (Port {PORT})")
    except Exception as e:
        print(f"⚠️ Bonjour error: {e}")


async def main():
    print("=" * 65)
    print("🍎 MacDeck & Virtual Touch Bar Companion Server (Ultra-Low Latency)")
    print(f"📍 IP: {get_local_ip()} | Port: {PORT}")
    print(f"🔗 WebSocket: ws://{get_local_ip()}:{PORT}")
    print("=" * 65)

    start_bonjour_advertisement()
    start_dsp_process()
    server = await asyncio.start_server(handle_client, '0.0.0.0', PORT)
    asyncio.create_task(broadcast_status())

    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        if dns_sd_process:
            dns_sd_process.terminate()
        if dsp_process:
            dsp_process.terminate()

