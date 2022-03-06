package Hub75;

import GetPut :: *;
import ClientServer :: *;
import FIFO :: *;
import SpecialFIFOs :: *;
import Vector :: *;
import Probe :: *;
import BRAM :: *;

import Gamma :: *;

typedef struct {
    Bit#(6) x;
    Bit#(TAdd#(4, TLog#(lines))) y;
} Coordinates#(numeric type lines) deriving (Bits);

typedef struct {
    Bit#(8) r;
    Bit#(8) g;
    Bit#(8) b;
} PixelData deriving (Bits);

typedef struct {
    Bit#(1) r;
    Bit#(1) g;
    Bit#(1) b;
} LinePort deriving (Bits);

typedef struct {
    Bit#(4) bank;
    Bit#(1) oe;
    Bit#(1) clk;
    Bit#(1) latch;
    Vector#(lines, LinePort) lines;
} Port#(numeric type lines) deriving (Bits);

function Port#(lines) defaultPort();
    return Port { bank: 0
                , oe: 0
                , clk: 0
                , latch: 0
                , lines: replicate(defaultLinePort())
                };
endfunction

function LinePort defaultLinePort();
    return LinePort { r: 0, g: 0, b: 0 };
endfunction

interface Hub75#(numeric type lines);
    interface Client #(Coordinates#(lines), PixelData) pixel_data;

    (* always_enabled *)
    method Port#(lines) port;
endinterface

typedef struct {
    Bit#(12) r;
    Bit#(12) g;
    Bit#(12) b;
} ColorExpanded deriving (Bits);

instance DefaultValue#(ColorExpanded);
    defaultValue = ColorExpanded { r: 0
                                 , g: 0
                                 , b: 0
                                 };
endinstance

typedef struct {
    Bit#(4) bank;
    Bit#(4) bitplane;
} State deriving (Bits);

typedef struct {
    State state;
    Bit#(6) x;
    Bool clk;
    Vector#(lines, ColorExpanded) colorData;
} SendingState#(numeric type lines) deriving (Bits);

typedef struct {
    State state;
    Bit#(12) counter;
} OutputtingState deriving (Bits);

typedef struct {
    State state;
    Bit#(6) x;
    Bit#(TLog#(lines)) line;
} LoadingState#(numeric type lines) deriving (Bits);

module mkHub75 (Hub75#(lines));
    GammaExpand gammaR <- mkGammaExpand;
    GammaExpand gammaG <- mkGammaExpand;
    GammaExpand gammaB <- mkGammaExpand;

    Vector#(lines, Integer) lineNums = genWith(id);

    BRAM_Configure linebufCfg = defaultValue;
    // Don't need this functionality, disabling adds timing slack.
    linebufCfg.allowWriteResponseBypass = False;
    // Testing with sample design:
    // 3: 1784 LUT4s
    // 2: 1853 LUT4s
    // 1: 1739 LUT4s
    linebufCfg.outFIFODepth = 3;

    Vector#(lines, BRAM1Port#(Bit#(6), Bit#(36))) linebuf <- replicateM(mkBRAM1Server(linebufCfg));

    Reg#(Maybe#(LoadingState#(lines))) loading <- mkReg(tagged Invalid);
    FIFO#(State) readyToLoad <- mkPipelineFIFO;

    Reg#(Maybe#(SendingState#(lines))) sending <- mkReg(tagged Invalid);
    FIFO#(State) readyToSend <- mkPipelineFIFO;

    Reg#(Bool) latching <- mkReg(False);
    FIFO#(State) readyToLatch <- mkPipelineFIFO;

    Reg#(Maybe#(OutputtingState)) outputting <- mkReg(tagged Invalid);
    FIFO#(State) readyToOutput <- mkPipelineFIFO;

    FIFO#(State) readyForNextLine <- mkPipelineFIFO;

    FIFO#(Coordinates#(lines)) loadRequest <- mkBypassFIFO;
    FIFO#(PixelData) loadResponse <- mkBypassFIFO;

    Vector#(lines, Bool) loadLineActive;
    let probeLoadActiveLine <- mkProbe;
    let probeLoadActiveX <- mkProbe;
    for (Integer i = 0; i < valueOf(lines); i = i + 1) begin
        loadLineActive[i] = False;
        case (loading) matches
            tagged Valid .ls: begin
                if (ls.line == fromInteger(i)) begin
                    loadLineActive[i] = True;
                end
            end
        endcase
    end

    let probeBRAMWriteLine <- mkProbe;
    let probeBRAMWriteAddress <- mkProbe;
    let probeBRAMWriteData <- mkProbe;
    function Rules genLoadRules(Tuple2#(BRAM1Port#(Bit#(6), Bit#(36)), Integer) args);
        let port = tpl_1(args);
        let lineno = tpl_2(args);
        return (rules
                rule process_load_N (loadLineActive[lineno] &&& loading matches tagged Valid .state);
                    let s = state;
                    Bool done = False;

                    probeLoadActiveLine <= fromInteger(lineno);
                    probeLoadActiveX <= s.x;

                    loadResponse.deq;
                    let resp = loadResponse.first;
                    let cd = ColorExpanded { r: gammaR.expand(resp.r)
                                           , g: gammaG.expand(resp.g)
                                           , b: gammaB.expand(resp.b)
                                           };
                    probeBRAMWriteLine <= fromInteger(lineno);
                    probeBRAMWriteAddress <= s.x;
                    probeBRAMWriteData <= pack(cd);
                    linebuf[lineno].portA.request.put(BRAMRequest { write: True
                                                          , responseOnWrite: False
                                                          , address: s.x
                                                          , datain: pack(cd)
                                                          });
                    
                    Bit#(TAdd#(4, TLog#(lines))) bankOffset = zeroExtend(s.line) << 4;
                    if (s.x == 63) begin
                        if (s.line == fromInteger((valueOf(lines) - 1))) begin
                            done = True;
                        end else begin
                            s.x = 0;
                            s.line = s.line + 1;
                            bankOffset = zeroExtend(s.line) << 4;
                            loadRequest.enq(Coordinates { x: s.x
                                                        , y: zeroExtend(s.state.bank) + bankOffset
                                                        });
                        end
                    end else begin
                        s.x = s.x + 1;
                        loadRequest.enq(Coordinates { x: s.x
                                                    , y: zeroExtend(s.state.bank) + bankOffset
                                                    });
                    end

                    if (done) begin
                        readyToSend.enq(s.state);
                        loading <= tagged Invalid;
                    end else begin
                        loading <= tagged Valid s;
                    end
                endrule
        endrules);
    endfunction
    addRules(joinRules(map(genLoadRules, zip(linebuf, lineNums))));

    rule start_load (loading matches tagged Invalid);
        readyToLoad.deq;
        let state = readyToLoad.first;
        loading <= tagged Valid LoadingState { state: state
                                            , x: 0
                                            , line: 0
                                            };
        loadRequest.enq(Coordinates { x: 0
                                    , y: zeroExtend(state.bank)
                                    });
    endrule

    let probeSendingX <- mkProbe;
    rule start_send (sending matches tagged Invalid);
        readyToSend.deq;
        let state = readyToSend.first;
        sending <= tagged Valid SendingState { state: state
                                            , x: 0
                                            , clk: False
                                            , colorData: replicate(defaultValue)
                                            };
        for (Integer i = 0; i < valueOf(lines); i = i + 1) begin
            linebuf[i].portA.request.put(BRAMRequest{ write: False
                                                 , responseOnWrite: False
                                                 , address: 0
                                                 , datain: 0
                                                 });
        end
    endrule
    (* mutually_exclusive = "process_load_N, process_send" *)
    rule process_send (sending matches tagged Valid .state);
        SendingState#(lines) s = state;
        Bool done = False;

        probeSendingX <= s.x;

        if (s.clk) begin
            s.clk = False;
            if (s.x == 63) begin
                readyToLatch.enq(s.state);
                done = True;
            end else begin
                let sxNext = s.x + 1;
                s.x = sxNext;
                for (Integer i = 0; i < valueOf(lines); i = i + 1) begin
                    linebuf[i].portA.request.put(BRAMRequest{ write: False
                                                         , responseOnWrite: False
                                                         , address: sxNext
                                                         , datain: 0
                                                         });
                end
            end
        end else begin
            for (Integer i = 0; i < valueOf(lines); i = i + 1) begin
                let resp <- linebuf[i].portA.response.get();
                s.colorData[i] = unpack(resp);
            end
            s.clk = True;
        end
        if (done) begin
            sending <= tagged Invalid;
        end else begin
            sending <= tagged Valid s;
        end
    endrule

    rule start_latch (outputting matches tagged Invalid);
        readyToLatch.deq;
        readyToOutput.enq(readyToLatch.first);
        latching <= True;
    endrule
    (* preempts="end_latch, start_latch" *)
    rule end_latch (latching);
        latching <= False;
    endrule

    Reg#(Bit#(4)) prevBank <- mkReg(0);
    let probeOutputBitplane <- mkProbe;
    let probeOutputCounter <- mkProbe;
    rule start_output (outputting matches tagged Invalid);
        readyToOutput.deq;
        let state = readyToOutput.first;
        probeOutputBitplane <= state.bitplane;
        outputting <= tagged Valid OutputtingState { state: readyToOutput.first
                                                  , counter: (1 << state.bitplane)
                                                  };
        readyForNextLine.enq(state);
    endrule
    rule process_output (outputting matches tagged Valid .state);
        let s = state;
        prevBank <= s.state.bank;
        Bool done = False;
        probeOutputCounter <= s.counter;
        if (s.counter > 0) begin
            s.counter = s.counter - 1;
        end else begin
            done = True;
        end
        if (done) begin
            outputting <= tagged Invalid;
        end else begin
            outputting <= tagged Valid s;
        end
    endrule

    rule process_next_line;
        readyForNextLine.deq;
        let state = readyForNextLine.first;

        if (state.bitplane == 11) begin
            state.bitplane = 0;
            if (state.bank == 15) begin
                state.bank = 0;
            end else begin
                state.bank = state.bank + 1;
            end
        end else begin
            state.bitplane = state.bitplane + 1;
        end
        readyToLoad.enq(state);
    endrule

    Reg#(Bool) kickstart <- mkReg(True);
    (* preempts = "process_kickstart, process_next_line" *)
    rule process_kickstart (kickstart);
        kickstart <= False;
        readyToLoad.enq(State { bank: 0
                              , bitplane: 0
                              });
    endrule

    interface Client pixel_data;
        interface request = toGet(loadRequest);
        interface response = toPut(loadResponse);
    endinterface

    method Port#(lines) port;
        Port#(lines) pv = defaultPort();

        let oe = case (outputting) matches
            tagged Invalid: False;
            tagged Valid .*: True;
        endcase;

        let bank = case (outputting) matches
            tagged Invalid: prevBank;
            tagged Valid .o: o.state.bank;
        endcase;

        case (sending) matches
            tagged Valid .s: begin
                for (Integer i = 0; i < valueOf(lines); i = i + 1) begin
                    Bit#(1) r = s.colorData[i].r[s.state.bitplane];
                    Bit#(1) g = s.colorData[i].g[s.state.bitplane];
                    Bit#(1) b = s.colorData[i].b[s.state.bitplane];
                    pv.lines[i] = LinePort { r: r
                                           , g: g
                                           , b: b };
                end
                pv.clk = pack(s.clk);                   
            end
        endcase

        pv.bank = pack(bank);
        pv.oe = pack(!oe);
        pv.latch = pack(latching);
        return pv;
    endmethod
endmodule

endpackage
