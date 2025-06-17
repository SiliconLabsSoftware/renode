import os
from conan import ConanFile
from conan.tools.build import can_run


class DotnetTestPkg(ConanFile):
    settings = "os", "arch"
    test_type = "explicit"  # Explicitly define this is a test package

    def requirements(self):
        # This test package depends on the package under test
        self.requires(self.tested_reference_str)

    def test(self):
        if can_run(self):
            self.output.info("Testing dotnet installation...")
            self.run("dotnet --version", env="conanrun")
            self.run("dotnet --help", env="conanrun")
