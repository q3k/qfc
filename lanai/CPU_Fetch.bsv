// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2022 Sergiusz Bazanski

package CPU_Fetch;

import ClientServer :: *;
import ConfigReg :: *;
import GetPut :: *;
import FIFO :: *;
import FIFOF :: *;
import Probe :: *;
import SpecialFIFOs :: *;

import Lanai_IFC :: *;
import CPU_Defs :: *;

interface CPU_Fetch;
    interface Get #(FetchToCompute) compute;
    interface Client #(Word, Word) imem;

    interface MispredictReport mispredictCompute;
    interface MispredictReport mispredictMemory;
endinterface

module mkCPUFetch #( RegisterRead pcRead
                   ) (CPU_Fetch);

    Reg#(Word) cPredictCount <- mkConfigReg(0);
    Reg#(Word) cMispredictOkCount <- mkConfigReg(0);
    Reg#(Word) cMispredictLagCount <- mkConfigReg(0);
    Reg#(Word) cMispredictErrorCount <- mkConfigReg(0);

    let pcProbe <- mkProbe;
    let wantProbe <- mkProbe;
    let fetchProbe <- mkProbe;
    let putProbe <- mkProbe;
    let getProbe <- mkProbe;
    let mispredictErrorProbe <- mkProbe;

    FIFOF#(FetchToCompute) out <- mkBypassFIFOF;
    Reg#(Word) cycle <- mkReg(0);
    Reg#(Word) wantPC <- mkReg(0);
    Reg#(Word) fetchPC <- mkWire;

    FIFOF#(Misprediction) mispredictComputeF <- mkBypassFIFOF;
    FIFOF#(Misprediction) mispredictMemoryF <- mkBypassFIFOF;

    FIFO#(Word) pcRequested <- mkPipelineFIFO;
    FIFOF#(Tuple2#(Word, Word)) fetched <- mkBypassFIFOF;

    rule upCycle;
        cycle <= cycle + 1;
    endrule

    rule kickstart (cycle == 0);
        fetchPC <= 0;
    endrule

    rule wantProbeUpdate;
        wantProbe <= wantPC;
    endrule

    rule fetchProbeUpdate;
        fetchProbe <= fetchPC;
    endrule

    rule mispredictProbeUpdate;
        mispredictErrorProbe <= cMispredictErrorCount;
    endrule

    interface Get compute;
        method ActionValue#(FetchToCompute) get() if (cycle != 0);
            fetched.deq;
            match { .pc, .data } = fetched.first; 
            //$display("%d: trySchedule %x", cycle, pc);

            Maybe#(Misprediction) override = tagged Invalid;
            if (mispredictComputeF.notEmpty) begin
                mispredictComputeF.deq;
                override = tagged Valid mispredictComputeF.first;
            end
            if (mispredictMemoryF.notEmpty) begin
                mispredictMemoryF.deq;
                override = tagged Valid mispredictMemoryF.first;
            end

            let sched = True;
            let nextPC = pc + 4;
            if (override matches tagged Valid .mispredict) begin
                $display("%d: mispredict:", cycle, fshow(mispredict));

                if (mispredict.pc != wantPC) begin
                    if (mispredict.opc == pc+4) begin
                        cMispredictOkCount <= cMispredictOkCount + 1;
                        $display("%d: pc miss, %x -> %x", cycle, pc, mispredict.pc);
                    end else if (mispredict.opc == pc) begin
                        cMispredictLagCount <= cMispredictLagCount + 1;
                        $display("%d: pc Miss, %x -> %x", cycle, pc, mispredict.pc);
                        sched = False;
                    end else if (mispredict.opc == pc-4) begin
                        cMispredictLagCount <= cMispredictLagCount + 1;
                        $display("%d: pc Miss, %x -> %x", cycle, pc, mispredict.pc);
                        sched = False;
                    end else begin
                        cMispredictErrorCount <= cMispredictErrorCount + 1;
                        $display("%d: pc MISS, %x -> %x", cycle, pc, mispredict.pc);
                        sched = False;
                    end
                    nextPC = mispredict.pc;
                end
            end
            wantPC <= nextPC;
            fetchPC <= nextPC;

            if (nextPC == pc + 4) begin
                cPredictCount <= cPredictCount + 1;
                //$display("%d: pc okay, %x", cycle, pc);
            end

            Instruction instr = tagged RI InstRI   { operation: unpack(0)
                                                , flags: unpack(0)
                                                , high: unpack(0)
                                                , destination: unpack(0)
                                                , source: unpack(0)
                                                , constant: unpack(0)
                                                };
            if (sched) begin
                Instruction instr2 = unpack(data);
                if (instr2 matches tagged Unknown .x) begin
                    //$display("Invalid instruction: ", x);
                end else begin
                    instr = instr2;
                end
                Bool runAlu = case(instr) matches
                    tagged RI .ri: True;
                    tagged RR .rr: True;
                    default: False;
                endcase;
                Register rs2 = case(instr) matches
                    tagged RM .rm: unpack(data[27:23]);
                    default: unpack(data[15:11]);
                endcase;

                pcProbe <= pc;
                return FetchToCompute { instr: instr
                                       , pc: pc
                                       , rs1: unpack(data[22:18])
                                       , rs2: rs2
                                       , rd: unpack(data[27:23])
                                       , runAlu: runAlu
                                       , aluOpKind: insAluOpKind(instr)
                                       };
            end else begin
                return FetchToCompute { instr: instr, pc: 0, rs1: R0, rs2: R0, rd: R0, runAlu: False, aluOpKind: tagged Add };
            end
        endmethod
    endinterface

    interface Client imem;
        interface Get request;
            method ActionValue#(Word) get if (fetchPC < sysmemSplit);
                let pc = fetchPC;
                //$display("%d get         pc: %x", cycle, pc);
                pcRequested.enq(pc);
                getProbe <= pc;
                return pc;
            endmethod
        endinterface
        interface Put response;
            method Action put(Word data) if (pcRequested.first < sysmemSplit);
                pcRequested.deq;
                let pc = pcRequested.first;
                putProbe <= pc;
                //$display("%d put         pc: %x, data: %x", cycle, pc, data);
                fetched.enq(tuple2(pc, data));
            endmethod
        endinterface
    endinterface

    interface MispredictReport mispredictCompute = toPut(mispredictComputeF);
    interface MispredictReport mispredictMemory = toPut(mispredictMemoryF);
endmodule

endpackage
