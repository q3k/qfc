// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2022 Sergiusz Bazanski

package CPU_RegisterFile;

import ConfigReg :: *;
import Vector :: *;

import CPU_Defs :: *;

interface CPU_RegisterFile;
    interface RegisterRead fetchRead;

    interface RegisterRead computeSource1;
    interface RegisterRead computeSource2;
    interface StatusWordRead computeStatusSource;
    interface RegisterWriteCompute computeWrite;
    interface RegisterWriteMemory memoryWrite;
endinterface

module mkConstantReg #(Word val)
                      (Reg#(Word));
     method Word _read;
         return val;
     endmethod
     method Action _write(Word w);
     endmethod
endmodule

(* synthesize *)
module mkRFReg(Reg#(Word));
    let res <- mkConfigReg(0);
    return res;
endmodule

typedef Wire#(Tuple2#(Register, Word)) WriteReq;

(* synthesize *)
module mkCPURegisterFile(CPU_RegisterFile);
    function m#(Reg#(Word)) makeRegs(Integer ix) provisos (IsModule#(m, c));
        return case (ix) matches
            0: mkConstantReg(32'h00000000);
            1: mkConstantReg(32'hFFFFFFFF);
            2: mkConstantReg(32'hDEADBEEF);
            4: mkConfigReg(32'h20002000);
            default: mkRFReg;
        endcase;
    endfunction
    Vector#(32, Reg#(Word)) regs <- genWithM(makeRegs);
    Reg#(Word) status <- mkReg(0);

    WriteReq writeReqCompute <- mkWire;
    WriteReq writeReqMemory <- mkWire;

    Vector #(2, WriteReq) writeReqs;
    writeReqs[0] = writeReqCompute;
    writeReqs[1] = writeReqMemory;


    Vector #(29, Register) writableRegisters;
    for (Integer i = 0; i < 29; i = i + 1) begin
        Bit#(32) no = fromInteger(i + 3);
        writableRegisters[i] = unpack(no[4:0]);
    end

    function Rules genRegRules(Register regno);
        function Rules genRegRule(WriteReq wr);
            return (rules
               rule foo if (tpl_1(wr) == regno);
                   regs[pack(regno)] <= tpl_2(wr);
               endrule
            endrules);
        endfunction
        return foldl1(rJoinPreempts, map(genRegRule, writeReqs));
    endfunction
    addRules(joinRules(map(genRegRules, writableRegisters)));

    function RegisterRead makeRead();
        return (interface RegisterRead;
            method Word read(Register ix);
                return regs[pack(ix)];
            endmethod
        endinterface);
    endfunction

    interface RegisterRead fetchRead = makeRead;
    interface RegisterRead computeSource1 = makeRead;
    interface RegisterRead computeSource2 = makeRead;
    interface StatusWordRead computeStatusSource;
        method StatusWord read = unpack(status);
    endinterface

    interface RegisterWriteCompute computeWrite;
        method Action write( Maybe#(StatusWord) sw
                           , Maybe#(Tuple2#(Register, Word)) rd
                           );

            case (sw) matches
                tagged Valid .swd: begin
                    status <= pack(swd);
                end
            endcase
            case (rd) matches
                tagged Valid .rdd: begin
                    writeReqCompute <= rdd;
                end
            endcase
        endmethod
    endinterface

    interface RegisterWriteMemory memoryWrite;
        method Action write(Register rd, Word value);
            writeReqMemory <= tuple2(rd, value);
        endmethod
    endinterface
endmodule


endpackage
