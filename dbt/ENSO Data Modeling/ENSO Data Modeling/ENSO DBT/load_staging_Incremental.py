"""
ENSO DATA WAREHOUSE — INCREMENTAL STAGING LOADER
LOCAL CSV FILES -> REMOTE SQL SERVER (staging schema)

Run from your PC (inside the activated virtual environment):
    python load_staging_Incremental.py --check         # checks packages + env vars + connection
    python load_staging_Incremental.py --dry-run       # validates files & previews new rows, no DB writes
    python load_staging_Incremental.py                 # incrementally loads new records only
    python load_staging_Incremental.py --data-dir "D:/other/folder"

Data folder: found automatically (the repo's `data/` folder, searched upward from this script);
override with --data-dir or the ENSO_DATA_DIR environment variable.

Behaviour (Incremental Mode):
    - Every column is loaded as text (NVARCHAR); dbt does the typing later.
    - Existing staging tables are NOT truncated.
    - Before inserting, the script checks existing business keys in SQL Server and
      appends ONLY new rows that do not already exist in the target table.
    - If a staging table does not exist yet, it is created automatically and all rows are loaded.
    - Audit columns _loaded_at and _source_file are added to every inserted batch.
"""

import argparse
import codecs
import os
import re
import sys
import time
import warnings
from datetime import datetime
from pathlib import Path
from urllib.parse import quote_plus

try:
    import pandas as pd
except ImportError:
    sys.exit("pandas is not installed in this Python environment.\n"
             "  Run:  python -m pip install pandas sqlalchemy pyodbc")

# =========================================================
# 1. SETTINGS
# =========================================================

def resolve_default_data_dir():
    """Find the project's `data/` folder without any hard-coded absolute path.

    Repo layout (this script lives in  <root>/dbt/ENSO Data Modeling/ENSO Data Modeling/ENSO DBT/):
        <root>/data/                      <- ENSO_NINO_data.csv, ffpi_monthly.csv, gpcp_*.csv, events csv
        <root>/data/Production_Crops_Livestock_E_All_Data_(Normalized)/   <- the 5 FAOSTAT csv files
    Order: 1) env var ENSO_DATA_DIR  2) the nearest `data/` folder found walking up from this script
           3) ./data in the current folder.  --data-dir on the command line overrides all of them.
    """
    env = os.getenv("ENSO_DATA_DIR")
    if env:
        return Path(env).expanduser()
    here = Path(__file__).resolve().parent
    for folder in [here, *here.parents]:
        cand = folder / "data"
        if cand.is_dir() and ((cand / "collect_data.py").exists() or (cand / FFPI_FILE_NAME).exists()):
            return cand
    return Path.cwd() / "data"


FFPI_FILE_NAME = "ffpi_monthly.csv"
DEFAULT_DATA_DIR = resolve_default_data_dir()

SCHEMA = "staging"

FAO_FILE = "Production_Crops_Livestock_E_All_Data_(Normalized).csv"
AREAS_FILE = "Production_Crops_Livestock_E_AreaCodes.csv"
ITEMS_FILE = "Production_Crops_Livestock_E_ItemCodes.csv"
ELEMENTS_FILE = "Production_Crops_Livestock_E_Elements.csv"
FLAGS_FILE = "Production_Crops_Livestock_E_Flags.csv"
EVENTS_FILE = "el-nino-southern-oscillation-enso-el-nino-and-la-nina-events.csv"
NINO_FILE = "ENSO_NINO_data.csv"
GPCP_FILE = "gpcp_monthly_precipitation.csv"
FFPI_FILE = FFPI_FILE_NAME

FAO_TARGETS = ["area_code", "area_code_m49", "area_name", "item_code", "item_code_cpc", "item_name",
               "element_code", "element_name", "year_code", "year", "unit", "value", "flag", "note"]
EVENTS_TARGETS = ["month_date", "total_sst", "clim_adjust", "anom", "anom_trimester",
                  "anom_trimester_round", "phase_trimester", "phase_event"]
NINO_TARGETS = ["yr", "mon", "nino12", "nino12_anom", "nino3", "nino3_anom",
                "nino4", "nino4_anom", "nino34", "nino34_anom"]
GPCP_TARGETS = ["month_date", "country", "original_lat", "original_lon",
                "grid_lat", "grid_lon", "precipitation_mm_per_day"]
FFPI_TARGETS = ["month_date", "ffpi", "meat", "dairy", "cereals", "oils", "sugar",
                "ffpi_real", "meat_real", "dairy_real", "cereals_real", "oils_real", "sugar_real"]

ALIASES = {"month_date": ["date", "month", "period"]}

# Business / composite keys used to detect already-loaded rows for incremental ingestion
TABLE_KEYS = {
    "fao_production": ["area_code", "item_code", "element_code", "year_code"],
    "fao_areas": ["area_code"],
    "fao_items": ["item_code"],
    "fao_elements": ["element_code"],
    "fao_flags": ["flag"],
    "enso_events": ["month_date"],
    "nino_regions": ["yr", "mon"],
    "gpcp_precipitation": ["month_date", "country", "grid_lat", "grid_lon"],
    "ffpi_monthly": ["month_date"],
}

ALL_TABLES = list(TABLE_KEYS.keys())

LOAD_TS = datetime.now().strftime("%Y-%m-%d %H:%M:%S")


# =========================================================
# 2. PACKAGES + SQL SERVER CONNECTION
# =========================================================

def require_packages():
    missing = []
    for module, pip_name in (("sqlalchemy", "sqlalchemy"), ("pyodbc", "pyodbc")):
        try:
            __import__(module)
        except ImportError:
            missing.append(pip_name)
    if missing:
        sys.exit(
            "Missing Python package(s): " + ", ".join(missing) + "\n"
            "Install them in the activated virtual environment with:\n"
            f"    python -m pip install {' '.join(missing)}\n"
            f"(this Python is: {sys.executable})"
        )


def env_first(*names):
    for n in names:
        v = os.getenv(n)
        if v:
            return v
    return None


def get_engine():
    require_packages()
    from sqlalchemy import create_engine

    server = env_first("DBT_SQLSERVER_HOST_001", "ENSO_SQL_SERVER")
    user = env_first("DBT_SQLSERVER_USER_001", "ENSO_SQL_USER")
    password = env_first("DBT_SQLSERVER_PASSWORD_001", "ENSO_SQL_PASSWORD")
    database = env_first("DBT_SQLSERVER_DATABASE", "ENSO_SQL_DB") or "ENSO_DB"
    port = env_first("DBT_SQLSERVER_PORT", "ENSO_SQL_PORT")
    driver = os.getenv("ENSO_ODBC_DRIVER", "ODBC Driver 18 for SQL Server")

    missing = [name for name, val in [("DBT_SQLSERVER_HOST", server),
                                      ("DBT_SQLSERVER_USER", user),
                                      ("DBT_SQLSERVER_PASSWORD", password)] if not val]
    if missing:
        sys.exit("Missing environment variables: " + ", ".join(missing) + "\n"
                 "Set them in this same terminal window first, e.g. in PowerShell:\n"
                 '    $env:DBT_SQLSERVER_HOST = "your-server"\n'
                 '    $env:DBT_SQLSERVER_USER = "your-login"\n'
                 '    $env:DBT_SQLSERVER_PASSWORD = "your-password"')

    if port and "," not in server:
        server = f"{server},{port}"

    conn_str = (
        f"DRIVER={{{driver}}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        f"UID={{{user}}};"
        f"PWD={{{password.replace('}', '}}')}}};"
        "Encrypt=yes;"
        "TrustServerCertificate=yes;"
        "Connection Timeout=30;"
    )
    return create_engine("mssql+pyodbc:///?odbc_connect=" + quote_plus(conn_str),
                         fast_executemany=True)


def explain_connection_error(err):
    text = str(err)
    print("\nCould not connect to SQL Server.")
    if "IM002" in text or "Data source name not found" in text:
        print("-> ODBC driver not found. Install 'Microsoft ODBC Driver 18 for SQL Server', or set "
              "ENSO_ODBC_DRIVER to the exact name of an installed driver.")
    elif "18456" in text or "Login failed" in text:
        print("-> Login failed. Check DBT_SQLSERVER_USER and DBT_SQLSERVER_PASSWORD.")
    elif "4060" in text or "Cannot open database" in text:
        print("-> The login cannot open the database. Check DBT_SQLSERVER_DATABASE (default ENSO_DB).")
    elif any(k in text for k in ("08001", "HYT00", "timeout", "network-related", "10060", "11001")):
        print("-> Server not reachable. Check the host name / port and firewall settings.")
    print("\nDriver message:\n" + text[:600])
    sys.exit(1)


def connect(engine):
    try:
        with engine.connect() as conn:
            return conn.exec_driver_sql("SELECT @@SERVERNAME, DB_NAME(), SUSER_NAME()").fetchone()
    except Exception as e:  # noqa: BLE001
        explain_connection_error(e)


def ensure_schema(engine):
    from sqlalchemy import text
    with engine.begin() as conn:
        conn.execute(text(
            f"IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = '{SCHEMA}') "
            f"EXEC('CREATE SCHEMA {SCHEMA}')"
        ))


# =========================================================
# 3. COMMON & INCREMENTAL HELPER FUNCTIONS
# =========================================================

def find_file(directory, filename, patterns=()):
    direct = directory / filename
    if direct.exists():
        return direct
    for hit in sorted(directory.rglob(filename)):
        return hit
    for pat in patterns:
        for hit in sorted(directory.rglob(pat)):
            return hit
    return None


def check_file(directory, filename, patterns=()):
    path = find_file(directory, filename, patterns)
    if path is None:
        present = sorted(p.name for p in directory.rglob("*.csv"))[:15]
        raise FileNotFoundError(
            f"Source file not found: {filename}\n"
            f"  searched in: {directory} (and its sub-folders)\n"
            f"  CSV files found there: {present if present else 'none'}"
        )
    return path


def detect_encoding(path):
    decoder = codecs.getincrementaldecoder("utf-8-sig")()
    try:
        with open(path, "rb") as f:
            while True:
                block = f.read(4 * 1024 * 1024)
                if not block:
                    decoder.decode(b"", final=True)
                    break
                decoder.decode(block)
        return "utf-8-sig"
    except UnicodeDecodeError:
        return "latin-1"


def read_csv_file(path, **kwargs):
    return pd.read_csv(path, dtype=str, keep_default_na=False, na_values=[""],
                       encoding=detect_encoding(path), **kwargs)


def clean_headers(df):
    df.columns = [str(c).strip() for c in df.columns]
    return df


def norm(name):
    return re.sub(r"[^0-9a-z]+", "", str(name).lower())


def map_columns(df, targets, label):
    by_key = {norm(c): c for c in df.columns}
    chosen = {}
    for t in targets:
        for key in [norm(t)] + [norm(a) for a in ALIASES.get(t, [])]:
            if key in by_key:
                chosen[t] = by_key[key]
                break
    if len(chosen) == len(targets):
        out = df[[chosen[t] for t in targets]].copy()
        out.columns = targets
        return out
    if df.shape[1] >= len(targets):
        used = list(df.columns[:len(targets)])
        print(f"  WARNING {label}: header names not recognised - using the first {len(targets)} "
              f"columns by position:\n    {used}\n    -> {targets}")
        out = df.iloc[:, :len(targets)].copy()
        out.columns = targets
        return out
    raise ValueError(f"{label}: expected {len(targets)} columns, found {df.shape[1]} ({list(df.columns)})")


def prepare(df, source_file):
    df = df.copy()
    df = df.astype("string").astype(object)
    df = df.where(pd.notna(df), None)
    df["_loaded_at"] = LOAD_TS
    df["_source_file"] = source_file
    return df


def validate_columns(df, table, engine):
    from sqlalchemy import inspect
    insp = inspect(engine)
    if not insp.has_table(table, schema=SCHEMA):
        return
    table_cols = [c["name"] for c in insp.get_columns(table, schema=SCHEMA)]
    if set(table_cols) != set(df.columns):
        raise ValueError(
            f"Column mismatch for {SCHEMA}.{table}\n"
            f"  only in file : {sorted(set(df.columns) - set(table_cols))}\n"
            f"  only in table: {sorted(set(table_cols) - set(df.columns))}\n"
            "Re-run 02_create_staging_layer.sql, or fix the file."
        )


def get_existing_keys(engine, table):
    """Fetch existing composite key tuples from SQL Server to prevent duplicate inserts."""
    from sqlalchemy import inspect, text
    if engine is None or not inspect(engine).has_table(table, schema=SCHEMA):
        return set()

    key_cols = TABLE_KEYS[table]
    col_expr = ", ".join(f"COALESCE(CAST([{c}] AS NVARCHAR(400)), '')" for c in key_cols)
    query = text(f"SELECT DISTINCT {col_expr} FROM {SCHEMA}.{table}")

    with engine.connect() as conn:
        result = conn.execute(query).fetchall()
    return {tuple(row) for row in result}


def filter_new_rows(df, table, existing_keys):
    """Return only rows whose business key tuple is not already in existing_keys."""
    if not existing_keys or df.empty:
        return df

    key_cols = TABLE_KEYS[table]
    # Build tuple series matching COALESCE(col, '') logic
    key_series = list(zip(*(df[c].fillna("").astype(str) for c in key_cols)))
    mask = [k not in existing_keys for k in key_series]

    # Add newly accepted keys to the set so intra-file duplicates are also prevented
    for k, keep in zip(key_series, mask):
        if keep:
            existing_keys.add(k)

    return df.loc[mask].copy()


def write_incremental(df, table, engine, first_chunk=True):
    """Validate schema on first chunk and APPEND new records without truncating."""
    from sqlalchemy.types import NVARCHAR

    if first_chunk:
        validate_columns(df, table, engine)

    if df.empty:
        return

    df.to_sql(name=table, con=engine, schema=SCHEMA, if_exists="append", index=False,
              dtype={c: NVARCHAR(400) for c in df.columns}, chunksize=5000)


def db_count(engine, table):
    from sqlalchemy import text
    with engine.connect() as conn:
        return conn.execute(text(f"SELECT COUNT(*) FROM {SCHEMA}.{table}")).scalar()


def load_small_incremental(df, table, source_file, engine, dry):
    df = prepare(clean_headers(df), source_file)
    total_read = len(df)

    existing_keys = set() if dry else get_existing_keys(engine, table)
    new_df = filter_new_rows(df, table, existing_keys)
    new_count = len(new_df)

    print(f"  {table:<22}read: {total_read:>9,} | new: {new_count:>9,}   <- {source_file}")
    if not dry:
        write_incremental(new_df, table, engine, first_chunk=True)
    return {"read": total_read, "inserted": new_count}


# =========================================================
# 4. FAOSTAT LOOKUPS
# =========================================================

def load_lookups(directory, engine, dry, wanted, stats):
    print("\nLoading FAOSTAT lookup tables (incremental)...")
    lookups = [
        (AREAS_FILE, "fao_areas", ["area_code", "m49_code", "area_name"]),
        (ITEMS_FILE, "fao_items", ["item_code", "cpc_code", "item_name"]),
        (ELEMENTS_FILE, "fao_elements", ["element_code", "element_name"]),
        (FLAGS_FILE, "fao_flags", ["flag", "description"]),
    ]
    for filename, table, cols in lookups:
        if table not in wanted:
            continue
        path = check_file(directory, filename)
        df = clean_headers(read_csv_file(path))
        if len(df.columns) != len(cols):
            raise ValueError(f"{filename}: expected {len(cols)} columns, "
                             f"found {len(df.columns)} ({list(df.columns)})")
        df.columns = cols
        stats[table] = load_small_incremental(df, table, path.name, engine, dry)


# =========================================================
# 5. ENSO / CLIMATE
# =========================================================

def load_enso_files(directory, engine, dry, wanted, stats):
    print("\nLoading ENSO datasets (incremental)...")

    if "enso_events" in wanted:
        path = check_file(directory, EVENTS_FILE, ["*enso*events*.csv"])
        ev = clean_headers(read_csv_file(path))
        if len(ev.columns) != len(EVENTS_TARGETS):
            raise ValueError(f"{path.name}: expected {len(EVENTS_TARGETS)} columns, "
                             f"found {len(ev.columns)} ({list(ev.columns)})")
        ev.columns = EVENTS_TARGETS
        stats["enso_events"] = load_small_incremental(ev, "enso_events", path.name, engine, dry)

    if "nino_regions" in wanted:
        path = check_file(directory, NINO_FILE, ["*NINO*.csv", "*nino*.csv"])
        n = map_columns(clean_headers(read_csv_file(path)), NINO_TARGETS, path.name)
        n = n.dropna(how="all")
        stats["nino_regions"] = load_small_incremental(n, "nino_regions", path.name, engine, dry)

    if "gpcp_precipitation" in wanted:
        path = check_file(directory, GPCP_FILE, ["gpcp*.csv"])
        g = map_columns(clean_headers(read_csv_file(path)), GPCP_TARGETS, path.name)
        g = g.dropna(how="all")
        stats["gpcp_precipitation"] = load_small_incremental(g, "gpcp_precipitation", path.name, engine, dry)


# =========================================================
# 6. FAO FOOD PRICE INDEX
# =========================================================

def load_ffpi(directory, engine, dry, wanted, stats):
    if "ffpi_monthly" not in wanted:
        return
    print("\nLoading FAO Food Price Index (incremental)...")
    path = check_file(directory, FFPI_FILE, ["ffpi_monthly*.csv", "ffpi*.csv"])
    f = clean_headers(read_csv_file(path)).dropna(how="all")
    f = map_columns(f, FFPI_TARGETS, path.name)
    f = f.dropna(subset=["month_date"])

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        parsed = pd.to_datetime(f["month_date"], errors="coerce")
    bad = f.loc[parsed.isna(), "month_date"]
    if bad.empty:
        f["month_date"] = parsed.dt.strftime("%Y-%m-%d")
    else:
        print(f"  WARNING {path.name}: {len(bad)} month_date value(s) are not dates "
              f"(examples: {list(bad.head(3))}); kept as they are.")
    stats["ffpi_monthly"] = load_small_incremental(f, "ffpi_monthly", path.name, engine, dry)


# =========================================================
# 7. FAOSTAT PRODUCTION (large, chunked incremental)
# =========================================================

def load_fao(directory, engine, dry, stats, chunk=100_000):
    path = check_file(directory, FAO_FILE, ["Production_Crops_Livestock_E_All_Data*.csv"])
    encoding = detect_encoding(path)
    print(f"\nLoading FAOSTAT production data incrementally (encoding={encoding})...\n  file: {path}")

    existing_keys = set() if dry else get_existing_keys(engine, "fao_production")
    if not dry:
        print(f"  Existing keys in staging.fao_production: {len(existing_keys):,}")

    total_read, total_inserted, started = 0, 0, time.time()
    reader = pd.read_csv(path, dtype=str, keep_default_na=False, na_values=[""],
                         chunksize=chunk, encoding=encoding)
    for k, ch in enumerate(reader):
        ch = clean_headers(ch)
        if k == 0 and ch.shape[1] != len(FAO_TARGETS):
            raise ValueError(f"FAO file has {ch.shape[1]} columns, expected {len(FAO_TARGETS)} "
                             f"({list(ch.columns)})")
        ch.columns = FAO_TARGETS
        ch = prepare(ch, path.name)

        new_ch = filter_new_rows(ch, "fao_production", existing_keys)
        if not dry:
            write_incremental(new_ch, "fao_production", engine, first_chunk=(k == 0))

        total_read += len(ch)
        total_inserted += len(new_ch)
        rate = total_read / max(time.time() - started, 1)
        print(f"  Chunk {k + 1}: read {total_read:,} | new {total_inserted:,} ({rate:,.0f} rows/s)", end="\r")

    print(f"\n  fao_production: {total_read:,} rows read | {total_inserted:,} new rows inserted")
    stats["fao_production"] = {"read": total_read, "inserted": total_inserted}


# =========================================================
# 8. MAIN
# =========================================================

def print_summary(stats, engine, dry):
    print("\n" + "=" * 75)
    print("INCREMENTAL LOAD SUMMARY")
    print("=" * 75)
    print(f"{'table':<22}{'file rows':>12}{'new rows':>12}{'total in db':>14}  status")
    for table in ALL_TABLES:
        if table not in stats:
            continue
        n_read = stats[table]["read"]
        n_new = stats[table]["inserted"]
        n_db = None if dry else db_count(engine, table)
        status = "dry run" if dry else "OK"
        shown_db = "-" if n_db is None else f"{n_db:,}"
        print(f"{table:<22}{n_read:>12,}{n_new:>12,}{shown_db:>14}  {status}")
    print("=" * 75)
    print("DRY RUN COMPLETED." if dry else "INCREMENTAL LOAD COMPLETED.")


def main():
    parser = argparse.ArgumentParser(description="ENSO CSV -> SQL Server incremental staging loader")
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR,
                        help="Folder with the CSV files (default: the repo's data/ folder, auto-detected).")
    parser.add_argument("--dry-run", action="store_true",
                        help="Read and validate files without touching the database.")
    parser.add_argument("--skip-fao", action="store_true",
                        help="Skip the large FAOSTAT production file.")
    parser.add_argument("--only", help="Comma-separated tables to incrementally load, e.g. fao_production")
    parser.add_argument("--check", action="store_true",
                        help="Only check packages, environment variables and the connection.")
    args = parser.parse_args()

    print("=" * 75)
    print("ENSO DATA WAREHOUSE - CSV -> SQL SERVER STAGING (INCREMENTAL)")
    print("=" * 75)

    if args.check:
        engine = get_engine()
        server, db, login = connect(engine)
        print(f"Connected  : {server} / database {db} / login {login}")
        from sqlalchemy import text
        with engine.connect() as conn:
            n = conn.execute(text(f"SELECT COUNT(*) FROM sys.tables WHERE SCHEMA_NAME(schema_id)='{SCHEMA}'")).scalar()
        print(f"Tables in schema {SCHEMA}: {n}")
        return

    if not args.data_dir.exists():
        sys.exit(f"Data directory does not exist: {args.data_dir}\n"
                 'Pass the right folder with --data-dir "C:/path/to/data" or set ENSO_DATA_DIR')

    wanted = set(ALL_TABLES)
    if args.only:
        wanted = {t.strip() for t in args.only.split(",")}
        unknown = wanted - set(ALL_TABLES)
        if unknown:
            sys.exit(f"Unknown table(s): {sorted(unknown)}. Valid: {ALL_TABLES}")
    if args.skip_fao:
        wanted.discard("fao_production")

    print(f"Data directory: {args.data_dir}")
    print(f"Mode          : {'DRY RUN (INCREMENTAL)' if args.dry_run else 'INCREMENTAL DATABASE LOAD'}")

    engine, stats = None, {}
    try:
        if not args.dry_run:
            engine = get_engine()
            server, db, login = connect(engine)
            print(f"Connected to  : {server} / database {db} (login {login})")
            ensure_schema(engine)

        load_lookups(args.data_dir, engine, args.dry_run, wanted, stats)
        load_enso_files(args.data_dir, engine, args.dry_run, wanted, stats)
        load_ffpi(args.data_dir, engine, args.dry_run, wanted, stats)
        if "fao_production" in wanted:
            load_fao(args.data_dir, engine, args.dry_run, stats)

        print_summary(stats, engine, args.dry_run)
    except (FileNotFoundError, ValueError) as e:
        sys.exit(f"\nERROR: {e}")
    finally:
        if engine is not None:
            engine.dispose()


if __name__ == "__main__":
    main()