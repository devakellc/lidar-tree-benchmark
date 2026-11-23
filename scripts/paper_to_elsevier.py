"""Convert the paper's markdown to the Elsevier LaTeX version for the ISPRS
Journal of Photogrammetry and Remote Sensing.

Reads paper/manuscript.md, paper/supplement.md, paper/figures/ and
docs/references.bib, and writes main.tex (Elsevier's elsarticle class in its
preprint layout, 12 pt on A4 with line numbers), supplement.tex (article class,
A4) and an Elsevier copy of the bibliography to OUT. The markdown machinery
(pandoc, code blocks, math, table widths, figure files, the numbers that a
reference may name) is that of scripts/paper_to_ieee.py, which this script
loads as a library; what differs is the journal's form:

- Citations are author-year (natbib with elsarticle-harv.bst): a bracketed
  group becomes \\citep, "(Jakubowski et al., 2013; Kaartinen et al., 2012)",
  sorted alphabetically then chronologically as the journal asks, and a
  narrative citation becomes \\citet, "Jakubowski et al. (2013)". A key that
  the bibliography does not hold stops the build.
- Numbering is the markdown's own: sections 1, 1.1, tables and figures 1, 2.
  Every reference to a manuscript section, table or figure is a \\ref, a
  figure panel stays as it is written (Fig. 2d), and the supplement writes
  the manuscript's numbers as text. The build stops when the markdown's
  section numbers are not the sequence LaTeX would print.
- The front matter keeps the highlights (3 to 5, each at most 85 characters,
  or the build stops), the abstract and at most six keywords, as the journal
  asks; headings keep the markdown's sentence case. The author block, the
  affiliation and the corresponding author's e-mail are TODO placeholders.
- The back matter keeps every section of the markdown between the conclusion
  and the references, in order, as unnumbered sections: CRediT statement,
  competing interest, funding, data and code availability, acknowledgements
  and, last before the references as the journal requires, the declaration
  of generative AI (the build stops if it is not last). A section that still
  reads "To be completed" gets a TODO comment.
- Tables take booktabs rules and no vertical rules. In the manuscript every
  caption goes directly below its figure or table and floats are placed here,
  at the top or the bottom of a page or on a page of their own ([!htbp]), as
  the journal asks of the single file of a first submission; a table whose
  words cannot fit the portrait width goes on a landscape page. The
  supplement's tables break across pages (xltabular), each captioned in its
  first head row, and its figures are labelled "Figure S1." in the text, as
  in the IEEE version.
- A figure is included as the vector PDF beside its PNG when there is one, at
  the width it was drawn as a share of the text width (160 mm in the
  manuscript, 170 mm in the supplement), at most the whole width and rounded
  up to hundredths; a figure with only a PNG takes its width from the PNG's
  aspect ratio.

The Elsevier copy of the bibliography is written for elsarticle-harv.bst,
which sets titles in sentence case and prints the DOI, URL and arXiv
identifier fields itself, but ignores version and urldate, a misc entry's
organization, and a proceedings paper's series, volume and number. Software
and dataset entries become misc entries; the version, the note and the access
date ("Accessed 2 October 2026") go into the note; a misc entry's publisher
becomes its howpublished, or joins the note, unless it repeats the author; a
proceedings paper's series, volume and number join its proceedings title. A
paper with a DOI is cited without its arXiv identifier, as the journal cites
the version of record, and an arXiv preprint (a misc entry) without one takes
its arXiv DOI (10.48550/arXiv.<id>), as the journal asks for a preprint's DOI;
a published paper without a DOI keeps its arXiv identifier only. A corporate
author written with its abbreviation, "National Ecological Observatory Network
(NEON)", loses the abbreviation, so the citation does not nest parentheses. A
publisher ending in a period loses it where the style adds one, and a long
commit hash in a note may break every eight characters. Acronyms,
single capitals and words with inner capitals in titles are braced, as in the
IEEE copy, a note's first letter is braced so the style keeps its case, and a
quotation inside a title keeps its double quotes. DOIs print as
https://doi.org/ links.

The converter stops with an error rather than guess in every case that
scripts/paper_to_ieee.py stops, and also on a bracketed citation of an
unknown key, a heading numbered out of sequence, highlights that break the
journal's limits, more than six keywords, or a back matter that does not end
with the declaration of generative AI.

Arguments are KEY=VALUE pairs:
  OUT=paper/elsevier    output directory (relative to the repository root)
  PANDOC=pandoc         pandoc binary (3.x)
  ZIP=path.zip          also write an Overleaf upload zip with the sources and
                        the figure files they include

  python3 scripts/paper_to_elsevier.py PANDOC=/path/to/pandoc \\
    ZIP=work/paper-elsevier/isprs-overleaf.zip
"""
import importlib.util
import math
import re
import shutil
import sys
import textwrap
from pathlib import Path, PurePosixPath

_spec = importlib.util.spec_from_file_location("paper_to_ieee", Path(__file__).resolve().parent / "paper_to_ieee.py")
p2i = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(p2i)

JOURNAL = "ISPRS Journal of Photogrammetry and Remote Sensing"
NBSP = p2i.NBSP
# The journal's limits (guide for authors, read 21 October 2026; Elsevier's
# highlights rule).
MAX_KEYWORDS = 6
HIGHLIGHTS = (3, 5)
HIGHLIGHT_CHARS = 85
AI_HEADING = "## Declaration of generative AI and AI-assisted technologies in the manuscript preparation process"

# Layout: A4 with 2.5 cm margins and 12 pt type in the manuscript, 2 cm
# margins and 10 pt type in the supplement. Widths in mm, in inches (figures)
# and in TeX points (tables); the table font sizes of each document; the space
# between two columns (twice \tabcolsep) and Times' interword space.
TEXT_WIDTH_MM = {"main": 160.0, "supp": 170.0}
TEXT_WIDTH_IN = {m: w / 25.4 for m, w in TEXT_WIDTH_MM.items()}
TABLE_PT = {m: w / 25.4 * 72.27 for m, w in TEXT_WIDTH_MM.items()}
# A manuscript table whose words cannot fit the portrait width goes on a
# landscape page of its own, as wide as the text is high (297 mm less the
# margins).
LANDSCAPE_PT = 247.0 / 25.4 * 72.27
FONT_PT = {"main": {"\\footnotesize": 10.0, "\\scriptsize": 8.0},
           "supp": {"\\footnotesize": 8.0, "\\scriptsize": 7.0}}
COLSEP_PT = 6.0
SPACE_EM = 0.25
X_THRESHOLD = {"main": 12, "supp": 16}
MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
          "November", "December"]

FIG_WIDTH = {}
FIG_FILE = {}

# ------------------------------------------------------------------ citations


def cite_labels(bib_text):
    """key -> (names, year) as natbib's author-year citations print them:
    'Surname', 'A and B' or 'Surname et al.' (a corporate author without its
    parenthesised abbreviation), and the year field."""
    names = p2i.bib_authors(bib_text)
    return {key: (short_corporate(names.get(key, key)), dict(fields).get("year", ""))
            for _, key, fields, _ in p2i.parse_bib(bib_text)}


def convert_citations(md, labels):
    """[@a; @b] -> \\citep{a,b}; a narrative @a -> \\citet{a}. Prefixes,
    locators, comma lists and unknown keys stop the build."""
    def known(key):
        if key not in labels:
            raise SystemExit(f"citation of {key}, which docs/references.bib does not hold")
        return key

    def group(m):
        return "\\citep{" + ",".join(known(k) for k in re.findall(r"@([a-z0-9]+)", m.group(0))) + "}"
    md = re.sub(r"\[@[a-z0-9]+(?:;\s*@[a-z0-9]+)*\]", group, md)
    left = re.search(r"\[[^\[\]]*@[a-z0-9]+[^\[\]]*\]", md)
    if left:
        raise SystemExit(f"unsupported citation form (prefix, locator or comma list): {left.group(0)!r}")
    left = re.search(r"(?<![\w@\\{])@[a-z0-9]+\s*\[", md)
    if left:
        raise SystemExit(f"unsupported citation form (narrative citation with a locator): {left.group(0)!r}")
    return re.sub(r"(?<![\w@\\{])@([a-z0-9]+)", lambda m: f"\\citet{{{known(m.group(1))}}}", md)


def cite_text(cell, labels):
    """A table cell with its citations and references written as they print,
    for estimating the widths of its words: (Name et al., 2020; ...) and
    Name et al. (2020), and 4.2 for \\ref{sec:4.2}."""
    def citep(m):
        return "(" + "; ".join(f"{labels[k][0]}, {labels[k][1]}" for k in m.group(1).split(",")) + ")"
    cell = re.sub(r"\\citep\{([^}]*)\}", citep, cell)
    cell = re.sub(r"\\citet\{([^}]*)\}", lambda m: f"{labels[m.group(1)][0]} ({labels[m.group(1)][1]})", cell)
    return re.sub(r"\\ref\{[a-z]+:([^}]*)\}", r"\1", cell)


# ------------------------------------------------------------- tables/figures


def one_line_em(cell):
    words = p2i.word_widths(cell, SPACE_EM)
    return sum(words) + SPACE_EM * max(len(words) - 1, 0)


def table_spec(est, aligns, mode, width_em):
    """The column letters of a table: paper_to_ieee.column_spec's, and when no
    column wraps but the table is wider than width_em at its natural width (or
    in the supplement, whose tables always span the text width), every column
    after the label column wraps."""
    spec = p2i.column_spec(est[0], est[1:], aligns, X_THRESHOLD[mode])
    natural = sum(max(one_line_em(r[j]) for r in est) for j in range(len(spec)))
    if not any(s in "LRC" for s in spec) and (mode == "supp" or natural > width_em):
        spec = [spec[0]] + [{"l": "L", "r": "R", "c": "C"}[a] for a in spec[1:]]
    return spec


def words_fit(spec, est, width_em, factors):
    """Whether every column holds its longest word at width_em: a wrapping
    column at its share of the width (its factor times the width that the X
    columns share after the other columns' widest cells), any other column at
    its widest cell, which the table must still leave room for."""
    xcols = [j for j, s in enumerate(spec) if s in "LRC"]
    fixed = sum(max(one_line_em(r[j]) for r in est) for j in range(len(spec)) if j not in xcols)
    if not xcols:
        return fixed <= width_em
    share = (width_em - fixed) / len(xcols)
    longest = [max((w for r in est for w in p2i.word_widths(r[j], SPACE_EM)), default=0.0) for j in xcols]
    return share > 0 and all(float(factors[j]) * share >= w for j, w in zip(xcols, longest))


def table_tex(num, caption_tex, header, aligns, body, mode, labels):
    """A table's LaTeX with booktabs rules. In the manuscript a table float
    ([!htbp]) with its caption directly below; a table that fits at its
    natural width is a centred tabular, any other a tabularx at the text
    width, and a table whose words cannot fit the text width at all goes on
    a landscape page (sidewaystable) as wide as the text is high, its caption
    below as well. In the supplement an
    xltabular at the text width that breaks across pages, its caption the
    first head row and its head repeated under 'Table Sn (continued)'. The X
    columns take widths in proportion to their text (paper_to_ieee.x_factors),
    estimated from the cells as they print."""
    flat = p2i.pandoc_snippets(header + [c for r in body for c in r])
    ncol = len(header)
    head_tex = flat[:ncol]
    rows_tex = [flat[ncol + i * ncol: ncol + (i + 1) * ncol] for i in range(len(body))]
    est = [[cite_text(c, labels) for c in r] for r in [header] + body]
    size = "\\footnotesize" if ncol <= 5 else "\\scriptsize"
    width_em = (TABLE_PT[mode] - COLSEP_PT * ncol) / FONT_PT[mode][size]
    spec = table_spec(est, aligns, mode, width_em)
    factors = p2i.x_factors(spec, est, width_em, SPACE_EM)
    landscape = mode == "main" and not words_fit(spec, est, width_em, factors)
    if landscape:
        # The landscape width takes the larger size when its words fit there.
        for size in ("\\footnotesize", "\\scriptsize"):
            width_em = (LANDSCAPE_PT - COLSEP_PT * ncol) / FONT_PT[mode][size]
            spec = table_spec(est, aligns, mode, width_em)
            factors = p2i.x_factors(spec, est, width_em, SPACE_EM)
            if words_fit(spec, est, width_em, factors):
                break
    preamble = "".join(s if f in (None, "1", "1.00") else f">{{\\hsize={f}\\hsize\\linewidth=\\hsize}}{s}"
                       for s, f in zip(spec, factors))
    head_row = " & ".join(head_tex) + " \\\\"
    body_rows = [" & ".join(r) + " \\\\" for r in rows_tex]
    setup = ["\\setlength{\\tabcolsep}{3pt}", "\\renewcommand{\\arraystretch}{1.15}"]
    if mode == "main":
        has_x = any(s in "LRC" for s in spec)
        env, width = ("tabularx", "{\\linewidth}") if has_x else ("tabular", "")
        float_env, place = ("sidewaystable", "") if landscape else ("table", "[!htbp]")
        # The caption goes directly below the table, as the journal asks of
        # the tables in the single file of a first submission.
        lines = [f"\\begin{{{float_env}}}{place}", "\\centering", "{" + size] + setup + [
            f"\\begin{{{env}}}{width}{{{preamble}}}", "\\toprule", head_row, "\\midrule"]
        return "\n".join(lines + body_rows + ["\\bottomrule", f"\\end{{{env}}}", "}", f"\\caption{{{caption_tex}}}",
                                              f"\\label{{tab:{num}}}", f"\\end{{{float_env}}}"])
    caption_row = (f"\\multicolumn{{{ncol}}}{{@{{}}p{{\\textwidth}}@{{}}}}"
                   f"{{\\normalsize\\textbf{{Table {num}.}} {caption_tex}}} \\\\[4pt]")
    continued_row = (f"\\multicolumn{{{ncol}}}{{@{{}}l@{{}}}}"
                     f"{{\\normalsize\\textbf{{Table {num}}} (continued)}} \\\\[4pt]")
    lines = ["{" + size] + setup + [f"\\begin{{xltabular}}{{\\textwidth}}{{{preamble}}}",
                                    caption_row, "\\toprule", head_row, "\\midrule", "\\endfirsthead",
                                    continued_row, "\\toprule", head_row, "\\midrule", "\\endhead",
                                    "\\bottomrule", "\\endfoot"]
    return "\n".join(lines + body_rows + ["\\end{xltabular}", "}"])


def figure_width(src, aspect, mode):
    """The width a figure prints at: with a PDF beside the PNG, the PDF's page
    width as a share of the text width, at most the whole width and rounded up
    to hundredths, so it prints at the size it was drawn; with the PNG alone,
    the full width from an aspect ratio of 1.6, 0.85 of it from 1.3 and 0.72
    below."""
    pdf = src.with_suffix(".pdf")
    if pdf.is_file():
        share = math.ceil(round(min(1.0, p2i.pdf_page_width(pdf) / TEXT_WIDTH_IN[mode]) * 100, 6)) / 100
        return "\\textwidth" if share >= 1 else f"{share:.2f}\\textwidth"
    return "\\textwidth" if aspect >= 1.6 else ("0.85\\textwidth" if aspect >= 1.3 else "0.72\\textwidth")


def figure_tex(num, path, caption_tex, mode):
    """A figure float with its caption below: \\caption and \\label in the
    manuscript; 'Figure Sn.' as text in the supplement, as its tables are
    labelled, floating here or to the top of a page ([!ht]) within its
    section (the supplement's barrier, as in the IEEE version)."""
    src, aspect = p2i.figure_png(path)
    width = figure_width(src, aspect, mode)
    graphic = str(PurePosixPath(path).with_suffix(".pdf")) if src.with_suffix(".pdf").is_file() else path
    FIG_WIDTH[num], FIG_FILE[num] = width, graphic
    if mode == "main":
        return "\n".join(["\\begin{figure}[!htbp]", "\\centering", f"\\includegraphics[width={width}]{{{graphic}}}",
                          f"\\caption{{{caption_tex}}}", f"\\label{{fig:{num}}}", "\\end{figure}"])
    return "\n".join(["\\begin{figure}[!ht]", f"{{\\centering\\includegraphics[width={width}]{{{graphic}}}\\par}}",
                      "\\medskip", f"\\textbf{{Figure {num}.}} {caption_tex}", "\\end{figure}"])


# ------------------------------------------------------------------ documents


def check_numbering(md):
    """The manuscript's headings must number 1, 1.1, 1.2, 2 ... in order, as
    LaTeX numbers them, since its references print LaTeX's numbers."""
    held, _ = p2i.hold_code(md)
    sec = sub = 0
    for m in re.finditer(r"(?m)^(#{2,6}) (.*)$", held):
        level, text = len(m.group(1)), m.group(2).strip()
        if level > 3:
            raise SystemExit(f"a heading below level 3 in the manuscript, which has no numbering for it: {text!r}")
        mm = re.match(r"(\d+)(?:\.(\d+))?\.?\s", text)
        if not mm:
            raise SystemExit(f"unnumbered heading in body: {text}")
        if level == 2:
            sec, sub = sec + 1, 0
            want = (str(sec), None)
        else:
            sub += 1
            want = (str(sec), str(sub))
        if (mm.group(1), mm.group(2)) != want or (level == 2) != (mm.group(2) is None):
            raise SystemExit(f"heading {text!r} is out of sequence: LaTeX numbers it {'.'.join(w for w in want if w)}")


def body_to_tex(md, mode, labels, known):
    """Convert a body of markdown (headings, paragraphs, tables, figures), as
    paper_to_ieee.body_to_tex does, in the Elsevier form."""
    p2i.check_math_fence(md)
    md, code = p2i.hold_code(md)
    md = p2i.links(convert_citations(md, labels), mode)
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
    md = p2i.FIGURE_BLOCK.sub(take_figure, md)
    if "![" in md or re.search(r"(?m)^\*\*Figure S?\d+\.\*\*", md):
        raise SystemExit("an image or figure caption is not in the '![Figure N.](path)' + '**Figure N.**' form")

    def take_table(m):
        tok = f"ZZTAB{m.group(1)}ZZ"
        blocks[tok] = ("table", m.group(1), m.group(2), m.group(3))
        return f"\n\n{tok}\n\n"
    md = p2i.TABLE_BLOCK.sub(take_table, md)
    stray = re.search(r"\*\*Table S?\d+[a-z]?\.\*\*", md)
    if stray:
        raise SystemExit(f"{stray.group(0)} is not a one-paragraph caption directly followed by its pipe table")
    stray = re.search(r"(?m)^[ \t]*\|.*$", md)
    if stray:
        raise SystemExit(f"a pipe table without a '**Table N.**' caption: {stray.group(0)[:60]!r}")

    md = p2i.convert_refs(md, mode, known, style="elsevier")

    def heading(m):
        level, text = len(m.group(1)), m.group(2).strip()
        if mode == "main":
            mm = re.match(r"(\d+(?:\.\d+)?)\.?\s+(.*)", text)
            num, title = mm.group(1), p2i.protect_urls(p2i.pandoc_snippets([mm.group(2)])[0])
            cmd = "section" if level == 2 else "subsection"
            return f"\n\\{cmd}{{{title}}}\\label{{sec:{num}}}\n"
        cmd = "section*" if level == 2 else "subsection*"
        return f"\n\\{cmd}{{{p2i.pandoc_snippets([text])[0]}}}\n"
    md = re.sub(r"(?m)^(#{2,3}) (.*)$", heading, md)

    tex = p2i.pandoc(p2i.restore_code(md, code))
    p2i.check_code_blocks(tex, len(code))
    tex = p2i.display_math(tex, numbered=mode == "main")

    for tok, spec in blocks.items():
        if spec[0] == "figure":
            _, num, path, cap = spec
            cap_tex = p2i.protect_urls(p2i.pandoc_snippets([p2i.convert_refs(cap, mode, known, "elsevier")])[0])
            repl = figure_tex(num, path, cap_tex, mode)
        else:
            _, num, cap, table = spec
            cap_tex = p2i.protect_urls(p2i.pandoc_snippets([p2i.convert_refs(cap, mode, known, "elsevier")])[0])
            header, aligns, body = p2i.parse_pipe_table(table)
            header = [p2i.convert_refs(c, mode, known, "elsevier") for c in header]
            body = [[p2i.convert_refs(c, mode, known, "elsevier") for c in r] for r in body]
            repl = table_tex(num, cap_tex, header, aligns, body, mode, labels)
        if tex.count(tok) != 1:
            raise SystemExit(f"placeholder {tok} found {tex.count(tok)} times")
        tex = tex.replace(tok, repl)
    return p2i.unescape_brackets(p2i.unicode_to_latex(tex))


def snippet(md, mode, labels, known):
    """Convert a section outside the body (the abstract, the back matter)."""
    p2i.check_math_fence(md)
    md, code = p2i.hold_code(md)
    md = p2i.links(p2i.convert_refs(convert_citations(md, labels), mode, known, "elsevier"), mode)
    if "![" in md:
        raise SystemExit("an image outside the body is not supported")
    tex = p2i.pandoc_snippets([p2i.restore_code(md, code)], inline=False)[0]
    p2i.check_code_blocks(tex, len(code))
    if any(display for _, _, display in p2i.math_spans(tex)):
        raise SystemExit("display math outside the body text (abstract, back matter) is not supported")
    return p2i.unescape_brackets(p2i.unicode_to_latex(tex))


def inline_tex(tex):
    """pandoc's LaTeX for a short piece of text, with its Unicode mapped to
    LaTeX as in the body, so every output is ASCII."""
    return p2i.unescape_brackets(p2i.unicode_to_latex(tex))


def front_matter(md):
    """(sections, full title, author, ORCID iD or None) of the manuscript."""
    sections = p2i.split_sections(md)
    front = sections[0][1]
    title = re.search(r"^Full title:\s*(.*?)\n\n", front, flags=re.S | re.M)
    if not title:
        raise SystemExit("cannot find the 'Full title:' line under the heading")
    author = re.search(r"^([A-Z][^.\n]*?)\.\s+Co-authors", front, flags=re.M)
    if not author:
        raise SystemExit("cannot find the author line under the title")
    orcid = re.search(r"^ORCID:\s*\[?(\d{4}-\d{4}-\d{4}-\d{3}[\dX])\b", front, flags=re.M)
    if re.search(r"^ORCID:", front, flags=re.M) and not orcid:
        raise SystemExit("cannot read the ORCID iD under the author line")
    return sections, " ".join(title.group(1).split()).rstrip("."), author.group(1), orcid.group(1) if orcid else None


def highlights(text):
    """The highlights as markdown items; 3 to 5 of at most 85 characters
    (spaces included, markup not), as Elsevier asks."""
    items = []
    for line in text.strip().split("\n"):
        if line.startswith("- "):
            items.append(line[2:].strip())
        elif line.startswith("  ") and line.strip() and items:
            items[-1] += " " + line.strip()
        elif line.strip():
            raise SystemExit(f"the highlights must be a '- ' list: {line!r}")
    if not HIGHLIGHTS[0] <= len(items) <= HIGHLIGHTS[1]:
        raise SystemExit(f"{len(items)} highlights; the journal asks for {HIGHLIGHTS[0]} to {HIGHLIGHTS[1]}")
    for item in items:
        n = len(re.sub(r"[*`]", "", item))
        if n > HIGHLIGHT_CHARS:
            raise SystemExit(f"a highlight of {n} characters (at most {HIGHLIGHT_CHARS}): {item!r}")
    return items


def build_main(labels):
    md = (p2i.REPO / "paper/manuscript.md").read_text(encoding="utf-8")
    known = p2i.paper_numbers()
    sections, title, author, orcid = front_matter(md)
    sec = {h: t for h, t in sections}
    heads = [h for h, _ in sections]
    for need in ("## Highlights", "## Abstract", "## 1. Introduction", "## References"):
        if need not in sec:
            raise SystemExit(f"the manuscript has no '{need}' section")
    abstract_md, _, keywords = sec["## Abstract"].partition("**Keywords:**")
    keywords = [k.strip().rstrip(".") for k in " ".join(keywords.split()).split(";") if k.strip()]
    if not keywords or len(keywords) > MAX_KEYWORDS:
        raise SystemExit(f"{len(keywords)} keywords; the journal takes 1 to {MAX_KEYWORDS}")
    items = highlights(sec["## Highlights"])

    start = heads.index("## 1. Introduction")
    end = next((i for i, h in enumerate(heads) if i > start and not re.match(r"## \d", h)), None)
    refs = heads.index("## References")
    if end is None or end > refs:
        raise SystemExit("the back matter must sit between the numbered sections and the references")
    body_md = "\n".join(h + "\n" + t for h, t in sections[start:end])
    check_numbering(body_md)
    back = sections[end:refs]
    if not back or back[-1][0] != AI_HEADING:
        raise SystemExit(f"the section before the references must be '{AI_HEADING[3:]}', as the journal asks")

    body_tex = body_to_tex(body_md, "main", labels, known)
    abstract_tex = snippet(abstract_md.strip(), "main", labels, known)
    highlights_tex = "\n".join("\\item " + inline_tex(t) for t in p2i.pandoc_snippets(items))
    keywords_tex = " \\sep ".join(inline_tex(t) for t in p2i.pandoc_snippets(keywords))
    back_tex = []
    for head, text in back:
        todo = "% TODO: complete this section.\n" if text.strip().lower().startswith("to be completed") else ""
        back_tex.append(f"\\section*{{{inline_tex(p2i.pandoc_snippets([head[3:]])[0])}}}\n{todo}"
                        f"{snippet(text.strip(), 'main', labels, known)}")
    title_tex = inline_tex(p2i.pandoc_snippets([title])[0])
    orcid_tex = (f"\\fnref{{orcid1}}", f"\\fntext[orcid1]{{ORCID: \\url{{https://orcid.org/{orcid}}}.}}\n") \
        if orcid else ("", "")
    nl = "\n\n"
    return f"""%% ISPRS Journal of Photogrammetry and Remote Sensing version of the benchmark
%% paper, generated from paper/manuscript.md by scripts/paper_to_elsevier.py.
%% Compile with pdfLaTeX and BibTeX (Overleaf's default). Search for TODO.
\\documentclass[preprint,12pt,authoryear,a4paper]{{elsarticle}}
\\usepackage[T1]{{fontenc}}
\\usepackage{{mathptmx}}
% Courier and Helvetica, so no text font falls back to bitmap Computer Modern.
\\renewcommand{{\\ttdefault}}{{pcr}}
\\renewcommand{{\\sfdefault}}{{phv}}
\\usepackage[a4paper,margin=2.5cm]{{geometry}}
\\usepackage{{amsmath}}
\\usepackage{{graphicx}}
% pdfTeX warns when a page holds several PDF figures that each carry a page
% group, as cairo writes them; the warning is harmless. Other engines skip this.
\\ifdefined\\pdfsuppresswarningpagegroup\\pdfsuppresswarningpagegroup=1\\relax\\fi
\\usepackage{{array}}
\\usepackage{{tabularx}}
\\usepackage{{booktabs}}
% Landscape pages for the tables too wide for the portrait text width.
\\usepackage{{rotating}}
\\usepackage{{url}}
\\urlstyle{{same}}
\\usepackage[hidelinks]{{hyperref}}
\\usepackage{{lineno}}
\\providecommand{{\\tightlist}}{{\\setlength{{\\itemsep}}{{0pt}}\\setlength{{\\parskip}}{{0pt}}}}
\\newcolumntype{{L}}{{>{{\\raggedright\\arraybackslash}}X}}
\\newcolumntype{{R}}{{>{{\\raggedleft\\arraybackslash}}X}}
\\newcolumntype{{C}}{{>{{\\centering\\arraybackslash}}X}}
\\graphicspath{{{{./}}{{../}}}}
\\setlength{{\\emergencystretch}}{{2em}}
% DOIs as https://doi.org/ links and URLs without a label, as the journal's
% reference style prints them; elsarticle-harv.bst defines these only when
% they are undefined.
\\newcommand{{\\DOIprefix}}{{}}
\\newcommand{{\\URLprefix}}{{}}
\\newcommand{{\\doi}}[1]{{\\url{{https://doi.org/#1}}}}

% The journal lists a group of citations alphabetically, then chronologically,
% as the reference list is sorted. elsarticle passes this option to natbib on
% the next run.
\\biboptions{{sort}}
\\journal{{{JOURNAL}}}

\\begin{{document}}

\\begin{{frontmatter}}

\\title{{{title_tex}}}

% TODO: complete the author block: every author, each affiliation with its full
% postal address and country, and the corresponding author's e-mail address.
\\author[aff1]{{{author}\\corref{{cor1}}{orcid_tex[0]}}}
\\cortext[cor1]{{Corresponding author.}}
{orcid_tex[1]}\\ead{{TODO}}
\\affiliation[aff1]{{organization={{TODO}},
            city={{TODO}},
            country={{TODO}}}}

\\begin{{abstract}}
{abstract_tex}
\\end{{abstract}}

\\begin{{highlights}}
{highlights_tex}
\\end{{highlights}}

\\begin{{keyword}}
{keywords_tex}
\\end{{keyword}}

\\end{{frontmatter}}

\\linenumbers

{body_tex}

{nl.join(back_tex)}

\\bibliographystyle{{elsarticle-harv}}
\\bibliography{{references}}

\\end{{document}}
"""


def build_supplement(labels):
    manuscript = (p2i.REPO / "paper/manuscript.md").read_text(encoding="utf-8")
    known = p2i.paper_numbers()
    _, title, author, _ = front_matter(manuscript)
    md = (p2i.REPO / "paper/supplement.md").read_text(encoding="utf-8")
    sections = p2i.split_sections(md)
    intro, code = p2i.hold_code(sections[0][1])
    intro = p2i.restore_code(re.sub(r"(?m)^# .*$", "", intro), code).strip()  # the H1, not a code comment
    # The markdown links the draft; the LaTeX supplement names the paper.
    intro, n = re.subn(r"Supplement to the draft manuscript \[[^\]]*\]\(manuscript\.md\)\.",
                       f"Supplement to the manuscript \u201c{title}.\u201d", intro)
    if n != 1:
        raise SystemExit("the supplement no longer opens with 'Supplement to the draft manuscript [...](manuscript.md).'")
    body_tex = body_to_tex("\n".join(h + "\n" + t for h, t in sections[1:]), "supp", labels, known)
    intro_tex = snippet(intro, "supp", labels, known) if intro else ""
    title_tex = inline_tex(p2i.pandoc_snippets([title])[0]).replace(": ", ":\n", 1)
    return f"""%% Supplementary material for the ISPRS Journal of Photogrammetry and Remote
%% Sensing submission, converted from paper/supplement.md by
%% scripts/paper_to_elsevier.py. Upload its PDF as supplementary material.
%% References to the manuscript use its numbering (Section 4.1, Table 3).
\\documentclass[10pt,a4paper]{{article}}
\\usepackage[T1]{{fontenc}}
\\usepackage{{mathptmx}}
\\renewcommand{{\\ttdefault}}{{pcr}}
\\renewcommand{{\\sfdefault}}{{phv}}
\\usepackage[a4paper,margin=2cm]{{geometry}}
\\usepackage[round,authoryear,sort]{{natbib}}
\\usepackage{{amsmath}}
\\usepackage{{graphicx}}
\\ifdefined\\pdfsuppresswarningpagegroup\\pdfsuppresswarningpagegroup=1\\relax\\fi
\\usepackage{{array}}
\\usepackage{{xltabular}}
\\usepackage{{booktabs}}
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
\\newcommand{{\\DOIprefix}}{{}}
\\newcommand{{\\URLprefix}}{{}}
\\newcommand{{\\doi}}[1]{{\\url{{https://doi.org/#1}}}}
\\makeatletter
% Figures float ([!ht]), so the text of their section fills the page before
% them, but never leave their section: before each section the figures still
% waiting go to the top of the next page, and after a section's heading no
% figure goes above it on the same page (as in the IEEE supplement).
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

\\title{{Supplementary material for ``{title_tex}''}}
\\author{{{author}}}
\\date{{}}

\\begin{{document}}
\\maketitle

{intro_tex}

{body_tex}

\\bibliographystyle{{elsarticle-harv}}
\\bibliography{{references}}

\\end{{document}}
"""


# --------------------------------------------------------------- bibliography

DROPS = {"version", "urldate", "archiveprefix", "primaryclass", "note"}


def accessed(date):
    m = re.fullmatch(r"(\d{4})-(\d{2})-(\d{2})", date)
    if not m:
        raise SystemExit(f"urldate {date!r} is not YYYY-MM-DD")
    return f"Accessed {int(m.group(3))} {MONTHS[int(m.group(2)) - 1]} {m.group(1)}"


def protect_note(note):
    """elsarticle-harv.bst sets a note's first letter in the case of its place
    in the sentence (lower case after a DOI or URL) unless it is braced, so the
    note keeps its own: a leading acronym and 'Accessed' are braced as in the
    IEEE copy, and any other first letter is braced alone."""
    note = p2i.protect_note(note)
    return note if note.startswith("{") else re.sub(r"^([A-Za-z])", r"{\1}", note)


def join_sentences(parts):
    text = ""
    for part in parts:
        part = part.strip()
        if text:
            text += " " if re.search(r"[.?!]\}?$", text) else ". "
        text += part
    return text


# A corporate author written with its abbreviation, {National Ecological
# Observatory Network (NEON)}: the author-year label drops the abbreviation, as
# "(National Ecological Observatory Network (NEON), 2026)" nests parentheses.
CORPORATE_ABBR = re.compile(r"^\{(.+?) \(([A-Z][A-Za-z0-9]*)\)\}$")


def short_corporate(name):
    """'Name (ABBR)' -> 'Name' for a name as bib_authors returns it."""
    return re.sub(r" \([A-Z][A-Za-z0-9]*\)$", "", name)


def elsevier_entry(etype, key, fields):
    f = dict(fields)
    kind = etype.lower()
    is_misc = kind in ("misc", "software", "online", "dataset")
    out = [(n, v) for n, v in fields if n not in DROPS and v.strip()]
    if "doi" in f:  # the version of record, not the preprint
        out = [(n, v) for n, v in out if n != "eprint"]
    elif is_misc and "eprint" in f and f.get("archiveprefix", "").lower() == "arxiv":
        # The journal asks for a preprint's DOI; arXiv's is derived from its
        # identifier, without a version. The eprint field stays, to name the
        # server. A published paper (an article or proceedings paper) keeps
        # its arXiv identifier only as the eprint.
        ident = re.sub(r"v\d+$", "", re.sub(r"^arXiv:", "", f["eprint"].strip(), flags=re.I))
        out.append(("doi", f"10.48550/arXiv.{ident}"))
    if kind == "inproceedings":
        # elsarticle-harv.bst prints no volume, number or series for a paper in
        # proceedings, so they join the proceedings title.
        extra = {n: f[n].strip() for n in ("series", "volume", "number") if f.get(n, "").strip()}
        if extra:
            title = f.get("booktitle", "") + (", " + extra["series"] if "series" in extra else "")
            title += (" " + extra["volume"] if "volume" in extra else "")
            title += (f" ({extra['number']})" if "number" in extra else "")
            out = [(n, title if n == "booktitle" else v) for n, v in out if n not in extra]
    if kind in ("inproceedings", "incollection") and not f.get("address", "").strip():
        # Without an address after it, the style writes '. ' after the
        # publisher whatever it ends with, so 'Inc.' would print 'Inc..'.
        out = [(n, re.sub(r"\.$", "", v) if n in ("publisher", "organization") else v) for n, v in out]
    have = {n for n, _ in out}
    author = p2i.decode_latex(f.get("author", ""))
    notes = []
    if "version" in f:
        v = f["version"]
        commit = v.lower().startswith("commit ")
        shown = v[len("commit "):] if commit else v
        stated = re.escape(shown) if commit else rf"\bversion\s+{re.escape(shown)}(?!\.?\w)"
        if not re.search(stated, f.get("note", ""), flags=re.I):
            notes.append(f"Commit {shown}" if commit else f"Version {shown}")
    if f.get("note", "").strip() and not f["note"].startswith("Undated page"):
        notes.append(f["note"])  # the access date below replaces the undated-page note
    if is_misc and f.get("publisher", "").strip():
        # The style's misc prints howpublished but not organization, so a
        # publisher that does not repeat the author goes to howpublished or,
        # when that is taken, to the note.
        out = [(n, v) for n, v in out if n != "publisher"]
        if p2i.decode_latex(f["publisher"]) != author:
            if "howpublished" not in have:
                out.append(("howpublished", f["publisher"]))
                have.add("howpublished")
            else:
                notes.append(f["publisher"])
    if "urldate" in f:
        notes.append(accessed(f["urldate"]))
    note = join_sentences(notes)
    if note:
        # A long commit or revision hash has no break point, so a justified
        # line stretches around it; it may break every eight characters.
        note = re.sub(r"\b[0-9a-f]{24,}\b",
                      lambda m: "\\allowbreak{}".join(m.group(0)[i:i + 8] for i in range(0, len(m.group(0)), 8)), note)
        out.append(("note", protect_note(note)))
    out = [(n, CORPORATE_ABBR.sub(r"{\1}", v) if n == "author" else v) for n, v in out]
    # The style does not quote titles, so a quotation inside one keeps the
    # source's double quotes.
    out = [(n, p2i.protect_title(v, single_quotes=False) if n == "title" else v) for n, v in out]
    width = max(len(n) for n, _ in out)

    def field(n, v):
        head = f"  {n:<{width}} = {{"
        return textwrap.fill(p2i.latex_accents(v), 79, initial_indent=head, subsequent_indent=" " * len(head),
                             break_long_words=False, break_on_hyphens=False) + "}"
    body = ",\n".join(field(n, v) for n, v in out)
    return f"@{'misc' if is_misc else etype}{{{key},\n{body},\n}}"


def elsevier_bib(bib_text):
    """Elsevier copy of the bibliography for elsarticle-harv.bst (see the
    module docstring). The source's section headings are kept."""
    heads = [(m.start(), m.group(1).replace("@", "(at)"))
             for m in re.finditer(r"(?m)^% -{10,}\n% (.+)\n% -{10,}$", bib_text)]
    rule = "% " + "-" * 75
    items = [(off, elsevier_entry(t, k, f)) for t, k, f, off in p2i.parse_bib(bib_text)]
    items += [(off, f"{rule}\n% {h}\n{rule}") for off, h in heads]
    # BibTeX reads an at-sign anywhere as an entry start, even after %, so the
    # header must not contain one.
    head = ("% Elsevier copy of docs/references.bib, generated by scripts/paper_to_elsevier.py\n"
            "% for elsarticle-harv.bst. Software and dataset entries become misc; the\n"
            "% version, the note and the access date go into the note; a misc entry's\n"
            "% publisher becomes howpublished, or joins the note, unless it repeats the\n"
            "% author. A paper with a DOI is cited without its arXiv identifier, and an\n"
            "% arXiv preprint takes its arXiv DOI. A proceedings paper's series, volume\n"
            "% and number join the proceedings title, which the style prints. A corporate\n"
            "% author loses its parenthesised abbreviation. Acronyms and inner capitals in\n"
            "% titles and a note's first letter are braced; other title words follow the\n"
            "% style's sentence case. Accented letters are written as LaTeX accents.\n\n")
    return head + p2i.latex_accents("\n\n".join(text for _, text in sorted(items))) + "\n"


# ----------------------------------------------------------------------- main


def main(argv):
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
    p2i.PANDOC = args.get("PANDOC", "pandoc")
    if shutil.which(p2i.PANDOC) is None and not Path(p2i.PANDOC).is_file():
        raise SystemExit(f"pandoc not found: {p2i.PANDOC}")
    out = (p2i.REPO / args.get("OUT", "paper/elsevier")).resolve()
    bib_text = (p2i.REPO / "docs/references.bib").read_text(encoding="utf-8")
    labels = cite_labels(bib_text)
    FIG_WIDTH.clear()
    FIG_FILE.clear()
    # Build everything before writing, so a failure leaves the folder as it was.
    docs = {"references.bib": elsevier_bib(bib_text), "main.tex": build_main(labels),
            "supplement.tex": build_supplement(labels)}
    out.mkdir(parents=True, exist_ok=True)
    for name, text in docs.items():
        (out / name).write_text(text, encoding="utf-8")
    print("wrote", ", ".join(str((out / n).relative_to(p2i.REPO)) if out.is_relative_to(p2i.REPO) else str(out / n)
                            for n in docs))
    print("figure widths:", FIG_WIDTH)
    print("figure files:", FIG_FILE)
    if "ZIP" in args:
        z = Path(args["ZIP"])
        z = z if z.is_absolute() else p2i.REPO / z
        print("wrote", p2i.write_zip(out, z))


if __name__ == "__main__":
    main(sys.argv[1:])
