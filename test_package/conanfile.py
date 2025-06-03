import os
import subprocess
import sys
from conan import ConanFile
from conan.tools.build import can_run
from conan.tools.files import copy

class TestRenodePackage(ConanFile):
    settings = ["os"]

    def requirements(self):
        self.requires(self.tested_reference_str)
        self.requires("dotnet_tools/8.0.409@silabs")

    def test(self):
        renode_pkg = self.dependencies["renode"].package_folder
        if can_run(self):
            self.run("echo $PATH", env="conanrun")
            self.run("which dotnet", env="conanrun")
            self.run("./renode-test --help", env="conanrun", cwd=renode_pkg)
            self.run("./renode-test tests/unit-tests/RenodeTests/RenodeTests_NET.csproj", env="conanrun", cwd=renode_pkg)
