/* Working days (Monday to Friday) between a date and today.
   Replaces NEXT_DAY, which depends on the session language (NLS) and failed
   with ORA-01846 in BIP. Replace ASSIGN_DATE with your own date column. */

SELECT
    t.ASSIGN_DATE,
    (TRUNC(SYSDATE) - TRUNC(t.ASSIGN_DATE))
    - FLOOR((TRUNC(SYSDATE) - TRUNC(t.ASSIGN_DATE)
             + MOD(TO_NUMBER(TO_CHAR(TRUNC(t.ASSIGN_DATE), 'D')) + 5, 7)) / 7)
    - FLOOR((TRUNC(SYSDATE) - TRUNC(t.ASSIGN_DATE)
             + MOD(TO_NUMBER(TO_CHAR(TRUNC(t.ASSIGN_DATE), 'D')) + 6, 7)) / 7)
    AS BUSINESS_DAYS_PENDING
FROM YOUR_TABLE t
