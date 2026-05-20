// tb_hlct.v — Verilator/Icarus testbench for hlct_top + axi4lite_bram
// Tests: edge-hash correctness, coverage increment, AXI4-Lite read-back
`timescale 1ns/1ps

module tb_hlct;

reg clk = 0, rst_n = 0;
always #5 clk = ~clk;  // 100 MHz

// ── HLCT DUT signals ─────────────────────────────────────────────────────
reg  [63:0] commit_pc;
reg         commit_valid;

wire [15:0] bram_a_addr;
wire        bram_a_we;
wire [7:0]  bram_a_wdata;
reg  [7:0]  bram_a_rdata;

// AXI4-Lite (Port B, driven from testbench to read coverage map)
reg  [31:0] s_axi_awaddr;  reg s_axi_awvalid;  wire s_axi_awready;
reg  [31:0] s_axi_wdata;   reg [3:0] s_axi_wstrb; reg s_axi_wvalid; wire s_axi_wready;
wire [1:0]  s_axi_bresp;   wire s_axi_bvalid;  reg  s_axi_bready;
reg  [31:0] s_axi_araddr;  reg s_axi_arvalid;  wire s_axi_arready;
wire [31:0] s_axi_rdata;   wire [1:0] s_axi_rresp; wire s_axi_rvalid; reg s_axi_rready;

wire [15:0] bram_b_addr;  wire bram_b_we;  wire [7:0] bram_b_wdata;  reg [7:0] bram_b_rdata;

// ── Shared BRAM model ─────────────────────────────────────────────────────
reg [7:0] bram [0:65535];
integer i;
initial begin
    for (i = 0; i < 65536; i = i + 1) bram[i] = 8'h00;
end

// Port A: HLCT writes coverage
always @(posedge clk) begin
    if (bram_a_we) bram[bram_a_addr] <= bram_a_wdata;
    bram_a_rdata <= bram[bram_a_addr];
end

// Port B: AXI slave reads coverage
always @(posedge clk) begin
    if (bram_b_we) bram[bram_b_addr] <= bram_b_wdata;
    bram_b_rdata <= bram[bram_b_addr];
end

hlct_top dut (
    .clk(clk), .rst_n(rst_n),
    .commit_pc(commit_pc), .commit_valid(commit_valid),
    .bram_a_addr(bram_a_addr), .bram_a_we(bram_a_we),
    .bram_a_wdata(bram_a_wdata), .bram_a_rdata(bram_a_rdata),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
    .bram_b_addr(bram_b_addr), .bram_b_we(bram_b_we),
    .bram_b_wdata(bram_b_wdata), .bram_b_rdata(bram_b_rdata)
);

// ── Helper: inject one committed PC ──────────────────────────────────────
task commit_one;
    input [63:0] pc;
    begin
        @(posedge clk); #1;
        commit_pc = pc; commit_valid = 1;
        @(posedge clk); #1;
        commit_valid = 0;
        repeat(6) @(posedge clk); // allow FSM to complete RMW (IDLE→WAIT→WRITE→IDLE + write)
    end
endtask

// ── Helper: AXI4-Lite single byte read ───────────────────────────────────
task axi_read;
    input  [15:0] addr;
    output [7:0]  rdata;
    begin
        @(posedge clk); #1;
        s_axi_araddr = {16'h0, addr}; s_axi_arvalid = 1; s_axi_rready = 1;
        wait(s_axi_arready); @(posedge clk); #1;
        s_axi_arvalid = 0;
        wait(s_axi_rvalid); #1;
        rdata = s_axi_rdata[7:0];
        @(posedge clk); #1;
    end
endtask

integer pass_count, fail_count;
reg [7:0] rval;
reg [15:0] expected_hash;

initial begin
    pass_count = 0; fail_count = 0;
    commit_pc = 0; commit_valid = 0;
    s_axi_arvalid = 0; s_axi_awvalid = 0; s_axi_wvalid = 0;
    s_axi_rready = 0; s_axi_bready = 1;
    s_axi_wstrb = 4'hF;

    rst_n = 0;
    repeat(4) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    $display("=== HLCT Coverage Tracking Testbench ===");

    // Transition PC_A → PC_B: hash = 0x1000 ^ (0x2000 >> 1) = 0x1000 ^ 0x1000 = 0x0000
    // prev_pc starts at 0 after reset; first commit PC=0x1000
    // edge_hash = 0 ^ (0x1000 >> 1) = 0x0800
    commit_one(64'h0000_0000_0000_1000);
    expected_hash = 16'h0800;

    // Read coverage map at hash 0x0800 — should be 1
    axi_read(expected_hash, rval);
    if (rval === 8'h01) begin
        $display("PASS: hash[0x%04h]=0x%02h (expected 0x01)", expected_hash, rval);
        pass_count = pass_count + 1;
    end else begin
        $display("FAIL: hash[0x%04h]=0x%02h (expected 0x01)", expected_hash, rval);
        fail_count = fail_count + 1;
    end

    // Second commit of same edge: count should increment to 2
    // prev_pc = 0x1000; commit PC = 0x2000; hash = 0x1000 ^ (0x2000 >> 1) = 0x1000^0x1000 = 0x0000
    commit_one(64'h0000_0000_0000_2000);
    expected_hash = 16'h1000 ^ (16'h2000 >> 1);  // = 0x1000 ^ 0x1000 = 0x0000
    axi_read(expected_hash, rval);
    if (rval === 8'h01) begin
        $display("PASS: first occurrence of edge 1000->2000: hash[0x%04h]=0x%02h", expected_hash, rval);
        pass_count = pass_count + 1;
    end else begin
        $display("FAIL: hash[0x%04h]=0x%02h (expected 0x01)", expected_hash, rval);
        fail_count = fail_count + 1;
    end

    // Third commit: same 0x2000→0x2000 self-loop, count should be 1
    commit_one(64'h0000_0000_0000_2000);
    expected_hash = 16'h2000 ^ (16'h2000 >> 1);  // = 0x2000 ^ 0x1000 = 0x3000
    axi_read(expected_hash, rval);
    if (rval === 8'h01) begin
        $display("PASS: self-loop 2000->2000: hash[0x%04h]=0x%02h", expected_hash, rval);
        pass_count = pass_count + 1;
    end else begin
        $display("FAIL: hash[0x%04h]=0x%02h (expected 0x01)", expected_hash, rval);
        fail_count = fail_count + 1;
    end

    $display("=== Results: %0d PASS, %0d FAIL ===", pass_count, fail_count);
    if (fail_count == 0)
        $display("ALL TESTS PASSED");
    $finish;
end

initial begin #500000; $display("TIMEOUT"); $finish; end

endmodule
