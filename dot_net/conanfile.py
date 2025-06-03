from conan import ConanFile
from conan.tools.files import get, copy
import os

class DotnetToolsConan(ConanFile):
    name = "dotnet_tools"
    version = "8.0.409"
    license = "MIT"
    url = "https://dotnet.microsoft.com/en-us/download/dotnet/8.0"
    description = ".NET 8.0 SDK"
    settings = "os", "arch"
    package_type = "application"
    user = "silabs"
    build_policy = "missing"


    def layout(self):
        self.folders.source = "."
        self.folders.build = "build"
        self.folders.packages = "package"

    def requirements(self):
        pass  # No dependenciesw

    def build(self):
        # Download the correct SDK for the platform
        base_url = f"https://builds.dotnet.microsoft.com/dotnet/Sdk/{self.version}/"
        if self.settings.os == "Macos":
            if self.settings.arch == "x86_64":
                url = f"{base_url}/dotnet-sdk-{self.version}-osx-x64.tar.gz"
            elif self.settings.arch == "armv8":
                url = f"{base_url}/dotnet-sdk-{self.version}-osx-arm64.tar.gz"
            else:
                raise ValueError("Unsupported Macos architecture")
        elif self.settings.os == "Linux":
            if self.settings.arch == "x86_64":
                url = f"{base_url}/dotnet-sdk-{self.version}-linux-x64.tar.gz"
            elif self.settings.arch == "armv8":
                url = f"{base_url}/dotnet-sdk-{self.version}-linux-arm64.tar.gz"
            else:
                raise ValueError("Unsupported Linux architecture")
        elif self.settings.os == "Windows":
            if self.settings.arch == "x86_64":
                url = f"{base_url}/dotnet-sdk-{self.version}-win-x64.zip"
            elif self.settings.arch == "x86":
                url = f"{base_url}/dotnet-sdk-{self.version}-win-x86.zip"
            elif self.settings.arch == "armv8":
                url = f"{base_url}/dotnet-sdk-{self.version}-win-arm64.zip"
            else:
                raise ValueError("Unsupported Windows architecture")
        else:
            raise ValueError("Unsupported OS")

        # Use strip_root=True for tar.gz, but False for zip files to avoid ConanException
        if url.endswith(".zip"):
            get(self, url, strip_root=False, destination=self.build_folder)
        else:
            get(self, url, strip_root=True, destination=self.build_folder)

    def package(self):
        # Copy everything to the package folder
        copy(self, "*", src=self.build_folder, dst=os.path.join(self.package_folder, "."))

    def package_info(self):
        self.buildenv_info.append_path("PATH", os.path.join(self.package_folder, "."))
        self.runenv_info.append_path("PATH", os.path.join(self.package_folder, "."))
