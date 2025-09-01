`timescale 1ns/1ps

module uart_controller_tb;

    // Testbench clock + reset
    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;   // 100 MHz clock (period = 10 ns)

    // PC interface
    reg  [7:0] pc_data_i;
    reg        pc_valid_i;
    wire       pc_ready_o;

    wire [7:0] pc_data_o;
    wire       pc_valid_o;
    reg        pc_ready_i;

    // UART serial lines
    wire txd;
    wire rxd;

    // Config (prescale = (clk_freq / baud_rate))
    reg [15:0] prescale = 868; // 100e6 / 115200 ≈ 868

    // Connect loopback
    assign rxd = txd;

    // DUT
    uart_controller dut (
        .clk(clk),
        .rst(rst),
        .pc_data_o(pc_data_o),
        .pc_valid_o(pc_valid_o),
        .pc_ready_i(pc_ready_i),
        .pc_data_i(pc_data_i),
        .pc_valid_i(pc_valid_i),
        .pc_ready_o(pc_ready_o),
        .rxd(rxd),
        .txd(txd),
        .prescale(prescale)
    );

    initial begin
        $dumpfile("uart_controller_tb.vcd");   // for GTKWave
        $dumpvars(0, uart_controller_tb);

        // Reset
        #100;
        rst = 0;
        pc_valid_i = 0;
        pc_ready_i = 1; // always ready to accept RX

        // Send a byte
        #200;
        pc_data_i = 8'h55;  // 0x55 = 01010101
        pc_valid_i = 1;

        // Wait until UART accepts it
        @(posedge pc_ready_o);
        pc_valid_i = 0;

        // Wait for it to come back
        wait (pc_valid_o);
        $display("Received byte: %02X", pc_data_o);

        #10000;
        $finish;
    end
endmodule
