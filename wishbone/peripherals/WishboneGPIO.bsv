package WishboneGPIO;

import Assert :: *;
import ClientServer :: *;
import Connectable :: *;
import FIFO :: *;
import GetPut :: *;
import SpecialFIFOs :: *;
import StmtFSM :: *;
import Vector :: *;
import Wishbone :: *;
import Probe :: *;

interface GPIOController#(numeric type wbAddr);
    interface Wishbone::Slave#(32, wbAddr, 4) slave;

    (* always_ready, result="oe" *)
    method Bit#(16) oe;
    (* always_ready, result="out" *)
    method Bit#(16) out;
    (* always_ready, always_enabled, prefix="" *)
    method Action in((* port="in" *) Bit#(16) value);
endinterface

typedef enum {
    INPUT,
    OUTPUT10,
    OUTPUT2,
    OUTPUT50
} Mode deriving (FShow, Eq);

instance Bits#(Mode, 2);
    function Mode unpack(Bit#(2) x);
        return case (x) matches
            0: INPUT;
            1: OUTPUT10;
            2: OUTPUT2;
            3: OUTPUT50;
        endcase;
    endfunction
    function Bit#(2) pack(Mode m);
        return case (m) matches
            INPUT: 0;
            OUTPUT10: 1;
            OUTPUT2: 2;
            OUTPUT50: 3;
        endcase;
    endfunction
endinstance

typedef enum {
    ANALOG,
    FLOATING,
    INPUT,
    RESERVED
} ControlInput deriving (FShow, Eq);

instance Bits#(ControlInput, 2);
    function ControlInput unpack(Bit#(2) x);
        return case (x) matches
            0: ANALOG;
            1: FLOATING;
            2: INPUT;
            3: RESERVED;
        endcase;
    endfunction
    function Bit#(2) pack(ControlInput m);
        return case (m) matches
            ANALOG: 0;
            FLOATING: 1;
            INPUT: 2;
            RESERVED: 3;
        endcase;
    endfunction
endinstance

typedef enum {
    GPIOPUSHPULL,
    GPIOOPENDRAIN,
    AFIOPUSHPULL,
    AFIOOPENDRAIN
} ControlOutput deriving (FShow, Eq);

instance Bits#(ControlOutput, 2);
    function ControlOutput unpack(Bit#(2) x);
        return case (x) matches
            0: GPIOPUSHPULL;
            1: GPIOOPENDRAIN;
            2: AFIOPUSHPULL;
            3: AFIOOPENDRAIN;
        endcase;
    endfunction
    function Bit#(2) pack(ControlOutput m);
        return case (m) matches
            GPIOPUSHPULL: 0;
            GPIOOPENDRAIN: 1;
            AFIOPUSHPULL: 2;
            AFIOOPENDRAIN: 3;
        endcase;
    endfunction
endinstance

module mkGPIOController (GPIOController#(wbAddr));
    Vector#(16, Reg#(Mode)) modes <- replicateM(mkReg(INPUT));
    Vector#(16, Reg#(Bit#(2))) controls <- replicateM(mkReg(1));
    Reg#(Bit#(16)) sampledInputs <- mkReg(0);
    Reg#(Bit#(16)) registeredOutputs <- mkReg(0);
    FIFO#(Bit#(32)) fNewCtl0 <- mkBypassFIFO;
    FIFO#(Bit#(32)) fNewCtl1 <- mkBypassFIFO;
    Wishbone::SlaveConnector#(32, wbAddr, 4) bus <- mkSyncSlaveConnector;

    Vector#(16, Bool) isInput;
    for (Integer n = 0; n < 16; n = n + 1) begin
        ControlInput ctl = unpack(controls[n]);
        isInput[n] = modes[n] == INPUT && (ctl == INPUT || ctl == FLOATING);
    end
    Vector#(16, Bool) isOutput;
    for (Integer n = 0; n < 16; n = n + 1) begin
        ControlOutput ctl = unpack(controls[n]);
        isOutput[n] = modes[n] != INPUT && ctl == GPIOPUSHPULL;
    end

    let probeModes <- mkProbe;
    let probeControls <- mkProbe;
    let probeIsInput <- mkProbe;
    let probeIsOutput <- mkProbe;
    rule updateProbes;
        Bit#(32) data = 0;
        for (Integer i = 0; i < 16; i = i + 1) begin
            data[i*2+1:i*2] = pack(modes[i]);
        end
        probeModes <= data;

        data = 0;
        for (Integer i = 0; i < 16; i = i + 1) begin
            data[i*2+1:i*2] = controls[i];
        end
        probeControls <= data;

        probeIsInput <= isInput;
        probeIsOutput <= isOutput;
    endrule

    rule applyCtl0;
        let d = fNewCtl0.first();
        fNewCtl0.deq();

        for (Integer i = 0; i < 8; i = i + 1) begin
            controls[i] <= d[4*i+3:4*i+2];
            modes[i] <= unpack(d[4*i+1:4*i]);
        end
    endrule

    rule applyCtl1;
        let d = fNewCtl1.first();
        fNewCtl1.deq();

        for (Integer i = 0; i < 8; i = i + 1) begin
            controls[i+8] <= d[4*i+3:4*i+2];
            modes[i+8] <= unpack(d[4*i+1:4*i]);
        end
    endrule

    rule wbRequest;
        let r <- bus.client.request.get();
        let resp = SlaveResponse { readData: tagged Invalid };
        $display("GPIO: wb request", fshow(r));

        case (r.address) matches
            0: begin
                case (r.writeData) matches
                    tagged Invalid: begin
                        Bit#(32) ctl0 = 0;
                        for (Integer i = 0; i < 8; i = i + 1) begin
                            ctl0[4*i+3:4*i+2] = controls[i];
                            ctl0[4*i+1:4*i] = pack(modes[i]);
                        end
                        resp.readData = tagged Valid ctl0;
                    end
                    tagged Valid .d: begin
                        fNewCtl0.enq(d);
                    end
                endcase
            end
            4: begin
                case (r.writeData) matches
                    tagged Invalid: begin
                        Bit#(32) ctl1 = 0;
                        for (Integer i = 0; i < 8; i = i + 1) begin
                            ctl1[4*i+3:4*i+2] = controls[i+8];
                            ctl1[4*i+1:4*i] = pack(modes[i+8]);
                        end
                        resp.readData = tagged Valid ctl1;
                    end
                    tagged Valid .d: begin
                        fNewCtl1.enq(d);
                    end
                endcase
            end
            8: begin
                case (r.writeData) matches
                    tagged Invalid: begin
                        Bit#(32) stat = { 16'b0, sampledInputs };
                        resp.readData = tagged Valid stat;
                    end
                    tagged Valid .d: begin
                    end
                endcase
            end
            'hc: begin
                case (r.writeData) matches
                    tagged Invalid: begin
                        Bit#(32) octl = { 16'b0, registeredOutputs };
                        resp.readData = tagged Valid octl;
                    end
                    tagged Valid .d: begin
                        registeredOutputs <= d[15:0];
                    end
                endcase
        end
        endcase
        bus.client.response.put(resp);
    endrule

    method Action in(Bit#(16) value); 
        Bit#(16) masked = 0;
        for (Integer i = 0; i < 16; i = i + 1) begin
            if (isInput[i]) begin
                masked[i] = value[i];
            end else begin
                masked[i] = 0;
            end
        end
        sampledInputs <= masked;
    endmethod

    method Bit#(16) oe;
        Bit#(16) res;
        for (Integer i = 0; i < 16; i = i + 1) begin
            res[i] = pack(isOutput[i]);
        end
        return res;
    endmethod

    method Bit#(16) out;
        Bit#(16) res;
        for (Integer i = 0; i < 16; i = i + 1) begin
            res[i] = case (isOutput[i]) matches
                False: 0;
                True: registeredOutputs[i];
            endcase;
        end
        return res;
    endmethod


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
module mkTbGPIOController(Empty);
    Wishbone::MasterConnector#(32, 32, 4) master <- mkMasterConnector;
    GPIOController#(32) controller <- mkGPIOController;
    mkConnection(master.master, controller.slave);

    rule feedInput;
        controller.in(16'hdead);
    endrule

    Reg#(Bit#(32)) tmp <- mkReg(0);
    Stmt test = seq
        // GPIO[4] output, everything else inputs.
        action
            Bit#(32) ctl0 = 32'h44444444;
            ctl0[19:18] = 0;
            ctl0[17:16] = 1;
            doWrite(master, 0, ctl0);
        endaction
        eatResponse(master);
        // GPIO[11] output, everything else inputs.
        action
            Bit#(32) ctl1 = 32'h44444444;
            ctl1[15:14] = 0;
            ctl1[13:12] = 1;
            doWrite(master, 4, ctl1);
        endaction
        eatResponse(master);
        // Write all ones.
        doWrite(master, 'hc, 'hffff_ffff);
        eatResponse(master);

        // Expect only bits 4 and 11 to be enabled.
        dynamicAssert(controller.oe == 'h0000_0810, "expected gpio 4 and 11 to have output enabled");
        // Expect only bits 4 and 11 to be lit.
        dynamicAssert(controller.out == 'h0000_0810, "expected gpio 4 and 11 to be lit");

        // Turn off bit 4.
        doRead(master, 'hc);
        getResponse(master, tmp);
        tmp <= tmp & 'hffff_ffef;
        doWrite(master, 'hc, tmp);
        eatResponse(master);

        // Expect only bit 11 to be lit.
        dynamicAssert(controller.out == 'h0000_0800, "expected gpio 11 to be lit");

        // Expect inputs to be 8'hdead, but with bit 11 off.
        doRead(master, 'h8);
        getResponse(master, tmp);
        $display("%x", tmp);
        dynamicAssert(tmp == 'h0000_d6ad, "expected inputs to be 0xdead with bit 11 off");
    endseq;
    mkAutoFSM(test);
endmodule

endpackage
