// Top-level module with UART
module top (
    input  logic clk,
    input  logic rst,
    
    // UART pins
    input  logic rxd,
    output logic txd,
    
    // Config
    input  logic [15:0] prescale
);

    logic [7:0] rx_data, tx_data;
    logic rx_valid, rx_ready;
    logic tx_valid, tx_ready;
    
    // UART Controller
    uart_controller uart_ctrl (
        .clk(clk),
        .rst(rst),
        .pc_data_o(rx_data),
        .pc_valid_o(rx_valid),
        .pc_ready_i(rx_ready),
        .pc_data_i(tx_data),
        .pc_valid_i(tx_valid),
        .pc_ready_o(tx_ready),
        .rxd(rxd),
        .txd(txd),
        .prescale(prescale)
    );
    
    // Insertion Sorter
    insertion_sorter #(
        .WIDTH(8),
        .DEPTH(10),
        .DEPTH_LOG2(4)
    ) sorter (
        .clk_i(clk),
        .reset_i(rst),
        .data_i(rx_data),
        .valid_i(rx_valid),
        .ready_o(rx_ready),
        .data_o(tx_data),
        .valid_o(tx_valid),
        .ready_i(tx_ready)
    );

endmodule