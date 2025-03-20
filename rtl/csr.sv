/**
 * File              : csr.sv
 * License           : MIT license <Check LICENSE>
 * Author            : Anderson Ignacio da Silva (aignacio) <anderson@aignacio.com>
 * Date              : 23.01.2022
 * Last Modified Date: 22.05.2022
 */
module csr
  import amba_axi_pkg::*;
  import amba_ahb_pkg::*;
  import nox_utils_pkg::*;
#(
  parameter int SUPPORT_DEBUG = 1,
  parameter int MTVEC_DEFAULT_VAL = 'h1000, // 4KB
  parameter int unsigned M_HART_ID = `M_HART_ID
)(
  input                     clk,
  input                     rst,
  input                     stall_i,
  input   s_csr_t           csr_i,
  input   rdata_t           rs1_data_i,
  input   imm_t             imm_i,
  output  rdata_t           csr_rd_o,
  // Interrupts [async trap] & Exceptions [sync trap]
  input   pc_t              pc_addr_i,
  input   pc_t              pc_lsu_i,
  input   s_irq_t           irq_i,
  input                     will_jump_i,
  input                     eval_trap_i,
  input   s_trap_info_t     dec_trap_i,
  input   s_trap_info_t     instr_addr_mis_i,
  input   s_trap_info_t     fetch_trap_i,
  input                     ecall_i,
  input                     ebreak_i,
  input                     mret_i,
  input                     wfi_i,
  input   s_trap_lsu_info_t lsu_trap_i,
  output  s_trap_info_t     trap_o
);
  typedef struct packed {
    csr_t   op;
    logic   rs1_is_x0;
    imm_t   imm;
    rdata_t rs1;
    rdata_t csr_rd;
    rdata_t mask;
  } s_wr_csr_t;

  logic mcause_interrupt;
  pc_t  mtvec_base_addr;
  logic mtvec_vectored;
  rdata_t trap_offset;
  logic   dbg_irq_mtime;
  logic   dbg_irq_msoft;
  logic   dbg_irq_mext;
  logic   traps_can_happen_wo_exec;

  mcause_int_t async_int;

  rdata_ext_t csr_minstret_ff,  next_minstret,
              csr_cycle_ff,     next_cycle,
              csr_time_ff,      next_time;

  rdata_t csr_mstatus_ff,   next_mstatus,
          csr_mie_ff,       next_mie,
          csr_mtvec_ff,     next_mtvec,
          csr_mscratch_ff,  next_mscratch,
          csr_mepc_ff,      next_mepc,
          csr_mcause_ff,    next_mcause,
          csr_mtval_ff,     next_mtval,
          csr_mip_ff,       next_mip;

  s_wr_csr_t csr_wr_args;

  s_trap_info_t trap_ff, next_trap;

  logic [2:0] irq_vec;

  function automatic rdata_t wr_csr_val(s_wr_csr_t wr_arg);
    rdata_t wr_val;

    case (wr_arg.op)
      RV_CSR_RW:  wr_val = wr_arg.rs1;
      RV_CSR_RS:  wr_val = wr_arg.csr_rd | wr_arg.rs1;
      RV_CSR_RC:  wr_val = wr_arg.csr_rd & ~wr_arg.rs1;
      RV_CSR_RWI: wr_val = wr_arg.imm;
      RV_CSR_RSI: wr_val = wr_arg.csr_rd | wr_arg.imm;
      RV_CSR_RCI: wr_val = wr_arg.csr_rd & ~wr_arg.imm;
      default:    wr_val = wr_arg.csr_rd;
    endcase

    if ((wr_arg.op != RV_CSR_RW) && (wr_arg.op != RV_CSR_RWI)) begin
      wr_val = wr_arg.rs1_is_x0 ? wr_arg.csr_rd : wr_val;
    end

    wr_val = (wr_val & wr_arg.mask);
    wr_val = stall_i ? wr_arg.csr_rd : wr_val;
    return wr_val;
  endfunction

  always_comb begin : rd_wr_csr
    // Output is combo cause there's a mux in the exe stg
    csr_rd_o = rdata_t'('0);

    //next_minstret = csr_minstret_ff;
    next_cycle    = csr_cycle_ff + 'd1;
    next_time     = csr_time_ff;
    next_mstatus  = csr_mstatus_ff;
    next_mie      = csr_mie_ff;
    next_mtvec    = csr_mtvec_ff;
    next_mscratch = csr_mscratch_ff;
    next_mepc     = csr_mepc_ff;
    next_mcause   = csr_mcause_ff;
    next_mtval    = csr_mtval_ff;
    next_mip      = csr_mip_ff;

    csr_wr_args.op        = csr_i.op;
    csr_wr_args.rs1_is_x0 = csr_i.rs1_is_x0;
    csr_wr_args.imm       = imm_i;
    csr_wr_args.rs1       = rs1_data_i;
    csr_wr_args.csr_rd    = '0;
    csr_wr_args.mask      = '1;

    case(csr_i.addr)
      RV_CSR_MSTATUS: begin
        csr_wr_args.mask   = 'h807FF9BB;
        csr_rd_o           = csr_mstatus_ff;
        csr_wr_args.csr_rd = csr_rd_o;
        next_mstatus       = wr_csr_val(csr_wr_args);
      end
      RV_CSR_MIE: begin
        csr_wr_args.mask   = 'h888;
        csr_rd_o           = csr_mie_ff;
        csr_wr_args.csr_rd = csr_rd_o;
        next_mie           = wr_csr_val(csr_wr_args);
      end
      RV_CSR_MTVEC: begin
        csr_wr_args.mask   = 'hFFFF_FFFD;
        csr_rd_o           = csr_mtvec_ff;
        csr_wr_args.csr_rd = csr_rd_o;
        next_mtvec         = wr_csr_val(csr_wr_args);
      end
      RV_CSR_MSCRATCH: begin
        csr_rd_o           = csr_mscratch_ff;
        csr_wr_args.csr_rd = csr_rd_o;
        next_mscratch      = wr_csr_val(csr_wr_args);
      end
      RV_CSR_MEPC: begin
        csr_wr_args.mask   = 'hFFFF_FFFC;
        csr_rd_o           = csr_mepc_ff;
        csr_wr_args.csr_rd = csr_rd_o;
        next_mepc          = wr_csr_val(csr_wr_args);
      end
      RV_CSR_MCAUSE: begin
        csr_rd_o = csr_mcause_ff;
      end
      RV_CSR_MTVAL: begin
        csr_rd_o           = csr_mtval_ff;
        csr_wr_args.csr_rd = csr_rd_o;
        next_mtval         = wr_csr_val(csr_wr_args);
      end
      RV_CSR_MIP: begin
        csr_wr_args.mask   = 'h8;
        csr_rd_o           = csr_mip_ff;
        csr_wr_args.csr_rd = csr_rd_o;
        next_mip           = wr_csr_val(csr_wr_args);
      end
      //RV_CSR_MCYCLE:    csr_rd_o = csr_cycle_ff[31:0];
      //RV_CSR_MCYCLEH:   csr_rd_o = csr_cycle_ff[63:32];
      //RV_CSR_MINSTRET:  csr_rd_o = csr_minstret_ff[31:0];
      //RV_CSR_MINSTRETH: csr_rd_o = csr_minstret_ff[63:32];
      RV_CSR_CYCLE:     csr_rd_o = csr_cycle_ff[31:0];
      RV_CSR_CYCLEH:    csr_rd_o = csr_cycle_ff[63:32];
      //RV_CSR_INSTRET:   csr_rd_o = csr_minstret_ff[31:0];
      //RV_CSR_INSTRETH:  csr_rd_o = csr_minstret_ff[63:32];
      //RV_CSR_TIME:      csr_rd_o = csr_time_ff[31:0];
      //RV_CSR_TIMEH:     csr_rd_o = csr_time_ff[63:32];
      RV_CSR_MISA:      csr_rd_o = `M_ISA_ID;
      //RV_CSR_MVENDORID: csr_rd_o = `M_VENDOR_ID;
      //RV_CSR_MARCHID:   csr_rd_o = `M_ARCH_ID;
      //RV_CSR_MIMPLID:   csr_rd_o = `M_IMPL_ID;
      RV_CSR_MHARTID:   csr_rd_o = M_HART_ID;
      default:          csr_rd_o = rdata_t'('0);
    endcase

    next_trap  = s_trap_info_t'('0);
    dbg_irq_mtime = 'b0;
    dbg_irq_msoft = 'b0;
    dbg_irq_mext  = 'b0;

    // Trap control
    // Priority decoder:
    // 1) IRQS [async traps]
    // 2) Exceptions [sync traps]


    // Acording to the priv. spec, these two bits needs to be
    // cleared by HW, mtip (mtimer) as soon as we reflect mtimecmp change
    // and meip (external) as soon as the IRQ controller turns it off
    next_mip[`RV_MIE_MTIP] = irq_i.timer_irq;
    next_mip[`RV_MIE_MEIP] = irq_i.ext_irq;

    priority case(1)
      (csr_mstatus_ff[`RV_MST_MIE] &&
       irq_i.ext_irq               &&
       csr_mie_ff[`RV_MIE_MEIP]): begin
        //next_mip[`RV_MIE_MEIP] = 'b1;
        next_mepc              = pc_addr_i;
        next_mcause            = 'h8000_000B;
        next_mtval             = rdata_t'('h0);
        next_trap.active       = 'b1;
        dbg_irq_mext           = 'b1;
      end
      (csr_mstatus_ff[`RV_MST_MIE] &&
       irq_i.sw_irq                &&
       csr_mie_ff[`RV_MIE_MSIP]): begin
        next_mip[`RV_MIE_MSIP] = 'b1;
        next_mepc              = pc_addr_i;
        next_mcause            = 'h8000_0003;
        next_mtval             = rdata_t'('h0);
        next_trap.active       = 'b1;
        dbg_irq_msoft          = 'b1;
      end
      (csr_mstatus_ff[`RV_MST_MIE] &&
       irq_i.timer_irq             &&
       csr_mie_ff[`RV_MIE_MTIP]): begin
        //next_mip[`RV_MIE_MTIP] = 'b1;
        next_mepc              = pc_addr_i;
        next_mcause            = 'h8000_0007;
        next_mtval             = rdata_t'('h0);
        next_trap.active       = 'b1;
        dbg_irq_mtime          = 'b1;
      end
      fetch_trap_i.active: begin  // TODO: test this feature
        next_mepc        = pc_addr_i;
        next_mcause      = 'd1;
        next_mtval       = fetch_trap_i.mtval;
        next_trap.active = 'b1;
      end
      (dec_trap_i.active && ~will_jump_i): begin
        next_mepc        = dec_trap_i.pc_addr;
        next_mcause      = 'd2;
        next_mtval       = dec_trap_i.mtval;
        next_trap.active = 'b1;
      end
      instr_addr_mis_i.active: begin
        next_mepc        = pc_addr_i;
        next_mcause      = 'd0;
        next_mtval       = instr_addr_mis_i.mtval;
        next_trap.active = 'b1;
      end
      ecall_i: begin
        next_mepc        = pc_addr_i;
        next_mcause      = 'd11;
        next_mtval       = rdata_t'('h0);
        next_trap.active = 'b1;
      end
      ebreak_i: begin
        next_mepc        = pc_addr_i;
        next_mcause      = 'd3;
        //next_mtval       = pc_addr_i;
        next_mtval       = '0;
        next_trap.active = 'b1;
      end
      mret_i: begin // Fake trap to return program
        next_mtval       = rdata_t'('h0);
        next_trap.active = 'b1;
      end
      lsu_trap_i.ld_mis.active: begin // TODO: test this feature
        next_mepc        = pc_lsu_i;
        next_mcause      = 'd4;
        next_mtval       = pc_lsu_i;
        next_trap.active = 'b1;
      end
      lsu_trap_i.ld.active: begin     // TODO: test this feature
        next_mepc        = pc_lsu_i;
        next_mcause      = 'd5;
        next_mtval       = pc_lsu_i;
        next_trap.active = 'b1;
      end
      lsu_trap_i.st_mis.active: begin // TODO: test this feature
        next_mepc        = pc_lsu_i;
        next_mcause      = 'd6;
        next_mtval       = pc_lsu_i;
        next_trap.active = 'b1;
      end
      lsu_trap_i.st.active: begin     // TODO: test this feature
        next_mepc        = pc_lsu_i;
        next_mcause      = 'd7;
        next_mtval       = pc_lsu_i;
        next_trap.active = 'b1;
      end
      // Added the below statement due to error while synthesizing on vivado
      default: next_trap  = s_trap_info_t'('0);
    endcase

    irq_vec = {dbg_irq_mtime, dbg_irq_msoft, dbg_irq_mtime};
    // In case we have one of the following traps
    // we don't need to wait till it's in the exec
    // stage to evaluate
    traps_can_happen_wo_exec = (fetch_trap_i.active       ||
                                lsu_trap_i.st.active      ||
                                lsu_trap_i.ld.active      ||
                                lsu_trap_i.st_mis.active  ||
                                lsu_trap_i.ld_mis.active);

    if (~traps_can_happen_wo_exec) begin
      if (~eval_trap_i && ~wfi_i) begin
        next_trap.active = 'b0;
      end
    end

    // Define trap address
    mtvec_base_addr   = {csr_mtvec_ff[31:2],2'h0};
    mtvec_vectored    = csr_mtvec_ff[0];
    mcause_interrupt  = next_mcause[31];
    async_int         = mcause_int_t'(next_mcause[3:0]);
    trap_offset       = 'h0;
    next_trap.pc_addr = mtvec_base_addr;

    // Vectored mode and MCAUSE is async interrupt
    if (mtvec_vectored && mcause_interrupt) begin
      case(async_int)
        RV_M_SW_INT:    trap_offset = 'h0c;
        RV_M_TIMER_INT: trap_offset = 'h1c;
        RV_M_EXT_INT:   trap_offset = 'h2c;
        default:        trap_offset = 'h0;
      endcase
    end

    if (next_trap.active && ~mret_i) begin
      // bkp mstatus[MIE]
      //To support nested traps, each privilege mode x has a two-level stack of interrupt-enable bits and privilege modes.
      //xPIE holds the value of the interrupt-enable bit active prior to the trap, and x PP holds the previous privilege mode.
      //The x PP fields can only hold privilege modes up to x, so MPP is two bits wide, SPP is one bit wide, and
      //UPP is implicitly zero. When a trap is taken from privilege mode y into privilege mode x, xPIE is set to the value
      //of xIE; xIE is set to 0; and xPP is set to y.
      next_mstatus[`RV_MST_MPIE] = csr_mstatus_ff[`RV_MST_MIE];
      next_mstatus[`RV_MST_MIE]  = 'b0;
      if (wfi_i && (|irq_vec)) begin
        // In this case, ISA says:
        //...If an enabled interrupt is present or later becomes present while the hart is stalled, the interrupt exception
        //will be taken on the following instruction, i.e., execution resumes in the trap handler and mepc = pc + 4.
        next_mepc = next_mepc + 'd4;
      end
    end

    if (mret_i) begin
      next_trap.pc_addr = csr_mepc_ff;
      //The MRET, SRET, or URET instructions are used to return from traps in M-mode, S-mode, or U-mode respectively.
      //When executing an x RET instruction, supposing x PP holds the value y, x IE is set to xPIE; the privilege mode
      //is changed to y; xPIE is set to 1; and xPP is set to U (or M if user-mode is not supported).
      next_mstatus[`RV_MST_MIE] = csr_mstatus_ff[`RV_MST_MPIE];
      next_mstatus[`RV_MST_MPIE] = 'b1;
    end
    else begin
      next_trap.pc_addr = mtvec_base_addr+trap_offset;
    end

    trap_o = trap_ff;
  end

  `CLK_PROC(clk, rst) begin
    `RST_TYPE(rst) begin
      csr_mstatus_ff  <=  'h1880;
      csr_mie_ff      <=  `OP_RST_L;
      csr_mtvec_ff    <=  MTVEC_DEFAULT_VAL;
      csr_mscratch_ff <=  `OP_RST_L;
      csr_mepc_ff     <=  `OP_RST_L;
      csr_mcause_ff   <=  `OP_RST_L;
      csr_mtval_ff    <=  `OP_RST_L;
      csr_mip_ff      <=  `OP_RST_L;
      csr_cycle_ff    <=  `OP_RST_L;
      //csr_time_ff     <=  `OP_RST_L;
      //csr_minstret_ff <=  `OP_RST_L;
      trap_ff         <=  `OP_RST_L;
    end
    else begin
      csr_mstatus_ff  <=  next_mstatus;
      csr_mie_ff      <=  next_mie;
      csr_mtvec_ff    <=  next_mtvec;
      csr_mscratch_ff <=  next_mscratch;
      csr_mepc_ff     <=  next_mepc;
      csr_mcause_ff   <=  next_mcause;
      csr_mtval_ff    <=  next_mtval;
      csr_mip_ff      <=  next_mip;
      csr_cycle_ff    <=  next_cycle;
      //csr_time_ff     <=  next_time;
      //csr_minstret_ff <=  next_minstret;
      trap_ff         <=  next_trap;
    end
  end
endmodule
