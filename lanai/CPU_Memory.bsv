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
    Maybe#(Register) rd;
} WaitReadResponse deriving (Bits);

module mkCPUMemory #( RegisterWriteMemory rwr
                    , RegisterWriteBypass bypass
                    ) (CPU_Memory);

    FIFOF #(ComputeToMemory) q <- mkPipelineFIFOF;
    FIFOF #(WaitReadResponse) waitRead <- mkPipelineFIFOF;

    PulseWire busyReq <- mkPulseWire;
    PulseWire busyResp <- mkPulseWire;
    PulseWire busyPut <- mkPulseWire;

    let busyReqProbe <- mkProbe;
    let busyRespProbe <- mkProbe;
    let busyPutProbe <- mkProbe;
    let fullQ <- mkProbe;
    let fullWaitRead <- mkProbe;

    let eaProbe <- mkProbe;
    let responseRegProbe <- mkProbe;

    rule updateBusyProbe;
        busyReqProbe <= busyReq;
        busyRespProbe <= busyResp;
    endrule
    rule updateBusyPutProbe;
        busyPutProbe <= busyPut;
    endrule
    rule updateFullQ;
        fullQ <= !q.notFull;
    endrule
    rule updateFullWaitRead;
        fullWaitRead <= !waitRead.notFull;
    endrule

    interface Client dmem;
        interface Get request;
            method ActionValue#(DMemReq) get;
                busyReq.send();

                q.deq;
                eaProbe <= q.first.ea;

                Maybe#(Word) data = tagged Invalid;
                case (q.first.op) matches
                    tagged Noop: begin
                        waitRead.enq(WaitReadResponse { rd: tagged Invalid });
                    end
                    tagged Load .rd: begin
                        waitRead.enq(WaitReadResponse { rd: tagged Valid rd });
                    end
                    tagged Store .d: begin
                        waitRead.enq(WaitReadResponse { rd: tagged Invalid });
                        data = tagged Valid d;
                    end
                endcase

                return DMemReq { addr: q.first.ea
                               , data: data
                               };
            endmethod
        endinterface
        interface Put response;
            method Action put(Word resp);

                waitRead.deq;
                if (waitRead.first.rd matches tagged Valid .rd) begin
                    busyResp.send();
                    responseRegProbe <= rd;
                    rwr.write(rd, resp);
                    bypass.strobe(rd, resp);
                end
            endmethod
        endinterface
    endinterface


    interface Put compute;
        method Action put(ComputeToMemory v);
            busyPut.send();
            q.enq(v);
        endmethod
    endinterface

endmodule

endpackage
