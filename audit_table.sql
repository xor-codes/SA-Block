/*
   SA-Block  —  Step 1 of 2

   login attempt (allowed AND blocked).

   Run this FIRST, before 2_create_logon_trigger.sql.
 */

USE [master];
GO

IF DB_ID(N'SABlockAudit') IS NULL
BEGIN
    CREATE DATABASE [SABlockAudit];
END;
GO

USE [SABlockAudit];
GO

IF OBJECT_ID(N'dbo.LoginAudit', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.LoginAudit
    (
        Id           bigint IDENTITY(1,1) NOT NULL
                     CONSTRAINT PK_LoginAudit PRIMARY KEY CLUSTERED,
        EventTimeUtc datetime2(3)  NOT NULL
                     CONSTRAINT DF_LoginAudit_Time DEFAULT (SYSUTCDATETIME()),
        LoginName    sysname        NOT NULL,
        ClientHost   nvarchar(128)  NULL,     
        AppName      nvarchar(256)  NULL,
        HostName     nvarchar(128)  NULL,     
        Spid         int            NULL,
        WasBlocked   bit            NOT NULL  
    );

    CREATE NONCLUSTERED INDEX IX_LoginAudit_Time
        ON dbo.LoginAudit (EventTimeUtc DESC)
        INCLUDE (LoginName, ClientHost, WasBlocked);
END;
GO

PRINT 'SABlockAudit database and dbo.LoginAudit table are ready.';
GO
