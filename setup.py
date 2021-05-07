from distutils.core import setup
from Cython.Build import cythonize

setup(
    author="Miloš Stanojević",
    author_email="milosh.stanojevic@gmail.com",
    version="0.0.1",
    ext_modules=cythonize("edin/**/*.pyx", language_level=3),
    url="https://github.com/stanojevic/ccg-tools-private",
    classifiers=[
                    "Programming Language :: Python :: 3",
                    "License :: OSI Approved :: Apache License 2.0",
                    "Operating System :: OS Independent",
                ],
)
