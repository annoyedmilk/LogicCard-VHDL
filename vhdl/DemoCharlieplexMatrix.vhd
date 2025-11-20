-- ================================================================
--  SIMPLE Charlieplexed LED Matrix Demo
--  11 pins, 105 LEDs - Simple LED chase from LED 0 to LED 104
--  With 4-button control: Invert, Speed Up, Speed Down, Pause/Play
-- ================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity DemoCharlieplexMatrix is
    generic (
        IN_CLK_HZ         : positive := 50000000;  -- 50 MHz input clock
        REFRESH_RATE_HZ   : positive := 1000;      -- LED refresh rate
        NUM_LEDS          : positive := 105        -- Total LEDs used
    );
    port (
        nreset : in  std_logic;
        clk    : in  std_logic;
        osc_en : out std_logic;

        -- 4 buttons for control
        btn1   : in  std_logic;  -- Invert pattern
        btn2   : in  std_logic;  -- Speed up
        btn3   : in  std_logic;  -- Speed down
        btn4   : in  std_logic;  -- Pause/Play

        -- 11 Charlieplex pins (bidirectional)
        cpx_pins_oe : out std_logic_vector(10 downto 0);
        cpx_pins    : out std_logic_vector(10 downto 0)
    );

    -- Synthesis attributes for ForgeFPGA
    attribute clkbuf_inhibit : string;
    attribute iopad_external_pin : string;
    attribute clkbuf_inhibit of clk : signal is "true";
    attribute iopad_external_pin of clk : signal is "true";
    attribute iopad_external_pin of nreset : signal is "true";
    attribute iopad_external_pin of osc_en : signal is "true";
    attribute iopad_external_pin of btn1 : signal is "true";
    attribute iopad_external_pin of btn2 : signal is "true";
    attribute iopad_external_pin of btn3 : signal is "true";
    attribute iopad_external_pin of btn4 : signal is "true";

end entity DemoCharlieplexMatrix;

architecture rtl of DemoCharlieplexMatrix is

    -- LED scanning
    constant LINE_SCAN_HZ : positive := REFRESH_RATE_HZ * NUM_LEDS;
    constant CNT_MAX      : positive := IN_CLK_HZ / LINE_SCAN_HZ - 1;

    signal counter   : natural range 0 to CNT_MAX := 0;
    signal led_index : natural range 0 to NUM_LEDS - 1 := 0;

    -- Button debouncing
    constant DEBOUNCE_MS : positive := 20;
    constant DEBOUNCE_CNT : positive := (IN_CLK_HZ / 1000) * DEBOUNCE_MS;

    signal btn_sync : std_logic_vector(3 downto 0) := "0000";
    signal btn_deb  : std_logic_vector(3 downto 0) := "0000";
    signal btn_prev : std_logic_vector(3 downto 0) := "0000";
    signal btn_press : std_logic_vector(3 downto 0) := "0000";
    signal deb_counter : natural range 0 to DEBOUNCE_CNT := 0;

    -- Chase pattern control
    signal invert_state : std_logic := '0';
    signal paused_state : std_logic := '0';
    signal speed_level  : natural range 0 to 4 := 1;  -- 5 speed levels
    signal speed_divisor : natural range 0 to 1000000 := 500000;

    signal chase_counter : natural range 0 to 1000000 := 0;
    signal chase_pos     : natural range 0 to NUM_LEDS - 1 := 0;

    -- Pin control
    signal pins    : std_logic_vector(10 downto 0) := (others => '0');
    signal pins_oe : std_logic_vector(10 downto 0) := (others => '0');

    -- LED on/off determination
    signal led_on : std_logic := '0';

begin

    -- Constant outputs
    osc_en <= '1';

    -- Output pin assignments
    cpx_pins_oe <= pins_oe;
    cpx_pins    <= pins;

    -- Main process
    process(clk)
    begin
        if rising_edge(clk) then
            if nreset = '0' then
                -- Reset state
                counter       <= 0;
                led_index     <= 0;
                chase_counter <= 0;
                chase_pos     <= 0;
                pins          <= (others => '0');
                pins_oe       <= (others => '0');
                btn_sync      <= "0000";
                btn_deb       <= "0000";
                btn_prev      <= "0000";
                btn_press     <= "0000";
                deb_counter   <= 0;
                invert_state  <= '0';
                paused_state  <= '0';
                speed_level   <= 1;
                speed_divisor <= 500000;
            else
                -- ============================================
                -- Button Debouncing and Edge Detection
                -- ============================================

                -- Synchronize buttons
                btn_sync <= btn4 & btn3 & btn2 & btn1;

                -- Debounce
                if deb_counter = 0 then
                    btn_deb <= btn_sync;
                    deb_counter <= DEBOUNCE_CNT - 1;
                else
                    deb_counter <= deb_counter - 1;
                end if;

                -- Edge detection (rising edge)
                btn_prev <= btn_deb;
                btn_press(0) <= btn_deb(0) and not btn_prev(0);  -- BTN1 press
                btn_press(1) <= btn_deb(1) and not btn_prev(1);  -- BTN2 press
                btn_press(2) <= btn_deb(2) and not btn_prev(2);  -- BTN3 press
                btn_press(3) <= btn_deb(3) and not btn_prev(3);  -- BTN4 press

                -- ============================================
                -- Button Control Logic
                -- ============================================

                -- BTN1: Invert pattern
                if btn_press(0) = '1' then
                    invert_state <= not invert_state;
                end if;

                -- BTN2: Speed up
                if btn_press(1) = '1' and speed_level < 4 then
                    speed_level <= speed_level + 1;
                end if;

                -- BTN3: Speed down
                if btn_press(2) = '1' and speed_level > 0 then
                    speed_level <= speed_level - 1;
                end if;

                -- BTN4: Pause/Play
                if btn_press(3) = '1' then
                    paused_state <= not paused_state;
                end if;

                -- Speed divisor lookup
                case speed_level is
                    when 0      => speed_divisor <= 1000000;  -- Slowest
                    when 1      => speed_divisor <= 500000;   -- Medium-slow
                    when 2      => speed_divisor <= 250000;   -- Medium
                    when 3      => speed_divisor <= 100000;   -- Medium-fast
                    when 4      => speed_divisor <= 50000;    -- Fastest
                    when others => speed_divisor <= 500000;
                end case;

                -- ============================================
                -- Chase Pattern Update
                -- ============================================
                if paused_state = '0' then
                    if chase_counter >= speed_divisor then
                        chase_counter <= 0;
                        if chase_pos >= NUM_LEDS - 1 then
                            chase_pos <= 0;
                        else
                            chase_pos <= chase_pos + 1;
                        end if;
                    else
                        chase_counter <= chase_counter + 1;
                    end if;
                end if;

                -- ============================================
                -- LED Scanning
                -- ============================================
                if counter >= CNT_MAX then
                    counter <= 0;
                    if led_index >= NUM_LEDS - 1 then
                        led_index <= 0;
                    else
                        led_index <= led_index + 1;
                    end if;
                else
                    counter <= counter + 1;
                end if;

                -- Determine if current LED should be on
                if led_index = chase_pos then
                    led_on <= '1' xor invert_state;  -- Apply invert if enabled
                else
                    led_on <= '0' xor invert_state;
                end if;

                -- ============================================
                -- Charlieplex Pin Control (Explicit Mapping)
                -- ============================================

                -- Default: all pins off
                pins    <= (others => '0');
                pins_oe <= (others => '0');

                if led_on = '1' then
                    -- Explicit case statement for each LED
                    case led_index is
                        -- Pin0 cathode (LEDs 0-9)
                        when 0   => pins_oe <= "00000000011"; pins <= "00000000010"; -- Pin1=H, Pin0=L
                        when 1   => pins_oe <= "00000000101"; pins <= "00000000100"; -- Pin2=H, Pin0=L
                        when 2   => pins_oe <= "00000001001"; pins <= "00000001000"; -- Pin3=H, Pin0=L
                        when 3   => pins_oe <= "00000010001"; pins <= "00000010000"; -- Pin4=H, Pin0=L
                        when 4   => pins_oe <= "00000100001"; pins <= "00000100000"; -- Pin5=H, Pin0=L
                        when 5   => pins_oe <= "00001000001"; pins <= "00001000000"; -- Pin6=H, Pin0=L
                        when 6   => pins_oe <= "00010000001"; pins <= "00010000000"; -- Pin7=H, Pin0=L
                        when 7   => pins_oe <= "00100000001"; pins <= "00100000000"; -- Pin8=H, Pin0=L
                        when 8   => pins_oe <= "01000000001"; pins <= "01000000000"; -- Pin9=H, Pin0=L
                        when 9   => pins_oe <= "10000000001"; pins <= "10000000000"; -- Pin10=H, Pin0=L

                        -- Pin1 cathode (LEDs 10-19)
                        when 10  => pins_oe <= "00000000011"; pins <= "00000000001"; -- Pin0=H, Pin1=L
                        when 11  => pins_oe <= "00000000110"; pins <= "00000000100"; -- Pin2=H, Pin1=L
                        when 12  => pins_oe <= "00000001010"; pins <= "00000001000"; -- Pin3=H, Pin1=L
                        when 13  => pins_oe <= "00000010010"; pins <= "00000010000"; -- Pin4=H, Pin1=L
                        when 14  => pins_oe <= "00000100010"; pins <= "00000100000"; -- Pin5=H, Pin1=L
                        when 15  => pins_oe <= "00001000010"; pins <= "00001000000"; -- Pin6=H, Pin1=L
                        when 16  => pins_oe <= "00010000010"; pins <= "00010000000"; -- Pin7=H, Pin1=L
                        when 17  => pins_oe <= "00100000010"; pins <= "00100000000"; -- Pin8=H, Pin1=L
                        when 18  => pins_oe <= "01000000010"; pins <= "01000000000"; -- Pin9=H, Pin1=L
                        when 19  => pins_oe <= "10000000010"; pins <= "10000000000"; -- Pin10=H, Pin1=L

                        -- Pin2 cathode (LEDs 20-29)
                        when 20  => pins_oe <= "00000000101"; pins <= "00000000001"; -- Pin0=H, Pin2=L
                        when 21  => pins_oe <= "00000000110"; pins <= "00000000010"; -- Pin1=H, Pin2=L
                        when 22  => pins_oe <= "00000001100"; pins <= "00000001000"; -- Pin3=H, Pin2=L
                        when 23  => pins_oe <= "00000010100"; pins <= "00000010000"; -- Pin4=H, Pin2=L
                        when 24  => pins_oe <= "00000100100"; pins <= "00000100000"; -- Pin5=H, Pin2=L
                        when 25  => pins_oe <= "00001000100"; pins <= "00001000000"; -- Pin6=H, Pin2=L
                        when 26  => pins_oe <= "00010000100"; pins <= "00010000000"; -- Pin7=H, Pin2=L
                        when 27  => pins_oe <= "00100000100"; pins <= "00100000000"; -- Pin8=H, Pin2=L
                        when 28  => pins_oe <= "01000000100"; pins <= "01000000000"; -- Pin9=H, Pin2=L
                        when 29  => pins_oe <= "10000000100"; pins <= "10000000000"; -- Pin10=H, Pin2=L

                        -- Pin3 cathode (LEDs 30-39)
                        when 30  => pins_oe <= "00000001001"; pins <= "00000000001"; -- Pin0=H, Pin3=L
                        when 31  => pins_oe <= "00000001010"; pins <= "00000000010"; -- Pin1=H, Pin3=L
                        when 32  => pins_oe <= "00000001100"; pins <= "00000000100"; -- Pin2=H, Pin3=L
                        when 33  => pins_oe <= "00000011000"; pins <= "00000010000"; -- Pin4=H, Pin3=L
                        when 34  => pins_oe <= "00000101000"; pins <= "00000100000"; -- Pin5=H, Pin3=L
                        when 35  => pins_oe <= "00001001000"; pins <= "00001000000"; -- Pin6=H, Pin3=L
                        when 36  => pins_oe <= "00010001000"; pins <= "00010000000"; -- Pin7=H, Pin3=L
                        when 37  => pins_oe <= "00100001000"; pins <= "00100000000"; -- Pin8=H, Pin3=L
                        when 38  => pins_oe <= "01000001000"; pins <= "01000000000"; -- Pin9=H, Pin3=L
                        when 39  => pins_oe <= "10000001000"; pins <= "10000000000"; -- Pin10=H, Pin3=L

                        -- Pin4 cathode (LEDs 40-49)
                        when 40  => pins_oe <= "00000010001"; pins <= "00000000001"; -- Pin0=H, Pin4=L
                        when 41  => pins_oe <= "00000010010"; pins <= "00000000010"; -- Pin1=H, Pin4=L
                        when 42  => pins_oe <= "00000010100"; pins <= "00000000100"; -- Pin2=H, Pin4=L
                        when 43  => pins_oe <= "00000011000"; pins <= "00000001000"; -- Pin3=H, Pin4=L
                        when 44  => pins_oe <= "00000110000"; pins <= "00000100000"; -- Pin5=H, Pin4=L
                        when 45  => pins_oe <= "00001010000"; pins <= "00001000000"; -- Pin6=H, Pin4=L
                        when 46  => pins_oe <= "00010010000"; pins <= "00010000000"; -- Pin7=H, Pin4=L
                        when 47  => pins_oe <= "00100010000"; pins <= "00100000000"; -- Pin8=H, Pin4=L
                        when 48  => pins_oe <= "01000010000"; pins <= "01000000000"; -- Pin9=H, Pin4=L
                        when 49  => pins_oe <= "10000010000"; pins <= "10000000000"; -- Pin10=H, Pin4=L

                        -- Pin5 cathode (LEDs 50-59)
                        when 50  => pins_oe <= "00000100001"; pins <= "00000000001"; -- Pin0=H, Pin5=L
                        when 51  => pins_oe <= "00000100010"; pins <= "00000000010"; -- Pin1=H, Pin5=L
                        when 52  => pins_oe <= "00000100100"; pins <= "00000000100"; -- Pin2=H, Pin5=L
                        when 53  => pins_oe <= "00000101000"; pins <= "00000001000"; -- Pin3=H, Pin5=L
                        when 54  => pins_oe <= "00000110000"; pins <= "00000010000"; -- Pin4=H, Pin5=L
                        when 55  => pins_oe <= "00001100000"; pins <= "00001000000"; -- Pin6=H, Pin5=L
                        when 56  => pins_oe <= "00010100000"; pins <= "00010000000"; -- Pin7=H, Pin5=L
                        when 57  => pins_oe <= "00100100000"; pins <= "00100000000"; -- Pin8=H, Pin5=L
                        when 58  => pins_oe <= "01000100000"; pins <= "01000000000"; -- Pin9=H, Pin5=L
                        when 59  => pins_oe <= "10000100000"; pins <= "10000000000"; -- Pin10=H, Pin5=L

                        -- Pin6 cathode (LEDs 60-69)
                        when 60  => pins_oe <= "00001000001"; pins <= "00000000001"; -- Pin0=H, Pin6=L
                        when 61  => pins_oe <= "00001000010"; pins <= "00000000010"; -- Pin1=H, Pin6=L
                        when 62  => pins_oe <= "00001000100"; pins <= "00000000100"; -- Pin2=H, Pin6=L
                        when 63  => pins_oe <= "00001001000"; pins <= "00000001000"; -- Pin3=H, Pin6=L
                        when 64  => pins_oe <= "00001010000"; pins <= "00000010000"; -- Pin4=H, Pin6=L
                        when 65  => pins_oe <= "00001100000"; pins <= "00000100000"; -- Pin5=H, Pin6=L
                        when 66  => pins_oe <= "00011000000"; pins <= "00010000000"; -- Pin7=H, Pin6=L
                        when 67  => pins_oe <= "00101000000"; pins <= "00100000000"; -- Pin8=H, Pin6=L
                        when 68  => pins_oe <= "01001000000"; pins <= "01000000000"; -- Pin9=H, Pin6=L
                        when 69  => pins_oe <= "10001000000"; pins <= "10000000000"; -- Pin10=H, Pin6=L

                        -- Pin7 cathode (LEDs 70-79)
                        when 70  => pins_oe <= "00010000001"; pins <= "00000000001"; -- Pin0=H, Pin7=L
                        when 71  => pins_oe <= "00010000010"; pins <= "00000000010"; -- Pin1=H, Pin7=L
                        when 72  => pins_oe <= "00010000100"; pins <= "00000000100"; -- Pin2=H, Pin7=L
                        when 73  => pins_oe <= "00010001000"; pins <= "00000001000"; -- Pin3=H, Pin7=L
                        when 74  => pins_oe <= "00010010000"; pins <= "00000010000"; -- Pin4=H, Pin7=L
                        when 75  => pins_oe <= "00010100000"; pins <= "00000100000"; -- Pin5=H, Pin7=L
                        when 76  => pins_oe <= "00011000000"; pins <= "00001000000"; -- Pin6=H, Pin7=L
                        when 77  => pins_oe <= "00110000000"; pins <= "00100000000"; -- Pin8=H, Pin7=L
                        when 78  => pins_oe <= "01010000000"; pins <= "01000000000"; -- Pin9=H, Pin7=L
                        when 79  => pins_oe <= "10010000000"; pins <= "10000000000"; -- Pin10=H, Pin7=L

                        -- Pin8 cathode (LEDs 80-89)
                        when 80  => pins_oe <= "00100000001"; pins <= "00000000001"; -- Pin0=H, Pin8=L
                        when 81  => pins_oe <= "00100000010"; pins <= "00000000010"; -- Pin1=H, Pin8=L
                        when 82  => pins_oe <= "00100000100"; pins <= "00000000100"; -- Pin2=H, Pin8=L
                        when 83  => pins_oe <= "00100001000"; pins <= "00000001000"; -- Pin3=H, Pin8=L
                        when 84  => pins_oe <= "00100010000"; pins <= "00000010000"; -- Pin4=H, Pin8=L
                        when 85  => pins_oe <= "00100100000"; pins <= "00000100000"; -- Pin5=H, Pin8=L
                        when 86  => pins_oe <= "00101000000"; pins <= "00001000000"; -- Pin6=H, Pin8=L
                        when 87  => pins_oe <= "00110000000"; pins <= "00010000000"; -- Pin7=H, Pin8=L
                        when 88  => pins_oe <= "01100000000"; pins <= "01000000000"; -- Pin9=H, Pin8=L
                        when 89  => pins_oe <= "10100000000"; pins <= "10000000000"; -- Pin10=H, Pin8=L

                        -- Pin9 cathode (LEDs 90-99)
                        when 90  => pins_oe <= "01000000001"; pins <= "00000000001"; -- Pin0=H, Pin9=L
                        when 91  => pins_oe <= "01000000010"; pins <= "00000000010"; -- Pin1=H, Pin9=L
                        when 92  => pins_oe <= "01000000100"; pins <= "00000000100"; -- Pin2=H, Pin9=L
                        when 93  => pins_oe <= "01000001000"; pins <= "00000001000"; -- Pin3=H, Pin9=L
                        when 94  => pins_oe <= "01000010000"; pins <= "00000010000"; -- Pin4=H, Pin9=L
                        when 95  => pins_oe <= "01000100000"; pins <= "00000100000"; -- Pin5=H, Pin9=L
                        when 96  => pins_oe <= "01001000000"; pins <= "00001000000"; -- Pin6=H, Pin9=L
                        when 97  => pins_oe <= "01010000000"; pins <= "00010000000"; -- Pin7=H, Pin9=L
                        when 98  => pins_oe <= "01100000000"; pins <= "00100000000"; -- Pin8=H, Pin9=L
                        when 99  => pins_oe <= "10100000000"; pins <= "10000000000"; -- Pin10=H, Pin9=L

                        -- Pin10 cathode (LEDs 100-104)
                        when 100 => pins_oe <= "10000000001"; pins <= "00000000001"; -- Pin0=H, Pin10=L
                        when 101 => pins_oe <= "10000000010"; pins <= "00000000010"; -- Pin1=H, Pin10=L
                        when 102 => pins_oe <= "10000000100"; pins <= "00000000100"; -- Pin2=H, Pin10=L
                        when 103 => pins_oe <= "10000001000"; pins <= "00000001000"; -- Pin3=H, Pin10=L
                        when 104 => pins_oe <= "10000010000"; pins <= "00000010000"; -- Pin4=H, Pin10=L

                        when others => null;
                    end case;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
