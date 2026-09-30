#!/bin/bash
#############################################################################
#  deploy_and_look.sh - flash the MiSTer and read the screen back           #
#                                                                           #
#  WHY (31-AUG-2026)                                                        #
#  ----------------                                                         #
#  Bring-up on this board was "build for 15 minutes, flash it, then ask      #
#  someone what is on the monitor". That is a terrible loop: it needs a      #
#  person in front of the screen for every attempt, and what comes back is   #
#  a description rather than the pixels.                                     #
#                                                                           #
#  MiSTer's main binary accepts a "screenshot" command on /dev/MiSTer_cmd    #
#  and writes a PNG under /media/fat/screenshots/<CORE>/. So the whole loop  #
#  can run over ssh: copy the bitstream, load the core, wait for it to boot, #
#  screenshot, pull the PNG back. Nobody has to look at anything.            #
#                                                                           #
#  USAGE                                                                    #
#    ./tools/deploy_and_look.sh            # deploy, load, screenshot (ssh key)#
#    MISTER_PASS=... ./tools/deploy_and_look.sh   # fallback if no key set up  #
#    ./tools/deploy_and_look.sh --look     # screenshot only, no reflash     #
#                                                                           #
#  Override the host with MISTER_HOST, the settle time with MISTER_SETTLE    #
#  (seconds to wait after loading the core before the screenshot - the CPU   #
#  needs time to get somewhere before its screen is worth reading).          #
#############################################################################
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOST="${MISTER_HOST:-MisterPi.HackerCorp.no}"
USER_AT="root@${HOST}"
SETTLE="${MISTER_SETTLE:-12}"
# The core and the screenshots live in the build folder,
# $ND120_BUILD_DIR/mister (local.mk at the repository root, written by
# configure.py; the environment wins) - `make build` copies the core there.
BUILD_MISTER="$(python3 "${HERE}/../../../../configure.py" --get ND120_BUILD_DIR)/mister" || {
    echo "nd-120: ND120_BUILD_DIR is not set - run python3 configure.py from the repository root"; exit 1; }
RBF="${BUILD_MISTER}/nd120.rbf"
CORE_PATH="/media/fat/_Computer/ND120.rbf"
OUTDIR="${MISTER_SHOTDIR:-${BUILD_MISTER}/shots}"

# Auth: SSH KEY by default (the board has this host's public key). MISTER_PASS
# is only the fallback for a board without the key installed - it is a
# password so it is NEVER stored in the repo; pass it on the command line if
# you must. With a key set up, no password is needed or wanted.
if [ -n "${MISTER_PASS:-}" ]; then
    SSH="sshpass -p ${MISTER_PASS} ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR"
    SCP="sshpass -p ${MISTER_PASS} scp -o StrictHostKeyChecking=no -o LogLevel=ERROR"
else
    SSH="ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR -o BatchMode=yes"
    SCP="scp -o StrictHostKeyChecking=no -o LogLevel=ERROR -o BatchMode=yes"
fi

LOOK_ONLY=0
[ "${1:-}" = "--look" ] && LOOK_ONLY=1

if [ "$LOOK_ONLY" -eq 0 ]; then
    [ -f "$RBF" ] || { echo "No bitstream at $RBF - run 'make build' first." >&2; exit 1; }
    echo "==> deploying $(basename "$RBF") ($(stat -c%s "$RBF") bytes)"
    $SCP "$RBF" "${USER_AT}:${CORE_PATH}"
    echo "==> loading core"
    $SSH "$USER_AT" "echo \"load_core ${CORE_PATH}\" > /dev/MiSTer_cmd"
    echo "==> settling ${SETTLE}s"
    sleep "$SETTLE"
fi

# Clear old shots first, so "the newest PNG" is unambiguous rather than a
# guess based on timestamps that may not even be set on this board.
echo "==> screenshot"
SHOT=$($SSH "$USER_AT" '
rm -f /media/fat/screenshots/*/*.png 2>/dev/null
echo "screenshot" > /dev/MiSTer_cmd
sleep 3
find /media/fat/screenshots -name "*.png" | head -1
')

if [ -z "$SHOT" ]; then
    echo "The board produced no screenshot. Is a core actually loaded?" >&2
    exit 1
fi

mkdir -p "$OUTDIR"
LOCAL="${OUTDIR}/$(basename "$SHOT")"
$SCP "${USER_AT}:${SHOT}" "$LOCAL"
echo "==> $LOCAL"
