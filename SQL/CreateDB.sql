USE [master]
GO

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SlackDW')
BEGIN
	CREATE DATABASE SlackDW;
END
GO

USE [SlackDW]
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'stage')
BEGIN
	EXEC('CREATE SCHEMA stage AUTHORIZATION dbo;')
END
GO