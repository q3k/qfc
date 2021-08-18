package Lanai_Memory;

import BRAM :: *;

import CPU_Defs :: *;
import Lanai_IFC :: *;

// n is the amount of kilowords of RAM available.
interface Lanai_Memory#(numeric type n);
    interface Server#(Word, Word) imem;
    interface Server#(DMemReq, Word) dmem;
endinterface

module mkBlockMemory#(String filename) (Lanai_Memory#(k)) provisos (Log#(k, n));
    BRAM_Configure cfg = defaultValue;
    cfg.latency = 1;
    cfg.loadFormat = tagged Hex filename;
    cfg.outFIFODepth = 3;
    cfg.allowWriteResponseBypass = True;
    BRAM2Port#(Bit#(n), Bit#(32)) bram <- mkBRAM2Server(cfg);

    let nwords = valueOf(n);

    interface Server imem;
        interface Put request;
            method Action put(Word addr);
                bram.portA.request.put(BRAMRequest { write: False
                                                   , responseOnWrite: False
                                                   , address: addr[nwords+1:2]
                                                   , datain: 0
                                                   });
            endmethod
        endinterface
        interface Get response = bram.portA.response;
    endinterface

    interface Server dmem;
        interface Put request;
            method Action put(DMemReq req);
                bram.portB.request.put(case (req) matches
                    tagged Read .addr: BRAMRequest { write: False
                                                   , responseOnWrite: False
                                                   , address: addr[nwords+1:2]
                                                   , datain: 0
                                                   };
                    tagged Write .wr: BRAMRequest  { write: True
                                                   , responseOnWrite: False
                                                   , address: wr.address[nwords+1:2]
                                                   , datain: wr.data
                                                   };
                endcase);
            endmethod
        endinterface
        interface Get response = bram.portB.response;
    endinterface
endmodule

endpackage
