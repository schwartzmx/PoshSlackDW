USE [SlackDW]
GO

IF OBJECT_ID('stage.Channel') IS NOT NULL
	DROP TABLE stage.[Channel];
GO
CREATE TABLE [stage].[Channel](
	[ID] [nvarchar](255) NOT NULL PRIMARY KEY CLUSTERED,
	[Name] [nvarchar](255) NULL,
	[IsDeleted] [NVARCHAR](10) NULL,
	[EpochCreateDate] [nvarchar](255) NULL,
	[CreatorMemberID] [nvarchar](255) NULL,
	[IsArchived] [NVARCHAR](10) NULL,
	[IsGeneral] [NVARCHAR](10) NULL,
	[IsMember] [NVARCHAR](10) NULL,
	[Topic] [nvarchar](255) NULL,
	[TopicCreatorMemberID] [nvarchar](255) NULL,
	[Purpose] [nvarchar](255) NULL,
	[PurposeCreatorMemberID] [nvarchar](255) NULL
) ON [PRIMARY]

GO

IF OBJECT_ID('stage.ChannelMember') IS NOT NULL
	DROP TABLE stage.[ChannelMember];
GO
CREATE TABLE stage.[ChannelMember] (
	[RID] INT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    [MemberID] nvarchar(255),
    [ChannelID] nvarchar(255)
) ON [PRIMARY]
GO

IF OBJECT_ID('stage.Member') IS NOT NULL
	DROP TABLE [stage].[Member];
GO
CREATE TABLE stage.[Member](
	[ID] NVARCHAR(255) NOT NULL PRIMARY KEY CLUSTERED,
	[Name] [NVARCHAR](255) NULL,
	[IsDeleted] [NVARCHAR](10) NULL,
	[RealName] [NVARCHAR](255) NULL,
	[TimeZone] [NVARCHAR](255) NULL,
	[Email] [NVARCHAR](255) NULL,
	[ImageURL] [NVARCHAR](255) NULL,
	[IsAdmin] [NVARCHAR](10) NULL,
	[IsOwner] [NVARCHAR](10) NULL,
	[IsPrimaryOwner] [NVARCHAR](10) NULL,
	[IsBot] [NVARCHAR](10) NULL
) ON [PRIMARY]

GO

IF OBJECT_ID('stage.UserGroup') IS NOT NULL
	DROP TABLE [stage].[UserGroup];
GO
CREATE TABLE stage.UserGroup (
    ID nvarchar(255) NOT NULL PRIMARY KEY CLUSTERED,
    Name nvarchar(255),
    Description nvarchar(255),
    Handle nvarchar(255)
)
GO

IF OBJECT_ID('stage.MemberUserGroup') IS NOT NULL
	DROP TABLE [stage].[MemberUserGroup];
GO
CREATE TABLE stage.MemberUserGroup (
	RID INT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    MemberID nvarchar(255),
    UserGroupID nvarchar(255)
)
GO

IF OBJECT_ID('stage.ChannelUserGroup') IS NOT NULL
	DROP TABLE [stage].[ChannelUserGroup];
GO
CREATE TABLE stage.ChannelUserGroup (
	RID INT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    ChannelID nvarchar(255),
    UserGroupID nvarchar(255)
)
GO

IF OBJECT_ID('stage.FactMessage') IS NOT NULL
	DROP TABLE stage.[FactMessage];
GO
CREATE TABLE stage.FactMessage (
    RID INT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    EpochTimeStamp nvarchar(60),
    MemberID nvarchar(40),
    Text nvarchar(max),
    ChannelID nvarchar(40)
)
GO

IF OBJECT_ID('stage.FactReaction') IS NOT NULL
	DROP TABLE stage.[FactReaction];
GO
CREATE TABLE stage.FactReaction (
	RID INT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    MessageRID INT,
    Name nvarchar(50),
    MemberID nvarchar(50)
)
GO

IF OBJECT_ID('stage.ProcessMessageLog') IS NOT NULL
	DROP TABLE [stage].[ProcessMessageLog];
GO
CREATE TABLE stage.ProcessMessageLog (
    RID INT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    EpochTimeStamp nvarchar(100),
	CreateDate DATETIME DEFAULT(GETDATE())
)
GO

IF OBJECT_ID('stage.FactStar') IS NOT NULL
	DROP TABLE [stage].[FactStar];
GO
CREATE TABLE stage.FactStar (
	RID INT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
	MemberID NVARCHAR(255) NOT NULL,
	StarType NVARCHAR(255),
	ChannelID NVARCHAR(255),
	[EpochTimeStamp] NVARCHAR(255),
	[MessageMemberID] NVARCHAR(255)
)
GO

-----------------------------------

IF OBJECT_ID('dbo.[FactMessage]', 'V') IS NOT NULL
	DROP VIEW [dbo].[FactMessage];
GO
CREATE VIEW dbo.[FactMessage] AS
SELECT f.RID as [Message], ISNULL(m.ID,'Unknown') as [MemberID], ISNULL(c.ID, 'Unknown') as [ChannelID], f.Text as [Mesage Text],
    DATEADD(ss,CONVERT(INT, LEFT(EpochTimeStamp, CHARINDEX('.',EpochTimeStamp)-1)), '1970-01-01 00:00:00' ) as LocalDate , 
	CONVERT(INT,CONVERT(VARCHAR(100),DATEADD(ss,CONVERT(INT, LEFT(EpochTimeStamp, CHARINDEX('.',EpochTimeStamp)-1)), '1970-01-01 00:00:00' ), 112)) AS DateSK,
	CONVERT(INT,DATEDIFF(s,CONVERT(VARCHAR(100),DATEADD(ss,CONVERT(INT, LEFT(EpochTimeStamp, CHARINDEX('.',EpochTimeStamp)-1)), '1970-01-01 00:00:00' ), 112),DATEADD(ss,CONVERT(INT, LEFT(EpochTimeStamp, CHARINDEX('.',EpochTimeStamp)-1)), '1970-01-01 00:00:00' ))) as TimeSK
FROM stage.FactMessage f
LEFT JOIN stage.Member m
    ON f.MemberID = m.ID
LEFT JOIN stage.Channel c
    ON c.ID = f.ChannelID 
GO

IF OBJECT_ID('dbo.[DimReactionGiven]', 'V') IS NOT NULL
	DROP VIEW [dbo].[DimReactionGiven];
GO
CREATE VIEW dbo.DimReactionGiven AS
SELECT d.MessageRID as [Message], m.Name as [User Name], m.RealName as [User Full Name], d.Name as [Reaction Name]
FROM stage.FactReaction d
LEFT JOIN stage.Member m
    ON d.MemberID = m.ID
GO


IF OBJECT_ID('dbo.[DimReactionReceived]', 'V') IS NOT NULL
	DROP VIEW [dbo].[DimReactionReceived];
GO
CREATE VIEW dbo.DimReactionReceived AS
SELECT d.MessageRID as [Message], m.Name as [User Name], m.RealName as [User Full Name]
FROM stage.FactReaction d
JOIN stage.FactMessage fm
    ON fm.RID = d.MessageRID
LEFT JOIN stage.Member m
    ON fm.MemberID = m.ID
GROUP BY d.MessageRID, m.Name, m.RealName
GO

IF OBJECT_ID('dbo.[DimMember]', 'V') IS NOT NULL
	DROP VIEW [dbo].[DimMember];
GO
CREATE VIEW dbo.DimMember AS
SELECT m.ID AS MemberID, Name as [User Name], RealName as [User Full Name], m.Email, m.IsAdmin, m.IsBot, m.IsDeleted, m.IsOwner, m.TimeZone, m.IsPrimaryOwner
FROM stage.Member m
GO

IF OBJECT_ID('dbo.[DimChannel]', 'V') IS NOT NULL
	DROP VIEW [dbo].[DimChannel];
GO
CREATE VIEW dbo.DimChannel AS
SELECT c.ID AS ChannelID, c.Name AS [Channel Name], c.IsArchived, c.IsDeleted, c.IsGeneral, c.Purpose, c.Topic, c.TopicCreatorMemberID, c.PurposeCreatorMemberID,
    DATEADD(ss,CONVERT(INT, EpochCreateDate), '1970-01-01 00:00:00' ) as LocalDate ,
	CONVERT(INT,CONVERT(VARCHAR(100),DATEADD(ss,CONVERT(INT, EpochCreateDate), '1970-01-01 00:00:00' ), 112)) AS DateID,
	CONVERT(INT,DATEDIFF(s,CONVERT(VARCHAR(100),DATEADD(ss,CONVERT(INT, EpochCreateDate), '1970-01-01 00:00:00' ), 112),DATEADD(ss,CONVERT(INT, EpochCreateDate), '1970-01-01 00:00:00' ))) as TimeID
FROM stage.Channel c

GO


IF OBJECT_ID('dbo.[FactChannelMember]', 'V') IS NOT NULL
	DROP VIEW [dbo].[FactChannelMember];
GO
CREATE VIEW dbo.FactChannelMember AS
SELECT m.Name AS [User Name], m.RealName AS [Full Name], c.Name AS [Channel Name]
FROM stage.ChannelMember
LEFT JOIN stage.Member m ON m.ID = ChannelMember.MemberID
LEFT JOIN stage.Channel c ON c.ID = ChannelMember.ChannelID
GO

IF OBJECT_ID('dbo.[DimTime]', 'V') IS NOT NULL
	DROP VIEW [dbo].[DimTime];
GO
CREATE VIEW dbo.DimTime AS
SELECT * FROM [stage].[Time]
GO

IF OBJECT_ID('dbo.[DimDate]', 'V') IS NOT NULL
	DROP VIEW [dbo].[DimDate];
GO
CREATE VIEW dbo.DimDate AS
SELECT * FROM [stage].[Date]
GO
