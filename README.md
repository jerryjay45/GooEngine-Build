# GooEngine-Build

A build script for [Goo Engine](https://github.com/dillongoostudios/goo-engine),
the toon/anime-focused Blender fork, on common Linux distributions.

It clones the upstream repo (default branch `goo-engine-v4.4-release`), installs build
dependencies using Blender's own installer, fetches the precompiled libraries,
and builds.

> **Status:** untested draft. Issues and fixes welcome.

## Requirements

- x86_64 Linux (Debian/Ubuntu, Fedora, Arch and openSUSE are handled by Blender's dependency installer)
- `git`, `python3`, and sudo access for installing packages
- About 40 GB free disk space and plenty of RAM (roughly 2 GB per build job)

## Usage

```bash
git clone https://github.com/jerryjay45/GooEngine-Build.git
cd GooEngine-Build
./build-goo-engine.sh -j6 -p ~/apps/goo-engine
```

The first run takes a long time. Re-running updates the checkout and rebuilds incrementally.

| Option | Meaning |
| --- | --- |
| `-b, --branch NAME` | Branch to build (default `goo-engine-v4.4-release`) |
| `-r, --repo URL` | Source repo (default upstream Goo Engine) |
| `-w, --workdir DIR` | Clone/build location (default `./work`) |
| `-j, --jobs N` | Parallel jobs; lower it if you run out of RAM |
| `-p, --prefix DIR` | Copy the build to `DIR` and link `~/.local/bin/goo-engine` |
| `--skip-deps` | Skip installing system packages |
| `--cmake-arg ARG` | Extra CMake argument, repeatable (e.g. `--cmake-arg -DWITH_CYCLES=OFF`) |
| `--with-haru` | Keep libharu (Grease Pencil PDF export); see Troubleshooting |

`-j 6`, `-j6` and `--jobs=6` all work.

Without `--prefix`, the binary is at `work/build_linux/bin/blender`.

## Notes

libharu (Grease Pencil PDF export) is disabled by default. Its static library needs
symbols that a system `libtiff.so` doesn't export, and CMake can pick the system TIFF
over the bundled one (seen on Arch/CachyOS: `undefined reference to TIFFFaxWhiteCodes`).
Toon shading and everything else are unaffected. Use `--with-haru` to try enabling it.

## Troubleshooting

- **Out of memory / killed:** reduce `-j`.
- **Out of disk space:** use `-w` to build on a larger drive.
- **Library download fails:** make sure `git-lfs` is installed (the libraries come from `projects.blender.org` via Git LFS and are several GB), then re-run.
- **`PYTHON_VERSION=3.11 not found`:** the precompiled libraries weren't fetched (upstream makes them opt-in on Linux). The script enables them; if you hit this from an older run, delete `work/build_linux` and re-run.
- **Dependency installer fails on your distro:** install Blender's build dependencies manually and use `--skip-deps`.
