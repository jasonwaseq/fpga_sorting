module uart_controller (
    input  logic clk,
    input  logic rst,

    // PC Interface
    output logic [7:0] pc_data_o,
    output logic       pc_valid_o,
    input  logic       pc_ready_i,

    input  logic [7:0] pc_data_i,
    input  logic       pc_valid_i,
    output logic       pc_ready_o,

    // UART Serial Pins
    input  logic rxd,
    output logic txd,

    // Config
    input  logic [15:0] prescale
);

    // UART Receiver
    uart_rx uart_rx_inst (
        .clk(clk),
        .rst(rst),
        .m_axis_tdata (pc_data_o),
        .m_axis_tvalid(pc_valid_o),
        .m_axis_tready(pc_ready_i),
        .rxd(rxd),
        .prescale(prescale)
    );

    // UART Transmitter 
    uart_tx uart_tx_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata (pc_data_i),
        .s_axis_tvalid(pc_valid_i),
        .s_axis_tready(pc_ready_o),
        .txd(txd),
        .prescale(prescale)
    );

endmodule
