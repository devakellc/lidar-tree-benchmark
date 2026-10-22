"""Convert the paper's markdown to the IEEE JSTARS LaTeX version.

Reads paper/manuscript.md, paper/supplement.md, paper/figures/ and
docs/references.bib, and writes main.tex (IEEEtran journal class),
supplement.tex (article class) and an IEEE copy of the bibliography to OUT.
Every markdown citation becomes \\cite, every manuscript cross-reference
becomes \\ref in IEEE numbering (Section IV-B, Table III), tables become
table or table* floats (xltabular in the supplement), and the remaining
Unicode is mapped to LaTeX so both documents compile with pdfLaTeX + BibTeX,
Overleaf's default. The highlights are dropped, the keywords become IEEE Index
Terms, headings take IEEE headline style, and the AI-use statement moves into
the Acknowledgment as IEEE asks.

The IEEE copy of the bibliography is written so that IEEEtran.bst prints every
field the source carries: software entries become misc, version, access date
(urldate), DOI and arXiv identifiers move into note or howpublished, a misc
entry's publisher becomes its howpublished or organization, capitalised words
are brace-protected from the style's case changes, and accented letters are
written as LaTeX accents.

The converter stops with an error instead of guessing when it meets markdown it
does not handle: a citation with a prefix or locator, a reference to a section,
table or figure that does not exist, a caption not followed by its table, an
image without a "Figure N." caption, or a table cell that pandoc would read as
a block.

Arguments are KEY=VALUE pairs:
  OUT=paper/ieee        output directory (relative to the repository root)
  PANDOC=pandoc         pandoc binary (3.x)
  ZIP=path.zip          also write an Overleaf upload zip with figures/

  python3 scripts/paper_to_ieee.py PANDOC=/path/to/pandoc \\
    ZIP=work/paper-ieee/jstars-overleaf.zip
"""
import re
import shutil
import subprocess
import sys
import textwrap
import unicodedata
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PANDOC = "pandoc"
REPO_URL = "https://github.com/devakellc/lidar-tree-benchmark/blob/main/"
NBSP = "\u00a0"
SEP = "ZZSNIPSEPZZ"
# The IEEE (headline-style) form of the manuscript's "Full title:" line. The
# build stops if the two differ other than in case, so a retitled manuscript
# cannot leave a stale title here.
TITLE_IEEE = ("Zero-Shot Deep Tree Detectors on National-Mapping Airborne LiDAR: Small Leads Above "
              "Chance at Native Density and No Guarantee Below the QL2 Floor")

# --------------------------------------------------------------------- helpers


def pandoc(md):
    # pandoc's smart quotes read an apostrophe right after a code span as an
    # opening quote; a typographic apostrophe avoids that.
    md = md.replace("`'", "`\u2019")
    try:
        r = subprocess.run(
            [PANDOC, "-f", "markdown+raw_tex-citations-auto_identifiers-implicit_figures-subscript-superscript"
             "-fancy_lists-example_lists",
             "-t", "latex", "--wrap=preserve"],
            input=md, capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        raise SystemExit(f"pandoc failed with exit status {e.returncode}: {e.stderr.strip()}")
    return r.stdout


BLOCK_MARK = re.compile(r"[-+*#>:~=|]")
BLOCK_TEX = re.compile(r"\\(begin\{(itemize|enumerate|description|quote|quotation|center|longtable)\}"
                       r"|(sub)*section\*?\{|rule\{)")


def pandoc_snippets(snips):
    """Convert many inline markdown snippets in one pandoc call."""
    guarded = []
    for s in snips:
        s = s.strip()
        # A snippet must stay inline text: escape anything pandoc would read
        # as the start of a list, heading, quote, definition, rule or table.
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
    for src, part in zip(snips, parts):
        if BLOCK_TEX.search(part):
            raise SystemExit(f"inline snippet became a block: {src!r} -> {part!r}")
    return parts


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


def headline(title):
    """IEEE headline style: capitalise every word except short articles,
    conjunctions and prepositions; leave words that already hold a capital."""
    words = title.split()

    def cap(part):
        if not part or not part[0].isalpha() or any(c.isupper() for c in part):
            return part
        return part[0].upper() + part[1:]
    out = []
    for i, w in enumerate(words):
        if 0 < i < len(words) - 1 and w.lower() in SMALL_WORDS:
            out.append(w)
        else:
            out.append("-".join(cap(p) for p in w.split("-")))
    return " ".join(out)


# ------------------------------------------------------------ bibliography

ENTRY_START = re.compile(r"@(\w+)\s*\{\s*([^,\s]+)\s*,")
FIELD_NAME = re.compile(r"([A-Za-z][\w-]*)\s*=\s*")


def parse_bib(text):
    """[(type, key, [(field, value), ...], offset)] with brace-balanced
    values, as BibTeX reads them (a value may span lines and hold nested
    braces); offset is where the entry starts in text."""
    entries = []
    i = 0
    while True:
        m = ENTRY_START.search(text, i)
        if not m:
            return entries
        j, fields = m.end(), []
        while True:
            while j < len(text) and text[j] in " \t\r\n,":
                j += 1
            if j >= len(text):
                raise SystemExit(f"unterminated entry {m.group(2)}")
            if text[j] == "}":
                j += 1
                break
            fm = FIELD_NAME.match(text, j)
            if not fm:
                raise SystemExit(f"cannot parse a field of {m.group(2)} at {text[j:j + 40]!r}")
            name, j = fm.group(1).lower(), fm.end()
            if text[j] == "{":
                depth, k = 0, j
                while True:
                    if text[k] == "{":
                        depth += 1
                    elif text[k] == "}":
                        depth -= 1
                        if depth == 0:
                            break
                    k += 1
                value, j = text[j + 1:k], k + 1
            elif text[j] == '"':
                k = text.index('"', j + 1)
                value, j = text[j + 1:k], k + 1
            else:
                vm = re.compile(r"[^,}\s]+").match(text, j)
                value, j = vm.group(0), vm.end()
            fields.append((name, " ".join(value.split())))
        entries.append((m.group(1), m.group(2), fields, m.start()))
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
DECODE_SPECIAL = {"ae": "æ", "AE": "Æ", "o": "ø", "O": "Ø", "ss": "ß", "l": "ł", "L": "Ł", "oe": "œ", "OE": "Œ"}


def decode_latex(s):
    """LaTeX accent macros back to Unicode, then drop protective braces."""
    def accent(m):
        return unicodedata.normalize("NFC", m.group(2) + DECODE_ACCENT[m.group(1)])
    s = re.sub(r"\\(textcommabelow|[`'^\"~=.]|[rcvukH](?=[\s{]))\s*\{?([A-Za-z])\}?", accent, s)
    s = re.sub(r"\\(ae|AE|oe|OE|ss|o|O|l|L)(?![A-Za-z])\s?", lambda m: DECODE_SPECIAL[m.group(1)], s)
    return s.replace("{", "").replace("}", "")


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
            elif a.startswith("{") and a.endswith("}") and split_top(a[1:-1], ",") == [a[1:-1]]:
                fam.append(decode_latex(a[1:-1]))  # corporate author
            elif len(split_top(a, ",")) > 1:
                fam.append(decode_latex(split_top(a, ",")[0]))
            else:
                # 'First von Last': the family name starts at the first
                # lower-case word after the first, as BibTeX reads it.
                words = split_top(a, " ")
                start = next((i for i in range(1, len(words) - 1) if words[i][:1].islower()), len(words) - 1)
                fam.append(decode_latex(" ".join(words[start:])))
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
    can recognise are braced in the source bibliography. A quotation inside
    a title takes single quotes, since IEEEtran adds the outer double ones."""
    title = re.sub(r"``(.*?)''", r"`\1'", title)
    out, depth, lead = [], 0, True
    for tok in re.findall(r"\s+|\S+", title):
        if tok.isspace():
            out.append(tok)
            continue
        if depth == 0 and not re.search(r"[{}\\]", tok):
            parts = re.split(r"(-)", tok)
            tok = "".join(protect_part(x, lead and i == 0) for i, x in enumerate(parts))
        depth += tok.count("{") - tok.count("}")
        lead = tok.endswith(":")
        out.append(tok)
    return "".join(out)


def protect_note(note):
    """Brace a leading acronym or single capital ('R package', 'MIT licence')
    that IEEEtran.bst would lower-case mid-sentence."""
    return re.sub(r"^([A-Z][A-Z0-9]*)\b", r"{\1}", note)


def ieee_entry(etype, key, fields):
    f = dict(fields)
    is_misc = etype.lower() in ("misc", "software", "online", "dataset")
    out = [(n, v) for n, v in fields if n not in IEEE_DROPS | {"note"}]
    have = {n for n, _ in out}
    author = decode_latex(f.get("author", ""))
    if is_misc and "publisher" in f:
        out = [(n, v) for n, v in out if n != "publisher"]
        if decode_latex(f["publisher"]) != author:
            out.append(("organization" if "howpublished" in have else "howpublished", f["publisher"]))
            have.add("howpublished")
    eprint_shown = False
    if is_misc and "eprint" in f and "howpublished" not in have:
        out.append(("howpublished", f"arXiv:{f['eprint']}"))
        eprint_shown = True
    notes = []
    if "version" in f:
        # Skip the version only when the note already states it.
        v = f["version"]
        commit = v.lower().startswith("commit ")
        shown = v[len("commit "):] if commit else v
        stated = re.escape(shown) if commit else rf"\bversion\s+{re.escape(shown)}(?![\w.])"
        if not re.search(stated, f.get("note", ""), flags=re.I):
            notes.append(f"Commit {shown}" if commit else f"Version {shown}")
    if "doi" in f:
        notes.append("doi: \\url{" + f["doi"] + "}")
    if "note" in f and not f["note"].startswith("Undated page"):
        notes.append(f["note"])  # the access date below replaces the undated-page note
    if "eprint" in f and not eprint_shown and "doi" not in f:
        notes.append(f"arXiv:{f['eprint']}")
    if "urldate" in f:
        notes.append(accessed(f["urldate"]))
    if notes:
        out.append(("note", protect_note(". ".join(n.rstrip(".") for n in notes))))
    out = [(n, protect_title(v) if n == "title" else v) for n, v in out]
    width = max(len(n) for n, _ in out)

    def field(n, v):
        head = f"  {n:<{width}} = {{"
        return textwrap.fill(latex_accents(v), 79, initial_indent=head, subsequent_indent=" " * len(head),
                             break_long_words=False, break_on_hyphens=False) + "}"
    body = ",\n".join(field(n, v) for n, v in out)
    return f"@{'misc' if is_misc else etype}{{{key},\n{body},\n}}"


def ieee_bib(bib_text):
    """IEEE copy of the bibliography in which IEEEtran.bst prints every field
    of the source (see the module docstring)."""
    # The source's section headings ('% ---' rulers around a title line) are
    # kept, so the copy stays navigable when it is edited by hand.
    heads = [(m.start(), m.group(1).replace("@", "(at)"))
             for m in re.finditer(r"(?m)^% -{10,}\n% (.+)\n% -{10,}$", bib_text)]
    rule = "% " + "-" * 75
    items = [(off, ieee_entry(t, k, f)) for t, k, f, off in parse_bib(bib_text)]
    items += [(off, f"{rule}\n% {h}\n{rule}") for off, h in heads]
    entries = [text for _, text in sorted(items)]
    # BibTeX reads an at-sign anywhere as an entry start, even after %, so the
    # header must not contain one.
    head = ("% IEEE copy of docs/references.bib, generated by scripts/paper_to_ieee.py\n"
            "% for IEEEtran.bst: software entries become misc; version, access date,\n"
            "% DOI and arXiv identifiers move into note or howpublished; a misc\n"
            "% entry's publisher becomes howpublished or organization; capitals are\n"
            "% brace-protected; accented letters are written as LaTeX accents.\n\n")
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
FIG_ITEM = r"\d+[a-z]?"


def convert_refs(md, mode, known=None):
    """Section/Table/Figure references. mode 'main' uses \\ref; 'supp' writes
    IEEE numbers for the manuscript's items and keeps S-items as text. known,
    when given, holds the manuscript's section, table and figure numbers;
    a reference to anything else stops the build."""
    def check(kind, item):
        if known is not None and item not in known[kind]:
            raise SystemExit(f"reference to {kind} {item}, which the manuscript does not have")

    def sec_one(it):
        if it.startswith("S"):
            return it
        check("sec", it)
        return f"\\ref{{sec:{it}}}" if mode == "main" else ieee_section_number(it)

    def tab_one(it):
        if it.startswith("S"):
            return it
        if not it.isdigit():
            raise SystemExit(f"Table {it}: the manuscript's tables have no lettered parts")
        check("tab", it)
        return f"\\ref{{tab:{it}}}" if mode == "main" else roman(int(it))

    def fig_one(it):
        mm = re.fullmatch(r"(\d+)([a-z]?)", it)
        check("fig", mm.group(1))
        return (f"\\ref{{fig:{mm.group(1)}}}" if mode == "main" else mm.group(1)) + mm.group(2)

    def rewrite(word_re, item_re, one, text):
        pattern = rf"\b({word_re})\s+({item_re}(?:{SEPS}{item_re}{CONT_END})*)\b"

        def repl(m):
            parts = re.split(f"({SEPS})", m.group(2))
            return m.group(1) + NBSP + "".join(one(p) if re.fullmatch(item_re, p) else p for p in parts)
        return re.sub(pattern, repl, text)
    md = rewrite(r"Sections?", SEC_ITEM, sec_one, md)
    md = rewrite(r"Tables?", TAB_ITEM, tab_one, md)
    return rewrite(r"Figs?\.|Figures?", FIG_ITEM, fig_one, md)


def unicode_to_latex(tex):
    tex = tex.replace("−", "$-$").replace("²", "\\textsuperscript{2}").replace("—", "---")
    tex = tex.replace("–", "--").replace("×", "$\\times$").replace("τ", "$\\tau$")
    tex = tex.replace("≤", "$\\leq$").replace("≥", "$\\geq$").replace("·", "$\\cdot$")
    tex = tex.replace(NBSP, "~")
    # Any accented letter left (e.g. in a narrative author name) becomes a
    # LaTeX accent; latex_accents stops on anything it cannot map.
    return latex_accents(tex)


def unescape_brackets(tex):
    """pandoc writes {[} and {]}; keep the escape only where a bare [ could be
    read as an optional argument (after \\item, \\\\, a control word or at a
    cell start)."""
    def opener(m):
        prev = tex_ref[0][:m.start()].rstrip()
        if not prev or prev.endswith(("\\\\", "\\item", "&")) or re.search(r"\\[A-Za-z]+\*?$", prev):
            return m.group(0)
        return "["
    tex_ref = [tex]
    tex = re.sub(r"\{\[\}", opener, tex)
    return tex.replace("{]}", "]")


def links(md, mode):
    """Repository-relative links point to GitHub in the supplement and keep
    their text elsewhere; web links become \\href in the supplement (which
    loads hyperref) and 'text (url)' in the manuscript (which does not)."""
    if mode == "supp":
        md = re.sub(r"(?<!!)\]\(\.\./([^)]+)\)", lambda m: "](" + REPO_URL + m.group(1) + ")", md)
    md = re.sub(r"(?<!!)\[([^\]]+)\]\((?!https?://)[^)]+\)", r"\1", md)
    if mode == "main":
        md = re.sub(r"(?<!!)\[([^\]]+)\]\((https?://[^)\s]+)\)", r"\1 (<\2>)", md)
    return md


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
        lines += [f"\\begin{{{float_env}}}[!t]", f"\\caption{{{caption_tex}}}", f"\\label{{tab:{num}}}",
                  "\\centering", size, "\\setlength{\\tabcolsep}{3pt}",
                  "\\renewcommand{\\arraystretch}{1.15}"]
        env = "tabularx" if has_x else "tabular"
        width = f"{{{line_width}}}" if has_x else ""
        lines.append(f"\\begin{{{env}}}{width}{{{''.join(spec)}}}")
        lines += ["\\hline", head_row, "\\hline"]
        lines += [" & ".join(r) + " \\\\" for r in rows_tex]
        lines += ["\\hline", f"\\end{{{env}}}", f"\\end{{{float_env}}}"]
    else:
        if not any(s in "LRC" for s in spec):
            spec[-1] = {"l": "L", "r": "R", "c": "C"}[spec[-1]]
        # The caption is the first head row, so a page break cannot separate
        # it from its table.
        caption_row = (f"\\multicolumn{{{ncol}}}{{@{{}}p{{\\textwidth}}@{{}}}}"
                       f"{{\\normalsize\\textbf{{Table {num}.}} {caption_tex}}} \\\\[4pt]")
        lines += ["{" + size, "\\setlength{\\tabcolsep}{3pt}", "\\renewcommand{\\arraystretch}{1.15}",
                  f"\\begin{{xltabular}}{{\\textwidth}}{{{''.join(spec)}}}",
                  caption_row, "\\hline", head_row, "\\hline", "\\endfirsthead",
                  "\\hline", head_row, "\\hline", "\\endhead",
                  "\\hline", "\\endfoot"]
        lines += [" & ".join(r) + " \\\\" for r in rows_tex]
        lines += ["\\end{xltabular}", "}"]
    return "\n".join(lines)


FIG_WIDTH = {}


def figure_tex(num, path, caption_tex):
    from struct import unpack
    b = (REPO / "paper" / path).read_bytes()
    w, h = unpack(">II", b[16:24])
    aspect = w / h
    width = "\\textwidth" if aspect >= 1.6 else ("0.85\\textwidth" if aspect >= 1.3 else "0.72\\textwidth")
    FIG_WIDTH[num] = width
    return "\n".join(["\\begin{figure*}[!t]", "\\centering", f"\\includegraphics[width={width}]{{{path}}}",
                      f"\\caption{{{caption_tex}}}", f"\\label{{fig:{num}}}", "\\end{figure*}"])


# ---------------------------------------------------------------- documents


def split_sections(md):
    """[(heading line or '', text)] for '## ' level-2 sections."""
    parts = re.split(r"(?m)^(## .*)$", md)
    out = [("", parts[0])]
    for i in range(1, len(parts), 2):
        out.append((parts[i].strip(), parts[i + 1]))
    return out


def manuscript_numbers(md):
    """The manuscript's section, table and figure numbers."""
    return {"sec": set(re.findall(r"(?m)^#{2,3} (\d+(?:\.\d+)?)\.?\s", md)),
            "tab": set(re.findall(r"(?m)^\*\*Table (\d+)\.\*\*", md)),
            "fig": set(re.findall(r"(?m)^\*\*Figure (\d+)\.\*\*", md))}


TABLE_BLOCK = re.compile(r"\*\*Table (S?\d+[a-z]?)\.\*\*[ \t]*((?:(?!\n[ \t]*\n).)*?)\n[ \t]*\n"
                         r"((?:\|[^\n]*(?:\n|\Z))+)", re.S)
FIGURE_BLOCK = re.compile(r"!\[Figure (\d+)\.\]\(([^)]+)\)[ \t]*\n[ \t]*\n\*\*Figure \1\.\*\*[ \t]*"
                          r"((?:(?!\n[ \t]*\n).)*)", re.S)


def body_to_tex(md, mode, authors, known):
    """Convert a body of markdown (headings, paragraphs, tables, figures)."""
    md = convert_citations(md, authors)
    blocks = {}

    def take_figure(m):
        num, path, cap = m.group(1), m.group(2), m.group(3)
        tok = f"ZZFIG{num}ZZ"
        blocks[tok] = ("figure", num, path, cap)
        return f"\n\n{tok}\n\n"
    md = FIGURE_BLOCK.sub(take_figure, md)
    if "![" in md or re.search(r"(?m)^\*\*Figure \d+\.\*\*", md):
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

    md = convert_refs(md, mode, known)

    def heading(m):
        level, text = len(m.group(1)), m.group(2).strip()
        if mode == "main":
            mm = re.match(r"(\d+(?:\.\d+)?)\.?\s+(.*)", text)
            if not mm:
                raise SystemExit(f"unnumbered heading in body: {text}")
            num, title = mm.group(1), pandoc_snippets([headline(mm.group(2))])[0]
            cmd = "section" if level == 2 else "subsection"
            return f"\n\\{cmd}{{{title}}}\\label{{sec:{num}}}\n"
        cmd = "section*" if level == 2 else "subsection*"
        return f"\n\\{cmd}{{{pandoc_snippets([headline(text)])[0]}}}\n"
    md = re.sub(r"(?m)^(#{2,3}) (.*)$", heading, md)
    md = links(md, mode)

    tex = pandoc(md)

    # Captions and table cells are converted after the text so their refs and
    # citations go through the same transforms.
    for tok, spec in blocks.items():
        if spec[0] == "figure":
            _, num, path, cap = spec
            cap_tex = pandoc_snippets([convert_refs(cap, mode, known)])[0]
            repl = figure_tex(num, path, cap_tex)
        else:
            _, num, cap, table = spec
            cap_tex = pandoc_snippets([convert_refs(cap, mode, known)])[0]
            header, aligns, body = parse_pipe_table(table)
            header = [convert_refs(c, mode, known) for c in header]
            body = [[convert_refs(c, mode, known) for c in r] for r in body]
            repl = table_tex(num, cap_tex, header, aligns, body, mode)
        if tex.count(tok) != 1:
            raise SystemExit(f"placeholder {tok} found {tex.count(tok)} times")
        tex = tex.replace(tok, repl)
    return unescape_brackets(unicode_to_latex(tex))


def snippet(md, mode, authors, known):
    md = links(convert_refs(convert_citations(md, authors), mode, known), mode)
    return unescape_brackets(unicode_to_latex(pandoc_snippets([md])[0]))


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
    known = manuscript_numbers(md)
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
    if re.search(r"highlight", body_md, flags=re.I):
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
\\usepackage{{cite}}
\\usepackage{{amsmath}}
\\usepackage{{graphicx}}
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
% TODO: adjust the sentence below to name those sections.
{ai_tex}

% Elsevier-only sections of the markdown draft, kept for reference. IEEE asks
% for competing interests in the ScholarOne submission form and does not print
% CRediT statements.
% CRediT authorship contribution statement: {" ".join(credit_md.split())}
% Declaration of competing interest: {" ".join(competing_md.split())}
% Funding: {" ".join(funding_md.split())}

\\bibliographystyle{{IEEEtran}}
\\bibliography{{references}}

% TODO (final version): author biographies, e.g.
% \\begin{{IEEEbiographynophoto}}{{{author}}}
% Biography text here.
% \\end{{IEEEbiographynophoto}}

\\end{{document}}
"""


def build_supplement(authors):
    manuscript = (REPO / "paper/manuscript.md").read_text(encoding="utf-8")
    known = manuscript_numbers(manuscript)
    _, author = front_matter(manuscript)
    md = (REPO / "paper/supplement.md").read_text(encoding="utf-8")
    sections = split_sections(md)
    intro = re.sub(r"(?m)^# .*$", "", sections[0][1]).strip()
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
\\usepackage{{cite}}
\\usepackage{{array}}
\\usepackage{{xltabular}}
\\usepackage{{url}}
\\usepackage[hidelinks]{{hyperref}}
\\providecommand{{\\tightlist}}{{\\setlength{{\\itemsep}}{{0pt}}\\setlength{{\\parskip}}{{0pt}}}}
\\newcolumntype{{L}}{{>{{\\raggedright\\arraybackslash}}X}}
\\newcolumntype{{R}}{{>{{\\raggedleft\\arraybackslash}}X}}
\\newcolumntype{{C}}{{>{{\\centering\\arraybackslash}}X}}
\\setlength{{\\parindent}}{{0pt}}
\\setlength{{\\parskip}}{{4pt}}
\\setlength{{\\emergencystretch}}{{3em}}

\\title{{Supplementary Material for ``{title}''}}
\\author{{{author}}}
\\date{{}}

\\begin{{document}}
\\maketitle

{intro_tex}

{body_tex}

\\bibliographystyle{{IEEEtran}}
\\bibliography{{references}}

\\end{{document}}
"""


def write_zip(out, zip_path):
    """Overleaf upload: the three sources at the root and figures/."""
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for name in ("main.tex", "supplement.tex", "references.bib"):
            z.write(out / name, name)
        for p in sorted((REPO / "paper/figures").glob("figure_*.png")):
            z.write(p, f"figures/{p.name}")
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
    # Build everything before writing, so a failure leaves the folder as it was.
    docs = {"references.bib": ieee_bib(bib_text), "main.tex": build_main(authors),
            "supplement.tex": build_supplement(authors)}
    out.mkdir(parents=True, exist_ok=True)
    for name, text in docs.items():
        (out / name).write_text(text, encoding="utf-8")
    print("wrote", ", ".join(str((out / n).relative_to(REPO)) if out.is_relative_to(REPO) else str(out / n)
                            for n in docs))
    print("figure widths:", FIG_WIDTH)
    if "ZIP" in args:
        z = Path(args["ZIP"])
        z = z if z.is_absolute() else REPO / z
        print("wrote", write_zip(out, z))


if __name__ == "__main__":
    main(sys.argv[1:])
