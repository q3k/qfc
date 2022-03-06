package Tb;

import Assert :: *;
import CBus :: *;
import StmtFSM :: *;

import Wishbone :: *;

typedef 24 DCBusAddrWidth;
typedef 32 DCBusDataWidth;

typedef CBus#(DCBusAddrWidth, DCBusDataWidth) DCBus;
typedef CRAddr#(DCBusAddrWidth, DCBusDataWidth) DCAddr;
typedef ModWithCBus#(DCBusAddrWidth, DCBusDataWidth, i) DModWithCBus#(type i);

typedef bit TCfgReset;

typedef Bit#(4) TCfgInit;
typedef Bit#(6) TCfgTz;
typedef Bit#(16) TCfgCnt;

typedef bit TCfgOnes;
typedef bit TCfgError;

Bit#(DCBusAddrWidth) cfgResetAddr = 0;
Bit#(DCBusAddrWidth) cfgStateAddr = 1;
Bit#(DCBusAddrWidth) cfgStatusAddr = 2;

DCAddr cfg_reset_reset = DCAddr { a: cfgResetAddr, o: 0 };

DCAddr cfg_setup_init = DCAddr { a: cfgStateAddr, o: 0 };
DCAddr cfg_setup_tz   = DCAddr { a: cfgStateAddr, o: 4 };
DCAddr cfg_setup_cnt  = DCAddr { a: cfgStateAddr, o: 16 };

DCAddr cfg_status_ones  = DCAddr { a: cfgStatusAddr, o: 0 };
DCAddr cfg_status_error = DCAddr { a: cfgStatusAddr, o: 1 };

interface Block;
endinterface

(* synthesize *)
module [Module] mkBlock(IWithCBus#(DCBus, Block));
    let ifc <- exposeCBusIFC(mkBlockInternal);
    return ifc;
endmodule

module [DModWithCBus] mkBlockInternal(Block);
    Reg#(TCfgReset) reg_reset_reset  <- mkCBRegW(cfg_reset_reset, 0);

    Reg#(TCfgInit)  reg_setup_init   <- mkCBRegRW(cfg_setup_init, 0);
    Reg#(TCfgTz)    reg_setup_tz     <- mkCBRegRW(cfg_setup_tz, 0);
    Reg#(TCfgCnt)   reg_setup_cnt    <- mkCBRegRW(cfg_setup_cnt, 1);

    Reg#(TCfgOnes)  reg_status_ones  <- mkCBRegRC(cfg_status_ones, 0);
    Reg#(TCfgError) reg_status_error <- mkCBRegRC(cfg_status_error, 0);

    rule bumpCounter (reg_setup_cnt != unpack('1) );
        reg_setup_cnt <= reg_setup_cnt + 1;
    endrule

    rule watch4ones (reg_setup_cnt == unpack('1));
        reg_status_ones <= 1;
    endrule
endmodule

(* synthesize *)
module mkTbInner(Wishbone::Slave#(32, 24, 4));
    IWithCBus#(DCBus,Block) dut <- mkBlock;
    Wishbone::Slave#(32, 24, 4) cbusSlave <- mkCBusBridge(dut.cbus_ifc);

    return cbusSlave;
endmodule

function Stmt doRead(Wishbone::Slave#(32, 24, 4) slave, Reg#(Bool) ack, Maybe#(Reg#(Bit#(32))) res, Bit#(24) addr);
    return seq
        slave.request(False, False, 0, 0, 0, False);
        while (!ack) seq
            par
                slave.request(True, True, addr, 0, 4'b1111, False);
                action
                    case (res) matches
                        tagged Valid .resR: resR <= slave.dat;
                    endcase
                endaction
            endpar
        endseq
        slave.request(False, False, 0, 0, 0, False);
    endseq;
endfunction

function Stmt doWrite(Wishbone::Slave#(32, 24, 4) slave, Reg#(Bool) ack, Bit#(32) data, Bit#(24) addr);
    return seq
        slave.request(False, False, 0, 0, 0, False);
        while (!ack) seq
            slave.request(True, True, addr, data, 4'b1111, True);
        endseq
        slave.request(False, False, 0, 0, 0, False);
    endseq;
endfunction

(* synthesize *)
module mkTb(Empty);
    Wishbone::Slave#(32, 24, 4) slave <- mkTbInner;

    Reg#(Bool) ack <- mkReg(False);
    Reg#(Bit#(32)) data <- mkReg(0);
    rule register;
        ack <= slave.ack;
        data <= slave.dat;
    endrule

    Reg#(Bit#(32)) res <- mkReg(0);

    Stmt test = seq
        // Read setup.count and ensure it counts up.
        //
        // setup.count increments on each cycle of the test core, the following
        // values have been made to correspond to practical behaviour of the
        // DUT.
        doRead(slave, ack, tagged Valid res, 1);
        dynamicAssert(res[31:16] == 4, "setup.count should've been 4");
        doRead(slave, ack, tagged Valid res, 1);
        dynamicAssert(res[31:16] == 9, "setup.count should've been 9");

        // Let's write setup.count to a slightly higher value and read it back.
        doWrite(slave, ack, 1337 << 16, 1);
        doRead(slave, ack, tagged Valid res, 1);
        dynamicAssert(res[31:16] == 1340, "setup.count should've been 1337+3");
    endseq;
    mkAutoFSM(test);

endmodule

endpackage
