module uart_controller(
    input clk_i, 
    input rst_i, 
    input pc_txdata_i,
    input pc_rxready_i,
    input pc_txready_i, 
    input pc_txvalid_i, 
    input [7:0] pc_data_i, 
    output logic pc_txdata_o
    );
    
    uart_rx
    #(
        .CLK_FREQ(100000000), // 100 MHz
        .BAUD_RATE(115200)
    ) uart_rx_inst (
        .clk(clk_i),
        .rst(rst_i),
        .rxd(rxd),
        .overrun_error(),
        .frame_error(),
    );

    uart_tx 
    #(
        .CLK_FREQ(100000000), // 100 MHz
        .BAUD_RATE(115200)
    ) uart_tx_inst (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .txd(tx_data),
        .busy(fpga_txready),
    );
    
    wire fpga_txd;
    wire fpga_txvalid;
    wire fpga_rxready;
    wire fpga_txready;
    wire fpga_rxvalid;
    wire [7:0] rx_processed;
    logic rxd;
    logic [7:0] tx_data;
    
    wire pc_rx_handshake;
    assign pc_rx_handshake = pc_txready_i & fpga_rxready;
    
    always_comb
    begin
    if(pc_rx_handshake)
    rxd = pc_txdata_i;
    end
    
    wire rx_tx_handshake;
    assign rx_tx_handshake = fpga_txready & fpga_rxready & fpga_rxvalid;
    
    always_comb
    begin
    if(rx_tx_handshake)
    tx_data = rx_processed;
    end
    
    wire tx_pc_handshake;
    assign tx_pc_handshake = pc_rxready_i & fpga_txready & fpga_txvalid;
   
    always_comb
    begin
    if(tx_pc_handshake)
    pc_txd_o = fpga_txd;
    end

    endmodule