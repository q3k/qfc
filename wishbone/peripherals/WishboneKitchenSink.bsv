// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2022 Sergiusz Bazanski

package WishboneKitchenSink;

import Assert :: *;
import ClientServer :: *;
import Connectable :: *;
import FIFO :: *;
import GetPut :: *;
import Probe :: *;
import SpecialFIFOs :: *;
import StmtFSM :: *;
import Wishbone :: *;

interface KitchenSinkController#(numeric type wbAddr);
    interface Wishbone::Slave#(32, wbAddr, 4) slave;
endinterface

module mkKitchenSinkController(KitchenSinkController#(wbAddr));
    Wishbone::SlaveConnector#(32, wbAddr, 4) bus <- mkSyncSlaveConnector;

    Reg#(Bit#(32)) upcounter <- mkReg(0);
    rule upcount;
        upcounter <= upcounter + 1;
    endrule

    rule wbRequest;
        let r <- bus.client.request.get();
        let resp = SlaveResponse { readData: tagged Invalid };
        $display("KSC: wb request", fshow(r));

        case (r.address) matches
            'h0: begin
                resp.readData = tagged Valid upcounter;
            end
            'h4: begin
                // '105c'
                resp.readData = tagged Valid 32'h31303563;
            end
            'h8: begin
                // 'q3k '
                resp.readData = tagged Valid 32'h71336b20;
            end
            'hc: begin
                // '2022'
                resp.readData = tagged Valid 32'h32303232;
            end
        endcase
        bus.client.response.put(resp);
    endrule

    interface slave = bus.slave;
endmodule


function Action doRead(Wishbone::MasterConnector#(32, 32, 4) master, Bit#(32) addr);
    return action
        master.server.request.put(SlaveRequest { address: addr
                                               , writeData: tagged Invalid
                                               , select: 4'b1111
                                               });
    endaction;
endfunction

function Action doWrite(Wishbone::MasterConnector#(32, 32, 4) master, Bit#(32) addr, Bit#(32) data);
    return action
        master.server.request.put(SlaveRequest { address: addr
                                               , writeData: tagged Valid data
                                               , select: 4'b1111
                                               });
    endaction;
endfunction

function Action eatResponse(Wishbone::MasterConnector#(32, 32, 4) master);
    action
        let _ <- master.server.response.get();
    endaction
endfunction

function Action getResponse(Wishbone::MasterConnector#(32, 32, 4) master, Reg#(Bit#(32)) data);
    action
        let d <- master.server.response.get();
        data <= fromMaybe(0, d.readData);
    endaction
endfunction

(* synthesize *)
module mkTbKitchenSink(Empty);
    Wishbone::MasterConnector#(32, 32, 4) master <- mkMasterConnector;
    KitchenSinkController#(32) controller <- mkKitchenSinkController;
    mkConnection(master.master, controller.slave);

    Reg#(Bit#(32)) tmp1 <- mkReg(0);
    Reg#(Bit#(32)) tmp2 <- mkReg(0);
    Stmt test = seq
        doRead(master, 0);
        getResponse(master, tmp1);
        doRead(master, 0);
        getResponse(master, tmp2);
        dynamicAssert(tmp2 > tmp1, "counter should be counting");

        doRead(master, 4);
        getResponse(master, tmp1);
        dynamicAssert(tmp1 == 32'h31303563, "magic value should be present");
    endseq;
    mkAutoFSM(test);
endmodule

endpackage
