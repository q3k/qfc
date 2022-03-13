package TbCrossbar;

import Assert :: *;
import ClientServer :: *;
import Connectable :: *;
import GetPut :: *;
import StmtFSM :: *;
import Vector :: *;

import Wishbone :: *;
import WishboneCrossbar :: *;

function Maybe#(WishboneCrossbar::DecodedAddr#(4, 32)) decoder(Bit#(32) addr);
    return case (addr) matches
        32'h0???_????: tagged Valid DecodedAddr { downstream: 0, address: addr & 32'hffff };
        32'h2???_????: tagged Valid DecodedAddr { downstream: 1, address: addr & 32'hffff };
        32'h4???_????: tagged Valid DecodedAddr { downstream: 2, address: addr & 32'hffff };
        32'h8???_????: tagged Valid DecodedAddr { downstream: 3, address: addr & 32'hffff };
    endcase;
endfunction

(* synthesize *)
module mkTbCrossbar(Empty);
    Vector#(4, Wishbone::MasterConnector#(32, 32, 4)) masters <- replicateM(mkMasterConnector);
    Vector#(4, Wishbone::SlaveConnector#(32, 32, 4)) slaves <- replicateM(mkAsyncSlaveConnector);

    WishboneCrossbar::Crossbar#(4, 4, 32, 32, 4) crossbar <- mkCrossbar(decoder);

    for (Integer j = 0; j < 4; j = j + 1) begin
        mkConnection(masters[j].master, crossbar.upstreams[j]);
    end
    for (Integer k = 0; k < 4; k = k + 1) begin
        mkConnection(slaves[k].slave, crossbar.downstreams[k]);
    end

    for (Integer k = 0; k < 4; k = k + 1) begin
        rule respond;
            let req <- slaves[k].client.request.get();
            let res = SlaveResponse { readData: tagged Valid req.address };
            slaves[k].client.response.put(res);
        endrule
    end

    Reg#(Bit#(32)) i <- mkReg(0);
    Stmt test = seq
        par
            masters[0].server.request.put(SlaveRequest { address: 32'h0000_1337
                                                       , writeData: tagged Invalid
                                                       , select: 4'b1111
                                                       });
            masters[1].server.request.put(SlaveRequest { address: 32'h8000_cafe
                                                       , writeData: tagged Invalid
                                                       , select: 4'b1111
                                                       });
            masters[2].server.request.put(SlaveRequest { address: 32'h8000_dead
                                                       , writeData: tagged Invalid
                                                       , select: 4'b1111
                                                       });
        endpar
        par
            action
                let res <- masters[0].server.response.get();
                dynamicAssert(fromMaybe(0, res.readData) == 'h1337, "wanted 0x1337");
            endaction
            action
                let res <- masters[1].server.response.get();
                dynamicAssert(fromMaybe(0, res.readData) == 'hcafe, "wanted 0xcafe");
            endaction
            action
                let res <- masters[2].server.response.get();
                dynamicAssert(fromMaybe(0, res.readData) == 'hdead, "wanted 0xdead");
            endaction
        endpar
    endseq;
    mkAutoFSM(test);
endmodule

endpackage
