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
    interface Get #(ComputeToMemory) memory;
    interface ComputedPC pc;
endinterface

module mkCPUCompute #( RegisterRead rs1
                     , RegisterRead rs2
                     , StatusWordRead rsw
                     , RegisterWriteCompute rwr
                     ) (CPU_Compute);

    FIFO#(FetchToCompute) q <- mkPipelineFIFO;
    FIFO#(ComputeToMemory) out <- mkBypassFIFO;
    Reg#(Word) computedPC <- mkWire;

    let busyProbe <- mkProbe;
    let instrProbe <- mkProbe;
    let pcProbe <- mkProbe;
    let eaProbe <- mkProbe;
    ALU_IFC alu1 <- mkALU;
    //ALU_IFC alu2 <- mkALU;

    rule execute;
        busyProbe <= True;

        q.deq;
        let instr = q.first.instr;
        let instrPC = q.first.pc;
        let runAlu = q.first.runAlu;
        let destination = q.first.rd;
        instrProbe <= instr;
        pcProbe <= instrPC;
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
        Maybe#(Tuple2#(Register, Word)) mrd = tagged Invalid;
        Maybe#(StatusWord) msw = tagged Invalid;


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
                        $display("eval cond code: ", rr.condition, ", sw: ", fshow(sw), ", res: ", aluOp.condition);
                    end
                endcase

                flags = rr.flags;
            end
            tagged RM .rm: begin
                Word added = (rs1v + signExtend(rm.constant))[31:0];
                Word ea = rm.p ? added : rs1v;
                if (rm.q) begin
                    mrd = tagged Valid tuple2(q.first.rs1, added);
                end
                out.enq(ComputeToMemory { ea: ea
                                        , store: rm.store
                                        , value: rs2v
                                        , rd: destination });
            end
        endcase

        if (runAlu) begin
            let aluRes <- alu1.run(aluOp);
            if (destination == PC) begin
                computedPC <= aluRes.result;
            end else begin
                mrd = tagged Valid tuple2(destination, aluRes.result);
            end
            if (flags) begin
                msw = tagged Valid aluRes.sw;
            end

        end
        rwr.write(msw, mrd);
    endrule

    (* preempts = "execute, noExecute" *)
    rule noExecute;
        busyProbe <= False;
    endrule

    interface Put fetch;
        method put = q.enq;
    endinterface

    interface Get memory;
        method ActionValue#(ComputeToMemory) get();
            out.deq;
            let o = out.first;
            eaProbe <= o.ea;
            return o;
        endmethod
    endinterface

    interface ComputedPC pc;
        method Word get;
            return computedPC;
        endmethod
    endinterface
endmodule

endpackage
