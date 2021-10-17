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
                     , MispredictReport mispredict
                     ) (CPU_Compute);

    FIFOF#(FetchToCompute) q <- mkPipelineFIFOF;
    RWire#(Tuple2#(Register, Word)) regFromMemory <- mkRWire;
    FIFO#(Misprediction) computedPC <- mkBypassFIFO;
    Reg#(Maybe#(Register)) memoryRegisterLoad <- mkReg(tagged Invalid);

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
            busy.send();

            let instr = q.first.instr;
            let instrPC = q.first.pc;
            let runAlu = q.first.runAlu;
            let destination = q.first.rd;
            instrProbe <= instr;
            pcProbe <= instrPC;
            StatusWord sw = rsw.read;

            let res = ComputeToMemory { ea: 0
                                      , op: tagged Noop
                                      , pc: instrPC
                                      , width: Word };

            Register rs1ix = q.first.rs1;
            Register rs2ix = q.first.rs2;
            // ... unless we're in SPLS, rs2 is rs2, otherwise it's... rd? Annoying mux.
            case (instr) matches
                tagged SLS .sls: begin
                    rs2ix = sls.destination;
                end
                tagged SPLS .spls: begin
                    rs2ix = spls.destination;
                end
            endcase

            // Lanai11 delays register reads after register loads.
            let delayRegisterLoad = False;
            if (memoryRegisterLoad matches tagged Valid .rd) begin
                if (rs1ix == destination || rs2ix == destination) begin
                    delayRegisterLoad = True;
                end
            end

            if (delayRegisterLoad) begin
                memoryRegisterLoad <= tagged Invalid;
                $display("%x: COMP: delay", instrPC);
                return res;
            end else begin
                q.deq;
                // Optimization: always read source1/source2 regs, as they use the same opcode positions.
                //$display("%x: BYPA: ", instrPC, fshow(regFromMemory.wget()));
                let rs1v = resolveRegister(rs1ix, instrPC, regFromMemory.wget(), rs1);
                let rs2v = resolveRegister(rs2ix, instrPC, regFromMemory.wget(), rs2);

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


                //$display("%x: COMP: ", instrPC, fshow(instr));
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
                    tagged BR .br: begin
                        if (evaluateCondition(br.condition, sw)) begin
                            $display("%x: BRAN: take", instrPC);
                            Word newPC = br.r ? unpack(signExtend(br.constant << 2) + instrPC)
                                              : unpack(zeroExtend(br.constant << 2));
                            mrd = tagged Valid tuple2(PC, newPC);
                        end else begin
                            $display("%x: BRAN: skip ", instrPC, fshow(br.condition), fshow(sw));
                        end
                    end
                    tagged SLS .sls: begin
                        res.ea = zeroExtend(sls.address);
                        res.op = sls.s ? tagged Store rs2v : tagged Load destination;
                    end
                    tagged SLI .sli: begin
                        Word imm = zeroExtend(sli.address);
                        mrd = tagged Valid tuple2(destination, imm);
                        $display("%x: COMP ", instrPC, fshow(sli));
                    end
                    tagged SPLS .spls: begin
                        Word added = (rs1v + signExtend(spls.constant))[31:0];
                        Word ea = spls.p ? added : rs1v;
                        if (spls.q) begin
                            mrd = tagged Valid tuple2(q.first.rs1, added);
                        end
                        res.ea = ea;
                        let rrv = resolveRegister(spls.destination, instrPC, regFromMemory.wget(), rs2);
                        case (spls) matches
                            InstSPLS { s: True, y: True }: begin
                                res.op = tagged Store rs2v;
                                res.width = Byte;
                            end
                            InstSPLS { s: False, y: True }: begin
                                res.op = tagged Store rs2v;
                                res.width = Word;
                            end
                            InstSPLS { s: True, y: False }: begin
                                res.op = tagged Load rs2ix;
                                res.width = Byte;
                            end
                            InstSPLS { s: False, y: False }: begin
                                res.op = tagged Load rs2ix;
                                res.width = Word;
                            end
                        endcase
                    end
                endcase

                if (runAlu) begin
                    let aluRes <- alu1.run(aluOp);
                    mrd = tagged Valid tuple2(destination, aluRes.result);
                    if (flags) begin
                        $display("%x: FLAG ", instrPC, fshow(aluRes.sw));
                        msw = tagged Valid aluRes.sw;
                    end
                end
                case (mrd) matches
                    tagged Valid { PC, .val }: begin
                        mispredict.put(Misprediction { pc : val
                                                     , opc: instrPC + 8
                                                     });
                    end
                endcase
                if (res.op matches tagged Load .rd) begin
                    memoryRegisterLoad <= tagged Valid rd;
                end else begin
                    memoryRegisterLoad <= tagged Invalid;
                end
                rwr.write(msw, mrd);
                return res;
            end
        endmethod
    endinterface

    interface Put fetch;
        method Action put(FetchToCompute v);
            busyPut.send();
            q.enq(v);
        endmethod
    endinterface

    interface RegisterWriteBypass memoryBypass;
        method Action strobe(Register ix, Word value);
            regFromMemory.wset(tuple2(ix, value));
        endmethod
    endinterface
endmodule

endpackage
