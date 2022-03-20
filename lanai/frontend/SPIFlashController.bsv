package SPIFlashController;

import Assert :: *;
import Connectable :: *;
import Vector :: *;
import StmtFSM :: *;
import FIFO :: *;
import SpecialFIFOs :: *;
import ClientServer :: *;
import GetPut :: *;
import Probe :: *;

import Wishbone :: *;
import WishboneSPI :: *;

typedef struct {
    Bit#(ways) lruPre;
    Bit#(ways) lruPost;
    Bit#(width) history;
} LRUCacheOutput#(numeric type ways, numeric type width) deriving (Bits);

interface LRUCacheController#(numeric type ways);
    method LRUCacheOutput#(ways, n) poke(Bit#(n) current, Bit#(ways) access) provisos (Div#(TMul#(ways, TSub#(ways, 1)), 2, n));
endinterface

function Action doRead(Wishbone::MasterConnector#(32, 8, 4) master, Bit#(8) addr);
    return action
        master.server.request.put(SlaveRequest { address: addr
                                               , writeData: tagged Invalid
                                               , select: 4'b1111
                                               });
    endaction;
endfunction

function Action doWrite(Wishbone::MasterConnector#(32, 8, 4) master, Bit#(8) addr, Bit#(32) data);
    return action
        master.server.request.put(SlaveRequest { address: addr
                                               , writeData: tagged Valid data
                                               , select: 4'b1111
                                               });
    endaction;
endfunction

function Action eatResponse(Wishbone::MasterConnector#(32, 8, 4) master);
    action
        let _ <- master.server.response.get();
    endaction
endfunction

function Action getResponse(Wishbone::MasterConnector#(32, 8, 4) master, Reg#(Bit#(32)) data);
    action
        let d <- master.server.response.get();
        data <= fromMaybe(0, d.readData);
    endaction
endfunction

function Stmt waitDoneSending(Wishbone::MasterConnector#(32, 8, 4) master, Reg#(Bit#(32)) tmp);
    return seq
        noAction; noAction;
        doRead(master, 8);
        getResponse(master, tmp);
        //$display("WDS1 %x", tmp);
        while (tmp[7] == 1) seq
            doRead(master, 8);
            getResponse(master, tmp);
            //$display("WDS2 %x", tmp);
        endseq
    endseq;
endfunction

function Stmt waitCanSend(Wishbone::MasterConnector#(32, 8, 4) master, Reg#(Bit#(32)) tmp);
    return seq
        noAction; noAction;
        doRead(master, 8);
        getResponse(master, tmp);
        while (tmp[1] == 0) seq
            doRead(master, 8);
            getResponse(master, tmp);
        endseq
    endseq;
endfunction

function Stmt waitRBNE(Wishbone::MasterConnector#(32, 8, 4) master, Reg#(Bit#(32)) tmp);
    return seq
        doRead(master, 8);
        getResponse(master, tmp);
        while (tmp[0] == 0) seq
            doRead(master, 8);
            getResponse(master, tmp);
        endseq
    endseq;
endfunction

// Algorithm borrowed from openrisc mor1kx_cache_lru.v.
module mkLRUCacheController(LRUCacheController#(ways));
    method LRUCacheOutput#(ways, n) poke(Bit#(n) current, Bit#(ways) access);
        Vector#(ways, Vector#(ways, Bool)) expand = replicate(replicate(False));
        LRUCacheOutput#(ways, n) res = LRUCacheOutput { lruPost: 0
                                                      , lruPre: 0
                                                      , history: 0
                                                      };

        Integer offset = 0;
        for (Integer i = 0; i < valueOf(ways); i = i + 1) begin
            expand[i][i] = True;
            for (Integer j = i + 1; j < valueOf(ways); j = j + 1) begin
                expand[i][j] = unpack(current[offset+j-i-1]);
            end
            for (Integer j = 0; j < i; j = j + 1) begin
                expand[i][j] = !expand[j][i];
            end
            offset = offset + valueOf(ways) - i - 1;
        end
        for (Integer i = 0; i < valueOf(ways); i = i + 1) begin
            res.lruPre[i] = pack(foldl(\&& , True, expand[i]));
        end
        for (Integer i = 0; i < valueOf(ways); i = i + 1) begin
            if (access[i] != 0) begin
                for (Integer j = 0; j < valueOf(ways); j = j + 1) begin
                    if (i != j) begin
                        expand[i][j] = False;
                    end
                end
                for (Integer j = 0; j < valueOf(ways); j = j + 1) begin
                    if (i != j) begin
                        expand[j][i] = True;
                    end
                end
            end
        end
        offset = 0;
        for (Integer i = 0; i < valueOf(ways); i = i + 1) begin
            for (Integer j = i + 1; j < valueOf(ways); j = j + 1) begin
                res.history[offset+j-i-1] = pack(expand[i][j]);
            end
            offset = offset + valueOf(ways) - i - 1;
        end
        for (Integer i = 0; i < valueOf(ways); i = i + 1) begin
            res.lruPost[i] = pack(foldl(\&& , True, expand[i]));
        end

        return res;
    endmethod
endmodule

function Bit#(k) oneHotDecode(Bit#(n) v) provisos (Log#(n, k));
    Bit#(k) res = 0;
    for (Integer i = 0; i < valueOf(n); i = i + 1) begin
        if (v[i] == 1) begin
            res = fromInteger(i);
        end
    end
    return res;
endfunction

interface SPIFlashController#(numeric type cacheWays, numeric type cacheWidth);
    interface WishboneSPI::Master spi;
    (* always_ready, result="spi_csb" *)
    method Bit#(1) csb;

    interface Server#(Bit#(32), Bit#(32)) serverA;
    interface Server#(Bit#(32), Bit#(32)) serverB;
endinterface

typedef struct {
    Bit#(TSub#(32, TLog#(cacheWidth))) tag;
    Vector#(cacheWidth, Bit#(8)) data;
} CacheEntry#(numeric type cacheWidth) deriving (Bits, FShow);

module mkSPIFlashController(SPIFlashController#(cacheWays, cacheWidth)) provisos (Log#(cacheWidth, shift));

    Vector#(cacheWays, Reg#(Maybe#(CacheEntry#(cacheWidth)))) cache;
    for (Integer i = 0; i < valueOf(cacheWays); i = i + 1) begin
        cache[i] <- mkReg(tagged Invalid);
    end

    Reg#(Bit#(TDiv#(TMul#(cacheWays, TSub#(cacheWays, 1)), 2))) cacheHistory <- mkReg(0);
    Reg#(Bit#(TLog#(cacheWays))) cacheLRU <- mkReg(0);
    Reg#(Bit#(cacheWays)) cacheFetchLock <- mkReg(0);

Vector#(2, LRUCacheController#(cacheWays)) cacheController <- replicateM(mkLRUCacheController);
Vector#(2, Reg#(Maybe#(Bit#(cacheWays)))) update <- replicateM(mkDWire(tagged Invalid));

    WishboneSPI::SPIController#(8) spiCtrl <- mkSPIController;
    Wishbone::MasterConnector#(32, 8, 4) spiMaster <- mkMasterConnector;
    mkConnection(spiCtrl.slave, spiMaster.master);

    rule updateHistory;
        Bit#(TDiv#(TMul#(cacheWays, TSub#(cacheWays, 1)), 2)) nextHistory = cacheHistory;
        Bit#(TLog#(cacheWays)) nextLRU = cacheLRU;
        for (Integer i = 0; i < 2 ; i = i + 1) begin
            if (update[i] matches tagged Valid .u) begin
                let res = cacheController[i].poke(nextHistory, u);
                nextHistory = res.history;
                nextLRU = oneHotDecode(res.lruPost);
            end
        end
        cacheHistory <= nextHistory;
        if (cacheLRU != nextLRU) begin
            $display("CACHE: LRU %d -> %d", cacheLRU, nextLRU);
        end
        cacheLRU <= nextLRU;
    endrule

    Vector#(2, FIFO#(Bit#(32))) fifoRequest <- replicateM(mkBypassFIFO);

    Vector#(2, FIFO#(Bit#(32))) fifoResponse <- replicateM(mkPipelineFIFO);
    FIFO#(Tuple2#(Bit#(TLog#(cacheWays)), Bit#(32))) fifoFetchPending <- mkPipelineFIFO;
    FIFO#(Bit#(32)) fifoFetching <- mkPipelineFIFO;

    Vector#(2, Reg#(Maybe#(Tuple2#(Bit#(TLog#(cacheWays)), CacheEntry#(cacheWidth))))) cacheWayForRequest <- replicateM(mkDWire(tagged Invalid));
    for (Integer i = 0; i < 2; i = i + 1) begin
        rule findRequest;
            let pending = fifoRequest[i].first;
            Bit#(TSub#(32, shift)) tag = pending[31:valueOf(shift)];
            //$display("WANT TAG: %x", tag);
            Maybe#(Tuple2#(Bit#(TLog#(cacheWays)), CacheEntry#(cacheWidth))) res = tagged Invalid;
            for (Integer line = 0; line < valueOf(cacheWays); line = line + 1) begin
                if (cache[line] matches tagged Valid .e &&& e.tag == tag) begin
                    res = tagged Valid tuple2(fromInteger(line), e);
                end
            end
            cacheWayForRequest[i] <= res;
            case (res) matches
                tagged Valid .r: $display("CWFR[%0d]: ", i, fshow(r));
            endcase
        endrule

        rule respondWithData (cacheWayForRequest[i] matches tagged Valid .t);
            let {line, e} = t;
            let pending = fifoRequest[i].first();
            fifoRequest[i].deq();
    
            Bit#(shift) wo = pending[valueOf(shift)-1:0];
            Bit#(32) res = { e.data[wo], e.data[wo+1], e.data[wo+2], e.data[wo+3] };
            fifoResponse[i].enq(res);
    
            Bit#(cacheWays) updateOH = 0;
            updateOH[line] = 1;
            update[i] <= tagged Valid updateOH;
    
            $display("CACHE[%0d][%x]: hit at %d (%x): %x", i, fifoRequest[i].first, line, e.tag << valueOf(shift), res);
        endrule

        rule queueFetch(cacheWayForRequest[i] matches tagged Invalid);
            let req = fifoRequest[i].first;
            Bit#(32) page = req[31:valueOf(shift)] << valueOf(shift);
            let line = cacheLRU;
            if (cacheFetchLock[line] == 1) begin
                // TODO(q3k): don't lock up here, find a way to re-do with a different cache line.
                $display("CACHE[%0d][%x]: miss, fetching %x into %d ABORTED, CACHE LOCK CONTENTION", i, req, page, line);
                // Although the poke here should unlock us at next cycle.
                Bit#(cacheWays) updateOH = 0;
                updateOH[line] = 1;
                update[i] <= tagged Valid updateOH;
            end else begin
                $display("CACHE[%0d][%x]: miss, fetching %x into %d", i, req, page, line);
                fifoFetchPending.enq(tuple2(line, page));
                cacheFetchLock[line] <= 1;
            end
        endrule
    end


    Reg#(Bit#(32)) fetchPage <- mkReg(0);
    Reg#(Bit#(TLog#(cacheWays))) fetchLine <- mkReg(0);

    Reg#(Bit#(32)) v <- mkReg(0);
    Reg#(Bit#(TSub#(32, shift))) byteNo <- mkReg(0);
    Reg#(Vector#(cacheWidth, Bit#(8))) fetchReg <- mkReg(replicate(0));
    Reg#(Bool) csbReg <- mkReg(True);
    FSM fetcher <- mkFSM(seq
        csbReg <= False;
        // CPOL = 0, CPHA = 0
        doWrite(spiMaster, 0, 'b1_001_1_00);
        eatResponse(spiMaster);

        // Read (0x03)
        waitCanSend(spiMaster, v);
        doWrite(spiMaster, 'hc, 'h03);
        eatResponse(spiMaster);

        // Address

        waitCanSend(spiMaster, v);
        noAction; noAction;
        doWrite(spiMaster, 'hc, zeroExtend(fetchPage[23:16]));
        eatResponse(spiMaster);

        waitCanSend(spiMaster, v);
        noAction; noAction;
        doWrite(spiMaster, 'hc, zeroExtend(fetchPage[15:8]));
        eatResponse(spiMaster);

        waitCanSend(spiMaster, v);
        noAction; noAction;
        doWrite(spiMaster, 'hc, zeroExtend(fetchPage[7:0]));
        eatResponse(spiMaster);

        for (byteNo <= 0; byteNo < fromInteger(valueOf(cacheWidth)); byteNo <= byteNo + 1) seq
            waitCanSend(spiMaster, v);
            doWrite(spiMaster, 'hc, 32'hff);
            eatResponse(spiMaster);

            waitCanSend(spiMaster, v);
            waitRBNE(spiMaster, v);
            doRead(spiMaster, 'hc);
            getResponse(spiMaster, v);
            //$display("FETCHER: SPI READ %x -> %x", fetchPage+zeroExtend(byteNo), v[7:0]);
            fetchReg[byteNo] <= v[7:0];
        endseq

        action
            let { line, page } = fifoFetchPending.first;

            Bit#(TSub#(32, shift)) tag = page[31:valueOf(shift)];
            cache[line] <= tagged Valid CacheEntry { tag: tag, data: fetchReg };
            $display("FETCHER: page %x done, data: %x, saving into %d with tag %x", page, fetchReg, line, tag);
        endaction

        waitDoneSending(spiMaster, v);

        csbReg <= True;
    endseq);

    rule startFetch;
        let { line, page } = fifoFetchPending.first;
        $display("FETCHER: page %x start", page);
        fetchPage <= page;
        fetchLine <= line;
        fetcher.start();
        fifoFetching.enq(page);
    endrule

    rule endFetch;
        fetcher.waitTillDone();
        fifoFetching.deq;

        let { line, page } = fifoFetchPending.first;
        fifoFetchPending.deq;
        $display("FETCHER: page %x FSM done", page);
        cacheFetchLock[line] <= 0;
    endrule

    let probeCsb <- mkProbe;
    rule updateProbes;
        probeCsb <= csbReg;
    endrule

    interface Server serverA;
        interface request = fifoToPut(fifoRequest[0]);
        interface response = fifoToGet(fifoResponse[0]);
    endinterface

    interface Server serverB;
        interface request = fifoToPut(fifoRequest[1]);
        interface response = fifoToGet(fifoResponse[1]);
    endinterface

    method csb = pack(csbReg);
    interface spi = spiCtrl.spiMaster;
endmodule

(* synthesize *)
module mkTbFlashController(Empty);
    SPIFlashController#(16, 16) dut <- mkSPIFlashController;

    Reg#(Bit#(32)) i <- mkReg(0);
    Reg#(Bit#(160)) shiftIn <- mkReg(0);
    Reg#(Bit#(160)) shiftOut <- mkReg('h00_000000_deadbeefc0def00dcafedead42421337);
    Reg#(Bit#(32)) bitNo <- mkReg(0);

    rule stuffMiso;
        dut.spi.miso(unpack(shiftOut[159-bitNo]));
    endrule

    Reg#(Bit#(32)) timeout <- mkReg(0);
    rule runTimeout;
        timeout <= timeout + 1;
        dynamicAssert(timeout < 5000, "TIMEOUT");
    endrule

    Stmt test = par
        // Frontend.
        seq
            par
                par
                    seq
                        dut.serverA.request.put(2138);
                        dut.serverA.request.put(1330);
                        dut.serverA.request.put(4242);
                    endseq
                    dut.serverB.request.put(2134);
                endpar
                par
                    seq
                        action
                            let res <- dut.serverA.response.get();
                            $display("TEST: RESULT A: %x", res);
                        endaction
                        action
                            let res <- dut.serverA.response.get();
                            $display("TEST: RESULT C: %x", res);
                        endaction
                        action
                            let res <- dut.serverA.response.get();
                            $display("TEST: RESULT D: %x", res);
                        endaction
                    endseq
                    action
                        let res <- dut.serverB.response.get();
                        $display("TEST: RESULT B: %x", res);
                    endaction
                endpar
            endpar

            while (bitNo != 160) seq
                noAction;
            endseq
            $display("TEST: shiftIn: %x", shiftIn);
            dynamicAssert(shiftIn[159:152] == 3, "expected READ command");
            dynamicAssert(shiftIn[151:128] == 'h850, "expected correct address");
        endseq

        // Backend/model.
        seq
            while (dut.csb == 1) seq
                noAction;
            endseq
            while (bitNo != 160) seq
                while (dut.spi.sclk == 0) seq
                    noAction;
                endseq
                shiftIn[159-bitNo] <= dut.spi.mosi;
                bitNo <= bitNo+1;
                while (dut.spi.sclk == 1) seq
                    noAction;
                endseq
            endseq
        endseq
    endpar;
    mkAutoFSM(test);
endmodule

endpackage
