module bubble_sort #(parameter N = 8) // Parameterizable array size (default 8)
(
    input  logic        clk,          // System clock
    input  logic        rst,          // Active-high reset
    input  logic        start,        // Start signal to begin sorting
    input  logic [7:0]  data_in [N-1:0], // Input array of N 8-bit values
    output logic [7:0]  data_out[N-1:0], // Output array (sorted results)
    output logic        done          // High when sorting is complete
);

    // State machine definition
    typedef enum logic [1:0] {IDLE, SORT, DONE} state_t;
    state_t state;

    // Local working array to hold values during sorting
    logic [7:0] arr[N-1:0];

    // Loop counters used for bubble sort
    int i, j;

    // Main sequential process (driven by clock and reset)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // On reset: go to IDLE, clear counters and done flag
            state <= IDLE;
            done  <= 0;
            i     <= 0;
            j     <= 0;
        end else begin
            case (state)

                // ----------------------
                // IDLE state: wait for start
                // ----------------------
                IDLE: begin
                    done <= 0; // Clear done flag
                    if (start) begin
                        // Copy input data into working array
                        for (int k = 0; k < N; k++) arr[k] <= data_in[k];
                        // Reset counters
                        i <= 0;
                        j <= 0;
                        // Transition to sorting
                        state <= SORT;
                    end
                end

                // ----------------------
                // SORT state: perform bubble sort
                // ----------------------
                SORT: begin
                    if (i < N-1) begin
                        if (j < N-i-1) begin  
                            // Compare adjacent elements
                            if (arr[j] > arr[j+1]) begin
                                // Swap if out of order
                                logic [7:0] tmp;
                                tmp      = arr[j];
                                arr[j]   = arr[j+1];
                                arr[j+1] = tmp;
                            end
                            // Move to next pair
                            j <= j + 1;
                        end else begin
                            // End of inner loop → reset j and increment i
                            j <= 0;
                            i <= i + 1;
                        end
                    end else begin
                        // Sorting complete → copy results to output
                        for (int k = 0; k < N; k++) data_out[k] <= arr[k];
                        // Move to DONE state
                        state <= DONE;
                    end
                end

                // ----------------------
                // DONE state: signal completion
                // ----------------------
                DONE: begin
                    done <= 1; 
                    // Stay here until reset or a new start pulse
                end

            endcase
        end
    end
endmodule
