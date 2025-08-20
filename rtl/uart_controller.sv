module uart_controller (
    input  logic       clk_i,
    input  logic       rst_i,

    // PC Interface
    input  logic       pc_txvalid_i, // PC has data available
    input  logic [7:0] pc_txdata_i,  // Data from PC to send over UART
    input  logic       pc_rxready_i, // PC ready to accept data
    output logic       pc_txready_o, // Controller ready to accept from PC
    output logic       pc_rxvalid_o, // Controller has data for PC
    output logic [7:0] pc_rxdata_o,  // Data received from UART
       
    // UART Serial Pins
    input  logic       rxd_i,        // UART RX serial line
    output logic       txd_o         // UART TX serial line
);

    // Internal RX signals 
    logic [7:0] rx_data;
    logic       rx_valid;
    logic       rx_ready;

    // Internal TX signals
    logic [7:0] tx_data;
    logic       tx_valid;
    logic       tx_ready;

    // UART Receiver
    uart_rx uart_rx_inst (
        .clk_i   (clk_i),
        .rst_i   (rst_i),
        .rxd_i   (rxd_i),
        .data_o  (rx_data),  // received byte
        .valid_o (rx_valid), // byte is valid
        .ready_i (rx_ready)  // controller/PC ready to take byte
    );

    // UART Transmitter 
    uart_tx uart_tx_inst (
        .clk_i   (clk_i),
        .rst_i   (rst_i),
        .data_i  (tx_data),  // byte to transmit
        .valid_i (tx_valid), // request to send
        .ready_o (tx_ready), // UART ready for new byte
        .txd_o   (txd_o)
    );

    // Handshake Logic
    // UART RX → PC
    assign pc_rxvalid_o = rx_valid;
    assign pc_rxdata_o  = rx_data;
    assign rx_ready     = pc_rxready_i;

    // PC → UART TX
    assign tx_valid     = pc_txvalid_i;
    assign tx_data      = pc_txdata_i;
    assign pc_txready_o = tx_ready;

endmodule
