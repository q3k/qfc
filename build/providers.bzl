# Bluespec Compiler provider, used by Bluespec Toolchain.
BscInfo = provider(
    fields = [
        "bsc",
        "bluetcl",
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
        "sim_objects",
        "verilog_objects",
        "sim_outputs",
        "data_files",
    ],
)

# Verilog module sources.
VerilogInfo = provider(
    fields = [
        "sources",
        "data_files",
    ],
)

