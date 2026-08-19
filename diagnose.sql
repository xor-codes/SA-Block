/* ============================================================
   SA-Block — Diagnostics
   Run this in SSMS (as sysadmin) ON THE SERVER where the
   trigger should be active. Read the three results in order.
   ============================================================ */

/* ------------------------------------------------------------
   1. Is the trigger actually installed HERE, and enabled?
      - No rows            -> script 2 was never run on this
                              server. Run 2_create_logon_trigger.sql.
      - is_disabled = 1    -> someone disabled it. Re-enable:
                              ENABLE TRIGGER [TR_SA_Block_RestrictedLogins] ON ALL SERVER;
   ------------------------------------------------------------ */
SELECT name, is_disabled, create_date, modify_date
FROM sys.server_triggers;

/* ------------------------------------------------------------
   2. What address does the server see for YOUR current
      connection? This is exactly the value the trigger
      compares against its allowlist.
      - If this shows an IP that is in your allowlist (or a
        LAN/NAT address), that is why you were let in.
   ------------------------------------------------------------ */
SELECT s.login_name,
       c.client_net_address,     -- what the trigger sees as ClientHost
       s.[host_name],            -- your machine's self-reported name
       s.[program_name],
       c.net_transport
FROM sys.dm_exec_connections c
JOIN sys.dm_exec_sessions   s ON s.session_id = c.session_id
WHERE c.session_id = @@SPID;

/* ------------------------------------------------------------
   3. The last 30 audited attempts. Every sa/x3 login should
      appear here the moment it happens.
      - Your remote login listed with WasBlocked = 0 and a
        ClientHost you did NOT allowlist -> tell me that value.
      - Your remote login NOT here at all -> the trigger is not
        firing (see result 1) or you are on a different server.
   ------------------------------------------------------------ */
SELECT TOP (30) Id, EventTimeUtc, LoginName, ClientHost,
       HostName, AppName, WasBlocked
FROM SABlockAudit.dbo.LoginAudit
ORDER BY Id DESC;

/* ------------------------------------------------------------
   4. Definition of the installed trigger — confirm the
      allowlist that is ACTUALLY live on this server (it may
      differ from the file on your disk).
   ------------------------------------------------------------ */
SELECT OBJECT_DEFINITION(t.object_id) AS trigger_definition
FROM sys.server_triggers t
WHERE t.name = N'TR_SA_Block_RestrictedLogins';
