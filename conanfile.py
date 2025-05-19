from conan import ConanFile
from conan.tools.files import copy
import os


class RenodeConan(ConanFile):
    name = "renode"
    license = "MIT"
    # We are having a copy of whatever is there on Stash in github for now.
    url = "https://stash.silabs.com/projects/EMBSW/repos/renode/browse"
    description = "Antmicro's open source simulation and virtual development framework for complex embedded systems"
    topics = ("iot", "simulation", "embedded-systems", "arm", "risc-v", "x86")
    settings = "os", "arch"
    # Copy all files from source folder to build folder
    exports_sources = "*"
    user = "silabs"
    # At this point, we do not have a process to build renode for multiple architectures.
    # So we are using the build_policy missing to build it for the other architectures, on the users machine.
    build_policy = "missing"

    def requirements(self):
        self.tool_requires("dotnet_tools/8.0.409@silabs")
        self.tool_requires("cmake/3.27.6")

    def set_version(self) -> None:
        with open(os.path.join(self.recipe_folder, "tools", "version"), "r") as f:
            self.version = f.read().strip()

    def layout(self):
        self.folders.build = "build"

    def build(self) -> None:
        if self.settings.os == "Windows":
            self.run("build.cmd", cwd=self.source_folder, shell=True)
        else:
            self.run("dotnet --version") 
            self.run("cmake --version")
            self.run("chmod +x build.sh", cwd=self.source_folder)
            if self.settings.arch == "armv8":
                self.run("./build.sh --net --host-arch aarch64", cwd=self.source_folder)
            elif self.settings.arch == "x86_64":
                self.run("./build.sh --net --host-arch x86_64", cwd=self.source_folder)
            else:
                self.run("./build.sh --net --host-arch x86", cwd=self.source_folder)

    def package(self) -> None:
        # Copy all files from build folder to package folder
        copy(self, "*", self.build_folder, self.package_folder)

        # Copy all files from current directory to package folder
        copy(self, "*", self.source_folder, self.package_folder, keep_path=True)

    def package_info(self) -> None:
        self.runenv_info.define("RENODE_HOME", self.package_folder)
        self.runenv_info.append_path("PATH", os.path.join(self.package_folder, "renode"))