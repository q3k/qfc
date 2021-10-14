package CPU_Compute;

import GetPut :: *;
import DReg :: *;
import FIFO :: *;
import FIFOF :: *;
import Probe :: *;
import SpecialFIFOs :: *;

import CPU_Defs :: *;
import CPU_ALU :: *;

interface CPU_Compute;
    interface Put #(FetchToCompute) fetch;
    interface Get #(ComputeToMemory) memory;
    interface ComputedPC pc;
    interface RegisterWriteBypass memoryBypass;
endinterface

function Word resolveRegister(Register ix, Word pc, Maybe#(Tuple2#(Register, Word)) bypass, RegisterRead rs);
    Maybe#(Word) fromPC = tagged Invalid;
    Maybe#(Word) fromBypass = tagged Invalid;

    if (ix == PC) begin
        fromPC = tagged Valid pc;
    end
    if (bypass matches tagged Valid { .bix, .bval }) begin
        if (ix == bix) begin
            fromBypass = tagged Valid bval;
        end
    end

    return case (tuple2(fromBypass, fromPC)) matches
        { tagged Valid .bval, .* }: bval;
        { tagged Invalid, tagged Valid .pval }: pval;
        { tagged Invalid, tagged Invalid }: rs.read(ix);
    endcase;
endfunction


module mkCPUCompute #( RegisterRead rs1
                     , RegisterRead rs2
                     , StatusWordRead rsw
                     , RegisterWriteCompute rwr
                     ) (CPU_Compute);

    FIFOF#(FetchToCompute) q <- mkPipelineFIFOF;
    Reg#(Word) computedPC <- mkWire;
    RWire#(Tuple2#(Register, Word)) regFromMemory <- mkRWire;

    let busy <- mkPulseWire;
    let busyPut <- mkPulseWire;

    let busyProbe <- mkProbe;
    let busyPutProbe <- mkProbe;
    let fullQ <- mkProbe;
    let instrProbe <- mkProbe;
    let pcProbe <- mkProbe;
    ALU_IFC alu1 <- mkALU;

    rule updateBusy;
        busyProbe <= busy;
    endrule
    rule updateBusyPut;
        busyPutProbe <= busyPut;
    endrule
    rule updateFullQ;
        fullQ <= !q.notFull;
    endrule

    interface Get memory;
        method ActionValue#(ComputeToMemory) get();
            let res = ComputeToMemory { ea: 0, op: tagged Noop };
            busy.send();

            q.deq;
            let instr = q.first.instr;
            let instrPC = q.first.pc;
            let runAlu = q.first.runAlu;
            let destination = q.first.rd;
            instrProbe <= instr;
            pcProbe <= instrPC;
            StatusWord sw = rsw.read;

            // Optimization: always read source1/source2 regs, as they use the same opcode positions.
            let rs1v = resolveRegister(q.first.rs1, instrPC, regFromMemory.wget(), rs1);
            let rs2v = resolveRegister(q.first.rs2, instrPC, regFromMemory.wget(), rs2);

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
                    res.ea = ea;
                    res.op = (rm.store ? tagged Store rs2v : tagged Load destination);
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
            return res;
        endmethod
    endinterface

    interface Put fetch;
        method Action put(FetchToCompute v);
            busyPut.send();
            q.enq(v);
        endmethod
    endinterface

    interface ComputedPC pc;
        method Word get;
            return computedPC;
        endmethod
    endinterface

    interface RegisterWriteBypass memoryBypass;
        method Action strobe(Register ix, Word value);
            regFromMemory.wset(tuple2(ix, value));
        endmethod
    endinterface
endmodule

endpackage
