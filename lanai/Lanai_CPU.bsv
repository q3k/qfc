package Lanai_CPU;

import GetPut :: *;
import Connectable :: *;

import Lanai_IFC :: *;
import CPU_Defs :: *;
import CPU_RegisterFile :: *;
import CPU_Fetch :: *;
import CPU_Compute :: *;
import CPU_Memory :: *;

(* synthesize *)
module mkLanaiCPU (Lanai_IFC);
    CPU_RegisterFile rf <- mkCPURegisterFile;
    CPU_Fetch fetch <- mkCPUFetch( rf.fetchRead
                                );
    CPU_Compute compute <- mkCPUCompute( rf.computeSource1
                                      , rf.computeSource2
                                      , rf.computeStatusSource
                                      , rf.computeWrite
                                      , fetch.mispredictCompute
                                      );
    CPU_Memory memory <- mkCPUMemory( rf.memoryWrite
                                   , compute.memoryBypass
                                   , fetch.mispredictMemory
                                   );
    //, compute.pc
    //, memory.pc
    //);

    mkConnection(fetch.compute, compute.fetch);
    mkConnection(compute.memory, memory.compute);

    method Word readPC;
        return rf.debug.read(R7);
    endmethod
    interface imem_client = fetch.imem;
    interface dmem_client = memory.dmem;
endmodule

endpackage
