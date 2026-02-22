// ============================================================
// APB Wrapper Module
// Top-level integration module that connects the APB Master and APB Slave together via the APB bus wires.
// This is the module you would instantiate in a testbench.
// ============================================================
module APB_Wrapper (
    // --- System / Testbench Inputs ---
    input        PCLK,          // APB clock
    input        PRESETn,       // Active-LOW reset
    input        SWRITE,        // System write request
    input [31:0] SADDR,         // System address
    input [31:0] SWDATA,        // System write data
    input [3:0]  SSTRB,         // System byte strobes
    input [2:0]  SPROT,         // System protection bits
    input        transfer,      // System transfer request flag

    // --- Output to Testbench ---
    output [31:0] PRDATA        // Read data returned from slave (exposed to system)
);

    // --- Internal APB Bus Wires ---
    // These wires carry APB signals between master and slave
    // They represent the actual APB bus interface
    wire        PSEL;           // Slave select line (Master → Slave)
    wire        PENABLE;        // Enable line (Master → Slave)
    wire        PWRITE;         // Write control (Master → Slave)
    wire [31:0] PADDR;          // Address bus (Master → Slave)
    wire [31:0] PWDATA;         // Write data bus (Master → Slave)
    wire [3:0]  PSTRB;          // Write strobes (Master → Slave)
    wire [2:0]  PPROT;          // Protection signals (Master → Slave)
    wire        PREADY;         // Ready signal (Slave → Master)
    wire        PSLVERR;        // Slave error signal (Slave → Master)

    // --- APB Master Instantiation ---
    // Translates system-side requests into APB bus transactions
    APB_Master Master (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),
        // System-side inputs
        .SWRITE  (SWRITE),
        .SADDR   (SADDR),
        .SWDATA  (SWDATA),
        .SSTRB   (SSTRB),
        .SPROT   (SPROT),
        .transfer(transfer),
        // APB bus outputs (to slave via wires)
        .PSEL    (PSEL),
        .PENABLE (PENABLE),
        .PWRITE  (PWRITE),
        .PADDR   (PADDR),
        .PWDATA  (PWDATA),
        .PSTRB   (PSTRB),
        .PPROT   (PPROT),
        // APB slave responses (from slave via wires)
        .PREADY  (PREADY),
        .PSLVERR (PSLVERR)
    );

    // --- APB Slave Instantiation ---
    // Responds to APB transactions from the master
    APB_Slave Slave (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),
        // APB bus inputs (from master via wires)
        .PSEL    (PSEL),
        .PENABLE (PENABLE),
        .PWRITE  (PWRITE),
        .PADDR   (PADDR),
        .PWDATA  (PWDATA),
        .PSTRB   (PSTRB),
        .PPROT   (PPROT),
        // APB slave outputs (to master and system)
        .PREADY  (PREADY),
        .PSLVERR (PSLVERR),
        .PRDATA  (PRDATA)   // Read data exposed at wrapper output
    );

endmodule
