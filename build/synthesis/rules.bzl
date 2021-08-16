load("//build:providers.bzl", "YosysFlowInfo", "VerilogInfo")

def _yosysflow_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        yosysflowinfo = YosysFlowInfo(
            yosys = ctx.attr.yosys,
            nextpnr = ctx.attr.nextpnr,
            packer = ctx.attr.packer,
        ),
    )
    return [toolchain_info]
    

yosysflow_toolchain = rule(
    implementation = _yosysflow_toolchain_impl,
    attrs = {
        "yosys": attr.label(
            executable = True,
            cfg = "exec",
        ),
        "nextpnr": attr.label(
            executable = True,
            cfg = "exec",
        ),
        "packer": attr.label(
            executable = True,
            cfg = "exec",
        ),
    },
)

def _is_set(ctx, attr):
    constraint = attr[platform_common.ConstraintValueInfo]
    return ctx.target_platform_has_constraint(constraint)

def _get_flags(ctx):
    if _is_set(ctx, ctx.attr._fpga_family_ecp5):
        nextpnr_flags = [
            "--lpf", "%CONSTRAINT_FILE%",
            "--json", "%JSON_FILE%",
            "--textcfg", "%OUT_FILE%",
        ]
        if _is_set(ctx, ctx.attr._ecp5_lfe5u_12f):
            nextpnr_flags.append("--12k")
        if _is_set(ctx, ctx.attr._ecp5_cabga381):
            nextpnr_flags += ["--package", "CABGA381"]

        return struct(
            yosys_synth_command = "synth_ecp5 -abc9 -nowidelut -top %TOP%",
            nextpnr_flags = nextpnr_flags,
        )
    fail("Unsupported FPGA (needs //build/platforms:fpga_family constraint set)")

def _yosysflow_bitstream_impl(ctx):
    info = ctx.toolchains["//build/synthesis:toolchain_type"].yosysflowinfo
    yosys = info.yosys[DefaultInfo].files_to_run
    nextpnr = info.nextpnr[DefaultInfo].files_to_run
    packer = info.packer[DefaultInfo].files_to_run
    flags = _get_flags(ctx)

    sources = depset(
        ctx.files.srcs,
        transitive = [dep[VerilogInfo].sources for dep in ctx.attr.deps],
    )
    data_files = depset(
        [],
        transitive = [dep[VerilogInfo].data_files for dep in ctx.attr.deps],
    )

    srcline = " ".join([s.path for s in sources.to_list()])
    synth_command = flags.yosys_synth_command.replace('%TOP%', ctx.attr.top)

    json = ctx.actions.declare_file(ctx.attr.name + ".json")
    scriptfile = ctx.actions.declare_file(ctx.attr.name + ".ys")
    ctx.actions.write(
        output = scriptfile,
        content = """
            read_verilog -defer {}
            {}
            write_json {}
        """.format(
            srcline,
            synth_command,
            json.path,
        ),
    )

    ctx.actions.run(
        mnemonic = "DesignSynthesize",
        executable = yosys,
        arguments = [
            "-s", scriptfile.path,
            "-q",
        ],
        inputs = depset([ scriptfile ], transitive=[ sources, data_files ]),
        outputs = [ json ],
    )

    unpacked = ctx.actions.declare_file(ctx.attr.name + ".pnr")

    nextpnr_arguments = [
        (f
            .replace("%CONSTRAINT_FILE%", ctx.file.constraints.path)
            .replace("%JSON_FILE%", json.path)
            .replace("%OUT_FILE%", unpacked.path)
        )
        for f in flags.nextpnr_flags
    ]

    ctx.actions.run(
        mnemonic = "BitstreamRoute",
        executable = nextpnr,
        arguments = nextpnr_arguments + [ "-q" ],
        inputs = [ json, ctx.file.constraints ],
        outputs = [ unpacked ],
    )

    packed = ctx.actions.declare_file(ctx.attr.name + ".bit")

    ctx.actions.run(
        mnemonic = "BitstreamPack",
        executable = packer,
        arguments = [ unpacked.path, packed.path ],
        inputs = [ unpacked ],
        outputs = [ packed ],
    )

    return [
        DefaultInfo(
            files = depset([packed]),
        )
    ]

yosysflow_bitstream = rule(
    implementation = _yosysflow_bitstream_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
        ),
        "deps": attr.label_list(
            providers = [VerilogInfo],
        ),
        "top": attr.string(),
        "constraints": attr.label(allow_single_file = True),

        "_fpga_family_ecp5": attr.label(default="//build/platforms:ecp5"),
        "_fpga_family_ice40": attr.label(default="//build/platforms:ice40"),
        "_ecp5_lfe5u_12f": attr.label(default="//build/platforms:LFE5U_12F"),
        "_ecp5_cabga381": attr.label(default="//build/platforms:CABGA381"),
    },
    toolchains = ["//build/synthesis:toolchain_type"],
)
