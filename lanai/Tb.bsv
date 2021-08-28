package Tb;

import Connectable :: *;

import Lanai_IFC :: *;
import Lanai_CPU :: *;
import Lanai_Memory :: *;

(* synthesize *)
module mkTb (Empty);
    Lanai_Memory#(4096) mem <- mkBlockMemory("lanai/bram.bin");
    Lanai_IFC cpu <- mkLanaiCPU;

    mkConnection(cpu.imem_client, mem.imem);
    mkConnection(cpu.dmem_client, mem.dmem);

    Reg#(int) i <- mkReg(0);
    rule testFetch;
        if (i > 300) begin
            $finish;
        end
        i <= i + 1;
        //$display("counter:", cpu.readPC);
    endrule
endmodule

endpackage
