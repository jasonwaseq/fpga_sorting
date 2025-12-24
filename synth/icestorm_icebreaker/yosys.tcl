yosys read_verilog synth/build/rtl.sv2v.v
yosys synth_ice40 -top top -json synth/icestorm_icebreaker/build/synth.json
