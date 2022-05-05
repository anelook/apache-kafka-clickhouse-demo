Hands-on material for session "Optimal data lake for analytics: Apache Kafka and ClickHouse"
============================================================================================

Hello all! This repository contains a set of instructions how to send data from an `Apache Kafka <https://kafka.apache.org/>`_ topic to a table in `ClickHouse <https://clickhouse.com/>`_ and how to run aggregation operations on data in ClickHouse.

In this example we'll look at the educational system of Hogwarts. Every time a student enters a classroom an event is generated and sent to an Apache Kafka topic. The data is accumulated over years. We would like to store raw data long term in ClickHouse DBMS, shape it and send requests for data aggregation to efficiently analyse past data.

Preparation steps
------------------

To follow this session you'll need Apache Kafka and ClickHouse servers. I'll be setting up both of them on my local Mac machine. I'll leave the steps I do for a reference, however, you might need to adjust instructions if you're not Mac user.

Set up Apache Kafka cluster (locally on Mac)
++++++++++++++++++++++++++++++++++++++++++++
#. Install Apache Kafka with brew. I used `kafka homebrew formulae <https://formulae.brew.sh/formula/kafka>_`.
#. Start Zookeeper by running `/usr/local/bin/zookeeper-server-start /usr/local/etc/zookeeper/zoo.cfg`.
#. Start Apache Kafka by running `/usr/local/bin/kafka-server-start /usr/local/etc/kafka/server.properties`.

You're ready to create and populate topics.

Set up ClickHouse cluster (using Docker)
++++++++++++++++++++++++++++++++++++++++++++
#. Pull Docker image `docker pull clickhouse/clickhouse-server`, read more in `docker hub reference page <https://hub.docker.com/r/clickhouse/clickhouse-server/>`.
#. Start server instance `docker run -it --rm --link some-clickhouse-server:clickhouse-server clickhouse/clickhouse-client --host clickhouse-server`.
#. Most convenient way to run SQL queries is to use `ClickHouse native client <https://hub.docker.com/r/clickhouse/clickhouse-client>`_ . To connect to native client run `run -it --rm --link some-clickhouse-server:clickhouse-server clickhouse/clickhouse-client --host clickhouse-server`.

You're ready to send requests to ClickHouse server, for example try

.. sql::

    SHOW TABLES

Unzip example data
+++++++++++++++++++

In this repository you can find two files with data which we'll use to inject into Apache Kafka topic: classes_years_2_12.ndjson.zip and classes_years_13_22.ndjson.zip. Unzip them to retrieve ndjson files. ndjson stands for *Newline Delimited JSON* and is used to store streaming structured data.

- `classes_years_2_12.ndjson` contains data for years 2002 - 2012
- `classes_years_13_22.ndjson` contains data for years 2013 - 2022


Step # 1: create and populate a topic with class attendance data
-----------------------------------------------------------------
#. Create Apache Kafka topic `kafka-topics --bootstrap-server localhost:9092 --topic class-attendance --create`.
#.


Step # 2: Bring data from the topic into ClickHouse table
------------------------------------------------------------


Resources and additional materials
----------------------------------
#. `Official docs for Apache Kafka <https://kafka.apache.org/>`_.
#. `Official docs for ClickHouse <https://clickhouse.com/docs/en/intro>`_.


License
-------

This work is licensed under the Apache License, Version 2.0. Full license text is available in the LICENSE file and at http://www.apache.org/licenses/LICENSE-2.0.txt