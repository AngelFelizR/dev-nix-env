# dev-nix-env

Template for a **private, reproducible and isolated** development environment
based on [Nix](https://nixos.org) + Docker. Copy it into a new project,
personalize the files marked `ToEdit_` and you get R, Python (and later
Julia/Rust) inside a container with pinned versions, without touching your
machine.

> This repo **is committed to GitHub as-is** (it is the template). When you
> copy it *into* a project, remember to gitignore these files if you don't want
> them to be part of that project's repo (see the final section).

## Why it is safe to work this way

1. **Total isolation.** R, Python and every tool live in a container. Your
   system's R/Python are never touched.
2. **Reproducible.** Nix pins an exact *snapshot* of versions (the "pin").
   Today and a year from now, `./build-image.sh` produces the same environment.
3. **Nothing breaks when experimenting.** Adding/removing packages is editing a
   list and rebuilding; if something goes wrong, you revert the change in git.
4. **`install.packages()` / `pip install` deliberately do not work** inside the
   container (the "slim" R ships no compiler). Everything goes through the pin,
   so the real state is always declared in files and versioned.
5. **It does not pollute the project repo.** These are private files (each
   project's `.gitignore` ignores them), just like a `.env`.

## How it works (mental model)

The **Dockerfile does not install packages**. It is a thin wrapper that receives
a tarball already compiled by Nix:

- **Nix** decides *what* gets installed and *in which version* (the `nix/`
  files).
- **`./build-image.sh`** compiles that Nix "closure" inside a container with a
  persistent volume (so R only compiles the first time) and saves the result to
  `dist/closure.tar.gz`.
- **`docker build` (the Dockerfile)** unpacks that tarball and leaves everything
  ready in `/opt/system` (tools) and `/opt/r` (R packages).
- **`entrypoint.sh`** starts an `sshd` you connect to over SSH.

## Decision log

The *why* of the structural decisions, in one place. The fine detail lives in
each file's comments (`r-slim.nix`, `system.nix`, `build-image.sh`); here only
the rationale.

### 1. A single Nix pin for the whole system
**Decision:** a single date in `nix/pkgs.nix` pins R, Python, Quarto, pandoc,
git, glibc and the compiler at once.
**Why:** a reproducible snapshot of *everything* in the system, not just the
libraries. Changing the date is one line; the git diff is the full history of
the environment.
**Discarded:** per-language lockfiles (`renv`, `pip`, `conda`) + per-tool base
images — each with its own update cycle and no control over the system beneath
the libraries.

### 2. Runtime image from pre-compiled closures
**Decision:** `./build-image.sh` compiles the Nix closures in a container with a
persistent volume, packages them into `dist/closure.tar.gz`, and the Dockerfile
only unpacks them.
**Why:** the `nixos/nix` base already brings Nix (no need to install it at
runtime), and compiling outside `docker build` means adding a package recompiles
only what is missing, not all of R.
**Discarded:** an Ubuntu image with Nix installed on top (installing Nix on each
build, larger and less reproducible images).

### 3. "Slim" R (`r-slim.nix`)
**Decision:** strip from R's closure the toolchain that is only needed to
compile, not to run (openjdk 573 MB, glib-dev → python3 144 MB, gcc-wrapper,
cairo/pango-dev, graphviz).
**Why:** ~800 MB less image. gfortran is kept on purpose (Fortran packages need
it), and the unwrapped gcc is dragged along by gfortran.
**Discarded / risk:** the mechanism is `sed` over `Makeconf`/`ldpaths`, now
hardened with literal paths from the pin and watched over by `check-r-slim.sh`.
The alternatives (re-injecting gfortran, `overrideScope`) were measured and do
not work; the detail is in `r-slim.nix`.

### 4. Non-root `dev` user (host UID)
**Decision:** SSH sessions log in as `dev` (UID 1000 = your `id -u`); `sshd` and
Nix run as root.
**Why:** the files you render keep the correct owner on your host, with no
`sudo chown` after each render. The Nix store stays root-only.
**Discarded:** running everything as root (forces the permission dance and opens
root SSH to the whole repo).

### 5. No `install.packages()` / `pip install`
**Decision:** there is no ad-hoc installation inside the container; every package
is declared in `nix/packages.nix` (or `nix/system.nix` for tools/languages) and
rebuilt. `Rprofile.site`
blocks `install.packages()`/`update.packages()` with a clear message (via
`R_PROFILE`).
**Why:** the real state always lives in a versioned file, so the environment is
rebuildable from scratch and the diff tells the whole story.
**Discarded:** ad-hoc installation — it reintroduces the drift this all avoids.

### 6. Positron Remote SSH with workarounds
**Decision:** keep the Positron workflow even though it does not support Nix
natively, via workarounds in the Dockerfile and `patch-reh.sh`.
**Why:** the `nixos/nix` base has no `/etc/os-release` nor a standard glibc; we
fake `ID=nixos` and point the FHS binaries at `/opt/positron-libs`
(glibc + libstdc++ + libgcc_s via `nix/positron-libs.nix`).
**Discarded:** using an editor that supports Nix, or a standard devcontainer —
it loses the Positron workflow you already have set up. Detail in the "Positron
(Remote SSH)" section.

## Files and what to edit

The files **with the `ToEdit_` prefix** are the ones you personalize; the rest
are generic and should not be touched.

| File | What it is | Edit |
|---|---|---|
| `nix/ToEdit_pkgs.nix` | The **pin** (versions of everything) | yes |
| `nix/ToEdit_system.nix` | Languages + tools (R, Python, Quarto…) | yes |
| `nix/ToEdit_packages.nix` | **Packages for every language** (R, Python) | yes |
| `ToEdit_Dockerfile` | Runtime wrapper | yes (little) |
| `ToEdit_docker-compose.yml` | Image/container/port/mount | yes |
| `ToEdit_build-image.sh` | Assembles closures + image | yes (names) |
| `ToEdit_setup.sh` | Starts + installs SSH key | yes |
| `ToEdit_patch-reh.sh` | Patches the Positron REH | yes (name) |
| `ToEdit_default.nix` | The repo's `nix-shell` | only if you change languages |
| `entrypoint.sh` | sshd bootstrap | no |
| `Rprofile.site` | Blocks `install.packages()`/`update.packages()` | no |
| `.dockerignore` | Build context | no |
| `nix/nix.conf` | Shared Nix config (substituters) | no |
| `nix/positron-libs.nix` | FHS libs for Positron (glibc/gcc) | no |
| `check` | Verifies pin consistency | no |
| `check-r-slim.sh` | Verifies the R strip did not regress | no |
| `nix/r-slim.nix`, `nix/slim-r-overlay.nix` | Compiler-less R (advanced) | **do not touch** |

### Step 0 — rename

After personalizing, drop the `ToEdit_` prefix:

```
ToEdit_Dockerfile         -> Dockerfile
ToEdit_docker-compose.yml -> docker-compose.yml
ToEdit_build-image.sh     -> build-image.sh
ToEdit_setup.sh           -> setup.sh
ToEdit_patch-reh.sh       -> patch-reh.sh
ToEdit_default.nix        -> default.nix
nix/ToEdit_pkgs.nix       -> nix/pkgs.nix
nix/ToEdit_system.nix     -> nix/system.nix
nix/ToEdit_packages.nix   -> nix/packages.nix
```

The scripts already reference the **final names** (`nix/pkgs.nix`,
`nix/system.nix`, `nix/packages.nix`, `entrypoint.sh`), so you only rename; you do
not touch references.

## Start a project

1. Copy this folder to your project.
2. Replace `myproject` with your project name (find-replace in the `ToEdit_*`
   files).
3. Drop the `ToEdit_` prefix (table above).
4. `./check`            # (optional) verify the pin is consistent
5. `./build-image.sh`  # compiles R the first time (~30-60 min); afterwards it's incremental
6. `./setup.sh`        # starts the stack and copies your SSH key
7. `ssh MyProject`     # the repo is mounted at /home/dev/myproject

Add once to `~/.ssh/config`:

```
Host MyProject
    HostName 127.0.0.1
    User dev
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
```

## Choose languages

### Python (comes ready)

Python 3.12 + the Jupyter engine are already in `nix/ToEdit_system.nix`. To add
the project's packages (`numpy`, `pandas`, …), declare them in
`nix/ToEdit_packages.nix`:

```nix
pythonPackages = ps: with ps; [
  numpy      # <- add
  pandas     # <- add
];
```

(`ps:` is the package set of the interpreter `system.nix` selects — keep that
form: it makes it impossible to list packages from a different Python version,
a mismatch that only shows up later as `ModuleNotFoundError`.)

Then: `./build-image.sh`.

### R (comes ready)

R packages go in `nix/ToEdit_packages.nix`:

```nix
rPackages = with pkgs.rPackages; [
  rmarkdown
  knitr
  dplyr        # <- add
  tidymodels   # <- add
];
```

### Python only (drop R)

1. Delete `nix/r-slim.nix` and `nix/slim-r-overlay.nix`.
2. In `nix/ToEdit_pkgs.nix`, point the pin at the official nixpkgs release and
   drop the overlay:

   ```nix
   import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/refs/tags/26.05.tar.gz") { }
   ```

3. In `nix/ToEdit_system.nix`, point `nixpkgsSrc` at the same URL and remove the
   `R` line; leave `rPackages` empty in `nix/ToEdit_packages.nix`, and in
   `ToEdit_default.nix` and `ToEdit_build-image.sh`, remove the `rEnv` lines.
   Run `./check` to confirm the pin matches.

### R only (drop Python)

In `nix/ToEdit_system.nix`, remove the `python` line and its `inherit`; the
`pythonPackages` section of `nix/ToEdit_packages.nix` is then simply unused.
That's it.

### Julia / Rust / other languages

In `nix/ToEdit_system.nix`, add them to the final `inherit (pkgs) ...`:

```nix
inherit R python quarto git nixpkgsSource julia rustup;
```

Nix already packages almost every language. Their libraries/packages belong in
`nix/ToEdit_packages.nix` as a new section, like the R and Python ones.

## Change versions (pin)

The pin is the `fetchTarball` in `nix/ToEdit_pkgs.nix`. Its date and `sha256`
come from `rix`'s snapshot table
([`available_df.csv`](https://raw.githubusercontent.com/ropensci/rix/refs/heads/main/inst/extdata/available_df.csv)):
each date is an `rstats-on-nix` snapshot of R + CRAN/Bioconductor. When bumping,
update the **date and the `sha256`** in `nix/ToEdit_pkgs.nix` *and* the matching
`nixpkgsSrc` in `nix/ToEdit_system.nix`. Before rebuilding, run `./check` to make
sure both the URL and the `sha256` match. Rebuild with `./build-image.sh`.

> **The CSV can lag reality.** If a build dies fetching the pin with
> `NAR hash mismatch`, that row's hash is stale: the archive GitHub serves for
> the ref changed after rix recorded it (seen with `2026-10-13`; the current
> `2026-09-28` hash was verified against GitHub). Recompute it with
> `nix-prefetch-url --unpack <URL>` and put the result in both files. `./check`
> only compares the two files with each other — it cannot catch a stale
> upstream hash.

> The R pin is not a plain date: it is `rstats-on-nix`'s **weekly dated branch**
> (CRAN moves weekly, so the fork cuts a matching snapshot with a binary cachix
> cache). The Python-only path instead uses the official nixpkgs release tag.

### What is actually cached

- **R + the popular packages** (dplyr, ggplot2, tidyverse, sf, terra, …) and
  their dependencies are pre-built by `rstats-on-nix` CI and served from
  `rstats-on-nix.cachix.org` (Linux amd64 + macOS arm64). A less-common R
  package compiles locally, regardless of the pin.
- **Python** always downloads from `cache.nixos.org`: the fork is a thin overlay
  on a real nixpkgs commit, so Python/numpy/pandas/Jupyter are byte-identical to
  upstream and come pre-built.

When bumping the pin:
- **`nix/positron-libs.nix`** and **`nix/r-slim.nix`** resolve their store paths
  from the pin itself (no longer using version globs), so you do not need to
  touch them; Nix resolves them on its own.
- After rebuilding, run **`./check-r-slim.sh`** to confirm the R strip did not
  regress (that openjdk/gcc-wrapper/glib-dev/etc. did not come back into the
  closure). For the full check that gfortran still compiles Fortran, follow the
  command in the comment inside `check-r-slim.sh`.

## Try a package without rebuilding the image

Add it to `nix/ToEdit_packages.nix` (or `nix/ToEdit_system.nix` for a tool or
language) and, inside the container, run:

```sh
# nix needs to write to /nix/store (root-only), so it runs as root:
docker compose exec -u root myproject-dev nix-shell
```

Inside that shell you already have the new package (the image is untouched):

```sh
R -e 'library(pkg)'           # or: python -c 'import numpy'
```

When you want it fixed, `./build-image.sh`.

## The `dev` user (non-root)

SSH sessions log in as `dev` (UID 1000 = your `id -u`), so the files you render
keep the correct owner on your host (no `sudo chown` after each render). `sshd`
and Nix operations run as root (the store is root-only). If your UID is not
1000, change it in `ToEdit_Dockerfile`, `entrypoint.sh` and
`docker-compose.yml`.

For root operations: `docker compose exec -u root myproject-dev sh`.

## Positron (Remote SSH)

Positron Remote SSH support is included (the container carries the Nix
workarounds). The server binary is **not** in the image: it lives in the
`myproject-positron-server` volume. After every Positron update that installs a
new REH, run `./patch-reh.sh`.

## Housekeeping

```sh
sudo rm -rf dist && docker volume rm myproject-nix-store
```

(Rebuilding after this recompiles R once.)

## If something ended up owned by root

`./build-image.sh` returns `dist/` to your user automatically, and sessions run
as `dev`, so normally this should not happen. If for some reason there are
root-owned files in the repo:

```sh
sudo chown -R $(id -u):$(id -g) .
```

## When copying into a project

These files are private: add the same entries to your project's `.gitignore` if
you do not want to commit them (e.g. `/Dockerfile`, `/nix/`, `/setup.sh`,
`/build-image.sh`, `/docker-compose.yml`, `/default.nix`, `/entrypoint.sh`,
`/patch-reh.sh`, `/check`, `/check-r-slim.sh`, `/Rprofile.site`, `/dist/`).
