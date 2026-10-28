/* Parameter patterns I use in every BIP data model. */

/* 1. Optional single or multi-select parameter with an "All" option.
      In the parameter setup choose "All Values Passed" = NULL. */
SELECT *
FROM HZ_PARTIES hz
WHERE (hz.PARTY_NAME IN (:P_Account) OR 'ALL' IN (:P_Account || 'ALL'))


/* 2. Date parameter that BIP sends as an ISO text string
      (for example 2026-07-17T00:00:00.000+05:00).
      TO_DATE(:P_Date, 'DD-MM-YYYY') fails with ORA-01861, so convert once
      in a params CTE and reuse it everywhere. */
WITH cte_params AS (
    SELECT TRUNC(TO_DATE(SUBSTR(:P_AsOf_Date, 1, 10), 'YYYY-MM-DD')) AS ASOF_DATE
    FROM DUAL
)
SELECT aps.*
FROM AR_PAYMENT_SCHEDULES_ALL aps
CROSS JOIN cte_params PRM
WHERE aps.TRX_DATE <= PRM.ASOF_DATE


/* 3. Keep only the current row from a table that has history
      (stops one customer turning into many rows). */
SELECT *
FROM (
    SELECT hop.*,
           ROW_NUMBER() OVER (PARTITION BY hop.PARTY_ID
                              ORDER BY hop.EFFECTIVE_START_DATE DESC) AS RN
    FROM HZ_ORGANIZATION_PROFILES hop
)
WHERE RN = 1
