"""Split the compiled business_questions.sql into one file per query (Q01.sql, Q02a.sql ...).
Usage (from the dbt project folder ...\\ENSO):
    dbt compile --select business_questions
    python split_queries.py                      # reads target/compiled/ENSO/analyses/business_questions.sql
    python split_queries.py <compiled.sql> <out_dir>
Output: <out_dir>/Qxx.sql  (default: target/compiled/ENSO/analyses/queries/)
"""
import re, sys
from pathlib import Path

src = Path(sys.argv[1] if len(sys.argv) > 1 else "target/compiled/ENSO/analyses/business_questions.sql")
out = Path(sys.argv[2] if len(sys.argv) > 2 else src.parent / "queries")
out.mkdir(parents=True, exist_ok=True)
text = src.read_text(encoding="utf-8-sig")

tag_re = re.compile(r"^--\s*(Q\d+[a-z]?)\b", re.I)
label, cur, blocks, used = "Q00", [], [], {}

def has_sql(buf):
    return re.search(r"\b(select|with)\b", re.sub(r"--.*", "", "\n".join(buf)), re.I) is not None

for line in text.splitlines():
    m = tag_re.match(line)
    if m and not has_sql(cur):
        label = m.group(1).upper()[:-1] + m.group(1)[-1].lower() if m.group(1)[-1].isalpha() else m.group(1).upper()
    cur.append(line)
    if not line.lstrip().startswith("--") and line.rstrip().endswith(";"):
        if has_sql(cur):
            blocks.append((label, "\n".join(cur).strip()))
        cur = []

for lab, body in blocks:
    n = used.get(lab, 0); used[lab] = n + 1
    name = lab if n == 0 else f"{lab}_{n+1}"
    m = re.match(r"Q(\d+)(.*)", name)
    name = f"Q{int(m.group(1)):02d}{m.group(2)}"
    (out / f"{name}.sql").write_text(body + "\n", encoding="utf-8")
print(f"{len(blocks)} queries written to {out}")
