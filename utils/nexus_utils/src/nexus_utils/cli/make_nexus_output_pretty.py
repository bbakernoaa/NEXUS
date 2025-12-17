#!/usr/bin/env python
"""
Post-processes raw NEXUS output to create a more user-friendly NetCDF file.

This script takes a raw, coordinate-less NetCDF file produced by NEXUS and
enriches it with proper time, latitude, and longitude coordinates. It reads
metadata from a grid specification file and a HEMCO time configuration file
to create a self-describing, analysis-ready dataset.

The key steps are:
1.  Read the source data, grid geometry, and time information.
2.  Generate a complete list of datetime objects for the time axis.
3.  Combine the source data with the grid's latitude/longitude coordinates.
4.  Assign the datetime objects to the time coordinate.
5.  Replicate the original script's behavior by adding a final, zero-filled
    time step.
6.  Fill any missing data with zeros.
7.  Write the final, "pretty" dataset to a new NetCDF file with zlib compression.
"""
import argparse
import datetime as dt
from pathlib import Path

import numpy as np
import xarray as xr


def get_hemco_dates(time_file: Path) -> list[dt.datetime]:
    """
    Parses a HEMCO time configuration file to generate a list of datetimes.

    The input file is expected to contain start time, end time, and the
    emissions timestep, formatted as follows:
    START: YYYY-MM-DD HH:MM:SS
    END:   YYYY-MM-DD HH:MM:SS
    TS_EMIS: <seconds>

    Args:
        time_file: The path to the HEMCO time configuration file.

    Returns:
        A list of datetime objects representing the full time axis.

    Raises:
        ValueError: If the start, end, or timestep cannot be parsed.
    """

    def parse_dt_line(line: str) -> dt.datetime:
        """Helper to parse a datetime from a line."""
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

    # Generate the sequence of dates from start to end, inclusive.
    total_seconds = (end - start).total_seconds()
    dates = [
        start + dt.timedelta(seconds=s) for s in np.arange(0, total_seconds + ts_emis, ts_emis)
    ]
    return dates


def main(s_fp: Path, g_fp: Path, t_fp: Path, o_fp: Path) -> int:
    """
    Main function to execute the data processing pipeline.

    Reads the raw NEXUS output and auxiliary files, processes them using
    xarray, and saves the result to a new NetCDF file.

    Args:
        s_fp: Path to the source ('ugly') NEXUS NetCDF file.
        g_fp: Path to the grid specification NetCDF file.
        t_fp: Path to the HEMCO time configuration file.
        o_fp: Path for the output ('pretty') NetCDF file.

    Returns:
        0 on success.
    """
    # Open the source data and the grid specification files lazily.
    ds_s = xr.open_dataset(s_fp, engine="netcdf4")
    ds_g = xr.open_dataset(g_fp, engine="netcdf4")

    # Generate datetime objects from the HEMCO time file.
    dates = get_hemco_dates(t_fp)
    # The raw data is missing the last time coordinate, so assign all but the last.
    ds_s = ds_s.assign_coords(time=dates[:-1])

    # Add the final time step and fill all variables with 0 for that step.
    # This matches the behavior of the original script.
    ds_s = ds_s.reindex({"time": dates}, fill_value=0)

    # Rename spatial dimensions for clarity and assign lat/lon coordinates.
    ds_s = ds_s.rename({"lon": "x", "lat": "y"})
    ds_s = ds_s.assign_coords(
        {
            "latitude": (("y", "x"), ds_g["grid_latt"].data),
            "longitude": (("y", "x"), ds_g["grid_lont"].data),
        }
    )
    ds_s.latitude.attrs = {"long_name": "latitude", "units": "degree_north"}
    ds_s.longitude.attrs = {"long_name": "longitude", "units": "degree_east"}

    # Update metadata and prepare encoding for compressed output.
    ds_s.attrs["title"] = "NEXUS Generated Emission Data"
    encoding = {}
    for var in ds_s.data_vars:
        ds_s[var].attrs.update({"units": "kg m-2 s-1", "long_name": var})
        encoding[var] = {"zlib": True, "complevel": 1}

    # Fill any remaining NaN values with 0.
    ds_s = ds_s.fillna(0)

    # Write the final dataset to a new NetCDF file.
    ds_s.to_netcdf(o_fp, "w", format="NETCDF4", engine="netcdf4", encoding=encoding)
    return 0


def parse_args(argv=None):
    """
    Parses command-line arguments.

    Sets up the argument parser and defines the command-line interface
    for the script.

    Args:
        argv: A list of command-line arguments, defaults to None
              (which uses sys.argv).

    Returns:
        A dictionary of the parsed arguments.
    """
    parser = argparse.ArgumentParser(
        description="Make the NEXUS output pretty",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "-s",
        "--src",
        type=Path,
        help="Input ('ugly') NEXUS file path.",
        required=True,
    )
    parser.add_argument(
        "-g",
        "--grid",
        type=Path,
        default=Path("./grid_spec.nc"),
        help="Grid specification file path.",
    )
    parser.add_argument(
        "-t",
        "--hemco-time",
        type=Path,
        default=Path("./HEMCO_sa_Time.rc"),
        help="HEMCO time configuration file path.",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Output ('pretty') file path.",
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
