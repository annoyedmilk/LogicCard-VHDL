# VHDL Synthesis for ForgeFPGA using Yosys/GHDL

This guide demonstrates how to use VHDL instead of Verilog for ForgeFPGA (Renesas SLG47910) projects. The workflow uses open-source tools (GHDL + Yosys) to synthesize VHDL to EDIF, which can then be imported into GoConfigure for place-and-route.

## Overview

**Traditional ForgeFPGA Workflow (Verilog):**
```
GoConfigure → Bitstream → Flash
```

**New VHDL Workflow:**
```
VHDL → GHDL/Yosys → EDIF → GoConfigure → Bitstream → Flash
```

## Prerequisites

### Software Requirements

1. **OSS CAD Suite** (includes Yosys + GHDL)
   - Download from: https://github.com/YosysHQ/oss-cad-suite-build
   - Install to: `~/oss-cad-suite/`

2. **GoConfigure** (Renesas ForgeFPGA Workshop)
   - Required for place-and-route and bitstream generation
   - GUI tool

3. **flashrom** (for programming the flash)
   ```bash
   sudo apt install flashrom
   ```

4. **serprog-compatible programmer**
   - CH552-based programmer on LogicCard
   - Or similar serprog-compatible device

### Hardware Requirements

- ForgeFPGA development board (e.g., LogicCard with SLG47910)
- USB connection for programming

## Project Structure

```
test/
├── vhdl/
│   └── blink.vhd              # VHDL source files
├── generated/
│   ├── netlist.edif           # Generated EDIF netlist
│   ├── post_synth_results.v   # Post-synthesis Verilog (for inspection)
│   └── post_synth_report.txt  # Synthesis statistics
├── goconfigure/
│   └── blink/
│       └── ffpga/build/bitstream/
│           ├── FPGA_bitstream_FLASH_MEM.bin     # 48KB bitstream
│           └── FPGA_bitstream_FLASH_MEM_1MB.bin # Padded for W25Q80
├── synthesize_vhdl.sh         # VHDL synthesis script
└── flash_bitstream.sh         # Bitstream flashing script
```

## Step-by-Step Workflow

### Step 1: Write VHDL Code

**Important Guidelines:**

1. **Flat Design Only** - Do not use component instantiations
   - Bad: Hierarchical design with component instantiation
   - Good: Single flat entity with all logic inline

2. **Add Synthesis Attributes** - Critical for ForgeFPGA
   ```vhdl
   -- Synthesis attributes for ForgeFPGA
   attribute clkbuf_inhibit : string;
   attribute iopad_external_pin : string;

   attribute clkbuf_inhibit of clk : signal is "true";
   attribute iopad_external_pin of clk : signal is "true";
   attribute iopad_external_pin of nreset : signal is "true";
   -- Add iopad_external_pin to all other ports
   ```

3. **Use Standard Libraries**
   ```vhdl
   library IEEE;
   use IEEE.STD_LOGIC_1164.ALL;
   use IEEE.NUMERIC_STD.ALL;
   ```

### Step 2: Synthesize VHDL to EDIF

Run the synthesis script:

```bash
./synthesize_vhdl.sh
```

**What this does:**
1. Loads VHDL using GHDL plugin
2. Synthesizes using Xilinx-compatible flow (compatible with ForgeFPGA)
3. Flattens the design completely
4. Generates EDIF netlist and post-synthesis Verilog

**Output:**
- `generated/netlist.edif` - Import this into GoConfigure
- `generated/post_synth_results.v` - For inspection
- `generated/post_synth_report.txt` - Resource usage

### Step 3: Place and Route in GoConfigure

1. **Open GoConfigure** (Windows GUI tool)
2. **Import EDIF:**
   - File → Import → EDIF Netlist
   - Select `generated/netlist.edif`
3. **Assign GPIO Pins:**
   - Map VHDL ports to physical FPGA pins
   - Example for LogicCard blink:
     ```
     clk            → Use internal oscillator (50 MHz)
     nreset         → GPIO11
     osc_en         → (internal signal)
     led1_anode_oe  → GPIO8 output enable
     led1_anode     → GPIO8
     led1_cathode_oe→ GPIO9 output enable
     led1_cathode   → GPIO9
     ```
4. **Run Place and Route (PnR)**
5. **Generate Bitstream:**
   - File → Generate Bitstream
   - Output: `FPGA_bitstream_FLASH_MEM.bin` (48KB)

### Step 4: Flash the Bitstream

Run the flash script:

```bash
./flash_bitstream.sh
```

**What this does:**
1. Finds the 48KB bitstream from GoConfigure build directory
2. Pads it to 1MB (W25Q80 flash size requirement)
3. Programs the flash via serprog/flashrom
4. Verifies the programming

## Common Issues and Solutions

### Issue 1: "Module id00061 referenced but not found"

**Problem:** Hierarchical component instantiation in VHDL causing undefined module references in EDIF.

**Solution:** Use a flat design - inline all logic into a single entity without component instantiation.

**Example Fix:**
```vhdl
-- BAD: Component instantiation
blinker_led1 : entity work.blinker
    port map (clk => clk, ...);

-- GOOD: Inline logic
process(clk)
begin
    if rising_edge(clk) then
        -- All logic here
    end if;
end process;
```

### Issue 2: "GHDL not found"

**Problem:** GHDL plugin not available in Yosys.

**Solution:** Install OSS CAD Suite which includes Yosys with GHDL plugin pre-built.

### Issue 3: Flatpak Environment Can't Find flashrom

**Problem:** Running from sandboxed environment (VSCode Flatpak).

**Solution:** Script automatically detects and uses `flatpak-spawn --host flashrom`.

## Design Guidelines for ForgeFPGA VHDL

### DO:

1. **Use flat designs** - Single entity with all logic inline
2. **Add synthesis attributes** - Include `clkbuf_inhibit` and `iopad_external_pin` on all ports
3. **Test synthesis output** - Check `post_synth_report.txt` for resource usage

### DON'T:

1. **Don't use component instantiation** - Causes EDIF hierarchy issues
2. **Don't skip synthesis attributes** - Missing attributes cause non-functional designs
3. **Don't skip flattening** - Always use `-flatten` in synthesis


## References

- **Go Configure Software Hub**: https://www.renesas.com/en/software-tool/go-configure-software-hub
- **OSS CAD Suite**: https://github.com/YosysHQ/oss-cad-suite-build
- **GHDL**: https://github.com/ghdl/ghdl
- **Yosys**: https://github.com/YosysHQ/yosys
- **LogicCard**: https://github.com/annoyedmilk/LogicCard

## License

This workflow and documentation is provided as-is for educational purposes.

## Troubleshooting

**Q: How do I verify the EDIF is correct?**

A: Check `generated/post_synth_results.v` - it should be a flat module with no submodule instantiations.

**Q: Can I use libraries other than IEEE standard?**

A: Stick to `IEEE.STD_LOGIC_1164` and `IEEE.NUMERIC_STD` for best compatibility.
