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

    logic [15:0] length_r;
    logic        length_valid_r;
    logic [17:0] output_byte_count_r;
    logic [17:0] output_bytes_sent_r;
    logic        header_sent_r;  // Track if both header bytes sent
    logic [7:0]  input_low_byte_r;
    logic [15:0] input_count_r;
    logic        output_byte_phase_r;  // 0=low byte, 1=high byte
    logic [VALUE_WIDTH-1:0] output_value_hold_r;  // Hold sorted value for 2-byte output

    logic start_pulse_r;
    logic [3:0] start_hold_r;
    logic start_pulse;

    // Input value FIFO (10-bit values)
    logic [VALUE_WIDTH-1:0] in_fifo_data;
    logic in_fifo_valid;
    logic in_fifo_ready;
    logic [VALUE_WIDTH-1:0] in_fifo_out;
    logic in_fifo_out_valid;
    logic in_fifo_out_ready;

    // Output byte FIFO (8-bit bytes)
    logic [7:0] out_fifo_data;
    logic out_fifo_valid;
    logic out_fifo_ready;
    logic [7:0] out_fifo_out;
    logic out_fifo_out_valid;
    logic out_fifo_out_ready;

    // Sorter interface
    logic [VALUE_WIDTH-1:0] sorter_output_value;
    logic sorter_output_valid;
    logic sorter_input_ready;

    assign busy_o = (state_r != ST_IDLE);
    assign start_pulse = start_pulse_r | (|start_hold_r);

    // Input value FIFO: 10-bit values, depth 16
    fifo_1r1w #(
        .width_p(VALUE_WIDTH),
        .depth_log2_p(4)  // 2^4 = 16 depth
    ) input_fifo (
        .clk_i(clk_i),
        .reset_i(reset_i),
        .data_i(in_fifo_data),
        .valid_i(in_fifo_valid),
        .ready_o(in_fifo_ready),
        .data_o(in_fifo_out),
        .valid_o(in_fifo_out_valid),
        .ready_i(in_fifo_out_ready)
    );

    // Output byte FIFO: 8-bit bytes, depth 256 (to handle large datasets)
    fifo_1r1w #(
        .width_p(8),
        .depth_log2_p(8)  // 2^8 = 256 depth
    ) output_fifo (
        .clk_i(clk_i),
        .reset_i(reset_i),
        .data_i(out_fifo_data),
        .valid_i(out_fifo_valid),
        .ready_o(out_fifo_ready),
        .data_o(out_fifo_out),
        .valid_o(out_fifo_out_valid),
        .ready_i(out_fifo_out_ready)
    );

    radix_sorter #(
        .VALUE_WIDTH(VALUE_WIDTH),
        .COUNT_WIDTH(COUNT_WIDTH)
    ) sorter (
        .clk_i(clk_i),
        .reset_i(reset_i),
        .start_i(start_pulse),
        .length_i(length_r),
        .value_i(in_fifo_out),
        .value_valid_i(in_fifo_out_valid),
        .value_ready_o(sorter_input_ready),
        .sorted_value_o(sorter_output_value),
        .sorted_valid_o(sorter_output_valid),
        .sorted_ready_i((state_r == ST_OUTPUT) && !output_byte_phase_r && sorter_output_valid && !out_fifo_valid),
        .busy_o(),
        .done_o()
    );

    // Connect input FIFO output to sorter input with ready handshake
    assign in_fifo_out_ready = sorter_input_ready;

    // Connect TX to output FIFO
    assign tx_data_o = out_fifo_out;
    assign tx_valid_o = out_fifo_out_valid;
    assign out_fifo_out_ready = tx_ready_i;

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
                if (length_valid_r && header_sent_r) begin
                    if (length_r == 16'd0) begin
                        state_n = ST_OUTPUT;
                    end else begin
                        state_n = ST_INPUT;
                    end
                end
            end
            
            ST_INPUT: begin
                // Ready only if input FIFO has space
                rx_ready_o = in_fifo_ready;
                // Move to output after receiving all payload bytes
                if (input_count_r >= (length_r << 1)) begin
                    state_n = ST_OUTPUT;
                end
            end
            
            ST_OUTPUT: begin
                if (output_bytes_sent_r >= output_byte_count_r && !out_fifo_out_valid) begin
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
            header_sent_r <= 1'b0;
            length_valid_r <= 1'b0;
            input_low_byte_r <= '0;
            input_count_r <= '0;
            start_pulse_r <= 1'b0;
            start_hold_r <= '0;
            in_fifo_data <= '0;
            in_fifo_valid <= 1'b0;
            out_fifo_data <= '0;
            out_fifo_valid <= 1'b0;
            output_byte_phase_r <= 1'b0;
            output_value_hold_r <= '0;
        end else begin
            state_r <= state_n;
            start_pulse_r <= 1'b0;
            in_fifo_valid <= 1'b0;
            // Don't clear out_fifo_valid unconditionally - only clear when accepted
            if (out_fifo_valid && out_fifo_ready) begin
                out_fifo_valid <= 1'b0;
            end

            if (start_hold_r != '0) begin
                start_hold_r <= start_hold_r - 1'b1;
            end

            case (state_r)
                ST_IDLE: begin
                    input_count_r <= '0;
                    output_bytes_sent_r <= '0;
                    header_sent_r <= 1'b0;
                    length_valid_r <= 1'b0;
                    output_byte_phase_r <= 1'b0;
                    // Capture first length byte
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
                        // Capture MSB
                        length_r[15:8] <= rx_data_i;
                        output_byte_count_r <= 18'h2 + ({rx_data_i, length_r[7:0]} << 1);
                        length_valid_r  <= 1'b1;
                    end
                    
                    // Send header bytes when FIFO is ready
                    if (length_valid_r && !header_sent_r) begin
                        if (!output_byte_phase_r) begin
                            // Send low byte
                            if (out_fifo_ready) begin
                                out_fifo_data <= length_r[7:0];
                                out_fifo_valid <= 1'b1;
                                output_byte_phase_r <= 1'b1;
                            end
                        end else begin
                            // Send high byte
                            if (out_fifo_ready) begin
                                out_fifo_data <= length_r[15:8];
                                out_fifo_valid <= 1'b1;
                                output_byte_phase_r <= 1'b0;
                                header_sent_r <= 1'b1;
                            end
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
                            // High byte - form complete value and push to input FIFO
                            in_fifo_data <= {rx_data_i[1:0], input_low_byte_r};
                            in_fifo_valid <= 1'b1;
                        end
                    end
                end
                
                ST_OUTPUT: begin
                    // Queue sorted values as bytes using two-phase write
                    if (!output_byte_phase_r) begin
                        // Phase 0: Capture new sorted value and send low byte
                        if (sorter_output_valid && !out_fifo_valid) begin
                            output_value_hold_r <= sorter_output_value;
                            out_fifo_data <= sorter_output_value[7:0];
                            out_fifo_valid <= 1'b1;
                            output_byte_phase_r <= 1'b1;
                        end
                    end else begin
                        // Phase 1: Send high byte of held value (wait for low byte to be accepted)
                        if (!out_fifo_valid) begin
                            out_fifo_data <= {6'd0, output_value_hold_r[VALUE_WIDTH-1:8]};
                            out_fifo_valid <= 1'b1;
                            output_byte_phase_r <= 1'b0;
                        end
                    end
                end
                
                default: ;
            endcase

            // Track output bytes sent for completion detection
            if (out_fifo_out_valid && tx_ready_i) begin
                output_bytes_sent_r <= output_bytes_sent_r + 1'b1;
            end
        end
    end

endmodule
