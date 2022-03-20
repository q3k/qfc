// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2022 Sergiusz Bazanski

package Board;

import Connectable :: *;
import TieOff :: *;

import ECP5 :: *;
import QF100 :: *;
import WishboneSPI :: *;

interface Top;
    (* always_enabled *)
    method Bit#(8) led;

    interface ESP32 wifi;

    (* always_enabled *)
    method Bool spiMOSI;

    (* always_enabled, always_ready *)
    method Action spiMISO(Bool value);

    (* always_enabled *)
    method Bool spiSCK;

    (* always_enabled *)
    method Bool spiCSB;
endinterface

interface ESP32;
    (* always_enabled *)
    method Bit#(1) gpio0;
endinterface

(* synthesize, default_clock_osc="clk_25mhz", default_reset="btn_pwr" *)
module mkTop (Top);
    GSR gsr <- mkGSR;

    let qf100 <- mkQF100;

    rule tieOff;
        qf100.gpio_in(0);
        qf100.spi.miso(False);
    endrule

    interface ESP32 wifi;
        method gpio0 = 1;
    endinterface

    method led = qf100.gpio_out[7:0];
    method spiMOSI = unpack(qf100.mspi.mosi);
    method spiSCK = unpack(qf100.mspi.sclk);
    method spiCSB = qf100.mspi_csb;

    method Action spiMISO(Bool value);
        qf100.mspi.miso(value);
    endmethod
endmodule

endpackage
