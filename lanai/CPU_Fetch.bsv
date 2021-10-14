package CPU_Fetch;

import ClientServer :: *;
import ConfigReg :: *;
import GetPut :: *;
import FIFO :: *;
import Probe :: *;
import SpecialFIFOs :: *;

import Lanai_IFC :: *;
import CPU_Defs :: *;

interface CPU_Fetch;
    interface Get #(FetchToCompute) compute;
    interface Client #(Word, Word) imem;
endinterface

module mkCPUFetch #( RegisterRead pcRead
                   , ComputedPC pcFromCompute
                   ) (CPU_Fetch);

    FIFO#(FetchToCompute) out <- mkBypassFIFO;
    Reg#(Word) fetched <- mkConfigReg(0);
    Reg#(Word) pc <- mkReg(0);
    FIFO#(Word) waitRead <- mkPipelineFIFO;

    PulseWire busyPredict <- mkPulseWire;
    PulseWire busyCorrectCompute <- mkPulseWire;
    PulseWire busyComputeGet <- mkPulseWire;

    let instructionProbe <- mkProbe;
    let pcProbe <- mkProbe;
    let busyPredictProbe <- mkProbe;
    let busyCorrectComputeProbe <- mkProbe;
    let busyComputeGetProbe <- mkProbe;

    rule updateProbes;
        busyPredictProbe <= busyPredict;
        busyCorrectComputeProbe <= busyCorrectCompute;
        busyComputeGetProbe <= busyComputeGet;
    endrule

    Reg#(Word) nextPC <- mkWire;
    Reg#(Word) fetchPC <- mkWire;
    rule updatePCPredict;
        busyPredict.send();
        nextPC <= pc + 4;
        fetchPC <= pc;
    endrule

    (* preempts = "updatePCCompute, updatePCPredict" *)
    rule updatePCCompute;
        busyCorrectCompute.send();
        let val = pcFromCompute.get;
        if (fetched != val) begin
            nextPC <= val + 4;
            fetchPC <= val;
            $display("updatePCCompute (miss)", val, pc);
        end else begin
            nextPC <= pc + 4;
            fetchPC <= pc;
            $display("updatePCCompute  (ok)", pc);
        end
    endrule

    interface Client imem;
        interface Get request;
            method ActionValue#(Word) get;
                pc <= nextPC;
                fetched <= fetchPC;
                waitRead.enq(fetchPC);
                return fetchPC;
            endmethod
        endinterface
        interface Put response;
            method Action put(Word data);
                waitRead.deq;
                let pc = waitRead.first;

                Instruction instr = unpack(data);
                Bool runAlu = case(instr) matches
                    tagged RI .ri: True;
                    tagged RR .rr: True;
                    default: False;
                endcase;
                Register rs2 = case(instr) matches
                    tagged RM .rm: unpack(data[27:23]);
                    default: unpack(data[15:11]);
                endcase;
                out.enq(FetchToCompute { instr: instr
                                       , pc: pc
                                       , rs1: unpack(data[22:18])
                                       , rs2: rs2
                                       , rd: unpack(data[27:23])
                                       , runAlu: runAlu
                                       , aluOpKind: insAluOpKind(instr)
                                       });
            endmethod
        endinterface
    endinterface

    interface Get compute;
        method ActionValue#(FetchToCompute) get();
            busyComputeGet.send();
            out.deq;
            let o = out.first;

            instructionProbe <= o.instr;
            pcProbe <= o.pc;
            return o;
        endmethod
    endinterface
endmodule

endpackage
