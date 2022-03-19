# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2022 Sergiusz Bazanski

import sys

name = sys.argv[1]
blackboxes = [b for b in sys.argv[2].strip().split(',') if b]

with open(sys.argv[3], "r") as f:
    data = f.read()
with open(sys.argv[4], "w") as f:
    declaration_prefix = f"module {name}("

    in_declaration = False
    for line in data.split("\n"):
        if in_declaration:
            if line.startswith(','):
                f.write(line + "\n")
            else:
                in_declaration = False
                f.write("`ifdef USE_POWER_PINS\n")
                f.write("    inout vccd1;\n")
                f.write("    inout vssd1;\n")
                f.write("`endif\n")
                f.write(line + "\n")
        else:
            if line.startswith(declaration_prefix):
                f.write(f"module {name}(\n")
                f.write("`ifdef USE_POWER_PINS\n")
                f.write("    vccd1,\n")
                f.write("    vssd1,\n")
                f.write("`endif\n")
                f.write(f"    " + line[len(declaration_prefix):] + "\n")
                in_declaration = True
            else:
                in_instantiation = False
                for blackbox in blackboxes:
                    if line.strip().startswith(blackbox + ' '):
                        assert line.endswith('(')
                        in_instantiation = True
                        break

                f.write(line + "\n")
                if in_instantiation:
                    f.write("`ifdef USE_POWER_PINS\n")
                    f.write("    .vccd1(vccd1),\n")
                    f.write("    .vssd1(vssd1),\n")
                    f.write("`endif\n")

