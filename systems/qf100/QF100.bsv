// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2022 Sergiusz Bazanski

package QF100;

import GetPut :: *;
import ClientServer :: *;
import Connectable :: *;
import Lanai_IFC :: *;
import Lanai_CPU :: *;
import Lanai_Memory :: *;
import LanaiFrontend :: *;
import SPIFlashController :: *;
import RAM :: *;
import WishboneCrossbar :: *;
import WishboneSPI :: *;
import WishboneGPIO :: *;


Bit#(1) wbAddrSPI = 0;
Bit#(1) wbAddrGPIO = 1;

function Maybe#(WishboneCrossbar::DecodedAddr#(2, 32)) decoder(Bit#(32) address);
    return case (address) matches
        32'h4001_30??: tagged Valid DecodedAddr { downstream: wbAddrSPI, address: address & 32'hff };
        32'h4001_08??: tagged Valid DecodedAddr { downstream: wbAddrGPIO, address: address & 32'hff };
        default: tagged Invalid;
    endcase;
endfunction

(* synthesize *)
module mkQF100Memory(Lanai_BlockRAM#(2048));
    Lanai_BlockRAM#(2048) inner <- mkBlockMemory(tagged Invalid);
    return inner;
endmodule

(* synthesize *)
module mkQF100SPI(WishboneSPI::SPIController#(32));
    let res <- mkSPIController;
    interface slave = res.slave;
    interface spiMaster = res.spiMaster;
endmodule

(* synthesize *)
module mkQF100GPIO(WishboneGPIO::GPIOController#(32));
    let res <- mkGPIOController;
    interface slave = res.slave;
    method in = res.in;
    method out = res.out;
    method oe = res.oe;
endmodule

interface QF100Fabric;
    interface Wishbone::Slave#(32, 32, 4) cpu;
    interface Wishbone::Master#(32, 32, 4) spi;
    interface Wishbone::Master#(32, 32, 4) gpio;
endinterface

(* synthesize *)
module mkQF100Fabric(QF100Fabric);
    WishboneCrossbar::Crossbar#(1, 2, 32, 32, 4) fabric <- mkCrossbar(decoder);

    interface cpu = fabric.upstreams[0];
    interface spi = fabric.downstreams[wbAddrSPI];
    interface gpio = fabric.downstreams[wbAddrGPIO];
endmodule

interface QF100;
    // Memory SPI.
    interface WishboneSPI::Master mspi;
    (* always_ready *)
    method    Bool                mspi_csb;

    // General purpose SPI.
    interface WishboneSPI::Master spi;

    // GPIO.
    (* always_ready *)
    method Bit#(16) gpio_oe;
    (* always_ready *)
    method Bit#(16) gpio_out;
    (* always_ready, always_enabled *)
    method Action   gpio_in(Bit#(16) value);
endinterface

(* synthesize *)
module mkQF100(QF100);
    LanaiFrontend frontend <- mkLanaiFrontend;

    Lanai_IFC cpu <- mkLanaiCPU;
    mkConnection(cpu.imem_client, frontend.core_imem);
    mkConnection(cpu.dmem_client, frontend.core_dmem);

    Lanai_BlockRAM#(2048) ram <- mkQF100Memory;
    mkConnection(frontend.ram_imem, ram.memory.imem);
    mkConnection(frontend.ram_dmem, ram.memory.dmem);

    SPIFlashController#(16, 64) fmc <- mkSPIFlashController;
    mkConnection(frontend.fmc_imem, fmc.serverA);
    rule fmcDMemTranslate;
        let req <- frontend.fmc_dmem.request.get();
        fmc.serverB.request.put(req.addr);
    endrule
    mkConnection(frontend.fmc_dmem.response, fmc.serverB.response);

    QF100Fabric fabric <- mkQF100Fabric;
    mkConnection(cpu.sysmem_client, fabric.cpu);

    WishboneSPI::SPIController#(32) spiCtrl <- mkQF100SPI;
    mkConnection(fabric.spi, spiCtrl.slave);

    WishboneGPIO::GPIOController#(32) gpioCtrl <- mkQF100GPIO;
    mkConnection(fabric.gpio, gpioCtrl.slave);

    interface mspi = fmc.spi;
    method Bool mspi_csb;
        return unpack(fmc.csb);
    endmethod
    interface spi  = spiCtrl.spiMaster;
    method gpio_oe = gpioCtrl.oe;
    method gpio_out = gpioCtrl.out;
    method gpio_in  = gpioCtrl.in;
endmodule

endpackage
