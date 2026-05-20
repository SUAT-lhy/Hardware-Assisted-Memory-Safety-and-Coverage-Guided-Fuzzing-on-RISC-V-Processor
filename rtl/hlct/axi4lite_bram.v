// axi4lite_bram.v
// AXI4-Lite slave wrapper for 64 KB dual-port BRAM (HLCT coverage map)
//
// Maps the 64 KB BRAM at AXI base address 0x7000_0000.
// Port A is driven by hlct_top for coverage write-back.
// Port B (this module) is exposed to the AXI4-Lite peripheral bus so that
// AFL++ can read and clear the coverage map via a single mmap() call.
`timescale 1ns/1ps

module axi4lite_bram #(
    parameter [31:0] BASE_ADDR   = 32'h7000_0000,
    parameter integer BRAM_DEPTH = 65536           // 64 KB
)(
    input  wire        clk,
    input  wire        rst_n,

    // ── AXI4-Lite slave interface ─────────────────────────────────────────
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,

    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,

    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,

    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,

    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready
);

// ── Internal 64 KB BRAM (synthesises to block RAM on Xilinx) ─────────────
reg [7:0] bram [0:BRAM_DEPTH-1];

integer i;
initial begin
    for (i = 0; i < BRAM_DEPTH; i = i + 1)
        bram[i] = 8'h00;
end

// ── Write path ────────────────────────────────────────────────────────────
reg        aw_active;
reg [15:0] aw_addr;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s_axi_awready <= 1'b1;
        s_axi_wready  <= 1'b0;
        s_axi_bvalid  <= 1'b0;
        s_axi_bresp   <= 2'b0;
        aw_active     <= 1'b0;
        aw_addr       <= 16'b0;
    end else begin
        if (s_axi_awvalid && s_axi_awready) begin
            aw_addr       <= s_axi_awaddr[15:0];
            aw_active     <= 1'b1;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b1;
        end
        if (aw_active && s_axi_wvalid && s_axi_wready) begin
            // Byte-lane write (AFL++ always writes full bytes)
            if (s_axi_wstrb[0]) bram[aw_addr]     <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) bram[aw_addr+1]   <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) bram[aw_addr+2]   <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) bram[aw_addr+3]   <= s_axi_wdata[31:24];
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b1;
            s_axi_bresp   <= 2'b00;
            aw_active     <= 1'b0;
            s_axi_awready <= 1'b1;
        end
        if (s_axi_bvalid && s_axi_bready)
            s_axi_bvalid <= 1'b0;
    end
end

// ── Read path (1-cycle BRAM latency) ─────────────────────────────────────
reg        ar_active;
reg [15:0] ar_addr;
reg        ar_read_d;   // delay slot for BRAM latency

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s_axi_arready <= 1'b1;
        s_axi_rvalid  <= 1'b0;
        s_axi_rdata   <= 32'b0;
        s_axi_rresp   <= 2'b0;
        ar_active     <= 1'b0;
        ar_addr       <= 16'b0;
        ar_read_d     <= 1'b0;
    end else begin
        ar_read_d <= 1'b0;
        if (s_axi_arvalid && s_axi_arready) begin
            ar_addr       <= s_axi_araddr[15:0];
            ar_active     <= 1'b1;
            s_axi_arready <= 1'b0;
            ar_read_d     <= 1'b1;  // issue BRAM read
        end
        if (ar_read_d && ar_active) begin
            // Pack 4 bytes (word-aligned read)
            s_axi_rdata  <= {bram[ar_addr+3], bram[ar_addr+2],
                             bram[ar_addr+1], bram[ar_addr]};
            s_axi_rresp  <= 2'b00;
            s_axi_rvalid <= 1'b1;
            ar_active    <= 1'b0;
            s_axi_arready <= 1'b1;
        end
        if (s_axi_rvalid && s_axi_rready)
            s_axi_rvalid <= 1'b0;
    end
end

endmodule
