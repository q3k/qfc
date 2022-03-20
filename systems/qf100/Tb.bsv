package Tb;

import QF100 :: *;
import SPIFlashEmulator :: *;
import StmtFSM :: *;
import WishboneSPI :: *;

(* synthesize *)
module mkTbQF100(Empty);
    QF100 qf100 <- mkQF100;
    SPIFlashEmulator emu <- mkSPIFlashEmulator("systems/qf100/flash.bin");

    rule feed_qf100_in;
        qf100.gpio_in(0);
        qf100.spi.miso(False);
        qf100.mspi.miso(emu.miso);
    endrule

    rule feed_emu_in;
        emu.mosi(unpack(qf100.mspi.mosi));
        emu.sclk(unpack(qf100.mspi.sclk));
        emu.csb(qf100.mspi_csb);
    endrule

    Reg#(Bit#(32)) tmp <- mkReg(0);
    Stmt test = seq
        for (tmp <= 0; tmp <= 20000; tmp <= tmp + 1) seq
            noAction;
        endseq
    endseq;
    mkAutoFSM(test);
endmodule

endpackage
