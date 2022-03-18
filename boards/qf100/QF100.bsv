// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2022 Sergiusz Bazanski

package QF100;

import Clocks :: *;
import Connectable :: *;
import TieOff :: *;

import Lanai_IFC :: *;
import Lanai_CPU :: *;
import Lanai_Memory :: *;
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

interface CaravelUserProject;
    // Logic Analyzer signals
    (* always_ready, always_enabled, prefix="" *)
    method Action la_in((* port="la_data_in" *) Bit#(128) data
                       ,(* port="la_oenb" *) Bit#(128) oenb
                       );
    (* always_ready, result="la_data_out" *)
    method Bit#(128) la_out;

    // IOs
    (* always_ready, always_enabled, prefix="" *)
    method Action io_in((* port="io_in" *) Bit#(38) data
                       );
    (* always_ready, result="io_out" *)
    method Bit#(38) io_out;
    (* always_ready, result="io_oeb" *)
    method Bit#(38) io_oeb;

    // IRQ
    (* always_ready, result="irq" *)
    method Bit#(3) irq;
endinterface

(* synthesize *)
module mkQF100Memory(Lanai_BlockRAM#(1024));
    // TODO(q3k): ... figure out how the fuck to unhardcode this.
    Lanai_BlockRAM#(1024) inner <- mkBlockMemory("boards/qf100/bram.bin");
    return inner;
endmodule

typedef struct {
    Bit#(19) unused;

    Bit#(16) gpio;

    Bit#(1) spi_miso;
    Bit#(1) spi_mosi;
    Bit#(1) spi_sck;

} IOPins deriving (Bits);

(* synthesize, default_clock_osc="wb_clk_i", default_reset="wb_rst_i" *)
module mkQF105 (CaravelUserProject);
    Reset reset   <- exposeCurrentReset();
    Reset reset_n <- mkResetInverter(reset);

    let res <- mkQF100Core(reset_by reset_n);
    return res;
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

module mkQF100Core(CaravelUserProject);

    QF100Fabric fabric <- mkQF100Fabric;

    Lanai_IFC cpu <- mkLanaiCPU;
    mkConnection(cpu.sysmem_client, fabric.cpu);

    let mem <- mkQF100Memory;
    mkConnection(cpu.imem_client, mem.memory.imem);
    mkConnection(cpu.dmem_client, mem.memory.dmem);

    WishboneSPI::SPIController#(32) spi <- mkQF100SPI;
    mkConnection(fabric.spi, spi.slave);

    WishboneGPIO::GPIOController#(32) gpio <- mkQF100GPIO;
    mkConnection(fabric.gpio, gpio.slave);

    method Bit#(128) la_out = 0;
    method Bit#(3) irq = 0;

    method Action io_in(Bit#(38) data);
        IOPins v = unpack(data);
        spi.spiMaster.miso(unpack(v.spi_miso));
        gpio.in(v.gpio);
    endmethod

    method Bit#(38) io_oeb;
        return ~pack(IOPins { spi_sck: 1
                            , spi_mosi: 1
                            , spi_miso: 0
                            , gpio: gpio.oe()
                            , unused: 0
                            });
    endmethod

    method Bit#(38) io_out;
        return pack(IOPins { spi_sck: spi.spiMaster.sclk
                           , spi_mosi: spi.spiMaster.mosi
                           , spi_miso: 0
                           , gpio: gpio.out()
                           , unused: 0
                           });
    endmethod
endmodule

endpackage
