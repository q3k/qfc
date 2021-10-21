package Tb;

import Connectable :: *;

import Lanai_IFC :: *;
import Lanai_CPU :: *;
import Lanai_Memory :: *;

(* synthesize *)
module mkTb (Empty);
    Lanai_BlockRAM#(4096) bram <- mkBlockMemory("lanai/bram.bin");
    Lanai_IFC cpu <- mkLanaiCPU;

    mkConnection(cpu.imem_client, bram.memory.imem);
    mkConnection(cpu.dmem_client, bram.memory.dmem);

    Reg#(int) i <- mkReg(0);
    rule testFetch;
        if (i > 5000) begin
            //bram.dump;
            $finish(0);
        end
        i <= i + 1;
        //$display("counter:", cpu.readPC);
    endrule
endmodule

endpackage
