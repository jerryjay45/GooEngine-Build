#!/usr/bin/env bash
# build-goo-engine.sh - clone and build Goo Engine on common Linux distros.
#
# Uses Blender's own tooling so the build matches upstream:
#   1. install_linux_packages.py installs build dependencies for your distro
#   2. `make update` fetches submodules and the precompiled libraries
#      (bundled Python, FFmpeg, OpenEXR, ...), avoiding system-library mismatches
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

usage() {
  cat <<USAGE
Usage: $0 [options]
  -b, --branch NAME   branch to build (default: $BRANCH)
  -r, --repo URL      source repository (default: $REPO_URL)
  -w, --workdir DIR   where to clone and build (default: $WORKDIR)
  -j, --jobs N        parallel jobs (default: $(nproc); lower it if you run out of RAM)
  -p, --prefix DIR    copy the finished build to DIR and link ~/.local/bin/goo-engine
      --skip-deps     don't install system packages
  -h, --help          show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--branch)  BRANCH="$2"; shift 2 ;;
    -r|--repo)    REPO_URL="$2"; shift 2 ;;
    -w|--workdir) WORKDIR="$2"; shift 2 ;;
    -j|--jobs)    JOBS="$2"; shift 2 ;;
    -p|--prefix)  PREFIX="$2"; shift 2 ;;
    --skip-deps)  SKIP_DEPS=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

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
  command -v svn >/dev/null || echo "Warning: 'svn' not found; 'make update' may need subversion."
fi

# --- submodules and precompiled libs --------------------------------------
echo "==> Fetching submodules and precompiled libraries..."
make update

# --- build -----------------------------------------------------------------
echo "==> Building with $JOBS jobs..."
export MAKEFLAGS="-j${JOBS}"
make -j"$JOBS"

[[ -x "$BUILD_BIN/blender" ]] || { echo "Build finished but $BUILD_BIN/blender is missing." >&2; exit 1; }

# --- optional install ------------------------------------------------------
if [[ -n "$PREFIX" ]]; then
  echo "==> Installing to $PREFIX..."
  mkdir -p "$PREFIX" "$HOME/.local/bin"
  cp -a "$BUILD_BIN/." "$PREFIX/"
  ln -sf "$PREFIX/blender" "$HOME/.local/bin/goo-engine"
  echo "Launcher: ~/.local/bin/goo-engine (make sure ~/.local/bin is in your PATH)"
else
  echo "==> Done. Run: $BUILD_BIN/blender"
fi
