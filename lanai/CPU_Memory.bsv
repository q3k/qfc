// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2022 Sergiusz Bazanski

package CPU_Memory;

import ClientServer :: *;
import GetPut :: *;
import FIFO :: *;
import FIFOF :: *;
import Probe :: *;
import SpecialFIFOs :: *;
import Wishbone :: *;

import Lanai_IFC :: *;
import CPU_Defs :: *;

interface CPU_Memory;
    interface Put #(ComputeToMemory) compute;
    interface Client #(DMemReq, Word) dmem;
    interface Wishbone::Master #(32, 32, 4) sysmem;
endinterface

typedef struct {
    Maybe#(Register) rd;
    Word pc;
    Word ea;
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
    FIFO#(Wishbone::SlaveResponse#(32)) delaySysmemResponse <- mkPipelineFIFO;

    Wishbone::MasterConnector#(32, 32, 4) sysmemMaster <- mkMasterConnector;

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

    rule sysmemRequest(!pcLoadStall && q.first.ea >= sysmemSplit);
        q.deq;
        busyReq.send();
        eaProbe <= q.first.ea;
        let pc = q.first.pc;
        Maybe#(Bit#(32)) data = tagged Invalid;
        Bool spurious = False;
        case (q.first.op) matches
            tagged Noop: begin
                waitRead.enq(WaitReadResponse { pc: pc, ea: q.first.ea, rd: tagged Invalid });
                spurious = True;
            end
            tagged Load .rd: begin
                waitRead.enq(WaitReadResponse { pc: pc, ea: q.first.ea, rd: tagged Valid rd });
                if (rd == PC) begin
                    startPCLoad <= True;
                end
            end
            tagged Store .d: begin
                waitRead.enq(WaitReadResponse { pc: pc, ea: q.first.ea, rd: tagged Invalid });
                data = tagged Valid d;
            end
        endcase
        sysmemMaster.server.request.put(SlaveRequest { address: q.first.ea
                                                     , writeData: data
                                                     , select: 4'b1111
                                                     });
    endrule

    rule sysmemResponseDelay;
        let data <- sysmemMaster.server.response.get();
        delaySysmemResponse.enq(data);
    endrule

    rule sysmemResponse(waitRead.first.ea >= sysmemSplit);
        waitRead.deq;
        let resp = delaySysmemResponse.first;
        delaySysmemResponse.deq();

        let data = fromMaybe(0, resp.readData);

        if (waitRead.first.rd matches tagged Valid .rd) begin
            busyResp.send();
            responseRegProbe <= rd;
            if (rd == PC) begin
                stopPCLoad <= True;
                mispredict.put(Misprediction { pc: data
                                             , opc: waitRead.first.pc + 8
                                             });
            end else begin
                rwr.write(rd, data);
                bypass.strobe(rd, data);
            end
        end
    endrule

    interface Client dmem;
        interface Get request;
            method ActionValue#(DMemReq) get if (!pcLoadStall && q.first.ea < sysmemSplit);
                busyReq.send();

                q.deq;
                eaProbe <= q.first.ea;
                let pc = q.first.pc;


                Maybe#(Word) data = tagged Invalid;
                Bool spurious = False;
                case (q.first.op) matches
                    tagged Noop: begin
                        waitRead.enq(WaitReadResponse { pc: pc, ea: q.first.ea, rd: tagged Invalid });
                        spurious = True;
                    end
                    tagged Load .rd: begin
                        waitRead.enq(WaitReadResponse { pc: pc, ea: q.first.ea, rd: tagged Valid rd });
                        if (rd == PC) begin
                            startPCLoad <= True;
                        end
                    end
                    tagged Store .d: begin
                        waitRead.enq(WaitReadResponse { pc: pc, ea: q.first.ea, rd: tagged Invalid });
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

    interface sysmem = sysmemMaster.master;
endmodule

endpackage
