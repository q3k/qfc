// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2022 Sergiusz Bazanski

package Tb;

import Connectable :: *;
import Wishbone :: *;
import TieOff :: *;

import Lanai_IFC :: *;
import Lanai_CPU :: *;
import Lanai_Memory :: *;
import WishboneCrossbar :: *;
import WishboneSPI :: *;

function Maybe#(WishboneCrossbar::DecodedAddr#(1, 32)) decoder(Bit#(32) address);
    return case (address) matches
        32'h4001_3???: tagged Valid DecodedAddr { downstream: 0, address: address & 32'hfff };
        default: tagged Invalid;
    endcase;
endfunction

(* synthesize *)
module mkTb (Empty);
    Lanai_BlockRAM#(4096) bram <- mkBlockMemory("lanai/bram.bin");
    Lanai_IFC cpu <- mkLanaiCPU;

    WishboneCrossbar::Crossbar#(1, 1, 32, 32, 4) fabric <- mkCrossbar(decoder);
    WishboneSPI::SPIController#(32) spi <- mkSPIController;
    mkConnection(fabric.downstreams[0], spi.slave);

    mkConnection(cpu.imem_client, bram.memory.imem);
    mkConnection(cpu.dmem_client, bram.memory.dmem);
    mkConnection(cpu.sysmem_client, fabric.upstreams[0]);

    Reg#(int) i <- mkReg(0);
    rule testFetch;
        if (i > 400) begin
            //bram.dump;
            $finish(0);
        end
        i <= i + 1;
        //$display("counter:", cpu.readPC);
    endrule
endmodule

endpackage
