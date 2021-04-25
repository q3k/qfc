load("//build:providers.bzl", "BscInfo", "VerilogInfo", "BluespecInfo")

def _bluespec_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        bscinfo = BscInfo(
            bsc = ctx.attr.bsc,
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
        "verilog_lib": attr.label_list(
            allow_files = True,
        ),
    },
)

def _compile(ctx, src, dep_objs, output, verilog=False, verilog_outputs=[]):
    info = ctx.toolchains["//build/bluespec:toolchain_type"].bscinfo
    bsc = info.bsc[DefaultInfo].files_to_run

    pkg_path_set = {}
    for obj in dep_objs.to_list():
        pkg_path_set[obj.dirname] = True
    pkg_path = ['+'] + pkg_path_set.keys()

    bdir = output.dirname
    arguments = [
        "-bdir", bdir,
        "-p", ":".join(pkg_path),
        "-q",
    ]
    mnemonic = "BluespecPartialCompile"
    if verilog:
        mnemonic = "BluespecVerilogCompile"
        vdir = bdir
        if len(verilog_outputs) > 0:
            vdir = verilog_outputs[0].dirname
        arguments += [
            "-verilog",
            "-vdir", vdir,
        ]
    arguments += [
        src.path,
    ]

    ctx.actions.run(
        mnemonic = mnemonic,
        executable = bsc,
        arguments = arguments,
        inputs = depset([ src ], transitive=[dep_objs]),
        outputs = verilog_outputs + [ output ],
    )
            

def _bluespec_library_impl(ctx):
    info = ctx.toolchains["//build/bluespec:toolchain_type"].bscinfo
    bsc = info.bsc[DefaultInfo].files_to_run

    package_order = []
    package_to_src = {}
    package_to_partial_obj = {}
    package_to_verilog_obj = {}
    package_to_verilog_modules = {}

    for src in ctx.files.srcs:
        basename = src.basename
        if not basename.endswith(".bsv"):
            fail("Source {} invalid: does not end in .bsv".format(basename))
        package = basename[:-4]

        package_order.append(package)
        package_to_src[package] = src
        partial_obj_name = "{}.partial/{}.bo".format(ctx.attr.name, package)
        verilog_obj_name = "{}.verilog/{}.bo".format(ctx.attr.name, package)
        package_to_partial_obj[package] = ctx.actions.declare_file(partial_obj_name)
        package_to_verilog_obj[package] = ctx.actions.declare_file(verilog_obj_name)


    for package, modules in ctx.attr.synthesize.items():
        if package not in package_to_src:
            fail("Package {} (in synthesize) does not exist in srcs".format(package))
        package_to_verilog_modules[package] = []
        for module in modules:
            verilog_name = "{}/{}.v".format(package, module)
            verilog = ctx.actions.declare_file(verilog_name)
            package_to_verilog_modules[package].append(verilog)


    input_partial_objects = depset(direct=[], transitive=[
        dep[BluespecInfo].partial_objects
        for dep in ctx.attr.deps
    ])
    input_verilog_objects = depset(direct=[], transitive=[
        dep[BluespecInfo].verilog_objects
        for dep in ctx.attr.deps
    ])

    cur_partial_objs = input_partial_objects
    cur_verilog_objs = input_verilog_objects

    for package in package_order:
        src = package_to_src[package]
        partial_obj = package_to_partial_obj[package]
        verilog_obj = package_to_verilog_obj[package]
        modules = package_to_verilog_modules.get(package, [])

        _compile(
            ctx = ctx,
            src = src,
            dep_objs = cur_partial_objs,
            output = partial_obj,
            verilog = False,
        )
        _compile(
            ctx = ctx,
            src = src,
            dep_objs = cur_verilog_objs,
            output = verilog_obj,
            verilog = True,
            verilog_outputs = modules,
        )

        cur_partial_objs = depset([ partial_obj ], transitive=[cur_partial_objs])
        cur_verilog_objs = depset([ verilog_obj ], transitive=[cur_verilog_objs])


    verilog_modules = []
    for modules in package_to_verilog_modules.values():
        verilog_modules += modules

    return [
        DefaultInfo(
            files=depset(
                package_to_partial_obj.values() +
                package_to_verilog_obj.values() +
                verilog_modules
            )
        ),
        BluespecInfo(
            partial_objects = depset(
                package_to_partial_obj.values(),
                transitive = [ input_partial_objects ],
            ),
            verilog_objects = depset(
                package_to_verilog_obj.values(),
                transitive = [ input_verilog_objects ],
            ),
        ),
        VerilogInfo(
            sources = depset(
                verilog_modules,
                transitive = [dep[VerilogInfo].sources for dep in ctx.attr.deps] + [
                    info.verilog_lib.sources
                ],
            ),
        ),
    ]

bluespec_library = rule(
    implementation = _bluespec_library_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(
            providers = [BluespecInfo, VerilogInfo],
        ),
        "synthesize": attr.string_list_dict(),
    },
    toolchains = ["//build/bluespec:toolchain_type"]
)

