"""Convert the paper's markdown to the IEEE JSTARS LaTeX version.

Reads paper/manuscript.md, paper/supplement.md, paper/figures/ and
docs/references.bib, and writes main.tex (IEEEtran journal class),
supplement.tex (article class) and an IEEE copy of the bibliography to OUT.
Every markdown citation becomes \\cite, every manuscript cross-reference
becomes \\ref in IEEE numbering (Section IV-B, Table III), tables become
table or table* floats (xltabular in the supplement), and the remaining
Unicode is mapped to LaTeX so both documents compile with pdfLaTeX + BibTeX,
Overleaf's default. The highlights are dropped, the keywords become IEEE Index
Terms, and the AI-use statement moves into the Acknowledgment as IEEE asks.

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
import unicodedata
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PANDOC = "pandoc"
REPO_URL = "https://github.com/devakellc/lidar-tree-benchmark/blob/main/"
NBSP = "\u00a0"
SEP = "ZZSNIPSEPZZ"

# --------------------------------------------------------------------- helpers


def pandoc(md):
    r = subprocess.run(
        [PANDOC, "-f", "markdown+raw_tex-citations-auto_identifiers-implicit_figures-subscript-superscript"
         "-fancy_lists-example_lists",
         "-t", "latex", "--wrap=preserve"],
        input=md, capture_output=True, text=True, check=True)
    return r.stdout


def pandoc_snippets(snips):
    """Convert many inline markdown snippets in one pandoc call."""
    guarded = []
    for s in snips:
        s = s.strip()
        # A cell that starts like a list item or heading must stay inline text.
        s = re.sub(r"^(\d+)\.(\s)", r"\1\\.\2", s)
        s = re.sub(r"^([-+*#])(\s)", r"\\\1\2", s)
        guarded.append(s)
    out = pandoc(f"\n\n{SEP}\n\n".join(guarded) + "\n")
    parts = [p.strip() for p in out.split(SEP)]
    if len(parts) != len(snips):
        raise SystemExit(f"snippet split mismatch: {len(parts)} vs {len(snips)}")
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


# ------------------------------------------------------------ bibliography


def bib_authors(bib_text):
    """key -> 'Surname', 'A and B' or 'Surname et al.' for narrative citations."""
    out = {}
    for key, body in re.findall(r"^@\w+\{([a-z0-9]+),(.*?)^\}", bib_text, flags=re.M | re.S):
        m = re.search(r"^\s*author\s*=\s*\{(.*?)\},?\s*$", body, flags=re.M | re.S)
        if not m:
            continue
        raw = " ".join(m.group(1).split())
        if raw.startswith("{") and raw.endswith("}"):
            out[key] = raw.strip("{}")
            continue
        names = [a.strip() for a in re.split(r"\s+and\s+", raw)]
        fam = []
        for a in names:
            if a == "others":
                fam.append("others")
                continue
            f = a.split(",")[0] if "," in a else a.split()[-1]
            fam.append(f.replace("{", "").replace("}", "").strip())
        if len(fam) == 1:
            out[key] = fam[0]
        elif len(fam) == 2 and fam[1] != "others":
            out[key] = f"{fam[0]} and {fam[1]}"
        else:
            out[key] = f"{fam[0]} et al."
    return out


ACCENT = {"\u0301": "'", "\u0300": "`", "\u0302": "^", "\u0308": '"', "\u0303": "~", "\u030a": "r",
          "\u0327": "c", "\u0326": "c", "\u030c": "v", "\u0306": "u", "\u0328": "k", "\u030b": "H",
          "\u0304": "=", "\u0307": "."}
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


def ieee_bib(bib_text):
    """Copy of the bibliography that IEEEtran.bst renders fully."""
    def fix(m):
        etype, key, body = m.group(1), m.group(2), m.group(3)
        fields = dict((f.lower(), v) for f, v in re.findall(r"^\s*([A-Za-z]+)\s*=\s*\{(.*?)\},?\s*$",
                                                         body, flags=re.M | re.S))
        etype_out = "misc" if etype.lower() in ("software", "online", "dataset") else etype
        extra = []
        if "eprint" in fields and etype.lower() == "misc" and "howpublished" not in fields:
            extra.append(("howpublished", f"arXiv:{fields['eprint'].strip()}"))
        if "doi" in fields:
            doi_note = "doi: \\url{" + fields["doi"].strip() + "}"
            note = fields.get("note")
            body = re.sub(r"^\s*note\s*=\s*\{.*?\},?\s*\n", "", body, flags=re.M | re.S)
            extra.append(("note", doi_note + (". " + note if note else "")))
        lines = body.rstrip().rstrip(",")
        for f, v in extra:
            lines += f",\n  {f} = {{{v}}}"
        return f"@{etype_out}{{{key},{lines}\n}}"
    entries = re.sub(r"^@(\w+)\{([a-z0-9]+),(.*?)^\}", fix, bib_text, flags=re.M | re.S)
    # BibTeX reads an at-sign anywhere as an entry start, even after %, so the
    # header must not contain one.
    head = ("% IEEE copy of docs/references.bib, generated for IEEEtran.bst: software\n"
            "% entries become misc, arXiv preprints carry howpublished = arXiv:ID, DOIs\n"
            "% move into note (IEEEtran.bst ignores the doi field) and accented\n"
            "% letters are written as LaTeX accents for pdfLaTeX + BibTeX.\n\n")
    body = re.sub(r"\A(%.*\n)+", "", entries)
    return head + latex_accents(body)


# ------------------------------------------------------- markdown transforms


def convert_citations(md, authors):
    def group(m):
        keys = re.findall(r"@([a-z0-9]+)", m.group(2))
        lead = NBSP if m.group(1) else ""
        return lead + "\\cite{" + ",".join(keys) + "}"
    md = re.sub(r"(\s?)(\[@[a-z0-9]+(?:;\s*@[a-z0-9]+)*\])", group, md)

    def narrative(m):
        key = m.group(1)
        if key not in authors:
            raise SystemExit(f"narrative citation of unknown key {key}")
        return f"{authors[key]}{NBSP}\\cite{{{key}}}"
    return re.sub(r"(?<![\w@\\{])@([a-z0-9]+)", narrative, md)


ITEM = r"S?\d+(?:\.\d+)?"
LIST_SEP = r"(?:,\s+|\s+and\s+|\s+to\s+|\s*–\s*)"


def convert_refs(md, mode):
    """Section/Table/Figure references. mode 'main' uses \\ref; 'supp' writes
    IEEE numbers for the manuscript's items and keeps S-items as text."""
    def sec(m):
        word, items = m.group(1), m.group(2)
        def one(it):
            if it.startswith("S"):
                return it
            return f"\\ref{{sec:{it}}}" if mode == "main" else ieee_section_number(it)
        parts = re.split(f"({LIST_SEP})", items)
        return word + NBSP + "".join(one(p) if re.fullmatch(ITEM, p) else p for p in parts)
    md = re.sub(rf"\b(Sections?)\s+({ITEM}(?:{LIST_SEP}{ITEM})*)\b", sec, md)

    def tab(m):
        word, items = m.group(1), m.group(2)
        def one(it):
            if it.startswith("S"):
                return it
            return f"\\ref{{tab:{it}}}" if mode == "main" else roman(int(it))
        parts = re.split(r"(,\s+|\s+and\s+|\s+to\s+)", items)
        return word + NBSP + "".join(one(p) if re.fullmatch(r"S?\d+[a-z]?", p) else p for p in parts)
    md = re.sub(r"\b(Tables?)\s+(S?\d+[a-z]?(?:(?:,\s+|\s+and\s+|\s+to\s+)S?\d+[a-z]?)*)\b", tab, md)

    def fig(m):
        word, items = m.group(1), m.group(2)
        def one(it):
            mm = re.fullmatch(r"(\d+)([a-z]?)", it)
            if not mm:
                return it
            return (f"\\ref{{fig:{mm.group(1)}}}" if mode == "main" else mm.group(1)) + mm.group(2)
        parts = re.split(r"(,\s+|\s+and\s+)", items)
        return word + NBSP + "".join(one(p) for p in parts)
    return re.sub(r"\b(Figs?\.|Figures?)\s+(\d+[a-z]?(?:(?:,\s+|\s+and\s+)\d+[a-z]?)*)\b", fig, md)


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
    read as an optional argument (after \\item, \\\\ or at a cell start)."""
    def opener(m):
        prev = tex_ref[0][:m.start()].rstrip()
        if not prev or prev.endswith(("\\\\", "\\item", "&")) or re.search(r"\\[A-Za-z]+\*?$", prev):
            return m.group(0)
        return "["
    tex_ref = [tex]
    tex = re.sub(r"\{\[\}", opener, tex)
    return tex.replace("{]}", "]")


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
        lines += ["\\hline", " & ".join(head_tex) + " \\\\", "\\hline"]
        lines += [" & ".join(r) + " \\\\" for r in rows_tex]
        lines += ["\\hline", f"\\end{{{env}}}", f"\\end{{{float_env}}}"]
    else:
        if not any(s in "LRC" for s in spec):
            spec[-1] = {"l": "L", "r": "R", "c": "C"}[spec[-1]]
        lines += [f"\\noindent\\textbf{{Table {num}.}} {caption_tex}", "",
                  "{" + size, "\\setlength{\\tabcolsep}{3pt}", "\\renewcommand{\\arraystretch}{1.15}",
                  f"\\begin{{xltabular}}{{\\textwidth}}{{{''.join(spec)}}}",
                  "\\hline", " & ".join(head_tex) + " \\\\", "\\hline", "\\endhead",
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


def body_to_tex(md, mode, authors, labels=True):
    """Convert a body of markdown (headings, paragraphs, tables, figures)."""
    md = convert_citations(md, authors)
    blocks = {}

    def take_figure(m):
        num, path, cap = m.group(1), m.group(2), m.group(3)
        tok = f"ZZFIG{num}ZZ"
        blocks[tok] = ("figure", num, path, cap)
        return f"\n\n{tok}\n\n"
    md = re.sub(r"!\[Figure (\d+)\.\]\(([^)]+)\)\s*\n\s*\n\*\*Figure \1\.\*\*\s*(.*?)(?=\n\s*\n|\Z)",
                take_figure, md, flags=re.S)

    def take_table(m):
        num, cap, table = m.group(1), m.group(2), m.group(3)
        tok = f"ZZTAB{num.replace('.', '')}ZZ"
        blocks[tok] = ("table", num, cap, table)
        return f"\n\n{tok}\n\n"
    md = re.sub(r"\*\*Table (S?\d+[a-z]?)\.\*\*\s*(.*?)\n\s*\n((?:\|[^\n]*\n?)+)", take_table, md, flags=re.S)

    md = convert_refs(md, mode)

    def heading(m):
        level, text = len(m.group(1)), m.group(2).strip()
        if mode == "main":
            mm = re.match(r"(\d+(?:\.\d+)?)\.?\s+(.*)", text)
            if not mm:
                raise SystemExit(f"unnumbered heading in body: {text}")
            num, title = mm.group(1), mm.group(2)
            cmd = "section" if level == 2 else "subsection"
            return f"\n\\{cmd}{{{title}}}\\label{{sec:{num}}}\n"
        cmd = "section*" if level == 2 else "subsection*"
        return f"\n\\{cmd}{{{text}}}\n"
    md = re.sub(r"(?m)^(#{2,3}) (.*)$", heading, md)

    if mode == "supp":
        md = re.sub(r"\]\(\.\./([^)]+)\)", lambda m: "](" + REPO_URL + m.group(1) + ")", md)
    # Any other repository-relative link would be dead in a PDF: keep its text.
    md = re.sub(r"\[([^\]]+)\]\((?!https?://)[^)]+\)", r"\1", md)

    tex = pandoc(md)

    # Captions and table cells are converted after the text so their refs and
    # citations go through the same transforms.
    for tok, spec in blocks.items():
        if spec[0] == "figure":
            _, num, path, cap = spec
            cap_tex = pandoc_snippets([convert_refs(cap, mode)])[0]
            repl = figure_tex(num, path, cap_tex)
        else:
            _, num, cap, table = spec
            cap_tex = pandoc_snippets([convert_refs(cap, mode)])[0]
            header, aligns, body = parse_pipe_table(table)
            header = [convert_refs(c, mode) for c in header]
            body = [[convert_refs(c, mode) for c in r] for r in body]
            repl = table_tex(num, cap_tex, header, aligns, body, mode)
        if tex.count(tok) != 1:
            raise SystemExit(f"placeholder {tok} found {tex.count(tok)} times")
        tex = tex.replace(tok, repl)
    return unescape_brackets(unicode_to_latex(tex))


def snippet(md, mode, authors):
    md = re.sub(r"\[([^\]]+)\]\((?!https?://)[^)]+\)", r"\1", md)
    return unescape_brackets(unicode_to_latex(pandoc_snippets([convert_refs(convert_citations(md, authors), mode)])[0]))


def build_main(authors):
    md = (REPO / "paper/manuscript.md").read_text(encoding="utf-8")
    sections = split_sections(md)
    sec = {h: t for h, t in sections}
    front = sections[0][1]
    full_title = re.search(r"^Full title:\s*(.*?)\n\n", front, flags=re.S | re.M).group(1)
    abstract_md = sec["## Abstract"].split("**Keywords:**")[0].strip()
    keywords = sec["## Abstract"].split("**Keywords:**")[1].strip()
    keywords = [k.strip().rstrip(".") for k in " ".join(keywords.split()).split(";") if k.strip()]
    index_terms = sorted(keywords, key=str.lower)
    index_terms = [index_terms[0][0].upper() + index_terms[0][1:]] + index_terms[1:]

    heads = [h for h, _ in sections]
    start = heads.index("## 1. Introduction")
    end = next(i for i, h in enumerate(heads) if h.startswith("## CRediT"))
    body_md = "\n".join(h + "\n" + t for h, t in sections[start:end])
    body_tex = body_to_tex(body_md, "main", authors)
    # IEEE journal drop cap on the first word of the Introduction.
    body_tex = re.sub(r"(\\label\{sec:1\}\n+)(\w)(\w*)", r"\1\\IEEEPARstart{\2}{\3}", body_tex, count=1)

    def back(name):
        h = next(x for x in heads if x.startswith(name))
        return sec[h].strip()
    data_tex = snippet(back("## Data and code availability"), "main", authors)
    ack_tex = snippet(back("## Acknowledgements"), "main", authors)
    ai_tex = snippet(back("## Declaration of generative AI"), "main", authors)
    abstract_tex = snippet(abstract_md, "main", authors)
    credit_md = back("## CRediT")
    competing_md = back("## Declaration of competing interest")
    funding_md = back("## Funding")

    title_ieee = ("Zero-Shot Deep Tree Detectors on National-Mapping Airborne LiDAR: Small Leads Above "
                  "Chance at Native Density and No Guarantee Below the QL2 Floor")
    tex = f"""% JSTARS submission version of the benchmark paper, generated from
% paper/manuscript.md by scripts/paper_to_ieee.py for editing on Overleaf.
% Compile with pdfLaTeX and BibTeX (Overleaf's default). Search for TODO.
% Original title (sentence case): {latex_accents(" ".join(full_title.split()))}
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

\\title{{{title_ieee}}}

% TODO: complete the author block. IEEE puts the funding statement in the first
% footnote and each author's affiliation and e-mail in the next ones.
\\author{{Alex~Grigoryev%
\\thanks{{Manuscript received Month DD, 2026. % TODO: leave for the journal or fill in
This work was supported by TODO. % TODO: funding statement, or remove this sentence
}}%
\\thanks{{A.~Grigoryev is with TODO affiliation (e-mail: TODO). % TODO
}}}}

\\markboth{{IEEE Journal of Selected Topics in Applied Earth Observations and Remote Sensing}}%
{{Grigoryev: Zero-Shot Deep Tree Detectors on National-Mapping Airborne LiDAR}}

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
% \\begin{{IEEEbiographynophoto}}{{Alex Grigoryev}}
% Biography text here.
% \\end{{IEEEbiographynophoto}}

\\end{{document}}
"""
    return tex


def build_supplement(authors):
    md = (REPO / "paper/supplement.md").read_text(encoding="utf-8")
    sections = split_sections(md)
    intro = re.sub(r"(?m)^# .*$", "", sections[0][1]).strip()
    body_md = "\n".join(h + "\n" + t for h, t in sections[1:])
    body_tex = body_to_tex(body_md, "supp", authors)
    intro_tex = snippet(intro, "supp", authors) if intro else ""
    return f"""% Supplementary material for the JSTARS submission, converted from
% paper/supplement.md. Upload its PDF as supplementary material. References to
% the manuscript use the IEEE numbering of main.tex (Section IV-A, Table III).
\\documentclass[10pt]{{article}}
\\usepackage[T1]{{fontenc}}
\\usepackage{{mathptmx}}
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

\\title{{Supplementary Material for ``Zero-Shot Deep Tree Detectors on National-Mapping Airborne
LiDAR: Small Leads Above Chance at Native Density and No Guarantee Below the QL2 Floor''}}
\\author{{Alex Grigoryev}}
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
    args = dict(a.split("=", 1) for a in argv if "=" in a)
    unknown = set(args) - {"OUT", "PANDOC", "ZIP"}
    if unknown:
        raise SystemExit(f"unknown arguments: {sorted(unknown)}")
    PANDOC = args.get("PANDOC", "pandoc")
    if shutil.which(PANDOC) is None and not Path(PANDOC).is_file():
        raise SystemExit(f"pandoc not found: {PANDOC}")
    out = (REPO / args.get("OUT", "paper/ieee")).resolve()
    bib_text = (REPO / "docs/references.bib").read_text(encoding="utf-8")
    authors = bib_authors(bib_text)
    out.mkdir(parents=True, exist_ok=True)
    (out / "references.bib").write_text(ieee_bib(bib_text), encoding="utf-8")
    (out / "main.tex").write_text(build_main(authors), encoding="utf-8")
    (out / "supplement.tex").write_text(build_supplement(authors), encoding="utf-8")
    print("wrote", ", ".join(str((out / n).relative_to(REPO)) if out.is_relative_to(REPO) else str(out / n)
                            for n in ("main.tex", "supplement.tex", "references.bib")))
    print("figure widths:", FIG_WIDTH)
    if "ZIP" in args:
        z = Path(args["ZIP"])
        z = z if z.is_absolute() else REPO / z
        print("wrote", write_zip(out, z))


if __name__ == "__main__":
    main(sys.argv[1:])
