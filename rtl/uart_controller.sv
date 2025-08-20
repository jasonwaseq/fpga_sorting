module uart_controller (
    input  logic        clk_i,
    input  logic        rst_i,
    // PC Interface
    input  logic       pc_txvalid_i, // PC has data available
    input  logic [7:0] pc_txdata_i,  // Data from PC
    input  logic       pc_rxready_i, // PC ready to accept
    output logic       pc_rxvalid_o, // Controller has data for PC
    output logic       pc_txready_o, // Controller ready to accept from PC
    output logic [7:0] pc_rxdata_o   // Data to PC
);

    logic        rxd;
    logic        txd;

    logic [7:0]  rx_data;
    logic        rx_valid;
    logic        rx_ready;

    logic [7:0]  tx_data;
    logic        tx_valid;
    logic        tx_ready;

    // ---------------- UART Receiver ----------------
    uart_rx uart_rx_inst (
        .clk_i (clk_i),
        .rst_i (rst_i),
        .rxd_i (rxd),
        .data_o (rx_data),
        .valid_o(rx_valid),
        .ready_i(rx_ready),
    );

    // ---------------- UART Transmitter ----------------
    uart_tx uart_tx_inst (
        .clk_i (clk_i),
        .rst_i (rst_i),
        .data_i (tx_data),
        .valid_i(tx_valid),
        .ready_o(tx_ready),
        .txd_o (txd)
    );

    // ---------------- Handshake Logic ----------------
    // From PC to UART RX
    assign rxd = pc_txvalid_i ? pc_txdata_i[0] : 1'b1;  
   
    // From UART RX to PC
    assign pc_rxvalid_o = rx_valid;
    assign pc_rxdata_o  = rx_data;
    assign rx_ready     = pc_rxready_i;

    // From PC to UART TX
    assign tx_valid     = pc_txvalid_i;
    assign tx_data      = pc_txdata_i;
    assign pc_txready_o = tx_ready;

endmodule
