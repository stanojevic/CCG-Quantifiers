# cython: boundscheck=False

import codecs
import copy
import glob
import os
import itertools
import re

from .combinators cimport *
from .category cimport Category, Atomic, Functor
from .rotations import TreeTransducer
from .grammar import Grammar

cdef list unary_normal = [
    TypeRaising(
        cat_arg=Category.from_str("NP"),
        cat_res=Category.from_str("S"),
        is_forward=True,
        is_order_preserving=True),
]

cdef list binary_normal = [
    B(is_forward=True , order=0, is_crossed=False),
    B(is_forward=True , order=1, is_crossed=False),
    B(is_forward=True , order=2, is_crossed=False),
    B(is_forward=False, order=0, is_crossed=False),
    B(is_forward=False, order=1, is_crossed=False),
    B(is_forward=False, order=1, is_crossed=True ),
    Conj(is_bottom=False),
    Conj(is_bottom=True),
    S(is_forward=False, is_crossed=True),
    Punc(punc_is_left=True),
    Punc(punc_is_left=False),
]

cdef inline UnaryCombinator recognize_unary_comb(Category cat_child, cat_parent):
    cdef UnaryCombinator c
    for c in unary_normal:
        if c.can_apply(cat_child) and c.apply(cat_child).equals(cat_parent):
            return c
    return TypeChanging1(cat_from=cat_child, cat_to=cat_parent)

cdef inline BinaryCombinator recognize_binary_comb(Category left, Category right, Category parent):
    cdef BinaryCombinator c
    for c in binary_normal:
        if c.can_apply(left, right) and c.apply(left, right).equals(parent):
            return c
    if left.is_atomic and (<Atomic> left).is_conj_atom and parent.is_right_adj_cat and (<Functor> parent).res == right:
        return Conj(is_bottom=True)
    return TypeChanging2(left=left, right=right, parent=parent)


# noinspection PyPackageRequirements
cdef class Node:

    def __cinit__(self):
        self._span_memo = None

    def topological_grouping(self):
        if self.is_term:
            return [[self]]
        elif self.is_unary:
            return self.child.topological_grouping() + [[self]]
        elif self.is_binary:
            ltop = self.left.topological_grouping()
            rtop = self.right.topological_grouping()
            res = []
            for i in range(min(len(ltop), len(rtop))):
                res.append(ltop[i]+rtop[i])
            mtop = ltop if len(ltop)>len(rtop) else rtop
            res += mtop[len(res):]
            res += [[self]]
            return res
        else:
            raise Exception("I didn't expect this")

    def __deepcopy__(self, memo):
        if self.is_unary:
            return Unary(copy.deepcopy(self.comb, memo), copy.deepcopy(self.child, memo))
        elif self.is_binary:
            return Binary(copy.deepcopy(self.comb, memo), copy.deepcopy(self.left, memo), copy.deepcopy(self.right, memo))
        elif self.is_term:
            return Terminal(copy.deepcopy(self.cat, memo), copy.deepcopy(self.word, memo), copy.deepcopy(self.pos, memo))
        else:
            raise Exception("I didn't expect this")

    property span:
        def __get__(self):
            cdef int pos
            if self._span_memo is None:
                if self.is_term:
                    pos = (<Terminal> self).pos
                    if pos<0:
                        raise Exception("terminal's position is not initialized")
                    self._span_memo = (pos, pos+1)
                elif self.is_unary:
                    self._span_memo = (<Unary> self).child.span
                else:
                    self._span_memo = ((<Binary> self).left.span[0], (<Binary> self).right.span[1])
            return self._span_memo

    cpdef void assign_word_positions(self):
        i = 0
        queue = [self]
        while queue:
            n = queue.pop()
            if n.is_term:
                if n.pos < 0:
                    n.pos = i
                i+=1
            else:
                queue.extend(reversed(n.children))

    cpdef list words(self):
        return [n.word for n in self.iter_terminals()]

    cpdef list stags(self):
        return [n.cat for n in self.iter_terminals()]

    def iter_terminals(self):
        iter_terms = filter(lambda n: n.is_term, self.iter_preorder())
        return iter_terms

    def iter_preorder(self):
        stack = [self]
        while stack:
            x = stack.pop()
            yield x
            stack.extend(reversed(x.children))

    def list_postorder(self):
        x = []
        self._list_postorder_rec(x)
        return x

    cdef _list_postorder_rec(self, list x):
        if self.is_unary:
            (<Unary> self).child._list_postorder_rec(x)
        elif self.is_binary:
            (<Binary> self).left._list_postorder_rec(x)
            (<Binary> self).right._list_postorder_rec(x)
        x.append(self)
        return x

    def _repr_svg_(self):
        from .visualization import CCG_dot_Visualize
        return CCG_dot_Visualize.ipython_svg(self)

    def print_latex(self):
        from .visualization import LaTeX
        print(LaTeX.to_latex(self))

    def save_proof(self, fn: str):
        from .visualization import LaTeX
        LaTeX.save_image(self, fn)

    def visualize_proof(self):
        from .visualization import LaTeX
        LaTeX.visualize(self)

    def _revealing_warning(self):
        if [n for n in self.iter_preorder() if n.is_binary and n.comb.is_special_right_adj]:
            return "this tree contains revealing nodes so the dependencies shown bellow "+ \
                   "are only an approximation of what happens when revealing is used."
        else:
            return ""

    def _show_image_with_title(self, img, title: str= None, warning: str= None):
        from IPython.display import Image, display, HTML
        display(HTML("<br/>"))
        if title:
            display(HTML(f"<b><font size=\"3\" color=\"red\">{title}</font></b>"))
        if warning:
            display(HTML(f"<font color=\"red\">WARNING: {warning}</font>"))
        if isinstance(img, str):
            display(Image(img))
        else:
            display(img)

    def show_proof(self, title: str=None):
        from edin.utils.tree_visualization import create_temp_file
        tmp_fn = create_temp_file("", "png")
        self.save_proof(tmp_fn)
        self._show_image_with_title(tmp_fn, title)

    def save_deps(self, fn:str, lang="English", include_conj_term=False):
        from .predarg import PredArgAssigner
        pa = PredArgAssigner(lang=lang, include_conj_term=include_conj_term)
        pa.all_deps_save(self, fn=fn)

    def show_deps(self, title=None, lang="English", include_conj_term=False):
        from .predarg import PredArgAssigner
        pa = PredArgAssigner(lang=lang, include_conj_term=include_conj_term)
        self._show_image_with_title(pa.show_all_deps(self),
                                    title=title,
                                    warning=self._revealing_warning())

    def visualize(self, name: str = "CCG derivation", file_type: str = "pdf"):
        from .visualization import CCG_dot_Visualize
        CCG_dot_Visualize.visualize(self, graph_label=name, file_type=file_type)

    def save_visual(self, fn: str):
        from .visualization import CCG_dot_Visualize
        CCG_dot_Visualize.save(self, fn)

    def print_ascii(self, title=""):
        from .visualization import ASCII_Art
        if title:
            print(title)
        print(ASCII_Art.deriv2ascii(self))

    def __str__(self):
        return self.to_ccgbank_str(with_indentation=False, comb_instead_of_cat=False)

    def to_ccgbank_str(self, depth: int = 0, with_indentation: bool = False, comb_instead_of_cat: bool = False):
        indentation = " "*depth*4 if with_indentation else ""
        nl = "\n" if with_indentation else " "
        if self.is_unary:
            if comb_instead_of_cat:
                c = str(self.comb)
            else:
                c = "<T %s 0 1>" % str(self.cat)
            return "".join([
                indentation,
                "(",
                c,
                nl,
                self.child.to_ccgbank_str(depth+1, with_indentation),
                " )"])
        elif self.is_binary:
            if comb_instead_of_cat:
                c = str(self.comb)
            else:
                if (isinstance(self.comb, B) and self.comb.is_backward) or \
                        (isinstance(self.comb, Punc) and self.comb.punc_is_left):
                    head_pointer = 1
                else:
                    head_pointer = 0
                c = "<T %s %d 2>" % (str(self.cat), head_pointer)
            return "".join([
                indentation,
                "(",
                c,
                nl,
                self.left.to_ccgbank_str(depth+1, with_indentation),
                nl,
                self.right.to_ccgbank_str(depth+1, with_indentation),
                " )"])
        elif self.is_term:
            return "%s(<L %s X X %s %s>)" % (indentation, self.cat, escape_bracket(self.word), self.cat)

    def to_left_branching(self, is_extreme: bool = True):
        transducer = TreeTransducer(is_extreme=is_extreme, g=Grammar())
        return transducer.to_left_branching(self)

    def to_left_branching_with_revealing(self, is_extreme: bool = True):
        transducer = TreeTransducer(is_extreme=is_extreme, g=Grammar())
        return transducer.to_left_branching_with_revealing(self)

    def to_right_branching(self, is_extreme: bool = True):
        transducer = TreeTransducer(is_extreme=is_extreme, g=Grammar())
        return transducer.to_right_branching(self)

cdef class Terminal(Node):

    def __reduce__(self):
        return Terminal, (self.cat, self.word, self.pos)

    def __cinit__(self, Category cat, str word, int pos = -1):
        self.cat = cat
        self.is_term   = True
        self.is_binary = False
        self.is_unary  = False
        self.word = word
        self.pos = pos
        self.children = []


cdef class Unary(Node):

    def __reduce__(self):
        return Unary, (self.comb, self.child)

    def __cinit__(self, UnaryCombinator comb, Node child):
        assert comb.can_apply(child.cat), "%s can't apply to %s" % (comb, child.cat)
        self.cat       = comb.apply(child.cat)
        self.is_term   = False
        self.is_binary = False
        self.is_unary  = True
        self.comb      = comb
        self.child     = child
        self.children  = [child]


cdef class Binary(Node):

    def __reduce__(self):
        return Binary, (self.comb, self.left, self.right)

    def __cinit__(self, BinaryCombinator comb, Node left, Node right):
        assert comb.can_apply(left.cat, right.cat), "%s can't combine %s and %s" % (comb, left.cat, right.cat)
        self.cat = comb.apply(left.cat, right.cat)
        self.is_term   = False
        self.is_binary = True
        self.is_unary  = False
        self.comb = comb
        self.left = left
        self.right = right
        self.children = [left, right]


cdef list _brackets = [
    ("{", "-LCB-"),
    ("}", "-RCB-"),
    ("[", "-LSB-"),
    ("]", "-RSB-"),
    ("(", "-LRB-"),
    (")", "-RRB-")
]


# escape only when reading in ccgbank format
cdef inline str unescape_bracket(str s):
    cdef str a, b
    for a, b in _brackets:
        if b == s:
            return a
    return s.replace("-LANGLE-", "<").replace("-RANGLE-", ">")


# escape only when printing in ccgbank format
cdef inline str escape_bracket(str s):
    cdef str a, b
    for a, b in _brackets:
        if a == s:
            return b
    return s.replace("<", "-LANGLE-").replace(">", "-RANGLE-")


cdef class DerivationLoader:

    @staticmethod
    def _files_from_treebank(str dir_name):
        def f2id(f: str):
            return int(f.split(".")[-2].split("_")[-1])
        def many_file_single_iterator(fs):
            return itertools.chain.from_iterable(map(DerivationLoader.iter_from_file, fs))
        files = glob.glob(os.path.join(dir_name, "**", "*.auto"), recursive=True)
        if not files:
            files = glob.glob(os.path.join(dir_name, "**", "*.fid"), recursive=True)
            if not files:
                raise Exception("this is nether English nor Chinese CCGbank")
        files = sorted(filter(os.path.isfile, files))
        return [(f2id(f), f) for f in files]

    @staticmethod
    def iter_from_treebank_train(str dir_name):
        return DerivationLoader._iter_from_treebank_general(dir_name, True, False, False, False)

    @staticmethod
    def iter_from_treebank_dev(str dir_name):
        return DerivationLoader._iter_from_treebank_general(dir_name, False, True, False, False)

    @staticmethod
    def iter_from_treebank_test(str dir_name):
        return DerivationLoader._iter_from_treebank_general(dir_name, False, False, True, False)

    @staticmethod
    def iter_from_treebank_rest(str dir_name):
        return DerivationLoader._iter_from_treebank_general(dir_name, False, False, False, True)

    @staticmethod
    def _iter_from_treebank_general(
            str dir_name, bint select_train, bint select_dev, bint select_test, bint select_rest):
        cdef list id_files = DerivationLoader._files_from_treebank(dir_name)
        cdef bint is_english = id_files[0][1].endswith(".auto")
        cdef bint is_chinese = id_files[0][1].endswith(".fid")
        cdef int fid, sec
        cdef str file
        cdef list selected = []
        for fid, file in id_files:
            if is_english:
                sec = fid//100
                if 2 <= sec <=21:
                    if select_train:
                        selected.append(file)
                elif sec == 0:
                    if select_dev:
                        selected.append(file)
                elif sec == 23:
                    if select_test:
                        selected.append(file)
                elif select_rest:
                    selected.append(file)
            elif is_chinese:
                if 2000 <= fid <=2980:
                    if select_train:
                        selected.append(file)
                elif 2981 <= fid <= 3029:
                    if select_dev:
                        selected.append(file)
                elif 3030 <= fid <= 3145:
                    if select_test:
                        selected.append(file)
                elif select_rest:
                    selected.append(file)
            else:
                raise Exception("unknown file extension")
        return itertools.chain.from_iterable(map(DerivationLoader.iter_from_file, selected))

    @staticmethod
    def iter_from_file(str fn):
        cdef str line
        with codecs.open(fn, "r", encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("("):
                    yield DerivationLoader.from_str(line)

    @staticmethod
    def from_str(str in_string):
        cdef list tokens = DerivationLoader._tokenize(in_string)
        cdef Node node
        cdef int pos
        node, pos = DerivationLoader._process_tokens(tokens, 0)
        assert pos == len(tokens)
        node.assign_word_positions()
        return node

    @staticmethod
    cdef tuple _process_tokens(list tokens, int next_token):
        assert tokens[next_token] == "(", f"token {next_token}  {tokens[next_token]} is not ("
        next_token += 1
        assert tokens[next_token] == "<", f"token {next_token}  {tokens[next_token]} is not <"
        next_token += 1

        cdef Node node, child
        cdef list children
        cdef Combinator comb

        if tokens[next_token] == "T":
            next_token += 1
            cat = Category.from_str(tokens[next_token])
            next_token += 1
            if tokens[next_token + 3] == ">":
                # some parser use this wrong format where
                # they add additional column for combinator type
                next_token += 1
            # head_index = tokens[next_token]
            next_token += 1
            # children_count = tokens[next_token]
            next_token += 1
            assert tokens[next_token] == ">"
            next_token += 1

            children = []
            while tokens[next_token] == "(":
                child, next_token = DerivationLoader._process_tokens(tokens, next_token)
                children.append(child)
            assert tokens[next_token] == ")"
            next_token += 1
            if len(children) == 1:
                child = children[0]
                if child.cat.equals(cat):
                    # this is an error in the treebank; ignore this unary rule
                    node = child
                else:
                    comb = recognize_unary_comb(child.cat, cat)
                    node = Unary(comb, child)
            elif len(children) == 2:
                [left, right] = children
                comb = recognize_binary_comb(left.cat, right.cat, cat)
                node = Binary(comb, left, right)
            else:
                raise Exception("Wrong number of children in CCG file")
        elif tokens[next_token] == "L":
            if tokens[next_token + 6] == ">" and tokens[next_token + 7] == ")":
                # standard CCG-bank
                cat = Category.from_str(tokens[next_token + 1])
                # modified_pos = tokens[next_token+2]
                # original_pos = tokens[next_token+3]
                word = tokens[next_token + 4]
                # pred_arg_CCG = tokens[next_token+5]
                next_token += 8
            elif tokens[next_token + 8] == ">" and tokens[next_token + 9] == ")":
                # non-standard format
                cat = Category.from_str(tokens[next_token + 1])
                word = tokens[next_token + 2]
                # lemma = tokens[next_token+3]
                # original_pos = tokens[next_token+4]
                # named_entity = tokens[next_token+5]
                # named_entity2 = tokens[next_token+6]
                # pred_arg_CCG = tokens[next_token+7]
                next_token += 10
            else:
                raise Exception("wrong format")

            node = Terminal(cat=cat, word=unescape_bracket(word))
        else:
            raise Exception("unknown node type %s" % tokens[next_token])
        return node, next_token

    @staticmethod
    cdef inline list _tokenize(str string):
        return string \
                     .replace("<", " < ") \
                     .replace(">", " > ") \
                     .replace("  ", " ") \
                     .strip() \
                     .split(" ")


cdef list _tokenization_patterns = [
    (re.compile("\\.\\.\\."            ), " ... "  ),  # three dots
    (re.compile("([,;:@#$%&?!])"       ), " \\1 "  ),  # all kinds of punctuation
    (re.compile("([\\]\\[(){}<>])"     ), " \\1 "  ),  # separating all possible brackets
    (re.compile("(--)"                 ), " \\1 "  ),  # double dash
    (re.compile("\""                   ), " '' "   ),  # making quotes more uniform
    (re.compile("``"                   ), " '' "   ),  # making quotes more uniform
    (re.compile("'([sSmMdD]) "         ), " '\\1 " ),  # for possesives, I'm and he'd
    (re.compile("'(ll|re|ve|LL|RE|VE) "), " '\\1 " ),  # for we're you'll you've etc.
    (re.compile("(n't|N'T) "           ), " \\1 "  ),  # negation
    (re.compile("([?!.] *$)"           ), " \\1 "  ),  # punctuation in the end of the sentence
]


cpdef list tokenize(str sent):
    cdef object p
    cdef str r
    for p, r in _tokenization_patterns:
        sent = p.sub(r, sent)
    return sent.split()
