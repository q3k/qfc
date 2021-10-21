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
module mkMemory(Lanai_BlockRAM#(1024));
    // TODO(q3k): ... figure out how the fuck to unhardcode this.
    Lanai_BlockRAM#(1024) inner <- mkBlockMemory("bazel-out/k8-fastbuild/bin/boards/ulx3s/bram.bin");
    return inner;
endmodule

(* synthesize, default_clock_osc="clk_25mhz", default_reset="btn_pwr" *)
module mkTop (Top);
    GSR gsr <- mkGSR;

    let mem <- mkMemory;
    Lanai_IFC cpu <- mkLanaiCPU;

    mkConnection(cpu.imem_client, mem.memory.imem);
    mkConnection(cpu.dmem_client, mem.memory.dmem);

    interface ESP32 wifi;
        method gpio0 = 1;
    endinterface

    method led = cpu.readPC[7:0];
endmodule

endpackage
