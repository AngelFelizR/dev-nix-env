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
- **`./build-image.sh`** runs `./check`, compiles that Nix "closure" inside a
  container with a persistent volume (so R only compiles the first time —
  the volume is **shared by all your projects**) and saves the result to
  `dist/closure.tar.gz`.
- **`docker build` (the Dockerfile)** unpacks that tarball and leaves everything
  ready in `/opt/system` (tools) and `/opt/r` (R packages).
- **`entrypoint.sh`** starts an `sshd` you connect to over SSH.

## Decision log

The *why* of the structural decisions, in one place. The fine detail lives in
each file's comments (`r-slim.nix`, `system.nix`, `build-image.sh`); here only
the rationale.

### 1. A single Nix pin for the whole system
**Decision:** a single date in `nix/pin.nix` pins R, Python, Quarto, pandoc,
git, glibc and the compiler at once — and that file is the *only* place the
pin exists: `nix/pkgs.nix` and `nix/system.nix` import it, and `./check`
fails if a copy reappears anywhere else (it runs at the start of every
`./build-image.sh` and in CI on every push).
**Why:** a reproducible snapshot of *everything* in the system, not just the
libraries. Changing the date is one line in one file; the git diff is the
full history of the environment.
**Discarded:** per-language lockfiles (`renv`, `pip`, `conda`) + per-tool base
images — each with its own update cycle and no control over the system beneath
the libraries. Also discarded: the URL + hash living in two files (the classic
"bumped one, forgot the other" failure) — `./check` caught it, `pin.nix`
removes the class of bug.

### 2. Runtime image from pre-compiled closures
**Decision:** `./build-image.sh` compiles the Nix closures in a container with a
persistent volume, packages them into `dist/closure.tar.gz`, and the Dockerfile
only unpacks them. That volume (`dev-nix-store`) is **one shared by every
project** on the machine.
**Why:** the `nixos/nix` base already brings Nix (no need to install it at
runtime), and compiling outside `docker build` means adding a package recompiles
only what is missing, not all of R. Sharing the store exploits the fact that
it is content-addressed: two projects on the same pin reuse the same built
paths, so R compiles once across projects instead of once per project (only
the build cache is shared — each project keeps its own image).
**Discarded:** an Ubuntu image with Nix installed on top (installing Nix on each
build, larger and less reproducible images). Also discarded: one store volume
per project — it duplicated ~1–2 GB of identical paths per project.

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
`R_PROFILE`). Packages the pin does not carry (GitHub-only) are declared from a
source snapshot in the same file, via the `rFromGitHub` / `pythonFromGitHub`
helpers — still declarative, still versioned.
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

### 7. `gitMinimal`, not `git.override`
**Decision:** use the pre-built `pkgs.gitMinimal` instead of a hand-rolled
`pkgs.git.override { perlSupport = false; pythonSupport = false; withManual = false; }`.
**Why:** any custom `override` changes the derivation hash, so the result is
*not* on `cache.nixos.org` and git compiles from source — running its own test
suite (the `t53xx-*.sh … ok` lines in the build) and dragging the compiler in.
`gitMinimal` is a first-class package with the same flags (no perl, python,
man pages, pcre2), so it is pre-built and downloads.
**Discarded:** plain `git` (carries perl + python + man pages, ~225 MB), and the
hand-rolled `git.override` (no cache → source build + git's test suite).

### 8. Patched quarto for the bundled pandoc
**Decision:** quarto 1.9.37 (in the pin) emits pandoc 3.8+'s `syntax-highlighting`
option, but nixpkgs bundles it against pandoc 3.7.0.2, which does not know it —
`quarto render` of revealjs dies with "Unknown option syntax-highlighting"
(nixpkgs#519484). `nix/system.nix` patches quarto via `overrideAttrs` to emit the
3.7 name (`highlight-style`) instead, and adds `pyyaml` to the jupyter engine's
Python (`share/jupyter/jupyter.py` does `import yaml`).
**Why:** without it the pin cannot render slides (or anything with highlighting)
at all, so neither dev nor prod could build the site.
**Residual:** quarto's `jog.lua` filter still logs a *non-fatal*
"Don't know how to traverse TableBody" for tables in revealjs (another 3.8/3.7
AST change). Tables render in place (not "jogged"/floated) with their content
intact.
**Discarded:** upgrading pandoc to 3.8+ (a full Haskell rebuild — nixpkgs#519484
shows it is not straightforward), or downgrading quarto to match pandoc 3.7.

## Files and what to edit

The files **with the `ToEdit_` prefix** are the ones you personalize; the rest
are generic and should not be touched.

| File | What it is | Edit |
|---|---|---|
| `nix/ToEdit_pin.nix` | The **pin** (date + sha256; single source) | yes |
| `nix/pkgs.nix` | The pkgs set (imports the pin + overlays) | no (generic; overlay only for Python-only) |
| `nix/ToEdit_system.nix` | Languages + tools (R, Python, Quarto…) | only to change languages |
| `nix/ToEdit_packages.nix` | **Packages for every language** (R, Python; from the pin *or* GitHub) | yes |
| `ToEdit_Dockerfile` | Runtime wrapper | yes (little) |
| `ToEdit_docker-compose.yml` | Image/container/port/mount | yes |
| `ToEdit_build-image.sh` | Assembles closures + image | yes (name) |
| `ToEdit_setup.sh` | Starts + installs SSH key | yes |
| `ToEdit_patch-reh.sh` | Patches the Positron REH | yes (name) |
| `ToEdit_prod.Dockerfile` | Production image (render + nginx serve) | yes (name) |
| `ToEdit_prod.sh` | Builds the production image | yes (name) |
| `ToEdit_prod-compose.yml` | Production compose (serves the site) | yes (name) |
| `default.nix` | The repo's `nix-shell` | no (generic; rEnv only if no R) |
| `entrypoint.sh` | sshd bootstrap | no |
| `Rprofile.site` | Blocks `install.packages()`/`update.packages()` | no |
| `.dockerignore` | Build context | no |
| `.dockerignore.prod` | Production build context | no (generic) |
| `nix/nix.conf` | Shared Nix config (substituters) | no |
| `nix/positron-libs.nix` | FHS libs for Positron (glibc/gcc) | no |
| `check` | Verifies the pin is single-sourced and consistent | no |
| `.github/workflows/check.yml` | CI: runs `./check` + parses every `.nix` on push/PR | no |
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
ToEdit_prod.Dockerfile     -> prod.Dockerfile
ToEdit_prod.sh             -> prod.sh
ToEdit_prod-compose.yml    -> prod-compose.yml
nix/ToEdit_pin.nix        -> nix/pin.nix
nix/ToEdit_system.nix     -> nix/system.nix
nix/ToEdit_packages.nix   -> nix/packages.nix
```

The scripts already reference the **final names** (`nix/pin.nix`,
`nix/pkgs.nix`, `nix/system.nix`, `nix/packages.nix`, `entrypoint.sh`), so you
only rename; you do not touch references. (`nix/pkgs.nix` and `default.nix`
already carry their final names — they are generic.) (`./check` works in both
states — before and after the rename — so you can run it either way.)

## Start a project

1. Copy this folder to your project.
2. Replace `myproject` with your project name (find-replace in the `ToEdit_*`
   files).
3. Drop the `ToEdit_` prefix (table above).
4. `./check`            # verify the pin is single-sourced (also runs automatically inside ./build-image.sh and in CI)
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

### Packages from GitHub (not in the pin)

If the pin does not carry a package — or you need a specific GitHub revision
of one — declare it in `nix/ToEdit_packages.nix` with the helpers already
defined there. Same rule as every other package: state in a versioned file,
rebuild, nothing installed inside the container.

R (helper `rFromGitHub`; compiled inside the Nix build, so C/C++/Fortran
source packages work):

```nix
rPackages = with pkgs.rPackages; [
  rmarkdown
  knitr
  (rFromGitHub {
    owner = "OWNER";
    repo = "REPO";
    rev = "v1.2.3";      # <- prefer a TAG: a branch is not reproducible
    sha256 = "...";      # <- nix-prefetch-github OWNER REPO
    deps = [ dplyr ];    # <- every dependency NOT already in this list
  })
];
```

Python (helper `pythonFromGitHub`; `pyproject = true` + setuptools/wheel by
default — a bare-`setup.py` repo can pass `pyproject = false`):

```nix
pythonPackages = ps: with ps; [
  (pythonFromGitHub ps {
    owner = "OWNER";
    repo = "REPO";
    rev = "v1.2.3";
    sha256 = "...";      # <- nix-prefetch-github OWNER REPO
    deps = [ numpy ];    # <- runtime deps, same `ps` set
  })
];
```

Notes:

- **Prefer the pin's name when the package exists there** (cached binaries);
  GitHub builds compile locally on the first build, then stay incremental.
- `sha256` comes from `nix-prefetch-github <owner> <repo>` (or
  `nix-prefetch-url --unpack https://github.com/<owner>/<repo>/archive/<rev>.tar.gz`).
- `pname` (R) defaults to the repo name — pass `pname = "pkgName"` when the
  package name that `library()` expects differs from the repo name.
- A missing `deps` entry fails the build with a clear error — add it there,
  don't install it by hand.

### Python only (drop R)

1. Delete `nix/r-slim.nix` and `nix/slim-r-overlay.nix`.
2. In `nix/ToEdit_pin.nix`, point the pin at the official nixpkgs release
   (URL *and* sha256 — `nix-prefetch-url --unpack <URL>` gives you the hash;
   `./check` requires both):

   ```nix
   url = "https://github.com/NixOS/nixpkgs/archive/refs/tags/26.05.tar.gz";
   sha256 = "...";
   ```

3. In `nix/pkgs.nix`, drop the overlay:

   ```nix
   let
     pin = import ./pin.nix;
   in
     import (fetchTarball { inherit (pin) url sha256; }) { }
   ```

4. In `nix/ToEdit_system.nix`, remove the `R` line and its `inherit`; leave
   `rPackages` empty in `nix/ToEdit_packages.nix`, and in
   `default.nix` and `ToEdit_build-image.sh`, remove the `rEnv` lines.
   Run `./check` to confirm the pin is consistent.

### R only (drop Python)

In `nix/ToEdit_system.nix`, remove the `python` line and its `inherit`; the
`pythonPackages` section of `nix/ToEdit_packages.nix` is then simply unused.
That's it.

### Julia / Rust / other languages

In `nix/ToEdit_system.nix`, add them to the final `inherit (pkgs) ...`:

```nix
inherit R python quarto git julia rustup;
```

Nix already packages almost every language. Their libraries/packages belong in
`nix/ToEdit_packages.nix` as a new section, like the R and Python ones.

## Change versions (pin)

The pin lives in **`nix/ToEdit_pin.nix`** (its `url` + `sha256`), and that
file is the single source: `nix/pkgs.nix` and `nix/ToEdit_system.nix`
both import it, so no other file carries a copy. Its date and `sha256` come
from rix's snapshot table
([`available_df.csv`](https://raw.githubusercontent.com/ropensci/rix/refs/heads/main/inst/extdata/available_df.csv)):
each date is an `rstats-on-nix` snapshot of R + CRAN/Bioconductor. When
bumping, update the **date and the `sha256`** in `nix/ToEdit_pin.nix` — and
only there. `./check` enforces the single source (it fails if a duplicated
URL reappears in any `nix/*.nix`); it runs at the start of every
`./build-image.sh` and on every push in CI. Rebuild with `./build-image.sh`.

> **The CSV can lag reality.** If a build dies fetching the pin with
> `NAR hash mismatch`, that row's hash is stale: the archive GitHub serves for
> the ref changed after rix recorded it (seen with `2026-10-13`; the current
> `2026-09-28` hash was verified against GitHub). Recompute it with
> `nix-prefetch-url --unpack <URL>` and put the result in `nix/ToEdit_pin.nix`.
> `./check` verifies the pin is single-sourced — it cannot catch a stale
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

> The first `nix-shell` in a fresh container downloads the pin's nixpkgs
> tarball (~80 MB) into the store; after that it is instant. The unpacked
> source is deliberately **not** shipped in the image to keep it ~0.5 GB
> smaller.

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

Positron and its language servers assume a normal Linux box; a Nix container is
not one. Every seam below fails **silently** — the build succeeds and the error
only appears when a kernel starts. If R packages are "missing" or a kernel will
not start, check these in order:

1. **Session environment ownership.** sshd's `PermitUserEnvironment` reads
   `~/.ssh/environment` only if it is owned by the login user (`dev`). The
   Dockerfile writes it and `chown`s it, and `entrypoint.sh` re-asserts the
   owner. If it ends up root-owned, sshd silently ignores it: `R_LIBS_SITE` and
   the `VSCODE_SERVER_*` vars never reach the session — R says "no package
   called tidymodels" and the REH's glibc check fails.
2. **Positron volume ownership.** The `myproject-positron-server` volume may be
   seeded as root, but the client logs in as `dev` and must write
   `.log`/`.token`/`.pid` plus `data/` and `extensions/`. `entrypoint.sh` does a
   recursive `chown`. A root-owned volume surfaces as an empty
   `connectionToken` → "Illegal argument: connectionToken".
3. **`LD_LIBRARY_PATH` for the Python language server.** Its bundled
   `ipykernel`/`zmq` is a generic manylinux wheel that needs `libstdc++.so.6`
   at load time, but the container has no `/lib` or `/usr/lib`. The image sets
   `LD_LIBRARY_PATH=/opt/positron-libs` (the flat FHS-ish dir from
   `nix/positron-libs.nix`) so those libs resolve.
4. **`ps`.** The REH and its install script use `ps`/`kill` for process
   management; `procps` is in `system.nix` for it (the base image has no `ps`).

## Production (static site)

The same closure that powers the dev image renders the project into a static
site, shipped as a tiny nginx image. This is the "final packaging": the dev
environment is the interactive toolchain, prod is a reproducible build of its
output.

```sh
./prod.sh                                  # build myproject:prod (needs the dev image)
docker run --rm -p 8080:80 myproject:prod  # serve it
# or: docker compose -f prod-compose.yml up -d
```

How it works (`prod.Dockerfile`, two stages):

1. **`render`** — `FROM myproject-dev:latest`, copies the repo and runs
   `quarto render`. All the weight (R, Quarto, pandoc, packages) stays in this
   stage and is discarded.
2. **`serve`** — `nginx:alpine` with only `_site/` copied in: a few tens of MB.

The prod image is *not* a slimmed dev image — it is the rendered artifact of the
same pin. To reproduce it, re-render with the same `nix/pin.nix` and source;
the whole path stays deterministic. `prod.sh` swaps `.dockerignore.prod` in so
the build context is the source (not `dist/`).

## Housekeeping

```sh
sudo rm -rf dist && docker volume rm dev-nix-store
```

> **`dev-nix-store` is shared by all your projects** (that is the point: the
> build cache is reused across them). Removing it makes *every* project
> recompile R once on its next `./build-image.sh`. To keep a project-private
> store instead, build it with `VOLUME=<project>-nix-store ./build-image.sh`.

## If something ended up owned by root

`./build-image.sh` returns `dist/` to your user automatically, and sessions run
as `dev`, so normally this should not happen. If for some reason there are
root-owned files in the repo:

```sh
sudo chown -R $(id -u):$(id -g) .
```

The usual culprit is running **`quarto render` as root** (for example inside
`docker compose exec -u root myproject-dev nix-shell`, or a `sudo quarto
render` on the host). Quarto writes `_site/`, `_freeze/`, `.quarto/` and the
generated `NN.qmd` chapter files with the invoking user's owner — root there
makes every later render as `dev` fail with `PermissionDenied` (`readdir`/`remove`
on those paths). Render as `dev` (via `ssh`, or plain `docker compose exec`), or
re-own those directories. They are all regenerable, so `rm -rf _site _freeze
.quarto NN.qmd` (then re-render as `dev`) is also a valid fix.

## When copying into a project

These files are private: add the same entries to your project's `.gitignore` if
you do not want to commit them (e.g. `/Dockerfile`, `/nix/`, `/setup.sh`,
`/build-image.sh`, `/docker-compose.yml`, `/default.nix`, `/entrypoint.sh`,
`/patch-reh.sh`, `/prod.Dockerfile`, `/prod.sh`, `/prod-compose.yml`,
`/.dockerignore.prod`, `/check`, `/check-r-slim.sh`, `/Rprofile.site`, `/dist/`,
`/.github/workflows/check.yml`).
