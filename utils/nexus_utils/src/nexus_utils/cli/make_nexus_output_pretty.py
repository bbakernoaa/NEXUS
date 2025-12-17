#!/usr/bin/env python
"""
Make NEXUS output pretty.
"""
import datetime as dt
from pathlib import Path

import numpy as np
import xarray as xr


def get_hemco_dates(time_file: Path) -> list[dt.datetime]:
    """Parse HEMCO time file for dates."""

    def parse_dt_line(line: str) -> dt.datetime:
        _, s_date, s_time = line.split()
        return dt.datetime.strptime(f"{s_date} {s_time}", r"%Y-%m-%d %H:%M:%S")

    start = end = ts_emis = None
    with open(time_file) as f:
        for line in f:
            line = line.strip()
            if line.startswith("START:"):
                start = parse_dt_line(line)
            elif line.startswith("END:"):
                end = parse_dt_line(line)
            elif line.startswith("TS_EMIS:"):  # time step (s), e.g. 3600
                _, s_ts = line.split()
                ts_emis = float(s_ts)

    if start is None or end is None or ts_emis is None:
        raise ValueError("Could not parse start, end, or timestep from HEMCO time file.")

    dates = [
        start + dt.timedelta(seconds=s)
        for s in np.arange(0, (end - start).total_seconds() + ts_emis, ts_emis)
    ]
    return dates


def main(s_fp: Path, g_fp: Path, t_fp: Path, o_fp: Path) -> int:
    """Main function to make NEXUS output pretty."""
    # Open source and grid datasets
    ds_s = xr.open_dataset(s_fp, engine="netcdf4")
    ds_g = xr.open_dataset(g_fp, engine="netcdf4")

    # Compute datetimes
    dates = get_hemco_dates(t_fp)
    ds_s = ds_s.assign_coords(time=dates[:-1])

    # Add final time step, filled with 0
    ds_s = ds_s.reindex({"time": dates}, fill_value=0)

    # Add coordinates
    ds_s = ds_s.rename({"lon": "x", "lat": "y"})
    ds_s = ds_s.assign_coords(
        {
            "latitude": (("y", "x"), ds_g["grid_latt"].data),
            "longitude": (("y", "x"), ds_g["grid_lont"].data),
        }
    )
    ds_s.latitude.attrs = {"long_name": "latitude", "units": "degree_north"}
    ds_s.longitude.attrs = {"long_name": "longitude", "units": "degree_east"}

    # Update attributes and save
    ds_s.attrs["title"] = "NEXUS Generated Emission Data"
    encoding = {}
    for var in ds_s.data_vars:
        ds_s[var].attrs.update({"units": "kg m-2 s-1", "long_name": var})
        encoding[var] = {"zlib": True, "complevel": 1}

    # Fill NaN values with 0
    ds_s = ds_s.fillna(0)

    ds_s.to_netcdf(o_fp, "w", format="NETCDF4", engine="netcdf4", encoding=encoding)
    return 0


def parse_args(argv=None):
    """Parse command line arguments."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Make the NEXUS output pretty",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "-s",
        "--src",
        type=Path,
        help="input ('ugly') NEXUS file path",
        required=True,
    )
    parser.add_argument(
        "-g",
        "--grid",
        type=Path,
        default=Path("./grid_spec.nc"),
        help="grid file path",
    )
    parser.add_argument(
        "-t",
        "--hemco-time",
        type=Path,
        default=Path("./HEMCO_sa_Time.rc"),
        help="HEMCO time file path",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="output file path",
        required=True,
    )

    args = parser.parse_args(argv)

    return {
        "s_fp": args.src,
        "g_fp": args.grid,
        "t_fp": args.hemco_time,
        "o_fp": args.output,
    }


if __name__ == "__main__":
    raise SystemExit(main(**parse_args()))
