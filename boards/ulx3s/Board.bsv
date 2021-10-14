package Board;

import Connectable :: *;
import Lanai_IFC :: *;
import Lanai_CPU :: *;
import Lanai_Memory :: *;
import ECP5 :: *;
import RAM :: *;

interface Top;
    (* always_enabled *)
    method Bit#(8) led;

    interface ESP32 wifi;
endinterface

interface ESP32;
    (* always_enabled *)
    method Bit#(1) gpio0;
endinterface

(* synthesize *)
module mkMemory(Lanai_Memory#(4096));
    Lanai_Memory#(4096) inner <- mkBlockMemory("boards/ulx3s/bram.bin");
    interface dmem = inner.dmem;
    interface imem = inner.imem;
endmodule

(* synthesize, default_clock_osc="clk_25mhz", default_reset="btn_pwr" *)
module mkTop (Top);
    GSR gsr <- mkGSR;

    Lanai_Memory#(4096) mem <- mkMemory;
    Lanai_IFC cpu <- mkLanaiCPU;

    mkConnection(cpu.imem_client, mem.imem);
    mkConnection(cpu.dmem_client, mem.dmem);

    interface ESP32 wifi;
        method gpio0 = 1;
    endinterface

    method led = cpu.readPC[7:0];
endmodule

endpackage
