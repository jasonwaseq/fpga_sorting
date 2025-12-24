# FPGA Sorting Hardware Accelerator

# How to Run
To open OSS-CAD-SUITE, and other open-source tools, run "source startup.sh", which will start a venv which has all the tools downloaded. You'll be able to run Verilator, Vivado, nextpnr, sv2v, etc...

A full end-to-end FPGA radix sorter on the iCE40 FPGA, architecting a UART-facing bridge with ready/valid handshakes, a read-priority synchronous FIFO, and a counting-sort core over 1024 buckets in block RAM, then closed timing at 12 MHz with only ~16% LUT utilization. Hardened correctness by fixing RAM read-after-write hazards and FIFO push/pop races, widened the output FIFO to sustain 100+ byte bursts, and validated behavior with a comprehensive testbench plus Python hardware harnesses that capture precise round-trip timing. The build flow (sv2v → yosys → nextpnr → icepack) and interactive scripts now produce a ready-to-flash bitstream and reproducible hardware tests.