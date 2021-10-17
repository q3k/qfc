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
    Word pc;
} WaitReadResponse deriving (Bits);

module mkCPUMemory #( RegisterWriteMemory rwr
                    , RegisterWriteBypass bypass
                    , MispredictReport mispredict
                    ) (CPU_Memory);

    FIFOF #(ComputeToMemory) q <- mkPipelineFIFOF;
    FIFOF #(WaitReadResponse) waitRead <- mkPipelineFIFOF;
    FIFO #(Misprediction) computedPC <- mkBypassFIFO;
    Reg#(Bool) pendingPCLoad <- mkReg(False);
    Reg#(Bool) startPCLoad <- mkDWire(False);
    Reg#(Bool) stopPCLoad <- mkDWire(False);
    let pcLoadStall = pendingPCLoad;

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

    rule setPend;
        if (startPCLoad) begin
            pendingPCLoad <= True;
        end else begin
            if (stopPCLoad) begin
                pendingPCLoad <= False;
            end
        end
    endrule

    interface Client dmem;
        interface Get request;
            method ActionValue#(DMemReq) get if (!pcLoadStall);
                busyReq.send();

                q.deq;
                eaProbe <= q.first.ea;
                let pc = q.first.pc;


                Maybe#(Word) data = tagged Invalid;
                Bool spurious = False;
                case (q.first.op) matches
                    tagged Noop: begin
                        waitRead.enq(WaitReadResponse { pc: pc, rd: tagged Invalid });
                        spurious = True;
                    end
                    tagged Load .rd: begin
                        waitRead.enq(WaitReadResponse { pc: pc, rd: tagged Valid rd });
                        if (rd == PC) begin
                            startPCLoad <= True;
                        end
                    end
                    tagged Store .d: begin
                        waitRead.enq(WaitReadResponse { pc: pc, rd: tagged Invalid });
                        data = tagged Valid d;
                    end
                endcase

                return DMemReq { addr: q.first.ea
                               , width: q.first.width
                               , data: data
                               , spurious: spurious
                               , pc: pc
                               };
            endmethod
        endinterface

        interface Put response;
            method Action put(Word resp);
                waitRead.deq;
                if (waitRead.first.rd matches tagged Valid .rd) begin
                    busyResp.send();
                    responseRegProbe <= rd;
                    if (rd == PC) begin
                        stopPCLoad <= True;
                        mispredict.put(Misprediction { pc: resp
                                                     , opc: waitRead.first.pc + 8
                                                     });
                    end else begin
                        rwr.write(rd, resp);
                        bypass.strobe(rd, resp);
                    end
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
