workspace(
    name = "qfc",
)

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "io_tweag_rules_nixpkgs",
    strip_prefix = "rules_nixpkgs-a388ab60dea07c3fc182453e89ff1a67c9d3eba6",
    urls = ["https://github.com/tweag/rules_nixpkgs/archive/a388ab60dea07c3fc182453e89ff1a67c9d3eba6.tar.gz"],
    sha256 = "6bedf80d6cb82d3f1876e27f2ff9a2cc814d65f924deba14b49698bb1fb2a7f7",
)

load("@io_tweag_rules_nixpkgs//nixpkgs:repositories.bzl", "rules_nixpkgs_dependencies")
rules_nixpkgs_dependencies()

load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl", "nixpkgs_git_repository", "nixpkgs_package")

nixpkgs_git_repository(
    name = "nixpkgs",
    revision = "6b574cd85176ecc96af1b93bf5d004c884863159",
    sha256 = "5d04d42ddc5462e89aad66b9383abd41d784259b8be0234d1f6cd3972a8a8b3a",
)

nixpkgs_package(
    name = "bluespec",
    repositories = { "nixpkgs": "@nixpkgs//:default.nix" },
    build_file_content = """
load("@qfc//build:utils.bzl", "external_binary_tool")
load("@qfc//build/bluespec:rules.bzl", "bluespec_toolchain")

external_binary_tool(
    name = "bsc",
    bin = "bin/bsc",
    deps = glob(["lib/**", "bin/core/**"]),
)

bluespec_toolchain(
    name = "bsc_nixpkgs",
    bsc = ":bsc",
    verilog_lib = glob(["lib/Verilog/*.v"], [
        "lib/Verilog/BRAM2.v",
        "lib/Verilog/BRAM2Load.v",
        "lib/Verilog/ConstrainedRandom.v",
        "lib/Verilog/Convert*Z.v",
        "lib/Verilog/InoutConnect.v",
        "lib/Verilog/ProbeHook.v",
        "lib/Verilog/RegFileLoad.v",
        "lib/Verilog/ResolveZ.v",
        "lib/Verilog/main.v",
    ]),
)

toolchain(
    name = "bsc_nixpkgs_toolchain",
    exec_compatible_with = [
        "@platforms//os:linux",
    ],
    toolchain = ":bsc_nixpkgs",
    toolchain_type = "@qfc//build/bluespec:toolchain_type",
)
    """,
)

nixpkgs_package(
    name = "yosysflow",
    repositories = { "nixpkgs": "@nixpkgs//:default.nix" },
    nix_file_content = """
with import <nixpkgs> {}; symlinkJoin {
    name = "yosysflow";
    paths = with pkgs; [ yosys nextpnr trellis ];
}
    """,
    build_file_content = """
load("@qfc//build:utils.bzl", "external_binary_tool")
load("@qfc//build/synthesis:rules.bzl", "yosysflow_toolchain")

external_binary_tool(
    name = "yosys",
    bin = "bin/yosys",
    deps = glob([
        "bin/yosys-*",
        "share/yosys/**",
    ]),
)

external_binary_tool(
    name = "nextpnr_ecp5",
    bin = "bin/nextpnr-ecp5",
    deps = [],
)

external_binary_tool(
    name = "ecppack",
    bin = "bin/ecppack",
    deps = [],
)

yosysflow_toolchain(
    name = "yosysflow_nixpkgs_ecp5",
    yosys = ":yosys",
    nextpnr = ":nextpnr_ecp5",
    packer = ":ecppack",
)

toolchain(
    name = "yosysflow_nixpkgs_ecp5_toolchain",
    exec_compatible_with = [
        "@platforms//os:linux",
    ],
    target_compatible_with = [
        "@qfc//build/platforms:ecp5",
    ],
    toolchain = ":yosysflow_nixpkgs_ecp5",
    toolchain_type = "@qfc//build/synthesis:toolchain_type",
)
    """,
)

register_toolchains(
    "@bluespec//:bsc_nixpkgs_toolchain",
    "@yosysflow//:yosysflow_nixpkgs_ecp5_toolchain",
)
