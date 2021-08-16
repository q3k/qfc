package CPU_RegisterFile;

import ConfigReg :: *;
import Vector :: *;

import CPU_Defs :: *;

interface CPU_RegisterFile;
    interface RegisterRead debug;

    interface RegisterRead fetchRead;

    interface RegisterRead computeSource1;
    interface RegisterRead computeSource2;
    interface StatusWordRead computeStatusSource;
    interface RegisterWriteCompute computeWrite;
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
module mkCPURegisterFile(CPU_RegisterFile);
    function m#(Reg#(Word)) makeRegs(Integer ix) provisos (IsModule#(m, c));
        return case (ix) matches
            0: mkConstantReg(32'h00000000);
            1: mkConstantReg(32'hFFFFFFFF);
            2: mkConstantReg(32'hDEADBEEF);
            default: mkConfigReg(0);
        endcase;
    endfunction
    Vector#(32, Reg#(Word)) regs <- genWithM(makeRegs);


    function RegisterRead makeRead();
        return (interface RegisterRead;
            method Word read(Register ix);
                return regs[pack(ix)];
            endmethod
        endinterface);
    endfunction

    function RegisterWrite makeWrite();
        return (interface RegisterWrite;
            method Action write(Register ix, Word data);
                regs[pack(ix)] <= data;
            endmethod
        endinterface);
    endfunction

    interface RegisterRead debug = makeRead;
    interface RegisterRead fetchRead = makeRead;
    interface RegisterRead computeSource1 = makeRead;
    interface RegisterRead computeSource2 = makeRead;
    interface StatusWordRead computeStatusSource;
        method StatusWord read = unpack(regs[pack(PS)]);
    endinterface

    interface RegisterWriteCompute computeWrite;
        method Action write( Maybe#(StatusWord) sw
                           , Maybe#(Tuple2#(Register, Word)) rd
                           );
            Bool wroteStatus = False;
            case (sw) matches
                tagged Valid .swd: begin
                    regs[pack(PS)] <= pack(swd);
                    wroteStatus = True;
                end
            endcase
            case (rd) matches
                tagged Valid .rdd: begin
                    let ix = tpl_1(rdd);
                    let data = tpl_2(rdd);
                    if ((ix != PS) || !wroteStatus) begin
                        regs[pack(ix)] <= data;
                    end
                end
            endcase
        endmethod
    endinterface
endmodule


endpackage
