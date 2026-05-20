// tb_mterv.v — Verilator/Icarus testbench for DCacheArbiter_mterv
// Tests: heap OOB (colour mismatch), use-after-free, correct access (no fault)
`timescale 1ns/1ps

module tb_mterv;

reg        clk = 0, rst_n = 0;
reg [63:0] lsu_vaddr;
reg        lsu_req_valid, lsu_is_store;
wire [63:0] dcache_vaddr;
wire        dcache_req_valid;
wire [31:0] tagmem_addr;
wire        tagmem_re;
wire        fault_valid;
wire [3:0]  fault_cause;

// 256-entry tag shadow memory model (covers 4 KB for simulation)
reg [7:0] tag_shadow [0:255];
reg [7:0] tagmem_rdata;

always #5 clk = ~clk;  // 100 MHz sim clock

// Tag memory read model (1-cycle latency)
always @(posedge clk) begin
    if (tagmem_re) begin
        tagmem_rdata <= tag_shadow[tagmem_addr[7:0]];
    end
end

DCacheArbiter_mterv #(.TAGMEM_BASE(32'h0000_0000)) dut (
    .clk(clk), .rst_n(rst_n),
    .lsu_vaddr(lsu_vaddr), .lsu_req_valid(lsu_req_valid),
    .lsu_is_store(lsu_is_store),
    .dcache_vaddr(dcache_vaddr), .dcache_req_valid(dcache_req_valid),
    .tagmem_addr(tagmem_addr), .tagmem_re(tagmem_re),
    .tagmem_rdata(tagmem_rdata),
    .fault_valid(fault_valid), .fault_cause(fault_cause)
);

integer pass_count, fail_count, cycle;

task apply_access;
    input [63:0] addr;
    input        is_store;
    input        expect_fault;
    input [63:0] testnum;
    begin
        lsu_vaddr = addr; lsu_req_valid = 1; lsu_is_store = is_store;
        @(posedge clk); #1;
        lsu_req_valid = 0;
        @(posedge clk); #1;  // wait for pipeline result
        if (fault_valid !== expect_fault) begin
            $display("FAIL test %0d: addr=%h fault=%b expected=%b",
                     testnum, addr, fault_valid, expect_fault);
            fail_count = fail_count + 1;
        end else begin
            $display("PASS test %0d: addr=%h fault=%b cause=%0d",
                     testnum, addr, fault_valid, fault_cause);
            pass_count = pass_count + 1;
        end
    end
endtask

initial begin
    pass_count = 0; fail_count = 0;
    // Initialise tag shadow: granule 0 → colour 5, granule 1 → colour 3
    // packed: byte 0 → {colour1[3:0], colour0[3:0]} = {3,5} = 8'h35
    tag_shadow[0] = 8'h35;  // granule 0 colour=5 (low nibble), granule 1 colour=3 (high)
    tag_shadow[1] = 8'hAA;  // granule 2 colour=A, granule 3 colour=A

    rst_n = 0; lsu_req_valid = 0; lsu_vaddr = 0; lsu_is_store = 0;
    repeat(4) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    $display("=== MTE-RV Tag Check Testbench ===");

    // Test 1: correct colour (5), load — no fault
    // ptr = colour[5] | real_addr[0x00] → granule 0, low nibble = 5
    apply_access(64'h5000_0000_0000_0000, 0, 0, 1);

    // Test 2: wrong colour (7 vs stored 5) — should fault (load, cause=5)
    apply_access(64'h7000_0000_0000_0000, 0, 1, 2);

    // Test 3: correct colour (3), load on granule 1 (addr=0x10) — no fault
    apply_access(64'h3000_0000_0000_0010, 0, 0, 3);

    // Test 4: use-after-free simulation: colour 0 vs stored 5 → fault
    apply_access(64'h0000_0000_0000_0000, 0, 1, 4);

    // Test 5: correct colour (A), store on granule 2 (addr=0x20) — no fault
    apply_access(64'hA000_0000_0000_0020, 1, 0, 5);

    // Test 6: wrong colour on store — store access fault (cause=7)
    apply_access(64'hB000_0000_0000_0020, 1, 1, 6);

    $display("=== Results: %0d PASS, %0d FAIL ===", pass_count, fail_count);
    if (fail_count == 0)
        $display("ALL TESTS PASSED");
    else
        $display("SOME TESTS FAILED");

    $finish;
end

// Timeout watchdog
initial begin
    #10000;
    $display("TIMEOUT");
    $finish;
end

endmodule
