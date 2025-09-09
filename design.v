module register_file (
	clk,
	rst,
	rs1_addr_i,
	rs2_addr_i,
	rd_addr_i,
	rd_data_i,
	we_i,
	re_i,
	rs1_data_o,
	rs2_data_o
);
	input clk;
	input rst;
	input wire [4:0] rs1_addr_i;
	input wire [4:0] rs2_addr_i;
	input wire [4:0] rd_addr_i;
	input wire [31:0] rd_data_i;
	input we_i;
	input re_i;
	output reg [31:0] rs1_data_o;
	output reg [31:0] rs2_data_o;
	reg [1023:0] reg_file_ff;
	reg [31:0] next_rs1;
	reg [31:0] rs1_ff;
	reg [31:0] next_rs2;
	reg [31:0] rs2_ff;
	always @(*) begin
		next_rs1 = 32'b00000000000000000000000000000000;
		next_rs2 = 32'b00000000000000000000000000000000;
		if (rs1_addr_i != 'h0)
			next_rs1 = reg_file_ff[rs1_addr_i * 32+:32];
		if (rs2_addr_i != 'h0)
			next_rs2 = reg_file_ff[rs2_addr_i * 32+:32];
		if (we_i && (rd_addr_i != 5'd0)) begin
			next_rs1 = (rs1_addr_i == rd_addr_i ? rd_data_i : next_rs1);
			next_rs2 = (rs2_addr_i == rd_addr_i ? rd_data_i : next_rs2);
		end
		if (~re_i) begin
			next_rs1 = rs1_ff;
			next_rs2 = rs2_ff;
		end
		rs1_data_o = rs1_ff;
		rs2_data_o = rs2_ff;
	end
	always @(posedge clk)
		if (~rst) begin
			rs1_ff <= 1'sb0;
			rs2_ff <= 1'sb0;
		end
		else begin
			if (we_i && (rd_addr_i != 'd0))
				reg_file_ff[rd_addr_i * 32+:32] <= rd_data_i;
			rs1_ff <= next_rs1;
			rs2_ff <= next_rs2;
		end
endmodule
module decode (
	clk,
	rst,
	jump_i,
	pc_reset_i,
	pc_jump_i,
	fetch_valid_i,
	fetch_ready_o,
	fetch_instr_i,
	wb_dec_i,
	id_ex_o,
	rs1_data_o,
	rs2_data_o,
	id_valid_o,
	id_ready_i
);
	parameter signed [31:0] SUPPORT_DEBUG = 1;
	input clk;
	input rst;
	input jump_i;
	input wire [31:0] pc_reset_i;
	input wire [31:0] pc_jump_i;
	input wire fetch_valid_i;
	output reg fetch_ready_o;
	input wire [31:0] fetch_instr_i;
	input wire [37:0] wb_dec_i;
	output reg [180:0] id_ex_o;
	output wire [31:0] rs1_data_o;
	output wire [31:0] rs2_data_o;
	output reg id_valid_o;
	input wire id_ready_i;
	reg dec_valid_ff;
	reg next_vld_dec;
	reg [31:0] instr_dec;
	reg wait_inst_ff;
	reg next_wait_inst;
	reg wfi_stop_ff;
	reg next_wfi_stop;
	reg [180:0] id_ex_ff;
	reg [180:0] next_id_ex;
	always @(*) begin
		next_vld_dec = dec_valid_ff;
		fetch_ready_o = id_ready_i && ~wfi_stop_ff;
		id_valid_o = dec_valid_ff;
		if (~id_valid_o || (id_valid_o && id_ready_i))
			next_vld_dec = fetch_valid_i;
		else if (id_valid_o && ~id_ready_i)
			next_vld_dec = 'b1;
	end
	always @(*)
		if (jump_i) begin
			id_ex_o = 181'b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
			id_ex_o[179-:32] = id_ex_ff[179-:32];
		end
		else if (wfi_stop_ff) begin
			id_ex_o = 181'b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
			id_ex_o[179-:32] = id_ex_ff[179-:32];
			id_ex_o[65] = 'b1;
		end
		else
			id_ex_o = id_ex_ff;
	function automatic [31:0] gen_imm;
		input reg [31:0] instr;
		input reg [2:0] imm_type;
		reg [31:0] imm_res;
		begin
			case (imm_type)
				3'd0: imm_res = {{21 {instr[31]}}, instr[30:25], instr[24:21], instr[20]};
				3'd1: imm_res = {{21 {instr[31]}}, instr[30:25], instr[11:8], instr[7]};
				3'd2: imm_res = {{20 {instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
				3'd3: imm_res = {instr[31], instr[30:20], instr[19:12], 12'd0};
				3'd4: imm_res = {{12 {instr[31]}}, instr[19:12], instr[20], instr[30:25], instr[24:21], 1'b0};
				3'd5: imm_res = {27'h0000000, instr[19:15]};
				default:
					;
			endcase
			gen_imm = imm_res;
		end
	endfunction
	function automatic [2:0] sv2v_cast_3;
		input reg [2:0] inp;
		sv2v_cast_3 = inp;
	endfunction
	always @(*) begin : dec_op
		instr_dec = fetch_instr_i;
		next_id_ex = 181'b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
		next_id_ex[64-:65] = 65'b00000000000000000000000000000000000000000000000000000000000000000;
		next_id_ex[135-:5] = instr_dec[11-:5];
		next_id_ex[94-:5] = instr_dec[19-:5];
		next_id_ex[89-:5] = instr_dec[24-:5];
		case (instr_dec[6-:7])
			7'b0010011: begin
				next_id_ex[130-:3] = instr_dec[14-:3];
				next_id_ex[147-:2] = 2'd0;
				next_id_ex[145-:2] = 2'd1;
				next_id_ex[126-:32] = gen_imm(fetch_instr_i, 3'd0);
				next_id_ex[127] = (instr_dec[30] ? 1'b1 : 1'b0);
				next_id_ex[180] = 1'b1;
			end
			7'b0110111: begin
				next_id_ex[130-:3] = 3'b000;
				next_id_ex[147-:2] = 2'd2;
				next_id_ex[145-:2] = 2'd1;
				next_id_ex[126-:32] = gen_imm(fetch_instr_i, 3'd3);
				next_id_ex[180] = 1'b1;
			end
			7'b0010111: begin
				next_id_ex[130-:3] = 3'b000;
				next_id_ex[147-:2] = 2'd3;
				next_id_ex[145-:2] = 2'd1;
				next_id_ex[126-:32] = gen_imm(fetch_instr_i, 3'd3);
				next_id_ex[180] = 1'b1;
			end
			7'b0110011: begin
				next_id_ex[130-:3] = instr_dec[14-:3];
				next_id_ex[147-:2] = 2'd0;
				next_id_ex[145-:2] = 2'd0;
				next_id_ex[136] = (instr_dec[30] ? 1'd1 : 1'd0);
				next_id_ex[127] = (instr_dec[30] ? 1'b1 : 1'b0);
				next_id_ex[180] = 1'b1;
			end
			7'b1101111: begin
				next_id_ex[137] = 1'b1;
				next_id_ex[130-:3] = 3'b000;
				next_id_ex[147-:2] = 2'd3;
				next_id_ex[145-:2] = 2'd1;
				next_id_ex[126-:32] = gen_imm(fetch_instr_i, 3'd4);
				next_id_ex[180] = 1'b1;
			end
			7'b1100111: begin
				next_id_ex[137] = 1'b1;
				next_id_ex[130-:3] = 3'b000;
				next_id_ex[147-:2] = 2'd0;
				next_id_ex[145-:2] = 2'd1;
				next_id_ex[126-:32] = gen_imm(fetch_instr_i, 3'd0);
				next_id_ex[180] = 1'b1;
			end
			7'b1100011: begin
				next_id_ex[138] = 1'b1;
				next_id_ex[130-:3] = instr_dec[14-:3];
				next_id_ex[147-:2] = 2'd0;
				next_id_ex[145-:2] = 2'd0;
				next_id_ex[126-:32] = gen_imm(fetch_instr_i, 3'd2);
			end
			7'b0000011: begin
				next_id_ex[143-:2] = 2'd1;
				next_id_ex[130-:3] = 3'b000;
				next_id_ex[147-:2] = 2'd0;
				next_id_ex[145-:2] = 2'd1;
				next_id_ex[180] = 1'b1;
				next_id_ex[141-:3] = sv2v_cast_3(instr_dec[14-:3]);
				next_id_ex[126-:32] = gen_imm(fetch_instr_i, 3'd0);
			end
			7'b0100011: begin
				next_id_ex[143-:2] = 2'd2;
				next_id_ex[130-:3] = 3'b000;
				next_id_ex[147-:2] = 2'd0;
				next_id_ex[145-:2] = 2'd1;
				next_id_ex[141-:3] = sv2v_cast_3(instr_dec[14-:3]);
				next_id_ex[126-:32] = gen_imm(fetch_instr_i, 3'd1);
			end
			7'b0001111: begin
				next_id_ex[130-:3] = 3'b000;
				next_id_ex[147-:2] = 2'd2;
				next_id_ex[145-:2] = 2'd2;
			end
			7'b1110011: begin
				next_id_ex[130-:3] = 3'b000;
				next_id_ex[147-:2] = 2'd2;
				next_id_ex[145-:2] = 2'd2;
				next_id_ex[126-:32] = gen_imm(fetch_instr_i, 3'd5);
				if ((instr_dec[14-:3] != 3'b000) && (instr_dec[14-:3] != 3'b100)) begin
					next_id_ex[147-:2] = 2'd0;
					next_id_ex[84-:3] = sv2v_cast_3(instr_dec[14-:3]);
					next_id_ex[81-:12] = instr_dec[31:20];
					next_id_ex[69] = (instr_dec[19-:5] == 'h0 ? 'b1 : 'b0);
					if (instr_dec[11-:5] != 'h0)
						next_id_ex[180] = 1'b1;
				end
				else if (((instr_dec[14-:3] == 3'b000) && (instr_dec[11-:5] == 'h0)) && (instr_dec[19-:5] == 'h0))
					case (1)
						instr_dec[24-:5] == 'h0: next_id_ex[68] = 'b1;
						instr_dec[24-:5] == 'h1: next_id_ex[67] = 'b1;
						(instr_dec[24-:5] == 'h2) && (instr_dec[31-:7] == 'h18): next_id_ex[66] = 'b1;
						(instr_dec[24-:5] == 'h5) && (instr_dec[31-:7] == 'h8): next_id_ex[65] = 'b1;
						default:
							if (fetch_valid_i && id_ready_i) begin
								next_id_ex[0] = 1'b1;
								next_id_ex[32-:32] = fetch_instr_i;
							end
					endcase
				else if (fetch_valid_i && id_ready_i) begin
					next_id_ex[0] = 1'b1;
					next_id_ex[32-:32] = fetch_instr_i;
				end
			end
			default:
				if (fetch_valid_i && id_ready_i) begin
					next_id_ex[0] = 1'b1;
					next_id_ex[32-:32] = fetch_instr_i;
				end
		endcase
		if (((fetch_valid_i && id_ready_i) && wait_inst_ff) && ~wfi_stop_ff)
			next_id_ex[179-:32] = id_ex_ff[179-:32] + 'd4;
		else
			next_id_ex[179-:32] = id_ex_ff[179-:32];
		if (jump_i)
			next_id_ex[179-:32] = pc_jump_i;
		next_id_ex[64-:32] = next_id_ex[179-:32];
		next_wait_inst = wait_inst_ff;
		if (~wait_inst_ff)
			next_wait_inst = fetch_valid_i && id_ready_i;
		else if (jump_i)
			next_wait_inst = 'b0;
		next_wfi_stop = wfi_stop_ff;
		if (wfi_stop_ff == 'b0)
			if ((fetch_valid_i && next_id_ex[65]) && id_ready_i)
				next_wfi_stop = 'b1;
		if (wfi_stop_ff)
			if (jump_i)
				next_wfi_stop = 'b0;
		if (~id_ready_i)
			next_id_ex = id_ex_ff;
	end
	always @(posedge clk)
		if (~rst) begin
			dec_valid_ff <= 'b0;
			id_ex_ff <= 1'sb0;
			id_ex_ff[179-:32] <= pc_reset_i;
			wait_inst_ff <= 'b0;
			wfi_stop_ff <= 'b0;
		end
		else begin
			dec_valid_ff <= next_vld_dec;
			id_ex_ff <= next_id_ex;
			wait_inst_ff <= next_wait_inst;
			wfi_stop_ff <= next_wfi_stop;
		end
	register_file u_register_file(
		.clk(clk),
		.rst(rst),
		.rs1_addr_i(instr_dec[19-:5]),
		.rs2_addr_i(instr_dec[24-:5]),
		.rd_addr_i(wb_dec_i[5-:5]),
		.rd_data_i(wb_dec_i[37-:32]),
		.we_i(wb_dec_i[0]),
		.re_i(id_ready_i),
		.rs1_data_o(rs1_data_o),
		.rs2_data_o(rs2_data_o)
	);
endmodule
module cb_to_ahb (
	cb_mosi_i,
	cb_miso_o,
	ahb_mosi_o,
	ahb_miso_i
);
	input wire [108:0] cb_mosi_i;
	output reg [40:0] cb_miso_o;
	output reg [87:0] ahb_mosi_o;
	input wire [34:0] ahb_miso_i;
	function automatic [1:0] sv2v_cast_2;
		input reg [1:0] inp;
		sv2v_cast_2 = inp;
	endfunction
	always @(*) begin
		ahb_mosi_o = 88'b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
		cb_miso_o = 41'b00000000000000000000000000000000000000000;
		if (cb_mosi_i[74] || cb_mosi_i[1]) begin
			ahb_mosi_o[87-:32] = (cb_mosi_i[74] ? cb_mosi_i[108-:32] : cb_mosi_i[35-:32]);
			ahb_mosi_o[55-:3] = 3'd0;
			ahb_mosi_o[44-:3] = 3'd2;
			ahb_mosi_o[35-:2] = 2'd2;
			ahb_mosi_o[1] = cb_mosi_i[74];
			ahb_mosi_o[0] = 'b1;
		end
		ahb_mosi_o[33-:32] = (cb_mosi_i[37] ? cb_mosi_i[73-:32] : 'h0);
		cb_miso_o[40] = ahb_miso_i[2];
		cb_miso_o[39] = ahb_miso_i[2];
		cb_miso_o[38-:2] = sv2v_cast_2(ahb_miso_i[1]);
		cb_miso_o[36] = 'b1;
		cb_miso_o[35] = ahb_miso_i[2];
		cb_miso_o[34-:32] = ahb_miso_i[34-:32];
		cb_miso_o[2-:2] = sv2v_cast_2(ahb_miso_i[1]);
		cb_miso_o[0] = ~ahb_miso_i[2];
	end
endmodule
module cb_to_axi (
	clk,
	cb_mosi_i,
	cb_miso_o,
	axi_mosi_o,
	axi_miso_i
);
	parameter AXI_ID = 0;
	input clk;
	input wire [108:0] cb_mosi_i;
	output reg [40:0] cb_miso_o;
	output reg [182:0] axi_mosi_o;
	input wire [59:0] axi_miso_i;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic [2:0] sv2v_cast_3;
		input reg [2:0] inp;
		sv2v_cast_3 = inp;
	endfunction
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	function automatic [1:0] sv2v_cast_2;
		input reg [1:0] inp;
		sv2v_cast_2 = inp;
	endfunction
	always @(*) begin
		axi_mosi_o = 183'b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
		cb_miso_o = 41'b00000000000000000000000000000000000000000;
		axi_mosi_o[182-:8] = AXI_ID;
		axi_mosi_o[71-:8] = AXI_ID;
		axi_mosi_o[174-:32] = sv2v_cast_32(cb_mosi_i[108-:32]);
		axi_mosi_o[134-:3] = sv2v_cast_3(cb_mosi_i[76-:2]);
		axi_mosi_o[112] = cb_mosi_i[74];
		axi_mosi_o[111-:32] = sv2v_cast_32(cb_mosi_i[73-:32]);
		axi_mosi_o[73] = cb_mosi_i[37];
		axi_mosi_o[75] = cb_mosi_i[37];
		axi_mosi_o[79-:4] = sv2v_cast_4(cb_mosi_i[41-:4]);
		axi_mosi_o[72] = cb_mosi_i[36];
		axi_mosi_o[63-:32] = sv2v_cast_32(cb_mosi_i[35-:32]);
		axi_mosi_o[23-:3] = sv2v_cast_3(cb_mosi_i[3-:2]);
		axi_mosi_o[1] = cb_mosi_i[1];
		axi_mosi_o[0] = cb_mosi_i[0];
		axi_mosi_o[13-:3] = 3'b010;
		axi_mosi_o[124-:3] = 3'b010;
		cb_miso_o[40] = axi_miso_i[59];
		cb_miso_o[39] = axi_miso_i[58];
		cb_miso_o[38-:2] = sv2v_cast_2(axi_miso_i[49-:2]);
		cb_miso_o[36] = axi_miso_i[46];
		cb_miso_o[35] = axi_miso_i[45];
		cb_miso_o[34-:32] = sv2v_cast_32(axi_miso_i[36-:32]);
		cb_miso_o[2-:2] = sv2v_cast_2(axi_miso_i[4-:2]);
		cb_miso_o[0] = axi_miso_i[0];
	end
endmodule
module nox (
	clk,
	arst,
	start_fetch_i,
	start_addr_i,
	irq_i,
	instr_ahb_mosi_o,
	instr_ahb_miso_i,
	lsu_ahb_mosi_o,
	lsu_ahb_miso_i
);
	parameter signed [31:0] SUPPORT_DEBUG = 1;
	parameter signed [31:0] MTVEC_DEFAULT_VAL = 'h1000;
	parameter signed [31:0] L0_BUFFER_SIZE = 2;
	parameter signed [31:0] TRAP_ON_MIS_LSU_ADDR = 1;
	parameter signed [31:0] TRAP_ON_LSU_ERROR = 1;
	parameter signed [31:0] FETCH_IF_ID = 0;
	parameter signed [31:0] LSU_IF_ID = 1;
	parameter [31:0] M_HART_ID = 0;
	input clk;
	input arst;
	input start_fetch_i;
	input wire [31:0] start_addr_i;
	input wire [2:0] irq_i;
	output wire [87:0] instr_ahb_mosi_o;
	input wire [34:0] instr_ahb_miso_i;
	output wire [87:0] lsu_ahb_mosi_o;
	input wire [34:0] lsu_ahb_miso_i;
	wire rst;
	wire [108:0] instr_cb_mosi;
	wire [108:0] lsu_cb_mosi;
	wire [40:0] instr_cb_miso;
	wire [40:0] lsu_cb_miso;
	wire fetch_valid;
	wire fetch_ready;
	wire [31:0] fetch_instr;
	wire [180:0] id_ex;
	wire [31:0] rs1_data;
	wire [31:0] rs2_data;
	wire id_valid;
	wire id_ready;
	wire [39:0] ex_mem_wb;
	wire [100:0] lsu_op;
	wire lsu_bp;
	wire [31:0] lsu_rd_data;
	wire [100:0] lsu_op_wb;
	wire fetch_req;
	wire [31:0] fetch_addr;
	wire [37:0] wb_dec;
	wire lsu_bp_data;
	wire [64:0] fetch_trap;
	wire [259:0] lsu_trap;
	wire [31:0] wb_fwd_load;
	wire lock_wb;
	wire [31:0] lsu_pc;
	reset_sync #(.RST_MODE(0)) u_reset_sync(
		.arst_i(arst),
		.clk(clk),
		.rst_o(rst)
	);
	cb_to_ahb u_instr_cb_to_ahb(
		.cb_mosi_i(instr_cb_mosi),
		.cb_miso_o(instr_cb_miso),
		.ahb_mosi_o(instr_ahb_mosi_o),
		.ahb_miso_i(instr_ahb_miso_i)
	);
	cb_to_ahb u_lsu_cb_to_ahb(
		.cb_mosi_i(lsu_cb_mosi),
		.cb_miso_o(lsu_cb_miso),
		.ahb_mosi_o(lsu_ahb_mosi_o),
		.ahb_miso_i(lsu_ahb_miso_i)
	);
	fetch #(
		.SUPPORT_DEBUG(SUPPORT_DEBUG),
		.L0_BUFFER_SIZE(L0_BUFFER_SIZE)
	) u_fetch(
		.clk(clk),
		.rst(rst),
		.instr_cb_mosi_o(instr_cb_mosi),
		.instr_cb_miso_i(instr_cb_miso),
		.fetch_start_i(start_fetch_i),
		.fetch_start_addr_i(start_addr_i),
		.fetch_req_i(fetch_req),
		.fetch_addr_i(fetch_addr),
		.fetch_valid_o(fetch_valid),
		.fetch_ready_i(fetch_ready),
		.fetch_instr_o(fetch_instr),
		.trap_info_o(fetch_trap)
	);
	decode #(.SUPPORT_DEBUG(SUPPORT_DEBUG)) u_decode(
		.clk(clk),
		.rst(rst),
		.jump_i(fetch_req),
		.pc_jump_i(fetch_addr),
		.pc_reset_i(start_addr_i),
		.fetch_valid_i(fetch_valid),
		.fetch_ready_o(fetch_ready),
		.fetch_instr_i(fetch_instr),
		.wb_dec_i(wb_dec),
		.id_ex_o(id_ex),
		.rs1_data_o(rs1_data),
		.rs2_data_o(rs2_data),
		.id_valid_o(id_valid),
		.id_ready_i(id_ready)
	);
	execute #(
		.SUPPORT_DEBUG(SUPPORT_DEBUG),
		.MTVEC_DEFAULT_VAL(MTVEC_DEFAULT_VAL),
		.M_HART_ID(M_HART_ID)
	) u_execute(
		.clk(clk),
		.rst(rst),
		.wb_value_i(wb_dec[37-:32]),
		.wb_load_i(wb_fwd_load),
		.lock_wb_i(lock_wb),
		.id_ex_i(id_ex),
		.rs1_data_i(rs1_data),
		.rs2_data_i(rs2_data),
		.id_valid_i(id_valid),
		.id_ready_o(id_ready),
		.ex_mem_wb_o(ex_mem_wb),
		.lsu_o(lsu_op),
		.lsu_bp_i(lsu_bp),
		.lsu_pc_i(lsu_pc),
		.irq_i(irq_i),
		.fetch_req_o(fetch_req),
		.fetch_addr_o(fetch_addr),
		.fetch_trap_i(fetch_trap),
		.lsu_trap_i(lsu_trap)
	);
	lsu #(
		.SUPPORT_DEBUG(SUPPORT_DEBUG),
		.TRAP_ON_MIS_LSU_ADDR(TRAP_ON_MIS_LSU_ADDR),
		.TRAP_ON_LSU_ERROR(TRAP_ON_LSU_ERROR)
	) u_lsu(
		.clk(clk),
		.rst(rst),
		.lsu_i(lsu_op),
		.lsu_bp_o(lsu_bp),
		.lsu_pc_o(lsu_pc),
		.lsu_bp_data_o(lsu_bp_data),
		.wb_lsu_o(lsu_op_wb),
		.lsu_data_o(lsu_rd_data),
		.data_cb_mosi_o(lsu_cb_mosi),
		.data_cb_miso_i(lsu_cb_miso),
		.lsu_trap_o(lsu_trap)
	);
	wb u_wb(
		.clk(clk),
		.rst(rst),
		.ex_mem_wb_i(ex_mem_wb),
		.wb_lsu_i(lsu_op_wb),
		.lsu_rd_data_i(lsu_rd_data),
		.lsu_bp_i(lsu_bp),
		.lsu_bp_data_i(lsu_bp_data),
		.wb_dec_o(wb_dec),
		.wb_fwd_load_o(wb_fwd_load),
		.lock_wb_o(lock_wb)
	);
endmodule
module skid_buffer (
	clk,
	rst,
	in_valid_i,
	in_ready_o,
	in_data_i,
	out_valid_o,
	out_ready_i,
	out_data_o
);
	parameter signed [31:0] DATA_WIDTH = 1;
	input clk;
	input rst;
	input in_valid_i;
	output reg in_ready_o;
	input [DATA_WIDTH - 1:0] in_data_i;
	output reg out_valid_o;
	input out_ready_i;
	output reg [DATA_WIDTH - 1:0] out_data_o;
	reg [1:0] st_ff;
	reg [1:0] next_st;
	reg [DATA_WIDTH - 1:0] data_bf_ff;
	reg [DATA_WIDTH - 1:0] next_data_bf;
	reg [DATA_WIDTH - 1:0] data_out_ff;
	reg [DATA_WIDTH - 1:0] next_data_out;
	always @(*) begin : out_ctrl
		in_ready_o = 'b0;
		out_valid_o = 'b0;
		next_data_bf = data_bf_ff;
		next_data_out = data_out_ff;
		out_data_o = data_out_ff;
		case (st_ff)
			2'd0: begin
				in_ready_o = 'b1;
				if (in_valid_i)
					next_data_out = in_data_i;
			end
			2'd1: begin
				in_ready_o = 'b1;
				out_valid_o = 'b1;
				if (in_valid_i && ~out_ready_i)
					next_data_bf = in_data_i;
				if (in_valid_i && out_ready_i)
					next_data_out = in_data_i;
			end
			2'd2: begin
				out_valid_o = 'b1;
				if (out_ready_i)
					next_data_out = data_bf_ff;
			end
			default: out_data_o = 'b0;
		endcase
	end
	always @(*) begin : fsm_ctrl
		next_st = st_ff;
		case (st_ff)
			2'd0:
				if (in_valid_i)
					next_st = 2'd1;
			2'd1: begin
				if (in_valid_i && ~out_ready_i)
					next_st = 2'd2;
				if (~in_valid_i && out_ready_i)
					next_st = 2'd0;
			end
			2'd2:
				if (out_ready_i)
					next_st = 2'd1;
			default: next_st = 2'd0;
		endcase
	end
	always @(posedge clk)
		if (~rst) begin
			st_ff <= 2'd0;
			data_bf_ff <= 1'sb0;
			data_out_ff <= 1'sb0;
		end
		else begin
			st_ff <= next_st;
			data_bf_ff <= next_data_bf;
			data_out_ff <= next_data_out;
		end
endmodule
module fetch (
	clk,
	rst,
	instr_cb_mosi_o,
	instr_cb_miso_i,
	fetch_start_i,
	fetch_start_addr_i,
	fetch_req_i,
	fetch_addr_i,
	fetch_valid_o,
	fetch_ready_i,
	fetch_instr_o,
	trap_info_o
);
	parameter signed [31:0] SUPPORT_DEBUG = 1;
	parameter signed [31:0] L0_BUFFER_SIZE = 2;
	input clk;
	input rst;
	output reg [108:0] instr_cb_mosi_o;
	input wire [40:0] instr_cb_miso_i;
	input fetch_start_i;
	input wire [31:0] fetch_start_addr_i;
	input fetch_req_i;
	input wire [31:0] fetch_addr_i;
	output reg fetch_valid_o;
	input wire fetch_ready_i;
	output reg [31:0] fetch_instr_o;
	output reg [64:0] trap_info_o;
	reg get_next_instr;
	reg write_instr;
	wire [$clog2(L0_BUFFER_SIZE):0] buffer_space;
	wire [31:0] instr_buffer;
	wire full_fifo;
	reg data_valid;
	reg data_ready;
	reg jump;
	reg clear_fifo;
	reg valid_addr;
	reg read_ot_fifo;
	wire ot_empty;
	reg [31:0] pc_addr_ff;
	reg [31:0] next_pc_addr;
	reg [31:0] pc_buff_ff;
	reg [31:0] next_pc_buff;
	reg req_ff;
	reg next_req;
	reg valid_txn_i;
	wire valid_txn_o;
	reg addr_ready;
	reg instr_access_fault;
	reg [1:0] st_ff;
	reg [1:0] next_st;
	reg [$clog2(L0_BUFFER_SIZE):0] ot_cnt_ff;
	reg [$clog2(L0_BUFFER_SIZE):0] next_ot;
	function automatic [($clog2(L0_BUFFER_SIZE) >= 0 ? $clog2(L0_BUFFER_SIZE) + 1 : 1 - $clog2(L0_BUFFER_SIZE)) - 1:0] sv2v_cast_47DFB;
		input reg [($clog2(L0_BUFFER_SIZE) >= 0 ? $clog2(L0_BUFFER_SIZE) + 1 : 1 - $clog2(L0_BUFFER_SIZE)) - 1:0] inp;
		sv2v_cast_47DFB = inp;
	endfunction
	always @(*) begin : addr_chn_req
		instr_cb_mosi_o[108-:32] = 32'b00000000000000000000000000000000;
		instr_cb_mosi_o[76-:2] = 2'b00;
		instr_cb_mosi_o[74] = 1'b0;
		instr_cb_mosi_o[73-:32] = 32'b00000000000000000000000000000000;
		instr_cb_mosi_o[41-:4] = 4'b0000;
		instr_cb_mosi_o[37] = 1'b0;
		instr_cb_mosi_o[36] = 1'b0;
		data_valid = instr_cb_miso_i[0];
		addr_ready = instr_cb_miso_i[35];
		clear_fifo = fetch_req_i || ~fetch_start_i;
		valid_addr = 1'b0;
		next_pc_addr = pc_addr_ff;
		next_pc_buff = pc_buff_ff;
		next_st = st_ff;
		jump = fetch_req_i;
		valid_txn_i = 1'b0;
		next_ot = (ot_cnt_ff + (req_ff && addr_ready)) - (data_valid && data_ready);
		case (st_ff)
			2'd0: begin
				next_st = (fetch_start_i ? 2'd1 : 2'd0);
				if (req_ff && ~addr_ready) begin
					valid_addr = 1'b1;
					valid_txn_i = 1'b0;
				end
			end
			2'd1: begin
				if (req_ff && ~addr_ready) begin
					valid_addr = 1'b1;
					valid_txn_i = 1'b1;
				end
				if (req_ff && addr_ready) begin
					valid_txn_i = 1'b1;
					next_pc_addr = pc_addr_ff + 'd4;
				end
				if ((req_ff && addr_ready) || ~req_ff)
					if (next_ot < sv2v_cast_47DFB(L0_BUFFER_SIZE))
						valid_addr = ~full_fifo;
				if (jump) begin
					next_pc_addr = fetch_addr_i;
					next_pc_buff = pc_addr_ff;
					valid_txn_i = 1'b0;
					if ((req_ff && ~addr_ready) || (next_ot > 'd0))
						next_st = 2'd2;
					if (req_ff && addr_ready)
						valid_addr = 1'b0;
				end
				if (~fetch_start_i)
					next_st = 2'd0;
			end
			2'd2: begin
				valid_txn_i = 1'b0;
				if (req_ff && ~addr_ready)
					valid_addr = 1'b1;
				else if (next_ot == {($clog2(L0_BUFFER_SIZE) >= 0 ? $clog2(L0_BUFFER_SIZE) + 1 : 1 - $clog2(L0_BUFFER_SIZE)) {1'sb0}}) begin
					next_st = 2'd1;
					valid_addr = 1'b1;
				end
			end
			default: valid_addr = 1'b0;
		endcase
		next_req = valid_addr;
		instr_cb_mosi_o[1] = req_ff;
		instr_cb_mosi_o[35-:32] = (req_ff ? (st_ff == 2'd2 ? pc_buff_ff : pc_addr_ff) : {32 {1'sb0}});
		instr_cb_mosi_o[3-:2] = (req_ff ? 2'd2 : 2'b00);
	end
	always @(*) begin : rd_chn
		write_instr = 'b0;
		data_ready = (st_ff == 2'd1 ? ~full_fifo : 'b1);
		instr_cb_mosi_o[0] = data_ready;
		read_ot_fifo = (ot_empty ? 1'b0 : data_valid && data_ready);
		if ((((~fetch_req_i && ~ot_empty) && valid_txn_o) && data_valid) && ~full_fifo)
			write_instr = 'b1;
	end
	always @(*) begin : trap_control
		trap_info_o = 65'b00000000000000000000000000000000000000000000000000000000000000000;
		instr_access_fault = instr_cb_miso_i[0] && (instr_cb_miso_i[2-:2] != 2'd0);
		if (instr_access_fault) begin
			trap_info_o[0] = 'b1;
			trap_info_o[64-:32] = pc_addr_ff;
			trap_info_o[32-:32] = pc_addr_ff;
		end
	end
	always @(posedge clk)
		if (~rst) begin
			pc_addr_ff <= fetch_start_addr_i;
			pc_buff_ff <= fetch_start_addr_i;
			st_ff <= 2'd0;
			req_ff <= 1'b0;
			ot_cnt_ff <= sv2v_cast_47DFB(1'sb0);
		end
		else begin
			pc_addr_ff <= next_pc_addr;
			pc_buff_ff <= next_pc_buff;
			st_ff <= next_st;
			req_ff <= next_req;
			ot_cnt_ff <= next_ot;
		end
	always @(*) begin : fetch_proc_if
		fetch_valid_o = 'b0;
		fetch_instr_o = 'd0;
		get_next_instr = 'b0;
		if ((fetch_start_i && ~fetch_req_i) && (buffer_space != 'd0)) begin
			fetch_valid_o = 'b1;
			fetch_instr_o = instr_buffer;
			get_next_instr = fetch_ready_i;
		end
	end
	fifo_nox #(
		.SLOTS(L0_BUFFER_SIZE),
		.WIDTH(1)
	) u_fifo_ot_rd(
		.clk(clk),
		.rst(rst),
		.clear_i(clear_fifo),
		.write_i(req_ff && addr_ready),
		.read_i(read_ot_fifo),
		.data_i(valid_txn_i),
		.data_o(valid_txn_o),
		.empty_o(ot_empty)
	);
	fifo_nox #(
		.SLOTS(L0_BUFFER_SIZE),
		.WIDTH(32)
	) u_fifo_l0(
		.clk(clk),
		.rst(rst),
		.clear_i(clear_fifo),
		.write_i(write_instr),
		.read_i(get_next_instr),
		.data_i(instr_cb_miso_i[34-:32]),
		.data_o(instr_buffer),
		.full_o(full_fifo),
		.ocup_o(buffer_space)
	);
endmodule
module fifo_nox (
	clk,
	rst,
	clear_i,
	write_i,
	read_i,
	data_i,
	data_o,
	error_o,
	full_o,
	empty_o,
	ocup_o
);
	parameter signed [31:0] SLOTS = 2;
	parameter signed [31:0] WIDTH = 8;
	input clk;
	input rst;
	input clear_i;
	input write_i;
	input read_i;
	input [WIDTH - 1:0] data_i;
	output reg [WIDTH - 1:0] data_o;
	output reg error_o;
	output reg full_o;
	output reg empty_o;
	output reg [$clog2((SLOTS > 1 ? SLOTS : 2)):0] ocup_o;
	reg [(SLOTS * WIDTH) - 1:0] fifo_ff;
	reg [$clog2((SLOTS > 1 ? SLOTS : 2)):0] write_ptr_ff;
	reg [$clog2((SLOTS > 1 ? SLOTS : 2)):0] read_ptr_ff;
	reg [$clog2((SLOTS > 1 ? SLOTS : 2)):0] next_write_ptr;
	reg [$clog2((SLOTS > 1 ? SLOTS : 2)):0] next_read_ptr;
	reg [$clog2((SLOTS > 1 ? SLOTS : 2)):0] fifo_ocup;
	always @(*) begin
		next_read_ptr = read_ptr_ff;
		next_write_ptr = write_ptr_ff;
		empty_o = write_ptr_ff == read_ptr_ff;
		full_o = (write_ptr_ff[$clog2((SLOTS > 1 ? SLOTS : 2)) - 1:0] == read_ptr_ff[$clog2((SLOTS > 1 ? SLOTS : 2)) - 1:0]) && (write_ptr_ff[$clog2((SLOTS > 1 ? SLOTS : 2))] != read_ptr_ff[$clog2((SLOTS > 1 ? SLOTS : 2))]);
		data_o = (empty_o ? {WIDTH {1'sb0}} : fifo_ff[read_ptr_ff[$clog2((SLOTS > 1 ? SLOTS : 2)) - 1:0] * WIDTH+:WIDTH]);
		if (write_i && ~full_o)
			next_write_ptr = write_ptr_ff + 'd1;
		if (read_i && ~empty_o)
			next_read_ptr = read_ptr_ff + 'd1;
		error_o = (write_i && full_o) || (read_i && empty_o);
		fifo_ocup = write_ptr_ff - read_ptr_ff;
		ocup_o = fifo_ocup;
		if (clear_i) begin
			next_read_ptr = 'd0;
			next_write_ptr = 'd0;
			data_o = 'd0;
			ocup_o = 'd0;
		end
	end
	always @(posedge clk)
		if (~rst) begin
			write_ptr_ff <= 1'sb0;
			read_ptr_ff <= 1'sb0;
		end
		else begin
			write_ptr_ff <= next_write_ptr;
			read_ptr_ff <= next_read_ptr;
			if (write_i && ~full_o)
				fifo_ff[write_ptr_ff[$clog2((SLOTS > 1 ? SLOTS : 2)) - 1:0] * WIDTH+:WIDTH] <= data_i;
		end
	initial begin
		begin : illegal_fifo_slot
			
		end
		begin : min_fifo_size
			
		end
	end
endmodule
module lsu (
	clk,
	rst,
	lsu_i,
	lsu_bp_o,
	lsu_pc_o,
	lsu_bp_data_o,
	wb_lsu_o,
	lsu_data_o,
	data_cb_mosi_o,
	data_cb_miso_i,
	lsu_trap_o
);
	parameter signed [31:0] SUPPORT_DEBUG = 1;
	parameter signed [31:0] TRAP_ON_MIS_LSU_ADDR = 0;
	parameter signed [31:0] TRAP_ON_LSU_ERROR = 0;
	input clk;
	input rst;
	input wire [100:0] lsu_i;
	output reg lsu_bp_o;
	output reg [31:0] lsu_pc_o;
	output reg lsu_bp_data_o;
	output reg [100:0] wb_lsu_o;
	output reg [31:0] lsu_data_o;
	output reg [108:0] data_cb_mosi_o;
	input wire [40:0] data_cb_miso_i;
	output reg [259:0] lsu_trap_o;
	reg [100:0] lsu_ff;
	reg [100:0] next_lsu;
	reg bp_addr;
	reg bp_data;
	reg ap_txn;
	reg ap_rd_txn;
	reg ap_wr_txn;
	reg dp_txn;
	reg dp_rd_txn;
	reg dp_wr_txn;
	reg dp_done_ff;
	reg next_dp_done;
	reg lock_ff;
	reg next_lock;
	reg unaligned_lsu;
	reg [31:0] locked_addr_ff;
	reg [31:0] next_locked_addr;
	reg [31:0] lsu_req_addr;
	function automatic [3:0] mask_strobe;
		input reg [2:0] size;
		input reg [1:0] shift_left;
		reg [3:0] mask;
		reg [0:1] _sv2v_jump;
		begin
			_sv2v_jump = 2'b00;
			case (size)
				3'b000: mask = 4'b0001;
				3'b001: mask = 4'b0011;
				3'b100: mask = 4'b0001;
				3'b101: mask = 4'b0011;
				3'b010: mask = 4'b1111;
				default: mask = 4'b1111;
			endcase
			begin : sv2v_autoblock_1
				reg signed [31:0] i;
				for (i = 0; i < 4; i = i + 1)
					if (_sv2v_jump < 2'b10) begin
						_sv2v_jump = 2'b00;
						if (i[1:0] == shift_left) begin
							mask_strobe = mask;
							_sv2v_jump = 2'b11;
						end
						else
							mask = {mask[2:0], 1'b0};
					end
				if (_sv2v_jump != 2'b11)
					_sv2v_jump = 2'b00;
			end
			if (_sv2v_jump == 2'b00) begin
				mask_strobe = mask;
				_sv2v_jump = 2'b11;
			end
		end
	endfunction
	always @(*) begin
		next_dp_done = dp_done_ff;
		data_cb_mosi_o = 109'b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
		data_cb_mosi_o[0] = 'b1;
		data_cb_mosi_o[36] = 'b1;
		lsu_bp_o = 'b0;
		ap_txn = lsu_i[100-:2] != 2'd0;
		ap_rd_txn = lsu_i[100-:2] == 2'd1;
		ap_wr_txn = lsu_i[100-:2] == 2'd2;
		dp_txn = lsu_ff[100-:2] != 2'd0;
		dp_rd_txn = lsu_ff[100-:2] == 2'd1;
		dp_wr_txn = lsu_ff[100-:2] == 2'd2;
		bp_data = 'b0;
		if (dp_txn) begin
			if (~dp_done_ff)
				bp_data = (dp_rd_txn ? ~data_cb_miso_i[0] : ~data_cb_miso_i[39]);
			if (dp_wr_txn) begin
				data_cb_mosi_o[41-:4] = mask_strobe(lsu_ff[98-:3], lsu_ff[65:64]);
				begin : sv2v_autoblock_2
					reg signed [31:0] i;
					for (i = 0; i < 4; i = i + 1)
						begin
							if (lsu_ff[65:64] == i[1:0])
								data_cb_mosi_o[73-:32] = lsu_ff[63-:32] << (8 * i);
							data_cb_mosi_o[42 + (i * 8)+:8] = (data_cb_mosi_o[38 + i] ? data_cb_mosi_o[42 + (i * 8)+:8] : 8'h00);
						end
				end
				data_cb_mosi_o[37] = ~dp_done_ff;
			end
			next_dp_done = ~bp_data;
		end
		if (lock_ff)
			lsu_req_addr = locked_addr_ff;
		else
			lsu_req_addr = lsu_i[95-:32];
		bp_addr = 'b0;
		if (ap_txn) begin
			bp_addr = (ap_rd_txn ? ~data_cb_miso_i[35] : ~data_cb_miso_i[40]);
			if (ap_wr_txn) begin
				data_cb_mosi_o[108-:32] = {lsu_req_addr[31:2], 2'b00};
				data_cb_mosi_o[76-:2] = 2'd2;
				data_cb_mosi_o[74] = ~bp_data;
			end
			else begin
				data_cb_mosi_o[35-:32] = {lsu_req_addr[31:2], 2'b00};
				data_cb_mosi_o[3-:2] = 2'd2;
				data_cb_mosi_o[1] = ~bp_data;
			end
		end
		next_lock = lock_ff;
		next_locked_addr = locked_addr_ff;
		if (ap_txn)
			next_lock = (ap_rd_txn ? data_cb_mosi_o[1] && ~data_cb_miso_i[35] : data_cb_mosi_o[74] && ~data_cb_miso_i[40]);
		next_locked_addr = (lock_ff ? locked_addr_ff : lsu_req_addr);
		lsu_bp_o = bp_addr || bp_data;
		lsu_bp_data_o = bp_data;
		next_lsu = lsu_ff;
		if (~lsu_bp_o) begin
			next_lsu = lsu_i;
			next_lsu[95-:32] = (lock_ff ? locked_addr_ff : lsu_i[95-:32]);
			next_dp_done = 'b0;
		end
		wb_lsu_o = lsu_ff;
		lsu_data_o = data_cb_miso_i[34-:32];
		lsu_pc_o = lsu_ff[31-:32];
	end
	always @(*) begin : trap_lsu
		lsu_trap_o = 260'b0;
		unaligned_lsu = 'b0;
		case (lsu_i[98-:3])
			3'b000: unaligned_lsu = 'b0;
			3'b001: unaligned_lsu = lsu_req_addr[1:0] == 'd3;
			3'b100: unaligned_lsu = 'b0;
			3'b101: unaligned_lsu = lsu_req_addr[1:0] == 'd3;
			3'b010: unaligned_lsu = lsu_req_addr[1:0] != 'd0;
			default: unaligned_lsu = 'b0;
		endcase
		if ((lsu_i[100-:2] != 2'd0) && unaligned_lsu) begin
			if ((lsu_i[100-:2] == 2'd1) && data_cb_mosi_o[1])
				lsu_trap_o[0] = TRAP_ON_MIS_LSU_ADDR == 'b1;
			if ((lsu_i[100-:2] == 2'd2) && data_cb_mosi_o[74])
				lsu_trap_o[65] = TRAP_ON_MIS_LSU_ADDR == 'b1;
		end
		if (data_cb_miso_i[36] && (data_cb_miso_i[38-:2] != 2'd0))
			lsu_trap_o[195] = TRAP_ON_LSU_ERROR == 'b1;
		if (data_cb_miso_i[0] && (data_cb_miso_i[2-:2] != 2'd0))
			lsu_trap_o[130] = TRAP_ON_LSU_ERROR == 'b1;
	end
	always @(posedge clk)
		if (~rst) begin
			lsu_ff <= 101'b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
			dp_done_ff <= 'b0;
			lock_ff <= 'b0;
			locked_addr_ff <= 1'sb0;
		end
		else begin
			lsu_ff <= next_lsu;
			dp_done_ff <= next_dp_done;
			lock_ff <= next_lock;
			locked_addr_ff <= next_locked_addr;
		end
endmodule
module reset_sync (
	arst_i,
	clk,
	rst_o
);
	parameter signed [31:0] RST_MODE = 0;
	input arst_i;
	input clk;
	output reg rst_o;
	reg rst_ff;
	reg meta_rst_ff;
	wire rstn_ff;
	wire meta_rstn_ff;
	always @(*) rst_o = rst_ff;
	generate
		if (RST_MODE == 1) begin : gen_rst_act_h
			always @(posedge clk or posedge arst_i) begin : act_high
				if (arst_i)
					{rst_ff, meta_rst_ff} <= 2'b11;
				else
					{rst_ff, meta_rst_ff} <= {meta_rst_ff, 1'b0};
			end
		end
		else begin : gen_rst_act_l
			always @(posedge clk or negedge arst_i) begin : act_low
				if (!arst_i)
					{rst_ff, meta_rst_ff} <= 2'b00;
				else
					{rst_ff, meta_rst_ff} <= {meta_rst_ff, 1'b1};
			end
		end
	endgenerate
endmodule
module execute (
	clk,
	rst,
	wb_value_i,
	wb_load_i,
	lock_wb_i,
	id_ex_i,
	rs1_data_i,
	rs2_data_i,
	id_valid_i,
	id_ready_o,
	ex_mem_wb_o,
	lsu_o,
	lsu_bp_i,
	lsu_pc_i,
	irq_i,
	fetch_req_o,
	fetch_addr_o,
	fetch_trap_i,
	lsu_trap_i
);
	parameter signed [31:0] SUPPORT_DEBUG = 1;
	parameter signed [31:0] MTVEC_DEFAULT_VAL = 'h1000;
	parameter [31:0] M_HART_ID = 0;
	input clk;
	input rst;
	input wire [31:0] wb_value_i;
	input wire [31:0] wb_load_i;
	input lock_wb_i;
	input wire [180:0] id_ex_i;
	input wire [31:0] rs1_data_i;
	input wire [31:0] rs2_data_i;
	input wire id_valid_i;
	output reg id_ready_o;
	output reg [39:0] ex_mem_wb_o;
	output reg [100:0] lsu_o;
	input lsu_bp_i;
	input wire [31:0] lsu_pc_i;
	input wire [2:0] irq_i;
	output reg fetch_req_o;
	output reg [31:0] fetch_addr_o;
	input wire [64:0] fetch_trap_i;
	input wire [259:0] lsu_trap_i;
	reg [39:0] ex_mem_wb_ff;
	reg [39:0] next_ex_mem_wb;
	reg [31:0] op1;
	reg [31:0] op2;
	reg [31:0] res;
	reg rs1_fwd;
	reg rs2_fwd;
	reg fwd_wdata;
	reg jump_or_branch;
	reg [33:0] branch_ff;
	reg [33:0] next_branch;
	reg [32:0] jump_ff;
	reg [32:0] next_jump;
	wire [31:0] csr_rdata;
	wire [64:0] trap_out;
	reg will_jump_next_clk;
	reg eval_trap;
	reg [64:0] instr_addr_misaligned;
	function automatic branch_dec;
		input reg [2:0] op;
		input reg [31:0] rs1;
		input reg [31:0] rs2;
		reg take_branch;
		begin
			case (op)
				3'b000: take_branch = rs1 == rs2;
				3'b001: take_branch = rs1 != rs2;
				3'b100: take_branch = $signed(rs1) < $signed(rs2);
				3'b101: take_branch = $signed(rs1) >= $signed(rs2);
				3'b110: take_branch = rs1 < rs2;
				3'b111: take_branch = rs1 >= rs2;
				default: take_branch = 'b0;
			endcase
			branch_dec = take_branch;
		end
	endfunction
	always @(*) begin : fwd_mux
		rs1_fwd = 1'd0;
		rs2_fwd = 1'd0;
		if ((ex_mem_wb_ff[36-:5] != 'h0) && ex_mem_wb_ff[37]) begin
			if ((id_ex_i[147-:2] == 2'd0) && (id_ex_i[94-:5] == ex_mem_wb_ff[36-:5]))
				rs1_fwd = 1'd1;
			if ((id_ex_i[145-:2] == 2'd0) && (id_ex_i[89-:5] == ex_mem_wb_ff[36-:5]))
				rs2_fwd = 1'd1;
		end
	end
	always @(*) begin : alu_proc
		op1 = 32'b00000000000000000000000000000000;
		op2 = 32'b00000000000000000000000000000000;
		res = 32'b00000000000000000000000000000000;
		id_ready_o = 'b1;
		next_ex_mem_wb = ex_mem_wb_ff;
		case (id_ex_i[147-:2])
			2'd0: op1 = rs1_data_i;
			2'd1: op1 = id_ex_i[126-:32];
			2'd2: op1 = 32'b00000000000000000000000000000000;
			2'd3: op1 = id_ex_i[179-:32];
			default: op1 = 32'b00000000000000000000000000000000;
		endcase
		op1 = (rs1_fwd == 1'd1 ? wb_value_i : op1);
		case (id_ex_i[145-:2])
			2'd0: op2 = rs2_data_i;
			2'd1: op2 = id_ex_i[126-:32];
			2'd2: op2 = 32'b00000000000000000000000000000000;
			2'd3: op2 = id_ex_i[179-:32];
			default: op2 = 32'b00000000000000000000000000000000;
		endcase
		op2 = (rs2_fwd == 1'd1 ? wb_value_i : op2);
		case (id_ex_i[130-:3])
			3'b000: res = (id_ex_i[136] == 1'd1 ? op1 - op2 : op1 + op2);
			3'b010: res = ($signed(op1) < $signed(op2) ? 'd1 : 'd0);
			3'b011: res = (op1 < op2 ? 'd1 : 'd0);
			3'b100: res = op1 ^ op2;
			3'b110: res = op1 | op2;
			3'b111: res = op1 & op2;
			3'b001: res = (id_ex_i[145-:2] == 2'd1 ? op1 << op2[4:0] : op1 << op2[4:0]);
			3'b101: res = (id_ex_i[127] == 1'b1 ? $signed($signed(op1) >>> op2[4:0]) : op1 >> op2[4:0]);
			default: res = 'd0;
		endcase
		next_ex_mem_wb[31-:32] = (id_ex_i[137] ? id_ex_i[179-:32] + 32'd4 : res);
		next_ex_mem_wb[36-:5] = id_ex_i[135-:5];
		next_ex_mem_wb[37] = id_ex_i[180];
		if (lsu_bp_i) begin
			next_ex_mem_wb = ex_mem_wb_ff;
			id_ready_o = 'b0;
		end
		if (jump_or_branch)
			next_ex_mem_wb[37] = 'b0;
		if (id_ex_i[84-:3] != 3'b000)
			next_ex_mem_wb[31-:32] = csr_rdata;
		ex_mem_wb_o = ex_mem_wb_ff;
		if (trap_out[0])
			ex_mem_wb_o[37] = 'b0;
	end
	always @(*) begin : jump_lsu_mgmt
		instr_addr_misaligned = 65'b00000000000000000000000000000000000000000000000000000000000000000;
		jump_or_branch = (branch_ff[32] && branch_ff[33]) || jump_ff[32];
		next_branch[32] = id_ex_i[138] && ~lsu_bp_i;
		next_branch[31-:32] = id_ex_i[179-:32] + id_ex_i[126-:32];
		next_branch[33] = ~jump_or_branch && branch_dec(id_ex_i[130-:3], op1, op2);
		next_jump[32] = (~jump_or_branch && id_ex_i[137]) && ~lsu_bp_i;
		next_jump[31-:32] = {res[31:1], 1'b0};
		fwd_wdata = (((id_ex_i[143-:2] == 2'd2) && ex_mem_wb_ff[37]) && (ex_mem_wb_ff[36-:5] == id_ex_i[89-:5])) && (ex_mem_wb_ff[36-:5] != 5'h00);
		lsu_o[100-:2] = id_ex_i[143-:2];
		lsu_o[98-:3] = id_ex_i[141-:3];
		lsu_o[95-:32] = res;
		lsu_o[63-:32] = rs2_data_i;
		lsu_o[31-:32] = id_ex_i[179-:32];
		if (fwd_wdata)
			lsu_o[63-:32] = (lock_wb_i ? wb_load_i : wb_value_i);
		will_jump_next_clk = next_branch[32] || next_jump[32];
		if (will_jump_next_clk && next_jump[32]) begin
			instr_addr_misaligned[0] = next_jump[1];
			instr_addr_misaligned[32-:32] = next_jump[31-:32];
		end
		if (will_jump_next_clk && next_branch[32]) begin
			instr_addr_misaligned[0] = next_branch[1] || next_branch[0];
			instr_addr_misaligned[32-:32] = next_branch[31-:32];
		end
	end
	always @(*) begin : fetch_req
		fetch_req_o = 1'sb0;
		fetch_addr_o = 1'sb0;
		fetch_req_o = (branch_ff[32] && branch_ff[33]) || jump_ff[32];
		fetch_addr_o = (branch_ff[32] ? branch_ff[31-:32] : jump_ff[31-:32]);
		if (trap_out[0]) begin
			fetch_req_o = 'b1;
			fetch_addr_o = trap_out[64-:32];
		end
		eval_trap = ((id_ready_o && id_valid_i) && ~fetch_req_o) && (lsu_o[100-:2] == 2'd0);
	end
	always @(posedge clk)
		if (~rst) begin
			ex_mem_wb_ff <= 1'sb0;
			branch_ff <= 34'h000000000;
			jump_ff <= 33'h000000000;
		end
		else begin
			ex_mem_wb_ff <= next_ex_mem_wb;
			branch_ff <= next_branch;
			jump_ff <= next_jump;
		end
	csr #(
		.SUPPORT_DEBUG(SUPPORT_DEBUG),
		.MTVEC_DEFAULT_VAL(MTVEC_DEFAULT_VAL),
		.M_HART_ID(M_HART_ID)
	) u_csr(
		.clk(clk),
		.rst(rst),
		.stall_i(lsu_bp_i),
		.csr_i(id_ex_i[84-:16]),
		.rs1_data_i(op1),
		.imm_i(id_ex_i[126-:32]),
		.csr_rd_o(csr_rdata),
		.pc_addr_i(id_ex_i[179-:32]),
		.pc_lsu_i(lsu_pc_i),
		.irq_i(irq_i),
		.will_jump_i(will_jump_next_clk),
		.eval_trap_i(eval_trap),
		.dec_trap_i(id_ex_i[64-:65]),
		.instr_addr_mis_i(instr_addr_misaligned),
		.fetch_trap_i(fetch_trap_i),
		.ecall_i(id_ex_i[68]),
		.ebreak_i(id_ex_i[67]),
		.mret_i(id_ex_i[66]),
		.wfi_i(id_ex_i[65]),
		.lsu_trap_i(lsu_trap_i),
		.trap_o(trap_out)
	);
endmodule
module csr (
	clk,
	rst,
	stall_i,
	csr_i,
	rs1_data_i,
	imm_i,
	csr_rd_o,
	pc_addr_i,
	pc_lsu_i,
	irq_i,
	will_jump_i,
	eval_trap_i,
	dec_trap_i,
	instr_addr_mis_i,
	fetch_trap_i,
	ecall_i,
	ebreak_i,
	mret_i,
	wfi_i,
	lsu_trap_i,
	trap_o
);
	parameter signed [31:0] SUPPORT_DEBUG = 1;
	parameter signed [31:0] MTVEC_DEFAULT_VAL = 'h1000;
	parameter [31:0] M_HART_ID = 0;
	input clk;
	input rst;
	input stall_i;
	input wire [15:0] csr_i;
	input wire [31:0] rs1_data_i;
	input wire [31:0] imm_i;
	output reg [31:0] csr_rd_o;
	input wire [31:0] pc_addr_i;
	input wire [31:0] pc_lsu_i;
	input wire [2:0] irq_i;
	input will_jump_i;
	input eval_trap_i;
	input wire [64:0] dec_trap_i;
	input wire [64:0] instr_addr_mis_i;
	input wire [64:0] fetch_trap_i;
	input ecall_i;
	input ebreak_i;
	input mret_i;
	input wfi_i;
	input wire [259:0] lsu_trap_i;
	output reg [64:0] trap_o;
	reg mcause_interrupt;
	reg [31:0] mtvec_base_addr;
	reg mtvec_vectored;
	reg [31:0] trap_offset;
	reg dbg_irq_mtime;
	reg dbg_irq_msoft;
	reg dbg_irq_mext;
	reg traps_can_happen_wo_exec;
	reg [3:0] async_int;
	wire [63:0] csr_minstret_ff;
	wire [63:0] next_minstret;
	reg [63:0] csr_cycle_ff;
	reg [63:0] next_cycle;
	wire [63:0] csr_time_ff;
	reg [63:0] next_time;
	reg [31:0] csr_mstatus_ff;
	reg [31:0] next_mstatus;
	reg [31:0] csr_mie_ff;
	reg [31:0] next_mie;
	reg [31:0] csr_mtvec_ff;
	reg [31:0] next_mtvec;
	reg [31:0] csr_mscratch_ff;
	reg [31:0] next_mscratch;
	reg [31:0] csr_mepc_ff;
	reg [31:0] next_mepc;
	reg [31:0] csr_mcause_ff;
	reg [31:0] next_mcause;
	reg [31:0] csr_mtval_ff;
	reg [31:0] next_mtval;
	reg [31:0] csr_mip_ff;
	reg [31:0] next_mip;
	reg [131:0] csr_wr_args;
	reg [64:0] trap_ff;
	reg [64:0] next_trap;
	reg [2:0] irq_vec;
	function automatic [31:0] wr_csr_val;
		input reg [131:0] wr_arg;
		reg [31:0] wr_val;
		begin
			case (wr_arg[131-:3])
				3'b001: wr_val = wr_arg[95-:32];
				3'b010: wr_val = wr_arg[63-:32] | wr_arg[95-:32];
				3'b011: wr_val = wr_arg[63-:32] & ~wr_arg[95-:32];
				3'b101: wr_val = wr_arg[127-:32];
				3'b110: wr_val = wr_arg[63-:32] | wr_arg[127-:32];
				3'b111: wr_val = wr_arg[63-:32] & ~wr_arg[127-:32];
				default: wr_val = wr_arg[63-:32];
			endcase
			if ((wr_arg[131-:3] != 3'b001) && (wr_arg[131-:3] != 3'b101))
				wr_val = (wr_arg[128] ? wr_arg[63-:32] : wr_val);
			wr_val = wr_val & wr_arg[31-:32];
			wr_val = (stall_i ? wr_arg[63-:32] : wr_val);
			wr_csr_val = wr_val;
		end
	endfunction
	always @(*) begin : rd_wr_csr
		csr_rd_o = 32'b00000000000000000000000000000000;
		next_cycle = csr_cycle_ff + 'd1;
		next_time = csr_time_ff;
		next_mstatus = csr_mstatus_ff;
		next_mie = csr_mie_ff;
		next_mtvec = csr_mtvec_ff;
		next_mscratch = csr_mscratch_ff;
		next_mepc = csr_mepc_ff;
		next_mcause = csr_mcause_ff;
		next_mtval = csr_mtval_ff;
		next_mip = csr_mip_ff;
		csr_wr_args[131-:3] = csr_i[15-:3];
		csr_wr_args[128] = csr_i[0];
		csr_wr_args[127-:32] = imm_i;
		csr_wr_args[95-:32] = rs1_data_i;
		csr_wr_args[63-:32] = 1'sb0;
		csr_wr_args[31-:32] = 1'sb1;
		case (csr_i[12-:12])
			12'h300: begin
				csr_wr_args[31-:32] = 'h807ff9bb;
				csr_rd_o = csr_mstatus_ff;
				csr_wr_args[63-:32] = csr_rd_o;
				next_mstatus = wr_csr_val(csr_wr_args);
			end
			12'h304: begin
				csr_wr_args[31-:32] = 'h888;
				csr_rd_o = csr_mie_ff;
				csr_wr_args[63-:32] = csr_rd_o;
				next_mie = wr_csr_val(csr_wr_args);
			end
			12'h305: begin
				csr_wr_args[31-:32] = 'hfffffffd;
				csr_rd_o = csr_mtvec_ff;
				csr_wr_args[63-:32] = csr_rd_o;
				next_mtvec = wr_csr_val(csr_wr_args);
			end
			12'h340: begin
				csr_rd_o = csr_mscratch_ff;
				csr_wr_args[63-:32] = csr_rd_o;
				next_mscratch = wr_csr_val(csr_wr_args);
			end
			12'h341: begin
				csr_wr_args[31-:32] = 'hfffffffc;
				csr_rd_o = csr_mepc_ff;
				csr_wr_args[63-:32] = csr_rd_o;
				next_mepc = wr_csr_val(csr_wr_args);
			end
			12'h342: csr_rd_o = csr_mcause_ff;
			12'h343: begin
				csr_rd_o = csr_mtval_ff;
				csr_wr_args[63-:32] = csr_rd_o;
				next_mtval = wr_csr_val(csr_wr_args);
			end
			12'h344: begin
				csr_wr_args[31-:32] = 'h8;
				csr_rd_o = csr_mip_ff;
				csr_wr_args[63-:32] = csr_rd_o;
				next_mip = wr_csr_val(csr_wr_args);
			end
			12'hc00: csr_rd_o = csr_cycle_ff[31:0];
			12'hc80: csr_rd_o = csr_cycle_ff[63:32];
			12'h301: csr_rd_o = 'h40000100;
			12'hf14: csr_rd_o = M_HART_ID;
			default: csr_rd_o = 32'b00000000000000000000000000000000;
		endcase
		next_trap = 65'b00000000000000000000000000000000000000000000000000000000000000000;
		dbg_irq_mtime = 'b0;
		dbg_irq_msoft = 'b0;
		dbg_irq_mext = 'b0;
		next_mip[7] = irq_i[0];
		next_mip[11] = irq_i[2];
		case (1)
			(csr_mstatus_ff[3] && irq_i[2]) && csr_mie_ff[11]: begin
				next_mepc = pc_addr_i;
				next_mcause = 'h8000000b;
				next_mtval = 32'h00000000;
				next_trap[0] = 'b1;
				dbg_irq_mext = 'b1;
			end
			(csr_mstatus_ff[3] && irq_i[1]) && csr_mie_ff[3]: begin
				next_mip[3] = 'b1;
				next_mepc = pc_addr_i;
				next_mcause = 'h80000003;
				next_mtval = 32'h00000000;
				next_trap[0] = 'b1;
				dbg_irq_msoft = 'b1;
			end
			(csr_mstatus_ff[3] && irq_i[0]) && csr_mie_ff[7]: begin
				next_mepc = pc_addr_i;
				next_mcause = 'h80000007;
				next_mtval = 32'h00000000;
				next_trap[0] = 'b1;
				dbg_irq_mtime = 'b1;
			end
			fetch_trap_i[0]: begin
				next_mepc = pc_addr_i;
				next_mcause = 'd1;
				next_mtval = fetch_trap_i[32-:32];
				next_trap[0] = 'b1;
			end
			dec_trap_i[0] && ~will_jump_i: begin
				next_mepc = dec_trap_i[64-:32];
				next_mcause = 'd2;
				next_mtval = dec_trap_i[32-:32];
				next_trap[0] = 'b1;
			end
			instr_addr_mis_i[0]: begin
				next_mepc = pc_addr_i;
				next_mcause = 'd0;
				next_mtval = instr_addr_mis_i[32-:32];
				next_trap[0] = 'b1;
			end
			ecall_i: begin
				next_mepc = pc_addr_i;
				next_mcause = 'd11;
				next_mtval = 32'h00000000;
				next_trap[0] = 'b1;
			end
			ebreak_i: begin
				next_mepc = pc_addr_i;
				next_mcause = 'd3;
				next_mtval = 1'sb0;
				next_trap[0] = 'b1;
			end
			mret_i: begin
				next_mtval = 32'h00000000;
				next_trap[0] = 'b1;
			end
			lsu_trap_i[0]: begin
				next_mepc = pc_lsu_i;
				next_mcause = 'd4;
				next_mtval = pc_lsu_i;
				next_trap[0] = 'b1;
			end
			lsu_trap_i[130]: begin
				next_mepc = pc_lsu_i;
				next_mcause = 'd5;
				next_mtval = pc_lsu_i;
				next_trap[0] = 'b1;
			end
			lsu_trap_i[65]: begin
				next_mepc = pc_lsu_i;
				next_mcause = 'd6;
				next_mtval = pc_lsu_i;
				next_trap[0] = 'b1;
			end
			lsu_trap_i[195]: begin
				next_mepc = pc_lsu_i;
				next_mcause = 'd7;
				next_mtval = pc_lsu_i;
				next_trap[0] = 'b1;
			end
			default: next_trap = 65'b00000000000000000000000000000000000000000000000000000000000000000;
		endcase
		irq_vec = {dbg_irq_mtime, dbg_irq_msoft, dbg_irq_mtime};
		traps_can_happen_wo_exec = (((fetch_trap_i[0] || lsu_trap_i[195]) || lsu_trap_i[130]) || lsu_trap_i[65]) || lsu_trap_i[0];
		if (~traps_can_happen_wo_exec)
			if (~eval_trap_i && ~wfi_i)
				next_trap[0] = 'b0;
		mtvec_base_addr = {csr_mtvec_ff[31:2], 2'h0};
		mtvec_vectored = csr_mtvec_ff[0];
		mcause_interrupt = next_mcause[31];
		async_int = next_mcause[3:0];
		trap_offset = 'h0;
		next_trap[64-:32] = mtvec_base_addr;
		if (mtvec_vectored && mcause_interrupt)
			case (async_int)
				4'd3: trap_offset = 'hc;
				4'd7: trap_offset = 'h1c;
				4'd11: trap_offset = 'h2c;
				default: trap_offset = 'h0;
			endcase
		if (next_trap[0] && ~mret_i) begin
			next_mstatus[7] = csr_mstatus_ff[3];
			next_mstatus[3] = 'b0;
			if (wfi_i && |irq_vec)
				next_mepc = next_mepc + 'd4;
		end
		if (mret_i) begin
			next_trap[64-:32] = csr_mepc_ff;
			next_mstatus[3] = csr_mstatus_ff[7];
			next_mstatus[7] = 'b1;
		end
		else
			next_trap[64-:32] = mtvec_base_addr + trap_offset;
		trap_o = trap_ff;
	end
	always @(posedge clk)
		if (~rst) begin
			csr_mstatus_ff <= 'h1880;
			csr_mie_ff <= 1'sb0;
			csr_mtvec_ff <= MTVEC_DEFAULT_VAL;
			csr_mscratch_ff <= 1'sb0;
			csr_mepc_ff <= 1'sb0;
			csr_mcause_ff <= 1'sb0;
			csr_mtval_ff <= 1'sb0;
			csr_mip_ff <= 1'sb0;
			csr_cycle_ff <= 1'sb0;
			trap_ff <= 1'sb0;
		end
		else begin
			csr_mstatus_ff <= next_mstatus;
			csr_mie_ff <= next_mie;
			csr_mtvec_ff <= next_mtvec;
			csr_mscratch_ff <= next_mscratch;
			csr_mepc_ff <= next_mepc;
			csr_mcause_ff <= next_mcause;
			csr_mtval_ff <= next_mtval;
			csr_mip_ff <= next_mip;
			csr_cycle_ff <= next_cycle;
			trap_ff <= next_trap;
		end
endmodule
module wb (
	clk,
	rst,
	ex_mem_wb_i,
	wb_lsu_i,
	lsu_rd_data_i,
	lsu_bp_i,
	lsu_bp_data_i,
	wb_dec_o,
	wb_fwd_load_o,
	lock_wb_o
);
	input clk;
	input rst;
	input wire [39:0] ex_mem_wb_i;
	input wire [100:0] wb_lsu_i;
	input wire [31:0] lsu_rd_data_i;
	input lsu_bp_i;
	input lsu_bp_data_i;
	output reg [37:0] wb_dec_o;
	output reg [31:0] wb_fwd_load_o;
	output reg lock_wb_o;
	reg lock_wr_ff;
	reg next_lock;
	reg [31:0] bkp_load_ff;
	reg [31:0] next_bkp;
	function automatic [31:0] fmt_load;
		input reg [100:0] load;
		input reg [31:0] rdata;
		reg [31:0] data;
		begin
			begin : sv2v_autoblock_1
				reg signed [31:0] i;
				for (i = 0; i < 4; i = i + 1)
					if (load[65:64] == i[1:0])
						data = rdata >> (8 * i);
			end
			case (load[98-:3])
				3'b000: fmt_load = {{24 {data[7]}}, data[7:0]};
				3'b001: fmt_load = {{16 {data[15]}}, data[15:0]};
				3'b100: fmt_load = {24'h000000, data[7:0]};
				3'b101: fmt_load = {16'h0000, data[15:0]};
				default: fmt_load = data;
			endcase
		end
	endfunction
	always @(*) begin : mux_for_w_rf
		next_lock = 'b0;
		wb_dec_o[0] = ex_mem_wb_i[37];
		wb_dec_o[37-:32] = ex_mem_wb_i[31-:32];
		wb_dec_o[5-:5] = ex_mem_wb_i[36-:5];
		if (wb_lsu_i[100-:2] == 2'd1) begin
			next_lock = (lsu_bp_i && ~lsu_bp_data_i ? 'b1 : 'b0);
			wb_dec_o[0] = (lsu_bp_data_i || lock_wr_ff ? 'b0 : ex_mem_wb_i[37]);
			wb_dec_o[37-:32] = fmt_load(wb_lsu_i, lsu_rd_data_i);
		end
	end
	always @(*) begin : bkp_load_for_fwd
		lock_wb_o = lock_wr_ff;
		next_bkp = bkp_load_ff;
		if (wb_dec_o[0])
			next_bkp = wb_dec_o[37-:32];
		wb_fwd_load_o = bkp_load_ff;
	end
	always @(posedge clk)
		if (~rst) begin
			lock_wr_ff <= 1'sb0;
			bkp_load_ff <= 1'sb0;
		end
		else begin
			lock_wr_ff <= next_lock;
			bkp_load_ff <= next_bkp;
		end
endmodule
