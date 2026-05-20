// DCacheArbiter_mterv.v
// MTE-RV tag-check extension for RISC-V Load/Store Unit
//
// Lock-and-key model: 4-bit colour tag embedded in ptr[63:60] (Sv39 unused bits).
// Tag shadow memory at TAGMEM_BASE: 4-bit tag per 16-byte granule, two tags packed
// per byte.  Tag-mem access runs in parallel with TLB/DCache lookup — zero extra
// cycles on cache hit.  On colour mismatch, fires RISC-V Load/Store Access Fault
// (cause 5 / 7), which Linux delivers as SIGSEGV with si_code=SEGV_MTEAERR.
//
// This module encapsulates the 31 lines added inside DCacheArbiter.v of MEISHA V100.
`timescale 1ns/1ps

module DCacheArbiter_mterv #(
    parameter [31:0] TAGMEM_BASE = 32'h8F00_0000  // top 16 MB of 1 GB DDR3
)(
    input  wire        clk,
    input  wire        rst_n,

    // ── From LSU: raw virtual address with colour tag in bits [63:60] ────
    input  wire [63:0] lsu_vaddr,
    input  wire        lsu_req_valid,
    input  wire        lsu_is_store,    // 0 = load, 1 = store / AMO

    // ── To downstream DCache arbiter: tag-stripped real address ──────────
    output wire [63:0] dcache_vaddr,
    output wire        dcache_req_valid,

    // ── Tag shadow SRAM interface (1-cycle synchronous read) ─────────────
    output wire [31:0] tagmem_addr,     // byte address into tag SRAM
    output wire        tagmem_re,
    input  wire [7:0]  tagmem_rdata,   // two 4-bit tags packed per byte

    // ── Exception output → trap controller ──────────────────────────────
    output reg         fault_valid,
    output reg  [3:0]  fault_cause     // 5 = LD access fault, 7 = ST access fault
);

// ── 1. Colour extraction and real-address reconstruction ─────────────────
wire [3:0]  ptr_colour = lsu_vaddr[63:60];
wire [63:0] real_vaddr = {4'b0000, lsu_vaddr[59:0]};  // strip tag; goes to TLB/cache

// ── 2. Tag-memory byte address ────────────────────────────────────────────
// 16-byte granule → 4-bit tag; two tags per byte → byte_addr = granule_idx >> 1
wire [27:0] granule_idx = real_vaddr[31:4];
assign tagmem_addr = TAGMEM_BASE + {4'b0, granule_idx[27:1]};
assign tagmem_re   = lsu_req_valid;

// ── 3. Pass real address to DCache with zero added latency ───────────────
assign dcache_vaddr     = real_vaddr;
assign dcache_req_valid = lsu_req_valid;

// ── 4. Pipeline register: hold colour and control 1 cycle for SRAM result
reg [3:0]  ptr_colour_r;
reg        req_valid_r, is_store_r;
reg        nibble_sel_r;               // which nibble of the packed byte

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ptr_colour_r <= 4'b0;
        req_valid_r  <= 1'b0;
        is_store_r   <= 1'b0;
        nibble_sel_r <= 1'b0;
    end else begin
        ptr_colour_r <= ptr_colour;
        req_valid_r  <= lsu_req_valid;
        is_store_r   <= lsu_is_store;
        nibble_sel_r <= granule_idx[0];  // 0 → low nibble, 1 → high nibble
    end
end

// ── 5. XOR comparator — fires RISC-V Access Fault on mismatch ────────────
wire [3:0] mem_colour = nibble_sel_r ? tagmem_rdata[7:4] : tagmem_rdata[3:0];
wire       mismatch   = req_valid_r && (ptr_colour_r !== mem_colour);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fault_valid <= 1'b0;
        fault_cause <= 4'b0;
    end else begin
        fault_valid <= mismatch;
        fault_cause <= is_store_r ? 4'd7 : 4'd5;
    end
end

endmodule
