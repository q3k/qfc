workspace(
    name = "qfc",
)

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "rules_cc",
    urls = ["https://github.com/bazelbuild/rules_cc/releases/download/0.0.1/rules_cc-0.0.1.tar.gz"],
    sha256 = "4dccbfd22c0def164c8f47458bd50e0c7148f3d92002cdb459c2a96a68498241",
)

http_archive(
    name = "io_tweag_rules_nixpkgs",
    strip_prefix = "rules_nixpkgs-81f61c4b5afcf50665b7073f7fce4c1755b4b9a3",
    urls = ["https://github.com/tweag/rules_nixpkgs/archive/81f61c4b5afcf50665b7073f7fce4c1755b4b9a3.tar.gz"],
    sha256 = "33fd540d0283cf9956d0a5a640acb1430c81539a84069114beaf9640c96d221a",
)

load("@io_tweag_rules_nixpkgs//nixpkgs:repositories.bzl", "rules_nixpkgs_dependencies")
rules_nixpkgs_dependencies()

load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl", "nixpkgs_git_repository", "nixpkgs_package", "nixpkgs_cc_configure")

nixpkgs_git_repository(
    name = "nixpkgs",
    revision = "36f0cc6def05dea2b0e9ab0ff4b1dbd9e0d94dda",
    sha256 = "a40fb99f59df730883a45d78f3091e59080eace36b81139bc5bea1c453cbd7a7",
)

nixpkgs_cc_configure(
    name = "local_config_cc",
    repository = "@nixpkgs//:default.nix",
)

nixpkgs_package(
    name = "bluespec",
    repositories = { "nixpkgs": "@nixpkgs//:default.nix" },
    build_file_content = """
load("@qfc//build/bluespec:rules.bzl", "bluespec_toolchain")

sh_binary(
    name = "bsc",
    data = [
        "bin/bsc"
    ] + glob(["lib/**", "bin/core/**"]),
    srcs = [
        "@qfc//build/bluespec:bsc.sh",
    ],
    deps = [
        "@bazel_tools//tools/bash/runfiles",
    ],
)

sh_binary(
    name = "bluetcl",
    data = [
        "bin/bluetcl"
    ] + glob(["lib/**", "bin/core/**"]),
    srcs = [
        "@qfc//build/bluespec:bluetcl.sh",
    ],
    deps = [
        "@bazel_tools//tools/bash/runfiles",
    ],
)

bluespec_toolchain(
    name = "bsc_nixpkgs",
    bsc = ":bsc",
    bluetcl = ":bluetcl",
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
    repositories = { "nixpkgs2": "@nixpkgs//:default.nix" },
    nix_file_content = """
with import <nixpkgs2> {}; symlinkJoin {
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
