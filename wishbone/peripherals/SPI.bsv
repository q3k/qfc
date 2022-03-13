package SPI;

import Assert :: *;
import ClientServer :: *;
import Connectable :: *;
import FIFO :: *;
import GetPut :: *;
import Probe :: *;
import SpecialFIFOs :: *;
import StmtFSM :: *;
import Wishbone :: *;

interface Master;
    (* always_ready, result="sclk" *)
    method Bit#(1) sclk;
    (* always_ready, result="mosi" *)
    method Bit#(1) mosi;
    (* always_ready, always_enabled, prefix="" *)
    method Action miso((* port="miso" *) Bool value);
    (* always_ready, result="mosi_oe" *)
    method Bit#(1) mosiOe;
endinterface

interface Controller#(numeric type wbAddr);
    interface Wishbone::Slave#(32, wbAddr, 4) slave;
    interface Master spiMaster;
endinterface

typedef struct {
    // Clock phase selection:
    //  0: Capture the first data at the first clock transition
    //  1: Capture the first data at the second clock transition
    Bit#(1) ckph;
    // Clock polarity selection:
    //  0: CLK pin is pulled low when SPI is idle
    //  1: CLK pin is pulled high when SPI is idle
    Bit#(1) ckpl;
    // Master mode enable:
    //  0: Slave mode
    //  1: Master mode
    Bit#(1) mstmod;
    // Master clock prescaler selection:
    //  000: SYSCLK/2
    //  001: SYSCLK/4
    //  010: SYSCLK/8
    //  011: SYSCLK/16
    //  100: SYSCLK/32
    //  101: SYSCLK/64
    //  110: SYSCLK/128
    //  111: SYSCLK/256
    Bit#(3) psc;
    // SPI enable:
    //  0: SPI peripheral is disabled
    //  1: SPI peripheral is enabled
    Bit#(1) spien;
    // LSB first mode:
    //  0: Transmit MSB first
    //  1: Transmit LSB first
    Bit#(1) lf;
    // Data frame format:
    //  0: 8-bit data frame format
    //  1: 16-bit data frame format
    Bit#(1) ff16;
    // Bidirectional transmit output enable. When BDEN is set, this bit
    // determines the direction of transfer:
    //  0: Work in receive
    //  1: Work in transmit-only mode
    Bit#(1) bdoen;
    // Bidirectional enable:
    //  0: 2 line unidirectional transmit mode
    //  1: 1 line bidirectional transmit mode. The information transfers
    //     between the MOSI pin in master and the MISO pin in slave
    Bit#(1) bden;
} RegCtl0 deriving (FShow);

instance Bits#(RegCtl0, 32);
    function RegCtl0 unpack(Bit#(32) x);
        return RegCtl0 { ckph: x[0]
                       , ckpl: x[1]
                       , mstmod: x[2]
                       , psc: x[5:3]
                       , spien: x[6]
                       , lf: x[7]
                       , ff16: x[11]
                       , bdoen: x[14]
                       , bden: x[15]
                       };
    endfunction
    function Bit#(32) pack(RegCtl0 r);
        return { 16'b0
               , pack(r.bden)
               , pack(r.bdoen)
               , 2'b0
               , pack(r.ff16)
               , 3'b0
               , pack(r.lf)
               , pack(r.spien)
               , pack(r.psc)
               , pack(r.mstmod)
               , pack(r.ckpl)
               , pack(r.ckph)
               };
    endfunction
endinstance

typedef struct {
    // Receive buffer not empty:
    //  0: Receive buffer is empty
    //  1: Receive buffer is not empty
    Bit#(1) rbne;
    // Transmit buffer empty:
    //  0: Transmit buffer is not empty
    //  1: Transmit buffer is empty
    Bit#(1) tbe;
    // Reception overrun error bit
    Bit#(1) rxorerr;
    // Transmitting ongoing bit
    //  0: SPI or I2S is idle.
    //  1: SPI or I2S is currently transmitting and/or receiving a frame
    Bit#(1) trans;
} RegStat deriving (FShow);


instance Bits#(RegStat, 32);
    function RegStat unpack(Bit#(32) x);
        return RegStat { rbne: x[0]
                       , tbe: x[1]
                       , rxorerr: x[6]
                       , trans: x[7]
                       };
    endfunction
    function Bit#(32) pack(RegStat r);
        return { 24'b0
               , pack(r.trans)
               , pack(r.rxorerr)
               , 4'b0
               , pack(r.tbe)
               , pack(r.rbne)
               };
    endfunction
endinstance

function Bit#(9) clockForPsc(Bit#(3) psc);
    return case (psc) matches
        0: 2;
        1: 4;
        2: 8;
        3: 16;
        4: 32;
        5: 64;
        6: 128;
        7: 256;
    endcase;
endfunction

module mkController#(Bit#(wbAddr) baseAddr) (Controller#(wbAddr));
    Wishbone::SlaveConnector#(32, wbAddr, 4) bus <- mkAsyncSlaveConnector;

    Reg#(Bit#(1)) ckph <- mkReg(0);
    Reg#(Bit#(1)) ckpl <- mkReg(0);
    Reg#(Bit#(1)) mstmod <- mkReg(0);
    Reg#(Bit#(3)) psc <- mkReg(0);
    Reg#(Bit#(1)) spien <- mkReg(0);
    Reg#(Bit#(1)) lf <- mkReg(0);
    Reg#(Bit#(1)) ff16 <- mkReg(0);
    Reg#(Bit#(1)) bdoen <- mkReg(0);
    Reg#(Bit#(1)) bden <- mkReg(0);

    Reg#(Bit#(16)) data <- mkReg(0);
    Reg#(Bool) dataValid <- mkReg(False);
    Reg#(Maybe#(Bit#(16))) shiftregTx <- mkReg(tagged Invalid);
    Reg#(Bit#(16)) shiftregRx <- mkReg(0);
    Reg#(Bit#(1)) rxSample <- mkWire;

    Reg#(Bit#(9)) clock <- mkReg(0);
    Reg#(Maybe#(Bit#(4))) sendingBit <- mkReg(tagged Invalid);

    FIFO#(RegCtl0) newConfig <- mkBypassFIFO;
    FIFO#(void) dataRead <- mkBypassFIFO;

    let enableMaster = spien == 1 && mstmod == 1;
    let maxClock = clockForPsc(psc) - 1;
    let halfClock = clockForPsc(psc) >> 1;
    let maxBit = case (ff16) matches
        0: 7;
        1: 15;
    endcase;
    let tbe = !dataValid;
    let trans = isValid(sendingBit);
    let activeBitNo = case (enableMaster) matches
        False: 0;
        True: case (sendingBit) matches
            tagged Invalid: 0;
            tagged Valid .b: begin
                let swapb = b;
                if (lf == 0) begin
                    swapb = maxBit - b;
                end
                return swapb;
            end
        endcase
    endcase;
    Reg#(Bit#(1)) rxorerr <- mkReg(0);
    Reg#(Bit#(1)) rbne <- mkReg(0);

    rule clockDownCount (clock != 0 && enableMaster && isValid(sendingBit));
        clock <= clock - 1;
    endrule

    let bitOver = clock == 0 && enableMaster && isValid(sendingBit) && isValid(shiftregTx);
    rule nextBit (bitOver && fromMaybe(0, sendingBit) != maxBit);
        clock <= maxClock;
        sendingBit <= tagged Valid (fromMaybe(0, sendingBit) + 1);
    endrule

    rule lastBit (bitOver && fromMaybe(0, sendingBit) == maxBit);
        sendingBit <= tagged Invalid;
        shiftregTx <= tagged Invalid;

        let writeback = case (tuple2(bden, bdoen)) matches
            { 0, .* }: True;
            { 1, 0 }: True;
            default: False;
        endcase;
        if (writeback) begin
            data <= shiftregRx;
            if (rbne == 1) begin
                rxorerr <= 1;
            end
            rbne <= 1;
        end
    endrule

    rule startSend (enableMaster && isValid(shiftregTx) && !isValid(sendingBit));
        $display("Starting SPI send...");
        sendingBit <= tagged Valid 0;
        clock <= maxClock;
        shiftregRx <= 0;
    endrule

    rule stuffTransmit (enableMaster && !isValid(shiftregTx) && dataValid);
        $display("Queueing SPI send...");
        shiftregTx <= tagged Valid data;
        dataValid <= False;
    endrule

    rule receive (enableMaster && isValid(sendingBit) && clock == halfClock);
        shiftregRx[activeBitNo] <= rxSample;
    endrule

    rule clearRbne (enableMaster && !isValid(sendingBit));
        dataRead.deq();
        rbne <= 0;
    endrule

    rule applyNewConfig;
        let v = newConfig.first();
        newConfig.deq();
        ckph <= v.ckph;
        ckpl <= v.ckpl;
        mstmod <= v.mstmod;
        psc <= v.psc;
        spien <= v.spien;
        lf <= v.lf;
        ff16 <= v.ff16;
        bdoen <= v.bdoen;
        bden <= v.bden;
    endrule

    (* preempts = "wbRequest, stuffTransmit" *)
    (* preempts = "wbRequest, lastBit" *)
    rule wbRequest;
        let r <- bus.client.request.get();
        let resp = SlaveResponse { readData: tagged Invalid };
        case (r.address) matches
            0: begin
                case (r.writeData) matches
                    tagged Invalid: begin
                        resp.readData = tagged Valid pack(RegCtl0 { ckph: ckph
                                                                  , ckpl: ckpl
                                                                  , mstmod: mstmod
                                                                  , psc: psc
                                                                  , spien: spien
                                                                  , lf: lf
                                                                  , ff16: ff16
                                                                  , bdoen: bdoen
                                                                  , bden: bden
                                                                  });
                    end
                    tagged Valid .d: begin
                        RegCtl0 v = unpack(d);
                        newConfig.enq(v);
                    end
                endcase
            end
            'h8: begin
                resp.readData = tagged Valid pack(RegStat { rbne: rbne
                                                          , tbe: pack(tbe)
                                                          , rxorerr: rxorerr
                                                          , trans: pack(trans)
                                                          });
                rxorerr <= 0;
            end
            'hc: begin
                case (r.writeData) matches
                    tagged Invalid: begin
                        resp.readData = tagged Valid zeroExtend(data);
                        dataRead.enq(?);
                    end
                    tagged Valid .d: begin
                        data <= d[15:0];
                        if (enableMaster) begin
                            dataValid <= True;
                        end
                    end
                endcase
            end
        endcase
        bus.client.response.put(resp);
    endrule

    let sclk = case (enableMaster) matches
        False: 0;
        True: case (sendingBit) matches
            tagged Invalid: ckpl;
            tagged Valid .*: begin
                let v = case (ckph) matches
                    0: pack(clock < halfClock);
                    1: pack(clock >= halfClock);
                endcase;
                if (ckpl == 1) begin
                    v = ~v;
                end
                return v;
            end
        endcase
    endcase;
    let mosi = case (enableMaster && isValid(sendingBit)) matches
        True: data[activeBitNo];
        False: 0;
    endcase;
    let mosiOe = case (enableMaster) matches
        True: case (bden) matches
            0: 1;
            1: bdoen;
        endcase
        False: 0;
    endcase;

    let probeSclk <- mkProbe;
    let probeMosi <- mkProbe;
    let probeMosiOe <- mkProbe;
    let probeMiso <- mkProbe;
    let probeTbe <- mkProbe;
    let probeRbne <- mkProbe;
    let probeRxorerr <- mkProbe;
    let probeTrans <- mkProbe;
    rule setProbes;
        probeSclk <= sclk;
        probeMosi <= mosi;
        probeMosiOe <= mosiOe;
        probeTbe <= tbe;
        probeRbne <= rbne;
        probeRxorerr <= rxorerr;
        probeTrans <= trans;
    endrule

    interface slave = bus.slave;
    interface Master spiMaster;
        method sclk = sclk;
        method mosi = mosi;
        method mosiOe = mosiOe;
        method Action miso(Bool value);
            probeMiso <= value;
            rxSample <= pack(value);
        endmethod
    endinterface
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
module mkTbSPIController(Empty);
    Wishbone::MasterConnector#(32, 32, 4) master <- mkMasterConnector;
    Controller#(32) controller <- mkController(32'h4001_3000);
    mkConnection(master.master, controller.slave);

    Reg#(Bit#(32)) i <- mkReg(0);
    Reg#(Bit#(32)) j <- mkReg(0);
    Reg#(Bit#(8)) sampleResponse <- mkReg(8'h42);
    Reg#(Bit#(8)) sampleRequest <- mkReg(0);
    Reg#(Bit#(32)) readBuf <- mkReg(0);
    Stmt test = seq
        // CPOL = 0, CPHA = 0
        doWrite(master, 0, 'b1_000_1_00);
        eatResponse(master);
        doWrite(master, 'hc, 'h55);
        eatResponse(master);
        for (i <= 0; i < 12; i <= i + 1) seq
            noAction;
        endseq

        // CPOL = 1, CPHA = 0
        doWrite(master, 0, 'b1_000_1_10);
        eatResponse(master);
        doWrite(master, 'hc, 'h55);
        eatResponse(master);
        for (i <= 0; i < 12; i <= i + 1) seq
            noAction;
        endseq

        // Read data and status to clear all bits.
        doRead(master, 'hc);
        eatResponse(master);
        doRead(master, 'h8);
        eatResponse(master);

        // CPOL = 0, CPHA = 1, 16-bit
        doWrite(master, 0, 'b1_000_0_1_000_1_01);
        eatResponse(master);
        doWrite(master, 'hc, 'hdead);
        eatResponse(master);
        for (i <= 0; i < 10; i <= i + 1) seq
            noAction;
        endseq
        doWrite(master, 'hc, 'hbeef);
        eatResponse(master);
        for (i <= 0; i < 30; i <= i + 1) seq
            noAction;
        endseq

        // CPOL = 1, CPHA = 1, PSC = /4
        doWrite(master, 0, 'b1_001_1_11);
        eatResponse(master);
        par
            seq
                doWrite(master, 'hc, 'h55);
                eatResponse(master);
                for (i <= 0; i < 20; i <= i + 1) seq
                    noAction;
                endseq
            endseq
            seq
                for (j <= 0; j < 8; j <= j + 1) seq
                    while (controller.spiMaster.sclk == 1) seq
                        noAction;
                    endseq
                    $display("%d: got falling edge", j);
                    controller.spiMaster.miso(unpack(sampleResponse[7-j]));
                    while (controller.spiMaster.sclk == 0) seq
                        noAction;
                    endseq
                    action
                        let mosi = controller.spiMaster.mosi;
                        sampleRequest[7-j] <= mosi;
                        $display("%d: got rising edge, mosi: %d", j, mosi);
                    endaction
                endseq
            endseq
        endpar
        dynamicAssert(sampleRequest == 8'h55, "expected 0x55 to have been transmitted");
        doRead(master, 'hc);
        getResponse(master, readBuf);
        dynamicAssert(readBuf == 32'h42, "expected to have received 0x42");

        // CPOL = 0, CPHA = 0, unidirectional send
        doWrite(master, 0, pack(RegCtl0 { ckph: 0
                                        , ckpl: 0
                                        , mstmod: 1
                                        , psc: 0
                                        , spien: 1
                                        , lf: 0
                                        , ff16: 0
                                        , bdoen: 1
                                        , bden: 1
                                        }));
        eatResponse(master);
        doWrite(master, 'hc, 'h55);
        eatResponse(master);
        for (i <= 0; i < 12; i <= i + 1) seq
            noAction;
        endseq
        doRead(master, 'hc);
        getResponse(master, readBuf);
        dynamicAssert(readBuf == 32'h55, "expected to still have 0x55");

        // CPOL = 1, CPHA = 1, unidirectional recv
        doWrite(master, 0, pack(RegCtl0 { ckph: 1
                                        , ckpl: 1
                                        , mstmod: 1
                                        , psc: 1
                                        , spien: 1
                                        , lf: 0
                                        , ff16: 0
                                        , bdoen: 0
                                        , bden: 1
                                        }));
        eatResponse(master);
        par
            seq
                doWrite(master, 'hc, 'h55);
                eatResponse(master);
                for (i <= 0; i < 12; i <= i + 1) seq
                    noAction;
                endseq
            endseq
            seq
                for (j <= 0; j < 8; j <= j + 1) seq
                    while (controller.spiMaster.sclk == 1) seq
                        noAction;
                    endseq
                    $display("%d: got falling edge", j);
                    controller.spiMaster.miso(unpack(sampleResponse[7-j]));
                    while (controller.spiMaster.sclk == 0) seq
                        noAction;
                    endseq
                endseq
            endseq
        endpar

        // Wait for buffer not empty
        doRead(master, 'h8);
        getResponse(master, readBuf);
        while (readBuf[0] != 1) seq
            doRead(master, 'h8);
            getResponse(master, readBuf);
        endseq

        doRead(master, 'hc);
        getResponse(master, readBuf);
        dynamicAssert(readBuf == 32'h42, "expected to have received 0x42");

    endseq;
    mkAutoFSM(test);
endmodule

endpackage
