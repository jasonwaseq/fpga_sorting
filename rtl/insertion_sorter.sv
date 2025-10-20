module insertion_sorter #(
    parameter WIDTH = 8,
    parameter DEPTH = 10,
    parameter DEPTH_LOG2 = 4  // ceil(log2(10)) = 4
)(
    input  logic clk_i,
    input  logic reset_i,
    
    // Input interface (from UART RX)
    input  logic [WIDTH-1:0] data_i,
    input  logic             valid_i,
    output logic             ready_o,
    
    // Output interface (to UART TX)
    output logic [WIDTH-1:0] data_o,
    output logic             valid_o,
    input  logic             ready_i
);

    // FSM States
    typedef enum logic [2:0] {
        IDLE,
        RECEIVE,
        SORT_DEQUEUE,
        SORT_COMPARE,
        SORT_ENQUEUE,
        OUTPUT
    } state_t;
    
    state_t state_r, state_n;
    
    // FIFO signals
    logic [WIDTH-1:0] fifo_data_i, fifo_data_o;
    logic fifo_valid_i, fifo_ready_o;
    logic fifo_valid_o, fifo_ready_i;
    
    // Control registers
    logic [DEPTH_LOG2:0] receive_count_r, receive_count_n;
    logic [DEPTH_LOG2:0] sort_count_r, sort_count_n;
    logic [DEPTH_LOG2:0] output_count_r, output_count_n;
    logic [WIDTH-1:0] current_data_r, current_data_n;
    logic [WIDTH-1:0] compare_data_r, compare_data_n;
    logic insert_found_r, insert_found_n;
    
    // FIFO instantiation
    fifo_1r1w #(
        .width_p(WIDTH),
        .depth_log2_p(DEPTH_LOG2)
    ) sorted_fifo (
        .clk_i(clk_i),
        .reset_i(reset_i),
        .data_i(fifo_data_i),
        .valid_i(fifo_valid_i),
        .ready_o(fifo_ready_o),
        .valid_o(fifo_valid_o),
        .data_o(fifo_data_o),
        .ready_i(fifo_ready_i)
    );
    
    // Comparator
    logic is_less_than;
    assign is_less_than = (current_data_r < compare_data_r);
    
    // FSM: State transition
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            state_r <= IDLE;
            receive_count_r <= '0;
            sort_count_r <= '0;
            output_count_r <= '0;
            current_data_r <= '0;
            compare_data_r <= '0;
            insert_found_r <= '0;
        end else begin
            state_r <= state_n;
            receive_count_r <= receive_count_n;
            sort_count_r <= sort_count_n;
            output_count_r <= output_count_n;
            current_data_r <= current_data_n;
            compare_data_r <= compare_data_n;
            insert_found_r <= insert_found_n;
        end
    end
    
    // FSM: Next state logic
    always_comb begin
        // Default assignments
        state_n = state_r;
        receive_count_n = receive_count_r;
        sort_count_n = sort_count_r;
        output_count_n = output_count_r;
        current_data_n = current_data_r;
        compare_data_n = compare_data_r;
        insert_found_n = insert_found_r;
        
        ready_o = 1'b0;
        fifo_data_i = '0;
        fifo_valid_i = 1'b0;
        fifo_ready_i = 1'b0;
        valid_o = 1'b0;
        data_o = '0;
        
        case (state_r)
            IDLE: begin
                ready_o = 1'b1;
                if (valid_i) begin
                    current_data_n = data_i;
                    receive_count_n = 1;
                    state_n = RECEIVE;
                end
            end
            
            RECEIVE: begin
                // First element goes directly to FIFO
                if (receive_count_r == 1) begin
                    fifo_data_i = current_data_r;
                    fifo_valid_i = 1'b1;
                    if (fifo_ready_o) begin
                        ready_o = 1'b1;
                        if (valid_i) begin
                            current_data_n = data_i;
                            receive_count_n = receive_count_r + 1;
                            if (receive_count_r + 1 == DEPTH) begin
                                state_n = SORT_DEQUEUE;
                                sort_count_n = '0;
                            end
                        end
                    end
                end
                // Subsequent elements need insertion sort
                else begin
                    state_n = SORT_DEQUEUE;
                    sort_count_n = '0;
                    insert_found_n = 1'b0;
                end
            end
            
            SORT_DEQUEUE: begin
                // Check if we've processed all existing sorted elements
                if (sort_count_r == receive_count_r - 1) begin
                    // Insert current element at end
                    fifo_data_i = current_data_r;
                    fifo_valid_i = 1'b1;
                    if (fifo_ready_o) begin
                        if (receive_count_r == DEPTH) begin
                            state_n = OUTPUT;
                            output_count_n = '0;
                        end else begin
                            ready_o = 1'b1;
                            if (valid_i) begin
                                current_data_n = data_i;
                                receive_count_n = receive_count_r + 1;
                                state_n = SORT_DEQUEUE;
                                sort_count_n = '0;
                                insert_found_n = 1'b0;
                            end else begin
                                state_n = RECEIVE;
                            end
                        end
                    end
                end
                else begin
                    // Dequeue element for comparison
                    fifo_ready_i = 1'b1;
                    if (fifo_valid_o) begin
                        compare_data_n = fifo_data_o;
                        state_n = SORT_COMPARE;
                    end
                end
            end
            
            SORT_COMPARE: begin
                if (!insert_found_r && is_less_than) begin
                    // Found insertion point, enqueue current element first
                    fifo_data_i = current_data_r;
                    fifo_valid_i = 1'b1;
                    if (fifo_ready_o) begin
                        insert_found_n = 1'b1;
                        // Then enqueue the dequeued element
                        state_n = SORT_ENQUEUE;
                    end
                end else begin
                    // Not insertion point, re-enqueue dequeued element
                    state_n = SORT_ENQUEUE;
                end
            end
            
            SORT_ENQUEUE: begin
                fifo_data_i = compare_data_r;
                fifo_valid_i = 1'b1;
                if (fifo_ready_o) begin
                    sort_count_n = sort_count_r + 1;
                    state_n = SORT_DEQUEUE;
                end
            end
            
            OUTPUT: begin
                valid_o = fifo_valid_o;
                data_o = fifo_data_o;
                fifo_ready_i = ready_i;
                if (fifo_valid_o && ready_i) begin
                    output_count_n = output_count_r + 1;
                    if (output_count_r + 1 == DEPTH) begin
                        state_n = IDLE;
                    end
                end
            end
            
            default: state_n = IDLE;
        endcase
    end

endmodule
