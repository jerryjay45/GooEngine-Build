# GooEngine-Build

A build script for [Goo Engine](https://github.com/dillongoostudios/goo-engine),
the toon/anime-focused Blender fork, on common Linux distributions.

It clones the upstream repo (default branch `v4.4-release`), installs build
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
| `-b, --branch NAME` | Branch to build (default `v4.4-release`) |
| `-r, --repo URL` | Source repo (default upstream Goo Engine) |
| `-w, --workdir DIR` | Clone/build location (default `./work`) |
| `-j, --jobs N` | Parallel jobs; lower it if you run out of RAM |
| `-p, --prefix DIR` | Copy the build to `DIR` and link `~/.local/bin/goo-engine` |
| `--skip-deps` | Skip installing system packages |

Without `--prefix`, the binary is at `work/build_linux/bin/blender`.

## Troubleshooting

- **Out of memory / killed:** reduce `-j`.
- **Out of disk space:** use `-w` to build on a larger drive.
- **`make update` fails:** install `subversion` and `git-lfs`, then re-run.
- **Dependency installer fails on your distro:** install Blender's build dependencies manually and use `--skip-deps`.
