# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2022 Sergiusz Bazanski

load("@qfc//build:providers.bzl", "BscInfo", "VerilogInfo", "BluespecInfo")
load("@rules_cc//cc:toolchain_utils.bzl", "find_cpp_toolchain")

def _bluespec_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        bscinfo = BscInfo(
            bsc = ctx.attr.bsc,
            bluetcl = ctx.attr.bluetcl,
            verilog_lib = VerilogInfo(
                sources = depset(ctx.files.verilog_lib),
            ),
        ),
    )
    return [toolchain_info]

bluespec_toolchain = rule(
    implementation = _bluespec_toolchain_impl,
    attrs = {
        "bsc": attr.label(
            executable = True,
            cfg = "exec",
        ),
        "bluetcl": attr.label(
            executable = True,
            cfg = "exec",
        ),
        "verilog_lib": attr.label_list(
            allow_files = True,
        ),
    },
)

def _compile(ctx, src, dep_objs, output, mode, verilog_outputs=[], sim_outputs=[]):
    info = ctx.toolchains["@qfc//build/bluespec:toolchain_type"].bscinfo

    bdir = output.dirname
    pkg_path_set = {}
    for obj in dep_objs.to_list():
        if obj.dirname == bdir:
            continue
        pkg_path_set[obj.dirname] = True
    pkg_path = ['+'] + pkg_path_set.keys()

    arguments = [
        "-bdir", bdir,
        "-p", ":".join(pkg_path),
        "-aggressive-conditions",
        "-q",
    ]
    if ctx.attr.split_if:
        arguments.append("-split-if")

    mnemonic = ""
    if mode == "verilog":
        mnemonic = "BluespecVerilogCompile"
        vdir = bdir
        if len(verilog_outputs) > 0:
            vdir = verilog_outputs[0].dirname
        arguments += [
            "-verilog",
            "-vdir", vdir,
        ]
    elif mode == "sim":
        mnemonic = "BluespecSimCompile"
        simdir = bdir
        arguments += [
            "-sim",
            "-check-assert",
        ]
    else:
        fail("Invalid mode {}".format(mode))

    arguments += [
        src.path,
    ]

    _, _, input_manifests = ctx.resolve_command(tools = [info.bsc])
    ctx.actions.run(
        mnemonic = mnemonic,
        executable = info.bsc.files_to_run,
        arguments = arguments,
        inputs = depset([ src ], transitive=[dep_objs]),
        outputs = sim_outputs + verilog_outputs + [ output ],
        input_manifests = input_manifests,
        use_default_shell_env = True,
        env = {
            "PATH": ctx.configuration.default_shell_env.get('PATH', ""),
        },
    )


def _library_inner(ctx):
    info = ctx.toolchains["@qfc//build/bluespec:toolchain_type"].bscinfo

    package_order = []
    package_to_src = {}
    package_to_sim_obj = {}
    package_to_verilog_obj = {}
    package_to_verilog_modules = {}
    package_to_sim_modules = {}

    for src in ctx.files.srcs:
        basename = src.basename
        if not basename.endswith(".bsv"):
            fail("Source {} invalid: does not end in .bsv".format(basename))
        package = basename[:-4]

        package_order.append(package)
        package_to_src[package] = src
        sim_obj_name = "{}.sim/{}.bo".format(ctx.attr.name, package)
        verilog_obj_name = "{}.verilog/{}.bo".format(ctx.attr.name, package)
        package_to_sim_obj[package] = ctx.actions.declare_file(sim_obj_name)
        package_to_verilog_obj[package] = ctx.actions.declare_file(verilog_obj_name)


    for package, modules in ctx.attr.synthesize.items():
        if package not in package_to_src:
            fail("Package {} (in synthesize) does not exist in srcs".format(package))
        package_to_verilog_modules[package] = []
        package_to_sim_modules[package] = []
        for module in modules:
            verilog_name = "{}/{}.v".format(package, module)
            verilog = ctx.actions.declare_file(verilog_name)
            package_to_verilog_modules[package].append(verilog)
            sim_name = "{}.sim/{}.ba".format(ctx.attr.name, module)
            sim = ctx.actions.declare_file(sim_name)
            package_to_sim_modules[package].append(sim)


    input_sim_objects = depset(direct=[], transitive=[
        dep[BluespecInfo].sim_objects
        for dep in ctx.attr.deps
    ])
    input_verilog_objects = depset(direct=[], transitive=[
        dep[BluespecInfo].verilog_objects
        for dep in ctx.attr.deps
    ])
    data_files = depset(
        direct = [],
        transitive = [
            d.files
            for d in ctx.attr.data
        ] + [
            dep[BluespecInfo].data_files
            for dep in ctx.attr.deps
        ],
    )

    cur_sim_objs = input_sim_objects
    cur_verilog_objs = input_verilog_objects

    for package in package_order:
        src = package_to_src[package]
        sim_obj = package_to_sim_obj[package]
        verilog_obj = package_to_verilog_obj[package]
        verilog_modules = package_to_verilog_modules.get(package, [])
        sim_modules = package_to_sim_modules.get(package, [])

        _compile(
            ctx = ctx,
            src = src,
            dep_objs = cur_sim_objs,
            output = sim_obj,
            mode = 'sim',
            sim_outputs = sim_modules,
        )
        _compile(
            ctx = ctx,
            src = src,
            dep_objs = cur_verilog_objs,
            output = verilog_obj,
            mode = 'verilog',
            verilog_outputs = verilog_modules,
        )

        cur_sim_objs = depset([ sim_obj ], transitive=[cur_sim_objs])
        cur_verilog_objs = depset([ verilog_obj ], transitive=[cur_verilog_objs])


    verilog_modules = []
    for modules in package_to_verilog_modules.values():
        verilog_modules += modules
    sim_modules = []
    for modules in package_to_sim_modules.values():
        sim_modules += modules

    return struct(
        sim_objs = package_to_sim_obj.values(),
        sim_objs_deps = input_sim_objects,
        verilog_objs = package_to_verilog_obj.values(),
        verilog_objs_deps = input_verilog_objects,
        verilog_modules = verilog_modules,
        verilog_modules_deps = depset(
            transitive = [dep[VerilogInfo].sources for dep in ctx.attr.deps]+ [
                info.verilog_lib.sources,
            ],
        ),
        sim_modules = sim_modules,
        sim_modules_deps = depset(
            [],
            transitive = [dep[BluespecInfo].sim_outputs for dep in ctx.attr.deps],
        ),
        data_files = data_files,
    )


def _bluespec_library_impl(ctx):
    compiled = _library_inner(ctx)

    return [
        DefaultInfo(
            files=depset(
                compiled.sim_objs +
                compiled.verilog_objs +
                compiled.verilog_modules
            )
        ),
        BluespecInfo(
            sim_objects = depset(
                compiled.sim_objs,
                transitive = [ compiled.sim_objs_deps ],
            ),
            verilog_objects = depset(
                compiled.verilog_objs,
                transitive = [ compiled.verilog_objs_deps ],
            ),
            sim_outputs = depset(
                compiled.sim_modules,
                transitive = [ compiled.sim_modules_deps ],
            ),
            data_files = compiled.data_files,
        ),
        VerilogInfo(
            sources = depset(
                compiled.verilog_modules,
                transitive = [ compiled.verilog_modules_deps ],
            ),
            data_files = compiled.data_files,
        ),
    ]

bluespec_library = rule(
    implementation = _bluespec_library_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(
            providers = [BluespecInfo, VerilogInfo],
        ),
        "data": attr.label_list(
            allow_files = True,
        ),
        "synthesize": attr.string_list_dict(),
        "split_if": attr.bool(),
    },
    toolchains = ["@qfc//build/bluespec:toolchain_type"]
)


def _bluesim_test_impl(ctx):
    info = ctx.toolchains["@qfc//build/bluespec:toolchain_type"].bscinfo
    cc_toolchain = find_cpp_toolchain(ctx)
    bsc = info.bsc
    bluetcl = info.bluetcl

    sim_objs = depset(
        [],
        transitive = [dep[BluespecInfo].sim_objects for dep in ctx.attr.deps],
    )
    sim_outputs = depset(
        [],
        transitive = [dep[BluespecInfo].sim_outputs for dep in ctx.attr.deps],
    )
    data_files = depset(
        [],
        transitive = [
            d.files
            for d in ctx.attr.data
        ] + [
            dep[BluespecInfo].data_files
            for dep in ctx.attr.deps
        ] + [ bluetcl.default_runfiles.files ],
    )

    pkg_path_set = {}
    for obj in sim_objs.to_list() + sim_outputs.to_list():
        pkg_path_set[obj.dirname] = True
    pkg_path = ['+'] + pkg_path_set.keys()

    test = ctx.actions.declare_file(ctx.attr.name)
    testSo = ctx.actions.declare_file(ctx.attr.name + ".so")

    cxx = cc_toolchain.compiler_executable
    # HACK: if we use foo/gcc, use foo/g++ instead. This is needed because bsc
    # uses the compiler to link C++ code, and gcc-as-a-linker does not -lstdc++
    # by default, while g++-as-a-linker does.
    # The proper way to fix this would be to better pipe cc_toolchain
    # information into bsc somehow. Maybe using a real linker?
    if cxx.endswith('/gcc'):
        cxx = cxx[:-2] + "++"
    elif cxx.endswith('/cc'):
        cxx = cxx[:-2] + "g++"

    ctx.actions.run(
        mnemonic = "BluespecSimLink",
        executable = ctx.executable._bscwrap,
        tools = [
            bsc.files_to_run
        ],
        inputs = depset(
            [],
            transitive = [ sim_objs, sim_outputs ],
        ),
        arguments = [
            bsc.files_to_run.executable.path, cxx, cc_toolchain.strip_executable,
            "--",
            "-p", ":".join(pkg_path),
            "-sim",
            "-simdir", test.dirname,
            "-o", test.path,
            "-e",
            ctx.attr.top,
        ],
        use_default_shell_env = True,
        outputs = [test, testSo]
    )

    wrapper = ctx.actions.declare_file(ctx.attr.name + ".wrap")
    test_path = ctx.workspace_name + "/" + test.short_path
    ctx.actions.write(
        output = wrapper,
        content = """#!/usr/bin/env bash
# --- begin runfiles.bash initialization v2 ---
# Copy-pasted from the Bazel Bash runfiles library v2.
set -uo pipefail; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$0.runfiles/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v2 --- """ + ("""
export PATH="$(dirname $(rlocation bluespec/bluetcl)):$PATH"
t="$(rlocation {})"
$t $@ >res 2>&1
cat res
if grep -q "Error:" res ; then
    exit 1
fi
if grep -q "Dynamic assertion failed:" res ; then
    exit 1
fi
""".format(test_path)),
        is_executable = True,
    )

    return [
        DefaultInfo(
            executable = wrapper,
            runfiles = ctx.runfiles(
                files = [ wrapper, test, testSo  ],
                transitive_files = data_files,
            ),
        ),
    ]

bluesim_test = rule(
    implementation = _bluesim_test_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(
            providers = [BluespecInfo],
        ),
        "data": attr.label_list(allow_files = True),
        "top": attr.string(),

        "_bscwrap": attr.label(
            default = Label("@qfc//build/bluespec:bscwrap"),
            executable = True,
            cfg = "exec",
        ),
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
    },
    test = True,
    toolchains = [
        "@qfc//build/bluespec:toolchain_type",
    ],
)
