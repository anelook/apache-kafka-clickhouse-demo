Hands-on material for session "Optimal data lake for analytics: Apache Kafka and ClickHouse"
============================================================================================

Hello all! This repository contains a set of instructions how to send data from an `Apache Kafka <https://kafka.apache.org/>`_ topic to a table in `ClickHouse <https://clickhouse.com/>`_ and how to run aggregation operations on data in ClickHouse.

In this example we'll look at the educational system of Hogwarts. Every time a student enters a classroom an event is generated and sent to an Apache Kafka topic. The data is accumulated over years. We would like to store raw data long term in ClickHouse DBMS, shape it and send requests for data aggregation to efficiently analyse past data.

Preparation steps
------------------

To follow this session you'll need Apache Kafka and ClickHouse servers. I'll be setting up both of them on my local Mac machine. I'll leave the steps I do for a reference, however, you might need to adjust instructions if you're not Mac user.

Set up Apache Kafka cluster (locally on Mac)
++++++++++++++++++++++++++++++++++++++++++++
#. Install Apache Kafka with brew. I used `kafka homebrew formula <https://formulae.brew.sh/formula/kafka>`_.
#. Start Zookeeper by running ``/usr/local/bin/zookeeper-server-start /usr/local/etc/zookeeper/zoo.cfg``.
#. Start Apache Kafka by running ``/usr/local/bin/kafka-server-start /usr/local/etc/kafka/server.properties``.
#. Install `kcat <https://github.com/edenhill/kcat>`_. We'll use this tool to send data into the topic.
#. This repository contains a simple kcat.config, which will be enough if you're using Apache Kafka locally. Make sure that you're located at the repository's directory when running kcat commands.

You're ready to create and populate topics.

Set up ClickHouse cluster (using Docker)
++++++++++++++++++++++++++++++++++++++++++++
#. Pull Docker image ``docker pull clickhouse/clickhouse-server``, read more in `docker hub reference page <https://hub.docker.com/r/clickhouse/clickhouse-server/>`_.
#. Start server instance ``docker run -it --rm --link some-clickhouse-server:clickhouse-server clickhouse/clickhouse-client --host clickhouse-server``.
#. Most convenient way to run SQL queries is to use `ClickHouse native client <https://hub.docker.com/r/clickhouse/clickhouse-client>`_ . To connect to native client run ``run -it --rm --link some-clickhouse-server:clickhouse-server clickhouse/clickhouse-client --host clickhouse-server``.

You're ready to send requests to ClickHouse server, for example try

.. code:: sql

    SHOW TABLES

Unzip example data
+++++++++++++++++++

In this repository you can find two files with data which we'll use to inject into Apache Kafka topic: classes_years_2_12.ndjson.zip and classes_years_13_22.ndjson.zip. Unzip them to retrieve ndjson files. ndjson stands for *Newline Delimited JSON* and is used to store streaming structured data.

- **classes_years_2_12.ndjson** contains data for years 2002 - 2012 (2 615 075 items from 1030867200000 till 1368453600000)
- **classes_years_13_22.ndjson** contains data for years 2013 - 2022 (2 649 615 items from 1378022400000 till 1652450400000)

Data is based on following assumptions and simplifications:
There are 18 subjects, 3 classes per day. Educational year starts in September and finishes in May. Each student spends 7 years in Hogwarts.

Step # 1: create and populate a topic with class attendance data
-----------------------------------------------------------------
#. Create Apache Kafka topic ``kafka-topics --bootstrap-server localhost:9092 --topic class-attendance --create``.
#. Populate topic with the content of **classes_years_2_12.ndjson** by running ``kcat -F kcat.config -P -t classes-attendance < classes_years_2_12.ndjson``.

Step # 2: Bring data from the topic into ClickHouse table
------------------------------------------------------------
To bring the data from an Apache Kafka topic into ClickHouse we'll use a `built-in ClickHouse engine for Apache Kafka <https://clickhouse.com/docs/en/engines/table-engines/integrations/kafka/>`_. To link it to the destination table we'll create a materialized view

1. Create ClickHouse Kafka engine table. We use **JSONAsString** to have granular control of each property later. Alternatively you can try **JSONEachRow**, but pay attention to complex json objects.

.. code:: sql

    CREATE TABLE class_attendance_queue
    (
        `message` String
    )
    ENGINE = Kafka
    SETTINGS
        kafka_broker_list = 'host.docker.internal:9092',
        kafka_topic_list = 'class-attendance',
        kafka_group_name = 'group1',
        kafka_format = 'JSONAsString'

2. Create the destination table where the data should be stored

.. code:: sql

    CREATE TABLE class_attendance
    (
        `timestamp` DateTime,
        `subject` String,
        `teacher` String,
        `room` String,
        `points` Int8,
        `student` Tuple(name String, house String)
    )
    ENGINE = MergeTree
    ORDER BY timestamp

3. Create materialised view to establish connection with ClickHouse Kafka Engine:

.. code:: sql

    CREATE MATERIALIZED VIEW materialized_view TO class_attendance
    AS SELECT
        fromUnixTimestamp64Milli(JSONExtractUInt(message, 'timestamp')) AS timestamp,
        JSONExtractString(message, 'subject') AS subject,
        JSONExtractString(message, 'teacher') AS teacher,
        JSONExtractString(message, 'room') AS room,
        toInt8(JSONExtractInt(message, 'points')) AS points,
        JSONExtract(message, 'student', 'Tuple(String,String)') AS student
    FROM class_attendance_queue

4. Test that you have the data:

.. code:: sql

    SELECT count(*) FROM class_attendance

Step # 3: Transform data into another table
--------------------------------------------
1. Create a new destination table of type MergeTree

.. code:: sql

    CREATE TABLE student_presence
    (
        `timestamp` DateTime,
        `subject` String,
        `studentCount` UInt16
    )
    ENGINE = MergeTree
    ORDER BY timestamp

2. Create a new destination table of type MergeTree

.. code:: sql

    CREATE MATERIALIZED VIEW student_presence_mv
    TO student_presence
    AS SELECT
        timestamp,
        subject,
        count(student) AS studentCount
    FROM class_attendance
    GROUP BY (timestamp, subject)
    ORDER BY timestamp ASC

3. If you run a query below, it will return 0 lines.

.. code:: sql

    SELECT count(*) FROM default.student_presence

 This is because by design materialised views will pull only new data from the source table. For the sake of our demo you can either add more data into the Apahce Kafka topic **class-attendance** or you can copy old lines manually from **class_attendance** into **student_presence** by running

.. code:: sql

    INSERT INTO student_presence
    SELECT
        timestamp,
        subject,
        count(student) AS studentCount
    FROM class_attendance
    GROUP BY (timestamp, subject)

4. Now you can see number of all rows by running

.. code:: sql

    SELECT count(*) FROM default.student_presence


Step # 4: Use AggregateFunction and SummingMergeTree
-----------------------------------------------------
1. Create a destination table of type SummingMergeTree

.. code:: sql

    CREATE TABLE student_aggregates_daily
    (
        `day` DateTime,
        `subject` String,
        `max_interm_state` AggregateFunction(max, UInt16),
        `min_interm_state` AggregateFunction(min, UInt16),
        `avg_interm_state` AggregateFunction(avg, UInt16)
    )
    ENGINE = SummingMergeTree
    PARTITION BY tuple()
    ORDER BY (day, subject)

2. Create a materialized view and use maxState

.. code:: sql

    CREATE MATERIALIZED VIEW student_aggregates_daily_mv TO student_aggregates_daily AS
    SELECT
        toStartOfDay(timestamp) AS day,
        subject,
        maxState(studentCount) AS max_intermediate_state,
        minState(studentCount) AS min_intermediate_state,
        avgState(studentCount) AS avg_intermediate_state
    FROM default.student_presence
    GROUP BY
        day,
        subject
    ORDER BY
        day ASC,
        subject ASC

3. As mentioned before, materialized view will send only new records into the destination table, so if you want to bring existing records, run:

.. code:: sql

    INSERT INTO student_aggregates_daily
    SELECT
      toStartOfDay(timestamp) as day,
      subject,
      maxState(studentCount) AS max_intermediate_state,
      minState(studentCount) AS min_intermediate_state,
      avgState(studentCount) AS avg_intermediate_state
    FROM default.student_presence
    GROUP BY day, subject
    ORDER BY day, subject

4. maxState, minState and avgState calculate intermediate values, and by themselves they don't bring any value. You can try retrieving first 10 lines to see that there is no readable values in this table.

.. code:: sql

    SELECT * FROM default.student_aggregates_daily LIMIT 10

To properly select the aggregated data run

.. code:: sql

    SELECT
      day,
      subject,
      maxMerge(max_intermediate_state) AS max,
      minMerge(min_intermediate_state) AS min,
      avgMerge(avg_intermediate_state) AS avg
    FROM student_aggregates_daily23
    GROUP BY (day, subject)
    ORDER BY (day, subject)

Resources and additional materials
----------------------------------
#. `Official docs for Apache Kafka <https://kafka.apache.org/>`_.
#. `Official docs for ClickHouse <https://clickhouse.com/docs/en/intro>`_.
#. How to start working with `Aiven for ClickHouse® <https://developer.aiven.io/docs/products/clickhouse/getting-started>`_.
#. `ClickHouse Kafka engine <https://clickhouse.com/docs/en/engines/table-engines/integrations/kafka>`_.
#. `Approximate calculations <https://clickhouse.com/docs/en/sql-reference/statements/select/sample/>`_.
#. `Array functions <https://clickhouse.com/docs/en/sql-reference/functions/array-functions/>`_.
#. `Cloudflare experience: ClickHouse Capacity Estimation Framework <https://blog.cloudflare.com/clickhouse-capacity-estimation-framework/>`_.
#. Benchmarking
    #. `ClickHouse benchmark data collection <https://clickhouse.com/benchmark/dbms/>`_.
    #. `Altinity benchmarks <https://altinity.com/benchmarks/>`_.
    #. `1.1 Billion Taxi Rides <https://tech.marksblogg.com/billion-nyc-taxi-rides-clickhouse-cluster.html>`_.
    #. `Benchmarks comparing QuestDB to InfluxDB, ClickHouse and TimescaleDB <https://questdb.io/blog/2021/05/10/questdb-release-6-0-tsbs-benchmark/>`_.
#.  `Example data sets <https://clickhouse.com/docs/en/getting-started/example-datasets/>`_.




License
-------
This work is licensed under the Apache License, Version 2.0. Full license text is available in the LICENSE file and at http://www.apache.org/licenses/LICENSE-2.0.txt