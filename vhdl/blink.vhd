-- ================================================================
--  DEMO: Simple Blinking LED
--  Flat VHDL-2008 implementation (no component instantiation)
-- ================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity DemoSimpleBlinking is
    generic (
        IN_CLK_HZ : positive := 50000000;
        BLINK_HZ  : positive := 2
    );
    port (
        nreset : in  std_logic;
        clk    : in  std_logic;
        osc_en : out std_logic;

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

end entity DemoSimpleBlinking;

architecture rtl of DemoSimpleBlinking is

    constant CNT_MAX : natural := IN_CLK_HZ / (2 * BLINK_HZ) - 1;
    constant CNT_WIDTH : natural := 24;

    signal counter : unsigned(CNT_WIDTH-1 downto 0);
    signal blink_signal : std_logic;

begin

    -- Constant outputs
    osc_en <= '1';
    led1_anode_oe   <= '1';
    led1_cathode_oe <= '1';
    led1_cathode    <= '0';

    -- Blinking LED
    led1_anode <= blink_signal;

    -- Blinker logic (inlined, no component)
    process(clk)
    begin
        if rising_edge(clk) then
            if nreset = '0' then
                counter <= (others => '0');
                blink_signal <= '0';
            else
                if counter >= CNT_MAX then
                    counter <= (others => '0');
                    blink_signal <= not blink_signal;
                else
                    counter <= counter + 1;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
