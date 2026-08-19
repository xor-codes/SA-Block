/* 
   SA-Block  —  Step 2 of 2

 */

USE [master];
GO

CREATE OR ALTER TRIGGER [TR_SA_Block_RestrictedLogins]
ON ALL SERVER
WITH EXECUTE AS N'sa'          -- lets the trigger write the audit row
                               -- even when the connecting login (Administrator)
                               -- has no rights on the audit table
FOR LOGON
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LoginName sysname = ORIGINAL_LOGIN();


    IF @LoginName NOT IN (N'sa', N'Administrator')
        RETURN;

    DECLARE @ClientHost nvarchar(128) =
        EVENTDATA().value('(/EVENT_INSTANCE/ClientHost)[1]', 'nvarchar(128)');

    DECLARE @WorkstationName nvarchar(128) = HOST_NAME();

    DECLARE @IsAllowed bit = 0;

    /* ----------------------------------------------------------
       ALLOWLIST — edit this section.
       Local connections + your trusted static IPs.
       ---------------------------------------------------------- */
    IF @ClientHost IS NULL
       OR @ClientHost IN
          (
              N'<local machine>',      -- shared memory / local named pipes
              N'127.0.0.1',            -- local TCP (IPv4)
              N'::1',                  -- local TCP (IPv6)

              /* ==== YOUR TRUSTED IPs — EDIT BELOW ==== */
              N'192.168.1.50',         -- example: app server
              N'192.168.1.51'          -- example: admin workstation
              /* ======================================= */
          )
    BEGIN
        SET @IsAllowed = 1;
    END;


    IF @IsAllowed = 0
       AND @WorkstationName IN
           (
               /* YOUR TRUSTED HOSTNAMES — EDIT BELOW  */
               N'www.google.com',        -- example: your laptop
               N'APP-SERVER-01'        -- example: app server

           )
    BEGIN
        SET @IsAllowed = 1;
    END;

    IF @IsAllowed = 1
    BEGIN
        /* Allowed: log it, but NEVER let a logging failure
           block a legitimate login. */
        BEGIN TRY
            INSERT INTO SABlockAudit.dbo.LoginAudit
                (LoginName, ClientHost, AppName, HostName, Spid, WasBlocked)
            VALUES
                (@LoginName, @ClientHost, APP_NAME(), HOST_NAME(), @@SPID, 0);
        END TRY
        BEGIN CATCH
            -- swallow logging errors on the allow path
        END CATCH;
        RETURN;
    END;


    ROLLBACK;

    BEGIN TRY
        INSERT INTO SABlockAudit.dbo.LoginAudit
            (LoginName, ClientHost, AppName, HostName, Spid, WasBlocked)
        VALUES
            (@LoginName, @ClientHost, APP_NAME(), HOST_NAME(), @@SPID, 1);
    END TRY
    BEGIN CATCH

    END CATCH;
END;
GO

PRINT 'Logon trigger TR_SA_Block_RestrictedLogins is installed.';
GO
