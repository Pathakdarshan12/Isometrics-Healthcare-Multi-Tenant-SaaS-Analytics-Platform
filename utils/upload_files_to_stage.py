"""Upload generated Parquet files to the Snowflake stage that load_data_to_snowflake.sql reads.

Run from the repo root (credentials come from .env, see utils/snowflake_connector.py):

    python -m utils.upload_files_to_stage
    python -m utils.upload_files_to_stage --folder data_generation/parquet \
        --stage RAW_PHI.HEALTHCARE_DATA_STAGE --subdirectory 2023
"""
import argparse
import os
import sys

from utils.snowflake_connector import SnowflakeConnection

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def upload_files_to_stage(folder_path, stage_name, subdirectory=None, pattern="*.parquet"):
    """PUT every file matching `pattern` in `folder_path` (relative to repo root) to the stage.

    Returns the PUT result rows; raises on any failure.
    """
    folder_path = os.path.abspath(os.path.join(REPO_ROOT, folder_path))
    if not os.path.isdir(folder_path):
        raise FileNotFoundError(f"Folder not found: {folder_path}")

    # Snowflake PUT needs forward slashes, also on Windows
    folder_path_snowflake = folder_path.replace("\\", "/")
    stage_path = f"@{stage_name}/{subdirectory.strip('/')}/" if subdirectory else f"@{stage_name}/"

    sf = SnowflakeConnection()
    sf.connect()
    try:
        with sf.get_cursor() as cursor:
            cursor.execute("SELECT CURRENT_ROLE(), CURRENT_DATABASE(), CURRENT_SCHEMA()")
            role, db, schema = cursor.fetchone()
            print(f"Context: Role={role}, DB={db}, Schema={schema}")
            print(f"🎯 Uploading {folder_path_snowflake}/{pattern} -> {stage_path}")

            cursor.execute(f"""
                PUT 'file://{folder_path_snowflake}/{pattern}'
                {stage_path}
                AUTO_COMPRESS = FALSE
                OVERWRITE = TRUE
                PARALLEL = 4
            """)
            results = cursor.fetchall()
    finally:
        sf.close()

    for row in results:
        # row: source, target, source_size, target_size, source_compression, target_compression, status, message
        print(f"  {row[0]:<40} {row[6]}")
    failed = [row for row in results if row[6] not in ("UPLOADED", "SKIPPED")]
    if failed:
        raise RuntimeError(f"{len(failed)} file(s) failed to upload")
    return results


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--folder", default="data_generation/parquet", help="Folder relative to repo root")
    parser.add_argument("--stage", default="RAW_PHI.HEALTHCARE_DATA_STAGE", help="Target stage name")
    parser.add_argument("--subdirectory", default="2023",
                        help="Stage subdirectory (load_data_to_snowflake.sql reads @stage/2023/)")
    parser.add_argument("--pattern", default="*.parquet")
    args = parser.parse_args(argv)

    upload_files_to_stage(args.folder, args.stage, args.subdirectory, args.pattern)
    return 0


if __name__ == "__main__":
    sys.exit(main())
