// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2022 Sergiusz Bazanski

package WishboneCrossbar;

import ClientServer :: *;
import GetPut :: *;
import FIFO :: *;
import SpecialFIFOs :: *;
import Vector :: *;
import Wishbone :: *;

interface Crossbar#( numeric type upstreamNum
                   , numeric type downstreamNum
                   , numeric type datSize
                   , numeric type adrSize
                   , numeric type selSize
                   );
    interface Vector#(upstreamNum, Wishbone::Slave#(datSize, adrSize, selSize)) upstreams;
    interface Vector#(downstreamNum, Wishbone::Master#(datSize, adrSize, selSize)) downstreams;
endinterface

typedef struct {
    Bit#(TLog#(downstreamNum)) downstream;
    Bit#(adrSize) address;
} DecodedAddr#(numeric type downstreamNum, numeric type adrSize) deriving (Bits);

module mkCrossbar#(function Maybe#(DecodedAddr#(downstreamNumer, adrSize)) decoder(Bit#(adrSize) addr))
                 (Crossbar#(upstreamNum, downstreamNum, datSize, adrSize, selSize));

    Vector#(upstreamNum, Wishbone::SlaveConnector#(datSize, adrSize, selSize)) upstreamConnectors <- replicateM(mkAsyncSlaveConnector);
    Vector#(downstreamNum, Wishbone::MasterConnector#(datSize, adrSize, selSize)) downstreamConnectors <- replicateM(mkMasterConnector);

    Vector#(upstreamNum, FIFO#(Wishbone::SlaveRequest#(datSize, adrSize, selSize))) upstreamRequests <- replicateM(mkBypassFIFO);
    Vector#(downstreamNum, FIFO#(Bit#(TLog#(upstreamNum)))) downstreamPending <- replicateM(mkBypassFIFO);

    function Bool canRoute(Integer u, Integer d);
        let req = upstreamRequests[u].first;
        let route = decoder(req.address);
        return case (route) matches
            tagged Invalid: False;
            tagged Valid .a: (a.downstream == fromInteger(d));
        endcase;
    endfunction

    for (Integer u = 0; u < valueOf(upstreamNum); u = u + 1) begin
        rule request_handle;
            let req <- upstreamConnectors[u].client.request.get();
            upstreamRequests[u].enq(req);
            //$display("Crossbar: req %02d -> ?", u);
        endrule

        for (Integer d = 0; d < valueOf(downstreamNum); d = d + 1) begin
            rule request_route(canRoute(u, d));
                let req = upstreamRequests[u].first;
                let route = decoder(req.address);
                case (route) matches
                    tagged Invalid: begin end
                    tagged Valid .a: begin
                        req.address = a.address;
                    end
                endcase
                upstreamRequests[u].deq();
                downstreamConnectors[d].server.request.put(req);
                downstreamPending[d].enq(fromInteger(u));
                //$display("Crossbar: req %02d -> %02d", u, d);
            endrule
        end
    end

    for (Integer d = 0; d < valueOf(downstreamNum); d = d + 1) begin
        for (Integer u = 0; u < valueOf(upstreamNum); u = u + 1) begin
            rule response_route(downstreamPending[d].first == fromInteger(u));
                let res <- downstreamConnectors[d].server.response.get();
                downstreamPending[d].deq();
                //$display("Crossbar: res %02d <- %02d", u, d);
                upstreamConnectors[u].client.response.put(res);
            endrule
        end
    end

    function Wishbone::Slave#(datSize, adrSize, selSize) getUpstream(Integer j);
        return upstreamConnectors[j].slave;
    endfunction

    function Wishbone::Master#(datSize, adrSize, selSize) getDownstream(Integer j);
        return downstreamConnectors[j].master;
    endfunction

    interface upstreams   = genWith(getUpstream);
    interface downstreams = genWith(getDownstream);
endmodule
endpackage
