create_clock -name core_clk -period 5.0000 [get_ports core_clk]
set_input_delay 1.5000 -clock core_clk [all_inputs -no_clocks]
set_output_delay 1.5000 -clock core_clk [all_outputs]
group_path -name reg2reg -from [all_registers] -to [all_registers]
