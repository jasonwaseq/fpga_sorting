module radix_sort #(
    parameter N = 8,           // number of elements
    parameter WIDTH = 8        // bit width of input numbers
)(
    input  logic              clk,
    input  logic              rst,
    input  logic              start,
    input  logic [WIDTH-1:0]  data_in [N-1:0],   // unsorted input array
    output logic [WIDTH-1:0]  data_out[N-1:0],   // sorted output array
    output logic              done
);

    // FSM states
    typedef enum logic [2:0] {IDLE, BUCKETIZE, COLLECT, NEXT_DIGIT, DONE_STATE} state_t;
    state_t state;

    // Working arrays
    logic [WIDTH-1:0] arr [N-1:0];   
    logic [WIDTH-1:0] temp[N-1:0];   

    // 10 buckets (for decimal digits 0-9)
    int bucket_count[0:9];  

    int digit;   // which decimal digit we’re sorting (0=ones, 1=tens, 2=hundreds)
    int divisor; // used to compute (value / divisor) % 10

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state   <= IDLE;
            done    <= 0;
            digit   <= 0;
            divisor <= 1;   // start with ones place
        end else begin
            case (state)
                // IDLE → Wait for start
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        // Copy input array
                        for (int k=0; k<N; k++) arr[k] <= data_in[k];
                        digit   <= 0;
                        divisor <= 1;   // 10^0 = 1
                        state   <= BUCKETIZE;
                    end
                end

                // BUCKETIZE → Count how many per bucket
                BUCKETIZE: begin
                    // Reset bucket counts
                    for (int b=0; b<10; b++) bucket_count[b] = 0;

                    // Count elements in each bucket
                    for (int k=0; k<N; k++) begin
                        int d = (arr[k] / divisor) % 10;  // extract current digit
                        bucket_count[d]++;
                    end

                    // Convert counts into prefix sums
                    for (int b=1; b<10; b++) bucket_count[b] += bucket_count[b-1];

                    // Place elements into temp array (stable order)
                    for (int k=N-1; k>=0; k--) begin
                        int d = (arr[k] / divisor) % 10;
                        bucket_count[d]--;
                        temp[bucket_count[d]] = arr[k];
                    end

                    state <= COLLECT;
                end

                // COLLECT → Copy temp back to arr
                COLLECT: begin
                    for (int k=0; k<N; k++) arr[k] <= temp[k];
                    state <= NEXT_DIGIT;
                end

                // NEXT_DIGIT → Check if another digit pass is needed
                NEXT_DIGIT: begin
                    if (digit == 2) begin
                        // We processed ones, tens, hundreds → done
                        for (int k=0; k<N; k++) data_out[k] <= arr[k];
                        state <= DONE_STATE;
                    end else begin
                        digit   <= digit + 1;
                        divisor <= divisor * 10; // move to next digit (10^d)
                        state   <= BUCKETIZE;
                    end
                end

                // DONE_STATE → Sorting complete
                DONE_STATE: begin
                    done <= 1;
                end
            endcase
        end
    end
endmodule
