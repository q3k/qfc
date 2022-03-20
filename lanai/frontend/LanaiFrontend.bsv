package LanaiFrontend;

import GetPut :: *;
import ClientServer :: *;
import FIFO :: *;
import SpecialFIFOs :: *;

import Lanai_IFC :: *;

interface LanaiFrontend;
    interface Server#(Word, Word) core_imem;
    interface Server#(DMemReq, Word) core_dmem;

    interface Client#(Word, Word) fmc_imem;
    interface Client#(DMemReq, Word) fmc_dmem;

    interface Client#(Word, Word) ram_imem;
    interface Client#(DMemReq, Word) ram_dmem;
endinterface

typedef enum {
    FMC,
    RAM
} RoutingDecision;

typeclass Routable#(type a);
    function RoutingDecision route(a req);
endtypeclass

instance Routable#(Word);
    function RoutingDecision route(Word addr);
        if (addr >= 'h2000_0000) begin
            return RAM;
        end else begin
            return FMC;
        end
    endfunction
endinstance

instance Routable#(DMemReq);
    function RoutingDecision route(DMemReq req);
        return route(req.addr);
    endfunction
endinstance

interface Fork#(type t);
    interface Server#(t, Word) core;
    interface Client#(t, Word) fmc;
    interface Client#(t, Word) ram;
endinterface

module mkFork(Fork#(t)) provisos (Routable#(t), Bits#(t, _));
    FIFO#(t)    fifoReqFMC <- mkBypassFIFO;
    FIFO#(t)    fifoReqRAM <- mkBypassFIFO;
    FIFO#(Word) fifoRes    <- mkBypassFIFO;

    interface Server core;
        interface Put request;
            method Action put(t req);
                case (route(req)) matches
                    FMC: fifoReqFMC.enq(req);
                    RAM: fifoReqRAM.enq(req);
                endcase
            endmethod
        endinterface
        interface response = fifoToGet(fifoRes);
    endinterface

    interface Client fmc;
        interface request = fifoToGet(fifoReqFMC);
        interface response = fifoToPut(fifoRes);
    endinterface
    interface Client ram;
        interface request = fifoToGet(fifoReqRAM);
        interface response = fifoToPut(fifoRes);
    endinterface
endmodule

(* synthesize *)
module mkLanaiFrontend(LanaiFrontend);
    Fork#(Word)    forkIMem <- mkFork;
    Fork#(DMemReq) forkDMem <- mkFork;

    interface core_imem = forkIMem.core;
    interface core_dmem = forkDMem.core;
    interface fmc_imem  = forkIMem.fmc;
    interface fmc_dmem  = forkDMem.fmc;
    interface ram_imem  = forkIMem.ram;
    interface ram_dmem  = forkDMem.ram;
endmodule

endpackage
