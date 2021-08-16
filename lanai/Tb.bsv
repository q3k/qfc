package Tb;

import Assert :: *;
import BRAM :: *;
import GetPut :: *;
import FIFO :: *;
import ClientServer :: *;
import Connectable :: *;
import Probe :: *;
import SpecialFIFOs :: *;

import Lanai_IFC :: *;
import Lanai_CPU :: *;

interface TestMem;
    interface Server#(Word, Word) imem;
    interface Server#(DMemReq, Word) dmem;
endinterface

module mkBlockMem (TestMem);
    BRAM_Configure cfg = defaultValue;
    cfg.latency = 1;
    cfg.loadFormat = tagged Hex "lanai/bram.bin";
    cfg.outFIFODepth = 3;
    cfg.allowWriteResponseBypass = True;
    BRAM2Port#(Bit#(13), Bit#(32)) bram <- mkBRAM2Server(cfg);

    let imemReqProbe <- mkProbe;
    let imemRespProbe <- mkProbe;

    interface Server imem;
        interface Put request;
            method Action put(Word addr);
                imemReqProbe <= addr;
                bram.portA.request.put(BRAMRequest { write: False
                                                   , responseOnWrite: False
                                                   , address: addr[14:2]
                                                   , datain: 0
                                                   });
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(Word) get;
                let val <- bram.portA.response.get;
                imemRespProbe <= val;
                return val;
            endmethod
        endinterface
    endinterface
endmodule

module mkTestMem (TestMem);
    Reg#(Word) pcq <- mkWire;

    let reqProbe <- mkProbe;
    let resProbe <- mkProbe;

    interface Server imem;
        interface Put request;
            method Action put(Word pc);
                pcq <= pc;
                reqProbe <= pc;
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(Word) get();
                Word w = pcq;
                resProbe <= w;
                case (w) matches
                    /// RI
                    // 0xdead_beef+0xbeef_dead
                    // == 0x1_9d9d_9d9c
                    0:  return 32'b0_101_01000_00000_11_1011111011101111; // or r8, r0, beef0000
                    4:  return 32'b0_101_01001_00000_10_1101111010101101; // or r9, r0, 0000dead
                    8:  return 32'b0_000_01000_01000_11_1101111010101101; // add r8, r8, dead0000
                    12: return 32'b0_001_01001_01001_10_1011111011101111; // addc r9, r9, beef
                    // shift left logic and arithmetic
                    16: return 32'b0_111_01010_01000_10_1111111111111000; // srl r10, r8, 8
                    20: return 32'b0_111_01011_01000_11_1111111111111000; // sra r11, r8, 8
                    // shift right logic and arithmetic
                    24: return 32'b0_111_01010_01010_10_0000000000001000; // sll r10, r10, 8
                    28: return 32'b0_111_01011_01011_11_0000000000001000; // sla r11, r11, 8

                    32: return 32'b0_101_01000_00000_10_1011111011101111; // or r8, r0, 0000beef
                    36: return 32'b0_101_01000_01000_11_1101111010101101; // or r8, r8, dead0000
                    40: return 32'b0_101_01001_00000_10_0000000000000001; // or r9, r0, 00000001

                    /// RR
                    64: return 32'b1100_01010_01000_10_01001_000_00000_000; // add r10, r8, r9
                    68: return 32'b1100_01010_01010_10_01001_000_00000_000; // add r10, r10, r9
                    72: return 32'b1100_01010_01010_10_01010_000_00000_000; // add r10, r10, r10

                    default: return 0;
                endcase
            endmethod
        endinterface
    endinterface
endmodule

(* synthesize *)
module mkTb (Empty);
    TestMem mem <- mkBlockMem;
    Lanai_IFC cpu <- mkLanaiCPU;

    mkConnection(cpu.imem_client, mem.imem);

    Reg#(int) i <- mkReg(0);
    rule testFetch;
        if (i > 100) begin
            $finish;
        end
        i <= i + 1;
        $display("counter:", cpu.readPC);
    endrule
endmodule

endpackage
