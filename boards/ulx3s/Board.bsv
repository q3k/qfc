package Board;

import Connectable :: *;
import Lanai_IFC :: *;
import Lanai_CPU :: *;
import Lanai_Memory :: *;

import RAM :: *;

interface GSR;
endinterface

import "BVI" GSR =
    module mkGSR (GSR ifc);
        default_clock no_clock;
        default_reset gsr (GSR);
    endmodule


interface Top;
    (* always_enabled *)
    method Bit#(8) led;

    interface ESP32 wifi;
endinterface

interface ESP32;
    (* always_enabled *)
    method Bit#(1) gpio0;
endinterface

(* synthesize, default_clock_osc="clk_25mhz", default_reset="btn_pwr" *)
module mkTop (Top);
    GSR gsr <- mkGSR;

    Lanai_Memory#(4096) mem <- mkBlockMemory("boards/ulx3s/bram.bin");
    Lanai_IFC cpu <- mkLanaiCPU;

    mkConnection(cpu.imem_client, mem.imem);

    interface ESP32 wifi;
        method gpio0 = 1;
    endinterface

    method led = cpu.readPC[23:16];
endmodule

endpackage
