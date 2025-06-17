from conan import ConanFile
from conan.tools.files import copy, load
import os

class RenodeConan(ConanFile):
    name = "renode"
    license = "MIT"
    url = "https://stash.silabs.com/projects/EMBSW/repos/renode/browse"
    description = "Antmicro's open source simulation and virtual development framework for complex embedded systems"
    topics = ("iot", "simulation", "embedded-systems", "arm", "risc-v", "x86")
    settings = "os", "arch"
    exports_sources = "*"
    user = "silabs"

    def set_version(self):
        version_path = os.path.join(self.recipe_folder, "tools", "version")
        self.version = load(self, version_path).strip()

    def requirements(self):
        self.tool_requires("dotnet_tools/8.0.409@silabs")
        self.tool_requires("cmake/3.27.6")

    def build(self):
        if self.settings.os == "Windows":
            self.run("build.cmd", cwd=self.source_folder, shell=True)
        else:
            self.run("dotnet --version", env="conanbuild")
            self.run("cmake --version", env="conanbuild")

            build_script = os.path.join(self.source_folder, "build.sh")
            if not os.path.isfile(build_script):
                raise FileNotFoundError(f"build.sh not found at {build_script}")
            self.run(f"chmod +x {build_script}")

            if self.settings.arch == "armv8":
                arch = "aarch64"
            elif self.settings.arch == "x86_64":
                arch = "x86_64"
            else:
                arch = "x86"

            self.run(f"{build_script} --net --host-arch {arch}", cwd=self.source_folder)

    def package(self):
        # Copy build output
        copy(self, "*", src=self.source_folder, dst=self.package_folder, keep_path=True)

    def package_info(self):
        renode_path = os.path.join(self.package_folder, ".")
        self.runenv_info.define("RENODE_HOME", self.package_folder)
        self.runenv_info.append_path("PATH", renode_path)
