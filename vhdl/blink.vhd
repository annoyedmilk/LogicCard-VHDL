-- ================================================================
--  Simple Blinking LED Demo
--  Single LED controlled via anode/cathode pair
--  Demonstrates basic clock divider and LED control for ForgeFPGA
-- ================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity blink is
    generic (
        IN_CLK_HZ : positive := 50000000;  -- 50 MHz input clock
        BLINK_HZ  : positive := 2          -- LED blink frequency
    );
    port (
        nreset : in  std_logic;
        clk    : in  std_logic;
        osc_en : out std_logic;

        -- LED control signals (anode/cathode pair)
        led1_anode_oe   : out std_logic;
        led1_anode      : out std_logic;
        led1_cathode_oe : out std_logic;
        led1_cathode    : out std_logic
    );

    -- Synthesis attributes for ForgeFPGA
    attribute clkbuf_inhibit : string;
    attribute iopad_external_pin : string;
    attribute clkbuf_inhibit of clk : signal is "true";
    attribute iopad_external_pin of clk : signal is "true";
    attribute iopad_external_pin of nreset : signal is "true";
    attribute iopad_external_pin of osc_en : signal is "true";
    attribute iopad_external_pin of led1_anode_oe : signal is "true";
    attribute iopad_external_pin of led1_anode : signal is "true";
    attribute iopad_external_pin of led1_cathode_oe : signal is "true";
    attribute iopad_external_pin of led1_cathode : signal is "true";

end entity blink;

architecture rtl of blink is

    -- Clock divider
    constant CNT_MAX : positive := IN_CLK_HZ / (2 * BLINK_HZ) - 1;

    signal counter      : natural range 0 to CNT_MAX := 0;
    signal blink_state  : std_logic := '0';

begin

    -- Constant outputs
    osc_en <= '1';

    -- LED output assignments
    -- Anode is driven high/low for on/off, cathode is always pulled low
    led1_anode_oe   <= '1';
    led1_cathode_oe <= '1';
    led1_cathode    <= '0';
    led1_anode      <= blink_state;

    -- Main process
    process(clk)
    begin
        if rising_edge(clk) then
            if nreset = '0' then
                -- Reset state
                counter     <= 0;
                blink_state <= '0';
            else
                -- ============================================
                -- Blink Counter
                -- ============================================
                if counter >= CNT_MAX then
                    counter     <= 0;
                    blink_state <= not blink_state;
                else
                    counter <= counter + 1;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
