-- ================================================================
--  CATCH THE DOT - Ultra-optimized for forgeFPGA (~100 CLBs)
--  15x7 LED Matrix + 4 Buttons
--  Player (solid) chases Target (blinking)
-- ================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity CatchTheDot is
    generic (
        IN_CLK_HZ   : positive := 50000000;  -- 50 MHz input clock
        REFRESH_HZ  : positive := 1000       -- LED refresh rate
    );
    port (
        nreset : in  std_logic;
        clk    : in  std_logic;
        osc_en : out std_logic;

        -- Button inputs (active high)
        btn1   : in  std_logic;  -- Left
        btn2   : in  std_logic;  -- Up
        btn3   : in  std_logic;  -- Down
        btn4   : in  std_logic;  -- Right

        -- 11 Charlieplex pins
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

end entity CatchTheDot;

architecture rtl of CatchTheDot is

    -- Constants
    constant NUM_LEDS     : positive := 105;
    constant LINE_SCAN_HZ : positive := REFRESH_HZ * NUM_LEDS;
    constant CNT_MAX      : positive := IN_CLK_HZ / LINE_SCAN_HZ - 1;
    constant TICK_MAX     : positive := 6250000 - 1;  -- ~8Hz tick

    -- Clock dividers
    signal slow_cnt   : unsigned(22 downto 0) := (others => '0');
    signal tick_8hz   : std_logic := '0';
    signal blink      : std_logic := '0';

    -- Button synchronization and edge detection
    signal btn_sync0  : std_logic_vector(3 downto 0) := "0000";
    signal btn_sync1  : std_logic_vector(3 downto 0) := "0000";
    signal btn_prev   : std_logic_vector(3 downto 0) := "0000";
    signal btn_press  : std_logic_vector(3 downto 0) := "0000";

    signal btn_left   : std_logic := '0';
    signal btn_up     : std_logic := '0';
    signal btn_down   : std_logic := '0';
    signal btn_right  : std_logic := '0';

    -- LFSR for random number generation
    signal lfsr       : std_logic_vector(9 downto 0) := "1010110011";
    signal lfsr_fb    : std_logic;

    -- Game state: player and target positions
    signal player_x   : unsigned(3 downto 0) := to_unsigned(7, 4);   -- 0-14
    signal player_y   : unsigned(2 downto 0) := to_unsigned(3, 3);   -- 0-6
    signal target_x   : unsigned(3 downto 0) := to_unsigned(12, 4);
    signal target_y   : unsigned(2 downto 0) := to_unsigned(5, 3);

    -- Random position computation
    signal rand_x     : unsigned(3 downto 0);
    signal rand_y     : unsigned(2 downto 0);

    -- Catch detection
    signal caught     : std_logic;

    -- LED scanner
    signal scan_cnt   : natural range 0 to CNT_MAX := 0;
    signal led_index  : natural range 0 to NUM_LEDS - 1 := 0;

    -- LED index to X,Y conversion
    signal query_x    : unsigned(3 downto 0) := (others => '0');
    signal query_y    : unsigned(2 downto 0) := (others => '0');

    -- LED on/off determination
    signal is_player  : std_logic;
    signal is_target  : std_logic;
    signal led_on     : std_logic := '0';

    -- Charlieplex pin mapping
    signal cathode       : natural range 0 to 10 := 0;
    signal pos_in_group  : natural range 0 to 9 := 0;
    signal anode         : natural range 0 to 10 := 0;

    -- Pin control
    signal pins       : std_logic_vector(10 downto 0) := (others => '0');
    signal pins_oe    : std_logic_vector(10 downto 0) := (others => '0');

begin

    -- Constant outputs
    osc_en <= '1';

    -- Output pin assignments
    cpx_pins_oe <= pins_oe;
    cpx_pins    <= pins;

    -- LFSR feedback
    lfsr_fb <= lfsr(9) xor lfsr(6);

    -- Random position computation (constrained to grid)
    rand_x <= unsigned(lfsr(3 downto 0)) when unsigned(lfsr(3 downto 0)) < 15
              else unsigned(lfsr(3 downto 0)) - 5;
    rand_y <= unsigned(lfsr(6 downto 4)) when unsigned(lfsr(6 downto 4)) < 7
              else unsigned(lfsr(6 downto 4)) - 2;

    -- Catch detection
    caught <= '1' when (player_x = target_x) and (player_y = target_y) else '0';

    -- Button press signals
    btn_left  <= btn_press(0);
    btn_up    <= btn_press(1);
    btn_down  <= btn_press(2);
    btn_right <= btn_press(3);

    -- LED position detection
    is_player <= '1' when (query_x = player_x) and (query_y = player_y) else '0';
    is_target <= '1' when (query_x = target_x) and (query_y = target_y) else '0';

    -- LED index to X,Y conversion (combinational)
    process(led_index)
    begin
        if led_index < 15 then
            query_y <= to_unsigned(0, 3);
            query_x <= to_unsigned(led_index, 4);
        elsif led_index < 30 then
            query_y <= to_unsigned(1, 3);
            query_x <= to_unsigned(led_index - 15, 4);
        elsif led_index < 45 then
            query_y <= to_unsigned(2, 3);
            query_x <= to_unsigned(led_index - 30, 4);
        elsif led_index < 60 then
            query_y <= to_unsigned(3, 3);
            query_x <= to_unsigned(led_index - 45, 4);
        elsif led_index < 75 then
            query_y <= to_unsigned(4, 3);
            query_x <= to_unsigned(led_index - 60, 4);
        elsif led_index < 90 then
            query_y <= to_unsigned(5, 3);
            query_x <= to_unsigned(led_index - 75, 4);
        else
            query_y <= to_unsigned(6, 3);
            query_x <= to_unsigned(led_index - 90, 4);
        end if;
    end process;

    -- Charlieplex cathode/anode computation (combinational)
    process(led_index)
    begin
        if led_index < 10 then
            cathode <= 0;
            pos_in_group <= led_index;
        elsif led_index < 20 then
            cathode <= 1;
            pos_in_group <= led_index - 10;
        elsif led_index < 30 then
            cathode <= 2;
            pos_in_group <= led_index - 20;
        elsif led_index < 40 then
            cathode <= 3;
            pos_in_group <= led_index - 30;
        elsif led_index < 50 then
            cathode <= 4;
            pos_in_group <= led_index - 40;
        elsif led_index < 60 then
            cathode <= 5;
            pos_in_group <= led_index - 50;
        elsif led_index < 70 then
            cathode <= 6;
            pos_in_group <= led_index - 60;
        elsif led_index < 80 then
            cathode <= 7;
            pos_in_group <= led_index - 70;
        elsif led_index < 90 then
            cathode <= 8;
            pos_in_group <= led_index - 80;
        elsif led_index < 100 then
            cathode <= 9;
            pos_in_group <= led_index - 90;
        else
            cathode <= 10;
            pos_in_group <= led_index - 100;
        end if;
    end process;

    -- Anode computation: skip the cathode pin number
    process(pos_in_group, cathode)
    begin
        if pos_in_group < cathode then
            anode <= pos_in_group;
        else
            anode <= pos_in_group + 1;
        end if;
    end process;

    -- Main process
    process(clk)
        variable cathode_oh : std_logic_vector(10 downto 0);
        variable anode_oh   : std_logic_vector(10 downto 0);
    begin
        if rising_edge(clk) then
            if nreset = '0' then
                -- Reset state
                slow_cnt   <= (others => '0');
                tick_8hz   <= '0';
                blink      <= '0';
                btn_sync0  <= "0000";
                btn_sync1  <= "0000";
                btn_prev   <= "0000";
                btn_press  <= "0000";
                lfsr       <= "1010110011";
                player_x   <= to_unsigned(7, 4);
                player_y   <= to_unsigned(3, 3);
                target_x   <= to_unsigned(12, 4);
                target_y   <= to_unsigned(5, 3);
                scan_cnt   <= 0;
                led_index  <= 0;
                led_on     <= '0';
                pins       <= (others => '0');
                pins_oe    <= (others => '0');
            else
                -- ============================================
                -- Slow clock divider (~8Hz tick)
                -- ============================================
                if slow_cnt >= TICK_MAX then
                    slow_cnt <= (others => '0');
                    tick_8hz <= '1';
                else
                    slow_cnt <= slow_cnt + 1;
                    tick_8hz <= '0';
                end if;

                -- Blink signal (~6Hz)
                blink <= slow_cnt(21);

                -- ============================================
                -- LFSR update (continuous)
                -- ============================================
                lfsr <= lfsr(8 downto 0) & lfsr_fb;

                -- ============================================
                -- Button sync and edge detect
                -- ============================================
                btn_sync0 <= btn4 & btn3 & btn2 & btn1;
                btn_sync1 <= btn_sync0;

                if tick_8hz = '1' then
                    btn_prev <= btn_sync1;
                end if;

                btn_press(0) <= btn_sync1(0) and not btn_prev(0);
                btn_press(1) <= btn_sync1(1) and not btn_prev(1);
                btn_press(2) <= btn_sync1(2) and not btn_prev(2);
                btn_press(3) <= btn_sync1(3) and not btn_prev(3);

                -- ============================================
                -- Game state update
                -- ============================================
                if tick_8hz = '1' then
                    -- Move player with wrap-around
                    if btn_up = '1' then
                        if player_y = 0 then
                            player_y <= to_unsigned(6, 3);
                        else
                            player_y <= player_y - 1;
                        end if;
                    end if;

                    if btn_down = '1' then
                        if player_y = 6 then
                            player_y <= to_unsigned(0, 3);
                        else
                            player_y <= player_y + 1;
                        end if;
                    end if;

                    if btn_left = '1' then
                        if player_x = 0 then
                            player_x <= to_unsigned(14, 4);
                        else
                            player_x <= player_x - 1;
                        end if;
                    end if;

                    if btn_right = '1' then
                        if player_x = 14 then
                            player_x <= to_unsigned(0, 4);
                        else
                            player_x <= player_x + 1;
                        end if;
                    end if;

                    -- Spawn new target when caught
                    if caught = '1' then
                        target_x <= rand_x;
                        target_y <= rand_y;
                    end if;
                end if;

                -- ============================================
                -- LED Scanner
                -- ============================================
                if scan_cnt >= CNT_MAX then
                    scan_cnt <= 0;
                    if led_index >= NUM_LEDS - 1 then
                        led_index <= 0;
                    else
                        led_index <= led_index + 1;
                    end if;
                else
                    scan_cnt <= scan_cnt + 1;
                end if;

                -- Determine if current LED should be on
                led_on <= is_player or (is_target and blink);

                -- ============================================
                -- Charlieplex Pin Control
                -- ============================================

                -- Convert cathode to one-hot
                case cathode is
                    when 0      => cathode_oh := "00000000001";
                    when 1      => cathode_oh := "00000000010";
                    when 2      => cathode_oh := "00000000100";
                    when 3      => cathode_oh := "00000001000";
                    when 4      => cathode_oh := "00000010000";
                    when 5      => cathode_oh := "00000100000";
                    when 6      => cathode_oh := "00001000000";
                    when 7      => cathode_oh := "00010000000";
                    when 8      => cathode_oh := "00100000000";
                    when 9      => cathode_oh := "01000000000";
                    when 10     => cathode_oh := "10000000000";
                    when others => cathode_oh := "00000000000";
                end case;

                -- Convert anode to one-hot
                case anode is
                    when 0      => anode_oh := "00000000001";
                    when 1      => anode_oh := "00000000010";
                    when 2      => anode_oh := "00000000100";
                    when 3      => anode_oh := "00000001000";
                    when 4      => anode_oh := "00000010000";
                    when 5      => anode_oh := "00000100000";
                    when 6      => anode_oh := "00001000000";
                    when 7      => anode_oh := "00010000000";
                    when 8      => anode_oh := "00100000000";
                    when 9      => anode_oh := "01000000000";
                    when 10     => anode_oh := "10000000000";
                    when others => anode_oh := "00000000000";
                end case;

                -- Drive charlieplex outputs
                if led_on = '1' then
                    pins_oe <= cathode_oh or anode_oh;
                    pins    <= anode_oh;
                else
                    pins_oe <= (others => '0');
                    pins    <= (others => '0');
                end if;

            end if;
        end if;
    end process;

end architecture rtl;
