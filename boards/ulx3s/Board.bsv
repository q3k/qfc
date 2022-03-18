package Board;

import Connectable :: *;
import TieOff :: *;

import Lanai_IFC :: *;
import Lanai_CPU :: *;
import Lanai_Memory :: *;
import ECP5 :: *;
import RAM :: *;
import WishboneCrossbar :: *;
import SPI :: *;

function Maybe#(WishboneCrossbar::DecodedAddr#(1, 32)) decoder(Bit#(32) address);
    return case (address) matches
        32'h4001_3???: tagged Valid DecodedAddr { downstream: 0, address: address & 32'hfff };
        default: tagged Invalid;
    endcase;
endfunction

interface Top;
    (* always_enabled *)
    method Bit#(8) led;

    (* always_enabled *)
    method Bool dutClock;

    (* always_enabled *)
    method Bool dutReset;

    interface ESP32 wifi;

    (* always_enabled *)
    method Bool spiMOSI;

    (* always_enabled *)
    method Bool spiSCK;
endinterface

interface ESP32;
    (* always_enabled *)
    method Bit#(1) gpio0;
endinterface

(* synthesize *)
module mkMemory(Lanai_BlockRAM#(1024));
    // TODO(q3k): ... figure out how the fuck to unhardcode this.
    Lanai_BlockRAM#(1024) inner <- mkBlockMemory("boards/ulx3s/bram.bin");
    return inner;
endmodule

(* synthesize, default_clock_osc="clk_25mhz", default_reset="btn_pwr" *)
module mkTop (Top);
    GSR gsr <- mkGSR;

    let mem <- mkMemory;
    Lanai_IFC cpu <- mkLanaiCPU;

    WishboneCrossbar::Crossbar#(1, 1, 32, 32, 4) fabric <- mkCrossbar(decoder);
    SPI::Controller#(32) spi <- mkSPIController;
    mkConnection(fabric.downstreams[0], spi.slave);

    mkConnection(cpu.imem_client, mem.memory.imem);
    mkConnection(cpu.dmem_client, mem.memory.dmem);
    mkConnection(cpu.sysmem_client, fabric.upstreams[0]);

    Reg#(Bit#(TLog#(25))) dutClockCounter <- mkReg(0);
    Reg#(Bool) dutClockValue <- mkReg(False);

    Reg#(Bit#(8)) dutResetCounter <- mkReg(0);

    rule dut_clock_up;
        if (dutClockCounter == 24) begin
            dutClockCounter <= 0;
            dutClockValue <= !dutClockValue;
        end else begin
            dutClockCounter <= dutClockCounter + 1;
        end
    endrule

    rule dut_reset_up;
        if (dutResetCounter != 255) begin
            dutResetCounter <= dutResetCounter + 1;
        end
    endrule

    interface ESP32 wifi;
        method gpio0 = 1;
    endinterface

    method led = cpu.readPC[7:0];

    method dutClock = dutClockValue;

    method Bool dutReset;
        return (dutResetCounter == 255);
    endmethod

    method spiMOSI = unpack(spi.spiMaster.mosi);
    method spiSCK  = unpack(spi.spiMaster.sclk);

endmodule

endpackage
