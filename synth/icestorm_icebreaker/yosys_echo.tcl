yosys read_verilog synth/build/rtl.sv2v.v
yosys synth_ice40 -top top_uart_echo -json synth/icestorm_icebreaker/build/synth_echo.json
