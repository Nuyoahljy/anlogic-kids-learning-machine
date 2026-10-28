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
set_max_delay -from [get_regs {u_p14_pipeline/backward/req_meta}] -to [get_regs {u_p14_pipeline/backward/req_sync}] 2.000
set_max_delay -from [get_regs {u_p14_pipeline/backward/ack_meta}] -to [get_regs {u_p14_pipeline/backward/ack_sync}] 2.000
# Bundled payload propagation is audited after routing on this exact database
# without broad clock-group cuts; see report-pixel14-cdc.tcl. No CDC MTBF claim.
# SC520_PIXEL14_CDC_END

# Board-debug mailbox and the actual fault/config synchronizer pairs.
set_max_delay -from [get_regs {u_p14_pipeline/staging_meta}] -to [get_regs {u_p14_pipeline/staging_sync}] 2.000
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

# T-018: SCL is an output waveform, not an internal register clock. Every
# I2C state/counter now uses pll_clk_24m. The asynchronous SDA pad is allowed
# only into the first metastability stage; the second stage stays fully timed.
set_false_path -from [get_ports {IO_cam_sda}] -to [get_regs {u_uicfgcs520/u_i2c/sda_meta}]
set_max_delay -from [get_regs {u_uicfgcs520/u_i2c/sda_meta}] -to [get_regs {u_uicfgcs520/u_i2c/sda_sync}] 2.000
set_max_delay -from [get_regs {u_uicfgcs520/u_i2c/reset_pipe[0]}] -to [get_regs {u_uicfgcs520/u_i2c/reset_pipe[1]}] 2.000

# D036 diagnostic payload handshake; the wildcard covers TD's generated-scope
# separator only. Each exact logical suffix must resolve uniquely in the audit.

# T022 precise asynchronous ingress only; second-stage hold remains analyzed.
# No invented external output/input delay: physical audio timing is not signed off.

# T023 same-domain reset copies. Tighten only the exact first->second stages.
set_max_delay -from [get_regs {S_awb28_meta[0]}] -to [get_regs {S_awb28_sync[0]}] 2.000
set_max_delay -from [get_regs {S_awb28_meta[1]}] -to [get_regs {S_awb28_sync[1]}] 2.000
set_max_delay -from [get_regs {u_p14_pipeline/capture_reset[0]}] -to [get_regs {u_p14_pipeline/capture_reset[1]}] 2.000
set_max_delay -from [get_regs {u_p14_pipeline/capture_reset[0]}] -to [get_regs {u_p14_pipeline/capture_release[0]}] 2.000
set_max_delay -from [get_regs {u_p14_pipeline/capture_reset[0]}] -to [get_regs {u_p14_pipeline/capture_release[1]}] 2.000
set_max_delay -from [get_regs {u_p14_pipeline/capture_reset[0]}] -to [get_regs {u_p14_pipeline/capture_release[2]}] 2.000
set_max_delay -from [get_regs {u_p14_pipeline/capture_reset[0]}] -to [get_regs {u_p14_pipeline/capture_release[3]}] 2.000
set_max_delay -from [get_regs {u_p14_pipeline/capture_reset[0]}] -to [get_regs {u_p14_pipeline/capture_release[4]}] 2.000
set_max_delay -from [get_regs {u_p14_pipeline/capture_reset[0]}] -to [get_regs {u_p14_pipeline/capture_release[5]}] 2.000
set_false_path -from [get_ports {I_style_switches[0]}] -to [get_regs {style_inputs/meta[0]}]
set_max_delay -from [get_regs {style_inputs/meta[0]}] -to [get_regs {style_inputs/sync[0]}] 2.000
set_false_path -from [get_ports {I_style_switches[1]}] -to [get_regs {style_inputs/meta[1]}]
set_max_delay -from [get_regs {style_inputs/meta[1]}] -to [get_regs {style_inputs/sync[1]}] 2.000
# I0310 SW4/D11 asynchronous input: cut only pad -> first stage and retain
# the synchronizer's second-stage setup/hold analysis.
set_false_path -from [get_ports {I_awb_recalibrate}] -to [get_regs {awb_retrigger/switch_meta}]
set_max_delay -from [get_regs {awb_retrigger/switch_meta}] -to [get_regs {awb_retrigger/switch_sync}] 2.000
set_max_delay -from [get_regs {S_awb_busy_sync[0]}] -to [get_regs {S_awb_busy_sync[1]}] 2.000
set_max_delay -from [get_regs {cal_reset[0]}] -to [get_regs {cal_reset[1]}] 2.000
set_max_delay -from [get_regs {u_p14_pipeline/display_reset[0]}] -to [get_regs {u_p14_pipeline/display_reset[1]}] 2.000
set_max_delay -from [get_regs {S_awb28_meta[2]}] -to [get_regs {S_awb28_sync[2]}] 2.000
set_max_delay -from [get_regs {S_addon_reset[0]}] -to [get_regs {S_addon_reset[1]}] 2.000
# TF MISO retains A022 source-synchronous SPI semantics; no blanket cut/multicycle.
set_false_path -from [get_regs {S_ui_cfg_ready_24m}] -to [get_regs {S_awb28_meta[2]}]
