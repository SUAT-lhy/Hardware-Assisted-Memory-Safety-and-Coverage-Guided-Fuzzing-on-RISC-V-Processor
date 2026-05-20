// hlct_top.v
// HLCT: Hardware-Level Coverage Tracking (148 lines)
//
// Passive read-only tap on Rocket Commit stage signals (io.commit.pc /
// io.commit.valid).  Computes AFL-compatible branch-edge hash in one cycle:
//   H = Prev_PC[15:0] XOR (Curr_PC[15:0] >> 1)
// Increments the corresponding byte counter in a dedicated 64 KB dual-port BRAM
// (Port A, completely outside the shared L1/L2 cache hierarchy).
// Port B is exposed via AXI4-Lite at 0x7000_0000; AFL++ reads coverage map
// with a single mmap() call — zero kernel involvement, zero copy.
`timescale 1ns/1ps

module hlct_top (
    input  wire        clk,
    input  wire        rst_n,

    // ── Rocket Commit stage tap (read-only passive fan-out) ─────────────
    input  wire [63:0] commit_pc,
    input  wire        commit_valid,

    // ── Dual-port BRAM Port A (HLCT internal write port) ────────────────
    output reg  [15:0] bram_a_addr,
    output reg         bram_a_we,
    output reg  [7:0]  bram_a_wdata,
    input  wire [7:0]  bram_a_rdata,   // read-before-write for increment

    // ── AXI4-Lite slave Port B (AFL++ reads / clears coverage map) ──────
    // Write address channel
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    // Write data channel
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    // Write response
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    // Read address channel
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    // Read data channel
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    // ── Port B BRAM interface (driven by AXI slave state machine) ────────
    output reg  [15:0] bram_b_addr,
    output reg         bram_b_we,
    output reg  [7:0]  bram_b_wdata,
    input  wire [7:0]  bram_b_rdata
);

// ── Wire declarations (must come before use in always blocks) ─────────────
// (ax_fsm declared inside AXI slave block below)

// ── AFL-compatible one-cycle XOR hash ────────────────────────────────────
reg [15:0] prev_pc_r;
wire [15:0] edge_hash = prev_pc_r ^ (commit_pc[15:0] >> 1);

// ── Coverage map update FSM (read-modify-write: 3 states, 3 cycles) ──────
// S_IDLE  : capture edge hash, set bram_a_addr, issue synchronous BRAM read
// S_WAIT  : 1-cycle BRAM read latency — bram_a_rdata stabilises this cycle
// S_WRITE : bram_a_rdata is stable; compute increment, assert bram_a_we
//           (the write itself lands on the NEXT clock, back in S_IDLE)
localparam [1:0] S_IDLE  = 2'd0,
                 S_WAIT  = 2'd1,
                 S_WRITE = 2'd2;

reg [1:0]  fsm;
reg [15:0] pending_hash;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        prev_pc_r    <= 16'b0;
        fsm          <= S_IDLE;
        pending_hash <= 16'b0;
        bram_a_addr  <= 16'b0;
        bram_a_we    <= 1'b0;
        bram_a_wdata <= 8'b0;
    end else begin
        bram_a_we <= 1'b0;
        case (fsm)
            S_IDLE: begin
                if (commit_valid) begin
                    prev_pc_r    <= commit_pc[15:0];
                    pending_hash <= edge_hash;
                    bram_a_addr  <= edge_hash;  // issue BRAM read; rdata valid next cycle
                    fsm          <= S_WAIT;
                end
            end
            S_WAIT: begin
                // bram_a_rdata now holds bram[pending_hash] (synchronous 1-cycle BRAM)
                fsm <= S_WRITE;
            end
            S_WRITE: begin
                // bram_a_rdata is stable; compute saturating increment
                bram_a_addr  <= pending_hash;
                bram_a_wdata <= (bram_a_rdata == 8'hFF) ? 8'h01
                                                        : bram_a_rdata + 8'h01;
                bram_a_we    <= 1'b1;   // write fires on next clock (back in S_IDLE)
                fsm          <= S_IDLE;
            end
            default: fsm <= S_IDLE;
        endcase
    end
end

// ── AXI4-Lite slave — AFL++ reads/clears coverage map via mmap ───────────
// 5-state FSM with explicit BRAM-read buffer cycle (AX_RBUF) so that
// bram_b_rdata is stable when sampled in AX_RDATA (avoids sim race on
// non-blocking assignment ordering in Iverilog/Verilator).
localparam [2:0] AX_IDLE  = 3'd0,
                 AX_RBUF  = 3'd1,   // 1-cycle BRAM read latency
                 AX_RDATA = 3'd2,
                 AX_WDATA = 3'd3,
                 AX_RESP  = 3'd4;

reg [2:0]  ax_fsm;
reg [15:0] ax_addr;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ax_fsm        <= AX_IDLE;
        ax_addr       <= 16'b0;
        s_axi_arready <= 1'b1;
        s_axi_rvalid  <= 1'b0;
        s_axi_rdata   <= 32'b0;
        s_axi_rresp   <= 2'b0;
        s_axi_awready <= 1'b1;
        s_axi_wready  <= 1'b0;
        s_axi_bvalid  <= 1'b0;
        s_axi_bresp   <= 2'b0;
        bram_b_addr   <= 16'b0;
        bram_b_we     <= 1'b0;
        bram_b_wdata  <= 8'b0;
    end else begin
        bram_b_we <= 1'b0;
        case (ax_fsm)
            AX_IDLE: begin
                s_axi_arready <= 1'b1;
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b0;
                if (s_axi_arvalid) begin
                    ax_addr       <= s_axi_araddr[15:0];
                    bram_b_addr   <= s_axi_araddr[15:0];  // issue BRAM read
                    s_axi_arready <= 1'b0;
                    ax_fsm        <= AX_RBUF;
                end else if (s_axi_awvalid) begin
                    ax_addr       <= s_axi_awaddr[15:0];
                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b1;
                    ax_fsm        <= AX_WDATA;
                end
            end
            AX_RBUF: begin
                // bram_b_rdata will be valid at the END of this cycle
                // (synchronous BRAM: addr set at T, data valid at T+1)
                ax_fsm <= AX_RDATA;
            end
            AX_RDATA: begin
                // bram_b_rdata is now stable; latch onto AXI read channel
                s_axi_rdata  <= {24'b0, bram_b_rdata};
                s_axi_rresp  <= 2'b00;
                s_axi_rvalid <= 1'b1;
                if (s_axi_rvalid && s_axi_rready) begin
                    s_axi_rvalid <= 1'b0;
                    ax_fsm       <= AX_IDLE;
                end
            end
            AX_WDATA: begin
                if (s_axi_wvalid) begin
                    bram_b_addr  <= ax_addr;
                    bram_b_wdata <= s_axi_wdata[7:0];
                    bram_b_we    <= 1'b1;
                    s_axi_wready <= 1'b0;
                    s_axi_bvalid <= 1'b1;
                    s_axi_bresp  <= 2'b00;
                    ax_fsm       <= AX_RESP;
                end
            end
            AX_RESP: begin
                if (s_axi_bvalid && s_axi_bready) begin
                    s_axi_bvalid <= 1'b0;
                    ax_fsm       <= AX_IDLE;
                end
            end
            default: ax_fsm <= AX_IDLE;
        endcase
    end
end

endmodule
