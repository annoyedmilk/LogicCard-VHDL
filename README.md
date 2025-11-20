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
   - Install to: `/opt/oss-cad-suite/`

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

- **LogicCard** - Compact FPGA development board featuring:
  - Renesas SLG47910V FPGA (1120 LUTs, 1120 DFFs)
  - CH552 microcontroller with serprog USB programming
  - W25Q80 SPI Flash (1 Mbit)
  - 15×7 Charlieplexed LED matrix (105 LEDs, 11 GPIO pins)
  - 4 user buttons
  - USB-powered
  - **Hardware Design**: [github.com/annoyedmilk/LogicCard](https://github.com/annoyedmilk/LogicCard)
- USB connection for programming via serprog/flashrom

## Project Structure

```
LogicCard-VHDL/
├── vhdl/
│   ├── blink.vhd                    # Simple LED blink demo
│   └── DemoCharlieplexMatrix.vhd    # Charlieplex LED matrix (11 GPIO, 105 LEDs)
├── generated/
│   ├── netlist.edif                 # Generated EDIF netlist (temp/working)
│   ├── post_synth_results.v         # Post-synthesis Verilog (for inspection)
│   ├── post_synth_report.txt        # Synthesis statistics
│   └── synthesis.log                # Detailed synthesis log
├── goconfigure/
│   ├── blink/                       # Blink demo GoConfigure project
│   │   └── ffpga/
│   │       ├── netlists/
│   │       │   └── netlist.edif     # EDIF imported into GoConfigure
│   │       ├── src/                 # Pin assignments and constraints
│   │       └── build/
│   │           └── bitstream/
│   │               ├── FPGA_bitstream_FLASH_MEM.bin     # 48KB bitstream
│   │               └── FPGA_bitstream_FLASH_MEM_1MB.bin # Padded for W25Q80
│   └── charlieplex/                 # Charlieplex demo GoConfigure project
│       └── ffpga/
│           ├── netlists/
│           │   └── netlist.edif     # EDIF imported into GoConfigure
│           ├── src/                 # Pin assignments and constraints
│           └── build/
│               └── bitstream/
│                   ├── FPGA_bitstream_FLASH_MEM.bin     # 48KB bitstream
│                   └── FPGA_bitstream_FLASH_MEM_1MB.bin # Padded for W25Q80
├── synthesize_vhdl.sh               # Universal VHDL synthesis script
└── flash_bitstream.sh               # Universal bitstream flashing script
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

Run the universal synthesis script:

```bash
./synthesize_vhdl.sh <vhdl_file> [top_module]
```

**Examples:**
```bash
# Synthesize blink demo (auto-detects top module)
./synthesize_vhdl.sh blink.vhd

# Synthesize charlieplex demo
./synthesize_vhdl.sh DemoCharlieplexMatrix.vhd

# Specify custom top module name
./synthesize_vhdl.sh mydesign.vhd MyTopEntity
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
- `generated/synthesis.log` - Full synthesis log

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

## Example Designs

### 1. Blink Demo (blink.vhd)
A simple LED blinking example demonstrating basic VHDL synthesis workflow.

**Features:**
- Single LED blink at configurable frequency
- Internal oscillator usage
- Basic clock divider
- 2 GPIO pins (LED anode/cathode)

### 2. Charlieplex LED Matrix Demo (DemoCharlieplexMatrix.vhd)
Simple LED matrix controller using Charlieplexing technique with 4-button control.

**Features:**
- 11 GPIO pins controlling 105 LEDs (11×10 Charlieplex configuration)
- Simple LED chase pattern from LED 0 to LED 104
- 4 button controls:
  - **BTN1**: Invert pattern (all LEDs except chase LED)
  - **BTN2**: Speed up (5 speed levels)
  - **BTN3**: Speed down
  - **BTN4**: Pause/Play
- Button debouncing (20ms) with edge detection
- Configurable refresh rate (1 kHz default)

**Resource Usage:**
- **87 CLBs** (62.1% of 1K LUT FPGA)
- **288 LUTs** utilized (51.4%)
- **96 FFs** utilized (17.1%)
- **Achievable frequency**: 99.721 MHz

**Optimization Highlights:**
- Explicit case statement for all 105 LEDs (no variable indexing)
- Simple on/off LED control (no PWM for minimal resource usage)
- No loops in synthesizable logic to prevent logic explosion
- Flat architecture suitable for EDIF export
- Successfully fits in 1K LUT FPGA

## Design Guidelines for ForgeFPGA VHDL

### DO:

1. **Use flat designs** - Single entity with all logic inline
2. **Add synthesis attributes** - Include `clkbuf_inhibit` and `iopad_external_pin` on all ports
3. **Test synthesis output** - Check `post_synth_report.txt` for resource usage
4. **Use explicit case statements** - For LED/pin mapping instead of variable indexing
5. **Use simple pattern assignments** - Direct signal assignments instead of complex aggregates
6. **Use subtraction-based wrapping** - For range limiting operations

### DON'T:

1. **Don't use component instantiation** - Causes EDIF hierarchy issues
2. **Don't skip synthesis attributes** - Missing attributes cause non-functional designs
3. **Don't skip flattening** - Always use `-flatten` in synthesis
4. **Don't use variable indexing** - `signal(variable_index)` creates massive multiplexers
5. **Don't use variable `while` loops** - GHDL synthesis requires static loop conditions
6. **Don't use `declare` blocks in processes** - Move variable declarations to process header
7. **Don't use loops in synthesis** - Even `for` loops unroll and create huge logic


## References

### Hardware
- **LogicCard Hardware**: https://github.com/annoyedmilk/LogicCard
  - Open-source hardware design files, schematics, and BOM
  - CH552 serprog firmware for USB programming
  - Pre-built Verilog examples with bitstreams
  - SLG47910V FPGA datasheet and documentation

### Software Tools
- **Go Configure Software Hub**: https://www.renesas.com/en/software-tool/go-configure-software-hub
- **OSS CAD Suite**: https://github.com/YosysHQ/oss-cad-suite-build
- **GHDL**: https://github.com/ghdl/ghdl
- **Yosys**: https://github.com/YosysHQ/yosys
- **flashrom**: https://www.flashrom.org/

## License

This workflow and documentation is provided as-is for educational purposes.

## Troubleshooting

**Q: How do I verify the EDIF is correct?**

A: Check `generated/post_synth_results.v` - it should be a flat module with no submodule instantiations.

**Q: Can I use libraries other than IEEE standard?**

A: Stick to `IEEE.STD_LOGIC_1164` and `IEEE.NUMERIC_STD` for best compatibility.

**Q: GHDL error: "loop condition must be static"**

A: GHDL synthesis requires loop bounds to be known at compile time. Replace variable `while` loops with:
- Fixed-iteration `for` loops with static bounds
- Multiple `if` statements for small ranges
- Successive subtraction for wrapping values to a specific range

Example:
```vhdl
-- BAD: Variable while loop
while value >= MAX_VALUE loop
    value := value - MAX_VALUE;
end loop;

-- GOOD: Fixed for loop
for i in 0 to 255 loop
    if value >= MAX_VALUE then
        value := value - MAX_VALUE;
    end if;
end loop;
```

**Q: GHDL error: "declaration not allowed within statements"**

A: Don't use `declare` blocks inside case statements or if statements. Move all variable declarations to the top of the process.

Example:
```vhdl
-- BAD: Declare block in case
when 0 =>
    declare
        variable temp : integer;
    begin
        temp := some_value;
    end;

-- GOOD: Variable at process start
process(clk)
    variable temp : integer;
begin
    case pattern is
        when 0 =>
            temp := some_value;
    end case;
end process;
```
