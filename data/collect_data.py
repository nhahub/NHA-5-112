#!/usr/bin/env python3
"""
data/collect_data.py - re-creates the project's data files, next to this script.

    python data/collect_data.py                    # everything
    python data/collect_data.py --only nino gpcp   # selected sources only
    python data/collect_data.py --force            # ignore the freshness check

Files written into the folder that contains this script:

  nino    ENSO_NINO_data.xlsx  (sheet NINO_Data)          <- NOAA CPC sstoi.indices
  ffpi    ffpi-data-YYYY-MM.xlsx  (YYYY-MM = download month) <- FAO Food Price Index workbook
  gpcp    gpcp_monthly_precipitation.csv                  <- NOAA PSL GPCP v2.3 (10 reference points)
  faostat Production_Crops_Livestock_E_All_Data_(Normalized)/  (5 CSVs) <- FAOSTAT bulk zip

Requires: pip install -r requirements.txt   (pandas requests openpyxl xarray netCDF4)
"""
from __future__ import annotations

import argparse
import re
import shutil
import sys
import tempfile
import time
import zipfile
from datetime import date
from pathlib import Path

import pandas as pd
import requests

DATA = Path(__file__).resolve().parent
UA = {"User-Agent": "Mozilla/5.0 (ENSO-project data collector)"}

URLS = {
    "nino": "https://www.cpc.ncep.noaa.gov/data/indices/sstoi.indices",
    "gpcp": ["https://psl.noaa.gov/thredds/fileServer/Datasets/gpcp/precip.mon.mean.nc",
             "https://downloads.psl.noaa.gov/Datasets/gpcp/precip.mon.mean.nc"],
    "ffpi_page": "https://www.fao.org/worldfoodsituation/foodpricesindex",
    "qcl": "https://bulks-faostat.fao.org/production/"
           "Production_Crops_Livestock_E_All_Data_(Normalized).zip",
}

# File names (exactly as in the repository)
NINO_FILE = "ENSO_NINO_data.xlsx"
GPCP_FILE = "gpcp_monthly_precipitation.csv"
QCL_DIR = "Production_Crops_Livestock_E_All_Data_(Normalized)"
QCL_MAIN = "Production_Crops_Livestock_E_All_Data_(Normalized).csv"

GPCP_START = "2000-01-01"
# country, original_lat, original_lon (same order and coordinates as the existing file)
GPCP_POINTS = [
    ("Egypt", 26.8206, 30.8025), ("Brazil", -14.2350, -51.9253),
    ("Indonesia", -0.7893, 113.9213), ("India", 20.5937, 78.9629),
    ("Australia", -25.2744, 133.7751), ("Kenya", -1.2921, 36.8219),
    ("Peru", -9.1900, -75.0152), ("USA_Midwest", 41.8781, -87.6298),
    ("South_Africa", -30.5595, 22.9375), ("Vietnam", 14.0583, 108.2772),
]


def log(msg: str) -> None:
    print(msg, flush=True)


def is_fresh(path: Path, max_age_days: float, force: bool) -> bool:
    return (not force) and path.exists() and (time.time() - path.stat().st_mtime) < max_age_days * 86400


def download(urls: str | list[str], dest: Path, retries: int = 3) -> Path:
    """Stream the first URL that works to dest (via a .part file)."""
    urls = [urls] if isinstance(urls, str) else urls
    err: Exception | None = None
    for url in urls:
        for attempt in range(1, retries + 1):
            try:
                log(f"  downloading ({attempt}/{retries}): {url}")
                tmp = dest.with_name(dest.name + ".part")
                with requests.get(url, headers=UA, stream=True, timeout=(15, 120)) as r:
                    r.raise_for_status()
                    with open(tmp, "wb") as f:
                        for chunk in r.iter_content(1 << 20):
                            f.write(chunk)
                tmp.replace(dest)
                return dest
            except Exception as e:  # noqa: BLE001
                err = e
                time.sleep(2 * attempt)
    raise RuntimeError(f"download failed ({err})")


# ------------------------------------------------------------------ Nino indices (xlsx)
NINO_COLS = ["YR", "MON", "NINO1+2", "NINO1+2_ANOM", "NINO3", "NINO3_ANOM",
             "NINO4", "NINO4_ANOM", "NINO3.4", "NINO3.4_ANOM"]


def build_nino(src: Path) -> pd.DataFrame:
    df = pd.read_csv(src, sep=r"\s+", skiprows=1, names=NINO_COLS)
    df[["YR", "MON"]] = df[["YR", "MON"]].astype(int)
    return df[df["YR"] >= 1982].reset_index(drop=True)


def run_nino(args) -> None:
    target = DATA / NINO_FILE
    with tempfile.TemporaryDirectory() as tmp:
        src = download(URLS["nino"], Path(tmp) / "sstoi.indices")
        df = build_nino(src)
    with pd.ExcelWriter(target, engine="openpyxl") as w:
        df.to_excel(w, sheet_name="NINO_Data", index=False)
    log(f"  -> {target.name}  ({len(df):,} rows, {df.YR.iloc[0]}-{df.MON.iloc[0]:02d} -> "
        f"{df.YR.iloc[-1]}-{df.MON.iloc[-1]:02d})")


# ------------------------------------------------------------------ FAO Food Price Index (raw xlsx)
def find_ffpi_link() -> str:
    html = requests.get(URLS["ffpi_page"], headers=UA, timeout=60).text
    links = re.findall(r'href=["\']([^"\']+\.xlsx[^"\']*)["\']', html, flags=re.I)
    pref = [l for l in links if re.search(r"ffpi|food.?price", l, re.I)] or links
    if not pref:
        raise RuntimeError("no .xlsx link found on the FAO page - use --ffpi-url or --ffpi-file")
    url = pref[0]
    return url if url.startswith("http") else "https://www.fao.org" + url


def check_ffpi(path: Path) -> None:
    names = pd.ExcelFile(path).sheet_names
    if "Indices_Monthly" not in names:
        raise ValueError(f"not the FFPI workbook (sheets: {names})")


def run_ffpi(args) -> None:
    target = DATA / f"ffpi-data-{date.today():%Y-%m}.xlsx"
    if args.ffpi_file:
        shutil.copyfile(args.ffpi_file, target)
    elif is_fresh(target, 1, args.force):
        log(f"  up to date: {target.name}")
        return
    else:
        download(args.ffpi_url or find_ffpi_link(), target)
    check_ffpi(target)
    log(f"  -> {target.name}")


# ------------------------------------------------------------------ GPCP (10 reference points)
def extract_gpcp(nc_path: Path) -> pd.DataFrame:
    import xarray as xr

    ds = xr.open_dataset(nc_path)
    lat = next(n for n in ("lat", "latitude") if n in ds.coords)
    lon = next(n for n in ("lon", "longitude") if n in ds.coords)
    var = "precip" if "precip" in ds else next(iter(ds.data_vars))
    da = ds[var].sel(time=slice(GPCP_START, None))
    frames = []
    for country, plat, plon in GPCP_POINTS:
        s = da.sel({lat: plat, lon: plon % 360}, method="nearest")  # grid longitudes are 0-360
        frames.append(pd.DataFrame({
            "date": pd.to_datetime(s["time"].values).strftime("%Y-%m-%d"),
            "country": country, "original_lat": plat, "original_lon": plon,
            "grid_lat": float(s[lat]), "grid_lon": float(s[lon]),
            "precipitation_mm_per_day": s.values.astype("float32")}))
    return pd.concat(frames, ignore_index=True)


def run_gpcp(args) -> None:
    target = DATA / GPCP_FILE
    with tempfile.TemporaryDirectory() as tmp:
        nc = download(URLS["gpcp"], Path(tmp) / "precip.mon.mean.nc")
        df = extract_gpcp(nc)
    df.to_csv(target, index=False, lineterminator="\n")
    log(f"  -> {target.name}  ({len(df):,} rows, {df['date'].min()[:7]} -> {df['date'].max()[:7]})")


# ------------------------------------------------------------------ FAOSTAT QCL (extract the zip as-is)
def extract_qcl(zip_path: Path, folder: Path) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as z:
        for m in z.infolist():
            if m.is_dir():
                continue
            with z.open(m) as src, open(folder / Path(m.filename).name, "wb") as dst:
                shutil.copyfileobj(src, dst, 1 << 20)
    if not (folder / QCL_MAIN).exists():
        raise RuntimeError(f"{QCL_MAIN} not found in the zip")


def run_faostat(args) -> None:
    folder = DATA / QCL_DIR
    if is_fresh(folder / QCL_MAIN, 90, args.force):
        log(f"  up to date: {QCL_DIR}/ (refreshed every 90 days; use --force)")
        return
    with tempfile.TemporaryDirectory() as tmp:
        z = download(URLS["qcl"], Path(tmp) / "qcl.zip")
        extract_qcl(z, folder)
    for f in sorted(folder.iterdir()):
        log(f"  -> {QCL_DIR}/{f.name}  ({f.stat().st_size / 1e6:,.1f} MB)")


# ------------------------------------------------------------------ main
RUNNERS = {"nino": run_nino, "ffpi": run_ffpi,
           "gpcp": run_gpcp, "faostat": run_faostat}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", nargs="+", choices=RUNNERS, help="run only these sources")
    ap.add_argument("--force", action="store_true", help="ignore the freshness checks")
    ap.add_argument("--ffpi-url", help="direct URL of the FFPI .xlsx (skips page scraping)")
    ap.add_argument("--ffpi-file", help="copy a local FFPI .xlsx instead of downloading")
    args = ap.parse_args()

    status = {}
    for name in args.only or RUNNERS:
        log(f"\n[{name}]")
        try:
            RUNNERS[name](args)
            status[name] = "OK"
        except Exception as e:  # noqa: BLE001
            status[name] = f"FAILED: {e}"
            log(f"  !! {e}")
    log("\nSummary")
    for k, v in status.items():
        log(f"  {k:8s} {v}")
    return 0 if all(v == "OK" for v in status.values()) else 1


if __name__ == "__main__":
    sys.exit(main())