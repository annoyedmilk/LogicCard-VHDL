#!/bin/bash
# ================================================================
# Universal FPGA Bitstream Flash Programming Script
# For ForgeFPGA with serprog/flashrom programming
# Automatically discovers available projects in goconfigure/
# ================================================================

set -e  # Exit on error

# Configuration
GOCONFIGURE_BASE="./goconfigure"
SERPROG_DEV="/dev/ttyACM0"
FLASH_SIZE_MB=1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored message
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Discover available projects
discover_projects() {
    local projects=()
    if [ -d "$GOCONFIGURE_BASE" ]; then
        for dir in "$GOCONFIGURE_BASE"/*/ ; do
            if [ -d "$dir" ]; then
                project=$(basename "$dir")
                # Check if it has the expected structure
                if [ -f "$dir/ffpga/build/bitstream/FPGA_bitstream_FLASH_MEM.bin" ]; then
                    projects+=("$project")
                fi
            fi
        done
    fi
    echo "${projects[@]}"
}

# Show usage
show_usage() {
    local available_projects=($(discover_projects))

    echo "Usage: $0 [project_name]"
    echo ""
    echo "Available projects:"
    if [ ${#available_projects[@]} -eq 0 ]; then
        echo "  (no projects found in $GOCONFIGURE_BASE)"
    else
        for proj in "${available_projects[@]}"; do
            echo "  - $proj"
        done
    fi
    echo ""
    echo "If no project is specified, you will be prompted to choose."
    echo ""
}

# Interactive project selection
select_project() {
    local projects=($(discover_projects))

    if [ ${#projects[@]} -eq 0 ]; then
        print_error "No projects found in $GOCONFIGURE_BASE/"
        print_status "Please ensure you have built bitstreams in GoConfigure first"
        exit 1
    fi

    if [ ${#projects[@]} -eq 1 ]; then
        echo "${projects[0]}"
        return
    fi

    echo "Available projects:"
    for i in "${!projects[@]}"; do
        printf "  %d) %s\n" $((i+1)) "${projects[$i]}"
    done
    echo ""

    while true; do
        read -p "Select project [1-${#projects[@]}]: " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#projects[@]}" ]; then
            echo "${projects[$((selection-1))]}"
            return
        else
            print_error "Invalid selection. Please enter a number between 1 and ${#projects[@]}"
        fi
    done
}

# Parse command line arguments
if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_usage
    exit 0
fi

if [ -n "$1" ]; then
    PROJECT="$1"
    # Validate project exists
    if [ ! -d "$GOCONFIGURE_BASE/$PROJECT/ffpga/build/bitstream" ]; then
        print_error "Project '$PROJECT' not found in $GOCONFIGURE_BASE/"
        echo ""
        show_usage
        exit 1
    fi
else
    # Interactive selection
    PROJECT=$(select_project)
fi

# Set paths based on selected project
GOCONFIGURE_DIR="$GOCONFIGURE_BASE/$PROJECT/ffpga/build/bitstream"
BITSTREAM_48KB="$GOCONFIGURE_DIR/FPGA_bitstream_FLASH_MEM.bin"
BITSTREAM_1MB="$GOCONFIGURE_DIR/FPGA_bitstream_FLASH_MEM_1MB.bin"

# Check if 48KB bitstream exists
if [ ! -f "$BITSTREAM_48KB" ]; then
    print_error "48KB bitstream not found: $BITSTREAM_48KB"
    print_status "Please ensure you have generated the bitstream in GoConfigure first"
    exit 1
fi

# Check bitstream size
BITSTREAM_SIZE=$(stat -c%s "$BITSTREAM_48KB")
EXPECTED_SIZE=49152  # 48KB = 48 * 1024 bytes
print_status "Bitstream size: $BITSTREAM_SIZE bytes (expected: ~$EXPECTED_SIZE bytes)"

if [ "$BITSTREAM_SIZE" -gt "$EXPECTED_SIZE" ]; then
    print_warning "Bitstream is larger than expected 48KB"
fi

# Pad bitstream to 1MB
print_status "Padding bitstream to ${FLASH_SIZE_MB}MB..."
cp "$BITSTREAM_48KB" "$BITSTREAM_1MB"
truncate -s ${FLASH_SIZE_MB}M "$BITSTREAM_1MB"

PADDED_SIZE=$(stat -c%s "$BITSTREAM_1MB")
print_status "Padded bitstream size: $PADDED_SIZE bytes (1 MB = 1,048,576 bytes)"

# Verify padded size
EXPECTED_PADDED_SIZE=$((FLASH_SIZE_MB * 1024 * 1024))
if [ "$PADDED_SIZE" -ne "$EXPECTED_PADDED_SIZE" ]; then
    print_error "Padded size mismatch! Expected: $EXPECTED_PADDED_SIZE, Got: $PADDED_SIZE"
    exit 1
fi

print_status "Successfully created padded bitstream: $BITSTREAM_1MB"

# Check if serprog device exists
if [ ! -e "$SERPROG_DEV" ]; then
    print_error "Serprog device not found: $SERPROG_DEV"
    print_status "Please ensure:"
    print_status "  1. LogicCard is connected via USB"
    print_status "  2. CH552 firmware (serprog) is programmed"
    print_status "  3. Device enumerated correctly (check 'dmesg' and 'lsusb')"
    exit 1
fi

# Check if flashrom is installed (handle flatpak environment)
if command -v flashrom &> /dev/null; then
    FLASHROM_CMD="flashrom"
elif command -v flatpak-spawn &> /dev/null && flatpak-spawn --host which flashrom &> /dev/null; then
    FLASHROM_CMD="flatpak-spawn --host flashrom"
else
    print_error "flashrom is not installed"
    print_status "Install with: sudo apt install flashrom"
    exit 1
fi

print_status "Using flashrom: $FLASHROM_CMD"

# Check device permissions
if [ ! -r "$SERPROG_DEV" ] || [ ! -w "$SERPROG_DEV" ]; then
    print_warning "No read/write permissions for $SERPROG_DEV"
    print_status "You may need to add yourself to the dialout group:"
    print_status "  sudo usermod -a -G dialout \$USER"
    print_status "  (then logout and login)"
fi

echo ""
echo "========================================"
echo "FPGA Bitstream Flash Programming"
echo "========================================"
echo "Project:        $PROJECT"
echo "Source (48KB):  $BITSTREAM_48KB"
echo "Padded (1MB):   $BITSTREAM_1MB"
echo "Device:         $SERPROG_DEV"
echo "Flash Size:     ${FLASH_SIZE_MB}MB (W25Q80)"
echo "========================================"
echo ""

# Ask for confirmation
read -p "Proceed with flashing? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "Flashing cancelled"
    exit 0
fi

# Flash the bitstream
print_status "Starting flash programming..."
print_warning "This may take 1-2 minutes. Do not disconnect the device!"

if $FLASHROM_CMD -p serprog:dev="$SERPROG_DEV" -w "$BITSTREAM_1MB"; then
    echo ""
    print_status "✓ Flash programming completed successfully!"
    print_status "The FPGA should now automatically configure and run"
    echo ""
    echo "========================================"
    echo "Programming Summary"
    echo "========================================"
    echo "Status:     SUCCESS"
    echo "Project:    $PROJECT"
    echo "Bitstream:  $BITSTREAM_1MB"
    echo "Device:     $SERPROG_DEV"
    echo "========================================"
else
    echo ""
    print_error "✗ Flash programming failed!"
    print_status "Troubleshooting steps:"
    print_status "  1. Check USB connection"
    print_status "  2. Verify serprog device: ls -l $SERPROG_DEV"
    print_status "  3. Check dmesg for USB errors"
    print_status "  4. Try reconnecting the device"
    print_status "  5. Try again - sometimes one retry is all it takes"
    exit 1
fi
