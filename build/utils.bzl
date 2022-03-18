# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2022 Sergiusz Bazanski

def _external_binary_tool_impl(ctx):
    bin_ = ctx.file.bin

    executable = ctx.actions.declare_file(ctx.attr.name + ".bin")
    path = executable.path + ".runfiles/" + ctx.workspace_name + "/" + ctx.file.bin.short_path
    ctx.actions.write(
        output = executable,
        content = """#!/bin/sh
            exec "{}" $@
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

