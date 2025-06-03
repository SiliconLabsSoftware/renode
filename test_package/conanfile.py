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

    def build(self):
        pass


    def test(self):
        self.output.info("Building test package...")
        venv_path = os.path.join(self.build_folder, "venv")
        if os.name != "nt":
            pip_exe = os.path.join(venv_path, "bin", "pip")
        else:
            pip_exe = os.path.join(venv_path, "Scripts", "pip.exe")

        # 1. Create a virtual environment using the current Python
        self.output.info("Creating Python virtual environment...")
        self.run(f'"{sys.executable}" -m venv "{venv_path}"')

        # 2. Upgrade pip and install requirements
        self.output.info("Installing Python dependencies...")
        self.run(f'"{pip_exe}" install --upgrade pip')
        self.run(f'"{pip_exe}" install -r "{os.path.join(self.source_folder, "../tests/requirements.txt")}"')

        # 3. Install the requirements for the tools
        self.run(f'"{pip_exe}" install -r "{os.path.join(self.source_folder, "../tools/csv2resd/requirements.txt")}"')
        self.run(f'"{pip_exe}" install -r "{os.path.join(self.source_folder, "../tools/execution_tracer/requirements.txt")}"')

        # Optionally store Python path for later test usage
        self.runenv_info.define_path("PYTHONPATH", venv_path)
        
        renode_pkg = self.dependencies["renode"].package_folder
        if can_run(self):
            self.run("echo $PATH", env="conanrun")
            self.run("which dotnet", env="conanrun")
            self.run("./renode-test --help", env="conanrun", cwd=renode_pkg)
            self.run("./renode-test tests/unit-tests/RenodeTests/RenodeTests_NET.csproj", env="conanrun", cwd=renode_pkg)
