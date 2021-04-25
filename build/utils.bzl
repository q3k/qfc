def _external_binary_tool_impl(ctx):
    executable = ctx.actions.declare_file(ctx.attr.name + ".bin")
    path = ctx.file.bin.path
    strip = "external/"
    if not path.startswith(strip):
        fail("Unexpected path {}".format(path))
    path = path[len(strip):]
    ctx.actions.write(
        output = executable,
        content = """#!/usr/bin/env sh
            sp="{}"
            bin=$0.runfiles/$sp
            exec $bin $@
        """.format(path),
        is_executable = True,
    )

    files = depset([executable])
    runfiles = ctx.runfiles(files = [ctx.file.bin, executable] + ctx.files.deps)
    res = [
        DefaultInfo(files=files, runfiles=runfiles, executable=executable),
    ]
    return res

external_binary_tool = rule(
    implementation = _external_binary_tool_impl,
    attrs = {
        "bin": attr.label(
            executable = True,
            allow_single_file = True,
            cfg = "exec",
        ),
        "deps": attr.label_list(
            allow_files = True,
        ),
    },
)

