module top(
    input  logic clk,
    input  logic rst,
    input  logic rxd,
    output logic txd,
    input  logic [15:0] prescale
);

    // Wires for UART <-> Bubble Sort
    logic [7:0] rx_data;
    logic       rx_valid, rx_ready;
    logic [7:0] tx_data;
    logic       tx_valid, tx_ready;

    // Instantiate UART
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

    // Bubble Sort signals
    parameter N = 8;
    logic [7:0] buffer_in [N-1:0];
    logic [7:0] buffer_out[N-1:0];
    logic start, done;
    int count;

    bubble_sort #(.N(N)) sorter (
        .clk(clk),
        .rst(rst),
        .start(start),
        .data_in(buffer_in),
        .data_out(buffer_out),
        .done(done)
    );

    // Control FSM: Collect -> Sort -> Transmit
    typedef enum logic [1:0] {WAIT_DATA, SORTING, SEND_BACK} sys_state_t;
    sys_state_t sys_state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sys_state <= WAIT_DATA;
            count     <= 0;
            start     <= 0;
            tx_valid  <= 0;
        end else begin
            case (sys_state)
                WAIT_DATA: begin
                    if (rx_valid) begin
                        buffer_in[count] <= rx_data;
                        count <= count + 1;
                        if (count == N-1) begin
                            start <= 1;
                            sys_state <= SORTING;
                        end
                    end
                end
                SORTING: begin
                    start <= 0;
                    if (done) begin
                        count <= 0;
                        sys_state <= SEND_BACK;
                    end
                end
                SEND_BACK: begin
                    if (tx_ready) begin
                        tx_data  <= buffer_out[count];
                        tx_valid <= 1;
                        count    <= count + 1;
                        if (count == N) begin
                            tx_valid <= 0;
                            sys_state <= WAIT_DATA;
                            count <= 0;
                        end
                    end else begin
                        tx_valid <= 0;
                    end
                end
            endcase
        end
    end
endmodule
