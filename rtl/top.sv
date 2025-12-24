`timescale 1ns/1ps
module top (
    input  logic clk,
    
    // UART pins
    input  logic rxd,
    output logic txd
);

    localparam logic [15:0] PRESCALE = 16'd13; // 115200 baud at 12 MHz (12MHz/(115200*8)=13)

    // Simple power-on reset (synchronous) to remove external reset pin
    // Power-on reset counter; initialize to 0 for simulation determinism
    logic [3:0] por_cnt = 4'd0;
    logic       rst_sync;
    always_ff @(posedge clk) begin
        if (&por_cnt) begin
            por_cnt <= por_cnt;
        end else begin
            por_cnt <= por_cnt + 1'b1;
        end
    end
    assign rst_sync = ~&por_cnt;

    logic [7:0] rx_data, tx_data;
    logic rx_valid, rx_ready;
    logic tx_valid, tx_ready;

    uart uart_inst (
        .clk(clk),
        .rst(rst_sync),
        .m_axis_tdata(rx_data),
        .m_axis_tvalid(rx_valid),
        .m_axis_tready(rx_ready),
        .s_axis_tdata(tx_data),
        .s_axis_tvalid(tx_valid),
        .s_axis_tready(tx_ready),
        .rxd(rxd),
        .txd(txd),
        .prescale(PRESCALE)
    );

    uart_sort_bridge #(
        .VALUE_WIDTH(10),
        .COUNT_WIDTH(16)
    ) sorter_bridge (
        .clk_i(clk),
        .reset_i(rst_sync),
        .rx_data_i(rx_data),
        .rx_valid_i(rx_valid),
        .rx_ready_o(rx_ready),
        .tx_data_o(tx_data),
        .tx_valid_o(tx_valid),
        .tx_ready_i(tx_ready),
        .busy_o()
    );

endmodule