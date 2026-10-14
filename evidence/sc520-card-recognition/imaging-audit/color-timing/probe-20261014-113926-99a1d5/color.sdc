create_clock -name CORE_CLK -period 9.660 [get_ports clk]
set_input_delay -clock CORE_CLK 0.000 [get_ports {pixel_byte* sof eol valid rst_n}]
set_output_delay -clock CORE_CLK 0.000 [all_outputs]
