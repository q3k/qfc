package Tb;

import Assert :: *;
import Connectable :: *;
import WishboneSPI :: *;

import QF100 :: *;
import Lanai_Memory :: *;
import SPIFlashEmulator :: *;

(* synthesize *)
module mkTbQF100(Empty);
    QF100 qf100 <- mkQF100;
    Lanai_BlockRAM#(2048) bram <- mkQF100BlockRAM;
    SPIFlashEmulator emu <- mkSPIFlashEmulator("systems/qf100/flash.bin");

    mkConnection(qf100.ram_imem, bram.memory.imem);
    mkConnection(qf100.ram_dmem, bram.memory.dmem);

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

    Reg#(Bit#(32)) counter <- mkReg(0);
    rule upcount;
        counter <= counter + 1;
    endrule
    rule timeout;
        dynamicAssert(counter < 40_000, "Timeout.");
    endrule
    rule findGPIOPatern;
        if (qf100.gpio_out == 3) begin
            $finish(0);
        end
    endrule
endmodule

endpackage
