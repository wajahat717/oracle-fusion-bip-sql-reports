WITH props AS (
    SELECT rp.REQUESTID,
           MAX(CASE WHEN rp.NAME = 'report_url'  THEN rp.VALUE END) AS REPORT_URL,
           MAX(CASE WHEN rp.NAME = 'ujobname'    THEN rp.VALUE END) AS JOB_NAME,
           MAX(CASE WHEN rp.NAME = 'CONTROL_XML' THEN rp.VALUE END) AS CONTROL_XML,
           MAX(CASE WHEN rp.NAME = 'is_bursting' THEN rp.VALUE END) AS IS_BURSTING,
           MAX(CASE WHEN rp.NAME = 'notify_to'   THEN rp.VALUE END) AS NOTIFY_TO
    FROM FUSION.ESS_REQUEST_PROPERTY rp
    WHERE rp.NAME IN ('report_url', 'ujobname', 'CONTROL_XML', 'is_bursting', 'notify_to')
    GROUP BY rp.REQUESTID
    HAVING MAX(CASE WHEN rp.NAME = 'report_url' THEN rp.VALUE END) IS NOT NULL
),
runs AS (
    SELECT rh.REQUESTID,
           NVL(NULLIF(rh.PARENTREQUESTID, 0), rh.REQUESTID) AS SCHEDULE_ID,
           rh.USERNAME     AS JOB_OWNER,
           rh.STATE,
           rh.PROCESSSTART AS LAST_RUN,
           rh.SCHEDULED    AS SCHEDULED_FOR,
           p.REPORT_URL,
           p.JOB_NAME,
           p.CONTROL_XML,
           p.IS_BURSTING,
           p.NOTIFY_TO,
           ROW_NUMBER() OVER (PARTITION BY NVL(NULLIF(rh.PARENTREQUESTID, 0), rh.REQUESTID)
                              ORDER BY rh.REQUESTID DESC) AS RN
    FROM FUSION.ESS_REQUEST_HISTORY rh
    JOIN props p
        ON p.REQUESTID = rh.REQUESTID
    WHERE NVL(rh.PROCESSSTART, rh.SCHEDULED) >= SYSDATE - 60
      AND ( :P_REPORT_SEARCH IS NULL
            OR UPPER(:P_REPORT_SEARCH) = 'ALL'
            OR UPPER(p.REPORT_URL) LIKE '%' || UPPER(:P_REPORT_SEARCH) || '%'
            OR UPPER(p.JOB_NAME)   LIKE '%' || UPPER(:P_REPORT_SEARCH) || '%' )
),
latest AS (
    SELECT *
    FROM runs
    WHERE RN = 1
),
emails AS (
    SELECT l.SCHEDULE_ID,
           LOWER(REGEXP_SUBSTR(l.CONTROL_XML,
                 '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', 1, LEVEL)) AS EMAIL
    FROM latest l
    CONNECT BY LEVEL <= REGEXP_COUNT(l.CONTROL_XML,
                         '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
        AND PRIOR l.SCHEDULE_ID = l.SCHEDULE_ID
        AND PRIOR SYS_GUID() IS NOT NULL
)
SELECT DISTINCT
    l.SCHEDULE_ID,
    l.JOB_NAME,
    TRIM(REGEXP_SUBSTR(l.REPORT_URL, '[^/]+$')) AS REPORT_NAME,
    l.REPORT_URL AS REPORT_PATH,
    l.JOB_OWNER,
    CASE l.STATE
        WHEN 1  THEN 'Active (waiting for next run)'
        WHEN 12 THEN 'Succeeded'
        WHEN 10 THEN 'Error'
        WHEN 9  THEN 'Canceled'
        WHEN 16 THEN 'Schedule Ended'
        ELSE TO_CHAR(l.STATE)
    END AS LAST_STATUS,
    l.LAST_RUN,
    l.SCHEDULED_FOR AS NEXT_OR_LAST_SCHEDULED,
    NVL(l.IS_BURSTING, 'false') AS IS_BURSTING,
    NVL(e.EMAIL, 'No email found') AS RECIPIENT_EMAIL,
    l.NOTIFY_TO AS STATUS_NOTIFY_TO
FROM latest l
LEFT JOIN emails e
    ON e.SCHEDULE_ID = l.SCHEDULE_ID
   AND e.EMAIL <> 'bipublisher-report@oracle.com'
WHERE ( NVL(:P_ACTIVE_ONLY, 'Y') = 'N' OR l.STATE = 1 )
ORDER BY REPORT_NAME, l.JOB_NAME, RECIPIENT_EMAIL
