module uart_controller (
    input logic clk_i,
    input logic rst_i,

    // PC Interface
    input  logic pc_txvalid_i, // PC has data available
    output logic pc_rxready_o, // PC ready to accept data
       
    // UART Serial Pins
    input  logic rxd_i, // UART RX serial line
    output logic txd_o  // UART TX serial line
);
    logic [7:0] data;
    logic rx_valid;
    
    // UART Receiver
    uart_rx uart_rx_inst (
        .clk_i   (clk_i),
        .rst_i   (rst_i),
        .rxd_i   (rxd_i),
        .data_o  (data), // received byte
        .valid_o (rx_valid), // byte is valid
        .ready_i (pc_txvalid_i) // controller/PC ready to take byte
    );

    // UART Transmitter 
    uart_tx uart_tx_inst (
        .clk_i   (clk_i),
        .rst_i   (rst_i),
        .data_i  (data), // byte to transmit
        .valid_i (rx_valid), // request to send
        .ready_o (pc_rxready_o), // UART ready for new byte
        .txd_o   (txd_o)
    );

endmodule