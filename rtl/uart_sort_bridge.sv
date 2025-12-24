`timescale 1ns/1ps
module uart_sort_bridge #(
    parameter int VALUE_WIDTH = 10,
    parameter int COUNT_WIDTH = 16
) (
    input  logic clk_i,
    input  logic reset_i,
    input  logic [7:0] rx_data_i,
    input  logic       rx_valid_i,
    output logic       rx_ready_o,
    output logic [7:0] tx_data_o,
    output logic       tx_valid_o,
    input  logic       tx_ready_i,
    output logic       busy_o
);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_HDR,
        ST_INPUT,
        ST_OUTPUT
    } state_e;

    state_e state_r, state_n;
    state_e state_prev_r;

    logic [15:0] length_r;
    logic        length_valid_r;
    logic [17:0] output_byte_count_r;
    logic [17:0] output_bytes_sent_r;
    logic        header_done_r;
    logic        header_queued_r;
    logic [7:0]  input_low_byte_r;
    logic [15:0] input_count_r;

    logic start_pulse_r;
    logic [3:0] start_hold_r;
    logic start_pulse;  // Declare before using in assign

    // Incoming value FIFO (assembled 10-bit values)
    localparam int FIFO_DEPTH = 16;
    localparam int FIFO_AW    = $clog2(FIFO_DEPTH);
    logic [VALUE_WIDTH-1:0] fifo_mem [0:FIFO_DEPTH-1];
    logic [FIFO_AW-1:0] fifo_wr_ptr, fifo_rd_ptr;
    logic [FIFO_AW:0]   fifo_count;
    logic fifo_full, fifo_empty;
    logic fifo_out_valid;
    logic [VALUE_WIDTH-1:0] fifo_out_value;

    assign fifo_full      = (fifo_count == FIFO_DEPTH);
    assign fifo_empty     = (fifo_count == 0);
    assign fifo_out_valid = !fifo_empty;
    assign fifo_out_value = fifo_mem[fifo_rd_ptr];

    // Sorter interface
    logic [VALUE_WIDTH-1:0] sorter_input_value;
    logic [VALUE_WIDTH-1:0] sorter_output_value;
    logic sorter_output_valid;
    logic sorter_input_ready;

    // Output byte FIFO to decouple TX handshakes
    localparam int OUT_FIFO_DEPTH = 64;
    localparam int OUT_FIFO_AW    = $clog2(OUT_FIFO_DEPTH);
    logic [7:0] out_fifo_mem [0:OUT_FIFO_DEPTH-1];
    logic [OUT_FIFO_AW-1:0] out_wr_ptr, out_rd_ptr;
    logic [OUT_FIFO_AW:0]   out_count;
    logic [OUT_FIFO_AW-1:0] out_wr_ptr_t, out_rd_ptr_t;
    logic [OUT_FIFO_AW:0]   out_count_t;
    // Temporaries for multi-push operations
    logic [OUT_FIFO_AW-1:0] tmp_wr_ptr;
    logic [OUT_FIFO_AW:0]   tmp_count;
    logic out_fifo_full, out_fifo_empty;
    assign out_fifo_full  = (out_count == OUT_FIFO_DEPTH);
    assign out_fifo_empty = (out_count == 0);

    assign sorter_input_value = fifo_out_value;
    assign busy_o = (state_r != ST_IDLE);
    assign start_pulse = start_pulse_r | (|start_hold_r);

    radix_sorter #(
        .VALUE_WIDTH(VALUE_WIDTH),
        .COUNT_WIDTH(COUNT_WIDTH)
    ) sorter (
        .clk_i(clk_i),
        .reset_i(reset_i),
        .start_i(start_pulse),
        .length_i(length_r),
        .value_i(sorter_input_value),
        // Feed sorter from a buffered pair; decouple RX from sorter readiness
        .value_valid_i(fifo_out_valid && sorter_input_ready),
        .value_ready_o(sorter_input_ready),
        .sorted_value_o(sorter_output_value),
        .sorted_valid_o(sorter_output_valid),
        .sorted_ready_i((state_r == ST_OUTPUT) && (out_count <= OUT_FIFO_DEPTH-2)),
        .busy_o(),
        .done_o()
    );

    always @(*) begin
        state_n = state_r;
        rx_ready_o = 1'b0;

        case (state_r)
            ST_IDLE: begin
                rx_ready_o = 1'b1;  // Ready to receive first length byte
                if (rx_valid_i) state_n = ST_HDR;
            end
            
            ST_HDR: begin
                rx_ready_o = 1'b1;  // capture high length byte
                if (length_valid_r && header_done_r) begin
                    if (length_r == 16'd0) begin
                        state_n = ST_OUTPUT;
                    end else begin
                        state_n = ST_INPUT;
                    end
                end
            end
            
            ST_INPUT: begin
                // Ready only if FIFO has space
                rx_ready_o = !fifo_full;
                // If no payload, jump to output once header is sent
                if ((length_r == 16'd0) && header_done_r) begin
                    state_n = ST_OUTPUT;
                end else begin
                    // Move to output after receiving all payload bytes
                    if (input_count_r >= (length_r << 1)) begin
                        state_n = ST_OUTPUT;
                    end
                end
            end
            
            ST_OUTPUT: begin
                if (output_bytes_sent_r >= output_byte_count_r && !tx_valid_o && out_fifo_empty) begin
                    state_n = ST_IDLE;
                end
            end
            
            default: state_n = ST_IDLE;
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            state_r <= ST_IDLE;
            length_r <= '0;
            output_byte_count_r <= '0;
            output_bytes_sent_r <= '0;
            header_done_r <= 1'b0;
            header_queued_r <= 1'b0;
            length_valid_r <= 1'b0;
            input_low_byte_r <= '0;
            input_count_r <= '0;
            start_pulse_r <= 1'b0;
            start_hold_r <= '0;
            tx_data_o <= '0;
            tx_valid_o <= 1'b0;
            fifo_wr_ptr <= '0;
            fifo_rd_ptr <= '0;
            fifo_count  <= '0;
            out_wr_ptr <= '0;
            out_rd_ptr <= '0;
            out_count  <= '0;
        end else begin
            // temporaries for FIFO updates
            out_wr_ptr_t = out_wr_ptr;
            out_rd_ptr_t = out_rd_ptr;
            out_count_t  = out_count;
            tmp_wr_ptr   = '0;
            tmp_count    = '0;

            state_prev_r <= state_r;
            state_r <= state_n;
            start_pulse_r <= 1'b0;

            if (start_hold_r != '0) begin
                start_hold_r <= start_hold_r - 1'b1;
            end

            case (state_r)
                ST_IDLE: begin
                    input_count_r <= '0;
                    output_bytes_sent_r <= '0;
                    header_done_r <= 1'b0;
                    header_queued_r <= 1'b0;
                    length_valid_r <= 1'b0;
                    // Clear output FIFO
                    out_wr_ptr <= '0;
                    out_rd_ptr <= '0;
                    out_count  <= '0;
                    // Capture first length byte when entering from IDLE
                    if (rx_valid_i && rx_ready_o) begin
                        length_r[7:0] <= rx_data_i;
                    end
                end
                
                ST_HDR: begin
                    // Pulse sorter start after length is captured
                    if (length_valid_r && !start_pulse_r && start_hold_r == '0) begin
                        start_pulse_r <= 1'b1;
                        start_hold_r <= 4'h3;
                    end
                    if (rx_valid_i && rx_ready_o) begin
                        // Capture MSB and enqueue both header bytes once
                        length_r[15:8] <= rx_data_i;
                        // Compute total bytes (header + values)
                        output_byte_count_r <= 18'h2 + ({rx_data_i, length_r[7:0]} << 1);
                        // Enqueue header bytes exactly once
                        if (!header_queued_r && !out_fifo_full) begin
                            tmp_wr_ptr = out_wr_ptr_t;
                            tmp_count  = out_count_t;
                            // low byte
                            out_fifo_mem[tmp_wr_ptr] <= length_r[7:0];
                            tmp_wr_ptr = tmp_wr_ptr + 1'b1;
                            tmp_count  = tmp_count + 1'b1;
                            // high byte (captured this cycle)
                            out_fifo_mem[tmp_wr_ptr] <= rx_data_i;
                            tmp_wr_ptr = tmp_wr_ptr + 1'b1;
                            tmp_count  = tmp_count + 1'b1;
                            out_wr_ptr_t = tmp_wr_ptr;
                            out_count_t  = tmp_count;
                            header_queued_r <= 1'b1;
                            header_done_r   <= 1'b1;
                            length_valid_r  <= 1'b1;
                        end
                    end
                end
                
                ST_INPUT: begin
                    if (rx_valid_i && rx_ready_o) begin
                        input_count_r <= input_count_r + 1'b1;
                        if (input_count_r[0] == 1'b0) begin
                            // Low byte - save it
                            input_low_byte_r <= rx_data_i;
                        end else begin
                            // High byte - form complete value and push to FIFO
                            if (!fifo_full) begin
                                fifo_mem[fifo_wr_ptr] <= {rx_data_i[1:0], input_low_byte_r};
                                fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
                                fifo_count <= fifo_count + 1'b1;
                            end
                        end
                    end

                end
                
                // No separate sorting state; output is produced while sorting proceeds
                
                ST_OUTPUT: begin
                    // Queue sorted values as bytes when FIFO has room
                    if (sorter_output_valid && (out_count_t <= OUT_FIFO_DEPTH-2)) begin
                        tmp_wr_ptr = out_wr_ptr_t;
                        tmp_count  = out_count_t;
                        // low byte
                        out_fifo_mem[tmp_wr_ptr] <= sorter_output_value[7:0];
                        tmp_wr_ptr = tmp_wr_ptr + 1'b1;
                        tmp_count  = tmp_count + 1'b1;
                        // high byte (top 2 bits)
                        out_fifo_mem[tmp_wr_ptr] <= {6'd0, sorter_output_value[VALUE_WIDTH-1:8]};
                        tmp_wr_ptr = tmp_wr_ptr + 1'b1;
                        tmp_count  = tmp_count + 1'b1;
                        out_wr_ptr_t = tmp_wr_ptr;
                        out_count_t  = tmp_count;
                        // consumed one sorted value implicitly via sorted_ready_i
                    end
                end
                
                default: ;
            endcase

            // Pop from input FIFO when sorter consumes a value
            if (fifo_out_valid && sorter_input_ready) begin
                fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
                if (fifo_count != 0) fifo_count <= fifo_count - 1'b1;
            end

            // Drive UART TX from output FIFO (active in all states)
            if (!tx_valid_o && !out_fifo_empty) begin
                tx_data_o <= out_fifo_mem[out_rd_ptr];
                tx_valid_o <= 1'b1;
            end else if (tx_valid_o && tx_ready_i) begin
                // Byte accepted; pop
                tx_valid_o <= 1'b0;
                out_rd_ptr_t = out_rd_ptr_t + 1'b1;
                if (out_count_t != 0) out_count_t = out_count_t - 1'b1;
                output_bytes_sent_r <= output_bytes_sent_r + 1'b1;
            end

            // Commit accumulated FIFO pointer/count updates
            out_wr_ptr <= out_wr_ptr_t;
            out_rd_ptr <= out_rd_ptr_t;
            out_count  <= out_count_t;
        end
    end

endmodule
