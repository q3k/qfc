package Lanai_Memory;

import BRAM :: *;
import FIFO :: *;
import SpecialFIFOs :: *;

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
    cfg.allowWriteResponseBypass = False;
    BRAM2Port#(Bit#(n), Bit#(32)) bram <- mkBRAM2Server(cfg);

    FIFO#(BRAMRequest#(Bit#(n), Bit#(32))) delayFIFO <- mkPipelineFIFO;

    let nwords = valueOf(n);

    rule delayed_dmem;
        delayFIFO.deq;
        let breq = delayFIFO.first;
        bram.portB.request.put(breq);
    endrule

    interface Server imem;
        interface Put request;
            method Action put(Word addr);
                bram.portA.request.put(BRAMRequest { write: False
                                                   , responseOnWrite: True
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
                let breq = BRAMRequest { write: isValid(req.data)
                                       , responseOnWrite: True
                                       , address: req.addr[nwords+1:2]
                                       , datain: fromMaybe(0, req.data)
                                       };
                if (req.addr == 256 || req.addr == 0) begin
                    bram.portB.request.put(breq);
                end else begin
                    delayFIFO.enq(breq);
                end
            endmethod
        endinterface
        interface Get response = bram.portB.response;
    endinterface
endmodule

endpackage
