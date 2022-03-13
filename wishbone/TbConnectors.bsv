package TbConnectors;

import Assert :: *;
import StmtFSM :: *;
import Connectable :: *;
import ClientServer :: *;
import GetPut :: *;

import Wishbone :: *;

function Action doRead(Wishbone::MasterConnector#(32, 24, 4) master, Bit#(24) addr);
    return action
        master.server.request.put(SlaveRequest { address: addr
                                               , writeData: tagged Invalid
                                               , select: 4'b1111
                                               });
    endaction;
endfunction

function Action doWrite(Wishbone::MasterConnector#(32, 24, 4) master, Bit#(24) addr, Bit#(32) data);
    return action
        master.server.request.put(SlaveRequest { address: addr
                                               , writeData: tagged Valid data
                                               , select: 4'b1111
                                               });
    endaction;
endfunction

function Action expectResponse(Wishbone::MasterConnector#(32, 24, 4) master, Bit#(32) want, String msg);
    return action
             let r <- master.server.response.get();
             let v = fromMaybe(0, r.readData);
             if (v != want) begin
                 $display("wanted %x, got %x", want, v);
             end
             dynamicAssert(v == want, msg);
    endaction;
endfunction

(* synthesize *)
module mkTbConnectors(Empty);
    Wishbone::SlaveConnector#(32, 24, 4) slave <- mkAsyncSlaveConnector;
    Wishbone::MasterConnector#(32, 24, 4) master <- mkMasterConnector;

    mkConnection(slave.slave, master.master);

    Reg#(Bit#(32)) slaveReg <- mkReg(0);
    Reg#(Bit#(32)) delay <- mkReg(0);
    
    rule delayDown (delay > 0);
        delay <= delay - 1;
    endrule
    rule slaveResponder (delay == 0);
        let req <- slave.client.request.get();
        let resp = SlaveResponse { readData: tagged Valid 32'hdeadbeef };
        if (req.address == 1337) begin
            case (req.writeData) matches
                tagged Invalid:
                    resp.readData = tagged Valid slaveReg;
                tagged Valid .wr: begin
                    slaveReg <= wr;
                end
            endcase
        end else begin
            resp.readData = tagged Valid 32'hdeadbeef;
            delay <= zeroExtend(req.address);
        end
        slave.client.response.put(resp);
    endrule

    Reg#(Bit#(32)) i <- mkReg(0);
    Stmt test = seq
        doRead(master, 0);
        expectResponse(master, 32'hdeadbeef, "wanted deadbeef");

        doRead(master, 1337);
        expectResponse(master, 0, "wanted 0");
        doWrite(master, 1337, 10);
        expectResponse(master, 0, "wanted 0");
        doRead(master, 1337);
        expectResponse(master, 10, "wanted 10");

        doRead(master, 5);
        expectResponse(master, 32'hdeadbeef, "wanted deadbeef");
        doRead(master, 5);
        expectResponse(master, 32'hdeadbeef, "wanted deadbeef");
        doRead(master, 0);
        expectResponse(master, 32'hdeadbeef, "wanted deadbeef");

        doRead(master, 0);
        par
            expectResponse(master, 32'hdeadbeef, "wanted deadbeef");
            doRead(master, 1337);
        endpar
        expectResponse(master, 10, "wanted 10");

        for (i <= 0; i < 12; i <= i + 1) seq
            noAction;
        endseq
    endseq;
    mkAutoFSM(test);
endmodule

endpackage
