from pyspark.sql import SparkSession
from pyspark.sql.functions import from_json, col, sqrt, window, avg, lit, struct, to_json, when
from pyspark.sql.types import StructType, StructField, LongType, StringType, DoubleType, IntegerType, TimestampType

# Constants for activity classification - FINALIZED BASED ON USER TUNING
STATIONARY_THRESHOLD = 2.0
WALKING_THRESHOLD = 8.0
RUNNING_THRESHOLD = 20.0 
# SPRINTING is >= RUNNING_THRESHOLD

# Window settings - Reflecting user's latest changes
WINDOW_DURATION = "10 seconds"
SLIDE_DURATION = "2 seconds" # User updated
WATERMARK_DELAY = "10 seconds"

# Initialize Spark
spark = SparkSession.builder \
    .appName("ActivityDetection") \
    .config("spark.jars.packages", "org.apache.spark:spark-sql-kafka-0-10_2.12:3.3.0") \
    .getOrCreate()

# Schema for incoming Kafka messages
schema = StructType([
    StructField("messageId", LongType()),
    StructField("sessionId", StringType()),
    StructField("deviceId", StringType()),
    StructField("sensorType", StringType()),
    StructField("x", DoubleType()),
    StructField("y", DoubleType()),
    StructField("z", DoubleType()),
    StructField("accuracy", IntegerType()),
    StructField("timestamp", LongType())  # Nanoseconds
])

try:
    print("Attempting to read from Kafka...")
    kafka_df = spark.readStream \
        .format("kafka") \
        .option("kafka.bootstrap.servers", "kafka:29092") \
        .option("subscribe", "raw_sensor_data") \
        .option("failOnDataLoss", "false") \
        .option("startingOffsets", "earliest") \
        .load()
    print("Successfully created kafka_df DataFrame.")

    # Debug: Print raw data directly from Kafka (before parsing) - COMMENTED OUT
    # raw_kafka_debug_query = kafka_df.selectExpr(
    #     "CAST(key AS STRING)", 
    #     "CAST(value AS STRING)", 
    #     "topic", 
    #     "partition", 
    #     "offset", 
    #     "timestamp", 
    #     "timestampType"
    # ).writeStream \
    #     .format("console") \
    #     .outputMode("append") \
    #     .option("truncate", "false") \
    #     .start()
    # print("raw_kafka_debug_query started.")

    # Parse JSON and preprocess data
    print("Attempting to parse JSON...")
    parsed_df = kafka_df.select(
        from_json(col("value").cast("string"), schema).alias("data")
    ).select(
        col("data.messageId"),
        col("data.sessionId"),
        col("data.deviceId"),
        col("data.sensorType"),
        col("data.x"),
        col("data.y"),
        col("data.z"),
        (col("data.timestamp") / 1e9).cast(TimestampType()).alias("timestamp")
    )
    print("parsed_df DataFrame created.")

    # Filter for standard accelerometer data only
    print("Attempting to filter for accelerometer data...")
    filtered_df = parsed_df.filter(
        col("sensorType") == "accelerometer"
    )
    print("filtered_df DataFrame created.")

    # Debug: Print filtered parsed data from Kafka - COMMENTED OUT (user had this commented)
    # parsed_query = filtered_df.writeStream \
    #     .format("console") \
    #     .outputMode("append") \
    #     .option("truncate", False) \
    #     # .start() # User had this commented
    # print("parsed_query (from filtered_df) started.")

    # Compute magnitude of acceleration
    print("Attempting to compute magnitude...")
    magnitude_df = filtered_df.withColumn(
        "magnitude",
        sqrt(col("x")**2 + col("y")**2 + col("z")**2)
    )
    print("magnitude_df DataFrame created.")

    # Debug: Print data with computed magnitude - COMMENTED OUT
    # magnitude_query = magnitude_df.select("magnitude").writeStream \
    #     .format("console") \
    #     .outputMode("append") \
    #     .option("truncate", False) \
    #     .start()
    # print("magnitude_query (showing only magnitude) started. Waiting for data or termination...")
    
    # Windowed aggregation to get average magnitude - RE-ENABLED
    print("Attempting windowed aggregation for average magnitude...")
    windowed_avg_magnitude_df = magnitude_df \
        .withWatermark("timestamp", WATERMARK_DELAY) \
        .groupBy(
            window(col("timestamp"), WINDOW_DURATION, SLIDE_DURATION),
            col("sessionId"), 
            col("deviceId")   
        ).agg(
            avg("magnitude").alias("avg_magnitude")
        )
    print("windowed_avg_magnitude_df DataFrame created.")

    # Debug: Print windowed average magnitude - COMMENTED OUT
    # avg_magnitude_debug_query = windowed_avg_magnitude_df.select(
    #     col("window.start"), 
    #     col("window.end"), 
    #     col("sessionId"), 
    #     col("deviceId"), 
    #     col("avg_magnitude")
    # ).writeStream \
    #     .format("console") \
    #     .outputMode("update") \
    #     .option("truncate", False) \
    #     .start()
    # print("avg_magnitude_debug_query started.")

    # Classify activity based on average magnitude - UPDATED WITH FINAL THRESHOLDS
    print("Attempting to classify activity...")
    activity_df = windowed_avg_magnitude_df.withColumn(
        "activity",
        when(col("avg_magnitude") < STATIONARY_THRESHOLD, "stationary")
        .when(col("avg_magnitude") < WALKING_THRESHOLD, "walking")
        .when(col("avg_magnitude") < RUNNING_THRESHOLD, "running")
        .otherwise("sprinting")
    ).withColumn(
        "confidence", # Placeholder confidence
        when(col("avg_magnitude") < STATIONARY_THRESHOLD, 0.95)
        .when(col("avg_magnitude") < WALKING_THRESHOLD, 0.85)
        .when(col("avg_magnitude") < RUNNING_THRESHOLD, 0.75)
        .otherwise(0.70)
    ).select(
        col("window.end").alias("event_timestamp"),
        col("sessionId"), 
        col("deviceId"),  
        col("activity"),
        col("confidence"),
        col("avg_magnitude")
    )
    print("activity_df DataFrame created.")

    # Prepare for Kafka output (JSON string) - RE-ENABLED
    print("Preparing data for Kafka output...")
    kafka_output_df = activity_df.select(
        to_json(struct(
            col("event_timestamp").cast("string").alias("timestamp"),
            col("sessionId"),
            col("deviceId"),
            col("activity"),
            col("confidence"),
            col("avg_magnitude")
        )).alias("value")
    )
    print("kafka_output_df DataFrame created.")

    # Write classified activities to Kafka - RE-ENABLED
    print("Starting Kafka sink query...")
    kafka_sink_query = kafka_output_df.writeStream \
        .format("kafka") \
        .option("kafka.bootstrap.servers", "kafka:29092") \
        .option("topic", "processed_activity") \
        .option("checkpointLocation", "/tmp/checkpoint/activity_detection_kafka") \
        .outputMode("append") \
        .start()
    print("Kafka sink query started.")

    # Await termination on the main Kafka sink query
    print("Awaiting termination of kafka_sink_query...")
    kafka_sink_query.awaitTermination()
    
    # If you want to run both Kafka sink and debug, and await any, you might need:
    # spark.streams.awaitAnyTermination()
    # For now, we are focusing on observing avg_magnitude for retuning thresholds.
    # So, kafka_sink_query.awaitTermination() is effectively paused.

except Exception as e:
    print(f"Critical error in Spark Streaming job: {str(e)}")
    import traceback
    traceback.print_exc()
    spark.stop() # Ensure Spark stops on error
    raise

print("Spark script execution finished or an unhandled exception occurred if this is the last message before exit.")