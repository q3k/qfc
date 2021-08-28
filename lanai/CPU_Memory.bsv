package CPU_Memory;

import ClientServer :: *;
import GetPut :: *;
import FIFO :: *;
import FIFOF :: *;
import Probe :: *;
import SpecialFIFOs :: *;

import Lanai_IFC :: *;
import CPU_Defs :: *;

interface CPU_Memory;
    interface Put #(ComputeToMemory) compute;
    interface Client #(DMemReq, Word) dmem;
endinterface

typedef struct {
    Register rd;
} WaitReadResponse deriving (Bits);

module mkCPUMemory #( RegisterWriteMemory rwr
                    ) (CPU_Memory);

    FIFO #(ComputeToMemory) q <- mkPipelineFIFO;
    FIFOF #(WaitReadResponse) waitRead <- mkPipelineFIFOF;
    PulseWire busyReq <- mkPulseWire;
    PulseWire busyResp <- mkPulseWire;

    let busyReqProbe <- mkProbe;
    let busyRespProbe <- mkProbe;
    let writeStallProbe <- mkProbe;

    let eaProbe <- mkProbe;
    let storeProbe <- mkProbe;
    let valueProbe <- mkProbe;
    let rdProbe <- mkProbe;

    let responseRegProbe <- mkProbe;

    rule updateBusyProbe;
        busyReqProbe <= busyReq;
        busyRespProbe <= busyResp;
    endrule

    rule updateStallProbe;
        writeStallProbe <= waitRead.notEmpty;
    endrule

    interface Client dmem;
        interface Get request;
            method ActionValue#(DMemReq) get;
                busyReq.send();

                q.deq;
                eaProbe <= q.first.ea;
                storeProbe <= q.first.store;
                valueProbe <= q.first.value;
                rdProbe <= q.first.rd;

                if (q.first.store == False) begin
                    waitRead.enq(WaitReadResponse { rd: q.first.rd });
                end

                return DMemReq { addr: q.first.ea
                               , data: case (q.first.store) matches
                                     True:  tagged Valid q.first.value;
                                     False: tagged Invalid;
                                 endcase
                               };
            endmethod
        endinterface
        interface Put response;
            method Action put(Word resp);
                busyResp.send();

                waitRead.deq;
                responseRegProbe <= waitRead.first.rd;
                rwr.write(waitRead.first.rd, resp);
            endmethod
        endinterface
    endinterface


    interface Put compute;
        method put = q.enq;
    endinterface

endmodule

endpackage
