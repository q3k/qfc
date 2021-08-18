package CPU_Compute;

import GetPut :: *;
import DReg :: *;
import FIFO :: *;
import Probe :: *;
import SpecialFIFOs :: *;

import CPU_Defs :: *;
import CPU_ALU :: *;

interface CPU_Compute;
    interface Put #(FetchToCompute) fetch;
    interface ComputedPC pc;
endinterface

module mkCPUCompute #( RegisterRead rs1
                     , RegisterRead rs2
                     , StatusWordRead rsw
                     , RegisterWriteCompute rwr
                     ) (CPU_Compute);

    FIFO#(FetchToCompute) q <- mkPipelineFIFO;
    Reg#(Word) computedPC <- mkWire;
    let probe <- mkProbe;
    ALU_IFC alu1 <- mkALU;
    //ALU_IFC alu2 <- mkALU;

    rule execute;
        q.deq;
        let instr = q.first.instr;
        let instrPC = q.first.pc;
        let runAlu = q.first.runAlu;
        let destination = q.first.rd;
        probe <= instr;
        StatusWord sw = rsw.read;

        // Optimization: always read source1/source2 regs, as they use the same opcode positions.
        let rs1v = (q.first.rs1 == PC) ? instrPC : rs1.read(q.first.rs1);
        let rs2v = (q.first.rs2 == PC) ? instrPC : rs2.read(q.first.rs2);

        // Optimization: always build arithmetic op.
        let aluOp = AluOperation { a: rs1v
                                 , b: 0
                                 , shiftArithmetic: False
                                 , addCarry: sw.carry
                                 , kind: q.first.aluOpKind
                                 , condition: False
                                 };

        Bool flags = False;
        case (instr) matches
            tagged RI .ri: begin
                let shift = ri.high ? 16 : 0;
                let czshift = zeroExtend(ri.constant) << shift;
                let coshift = ri.high ? { ri.constant, 16'hFFFF } : { 16'hFFFF, ri.constant };
                aluOp.b = czshift;
                aluOp.shiftArithmetic = ri.high;

                case (ri.operation) matches
                    Add: begin
                        aluOp.addCarry = False;
                    end
                    Sub: begin
                        aluOp.addCarry = True;
                    end
                    And: begin
                        aluOp.b = coshift;
                    end
                    Shift: begin
                        aluOp.b = signExtend(ri.constant);
                    end
                endcase

                flags = ri.flags;
            end
            tagged RR .rr: begin
                aluOp.b = rs2v;
                case (rr.operation) matches
                    Add: begin
                        aluOp.addCarry = False;
                    end
                    Sub: begin
                        aluOp.addCarry = True;
                    end
                    AShift: begin
                        aluOp.shiftArithmetic = True;
                    end
                    Select: begin
                        aluOp.condition = evaluateCondition(rr.condition, sw);
                    end
                endcase

                flags = rr.flags;
            end
        endcase

        if (runAlu) begin
            Maybe#(StatusWord) msw = tagged Invalid;
            Maybe#(Tuple2#(Register, Word)) mrd = tagged Invalid;

            let aluRes <- alu1.run(aluOp);
            if (destination == PC) begin
                computedPC <= aluRes.result;
            end else begin
                mrd = tagged Valid tuple2(destination, aluRes.result);
            end
            if (flags) begin
                msw = tagged Valid aluRes.sw;
            end

            rwr.write(msw, mrd);
        end
    endrule

    interface Put fetch;
        method put = q.enq;
    endinterface

    interface ComputedPC pc;
        method Word get;
            return computedPC;
        endmethod
    endinterface
endmodule

endpackage
