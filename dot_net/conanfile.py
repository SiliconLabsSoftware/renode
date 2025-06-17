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
    user = "silabs"

    def build(self):
        base_url = f"https://dotnetcli.azureedge.net/dotnet/Sdk/{self.version}"
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

        # Always use strip_root=False for .NET SDK archives
        get(self, url, strip_root=False, keep_permissions=True)

    def package(self):
        copy(self, "*", src=self.source_folder, dst=self.package_folder)

    def package_info(self):
        bin_path = os.path.join(self.package_folder, ".")
        self.buildenv_info.append_path("PATH", bin_path)
        self.runenv_info.append_path("PATH", bin_path)
