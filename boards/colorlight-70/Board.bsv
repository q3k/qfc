// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2022 Sergiusz Bazanski

package Board;

import GetPut :: *;
import ClientServer :: *;
import Connectable :: *;
import ECP5 :: *;
import RAM :: *;
import FIFO :: *;
import SpecialFIFOs :: *;
import Probe :: *;

import Hub75 :: *;

module mkPatternGen (Server #(Coordinates#(4), PixelData));
    FIFO#(Coordinates#(4)) fifoReq <- mkPipelineFIFO;
    Reg#(Bit#(32)) upcounter <- mkReg(0);

    rule upcount;
        upcounter <= upcounter + 1;
    endrule

    let timer = upcounter[24:19];

    interface Put request;
        method Action put(Coordinates#(4) c);
            fifoReq.enq(c);
        endmethod
    endinterface
    interface Get response;
        method ActionValue#(PixelData) get;
            fifoReq.deq;
            let r = fifoReq.first;
            return PixelData { r: zeroExtend((r.x + timer) ^ r.y) << 2
                             , b: zeroExtend(r.x ^ (r.y + timer)) << 2
                             , g: 0
                             };
        endmethod
    endinterface
endmodule


interface Top;
    (* always_enabled *)
    method Bit#(1) led;

    (* always_enabled *)
    method Bit#(1) hub75_a;
    (* always_enabled *)
    method Bit#(1) hub75_b;
    (* always_enabled *)
    method Bit#(1) hub75_c;
    (* always_enabled *)
    method Bit#(1) hub75_d;

    (* always_enabled *)
    method Bit#(1) hub75_clk;
    (* always_enabled *)
    method Bit#(1) hub75_lat;
    (* always_enabled *)
    method Bit#(1) hub75_oe;

    (* always_enabled *)
    method Bit#(1) hub75_j5_r0;
    (* always_enabled *)
    method Bit#(1) hub75_j5_g0;
    (* always_enabled *)
    method Bit#(1) hub75_j5_b0;
    (* always_enabled *)
    method Bit#(1) hub75_j5_r1;
    (* always_enabled *)
    method Bit#(1) hub75_j5_g1;
    (* always_enabled *)
    method Bit#(1) hub75_j5_b1;
    (* always_enabled *)
    method Bit#(1) hub75_j6_r0;
    (* always_enabled *)
    method Bit#(1) hub75_j6_g0;
    (* always_enabled *)
    method Bit#(1) hub75_j6_b0;
    (* always_enabled *)
    method Bit#(1) hub75_j6_r1;
    (* always_enabled *)
    method Bit#(1) hub75_j6_g1;
    (* always_enabled *)
    method Bit#(1) hub75_j6_b1;
endinterface

(* synthesize, default_clock_osc="clk_25mhz", default_reset="btn_user" *)
module mkTop (Top);
    GSR gsr <- mkGSR;
    Reg#(Bit#(25)) upcounter <- mkReg(0);
    Reg#(Bool) ledval <- mkReg(False);

    Hub75#(4) hub75 <- mkHub75;
    let patternGen <- mkPatternGen;

    mkConnection(hub75.pixel_data, patternGen);

    rule upcount;
        if (upcounter == 25000000) begin
            upcounter <= 0;
            ledval <= !ledval;
        end else begin
            upcounter <= upcounter + 1;
        end
    endrule

    method led = pack(ledval);

    method hub75_clk = hub75.port.clk;
    method hub75_lat = hub75.port.latch;
    method hub75_oe = hub75.port.oe;
    method hub75_j5_r0 = hub75.port.lines[0].r;
    method hub75_j5_g0 = hub75.port.lines[0].g;
    method hub75_j5_b0 = hub75.port.lines[0].b;
    method hub75_j5_r1 = hub75.port.lines[1].r;
    method hub75_j5_g1 = hub75.port.lines[1].g;
    method hub75_j5_b1 = hub75.port.lines[1].b;
    method hub75_j6_r0 = hub75.port.lines[2].r;
    method hub75_j6_g0 = hub75.port.lines[2].g;
    method hub75_j6_b0 = hub75.port.lines[2].b;
    method hub75_j6_r1 = hub75.port.lines[3].r;
    method hub75_j6_g1 = hub75.port.lines[3].g;
    method hub75_j6_b1 = hub75.port.lines[3].b;
    method hub75_a = hub75.port.bank[0];
    method hub75_b = hub75.port.bank[1];
    method hub75_c = hub75.port.bank[2];
    method hub75_d = hub75.port.bank[3];
endmodule

endpackage
