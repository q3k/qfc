package Sky130SRAM;

import FIFO :: *;
import SpecialFIFOs :: *;
import GetPut :: *;
import ClientServer :: *;
import Lanai_Memory :: *;
import Lanai_IFC :: *;

interface Sky130SRAMCore;
    method Action request0(Bit#(9) addr0, Bit#(32) din0, Bool web0, Bit#(4) wmask0);
    method Bit#(32) response0;

    method Action request1(Bit#(9) addr1);
    method Bit#(32) response1;
endinterface

import "BVI" sky130_sram_2kbyte_1rw1r_32x512_8_wrapper =
module mkSky130SRAMCore#(Clock clk0, Reset rst0, Clock rclk1, Reset rst1)(Sky130SRAMCore);
        default_clock no_clock;
        default_reset no_reset;

        input_clock clk0(clk0, (*unused*)clk0_gate) = clk0;
        input_reset rsb0() = rst0;
        input_reset rsb1() = rst1;
        method request0(addr0, din0, web0, wmask0) clocked_by (clk0) enable (cs0);
        method dout0 response0 clocked_by (clk0);

        schedule (response0) SB (request0);

        input_clock clk1(clk1, (*unused*)clk1_gate) = clk0;
        method request1(addr1) clocked_by (clk1) enable (cs1);
        method dout1 response1 clocked_by (clk1);

        schedule (response1) SB (request1);
    endmodule

interface Sky130SRAM;
    interface Server#(DMemReq, Word) portA;
    interface Server#(Word, Word) portB;
endinterface

module mkSky130SRAM(Sky130SRAM);
    Clock clk <- exposeCurrentClock;
    Reset rst <- exposeCurrentReset;
    let core <- mkSky130SRAMCore(clk, rst, clk, rst);

    FIFO#(void) inFlight0 <- mkPipelineFIFO;
    FIFO#(void) inFlight1 <- mkPipelineFIFO;

    interface Server portA;
        interface Put request;
            method Action put(DMemReq req);
                inFlight0.enq(?);

                Bit#(4) wmask = 0;
                Bit#(32) din = 0;
                Bool web = False;
                if (req.data matches tagged Valid .val) begin
                    web = True;
                    case (req.width) matches
                        tagged Word: begin
                            //$display("%x: DMEM WRITE REQ,  word [%x] <-  %x", req.pc, req.addr, val);
                            wmask = 4'b1111;
                            din = val;
                        end
                        tagged HalfWord: begin
                            Bit#(32) valH = zeroExtend(val[15:0]);
                            //$display("%x: DMEM WRITE REQ, hword [%x] <- %x", req.pc, req.addr, valH);
                            case (req.addr[1]) matches
                                1'b1: begin
                                    wmask = 4'b0011;
                                    din = valH;
                                end
                                1'b0: begin
                                    wmask = 4'b1100;
                                    din = valH << 16;
                                end
                            endcase
                            if (req.addr[1] == 1) begin
                                wmask = 4'b1100;
                                din = val << 16;
                            end else begin
                                wmask = 4'b0011;
                                din = zeroExtend(val[15:0]);
                            end
                        end
                        tagged Byte: begin
                            Bit#(32) valB = zeroExtend(val[7:0]);
                            //$display("%x: DMEM WRITE REQ, byte  [%x] <- %x", req.pc, req.addr, valB);
                            case (req.addr[1:0]) matches
                                2'b11: begin
                                    wmask = 4'b0001;
                                    din = valB;
                                end
                                2'b10: begin
                                    wmask = 4'b0010;
                                    din = valB << 8;
                                end
                                2'b01: begin
                                    wmask = 4'b0100;
                                    din = valB << 16;
                                end
                                2'b00: begin
                                    wmask = 4'b1000;
                                    din = valB << 24;
                                end
                            endcase
                        end
                    endcase
                end

                core.request0(req.addr[8:0], din, !web, wmask);
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(Bit#(32)) get();
                inFlight0.deq;

                let res = core.response0;
                return res;
            endmethod
        endinterface
    endinterface
    interface Server portB;
        interface Put request;
            method Action put(Bit#(32) address);
                inFlight1.enq(?);
                core.request1(address[8:0]);
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(Bit#(32)) get();
                inFlight1.deq;

                let res = core.response1;
                return res;
            endmethod
        endinterface
    endinterface
endmodule

endpackage
