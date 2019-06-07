
from setuptools import setup, Extension
from Cython.Build import cythonize
from Cython.Distutils import build_ext
from pathlib import Path


source_files_directory = Path(__file__).resolve().parent.joinpath('lib', 'dxfeed-c-api', 'src')
source_files_paths = [str(path) for path in source_files_directory.glob('*.c')]
source_files_paths.remove(str(source_files_directory.joinpath('Linux.c')))

NAME = 'pcapi'
SRC_DIR = "lib"
PACKAGES = [SRC_DIR]

ext_connection = Extension(name=SRC_DIR + ".wrapper.connect",
                           sources=[SRC_DIR + "/wrapper/connect.pyx"] + source_files_paths,
                           libraries=['ws2_32'],
                           include_dirs=[SRC_DIR + "/dxfeed-c-api/include/", SRC_DIR + "/dxfeed-c-api/src"])

ext_subscription = Extension(name=SRC_DIR + ".wrapper.subscribe",
                             sources=[SRC_DIR + "/wrapper/subscribe.pyx"] + source_files_paths,
                             libraries=['ws2_32'],
                             include_dirs=[SRC_DIR + "/dxfeed-c-api/include/", SRC_DIR + "/dxfeed-c-api/src"] +
                             [SRC_DIR + '/wrapper/pxd_include'])

EXTENSIONS = [
    ext_connection,
    # ext_subscription,
]

if __name__ == "__main__":
    setup(
        # install_requires=REQUIRES,
        packages=PACKAGES,
        zip_safe=False,
        name=NAME,
        # version=VERSION,
        # description=DESCR,
        # author=AUTHOR,
        # author_email=EMAIL,
        # url=URL,
        # license=LICENSE,
        # package_data={PACKAGES[0]: [SRC_DIR + '/wrapper/pxd_include']},
        cmdclass={"build_ext": build_ext},
        ext_modules=cythonize(EXTENSIONS, language_level=3)
        )





# new_logic_ext = Extension(
#     name="pyconnect.wrapper",
#     sources=["lib/wrapper/connect.pyx"] + source_files_paths,
#     language='c',
#     include_dirs=["lib/dxfeed-c-api/include/", "lib/dxfeed-c-api/src"],
#     libraries=['ws2_32']
# )
#
# setup(
#     name="pyconnect",
#     packages=['pyconnect', 'pyconnect.wrapper'],
#     package_dir={'pyconnect': 'lib',
#                  'pyconnect.wrapper': 'lib/wrapper'
#                  },
#     package_data={'pyconnect': ["lib/wrapper/connect.pyx"] + source_files_paths,
#                   'pyconnect.wrapper': ["lib/wrapper/connect.pyx"] + source_files_paths
#                  },
#     ext_modules=cythonize([
#         new_logic_ext,
#         ], language_level=3),
#     cmdclass={'build_ext': build_ext}
# )