package TbCrossbar;

import ClientServer :: *;
import Connectable :: *;
import GetPut :: *;
import StmtFSM :: *;
import Vector :: *;

import Wishbone :: *;
import WishboneCrossbar :: *;

function Maybe#(WishboneCrossbar::DecodedAddr#(4, 32)) decoder(Bit#(32) addr);
    return case (addr) matches
        32'h0???_????: tagged Valid DecodedAddr { downstream: 0, address: addr };
        32'h2???_????: tagged Valid DecodedAddr { downstream: 1, address: addr };
        32'h4???_????: tagged Valid DecodedAddr { downstream: 2, address: addr };
        32'h8???_????: tagged Valid DecodedAddr { downstream: 3, address: addr };
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
        masters[0].server.request.put(SlaveRequest { address: 0
                                                   , writeData: tagged Invalid
                                                   , select: 4'b1111
                                                   });
        for (i <= 0; i < 12; i <= i + 1) seq
            noAction;
        endseq
    endseq;
    mkAutoFSM(test);
endmodule

endpackage
