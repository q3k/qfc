// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2022 Sergiusz Bazanski

package CPU_ALU;

import Vector :: *;

import CPU_Defs :: *;

typedef struct {
    Word a;
    Word b;
    AluOperationKind kind;
    Bool shiftArithmetic;
    Bool addCarry;
    Bool condition;
} AluOperation deriving (Bits);

typedef struct {
    Word result;
    StatusWord sw;
} AluResult deriving (Bits);

interface ALU_IFC;
    method ActionValue#(AluResult) run(AluOperation op);
endinterface

(* synthesize *)
module mkALU (ALU_IFC);
    method ActionValue#(AluResult) run(AluOperation op);
        let res = AluResult { result: 0
                            , sw: StatusWord { carry: False
                                             , overflow: False
                                             , zero: False
                                             , negative: False
                                             }
                            };

        Bit#(64) shiftIn = op.shiftArithmetic
                           ? signExtend(op.a)
                           : zeroExtend(op.a);
        // Make barrel shifter.
        function Bit#(33) makeShifts(Integer ix);
            if (ix < 32) begin
                return truncate(shiftIn << ix);
            end else begin
                Bit#(6) twoc = (~fromInteger(ix))+1;
                return truncate(shiftIn >> twoc);
            end
        endfunction
        Vector#(64, Bit#(33)) shifts = genWith(makeShifts);

        case (op.kind) matches
            Add: begin
                Bit#(33) out = zeroExtend(op.a) + zeroExtend(op.b) + zeroExtend(pack(op.addCarry));
                res.sw.carry = out[32] == 1;
                res.result = out[31:0];
                if ((op.a[31] == op.b[31]) && (op.a[31] != res.result[31])) begin
                    res.sw.overflow = True;
                end
            end
            Sub: begin
                Bit#(33) out = zeroExtend(op.a) + zeroExtend(~op.b) + zeroExtend(pack(op.addCarry));
                res.sw.carry = out[32] == 1;
                res.result = out[31:0];
                if ((op.a[31] == op.b[31]) && (op.a[31] != res.result[31])) begin
                    res.sw.overflow = True;
                end
            end
            And: res.result = op.a & op.b;
            Or: res.result = op.a | op.b;
            Xor: res.result = op.a ^ op.b;
            Shift: begin
                // TODO: optimize, this is our slowest path (42 -> 34MHz fclk).
                Bit#(6) amount = truncate(op.b);
                Bit#(33) shifted = shifts[amount];
                res.result = shifted[31:0];
                if ((amount > 0) && op.shiftArithmetic)
                    res.sw.carry = shifted[32] == 1;
            end
            Select: begin
                res.result = op.condition ? op.a : op.b;
            end
        endcase

        res.sw.zero = (res.result == 0);
        res.sw.negative = (res.result[31] == 1);

        return res;
    endmethod
endmodule


endpackage
