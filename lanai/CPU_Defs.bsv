// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2022 Sergiusz Bazanski

package CPU_Defs;

import GetPut :: *;

typedef Bit#(32) Word;
typedef Bit#(16) Half;
typedef Bit#(8) Byte;

typedef Bit#(4) Epoch;

typedef enum {
    R0, R1, PC, R3, R4, R5, R6, R7,
    R8, R9, R10, R11, R12, R13, R14, R15,
    R16, R17, R18, R19, R20, R21, R22, R23,
    R24, R25, R26, R27, R28, R29, R30, R31
} Register deriving (Bits, Eq, FShow);

typedef struct {
    Bool zero;
    Bool negative;
    Bool overflow;
    Bool carry;
} StatusWord deriving (FShow);

instance Bits#(StatusWord, 32);
    function StatusWord unpack(Bit#(32) x);
        return StatusWord { zero: x[0] == 1
                          , negative: x[1] == 1
                          , overflow: x[2] == 1
                          , carry: x[3] == 1
                          };
    endfunction
    function Bit#(32) pack(StatusWord sw);
        return { 28'b0
               , pack(sw.carry)
               , pack(sw.overflow)
               , pack(sw.negative)
               , pack(sw.zero)
               };
    endfunction
endinstance

typedef union tagged {
    InstRI   RI;
    InstRR   RR;
    InstRM   RM;
    InstRRM  RRM;
    InstBR   BR;
    InstSLS  SLS;
    InstSLI  SLI;
    InstSPLS SPLS;
    Word Unknown;
} Instruction deriving(FShow);

instance Bits#(Instruction, 32);
    function Instruction unpack(Bit#(32) x);
        return case (x[31:28]) matches
            4'b0???: tagged RI InstRI   { operation: unpack(x[30:28])
                                        , destination: unpack(x[27:23])
                                        , source: unpack(x[22:18])
                                        , flags: unpack(x[17])
                                        , high: unpack(x[16])
                                        , constant: x[15:0]
                                        };
            4'b1100: tagged RR InstRR   { destination: unpack(x[27:23])
                                        , source1: unpack(x[22:18])
                                        , flags: unpack(x[17])
                                        , source2: unpack(x[15:11])
                                        , operation: unpack(x[10:3])
                                        , condition: unpack({x[2:0], x[16]})
                                        };
            4'b100?: tagged RM InstRM   { store: unpack(x[28])
                                        , destination: unpack(x[27:23])
                                        , source: unpack(x[22:18])
                                        , p: unpack(x[17])
                                        , q: unpack(x[16])
                                        , constant: x[15:0]
                                        };
            4'b101?: tagged RRM InstRRM { store: unpack(x[28])
                                        , destination: unpack(x[27:23])
                                        , source1: unpack(x[22:18])
                                        , p: unpack(x[17])
                                        , q: unpack(x[16])
                                        , source2: unpack(x[15:11])
                                        , operation: unpack(x[10:3])
                                        , memoryAccess: unpack(x[2:1])
                                        , zeroExtend: unpack(x[0])
                                        };
            4'b1110: tagged BR InstBR   { condition: unpack({x[27:25], x[0]})
                                        , constant: unpack(x[24:2])
                                        , r: unpack(x[1])
                                        };
            4'b1111: case (x[17:15]) matches
                3'b0??: tagged SLS  InstSLS  { destination: unpack(x[27:23])
                                             , address: unpack({x[22:18], x[15:0]})
                                             , s: unpack(x[16])
                                             };
                3'b10?: tagged SLI  InstSLI  { destination: unpack(x[27:23])
                                             , address: unpack({x[22:18], x[15:0]})
                                             };
                3'b110: tagged SPLS InstSPLS { destination: unpack(x[27:23])
                                             , source1: unpack(x[22:18])
                                             , y: unpack(x[14])
                                             , s: unpack(x[13])
                                             , e: unpack(x[12])
                                             , p: unpack(x[11])
                                             , q: unpack(x[10])
                                             , constant: unpack(x[9:0])
                                             };
                default: tagged Unknown x;
            endcase
            default: tagged Unknown x;
        endcase;
    endfunction
    function Bit#(32) pack(Instruction i);
        return case (i) matches
            tagged RI .ri:     { 1'b0
                               , pack(ri.operation)
                               , pack(ri.destination)
                               , pack(ri.source)
                               , pack(ri.flags)
                               , pack(ri.high)
                               , pack(ri.constant)
                               };
            tagged RR .rr:     { 4'b1100
                               , pack(rr.destination)
                               , pack(rr.source1)
                               , pack(rr.flags)
                               , pack(rr.condition)[0]
                               , pack(rr.source2)
                               , pack(rr.operation)
                               , pack(rr.condition)[3:1]
                               };
            tagged RM .rm:     { 3'b100
                               , pack(rm.store)
                               , pack(rm.destination)
                               , pack(rm.source)
                               , pack(rm.p)
                               , pack(rm.q)
                               , pack(rm.constant)
                               };
            tagged RRM .rrm:   { 3'b101
                               , pack(rrm.store)
                               , pack(rrm.destination)
                               , pack(rrm.source1)
                               , pack(rrm.p)
                               , pack(rrm.q)
                               , pack(rrm.source2)
                               , pack(rrm.operation)
                               , pack(rrm.memoryAccess)
                               , pack(rrm.zeroExtend)
                               };
            tagged BR .br:     { 4'b1110
                               , pack(br.condition)[3:1]
                               , pack(br.constant)
                               , pack(br.r)
                               , pack(br.condition)[0]
                               };
            tagged SLS .sls:   { 4'b1111
                               , pack(sls.destination)
                               , pack(sls.address[20:16])
                               , 1'b0
                               , pack(sls.s)
                               , pack(sls.address[15:0])
                               };
            tagged SLI .sli:   { 4'b1111
                               , pack(sli.destination)
                               , pack(sli.address[20:16])
                               , 2'b10
                               , pack(sli.address[15:0])
                               };
            tagged SPLS. spls: { 4'b1111
                               , pack(spls.destination)
                               , pack(spls.source1)
                               , 3'b110
                               , pack(spls.y), pack(spls.s), pack(spls.e)
                               , pack(spls.p), pack(spls.q)
                               , pack(spls.constant)
                               };
        endcase;
    endfunction
endinstance

typedef struct {
    RI_Operation operation;
    Bool flags;
    Bool high;
    Register destination;
    Register source;
    Bit#(16) constant;
} InstRI deriving (FShow);

typedef struct {
    Register destination;
    Register source1;
    Register source2;
    Bool flags;
    RR_Operation operation;
    Condition condition;
} InstRR deriving (FShow);

typedef struct {
    Bool store;
    Register destination;
    Register source;
    Bool p;
    Bool q;
    Bit#(16) constant;
} InstRM deriving (FShow);

typedef struct {
    Bool store;
    Register destination;
    Register source1;
    Bool p;
    Bool q;
    Register source2;
    RR_Operation operation;
    RRM_MemoryAccess memoryAccess;
    Bool zeroExtend;
} InstRRM deriving (FShow);

typedef struct {
    Condition condition;
    Bit#(23) constant;
    Bool r;
} InstBR deriving (FShow);

typedef struct {
    Register destination;
    Bit#(21) address;
    Bool s;
} InstSLS deriving (FShow);

typedef struct {
    Register destination;
    Bit#(21) address;
} InstSLI deriving (FShow);

typedef struct {
    Register destination;
    Register source1;
    Bool y;
    Bool s;
    Bool e;
    Bool p;
    Bool q;
    Bit#(10) constant;
} InstSPLS deriving (FShow);

typedef enum { T  = 4'b0000 // true
             , F  = 4'b0001 // false
             , HI = 4'b0010 // high
             , LS = 4'b0011 // low or same
             , CC = 4'b0100 // carry cleared
             , CS = 4'b0101 // carrry set
             , NE = 4'b0110 // not equal
             , EQ = 4'b0111 // equal
             , VC = 4'b1000 // overflow cleared
             , VS = 4'b1001 // overflow set
             , PL = 4'b1010 // plus
             , MI = 4'b1011 // minus
             , GE = 4'b1100 // greater than or equal
             , LT = 4'b1101 // less than
             , GT = 4'b1110 // greater than
             , LE = 4'b1111 // less than or equal
             } Condition deriving (Bits, Eq, FShow);

function Bool evaluateCondition(Condition cond, StatusWord sw);
    return case (cond) matches
        T: True;
        F: False;
        HI: (sw.carry && !sw.zero);
        LS: (!sw.carry || sw.zero);
        CC: !sw.carry;
        CS: sw.carry;
        NE: !sw.zero;
        EQ: sw.zero;
        VC: !sw.overflow;
        VS: sw.overflow;
        PL: !sw.negative;
        MI: sw.negative;
        GE: ((sw.negative && sw.overflow) || (!sw.negative && !sw.overflow));
        LT: ((sw.negative && !sw.overflow) || (!sw.negative && sw.overflow));
        GT: ((sw.negative && sw.overflow && !sw.zero) || (!sw.negative && !sw.overflow && !sw.zero));
        LE: (sw.zero || (sw.negative && !sw.overflow) || (!sw.negative && sw.overflow));
    endcase;
endfunction

typedef enum {
    FullWord = 2'b01,
    HalfWord = 2'b00,
    Byte     = 2'b10
} RRM_MemoryAccess deriving (Bits, Eq, FShow);

typedef enum {
    Add   = 3'b000,
    Addc  = 3'b001,
    Sub   = 3'b010,
    Subb  = 3'b011,
    And   = 3'b100,
    Or    = 3'b101,
    Xor   = 3'b110,
    Shift = 3'b111
} RI_Operation deriving (Bits, Eq, FShow);

typedef enum {
    Add, Addc, Sub, Subb, And, Or, Xor, LShift, AShift, Select, Unknown
} RR_Operation deriving (Eq, FShow);

instance Bits#(RR_Operation, 8);
    function RR_Operation unpack(Bit#(8) x);
        return case (x) matches
            8'b000?????: Add;
            8'b001?????: Addc;
            8'b010?????: Sub;
            8'b011?????: Subb;
            8'b100?????: And;
            8'b101?????: Or;
            8'b110?????: Xor;
            8'b11110???: LShift;
            8'b11111???: AShift;
            8'b11100000: Select;
            default:     Unknown;
        endcase;
    endfunction
    function Bit#(8) pack(RR_Operation x);
        return case(x) matches
            Add:    8'b000_00000;
            Addc:   8'b001_00000;
            Sub:    8'b010_00000;
            Subb:   8'b011_00000;
            And:    8'b100_00000;
            Or:     8'b101_00000;
            Xor:    8'b110_00000;
            LShift: 8'b111_10000;
            AShift: 8'b111_11000;
            Select: 8'b111_00000;
        endcase;
    endfunction
endinstance

interface RegisterRead;
    method Word read(Register ix);
endinterface

interface RegisterWrite;
    method Action write(Register ix, Word data);
endinterface

interface StatusWordRead;
    method StatusWord read;
endinterface

interface StatusWordWrite;
    method Action write(StatusWord sw);
endinterface

interface RegisterWriteCompute;
    method Action write(Maybe#(StatusWord) sw, Maybe#(Tuple2#(Register, Word)) rd);
endinterface

interface RegisterWriteMemory;
    method Action write(Register rd, Word value);
endinterface

interface RegisterWriteBypass;
    (* always_ready *)
    method Action strobe(Register ix, Word value);
endinterface

typedef enum {
    Add, Sub, And, Or, Xor, Shift, Select
} AluOperationKind deriving (Bits);

function AluOperationKind insAluOpKind(Instruction instr);
    return case (instr) matches
        tagged RI .ri: case (ri.operation) matches
            Add: Add;
            Addc: Add;
            Sub: Sub;
            Subb: Sub;
            And: And;
            Or: Or;
            Xor: Xor;
            Shift: Shift;
            default: Add;
        endcase
        tagged RR .rr: case (rr.operation) matches
            Add: Add;
            Addc: Add;
            Sub: Sub;
            Subb: Sub;
            And: And;
            Or: Or;
            Xor: Xor;
            LShift: Shift;
            AShift: Shift;
            Select: Select;
            default: Add;
        endcase
    endcase;
endfunction

typedef struct {
    Instruction instr;
    Word pc;
    Register rs1;
    Register rs2;
    Register rd;
    Bool runAlu;
    AluOperationKind aluOpKind;
} FetchToCompute deriving (Bits);

typedef union tagged {
    void Noop;
    Word Store;
    Register Load;
} ComputeToMemoryOp deriving (Bits);

typedef struct {
    Word ea;
    Word pc;
    ComputeToMemoryOp op;
    DMemReqWidth width;
} ComputeToMemory deriving (Bits);

typedef struct {
    Word pc;
    Word opc;
} Misprediction deriving (Bits, FShow);

typedef Put #(Misprediction) MispredictReport;

typedef enum {
    Word,
    HalfWord,
    Byte
} DMemReqWidth deriving (Bits);

// Everything below sysmemSplit is routed to imem/dmem. Everything including
// and above is routed to sysmem/wishbone.
Word sysmemSplit = 32'h2000_0000;

endpackage
