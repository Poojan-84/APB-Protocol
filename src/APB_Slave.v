// ============================================================
// APB Slave Module
// Responds to APB transfers with an internal cache memory.
// Supports all PSTRB combinations for partial word writes.
// ============================================================
module APB_Slave #(
    parameter MEM_WIDTH = 32,   // Width of each memory word in bits
    parameter MEM_DEPTH = 1024  // Number of addressable memory locations
)(
    // --- APB Bus Inputs (from Master) ---
    input        PSEL,          // Peripheral Select: this slave is being addressed
    input        PENABLE,       // Enable: high during ACCESS phase
    input        PWRITE,        // 1=write transfer, 0=read transfer
    input [31:0] PADDR,         // Address of the target memory location
    input [31:0] PWDATA,        // Write data from master
    input [3:0]  PSTRB,         // Write strobe: which byte lanes carry valid data
    input [2:0]  PPROT,         // Protection signals (not used in logic here but received)

    // --- APB Clock and Reset ---
    input        PCLK,          // APB clock
    input        PRESETn,       // Active-LOW reset

    // --- APB Slave Outputs (to Master) ---
    output reg [31:0] PRDATA,   // Read data returned to master
    output            PREADY,   // Ready signal: 1=slave can complete transfer now
    output reg        PSLVERR   // Slave error flag: 1=error occurred
);

    // --- Internal Cache Memory ---
    // Simulates a simple memory inside the slave for testing read/write
    // Indexed by PADDR, each location is MEM_WIDTH bits wide
    reg [MEM_WIDTH-1:0] Cache [MEM_DEPTH-1:0];

    // -------------------------------------------------------
    // MAIN SEQUENTIAL BLOCK
    // Handles write, read, and error detection
    //
    // BIG FIX HERE: Changed `else if (PSEL)` to `else if (PSEL && PENABLE)`
    // REASON: Per APB spec, the actual data transfer must only occur
    // in the ACCESS phase, which is when BOTH PSEL AND PENABLE are high.
    // The original code wrote to memory during SETUP (PSEL=1, PENABLE=0),
    // which violates the protocol — data/address signals are only being
    // set up in SETUP phase and are not yet guaranteed stable for capture.
    // -------------------------------------------------------
    always @(posedge PCLK) begin
        if (~PRESETn) begin
            // On reset: clear error flag and read data output
            PSLVERR <= 0;
            PRDATA  <= 0;
            // Note: Cache memory is NOT cleared on reset here (synthesis limitation;
            // clearing large memories on reset is expensive in hardware)
        end
        else if (PSEL && PENABLE) begin  // ← FIXED: was `else if (PSEL)`
            // Only act during the ACCESS phase (PSEL=1 AND PENABLE=1)

            if (PWRITE) begin
                // --- WRITE OPERATION ---
                // PSTRB controls which byte lanes of PWDATA are written to memory.
                // Each bit of PSTRB corresponds to one byte:
                //   PSTRB[0]=1 → byte [7:0]   is valid
                //   PSTRB[1]=1 → byte [15:8]  is valid
                //   PSTRB[2]=1 → byte [23:16] is valid
                //   PSTRB[3]=1 → byte [31:24] is valid
                // The implementation below stores only the enabled bytes,
                // zeroing or sign-extending the rest.
                case (PSTRB)
                    4'b0001: Cache[PADDR] <= {{24{PWDATA[7]}},  PWDATA[7:0]};
                    // Byte 0 only: sign-extend from bit 7 to fill upper 24 bits

                    4'b0010: Cache[PADDR] <= {{24{PWDATA[15]}}, PWDATA[15:8],  8'h00};
                    // Byte 1 only: sign-extend from bit 15, zero-fill byte 0

                    4'b0011: Cache[PADDR] <= {{16{PWDATA[15]}}, PWDATA[15:0]};
                    // Bytes 0+1 (half-word): sign-extend from bit 15

                    4'b0100: Cache[PADDR] <= {{24{PWDATA[23]}}, PWDATA[23:16], 8'h00};
                    // Byte 2 only: sign-extend from bit 23, zero-fill byte 0

                    4'b0101: Cache[PADDR] <= {{16{PWDATA[23]}}, PWDATA[23:16], 8'h00, PWDATA[7:0]};
                    // Bytes 0+2: sign-extend from bit 23, zero byte 1

                    4'b0110: Cache[PADDR] <= {{8{PWDATA[23]}},  PWDATA[23:8],  8'h00};
                    // Bytes 1+2: sign-extend from bit 23, zero byte 0

                    4'b0111: Cache[PADDR] <= {{8{PWDATA[23]}},  PWDATA[23:0]};
                    // Bytes 0+1+2: sign-extend from bit 23

                    4'b1000: Cache[PADDR] <= {PWDATA[31:24], 24'h000000};
                    // Byte 3 only: store MSB, zero-fill lower 24 bits (no sign extend)

                    4'b1001: Cache[PADDR] <= {PWDATA[31:24], 16'h0000,        PWDATA[7:0]};
                    // Bytes 0+3: store MSB and LSB, zero middle 2 bytes

                    4'b1010: Cache[PADDR] <= {PWDATA[31:23], 8'h00, PWDATA[15:8], 8'h00};
                    // Bytes 1+3: store bytes 1 and 3, zero bytes 0 and 2

                    4'b1011: Cache[PADDR] <= {PWDATA[31:23], 8'h00, PWDATA[15:0]};
                    // Bytes 0+1+3: store bytes 0,1,3; zero byte 2

                    4'b1100: Cache[PADDR] <= {PWDATA[31:16], 16'h0000};
                    // Bytes 2+3 (upper half-word): zero-fill lower 16 bits

                    4'b1101: Cache[PADDR] <= {PWDATA[31:16], 8'h00, PWDATA[7:0]};
                    // Bytes 0+2+3: zero byte 1

                    4'b1110: Cache[PADDR] <= {PWDATA[31:8],  8'h00};
                    // Bytes 1+2+3: zero byte 0

                    4'b1111: Cache[PADDR] <= PWDATA[31:0];
                    // All 4 bytes: full 32-bit word write

                    default: Cache[PADDR] <= 32'h00000000;
                    // Safety default: zero out memory for undefined PSTRB
                endcase
                PSLVERR <= 0; // Write completed successfully, no error

            end
            else begin
                // --- READ OPERATION ---
                if (PSTRB != 0) begin
                    // Per APB spec: PSTRB must be 0 during read transfers.
                    // If master sends non-zero PSTRB on a read, flag it as a slave error.
                    PSLVERR <= 1;
                end
                else begin
                    // Normal read: fetch word from cache at requested address
                    PRDATA  <= Cache[PADDR];
                    PSLVERR <= 0;
                end
            end
        end
    end

    // --- PREADY Generation ---
    // This slave has no internal wait states, so it asserts PREADY
    // as soon as it enters the ACCESS phase (PSEL && PENABLE both high).
    // For a slower slave, PREADY could be delayed using a counter etc.
    assign PREADY = (PSEL && PENABLE) ? 1 : 0;

endmodule
