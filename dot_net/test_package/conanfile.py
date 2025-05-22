import os
from conan import ConanFile
from conan.tools.build import can_run


class DotnetTestPkg(ConanFile):
    # Install dotnet with Conan and run the version command to make sure it boots.
    settings = ["os"]

    def requirements(self):
        # This is a test package, so it must depend on the package under test.
        self.requires(self.tested_reference_str)

    def test(self):
        # Execute dotnet and make sure it runs.
        if can_run(self):
            self.run(f'dotnet --version', env="conanbuild")
            self.run(f'dotnet --help', env="conanbuild")
