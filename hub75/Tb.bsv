package Tb;

import GetPut :: *;
import ClientServer :: *;
import FIFO :: *;
import Connectable :: *;
import SpecialFIFOs :: *;
import Probe :: *;

import Hub75 :: *;

module mkPatternGen (Server #(Coordinates#(2), PixelData));
    FIFO#(Coordinates#(2)) fifoReq <- mkPipelineFIFO;

    let probeLoadRequestX <- mkProbe;
    let probeLoadRequestY <- mkProbe;

    interface Put request;
        method Action put(Coordinates#(2) c);
            fifoReq.enq(c);
            probeLoadRequestX <= c.x;
            probeLoadRequestY <= c.y;
        endmethod
    endinterface
    interface Get response;
        method ActionValue#(PixelData) get;
            fifoReq.deq;
            let r = fifoReq.first;
            let v = 0;
            if (r.y == 16)
                v = 255;
            return PixelData { r: v
                             , g: 0
                             , b: 0
                             };
        endmethod
    endinterface
endmodule

(* synthesize *)
module mkTb (Empty);
    Reg#(int) i <- mkReg(0);

    Hub75#(2) hub75 <- mkHub75;
    let patternGen <- mkPatternGen;

    mkConnection(hub75.pixel_data, patternGen);

    rule testFetch;
        if (i > 100000) begin
            //bram.dump;
            $finish(0);
        end
        i <= i + 1;
        //$display("counter:", cpu.readPC);
    endrule

    let probeBank <- mkProbe;
    let probeOE <- mkProbe;
    let probeClk <- mkProbe;
    let probeLatch <- mkProbe;
    rule probeOut;
        probeBank <= hub75.port.bank;
        probeOE <= hub75.port.oe;
        probeClk <= hub75.port.clk;
        probeLatch <= hub75.port.latch;
    endrule
endmodule

endpackage
