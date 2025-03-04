#There's an input JSON value like-
#{"task_type" : "CDM", "table_name" : "CDM1", "start_date" : "2024-01-01", "end_date" : "2024-06-30", frequency: "Monthly"},
#{"task_type": "CDM", "table_name": "CDM2", "start_date": "2024-06-15", "end_date": "2024-06-20",
#frequency: "Daily"), {"task_type": "RDM", "table_name": "RDM1", "start_date": "2025-01-04", "end_date": "2024-01-31", frequency: "Weekly"},
#{"task_type": "RDM", "table_name": "RDM1", "start_date": "2024-01-01", "end_date": "2024-06-30", frequency: "Daily"}
#You can create a variable & assign this value manually to it for now.
#Use this in such a way, that these JSON values can be ingested in a temp table as individual rows. Then for all these row, extract the JSON to get each specified value like task_type,table_name,etc. of a JSON in respective columns.


-----

WITH RAW_DATA AS (
    SELECT '''
    [
        {"task_type": "CDM", "table_name": "CDM1", "start_date": "2024-01-01", "end_date": "2024-06-30", "frequency": "Monthly"},
        {"task_type": "CDM", "table_name": "CDM2", "start_date": "2024-06-15", "end_date": "2024-06-20", "frequency": "Daily"},
        {"task_type": "RDM", "table_name": "RDM1", "start_date": "2025-01-04", "end_date": "2025-01-31", "frequency": "Weekly"},
        {"task_type": "RDM", "table_name": "RDM2", "start_date": "2024-01-01", "end_date": "2024-06-30", "frequency": "Daily"}
    ]
    ''' AS JSON_DATA
),
PARSED_DATA AS (
    SELECT 
        JSON_VALUE(ITEM, '$.task_type') AS TASK_TYPE,
        JSON_VALUE(ITEM, '$.table_name') AS TABLE_NAME,
        DATE(JSON_VALUE(ITEM, '$.start_date')) AS START_DATE,
        DATE(JSON_VALUE(ITEM, '$.end_date')) AS END_DATE,
        JSON_VALUE(ITEM, '$.frequency') AS FREQUENCY
    FROM RAW_DATA, UNNEST(JSON_QUERY_ARRAY(JSON_DATA)) AS ITEM
),
-- CDM Expansion (Monthly & Daily)
EXPANDED_CDM AS (
    -- Monthly Frequency (One Unique Record per Month)
    SELECT 
        TABLE_NAME,
        FORMAT_DATE('%d-%m-%Y', DATE_ADD(DATE_TRUNC(START_DATE, MONTH), INTERVAL MONTH_OFFSET MONTH)) AS START_DATE,
        FORMAT_DATE('%d-%m-%Y', LAST_DAY(DATE_ADD(DATE_TRUNC(START_DATE, MONTH), INTERVAL MONTH_OFFSET MONTH))) AS END_DATE,
        'Monthly' AS FREQUENCY
    FROM PARSED_DATA, 
    UNNEST(GENERATE_ARRAY(0, DATE_DIFF(END_DATE, START_DATE, MONTH))) AS MONTH_OFFSET
    WHERE TASK_TYPE = 'CDM' AND FREQUENCY = 'Monthly'

    UNION ALL

    -- Daily Frequency (One Record per Day)
    SELECT 
        TABLE_NAME,
        FORMAT_DATE('%d-%m-%Y', DATE_ADD(START_DATE, INTERVAL DAY_OFFSET DAY)) AS START_DATE,
        FORMAT_DATE('%d-%m-%Y', DATE_ADD(START_DATE, INTERVAL DAY_OFFSET DAY)) AS END_DATE,
        'Daily' AS FREQUENCY
    FROM PARSED_DATA,
    UNNEST(GENERATE_ARRAY(0, DATE_DIFF(END_DATE, START_DATE, DAY))) AS DAY_OFFSET
    WHERE TASK_TYPE = 'CDM' AND FREQUENCY = 'Daily'
),
-- RDM Expansion (Weekly & Other)
EXPANDED_RDM AS (
    -- Weekly Frequency (Saturday–Friday Segmentation, Fixed INT64 Issue)
    SELECT 
        TABLE_NAME,
        FORMAT_DATE('%d-%m-%Y', DATE_ADD(DATE_TRUNC(START_DATE, WEEK(SATURDAY)), INTERVAL CAST(WEEK_OFFSET * 7 AS INT64) DAY)) AS START_DATE,
        FORMAT_DATE('%d-%m-%Y', LEAST(DATE_ADD(DATE_TRUNC(START_DATE, WEEK(SATURDAY)), INTERVAL CAST(WEEK_OFFSET * 7 + 6 AS INT64) DAY), END_DATE)) AS END_DATE,
        'Weekly' AS FREQUENCY
    FROM PARSED_DATA,
    UNNEST(GENERATE_ARRAY(0, FLOOR(DATE_DIFF(END_DATE, DATE_TRUNC(START_DATE, WEEK(SATURDAY)), DAY) / 7))) AS WEEK_OFFSET
    WHERE TASK_TYPE = 'RDM' AND FREQUENCY = 'Weekly'

    UNION ALL

    -- Other RDM Frequencies (No Change)
    SELECT 
        TABLE_NAME,
        FORMAT_DATE('%d-%m-%Y', START_DATE) AS START_DATE,
        FORMAT_DATE('%d-%m-%Y', END_DATE) AS END_DATE,
        FREQUENCY
    FROM PARSED_DATA
    WHERE TASK_TYPE = 'RDM' AND FREQUENCY != 'Weekly'
)
-- Display Final Output
SELECT * FROM EXPANDED_CDM
UNION ALL
SELECT * FROM EXPANDED_RDM
ORDER BY TABLE_NAME, PARSE_DATE('%d-%m-%Y', START_DATE);
