# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2022 Sergiusz Bazanski

load("@qfc//build:providers.bzl", "YosysFlowInfo", "VerilogInfo")

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
        if _is_set(ctx, ctx.attr._ecp5_lfe5u_25f):
            nextpnr_flags.append("--25k")
        if _is_set(ctx, ctx.attr._ecp5_lfe5u_85f):
            nextpnr_flags.append("--85k")
        if _is_set(ctx, ctx.attr._ecp5_cabga381):
            nextpnr_flags += ["--package", "CABGA381"]
        if _is_set(ctx, ctx.attr._ecp5_cabga256):
            nextpnr_flags += ["--package", "CABGA256"]

        return struct(
            yosys_synth_command = "synth_ecp5 -abc9 -top %TOP%",
            nextpnr_flags = nextpnr_flags,
        )
    fail("Unsupported FPGA (needs //build/platforms:fpga_family constraint set)")

def _yosysflow_bitstream_impl(ctx):
    info = ctx.toolchains["@qfc//build/synthesis:toolchain_type"].yosysflowinfo
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
        arguments = nextpnr_arguments + [ ],
        inputs = [ json, ctx.file.constraints ],
        outputs = [ unpacked ],
    )

    packed = ctx.actions.declare_file(ctx.attr.name + ".bit")
    svf = ctx.actions.declare_file(ctx.attr.name + ".svf")

    ctx.actions.run(
        mnemonic = "BitstreamPack",
        executable = packer,
        arguments = [ unpacked.path, packed.path, "--svf", svf.path ],
        inputs = [ unpacked ],
        outputs = [ packed, svf ],
    )

    return [
        DefaultInfo(
            files = depset([packed, svf]),
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

        "_fpga_family_ecp5": attr.label(default="@qfc//build/platforms:ecp5"),
        "_fpga_family_ice40": attr.label(default="@qfc//build/platforms:ice40"),
        "_ecp5_lfe5u_12f": attr.label(default="@qfc//build/platforms:LFE5U_12F"),
        "_ecp5_lfe5u_25f": attr.label(default="@qfc//build/platforms:LFE5U_25F"),
        "_ecp5_lfe5u_85f": attr.label(default="@qfc//build/platforms:LFE5U_85F"),
        "_ecp5_cabga381": attr.label(default="@qfc//build/platforms:CABGA381"),
        "_ecp5_cabga256": attr.label(default="@qfc//build/platforms:CABGA256"),
    },
    toolchains = ["@qfc//build/synthesis:toolchain_type"],
)

def _rtl_bundle_impl(ctx):
    sources = depset(
        ctx.files.srcs,
        transitive = [dep[VerilogInfo].sources for dep in ctx.attr.deps],
    )
    data_files = depset(
        [],
        transitive = [dep[VerilogInfo].data_files for dep in ctx.attr.deps],
    )

    info = ctx.toolchains["@qfc//build/synthesis:toolchain_type"].yosysflowinfo
    yosys = info.yosys[DefaultInfo].files_to_run

    bundle = ctx.actions.declare_file(ctx.label.name + ".bundle.zip")

    args = ["c", bundle.path]
    for f in sources.to_list() + data_files.to_list():
        args.append(f.path)

    ctx.actions.run(
        inputs = sources.to_list() + data_files.to_list(),
        outputs = [bundle],
        executable = ctx.executable._zipper,
        arguments = args,
        progress_message = "Creating bundle...",
        mnemonic = "zipper",
    )

    outputs = []
    for (name, blackboxes) in ctx.attr.outputs.items():
        srcline = " ".join([s.path for s in sources.to_list()])
        intermediate = ctx.actions.declare_file(ctx.label.name + "_/" + name + ".intermediate.v")
        presynth = ctx.actions.declare_file(ctx.label.name + "/" + name + ".v")
        scriptfile = ctx.actions.declare_file(ctx.attr.name + "_/" + name + ".ys")
        content = """
            read_verilog -defer {}
            hierarchy -top {} -purge_lib
        """.format(srcline, name)

        for blackbox in blackboxes:
            content += "blackbox {}\n".format(blackbox)

        content += """
            hierarchy -top {} -purge_lib
            write_verilog {}
        """.format(
            name,
            intermediate.path,
        )

        ctx.actions.write(
            output = scriptfile,
            content = content
        )

        ctx.actions.run(
            mnemonic = "DesignPresynth",
            executable = yosys,
            arguments = [
                "-s", scriptfile.path,
                "-q",
            ],
            inputs = depset([ scriptfile ], transitive=[ sources, data_files ]),
            outputs = [intermediate],
        )

        ctx.actions.run(
            mnemonic = "PowerPinsAdd",
            executable = ctx.executable._add_power_pins,
            arguments = [
                name,
                ','.join(blackboxes),
                intermediate.path,
                presynth.path,
            ],
            inputs = [ intermediate ],
            outputs = [ presynth ],
        )

        outputs.append(presynth)

    return [
        DefaultInfo(
            files = depset([bundle]+outputs),
        )
    ]

rtl_bundle = rule(
    implementation = _rtl_bundle_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
        ),
        "deps": attr.label_list(
            providers = [VerilogInfo],
        ),
        "outputs": attr.string_list_dict(),
        "_add_power_pins": attr.label(
            default = Label("//build/synthesis:add_power_pins"),
            cfg = "host",
            executable = True,
        ),
        "_zipper": attr.label(
            default = Label("@bazel_tools//tools/zip:zipper"),
            cfg = "host",
            executable = True,
        ),
    },
    toolchains = ["@qfc//build/synthesis:toolchain_type"],
)
