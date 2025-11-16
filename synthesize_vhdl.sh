#!/bin/bash
# ================================================================
# VHDL to EDIF Synthesis Script for ForgeFPGA
# Uses GHDL plugin in Yosys to synthesize VHDL to netlist
# ================================================================

set -e  # Exit on error

# Configuration
YOSYS_PATH="yosys"
VHDL_DIR="./vhdl"
OUTPUT_DIR="./generated"
TOP_MODULE="DemoSimpleBlinking"

# Input files
VHDL_FILE="$VHDL_DIR/blink.vhd"

# Output files
SYNTH_SCRIPT="$OUTPUT_DIR/synth_script.ys"
NETLIST_EDIF="$OUTPUT_DIR/netlist.edif"
POST_SYNTH_V="$OUTPUT_DIR/post_synth_results.v"
SYNTH_REPORT="$OUTPUT_DIR/post_synth_report.txt"
SYNTH_LOG="$OUTPUT_DIR/synthesis.log"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Generate Yosys synthesis script
cat > "$SYNTH_SCRIPT" << 'EOF'
# Load GHDL plugin for VHDL support
ghdl --std=08 --work=work blink.vhd -e DemoSimpleBlinking

# Synthesize using Xilinx-compatible flow (like working Verilog project)
synth_xilinx -nobram -noiopad -flatten -nodsp -widemux 5

# Clean up
clean

# Write outputs
write_verilog "post_synth_results.v"
write_edif "netlist.edif"
tee -q -o post_synth_report.txt stat
EOF

echo "========================================"
echo "VHDL to EDIF Synthesis for ForgeFPGA"
echo "========================================"
echo "VHDL Source: $VHDL_FILE"
echo "Output Dir:  $OUTPUT_DIR"
echo "Top Module:  $TOP_MODULE"
echo "========================================"

# Run Yosys synthesis
echo "Running Yosys synthesis..."
cd "$VHDL_DIR"
"$YOSYS_PATH" -m ghdl -s "../$SYNTH_SCRIPT" -l "../$SYNTH_LOG"

# Move output files to generated directory
echo "Moving output files..."
mv post_synth_results.v "../$POST_SYNTH_V" 2>/dev/null || true
mv netlist.edif "../$NETLIST_EDIF" 2>/dev/null || true
mv post_synth_report.txt "../$SYNTH_REPORT" 2>/dev/null || true

echo ""
echo "========================================"
echo "Synthesis Complete!"
echo "========================================"
echo "Generated files:"
echo "  - EDIF Netlist:    $NETLIST_EDIF"
echo "  - Post-Synth RTL:  $POST_SYNTH_V"
echo "  - Synthesis Report: $SYNTH_REPORT"
echo "  - Synthesis Log:    $SYNTH_LOG"
echo "========================================"

# Display synthesis statistics if available
if [ -f "$SYNTH_REPORT" ]; then
    echo ""
    echo "Synthesis Statistics:"
    cat "$SYNTH_REPORT"
fi
