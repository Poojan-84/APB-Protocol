// ============================================================
// APB Master Module
// Drives the APB bus based on external system inputs.
// Implements the 3-state FSM: IDLE -> SETUP -> ACCESS
// ============================================================
module APB_Master (
    // --- External System Inputs ---
    // These signals come from outside (e.g., testbench acting as the system)
    // "S" prefix = System-side signals (not APB bus signals)
    input SWRITE,              // System write enable: 1=write, 0=read
    input [31:0] SADDR,        // System address to transfer on APB
    input [31:0] SWDATA,       // System write data
    input [3:0]  SSTRB,        // System write strobe: each bit enables one byte lane
    input [2:0]  SPROT,        // System protection type (privilege/security/instruction)
    input        transfer,     // Handshake from system: 1 = initiate/continue a transfer

    // --- APB Bus Master Outputs ---
    // These are the actual APB signals driven onto the bus
    output reg        PSEL,    // Peripheral Select: activates the target slave
    output reg        PENABLE, // Enable: goes high in ACCESS state to complete transfer
    output reg        PWRITE,  // Write control: 1=write, 0=read (stable across SETUP+ACCESS)
    output reg [31:0] PADDR,   // APB Address bus (stable across SETUP+ACCESS)
    output reg [31:0] PWDATA,  // APB Write Data (stable across SETUP+ACCESS)
    output reg [3:0]  PSTRB,   // APB Write Strobe: which byte lanes are active
    output reg [2:0]  PPROT,   // APB Protection signals

    // --- APB Clock and Reset ---
    input PCLK,                // APB clock: all APB transfers are synchronous to this
    input PRESETn,             // Active-LOW synchronous reset (APB spec requires this)

    // --- APB Slave Response Inputs ---
    input PREADY,              // Slave ready: 1=slave can complete transfer, 0=insert wait states
    input PSLVERR              // Slave error: 1=transfer failed (optional signal per APB spec)
);

    // --- FSM State Encoding ---
    // Using 2-bit binary encoding for 3 states
    // The (* fsm_encoding = "one_hot" *) attribute overrides this to one-hot in synthesis
    localparam IDLE   = 2'b00, // No transfer in progress, bus is idle
               SETUP  = 2'b01, // First cycle: PSEL asserted, signals driven, PENABLE=0
               ACCESS = 2'b10; // Second+ cycle: PENABLE asserted, waiting for PREADY

    // (* fsm_encoding = "one_hot" *) tells the synthesizer to use one-hot encoding
    // even though we coded it as binary. One-hot is faster for small FSMs on FPGAs
    (* fsm_encoding = "one_hot" *)
    reg [1:0] ns, cs; // ns = next state, cs = current state

    // -------------------------------------------------------
    // STATE MEMORY (Sequential Block)
    // Registers the current state on every rising clock edge
    // Resets to IDLE on active-low reset
    // -------------------------------------------------------
    always @(posedge PCLK, negedge PRESETn) begin
        if (~PRESETn)
            cs <= IDLE;   // Asynchronous reset: go to IDLE immediately when reset asserted
        else
            cs <= ns;     // On each rising clock edge, advance to next state
    end

    // -------------------------------------------------------
    // NEXT STATE LOGIC (Combinational Block)
    // Determines the next state based on current state and inputs
    // -------------------------------------------------------
    always @(*) begin
        case (cs)
            IDLE : begin
                // Stay IDLE until the system requests a transfer
                if (transfer)
                    ns = SETUP;
                else
                    ns = IDLE;
            end

            SETUP : begin
                // SETUP always lasts exactly ONE clock cycle per APB spec.
                // No conditions — always move to ACCESS next cycle.
                ns = ACCESS;
            end

            ACCESS : begin
                // Stay in ACCESS (insert wait states) as long as PREADY=0
                if (PREADY && !transfer)
                    ns = IDLE;       // Transfer done, no new transfer pending → go idle
                else if (PREADY && transfer)
                    ns = SETUP;      // Transfer done, new transfer pending → back to SETUP
                else
                    ns = ACCESS;     // Slave not ready yet → stay in ACCESS (wait state)
            end

            default : ns = IDLE;    // Safety default for synthesis
        endcase
    end

    // -------------------------------------------------------
    // OUTPUT LOGIC (Combinational Block — Mealy/Moore outputs)
    // Drives APB signals based on current state
    // -------------------------------------------------------
    always @(*) begin
        if (~PRESETn) begin
            // On reset: deassert all APB outputs to safe defaults
            PSEL    = 0;
            PENABLE = 0;
            PWRITE  = 0;
            PADDR   = 0;
            PWDATA  = 0;
            PSTRB   = 0;
            PPROT   = 0;
        end
        else begin
            case (cs)
                IDLE : begin
                    // Bus is idle: deselect slave, disable transfer
                    PSEL    = 0;
                    PENABLE = 0;
                    // PWRITE, PADDR, PWDATA etc. are don't-care in IDLE
                    // (they retain last values — harmless since PSEL=0)
                end

                SETUP : begin
                    // Assert PSEL to select the slave
                    // PENABLE stays LOW — this distinguishes SETUP from ACCESS
                    // All address/data/control signals are set up here and must
                    // remain STABLE through the ACCESS phase (APB spec requirement)
                    PSEL    = 1;
                    PENABLE = 0;
                    PWRITE  = SWRITE;  // Latch write/read direction from system
                    PADDR   = SADDR;   // Latch target address from system
                    PWDATA  = SWDATA;  // Latch write data from system
                    PSTRB   = SSTRB;   // Latch byte strobes from system
                    PPROT   = SPROT;   // Latch protection bits from system
                end

                ACCESS : begin
                    // Assert PENABLE to signal start of access phase
                    // PSEL remains HIGH
                    // Address/data signals must NOT change here (set in SETUP, held stable)
                    PSEL    = 1;
                    PENABLE = 1;
                    // PWRITE, PADDR, PWDATA, PSTRB, PPROT hold their values
                    // automatically since this is combinational and cs hasn't changed
                end
            endcase
        end
    end

endmodule
