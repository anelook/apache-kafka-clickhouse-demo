Hands-on material for session "Apache Kafka and ClickHouse"
============================================================================================

Hello all! This repository contains a set of instructions explaining how to work with a combination of Apache Kafka and ClickHouse. In particular, we'll look at how to send data from an `Apache Kafka <https://kafka.apache.org/>`_ topic to a table in `ClickHouse <https://clickhouse.com/>`_, how to transform the data with the help of ClickHouse materialized views and how to run aggregation requests.

We'll take the educational system of Hogwarts as an idea for our scenario. Every time a student enters a classroom an event is generated and sent to an Apache Kafka topic. The data is accumulated over years. We would like to send the raw data from this topic into ClickHouse for long term storage, shape it and send requests for data aggregation to efficiently analyse past data.

Preparation steps
------------------

To follow these steps you'll need running instances of Apache Kafka and ClickHouse. I'll be running both of them on my local machine.

You can find instructions on how to set up both of the instances in the `quick start for ClickHouse <https://clickhouse.com/docs/en/quick-start>`_ and `quick start for Apache Kafka <https://kafka.apache.org/quickstart>`_

If you're using a mac machine, you can also use the instructions below:

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

In this repository you can find two files containing data for our experiments: events_years_2_12.ndjson.zip and events_years_2_12.ndjson.zip. Unzip them to retrieve ndjson files. NDJSON stands for *Newline Delimited JSON* and is used to store streaming structured data.

- **events_years_2_12.ndjson** contains data for years 2002 - 2012 (2 615 075 items from 1030867200000 till 1368453600000)
- **events_years_2_12.ndjson** contains data for years 2013 - 2022 (2 649 615 items from 1378022400000 till 1652450400000)

Data is based on following assumptions and simplifications:
There are 18 subjects, 3 classes per day. Educational year starts in September and finishes in May. Each student spends 7 years in Hogwarts.

Step # 1: create and populate a topic with class attendance data
-----------------------------------------------------------------
#. Create Apache Kafka topic ``kafka-topics --bootstrap-server localhost:9092 --topic class-attendance --create``.
#. Populate topic with the content of the first file **events_years_2_12.ndjson** by running ``kcat -F kcat.config -P -t classes-attendance < events_years_2_12.ndjson``. This will add first half of our data as a bulk.
#. Run `send_data`, this script will send messages from the second file one by one, imitating a data flow into the topic.

Step # 2: Bring data from the topic into ClickHouse table
------------------------------------------------------------
We'll use a `built-in ClickHouse engine for Apache Kafka <https://clickhouse.com/docs/en/engines/table-engines/integrations/kafka/>`_ and `a materialized view <https://clickhouse.com/docs/en/guides/developer/working-with-json/json-other-approaches#using-materialized-views>` .

1. In the ClickHouse client run SQL statement to create a Kafka engine table. For data format we use **JSONAsString** to have a granular control on transforming every property. Alternatively you can try **JSONEachRow**.

.. code:: sql

    CREATE TABLE entry_event_queue
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

    CREATE TABLE student_entry_event
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

3. Create materialised view to establish connection between the Kafka Engine and the destination table:

.. code:: sql

    CREATE MATERIALIZED VIEW materialized_view TO student_entry_event
    AS SELECT
        fromUnixTimestamp64Milli(JSONExtractUInt(message, 'timestamp')) AS timestamp,
        JSONExtractString(message, 'subject') AS subject,
        JSONExtractString(message, 'teacher') AS teacher,
        JSONExtractString(message, 'room') AS room,
        toInt8(JSONExtractInt(message, 'points')) AS points,
        JSONExtract(message, 'student', 'Tuple(String,String)') AS student
    FROM entry_event_queue

4. Test that you have the data:

.. code:: sql

    SELECT count(*) FROM student_entry_event


.. code:: sql

    SELECT student.house as house, sum(points)
    FROM default.student_entry_event
    GROUP BY student.house


Step # 3: Transform data into another table
--------------------------------------------
In this step our goal is to transform and aggregate data coming from ``student_entry_event`` (source table), and store new information in a table ``class_attendance_granular``(destination table).

Because the data is continuously flowing into the source table, we need to be careful not to miss any items when processing requests for the destination table. To  overcome this challenge, we'll select a timestamp in the future. Based on this timestamp we create a materialized view, and the old items we'll copy with the insert with the help of INSERT statement.

1. Create a new destination table of a type MergeTree

.. code:: sql

    CREATE TABLE class_attendance_granular
    (
        `timestamp` DateTime,
        `subject` String,
        `studentCount` UInt16
    )
    ENGINE = MergeTree
    ORDER BY timestamp

2. Check what is the timestamp of the latest event in the source table

.. code:: sql

    SELECT timestamp
    FROM default.student_entry_event
    ORDER BY timestamp DESC
    LIMIT 1

3. Select a timestamp a bit farther in the future (you can use 1 or 2 days into the future, our data is moving fast enough)


4.Create a materialized view

.. code:: sql

    CREATE MATERIALIZED VIEW default.materialized_view_class_attendance_granular TO default.class_attendance_granular
    AS SELECT
      timestamp,
      subject,
      count(student) as studentCount
    FROM default.student_entry_event
    WHERE timestamp >= 'use-your-future-time-stamp-here'
    Group by (timestamp, subject)
    ORDER BY timestamp;

5. Wait till you cross that date

6. Verify that the data is flowing

.. code:: sql

    SELECT count(*) FROM default.class_attendance_granular

You should see low numbers of fresh data coming into the destination table (data starting from your selected timestamp)

7. Copy the old data from the source table with a help of INSERT statement

.. code:: sql

    INSERT INTO default.class_attendance_granular
    SELECT
      timestamp,
      subject,
      count(student) as studentCount
    FROM default.student_entry_event
    WHERE timestamp < 'use-your-future-time-stamp-here'
    GROUP BY (timestamp, subject)

4. Now you can see number of all rows by running

.. code:: sql

    SELECT count(*) FROM default.class_attendance_granular


Step # 4: Use AggregateFunction and SummingMergeTree
-----------------------------------------------------
Similar to the previous step, but now using a table that includes aggregate functions.
We'll pre-aggregate data about maximum/minimum/average students in a class.

1. Create a destination table of type SummingMergeTree

.. code:: sql

    CREATE TABLE class_attendance_daily
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

    CREATE MATERIALIZED VIEW class_attendance_daily_mv TO class_attendance_daily AS
    SELECT
        toStartOfDay(timestamp) AS day,
        subject,
        maxState(studentCount) AS max_intermediate_state,
        minState(studentCount) AS min_intermediate_state,
        avgState(studentCount) AS avg_intermediate_state
    FROM default.class_attendance_granular
    WHERE timestamp >= 'use-your-future-time-stamp-here'
    GROUP BY
        day,
        subject
    ORDER BY
        day ASC,
        subject ASC

3. The materialized view will only process new records, so if you want to bring old records, run:

.. code:: sql

    INSERT INTO class_attendance_daily
    SELECT
      toStartOfDay(timestamp) as day,
      subject,
      maxState(studentCount) AS max_intermediate_state,
      minState(studentCount) AS min_intermediate_state,
      avgState(studentCount) AS avg_intermediate_state
    FROM default.class_attendance_granular
    WHERE timestamp < 'use-your-future-time-stamp-here'
    GROUP BY day, subject
    ORDER BY day, subject

4. **maxState**, **minState** and **avgState** calculate intermediate values, and by themselves they don't bring any value. You can try retrieving first 10 lines to see that there is no readable values in those columns.

.. code:: sql

    SELECT * FROM default.class_attendance_daily LIMIT 10

To properly select the aggregated data we need to merge it back:

.. code:: sql

    SELECT
      day,
      subject,
      maxMerge(max_intermediate_state) AS max,
      minMerge(min_intermediate_state) AS min,
      avgMerge(avg_intermediate_state) AS avg
    FROM class_attendance_daily
    GROUP BY (day, subject)
    ORDER BY (day, subject)

Resources and additional materials
----------------------------------
#. `Official docs for Apache Kafka <https://kafka.apache.org/>`_.
#. `Official docs for ClickHouse <https://clickhouse.com/docs/en/intro>`_.
#. `Distinctive Features of ClickHouse <https://clickhouse.com/docs/en/about-us/distinctive-features>`_.
#. How to start working with `Aiven for ClickHouse® <https://developer.aiven.io/docs/products/clickhouse/getting-started>`_.
#. `ClickHouse Kafka engine <https://clickhouse.com/docs/en/engines/table-engines/integrations/kafka>`_.
#. `Using Materialized Views <https://clickhouse.com/docs/en/guides/developer/working-with-json/json-other-approaches#using-materialized-views>`_.
#. `Approximate calculations <https://clickhouse.com/docs/en/sql-reference/statements/select/sample/>`_.
#. `Array functions <https://clickhouse.com/docs/en/sql-reference/functions/array-functions/>`_.
#. `Cloudflare experience: ClickHouse Capacity Estimation Framework <https://blog.cloudflare.com/clickhouse-capacity-estimation-framework/>`_.
#. Benchmarking
    #. `ClickHouse benchmark data collection <https://clickhouse.com/benchmark/dbms/>`_.
    #. `Altinity benchmarks <https://altinity.com/benchmarks/>`_.
    #. `1.1 Billion Taxi Rides <https://tech.marksblogg.com/billion-nyc-taxi-rides-clickhouse-cluster.html>`_.
    #. `Benchmarks comparing QuestDB to InfluxDB, ClickHouse and TimescaleDB <https://questdb.io/blog/2021/05/10/questdb-release-6-0-tsbs-benchmark/>`_.
#.  `A variety of example data sets <https://clickhouse.com/docs/en/getting-started/example-datasets/>`_.


License
-------
This work is licensed under the Apache License, Version 2.0. Full license text is available in the LICENSE file and at http://www.apache.org/licenses/LICENSE-2.0.txt
