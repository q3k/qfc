// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2022 Sergiusz Bazanski

package SPIFlashEmulator;

import BRAM :: *;
import FIFO :: *;
import SpecialFIFOs :: *;
import StmtFSM :: *;

interface SPIFlashEmulator;
    (* always_enabled, always_ready *)
    method Action mosi(Bool value);
    (* always_enabled *)
    method Bool miso;
    (* always_enabled, always_ready *)
    method Action sclk(Bool value);
    (* always_enabled, always_ready *)
    method Action csb(Bool value);
endinterface

module mkSPIFlashEmulator#(String filename) (SPIFlashEmulator);
    BRAM_Configure cfg = defaultValue;
    cfg.latency = 1;
    cfg.loadFormat = tagged Hex filename;
    cfg.outFIFODepth = 3;
    cfg.allowWriteResponseBypass = False;
    BRAM1Port#(Bit#(12), Bit#(32)) bram <- mkBRAM1Server(cfg);

    Reg#(Bool) csbReg <- mkReg(False);
    Reg#(Bool) sclkReg <- mkReg(False);
    Reg#(Bool) mosiReg <- mkReg(False);

    Reg#(Bit#(8)) incomingByte <- mkReg(0);
    Reg#(Maybe#(Bit#(3))) bitNo <- mkReg(tagged Invalid);

    rule startReceive(bitNo matches tagged Invalid &&& csbReg == False);
        bitNo <= tagged Valid 0;
    endrule

    Reg#(Bool) prevSclk <- mkReg(False);
    rule updatePrevSclk;
        prevSclk <= sclkReg;
    endrule

    FIFO#(Maybe#(Bit#(8))) pendingByte <- mkPipelineFIFO;

    Bool clockRisen = prevSclk == False && sclkReg == True;

    rule onClockRisen(bitNo matches tagged Valid .bn &&& csbReg == False &&& clockRisen);
        let val = incomingByte;
        val[7-bn] = pack(mosiReg);

        if (bn == 7) begin
            pendingByte.enq(tagged Valid val);
            bitNo <= tagged Invalid;
        end else begin
            incomingByte <= val;
            bitNo <= tagged Valid (bn + 1);
        end
    endrule

    rule onCSBHigh(bitNo matches tagged Valid .bn &&& csbReg == True);
        pendingByte.enq(tagged Invalid);
        bitNo <= tagged Invalid;
    endrule

    Reg#(Bit#(8)) command <- mkReg(0);
    Reg#(Bool) failed <- mkReg(False);
    Reg#(Bit#(24)) readAddr <- mkReg(0);
    Reg#(Bit#(24)) readAddrWait <- mkReg(0);
    Reg#(Bit#(32)) bramBuf <- mkReg(0);
    Reg#(Bit#(24)) bramAddr <- mkReg('h1);
    Reg#(Bit#(8)) sending <- mkReg(0);
    Stmt fsm = seq
        while (True) seq
            failed <= False;
            action
                pendingByte.deq();
                case (pendingByte.first) matches
                    tagged Valid .v: command <= v;
                    tagged Invalid: failed <= True;
                endcase
            endaction

            if (failed) continue;

            $display("Flash emulator: recv %x", command);
            if (command == 3) seq
                action
                    pendingByte.deq();
                    case (pendingByte.first) matches
                        tagged Valid .v: readAddr[23:16] <= v;
                        tagged Invalid: failed <= True;
                    endcase
                endaction
                if (failed) continue;
                action
                    pendingByte.deq();
                    case (pendingByte.first) matches
                        tagged Valid .v: readAddr[15:8] <= v;
                        tagged Invalid: failed <= True;
                    endcase
                endaction
                if (failed) continue;
                action
                    pendingByte.deq();
                    case (pendingByte.first) matches
                        tagged Valid .v: readAddr[7:0] <= v;
                        tagged Invalid: failed <= True;
                    endcase
                endaction
                if (failed) continue;
                
                par
                    while (!failed) seq
                        while (readAddr[1:0] != 0 && failed == False) seq
                            noAction;
                        endseq
                        readAddrWait <= readAddr;
                        bram.portA.request.put(BRAMRequest { responseOnWrite: True
                                                           , address: readAddrWait[13:2]
                                                           , datain: 0
                                                           , write: False
                                                           });
                        action
                            let bramRes <- bram.portA.response.get();
                            action
                                bramBuf <= bramRes;
                                bramAddr <= readAddrWait;
                            endaction
                        endaction
                    endseq

                    seq
                        while (bramAddr != readAddr) seq
                            noAction;
                        endseq
                        action
                            let byteInBuf = (7 - (readAddr & 'b111)) << 3;
                            sending <= bramBuf[byteInBuf+7:byteInBuf];
                        endaction
                        $display("Flash emulator: read addr: %x", readAddr);
                        while (!failed) seq
                            action
                                case (pendingByte.first) matches
                                    tagged Invalid: failed <= True;
                                endcase
                                pendingByte.deq();
                            endaction
                            seq
                                readAddr <= readAddr + 1;
                                while (bramAddr != (readAddr & (~'b11))) seq
                                    noAction;
                                endseq
                                action
                                    let byteInBuf = (7 - (readAddr & 'b111)) << 3;
                                    sending <= bramBuf[byteInBuf+7:byteInBuf];
                                endaction
                            endseq
                        endseq
                        $display("Flash emulator: read done");
                    endseq
                endpar

            endseq else seq
                $display("Flash emulator: unhandled command %x", command);
            endseq
        endseq
    endseq;

    mkAutoFSM(fsm);

    method Action mosi(Bool value);
        mosiReg <= value;
    endmethod
    method Action sclk(Bool value);
        sclkReg <= value;
    endmethod
    method Action csb(Bool value);
        csbReg <= value;
    endmethod
    method Bool miso;
        return case (bitNo) matches
            tagged Valid .bn: unpack(sending[7-bn]);
            tagged Invalid: False;
        endcase;
    endmethod
endmodule

endpackage
