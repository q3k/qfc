package ECP5;

interface GSR;
endinterface

import "BVI" GSR = module mkGSR(GSR ifc);
    default_clock no_clock;
    default_reset gsr (GSR);
endmodule

interface EHXPLL;
    interface Clock clkop;

    (* always_ready, always_enabled *)
    method Bool locked;
endinterface

import "BVI" EHXPLLL = module mkPLL#(Clock clk_in, Reset rst_in) (EHXPLL);
    Bit#(1) zero = 0;
    Bit#(1) one = 1;

    parameter PLLRST_ENA = "DISABLED";
    parameter INTFB_WAKE = "DISABLED";
    parameter STDBY_ENABLE = "DISABLED";
    parameter DPHASE_SOURCE = "DISABLED";
    parameter OUTDIVIDER_MUXA = "DIVA";
    parameter OUTDIVIDER_MUXB = "DIVB";
    parameter OUTDIVIDER_MUXC = "DIVC";
    parameter OUTDIVIDER_MUXD = "DIVD";
    parameter CLKI_DIV = 1;
    parameter CLKOP_ENABLE = "ENABLED";
    parameter CLKOP_DIV = 7;
    parameter CLKOP_CPHASE = 2;
    parameter CLKOP_FPHASE = 0;
    parameter FEEDBK_PATH = "CLKOP";
    parameter CLKFB_DIV = 4;

    default_clock clki(CLKI, (* unused *) UNUSED) = clk_in;
    default_reset rsti = rst_in;

    method LOCK locked clocked_by(no_clock);

    output_clock clkop(CLKOP);
    port RST = zero;
    port STDBY = zero;
    port PHASESEL0 = zero;
    port PHASESEL1 = zero;
    port PHASEDIR = one;
    port PHASESTEP = one;
    port PHASELOADREG = one;
    port PLLWAKESYNC = zero;
    port ENCLKOP = zero;

    same_family(clki, clkop);
endmodule

endpackage
