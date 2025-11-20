#!/bin/bash
# ================================================================
# Universal VHDL to EDIF Synthesis Script for ForgeFPGA
# Uses GHDL plugin in Yosys to synthesize VHDL to netlist
# ================================================================

set -e  # Exit on error

# Configuration
YOSYS_PATH="/opt/oss-cad-suite/bin/yosys"
VHDL_DIR="./vhdl"
OUTPUT_DIR="./generated"

# Parse command line arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 <vhdl_file> [top_module]"
    echo ""
    echo "Arguments:"
    echo "  vhdl_file   - Name of VHDL file (without path)"
    echo "  top_module  - Top entity name (optional, defaults to filename without extension)"
    echo ""
    exit 1
fi

VHDL_FILENAME="$1"
VHDL_FILE="$VHDL_DIR/$VHDL_FILENAME"

# Determine top module name
if [ $# -ge 2 ]; then
    TOP_MODULE="$2"
else
    # Extract from filename (remove .vhd extension)
    TOP_MODULE=$(basename "$VHDL_FILENAME" .vhd)
fi

# Output files
SYNTH_SCRIPT="$OUTPUT_DIR/synth_script.ys"
NETLIST_EDIF="$OUTPUT_DIR/netlist.edif"
POST_SYNTH_V="$OUTPUT_DIR/post_synth_results.v"
SYNTH_REPORT="$OUTPUT_DIR/post_synth_report.txt"
SYNTH_LOG="$OUTPUT_DIR/synthesis.log"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Generate Yosys synthesis script
cat > "$SYNTH_SCRIPT" << EOF
# Load GHDL plugin for VHDL support
ghdl --std=08 --work=work ${VHDL_FILENAME} -e ${TOP_MODULE}

# Synthesize using Xilinx-compatible flow
# -nobram: Don't use block RAM (use distributed RAM/registers instead)
# -noiopad: Don't insert I/O pads (will be handled by place & route)
# -flatten: Flatten hierarchy for better optimization
# -nodsp: Don't use DSP blocks
# -widemux 5: Use wider mux structures (max 5 inputs before cascading)
synth_xilinx -nobram -noiopad -flatten -nodsp -widemux 5

# Clean up intermediate representations
clean

# Write outputs
write_verilog "post_synth_results.v"
write_edif "netlist.edif"
tee -q -o post_synth_report.txt stat
EOF

echo "========================================"
echo "VHDL to EDIF Synthesis for ForgeFPGA"
echo "========================================"
echo "VHDL File:   $VHDL_FILENAME"
echo "VHDL Path:   $VHDL_FILE"
echo "Top Module:  $TOP_MODULE"
echo "Output Dir:  $OUTPUT_DIR"
echo "========================================"

# Check if VHDL file exists
if [ ! -f "$VHDL_FILE" ]; then
    echo "ERROR: VHDL file not found: $VHDL_FILE"
    exit 1
fi

# Run Yosys synthesis
echo "Running Yosys synthesis..."
cd "$VHDL_DIR"
"$YOSYS_PATH" -m ghdl -s "../$SYNTH_SCRIPT" -l "../$SYNTH_LOG"

# Move output files to generated directory
echo "Moving output files..."
mv post_synth_results.v "../$POST_SYNTH_V" 2>/dev/null || true
mv netlist.edif "../$NETLIST_EDIF" 2>/dev/null || true
mv post_synth_report.txt "../$SYNTH_REPORT" 2>/dev/null || true

cd ..

echo ""
echo "========================================"
echo "Synthesis Complete!"
echo "========================================"
echo "Generated files:"
echo "  - EDIF Netlist:     $NETLIST_EDIF"
echo "  - Post-Synth RTL:   $POST_SYNTH_V"
echo "  - Synthesis Report: $SYNTH_REPORT"
echo "  - Synthesis Log:    $SYNTH_LOG"
echo "========================================"

# Display synthesis statistics if available
if [ -f "$SYNTH_REPORT" ]; then
    echo ""
    echo "Synthesis Statistics:"
    cat "$SYNTH_REPORT"
fi
