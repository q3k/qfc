// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2022 Sergiusz Bazanski

package Board;

import Clocks :: *;
import Connectable :: *;
import TieOff :: *;

import QF100 :: *;
import Sky130SRAM :: *;

import Lanai_IFC :: *;
import Lanai_CPU :: *;
import Lanai_Memory :: *;
import RAM :: *;
import WishboneCrossbar :: *;
import WishboneSPI :: *;
import WishboneGPIO :: *;

import SPIFlashEmulator :: *;

(* synthesize *)
module mkQF100SPIFlashEmulator(SPIFlashEmulator);
    let res <- mkSPIFlashEmulator("boards/qf100/flash.bin");
    return res;
endmodule

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

typedef struct {
    Bit#(7) unused;

    Bit#(16) gpio;

    Bit#(1) spi_miso;
    Bit#(1) spi_mosi;
    Bit#(1) spi_sck;

    Bit#(1) mspi_miso;
    Bit#(1) mspi_mosi;
    Bit#(1) mspi_sck;
    Bit#(1) mspi_csb;

    Bit#(8) reserved;
} IOPins deriving (Bits);

module mkQF105Inner(CaravelUserProject);
    let qf100 <- mkQF100;
    let sram <- mkSky130SRAM;

    mkConnection(qf100.ram_imem, sram.portB);
    mkConnection(qf100.ram_dmem, sram.portA);

    method Bit#(128) la_out = 0;
    method Bit#(3) irq = 0;
    
    method Action io_in(Bit#(38) data);
        IOPins v = unpack(data);

        qf100.spi.miso(unpack(v.spi_miso));
        qf100.mspi.miso(unpack(v.mspi_miso));
        qf100.gpio_in(v.gpio);
    endmethod
    
    method Bit#(38) io_oeb;
        return ~pack(IOPins { reserved: 0

                            , mspi_csb: 1
                            , mspi_sck: 1
                            , mspi_mosi: 1
                            , mspi_miso: 0

                            , spi_sck: 1
                            , spi_mosi: 1
                            , spi_miso: 0

                            , gpio: qf100.gpio_oe()

                            , unused: 0
                            });
    endmethod
    
    method Bit#(38) io_out;
        return  pack(IOPins { reserved: 0

                            , mspi_csb: pack(qf100.mspi_csb)
                            , mspi_sck: pack(qf100.mspi.sclk)
                            , mspi_mosi: qf100.mspi.mosi
                            , mspi_miso: 0

                            , spi_sck: qf100.spi.sclk
                            , spi_mosi: qf100.spi.mosi
                            , spi_miso: 0

                            , gpio: qf100.gpio_out()

                            , unused: 0
                            });
    endmethod
endmodule

(* synthesize, default_clock_osc="wb_clk_i", default_reset="wb_rst_i" *)
module mkQF105 (CaravelUserProject);
    Reset reset   <- exposeCurrentReset();
    Reset reset_n <- mkResetInverter(reset);

    let qf100 <- mkQF105Inner(reset_by reset_n);
    return qf100;
endmodule


endpackage
