#!/bin/bash
# =============================================================================
#  TO EDIT — customize for each project. When done, rename:
#           ToEdit_patch-reh.sh -> patch-reh.sh
#  ---------------------------------------------------------------------------
#  WHAT TO CHANGE:
#    1. The CONTAINER default below: myproject-dev -> <your-container>.
# =============================================================================
# Patch the bundled FHS binaries of the Positron REH (kcserver, ark, rg,
# deno, ...) so they run on the Nix image: interpreter + rpath -> the
# /opt/positron-libs symlink farm. The positron-server launcher only
# patchelfs its own node; the supervisor (kallichore/kcserver) and the R
# kernel (ark) are executed directly and need this. Run it after every
# Positron update that installs a new REH version into the volume.
set -euo pipefail

CONTAINER="${CONTAINER:-myproject-dev}"

docker exec "$CONTAINER" sh -c '
set -e
cd /home/dev/.positron-server/bin/*
echo "patching REH in $(pwd)"
find . -type f -perm -u+x | while read -r f; do
    # ./node belongs to the running server and is re-patched by the
    # positron-server launcher on every start; never touch it live.
    [ "$f" = "./node" ] && continue
    head -c4 "$f" 2>/dev/null | od -An -tx1 | tr -d " \n" | grep -q "7f454c46" || continue
    /opt/system/bin/patchelf --print-interpreter "$f" >/dev/null 2>&1 || continue
    rpath=$(/opt/system/bin/patchelf --print-rpath "$f" 2>/dev/null || true)
    case ":$rpath:" in
        *:/opt/positron-libs:*) ;;
        *) /opt/system/bin/patchelf --set-rpath "${rpath:+$rpath:}/opt/positron-libs" "$f" ;;
    esac
    /opt/system/bin/patchelf \
        --set-interpreter /opt/positron-libs/ld-linux-x86-64.so.2 "$f"
    echo "patched $f"
done
'
