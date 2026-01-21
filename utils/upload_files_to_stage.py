import os
from utils.snowflake_connector import SnowflakeConnection

sf = SnowflakeConnection()

def upload_files_to_stage(folder_path, stage_name, subdirectory=None):
    sf.connect()

    try:
        with sf.get_cursor() as cursor:
            # Check context
            cursor.execute("SELECT CURRENT_ROLE(), CURRENT_DATABASE(), CURRENT_SCHEMA()")
            role, db, schema = cursor.fetchone()
            print(f"Context: Role={role}, DB={db}, Schema={schema}")

            # Get absolute path
            base_dir = os.path.dirname(os.path.abspath(__file__))
            folder_path = os.path.abspath(os.path.join(base_dir, "..", folder_path))

            if not os.path.isdir(folder_path):
                raise FileNotFoundError(f"Folder not found: {folder_path}")

            # Convert to forward slashes for Snowflake
            folder_path_snowflake = folder_path.replace("\\", "/")

            # Build stage path
            if subdirectory:
                subdirectory = subdirectory.strip("/")
                stage_path = f"@{stage_name}/{subdirectory}/"
            else:
                stage_path = f"@{stage_name}/"

            print(f"\n🎯 Target stage: {stage_path}")

            # PUT command
            put_sql = f"PUT 'file://{folder_path_snowflake}/*' {stage_path}"

            put_sql = f"""
                PUT 'file://{folder_path_snowflake}/*'
                {stage_path}
                AUTO_COMPRESS = FALSE
                OVERWRITE = TRUE
                PARALLEL = 4
            """

            cursor.execute(put_sql)
            result = cursor.fetchall()

    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()

    finally:
        sf.close()

# Run the upload
file_names = ['billing_transactions.parquet', 'diagnoses.parquet', 'encounters.parquet', 'facilities.parquet', 'hospitals.parquet',
                  'patients.parquet', 'payers.parquet', 'procedures.parquet', 'providers.parquet']
upload_file_to_stage(folder_path="data/restaurant", stage_name="BRONZE.CSV_STG",subdirectory="restaurant")
upload_file_to_stage(folder_path="data/order_item", stage_name="BRONZE.CSV_STG",subdirectory="order_item")
upload_file_to_stage(folder_path="data/menu", stage_name="BRONZE.CSV_STG",subdirectory="menu")
upload_file_to_stage(folder_path="data/login_audit", stage_name="BRONZE.CSV_STG",subdirectory="login_audit")
upload_file_to_stage(folder_path="data/location", stage_name="BRONZE.CSV_STG",subdirectory="location")
upload_file_to_stage(folder_path="data/order", stage_name="BRONZE.CSV_STG",subdirectory="order")
upload_file_to_stage(folder_path="data/delivery_agent", stage_name="BRONZE.CSV_STG",subdirectory="delivery_agent")
upload_file_to_stage(folder_path="data/delivery", stage_name="BRONZE.CSV_STG",subdirectory="delivery")
upload_file_to_stage(folder_path="data/customer", stage_name="BRONZE.CSV_STG",subdirectory="customer")
upload_file_to_stage(folder_path="data/customer_address", stage_name="BRONZE.CSV_STG",subdirectory="customer_address")