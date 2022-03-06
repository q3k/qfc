package Wishbone;

// This package implements a Wishbone interface definition in Bluespec plus a
// few helpers:
//  - SlaveConnector, a simple Wishbone Classic connector that converts a
//    Wishbone interface into a Client issuing read/write requests and
//    expecting read/write response.
//  - CBus Bridge, which exposes a CBus as a Wishbone Classic Slave.
// 

import GetPut :: *;
import ClientServer :: *;
import FIFO :: *;
import SpecialFIFOs :: *;
import Connectable :: *;
import CBus :: *;
import Probe :: *;

interface Slave#( numeric type datSize
                , numeric type adrSize
                , numeric type selSize
                );

    (* always_ready, always_enabled, prefix = "" *)
    method Action request((* port="cyc_i" *) Bool cyc
                         ,(* port="stb_i" *) Bool stb
                         ,(* port="adr_i" *) Bit#(adrSize) adr
                         ,(* port="dat_i" *) Bit#(datSize) dat
                         ,(* port="sel_i" *) Bit#(selSize) sel
                         ,(* port="we_i"  *) Bool we
                         );

    (* always_ready, result="ack_o" *)
    method Bool ack;
    (* always_ready, result="err_o" *)
    method Bool err;
    (* always_ready, result="rty_o" *)
    method Bool rty;
    (* always_ready, result="dat_o" *)
    method Bit#(datSize) dat;
endinterface

typedef struct {
    Bit#(adrSize) address;
    Maybe#(Bit#(datSize)) writeData;
    Bit#(selSize) select;
} SlaveRequest#( numeric type datSize
               , numeric type adrSize
               , numeric type selSize
               )
deriving (Bits);

typedef struct {
    Maybe#(Bit#(datSize)) readData;
} SlaveResponse#( numeric type datSize
                )
deriving (Bits, FShow);

interface SlaveConnector#( numeric type datSize
                         , numeric type adrSize
                         , numeric type selSize
                         );
    interface Slave#(datSize, adrSize, selSize) slave;

    interface Client#(SlaveRequest#(datSize, adrSize, selSize), SlaveResponse#(datSize)) client;
endinterface

module mkSyncSlaveConnector (SlaveConnector#(datSize, adrSize, selSize));
    let inner <- mkSlaveConnector(True);
    return inner;
endmodule

module mkSlaveConnector#(Bool sync) (SlaveConnector#(datSize, adrSize, selSize));
    FIFO#(SlaveRequest#(datSize, adrSize, selSize)) fReq;
    if (sync) begin
        fReq <- mkPipelineFIFO;
    end else begin
        fReq <- mkBypassFIFO;
    end
    FIFO#(SlaveResponse#(datSize)) fRes <- mkBypassFIFO;

    Reg#(SlaveRequest#(datSize, adrSize, selSize)) incoming <- mkWire;
    Reg#(Maybe#(SlaveResponse#(datSize))) outgoing <- mkDWire(tagged Invalid);

    let probeCyc <- mkProbe;
    let probeStb <- mkProbe;
    let probeAdr <- mkProbe;
    let probeSel <- mkProbe;
    let probeWe <- mkProbe;
    let probeDataIn <- mkProbe;
    let probeDataOut <- mkProbe;
    let probeAck <- mkProbe;

    rule process_incoming;
        fReq.enq(incoming);
    endrule

    rule process_outgoing;
        fRes.deq();
        outgoing <= tagged Valid fRes.first();
    endrule

    rule other_probes;
        probeDataOut <= case (outgoing) matches
            tagged Invalid: 0;
            tagged Valid .sr: fromMaybe(0, sr.readData);
        endcase;
        probeAck <= isValid(outgoing);
    endrule

    interface Slave slave;
        method Action request( Bool cyc
                             , Bool stb
                             , Bit#(adrSize) adr
                             , Bit#(datSize) dat
                             , Bit#(selSize) sel
                             , Bool we
                             );
            probeCyc <= cyc;
            probeStb <= stb;
            probeAdr <= adr;
            probeDataIn <= dat;
            probeSel <= sel;
            probeWe <= we;

            let stall = False;
            if (sync) begin
                stall = isValid(outgoing);
            end

            if (cyc && stb && !stall) begin
                if (we) begin
                    incoming <= SlaveRequest { address: adr
                                            , writeData: tagged Valid dat
                                            , select: sel
                                            };
                end else begin
                    incoming <= SlaveRequest { address: adr
                                            , writeData: tagged Invalid
                                            , select: sel
                                            };
                end
            end
        endmethod
        method ack = isValid(outgoing);
        method dat = case (outgoing) matches
            tagged Invalid: 0;
            tagged Valid .sr: fromMaybe(0, sr.readData);
        endcase;
        method err = False;
        method rty = False;
    endinterface

    interface Client client;
        interface Get request = fifoToGet(fReq);
        interface Put response = fifoToPut(fRes);
    endinterface
endmodule

// zeroSel zeroes out a value based on a given 'sel' value. Bits of the
// incoming value corresponding to a zero in sel get zeroes out.
function Bit#(a) zeroSel(Bit#(s) sel, Bit#(a) data) provisos (Mul#(s, n, a));
    Bit#(a) res = data;
    for (Integer i = 0; i < valueOf(s); i = i + 1) begin
        Integer bl = i * valueOf(n);
        Integer bh = bl + valueOf(n);
        if (sel[i] == 0) begin
            for (Integer j = bh; j < bh; j = j + 1) begin
                res[j] = 0;
            end
        end
    end
    return res;
endfunction

// mergeSel 'merges' two values based on a given 'sel' value. Bits
// corresponding to zero in sel get taken from 'a', corresponding to one get
// taken from 'b'.
function Bit#(d) mergeSel(Bit#(s) sel, Bit#(d) a, Bit#(d) b) provisos(Mul#(s, n, d));
    Bit#(a) res = 0;
    for (Integer i = 0; i < valueOf(s); i = i + 1) begin
        Integer bl = i * valueOf(n);
        Integer bh = bl + valueOf(n);
        for (Integer j = bl; j < bh; j = j + 1) begin
            if (sel[i] == 0) begin
                res[j] = a[j];
            end else begin
                res[j] = b[j];
            end
        end
    end
    return res;
endfunction


// Make a CBus to Wishbone Classic bridge.
module mkCBusBridge#( CBus#(saddr, sdata) cbus
                    ) (Slave#(sdata, saddr, 4))
                    provisos (Mul#(4, _, sdata));

    SlaveConnector#(sdata, saddr, 4) sconn <- mkSyncSlaveConnector;
    FIFO#(Tuple2#(Bit#(saddr), Bit#(sdata))) fWrite <- mkBypassFIFO;

    rule writeback;
        fWrite.deq();
        let tpl = fWrite.first();

        // The following split is load-bearing. It cascades into splitting up
        // the entire cbus address decoder mux into a ton of separate rules.
        // This is required to ensure that 'writeback' can actually fire when
        // some CBus addresses are currently unavailable (eg. when they are
        // taking a write in the core).
        //
        // I think this shouldn't be necessary as CBus registers have an
        // internal bypass wire which should technically drop writes from
        // inside the core if they conflict with a CBus write. But this doesn't
        // work if a rule inside a core does a read-then-write in a single
        // cycle.
        //
        // Is this a CBus bug?
        (* split *)
        cbus.write(tpl_1(tpl), tpl_2(tpl));
    endrule

    rule handle_request;
        SlaveRequest#(sdata, saddr, 4) req <- sconn.client.request.get;

        case (req.writeData) matches
            tagged Invalid: begin
                Bit#(sdata) data <- cbus.read(req.address);
                $display("CBusBridge: read: %x -> %x", req.address, data);
                data = zeroSel(req.select, data);
                sconn.client.response.put(SlaveResponse{ readData: tagged Valid data });
            end
            tagged Valid .data: begin

                Bit#(sdata) existing <- cbus.read(req.address);
                let dataNew = mergeSel(req.select, existing, data);
                $display("CBusBridge: write: %x <- %x (mergeSel(%x, %x, %x))", req.address, dataNew, req.select, existing, data);

                $display("CBusBridge: write: %x <- %x", req.address, dataNew);
                fWrite.enq(tuple2(req.address, dataNew));
                sconn.client.response.put(SlaveResponse{ readData: tagged Invalid });
            end
        endcase
    endrule

    return sconn.slave;
endmodule

endpackage