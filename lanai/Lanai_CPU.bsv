package Lanai_CPU;

import GetPut :: *;
import Connectable :: *;

import Lanai_IFC :: *;
import CPU_Defs :: *;
import CPU_RegisterFile :: *;
import CPU_Fetch :: *;
import CPU_Compute :: *;

interface CPU_Memory;
endinterface

(* synthesize *)
module mkLanaiCPU (Lanai_IFC);
    CPU_RegisterFile rf <- mkCPURegisterFile;
    CPU_Compute compute <- mkCPUCompute( rf.computeSource1
                                      , rf.computeSource2
                                      , rf.computeStatusSource
                                      , rf.computeWrite
                                      );
    CPU_Fetch fetch <- mkCPUFetch( rf.fetchRead
                                , compute.pc
                                );

    mkConnection(fetch.compute, compute.fetch);

    method Word readPC;
        return rf.debug.read(R7);
    endmethod
    interface imem_client = fetch.imem;
endmodule

endpackage
