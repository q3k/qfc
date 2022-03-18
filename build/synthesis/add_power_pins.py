import sys

name = sys.argv[1]

with open(sys.argv[2], "r") as f:
    data = f.read()
with open(sys.argv[3], "w") as f:
    prefix = f"module {name}("

    want_end = False
    for line in data.split("\n"):
        if want_end:
            if line.startswith(','):
                f.write(line + "\n")
            else:
                want_end = False
                f.write("`ifdef USE_POWER_PINS\n")
                f.write("    inout VPWR;\n")
                f.write("    inout VGND;\n")
                f.write("`endif\n")
                f.write(line + "\n")
        else:
            if line.startswith(prefix):
                f.write(f"module {name}(\n")
                f.write("`ifdef USE_POWER_PINS\n")
                f.write("    VPWR,\n")
                f.write("    VGND,\n")
                f.write("`endif\n")
                f.write(f"    " + line[len(prefix):] + "\n")
                want_end = True
            else:
                f.write(line + "\n")

