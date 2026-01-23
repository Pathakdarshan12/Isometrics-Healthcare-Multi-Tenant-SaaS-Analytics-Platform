import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from pathlib import Path

def csv_to_parquet():
    chunk_size = 100_000
    BASE_DIR = Path(__file__).resolve().parent.parent

    csv_file_names = ['billing_transactions.csv', 'clinical_orders.csv',
                      'clinical_results.csv', 'diagnoses.csv',
                      'encounters.csv', 'facilities.csv',
                      'hospitals.csv', 'patients.csv',
                      'patient_allergies.csv', 'patient_coverage.csv',
                      'payers.csv', 'problem_list.csv',
                      'procedures.csv', 'providers.csv',
                      'sdoh_screenings.csv', 'vital_signs.csv']
    for csv_file_name in csv_file_names:
        csv_path = BASE_DIR / "data_generation" / "2025"/ csv_file_name
        parquet_dir = BASE_DIR / "data_generation" / "parquet"
        parquet_dir.mkdir(parents=True, exist_ok=True)
        parquet_path = parquet_dir / (Path(csv_file_name).stem + ".parquet")

        writer = None

        for chunk in pd.read_csv(csv_path, chunksize=chunk_size):
            table = pa.Table.from_pandas(chunk, preserve_index=False)

            if writer is None:
                writer = pq.ParquetWriter(
                    str(parquet_path),
                    table.schema,
                    compression="snappy"
                )

            writer.write_table(table)

        if writer:
            writer.close()

        print(f"Parquet created: {parquet_path}")


if __name__ == "__main__":
    csv_to_parquet()