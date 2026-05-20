#!/bin/bash
# run_lavam.sh — LAVA-M bug-detection experiment
# Downloads LAVA-M binaries and runs AFL++ for 24 hours on each program.
# Reports how many of the injected bugs (ground-truth list) are triggered.
#
# LAVA-M programs: who, base64, md5sum, uniq (total 143 injected bugs)
# Reference: Dolan-Gavitt et al., IEEE S&P 2016
set -e
cd "$(dirname "$0")"

TIMEOUT=${TIMEOUT:-86400}   # 24 hours (set lower for quick test)
AFL_PP=${AFLPP:-afl-fuzz}
OUTDIR=lava_results

mkdir -p $OUTDIR

LAVAM_PROGRAMS=(who base64 md5sum uniq)
# Ground-truth injected bug counts per program
declare -A INJECTED=([who]=2126 [base64]=44 [md5sum]=57 [uniq]=28)

# Download LAVA-M if not present
if [ ! -d lava-m ]; then
    echo "Downloading LAVA-M binaries..."
    wget -q https://github.com/llvm-mirror/lava/archive/master.tar.gz \
        -O lava_master.tar.gz 2>/dev/null || {
        echo "Note: LAVA-M not available for download from this URL."
        echo "Please manually place LAVA-M binaries in ./lava-m/"
        echo "See: https://github.com/BugzillaHub/lava-m"
        exit 1
    }
fi

echo "=== LAVA-M Bug Detection Experiment ==="
echo "AFL timeout per program: ${TIMEOUT}s"
echo ""

TOTAL_FOUND=0
TOTAL_INJECTED=0

for prog in "${LAVAM_PROGRAMS[@]}"; do
    BINARY=./lava-m/$prog/bin/${prog}-lava
    if [ ! -x "$BINARY" ]; then
        echo "[$prog] binary not found at $BINARY — skipping"
        continue
    fi

    SEEDS=./lava-m/$prog/seeds
    mkdir -p $OUTDIR/$prog

    echo "[$prog] Running AFL++ for ${TIMEOUT}s..."
    timeout $TIMEOUT $AFL_PP \
        -i $SEEDS \
        -o $OUTDIR/$prog \
        -V $TIMEOUT \
        -- $BINARY @@ 2>/dev/null || true

    # Count triggered bugs from crash inputs
    FOUND=0
    if [ -d $OUTDIR/$prog/default/crashes ]; then
        for crash in $OUTDIR/$prog/default/crashes/id:*; do
            [ -f "$crash" ] || continue
            # LAVA-M bug IDs are printed to stderr on trigger
            BUGIDS=$($BINARY "$crash" 2>&1 | grep -oP 'Successfully triggered bug \K[0-9]+' || true)
            for bid in $BUGIDS; do
                FOUND=$((FOUND + 1))
            done
        done
    fi

    echo "[$prog] Found ${FOUND} / ${INJECTED[$prog]} injected bugs"
    TOTAL_FOUND=$((TOTAL_FOUND + FOUND))
    TOTAL_INJECTED=$((TOTAL_INJECTED + ${INJECTED[$prog]}))
done

echo ""
echo "=== LAVA-M Summary ==="
echo "Total bugs found: ${TOTAL_FOUND} / ${TOTAL_INJECTED}"
echo "Detection rate: $(python3 -c "print(f'{100*$TOTAL_FOUND/$TOTAL_INJECTED:.1f}%')" 2>/dev/null || echo 'N/A')"
