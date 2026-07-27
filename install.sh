#!/usr/bin/env bash
# ==============================================================================
# Antigravity 2.0 GUI - Kiosk Installer (Optimized)
# ==============================================================================
# Version: v1.0.0
# ==============================================================================

set -e

INSTALLER_VERSION="1.0.0"

# ANSI Colors
CYAN='\033[38;5;39m'
CYAN_BOLD='\033[1;38;5;39m'
PURPLE_BOLD='\033[1;38;5;141m'
GREEN_BOLD='\033[1;38;5;48m'
RED_BOLD='\033[1;38;5;196m'
GRAY='\033[38;5;242m'
WHITE='\033[1;37m'
RESET='\033[0m'

DIM='\033[2m'

get_cols() {
    local c=""
    if [ -r /dev/tty ]; then c=$(stty size </dev/tty 2>/dev/null | awk '{print $2}' || true); fi
    if [ -z "$c" ]; then c=$(tput cols </dev/tty 2>/dev/null || true); fi
    if [ -z "$c" ] || ! [[ "$c" =~ ^[0-9]+$ ]] || [ "$c" -lt 25 ]; then c="${TERM_WIDTH:-${COLUMNS:-50}}"; fi
    if ! [[ "$c" =~ ^[0-9]+$ ]] || [ "$c" -lt 25 ]; then c=50; fi
    echo "$c"
}

wrap_log() {
    local prefix_vis_len="$1"; local prefix_str="$2"; local indent_str="$3"; local indent_vis_len="$4"; local text="$5"
    local cols=$(get_cols)
    local max_first=$(( cols - prefix_vis_len - 1 )); local max_cont=$(( cols - indent_vis_len - 1 ))
    if [ $max_first -lt 15 ]; then max_first=15; fi; if [ $max_cont -lt 15 ]; then max_cont=15; fi
    local words=($text); local line=""; local is_first=1
    for word in "${words[@]}"; do
        if [ ${#line} -eq 0 ]; then line="$word"; else
            local cur_limit=$max_first; if [ $is_first -eq 0 ]; then cur_limit=$max_cont; fi
            if [ $(( ${#line} + 1 + ${#word} )) -le $cur_limit ]; then line="$line $word"; else
                if [ $is_first -eq 1 ]; then echo -e "${prefix_str}${line}${RESET}"; is_first=0; else echo -e "${indent_str}${line}${RESET}"; fi
                line="$word"
            fi
        fi
    done
    if [ ${#line} -gt 0 ]; then
        if [ $is_first -eq 1 ]; then echo -e "${prefix_str}${line}${RESET}"; else echo -e "${indent_str}${line}${RESET}"; fi
    fi
}

step()    { echo -e ""; wrap_log 3 "◆  ${PURPLE_BOLD}" "   ${PURPLE_BOLD}└─ ${RESET}${PURPLE_BOLD}" 6 "$1"; }
info()    { wrap_log 6 "   ${CYAN}ℹ${RESET}  ${DIM}" "      ${DIM}└─ ${RESET}${DIM}" 9 "$1"; }
success() { wrap_log 6 "   ${GREEN_BOLD}✓${RESET}  ${WHITE}" "      ${DIM}└─ ${RESET}${WHITE}" 9 "$1"; }
error()   { wrap_log 6 "   ${RED_BOLD}✗  Error: ${RESET}${RED_BOLD}" "      ${DIM}└─ ${RESET}${RED_BOLD}" 9 "$1"; }

draw_banner() {
    local ver="$1"
    local term_w=$(get_cols)
    local max_w=$((term_w - 4))
    if [ "$max_w" -lt 38 ]; then max_w=38; fi

    local hline=""
    for ((i=0; i<max_w; i++)); do hline="${hline}─"; done

    pad_text() {
        local text="$1"; local vis_len="$2"
        local pad_len=$(( max_w - vis_len - 2 ))
        if [ "$pad_len" -lt 0 ]; then pad_len=0; fi
        local pad_str=""
        for ((i=0; i<pad_len; i++)); do pad_str="${pad_str} "; done
        echo -n "${text}${pad_str}"
    }

    echo -e "\n${CYAN_BOLD}  ┌${hline}┐${RESET}"
    echo -e "${CYAN_BOLD}  │ $(pad_text "${GRAY}ANTIGRAVITY 2.0  ${RESET}${PURPLE_BOLD}MOBILE GUI" 27) ${CYAN_BOLD}│${RESET}"
    echo -e "${CYAN_BOLD}  ├${hline}┤${RESET}"
    echo -e "${CYAN_BOLD}  │ $(pad_text "${GRAY}Version        : ${RESET}${GREEN_BOLD}v${ver}" $(( 18 + ${#ver} ))) ${CYAN_BOLD}│${RESET}"
    echo -e "${CYAN_BOLD}  │ $(pad_text "${GRAY}Target OS      : ${RESET}${WHITE}Android Termux X11" 35) ${CYAN_BOLD}│${RESET}"
    echo -e "${CYAN_BOLD}  │ $(pad_text "${GRAY}Architecture   : ${RESET}${WHITE}Debian PRoot Matchbox" 38) ${CYAN_BOLD}│${RESET}"
    echo -e "${CYAN_BOLD}  └${hline}┘${RESET}"
}

on_host_interrupt() {
    trap - SIGINT SIGTERM
    echo -e "\n${RED_BOLD}✗  Installation aborted by user.${RESET}"
    rm -f "$PREFIX/tmp/setup_antigravity.sh" /tmp/antigravity.tar.gz 2>/dev/null || true
    exit 130
}
trap on_host_interrupt SIGINT SIGTERM

clear || true
draw_banner "$INSTALLER_VERSION"

if [ -z "$PREFIX" ] || [ ! -d "/data/data/com.termux/files/usr" ]; then
    error "Must be executed within Termux."
    exit 1
fi

step "Initializing Host Environment (Termux System)"
info "Updating Termux repository mirrors (this may take a few moments)..."
# Use apt directly to avoid SSL/curl bootstrap issues with pkg
apt update -y >/dev/null 2>&1 || pkg update -y >/dev/null 2>&1 || true
# Full upgrade to fix any broken package states (e.g. libngtcp2_crypto_ossl SSL mismatch)
apt full-upgrade -y >/dev/null 2>&1 || true

# Host packages are configured for direct GPU container translation

info "Installing core system packages..."
# Enable x11 repo first so termux-x11-nightly is discoverable
pkg install -y x11-repo >/dev/null 2>&1 || true
pkg install -y proot-distro curl tar python xdotool >/dev/null 2>&1 || true
info "Installing GUI and hardware acceleration drivers..."
pkg install -y termux-x11-nightly >/dev/null 2>&1 || true

MISSING_PKGS=()
for cmd in proot-distro curl tar python3 termux-x11 xdotool; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_PKGS+=("$cmd")
    fi
done

if [ ${#MISSING_PKGS[@]} -ne 0 ]; then
    error "Failed to install required host packages: ${MISSING_PKGS[*]}"
    echo -e "   ${CYAN}ℹ${RESET}  ${DIM}└─ ${RESET}Run: apt update && apt full-upgrade -y && pkg install -y x11-repo termux-x11-nightly xdotool"
    exit 1
fi
success "Host utilities and dynamic GPU drivers successfully installed."

step "Verifying Debian Subsystem (PRoot Container)"
if ! proot-distro login debian -- true </dev/null >/dev/null 2>&1; then
    if ! proot-distro install debian </dev/null >/dev/null 2>&1; then
        error "Failed to provision Debian container. Check your connection."
        exit 1
    fi
    success "Debian container provisioned successfully."
else
    success "Debian container is already provisioned."
fi

SETUP_TMP_DIR="$PREFIX/tmp"
mkdir -p "$SETUP_TMP_DIR"
DEBIAN_SETUP_SCRIPT="$SETUP_TMP_DIR/setup_antigravity.sh"

cat << 'EOF_DEBIAN' > "$DEBIAN_SETUP_SCRIPT"
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

info() {
    echo -e "   \033[1;36mℹ\033[0m  \033[2m$1\033[0m"
}

info "Updating Debian package lists..."
apt-get update -y >/dev/null 2>&1

info "Installing X11, GTK, graphics, and secure keyring dependencies..."
apt-get install -y --no-install-recommends matchbox-window-manager curl wget ca-certificates tar \
    libnss3 libnspr4 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 \
    libgbm1 libpango-1.0-0 libcairo2 libasound2 libatk1.0-0 libcups2 libatk-bridge2.0-0 \
    libgtk-3-0 libgl1 libglx-mesa0 libegl1 libgl1-mesa-dri mesa-vulkan-drivers \
    dbus dbus-x11 gnome-keyring libsecret-1-0 x11-xserver-utils >/dev/null 2>&1 || \
apt-get install -y --no-install-recommends matchbox-window-manager curl wget ca-certificates tar \
    libnss3 libnspr4 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 \
    libgbm1 libpango-1.0-0 libcairo2 libasound2t64 libatk1.0-0t64 libcups2t64 libatk-bridge2.0-0t64 \
    libgtk-3-0t64 libgl1 libglx-mesa0 libegl1 libgl1-mesa-dri mesa-vulkan-drivers \
    dbus dbus-x11 gnome-keyring libsecret-1-0 x11-xserver-utils >/dev/null 2>&1 || true

info "Installing icon and emoji fonts..."
apt-get install -y --no-install-recommends \
    fonts-noto-core \
    fonts-noto-color-emoji \
    fontconfig >/dev/null 2>&1 || true
fc-cache -f >/dev/null 2>&1 || true

info "Resolving latest package versions (Antigravity 2.0 & Mesa)..."
RESOLVER_SCRIPT="/tmp/resolve_urls.py"
rm -f /usr/local/bin/resolve_urls.py
cat << 'EOF_RESOLVER' > "$RESOLVER_SCRIPT"
#!/usr/bin/env python3
import urllib.request
import re
import json
import gzip
import sys

def resolve_antigravity():
    base_url = "https://antigravity.google/download"
    visited = set()

    def fetch(url):
        if url in visited:
            return ""
        visited.add(url)
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)", "Accept-Encoding": "gzip"})
            res = urllib.request.urlopen(req)
            data = res.read()
            if res.info().get("Content-Encoding") == "gzip":
                data = gzip.decompress(data)
            return data.decode("utf-8", errors="ignore")
        except Exception:
            return ""

    html = fetch(base_url)
    if not html:
        return "", ""

    script_urls = set()
    for s in re.findall(r'src=["\'](.*?\.(?:js))["\']', html):
        script_urls.add("https://antigravity.google" + s if s.startswith("/") else s)

    text_to_search = [html]
    for surl in script_urls:
        stext = fetch(surl)
        if stext:
            text_to_search.append(stext)
            for imp in re.findall(r'from\s*["\'](\./[^"\']+\.js)["\']', stext):
                text_to_search.append(fetch("https://antigravity.google/_astro/" + imp.lstrip("./")))

    all_text = "\n".join(text_to_search).replace("\\/", "/")
    
    found = re.findall(r'https://[^\s"\'<>]*/linux-arm/[^\s"\'<>]*\.tar\.gz', all_text, re.IGNORECASE)
    if not found:
        found = re.findall(r'https://[^\s"\'<>]*linux[^\s"\'<>]*\.tar\.gz', all_text, re.IGNORECASE)

    if found:
        hub_found = [u for u in found if "antigravity-hub" in u or "storage.googleapis.com" in u]
        target = hub_found[0] if hub_found else found[0]
        ver_match = re.search(r'/([\d\.\-]+)/linux-arm', target)
        ver = ver_match.group(1) if ver_match else "latest"
        return target, ver

    return "", ""

def resolve_mesa():
    url = "https://api.github.com/repos/lfdevs/mesa-for-android-container/releases/latest"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        res = urllib.request.urlopen(req)
        data = json.loads(res.read().decode("utf-8"))
        tag = data.get("tag_name", "")
        assets = data.get("assets", [])
        debian_assets = [a.get("browser_download_url", "") for a in assets if "debian" in a.get("browser_download_url", "") and a.get("browser_download_url", "").endswith(".tar.gz")]
        if debian_assets:
            return debian_assets[0], tag
        arm64_assets = [a.get("browser_download_url", "") for a in assets if "arm64" in a.get("browser_download_url", "") and a.get("browser_download_url", "").endswith(".tar.gz")]
        if arm64_assets:
            return arm64_assets[0], tag
    except Exception:
        try:
            rel_req = urllib.request.Request("https://github.com/lfdevs/mesa-for-android-container/releases/latest", headers={"User-Agent": "Mozilla/5.0"})
            rel_res = urllib.request.urlopen(rel_req)
            tag = rel_res.geturl().split("/")[-1]
            dl = f"https://github.com/lfdevs/mesa-for-android-container/releases/download/{tag}/mesa-for-android-container_{tag}_debian_trixie_arm64.tar.gz"
            return dl, tag
        except Exception:
            pass
    return "", ""

if __name__ == "__main__":
    ag_url, ag_ver = resolve_antigravity()
    mesa_url, mesa_ver = resolve_mesa()
    print(json.dumps({
        "antigravity_url": ag_url,
        "antigravity_version": ag_ver,
        "mesa_url": mesa_url,
        "mesa_version": mesa_ver
    }))
EOF_RESOLVER

RESOLVED_JSON=$(python3 "$RESOLVER_SCRIPT" 2>/dev/null || echo "{}")
rm -f "$RESOLVER_SCRIPT"

AG_URL=$(echo "$RESOLVED_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('antigravity_url', ''))" 2>/dev/null || true)
AG_VER=$(echo "$RESOLVED_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('antigravity_version', ''))" 2>/dev/null || true)
MESA_URL=$(echo "$RESOLVED_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('mesa_url', ''))" 2>/dev/null || true)
MESA_VER=$(echo "$RESOLVED_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('mesa_version', ''))" 2>/dev/null || true)

mkdir -p /opt/antigravity

# --- Mesa Driver Installation & Version Check ---
INSTALLED_MESA_VER=$(cat /opt/antigravity/.installed_mesa_version 2>/dev/null || true)

if [ -n "$MESA_URL" ] && [ "$INSTALLED_MESA_VER" != "$MESA_VER" ]; then
    info "Downloading latest graphics drivers ($MESA_VER)..."
    wget -q --show-progress "$MESA_URL" -O /tmp/mesa-zink.tar.gz
    info "Installing Turnip and Zink graphics drivers..."
    tar -xzf /tmp/mesa-zink.tar.gz -C /
    rm -f /tmp/mesa-zink.tar.gz
    echo "$MESA_VER" > /opt/antigravity/.installed_mesa_version
    info "Mesa drivers successfully updated to version $MESA_VER."
else
    DISPLAY_MESA_VER="${INSTALLED_MESA_VER:-${MESA_VER:-latest}}"
    info "Mesa graphics drivers are up to date ($DISPLAY_MESA_VER)."
fi

# --- Antigravity 2.0 Package Installation & Version Check ---
INSTALLED_AG_VER=$(cat /opt/antigravity/.installed_version 2>/dev/null || true)

if [ ! -x "/opt/antigravity/antigravity" ] || { [ -n "$AG_VER" ] && [ "$INSTALLED_AG_VER" != "$AG_VER" ]; }; then
    if [ -n "$AG_URL" ]; then
        info "Downloading latest Antigravity 2.0 (${AG_VER:-latest})..."
        wget -q --show-progress "$AG_URL" -O /tmp/antigravity.tar.gz
        info "Extracting and updating Antigravity binaries..."
        find /opt/antigravity -mindepth 1 -maxdepth 1 ! -name '.installed*' -exec rm -rf {} + 2>/dev/null || true
        tar -xzf /tmp/antigravity.tar.gz -C /opt/antigravity --strip-components=1 2>/dev/null || tar -xzf /tmp/antigravity.tar.gz -C /opt/antigravity
        rm -f /tmp/antigravity.tar.gz
        [ -f "/opt/antigravity/Antigravity" ] && mv /opt/antigravity/Antigravity /opt/antigravity/antigravity
        chmod +x /opt/antigravity/antigravity
        [ -n "$AG_VER" ] && echo "$AG_VER" > /opt/antigravity/.installed_version
        info "Antigravity Core successfully updated to version ${AG_VER:-latest}."
    else
        echo "Error: Could not resolve Antigravity 2.0 download URL from google.com."
        if [ ! -x "/opt/antigravity/antigravity" ]; then
            exit 1
        fi
    fi
else
    DISPLAY_AG_VER="${INSTALLED_AG_VER:-${AG_VER:-latest}}"
    info "Antigravity Core is up to date ($DISPLAY_AG_VER)."
fi
# Replaced Openbox configurations with Matchbox window manager defaults

# Create custom xdg-open to redirect browser launches to host via FIFO
cat << 'EOF_XDG' > /usr/local/bin/xdg-open
#!/bin/bash
if [ -p /tmp/termux_open_fifo ]; then
    echo "$1" > /tmp/termux_open_fifo
else
    echo "FIFO not found, cannot open: $1" >&2
fi
EOF_XDG
chmod +x /usr/local/bin/xdg-open

# Run script for Antigravity inside Debian
cat << 'EOF_RUN' > /opt/antigravity/run.sh
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DISPLAY=:0
export ELECTRON_OZONE_PLATFORM_HINT=x11
export GDK_BACKEND=x11
export NO_AT_BRIDGE=1
export XDG_RUNTIME_DIR=/tmp/runtime-root

# Ensure runtime & D-Bus directories exist to prevent connection log errors
mkdir -p /var/run/dbus /run/dbus "$XDG_RUNTIME_DIR" 2>/dev/null || true
touch /etc/drirc "$HOME/.drirc" 2>/dev/null || true

# Initialize gnome-keyring-daemon (Passwordless login keyring)
mkdir -p "$HOME/.local/share/keyrings"
if [ ! -f "$HOME/.local/share/keyrings/default" ]; then
    echo -n "login" > "$HOME/.local/share/keyrings/default"
fi
if [ ! -f "$HOME/.local/share/keyrings/login.keyring" ]; then
    echo "[keyring]" > "$HOME/.local/share/keyrings/login.keyring"
    echo "display-name=login" >> "$HOME/.local/share/keyrings/login.keyring"
    echo "ctime=0" >> "$HOME/.local/share/keyrings/login.keyring"
    echo "mtime=0" >> "$HOME/.local/share/keyrings/login.keyring"
    echo "lock-on-idle=false" >> "$HOME/.local/share/keyrings/login.keyring"
    echo "lock-after=false" >> "$HOME/.local/share/keyrings/login.keyring"
    chmod 600 "$HOME/.local/share/keyrings/login.keyring" "$HOME/.local/share/keyrings/default"
fi

# Start D-Bus system and session services if not running
if [ -x /etc/init.d/dbus ]; then
    /etc/init.d/dbus start >/dev/null 2>&1 || true
fi
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

# Unlock/Start the keyring daemon
echo -n "" | gnome-keyring-daemon --unlock --components=secrets >/dev/null 2>&1 || true
eval $(gnome-keyring-daemon --start --components=secrets)
export GNOME_KEYRING_CONTROL
export GNOME_KEYRING_PID

# Global UI Scaling (3x)
export GDK_SCALE=3
export GDK_DPI_SCALE=1
export QT_SCALE_FACTOR=3
export ELM_SCALE=3
export XCURSOR_SIZE=36
echo "Xft.dpi: 288" | xrdb -merge 2>/dev/null || true

# Hardware Acceleration Flags (Native Zink + Turnip KGSL)
export GALLIUM_DRIVER=zink
export MESA_LOADER_DRIVER_OVERRIDE=zink
export TU_DEBUG=sysmem,noconform
export ZINK_DESCRIPTORS=lazy
export MESA_VK_WSI_PRESENT_MODE=mailbox
export MESA_VK_IGNORE_EXTENSIONS="VK_EXT_calibrated_timestamps,VK_KHR_calibrated_timestamps"
export MESA_GL_VERSION_OVERRIDE=4.6COMPAT
export MESA_GLES_VERSION_OVERRIDE=3.2
export MESA_GLTHREAD=true
export vblank_mode=0
GPU_ARGS="--ignore-gpu-blocklist --disable-vulkan --enable-gpu-rasterization --enable-oop-rasterization --canvas-oop-rasterization --gpu-rasterization-msaa-sample-count=0 --enable-zero-copy --use-gl=angle --enable-webgl --enable-accelerated-2d-canvas --num-raster-threads=8 --start-maximized --disable-gpu-sandbox --force-device-scale-factor=3 --enable-smooth-scrolling"

SOFTWARE_MODE=0
DEBUG_MODE=0
ARGS=()
for arg in "$@"; do
    if [ "$arg" == "--debug" ]; then
        DEBUG_MODE=1
    elif [ "$arg" == "--software" ]; then
        SOFTWARE_MODE=1
    else
        ARGS+=("$arg")
    fi
done

if [ "$SOFTWARE_MODE" -eq 1 ]; then
    export LIBGL_ALWAYS_SOFTWARE=1
    export GALLIUM_DRIVER=llvmpipe
    GPU_ARGS="--disable-gpu --force-device-scale-factor=3"
fi

if ! pgrep -f "matchbox-window-manager" > /dev/null 2>&1; then matchbox-window-manager -use_titlebar no & sleep 0.2; fi

# Clean up orphaned language_server instances and singleton locks to prevent white screen on auto-restart
pkill -9 -f "language_server" >/dev/null 2>&1 || true
rm -rf "$HOME/.config/Antigravity/Singleton*" "$HOME/.config/Antigravity/lockfile" 2>/dev/null || true

# Launch App
if [ "$DEBUG_MODE" -eq 1 ]; then
    export ELECTRON_ENABLE_LOGGING=1
    export ELECTRON_ENABLE_STACK_DUMPING=1
    exec /opt/antigravity/antigravity --no-sandbox $GPU_ARGS --enable-logging --v=1 --log-level=0 "${ARGS[@]}"
else
    exec /opt/antigravity/antigravity --no-sandbox $GPU_ARGS "${ARGS[@]}" >/dev/null 2>&1
fi
EOF_RUN
chmod +x /opt/antigravity/run.sh
EOF_DEBIAN
chmod +x "$DEBIAN_SETUP_SCRIPT"

step "Executing Subsystem Configuration inside Container"
proot-distro login debian --bind "$SETUP_TMP_DIR:/installer_tmp" --shared-tmp -- bash /installer_tmp/setup_antigravity.sh </dev/null
rm -f "$DEBIAN_SETUP_SCRIPT"

step "Applying Native VA39 Binary Patch to Language Server"
PATCHER="$PREFIX/bin/patch_va39.py"
cat << 'EOF_PATCHER' > "$PATCHER"
import shutil
import struct
from pathlib import Path
import os

bin_path = Path("/data/data/com.termux/files/usr/var/lib/proot-distro/containers/debian/rootfs/opt/antigravity/resources/bin/language_server")
bak_path = Path(str(bin_path) + ".bak")
flag_path = Path(str(bin_path) + ".patched")

if not bin_path.exists():
    print("Warning: language_server not found. Skipping binary patch.")
    exit(0)

# Check if already patched by looking at our mmap signature
try:
    data = bytearray(bin_path.read_bytes())
    if data.count(struct.pack("<I", 0xD2C00409)) > 0 and data.count(struct.pack("<I", 0xD2C20009)) == 0:
        print("   \033[1;32m✓\033[0m  VA39 binary patch already applied.")
        flag_path.touch()
        exit(0)
except Exception as e:
    print(f"Error reading {bin_path}: {e}")
    exit(1)

print("   \033[1;36mℹ\033[0m  \033[2mUnpatched binary detected. Applying VA39 patch...\033[0m")

# Create backup of the unpatched binary if it doesn't exist
if not bak_path.exists():
    shutil.copyfile(bin_path, bak_path)
elif os.path.getmtime(bin_path) > os.path.getmtime(bak_path):
    shutil.copyfile(bin_path, bak_path)

data = bytearray(bak_path.read_bytes())

def get(off): return struct.unpack_from("<I", data, off)[0]
def put(off, word): struct.pack_into("<I", data, off, word)

def find_section(name_target):
    if data[:4] != b"\x7fELF": return None, None
    e_shoff = struct.unpack_from("<Q", data, 40)[0]
    e_shentsize = struct.unpack_from("<H", data, 58)[0]
    e_shnum = struct.unpack_from("<H", data, 60)[0]
    e_shstrndx = struct.unpack_from("<H", data, 62)[0]
    shstr_base = e_shoff + e_shstrndx * e_shentsize
    shstr_off = struct.unpack_from("<Q", data, shstr_base + 24)[0]
    for i in range(e_shnum):
        base = e_shoff + i * e_shentsize
        sh_name = struct.unpack_from("<I", data, base)[0]
        sh_offset = struct.unpack_from("<Q", data, base + 24)[0]
        sh_size = struct.unpack_from("<Q", data, base + 32)[0]
        nend = data.index(b"\x00", shstr_off + sh_name)
        section = data[shstr_off + sh_name : nend].decode("utf-8", errors="replace")
        if section == name_target:
            return sh_offset, sh_offset + sh_size
    return None, None

lo, hi = 0, len(data)
sec_lo, sec_hi = find_section("google_malloc")
if sec_lo is not None: lo, hi = sec_lo, sec_hi
else:
    sec_lo, sec_hi = find_section(".text")
    if sec_lo is not None: lo, hi = sec_lo, sec_hi

word_rewrites = {
    0xD2C20009: 0xD2C00409, 0xD2C2000A: 0xD2C0040A,
    0xF2C20008: 0xF2DFF408, 0xF2C20009: 0xF2DFF409,
    0xD2C10009: 0xD2C00209, 0xD2C1000A: 0xD2C0020A,
    0xF2C38008: 0xF2DFF708, 0xF2C38009: 0xF2DFF709,
    0x92560A6C: 0x925D0A6C, 0x92560A6A: 0x925D0A6A,
    0xD2C3000D: 0xD2C0060D, 0xD2C3000C: 0xD2C0060C,
    0xD2C08008: 0xD2C00108,
}

ubfx_count = lsl_count = mask_count = mmap_count = tags_count = 0
for off in range(lo, hi, 4):
    w = get(off)
    if (w & 0x7F800000) == 0x53000000:
        immr = (w >> 16) & 0x3F
        imms = (w >> 10) & 0x3F
        if immr == 42 and imms == 44:
            put(off, (w & ~((0x3F << 16) | (0x3F << 10))) | (35 << 16) | (37 << 10))
            ubfx_count += 1
        elif immr == 22 and imms == 21:
            put(off, (w & ~((0x3F << 16) | (0x3F << 10))) | (29 << 16) | (28 << 10))
            lsl_count += 1
    elif w == 0xF2E00029:
        put(off, 0xD3596129)
        mmap_count += 1
    elif w == 0x92D3800A and off + 4 < hi and get(off + 4) == 0xF2E0000A:
        put(off, 0x9280000A)
        put(off + 4, 0xD35DFD4A)
        mask_count += 1
    elif w in word_rewrites:
        put(off, word_rewrites[w])
        tags_count += 1

bin_path.write_bytes(data)
bin_path.chmod(0o755)
flag_path.touch()

print(f"   \033[1;36mℹ\033[0m  \033[2mPatches applied: UBFX={ubfx_count}, LSL={lsl_count}, MASK={mask_count}, MMAP={mmap_count}, TAGS={tags_count}\033[0m")
print("   \033[1;32m✓\033[0m  Native VA39 Binary Patch applied successfully.")
EOF_PATCHER
python3 "$PATCHER"

# Deploy helper watchdog script for Termux host to track window presence
GEM_WATCHDOG="$PREFIX/bin/gem-watchdog"
cat << 'EOF_WATCHDOG' > "$GEM_WATCHDOG"
#!/usr/bin/env bash
sleep 8
while true; do
    if ! pgrep -f "/opt/antigravity/antigravity" >/dev/null; then
        exit 0
    fi
    if ! DISPLAY=:0 xdotool search --onlyvisible --class "antigravity" >/dev/null 2>&1; then
        # Visible window is gone but process is alive -> user clicked close button
        pkill -f "/opt/antigravity|language_server" >/dev/null 2>&1 || true
        exit 0
    fi
    sleep 2
done
EOF_WATCHDOG
chmod +x "$GEM_WATCHDOG"
if command -v termux-fix-shebang >/dev/null 2>&1; then termux-fix-shebang "$GEM_WATCHDOG"; fi

step "Deploying Command-Line Launcher ('gem')"
GEM_LAUNCHER="$PREFIX/bin/gem"
cat << 'EOF_TERMUX' > "$GEM_LAUNCHER"
#!/usr/bin/env bash
unset LD_PRELOAD
unset LD_LIBRARY_PATH
export DISPLAY=:0

cleanup_and_exit() {
    trap - SIGINT SIGTERM
    pkill -f gem-watchdog >/dev/null 2>&1 || true
    pkill -TERM -P $$ 2>/dev/null || true
    pkill -f "antigravity|matchbox|language_server" >/dev/null 2>&1 || true
    if [ -n "$FIFO_PID" ]; then kill -9 "$FIFO_PID" 2>/dev/null || true; fi
    rm -f "/data/data/com.termux/files/usr/tmp/termux_open_fifo"
    
    # Fast container-side shutdown
    /data/data/com.termux/files/usr/bin/proot \
        --rootfs="/data/data/com.termux/files/usr/var/lib/proot-distro/containers/debian/rootfs" \
        /bin/bash -c "pkill -9 -f 'antigravity|language_server'" >/dev/null 2>&1 || true
    
    echo -e "\n\033[1;38;5;221m  ┌──────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;38;5;221m  │ \033[38;5;242mSTATUS         : \033[0m\033[1;38;5;221mSHUTTING DOWN ANTIGRAVITY       \033[1;38;5;221m│\033[0m"
    echo -e "\033[1;38;5;221m  └──────────────────────────────────────────────────┘\033[0m\n"
    exit 0
}
trap cleanup_and_exit SIGINT SIGTERM

# Start FIFO bridge
FIFO="/data/data/com.termux/files/usr/tmp/termux_open_fifo"
rm -f "$FIFO"; mkfifo "$FIFO"
( while [ -p "$FIFO" ]; do if read -r url < "$FIFO"; then termux-open "$url"; fi; done ) &
FIFO_PID=$!

get_cols() {
    local c=""
    if [ -r /dev/tty ]; then c=$(stty size </dev/tty 2>/dev/null | awk '{print $2}' || true); fi
    if [ -z "$c" ]; then c=$(tput cols </dev/tty 2>/dev/null || true); fi
    if [ -z "$c" ] || ! [[ "$c" =~ ^[0-9]+$ ]] || [ "$c" -lt 25 ]; then c="${TERM_WIDTH:-${COLUMNS:-50}}"; fi
    if ! [[ "$c" =~ ^[0-9]+$ ]] || [ "$c" -lt 25 ]; then c=50; fi
    echo "$c"
}

draw_banner() {
    local ver="$1"
    local term_w=$(get_cols)
    local max_w=$((term_w - 4))
    if [ "$max_w" -lt 38 ]; then max_w=38; fi

    local hline=""
    for ((i=0; i<max_w; i++)); do hline="${hline}─"; done

    pad_text() {
        local text="$1"; local vis_len="$2"
        local pad_len=$(( max_w - vis_len - 2 ))
        if [ "$pad_len" -lt 0 ]; then pad_len=0; fi
        local pad_str=""
        for ((i=0; i<pad_len; i++)); do pad_str="${pad_str} "; done
        echo -n "${text}${pad_str}"
    }

    echo -e "\n\033[1;38;5;39m  ┌${hline}┐\033[0m"
    echo -e "\033[1;38;5;39m  │ $(pad_text "\033[38;5;242mANTIGRAVITY 2.0  \033[0m\033[1;38;5;141mMOBILE GUI" 27) \033[1;38;5;39m│\033[0m"
    echo -e "\033[1;38;5;39m  ├${hline}┤\033[0m"
    echo -e "\033[1;38;5;39m  │ $(pad_text "\033[38;5;242mVersion        : \033[0m\033[1;38;5;48mv${ver}" $(( 18 + ${#ver} ))) \033[1;38;5;39m│\033[0m"
    echo -e "\033[1;38;5;39m  │ $(pad_text "\033[38;5;242mTarget OS      : \033[0m\033[1;37mAndroid Termux X11" 35) \033[1;38;5;39m│\033[0m"
    echo -e "\033[1;38;5;39m  │ $(pad_text "\033[38;5;242mArchitecture   : \033[0m\033[1;37mDebian PRoot Matchbox" 38) \033[1;38;5;39m│\033[0m"
    echo -e "\033[1;38;5;39m  └${hline}┘\033[0m"
}

draw_banner "1.0.0"
echo -e "  \033[1;30m💡 Tip: Press \033[1;31mCtrl+C\033[1;30m in this terminal to exit gracefully.\033[0m\n"

# Auto-Patching mechanism for Updates
BIN_PATH="/data/data/com.termux/files/usr/var/lib/proot-distro/containers/debian/rootfs/opt/antigravity/resources/bin/language_server"
FLAG_FILE="${BIN_PATH}.patched"
if [ "$BIN_PATH" -nt "$FLAG_FILE" ] || [ ! -f "$FLAG_FILE" ]; then
    echo -e "\033[1;33m[UPDATE DETECTED] Re-applying VA39 binary patch to language_server...\033[0m"
    python3 "$PREFIX/bin/patch_va39.py"
fi

DEBUG_MODE=0
for arg in "$@"; do
    if [ "$arg" == "--debug" ]; then
        DEBUG_MODE=1
    elif [ "$arg" == "--proot-reset" ]; then
        echo -e "\n\033[1;33m⚠️ WARNING: This will completely reinstall the proot container and all its files.\033[0m"
        read -p "Are you sure you want to proceed? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "\033[1;32mResetting proot-distro...\033[0m"
            proot-distro reset debian
            echo -e "\033[1;32mReinstalling Antigravity-Mobile...\033[0m"
            curl -sL https://raw.githubusercontent.com/tr1xx-tech/Antigravity-Mobile/main/install.sh | bash
            exit 0
        else
            echo "Cancelled."
            exit 0
        fi
    elif [ "$arg" == "--full-delete" ]; then
        echo -e "\n\033[1;31m⚠️  WARNING: This will completely DELETE the application, container, caches, and all related files.\033[0m"
        read -p "Are you sure you want to proceed? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "\033[1;31mDeleting proot-distro container...\033[0m"
            proot-distro remove debian >/dev/null 2>&1 || true
            echo -e "\033[1;31mRemoving Termux host packages...\033[0m"
            pkg uninstall -y proot-distro termux-x11-nightly >/dev/null 2>&1 || true
            echo -e "\033[1;31mRemoving patcher & watchdog scripts...\033[0m"
            rm -f "$PREFIX/bin/patch_va39.py" "$PREFIX/bin/gem-watchdog"
            echo -e "\033[1;31mRemoving gem launcher...\033[0m"
            rm -f "$PREFIX/bin/gem"
            echo -e "\033[1;31mRemoving Antigravity config and cache...\033[0m"
            rm -rf "$HOME/.config/Antigravity"
            rm -f "$HOME/antigravity_debug.log"
            echo -e "\033[1;32mSuccessfully deleted everything. You can close Termux now.\033[0m"
            exit 0
        else
            echo "Cancelled."
            exit 0
        fi
    fi
done

PROOT_ARGS=(
    --kill-on-exit --link2symlink --sysvipc
    --kernel-release="Linux localhost 6.17.0-PRoot-Distro #1 SMP PREEMPT_DYNAMIC Fri, 10 Oct 2025 00:00:00 +0000 aarch64 localdomain -1"
    -L --change-id=0:0
    --rootfs="/data/data/com.termux/files/usr/var/lib/proot-distro/containers/debian/rootfs"
    --cwd=/root --bind=/dev --bind=/proc --bind=/sys --bind=/dev/urandom:/dev/random
)

if [ ! -L /dev/fd ]; then PROOT_ARGS+=(--bind=/proc/self/fd:/dev/fd); fi
for i in 0 1 2; do
    name=""; case $i in 0) name="stdin" ;; 1) name="stdout" ;; 2) name="stderr" ;; esac
    if [ ! -L "/dev/$name" ] && [ -e "/proc/self/fd/$i" ]; then PROOT_ARGS+=(--bind=/proc/self/fd/$i:/dev/$name); fi
done

SYSDATA_DIR="/data/data/com.termux/files/usr/var/lib/proot-distro/containers/debian/sysdata"
PROOT_ARGS+=(
    --bind="$SYSDATA_DIR/sys_empty:/sys/fs/selinux"
    --bind="$SYSDATA_DIR/loadavg:/proc/loadavg"
    --bind="$SYSDATA_DIR/stat:/proc/stat"
    --bind="$SYSDATA_DIR/uptime:/proc/uptime"
    --bind="$SYSDATA_DIR/version:/proc/version"
    --bind="$SYSDATA_DIR/vmstat:/proc/vmstat"
    --bind="$SYSDATA_DIR/sysctl_entry_cap_last_cap:/proc/sys/kernel/cap_last_cap"
    --bind="$SYSDATA_DIR/sysctl_inotify_max_user_watches:/proc/sys/fs/inotify/max_user_watches"
    --bind="$SYSDATA_DIR/sysctl_kernel_overflowuid:/proc/sys/kernel/overflowuid"
    --bind="$SYSDATA_DIR/sysctl_kernel_overflowgid:/proc/sys/kernel/overflowgid"
)

PROOT_ARGS+=(
    --bind="/data/data/com.termux/files/usr/var/lib/proot-distro/containers/debian/rootfs/tmp:/dev/shm"
    --bind="/data/data/com.termux/files/usr/tmp:/tmp"
    --bind="/data/data/com.termux/files/usr/tmp/.X11-unix:/tmp/.X11-unix"
)

for p in /data/app /data/dalvik-cache /data/misc/apexdata/com.android.art/dalvik-cache /apex /odm /product /system /system_ext /vendor /linkerconfig/ld.config.txt /linkerconfig/com.android.art/ld.config.txt; do
    if [ -d "$p" ] || [ -f "$p" ]; then PROOT_ARGS+=(--bind="$p"); fi
done

if [ -d "/storage/self/primary" ]; then PROOT_ARGS+=(--bind=/storage/self/primary:/sdcard); fi

PROOT_ARGS+=( --bind="/data/data/com.termux/cache" --bind="$HOME" --bind="$PREFIX" )

# Launch loop (automatic restart on close/disconnect)
while true; do
    if ! pgrep -f "termux-x11" > /dev/null 2>&1; then
        termux-x11 :0 >/dev/null 2>&1 &
        sleep 1
    fi

    if [ "$DEBUG_MODE" -eq 0 ]; then
        if ! am start -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1; then
            echo -e "\n\033[1;31m✗ Error: Termux-X11 Android App is not installed!\033[0m"
            echo -e "\033[1;34mℹ\033[0m You need the Termux-X11 app to view the GUI."
            echo -e "\033[1;34mℹ\033[0m Opening the GitHub download page..."
            termux-open "https://github.com/termux/termux-x11/releases"
            exit 1
        fi
    fi

    # Start X11 Window Monitor in background
    gem-watchdog &

    if [ "$DEBUG_MODE" -eq 1 ]; then
        echo -e "\033[1;33m[DEBUG] Running in foreground. Logs are saved to /data/data/com.termux/files/home/antigravity_debug.log\033[0m"
        /data/data/com.termux/files/usr/bin/proot "${PROOT_ARGS[@]}" /opt/antigravity/run.sh "$@" 2>&1 | tee /data/data/com.termux/files/home/antigravity_debug.log
    else
        /data/data/com.termux/files/usr/bin/proot "${PROOT_ARGS[@]}" /opt/antigravity/run.sh "$@" >/dev/null 2>&1 &
        wait "$!" 2>/dev/null || true
    fi

    pkill -f gem-watchdog >/dev/null 2>&1 || true
    sleep 1
done
cleanup_and_exit
EOF_TERMUX

chmod +x "$GEM_LAUNCHER"
if command -v termux-fix-shebang >/dev/null 2>&1; then termux-fix-shebang "$GEM_LAUNCHER"; fi

success "Installation and Optimization Complete. Run 'gem' to start."
