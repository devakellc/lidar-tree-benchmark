"""Convert the paper's markdown to the IEEE JSTARS LaTeX version.

Reads paper/manuscript.md, paper/supplement.md, paper/figures/ and
docs/references.bib, and writes main.tex (IEEEtran journal class),
supplement.tex (article class) and an IEEE copy of the bibliography to OUT.
Every markdown citation becomes \\cite, every manuscript cross-reference
becomes \\ref in IEEE numbering (Section IV-B, Table III, Fig. 2(d)), tables
become table or table* floats (xltabular in the supplement), and the remaining
Unicode is mapped to LaTeX so both documents compile with pdfLaTeX + BibTeX,
Overleaf's default. The highlights are dropped, the keywords become IEEE Index
Terms, headings take IEEE headline style, and the AI-use statement moves into
the Acknowledgment as IEEE asks.

A figure is included as the PDF beside its PNG (figure_3.pdf beside
figure_3.png) when there is one and as the PNG otherwise; its width follows the
PNG's aspect ratio. The manuscript's floats go at the top of a page or, when
the floats waiting fill most of a page, on a page of their own ([!tp]), so no
text page is left with floats alone. The supplement's figures (Figure S1) are
labelled in the text like its tables, without LaTeX's numbering; they float
([!ht]) so that the text of their section fills the page before them, and a
barrier before each section keeps them in their own section. References to
them (Fig. S1, Fig S1) stay as text in both documents. Display math ($$...$$)
becomes a numbered equation in main.tex and stays unnumbered in the
supplement; it joins the paragraph before it, and the text after it when that
text continues the sentence in lower case. Inline math ($...$) is kept, and the
Unicode symbols in math become math commands. A fenced code block is copied
as it is, as verbatim: no citation, reference, link, math or Unicode in it is
converted, and its language (```sh) is dropped, as the LaTeX has no
highlighting macros.

The columns of a table that wrap (tabularx's X columns, which xltabular shares)
take widths in proportion to their text, the printed width of their cells
estimated from the fonts' metrics, but none is narrower than half an equal
share or than its longest word; a table keeps equal widths unless the
estimate finds it shorter with unequal ones.

The IEEE copy of the bibliography is written for IEEEtran.bst, which ignores
several fields. Software and dataset entries become misc entries. The version,
the access date (urldate), the DOI (last, as in IEEE's reference forms) and,
for an entry without a DOI, the arXiv identifier move into the note; IEEE
cites the version of record, so a paper with a DOI is cited without its arXiv
identifier, and the arXiv primary class is not printed. A misc entry's
publisher becomes its howpublished or organization unless it repeats the
author, and the maintainer's "Undated page" note gives way to the access date.
In titles only acronyms, single capitals and words with inner capitals are
brace-protected; other words follow the style's sentence case, so proper nouns
are braced in docs/references.bib. A note's leading acronym and its "Accessed"
label are braced, accented letters are written as LaTeX accents, and a control
entry makes IEEEtran.bst print the first author and "et al." when there are
more than six, as IEEE asks.

The converter stops with an error instead of guessing when it meets markdown it
does not handle: a bracketed citation with a prefix or locator, a narrative
citation followed by a bracket, a reference to a section, table or figure that
neither the manuscript nor the supplement has, a caption not followed by its
table, a table without a caption, an image without a "Figure N." caption
("Figure Sn." in the supplement), a figure that is not a PNG file under paper/,
a table cell, caption or heading that pandoc would read as a block or that
holds display math, display math outside the body text or in a ```math fence
(GitHub's other form), a character in math that has no LaTeX mapping, a code
fence that is never closed, an indented code block (code must be fenced), a
character outside ASCII in a code block, or a BibTeX form it does not parse
(@string, @preamble, @comment, "#" concatenation or a macro value).

Arguments are KEY=VALUE pairs:
  OUT=paper/ieee        output directory (relative to the repository root)
  PANDOC=pandoc         pandoc binary (3.x)
  ZIP=path.zip          also write an Overleaf upload zip with the sources and
                        the figure files they include

  python3 scripts/paper_to_ieee.py PANDOC=/path/to/pandoc \\
    ZIP=work/paper-ieee/jstars-overleaf.zip
"""
import math
import re
import shutil
import subprocess
import sys
import textwrap
import unicodedata
import zipfile
from pathlib import Path, PurePosixPath
from struct import unpack

REPO = Path(__file__).resolve().parents[1]
PANDOC = "pandoc"
REPO_URL = "https://github.com/devakellc/lidar-tree-benchmark/blob/main/"
NBSP = "\u00a0"
SEP = "ZZSNIPSEPZZ"
# The IEEE (headline-style) form of the manuscript's "Full title:" line. The
# build stops if the two differ other than in case, so a retitled manuscript
# cannot leave a stale title here.
TITLE_IEEE = ("Choosing Tree Detectors by Point Density: A Field-Stem Benchmark for National-Mapping "
              "Airborne LiDAR")

# --------------------------------------------------------------------- helpers


def pandoc(md):
    # pandoc's smart quotes read an apostrophe right after a code span as an
    # opening quote; a typographic apostrophe avoids that. Code blocks keep
    # their text but lose their language (```sh), so pandoc writes each as
    # plain verbatim, which needs no highlighting macros in the preamble.
    md, code = hold_code(md)
    md = restore_code(md.replace("`'", "`\u2019"), [bare_fence(block) for block in code])
    try:
        r = subprocess.run(
            [PANDOC, "-f", "markdown+raw_tex-citations-auto_identifiers-implicit_figures-subscript-superscript"
             "-fancy_lists-example_lists",
             "-t", "latex", "--wrap=preserve"],
            input=md, capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        raise SystemExit(f"pandoc failed with exit status {e.returncode}: {e.stderr.strip()}")
    return r.stdout


BLOCK_MARK = re.compile(r"[>:~=|]|[-+*#](?=\s|$)")
BLOCK_TEX = re.compile(r"\\(begin\{(itemize|enumerate|description|quote|quotation|center|longtable)\}"
                       r"|(sub)*section\*?\{|rule\{)")


def pandoc_snippets(snips, inline=True):
    """Convert many markdown snippets in one pandoc call. Inline snippets
    (table cells, captions, headings) are guarded so that pandoc cannot read
    them as a block, and the build stops if one still becomes a block; whole
    back-matter sections are converted as they are (inline=False)."""
    guarded = []
    for s in snips:
        s = s.strip()
        if inline:
            # Escape a leading marker that would start a list, heading, quote,
            # definition, rule or table; emphasis such as *Pinus* stays.
            if re.match(r"\d+[.)](\s|$)", s):
                s = re.sub(r"^(\d+)([.)])", r"\1\\\2", s)
            elif BLOCK_MARK.match(s):
                s = "\\" + s
        guarded.append(s)
    # Two blank lines: pandoc allows at most one between a definition term
    # and its definition, so the separator can never join a definition list.
    out = pandoc(f"\n\n\n{SEP}\n\n\n".join(guarded) + "\n")
    parts = [p.strip() for p in out.split(SEP)]
    if len(parts) != len(snips):
        raise SystemExit(f"snippet split mismatch: {len(parts)} vs {len(snips)}")
    if inline:
        for src, part in zip(snips, parts):
            if BLOCK_TEX.search(part):
                raise SystemExit(f"inline snippet became a block: {src!r} -> {part!r}")
            if any(display for _, _, display in math_spans(part)):
                raise SystemExit(f"display math in a table cell, caption or heading: {src!r}")
    return parts


# ----------------------------------------------------------------- code blocks

FENCE = re.compile(r"[ \t]*(`{3,}|~{3,})(.*)")
VERBATIM = re.compile(r"\\begin\{verbatim\}.*?\\end\{verbatim\}", re.S)


def hold_code(md):
    """Set the fenced code blocks aside, so that no markdown transform
    (citations, links, references, headings, tables, figures) touches code:
    (md with each block replaced by a placeholder line at its indentation,
    [blocks]); restore_code puts them back before pandoc runs. A fence that is
    never closed stops the build, as pandoc would read the rest as code."""
    lines, out, code, i = md.split("\n"), [], [], 0
    while i < len(lines):
        m = FENCE.fullmatch(lines[i])
        if not m or (m.group(1)[0] == "`" and "`" in m.group(2)):  # ```a`b opens inline code
            out.append(lines[i])
            i += 1
            continue
        close = re.compile(rf"[ \t]*{re.escape(m.group(1)[0])}{{{len(m.group(1))},}}[ \t]*")
        j = next((k for k in range(i + 1, len(lines)) if close.fullmatch(lines[k])), None)
        if j is None:
            raise SystemExit(f"a code fence that is never closed: {lines[i].strip()!r}")
        indent = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
        out.append(f"{indent}ZZCODE{len(code)}ZZ")
        code.append("\n".join([lines[i][len(indent):]] + lines[i + 1:j + 1]))
        i = j + 1
    return "\n".join(out), code


def restore_code(md, code):
    """Put back the code blocks that hold_code set aside."""
    for n, block in enumerate(code):
        tok = f"ZZCODE{n}ZZ"
        if md.count(tok) != 1:
            raise SystemExit(f"a code block in a caption, table or heading: {block[:60]!r}")
        md = md.replace(tok, block)
    return md


def bare_fence(block):
    """A code block without its language or attributes (```sh -> ```)."""
    head, rest = block.split("\n", 1)
    return FENCE.fullmatch(head).group(1) + "\n" + rest


def verbatim_spans(tex):
    """[(start, end)] of pandoc's verbatim environments, its code blocks, which
    the LaTeX transforms leave as they are."""
    return [m.span() for m in VERBATIM.finditer(tex)]


def check_code_blocks(tex, fenced):
    """Every verbatim environment must come from one of the fenced code
    blocks: an indented code block has been through the markdown transforms."""
    if len(verbatim_spans(tex)) != fenced:
        raise SystemExit("an indented code block (or a raw verbatim environment): fence code with ```")


def code_to_latex(code):
    """A code block is copied as it is, so it must be ASCII."""
    bad = next((c for c in code if ord(c) > 127), None)
    if bad:
        raise SystemExit(f"{bad!r} U+{ord(bad):04X} in a code block, which is copied verbatim: write code in ASCII")
    return code


# ------------------------------------------------------------------------ math

MATH_OPEN = {"(": "\\)", "[": "\\]"}


def math_spans(tex):
    """[(start, end, display)] of the math in pandoc's LaTeX: \\(...\\) inline,
    \\[...\\] display, and the equation environments made from the latter.
    Pandoc escapes a literal backslash, bracket or parenthesis in text, so only
    math opens these; a doubled backslash (a line break, as in \\\\[4pt])
    opens nothing. Code blocks (verbatim), which pandoc does not escape, are
    skipped."""
    verbatim = verbatim_spans(tex)
    spans, i = [], 0
    while (j := tex.find("\\", i)) >= 0:
        code_end = next((e for s, e in verbatim if s <= j < e), None)
        if code_end is not None:
            i = code_end
            continue
        if tex[j + 1:j + 2] in MATH_OPEN:
            close = MATH_OPEN[tex[j + 1]]
        elif tex.startswith("\\begin{equation}", j):
            close = "\\end{equation}"
        else:
            i = j + 2  # an escaped character or a control word
            continue
        k = j + 2
        while not tex.startswith(close, k):
            k = tex.find("\\", k if tex[k:k + 1] != "\\" else k + 2)
            if k < 0:
                raise SystemExit(f"unterminated math: {tex[j:j + 60]!r}")
        spans.append((j, k + len(close), tex[j + 1] != "("))
        i = k + len(close)
    return spans


# Math takes math commands for the symbols that text maps to $...$.
MATH_UNICODE = {"\u2212": "-", "\u00d7": "\\times{}", "\u03c4": "\\tau{}", "\u2264": "\\leq{}",
                "\u2265": "\\geq{}", "\u00b7": "\\cdot{}", "\u00b2": "^{2}", NBSP: "~"}


def math_to_latex(math):
    out = "".join(MATH_UNICODE.get(c, c) for c in math)
    bad = next((c for c in out if ord(c) > 127), None)
    if bad:
        raise SystemExit(f"no LaTeX mapping for {bad!r} U+{ord(bad):04X} in math: {math!r}")
    return out


MATH_FENCE = re.compile(r"(?m)^[ \t]*(?:`{3,}|~{3,})[ \t]*\{?[ \t]*\.?math\b")


def check_math_fence(md):
    """GitHub also reads a ```math fence as display math; pandoc reads it as a
    code listing, so the build stops instead."""
    if MATH_FENCE.search(md):
        raise SystemExit("a ```math fence: write display math as $$...$$")


def display_math(tex, numbered):
    """Display math as an equation environment (numbered, as IEEE numbers
    displayed equations) or as \\[...\\]. A display joins the paragraph before
    it, since a blank line there would print an empty line, and the text after
    it when that text continues the sentence in lower case ('where ...')."""
    out, i = [], 0
    for start, end, _ in math_spans(tex):
        if not tex.startswith("\\[", start):
            continue  # inline math, or an equation environment already
        out.append(re.sub(r"\n[ \t]*\n\s*$", "\n", tex[i:start]))
        body = tex[start + 2:end - 2].strip()
        out.append(f"\\begin{{equation}}\n{body}\n\\end{{equation}}" if numbered else f"\\[\n{body}\n\\]")
        i = end
        after = re.match(r"[ \t]*\n[ \t]*\n\s*(?=[a-z])", tex[i:])
        if after:
            out.append("\n")
            i += after.end()
    out.append(tex[i:])
    return "".join(out)


def roman(n):
    vals = [(10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
    out = ""
    for v, s in vals:
        while n >= v:
            out += s
            n -= v
    return out


def ieee_section_number(num):
    """'4' -> 'IV'; '4.10' -> 'IV-J' (IEEEtran's numbering of a subsection)."""
    if "." in num:
        a, b = num.split(".")
        return f"{roman(int(a))}-{chr(64 + int(b))}"
    return roman(int(num))


SMALL_WORDS = {"a", "an", "the", "and", "but", "or", "nor", "for", "so", "yet", "as", "at", "by", "in", "of",
               "on", "to", "up", "via", "per", "vs", "vs."}
UNIT_WORDS = {"m", "cm", "mm", "km", "ha", "h", "s"}


def headline(title):
    """IEEE headline style: capitalise every word except short articles,
    conjunctions and prepositions, which stay lower case unless they open the
    title, end it or follow a colon. Words that already hold a capital, a
    digit or an underscore, a unit after a number (2 m, 10 pulses/m²) and
    inline math ($x + y$) are left as they are."""
    maths = re.findall(r"\$[^$]+\$", title)
    if maths:
        index = iter(range(len(maths)))
        out = headline(re.sub(r"\$[^$]+\$", lambda m: f"ZZMATH{next(index)}ZZ", title))
        return re.sub(r"ZZMATH(\d+)ZZ", lambda m: maths[int(m.group(1))], out)
    words = title.split()

    def cap(part):
        if not part or not part[0].isalpha() or any(c.isupper() or c.isdigit() or c == "_" for c in part):
            return part
        return part[0].upper() + part[1:]
    out = []
    for i, w in enumerate(words):
        prev = words[i - 1] if i else ""
        if re.search(r"\d$", prev) and (w.lower().strip(".,;:") in UNIT_WORDS or "/" in w):
            out.append(w)
        elif 0 < i < len(words) - 1 and not prev.endswith(":") and w.lower() in SMALL_WORDS:
            out.append(w)
        else:
            out.append("-".join(cap(x) for x in w.split("-")))
    return " ".join(out)


# ------------------------------------------------------------ bibliography

ENTRY_AT = re.compile(r"@(\w+)\s*([({])")
FIELD_NAME = re.compile(r"([A-Za-z][\w-]*)\s*=\s*")


def parse_bib(text):
    """[(type, key, [(field, value), ...], offset)] for the BibTeX forms the
    repository bibliography uses: braced or quoted values, which may span
    lines and nest braces, and bare numbers. @string, @preamble, @comment,
    parenthesised entries, '#' concatenation and macro values stop the build
    rather than being misread. offset is where the entry starts in text."""
    entries = []
    i = 0
    while True:
        m = ENTRY_AT.search(text, i)
        if not m:
            return entries
        etype = m.group(1)
        if etype.lower() in ("string", "preamble", "comment") or m.group(2) == "(":
            raise SystemExit(f"unsupported BibTeX form at {text[m.start():m.start() + 40]!r}")
        km = re.compile(r"\s*([^,\s]+)\s*,").match(text, m.end())
        if not km:
            raise SystemExit(f"cannot read the key at {text[m.start():m.start() + 40]!r}")
        key, j, fields = km.group(1), km.end(), []
        while True:
            while j < len(text) and text[j] in " \t\r\n,":
                j += 1
            if j >= len(text):
                raise SystemExit(f"unterminated entry {key}")
            if text[j] == "}":
                j += 1
                break
            fm = FIELD_NAME.match(text, j)
            if not fm:
                raise SystemExit(f"cannot parse a field of {key} at {text[j:j + 40]!r}")
            name, j = fm.group(1).lower(), fm.end()
            if j < len(text) and text[j] in '{"':
                close = "}" if text[j] == "{" else '"'
                depth, k = 0, j + 1
                while k < len(text):
                    c = text[k]
                    if c == "{":
                        depth += 1
                    elif c == "}" and depth > 0:
                        depth -= 1
                    elif c == close and depth == 0:
                        break
                    k += 1
                else:
                    raise SystemExit(f"unterminated value of {key}.{name}")
                value, j = text[j + 1:k], k + 1
            else:
                vm = re.compile(r"\d+(?=[\s,}#])").match(text, j)
                if not vm:
                    raise SystemExit(f"{key}.{name}: macro values are not supported ({text[j:j + 30]!r})")
                value, j = vm.group(0), vm.end()
            if re.compile(r"\s*#").match(text, j):
                raise SystemExit(f"{key}.{name}: '#' concatenation is not supported")
            fields.append((name, " ".join(value.split())))
        entries.append((etype, key, fields, m.start()))
        i = j


def split_top(s, sep):
    """Split s on sep where sep sits at brace depth 0."""
    parts, depth, start, i = [], 0, 0, 0
    while i < len(s):
        if s[i] == "{":
            depth += 1
        elif s[i] == "}":
            depth -= 1
        elif depth == 0 and s.startswith(sep, i):
            parts.append(s[start:i])
            i += len(sep)
            start = i
            continue
        i += 1
    parts.append(s[start:])
    return [p.strip() for p in parts]


DECODE_ACCENT = {"'": "\u0301", "`": "\u0300", "^": "\u0302", '"': "\u0308", "~": "\u0303", "r": "\u030a",
                 "c": "\u0327", "v": "\u030c", "u": "\u0306", "k": "\u0328", "H": "\u030b", "=": "\u0304",
                 ".": "\u0307", "textcommabelow": "\u0326"}
DECODE_SPECIAL = {"ae": "æ", "AE": "Æ", "o": "ø", "O": "Ø", "ss": "ß", "l": "ł", "L": "Ł", "oe": "œ", "OE": "Œ",
                  "aa": "å", "AA": "Å"}


def decode_latex(s):
    """LaTeX accent macros back to Unicode, then drop protective braces."""
    def accent(m):
        return unicodedata.normalize("NFC", m.group(2) + DECODE_ACCENT[m.group(1)])
    s = re.sub(r"\\([ij])(?![A-Za-z])\s*", r"\1", s)  # dotless i and j, as accent bases
    s = re.sub(r"\\(textcommabelow|[`'^\"~=.]|[rcvukH](?=[\s{]))\s*\{?\s*([A-Za-z])\s*\}?", accent, s)
    s = re.sub(r"\\(ae|AE|oe|OE|aa|AA|ss|o|O|l|L)(?![A-Za-z])\s?", lambda m: DECODE_SPECIAL[m.group(1)], s)
    return s.replace("{", "").replace("}", "")


def braced_whole(a):
    """True when the brace that opens a closes at its last character."""
    if not a.startswith("{"):
        return False
    depth = 0
    for i, c in enumerate(a):
        depth += (c == "{") - (c == "}")
        if depth == 0:
            return i == len(a) - 1
    return False


def bib_authors(bib_text):
    """key -> 'Surname', 'A and B' or 'Surname et al.' for narrative citations,
    in Unicode (the LaTeX output re-encodes accents)."""
    out = {}
    for _, key, fields, _ in parse_bib(bib_text):
        raw = dict(fields).get("author")
        if not raw:
            continue
        fam = []
        for a in split_top(raw, " and "):
            if a == "others":
                fam.append("others")
                continue
            if braced_whole(a):
                name = decode_latex(a[1:-1])  # corporate author
            elif len(split_top(a, ",")) > 1:
                name = decode_latex(split_top(a, ",")[0])
            else:
                # 'First von Last': the family name starts at the first
                # lower-case word after the first, as BibTeX reads it.
                words = split_top(a, " ")
                start = next((i for i in range(1, len(words) - 1) if words[i][:1].islower()), len(words) - 1)
                name = decode_latex(" ".join(words[start:]))
            if "\\" in name:
                raise SystemExit(f"{key}: cannot decode the author name {a!r}")
            fam.append(name)
        if len(fam) == 1:
            out[key] = fam[0]
        elif len(fam) == 2 and fam[1] != "others":
            out[key] = f"{fam[0]} and {fam[1]}"
        else:
            out[key] = f"{fam[0]} et al."
    return out


ACCENT = {"\u0301": "'", "\u0300": "`", "\u0302": "^", "\u0308": '"', "\u0303": "~", "\u030a": "r",
          "\u0327": "c", "\u0326": "textcommabelow", "\u030c": "v", "\u0306": "u", "\u0328": "k",
          "\u030b": "H", "\u0304": "=", "\u0307": "."}
SPECIAL = {"æ": r"{\ae}", "Æ": r"{\AE}", "ø": r"{\o}", "Ø": r"{\O}", "ß": r"{\ss}", "ł": r"{\l}",
           "Ł": r"{\L}", "œ": r"{\oe}", "Œ": r"{\OE}", "–": "--", "—": "---", "’": "'", "‘": "`",
           "“": "``", "”": "''", "²": r"\textsuperscript{2}", "×": r"$\times$", "−": "-", "\u00a0": "~"}


def latex_accents(text):
    out = []
    for ch in text:
        if ord(ch) < 128:
            out.append(ch)
            continue
        if ch in SPECIAL:
            out.append(SPECIAL[ch])
            continue
        d = unicodedata.normalize("NFD", ch)
        if len(d) == 2 and d[1] in ACCENT and ord(d[0]) < 128:
            cmd = ACCENT[d[1]]
            out.append("{\\" + cmd + ("{" + d[0] + "}" if cmd.isalpha() else d[0]) + "}")
            continue
        raise SystemExit(f"no LaTeX mapping for {ch!r} U+{ord(ch):04X}")
    return "".join(out)


MONTHS = ["Jan.", "Feb.", "Mar.", "Apr.", "May", "Jun.", "Jul.", "Aug.", "Sep.", "Oct.", "Nov.", "Dec."]
IEEE_DROPS = {"version", "urldate", "doi", "eprint", "archiveprefix", "primaryclass"}


def accessed(date):
    m = re.fullmatch(r"(\d{4})-(\d{2})-(\d{2})", date)
    if not m:
        raise SystemExit(f"urldate {date!r} is not YYYY-MM-DD")
    return f"Accessed: {MONTHS[int(m.group(2)) - 1]} {int(m.group(3))}, {m.group(1)}"


def protect_part(part, lead):
    """Brace one hyphen-separated part of a title word if IEEEtran.bst's
    sentence casing would lower a capital that must stay: an acronym or
    single capital (D in 3-D, QL2), or a capital inside a word (PointNet).
    lead marks the first letter of the title or of the text after ': ',
    which the style keeps, so a single capital there needs no braces."""
    m = re.search(r"[A-Za-z0-9](?:.*[A-Za-z0-9])?", part)
    if not m:
        return part
    core = m.group(0)
    letters = [c for c in core if c.isalpha()]
    if not any(c.isupper() for c in letters):
        return part
    inner = any(c.isupper() for c in core[1:])
    acronym = all(c.isupper() for c in letters)
    if inner or (acronym and not lead):
        return part[:m.start()] + "{" + core + "}" + part[m.end():]
    return part


def protect_title(title):
    """Protect what IEEEtran.bst's sentence casing of titles would damage.
    Ordinary capitalised words are left for the style to lower-case, as IEEE
    reference lists set titles in sentence case; proper nouns that no rule
    can recognise are braced in the source bibliography. Brace groups, math
    and control words are kept as they are, and the text around them is
    protected word by word. A quotation inside a title takes single quotes,
    since IEEEtran adds the outer double ones."""
    title = re.sub(r"``(.*?)''", r"`\1'", title)
    segs, i = [], 0
    while i < len(title):
        c = title[i]
        if c == "{":
            depth, k = 0, i
            while k < len(title):
                depth += (title[k] == "{") - (title[k] == "}")
                if depth == 0:
                    break
                k += 1
            segs.append((False, title[i:k + 1]))
            i = k + 1
        elif c == "$":
            k = title.find("$", i + 1)
            if k < 0:
                raise SystemExit(f"unbalanced $ in title {title!r}")
            segs.append((False, title[i:k + 1]))
            i = k + 1
        elif c == "\\":
            m = re.match(r"\\[A-Za-z]+\*?|\\.", title[i:])
            segs.append((False, m.group(0)))
            i += len(m.group(0))
        else:
            m = re.match(r"[^{}$\\]+", title[i:])
            segs.append((True, m.group(0)))
            i += len(m.group(0))
    out = ""
    for is_text, seg in segs:
        if not is_text:
            out += seg
            continue
        for tok in re.findall(r"\s+|\S+", seg):
            if not tok.isspace():
                # The style keeps the first letter of the title and the one
                # after ': ', so a single capital there needs no braces.
                lead = not re.search(r"[A-Za-z0-9]", out) or bool(re.search(r":\s+$", out))
                parts = re.split(r"(-)", tok)
                tok = "".join(protect_part(x, lead and k == 0) for k, x in enumerate(parts))
            out += tok
    return out


def protect_note(note):
    """Brace what IEEEtran.bst's format.note would lower-case: the first letter
    of a note that opens with an acronym or a single capital ('R package',
    'MIT licence') or with the access-date label ('Accessed: ...')."""
    note = re.sub(r"^Accessed\b", "{A}ccessed", note)
    return re.sub(r"^([A-Z][A-Z0-9]*)\b", r"{\1}", note)


def join_notes(parts, doi):
    """Join note parts into sentences without doubling end punctuation, and put
    the DOI last after a comma, as IEEE's reference forms do."""
    text = ""
    for part in parts:
        part = part.strip()
        if text:
            text += " " if re.search(r"[.?!]\}?$", text) else ". "
        text += part
    if doi:
        doi_part = "doi: \\url{" + doi + "}"
        text = (re.sub(r"\.$", "", text) + ", " + doi_part) if text else doi_part
    return text


def ieee_entry(etype, key, fields):
    f = dict(fields)
    is_misc = etype.lower() in ("misc", "software", "online", "dataset")
    out = [(n, v) for n, v in fields if n not in IEEE_DROPS | {"note"} and v.strip()]
    have = {n for n, _ in out}
    author = decode_latex(f.get("author", ""))
    notes = []
    # IEEE's preprint form is 'year, arXiv:ID', so the identifier opens the
    # note; a paper with a DOI is cited by its version of record.
    if "eprint" in f and "doi" not in f:
        notes.append(f"arXiv:{f['eprint']}")
    if "version" in f:
        # Skip the version only when the note already states it.
        v = f["version"]
        commit = v.lower().startswith("commit ")
        shown = v[len("commit "):] if commit else v
        stated = re.escape(shown) if commit else rf"\bversion\s+{re.escape(shown)}(?!\.?\w)"
        if not re.search(stated, f.get("note", ""), flags=re.I):
            notes.append(f"Commit {shown}" if commit else f"Version {shown}")
    if f.get("note", "").strip() and not f["note"].startswith("Undated page"):
        notes.append(f["note"])  # the access date below replaces the undated-page note
    if is_misc and f.get("publisher", "").strip():
        out = [(n, v) for n, v in out if n != "publisher"]
        if decode_latex(f["publisher"]) != author:
            if "howpublished" not in have:
                out.append(("howpublished", f["publisher"]))
                have.add("howpublished")
            elif "organization" not in have:
                out.append(("organization", f["publisher"]))
                have.add("organization")
            else:
                notes.append(f["publisher"])
    if "urldate" in f:
        notes.append(accessed(f["urldate"]))
    note = join_notes(notes, f.get("doi", "").strip())
    if note:
        out.append(("note", protect_note(note)))
    out = [(n, protect_title(v) if n == "title" else v) for n, v in out]
    width = max(len(n) for n, _ in out)

    def field(n, v):
        head = f"  {n:<{width}} = {{"
        return textwrap.fill(latex_accents(v), 79, initial_indent=head, subsequent_indent=" " * len(head),
                             break_long_words=False, break_on_hyphens=False) + "}"
    body = ",\n".join(field(n, v) for n, v in out)
    return f"@{'misc' if is_misc else etype}{{{key},\n{body},\n}}"


# IEEE lists all authors up to six and the first author and "et al." beyond;
# IEEEtran.bst does so only when this control entry is cited first. Repeated
# author lists are written out, so two "et al." lists are never shown as one.
BSTCTL = """@IEEEtranBSTCTL{IEEEexample:BSTcontrol,
  CTLuse_forced_etal       = "yes",
  CTLmax_names_forced_etal = "6",
  CTLnames_show_etal       = "1",
  CTLdash_repeated_names   = "no",
}"""


def ieee_bib(bib_text):
    """IEEE copy of the bibliography for IEEEtran.bst (see the module
    docstring for what moves where and what is not printed)."""
    # The source's section headings ('% ---' rulers around a title line) are
    # kept, so the copy stays navigable when it is edited by hand.
    heads = [(m.start(), m.group(1).replace("@", "(at)"))
             for m in re.finditer(r"(?m)^% -{10,}\n% (.+)\n% -{10,}$", bib_text)]
    rule = "% " + "-" * 75
    items = [(off, ieee_entry(t, k, f)) for t, k, f, off in parse_bib(bib_text)]
    items += [(off, f"{rule}\n% {h}\n{rule}") for off, h in heads]
    entries = [BSTCTL] + [text for _, text in sorted(items)]
    # BibTeX reads an at-sign anywhere as an entry start, even after %, so the
    # header must not contain one.
    head = ("% IEEE copy of docs/references.bib, generated by scripts/paper_to_ieee.py for\n"
            "% IEEEtran.bst. Software and dataset entries become misc; the version, the\n"
            "% access date, the DOI and, without a DOI, the arXiv identifier move into\n"
            "% the note; a misc entry's publisher becomes howpublished or organization\n"
            "% unless it repeats the author. Acronyms and inner capitals in titles and a\n"
            "% note's first word are braced; other title words follow IEEE's sentence\n"
            "% case. Accented letters are written as LaTeX accents. The control entry\n"
            "% makes IEEEtran.bst list the first author and et al. beyond six authors.\n\n")
    return head + latex_accents("\n\n".join(entries)) + "\n"


# ------------------------------------------------------- markdown transforms


def convert_citations(md, authors):
    def group(m):
        keys = re.findall(r"@([a-z0-9]+)", m.group(2))
        lead = NBSP if m.group(1) else ""
        return lead + "\\cite{" + ",".join(keys) + "}"
    md = re.sub(r"(\s?)(\[@[a-z0-9]+(?:;\s*@[a-z0-9]+)*\])", group, md)
    left = re.search(r"\[[^\[\]]*@[a-z0-9]+[^\[\]]*\]", md)
    if left:
        raise SystemExit(f"unsupported citation form (prefix, locator or comma list): {left.group(0)!r}")
    left = re.search(r"(?<![\w@\\{])@[a-z0-9]+\s*\[", md)
    if left:
        raise SystemExit(f"unsupported citation form (narrative citation with a locator): {left.group(0)!r}")

    def narrative(m):
        key = m.group(1)
        if key not in authors:
            raise SystemExit(f"narrative citation of unknown key {key}")
        return f"{authors[key]}{NBSP}\\cite{{{key}}}"
    return re.sub(r"(?<![\w@\\{])@([a-z0-9]+)", narrative, md)


SEPS = r"(?:,\s+(?:and\s+|or\s+)?|\s+(?:and|or|to)\s+|\s*–\s*)"
# A list continues only with a bare item: '4.2 and 4.3', not 'and 4 m' or 'and 2.5 pulses'.
CONT_END = r"(?!\.?\d)(?!\s*(?:m\b|km\b|%|pulses|points|pts|stems|plots|trees|cm\b|ha\b))"
SEC_ITEM = r"S?\d+(?:\.\d+)?"
TAB_ITEM = r"S?\d+[a-z]?"
FIG_ITEM = r"S?\d+[a-z]?"


def convert_refs(md, mode, known=None):
    """Section/Table/Figure references. mode 'main' uses \\ref; 'supp' writes
    IEEE numbers for the manuscript's items. Supplement items (S-numbers) stay
    as text. known, when given, holds the section, table and figure numbers of
    the manuscript and the supplement (see paper_numbers); a reference to
    anything else stops the build. A plural word (Sections, Tables, Figures,
    Figs.) starts a list; after a singular one only 'or' continues it, so a
    number in the prose after 'Table 2 and' is never read as a reference. Fig
    and Figs are read with or without their period. A figure panel is written
    the IEEE way in both documents: Fig. 2d and Fig. S1d become Fig. 2(d) and
    Fig. S1(d)."""
    def check(kind, item):
        if known is not None and item not in known[kind]:
            raise SystemExit(f"reference to {kind} {item}, which the manuscript does not have")

    def s_check(kind, item):
        if known is None:
            return
        pool = known.get(kind, set())
        # 'Table S16' may name the group of Tables S16a, S16b and so on.
        if item in pool or (kind == "stab" and any(re.fullmatch(re.escape(item) + "[a-z]", t) for t in pool)):
            return
        raise SystemExit(f"reference to supplement item {item}, which the supplement does not have")

    def sec_one(it):
        if it.startswith("S"):
            s_check("ssec", it)
            return it
        check("sec", it)
        return f"\\ref{{sec:{it}}}" if mode == "main" else ieee_section_number(it)

    def tab_one(it):
        if it.startswith("S"):
            s_check("stab", it)
            return it
        if not it.isdigit():
            raise SystemExit(f"Table {it}: the manuscript's tables have no lettered parts")
        check("tab", it)
        return f"\\ref{{tab:{it}}}" if mode == "main" else roman(int(it))

    def fig_one(it):
        mm = re.fullmatch(r"(S?)(\d+)([a-z]?)", it)
        if mm.group(1):
            s_check("sfig", "S" + mm.group(2))
            base = "S" + mm.group(2)
        else:
            check("fig", mm.group(2))
            base = f"\\ref{{fig:{mm.group(2)}}}" if mode == "main" else mm.group(2)
        return base + (f"({mm.group(3)})" if mm.group(3) else "")  # IEEE writes Fig. 2(d)

    def rewrite(plural, single, item_re, one, text):
        pattern = (rf"\b(?:({plural})\s+({item_re}(?:{SEPS}{item_re}{CONT_END})*)"
                   rf"|({single})\s+({item_re}(?:\s+or\s+{item_re}{CONT_END})?))\b")

        def repl(m):
            word, items = (m.group(1), m.group(2)) if m.group(1) else (m.group(3), m.group(4))
            parts = re.split(f"({SEPS})", items)
            return word + NBSP + "".join(one(x) if re.fullmatch(item_re, x) else x for x in parts)
        return re.sub(pattern, repl, text)
    md = rewrite(r"Sections", r"Section", SEC_ITEM, sec_one, md)
    md = rewrite(r"Tables", r"Table", TAB_ITEM, tab_one, md)
    return rewrite(r"Figs\.?|Figures", r"Fig\.?|Figure", FIG_ITEM, fig_one, md)


def text_to_latex(tex):
    tex = tex.replace("−", "$-$").replace("²", "\\textsuperscript{2}").replace("—", "---")
    tex = tex.replace("–", "--").replace("×", "$\\times$").replace("τ", "$\\tau$")
    tex = tex.replace("≤", "$\\leq$").replace("≥", "$\\geq$").replace("·", "$\\cdot$")
    tex = tex.replace(NBSP, "~")
    # Any accented letter left (e.g. in a narrative author name) becomes a
    # LaTeX accent; latex_accents stops on anything it cannot map.
    return latex_accents(tex)


def unicode_to_latex(tex):
    """Map the Unicode left in pandoc's LaTeX: text symbols to $...$ or text
    commands, and symbols inside math to math commands. Code blocks
    (verbatim) are left as they are."""
    parts = [(s, e, math_to_latex) for s, e, _ in math_spans(tex)]
    parts += [(s, e, code_to_latex) for s, e in verbatim_spans(tex)]
    out, i = [], 0
    for start, end, convert in sorted(parts, key=lambda p: p[0]):
        out += [text_to_latex(tex[i:start]), convert(tex[start:end])]
        i = end
    return "".join(out) + text_to_latex(tex[i:])


def unescape_brackets(tex):
    """pandoc writes {[} and {]}; keep the escape only where a bare [ could be
    read as an optional argument (after \\item, \\\\, a control word or at a
    cell start). Code blocks (verbatim) are left as they are."""
    verbatim = verbatim_spans(tex)

    def repl(m):
        if any(s <= m.start() < e for s, e in verbatim):
            return m.group(0)
        if m.group(0) == "{]}":
            return "]"
        prev = tex[:m.start()].rstrip()
        if not prev or prev.endswith(("\\\\", "\\item", "&")) or re.search(r"\\[A-Za-z]+\*?$", prev):
            return m.group(0)
        return "["
    return re.sub(r"\{\[\}|\{\]\}", repl, tex)


LINK = re.compile(r'(?<!!)\[([^\]]+)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)')


def links(md, mode):
    """Repository-relative links point to GitHub in the supplement and keep
    their text elsewhere; web links become \\href in the supplement (which
    loads hyperref) and 'text (url)' in the manuscript (which does not).
    Images are left alone."""
    def repl(m):
        text, url = m.group(1), m.group(2)
        if url.startswith(("http://", "https://")):
            return f"{text} (<{url}>)" if mode == "main" else f"[{text}]({url})"
        if mode == "supp" and url.startswith("../"):
            return f"[{text}]({REPO_URL}{url[3:]})"
        return text
    return LINK.sub(repl, md)


def protect_urls(tex):
    """url.sty's \\url is fragile in a moving argument (caption, heading)."""
    return tex.replace("\\url{", "\\protect\\url{")


# ------------------------------------------------------------- tables/figures


def plain_len(cell):
    s = re.sub(r"\\cite\{[^}]*\}", "[1]", cell)
    s = re.sub(r"\\ref\{[^}]*\}", "IV", s)
    s = re.sub(r"[*`]", "", s)
    return len(s)


def parse_pipe_table(block):
    rows = [ln.strip() for ln in block.strip().split("\n") if ln.strip().startswith("|")]
    cells = [[c.strip() for c in r.strip("|").split("|")] for r in rows]
    header, sep, body = cells[0], cells[1], cells[2:]
    aligns = ["r" if s.endswith(":") and not s.startswith(":") else ("c" if s.startswith(":") and s.endswith(":") else "l")
              for s in sep]
    return header, aligns, body


def column_spec(header, body, aligns, x_threshold):
    spec = []
    for j, al in enumerate(aligns):
        width = max(plain_len(r[j]) for r in [header] + body)
        if width <= x_threshold:
            spec.append(al)
        else:
            spec.append({"l": "L", "r": "R", "c": "C"}[al])
    return spec


# Printed widths for laying out the X columns of a table, in em of the table's
# font. Times Roman, the text font of both documents, after Adobe's metrics in
# thousandths of an em; code (\texttt) is Courier, 600 for every character; the
# math symbols that text maps to $...$ (minus, times, <=, >=) are about 778.
TIMES_WIDTHS = {"|": 200, " ,.": 250, "/:;ijlt\\": 278, "!'()-I[]`fr\u2019": 333, "Js": 389, '"': 408,
                "?acez\u201c\u201d": 444, "^": 469, "{}": 480, "#$*0123456789_bdghknopquvxy\u2013": 500,
                "~": 541, "FPS": 556, "+<=>": 564, "ELTZ": 611, "BCR": 667, "ADGHKNOQUVXYw": 722,
                "&m\u2212\u00d7\u2264\u2265": 778, "%": 833, "M": 889, "@": 921, "W": 944, "\u2014": 1000}
CHAR_EM = {c: w / 1000 for chars, w in TIMES_WIDTHS.items() for c in chars}
# The width a table is set to (IEEEtran's text and column widths; the
# supplement's text width on letter paper with 2 cm margins) and its font size,
# in pt; the space between two columns (twice \tabcolsep); and the interword
# space, which IEEEtran widens from Times' 0.25 em to 0.35 em.
TABLE_PT = {("main", "\\textwidth"): 516.0, ("main", "\\columnwidth"): 252.0, ("supp", "\\textwidth"): 500.5}
FONT_PT = {"\\scriptsize": 7.0, "\\footnotesize": 8.0}
COLSEP_PT = 6.0
SPACE_EM = {"main": 0.35, "supp": 0.25}
# No X column is narrower than half the width the X columns would share
# equally, or than its longest word plus this margin, in em.
MIN_X_FACTOR = 0.5
WORD_MARGIN_EM = 0.5


def word_widths(cell, space=0.25):
    """The printed width, in em, of each word of a markdown table cell: the
    text between breakable spaces, so a no-break space joins two words. A
    citation prints as [12], a reference as IV-B, a link as its text, a code
    span in Courier and math as its letters."""
    s = re.sub(r"\\cite\{[^}]*\}", "[12]", cell)
    s = re.sub(r"\\ref\{[^}]*\}", "IV-B", s)
    s = re.sub(r"(?<!!)\[([^\]]*)\]\([^)]*\)", r"\1", s)
    s = re.sub(r"\$([^$]*)\$", lambda m: re.sub(r"\\[A-Za-z]+|[{}^_\\]", "", m.group(1)), s)
    widths, code = [], False
    for word in re.findall(r"[^ \t\n]+", s):
        w = 0.0
        for ch in word:
            if ch == "`":
                code = not code
            elif ch == NBSP:
                w += space
            elif ch != "*":
                w += 0.6 if code else CHAR_EM.get(unicodedata.normalize("NFD", ch)[0], 0.5)
        widths.append(w)
    return widths


def table_lines(rows, widths, space=0.25):
    """The estimated height of a table in lines: for each row, the most lines
    that one of its cells takes when its words are wrapped into its column's
    width in em (None for a column that does not wrap)."""
    total = 0
    for row in rows:
        most = 1
        for cell, width in zip(row, widths):
            if width is None:
                continue
            lines, used = 1, None
            for w in word_widths(cell, space):
                if used is not None and used + space + w > width:
                    lines, used = lines + 1, None
                used = w if used is None else used + space + w
            most = max(most, lines)
        total += most
    return total


def x_factors(spec, rows, width_em, space=0.25):
    """The width factors of a table's X columns (L, R or C in spec), as the
    decimals written into the LaTeX, and None for its other columns. tabularx
    gives every X column the same width; a factor f scales one
    (>{\\hsize=f\\hsize}), and the factors of a table must sum to its number of
    X columns, so that the table keeps its width. They follow the columns'
    text, the summed printed width of their cells, so a column of long cells
    widens and one of short cells narrows, but no X column is narrower than
    half the equal width or than its longest word with a margin. The factors
    have two decimals and sum to the number of X columns, except that the
    largest may give up a few hundred-thousandths so that TeX's sum of them
    stays below it (see tex_units). The table keeps equal widths (every factor
    "1") unless the factors shorten it, by the estimate of table_lines, or
    when the floors leave no room. rows holds the header and the body in
    markdown; width_em is the width that the columns share after the space
    between them, in em."""
    xcols = [j for j, s in enumerate(spec) if s in "LRC"]
    equal = ["1" if j in xcols else None for j in range(len(spec))]
    n = len(xcols)
    one_line = [[sum(w) + space * max(len(w) - 1, 0) for w in (word_widths(c, space) for c in r)] for r in rows]
    fixed = sum(max(r[j] for r in one_line) for j in range(len(spec)) if j not in xcols)
    share = (width_em - fixed) / n if n else 0
    if n < 2 or share <= 0:
        return equal
    text = [sum(r[j] for r in one_line) for j in xcols]
    longest = [max((w for r in rows for w in word_widths(r[j], space)), default=0.0) for j in xcols]
    floors = [math.ceil(max(MIN_X_FACTOR, (w + WORD_MARGIN_EM) / share) * 100 - 1e-9) / 100 for w in longest]
    if sum(floors) > n + 1e-9:
        return equal
    # In proportion to the text, raising a column below its floor to the floor
    # and sharing the rest among the others in proportion to theirs.
    f, pinned = list(floors), set()
    while True:
        free = [k for k in range(n) if k not in pinned]
        rest, weight = n - sum(floors[k] for k in pinned), sum(text[k] for k in free)
        for k in free:
            f[k] = rest * text[k] / weight if weight else rest / len(free)
        low = [k for k in free if f[k] < floors[k]]
        if not low:
            break
        pinned.update(low)
        for k in low:
            f[k] = floors[k]
    # Hundredths that sum exactly to n: round down, then add the units left to
    # the largest remainders. A floor is a whole number of hundredths, so no
    # factor falls below its floor.
    units = [math.floor(x * 100 + 1e-9) for x in f]
    for k in sorted(range(n), key=lambda k: units[k] - f[k] * 100)[:100 * n - sum(units)]:
        units[k] += 1
    texts = [f"{u / 100:.2f}" for u in units]
    # TeX reads a factor to the nearest 1/65536 (0.63 as 41288/65536), so
    # factors that sum to n can sum to a little more in TeX, and tabularx then
    # sets the table a few thousandths of a point short of its width, which
    # TeX reports as an underfull row. The largest factor then gives up just
    # enough (a few hundred-thousandths) for TeX's sum to fall 1/65536 below
    # n, so the table ends at most a few hundredths of a point too wide,
    # within \hfuzz.
    over = sum(tex_units(t) for t in texts) - 65536 * n
    if over >= 0:
        k = max(range(n), key=lambda i: units[i])
        texts[k] = f"{(tex_units(texts[k]) - over - 1) / 65536:.5f}"
    factors = list(equal)
    for k, j in enumerate(xcols):
        factors[j] = texts[k]
    shorter = (table_lines(rows, [float(x) * share if x else None for x in factors], space)
               < table_lines(rows, [float(x) * share if x else None for x in equal], space))
    return factors if shorter else equal


def tex_units(factor):
    """The value TeX reads from a decimal factor such as 0.63 in 0.63\\hsize,
    in units of 1/65536: TeX rounds the decimal fraction to the nearest unit,
    digit by digit from the last (TeX: The Program, section 102)."""
    whole, _, frac = factor.partition(".")
    a = 0
    for d in reversed(frac[:17]):
        a = (a + int(d) * 131072) // 10
    return int(whole or 0) * 65536 + (a + 1) // 2


def column_preamble(spec, rows, mode, line_width, size):
    """A table's column preamble: an X column whose factor is not 1 takes
    >{\\hsize=f\\hsize\\linewidth=\\hsize} before its L, R or C, tabularx's
    form for X columns of unequal widths, which xltabular shares."""
    width_em = (TABLE_PT[(mode, line_width)] - COLSEP_PT * len(spec)) / FONT_PT[size]
    factors = x_factors(spec, rows, width_em, SPACE_EM[mode])
    return "".join(s if f in (None, "1", "1.00") else f">{{\\hsize={f}\\hsize\\linewidth=\\hsize}}{s}"
                   for s, f in zip(spec, factors))


def table_tex(num, caption_tex, header, aligns, body, mode):
    flat = pandoc_snippets(header + [c for r in body for c in r])
    ncol = len(header)
    head_tex = flat[:ncol]
    rows_tex = [flat[ncol + i * ncol: ncol + (i + 1) * ncol] for i in range(len(body))]
    spec = column_spec(header, body, aligns, 12 if mode == "main" else 16)
    size = "\\footnotesize" if ncol <= 5 else "\\scriptsize"
    head_row = " & ".join(head_tex) + " \\\\"
    lines = []
    if mode == "main":
        # A table whose body cells are all short fits one column of the
        # two-column page; anything wider spans both columns.
        body_width = sum(max(plain_len(r[j]) for r in body) for j in range(ncol))
        single = ncol <= 5 and body_width <= 45
        float_env = "table" if single else "table*"
        line_width = "\\columnwidth" if single else "\\textwidth"
        if single:
            spec = [{"l": "L", "r": "R", "c": "C"}[a] if plain_len(header[j]) > 10 else a
                    for j, a in enumerate(aligns)]
            spec[0] = "l"
        has_x = any(s in "LRC" for s in spec)
        lines += [f"\\begin{{{float_env}}}[!tp]", f"\\caption{{{caption_tex}}}", f"\\label{{tab:{num}}}",
                  "\\centering", size, "\\setlength{\\tabcolsep}{3pt}",
                  "\\renewcommand{\\arraystretch}{1.15}"]
        env = "tabularx" if has_x else "tabular"
        width = f"{{{line_width}}}" if has_x else ""
        lines.append(f"\\begin{{{env}}}{width}{{{column_preamble(spec, [header] + body, mode, line_width, size)}}}")
        lines += ["\\hline", head_row, "\\hline"]
        lines += [" & ".join(r) + " \\\\" for r in rows_tex]
        lines += ["\\hline", f"\\end{{{env}}}", f"\\end{{{float_env}}}"]
    else:
        if not any(s in "LRC" for s in spec):
            # A narrow table still spans the text width: share the slack among
            # every column after the label column instead of the last one.
            spec = [spec[0]] + [{"l": "L", "r": "R", "c": "C"}[a] for a in spec[1:]]
        # The caption is the first head row, so a page break cannot separate
        # it from its table; a continuation page repeats the head with a label.
        caption_row = (f"\\multicolumn{{{ncol}}}{{@{{}}p{{\\textwidth}}@{{}}}}"
                       f"{{\\normalsize\\textbf{{Table {num}.}} {caption_tex}}} \\\\[4pt]")
        continued_row = (f"\\multicolumn{{{ncol}}}{{@{{}}l@{{}}}}"
                         f"{{\\normalsize\\textbf{{Table {num}}} (continued)}} \\\\[4pt]")
        preamble = column_preamble(spec, [header] + body, mode, "\\textwidth", size)
        lines += ["{" + size, "\\setlength{\\tabcolsep}{3pt}", "\\renewcommand{\\arraystretch}{1.15}",
                  f"\\begin{{xltabular}}{{\\textwidth}}{{{preamble}}}",
                  caption_row, "\\hline", head_row, "\\hline", "\\endfirsthead",
                  continued_row, "\\hline", head_row, "\\hline", "\\endhead",
                  "\\hline", "\\endfoot"]
        lines += [" & ".join(r) + " \\\\" for r in rows_tex]
        lines += ["\\end{xltabular}", "}"]
    return "\n".join(lines)


FIG_WIDTH = {}
FIG_FILE = {}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def figure_png(path):
    """(file, aspect ratio) of the PNG that a figure's markdown names, relative
    to paper/. The aspect ratio sets the printed width, and the Overleaf zip
    keeps the path, so it must be a PNG file under paper/ with a name that
    LaTeX reads as it is."""
    p = PurePosixPath(path)
    if p.is_absolute() or ".." in p.parts or not re.fullmatch(r"[A-Za-z0-9_./-]+\.png", path):
        raise SystemExit(f"figure {path!r}: expected the path of a PNG under paper/, such as figures/figure_1.png")
    src = REPO / "paper" / p
    if not src.is_file():
        raise SystemExit(f"figure file not found: {src}")
    with src.open("rb") as f:
        head = f.read(24)
    w, h = unpack(">II", head[16:24]) if len(head) == 24 else (0, 0)
    if head[:8] != PNG_SIGNATURE or head[12:16] != b"IHDR" or not (w and h):
        raise SystemExit(f"{src} is not a PNG file")
    return src, w / h


def figure_tex(num, path, caption_tex, mode="main"):
    """A figure's LaTeX: a figure* float with \\caption and \\label in the
    manuscript. In the supplement a figure is labelled 'Figure Sn.' in the text,
    as its tables are, so LaTeX's own numbering never shows. It floats here or
    to the top of a page ([!ht]), so the text of its section fills the page
    before it, and the supplement's barrier before each section keeps it in its
    own section (see build_supplement). The PDF beside the PNG is included when
    there is one."""
    src, aspect = figure_png(path)
    width = "\\textwidth" if aspect >= 1.6 else ("0.85\\textwidth" if aspect >= 1.3 else "0.72\\textwidth")
    graphic = str(PurePosixPath(path).with_suffix(".pdf")) if src.with_suffix(".pdf").is_file() else path
    FIG_WIDTH[num], FIG_FILE[num] = width, graphic
    if mode == "main":
        return "\n".join(["\\begin{figure*}[!tp]", "\\centering", f"\\includegraphics[width={width}]{{{graphic}}}",
                          f"\\caption{{{caption_tex}}}", f"\\label{{fig:{num}}}", "\\end{figure*}"])
    return "\n".join(["\\begin{figure}[!ht]", f"{{\\centering\\includegraphics[width={width}]{{{graphic}}}\\par}}",
                      "\\medskip", f"\\textbf{{Figure {num}.}} {caption_tex}", "\\end{figure}"])


# ---------------------------------------------------------------- documents


def split_sections(md):
    """[(heading line or '', text)] for '## ' level-2 sections; a '## ' line in
    a code block is code, not a heading."""
    held, code = hold_code(md)

    def back(text):
        return re.sub(r"ZZCODE(\d+)ZZ", lambda m: code[int(m.group(1))], text)
    parts = re.split(r"(?m)^(## .*)$", held)
    out = [("", back(parts[0]))]
    for i in range(1, len(parts), 2):
        out.append((parts[i].strip(), back(parts[i + 1])))
    return out


def manuscript_numbers(md, supp_md=""):
    """The section, table and figure numbers of the manuscript, and the section,
    table and figure numbers of the supplement (S1, S12c, S1)."""
    return {"sec": set(re.findall(r"(?m)^#{2,3} (\d+(?:\.\d+)?)\.?\s", md)),
            "tab": set(re.findall(r"(?m)^\*\*Table (\d+)\.\*\*", md)),
            "fig": set(re.findall(r"(?m)^\*\*Figure (\d+)\.\*\*", md)),
            "ssec": set(re.findall(r"(?m)^#{2,3} (S\d+)\.?\s", supp_md)),
            "stab": set(re.findall(r"(?m)^\*\*Table (S\d+[a-z]?)\.\*\*", supp_md)),
            "sfig": set(re.findall(r"(?m)^\*\*Figure (S\d+)\.\*\*", supp_md))}


def paper_numbers():
    return manuscript_numbers((REPO / "paper/manuscript.md").read_text(encoding="utf-8"),
                              (REPO / "paper/supplement.md").read_text(encoding="utf-8"))


TABLE_BLOCK = re.compile(r"\*\*Table (S?\d+[a-z]?)\.\*\*[ \t]*((?:(?!\n[ \t]*\n).)*?)\n[ \t]*\n"
                         r"((?:\|[^\n]*(?:\n|\Z))+)", re.S)
FIGURE_BLOCK = re.compile(r"!\[Figure (S?\d+)\.\]\(([^)]+)\)[ \t]*\n[ \t]*\n\*\*Figure \1\.\*\*[ \t]*"
                          r"((?:(?!\n[ \t]*\n).)*)", re.S)


def body_to_tex(md, mode, authors, known):
    """Convert a body of markdown (headings, paragraphs, tables, figures)."""
    check_math_fence(md)
    md, code = hold_code(md)  # no markdown transform touches code
    # Links first, so headings, captions and table cells get them too.
    md = links(convert_citations(md, authors), mode)
    blocks = {}

    def take_figure(m):
        num, path, cap = m.group(1), m.group(2), m.group(3)
        if (mode == "main") == num.startswith("S"):
            where = "the manuscript's figures are Figure 1, 2" if mode == "main" else \
                "the supplement's figures are Figure S1, S2"
            raise SystemExit(f"Figure {num}: {where} and so on")
        tok = f"ZZFIG{num}ZZ"
        blocks[tok] = ("figure", num, path, cap)
        return f"\n\n{tok}\n\n"
    md = FIGURE_BLOCK.sub(take_figure, md)
    if "![" in md or re.search(r"(?m)^\*\*Figure S?\d+\.\*\*", md):
        raise SystemExit("an image or figure caption is not in the '![Figure N.](path)' + '**Figure N.**' form")

    def take_table(m):
        num, cap, table = m.group(1), m.group(2), m.group(3)
        tok = f"ZZTAB{num}ZZ"
        blocks[tok] = ("table", num, cap, table)
        return f"\n\n{tok}\n\n"
    md = TABLE_BLOCK.sub(take_table, md)
    stray = re.search(r"\*\*Table S?\d+[a-z]?\.\*\*", md)
    if stray:
        raise SystemExit(f"{stray.group(0)} is not a one-paragraph caption directly followed by its pipe table")
    stray = re.search(r"(?m)^[ \t]*\|.*$", md)
    if stray:
        raise SystemExit(f"a pipe table without a '**Table N.**' caption: {stray.group(0)[:60]!r}")

    md = convert_refs(md, mode, known)

    def heading(m):
        level, text = len(m.group(1)), m.group(2).strip()
        if mode == "main":
            mm = re.match(r"(\d+(?:\.\d+)?)\.?\s+(.*)", text)
            if not mm:
                raise SystemExit(f"unnumbered heading in body: {text}")
            num, title = mm.group(1), mm.group(2)
            if title == "Conclusions":
                title = "Conclusion"  # IEEE's head is singular
            title = protect_urls(pandoc_snippets([headline(title)])[0])
            cmd = "section" if level == 2 else "subsection"
            return f"\n\\{cmd}{{{title}}}\\label{{sec:{num}}}\n"
        cmd = "section*" if level == 2 else "subsection*"
        return f"\n\\{cmd}{{{pandoc_snippets([headline(text)])[0]}}}\n"
    md = re.sub(r"(?m)^(#{2,3}) (.*)$", heading, md)

    tex = pandoc(restore_code(md, code))
    check_code_blocks(tex, len(code))
    # IEEE numbers displayed equations; the supplement's stay unnumbered.
    tex = display_math(tex, numbered=mode == "main")

    # Captions and table cells are converted after the text so their refs and
    # citations go through the same transforms.
    for tok, spec in blocks.items():
        if spec[0] == "figure":
            _, num, path, cap = spec
            cap_tex = protect_urls(pandoc_snippets([convert_refs(cap, mode, known)])[0])
            repl = figure_tex(num, path, cap_tex, mode)
        else:
            _, num, cap, table = spec
            cap_tex = pandoc_snippets([convert_refs(cap, mode, known)])[0]
            if mode == "main":
                cap_tex = protect_urls(cap_tex)
            header, aligns, body = parse_pipe_table(table)
            header = [convert_refs(c, mode, known) for c in header]
            body = [[convert_refs(c, mode, known) for c in r] for r in body]
            repl = table_tex(num, cap_tex, header, aligns, body, mode)
        if tex.count(tok) != 1:
            raise SystemExit(f"placeholder {tok} found {tex.count(tok)} times")
        tex = tex.replace(tok, repl)
    return unescape_brackets(unicode_to_latex(tex))


def snippet(md, mode, authors, known):
    """Convert a whole section that is not part of the body (the abstract and
    the back matter)."""
    check_math_fence(md)
    md, code = hold_code(md)
    md = links(convert_refs(convert_citations(md, authors), mode, known), mode)
    if "![" in md:
        raise SystemExit("an image outside the body is not supported")
    tex = pandoc_snippets([restore_code(md, code)], inline=False)[0]
    check_code_blocks(tex, len(code))
    if any(display for _, _, display in math_spans(tex)):
        raise SystemExit("display math outside the body text (abstract, back matter) is not supported")
    return unescape_brackets(unicode_to_latex(tex))


def front_matter(md):
    sections = split_sections(md)
    front = sections[0][1]
    full_title = " ".join(re.search(r"^Full title:\s*(.*?)\n\n", front, flags=re.S | re.M).group(1).split())
    if TITLE_IEEE.lower() != full_title.rstrip(".").lower():
        raise SystemExit(f"TITLE_IEEE no longer matches the manuscript's 'Full title:' line: {full_title!r}")
    author = re.search(r"^([A-Z][^.\n]*?)\.\s+Co-authors", front, flags=re.M)
    if not author:
        raise SystemExit("cannot find the author line under the title")
    return sections, author.group(1)


def build_main(authors):
    md = (REPO / "paper/manuscript.md").read_text(encoding="utf-8")
    known = paper_numbers()
    sections, author = front_matter(md)
    surname = author.split()[-1]
    initials = "~".join(f"{p[0]}." for p in author.split()[:-1])
    sec = {h: t for h, t in sections}
    abstract_md = sec["## Abstract"].split("**Keywords:**")[0].strip()
    keywords = sec["## Abstract"].split("**Keywords:**")[1].strip()
    keywords = [k.strip().rstrip(".") for k in " ".join(keywords.split()).split(";") if k.strip()]
    index_terms = sorted(keywords, key=str.lower)
    index_terms = [index_terms[0][0].upper() + index_terms[0][1:]] + index_terms[1:]

    heads = [h for h, _ in sections]
    start = heads.index("## 1. Introduction")
    end = next(i for i, h in enumerate(heads) if h.startswith("## CRediT"))
    body_md = "\n".join(h + "\n" + t for h, t in sections[start:end])
    # The IEEE version has no highlights, so the text must not point to them.
    body_md = re.sub(r"the\s+highlights,\s+", "", body_md)
    if re.search(r"\bthe\s+highlights\b", body_md, flags=re.I):
        raise SystemExit("the manuscript body mentions the highlights, which the IEEE version drops")
    body_tex = body_to_tex(body_md, "main", authors, known)
    # IEEE journal drop cap on the first word of the Introduction.
    body_tex = re.sub(r"(\\label\{sec:1\}\n+)(\w)(\w*)", r"\1\\IEEEPARstart{\2}{\3}", body_tex, count=1)

    def back(name):
        h = next(x for x in heads if x.startswith(name))
        return sec[h].strip()
    data_tex = snippet(back("## Data and code availability"), "main", authors, known)
    ack_tex = snippet(back("## Acknowledgements"), "main", authors, known)
    ai_tex = snippet(back("## Declaration of generative AI"), "main", authors, known)
    abstract_tex = snippet(abstract_md, "main", authors, known)
    credit_md = back("## CRediT")
    competing_md = back("## Declaration of competing interest")
    funding_md = back("## Funding")
    short_title = TITLE_IEEE.split(":")[0]

    return f"""% JSTARS submission version of the benchmark paper, generated from
% paper/manuscript.md by scripts/paper_to_ieee.py for editing on Overleaf.
% Compile with pdfLaTeX and BibTeX (Overleaf's default). Search for TODO.
\\documentclass[journal]{{IEEEtran}}
\\usepackage[T1]{{fontenc}}
% IEEE writes citation ranges out: [1], [2], [3], not [1]--[3].
\\usepackage[nocompress]{{cite}}
\\usepackage{{amsmath}}
\\usepackage{{graphicx}}
% pdfTeX warns when a page holds several PDF figures that each carry a page
% group, as cairo writes them; the warning is harmless. Other engines skip this.
\\ifdefined\\pdfsuppresswarningpagegroup\\pdfsuppresswarningpagegroup=1\\relax\\fi
\\usepackage{{array}}
\\usepackage{{tabularx}}
\\usepackage{{url}}
\\urlstyle{{same}}
\\providecommand{{\\tightlist}}{{\\setlength{{\\itemsep}}{{0pt}}\\setlength{{\\parskip}}{{0pt}}}}
\\newcolumntype{{L}}{{>{{\\raggedright\\arraybackslash}}X}}
\\newcolumntype{{R}}{{>{{\\raggedleft\\arraybackslash}}X}}
\\newcolumntype{{C}}{{>{{\\centering\\arraybackslash}}X}}
\\graphicspath{{{{./}}{{../}}}}

\\begin{{document}}
% IEEEtran.bst control: the first author and "et al." beyond six authors.
\\bstctlcite{{IEEEexample:BSTcontrol}}

\\title{{{TITLE_IEEE}}}

% TODO: complete the author block. IEEE puts the funding statement in the first
% footnote and each author's affiliation and e-mail in the next ones.
\\author{{{author.replace(" ", "~")}%
\\thanks{{Manuscript received Month DD, 2026. % TODO: leave for the journal or fill in
This work was supported by TODO. % TODO: funding statement, or remove this sentence
}}%
\\thanks{{{initials}~{surname} is with TODO affiliation (e-mail: TODO). % TODO
}}}}

\\markboth{{IEEE Journal of Selected Topics in Applied Earth Observations and Remote Sensing}}%
{{{surname}: {short_title}}}

\\maketitle

\\begin{{abstract}}
{abstract_tex}
\\end{{abstract}}

\\begin{{IEEEkeywords}}
{", ".join(index_terms)}.
\\end{{IEEEkeywords}}

{body_tex}

\\section*{{Data and Code Availability}}

{data_tex}

\\section*{{Acknowledgment}}

{ack_tex}

% IEEE policy: disclose AI-generated content here, name the AI system, identify
% the sections that contain AI-generated text and say at what level it was used.
% The statement below does all three; check it against the final text.
{ai_tex}

% Elsevier-only sections of the markdown draft, kept for reference. IEEE asks
% for competing interests in the ScholarOne submission form and does not print
% CRediT statements.
% CRediT authorship contribution statement: {" ".join(credit_md.split())}
% Declaration of competing interest: {" ".join(competing_md.split())}
% Funding: {" ".join(funding_md.split())}

\\bibliographystyle{{IEEEtran}}
\\bibliography{{references}}

% TODO: JSTARS asks for a brief biography and a photograph of each author,
% e.g. with the photograph saved as photo.jpg next to this file:
% \\begin{{IEEEbiography}}[{{\\includegraphics[width=1in,height=1.25in,clip,keepaspectratio]{{photo}}}}]{{{author}}}
% Biography text here.
% \\end{{IEEEbiography}}

\\end{{document}}
"""


def build_supplement(authors):
    manuscript = (REPO / "paper/manuscript.md").read_text(encoding="utf-8")
    known = paper_numbers()
    _, author = front_matter(manuscript)
    md = (REPO / "paper/supplement.md").read_text(encoding="utf-8")
    sections = split_sections(md)
    intro, code = hold_code(sections[0][1])
    intro = restore_code(re.sub(r"(?m)^# .*$", "", intro), code).strip()  # the H1, not a code comment
    # The markdown links the draft; the IEEE supplement names the paper.
    intro, n = re.subn(r"Supplement to the draft manuscript \[[^\]]*\]\(manuscript\.md\)\.",
                       f"Supplement to the manuscript \u201c{TITLE_IEEE}.\u201d", intro)
    if n != 1:
        raise SystemExit("the supplement no longer opens with 'Supplement to the draft manuscript [...](manuscript.md).'")
    body_md = "\n".join(h + "\n" + t for h, t in sections[1:])
    body_tex = body_to_tex(body_md, "supp", authors, known)
    intro_tex = snippet(intro, "supp", authors, known) if intro else ""
    title = TITLE_IEEE.replace(": ", ":\n", 1)
    return f"""% Supplementary material for the JSTARS submission, converted from
% paper/supplement.md. Upload its PDF as supplementary material. References to
% the manuscript use the IEEE numbering of main.tex (Section IV-A, Table III).
\\documentclass[10pt]{{article}}
\\usepackage[T1]{{fontenc}}
\\usepackage{{mathptmx}}
\\renewcommand{{\\ttdefault}}{{pcr}}
\\usepackage[margin=2cm]{{geometry}}
\\usepackage[nocompress]{{cite}}
\\usepackage{{amsmath}}
\\usepackage{{graphicx}}
\\ifdefined\\pdfsuppresswarningpagegroup\\pdfsuppresswarningpagegroup=1\\relax\\fi
\\usepackage{{array}}
\\usepackage{{xltabular}}
\\usepackage{{url}}
\\usepackage[hidelinks]{{hyperref}}
\\providecommand{{\\tightlist}}{{\\setlength{{\\itemsep}}{{0pt}}\\setlength{{\\parskip}}{{0pt}}}}
\\newcolumntype{{L}}{{>{{\\raggedright\\arraybackslash}}X}}
\\newcolumntype{{R}}{{>{{\\raggedleft\\arraybackslash}}X}}
\\newcolumntype{{C}}{{>{{\\centering\\arraybackslash}}X}}
\\graphicspath{{{{./}}{{../}}}}
\\setlength{{\\parindent}}{{0pt}}
\\setlength{{\\parskip}}{{4pt}}
\\setlength{{\\emergencystretch}}{{3em}}
% IEEEtran.bst's control entry has to be cited first without a reference-list
% item; this is the IEEEtran class's \\bstctlcite, which article lacks.
\\makeatletter
\\newcommand{{\\bstctlcite}}[1]{{\\@bsphack\\if@filesw\\immediate\\write\\@auxout{{\\string\\citation{{#1}}}}\\fi\\@esphack}}
% Figures float ([!ht]), so the text of their section fills the page before
% them, but never leave their section. Before each section (the references
% too), the figures still waiting go to the top of the next page or pages:
% the page builder settles first (\\addpenalty), \\null ends a page of floats
% alone, and \\clearpage is the last resort for a figure no page can take.
% After a section's heading, no figure goes above it on the same page. This
% is placeins's [section] option without its pages of floats alone.
\\newcommand\\suppFloatBarrier{{\\par\\addpenalty\\z@
  \\ifx\\@deferlist\\@empty\\else\\expandafter\\supp@flush\\fi}}
\\newcommand\\supp@flush{{\\let\\supp@waiting\\@deferlist
  \\newpage
  \\ifx\\@deferlist\\supp@waiting\\null\\newpage\\fi
  \\ifx\\@deferlist\\supp@waiting\\expandafter\\clearpage\\else\\expandafter\\suppFloatBarrier\\fi}}
\\gdef\\supp@afterheading{{}}
\\g@addto@macro\\@afterheading{{\\supp@afterheading}}
\\AtBeginDocument{{\\let\\supp@section\\section
  \\renewcommand\\section{{\\suppFloatBarrier
    \\gdef\\supp@afterheading{{\\suppressfloats[t]\\gdef\\supp@afterheading{{}}}}\\supp@section}}}}
\\makeatother

\\title{{Supplementary Material for ``{title}''}}
\\author{{{author}}}
\\date{{}}

\\begin{{document}}
\\bstctlcite{{IEEEexample:BSTcontrol}}% IEEEtran.bst control: the first author and "et al." beyond six
\\maketitle

{intro_tex}

{body_tex}

\\bibliographystyle{{IEEEtran}}
\\bibliography{{references}}

\\end{{document}}
"""


INCLUDE_GRAPHICS = re.compile(r"\\includegraphics(?:\[[^\]]*\])?\{([^}]*)\}")


def graphics_files(tex):
    """The files that a LaTeX document includes with \\includegraphics, outside
    comments and code blocks, in order of first use."""
    tex = VERBATIM.sub("", tex)
    return list(dict.fromkeys(INCLUDE_GRAPHICS.findall(re.sub(r"(?<!\\)%.*", "", tex))))


def write_zip(out, zip_path):
    """Overleaf upload: the three sources at the root and every figure file
    that main.tex or supplement.tex includes, at the path it is included by
    (relative to paper/, e.g. figures/figure_3.pdf)."""
    sources = ("main.tex", "supplement.tex", "references.bib")
    figures = list(dict.fromkeys(f for name in sources[:2]
                                 for f in graphics_files((out / name).read_text(encoding="utf-8"))))
    missing = [f for f in figures if not (REPO / "paper" / f).is_file()]
    if missing:
        raise SystemExit(f"figure files that the LaTeX includes are not under paper/: {missing}")
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for name in sources:
            z.write(out / name, name)
        for f in figures:
            z.write(REPO / "paper" / f, f)
    return zip_path


def main(argv):
    global PANDOC
    if any(a in ("-h", "--help") for a in argv):
        print(__doc__)
        return
    bad = [a for a in argv if "=" not in a]
    if bad:
        raise SystemExit(f"arguments must be KEY=VALUE (see --help); got {bad}")
    args = dict(a.split("=", 1) for a in argv)
    unknown = set(args) - {"OUT", "PANDOC", "ZIP"}
    if unknown:
        raise SystemExit(f"unknown arguments: {sorted(unknown)}")
    PANDOC = args.get("PANDOC", "pandoc")
    if shutil.which(PANDOC) is None and not Path(PANDOC).is_file():
        raise SystemExit(f"pandoc not found: {PANDOC}")
    out = (REPO / args.get("OUT", "paper/ieee")).resolve()
    bib_text = (REPO / "docs/references.bib").read_text(encoding="utf-8")
    authors = bib_authors(bib_text)
    FIG_WIDTH.clear()
    FIG_FILE.clear()
    # Build everything before writing, so a failure leaves the folder as it was.
    docs = {"references.bib": ieee_bib(bib_text), "main.tex": build_main(authors),
            "supplement.tex": build_supplement(authors)}
    out.mkdir(parents=True, exist_ok=True)
    for name, text in docs.items():
        (out / name).write_text(text, encoding="utf-8")
    print("wrote", ", ".join(str((out / n).relative_to(REPO)) if out.is_relative_to(REPO) else str(out / n)
                            for n in docs))
    print("figure widths:", FIG_WIDTH)
    print("figure files:", FIG_FILE)
    if "ZIP" in args:
        z = Path(args["ZIP"])
        z = z if z.is_absolute() else REPO / z
        print("wrote", write_zip(out, z))


if __name__ == "__main__":
    main(sys.argv[1:])
