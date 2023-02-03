#
# adapt to legacy build scripts
#
import os
import shutil
import subprocess
from setuptools.command.build_py import build_py

command_clear = [
    "python",
    "-c",
    "from clear import *;",
]

command_build = [
    "python",
    "-c",
    "from build import *; build_extensions();",
]


class this_build(build_py):

    def run(self):

        this_dir = os.path.dirname(os.path.realpath(__file__))
        build_dir = f"{this_dir}/build"
        shutil.rmtree(build_dir, True)

        subprocess.check_call(command_clear)
        subprocess.check_call(command_build)
        super().run()
