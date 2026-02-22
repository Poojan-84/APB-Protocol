`timescale 1ns / 1ps
// ============================================================
// APB Testbench
// Tests the APB_Wrapper (Master + Slave) for:
//   1. Single Write
//   2. Single Read  (and verify data matches what was written)
//   3. Back-to-back Writes
//   4. Back-to-back Write then Read
//   5. Partial write using PSTRB (byte write)
//   6. Partial write using PSTRB (half-word write)
//   7. Read with non-zero PSTRB  → expects PSLVERR
//   8. Reset in the middle of a transfer
//   9. Multiple address locations write then readback
// ============================================================

module APB_tb;

    // -------------------------------------------------------
    // DUT Signal Declarations
    // These match the APB_Wrapper port list exactly
    // -------------------------------------------------------
    reg         PCLK;       // Clock
    reg         PRESETn;    // Active-low reset
    reg         SWRITE;     // 1=write, 0=read
    reg  [31:0] SADDR;      // Address to access
    reg  [31:0] SWDATA;     // Data to write
    reg  [3:0]  SSTRB;      // Byte strobes
    reg  [2:0]  SPROT;      // Protection bits
    reg         transfer;   // Initiate a transfer

    wire [31:0] PRDATA;     // Read data output from slave

    // -------------------------------------------------------
    // Internal signals for monitoring (tap into DUT internals)
    // -------------------------------------------------------
    wire        PSEL;
    wire        PENABLE;
    wire        PWRITE;
    wire [31:0] PADDR;
    wire [31:0] PWDATA;
    wire [3:0]  PSTRB;
    wire [2:0]  PPROT;
    wire        PREADY;
    wire        PSLVERR;

    // -------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------
    APB_Wrapper DUT (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),
        .SWRITE  (SWRITE),
        .SADDR   (SADDR),
        .SWDATA  (SWDATA),
        .SSTRB   (SSTRB),
        .SPROT   (SPROT),
        .transfer(transfer),
        .PRDATA  (PRDATA)
    );

    // -------------------------------------------------------
    // Tap internal wires for waveform visibility in Xilinx
    // These assign statements expose internal DUT bus signals
    // -------------------------------------------------------
    assign PSEL    = DUT.PSEL;
    assign PENABLE = DUT.PENABLE;
    assign PWRITE  = DUT.PWRITE;
    assign PADDR   = DUT.PADDR;
    assign PWDATA  = DUT.PWDATA;
    assign PSTRB   = DUT.PSTRB;
    assign PPROT   = DUT.PPROT;
    assign PREADY  = DUT.PREADY;
    assign PSLVERR = DUT.PSLVERR;

    // -------------------------------------------------------
    // Clock Generation
    // 10ns period → 100 MHz clock
    // -------------------------------------------------------
    initial PCLK = 0;
    always #5 PCLK = ~PCLK;

    // -------------------------------------------------------
    // Test Tracking Variables
    // -------------------------------------------------------
    integer test_num;
    integer pass_count;
    integer fail_count;

    // -------------------------------------------------------
    // TASK: apb_write
    // Performs one complete APB write transfer
    // Arguments: addr, data, strb, prot
    // -------------------------------------------------------
    task apb_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        input [2:0]  prot;
        begin
            @(negedge PCLK); // Drive inputs on falling edge (safe, sampled on rising edge)
            SWRITE   = 1;
            SADDR    = addr;
            SWDATA   = data;
            SSTRB    = strb;
            SPROT    = prot;
            transfer = 1;    // Assert transfer → FSM moves IDLE→SETUP

            @(negedge PCLK); // SETUP phase happens (PSEL=1, PENABLE=0)
            transfer = 0;    // Deassert after one cycle so FSM goes IDLE after this transfer

            // Wait for PREADY to go high (ACCESS phase done)
            // Since our slave has no wait states, this is immediate (1 cycle in ACCESS)
            @(posedge PCLK);
            #1; // Small delay to let PREADY settle after rising edge
            while (!PREADY) begin
                @(posedge PCLK);
                #1;
            end

            @(negedge PCLK); // Let FSM transition back to IDLE
            SWRITE   = 0;
            SADDR    = 0;
            SWDATA   = 0;
            SSTRB    = 0;
            SPROT    = 0;
        end
    endtask

    // -------------------------------------------------------
    // TASK: apb_read
    // Performs one complete APB read transfer
    // Arguments: addr, prot
    // Result is available on PRDATA wire after task completes
    // -------------------------------------------------------
    task apb_read;
        input [31:0] addr;
        input [2:0]  prot;
        begin
            @(negedge PCLK);
            SWRITE   = 0;
            SADDR    = addr;
            SWDATA   = 0;
            SSTRB    = 4'b0000; // Must be 0 for reads (per APB spec)
            SPROT    = prot;
            transfer = 1;       // Assert transfer → FSM moves IDLE→SETUP

            @(negedge PCLK);
            transfer = 0;       // One transfer only

            // Wait for PREADY
            @(posedge PCLK);
            #1;
            while (!PREADY) begin
                @(posedge PCLK);
                #1;
            end

            @(negedge PCLK); // Let FSM settle back to IDLE
            SADDR  = 0;
            SPROT  = 0;
        end
    endtask

    // -------------------------------------------------------
    // TASK: check
    // Compares actual vs expected value and prints PASS/FAIL
    // -------------------------------------------------------
    task check;
        input [31:0]  actual;
        input [31:0]  expected;
        input [127:0] test_name; // String label (16 chars max for $display)
        begin
            if (actual === expected) begin
                $display("  [PASS] Test %0d (%s): Got 0x%08X  ✓", test_num, test_name, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] Test %0d (%s): Expected 0x%08X, Got 0x%08X  ✗",
                          test_num, test_name, expected, actual);
                fail_count = fail_count + 1;
            end
            test_num = test_num + 1;
        end
    endtask

    // -------------------------------------------------------
    // TASK: apply_reset
    // Drives PRESETn low for a few cycles then releases
    // -------------------------------------------------------
    task apply_reset;
        begin
            PRESETn  = 0;
            SWRITE   = 0;
            SADDR    = 0;
            SWDATA   = 0;
            SSTRB    = 0;
            SPROT    = 0;
            transfer = 0;
            repeat(4) @(posedge PCLK); // Hold reset for 4 clock cycles
            @(negedge PCLK);
            PRESETn = 1;               // Release reset on falling edge
            @(negedge PCLK);           // One extra cycle to stabilize
        end
    endtask

    // -------------------------------------------------------
    // MAIN TEST SEQUENCE
    // -------------------------------------------------------
    initial begin
        // Xilinx Vivado: dump waveforms for simulation
        $dumpfile("APB_tb.vcd");
        $dumpvars(0, APB_tb);

        // Initialize counters
        test_num   = 1;
        pass_count = 0;
        fail_count = 0;

        $display("============================================");
        $display("       APB Master-Slave Testbench          ");
        $display("============================================");

        // =======================================================
        // RESET
        // =======================================================
        $display("\n--- Applying Reset ---");
        apply_reset;
        $display("    Reset released. FSM in IDLE.");

        // =======================================================
        // TEST 1: Single Full-Word Write to address 0x00000000
        // Write 0xDEADBEEF with all strobe bits set (4'b1111)
        // =======================================================
        $display("\n--- Test 1: Single Full-Word Write ---");
        apb_write(32'h00000000, 32'hDEADBEEF, 4'b1111, 3'b000);
        $display("    Written 0xDEADBEEF to address 0x00000000");

        // =======================================================
        // TEST 2: Single Read from address 0x00000000
        // Expect PRDATA = 0xDEADBEEF (what we just wrote)
        // =======================================================
        $display("\n--- Test 2: Single Read Verification ---");
        apb_read(32'h00000000, 3'b000);
        #2;
        check(PRDATA, 32'hDEADBEEF, "SingleRead  ");

        // =======================================================
        // TEST 3: Write to a different address (0x00000004)
        // =======================================================
        $display("\n--- Test 3: Write to addr 0x00000004 ---");
        apb_write(32'h00000004, 32'hCAFEBABE, 4'b1111, 3'b000);

        // Read back and verify
        apb_read(32'h00000004, 3'b000);
        #2;
        check(PRDATA, 32'hCAFEBABE, "Addr4Write  ");

        // =======================================================
        // TEST 4: Byte Write — PSTRB=4'b0001 (only byte 0)
        // Write 0xABCDEF12 with PSTRB=0001
        // Slave sign-extends byte [7:0] = 0x12 → 0x00000012
        // =======================================================
        $display("\n--- Test 4: Byte Write (PSTRB=0001) ---");
        apb_write(32'h00000008, 32'hABCDEF12, 4'b0001, 3'b000);
        apb_read(32'h00000008, 3'b000);
        #2;
        // PSTRB=0001: Cache[addr] = {{24{PWDATA[7]}}, PWDATA[7:0]}
        // PWDATA[7:0] = 0x12 = 0001_0010, bit7=0 → sign ext = 0x00000012
        check(PRDATA, 32'h00000012, "ByteWrite   ");

        // =======================================================
        // TEST 5: Byte Write — PSTRB=4'b1000 (only byte 3, MSB)
        // Write 0xAB000000 with PSTRB=1000
        // Slave stores: {PWDATA[31:24], 24'h000000} = 0xAB000000
        // =======================================================
        $display("\n--- Test 5: MSB Byte Write (PSTRB=1000) ---");
        apb_write(32'h0000000C, 32'hAB000000, 4'b1000, 3'b000);
        apb_read(32'h0000000C, 3'b000);
        #2;
        check(PRDATA, 32'hAB000000, "MSBByteWrite");

        // =======================================================
        // TEST 6: Half-Word Write — PSTRB=4'b0011 (bytes 0 and 1)
        // Write 0x00005A5A, PSTRB=0011
        // Slave: {{16{PWDATA[15]}}, PWDATA[15:0]}
        // PWDATA[15:0] = 0x5A5A, bit15=0 → 0x00005A5A
        // =======================================================
        $display("\n--- Test 6: Half-Word Write (PSTRB=0011) ---");
        apb_write(32'h00000010, 32'h00005A5A, 4'b0011, 3'b000);
        apb_read(32'h00000010, 3'b000);
        #2;
        check(PRDATA, 32'h00005A5A, "HalfWordWr  ");

        // =======================================================
        // TEST 7: Full Word Write — PSTRB=4'b1111
        // Write 0xFFFFFFFF to address 0x00000014
        // =======================================================
        $display("\n--- Test 7: Full Word Write (PSTRB=1111) ---");
        apb_write(32'h00000014, 32'hFFFFFFFF, 4'b1111, 3'b000);
        apb_read(32'h00000014, 3'b000);
        #2;
        check(PRDATA, 32'hFFFFFFFF, "FullWordWr  ");

        // =======================================================
        // TEST 8: Upper Half-Word Write — PSTRB=4'b1100 (bytes 2 and 3)
        // Write 0xBEEF0000, PSTRB=1100
        // Slave: {PWDATA[31:16], 16'h0000} = 0xBEEF0000
        // =======================================================
        $display("\n--- Test 8: Upper Half-Word Write (PSTRB=1100) ---");
        apb_write(32'h00000018, 32'hBEEF0000, 4'b1100, 3'b000);
        apb_read(32'h00000018, 3'b000);
        #2;
        check(PRDATA, 32'hBEEF0000, "UpperHalfWr ");

        // =======================================================
        // TEST 9: PSLVERR check — Read with non-zero PSTRB
        // Per APB spec PSTRB must be 0 during reads.
        // Our slave asserts PSLVERR when PSTRB!=0 on a read.
        // We manually set SSTRB non-zero to trigger this.
        // -------------------------------------------------------
        // NOTE: We directly drive the signals here (bypass task)
        // so we can send an illegal SSTRB=4'b0001 on a read.
        // =======================================================
        $display("\n--- Test 9: PSLVERR on Read with PSTRB!=0 ---");
        @(negedge PCLK);
        SWRITE   = 0;               // Read operation
        SADDR    = 32'h00000000;
        SWDATA   = 0;
        SSTRB    = 4'b0001;         // ILLEGAL for read — should cause PSLVERR
        SPROT    = 3'b000;
        transfer = 1;

        @(negedge PCLK);
        transfer = 0;

        @(posedge PCLK); #1;
        while (!PREADY) begin
            @(posedge PCLK); #1;
        end

        @(negedge PCLK);
        // Give one more clock for PSLVERR to latch in slave (sequential output)
        @(posedge PCLK); #2;
        check(PSLVERR, 1'b1, "PSLVERR     ");
        SSTRB = 0;
        SWRITE = 0;
        SADDR = 0;

        // =======================================================
        // TEST 10: Reset in the middle of a transfer
        // Start a write, assert reset mid-way, verify bus idles
        // =======================================================
        $display("\n--- Test 10: Reset Mid-Transfer ---");
        @(negedge PCLK);
        SWRITE   = 1;
        SADDR    = 32'h000000FF;
        SWDATA   = 32'h12345678;
        SSTRB    = 4'b1111;
        SPROT    = 3'b000;
        transfer = 1;

        @(negedge PCLK); // Now in SETUP phase

        // Assert reset mid-transfer (during ACCESS phase)
        PRESETn = 0;
        transfer = 0;
        @(negedge PCLK);
        @(negedge PCLK);

        // Check bus is idle after reset
        #2;
        $display("    After mid-transfer reset: PSEL=%0b PENABLE=%0b", PSEL, PENABLE);
        if (PSEL === 0 && PENABLE === 0)
            $display("  [PASS] Test %0d (MidRstIdle): Bus correctly idle after reset ✓", test_num);
        else
            $display("  [FAIL] Test %0d (MidRstIdle): Bus NOT idle after reset! ✗", test_num);
        test_num = test_num + 1;

        // Release reset and stabilize
        @(negedge PCLK);
        PRESETn = 1;
        @(negedge PCLK);

        // =======================================================
        // TEST 11 & 12: Multiple address write, then batch readback
        // Write to 3 locations, then read all 3 back and verify
        // =======================================================
        $display("\n--- Tests 11-13: Multi-Address Write then Readback ---");
        apb_write(32'h00000020, 32'hAABBCCDD, 4'b1111, 3'b000);
        apb_write(32'h00000024, 32'h11223344, 4'b1111, 3'b000);
        apb_write(32'h00000028, 32'h55667788, 4'b1111, 3'b000);

        apb_read(32'h00000020, 3'b000);
        #2;
        check(PRDATA, 32'hAABBCCDD, "MultiRd_0   ");

        apb_read(32'h00000024, 3'b000);
        #2;
        check(PRDATA, 32'h11223344, "MultiRd_1   ");

        apb_read(32'h00000028, 3'b000);
        #2;
        check(PRDATA, 32'h55667788, "MultiRd_2   ");

        // =======================================================
        // TEST 14: Back-to-back transfers using transfer signal
        // Keep transfer=1 for two write cycles → FSM goes
        // ACCESS→SETUP→ACCESS (back-to-back without returning to IDLE)
        // =======================================================
        $display("\n--- Test 14: Back-to-Back Transfers ---");
        @(negedge PCLK);
        SWRITE   = 1;
        SADDR    = 32'h00000030;
        SWDATA   = 32'hAAAA1111;
        SSTRB    = 4'b1111;
        SPROT    = 3'b000;
        transfer = 1;       // Keep high for back-to-back

        @(negedge PCLK);    // In SETUP for first transfer
        // Change address/data for second transfer while first is in ACCESS
        SADDR  = 32'h00000034;
        SWDATA = 32'hBBBB2222;

        // Wait for first PREADY
        @(posedge PCLK); #1;
        while (!PREADY) begin @(posedge PCLK); #1; end

        @(negedge PCLK);
        transfer = 0; // No more after this second transfer

        // Wait for second PREADY
        @(posedge PCLK); #1;
        while (!PREADY) begin @(posedge PCLK); #1; end

        @(negedge PCLK);
        SWRITE = 0; SADDR = 0; SWDATA = 0; SSTRB = 0;

        // Verify both back-to-back writes
        apb_read(32'h00000030, 3'b000);
        #2;
        check(PRDATA, 32'hAAAA1111, "BackToBack_0");

        apb_read(32'h00000034, 3'b000);
        #2;
        check(PRDATA, 32'hBBBB2222, "BackToBack_1");

        // =======================================================
        // FINAL SUMMARY
        // =======================================================
        $display("\n============================================");
        $display("  SIMULATION COMPLETE");
        $display("  Total Tests : %0d", test_num - 1);
        $display("  PASSED      : %0d", pass_count);
        $display("  FAILED      : %0d", fail_count);
        $display("============================================\n");

        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED *** \n");
        else
            $display("  *** %0d TEST(S) FAILED — CHECK WAVEFORMS *** \n", fail_count);

        $finish;
    end

    // -------------------------------------------------------
    // TIMEOUT WATCHDOG
    // Kills simulation if it hangs (e.g. PREADY never arrives)
    // 10,000 ns = 10 µs should be more than enough
    // -------------------------------------------------------
    initial begin
        #100000;
        $display("[WATCHDOG] Simulation timeout! PREADY may be stuck.");
        $finish;
    end

    // -------------------------------------------------------
    // WAVEFORM MONITOR (prints key signal transitions)
    // -------------------------------------------------------
    initial begin
        $monitor("[%0t ns] PSEL=%0b PENABLE=%0b PWRITE=%0b PADDR=0x%08X PWDATA=0x%08X PRDATA=0x%08X PREADY=%0b PSLVERR=%0b",
                  $time, PSEL, PENABLE, PWRITE, PADDR, PWDATA, PRDATA, PREADY, PSLVERR);
    end

endmodule
