create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {mipi_rx_ck_pad} -period 2.415 -waveform {0.000 1.208} [get_nets {IO_rx_clk_pad_p}]

derive_clocks

rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]

rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]


set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m HDMI_PIXEL_CLK HDMI_SERIAL_CLK}] \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]

# SC520_BOARD_KEYS_BEGIN
# K1..K4 are asynchronous, active-low inputs. Exempt only port -> first REG.
# Do not exempt the meta -> safe paths or the safe -> debounce logic.
# Logical get_regs names survive TD's packing of two FFs into one LSLICE.
# Gate-only *_reg[i].d/cell names do not survive that physical conversion.
set_false_path -from [get_ports {I_quiz_keys_n[0]}] -to [get_regs {u_quiz_keys/keys_sync_meta[0]}]
set_false_path -from [get_ports {I_quiz_keys_n[1]}] -to [get_regs {u_quiz_keys/keys_sync_meta[1]}]
set_false_path -from [get_ports {I_quiz_keys_n[2]}] -to [get_regs {u_quiz_keys/keys_sync_meta[2]}]
set_false_path -from [get_ports {I_quiz_keys_n[3]}] -to [get_regs {u_quiz_keys/keys_sync_meta[3]}]
# A tighter same-clock setup budget encourages short synchronizer routing.
# Deliberately omit -datapath_only: in TD it also exempts hold analysis.
set_max_delay -from [get_regs {u_quiz_keys/keys_sync_meta[0]}] -to [get_regs {u_quiz_keys/keys_sync_safe[0]}] 2.000
set_max_delay -from [get_regs {u_quiz_keys/keys_sync_meta[1]}] -to [get_regs {u_quiz_keys/keys_sync_safe[1]}] 2.000
set_max_delay -from [get_regs {u_quiz_keys/keys_sync_meta[2]}] -to [get_regs {u_quiz_keys/keys_sync_safe[2]}] 2.000
set_max_delay -from [get_regs {u_quiz_keys/keys_sync_meta[3]}] -to [get_regs {u_quiz_keys/keys_sync_safe[3]}] 2.000
# SC520_BOARD_KEYS_END

# SC520_PIXEL14_CDC_BEGIN: preserve hold analysis on same-domain synchronizers.
set_max_delay -from [get_regs {u_p14_pipeline/forward/req_meta}] -to [get_regs {u_p14_pipeline/forward/req_sync}] 2.000
set_max_delay -from [get_regs {u_p14_pipeline/forward/ack_meta}] -to [get_regs {u_p14_pipeline/forward/ack_sync}] 2.000
set_max_delay -from [get_regs {u_p14_pipeline/forward/fault_meta}] -to [get_regs {u_p14_pipeline/forward/fault_sync}] 2.000
set_max_delay -from [get_regs {u_p14_pipeline/backward/req_meta}] -to [get_regs {u_p14_pipeline/backward/req_sync}] 2.000
set_max_delay -from [get_regs {u_p14_pipeline/backward/ack_meta}] -to [get_regs {u_p14_pipeline/backward/ack_sync}] 2.000
set_max_delay -from [get_regs {u_p14_pipeline/backward/fault_meta}] -to [get_regs {u_p14_pipeline/backward/fault_sync}] 2.000
# Bundled payload propagation is audited after routing on this exact database
# without broad clock-group cuts; see report-pixel14-cdc.tcl. No CDC MTBF claim.
# SC520_PIXEL14_CDC_END

# Board-debug mailbox and the actual fault/config synchronizer pairs.
set_max_delay -from [get_regs {u_p14_diag_cdc/req_meta}] -to [get_regs {u_p14_diag_cdc/req_sync}] 2.000
set_max_delay -from [get_regs {u_p14_diag_cdc/ack_meta}] -to [get_regs {u_p14_diag_cdc/ack_sync}] 2.000
set_max_delay -from [get_regs {u_p14_pipeline/staging_fault_meta}] -to [get_regs {u_p14_pipeline/staging_fault_sync}] 2.000
set_max_delay -from [get_regs {S_p14_cfg_done[0]}] -to [get_regs {S_p14_cfg_done[1]}] 2.000
set_max_delay -from [get_regs {S_p14_cfg_error[0]}] -to [get_regs {S_p14_cfg_error[1]}] 2.000

# I2C completion crosses into the configuration clock before use. The atomic
# diagnostic mailbox then transfers the held word from 24 MHz to MIPI.
set_max_delay -from [get_regs {u_uicfgcs520/busy_meta}] -to [get_regs {u_uicfgcs520/busy_sync}] 2.000
set_max_delay -from [get_regs {u_uicfgcs520/error_meta}] -to [get_regs {u_uicfgcs520/error_sync}] 2.000

# The diagnostic mailbox deliberately uses a handshake between these PLL outputs.
# Exempt only its crossing nets; keep both same-clock synchronizer stages timed.
# The held payload remains unchanged until acknowledgement; routed propagation
# is checked per physical bit in the independent unconstrained mailbox report.
set_false_path -from [get_clocks {pll_clk_24m}] -through [get_nets {u_p14_i2c_cdc/request}] -to [get_clocks {HDMI_PIXEL_CLK}]
set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] -through [get_nets {u_p14_i2c_cdc/acknowledge}] -to [get_clocks {pll_clk_24m}]
set_false_path -from [get_clocks {pll_clk_24m}] -through [get_nets {u_p14_i2c_cdc/held_data*}] -to [get_clocks {HDMI_PIXEL_CLK}]
set_max_delay -from [get_regs {u_p14_i2c_cdc/req_meta}] -to [get_regs {u_p14_i2c_cdc/req_sync}] 2.000
set_max_delay -from [get_regs {u_p14_i2c_cdc/ack_meta}] -to [get_regs {u_p14_i2c_cdc/ack_sync}] 2.000
