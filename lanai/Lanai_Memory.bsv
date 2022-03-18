package Lanai_Memory;

import BRAM :: *;
import FIFO :: *;
import SpecialFIFOs :: *;

import CPU_Defs :: *;
import Lanai_IFC :: *;

interface Lanai_Memory;
    interface Server#(Word, Word) imem;
    interface Server#(DMemReq, Word) dmem;
endinterface

// n is the amount of kilowords of RAM available.
interface Lanai_BlockRAM#(numeric type n);
    interface Lanai_Memory memory;
endinterface

module mkBlockMemory#(String filename) (Lanai_BlockRAM#(k)) provisos (Log#(k, n));
    BRAM_Configure cfg = defaultValue;
    cfg.latency = 1;
    cfg.loadFormat = tagged Hex filename;
    cfg.outFIFODepth = 3;
    cfg.allowWriteResponseBypass = False;
    BRAM2PortBE#(Bit#(n), Bit#(32), 4) bram <- mkBRAM2ServerBE(cfg);

    FIFO#(BRAMRequestBE#(Bit#(n), Bit#(32), 4)) delayFIFO <- mkPipelineFIFO;

    FIFO#(DMemReq) waitQ <- mkPipelineFIFO;

    let nwords = valueOf(n);

    rule delayed_dmem;
        delayFIFO.deq;
        let breq = delayFIFO.first;
        bram.portB.request.put(breq);
    endrule

    interface Lanai_Memory memory;
        interface Server imem;
            interface Put request;
                method Action put(Word addr);
                    bram.portA.request.put(BRAMRequestBE { writeen: 4'b000
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
                    waitQ.enq(req);
                    Bit#(n) addr = req.addr[nwords+1:2];
                    let breq = BRAMRequestBE { writeen: 4'b0000
                                             , responseOnWrite: True
                                             , address: addr
                                             , datain: 0
                                             };
                    if (!req.spurious) begin
                        case (req.data) matches
                            tagged Valid .val: begin
                                case (req.width) matches
                                    tagged Word: begin
                                        $display("%x: DMEM WRITE REQ,  word [%x] <-  %x", req.pc, req.addr, val);
                                        breq.writeen = 4'b1111;
                                        breq.datain = val;
                                    end
                                    tagged HalfWord: begin
                                        Bit#(32) valH = zeroExtend(val[15:0]);
                                        $display("%x: DMEM WRITE REQ, hword [%x] <- %x", req.pc, req.addr, valH);
                                        case (req.addr[1]) matches
                                            1'b1: begin
                                                breq.writeen = 4'b0011;
                                                breq.datain = valH;
                                            end
                                            1'b0: begin
                                                breq.writeen = 4'b1100;
                                                breq.datain = valH << 16;
                                            end
                                        endcase
                                        if (req.addr[1] == 1) begin
                                            breq.writeen = 4'b1100;
                                            breq.datain = val << 16;
                                        end else begin
                                            breq.writeen = 4'b0011;
                                            breq.datain = zeroExtend(val[15:0]);
                                        end
                                    end
                                    tagged Byte: begin
                                        Bit#(32) valB = zeroExtend(val[7:0]);
                                        $display("%x: DMEM WRITE REQ, byte  [%x] <- %x", req.pc, req.addr, valB);
                                        case (req.addr[1:0]) matches
                                            2'b11: begin
                                                breq.writeen = 4'b0001;
                                                breq.datain = valB;
                                            end
                                            2'b10: begin
                                                breq.writeen = 4'b0010;
                                                breq.datain = valB << 8;
                                            end
                                            2'b01: begin
                                                breq.writeen = 4'b0100;
                                                breq.datain = valB << 16;
                                            end
                                            2'b00: begin
                                                breq.writeen = 4'b1000;
                                                breq.datain = valB << 24;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                            tagged Invalid: begin
                                if (req.width matches tagged Word) begin
                                    $display("%x: DMEM READ  REQ,  word [%x] ->", req.pc, req.addr);
                                end else begin
                                    $display("%x: DMEM READ  REQ, other [%x] ->", req.pc, req.addr);
                                    $finish(1);
                                end
                            end
                        endcase
                    end
                    if (req.addr < 1024) begin
                        bram.portB.request.put(breq);
                    end else begin
                        delayFIFO.enq(breq);
                    end
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Word) get();
                    waitQ.deq();
                    let req = waitQ.first;
                    Bit#(n) addr = req.addr[nwords+1:2];
                    Word res <- bram.portB.response.get();
                    if (!req.spurious) begin
                        if (req.data matches Invalid) begin
                            $display("%x: DMEM READ  RES,  word [%x] -> %x", req.pc, req.addr, res);
                        end
                    end
                    return res;
                endmethod
            endinterface
        endinterface
    endinterface
endmodule

endpackage
