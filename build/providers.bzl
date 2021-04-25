# Bluespec Compiler provider, used by Bluespec Toolchain.
BscInfo = provider(
    fields = [
        "bsc",
        "verilog_lib",
    ],
)

YosysFlowInfo = provider(
    fields = [
        "yosys",
        "nextpnr",
        "packer",

        "synth_command",
    ],
)

# Bluespec intermediary compilation data.
BluespecInfo = provider(
    fields = [
        "partial_objects",
        "verilog_objects",
    ],
)

# Verilog module sources.
VerilogInfo = provider(
    fields = [
        "sources",
    ],
)

