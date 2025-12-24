`timescale 1ns/1ps
module radix_sorter #(
    parameter int VALUE_WIDTH = 10,
    parameter int COUNT_WIDTH = 16
) (
    input  logic                     clk_i,
    input  logic                     reset_i,
    input  logic                     start_i,
    input  logic [15:0]              length_i,
    input  logic [VALUE_WIDTH-1:0]   value_i,
    input  logic                     value_valid_i,
    output logic                     value_ready_o,
    output logic [VALUE_WIDTH-1:0]   sorted_value_o,
    output logic                     sorted_valid_o,
    input  logic                     sorted_ready_i,
    output logic                     busy_o,
    output logic                     done_o
);

    localparam int BUCKETS   = 1 << VALUE_WIDTH;
    localparam int ADDR_W    = VALUE_WIDTH;
    localparam int unsigned LAST_BUCKET = BUCKETS-1;

    typedef enum logic [3:0] {
        S_IDLE,
        S_CLEAR,
        S_LOAD_WAIT,
        S_LOAD_READ,
        S_LOAD_WRITE,
        S_SCAN_REQ,
        S_SCAN_CHECK,
        S_EMIT,
        S_DONE
    } state_e;

    state_e state_r, state_n;

    // Count storage in block RAM
    logic [COUNT_WIDTH-1:0] ram_rdata;
    logic [COUNT_WIDTH-1:0] ram_rdata_q;
    logic [COUNT_WIDTH-1:0] ram_wdata;
    logic [ADDR_W-1:0]      ram_raddr;
    logic [ADDR_W-1:0]      ram_waddr;
    logic                   ram_wr_en;

    logic rd_en;

    ram_1r1w_sync #(
        .width_p(COUNT_WIDTH),
        .depth_p(BUCKETS),
        .filename_p("")
    ) count_ram (
        .clk_i(clk_i),
        .reset_i(reset_i),
        .wr_valid_i(ram_wr_en),
        .wr_data_i(ram_wdata),
        .wr_addr_i(ram_waddr),
        .rd_valid_i(rd_en),
        .rd_addr_i(ram_raddr),
        .rd_data_o(ram_rdata)
    );

    logic [ADDR_W-1:0] clear_idx_r;
    logic [15:0]       loaded_count_r;
    logic [ADDR_W-1:0] scan_addr_r;
    logic [ADDR_W-1:0] scan_addr_q;  // Capture address for registered read
    logic [COUNT_WIDTH-1:0] emit_remaining_r;
    logic [VALUE_WIDTH-1:0] emit_value_r;
    logic [ADDR_W-1:0] load_addr_r;

    logic start_pulse;
    assign start_pulse = start_i && (state_r == S_IDLE || state_r == S_DONE);

    assign value_ready_o  = (state_r == S_LOAD_WAIT);
    assign sorted_valid_o = (state_r == S_EMIT);
    assign sorted_value_o = emit_value_r;
    assign busy_o         = (state_r != S_IDLE);
    assign done_o         = (state_r == S_DONE);

    // Register RAM read data for pipeline alignment
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            ram_rdata_q <= '0;
        end else begin
            ram_rdata_q <= ram_rdata;
        end
    end

    always_comb begin
        state_n   = state_r;
        ram_wr_en = 1'b0;
        ram_waddr = '0;
        ram_wdata = '0;
        ram_raddr = '0;
        rd_en     = 1'b0;

        case (state_r)
            S_IDLE: begin
                if (start_pulse) begin
                    state_n = S_CLEAR;
                end
            end

            S_CLEAR: begin
                ram_wr_en = 1'b1;
                ram_waddr = clear_idx_r;
                ram_wdata = '0;
                if (clear_idx_r == ADDR_W'(LAST_BUCKET)) begin
                    if (length_i == 0) begin
                        state_n = S_DONE;
                    end else begin
                        state_n = S_LOAD_WAIT;
                    end
                end
            end

            S_LOAD_WAIT: begin
                if (value_valid_i && value_ready_o) begin
                    state_n = S_LOAD_READ;
                end
            end

            S_LOAD_READ: begin
                rd_en     = 1'b1;
                ram_raddr = load_addr_r;
                state_n   = S_LOAD_WRITE;
            end

            S_LOAD_WRITE: begin
                ram_wr_en = 1'b1;
                ram_waddr = load_addr_r;
                ram_wdata = ram_rdata + 1'b1;
                if (loaded_count_r + 1'b1 >= length_i) begin
                    state_n = S_SCAN_REQ;
                end else begin
                    state_n = S_LOAD_WAIT;
                end
            end

            S_SCAN_REQ: begin
                rd_en     = 1'b1;
                ram_raddr = scan_addr_r;
                state_n   = S_SCAN_CHECK;
            end

            S_SCAN_CHECK: begin
                if (ram_rdata != 0) begin
                    state_n = S_EMIT;
                end else begin
                    if (scan_addr_r == ADDR_W'(LAST_BUCKET)) begin
                        state_n = S_DONE;
                    end else begin
                        state_n = S_SCAN_REQ;
                    end
                end
            end

            S_EMIT: begin
                if (sorted_valid_o && sorted_ready_i) begin
                    if (emit_remaining_r == 1) begin
                        if (scan_addr_r == LAST_BUCKET[ADDR_W-1:0]) begin
                            state_n = S_DONE;
                        end else begin
                            state_n = S_SCAN_REQ;
                        end
                    end
                end
            end

            S_DONE: begin
                if (start_pulse) begin
                    state_n = S_CLEAR;
                end
            end

            default: state_n = S_IDLE;
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            state_r          <= S_IDLE;
            clear_idx_r      <= '0;
            loaded_count_r   <= '0;
            scan_addr_r      <= '0;
            scan_addr_q      <= '0;
            emit_remaining_r <= '0;
            emit_value_r     <= '0;
            load_addr_r      <= '0;
        end else begin
            state_r <= state_n;

            case (state_r)
                S_IDLE: begin
                    if (start_pulse) begin
                        clear_idx_r    <= '0;
                        loaded_count_r <= '0;
                        scan_addr_r    <= '0;
                        scan_addr_q    <= '0;
                    end
                end

                S_CLEAR: begin
                    if (clear_idx_r == ADDR_W'(LAST_BUCKET)) begin
                        clear_idx_r <= '0;
                    end else begin
                        clear_idx_r <= clear_idx_r + 1'b1;
                    end
                end

                S_LOAD_WAIT: begin
                    if (value_valid_i && value_ready_o) begin
                        load_addr_r <= value_i;
                    end
                end

                S_LOAD_WRITE: begin
                    loaded_count_r <= loaded_count_r + 1'b1;
                end

                S_SCAN_REQ: begin
                    // Capture address for next cycle's data
                    scan_addr_q <= scan_addr_r;
                end

                S_SCAN_CHECK: begin
                    if (ram_rdata != 0) begin
                        emit_remaining_r <= ram_rdata;
                        emit_value_r     <= scan_addr_q;  // Use captured address
                    end else begin
                        if (scan_addr_r != ADDR_W'(LAST_BUCKET)) begin
                            scan_addr_r <= scan_addr_r + 1'b1;
                        end
                    end
                end 

                S_EMIT: begin
                    if (sorted_valid_o && sorted_ready_i) begin
                        if (emit_remaining_r > 1) begin
                            emit_remaining_r <= emit_remaining_r - 1'b1;
                        end else begin
                            emit_remaining_r <= '0;
                            if (scan_addr_r != ADDR_W'(LAST_BUCKET)) begin
                                scan_addr_r <= scan_addr_r + 1'b1;
                            end
                        end
                    end
                end

                S_DONE: begin
                    if (start_pulse) begin
                        clear_idx_r    <= '0;
                        loaded_count_r <= '0;
                        scan_addr_r    <= '0;
                        scan_addr_q    <= '0;
                    end
                end

                default: ;
            endcase
        end
    end

endmodule
