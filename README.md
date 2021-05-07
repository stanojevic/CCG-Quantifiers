# CCG Quantifiers

This code implements the ideas presented in:

Computing All Quantifier Scopes with CCG  
IWCS 2021  
Miloš Stanojević and Mark Steedman

It takes as input a CCG parse in AUTO format (CCGbank format) and annotates it with logical semantics.
This implementation is mostly a proof of concept how all quantifier scopes can be computed.
It cannot process all possible trees that come out of the CCG parser because it has logical forms only for a handful of lexical categories.
This will likely change in the future.

## Installation

### Requirements

All python package requirements of this code base is in requirements.txt. To install them type:

    pip3 install -r requirements.txt

In addition to python packages, your system needs to have imagemagic, graphviz and latex installed.
To do that on ubuntu you can run:

    sudo apt install imagemagic graphviz texlive-full

After that is done, you need to compile the cython code with the following command:

    python3 setup.py build_ext --inplace

### Possible problems with ImageMagic security

On some systems there is a problem with security settings of ImageMagic where
it's set up so that conversion from PDF is considered unsafe. To change that
modify /etc/ImageMagick-*/policy.xml file by adding (or uncommenting):

    <policy domain="coder" rights="read | write" pattern="PDF" />

just before \</policymap\>

This matters only if you are using the notebook and only if you encounter problems.

## Notebook

You can start by playing with the provided notebook by running:

    jupyter notebook notebook_simple.ipynb

## Author
Miloš Stanojević
milosh.stanojevic@gmail.com
