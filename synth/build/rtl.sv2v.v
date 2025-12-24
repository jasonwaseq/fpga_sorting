module top (
	clk,
	rxd,
	txd
);
	input wire clk;
	input wire rxd;
	output wire txd;
	localparam [15:0] PRESCALE = 16'd13;
	reg [3:0] por_cnt = 4'd0;
	wire rst_sync;
	always @(posedge clk)
		if (&por_cnt)
			por_cnt <= por_cnt;
		else
			por_cnt <= por_cnt + 1'b1;
	assign rst_sync = ~&por_cnt;
	wire [7:0] rx_data;
	wire [7:0] tx_data;
	wire rx_valid;
	wire rx_ready;
	wire tx_valid;
	wire tx_ready;
	uart uart_inst(
		.clk(clk),
		.rst(rst_sync),
		.m_axis_tdata(rx_data),
		.m_axis_tvalid(rx_valid),
		.m_axis_tready(rx_ready),
		.s_axis_tdata(tx_data),
		.s_axis_tvalid(tx_valid),
		.s_axis_tready(tx_ready),
		.rxd(rxd),
		.txd(txd),
		.prescale(PRESCALE)
	);
	uart_sort_bridge #(
		.VALUE_WIDTH(10),
		.COUNT_WIDTH(16)
	) sorter_bridge(
		.clk_i(clk),
		.reset_i(rst_sync),
		.rx_data_i(rx_data),
		.rx_valid_i(rx_valid),
		.rx_ready_o(rx_ready),
		.tx_data_o(tx_data),
		.tx_valid_o(tx_valid),
		.tx_ready_i(tx_ready),
		.busy_o()
	);
endmodule
module uart_sort_bridge (
	clk_i,
	reset_i,
	rx_data_i,
	rx_valid_i,
	rx_ready_o,
	tx_data_o,
	tx_valid_o,
	tx_ready_i,
	busy_o
);
	reg _sv2v_0;
	parameter signed [31:0] VALUE_WIDTH = 10;
	parameter signed [31:0] COUNT_WIDTH = 16;
	input wire clk_i;
	input wire reset_i;
	input wire [7:0] rx_data_i;
	input wire rx_valid_i;
	output reg rx_ready_o;
	output wire [7:0] tx_data_o;
	output wire tx_valid_o;
	input wire tx_ready_i;
	output wire busy_o;
	reg [1:0] state_r;
	reg [1:0] state_n;
	reg [15:0] length_r;
	reg length_valid_r;
	reg [17:0] output_byte_count_r;
	reg [17:0] output_bytes_sent_r;
	reg header_sent_r;
	reg [7:0] input_low_byte_r;
	reg [15:0] input_count_r;
	reg output_byte_phase_r;
	reg [VALUE_WIDTH - 1:0] output_value_hold_r;
	reg start_pulse_r;
	reg [3:0] start_hold_r;
	wire start_pulse;
	reg [VALUE_WIDTH - 1:0] in_fifo_data;
	reg in_fifo_valid;
	wire in_fifo_ready;
	wire [VALUE_WIDTH - 1:0] in_fifo_out;
	wire in_fifo_out_valid;
	wire in_fifo_out_ready;
	reg [7:0] out_fifo_data;
	reg out_fifo_valid;
	wire out_fifo_ready;
	wire [7:0] out_fifo_out;
	wire out_fifo_out_valid;
	wire out_fifo_out_ready;
	wire [VALUE_WIDTH - 1:0] sorter_output_value;
	wire sorter_output_valid;
	wire sorter_input_ready;
	assign busy_o = state_r != 2'd0;
	assign start_pulse = start_pulse_r | (|start_hold_r);
	fifo_1r1w #(
		.width_p(VALUE_WIDTH),
		.depth_log2_p(4)
	) input_fifo(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.data_i(in_fifo_data),
		.valid_i(in_fifo_valid),
		.ready_o(in_fifo_ready),
		.data_o(in_fifo_out),
		.valid_o(in_fifo_out_valid),
		.ready_i(in_fifo_out_ready)
	);
	fifo_1r1w #(
		.width_p(8),
		.depth_log2_p(8)
	) output_fifo(
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
	) sorter(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.start_i(start_pulse),
		.length_i(length_r),
		.value_i(in_fifo_out),
		.value_valid_i(in_fifo_out_valid),
		.value_ready_o(sorter_input_ready),
		.sorted_value_o(sorter_output_value),
		.sorted_valid_o(sorter_output_valid),
		.sorted_ready_i((((state_r == 2'd3) && !output_byte_phase_r) && sorter_output_valid) && !out_fifo_valid),
		.busy_o(),
		.done_o()
	);
	assign in_fifo_out_ready = sorter_input_ready;
	assign tx_data_o = out_fifo_out;
	assign tx_valid_o = out_fifo_out_valid;
	assign out_fifo_out_ready = tx_ready_i;
	always @(*) begin
		if (_sv2v_0)
			;
		state_n = state_r;
		rx_ready_o = 1'b0;
		case (state_r)
			2'd0: begin
				rx_ready_o = 1'b1;
				if (rx_valid_i)
					state_n = 2'd1;
			end
			2'd1: begin
				rx_ready_o = 1'b1;
				if (length_valid_r && header_sent_r) begin
					if (length_r == 16'd0)
						state_n = 2'd3;
					else
						state_n = 2'd2;
				end
			end
			2'd2: begin
				rx_ready_o = in_fifo_ready;
				if (input_count_r >= (length_r << 1))
					state_n = 2'd3;
			end
			2'd3:
				if ((output_bytes_sent_r >= output_byte_count_r) && !out_fifo_out_valid)
					state_n = 2'd0;
			default: state_n = 2'd0;
		endcase
	end
	always @(posedge clk_i)
		if (reset_i) begin
			state_r <= 2'd0;
			length_r <= 1'sb0;
			output_byte_count_r <= 1'sb0;
			output_bytes_sent_r <= 1'sb0;
			header_sent_r <= 1'b0;
			length_valid_r <= 1'b0;
			input_low_byte_r <= 1'sb0;
			input_count_r <= 1'sb0;
			start_pulse_r <= 1'b0;
			start_hold_r <= 1'sb0;
			in_fifo_data <= 1'sb0;
			in_fifo_valid <= 1'b0;
			out_fifo_data <= 1'sb0;
			out_fifo_valid <= 1'b0;
			output_byte_phase_r <= 1'b0;
			output_value_hold_r <= 1'sb0;
		end
		else begin
			state_r <= state_n;
			start_pulse_r <= 1'b0;
			in_fifo_valid <= 1'b0;
			if (out_fifo_valid && out_fifo_ready)
				out_fifo_valid <= 1'b0;
			if (start_hold_r != {4 {1'sb0}})
				start_hold_r <= start_hold_r - 1'b1;
			case (state_r)
				2'd0: begin
					input_count_r <= 1'sb0;
					output_bytes_sent_r <= 1'sb0;
					header_sent_r <= 1'b0;
					length_valid_r <= 1'b0;
					output_byte_phase_r <= 1'b0;
					if (rx_valid_i && rx_ready_o)
						length_r[7:0] <= rx_data_i;
				end
				2'd1: begin
					if ((length_valid_r && !start_pulse_r) && (start_hold_r == {4 {1'sb0}})) begin
						start_pulse_r <= 1'b1;
						start_hold_r <= 4'h3;
					end
					if (rx_valid_i && rx_ready_o) begin
						length_r[15:8] <= rx_data_i;
						output_byte_count_r <= 18'h00002 + ({rx_data_i, length_r[7:0]} << 1);
						length_valid_r <= 1'b1;
					end
					if (length_valid_r && !header_sent_r) begin
						if (!output_byte_phase_r) begin
							if (out_fifo_ready) begin
								out_fifo_data <= length_r[7:0];
								out_fifo_valid <= 1'b1;
								output_byte_phase_r <= 1'b1;
							end
						end
						else if (out_fifo_ready) begin
							out_fifo_data <= length_r[15:8];
							out_fifo_valid <= 1'b1;
							output_byte_phase_r <= 1'b0;
							header_sent_r <= 1'b1;
						end
					end
				end
				2'd2:
					if (rx_valid_i && rx_ready_o) begin
						input_count_r <= input_count_r + 1'b1;
						if (input_count_r[0] == 1'b0)
							input_low_byte_r <= rx_data_i;
						else begin
							in_fifo_data <= {rx_data_i[1:0], input_low_byte_r};
							in_fifo_valid <= 1'b1;
						end
					end
				2'd3:
					if (!output_byte_phase_r) begin
						if (sorter_output_valid && !out_fifo_valid) begin
							output_value_hold_r <= sorter_output_value;
							out_fifo_data <= sorter_output_value[7:0];
							out_fifo_valid <= 1'b1;
							output_byte_phase_r <= 1'b1;
						end
					end
					else if (!out_fifo_valid) begin
						out_fifo_data <= {6'd0, output_value_hold_r[VALUE_WIDTH - 1:8]};
						out_fifo_valid <= 1'b1;
						output_byte_phase_r <= 1'b0;
					end
				default:
					;
			endcase
			if (out_fifo_out_valid && tx_ready_i)
				output_bytes_sent_r <= output_bytes_sent_r + 1'b1;
		end
	initial _sv2v_0 = 0;
endmodule
module radix_sorter (
	clk_i,
	reset_i,
	start_i,
	length_i,
	value_i,
	value_valid_i,
	value_ready_o,
	sorted_value_o,
	sorted_valid_o,
	sorted_ready_i,
	busy_o,
	done_o
);
	reg _sv2v_0;
	parameter signed [31:0] VALUE_WIDTH = 10;
	parameter signed [31:0] COUNT_WIDTH = 16;
	input wire clk_i;
	input wire reset_i;
	input wire start_i;
	input wire [15:0] length_i;
	input wire [VALUE_WIDTH - 1:0] value_i;
	input wire value_valid_i;
	output wire value_ready_o;
	output wire [VALUE_WIDTH - 1:0] sorted_value_o;
	output wire sorted_valid_o;
	input wire sorted_ready_i;
	output wire busy_o;
	output wire done_o;
	localparam signed [31:0] BUCKETS = 1 << VALUE_WIDTH;
	localparam signed [31:0] ADDR_W = VALUE_WIDTH;
	localparam [31:0] LAST_BUCKET = BUCKETS - 1;
	reg [3:0] state_r;
	reg [3:0] state_n;
	wire [COUNT_WIDTH - 1:0] ram_rdata;
	reg [COUNT_WIDTH - 1:0] ram_rdata_q;
	reg [COUNT_WIDTH - 1:0] ram_wdata;
	reg [ADDR_W - 1:0] ram_raddr;
	reg [ADDR_W - 1:0] ram_waddr;
	reg ram_wr_en;
	reg rd_en;
	ram_1r1w_sync #(
		.width_p(COUNT_WIDTH),
		.depth_p(BUCKETS),
		.filename_p("")
	) count_ram(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.wr_valid_i(ram_wr_en),
		.wr_data_i(ram_wdata),
		.wr_addr_i(ram_waddr),
		.rd_valid_i(rd_en),
		.rd_addr_i(ram_raddr),
		.rd_data_o(ram_rdata)
	);
	reg [ADDR_W - 1:0] clear_idx_r;
	reg [15:0] loaded_count_r;
	reg [ADDR_W - 1:0] scan_addr_r;
	reg [ADDR_W - 1:0] scan_addr_q;
	reg [COUNT_WIDTH - 1:0] emit_remaining_r;
	reg [VALUE_WIDTH - 1:0] emit_value_r;
	reg [ADDR_W - 1:0] load_addr_r;
	wire start_pulse;
	assign start_pulse = start_i && ((state_r == 4'd0) || (state_r == 4'd8));
	assign value_ready_o = state_r == 4'd2;
	assign sorted_valid_o = state_r == 4'd7;
	assign sorted_value_o = emit_value_r;
	assign busy_o = state_r != 4'd0;
	assign done_o = state_r == 4'd8;
	always @(posedge clk_i)
		if (reset_i)
			ram_rdata_q <= 1'sb0;
		else
			ram_rdata_q <= ram_rdata;
	function automatic [ADDR_W - 1:0] sv2v_cast_8FFD8;
		input reg [ADDR_W - 1:0] inp;
		sv2v_cast_8FFD8 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		state_n = state_r;
		ram_wr_en = 1'b0;
		ram_waddr = 1'sb0;
		ram_wdata = 1'sb0;
		ram_raddr = 1'sb0;
		rd_en = 1'b0;
		case (state_r)
			4'd0:
				if (start_pulse)
					state_n = 4'd1;
			4'd1: begin
				ram_wr_en = 1'b1;
				ram_waddr = clear_idx_r;
				ram_wdata = 1'sb0;
				if (clear_idx_r == sv2v_cast_8FFD8(LAST_BUCKET)) begin
					if (length_i == 0)
						state_n = 4'd8;
					else
						state_n = 4'd2;
				end
			end
			4'd2:
				if (value_valid_i && value_ready_o)
					state_n = 4'd3;
			4'd3: begin
				rd_en = 1'b1;
				ram_raddr = load_addr_r;
				state_n = 4'd4;
			end
			4'd4: begin
				ram_wr_en = 1'b1;
				ram_waddr = load_addr_r;
				ram_wdata = ram_rdata + 1'b1;
				if ((loaded_count_r + 1'b1) >= length_i)
					state_n = 4'd5;
				else
					state_n = 4'd2;
			end
			4'd5: begin
				rd_en = 1'b1;
				ram_raddr = scan_addr_r;
				state_n = 4'd6;
			end
			4'd6:
				if (ram_rdata != 0)
					state_n = 4'd7;
				else if (scan_addr_r == sv2v_cast_8FFD8(LAST_BUCKET))
					state_n = 4'd8;
				else
					state_n = 4'd5;
			4'd7:
				if (sorted_valid_o && sorted_ready_i) begin
					if (emit_remaining_r == 1) begin
						if (scan_addr_r == LAST_BUCKET[ADDR_W - 1:0])
							state_n = 4'd8;
						else
							state_n = 4'd5;
					end
				end
			4'd8:
				if (start_pulse)
					state_n = 4'd1;
			default: state_n = 4'd0;
		endcase
	end
	always @(posedge clk_i)
		if (reset_i) begin
			state_r <= 4'd0;
			clear_idx_r <= 1'sb0;
			loaded_count_r <= 1'sb0;
			scan_addr_r <= 1'sb0;
			scan_addr_q <= 1'sb0;
			emit_remaining_r <= 1'sb0;
			emit_value_r <= 1'sb0;
			load_addr_r <= 1'sb0;
		end
		else begin
			state_r <= state_n;
			case (state_r)
				4'd0:
					if (start_pulse) begin
						clear_idx_r <= 1'sb0;
						loaded_count_r <= 1'sb0;
						scan_addr_r <= 1'sb0;
						scan_addr_q <= 1'sb0;
					end
				4'd1:
					if (clear_idx_r == sv2v_cast_8FFD8(LAST_BUCKET))
						clear_idx_r <= 1'sb0;
					else
						clear_idx_r <= clear_idx_r + 1'b1;
				4'd2:
					if (value_valid_i && value_ready_o)
						load_addr_r <= value_i;
				4'd4: loaded_count_r <= loaded_count_r + 1'b1;
				4'd5: scan_addr_q <= scan_addr_r;
				4'd6:
					if (ram_rdata != 0) begin
						emit_remaining_r <= ram_rdata;
						emit_value_r <= scan_addr_q;
					end
					else if (scan_addr_r != sv2v_cast_8FFD8(LAST_BUCKET))
						scan_addr_r <= scan_addr_r + 1'b1;
				4'd7:
					if (sorted_valid_o && sorted_ready_i) begin
						if (emit_remaining_r > 1)
							emit_remaining_r <= emit_remaining_r - 1'b1;
						else begin
							emit_remaining_r <= 1'sb0;
							if (scan_addr_r != sv2v_cast_8FFD8(LAST_BUCKET))
								scan_addr_r <= scan_addr_r + 1'b1;
						end
					end
				4'd8:
					if (start_pulse) begin
						clear_idx_r <= 1'sb0;
						loaded_count_r <= 1'sb0;
						scan_addr_r <= 1'sb0;
						scan_addr_q <= 1'sb0;
					end
				default:
					;
			endcase
		end
	initial _sv2v_0 = 0;
endmodule
module fifo_1r1w (
	clk_i,
	reset_i,
	data_i,
	ready_i,
	valid_i,
	ready_o,
	valid_o,
	data_o
);
	parameter [31:0] width_p = 8;
	parameter [31:0] depth_log2_p = 8;
	input [0:0] clk_i;
	input [0:0] reset_i;
	input [width_p - 1:0] data_i;
	input [0:0] ready_i;
	input [0:0] valid_i;
	output wire [0:0] ready_o;
	output wire [0:0] valid_o;
	output wire [width_p - 1:0] data_o;
	reg [depth_log2_p:0] wr_ptr;
	reg [depth_log2_p:0] rd_ptr;
	wire wr_en;
	assign wr_en = valid_i & ready_o;
	wire rd_en;
	assign rd_en = valid_o & ready_i;
	wire [0:0] full;
	assign full = (wr_ptr[depth_log2_p] ^ rd_ptr[depth_log2_p]) && (wr_ptr[depth_log2_p - 1:0] == rd_ptr[depth_log2_p - 1:0]);
	wire [0:0] empty;
	assign empty = ~(wr_ptr[depth_log2_p] ^ rd_ptr[depth_log2_p]) && (wr_ptr[depth_log2_p - 1:0] == rd_ptr[depth_log2_p - 1:0]);
	assign ready_o = ~full;
	assign valid_o = ~empty;
	wire [width_p - 1:0] rd_data_l;
	wire [depth_log2_p:0] mux;
	assign mux = (rd_en ? rd_ptr + 1 : rd_ptr);
	ram_1r1w_sync #(
		.width_p(width_p),
		.depth_p(1 << depth_log2_p),
		.filename_p("")
	) ram_inst(
		.clk_i(clk_i),
		.reset_i(reset_i),
		.wr_valid_i(wr_en),
		.wr_data_i(data_i),
		.wr_addr_i(wr_ptr[depth_log2_p - 1:0]),
		.rd_valid_i(1'b1),
		.rd_addr_i(mux[depth_log2_p - 1:0]),
		.rd_data_o(rd_data_l)
	);
	reg [0:0] trail;
	reg [width_p - 1:0] data_l;
	reg [0:0] firstwrite;
	always @(posedge clk_i)
		if (reset_i) begin
			wr_ptr <= 1'sb0;
			rd_ptr <= 1'sb0;
			data_l <= 1'sb0;
			trail <= 1'sb0;
			firstwrite <= 1'sb0;
		end
		else begin
			if (wr_en) begin
				wr_ptr <= wr_ptr + 1;
				data_l <= data_i;
			end
			if (rd_en)
				rd_ptr <= rd_ptr + 1;
			firstwrite <= (wr_en & empty) | (firstwrite & rd_en);
			trail <= (mux == wr_ptr) & rd_en;
		end
	assign data_o = (firstwrite | trail ? data_l : rd_data_l);
endmodule
module ram_1r1w_sync (
	clk_i,
	reset_i,
	wr_valid_i,
	wr_data_i,
	wr_addr_i,
	rd_valid_i,
	rd_addr_i,
	rd_data_o
);
	parameter [31:0] width_p = 8;
	parameter [31:0] depth_p = 512;
	parameter filename_p = "memory_init_file.bin";
	input [0:0] clk_i;
	input [0:0] reset_i;
	input [0:0] wr_valid_i;
	input [width_p - 1:0] wr_data_i;
	input [$clog2(depth_p) - 1:0] wr_addr_i;
	input [0:0] rd_valid_i;
	input [$clog2(depth_p) - 1:0] rd_addr_i;
	output wire [width_p - 1:0] rd_data_o;
	reg [width_p - 1:0] ram [depth_p - 1:0];
	reg [width_p - 1:0] rd_data_l;
	always @(posedge clk_i) begin
		if (reset_i)
			rd_data_l <= 1'sb0;
		else if (rd_valid_i)
			rd_data_l <= ram[rd_addr_i];
		if (wr_valid_i)
			ram[wr_addr_i] <= wr_data_i;
	end
	assign rd_data_o = rd_data_l;
	initial begin
		$display("%m: depth_p is %d, width_p is %d", depth_p, width_p);
		begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < depth_p; i = i + 1)
				$dumpvars(0, ram[i]);
		end
	end
endmodule
module uart (
	clk,
	rst,
	s_axis_tdata,
	s_axis_tvalid,
	s_axis_tready,
	m_axis_tdata,
	m_axis_tvalid,
	m_axis_tready,
	rxd,
	txd,
	tx_busy,
	rx_busy,
	rx_overrun_error,
	rx_frame_error,
	prescale
);
	parameter DATA_WIDTH = 8;
	input wire clk;
	input wire rst;
	input wire [DATA_WIDTH - 1:0] s_axis_tdata;
	input wire s_axis_tvalid;
	output wire s_axis_tready;
	output wire [DATA_WIDTH - 1:0] m_axis_tdata;
	output wire m_axis_tvalid;
	input wire m_axis_tready;
	input wire rxd;
	output wire txd;
	output wire tx_busy;
	output wire rx_busy;
	output wire rx_overrun_error;
	output wire rx_frame_error;
	input wire [15:0] prescale;
	uart_tx #(.DATA_WIDTH(DATA_WIDTH)) uart_tx_inst(
		.clk(clk),
		.rst(rst),
		.s_axis_tdata(s_axis_tdata),
		.s_axis_tvalid(s_axis_tvalid),
		.s_axis_tready(s_axis_tready),
		.txd(txd),
		.busy(tx_busy),
		.prescale(prescale)
	);
	uart_rx #(.DATA_WIDTH(DATA_WIDTH)) uart_rx_inst(
		.clk(clk),
		.rst(rst),
		.m_axis_tdata(m_axis_tdata),
		.m_axis_tvalid(m_axis_tvalid),
		.m_axis_tready(m_axis_tready),
		.rxd(rxd),
		.busy(rx_busy),
		.overrun_error(rx_overrun_error),
		.frame_error(rx_frame_error),
		.prescale(prescale)
	);
endmodule
module uart_rx (
	clk,
	rst,
	m_axis_tdata,
	m_axis_tvalid,
	m_axis_tready,
	rxd,
	busy,
	overrun_error,
	frame_error,
	prescale
);
	parameter DATA_WIDTH = 8;
	input wire clk;
	input wire rst;
	output wire [DATA_WIDTH - 1:0] m_axis_tdata;
	output wire m_axis_tvalid;
	input wire m_axis_tready;
	input wire rxd;
	output wire busy;
	output wire overrun_error;
	output wire frame_error;
	input wire [15:0] prescale;
	reg [DATA_WIDTH - 1:0] m_axis_tdata_reg = 0;
	reg m_axis_tvalid_reg = 0;
	reg rxd_reg = 1;
	reg busy_reg = 0;
	reg overrun_error_reg = 0;
	reg frame_error_reg = 0;
	reg [DATA_WIDTH - 1:0] data_reg = 0;
	reg [18:0] prescale_reg = 0;
	reg [3:0] bit_cnt = 0;
	assign m_axis_tdata = m_axis_tdata_reg;
	assign m_axis_tvalid = m_axis_tvalid_reg;
	assign busy = busy_reg;
	assign overrun_error = overrun_error_reg;
	assign frame_error = frame_error_reg;
	always @(posedge clk)
		if (rst) begin
			m_axis_tdata_reg <= 0;
			m_axis_tvalid_reg <= 0;
			rxd_reg <= 1;
			prescale_reg <= 0;
			bit_cnt <= 0;
			busy_reg <= 0;
			overrun_error_reg <= 0;
			frame_error_reg <= 0;
		end
		else begin
			rxd_reg <= rxd;
			overrun_error_reg <= 0;
			frame_error_reg <= 0;
			if (m_axis_tvalid && m_axis_tready)
				m_axis_tvalid_reg <= 0;
			if (prescale_reg > 0)
				prescale_reg <= prescale_reg - 1;
			else if (bit_cnt > 0) begin
				if (bit_cnt > (DATA_WIDTH + 1)) begin
					if (!rxd_reg) begin
						bit_cnt <= bit_cnt - 1;
						prescale_reg <= (prescale << 3) - 1;
					end
					else begin
						bit_cnt <= 0;
						prescale_reg <= 0;
					end
				end
				else if (bit_cnt > 1) begin
					bit_cnt <= bit_cnt - 1;
					prescale_reg <= (prescale << 3) - 1;
					data_reg <= {rxd_reg, data_reg[DATA_WIDTH - 1:1]};
				end
				else if (bit_cnt == 1) begin
					bit_cnt <= bit_cnt - 1;
					if (rxd_reg) begin
						m_axis_tdata_reg <= data_reg;
						m_axis_tvalid_reg <= 1;
						overrun_error_reg <= m_axis_tvalid_reg;
					end
					else
						frame_error_reg <= 1;
				end
			end
			else begin
				busy_reg <= 0;
				if (!rxd_reg) begin
					prescale_reg <= (prescale << 2) - 2;
					bit_cnt <= DATA_WIDTH + 2;
					data_reg <= 0;
					busy_reg <= 1;
				end
			end
		end
endmodule
module uart_tx (
	clk,
	rst,
	s_axis_tdata,
	s_axis_tvalid,
	s_axis_tready,
	txd,
	busy,
	prescale
);
	parameter DATA_WIDTH = 8;
	input wire clk;
	input wire rst;
	input wire [DATA_WIDTH - 1:0] s_axis_tdata;
	input wire s_axis_tvalid;
	output wire s_axis_tready;
	output wire txd;
	output wire busy;
	input wire [15:0] prescale;
	reg s_axis_tready_reg = 0;
	reg txd_reg = 1;
	reg busy_reg = 0;
	reg [DATA_WIDTH:0] data_reg = 0;
	reg [18:0] prescale_reg = 0;
	reg [3:0] bit_cnt = 0;
	assign s_axis_tready = s_axis_tready_reg;
	assign txd = txd_reg;
	assign busy = busy_reg;
	always @(posedge clk)
		if (rst) begin
			s_axis_tready_reg <= 0;
			txd_reg <= 1;
			prescale_reg <= 0;
			bit_cnt <= 0;
			busy_reg <= 0;
		end
		else if (prescale_reg > 0) begin
			s_axis_tready_reg <= 0;
			prescale_reg <= prescale_reg - 1;
		end
		else if (bit_cnt == 0) begin
			s_axis_tready_reg <= 1;
			busy_reg <= 0;
			if (s_axis_tvalid) begin
				s_axis_tready_reg <= !s_axis_tready_reg;
				prescale_reg <= (prescale << 3) - 1;
				bit_cnt <= DATA_WIDTH + 1;
				data_reg <= {1'b1, s_axis_tdata};
				txd_reg <= 0;
				busy_reg <= 1;
			end
		end
		else if (bit_cnt > 1) begin
			bit_cnt <= bit_cnt - 1;
			prescale_reg <= (prescale << 3) - 1;
			{data_reg, txd_reg} <= {1'b0, data_reg};
		end
		else if (bit_cnt == 1) begin
			bit_cnt <= bit_cnt - 1;
			prescale_reg <= prescale << 3;
			txd_reg <= 1;
		end
endmodule