#!/usr/bin/env bash
# build-goo-engine.sh - clone and build Goo Engine on common Linux distros.
#
# Uses Blender's own tooling so the build matches upstream:
#   1. install_linux_packages.py installs build dependencies for your distro
#   2. make_update.py --use-linux-libraries fetches submodules and the precompiled
#      libraries (bundled Python 3.11, FFmpeg, OpenEXR, ...). Upstream makes the Linux
#      libraries opt-in, so a plain `make update` skips them and the build falls back
#      to system libraries (which fails on distros with a newer Python).
#   3. `make` builds; the result lands in <workdir>/build_linux/bin
#
# Untested draft - please report issues.

set -euo pipefail

REPO_URL="https://github.com/dillongoostudios/goo-engine.git"
BRANCH="goo-engine-v4.4-release"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$SCRIPT_DIR/work"
JOBS="$(nproc)"
PREFIX=""
SKIP_DEPS=0
KEEP_HARU=0
SEPARATE_CONFIG=0
INSTALL_DESKTOP=1
CMAKE_ARGS_STR=""

usage() {
  cat <<USAGE
Usage: $0 [options]
  -b, --branch NAME   branch to build (default: $BRANCH)
  -r, --repo URL      source repository (default: $REPO_URL)
  -w, --workdir DIR   where to clone and build (default: $WORKDIR)
  -j, --jobs N        parallel jobs (default: $(nproc); lower it if you run out of RAM)
  -p, --prefix DIR    copy the finished build to DIR and link ~/.local/bin/goo-engine
      --skip-deps     don't install system packages
      --cmake-arg ARG extra CMake argument, repeatable (e.g. --cmake-arg -DWITH_CYCLES=OFF)
      --with-haru     keep libharu (Grease Pencil PDF export); may fail to link, see README
      --separate-config  with --prefix: keep Goo's settings/add-ons apart from stock Blender
      --no-desktop    with --prefix: don't install an application-menu entry
  -h, --help          show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--branch)  BRANCH="$2"; shift 2 ;;
    -r|--repo)    REPO_URL="$2"; shift 2 ;;
    -w|--workdir) WORKDIR="$2"; shift 2 ;;
    -j|--jobs)    JOBS="$2"; shift 2 ;;
    -j[0-9]*)     JOBS="${1#-j}"; shift ;;
    --jobs=*)     JOBS="${1#--jobs=}"; shift ;;
    -p|--prefix)  PREFIX="$2"; shift 2 ;;
    --skip-deps)  SKIP_DEPS=1; shift ;;
    --cmake-arg)  CMAKE_ARGS_STR+=" $2"; shift 2 ;;
    --with-haru)  KEEP_HARU=1; shift ;;
    --separate-config) SEPARATE_CONFIG=1; shift ;;
    --no-desktop) INSTALL_DESKTOP=0; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# libharu (Grease Pencil PDF export) fails to link when CMake picks up a system
# libtiff.so, which doesn't export the symbols libharu needs. It's off by default.
if (( KEEP_HARU )); then
  CMAKE_ARGS_STR+=" -DWITH_HARU=ON"
else
  CMAKE_ARGS_STR+=" -DWITH_HARU=OFF"
fi

SRC_DIR="$WORKDIR/goo-engine"
BUILD_BIN="$WORKDIR/build_linux/bin"

# --- sanity checks ---------------------------------------------------------
command -v git >/dev/null || { echo "git is required." >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required." >&2; exit 1; }
[[ "$(uname -m)" == "x86_64" ]] || echo "Warning: precompiled libs are only provided for x86_64."

mkdir -p "$WORKDIR"
avail_gb=$(df -BG --output=avail "$WORKDIR" | tail -1 | tr -dc '0-9')
(( avail_gb >= 40 )) || echo "Warning: only ${avail_gb} GB free in $WORKDIR; a build needs roughly 40 GB."

mem_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
safe_jobs=$(( mem_gb / 2 > 0 ? mem_gb / 2 : 1 ))
(( JOBS <= safe_jobs )) || echo "Note: ${mem_gb} GB RAM with $JOBS jobs may run out of memory; consider -j $safe_jobs."

# --- get the source --------------------------------------------------------
if [[ -d "$SRC_DIR/.git" ]]; then
  echo "==> Updating existing checkout in $SRC_DIR..."
  git -C "$SRC_DIR" fetch origin "$BRANCH"
  git -C "$SRC_DIR" checkout "$BRANCH"
  git -C "$SRC_DIR" pull --ff-only origin "$BRANCH"
else
  echo "==> Cloning $REPO_URL ($BRANCH)..."
  git clone --branch "$BRANCH" "$REPO_URL" "$SRC_DIR"
fi
cd "$SRC_DIR"

# --- dependencies ----------------------------------------------------------
if (( ! SKIP_DEPS )); then
  INSTALLER="build_files/build_environment/install_linux_packages.py"
  if [[ -f "$INSTALLER" ]]; then
    echo "==> Installing build dependencies (may ask for sudo)..."
    python3 "$INSTALLER"
  else
    echo "Dependency installer not found on this branch; install Blender's build dependencies manually."
  fi
fi

# --- submodules and precompiled libs --------------------------------------
echo "==> Fetching submodules and precompiled libraries (large download)..."
python3 build_files/utils/make_update.py --use-linux-libraries

if [[ -z "$(ls -A lib/linux_x64 2>/dev/null)" ]]; then
  echo "Precompiled libraries were not fetched (lib/linux_x64 is empty)." >&2
  echo "The build would fall back to system libraries and likely fail on Python 3.11." >&2
  exit 1
fi

# --- build -----------------------------------------------------------------
echo "==> Building with $JOBS jobs (CMake args:${CMAKE_ARGS_STR})..."
export MAKEFLAGS="-j${JOBS}"
make -j"$JOBS" BUILD_CMAKE_ARGS="${CMAKE_ARGS_STR# }"

[[ -x "$BUILD_BIN/blender" ]] || { echo "Build finished but $BUILD_BIN/blender is missing." >&2; exit 1; }

# --- optional install ------------------------------------------------------
if [[ -n "$PREFIX" ]]; then
  mkdir -p "$PREFIX" "$HOME/.local/bin"
  PREFIX="$(cd "$PREFIX" && pwd)"
  echo "==> Installing to $PREFIX..."
  cp -a "$BUILD_BIN/." "$PREFIX/"

  # Remove any old launcher first: writing through an old symlink would
  # overwrite the blender binary it points to.
  LAUNCHER="$HOME/.local/bin/goo-engine"
  rm -f "$LAUNCHER"
  if (( SEPARATE_CONFIG )); then
    CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/goo-engine"
    cat > "$LAUNCHER" <<LAUNCH
#!/usr/bin/env bash
# Keeps Goo Engine's settings, add-ons and extensions apart from stock Blender.
export BLENDER_USER_RESOURCES="$CONFIG_DIR"
mkdir -p "\$BLENDER_USER_RESOURCES"
exec "$PREFIX/blender" "\$@"
LAUNCH
    chmod +x "$LAUNCHER"
    echo "Launcher: $LAUNCHER (user data in $CONFIG_DIR)"
  else
    ln -s "$PREFIX/blender" "$LAUNCHER"
    echo "Launcher: $LAUNCHER (shares ~/.config/blender with stock Blender; see --separate-config)"
  fi
  echo "Make sure ~/.local/bin is in your PATH."

  if (( INSTALL_DESKTOP )); then
    DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
    APPS_DIR="$DATA_DIR/applications"
    ICON_DIR="$DATA_DIR/icons/hicolor/scalable/apps"
    ICON_NAME="blender"
    mkdir -p "$APPS_DIR" "$ICON_DIR"
    if [[ -f "$PREFIX/blender.svg" ]]; then
      cp "$PREFIX/blender.svg" "$ICON_DIR/goo-engine.svg"
      ICON_NAME="goo-engine"
    fi
    # No MimeType on purpose: don't take over .blend files from stock Blender.
    cat > "$APPS_DIR/goo-engine.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Goo Engine
GenericName=3D modeler
Comment=Blender fork with a toon/anime shading pipeline
Exec="$LAUNCHER" %f
Icon=$ICON_NAME
Terminal=false
Categories=Graphics;3DGraphics;
DESKTOP
    update-desktop-database "$APPS_DIR" 2>/dev/null || true
    echo "Menu entry: $APPS_DIR/goo-engine.desktop"
  fi
else
  echo "==> Done. Run: $BUILD_BIN/blender"
fi
