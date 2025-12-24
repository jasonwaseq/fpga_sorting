`timescale 1ns/1ps
// Comprehensive testbench covering all hardware test scenarios

module testbench_comprehensive;
    reg clk = 0;
    always #41.666 clk = ~clk;  // 12 MHz

    wire rxd, txd;

    // Host-side UART TX
    reg  [7:0] host_tx_data;
    reg        host_tx_valid;
    wire       host_tx_ready;
    wire       host_tx_busy;

    uart_tx #(.DATA_WIDTH(8)) host_uart_tx (
        .clk(clk), .rst(1'b0),
        .s_axis_tdata(host_tx_data),
        .s_axis_tvalid(host_tx_valid),
        .s_axis_tready(host_tx_ready),
        .txd(rxd), .busy(host_tx_busy),
        .prescale(16'd13)
    );

    // Host-side UART RX
    wire [7:0] host_rx_data;
    wire       host_rx_valid;
    reg        host_rx_ready = 1'b1;

    uart_rx #(.DATA_WIDTH(8)) host_uart_rx (
        .clk(clk), .rst(1'b0),
        .m_axis_tdata(host_rx_data),
        .m_axis_tvalid(host_rx_valid),
        .m_axis_tready(host_rx_ready),
        .rxd(txd), .busy(), .overrun_error(), .frame_error(),
        .prescale(16'd13)
    );

    // DUT
    top dut (
        .clk(clk),
        .rxd(rxd),
        .txd(txd)
    );

    // RX buffer
    reg [7:0] rx_buf [0:1023];
    integer rx_wr = 0;

    always @(posedge clk) begin
        if (host_rx_valid && host_rx_ready) begin
            rx_buf[rx_wr] <= host_rx_data;
            rx_wr <= rx_wr + 1;
        end
    end

    task send_byte(input [7:0] b);
    begin
        @(posedge clk);
        while (!host_tx_ready) @(posedge clk);
        host_tx_data  <= b;
        host_tx_valid <= 1'b1;
        @(posedge clk);
        host_tx_valid <= 1'b0;
        while (host_tx_busy) @(posedge clk);
    end
    endtask

    task send_value(input [9:0] val);
    begin
        send_byte(val[7:0]);
        send_byte({6'd0, val[9:8]});
    end
    endtask

    function [9:0] decode_val(input integer idx);
    begin
        decode_val = {rx_buf[idx+1][1:0], rx_buf[idx]};
    end
    endfunction

    // Test data storage
    reg [9:0] test_vals [0:63];
    reg [9:0] test_expected [0:63];

    task run_test(input [127:0] name, input integer n);
    integer i, j;
    reg [9:0] got;
    integer errors;
    begin
        $display("\n======================================================================");
        $display("TEST: %0s", name);
        $display("======================================================================");
        
        rx_wr = 0;
        
        // Send length
        send_byte(n[7:0]);
        send_byte(n[15:8]);
        
        // Send values
        for (i = 0; i < n; i = i + 1) begin
            send_value(test_vals[i]);
        end
        
        // Wait for processing (scaled by number of values)
        // Wait generously for: clear, load, scan, emit, and UART TX
        // UART at 115200 baud = ~1040 clocks/byte at 12MHz with prescale 13
        // Large margin for clustered duplicates
        repeat (50000 + n*20000) @(posedge clk);
        
        // Check header
        if (rx_wr < 2) begin
            $display("❌ FAIL: No header received (got %0d bytes)", rx_wr);
            $fatal(1);
        end
        
        if ({rx_buf[1], rx_buf[0]} != n) begin
            $display("❌ FAIL: Length mismatch: got %0d, expected %0d", {rx_buf[1], rx_buf[0]}, n);
            $fatal(1);
        end
        
        // Check payload
        if (rx_wr < (2 + 2*n)) begin
            $display("❌ FAIL: Incomplete payload: got %0d bytes, expected %0d", rx_wr, 2+2*n);
            $display("Received header: 0x%02x 0x%02x (length=%0d)", rx_buf[0], rx_buf[1], {rx_buf[1], rx_buf[0]});
            for (j = 2; j < rx_wr; j = j + 2) begin
                if (j+1 < rx_wr)
                    $display("  Value[%0d] = %0d (0x%02x 0x%02x)", (j-2)/2, decode_val(j), rx_buf[j], rx_buf[j+1]);
                else
                    $display("  Value[%0d] = incomplete (0x%02x)", (j-2)/2, rx_buf[j]);
            end
            $fatal(1);
        end
        
        // Verify sorted values
        errors = 0;
        for (i = 0; i < n; i = i + 1) begin
            got = decode_val(2 + i*2);
            if (got != test_expected[i]) begin
                $display("❌ Value[%0d]: got %0d, expected %0d", i, got, test_expected[i]);
                errors = errors + 1;
            end
        end
        
        if (errors > 0) begin
            $display("❌ FAIL: %0d value(s) incorrect", errors);
            $fatal(1);
        end else begin
            $display("✅ PASS: All %0d values correctly sorted", n);
        end
    end
    endtask

    integer i;

    initial begin
        host_tx_valid = 0;
        repeat (200) @(posedge clk);

        // Test 1: Basic [5,4,1]
        test_vals[0] = 5; test_vals[1] = 4; test_vals[2] = 1;
        test_expected[0] = 1; test_expected[1] = 4; test_expected[2] = 5;
        run_test("Basic sorting [5,4,1]", 3);

        // Test 2: Duplicates [5,2,5,1,5,2]
        test_vals[0] = 5; test_vals[1] = 2; test_vals[2] = 5;
        test_vals[3] = 1; test_vals[4] = 5; test_vals[5] = 2;
        test_expected[0] = 1; test_expected[1] = 2; test_expected[2] = 2;
        test_expected[3] = 5; test_expected[4] = 5; test_expected[5] = 5;
        run_test("Duplicates [5,2,5,1,5,2]", 6);

        // Test 3: All same [100,100,100]
        test_vals[0] = 100; test_vals[1] = 100; test_vals[2] = 100;
        test_expected[0] = 100; test_expected[1] = 100; test_expected[2] = 100;
        run_test("All same value [100,100,100]", 3);

        // Test 4: Max values [1023,0,511,256]
        test_vals[0] = 1023; test_vals[1] = 0; test_vals[2] = 511; test_vals[3] = 256;
        test_expected[0] = 0; test_expected[1] = 256; test_expected[2] = 511; test_expected[3] = 1023;
        run_test("Max 10-bit values", 4);

        // Test 5: Empty dataset
        run_test("Empty dataset", 0);

        // Test 6: Single value
        test_vals[0] = 42;
        test_expected[0] = 42;
        run_test("Single value [42]", 1);

        // Test 7: Large dataset (20 values)
        test_vals[0] = 853; test_vals[1] = 20; test_vals[2] = 611; test_vals[3] = 754;
        test_vals[4] = 396; test_vals[5] = 553; test_vals[6] = 893; test_vals[7] = 331;
        test_vals[8] = 764; test_vals[9] = 254; test_vals[10] = 886; test_vals[11] = 534;
        test_vals[12] = 357; test_vals[13] = 382; test_vals[14] = 726; test_vals[15] = 186;
        test_vals[16] = 844; test_vals[17] = 341; test_vals[18] = 303; test_vals[19] = 421;
        test_expected[0] = 20; test_expected[1] = 186; test_expected[2] = 254; test_expected[3] = 303;
        test_expected[4] = 331; test_expected[5] = 341; test_expected[6] = 357; test_expected[7] = 382;
        test_expected[8] = 396; test_expected[9] = 421; test_expected[10] = 534; test_expected[11] = 553;
        test_expected[12] = 611; test_expected[13] = 726; test_expected[14] = 754; test_expected[15] = 764;
        test_expected[16] = 844; test_expected[17] = 853; test_expected[18] = 886; test_expected[19] = 893;
        run_test("Large dataset (20 values)", 20);

        $display("\n======================================================================");
        $display("✅ ALL TESTS PASSED");
        $display("======================================================================");
        $finish;
    end
endmodule
