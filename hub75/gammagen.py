import math
import sys

f = open(sys.argv[1], 'w')
f.write("package Gamma;\n\n")

f.write("interface GammaExpand;\n")
f.write("    method Bit#(12) expand(Bit#(8) val);\n")
f.write("endinterface\n\n")

f.write("(* synthesize *)\n")
f.write("module mkGammaExpand (GammaExpand);\n")
f.write("    method Bit#(12) expand(Bit#(8) val);\n")
f.write("        return case (val)\n")
for i in range(256):
    g = int(4095 * math.pow(i/255, 2.2))
    f.write(f"             8'h{i:02x}: 12'h{g:03x};\n")
f.write("        endcase;\n")
f.write("    endmethod\n")
f.write("endmodule\n\n")

f.write("endpackage")
