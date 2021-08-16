package Board;

import BRAM :: *;
import ClientServer :: *;
import Connectable :: *;
import Lanai_IFC :: *;
import Lanai_CPU :: *;

interface GSR;
endinterface

import "BVI" GSR =
    module mkGSR (GSR ifc);
        default_clock no_clock;
        default_reset gsr (GSR);
    endmodule


interface TestMem;
    interface Server#(Word, Word) imem;
    interface Server#(DMemReq, Word) dmem;
endinterface

module mkBlockMem (TestMem);
    BRAM_Configure cfg = defaultValue;
    cfg.latency = 1;
    cfg.loadFormat = tagged Hex "boards/ulx3s/bram.bin";
    cfg.outFIFODepth = 3;
    cfg.allowWriteResponseBypass = True;
    BRAM2Port#(Bit#(13), Bit#(32)) bram <- mkBRAM2Server(cfg);

    interface Server imem;
        interface Put request;
            method Action put(Word addr);
                bram.portA.request.put(BRAMRequest { write: False
                                                   , responseOnWrite: False
                                                   , address: addr[14:2]
                                                   , datain: 0
                                                   });
            endmethod
        endinterface
        interface Get response = bram.portA.response;
    endinterface
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

    TestMem mem <- mkBlockMem;
    Lanai_IFC cpu <- mkLanaiCPU;
    mkConnection(cpu.imem_client, mem.imem);

    interface ESP32 wifi;
        method gpio0 = 1;
    endinterface

    method led = cpu.readPC[23:16];
endmodule

endpackage
