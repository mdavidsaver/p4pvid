#!/usr/bin/env python

import sys
from setuptools import setup, Extension
from Cython.Build import cythonize

ext = Extension('p4pvid.v4l', ['p4pvid/v4l.pyx'])

setup(
    name='p4pvid',
    version='0.1',
    description="Stream a V4L2 device over PVA",
    author='Michael Davidsaver',
    author_email='mdavidsaver@gmail.com',
    license='BSD',
    python_requires='>=2.7',
    install_requires = [
        'p4p>=3.1.1',
        'Cython>=0.25.2',
    ],
    zip_safe = False,

    packages = ['p4pvid'],
    ext_modules=cythonize([ext]),
)
