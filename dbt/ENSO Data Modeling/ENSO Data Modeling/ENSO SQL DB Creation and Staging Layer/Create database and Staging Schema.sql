/* ============================================================
   01 - Create database and Staging Schema
   ============================================================ */
IF DB_ID('ENSO_DB') IS NULL
    CREATE DATABASE ENSO_DB;
GO
ALTER DATABASE ENSO_DB SET RECOVERY SIMPLE;   -- smaller log during the 4.2M-row load
GO

USE ENSO_DB;
GO

IF SCHEMA_ID('staging') IS NULL EXEC('CREATE SCHEMA staging');   -- raw files as text
GO

SELECT name AS schema_name FROM sys.schemas WHERE name IN ('staging');
GO
